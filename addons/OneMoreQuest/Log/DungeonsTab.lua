local _, ns = ...

-- The quest log window: the Dungeons tab. Every dungeon (and raid) with quests for the player, by level, from every
-- quest provider (QuestieDB, the DungeonJournal addon, what was learned by playing). Selecting one opens its page:
-- its levels and way in, its quests by what to do about them, and its quests unfold under its row in the list. A
-- quest of it opens its page to pick it up; one already in the log opens on My quests.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, DungeonsTab = ns.LogList, ns.LogQuestPage, ns.LogDungeonsTab
local addListQuest = List.addListQuest
local drawAvailableQuest = QuestPage.drawAvailableQuest
local selectQuest = Actions.selectQuest
local selectedQuestIds = State.selectedQuestIds
local COLORS, DOT, GIVER_ICON, PADDING = Style.COLORS, Style.DOT, Style.GIVER_ICON, Style.PADDING
local TAB_DUNGEONS, MEDIA = Style.TAB_DUNGEONS, Style.MEDIA
-- Up, for a lead-in's arrow to the quest it opens: the chevron that points down, turned over
local UP_CHEVRON, UP_COORDS = MEDIA .. "ChevronDown", { 0, 1, 1, 0 }

local ROWS_SECONDS = 2 -- the list of dungeons is worked out again at most this often
local SECTIONS = {
    { key = "inLog", title = "In your log" },
    { key = "pickUp", title = "Pick up before you go" },
    { key = "foundInside", title = "Found inside" },
    { key = "behindLeadIn", title = "Behind a lead-in" },
    { key = "notYet", title = "Not yet" },
}

