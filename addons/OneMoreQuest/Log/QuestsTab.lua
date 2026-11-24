local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: the My quests tab (its filters and the quests grouped by zone).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local isMatch = Actions.isMatch
local addListQuest = List.addListQuest
local composeProgress, drawLogQuest, drawZonePage =
    QuestPage.composeProgress, QuestPage.drawLogQuest, QuestPage.drawZonePage
local filterDropdown, listOpening, selectedQuestIds = State.filterDropdown, State.listOpening, State.selectedQuestIds
local COLORS, FILTERS, HEADER_BAR_HIGH, HEADER_BAR_LOW, ITEM_ICON, PADDING =
    Style.COLORS, Style.FILTERS, Style.HEADER_BAR_HIGH, Style.HEADER_BAR_LOW, Style.ITEM_ICON, Style.PADDING
local SWITCH_EDGE, SWITCH_TRACK, TAB_QUESTS = Style.SWITCH_EDGE, Style.SWITCH_TRACK, Style.TAB_QUESTS

---------------------------------------------------------------------------------------------------------------
-- The two tabs

local FILTER_LABELS = { all = "All", ready = "Ready", tracked = "Tracked" }

local function selectFilter(filter)
    State.logFilter = filter
    Log.refresh()
end

---The filter chips above the list, with how many quests each one keeps.
---@return number y Below the chips
local function addFilters(y, counts)
    -- One switch of three parts, as All, Ready and Tracked are one choice: the chosen part in the frame's wood
    -- with gold text, the others sunk into a dark track
    local left, width, height = 6, State.list.width - 12, 22
    local partWidth = width / #FILTERS
    State.list:addRect(left, y, width, height, SWITCH_EDGE)
    State.list:addRect(left + 1, y + 1, width - 2, height - 2, SWITCH_TRACK, 1)
    for index, filter in ipairs(FILTERS) do
        local label = ns.L(FILTER_LABELS[filter]) .. (counts[filter] and (" " .. counts[filter]) or "")
        local x = left + (index - 1) * partWidth
        local isSelected = filter == State.logFilter
        if isSelected then
            State.list:addRect(x + 1, y + 1, partWidth - 2, height - 2, HEADER_BAR_LOW, 2)
            State.list:addRect(x + 1, y + 1, partWidth - 2, (height - 2) / 2, HEADER_BAR_HIGH, 3)
            State.list:addRect(x + 1, y + 1, partWidth - 2, 1, { 1, 1, 1, 0.16 }, 4)
        end
        if index > 1 then
            State.list:addRect(x, y + 3, 1, height - 6, SWITCH_EDGE, 5)
        end
        State.list:addText(label, x, y + 5, {
            font = "GameFontHighlightSmall",
            color = isSelected and COLORS.gold or COLORS.tan,
            width = partWidth,
            justify = "CENTER",
            isSingleLine = true,
        })
        State.list:addButton(x, y, partWidth, height, selectFilter, filter)
    end
    return y + height + 8
end

local GAUGE_FULL, GAUGE_EMPTY, GAUGE_WARN = { 0.78, 0.55, 0.13 }, { 0.23, 0.16, 0.09 }, { 1, 0.6, 0.48 }
local ABANDON_EDGE = { 0.48, 0.16, 0.1 }

local function showQuest(questId)
    Log.showQuestAnywhere(questId)
end

local function abandon(questId)
    Log.abandonQuest(questId) -- the game's own "Abandon?" asks first
end

-- The quests worth giving up, in a small window of their own beside the list, opened from the list's slim line:
-- each with why and a button to abandon it. Made the first time it opens; filled again only while it is open.
local DROP_WINDOW_WIDTH, DROP_ROW_HEIGHT, DROP_TOP = 260, 34, 28
local DROP_EDGE, DROP_BACK = { 0.42, 0.29, 0.13 }, { 0.03, 0.02, 0.01, 0.95 }
local dropWindow

local function setEdged(frame, edge, back)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(back[1], back[2], back[3], back[4] or 1)
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
end

