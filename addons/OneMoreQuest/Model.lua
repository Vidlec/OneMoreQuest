local _, ns = ...

-- Turns the tracked quests into what the tracker draws: zone groups, each with its quests in order.
local Model = {}
ns.Model = Model

---@return { zoneId: number?, zoneName: string?, position: table? } player
function Model.getPlayer()
    local position = ns.Geometry.getPlayerPosition()
    local uiMapId = position and position.uiMapId or C_Map.GetBestMapForUnit("player")
    local areaId = uiMapId and ns.Database.getAreaId(uiMapId)
    local zoneName = GetRealZoneText and GetRealZoneText() or nil
    -- Inside a dungeon the game's own number for the instance is the surest guide; then the map, then the name
    local zoneId = ns.Database.getInstanceDungeonId() or (areaId and ns.Database.getParentZoneId(areaId)) or nil
    if not zoneId and IsInInstance and IsInInstance() then
        -- Inside an instance the map often belongs to no known area; the instance's name still says where
        local dungeon = ns.Database.getDungeonByName(zoneName)
        zoneId = dungeon and dungeon.areaId or nil
    end
    return {
        zoneId = zoneId,
        zoneName = zoneName,
        parentZoneName = zoneId and ns.Database.getZoneName(zoneId) or nil, -- the zone a subzone belongs to
        position = position,
    }
end

---@class TrackerEntry : TrackedQuest
---@field zoneId number
---@field isTurnIn boolean
---@field finisherName string?
---@field distance number? Yards to the nearest place of the step
---@field direction string?
---@field chainIndex number?
---@field chainTotal number?
---@field unlockIds number[] The quests it opens besides its chain, still to do (Chain.getUnlockedQuestIds)
---@field requiredIds number[] The quests it needed first besides its chain (Chain.getRequiredQuestIds)
---@field item table? The quest's usable item, while it is still of use
---@field number number? The quest's number on the map, set for tracked quests
---@field unlocatedCount number Unfinished objectives the database has no place for
---@field allPlaces table[] Places of the step in every zone it can be done in
---@field otherZonesText string? "Also in ...", when the step can be done in zones besides the one it lists under
---@field zoneIds number[]? Every zone the step can be done in, the one it lists under first; set with otherZonesText

local MAX_ZONE_NAMES = 2

