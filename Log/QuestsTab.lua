local _, ns = ...

-- The quest log window: the My quests tab (its filters and the quests grouped by zone).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window = ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local isMatch = Actions.isMatch
local addListQuest = List.addListQuest
local composeProgress, drawLogQuest, drawZonePage = QuestPage.composeProgress, QuestPage.drawLogQuest, QuestPage.drawZonePage
local filterDropdown, listOpening, selectedQuestIds = State.filterDropdown, State.listOpening, State.selectedQuestIds
local COLORS, FILTERS, HEADER_BAR_HIGH, HEADER_BAR_LOW, ITEM_ICON, PADDING = Style.COLORS, Style.FILTERS, Style.HEADER_BAR_HIGH, Style.HEADER_BAR_LOW, Style.ITEM_ICON, Style.PADDING
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
            font = "GameFontHighlightSmall", color = isSelected and COLORS.gold or COLORS.tan, width = partWidth, justify = "CENTER", isSingleLine = true,
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

---As the log fills up: a gauge of its places, and the quests best given up, each with why and a button to abandon
---it (Warnings.getDropSuggestions). Nothing while it has room.
---@return number y Below it
local function addDropSuggestions(y)
    local suggestions = ns.Warnings.getDropSuggestions()
    if #suggestions == 0 then
        return y
    end
    local count, max = ns.QuestState.getLogSize()
    local left, width = 6, State.list.width - 12
    local top = y
    y = y + 6
    State.list:addText(ns.L("Quest log %d of %d", count, max), left + 8, y, { font = "GameFontNormalSmall", color = COLORS.gold, isSingleLine = true })
    local free = math.max(max - count, 0)
    State.list:addText(free == 0 and ns.L("full") or ns.Lp(free, "%d place left", "%d places left"), left + 8, y, {
        font = "GameFontHighlightSmall", color = GAUGE_WARN, width = width - 16, justify = "RIGHT", isSingleLine = true,
    })
    y = y + 16
    -- One mark a place, filled for each quest in the log
    local slotWidth = (width - 16 - (max - 1) * 2) / max
    for slot = 1, max do
        State.list:addRect(left + 8 + (slot - 1) * (slotWidth + 2), y, slotWidth, 5, slot <= count and GAUGE_FULL or GAUGE_EMPTY, 2)
    end
    y = y + 11
    State.list:addText(ns.L("Worth dropping"), left + 8, y, { font = "GameFontDisableSmall", color = COLORS.tan, isSingleLine = true })
    y = y + 15
    for _, suggestion in ipairs(suggestions) do
        local title = C_QuestLog.GetTitleForQuestID(suggestion.questId) or ns.QuestText.getQuestName(suggestion.questId) or ("Quest " .. suggestion.questId)
        local buttonWidth = 58
        State.list:addRect(left + 6, y - 2, width - 12, 1, { 1, 1, 1, 0.06 }, 2)
        State.list:addText(string.format("[%d] %s", suggestion.level, title), left + 8, y + 2, {
            font = "GameFontHighlightSmall", color = COLORS.white, width = width - buttonWidth - 24, isSingleLine = true,
        })
        State.list:addText(suggestion.reason, left + 8, y + 15, { font = "GameFontHighlightSmall", color = COLORS.tan, width = width - buttonWidth - 24, isSingleLine = true })
        State.list:addButton(left + 6, y, width - buttonWidth - 20, 28, showQuest, suggestion.questId)
        local buttonLeft = left + width - buttonWidth - 8
        State.list:addRect(buttonLeft, y + 5, buttonWidth, 17, ABANDON_EDGE, 3)
        State.list:addRect(buttonLeft + 1, y + 6, buttonWidth - 2, 15, { 0.1, 0.04, 0.02 }, 4)
        State.list:addText(ns.L("Abandon"), buttonLeft, y + 8, { font = "GameFontHighlightSmall", color = GAUGE_WARN, width = buttonWidth, justify = "CENTER", isSingleLine = true })
        State.list:addButton(buttonLeft, y + 5, buttonWidth, 17, abandon, suggestion.questId)
        y = y + 31
    end
    -- The panel behind it all, drawn last at the bottom layer, now that its height is known
    State.list:addRect(left, top, width, y - top + 2, { 0.42, 0.29, 0.13 }, 0)
    State.list:addRect(left + 1, top + 1, width - 2, y - top, { 0.03, 0.02, 0.01, 0.82 }, 1)
    return y + 10
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
    for _, group in ipairs(model.groups) do
        if #group.shownEntries > 0 then
            State.shownZoneIds[#State.shownZoneIds + 1] = group.zoneId
            local isZoneSelected = group.zoneId == State.selectedLogZoneId
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
                    title = entry.title, level = entry.level, isReady = entry.isTurnIn,
                    isTracked = isTracked[entry.questId],
                    canShareWithParty = Log.canShareWithParty(entry.questId),
                    number = entry.number,
                    progress = ns.MapMarks.getProgress(entry),
                    isFocused = entry.questId == ns.Focus.get(),
                    canFocus = true,
                    itemTexture = entry.item and (entry.item.texture or ITEM_ICON) or nil,
                    subText = progressText ~= "" and progressText or nil,
                    chainText = entry.chainIndex and string.format("%d/%d", entry.chainIndex, entry.chainTotal) or nil,
                    profitText = ns.settings.shouldShowProfit and ns.Profit.format(ns.Profit.get(entry.questId)) or nil,
                })
            end
            y = y + (isCollapsed and 2 or 8) -- folded zones stack close together
        end
    end
    if model.questCount == 0 then
        State.list:addText(ns.L("Your quest log is empty."), 10, y + 4, { color = COLORS.tan, width = State.list.width - 20 })
    elseif not firstEntry then
        State.list:addText(ns.L("No quest matches."), 10, y + 4, { color = COLORS.tan, width = State.list.width - 20 })
    end
    State.list:finish(y + 30)

    local count, max, isNearlyFull = ns.Warnings.getLogSize()
    -- Only the count, to fit beside the tabs over the list (words did not, in Czech least of all); its colour says
    -- how full: amber nearly, red full. The panel over the list says it in words.
    State.frame.status:SetText(string.format("%d/%d", count, max))
    ns.Widgets.setColor(State.frame.status, count >= max and GAUGE_WARN or isNearlyFull and COLORS.amber or COLORS.tan)

    if selectedGroup then
        State.detail:finish(drawZonePage(selectedGroup))
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
        State.detail:finish(drawLogQuest(selectedEntry))
    else
        local hint = model.questCount > 0 and ns.L("Select a quest to open its page and highlight it on the map. Click it again to let go of it.") or ""
        State.detail:addText(hint, PADDING, PADDING, { font = "QuestFont", color = COLORS.softInk, width = State.detail.width - 2 * PADDING })
        State.detail:finish(80)
    end
    return selectedEntry, count
end

-- Shared with the other parts of the window
QuestsTab.FILTER_LABELS = FILTER_LABELS
QuestsTab.drawLogTab = drawLogTab
QuestsTab.selectFilter = selectFilter
