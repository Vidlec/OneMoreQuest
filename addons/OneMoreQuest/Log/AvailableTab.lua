local _, ns = ...

-- The quest log window: the Available tab (quests to pick up in a zone or a dungeon run).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local addListHeading, addListQuest = List.addListHeading, List.addListQuest
local drawAvailableQuest = QuestPage.drawAvailableQuest
local selectedQuestIds = State.selectedQuestIds
local CHAIN_ICON, COLORS, DOT, GIVER_ICON, HEADER_BAR_HIGH, HEADER_BAR_LOW =
    Style.CHAIN_ICON, Style.COLORS, Style.DOT, Style.GIVER_ICON, Style.HEADER_BAR_HIGH, Style.HEADER_BAR_LOW
local MEDIA, TAB_AVAILABLE = Style.MEDIA, Style.TAB_AVAILABLE

-- What the Spoilers choice keeps back of the story, asked once a drawing (Availability.isLaterHidden): a quest still
-- to come, and a dungeon. One table, as the file is near the number of names Lua allows it.
local Told = { isStoryHidden = false, isDungeonHidden = false, isChainHidden = false }

local AVAILABLE_SECTIONS =
    { "Pick up here", "Starts from an item found here", "Turned in here, starts elsewhere", "Not yet available" }
local UPCOMING_SECTION = 4

local LOG_FULL_COLOR = { 1, 0.69, 0.29 }
local LOG_FULL_GROUND = { 0.23, 0.1, 0.04 }
local LOG_FULL_HEIGHT = 38

---With a controller, the log full: one banner over the list instead of the warning on every quest's page, A on it
---going to My quests' quests worth dropping. (The rows leave the warning out: it would repeat on each.)
---@return number y Below it
local function addLogFullBanner(y)
    if not ns.Gamepad.isGamepadUI() then
        return y
    end
    local count, max = ns.QuestState.getLogSize()
    if count < max then
        return y
    end
    local width = State.list.width
    State.list:addRect(4, y, width - 8, LOG_FULL_HEIGHT, LOG_FULL_GROUND, 1)
    State.list:addRect(4, y, 3, LOG_FULL_HEIGHT, LOG_FULL_COLOR, 2)
    State.list:addText(
        ns.L("Your quest log is full (%d/%d)", count, max),
        14,
        y + 5,
        { font = "GameFontNormal", color = LOG_FULL_COLOR, width = width - 28, isSingleLine = true }
    )
    State.list:addText(
        ns.L("Drop one to pick these up"),
        14,
        y + 21,
        { font = "GameFontHighlightSmall", color = COLORS.white, width = width - 28, isSingleLine = true }
    )
    State.list:addButton(4, y, width - 8, LOG_FULL_HEIGHT, Log.showDropSuggestions, false).isLogFullBanner = true
    return y + LOG_FULL_HEIGHT + 6
end

local function getSectionIndex(quest)
    if quest.availableAtLevel or quest.blocker then
        return UPCOMING_SECTION
    elseif quest.isHandedInHere then
        return 3
    elseif quest.startType == "item" then
        return 2
    end
    return 1
end

---@return string text The text, then who gives the quest ("· unknown giver" when nobody knows)
local function withGiver(text, quest)
    return text .. DOT .. (quest.starterName or ns.L("unknown giver"))
end

---@return string text The text, then the spot where the quest starts, when it has one
local function withSpot(text, quest)
    local place = quest.nearestPlace or quest.places[1]
    local where = place and place.x >= 0 and string.format("%d, %d", place.x, place.y) or nil
    return text .. (where and (DOT .. where) or "")
end

---A low-level quest (grey, as the game shows it), listed all the same because its chain climbs into the player's
---range: says so, and where it goes.
local function composeLeadsOnText(quest)
    if Told.isStoryHidden then
        return ns.L("Low-level, but its story leads on into your levels") -- (the quest it leads to is later in the story)
    end
    local lead = quest.leadsTo
    return ns.L("Low-level, but leads to [%d] %s", lead.level, lead.title)
        .. DOT
        .. (lead.stepCount == 1 and ns.L("the next step") or ns.Lp(lead.stepCount, "%d step on", "%d steps on"))
end

---A quest whose item drops elsewhere and is handed in here: where the item is, and who takes it.
local function composeHandedInHereText(quest)
    local itemText = quest.isItemInBags and ns.L("Item is in your bags")
        or (
            quest.sourceZoneName and ns.L("Item drops in %s", quest.sourceZoneName)
            or ns.L("Item drops in another place")
        )
    return itemText
        .. DOT
        .. (quest.finisherName and ns.L("turn in to %s", quest.finisherName) or ns.L("turn in to the quest giver"))
end

---A quest to pick up now: what starts it (a creature's drop, the game's own "!", a giver) and where.
local function composeStartText(quest)
    if quest.startType == "item" then
        return withSpot(
            quest.starterName and ns.L("Drops from %s", quest.starterName) or ns.L("Drops from a creature here"),
            quest
        )
    end
    if quest.isFromGame and not quest.starterName then
        -- Not in the quest database: the game's own "!" says where it starts
        return withSpot(ns.L("Shown by the game"), quest)
    end
    return withSpot(quest.starterName or ns.L("Unknown giver"), quest)
end

---What a quest's row says under its title on the Available tab: what holds it back, or what starts it and where.
---@param isBare boolean? Without the steps done back to back (stepsText)
local function composeAvailableSubText(quest, isBare)
    if quest.stepsText and not isBare then
        -- Steps done back to back, versions of one quest: said first, as what the row stands for
        return quest.stepsText .. DOT .. composeAvailableSubText(quest, true)
    end
    if quest.availableAtLevel then
        return withGiver(ns.L("At level %d", quest.availableAtLevel), quest)
    end
    if quest.leadsTo and not quest.blocker then
        return composeLeadsOnText(quest)
    end
    if quest.blocker then
        -- What to do to unlock it: the quest to do first and whether it can be taken now, or the level to reach
        return withGiver(ns.Availability.getShownReason(quest.blocker, quest.unlockText or quest.blocker.text), quest)
    end
    if quest.dungeonStepTitle and not Told.isStoryHidden and not Told.isDungeonHidden then
        -- Picked up elsewhere, it leads into the dungeon a few quests on
        return withGiver(ns.L("Leads to %s", quest.dungeonStepTitle), quest)
    end
    if quest.isHandedInHere then
        return composeHandedInHereText(quest)
    end
    return composeStartText(quest)
