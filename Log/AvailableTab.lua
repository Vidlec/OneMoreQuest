local _, ns = ...

-- The quest log window: the Available tab (quests to pick up in a zone or a dungeon run).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window = ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local addListHeading, addListQuest = List.addListHeading, List.addListQuest
local drawAvailableQuest = QuestPage.drawAvailableQuest
local selectedQuestIds = State.selectedQuestIds
local CHAIN_ICON, COLORS, DOT, GIVER_ICON, HEADER_BAR_HIGH, HEADER_BAR_LOW = Style.CHAIN_ICON, Style.COLORS, Style.DOT, Style.GIVER_ICON, Style.HEADER_BAR_HIGH, Style.HEADER_BAR_LOW
local ITEM_ICON, MEDIA, OBJECT_ICON, PADDING, TAB_AVAILABLE = Style.ITEM_ICON, Style.MEDIA, Style.OBJECT_ICON, Style.PADDING, Style.TAB_AVAILABLE

local AVAILABLE_SECTIONS = { "Pick up here", "Starts from an item found here", "Turned in here, starts elsewhere", "Not yet available" }
local UPCOMING_SECTION = 4

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

local function composeAvailableSubText(quest, isBare)
    if quest.stepsText and not isBare then
        -- Steps done back to back, versions of one quest: said first, as what the row stands for
        return quest.stepsText .. DOT .. composeAvailableSubText(quest, true)
    end
    local place = quest.nearestPlace or quest.places[1]
    local where = place and place.x >= 0 and string.format("%d, %d", place.x, place.y) or nil
    if quest.availableAtLevel then
        return ns.L("At level %d", quest.availableAtLevel) .. DOT .. (quest.starterName or ns.L("unknown giver"))
    elseif quest.leadsTo and not quest.blocker then
        -- Low-level (grey, as the game shows it), listed all the same because its chain climbs into the player's
        -- range: says so, and where it goes
        local lead = quest.leadsTo
        return ns.L("Low-level, but leads to [%d] %s", lead.level, lead.title) .. DOT
            .. (lead.stepCount == 1 and ns.L("the next step") or ns.Lp(lead.stepCount, "%d step on", "%d steps on"))
    elseif quest.blocker then
        -- What to do to unlock it: the quest to do first and whether it can be taken now, or the level to reach
        return (quest.unlockText or quest.blocker.text) .. DOT .. (quest.starterName or ns.L("unknown giver"))
    elseif quest.dungeonStepTitle then
        -- Picked up elsewhere, it leads into the dungeon a few quests on
        return ns.L("Leads to %s", quest.dungeonStepTitle) .. DOT .. (quest.starterName or ns.L("unknown giver"))
    elseif quest.isHandedInHere then
        local itemText = quest.isItemInBags and ns.L("Item is in your bags")
            or (quest.sourceZoneName and ns.L("Item drops in %s", quest.sourceZoneName) or ns.L("Item drops in another place"))
        return itemText .. DOT .. (quest.finisherName and ns.L("turn in to %s", quest.finisherName) or ns.L("turn in to the quest giver"))
    elseif quest.startType == "item" then
        return (quest.starterName and ns.L("Drops from %s", quest.starterName) or ns.L("Drops from a creature here")) .. (where and (DOT .. where) or "")
    elseif quest.isFromGame and not quest.starterName then
        -- Not in the quest database: the game's own "!" says where it starts
        return ns.L("Shown by the game") .. (where and (DOT .. where) or "")
    end
    return (quest.starterName or ns.L("Unknown giver")) .. (where and (DOT .. where) or "")
end

local LOCK_ICON = Style.LOCK_ICON