-- Listed after the rest, but not counted among the quests left: a dungeon with only these is all done
local DONE_SECTION = { key = "done", title = "Done" }
local LISTED_SECTIONS = {}
for _, section in ipairs(SECTIONS) do
    LISTED_SECTIONS[#LISTED_SECTIONS + 1] = section
end
LISTED_SECTIONS[#LISTED_SECTIONS + 1] = DONE_SECTION
local DONE_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready" -- the game's green check

local cachedRows, cachedAt, cachedFor -- (cachedFor: Availability's change key they were worked out at)
-- What the Spoilers choice lets the tab name, asked once a drawing: which quests to pick up (List.getPickupChoice), and
-- whether quests still to come in a story are kept back (Availability.isLaterHidden)
local Told = { pickup = "all", isStoryHidden = false }

---@return table[] rows Each dungeon with quests for the player: { dungeon, run, minLevel, maxLevel, inLog, toPickUp, total }
local function getRows()
    local now = GetTime and GetTime() or 0
    -- (a few seconds, and only while who can pick up what stands: a quest taken or handed in redraws it at once)
    local changeKey = ns.Availability.getChangeKey and ns.Availability.getChangeKey()
    if cachedRows and cachedAt and now - cachedAt < ROWS_SECONDS and cachedFor == changeKey then
        return cachedRows
    end
    cachedFor = changeKey
    local rows = {}
    for _, dungeonId in ipairs(ns.Availability.getDungeonIds()) do
        local dungeon = ns.Database.getDungeon(dungeonId)
        if dungeon and dungeon.areaId == dungeonId then
            local run = ns.Availability.getDungeonRun(dungeonId)
            local total = 0
            for _, section in ipairs(SECTIONS) do
                total = total + #run[section.key]
            end
            -- Done ones too: a dungeon with nothing left for the player is listed as done
            local doneCount = ns.Availability.getZoneSummary(dungeonId).done
            if total > 0 or doneCount > 0 then
                local minLevel, maxLevel = ns.Availability.getZoneLevels(dungeonId)
                rows[#rows + 1] = {
                    dungeon = dungeon,
                    run = run,
                    minLevel = minLevel,
                    maxLevel = maxLevel,
                    total = total,
                    inLog = #run.inLog,
                    toPickUp = #run.pickUp + #run.foundInside,
                    doneCount = doneCount,
                    isDone = total == 0,
                }
            end
        end
    end
    -- By level, the lowest first; a dungeon with no level known at the end
    table.sort(rows, function(first, second)
        local firstLevel, secondLevel = first.minLevel or 999, second.minLevel or 999
        if firstLevel ~= secondLevel then
            return firstLevel < secondLevel
        end
        return first.dungeon.name < second.dungeon.name
    end)
    cachedRows, cachedAt = rows, now
    return rows
end

---Forgets the worked-out list (the quests changed).
function DungeonsTab.invalidate()
    cachedRows = nil
end

---@return table? place The dungeon's way in, as the map and the Show entrance button take a place
local function getEntrancePlace(dungeon)
    local entrance = dungeon.entrances and dungeon.entrances[1]
    if not entrance then
        return nil
    end
    return {
        zoneId = entrance.zoneId,
        x = entrance.x,
        y = entrance.y,
        groupZoneId = dungeon.areaId,
        mapZoneId = ns.Database.getParentZoneId(entrance.zoneId) or entrance.zoneId,
        dungeonName = dungeon.name,
        dungeonZoneId = dungeon.areaId,
    }
end

---A level in the game's difficulty colour for the player, as quest titles are coloured.
---@param shade number? How light the colour stays: 1 on the dark list, less on parchment
local function colorLevel(level, shade)
    local color, factor = ns.Widgets.getDifficultyColor(level), shade or 1
    return string.format(
        "|cff%02x%02x%02x%d|r",
        color[1] * 255 * factor,
        color[2] * 255 * factor,
        color[3] * 255 * factor,
        level
    )
end

---The dungeon's levels, each number in its own difficulty colour: "levels 30-34" can be grey at one end and yellow
---at the other. A dungeon that is all done says it plainly, in the row's muted colour.
---@param shade number? The colours darkened by this much, for the parchment page
local function composeLevels(row, shade)
    if not row.minLevel then
        return nil
    end
    local hasRange = row.maxLevel and row.maxLevel ~= row.minLevel
    if row.isDone then
        return hasRange and ns.L("levels %d-%d", row.minLevel, row.maxLevel) or ns.L("level %d", row.minLevel)
    end
    -- The translation's numbers swapped for the coloured ones, so the words stay where the language puts them
    if hasRange then
        return (ns.L("levels %d-%d"):gsub("%%d", "%%s")):format(
            colorLevel(row.minLevel, shade),
            colorLevel(row.maxLevel, shade)
        )
    end
    return (ns.L("level %d"):gsub("%%d", "%%s")):format(colorLevel(row.minLevel, shade))
end

---What a dungeon's row says under its band: where its way in is, and its quests for the player.
local function composeRowText(row)
    local parts = {}
    local place = getEntrancePlace(row.dungeon)
    parts[#parts + 1] = place and ns.Database.getZoneName(place.mapZoneId) or nil
    if row.inLog > 0 then
        parts[#parts + 1] = ns.Lp(row.inLog, "%d in your log", "%d in your log")
    end
    if row.toPickUp > 0 and Told.pickup == "all" then -- (a count of quests the choice does not all name would tell)
        parts[#parts + 1] = ns.Lp(row.toPickUp, "%d to pick up", "%d to pick up")
    end
    if row.doneCount > 0 and not row.isDone then
        parts[#parts + 1] = ns.Lp(row.doneCount, "%d done", "%d done")
    end
    return table.concat(parts, DOT)
end

---What a quest of a dungeon says: where it stands and what to do about it.
local function composeQuestText(quest, sectionKey, isNested)
    if sectionKey == "inLog" then
        return ns.L("In your log")
    elseif sectionKey == "done" then
        return "|cff7ce07c" .. ns.L("Done") .. "|r"
    elseif quest.isLeadIn and (isNested or Told.isStoryHidden) then
        -- Under the quest it leads to: that one is plain to see
        return ns.L("Lead-in") .. DOT .. (quest.starterName or ns.L("unknown giver"))
    elseif quest.isLeadIn then
        return ns.L("Lead-in for %s", quest.leadsToTitle) .. DOT .. (quest.starterName or ns.L("unknown giver"))
    elseif quest.leadInIds and Told.isStoryHidden then
        return ns.L("Later in the story")
    elseif quest.leadInIds then
        local names = {}
        for _, leadInId in ipairs(quest.leadInIds) do
            names[#names + 1] = ns.QuestText.getQuestName(leadInId) or ("Quest " .. leadInId)
        end
        return #names > 2 and ns.L("After %d lead-ins, from %s", #names, names[1])
            or ns.L("After %s", table.concat(names, " > "))
    elseif sectionKey == "foundInside" then
        return ns.L(
            quest.startType == "item" and "Drops inside: %s" or "Given inside: %s",
            quest.itemName or quest.starterName or ns.L("unknown")
        )
    elseif quest.availableAtLevel then
        return ns.L("At level %d", quest.availableAtLevel) .. DOT .. (quest.starterName or ns.L("unknown giver"))
    elseif quest.blocker then
        return ns.Availability.getShownReason(quest.blocker)
    end
    return quest.starterName or ns.L("Unknown giver")
end

-- The game's own quest marks for a quest in the log: a grey ? while it is worked on, a yellow one when it is done
local IN_LOG_ICON, READY_ICON = "Interface\\GossipFrame\\IncompleteQuestIcon", "Interface\\GossipFrame\\ActiveQuestIcon"

---A dungeon's quests in the order they are listed, each with how far it is nested: a lead-in under the quest it leads
---to, not on its own further up (when that quest is listed at all)
---@return { quest: table, sectionKey: string, depth: number }[] entries
local function composeEntries(run)
    local listedIds = {}
    for _, section in ipairs(SECTIONS) do
        for _, quest in ipairs(run[section.key]) do
            listedIds[quest.questId] = true
        end
    end
    local leadInsByTarget, sectionOf = {}, {}
    for _, sectionKey in ipairs({ "pickUp", "inLog" }) do
        for _, quest in ipairs(run[sectionKey]) do
            if
                quest.isLeadIn
                and quest.leadsToQuestId
                and listedIds[quest.leadsToQuestId]
                and quest.leadsToQuestId ~= quest.questId
            then
                leadInsByTarget[quest.leadsToQuestId] = leadInsByTarget[quest.leadsToQuestId] or {}
                table.insert(leadInsByTarget[quest.leadsToQuestId], quest)
                sectionOf[quest] = sectionKey
            end
        end
    end
    local entries, isNested = {}, {}
    for _, leadIns in pairs(leadInsByTarget) do
        for _, leadIn in ipairs(leadIns) do
            isNested[leadIn] = true
        end
    end
    for _, section in ipairs(LISTED_SECTIONS) do
        for _, quest in ipairs(run[section.key] or {}) do
            if not isNested[quest] then
                entries[#entries + 1] = { quest = quest, sectionKey = section.key, depth = 0 }
                for _, leadIn in ipairs(leadInsByTarget[quest.questId] or {}) do
                    entries[#entries + 1] = { quest = leadIn, sectionKey = sectionOf[leadIn], depth = 1 }
                end
            end
        end
    end
    return entries
end

---A quest's mark in the list: the game's padlock for one that cannot be taken yet (behind a lead-in, or above the
---player's level; the line under it says why), else what starts it. The title keeps its difficulty colour either way.
local function getStartIcon(quest)
    if quest.blocker or quest.availableAtLevel then
        return Style.LOCK_ICON
    end
    return List.getStartTypeIcon(quest)
end

---Opens a dungeon (its page, its quests under its row), or folds it again when it was open.
local function selectDungeon(rowId)
    local dungeonId = -rowId
    if State.selectedDungeonId == dungeonId and selectedQuestIds[TAB_DUNGEONS] == rowId then
        State.selectedDungeonId, selectedQuestIds[TAB_DUNGEONS] = nil, nil
    else
        State.selectedDungeonId, selectedQuestIds[TAB_DUNGEONS] = dungeonId, rowId
        local dungeon = ns.Database.getDungeon(dungeonId)
        local place = dungeon and getEntrancePlace(dungeon)
        if place then
            -- The map turns to the zone of its way in, where its gate is marked
            State.isMapFollowPaused = true
            ns.MapDock.showZoneMap(place.mapZoneId)
            State.isMapFollowPaused = false
        end
    end
    State.view = "quests"
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---A done quest's row: nothing is left to do about it, so a click does nothing
local function ignoreClick() end

---A quest of the dungeon: one in the log opens there; the others open their page here.
local function openQuest(questId)
    if ns.QuestState.isInLog(questId) then
        Log.showQuestAnywhere(questId)
        return
    end
    selectQuest(questId)
end

-- The page's progress bar, in the zone page's colours: done, in the log, to pick up, for later
local PROGRESS_COLORS = {
    done = COLORS.darkGreen,
    inLog = Style.SELECTED_EDGE,
    pickUp = { 0.96, 0.93, 0.82 },
    later = { 0.54, 0.52, 0.47 },
}

---The quests one run is about: those in the log, to pick up (their lead-ins too: they are done on the way) and
---found inside.
local function getRunQuests(run)
    local quests = {}
    for _, key in ipairs({ "inLog", "pickUp", "foundInside" }) do
        for _, quest in ipairs(run[key]) do
            quests[#quests + 1] = quest
        end
    end
    return quests
end

---How far the character is through the dungeon: its quests done, in the log, to pick up and for later.
---@return { key: string, count: number, label: string }[] parts
local function composeProgress(run)
    local inLog, pickUp = 0, 0
    for _, quest in ipairs(run.inLog) do
        inLog = inLog + (quest.isLeadIn and 0 or 1)
    end
    for _, quest in ipairs(run.pickUp) do
        pickUp = pickUp + (quest.isLeadIn and 0 or 1)
    end
    pickUp = pickUp + #run.foundInside
    local later = #run.behindLeadIn + #run.notYet
    return {
        { key = "done", count = run.doneCount, label = ns.Lp(run.doneCount, "%d done", "%d done") },
        { key = "inLog", count = inLog, label = ns.Lp(inLog, "%d in your log", "%d in your log") },
        { key = "pickUp", count = pickUp, label = ns.Lp(pickUp, "%d to pick up", "%d to pick up") },
        { key = "later", count = later, label = ns.Lp(later, "%d for later", "%d for later") },
    }
end

---The run's progress as the zone page shows a zone's: one bar in parts, and what it counts under it.
---@return number y Below it
local function addProgress(y, run, width)
    local parts, total, labels = composeProgress(run), 0, {}
    for _, part in ipairs(parts) do
        total = total + part.count
        if part.count > 0 then
            labels[#labels + 1] = part.label
        end
    end
    if total == 0 then
        return y
    end
    State.detail:addRect(PADDING, y, width, 10, COLORS.ink)
    local x = PADDING + 1
    for _, part in ipairs(parts) do
        local partWidth = (width - 2) * part.count / total
        if partWidth > 0 then
            State.detail:addRect(x, y + 1, partWidth, 8, PROGRESS_COLORS[part.key], 1)
            x = x + partWidth
        end
    end
    y = y + 15
    return QuestPage.addBody(y, table.concat(labels, DOT), COLORS.softInk) + 12
end

---What the quests left here give together: experience at the character's level, money and reward items (a choice
---counts as one), and their names for the tile's note.
local function composeRunRewards(run)
    local total = { experience = 0, money = 0, itemCount = 0, itemNames = {} }
    for _, quest in ipairs(getRunQuests(run)) do
        local rewards = ns.QuestState.getRewards(quest.questId)
        total.experience = total.experience + (rewards.experience or 0)
        total.money = total.money + (rewards.money or 0)
        for _, item in ipairs(rewards.items or {}) do
            total.itemCount = total.itemCount + 1
            total.itemNames[#total.itemNames + 1] = item.name
        end
        if #(rewards.choices or {}) > 0 then
            total.itemCount = total.itemCount + 1
            total.itemNames[#total.itemNames + 1] = ns.L("a choice from %s", quest.title)
        end
    end
    return total
end

local ICONS = "Interface\\Icons\\"

---The run at a glance, on the dark wood the chronicle's At a glance uses: what the quests left are worth, and how
---far through the dungeon's quests the character is.
---@return number y Below the strip
---The experience of all the dungeon's quests: the experience left (as the game gives it), what the quests for
---later would give, reckoned the same way, and what the done ones gave, as the chronicle kept it (the database's
---amount for one done before it began).
---@param leftExperience number What the quests left give
local function composeAllExperience(run, leftExperience)
    local allExperience = leftExperience
    for _, key in ipairs({ "behindLeadIn", "notYet" }) do
        for _, quest in ipairs(run[key]) do
            allExperience = allExperience + (ns.QuestState.getRewards(quest.questId).experience or 0)
        end
    end
    local keptExperience = {}
    for _, entry in ipairs(ns.Chronicle.getEntries() or {}) do
        if entry.questId then
            keptExperience[entry.questId] = entry.experience
        end
    end
    for _, quest in ipairs(run.done) do
        allExperience = allExperience
            + (keptExperience[quest.questId] or ns.Database.getQuestExperience(quest.questId) or 0)
    end
    return allExperience
end

---@return number? percent How much of the character's current level the experience would fill
local function getLevelShare(experience)
    local levelMax = UnitXPMax and UnitXPMax("player") or 0
    if levelMax > 0 and experience > 0 then
        return math.floor(experience / levelMax * 100 + 0.5)
    end
    return nil
end

local function addGlance(y, run)
    local rewards = composeRunRewards(run)
    local leftCount = #getRunQuests(run)
    local allExperience = composeAllExperience(run, rewards.experience)
    local levelShare = getLevelShare(rewards.experience)
    local totalCount = run.doneCount + leftCount + #run.behindLeadIn + #run.notYet
    local formatNumber = ns.ChroniclePage.formatNumber
    return ns.ChroniclePage.addRewardStrip(State.detail, y, {
        {
            label = ns.L("Experience left"),
            value = rewards.experience > 0 and formatNumber(rewards.experience) or "-",
            icon = ICONS .. "XP_Icon",
            note = ns.Lp(
                leftCount,
                "From the %d quest still to do here, at your level",
                "From the %d quests still to do here, at your level"
            ),
        },
        {
            label = ns.L("Money"),
            value = rewards.money > 0 and ns.ChroniclePage.formatTileMoney(rewards.money) or "-",
            icon = ICONS .. "INV_Misc_Coin_01",
            note = ns.L("The quests still to do here, handed in"),
        },
        {
            label = ns.L("Reward items"),
            value = rewards.itemCount > 0 and tostring(rewards.itemCount) or "-",
            icon = ICONS .. "INV_Box_01",
            note = #rewards.itemNames > 0 and table.concat(rewards.itemNames, ", ")
                or ns.L("No items among the rewards"),
        },
        {
            label = ns.L("Quests done"),
            value = ns.L("%d of %d", run.doneCount, totalCount),
            icon = ICONS .. "INV_Scroll_03",
            note = ns.L("The dungeon's quests you can have, lead-ins left out"),
        },
        {
            label = ns.L("Experience in all"),
            value = allExperience > 0 and formatNumber(allExperience) or "-",
            icon = ICONS .. "INV_Misc_Book_09",
            note = ns.L("What is left here, what the quests for later would give, and what the done ones gave"),
        },
        {
            label = ns.L("Of your level"),
            value = levelShare and (levelShare .. "%") or "-",
            icon = ICONS .. "Spell_Holy_SealOfWisdom",
            note = ns.L("How much of your current level the experience left would fill"),
        },
    }, 2) -- two to a row: the page is narrower than the chronicle's
end

---Turns the map to the dungeon's way in, as the page's Show entrance button does.
local function showEntrance(place)
    Actions.showPlaceOnMap(place.mapZoneId or place.groupZoneId, place)
end

---@return string text Text in a colour, for a line that mixes colours
local function colorText(text, color)
    return string.format("|cff%02x%02x%02x%s|r", color[1] * 255, color[2] * 255, color[3] * 255, text)
end

---A quest's line on the route: its name with its level, then who gives or takes it, quieter.
local function composeQuestLine(quest, note)
    local name = string.format(
        "[%d] %s",
        quest.level or 0,
        quest.title or ns.QuestText.getQuestName(quest.questId) or ("Quest " .. quest.questId)
    )
    return { text = name .. (note and ("  " .. colorText(note, COLORS.softInk)) or ""), questId = quest.questId }
end

---Places grouped into stops by their zone, the nearest to the player first.
---@param items { place: table?, distance: number?, line: table }[]
---@return { title: string, lines: table[] }[] stops
local function groupIntoStops(items)
    local stopsByName, stops = {}, {}
    for _, item in ipairs(items) do
        local name = item.place
                and ns.Database.getZoneName(item.place.mapZoneId or item.place.groupZoneId or item.place.zoneId)
            or ns.L("Unknown location")
        local stop = stopsByName[name]
        if not stop then
            stop = { title = name, lines = {}, distance = math.huge }
            stopsByName[name] = stop
            stops[#stops + 1] = stop
        end
        stop.distance = math.min(stop.distance, item.distance or math.huge)
        stop.lines[#stop.lines + 1] = item.line
    end
    table.sort(stops, function(first, second)
        if first.distance ~= second.distance then
            return first.distance < second.distance
        end
        return first.title < second.title
    end)
    return stops
end

---Before going in: the quests to pick up on the way (lead-ins too), by the place they are given.
local function composePickUpStops(run)
    local items = {}
    for _, quest in ipairs(run.pickUp) do
        local note = (quest.starterName or ns.L("unknown giver"))
            .. (quest.isLeadIn and not Told.isStoryHidden and (DOT .. ns.L("Lead-in for %s", quest.leadsToTitle)) or "")
        items[#items + 1] = {
            place = quest.nearestPlace or (quest.places or {})[1],
            distance = quest.distance,
            line = composeQuestLine(quest, note),
        }
    end
    return groupIntoStops(items)
end

---Inside: what the quests in the log still need, then the quests picked up in there; one stop, the dungeon.
local function composeInsideStops(run)
    local lines = {}
    for _, quest in ipairs(run.inLog) do
        local logQuest = not quest.isLeadIn and ns.QuestState.getQuest(quest.questId)
        for _, objective in ipairs(logQuest and logQuest.objectives or {}) do
            if not objective.isFinished then
                lines[#lines + 1] = {
                    text = (objective.shownLabel or objective.label or "")
                        .. "  "
                        .. colorText(quest.title, COLORS.softInk),
                    rightText = (objective.required or 0) > 1
                            and ns.L("%d of %d", objective.fulfilled or 0, objective.required)
                        or nil,
                    questId = quest.questId,
                }
            end
        end
    end
    for _, quest in ipairs(run.foundInside) do
        local source = ns.L(
            quest.startType == "item" and "Drops inside: %s" or "Given inside: %s",
            quest.itemName or quest.starterName or ns.L("unknown")
        )
        lines[#lines + 1] = { text = source, rightText = ns.L("starts %s", quest.title), questId = quest.questId }
    end
    return #lines > 0 and { { isInside = true, lines = lines } } or {}
end

---After the run: where each quest is handed in, by place.
local function composeHandInStops(run)
    local position = ns.Geometry.getPlayerPosition()
    local items = {}
    local isSpoiling = ns.Spoilers.isActive()
    for _, quest in ipairs(getRunQuests(run)) do
        -- (where the Spoilers choice keeps the turn-in back, the quest is not put at a place)
        if not isSpoiling or ns.Model.isTurnInShown(quest.questId) then
            local places, finisherName = ns.Location.getFinisherPlaces(quest.questId)
            local distance, _, place = ns.Geometry.getNearest(places, position, ns.Database.getUiMapId)
            items[#items + 1] =
                { place = place or places[1], distance = distance, line = composeQuestLine(quest, finisherName) }
        end
    end
    return groupIntoStops(items)
end

local STOP_DOT, STOP_TEXT_LEFT, RIGHT_TEXT_WIDTH = 20, 32, 110

---The route's stops, as the quest page draws its steps: a ring for a place on the way, a filled one for inside the
---dungeon, joined by a line; the place in ink, then a line for each thing to do there, clicked to open its quest.
---@param stops { title: string?, isInside: boolean?, lines: { text: string, rightText: string?, questId: number? }[] }[]
---@return number y Below them
local function addStops(y, stops)
    local textLeft = PADDING + STOP_TEXT_LEFT
    local textWidth = State.detail.width - PADDING - textLeft
    for stopIndex, stop in ipairs(stops) do
        local top = y
        if stop.title then
            y = y
                + State.detail:addText(
                    stop.title,
                    textLeft,
                    y + 2,
                    { font = "QuestFont", color = COLORS.ink, width = textWidth, isSingleLine = true }
                )
                + 5
        else
            y = y + 2
        end
        for _, line in ipairs(stop.lines) do
            local lineTop, rightWidth = y, 0
            if line.rightText then
                local _, measured =
                    State.detail:addText(line.rightText, textLeft + textWidth - RIGHT_TEXT_WIDTH, y + 2, {
                        font = "GameFontHighlightSmall",
                        color = COLORS.softInk,
                        width = RIGHT_TEXT_WIDTH,
                        justify = "RIGHT",
                        isSingleLine = true,
                    })
                rightWidth = math.min(type(measured) == "number" and measured or RIGHT_TEXT_WIDTH, RIGHT_TEXT_WIDTH) + 8
            end
            y = y
                + State.detail:addText(
                    line.text,
                    textLeft,
                    y,
                    { font = "QuestFont", color = COLORS.brown, width = textWidth - rightWidth }
                )
                + 4
            if line.questId then
                State.detail:addButton(textLeft - 4, lineTop - 1, textWidth + 4, y - lineTop, openQuest, line.questId)
            end
        end
        y = y + 10
        if stopIndex < #stops then
            State.detail:addRect(PADDING + 8.5, top + 10, 3, y - top, COLORS.sand)
        end
        State.detail:addDot(PADDING, top, STOP_DOT, COLORS.brown, 0)
        if stop.isInside then
            State.detail:addDot(PADDING + 4, top + 4, STOP_DOT - 8, Style.SELECTED_EDGE, 1)
        else
            State.detail:addDot(PADDING + 3, top + 3, STOP_DOT - 6, COLORS.parchment, 1)
        end
    end
    return y
end

---A line as the zone page lists its quests: a title, a note under it, and what to click.
---@return number y Below it
local function addLine(y, title, note, questId)
    local width = State.detail.width - 2 * PADDING
    State.detail:addText(
        title,
        PADDING,
        y + 2,
        { font = "QuestFont", color = COLORS.ink, width = width, isSingleLine = true }
    )
    State.detail:addText(
        note,
        PADDING,
        y + 18,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width, isSingleLine = true }
    )
    if questId then
        State.detail:addButton(PADDING - 4, y, width + 8, 34, openQuest, questId)
    end
    return y + 38
end

---The dungeon's page, a plan for a run: the game's title bar with its levels and way in, how far through it the
---character is, the run at a glance on dark wood, then the route: what to pick up on the way, what to do inside,
---where to hand in afterwards; then what has to wait, and what is done.
---@return number height
---@param run table The row's run with only what the Spoilers choice lets be named (List.keepRunToPickUp)
local function drawDungeonPage(row, run)
    local dungeon = row.dungeon
    local width = State.detail.width - 2 * PADDING
    local place = getEntrancePlace(dungeon)
    -- (a dungeon with no level known leaves its levels out rather than leaving a hole in the list)
    local facts = {}
    facts[#facts + 1] = composeLevels(row)
    facts[#facts + 1] = dungeon.isRaid and ns.L("Raid") or ns.L("Dungeon")
    local before = table.concat(facts, DOT) .. DOT
    local zoneLink, factsText
    if place then
        local wayText = string.format("%s %d, %d", ns.Database.getZoneName(place.mapZoneId), place.x, place.y)
        factsText = before .. wayText
        zoneLink = { before = before, text = wayText, handleClick = showEntrance, data = place }
    else
        factsText = before .. ns.L("Way in not known yet")
    end
    QuestPage.setPageHeader(dungeon.name, factsText, nil, nil, zoneLink)
    QuestPage.setPageRewards(nil)
    local y = 12
    if dungeon.isLearned then
        y = QuestPage.addBody(
            y,
            ns.L(
                "Not in the quest database: known from another addon or your own runs, so more quests may be done here."
            ),
            COLORS.softInk
        ) + 8
    end
    y = addProgress(y, run, width)
    -- (the run's worth: not where the Spoilers choice keeps rewards back)
    if not row.isDone and (not ns.Spoilers.isActive() or ns.Spoilers.getChoice("rewards") == "shown") then
        y = addGlance(y, run) + 4
    end

    local pickUpStops = composePickUpStops(run)
    if #pickUpStops > 0 then
        y = addStops(QuestPage.addHeading(y, ns.L("Before you go")), pickUpStops) + 4
    end
    local insideStops = composeInsideStops(run)
    if #insideStops > 0 then
        y = addStops(QuestPage.addHeading(y, ns.L("Inside")), insideStops) + 4
    end
    local handInStops = composeHandInStops(run)
    if #handInStops > 0 then
        y = addStops(QuestPage.addHeading(y, ns.L("Hand in")), handInStops) + 4
    end
    -- What has to wait: behind a lead-in, or a level, a reputation or a profession away; each says why
    local later = {}
    for _, key in ipairs({ "behindLeadIn", "notYet" }) do
        for _, quest in ipairs(run[key]) do
            later[#later + 1] = { quest = quest, key = key }
        end
    end
    if #later > 0 then
        y = QuestPage.addHeading(y, ns.L("Later"))
        for _, item in ipairs(later) do
            y = addLine(
                y,
                string.format("[%d] %s", item.quest.level or 0, item.quest.title),
                composeQuestText(item.quest, item.key, false),
                item.quest.questId
            )
        end
        y = y + 12
    end
    if #run.done > 0 then
        y = QuestPage.addHeading(y, ns.L("Done here"))
        for _, quest in ipairs(run.done) do
            State.detail:addIcon(PADDING, y + 1, 14, DONE_ICON, nil, 3)
            y = y
                + State.detail:addText(string.format("[%d] %s", quest.level or 0, quest.title), PADDING + 20, y, {
                    font = "QuestFont",
                    color = COLORS.softInk,
                    width = width - 20,
                    isSingleLine = true,
                })
                + 6
        end
        y = y + 6
    end
    if row.isDone then
        y = QuestPage.addBody(y + 4, ns.L("You have done every quest of this dungeon you can.")) + 8
    end
    State.shownDungeon = { name = dungeon.name, entrance = place }
    return y + PADDING
end

---@return table[] rows The dungeons the tab lists: with the Spoilers choice, only those it lets be named (entered, or
---with quests of the player's own, or all)
local function getShownRows(rows)
    if not ns.Spoilers.isActive() then
        return rows
    end
    local shownRows = {}
    for _, row in ipairs(rows) do
        if List.isDungeonShown(row.dungeon.areaId, row.inLog > 0 or row.doneCount > 0) then
            shownRows[#shownRows + 1] = row
        end
    end
    return shownRows
end

---The flow from a lead-in's icon along the icon column up into the quest it opens, the arrow head just under that
---quest's icon.
local function addLeadInArrow(parentTop, rowTop)
    local lineTop, lineBottom = parentTop + 30, rowTop + 12
    State.list:addRect(17, lineTop, 2, lineBottom - lineTop, COLORS.gold, 4)
    State.list:addRect(17, lineBottom - 1, 9, 2, COLORS.gold, 4)
    State.list:addIcon(11, parentTop + 20, 14, UP_CHEVRON, COLORS.gold, 5, UP_COORDS)
end

---The mark of a quest of the open dungeon: the game's check for a done one, its own ? for one in the log (grey while
---worked on, yellow when done), else what starts it.
local function getRunQuestIcon(quest, logQuest, isInLog)
    if quest.isDone then
        return DONE_ICON
    end
    if isInLog then
        return logQuest and logQuest.isComplete and READY_ICON or IN_LOG_ICON
    end
    return getStartIcon(quest)
end

---One quest of the open dungeon, under the dungeon's mark and name: its icon under the mark, its title where the
---name starts; a quest in the log saying so in green.
---@return number y Below the row
local function addRunQuestRow(y, entry)
    local quest, isInLog = entry.quest, entry.sectionKey == "inLog"
    local logQuest = isInLog and ns.QuestState.getQuest(quest.questId)
    local icon = getRunQuestIcon(quest, logQuest, isInLog)
    local isColoured = icon == GIVER_ICON or icon == READY_ICON -- (the "!" and the "?" ready: in the kind's colour)
    return addListQuest(y, quest.questId, {
        indent = 2 + entry.depth * 16,
        isIconSpaceKept = true,
        title = quest.title,
        level = quest.level,
        subText = isInLog and ("|cff7ce07c" .. ns.L(
            logQuest and logQuest.isComplete and "Ready to turn in" or "In your log"
        ) .. "|r") or composeQuestText(quest, entry.sectionKey, entry.depth > 0),
        icon = icon,
        iconColour = isColoured and ns.MapMarks.getQuestIconColour(quest.questId, quest.isLowLevel, icon == READY_ICON)
            or nil,
        isTurnInIcon = icon == READY_ICON,
        color = quest.isDone and COLORS.tan or nil, -- handed in: its difficulty no longer matters
        handleClick = quest.isDone and ignoreClick or openQuest,
    })
end

---The open dungeon's quests, unfolded under its row, each lead-in under the quest it leads to.
---@return number y Below them
---@return table? selectedQuest The selected quest among them, to pick up (not one in the log, nor one done)
local function addRunQuests(y, row, selectedId)
    local selectedQuest
    local parentTop = y
    for _, entry in ipairs(composeEntries(List.keepRunToPickUp(row.run, Told.pickup))) do
        local quest = entry.quest
        if quest.questId == selectedId and entry.sectionKey ~= "inLog" and not quest.isDone then
            selectedQuest = quest
        end
        local rowTop = y
        if entry.depth == 0 then
            parentTop = y
        end
        y = addRunQuestRow(y, entry)
        if entry.depth > 0 then
            addLeadInArrow(parentTop, rowTop)
        end
    end
    return y, selectedQuest
end

---The list: each dungeon's row, the open one with its quests under it.
---@return number y Below the list
---@return table? selectedRow The dungeon whose page is shown
---@return table? selectedQuest The quest of it whose page is shown instead
local function addDungeonRows(rows)
    local selectedId = selectedQuestIds[TAB_DUNGEONS]
    local selectedRow, selectedQuest
    local y = 6
    for _, row in ipairs(rows) do
        local dungeonId = row.dungeon.areaId
        y = List.addDungeonRow(y, {
            name = row.dungeon.name,
            levelText = composeLevels(row),
            subText = composeRowText(row),
            isSelected = selectedId == -dungeonId or State.selectedDungeonId == dungeonId,
            isDone = row.isDone,
            handleClick = selectDungeon,
            data = -dungeonId,
        })
        if State.selectedDungeonId == dungeonId then
            selectedRow = selectedId == -dungeonId and row or selectedRow
            local runQuest
            y, runQuest = addRunQuests(y, row, selectedId)
            selectedQuest = runQuest or selectedQuest
            y = y + 6
        end
    end
    return y, selectedRow, selectedQuest
end

local pageQuest, pageRow, pageRun -- what the page beside the list shows, read by its drawing functions below

local function drawSelectedQuestPage()
    return drawAvailableQuest(pageQuest, State.selectedDungeonId)
end

local function drawSelectedDungeonPage()
    return drawDungeonPage(pageRow, pageRun)
end

---The page beside the list: the selected quest's, the open dungeon's, or a hint on selecting one.
local function drawDungeonsTabPage(selectedRow, selectedQuest)
    if selectedQuest then
        if State.mapQuestId == selectedQuest.questId then
            Actions.showChosenQuestStart(selectedQuest)
        end
        State.mapQuestId = nil
        State.selectedAvailableQuest = selectedQuest
        pageQuest = selectedQuest
        State.frame.finishPage(drawSelectedQuestPage)
    elseif selectedRow then
        pageRow, pageRun = selectedRow, List.keepRunToPickUp(selectedRow.run, Told.pickup)
        State.frame.finishPage(drawSelectedDungeonPage)
    else
        QuestPage.drawHintPage(
            ns.L("Select a dungeon to see its quests, where its way in is, and what to pick up before you go.")
        )
    end
end

---Draws the Dungeons tab: the dungeons with quests for the player, the open one's quests under it, and the page.
---@return table? selected, number? dungeonCount nil while the database is being read
function DungeonsTab.drawDungeonsTab()
    if not ns.Availability.isReady() then
        List.drawDatabaseWait()
        return nil, nil
    end
    local rows = getRows()
    Told.pickup, Told.isStoryHidden = List.getPickupChoice(), ns.Availability.isLaterHidden("quest")
    rows = getShownRows(rows)
    local y, selectedRow, selectedQuest = addDungeonRows(rows)
    if #rows == 0 then
        State.list:addText(
            ns.L("No dungeon has quests for you right now."),
            10,
            y + 4,
            { color = COLORS.tan, width = State.list.width - 20 }
        )
        y = y + 24
    end
    State.list:finish(y + 8)
    State.frame.status:SetText("")
    drawDungeonsTabPage(selectedRow, selectedQuest)
    return selectedQuest, #rows
end