end

---"Leads to <dungeon> · <giver>": a quest to pick up for a dungeon (or the start of its chain), where the Spoilers
---choice lets the dungeon be named.
---@return string? text Nil for a quest that leads into no dungeon, one not to be had yet, or one held back
local function composeLeadsToDungeonText(quest)
    if not quest.leadsToDungeonName or quest.availableAtLevel or quest.blocker or Told.isDungeonHidden then
        return nil
    end
    return withGiver(ns.L("Leads to %s", quest.leadsToDungeonName), quest)
end

local LOCK_ICON = Style.LOCK_ICON

local function getStartIcon(quest)
    if quest.blocker then
        return LOCK_ICON
    end
    return List.getStartTypeIcon(quest)
end

local function pickZone(zoneId)
    State.pickedZoneId = zoneId or nil
    State.isPickingZone = false
    selectedQuestIds[TAB_AVAILABLE] = nil
    ns.MapDock.showZoneMap(State.pickedZoneId or ns.Model.getPlayer().zoneId)
    Log.refresh()
end

local function toggleLowLevel()
    ns.settings.shouldShowLowLevel = not ns.settings.shouldShowLowLevel
    -- Everything that lists or marks quests to pick up follows: this list, the map's and the minimap's "!"
    ns.Availability.invalidate()
    ns.queueRefresh()
end

---The list of zones to choose from, shown in place of the quests.
local function drawZonePicker(playerZoneId)
    local y = 4
    local width = State.list.width
    if State.pickedZoneId and playerZoneId then
        State.list:addText(
            ns.L("Back to my location: %s", ns.Database.getZoneName(playerZoneId)),
            10,
            y + 5,
            { font = "GameFontNormal", color = COLORS.gold, width = width - 20, isSingleLine = true }
        )
        State.list:addButton(2, y, width - 4, 24, pickZone, false)
        y = y + 30
    end
    local zones = ns.Availability.getZones({ shouldShowLowLevel = ns.settings.shouldShowLowLevel })
    local hasHeading = false
    for _, zone in ipairs(zones) do
        -- Zones only: the dungeons have a tab of their own
        if zone.isDungeon == false then
            if not hasHeading then
                y = addListHeading(y, ns.L("Zones with quests for you"), "", COLORS.parchment)
                hasHeading = true
            end
            local isCurrent = zone.zoneId == playerZoneId
            State.list:addText(zone.zoneName .. (isCurrent and (DOT .. ns.L("you are here")) or ""), 10, y + 5, {
                font = "GameFontNormal",
                color = isCurrent and COLORS.gold or COLORS.white,
                width = width - 60,
                isSingleLine = true,
            })
            State.list:addText(zone.count, width - 40, y + 6, {
                font = "GameFontHighlightSmall",
                color = COLORS.tan,
                width = 30,
                justify = "RIGHT",
                isSingleLine = true,
            })
            State.list:addButton(2, y, width - 4, 24, pickZone, zone.zoneId)
            y = y + 24
        end
    end
    State.list:finish(y + 20)
end