local function getStartIcon(quest)
    if quest.blocker then
        return LOCK_ICON
    end
    if quest.startType == "item" then
        local icon = quest.itemId and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(quest.itemId)
        return icon or ITEM_ICON
    end
    return quest.startType == "object" and OBJECT_ICON or GIVER_ICON
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
        State.list:addText(ns.L("Back to my location: %s", ns.Database.getZoneName(playerZoneId)), 10, y + 5, { font = "GameFontNormal", color = COLORS.gold, width = width - 20, isSingleLine = true })
        State.list:addButton(2, y, width - 4, 24, pickZone, false)
        y = y + 30
    end
    local zones = ns.Availability.getZones({ shouldShowLowLevel = ns.settings.shouldShowLowLevel })
    -- Zones only: the dungeons have a tab of their own
    for _, section in ipairs({ { title = "Zones with quests for you", isDungeon = false } }) do
        local hasHeading = false
        for _, zone in ipairs(zones) do
            if zone.isDungeon == section.isDungeon then
                if not hasHeading then
                    y = addListHeading(y + (section.isDungeon and 10 or 0), ns.L(section.title), "", COLORS.parchment)
                    hasHeading = true
                end
                local isCurrent = zone.zoneId == playerZoneId
                State.list:addText(zone.zoneName .. (isCurrent and (DOT .. ns.L("you are here")) or ""), 10, y + 5, {
                    font = "GameFontNormal", color = isCurrent and COLORS.gold or COLORS.white, width = width - 60, isSingleLine = true,
                })
                State.list:addText(zone.count, width - 40, y + 6, { font = "GameFontHighlightSmall", color = COLORS.tan, width = 30, justify = "RIGHT", isSingleLine = true })
                State.list:addButton(2, y, width - 4, 24, pickZone, zone.zoneId)
                y = y + 24
            end
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
    State.list:addText(ns.L("%d done%s%d in your log%s%d available%s%d not yet", summary.done, DOT, summary.inLog, DOT, summary.available, DOT, summary.notYet), 8, y + 14, {
        font = "GameFontHighlightSmall", color = COLORS.tan, width = State.list.width - 16, isSingleLine = true,
    })
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
                        key = key, name = ns.QuestText.getQuestName(key) or ("Quest " .. key), quests = {},
                        doneCount = doneCount, total = #chainQuestIds,
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
        local note = ns.Lp(#chain.quests, "%d waiting%s%d of %d done", "%d waiting%s%d of %d done", DOT, chain.doneCount, chain.total)
        local _, noteWidth = State.list:addText(note, width - 10 - 140, y + 6, { font = "GameFontHighlightSmall", color = COLORS.tan, width = 140, justify = "RIGHT", isSingleLine = true })
        State.list:addText(chain.name, 40, y + 5, {
            font = "GameFontNormal", color = COLORS.parchment, isSingleLine = true, width = width - 10 - math.min(noteWidth, 140) - 8 - 40,
        })
        State.list:addButton(2, y, width - 4, height, toggleChain, chain.key)
        return y + height + 2
    end

    function ChainList.isFolded(chainKey)
        return foldedChains[chainKey] == true
    end
end

---The fixed line under the Available list: low-level quests are hidden unless ticked, and it says how many.
State.setLowLevelCount = function(hiddenCount)
    if not State.lowLevelCheck then
        return
    end
    State.lowLevelCheck:SetChecked(ns.settings.shouldShowLowLevel == true)
    State.lowLevelLabel:SetText(ns.L("Show low-level quests") .. (hiddenCount > 0 and (" " .. ns.Lp(hiddenCount, "(%d hidden)", "(%d hidden)")) or ""))
end

---@return table? selected, number? availableCount nil while the database is being read
local function drawAvailableTab()
    local player = ns.Model.getPlayer()
    local zoneId = State.pickedZoneId or player.zoneId
    local zoneName = zoneId and ns.Database.getZoneName(zoneId) or player.zoneName or ns.L("Unknown location")
    State.frame.zoneButton.label:SetText(zoneName)
    State.frame.zoneButton.note:SetText(zoneId == player.zoneId and ns.L("you are here") or "")
    State.frame.zoneButton.arrow:SetText(ns.L("change"))
    -- Its text follows the location, also when the map chose it: the menu is built again only when the location
    -- shown changed (building it lists every zone with quests), and anyway as it opens
    local menuKey = tostring(zoneId) .. ":" .. tostring(player.zoneId) .. ":" .. zoneName
    if State.zoneDropdown and State.zoneDropdown.GenerateMenu and State.zoneMenuKey ~= menuKey then
        State.zoneMenuKey = menuKey
        if State.zoneDropdown.SetDefaultText then
            State.zoneDropdown:SetDefaultText(zoneName) -- named even if no line of the menu is the one shown
        end
        State.zoneDropdown:GenerateMenu()
    end

    if not ns.Availability.isReady() then
        State.list:addText(ns.L("Reading the quest database..."), 10, 8, { color = COLORS.tan, width = State.list.width - 20 })
        State.list:finish(40)
        State.detail:finish(1)
        State.frame.status:SetText("")
        ns.Availability.prepare(Log.refresh)
        return nil, nil
    end
    if State.isPickingZone then
        drawZonePicker(player.zoneId)
        State.detail:finish(1)
        State.frame.status:SetText("")
        return nil, nil
    end

    local quests, hiddenCount = ns.Availability.getQuests(zoneId, { shouldShowLowLevel = ns.settings.shouldShowLowLevel })
    local sections = { {}, {}, {}, {} }
    local selectedQuest, firstQuest
    local availableCount = 0
    for _, quest in ipairs(quests) do
        if not quest.availableAtLevel then
            availableCount = availableCount + 1
        end
        -- The search box belongs to My quests and is hidden here, so it does not filter this list
        local section = sections[getSectionIndex(quest)]
        section[#section + 1] = quest
    end
    -- After the quests a few levels away, the ones held back by something else, each saying what
    local isListed = {}
    for _, quest in ipairs(quests) do
        isListed[quest.questId] = true
    end
    local blockedQuests, blockedHiddenCount = ns.Availability.getBlockedQuests(zoneId, { shouldShowLowLevel = ns.settings.shouldShowLowLevel })
    hiddenCount = hiddenCount + blockedHiddenCount
    for _, quest in ipairs(blockedQuests) do
        table.insert(sections[UPCOMING_SECTION], quest)
        isListed[quest.questId] = true
    end
    -- A quest chosen elsewhere (a link to an earlier quest, a mark on the map) is listed even when the low-level
    -- filter hides it, so its page is there to see
    local chosenQuestId = selectedQuestIds[TAB_AVAILABLE]
    if chosenQuestId and not isListed[chosenQuestId] and not ns.settings.shouldShowLowLevel then
        for _, quest in ipairs(ns.Availability.getQuests(zoneId, { shouldShowLowLevel = true })) do
            if quest.questId == chosenQuestId then
                local section = sections[getSectionIndex(quest)]
                section[#section + 1] = quest
            end
        end
    end
    -- A dungeon's list is a plan for one run: every quest done inside, sorted by what to do about it, and the
    -- lead-ins that open the ones behind them, named as lead-ins
    local sectionTitles, foldedSectionIndex = AVAILABLE_SECTIONS, UPCOMING_SECTION
    local isDungeonRun = ns.Database.getDungeon(zoneId) ~= nil
    local isRowListed = #quests > 0
    if isDungeonRun then
        local run = ns.Availability.getDungeonRun(zoneId)
        sections = { run.inLog, run.pickUp, run.foundInside, run.behindLeadIn, run.notYet }
        sectionTitles = { "In your log", "Pick up before you go", "Found inside", "Behind a lead-in", "Not yet" }
        foldedSectionIndex, hiddenCount = nil, 0
        availableCount = #run.pickUp + #run.foundInside
        isRowListed = #run.inLog + #run.pickUp + #run.foundInside + #run.behindLeadIn + #run.notYet > 0
    end
    -- The search beside the location keeps the quests whose title, giver or start item holds what is typed; a
    -- search opens the quests not yet available too, as what is looked for may be among them
    local searchText = State.availableSearchText or ""
    local isSearching = searchText ~= ""
    if isSearching then
        for sectionIndex, section in ipairs(sections) do
            local kept = {}
            for _, quest in ipairs(section) do
                if ns.Availability.isSearchMatch(quest, searchText) then
                    kept[#kept + 1] = quest
                end
            end
            sections[sectionIndex] = kept
        end
        isRowListed = false
        for _, section in ipairs(sections) do
            isRowListed = isRowListed or #section > 0
        end
    end
    local isUpcomingOpen = State.isUpcomingShown or isSearching
    for sectionIndex, section in ipairs(sections) do
        if sectionIndex ~= foldedSectionIndex or isUpcomingOpen then
            for _, quest in ipairs(section) do
                firstQuest = firstQuest or quest
                if quest.questId == selectedQuestIds[TAB_AVAILABLE] and not (isDungeonRun and sectionIndex == 1) then
                    selectedQuest = quest
                end
            end
        end
    end
    -- No quest is selected until the player picks one, here as on My quests
    State.selectedAvailableQuest = selectedQuest

    ---What a row of a dungeon's run says under its title: where it stands and what to do about it.
    local function composeRunText(quest, sectionIndex)
        local text
        if sectionIndex == 1 then
            text = ns.L("In your log")
        elseif quest.isLeadIn then
            text = ns.L("Lead-in for %s", quest.leadsToTitle) .. DOT .. (quest.starterName or ns.L("unknown giver"))
        elseif quest.leadInIds then
            local names = {}
            for _, leadInId in ipairs(quest.leadInIds) do
                names[#names + 1] = ns.QuestText.getQuestName(leadInId) or ("Quest " .. leadInId)
            end
            -- A long chain says how long it is and where it starts, not every step
            text = #names > 2 and ns.L("After %d lead-ins, from %s", #names, names[1]) or ns.L("After %s", table.concat(names, " > "))
            local lastLeadInId = quest.leadInIds[#quest.leadInIds]
            local lastLeadInDungeon = lastLeadInId and ns.Database.getDungeon(ns.Location.getInsideDungeonIds(lastLeadInId)[1] or 0)
            if lastLeadInDungeon and lastLeadInDungeon.areaId ~= zoneId then
                text = text .. " (" .. lastLeadInDungeon.name .. ")" -- a run of another dungeon first
            end
            if lastLeadInId and ns.QuestState.isInLog(lastLeadInId) then
                text = text .. DOT .. ns.L("in your log")
            end
        elseif sectionIndex == 3 then
            text = ns.L(quest.startType == "item" and "Drops inside: %s" or "Given inside: %s", quest.itemName or quest.starterName or ns.L("unknown"))
            text = quest.stepsText and (quest.stepsText .. DOT .. text) or text
        else
            text = composeAvailableSubText(quest)
        end
        if quest.opensTitle then
            text = text .. DOT .. ns.L("opens %s", quest.opensTitle)
        elseif quest.isLeadInOnRun then
            text = text .. DOT .. ns.L("both on one run")
        end
        return quest.isLowLevel and (text .. DOT .. ns.L("low-level")) or text
    end
    local function openInLog(questId)
        Log.showQuestAnywhere(questId)
    end

    local y = addZoneSummary(6, zoneId)
    local runDungeon = isDungeonRun and ns.Database.getDungeon(zoneId)
    if runDungeon and runDungeon.isLearned then
        local noteHeight = State.list:addText(-- a dungeon the database does not know: only the quests seen done inside
            ns.L("Learned from your runs: the quest database does not know this dungeon yet, so only the quests you picked up, worked on or handed in inside are listed. More may be done here. The QuestieTrace addon helps the database learn it."), 10, y + 2, { color = COLORS.tan, width = State.list.width - 20 })
        y = y + 8 + math.max(tonumber(noteHeight) or 0, 28)
    end
    for sectionIndex, section in ipairs(sections) do
        if #section > 0 then
            local isUpcoming = sectionIndex == foldedSectionIndex
            local label = (isUpcoming and not isUpcomingOpen and "+ " or "") .. ns.L(sectionTitles[sectionIndex])
            y = addListHeading(y, label, #section, COLORS.parchment, isUpcoming and not isSearching and toggleUpcoming or nil)
            if not isUpcoming or isUpcomingOpen then
                local function addQuestRow(quest, indent)
                    local isInLog = isDungeonRun and sectionIndex == 1
                    local icon = not isInLog and getStartIcon(quest) or nil
                    y = addListQuest(y, quest.questId, {
                        indent = indent, title = quest.title, level = quest.level,
                        -- A quest for a dungeon (or the start of its chain) says where it leads
                        subText = isDungeonRun and composeRunText(quest, sectionIndex)
                            or (quest.leadsToDungeonName and not quest.availableAtLevel and not quest.blocker
                                and (ns.L("Leads to %s", quest.leadsToDungeonName) .. DOT .. (quest.starterName or ns.L("unknown giver"))))
                            or composeAvailableSubText(quest),
                        color = (quest.availableAtLevel or quest.blocker or quest.isLowLevel) and COLORS.grey or nil,
                        icon = icon,
                        -- (a giver's "!" in the colour of the quest's kind: repeatable blue, an event's green...)
                        iconColour = icon == GIVER_ICON and ns.MapMarks.getQuestIconColour(quest.questId, quest.isLowLevel) or nil,
                        chainText = quest.chainIndex and string.format("%d/%d", quest.chainIndex, quest.chainTotal) or nil,
                        warnings = not isInLog and ns.Warnings.getQuestWarnings(quest.questId, true) or nil,
                        handleClick = isInLog and openInLog or nil, -- a quest in the log opens there
                    })
                end
                -- Quests not yet available: the steps of one chain under a heading of its own
                for _, entry in ipairs(isUpcoming and ChainList.composeEntries(section) or {}) do
                    if entry.chain then
                        y = ChainList.addHeading(y, entry.chain)
                        -- A folded chain still shows its selected step, so a quest opened by a link is in view
                        local isFolded = ChainList.isFolded(entry.chain.key)
                        for _, quest in ipairs(entry.chain.quests) do
                            if not isFolded or quest.questId == selectedQuestIds[TAB_AVAILABLE] then
                                addQuestRow(quest, 14)
                            end
                        end
                    else
                        addQuestRow(entry.quest, 0)
                    end
                end
                for _, quest in ipairs(isUpcoming and {} or section) do
                    addQuestRow(quest, 0)
                end
            end
            y = y + 8
        end
    end
    -- A search names the other zones with quests that match, each a click away (the search stays)
    if isSearching then
        local others = ns.Availability.findInOtherZones(searchText, zoneId, { shouldShowLowLevel = ns.settings.shouldShowLowLevel })
        if #others > 0 then
            y = addListHeading(y, ns.L("In other zones"), #others, COLORS.parchment)
            local function pickOtherZone(otherZoneId)
                pickZone(otherZoneId)
            end
            for index = 1, math.min(#others, 6) do
                local other = others[index]
                local text = "|cffffd100" .. other.zoneName .. "|r" .. DOT .. table.concat(other.titles, ", ")
                local textHeight = State.list:addText(text, 10, y + 3, { font = "GameFontHighlightSmall", color = COLORS.tan, width = State.list.width - 20 })
                local height = math.max(tonumber(textHeight) or 12, 12) + 6
                State.list:addButton(2, y, State.list.width - 4, height, pickOtherZone, other.zoneId)
                y = y + height
            end
            y = y + 8
            isRowListed = true
        end
    end
    -- Dungeons whose way in is here: their quests are the dungeon's, on the Dungeons tab; this points the way
    if not isDungeonRun and not isSearching then
        local entranceDungeons = ns.Availability.getEntranceDungeons(zoneId)
        local function showEntranceDungeon(rowId)
            Log.showDungeon(-rowId)
        end
        if #entranceDungeons > 0 then
            y = addListHeading(y, ns.L("Dungeons with their way in here"), #entranceDungeons, COLORS.parchment)
            for _, entrance in ipairs(entranceDungeons) do
                local minLevel, maxLevel = ns.Availability.getZoneLevels(entrance.dungeonId)
                local countText = ns.Lp(entrance.count, "%d quest to pick up inside", "%d quests to pick up inside")
                y = addListQuest(y, -entrance.dungeonId, {
                    title = entrance.name, level = minLevel or ns.Model.getPlayer().level or 1, color = COLORS.parchment,
                    subText = countText .. (minLevel and maxLevel and minLevel ~= maxLevel and (DOT .. ns.L("levels %d-%d", minLevel, maxLevel)) or ""),
                    icon = "Interface\\Icons\\INV_Misc_Key_03", handleClick = showEntranceDungeon,
                })
            end
            y = y + 8
            isRowListed = true
        end
    end
    if not isRowListed then
        local emptyText = isSearching and ns.L("No quest to pick up matches \"%s\".", State.availableSearchText)
            or ns.L(isDungeonRun and "No quests for you are done in here, or all of them are done." or "Nothing to pick up here right now.")
        State.list:addText(emptyText, 10, y + 4, { color = COLORS.tan, width = State.list.width - 20 })
        y = y + 24
    end
    State.setLowLevelCount(hiddenCount)
    State.list:finish(y + 8)

    -- The tab counts what is available, and the low-level switch under the list how many it hides: nothing
    -- more to say beside the tabs
    State.frame.status:SetText("")

    if selectedQuest and State.mapQuestId == selectedQuest.questId then
        -- Chosen by hand: the map turns to where the quest starts and slides to it, as for a quest in the log.
        -- The list stays on its location meanwhile, though the map now shows another zone.
        local place = selectedQuest.nearestPlace or selectedQuest.places[1]
        if place and place.x >= 0 then
            State.isMapFollowPaused = true
            ns.MapDock.showQuestPlace(place.mapZoneId or place.groupZoneId, place)
            State.isMapFollowPaused = false
        end
    end
    State.mapQuestId = nil
    if selectedQuest then
        State.detail:finish(drawAvailableQuest(selectedQuest, zoneId))
    else
        local hint = #quests > 0 and ns.L("Select a quest to see how to start it and to mark its giver and turn-in on the map. Click it again to let go of it.") or ""
        State.detail:addText(hint, PADDING, PADDING, { font = "QuestFont", color = COLORS.softInk, width = State.detail.width - 2 * PADDING })
        State.detail:finish(80)
    end
    return selectedQuest, availableCount
end

-- Shared with the other parts of the window
AvailableTab.drawAvailableTab = drawAvailableTab
AvailableTab.pickZone = pickZone
AvailableTab.toggleLowLevel = toggleLowLevel