local function createDropRow(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(DROP_ROW_HEIGHT)
    local hover = row:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(row)
    hover:SetColorTexture(1, 1, 1, 0.06)
    row.title = ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
    row.reason = ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.reason:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
    row.reason:SetTextColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
    local abandonButton = CreateFrame("Button", nil, row, "BackdropTemplate")
    abandonButton:SetSize(62, 18)
    abandonButton:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    setEdged(abandonButton, ABANDON_EDGE, { 0.1, 0.04, 0.02 })
    abandonButton.text = ns.Widgets.createFontString(abandonButton, "OVERLAY", "GameFontHighlightSmall")
    abandonButton.text:SetPoint("CENTER", abandonButton, "CENTER", 0, 0)
    abandonButton.text:SetTextColor(GAUGE_WARN[1], GAUGE_WARN[2], GAUGE_WARN[3])
    abandonButton.text:SetText(ns.L("Abandon"))
    local glow = abandonButton:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(abandonButton)
    glow:SetColorTexture(1, 0.6, 0.48, 0.12)
    abandonButton:SetScript("OnClick", function()
        abandon(row.questId)
    end)
    row:SetScript("OnClick", function()
        showQuest(row.questId)
    end)
    -- With a controller the row is one stop: A opens the quest, its menu (Y) abandons (Gamepad.lua)
    row.isDropSuggestion, row.abandonButton = true, abandonButton
    for _, text in ipairs({ row.title, row.reason }) do
        text:SetPoint("RIGHT", abandonButton, "LEFT", -6, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
    end
    return row
end

---Fills the window with the quests worth dropping now; with none left, it closes.
local function fillDropWindow()
    if not dropWindow or not dropWindow:IsShown() then
        return
    end
    local suggestions = ns.Warnings.getDropSuggestions()
    if #suggestions == 0 then
        dropWindow:Hide()
        return
    end
    for index, suggestion in ipairs(suggestions) do
        local row = dropWindow.rows[index]
        if not row then
            row = createDropRow(dropWindow)
            row:SetPoint("TOPLEFT", dropWindow, "TOPLEFT", 1, -DROP_TOP - (index - 1) * DROP_ROW_HEIGHT)
            row:SetPoint("RIGHT", dropWindow, "RIGHT", -1, 0)
            dropWindow.rows[index] = row
        end
        row.questId, row.data = suggestion.questId, suggestion.questId -- (data: the quest a controller's cursor is on)
        local title = C_QuestLog.GetTitleForQuestID(suggestion.questId)
            or ns.QuestText.getQuestName(suggestion.questId)
            or ("Quest " .. suggestion.questId)
        row.title:SetText(string.format("[%d] %s", suggestion.level, title))
        row.reason:SetText(suggestion.reason)
        row:Show()
    end
    for index = #suggestions + 1, #dropWindow.rows do
        dropWindow.rows[index]:Hide()
    end
    local count, max = ns.QuestState.getLogSize()
    dropWindow.count:SetText(ns.L("Quest log %d of %d", count, max))
    dropWindow:SetHeight(DROP_TOP + #suggestions * DROP_ROW_HEIGHT + 6)
end

local function createDropWindow()
    dropWindow = CreateFrame("Frame", "OneMoreQuestDropWindow", State.frame, "BackdropTemplate")
    dropWindow:SetWidth(DROP_WINDOW_WIDTH)
    dropWindow:SetFrameStrata("DIALOG") -- over the page and its parts, whatever their levels
    dropWindow:SetToplevel(true)
    dropWindow:EnableMouse(true)
    dropWindow:EnableMouseWheel(true)
    dropWindow:SetScript("OnMouseWheel", function() end)
    setEdged(dropWindow, DROP_EDGE, DROP_BACK)
    -- (and a solid ground of its own under the rows: nothing of the page shows through)
    local ground = dropWindow:CreateTexture(nil, "BACKGROUND", nil, 1)
    ground:SetPoint("TOPLEFT", dropWindow, "TOPLEFT", 1, -1)
    ground:SetPoint("BOTTOMRIGHT", dropWindow, "BOTTOMRIGHT", -1, 1)
    ground:SetColorTexture(DROP_BACK[1], DROP_BACK[2], DROP_BACK[3], 1)
    local title = ns.Widgets.createFontString(dropWindow, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", dropWindow, "TOPLEFT", 9, -9)
    title:SetText(ns.L("Worth dropping"))
    dropWindow.count = ns.Widgets.createFontString(dropWindow, "OVERLAY", "GameFontDisableSmall")
    dropWindow.count:SetPoint("LEFT", title, "RIGHT", 8, 0)
    -- The flat cross the quest window's own drawn looks use (Media\Close), lit on hover
    local close = CreateFrame("Button", nil, dropWindow)
    close:SetSize(14, 14)
    close:SetPoint("TOPRIGHT", dropWindow, "TOPRIGHT", -7, -7)
    local crossFile = "Interface\\AddOns\\" .. ns.addonName .. "\\Media\\Close"
    local cross = close:CreateTexture(nil, "ARTWORK")
    cross:SetAllPoints(close)
    cross:SetTexture(crossFile)
    cross:SetVertexColor(0.85, 0.85, 0.85)
    local lit = close:CreateTexture(nil, "HIGHLIGHT")
    lit:SetAllPoints(close)
    lit:SetTexture(crossFile)
    lit:SetBlendMode("ADD")
    lit:SetAlpha(0.5)
    close:SetScript("OnClick", function()
        dropWindow:Hide()
    end)
    dropWindow.rows = {}
    dropWindow:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "OneMoreQuestDropWindow") -- Escape closes it first, as the game's own windows
    end
end

local function toggleDropWindow()
    if not dropWindow then
        createDropWindow()
    end
    if dropWindow:IsShown() then
        dropWindow:Hide()
        return
    end
    -- Beside the list, over the top of the page; with a controller's one pane, over the list itself
    dropWindow:ClearAllPoints()
    if Log.isNarrow() then
        dropWindow:SetPoint("TOPLEFT", State.list.frame, "TOPLEFT", 0, 0)
        dropWindow:SetPoint("RIGHT", State.list.frame, "RIGHT", 0, 0)
    else
        dropWindow:SetPoint("TOPLEFT", State.list.frame, "TOPRIGHT", 6, 0)
        dropWindow:SetWidth(DROP_WINDOW_WIDTH)
    end
    dropWindow:Show()
    fillDropWindow()
end
QuestsTab.toggleDropWindow = toggleDropWindow -- (for the tests and the simulator)

---Opens the quests worth dropping, if any (a controller's way from a full log); open already, it stays.
function QuestsTab.openDropWindow()
    if not (dropWindow and dropWindow:IsShown()) and #ns.Warnings.getDropSuggestions() > 0 then
        toggleDropWindow()
    end
end

---@return Button[] rows The drop window's rows shown now (none while it is closed)
function QuestsTab.getDropRows()
    local shown = {}
    if dropWindow and dropWindow:IsShown() then
        for _, row in ipairs(dropWindow.rows) do
            if row:IsShown() then
                shown[#shown + 1] = row
            end
        end
    end
    return shown
end

---@return boolean isClosed The drop window was open and is closed now (a controller's B closes it first)
function QuestsTab.closeDropWindow()
    if dropWindow and dropWindow:IsShown() then
        dropWindow:Hide()
        return true
    end
    return false
end

---As the log fills up, one slim line at the top of the list: how full it is, and a button that opens the quests worth
---dropping (Warnings.getDropSuggestions) in a window of their own. Nothing while it has room.
---@return number y Below it
local function addDropSuggestions(y)
    local suggestions = ns.Warnings.getDropSuggestions()
    if #suggestions == 0 then
        if dropWindow and dropWindow:IsShown() then
            dropWindow:Hide()
        end
        return y
    end
    local count, max = ns.QuestState.getLogSize()
    local left, width = 6, State.list.width - 12
    local buttonWidth = 78
    local buttonLeft = left + width - buttonWidth
    State.list:addText(
        ns.L("Log %d/%d", count, max),
        left + 4,
        y + 4,
        { font = "GameFontNormalSmall", color = COLORS.gold, isSingleLine = true }
    )
    -- How full: one thin bar, the full part in the warning colour once nothing is left
    local gaugeLeft = left + 64
    local gaugeWidth = math.max(buttonLeft - 8 - gaugeLeft, 10)
    local share = max > 0 and math.min(count / max, 1) or 0
    State.list:addRect(gaugeLeft, y + 8, gaugeWidth, 4, GAUGE_EMPTY, 2)
    if share > 0 then
        State.list:addRect(gaugeLeft, y + 8, gaugeWidth * share, 4, count >= max and GAUGE_WARN or GAUGE_FULL, 3)
    end
    State.list:addRect(buttonLeft, y + 1, buttonWidth, 18, ABANDON_EDGE, 3)
    State.list:addRect(buttonLeft + 1, y + 2, buttonWidth - 2, 16, { 0.1, 0.04, 0.02 }, 4)
    State.list:addText(ns.Lp(#suggestions, "%d to drop", "%d to drop") .. " >", buttonLeft, y + 4, {
        font = "GameFontHighlightSmall",
        color = GAUGE_WARN,
        width = buttonWidth,
        justify = "CENTER",
        isSingleLine = true,
    })
    State.list:addButton(buttonLeft, y + 1, buttonWidth, 18, toggleDropWindow)
    fillDropWindow() -- (open: the quests in it follow the log)
    return y + 26
end

local function isKeptByFilter(entry, isTracked)
    if State.logFilter == "ready" then
        return entry.isTurnIn
    elseif State.logFilter == "tracked" then
        return isTracked
    end
    return true
end

---@return table? selected The quest or zone group shown on the page
---@return number questCount
local function drawLogTab()
    local model = ns.Model.compose(nil, {
        questIds = ns.QuestState.getLogQuestIds(),
        collapsedZones = {},
        isExpandedByDefault = true,
    })
    local counts = { ready = 0, tracked = 0 }
    local isTracked = {}
    local selectedEntry, firstEntry, selectedGroup
    for _, group in ipairs(model.groups) do
        group.shownEntries = {}
        if group.zoneId == State.selectedLogZoneId then
            selectedGroup = group
        end
        for _, entry in ipairs(group.entries) do
            isTracked[entry.questId] = ns.QuestState.isWatched(entry.questId)
            counts.ready = counts.ready + (entry.isTurnIn and 1 or 0)
            counts.tracked = counts.tracked + (isTracked[entry.questId] and 1 or 0)
            -- What a search looks through, gathered only while one is typed (every quest of the log is asked, the
            -- ones under folded zones too)
            local searched
            if State.searchText ~= "" then
                local objectiveLabels = {}
                for _, objective in ipairs(entry.objectives) do
                    objectiveLabels[#objectiveLabels + 1] = objective.label
                    objectiveLabels[#objectiveLabels + 1] = objective.shownLabel
                end
                -- A translated quest is found by its English title too
                objectiveLabels[#objectiveLabels + 1] = entry.englishTitle
                searched = table.concat(objectiveLabels, " ")
            end
            if isKeptByFilter(entry, isTracked[entry.questId]) and isMatch(entry.title, group.zoneName, searched) then
                group.shownEntries[#group.shownEntries + 1] = entry
                firstEntry = firstEntry or entry
                if entry.questId == selectedQuestIds[TAB_QUESTS] then
                    selectedEntry = entry
                end
            end
        end
    end
    -- A quest chosen outside the list (its map pin, the tracker) that a search or filter left there hides: the
    -- search and filter give way, rather than the quest being let go of with no row to show for it
    if
        State.scrollTargetQuestId
        and State.scrollTargetQuestId == selectedQuestIds[TAB_QUESTS]
        and not selectedEntry
        and (State.searchText ~= "" or State.logFilter ~= "all")
        and ns.QuestState.isInLog(State.scrollTargetQuestId)
    then
        State.searchText, State.logFilter = "", "all"
        if type(State.frame.search) == "table" and type(State.frame.search.SetText) == "function" then
            State.frame.search:SetText("") -- (its OnTextChanged finds the text already cleared: no second drawing)
        end
        return drawLogTab()
    end
    if not selectedGroup then
        State.selectedLogZoneId = nil
    end
    -- No quest is selected until the player picks one; the list never chooses for them

    -- The filter is the game's dropdown beside the search; without one, a switch of three parts above the list
    filterDropdown.counts = counts
    local y = 4
    if filterDropdown.button then
        filterDropdown.button:GenerateMenu()
    else
        y = addFilters(4, counts)
    end
    if State.searchText == "" and ns.settings.shouldSuggestDrops ~= false then
        y = addDropSuggestions(y) -- (the player's choice: Quest window, Quest lists)
    end
    local mapZoneId = List.getShownMapZoneId()
    State.drawnMapZoneId = mapZoneId
    State.shownZoneIds = {}
    -- On opening, the list starts at the group of the focused quest; with none in the list, at the first open
    -- group with a tracked quest
    local openingQuestId = listOpening.isOpening and ns.Focus.get() or nil
    local isOpeningQuestShown = false
    for _, group in ipairs(openingQuestId and model.groups or {}) do
        for _, entry in ipairs(group.shownEntries) do
            isOpeningQuestShown = isOpeningQuestShown or entry.questId == openingQuestId
        end
    end
    listOpening.scrollTop = nil
    -- A chain's step on the row ("2/5") says how long the chain is: not where the Spoilers choice hides chains
    local isChainShown = not ns.Spoilers.isActive() or ns.Spoilers.getChoice("chains") ~= "hidden"
    for _, group in ipairs(model.groups) do
        if #group.shownEntries > 0 then
            State.shownZoneIds[#State.shownZoneIds + 1] = group.zoneId
            -- The first time a zone is listed it is open only if it holds a tracked quest. Its state is kept
            -- from then on, and changes only when the player opens or shuts it.
            local collapsedZones = ns.settings.collapsedLogZones
            local hasTracked = false
            for _, entry in ipairs(group.entries) do
                hasTracked = hasTracked or isTracked[entry.questId] == true
            end
            if collapsedZones[group.zoneId] == nil then
                collapsedZones[group.zoneId] = not hasTracked
            end
            -- A search shows what it found, folded or not
            local isCollapsed = collapsedZones[group.zoneId] == true and State.searchText == ""
            if isCollapsed and State.scrollTargetQuestId then
                for _, entry in ipairs(group.shownEntries) do
                    if entry.questId == State.scrollTargetQuestId then
                        -- A quest picked on the map must be seen, so its folded zone opens
                        collapsedZones[group.zoneId] = false
                        isCollapsed = false
                    end
                end
            end
            if listOpening.isOpening and not listOpening.scrollTop then
                local holdsOpeningQuest = false
                for _, entry in ipairs(group.shownEntries) do
                    holdsOpeningQuest = holdsOpeningQuest or entry.questId == openingQuestId
                end
                if isOpeningQuestShown and holdsOpeningQuest then
                    collapsedZones[group.zoneId], isCollapsed = false, false -- the focused quest is in view
                    listOpening.scrollTop = y
                elseif not isOpeningQuestShown and hasTracked and not isCollapsed then
                    listOpening.scrollTop = y
                end
            end
            y = List.addZoneHeading(y, group, isCollapsed, hasTracked)
            for _, entry in ipairs(isCollapsed and {} or group.shownEntries) do
                local progressText = composeProgress(entry)
                y = addListQuest(y, entry.questId, {
                    title = entry.title,
                    level = entry.level,
                    isReady = entry.isTurnIn,
                    isTracked = isTracked[entry.questId],
                    canShareWithParty = Log.canShareWithParty(entry.questId),
                    number = entry.number,
                    progress = ns.MapMarks.getProgress(entry),
                    isFocused = entry.questId == ns.Focus.get(),
                    canFocus = true,
                    itemTexture = entry.item and (entry.item.texture or ITEM_ICON) or nil,
                    subText = progressText ~= "" and progressText or nil,
                    chainText = entry.chainIndex
                            and isChainShown
                            and string.format("%d/%d", entry.chainIndex, entry.chainTotal)
                        or nil,
                    profitText = ns.settings.shouldShowProfit and ns.Profit.format(ns.Profit.get(entry.questId)) or nil,
                })
            end
            y = y + (isCollapsed and 2 or 8) -- folded zones stack close together
        end
    end
    if model.questCount == 0 then
        State.list:addText(
            ns.L("Your quest log is empty."),
            10,
            y + 4,
            { color = COLORS.tan, width = State.list.width - 20 }
        )
    elseif not firstEntry then
        State.list:addText(ns.L("No quest matches."), 10, y + 4, { color = COLORS.tan, width = State.list.width - 20 })
    end
    State.list:finish(y + 30)

    -- The log's size is on the My quests tab, "My quests (31/40)", amber nearly full, red full (Window's tab texts);
    -- the panel over the list says it in words
    local count = ns.Warnings.getLogSize() -- (the tab's count, given back below)
    State.frame.status:SetText("")

    if selectedGroup then
        State.frame.finishPage(function()
            return drawZonePage(selectedGroup)
        end)
        return selectedGroup, count
    end
    if selectedQuestIds[TAB_QUESTS] and not selectedEntry then
        -- The selected quest is no longer in the list (filtered out, searched away, or gone): keeping it
        -- highlighted on the map with no row to show for it would be a highlight nobody can see the reason for
        selectedQuestIds[TAB_QUESTS] = nil
        ns.MapPins.queueRefresh()
    end
    if selectedEntry and State.mapQuestId == selectedEntry.questId then
        ns.MapDock.showQuest(selectedEntry)
    end
    State.mapQuestId = nil
    if selectedEntry then
        State.frame.finishPage(function()
            return drawLogQuest(selectedEntry)
        end)
    else
        local hint = model.questCount > 0
                and ns.L("Select a quest to open its page and highlight it on the map. Click it again to let go of it.")
            or ""
        State.frame.finishPage(function()
            State.detail:addText(
                hint,
                PADDING,
                PADDING,
                { font = "QuestFont", color = COLORS.softInk, width = State.detail.width - 2 * PADDING }
            )
            return 80
        end)
    end
    return selectedEntry, count
end

-- Shared with the other parts of the window
QuestsTab.FILTER_LABELS = FILTER_LABELS
QuestsTab.drawLogTab = drawLogTab
QuestsTab.selectFilter = selectFilter
