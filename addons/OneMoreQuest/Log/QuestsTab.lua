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
local COLORS, FILTERS, HEADER_BAR_HIGH, HEADER_BAR_LOW, ITEM_ICON =
    Style.COLORS, Style.FILTERS, Style.HEADER_BAR_HIGH, Style.HEADER_BAR_LOW, Style.ITEM_ICON
local SWITCH_EDGE, SWITCH_TRACK, TAB_QUESTS = Style.SWITCH_EDGE, Style.SWITCH_TRACK, Style.TAB_QUESTS

---------------------------------------------------------------------------------------------------------------
-- The filters above the list

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
local setEdged = Style.setEdged

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
    Style.addCloseButton(dropWindow, 7)
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

---@return boolean isHeld One of the entries is the quest
local function holdsQuest(entries, questId)
    for _, entry in ipairs(entries) do
        if entry.questId == questId then
            return true
        end
    end
    return false
end

---What a search looks through besides the title and the zone, gathered only while one is typed (every quest of
---the log is asked, the ones under folded zones too).
---@return string? searched
local function composeSearchedText(entry)
    if State.searchText == "" then
        return nil
    end
    local objectiveLabels = {}
    for _, objective in ipairs(entry.objectives) do
        objectiveLabels[#objectiveLabels + 1] = objective.label
        objectiveLabels[#objectiveLabels + 1] = objective.shownLabel
    end
    -- A translated quest is found by its English title too
    objectiveLabels[#objectiveLabels + 1] = entry.englishTitle
    return table.concat(objectiveLabels, " ")
end

---Sorts the log's quests into what the list shows: each group's shownEntries (what the filter and the search
---keep), how many quests each filter keeps, and which quests are tracked.
---@return table pass { counts, isTracked, selectedEntry?, firstEntry?, selectedGroup? }
local function collectShownEntries(model)
    local pass = { counts = { ready = 0, tracked = 0 }, isTracked = {} }
    local counts, isTracked = pass.counts, pass.isTracked
    for _, group in ipairs(model.groups) do
        group.shownEntries = {}
        if group.zoneId == State.selectedLogZoneId then
            pass.selectedGroup = group
        end
        for _, entry in ipairs(group.entries) do
            isTracked[entry.questId] = ns.QuestState.isWatched(entry.questId)
            counts.ready = counts.ready + (entry.isTurnIn and 1 or 0)
            counts.tracked = counts.tracked + (isTracked[entry.questId] and 1 or 0)
            local searched = composeSearchedText(entry)
            if isKeptByFilter(entry, isTracked[entry.questId]) and isMatch(entry.title, group.zoneName, searched) then
                group.shownEntries[#group.shownEntries + 1] = entry
                pass.firstEntry = pass.firstEntry or entry
                if entry.questId == selectedQuestIds[TAB_QUESTS] then
                    pass.selectedEntry = entry
                end
            end
        end
    end
    return pass
end

---A quest chosen outside the list (its map pin, the tracker) that a search or filter left there hides: the
---search and filter give way, rather than the quest being let go of with no row to show for it.
---@return boolean isGivenWay The search and the filter were cleared, and the list must be drawn again
local function giveWayToChosenQuest(selectedEntry)
    local questId = State.scrollTargetQuestId
    if
        not questId
        or questId ~= selectedQuestIds[TAB_QUESTS]
        or selectedEntry
        or (State.searchText == "" and State.logFilter == "all")
        or not ns.QuestState.isInLog(questId)
    then
        return false
    end
    State.searchText, State.logFilter = "", "all"
    if type(State.frame.search) == "table" and type(State.frame.search.SetText) == "function" then
        State.frame.search:SetText("") -- (its OnTextChanged finds the text already cleared: no second drawing)
    end
    return true
end

---What stands over the quests: the filter, the game's dropdown beside the search (without one, a switch of three
---parts above the list), then the log's fill and the quests worth dropping.
---@return number y Below it
local function addListTop(counts)
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
    return y
end

---@return boolean hasTracked One of the group's quests (shown or not) is tracked
local function hasTrackedQuest(group, isTracked)
    for _, entry in ipairs(group.entries) do
        if isTracked[entry.questId] == true then
            return true
        end
    end
    return false
end

---Whether a zone is folded. The first time a zone is listed it is open only if it holds a tracked quest. Its state
---is kept from then on, and changes only when the player opens or shuts it.
---@return boolean isCollapsed
local function isZoneCollapsed(group, hasTracked)
    local collapsedZones = ns.settings.collapsedLogZones
    if collapsedZones[group.zoneId] == nil then
        collapsedZones[group.zoneId] = not hasTracked
    end
    -- A search shows what it found, folded or not
    local isCollapsed = collapsedZones[group.zoneId] == true and State.searchText == ""
    if isCollapsed and State.scrollTargetQuestId and holdsQuest(group.shownEntries, State.scrollTargetQuestId) then
        -- A quest picked on the map must be seen, so its folded zone opens
        collapsedZones[group.zoneId] = false
        isCollapsed = false
    end
    return isCollapsed
end

---On opening, the list starts at the group of the focused quest; with none in the list, at the first open group
---with a tracked quest. The first group that qualifies keeps its top (listOpening.scrollTop).
---@param opening { questId: number?, isShown: boolean } The focused quest, and whether the list shows it
---@return boolean isCollapsed The group's folding: opened when it holds the focused quest
local function markOpeningGroup(y, group, isCollapsed, hasTracked, opening)
    if not listOpening.isOpening or listOpening.scrollTop then
        return isCollapsed
    end
    if opening.isShown and holdsQuest(group.shownEntries, opening.questId) then
        ns.settings.collapsedLogZones[group.zoneId] = false -- the focused quest is in view
        listOpening.scrollTop = y
        return false
    end
    if not opening.isShown and hasTracked and not isCollapsed then
        listOpening.scrollTop = y
    end
    return isCollapsed
end

---@return number y Below the quest's row
local function addLogQuestRow(y, entry, isTracked, isChainShown)
    local progressText = composeProgress(entry)
    return addListQuest(y, entry.questId, {
        title = entry.title,
        level = entry.level,
        isReady = entry.isTurnIn,
        isTracked = isTracked,
        canShareWithParty = Log.canShareWithParty(entry.questId),
        partyCount = Log.getPartyCount(entry.questId),
        number = entry.number,
        progress = ns.MapMarks.getProgress(entry),
        isFocused = entry.questId == ns.Focus.get(),
        canFocus = true,
        itemTexture = entry.item and (entry.item.texture or ITEM_ICON) or nil,
        subText = progressText ~= "" and progressText or nil,
        chainText = isChainShown and List.composeChainText(entry) or nil,
        chainIcon = not entry.chainIndex and ns.LogStyle.UNLOCK_ICON or nil,
        profitText = ns.settings.shouldShowProfit and ns.Profit.format(ns.Profit.get(entry.questId)) or nil,
    })
end

---@return { questId: number?, isShown: boolean } opening The quest the list opens at (the focused one), if any
local function findOpeningQuest(model)
    local opening = { questId = listOpening.isOpening and ns.Focus.get() or nil, isShown = false }
    if opening.questId then
        for _, group in ipairs(model.groups) do
            opening.isShown = opening.isShown or holdsQuest(group.shownEntries, opening.questId)
        end
    end
    return opening
end

---The zones with quests the filter and the search keep, each its heading and, unless folded, its quests.
---@return number y Below the last zone
local function addLogGroups(y, model, isTracked)
    State.shownZoneIds = {}
    local opening = findOpeningQuest(model)
    listOpening.scrollTop = nil
    -- A chain's step on the row ("2/5") says how long the chain is: not where the Spoilers choice hides chains
    local isChainShown = not ns.Spoilers.isActive() or ns.Spoilers.getChoice("chains") ~= "hidden"
    for _, group in ipairs(model.groups) do
        if #group.shownEntries > 0 then
            State.shownZoneIds[#State.shownZoneIds + 1] = group.zoneId
            local hasTracked = hasTrackedQuest(group, isTracked)
            local isCollapsed = isZoneCollapsed(group, hasTracked)
            isCollapsed = markOpeningGroup(y, group, isCollapsed, hasTracked, opening)
            y = List.addZoneHeading(y, group, isCollapsed, hasTracked)
            if not isCollapsed then
                for _, entry in ipairs(group.shownEntries) do
                    y = addLogQuestRow(y, entry, isTracked[entry.questId], isChainShown)
                end
            end
            y = y + (isCollapsed and 2 or 8) -- folded zones stack close together
        end
    end
    return y
end

---Under an empty list, why it is empty.
local function addEmptyListNote(y, model, firstEntry)
    local note
    if model.questCount == 0 then
        note = ns.L("Your quest log is empty.")
    elseif not firstEntry then
        note = ns.L("No quest matches.")
    end
    if note then
        State.list:addText(note, 10, y + 4, { color = COLORS.tan, width = State.list.width - 20 })
    end
end

local pageGroup, pageEntry -- what the page beside the list shows, read by its drawing functions below

local function drawSelectedZonePage()
    return drawZonePage(pageGroup)
end

local function drawSelectedQuestPage()
    return drawLogQuest(pageEntry)
end

---The page beside the list: the selected zone's page, the selected quest's, or a hint on selecting one.
local function drawLogPage(model, selectedGroup, selectedEntry)
    if selectedGroup then
        pageGroup = selectedGroup
        State.frame.finishPage(drawSelectedZonePage)
        return
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
        pageEntry = selectedEntry
        State.frame.finishPage(drawSelectedQuestPage)
        return
    end
    QuestPage.drawHintPage(
        model.questCount > 0
                and ns.L("Select a quest to open its page and highlight it on the map. Click it again to let go of it.")
            or ""
    )
end

---Draws the My quests tab: the list of the log's quests by zone, and the page beside it.
---@return table? selected The quest or zone group shown on the page
---@return number questCount
local function drawLogTab()
    local model = ns.Model.compose(nil, {
        questIds = ns.QuestState.getLogQuestIds(),
        collapsedZones = {},
        isExpandedByDefault = true,
    })
    local pass = collectShownEntries(model)
    if giveWayToChosenQuest(pass.selectedEntry) then
        return drawLogTab()
    end
    if not pass.selectedGroup then
        State.selectedLogZoneId = nil
    end
    -- No quest is selected until the player picks one; the list never chooses for them

    local y = addListTop(pass.counts)
    State.drawnMapZoneId = List.getShownMapZoneId()
    y = addLogGroups(y, model, pass.isTracked)
    addEmptyListNote(y, model, pass.firstEntry)
    State.list:finish(y + 30)

    -- The log's size is on the My quests tab, "My quests (31/40)", amber nearly full, red full (Window's tab texts);
    -- the panel over the list says it in words
    local count = ns.Warnings.getLogSize() -- (the tab's count, given back below)
    State.frame.status:SetText("")

    drawLogPage(model, pass.selectedGroup, pass.selectedEntry)
    return pass.selectedGroup or pass.selectedEntry, count
end

-- Shared with the other parts of the window
QuestsTab.FILTER_LABELS = FILTER_LABELS
QuestsTab.drawLogTab = drawLogTab
QuestsTab.selectFilter = selectFilter