---The quiet line under a quest that can be done in more zones than the one it is listed under.
---@param isEveryZone boolean? The zones are all the quest's, not others besides one: "In ..." rather than "Also in ..."
---@return string? text nil when there is no other zone
function Model.composeOtherZonesText(zoneIds, isEveryZone)
    if not zoneIds or #zoneIds == 0 then
        return nil
    end
    local names = {}
    for index = 1, math.min(#zoneIds, MAX_ZONE_NAMES) do
        names[index] = ns.Database.getZoneName(zoneIds[index])
    end
    local text = ns.L(isEveryZone and "In %s" or "Also in %s", table.concat(names, ", "))
    if #zoneIds > MAX_ZONE_NAMES then
        text = text .. ns.Lp(#zoneIds - MAX_ZONE_NAMES, " and %d more", " and %d more")
    end
    return text
end

-- Where each quest leads now (Location.composeStep), kept while the quest stands where it did: the map, the minimap
-- and the tracker each ask for every quest's, at every drawing, and working it out is most of a drawing's cost.
-- Kept by what it follows, and checked against it at every asking: whether the quest is done, which of its
-- objectives are (each by its kind and its words, which is how its places are found), and the player's zone. Not
-- how far along an objective is: a kill or a loot counted leaves every place where it was. So a step lasts from
-- one drawing to the next, through every count, until the quest really moves on.
local stepCache = {} -- [questId] = { key, step }
local wordsGeneration = 0 -- raised whenever the words or what is known of quests changed (Model.forgetSteps)
local dataGeneration = 0 -- raised whenever the quests may have changed in any way (Model.forgetEntries)

-- One entry a quest for everything drawn: the tracker, the quest window, the map and the minimap each ask for every
-- tracked quest's, one after the other (a frame apart, Core's shared redraw), and each used to compose it anew.
-- Kept until the quests may have changed (Model.forgetEntries) or the player is in another zone. Walking on, only
-- what follows the player is told again, in the entry itself: how far and which way its nearest place lies, once
-- the player is ENTRY_REUSE_YARDS from where that was last told. Shared: to read, not to change.
local ENTRY_REUSE_YARDS = 4
local entryCache, entryCacheAt = {}, nil
local structureKeyCache -- { generation, zoneId, extraQuestId, watchKey, spoilerKey, key }: Model.getStructureKey, worked out once a redraw

local providersKey -- which sources of quest data answered when the steps kept were worked out (Database.getProvidersKey)

---The log, the bags, the zone or the level may have changed: every quest's entry is composed again when next asked
---for. Where each leads (its step) stays, checked against what it follows; all of them go when another source of
---quest data has come or gone (an addon loaded on demand), as what the database says of a quest may then differ.
function Model.forgetEntries()
    entryCache, entryCacheAt = {}, nil
    dataGeneration = dataGeneration + 1
    local key = ns.Database.getProvidersKey()
    if providersKey ~= nil and key ~= providersKey then
        stepCache = {}
        wordsGeneration = wordsGeneration + 1
    end
    providersKey = key
end

---The words of quests, or what is known of them, changed (the language, a translation arrived, a quest found
---missing from the game): where each quest leads is worked out again too.
function Model.forgetSteps()
    stepCache = {}
    wordsGeneration = wordsGeneration + 1
    Model.forgetEntries()
end

---@return string key What a quest's step follows: the player's zone, whether the quest is done, and each objective's
---kind, words and whether it is finished
local function getStepKey(entry, zoneId)
    local parts = { tostring(zoneId), entry.isComplete and "c" or "o", entry.isFailed and "f" or "" }
    for _, objective in ipairs(entry.objectives or {}) do
        parts[#parts + 1] = tostring(objective.type)
            .. (objective.isFinished and "+" or "-")
            .. tostring(objective.label)
    end
    return table.concat(parts, ":")
end

local function composeStep(questId, entry, zoneId)
    local key = getStepKey(entry, zoneId)
    local cached = stepCache[questId]
    if cached and cached.key == key then
        return cached.step
    end
    local step = ns.Location.composeStep(entry, zoneId)
    providersKey = providersKey or ns.Database.getProvidersKey() -- (what answered when the first of them was worked out)
    stepCache[questId] = { key = key, step = step }
    return step
end

---@return boolean isHere The player is where distances were last told from (entryCacheAt): no further on than
---ENTRY_REUSE_YARDS
local function isMeasuredHere(player)
    local at, position = entryCacheAt, player.position
    if (at.north == nil) ~= (position == nil) then
        return false
    end
    return position == nil
        or (
            at.continentId == position.continentId
            and ns.Geometry.getDistance(at.north, at.west, position.north, position.west) <= ENTRY_REUSE_YARDS
        )
end

---@return TrackerEntry entry Shared with everyone who asks: to read, not to change
function Model.composeEntry(questId, player)
    local isKept = ns.frameNumber > 0 -- (in the tests, where no frames run, every asking composes)
    if isKept then
        if not entryCacheAt or entryCacheAt.zoneId ~= player.zoneId then
            entryCache, entryCacheAt = {}, nil -- another zone: where each quest leads may be another place
        end
        if not entryCacheAt or not isMeasuredHere(player) then
            -- (a new table each time the player has walked on: each entry kept says which one it was measured from)
            local position = player.position
            entryCacheAt = {
                zoneId = player.zoneId,
                continentId = position and position.continentId,
                north = position and position.north,
                west = position and position.west,
            }
        end
        local kept = entryCache[questId]
        if kept then
            if kept.measuredAt ~= entryCacheAt then
                kept.measuredAt = entryCacheAt
                kept.distance, kept.direction, kept.nearestPlace =
                    ns.Geometry.getNearest(kept.places, player.position, ns.Database.getUiMapId)
            end
            return kept
        end
    end
    local entry = ns.QuestState.getQuest(questId)
    local step = composeStep(questId, entry, player.zoneId)
    entry.stepKey = stepCache[questId] and stepCache[questId].key or nil -- (for Model.getStructureKey)
    entry.zoneId, entry.isTurnIn, entry.finisherName = step.zoneId, step.isTurnIn, step.finisherName
    entry.unlocatedCount = step.unlocatedCount
    if step.isEvent then
        -- What the quest asks, in the game's words, stands in for the objectives it does not have
        local texts = ns.Database.getQuestField(questId, "objectivesText")
        -- In the player's language when a translation addon has the whole text, else its first line as the game wrote it
        local whole = type(texts) == "table" and table.concat(texts, " ")
        local translated = whole and ns.QuestText.getObjectives(questId, whole)
        entry.eventText = translated ~= whole and translated
            or type(texts) == "table" and texts[1]
            or ns.L("Speak with %s", entry.finisherName or ns.L("the quest giver"))
    end
    entry.places, entry.allPlaces = step.places, step.allPlaces or step.places
    entry.otherZonesText = Model.composeOtherZonesText(step.otherZoneIds)
    if entry.otherZonesText then
        entry.zoneIds = { step.zoneId }
        for _, zoneId in ipairs(step.otherZoneIds) do
            entry.zoneIds[#entry.zoneIds + 1] = zoneId
        end
    end
    -- A quest of a category (cooking, a class, a holiday) is listed under it, as the game's own quest log does;
    -- its places stay what they are, and its page says which zones they are in
    entry.categoryId = ns.Database.getQuestCategoryId(questId)
    if entry.categoryId then
        entry.categoryName = ns.Database.getCategoryName(entry.categoryId, ns.QuestState.getLogHeader(questId))
        local zoneIds = { step.zoneId }
        for _, zoneId in ipairs(step.otherZoneIds or {}) do
            zoneIds[#zoneIds + 1] = zoneId
        end
        if step.zoneId ~= ns.Location.UNKNOWN_ZONE_ID then
            entry.otherZonesText = Model.composeOtherZonesText(zoneIds, true)
            entry.zoneIds = #zoneIds > 1 and zoneIds or nil
        end
    end
    entry.distance, entry.direction, entry.nearestPlace =
        ns.Geometry.getNearest(step.places, player.position, ns.Database.getUiMapId)
    entry.chainIndex, entry.chainTotal = ns.Chain.getStep(questId)
    entry.unlockIds, entry.requiredIds = ns.Chain.getUnlockedQuestIds(questId), ns.Chain.getRequiredQuestIds(questId)
    local item = ns.QuestState.getItem(questId)
    if item and (not entry.isComplete or item.shouldShowWhenComplete) then
        entry.item = item
    end
    if isKept then
        entry.measuredAt = entryCacheAt
        entryCache[questId] = entry
    end
    return entry
end

---@return number generation Raised whenever where quests lead may have changed apart from how far along they are: the
---words of quests, the sources of quest data, a dungeon learned (Model.forgetSteps). An objective's places, and
---what is worked out from them, hold while it does.
function Model.getWordsGeneration()
    return wordsGeneration
end

---@return number generation Raised whenever the quests may have changed in any way: what was worked out from
---them under one number holds while the number does
function Model.getGeneration()
    return dataGeneration
end

---@return string key What a map's marks, icons and areas follow of the tracked quests: which they are and in what
---order, how each is called, where each one's step is, whether it is done and which of its objectives are. Not how
---far along they are: a kill or a loot counted changes no mark, icon or area, only words in a tooltip and counts in
---the tracker. So whoever draws a map can tell a count going up from the quests really moving on.
---@param extraQuestId number? A quest drawn though it is not tracked (one selected in the quest list)
function Model.getStructureKey(extraQuestId)
    local player = Model.getPlayer()
    local kept = structureKeyCache
    -- (and the quests tracked: this addon tracking one more, or one less, changes them within one redraw)
    local watchKey = ns.QuestState.getWatchKey()
    -- (and what the spoiler choices let show: a choice, a hint or something found changes what is drawn)
    local spoilerKey = ns.Spoilers.getKey()
    if
        ns.frameNumber > 0
        and kept
        and kept.generation == dataGeneration
        and kept.zoneId == player.zoneId
        and kept.extraQuestId == extraQuestId
        and kept.watchKey == watchKey
        and kept.spoilerKey == spoilerKey
    then
        return kept.key
    end
    local numbers = ns.QuestState.getWatchNumbers()
    -- (the quests the maps show: the tracked ones and those ready to hand in, an untracked one's "?" coming with it)
    local questIds = ns.QuestState.getShownOnMapQuestIds()
    if extraQuestId and not numbers[extraQuestId] and ns.QuestState.isInLog(extraQuestId) then
        questIds[#questIds + 1] = extraQuestId
    end
    local parts = {}
    for index, questId in ipairs(questIds) do
        local entry = Model.composeEntry(questId, player)
        parts[index] = table.concat({
            questId,
            tostring(numbers[questId]),
            tostring(entry.stepKey or getStepKey(entry, player.zoneId)),
            tostring(entry.title),
            tostring(entry.level),
            tostring(entry.eventText or ""),
        }, "=")
    end
    local key = table.concat(parts, ";")
        .. "@"
        .. tostring(player.zoneId)
        .. "~"
        .. wordsGeneration
        .. "~"
        .. spoilerKey
    structureKeyCache = {
        generation = dataGeneration,
        zoneId = player.zoneId,
        extraQuestId = extraQuestId,
        watchKey = watchKey,
        spoilerKey = spoilerKey,
        key = key,
    }
    return key
end

---The order of a list that holds tracked and untracked quests alike, such as the quest log's: by level and
---name. Tracking a quest gives it a number but leaves it where it is.
local function isBeforeByLevel(first, second)
    if first.level ~= second.level then
        return first.level < second.level
    end
    if first.title ~= second.title then
        return first.title < second.title
    end
    return first.questId < second.questId
end

---The tracker's order, where every quest is tracked: by number, which only changes when tracking does.
---Nothing moves as the player walks around.
local function isBeforeByNumber(first, second)
    if first.number and second.number and first.number ~= second.number then
        return first.number < second.number
    end
    return isBeforeByLevel(first, second)
end

---@return number share How much of a quest is done, 0 to 1: ready to hand in is all of it
function Model.getDoneShare(entry)
    if entry.isTurnIn or entry.isComplete then
        return 1
    end
    local done, wanted = 0, 0
    for _, objective in ipairs(entry.objectives or {}) do
        local required = math.max(objective.required or 1, 1)
        done = done + math.min((objective.fulfilled or 0) / required, 1)
        wanted = wanted + 1
    end
    return wanted > 0 and done / wanted or 0
end

-- The tracker's other orders inside a zone, the player's choice: nearest first (it moves as the player walks), by
-- level, or nearest to done
local TRACKER_ORDERS = {
    ["distance"] = function(first, second)
        local firstDistance, secondDistance = first.distance or math.huge, second.distance or math.huge
        if firstDistance ~= secondDistance then
            return firstDistance < secondDistance
        end
        return isBeforeByNumber(first, second)
    end,
    ["level"] = isBeforeByLevel,
    ["progress"] = function(first, second)
        local firstShare, secondShare = Model.getDoneShare(first), Model.getDoneShare(second)
        if firstShare ~= secondShare then
            return firstShare > secondShare
        end
        return isBeforeByNumber(first, second)
    end,
}

---@class TrackerGroup
---@field zoneId number
---@field zoneName string
---@field isCurrent boolean The player is in this zone
---@field isCategory boolean A category such as cooking, not a zone: `zoneId` is the category's (negative) number
---@field hasTurnIn boolean A quest here is ready to hand in
---@field isCollapsed boolean
---@field entries TrackerEntry[]

---The zone the game's own quest log puts a quest under: the one it is filed under in the database, mostly
---where it is picked up. A town counts for the zone around it; a dungeon stays a dungeon.
---@return number? zoneId nil when the database files it under nothing
function Model.getPickupZoneId(questId)
    local zoneOrSort = ns.Database.getQuestField(questId, "zoneOrSort") or 0
    if zoneOrSort <= 0 then
        return nil
    end
    if ns.Database.getDungeon(zoneOrSort) then
        return zoneOrSort
    end
    return ns.Database.getParentZoneId(zoneOrSort) or zoneOrSort
end

-- What the spoiler choices let be told of a quest's places (Spoilers). Asked only while something is held back:
-- in Guide every one of these is true, and the parts that draw do not ask.

---@return boolean isShown Who a quest is handed in to, and where, may be told: shown, or "once you met them" and the
---player has met someone it is handed in to (a hint lifts it)
function Model.isTurnInShown(questId)
    if not ns.Spoilers.isActive() then
        return true
    end
    local choice = ns.Spoilers.get("turnIn", questId)
    if choice ~= "met" then
        return choice == "shown"
    end
    local finishedBy = ns.Database.getQuestField(questId, "finishedBy")
    for _, npcId in ipairs(type(finishedBy) == "table" and finishedBy[1] or {}) do
        if ns.Spoilers.hasMet(npcId) then
            return true
        end
    end
    return false
end

---@return boolean isHidden Where a quest's next step is, its zone too, is held back: its objectives hidden (or
---"where you found them" with nothing found yet), or, ready to hand in, its turn-in; and no hint gave the zone
function Model.isWhereHidden(entry)
    if not ns.Spoilers.isActive() or ns.Spoilers.getHint(entry.questId) >= ns.Spoilers.HINT_ZONE then
        return false
    end
    if entry.isTurnIn then
        return not Model.isTurnInShown(entry.questId)
    end
    local choice = ns.Spoilers.get("objectives", entry.questId)
    return choice == "hidden" or (choice == "found" and not ns.Spoilers.hasFoundAny(entry.questId))
end

---@param activeQuestId number? The quest the player picked as active; nil or an untracked one means none
---@param options { questIds: number[]?, collapsedZones: table?, isExpandedByDefault: boolean? }? Defaults: the
---tracked quests, the tracker's collapsed zones, other zones collapsed
---@return { groups: TrackerGroup[], activeQuestId: number?, questCount: number }
function Model.compose(activeQuestId, options)
    options = options or {}
    local player = Model.getPlayer()
    local groups, groupsByZoneId, isPresent = {}, {}, {}
    local collapsedZones = options.collapsedZones or ns.settings.collapsedZones

    local questIds = options.questIds or ns.QuestState.getWatchedQuestIds()
    local numbers = ns.QuestState.getWatchNumbers()
    local isSpoiling = ns.Spoilers.isActive() -- (asked once: in Guide nothing below asks the spoiler choices)
    for _, questId in ipairs(questIds) do
        local entry = Model.composeEntry(questId, player)
        entry.number = numbers[questId]
        -- Under where its next step is done, or, as the game's own quest log has it, where it was picked up
        local groupZoneId = entry.zoneId
        local isWhereHidden = isSpoiling and not entry.categoryId and Model.isWhereHidden(entry)
        if ns.settings.logGrouping == "pickup" or isWhereHidden then
            -- (where the next step is held back, its zone's heading would tell it: under where it was picked up, or
            -- under no zone)
            groupZoneId = Model.getPickupZoneId(questId)
                or (isWhereHidden and ns.Location.UNKNOWN_ZONE_ID)
                or entry.zoneId
        end
        local groupId = entry.categoryId or groupZoneId
        local group = groupsByZoneId[groupId]
        if not group then
            local zoneName = entry.categoryName or ns.Database.getZoneName(groupZoneId)
            if isWhereHidden and groupZoneId == ns.Location.UNKNOWN_ZONE_ID then
                zoneName = ns.L("Quests")
            end
            group = {
                zoneId = groupId,
                zoneName = zoneName,
                isCategory = entry.categoryId ~= nil,
                -- The zone the player is in: by its number, or by its name as the game names where the player is (a
                -- city's map and its quests can name it by different area numbers)
                isCurrent = not entry.categoryId
                    and (
                        groupZoneId == player.zoneId
                        or (zoneName ~= nil and (zoneName == player.zoneName or zoneName == player.parentZoneName))
                    ),
                hasTurnIn = false,
                entries = {},
            }
            groupsByZoneId[groupId] = group
            groups[#groups + 1] = group
        end
        group.entries[#group.entries + 1] = entry
        group.hasTurnIn = group.hasTurnIn or entry.isTurnIn
        -- A category (cooking, a class) is current, and so open, when a quest's next step is where the player is:
        -- a cooking quest just picked up in Hillsbrad is not hidden while the player hunts its turtles there
        if group.isCategory and entry.zoneId == player.zoneId and player.zoneId ~= nil then
            group.isCurrent = true
        end
        isPresent[questId] = true
    end

    for _, group in ipairs(groups) do
        -- The quest log's list by level; the tracker's by number, or in the order the player chose
        table.sort(
            group.entries,
            options.questIds and isBeforeByLevel or TRACKER_ORDERS[ns.settings.trackerOrder] or isBeforeByNumber
        )
    end
    table.sort(groups, function(first, second)
        if first.isCurrent ~= second.isCurrent then
            return first.isCurrent
        end
        if first.hasTurnIn ~= second.hasTurnIn then
            return first.hasTurnIn
        end
        if first.isCategory ~= second.isCategory then
            return not first.isCategory -- places first, then categories such as cooking
        end
        return first.zoneName < second.zoneName
    end)

    -- The active quest is only ever the one the player picked; with no pick, none is
    if not isPresent[activeQuestId] then
        activeQuestId = nil
    end

    for _, group in ipairs(groups) do
        local hasActiveQuest = false
        for _, entry in ipairs(group.entries) do
            hasActiveQuest = hasActiveQuest or entry.questId == activeQuestId
        end
        local chosen = collapsedZones[group.zoneId]
        if chosen == nil then
            group.isCollapsed = not (
                options.isExpandedByDefault
                or group.isCurrent
                or group.hasTurnIn
                or hasActiveQuest
            )
        else
            group.isCollapsed = chosen
        end
    end

    return { groups = groups, activeQuestId = activeQuestId, questCount = #questIds }
end

-- Walking from one subzone to the next (ZONE_CHANGED) changes nothing drawn unless the zone the lists go by changed
local lastZone

-- Entries in the player's language, and the game's words for quests, follow when either changes; so does where
-- each quest leads
ns.on("LANGUAGE_CHANGED", Model.forgetSteps)
ns.on("QUEST_TEXT_CHANGED", Model.forgetSteps)
ns.on("QUEST_FACTS_CHANGED", Model.forgetSteps)

ns.registerModule({
    name = "Model",
    invalidate = Model.forgetEntries, -- every redraw of everything: the log, bags, zone or level changed
    changes = {
        ZONE_CHANGED = function()
            local player = Model.getPlayer()
            local zone = tostring(player.zoneId) .. ":" .. tostring(player.zoneName)
            local changed = zone ~= lastZone
            lastZone = zone
            return changed
        end,
    },
})