---A bar of how far the character is through the zone, with the numbers under it.
---@return number y Below the summary
local function addZoneSummary(y, zoneId)
    local summary = ns.Availability.getZoneSummary(zoneId)
    local total = summary.done + summary.inLog + summary.available + summary.notYet
    if total == 0 then
        return y
    end
    local width = State.list.width - 16
    local parts = {
        { count = summary.done, color = { 0.18, 0.56, 0.25 } },
        { count = summary.inLog, color = { 0.79, 0.64, 0.15 } },
        { count = summary.available, color = { 0.95, 0.89, 0.69 } },
        { count = summary.notYet, color = { 0.35, 0.35, 0.38 } },
    }
    local barParts = {}
    for _, part in ipairs(parts) do
        barParts[#barParts + 1] = { share = part.count / total, color = part.color }
    end
    State.list:addStatBar(7, y - 2, width + 2, 13, barParts)
    State.list:addText(
        ns.L(
            "%d done%s%d in your log%s%d available%s%d not yet",
            summary.done,
            DOT,
            summary.inLog,
            DOT,
            summary.available,
            DOT,
            summary.notYet
        ),
        8,
        y + 14,
        {
            font = "GameFontHighlightSmall",
            color = COLORS.tan,
            width = State.list.width - 16,
            isSingleLine = true,
        }
    )
    return y + 34
end

local function toggleUpcoming()
    State.isUpcomingShown = not State.isUpcomingShown
    Log.refresh()
end

-- The steps of one chain kept together under a heading, in the list of quests not yet available. Kept in one
-- table: the file is near the number of names Lua allows it.
local ChainList = {}
do
    local foldedChains = {} -- [the chain's first quest] = true while its heading is folded

    local function toggleChain(chainKey)
        foldedChains[chainKey] = not foldedChains[chainKey] or nil
        Log.refresh()
    end

    ---The quests of a list section with the steps of one chain kept together: a chain with two or more of them
    ---becomes one entry with its steps in chain order, in the place of its first; the rest stay as they are.
    ---@return ({ quest: table }|{ chain: { key: number, name: string, quests: table[], doneCount: number, total: number } })[] entries
    function ChainList.composeEntries(quests)
        local chainKeys, memberCounts = {}, {}
        for _, quest in ipairs(quests) do
            local chainQuestIds = ns.Chain.getQuestIds(quest.questId)
            if #chainQuestIds > 1 then
                chainKeys[quest.questId] = chainQuestIds[1]
                memberCounts[chainQuestIds[1]] = (memberCounts[chainQuestIds[1]] or 0) + 1
            end
        end
        local entries, chainsByKey = {}, {}
        for _, quest in ipairs(quests) do
            local key = chainKeys[quest.questId]
            if key and memberCounts[key] >= 2 then
                local chain = chainsByKey[key]
                if not chain then
                    local chainQuestIds = ns.Chain.getQuestIds(quest.questId)
                    local doneCount = 0
                    for _, chainQuestId in ipairs(chainQuestIds) do
                        doneCount = doneCount + (ns.QuestState.isTurnedIn(chainQuestId) and 1 or 0)
                    end
                    chain = {
                        key = key,
                        name = ns.QuestText.getQuestName(key) or ("Quest " .. key),
                        quests = {},
                        doneCount = doneCount,
                        total = #chainQuestIds,
                    }
                    chainsByKey[key] = chain
                    entries[#entries + 1] = { chain = chain }
                end
                chain.quests[#chain.quests + 1] = quest
            else
                entries[#entries + 1] = { quest = quest }
            end
        end
        for _, chain in pairs(chainsByKey) do
            table.sort(chain.quests, function(first, second)
                return (first.chainIndex or 0) < (second.chainIndex or 0)
            end)
        end
        return entries
    end

    ---A chain's heading over its steps: folds them away or opens them, says how many wait and how far it is done.
    ---@return number y Below the heading
    function ChainList.addHeading(y, chain)
        local width, height = State.list.width, 24
        local isFolded = foldedChains[chain.key]
        State.list:addRect(2, y, width - 4, height, HEADER_BAR_LOW)
        State.list:addRect(2, y, width - 4, height / 2, HEADER_BAR_HIGH, 1)
        State.list:addIcon(8, y + 6, 12, MEDIA .. (isFolded and "ChevronRight" or "ChevronDown"), COLORS.tan, 2)
        State.list:addIcon(24, y + 6, 12, CHAIN_ICON, COLORS.tan, 2)
        local note = ns.Lp(
            #chain.quests,
            "%d waiting%s%d of %d done",
            "%d waiting%s%d of %d done",
            DOT,
            chain.doneCount,
            chain.total
        )
        local _, noteWidth = State.list:addText(
            note,
            width - 10 - 140,
            y + 6,
            { font = "GameFontHighlightSmall", color = COLORS.tan, width = 140, justify = "RIGHT", isSingleLine = true }
        )
        State.list:addText(chain.name, 40, y + 5, {
            font = "GameFontNormal",
            color = COLORS.parchment,
            isSingleLine = true,
            width = width - 10 - math.min(noteWidth, 140) - 8 - 40,
        })
        State.list:addButton(2, y, width - 4, height, toggleChain, chain.key)
        return y + height + 2
    end

    ---The same entries with no chain kept together: each quest on its own.
    function ChainList.composePlainEntries(quests)
        local entries = {}
        for _, quest in ipairs(quests) do
            entries[#entries + 1] = { quest = quest }
        end
        return entries
    end

    function ChainList.isFolded(chainKey)
        return foldedChains[chainKey] == true
    end
end

-- The zone's quests by what to do next: the ones to pick up now, then the ones not yet to be had under what opens
-- them, nearest first: a quest in the log, a quest to pick up now, a level to reach, anything else. Each of those
-- is named once, as a heading over the quests it opens, not on every row. Chips over the list keep it to what is
-- near. Kept in one table: the file is near the number of names Lua allows it.
local NextList = {}
do
    local MAX_GROUP_ROWS = 4 -- a group with more quests shows these and "N more"
    local FILTERS = { "all", "now", "soon", "later" }
    local FILTER_LABELS = { all = "All", now = "Now", soon = "Soon", later = "Later" }
    local SECTION_ORDER = { "now", "log", "take", "level", "other" }
    local SECTION_TITLES = {
        now = "Pick up now",
        log = "Opens from your log",
        take = "Opens after a pick-up",
        level = "Needs a level",
        other = "Needs something else",
    }
    local SECTION_FILTERS = { now = "now", log = "soon", take = "soon", level = "later", other = "later" }
    local ACTIVE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"
    local foldedGroups = {} -- [group key] = true or false once its heading was clicked; before that, by its kind
    local openedGroups = {} -- [group key] = true once its "N more" was clicked: every quest of it shows

    local function toggleGroup(group)
        foldedGroups[group.key] = not group.isFolded
        Log.refresh()
    end

    local function openGroup(key)
        openedGroups[key] = true
        Log.refresh()
    end

    local function pickFilter(filter)
        State.availableFilter = filter
        Log.refresh()
    end

    ---The quests sorted into the sections: those to pick up now as they are, the others in groups by what opens them.
    ---@param available table[] Quests to pick up now
    ---@param upcoming table[] Quests not yet to be had: a few levels away (availableAtLevel), or held back (unlockRoot)
    ---@return table<string, table[]> sections [section] = quests ("now") or groups { key, kind, title, note, quests }
    ---@return table<string, number> counts How many quests each filter keeps
    function NextList.compose(available, upcoming, player)
        local sections = { now = available, log = {}, take = {}, level = {}, other = {} }
        local groups = {}
        for _, quest in ipairs(upcoming) do
            local root = quest.unlockRoot
                or { kind = "level", level = quest.availableAtLevel or (quest.blocker and quest.blocker.level) }
            if root.kind == "level" and not root.level then
                root = { kind = "other", text = quest.blocker and quest.blocker.text or ns.L("Not yet") }
            end
            local key = root.kind .. ":" .. tostring(root.questId or root.level or root.text)
            local group = groups[key]
            if not group then
                group = { key = key, kind = root.kind, questId = root.questId, level = root.level, quests = {} }
                if root.questId then
                    group.title = ns.QuestText.getQuestName(root.questId) or ns.L("Quest %s", root.questId)
                elseif root.level then
                    group.title = ns.L("At level %d", root.level)
                else
                    group.title = root.text
                end
                groups[key] = group
                table.insert(sections[root.kind], group)
            end
            group.quests[#group.quests + 1] = quest
        end
        table.sort(sections.level, function(first, second)
            return first.level < second.level
        end)
        local counts = { all = #available, now = #available, soon = 0, later = 0 }
        for _, name in ipairs({ "log", "take", "level", "other" }) do
            for _, group in ipairs(sections[name]) do
                local count = #group.quests
                counts.all, counts[SECTION_FILTERS[name]] = counts.all + count, counts[SECTION_FILTERS[name]] + count
                if group.kind == "log" then
                    group.note = ns.L("in your log") .. DOT .. ns.Lp(count, "opens %d", "opens %d")
                elseif group.kind == "take" then
                    group.note = ns.L("pick up now") .. DOT .. ns.Lp(count, "opens %d", "opens %d")
                elseif group.kind == "level" then
                    group.note = ns.Lp(
                        math.max(group.level - (player.level or 0), 0),
                        "%d level to go",
                        "%d levels to go"
                    ) .. DOT .. ns.Lp(count, "%d quest", "%d quests")
                else
                    group.note = ns.Lp(count, "%d quest", "%d quests")
                end
            end
        end
        return sections, counts
    end

    ---The chips over the list: all of the zone's quests, or only those for now, soon (a quest away) or later.
    ---@return number y Below them
    function NextList.addChips(y, counts)
        local x = 8
        local chosen = State.availableFilter or "all"
        for _, filter in ipairs(FILTERS) do
            local text = ns.L(FILTER_LABELS[filter]) .. " " .. counts[filter]
            local isChosen = filter == chosen
            local _, textWidth = State.list:addText(text, x + 9, y + 4, {
                font = "GameFontHighlightSmall",
                color = isChosen and COLORS.white or COLORS.tan,
                isSingleLine = true,
            })
            local width = math.ceil(textWidth or #text * 6) + 18
            State.list:addRect(x, y, width, 20, isChosen and Style.SELECTED_EDGE or COLORS.rule)
            State.list:addRect(x + 1, y + 1, width - 2, 18, isChosen and HEADER_BAR_HIGH or Style.BACKGROUND, 1)
            State.list:addButton(x, y, width, 20, pickFilter, filter)
            x = x + width + 6
        end
        return y + 28
    end

    ---A group's heading: what opens its quests, where that stands, and how many it opens; a click folds the group.
    ---@return number y Below the heading
    local function addGroupHeading(y, group)
        local width, height = State.list.width, 24
        State.list:addRect(2, y, width - 4, height, HEADER_BAR_LOW)
        State.list:addRect(2, y, width - 4, height / 2, HEADER_BAR_HIGH, 1)
        State.list:addIcon(8, y + 6, 12, MEDIA .. (group.isFolded and "ChevronRight" or "ChevronDown"), COLORS.tan, 2)
        local icon = group.kind == "log" and ACTIVE_ICON or group.kind == "take" and GIVER_ICON or Style.LOCK_ICON
        State.list:addIcon(23, y + 4, 16, icon, nil, 2)
        local _, noteWidth = State.list:addText(
            group.note,
            width - 10 - 170,
            y + 6,
            { font = "GameFontHighlightSmall", color = COLORS.tan, width = 170, justify = "RIGHT", isSingleLine = true }
        )
        State.list:addText(group.title, 43, y + 5, {
            font = "GameFontNormal",
            color = COLORS.parchment,
            isSingleLine = true,
            width = width - 10 - math.min(noteWidth or 170, 170) - 8 - 43,
        })
        State.list:addButton(2, y, width - 4, height, toggleGroup, group)
        return y + height + 2
    end

    ---What a quest under a heading still says for itself: how much further down the chain it is, a level it needs
    ---besides, or (under a level) who gives it.
    local function composeGroupSubText(quest, group)
        local parts = {}
        local stepCount = quest.unlockRoot and quest.unlockRoot.stepCount or 0
        if group.questId and stepCount > 1 then
            parts[#parts + 1] = ns.Lp(stepCount - 1, "%d more quest first", "%d more quests first")
        end
        if group.kind ~= "level" and quest.blocker and quest.blocker.level then
            parts[#parts + 1] = ns.L("needs level %d", quest.blocker.level)
        end
        if group.kind == "level" and quest.starterName then
            parts[#parts + 1] = quest.starterName
        end
        return #parts > 0 and table.concat(parts, DOT) or nil
    end

    ---Draws the sections the chosen chip keeps.
    ---@param addQuestRow fun(quest: table, indent: number, subText: string?) Draws one quest's row at the list's y
    ---@param options { isSearching: boolean, selectedQuestId: number? }
    ---@return number y Below them
    function NextList.draw(y, sections, addHeading, addQuestRow, options)
        local chosen = State.availableFilter or "all"
        for _, name in ipairs(SECTION_ORDER) do
            local section = sections[name]
            local isKept = #section > 0 and (chosen == "all" or SECTION_FILTERS[name] == chosen or options.isSearching)
            if isKept and name == "now" then
                y = addHeading(y, ns.L(SECTION_TITLES.now), #section)
                for _, quest in ipairs(section) do
                    y = addQuestRow(y, quest, 0)
                end
                y = y + 8
            elseif isKept then
                local count = 0
                for _, group in ipairs(section) do
                    count = count + #group.quests
                end
                y = addHeading(y, ns.L(SECTION_TITLES[name]), count)
                for _, group in ipairs(section) do
                    -- Folded until asked for where what opens them is far off; a search opens every group
                    group.isFolded = foldedGroups[group.key]
                    if group.isFolded == nil then
                        group.isFolded = group.kind == "level" or group.kind == "other"
                    end
                    group.isFolded = group.isFolded and not options.isSearching
                    y = addGroupHeading(y, group)
                    local isWhole = openedGroups[group.key]
                        or options.isSearching
                        or #group.quests <= MAX_GROUP_ROWS + 1
                    local shownCount = 0
                    for position, quest in ipairs(group.quests) do
                        -- (the selected quest shows whatever is folded, so a quest opened by a link is in view)
                        local isShown = (not group.isFolded and (isWhole or position <= MAX_GROUP_ROWS))
                            or quest.questId == options.selectedQuestId
                        if isShown then
                            shownCount = shownCount + 1
                            y = addQuestRow(y, quest, 14, composeGroupSubText(quest, group) or false)
                        end
                    end
                    if not group.isFolded and shownCount < #group.quests then
                        State.list:addText(
                            "+ " .. ns.Lp(#group.quests - shownCount, "%d more quest", "%d more quests"),
                            30,
                            y + 3,
                            { font = "GameFontHighlightSmall", color = COLORS.tan, isSingleLine = true }
                        )
                        State.list:addButton(2, y, State.list.width - 4, 20, openGroup, group.key)
                        y = y + 22
                    end
                    y = y + 2
                end
                y = y + 8
            end
        end
        return y
    end
end

---The fixed line under the Available list: low-level quests are hidden unless ticked, and it says how many.
State.setLowLevelCount = function(hiddenCount)
    if not State.lowLevelCheck then
        return
    end
    State.lowLevelCheck:SetChecked(ns.settings.shouldShowLowLevel == true)
    State.lowLevelLabel:SetText(
        ns.L("Show low-level quests")
            .. (hiddenCount > 0 and (" " .. ns.Lp(hiddenCount, "(%d hidden)", "(%d hidden)")) or "")
    )
end

---------------------------------------------------------------------------------------------------------------
-- What the list holds. Worked out once a drawing into one table, the view:
--   zoneId, pickup        the location shown, and the Spoilers choice of which quests to pick up may be named
--   quests                the zone's quests to pick up (List.keepToPickUp), before those held back are added
--   sections, sectionTitles, foldedSectionIndex
--                         the quests by section, each section's title, and the one folded until asked for (none in
--                         a dungeon's run)
--   hiddenCount, availableCount
--                         the low-level quests the filter hides, and the count on the tab
--   isDungeonRun, isSearching, searchText, isNextList, isUpcomingOpen, isRowListed
--                         what kind of list it is, and whether any row is listed

---Puts a quest in the section of AVAILABLE_SECTIONS it belongs to.
local function addToSection(sections, quest)
    local section = sections[getSectionIndex(quest)]
    section[#section + 1] = quest
end

---After the quests a few levels away, the ones held back by something else, each saying what. A quest the game
---itself offers is listed to pick up, though the rules hold it back: once, not again here.
---@param isListed table<number, boolean> The quests listed already; those added are marked in it
---@return number hiddenCount The low-level ones among them the filter hides
local function addBlockedQuests(view, isListed)
    local blockedQuests, blockedHiddenCount =
        ns.Availability.getBlockedQuests(view.zoneId, { shouldShowLowLevel = ns.settings.shouldShowLowLevel })
    blockedQuests = List.keepToPickUp(blockedQuests, view.pickup)
    for _, quest in ipairs(blockedQuests) do
        if not isListed[quest.questId] then
            table.insert(view.sections[UPCOMING_SECTION], quest)
            isListed[quest.questId] = true
        end
    end
    return blockedHiddenCount
end

---A quest chosen elsewhere (a link to an earlier quest, a mark on the map) is listed even when the low-level filter
---hides it, so its page is there to see; or one not to be taken yet (a later step of a chain, opened from the chain
---on a quest's page).
---@param isListed table<number, boolean> The quests listed already
local function addChosenQuest(view, isListed)
    local chosenQuestId = selectedQuestIds[TAB_AVAILABLE]
    if not chosenQuestId or isListed[chosenQuestId] or ns.settings.shouldShowLowLevel then
        return
    end
    local quests = ns.Availability.getQuests(view.zoneId, { shouldShowLowLevel = true })
    for _, quest in ipairs(List.keepToPickUp(quests, view.pickup)) do
        if quest.questId == chosenQuestId then
            addToSection(view.sections, quest)
            isListed[chosenQuestId] = true
        end
    end
    if isListed[chosenQuestId] then
        return
    end
    local blockedQuests = ns.Availability.getBlockedQuests(view.zoneId, { shouldShowLowLevel = true })
    for _, quest in ipairs(List.keepToPickUp(blockedQuests, view.pickup)) do
        if quest.questId == chosenQuestId then
            table.insert(view.sections[UPCOMING_SECTION], quest)
            isListed[chosenQuestId] = true
        end
    end
end

---The zone's quests by AVAILABLE_SECTIONS: to pick up here, from an item, turned in here, and not yet available.
local function composeZoneSections(view)
    local quests, hiddenCount =
        ns.Availability.getQuests(view.zoneId, { shouldShowLowLevel = ns.settings.shouldShowLowLevel })
    quests = List.keepToPickUp(quests, view.pickup)
    view.quests, view.sections = quests, { {}, {}, {}, {} }
    view.sectionTitles, view.foldedSectionIndex = AVAILABLE_SECTIONS, UPCOMING_SECTION
    view.availableCount = 0
    local isListed = {}
    for _, quest in ipairs(quests) do
        if not quest.availableAtLevel then
            view.availableCount = view.availableCount + 1
        end
        -- The search box belongs to My quests and is hidden here, so it does not filter this list
        addToSection(view.sections, quest)
        isListed[quest.questId] = true
    end
    view.hiddenCount = hiddenCount + addBlockedQuests(view, isListed)
    addChosenQuest(view, isListed)
    view.isRowListed = #quests > 0
end

local RUN_SECTION_TITLES = { "In your log", "Pick up before you go", "Found inside", "Behind a lead-in", "Not yet" }

---A dungeon's list is a plan for one run: every quest done inside, sorted by what to do about it, and the lead-ins
---that open the ones behind them, named as lead-ins.
local function composeRunSections(view)
    local run = List.keepRunToPickUp(ns.Availability.getDungeonRun(view.zoneId), view.pickup)
    view.sections = { run.inLog, run.pickUp, run.foundInside, run.behindLeadIn, run.notYet }
    view.sectionTitles, view.foldedSectionIndex = RUN_SECTION_TITLES, nil
    view.hiddenCount = 0
    view.availableCount = #run.pickUp + #run.foundInside
    view.isRowListed = #run.inLog + #run.pickUp + #run.foundInside + #run.behindLeadIn + #run.notYet > 0
end

---The search beside the location keeps the quests whose title, giver or start item holds what is typed.
local function keepSearchedQuests(view)
    view.isRowListed = false
    for sectionIndex, section in ipairs(view.sections) do
        local kept = {}
        for _, quest in ipairs(section) do
            if ns.Availability.isSearchMatch(quest, view.searchText) then
                kept[#kept + 1] = quest
            end
        end
        view.sections[sectionIndex] = kept
        view.isRowListed = view.isRowListed or #kept > 0
    end
end

---Works out what the list of a location holds (the view above).
local function composeView(zoneId)
    -- The Spoilers choice: which quests to pick up may be named (all, or only those whose giver the player met), and
    -- what of the story is kept back; asked once for the whole list
    local view = { zoneId = zoneId, pickup = List.getPickupChoice() }
    Told.isStoryHidden, Told.isDungeonHidden =
        ns.Availability.isLaterHidden("quest"), ns.Availability.isLaterHidden("dungeon")
    Told.isChainHidden = ns.Spoilers.isActive() and ns.Spoilers.getChoice("chains") == "hidden"
    composeZoneSections(view)
    view.isDungeonRun = ns.Database.getDungeon(zoneId) ~= nil
    if view.isDungeonRun then
        composeRunSections(view)
    end
    -- A search opens the quests not yet available too, as what is looked for may be among them
    view.searchText = State.availableSearchText or ""
    view.isSearching = view.searchText ~= ""
    if view.isSearching then
        keepSearchedQuests(view)
    end
    -- A zone's list is by what to do next (NextList), unless the Spoilers choice keeps the story back: what opens a
    -- quest would name the quests before it
    view.isNextList = not view.isDungeonRun and not Told.isStoryHidden
    view.isUpcomingOpen = State.isUpcomingShown or view.isSearching or view.isNextList
    return view
end

---@return table? quest The selected quest, when the list shows it (not under the folded section, nor a dungeon's
---quest in the log, which opens on My quests)
local function findSelectedQuest(view)
    local selectedQuest
    for sectionIndex, section in ipairs(view.sections) do
        if sectionIndex ~= view.foldedSectionIndex or view.isUpcomingOpen then
            for _, quest in ipairs(section) do
                if
                    quest.questId == selectedQuestIds[TAB_AVAILABLE] and not (view.isDungeonRun and sectionIndex == 1)
                then
                    selectedQuest = quest
                end
            end
        end
    end
    return selectedQuest
end

---------------------------------------------------------------------------------------------------------------
-- A dungeon's run: what its rows say

---"After <lead-ins>": the quests to do first (a long chain says how long it is and where it starts, not every
---step), with the other dungeon whose run comes first, and whether the last of them is in the log.
local function composeAfterLeadInsText(quest, zoneId)
    local names = {}
    for _, leadInId in ipairs(quest.leadInIds) do
        names[#names + 1] = ns.QuestText.getQuestName(leadInId) or ("Quest " .. leadInId)
    end
    local text = #names > 2 and ns.L("After %d lead-ins, from %s", #names, names[1])
        or ns.L("After %s", table.concat(names, " > "))
    local lastLeadInId = quest.leadInIds[#quest.leadInIds]
    local lastLeadInDungeon = lastLeadInId
        and ns.Database.getDungeon(ns.Location.getInsideDungeonIds(lastLeadInId)[1] or 0)
    if lastLeadInDungeon and lastLeadInDungeon.areaId ~= zoneId then
        text = text .. " (" .. lastLeadInDungeon.name .. ")" -- a run of another dungeon first
    end
    if lastLeadInId and ns.QuestState.isInLog(lastLeadInId) then
        text = text .. DOT .. ns.L("in your log")
    end
    return text
end

---Where a quest of the run stands: in the log, a lead-in, behind lead-ins, found inside, or as a zone's quest.
local function composeRunStanding(quest, sectionIndex, zoneId)
    if sectionIndex == 1 then
        return ns.L("In your log")
    end
    if quest.isLeadIn and Told.isStoryHidden then
        return withGiver(ns.L("Lead-in"), quest) -- (what it leads to is later in the story)
    end
    if quest.leadInIds and Told.isStoryHidden then
        return ns.L("Later in the story")
    end
    if quest.isLeadIn then
        return withGiver(ns.L("Lead-in for %s", quest.leadsToTitle), quest)
    end
    if quest.leadInIds then
        return composeAfterLeadInsText(quest, zoneId)
    end
    if sectionIndex == 3 then
        local text = ns.L(
            quest.startType == "item" and "Drops inside: %s" or "Given inside: %s",
            quest.itemName or quest.starterName or ns.L("unknown")
        )
        return quest.stepsText and (quest.stepsText .. DOT .. text) or text
    end
    return composeAvailableSubText(quest)
end

---What a row of a dungeon's run says under its title: where it stands and what to do about it.
local function composeRunText(quest, sectionIndex, zoneId)
    local text = composeRunStanding(quest, sectionIndex, zoneId)
    if quest.opensTitle and not Told.isStoryHidden then -- (held back, the quest it opens is later in the story)
        text = text .. DOT .. ns.L("opens %s", quest.opensTitle)
    elseif quest.isLeadInOnRun then
        text = text .. DOT .. ns.L("both on one run")
    end
    return quest.isLowLevel and (text .. DOT .. ns.L("low-level")) or text
end

---------------------------------------------------------------------------------------------------------------
-- The list's parts

---A dungeon the database does not know: only the quests seen done inside are listed, and the list says so.
---@return number y Below the note
local function addLearnedDungeonNote(y, view)
    local runDungeon = view.isDungeonRun and ns.Database.getDungeon(view.zoneId)
    if not (runDungeon and runDungeon.isLearned) then
        return y
    end
    local noteHeight = State.list:addText(
        ns.L(
            "Learned from your runs: the quest database does not know this dungeon yet, so only the quests you picked up, worked on or handed in inside are listed. More may be done here. The QuestieTrace addon helps the database learn it."
        ),
        10,
        y + 2,
        { color = COLORS.tan, width = State.list.width - 20 }
    )
    return y + 8 + math.max(tonumber(noteHeight) or 0, 28)
end

local function addNextHeading(top, title, count)
    return addListHeading(top, title, count, COLORS.parchment)
end

---A quest's row in the list by what to do next (NextList.draw).
---@param subText string|false|nil What its heading leaves it to say; false: nothing; nil: what starts it, and how
---far the way to it is
local function addNextQuestRow(top, quest, indent, subText)
    local icon = getStartIcon(quest)
    local isAvailable = not (quest.availableAtLevel or quest.blocker)
    if subText == nil then
        subText = composeLeadsToDungeonText(quest) or composeAvailableSubText(quest)
        -- How far the way to it is, for a quest to pick up now
        if isAvailable and quest.distance then
            subText = subText .. DOT .. ns.Widgets.formatDistance(quest.distance)
        end
    end
    local experience = isAvailable
        and ns.QuestTooltip.isExperienceShown(quest.questId)
        and ns.QuestTooltip.getExperience(quest.questId)
    return addListQuest(top, quest.questId, {
        indent = indent,
        title = quest.title,
        level = quest.level,
        subText = subText or nil,
        profitText = experience and ns.QuestTooltip.formatExperience(experience) or nil,
        color = (not isAvailable or quest.isLowLevel) and COLORS.grey or nil,
        icon = icon,
        iconColour = icon == GIVER_ICON and ns.MapMarks.getQuestIconColour(quest.questId, quest.isLowLevel) or nil,
        chainText = not Told.isChainHidden and List.composeChainText(quest) or nil,
        chainIcon = not quest.chainIndex and ns.LogStyle.UNLOCK_ICON or nil,
        warnings = isAvailable and ns.Warnings.getQuestWarnings(quest.questId, true) or nil,
    })
end

---A zone's list by what to do next: the chips, then the sections they keep.
---@return number y Below it
local function addNextList(y, view)
    local available = {}
    for sectionIndex = 1, UPCOMING_SECTION - 1 do
        for _, quest in ipairs(view.sections[sectionIndex]) do
            available[#available + 1] = quest
        end
    end
    local nextSections, counts =
        NextList.compose(available, view.sections[UPCOMING_SECTION], ns.Availability.getPlayer())
    if counts.all > 0 and not view.isSearching then
        y = NextList.addChips(y, counts)
    end
    return NextList.draw(y, nextSections, addNextHeading, addNextQuestRow, {
        isSearching = view.isSearching,
        selectedQuestId = selectedQuestIds[TAB_AVAILABLE],
    })
end

local function openInLog(questId)
    Log.showQuestAnywhere(questId)
end

---A quest's row in a section; a quest for a dungeon (or the start of its chain) says where it leads.
---@return number y Below the row
local function addSectionQuestRow(y, quest, indent, view, sectionIndex)
    local isInLog = view.isDungeonRun and sectionIndex == 1
    local icon = not isInLog and getStartIcon(quest) or nil
    return addListQuest(y, quest.questId, {
        indent = indent,
        title = quest.title,
        level = quest.level,
        subText = view.isDungeonRun and composeRunText(quest, sectionIndex, view.zoneId) or composeLeadsToDungeonText(
            quest
        ) or composeAvailableSubText(quest),
        color = (quest.availableAtLevel or quest.blocker or quest.isLowLevel) and COLORS.grey or nil,
        icon = icon,
        -- (a giver's "!" in the colour of the quest's kind: repeatable blue, an event's green...)
        iconColour = icon == GIVER_ICON and ns.MapMarks.getQuestIconColour(quest.questId, quest.isLowLevel) or nil,
        chainText = not Told.isChainHidden and List.composeChainText(quest) or nil,
        chainIcon = not quest.chainIndex and ns.LogStyle.UNLOCK_ICON or nil,
        warnings = not isInLog and ns.Warnings.getQuestWarnings(quest.questId, true) or nil,
        handleClick = isInLog and openInLog or nil, -- a quest in the log opens there
    })
end

---Quests not yet available: the steps of one chain under a heading of its own (where the Spoilers choice keeps the
---story back, no chain's heading names its first step).
---@return number y Below them
local function addUpcomingQuests(y, section, view, sectionIndex)
    local entries = Told.isStoryHidden and ChainList.composePlainEntries(section) or ChainList.composeEntries(section)
    for _, entry in ipairs(entries) do
        if entry.chain then
            y = ChainList.addHeading(y, entry.chain)
            -- A folded chain still shows its selected step, so a quest opened by a link is in view
            local isFolded = ChainList.isFolded(entry.chain.key)
            for _, quest in ipairs(entry.chain.quests) do
                if not isFolded or quest.questId == selectedQuestIds[TAB_AVAILABLE] then
                    y = addSectionQuestRow(y, quest, 14, view, sectionIndex)
                end
            end
        else
            y = addSectionQuestRow(y, entry.quest, 0, view, sectionIndex)
        end
    end
    return y
end

---The list by sections (a dungeon's run, or a zone's while the story is kept back), each under its heading; the
---section of quests not yet available is folded until its heading is clicked.
---@return number y Below them
local function addSectionLists(y, view)
    for sectionIndex, section in ipairs(view.sections) do
        if #section > 0 then
            local isUpcoming = sectionIndex == view.foldedSectionIndex
            local label = (isUpcoming and not view.isUpcomingOpen and "+ " or "")
                .. ns.L(view.sectionTitles[sectionIndex])
            y = addListHeading(
                y,
                label,
                #section,
                COLORS.parchment,
                isUpcoming and not view.isSearching and toggleUpcoming or nil
            )
            if not isUpcoming then
                for _, quest in ipairs(section) do
                    y = addSectionQuestRow(y, quest, 0, view, sectionIndex)
                end
            elseif view.isUpcomingOpen then
                y = addUpcomingQuests(y, section, view, sectionIndex)
            end
            y = y + 8
        end
    end
    return y
end

---A search names the other zones with quests that match, each a click away (the search stays).
---@return number y Below them
---@return boolean isListed Some were named
local function addOtherZones(y, view)
    local others = ns.Availability.findInOtherZones(
        view.searchText,
        view.zoneId,
        { shouldShowLowLevel = ns.settings.shouldShowLowLevel }
    )
    if #others == 0 then
        return y, false
    end
    y = addListHeading(y, ns.L("In other zones"), #others, COLORS.parchment)
    for index = 1, math.min(#others, 6) do
        local other = others[index]
        local text = "|cffffd100" .. other.zoneName .. "|r" .. DOT .. table.concat(other.titles, ", ")
        local textHeight = State.list:addText(
            text,
            10,
            y + 3,
            { font = "GameFontHighlightSmall", color = COLORS.tan, width = State.list.width - 20 }
        )
        local height = math.max(tonumber(textHeight) or 12, 12) + 6
        State.list:addButton(2, y, State.list.width - 4, height, pickZone, other.zoneId)
        y = y + height
    end
    return y + 8, true
end

---@return table[] entrances The dungeons whose way in is in the zone: only those the Spoilers choice lets be named
---(those entered, or all, or none)
local function getEntranceDungeons(zoneId)
    local entranceDungeons = ns.Availability.getEntranceDungeons(zoneId)
    if not ns.Spoilers.isActive() then
        return entranceDungeons
    end
    local known = {}
    for _, entrance in ipairs(entranceDungeons) do
        if List.isDungeonKnown(entrance.dungeonId) then
            known[#known + 1] = entrance
        end
    end
    return known
end

local function showEntranceDungeon(rowId)
    Log.showDungeon(-rowId)
end

---Under a dungeon's row: how many quests to pick up inside, and its levels. (The count is left out where the choice
---names only some of them.)
local function composeEntranceText(entrance, pickup, minLevel, maxLevel)
    local countText = pickup == "all"
            and ns.Lp(entrance.count, "%d quest to pick up inside", "%d quests to pick up inside")
        or ns.L("Dungeon")
    if minLevel and maxLevel and minLevel ~= maxLevel then
        return countText .. DOT .. ns.L("levels %d-%d", minLevel, maxLevel)
    end
    return countText
end

---Dungeons whose way in is here: their quests are the dungeon's, on the Dungeons tab; this points the way.
---@return number y Below them
---@return boolean isListed Some were named
local function addEntranceDungeons(y, view)
    local entranceDungeons = getEntranceDungeons(view.zoneId)
    if #entranceDungeons == 0 then
        return y, false
    end
    y = addListHeading(y, ns.L("Dungeons with their way in here"), #entranceDungeons, COLORS.parchment)
    for _, entrance in ipairs(entranceDungeons) do
        local minLevel, maxLevel = ns.Availability.getZoneLevels(entrance.dungeonId)
        y = addListQuest(y, -entrance.dungeonId, {
            title = entrance.name,
            level = minLevel or ns.Model.getPlayer().level or 1,
            color = COLORS.parchment,
            subText = composeEntranceText(entrance, view.pickup, minLevel, maxLevel),
            icon = "Interface\\Icons\\INV_Misc_Key_03",
            handleClick = showEntranceDungeon,
        })
    end
    return y + 8, true
end

---@return number y Below the line that says why the list is empty
local function addEmptyNote(y, view)
    local emptyText = view.isSearching and ns.L('No quest to pick up matches "%s".', State.availableSearchText)
        or ns.L(
            view.isDungeonRun and "No quests for you are done in here, or all of them are done."
                or "Nothing to pick up here right now."
        )
    State.list:addText(emptyText, 10, y + 4, { color = COLORS.tan, width = State.list.width - 20 })
    return y + 24
end

---The list of a location's quests: the log-full banner and the zone's summary, its quests, then (searching) the
---other zones with matches, or the dungeons whose way in is here; a line when nothing is listed.
---@return number y Below the list
local function addAvailableList(view)
    -- (the summary counts the quests to pick up here: not while the choice names only some of them)
    local top = addLogFullBanner(6)
    local y = view.pickup == "all" and addZoneSummary(top, view.zoneId) or top
    y = addLearnedDungeonNote(y, view)
    if view.isNextList then
        y = addNextList(y, view)
    else
        y = addSectionLists(y, view)
    end
    local isListed
    if view.isSearching and view.pickup == "all" then -- (other zones would name quests the choice keeps back)
        y, isListed = addOtherZones(y, view)
        view.isRowListed = view.isRowListed or isListed
    end
    if not view.isDungeonRun and not view.isSearching then
        y, isListed = addEntranceDungeons(y, view)
        view.isRowListed = view.isRowListed or isListed
    end
    if not view.isRowListed then
        y = addEmptyNote(y, view)
    end
    return y
end

---------------------------------------------------------------------------------------------------------------
-- The tab

---The location over the list. Its text follows the location, also when the map chose it: the menu is built again
---only when the location shown changed (building it lists every zone with quests), and anyway as it opens.
local function showLocation(player, zoneId)
    local zoneName = zoneId and ns.Database.getZoneName(zoneId) or player.zoneName or ns.L("Unknown location")
    State.frame.zoneButton.label:SetText(zoneName)
    State.frame.zoneButton.note:SetText(zoneId == player.zoneId and ns.L("you are here") or "")
    State.frame.zoneButton.arrow:SetText(ns.L("change"))
    local menuKey = tostring(zoneId) .. ":" .. tostring(player.zoneId) .. ":" .. zoneName
    if State.zoneDropdown and State.zoneDropdown.GenerateMenu and State.zoneMenuKey ~= menuKey then
        State.zoneMenuKey = menuKey
        if State.zoneDropdown.SetDefaultText then
            State.zoneDropdown:SetDefaultText(zoneName) -- named even if no line of the menu is the one shown
        end
        State.zoneDropdown:GenerateMenu()
    end
end

local pageQuest, pageZoneId -- what the page beside the list shows, read by its drawing function below

local function drawSelectedQuestPage()
    return drawAvailableQuest(pageQuest, pageZoneId)
end

---The page beside the list: the selected quest's, or a hint on selecting one.
local function drawAvailablePage(selectedQuest, view)
    if selectedQuest and State.mapQuestId == selectedQuest.questId then
        Actions.showChosenQuestStart(selectedQuest)
    end
    State.mapQuestId = nil
    if selectedQuest then
        pageQuest, pageZoneId = selectedQuest, view.zoneId
        State.frame.finishPage(drawSelectedQuestPage)
        return
    end
    QuestPage.drawHintPage(
        #view.quests > 0
                and ns.L(
                    "Select a quest to see how to start it and to mark its giver and turn-in on the map. Click it again to let go of it."
                )
            or ""
    )
end

---Draws the Available tab: the location's quests to pick up (or the zones to choose from), and the page.
---@return table? selected, number? availableCount nil while the database is being read
local function drawAvailableTab()
    local player = ns.Model.getPlayer()
    local zoneId = State.pickedZoneId or player.zoneId
    showLocation(player, zoneId)
    if not ns.Availability.isReady() then
        List.drawDatabaseWait()
        return nil, nil
    end
    if State.isPickingZone then
        drawZonePicker(player.zoneId)
        State.detail:finish(1)
        State.frame.status:SetText("")
        return nil, nil
    end
    local view = composeView(zoneId)
    -- No quest is selected until the player picks one, here as on My quests
    local selectedQuest = findSelectedQuest(view)
    State.selectedAvailableQuest = selectedQuest
    local y = addAvailableList(view)
    State.setLowLevelCount(view.hiddenCount)
    State.list:finish(y + 8)

    -- The tab counts what is available, and the low-level switch under the list how many it hides: nothing
    -- more to say beside the tabs
    State.frame.status:SetText("")
    drawAvailablePage(selectedQuest, view)
    return selectedQuest, view.availableCount
end

-- Shared with the other parts of the window
AvailableTab.drawAvailableTab = drawAvailableTab
AvailableTab.pickZone = pickZone
AvailableTab.toggleLowLevel = toggleLowLevel
