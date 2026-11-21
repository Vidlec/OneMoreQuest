local _, ns = ...

-- Works out where the current step of a quest takes place: the unfinished objectives, or the turn-in once
-- everything is done. A place is { zoneId, x, y } with x and y in 0-100, or -1 inside an instance.
local Location = {}
ns.Location = Location

local CREATURES, OBJECTS, ITEMS, KILL_CREDITS = 1, 2, 3, 5
local UNKNOWN_ZONE_ID = 0

Location.UNKNOWN_ZONE_ID = UNKNOWN_ZONE_ID

---Something inside a dungeon has no map position of its own, so it is placed at the dungeon's entrances:
---that is where the player has to go, and where the map can show it. Such a place is filed under the dungeon
---(groupZoneId) and drawn in the zone the entrance stands in (mapZoneId).
---@return boolean isAdded False when the dungeon or its entrances are not known
local function addDungeonEntrances(places, dungeonZoneId)
    local dungeon = ns.Database.getDungeon(dungeonZoneId)
    if not dungeon or #dungeon.entrances == 0 then
        return false
    end
    for _, entrance in ipairs(dungeon.entrances) do
        places[#places + 1] = {
            zoneId = entrance.zoneId, groupZoneId = dungeon.areaId, mapZoneId = ns.Database.getParentZoneId(entrance.zoneId),
            x = entrance.x, y = entrance.y, dungeonName = dungeon.name, dungeonZoneId = dungeon.areaId,
        }
    end
    return true
end

local function addSpawns(places, spawns)
    for zoneId, points in pairs(spawns or {}) do
        local parentZoneId = ns.Database.getParentZoneId(zoneId)
        local hasEntrances = false
        -- A dungeon's own area, or one of the areas inside it (the database records some spawns by those)
        local isDungeon = ns.Database.getDungeon(parentZoneId) ~= nil
        for _, point in ipairs(points) do
            if point[1] < 0 or isDungeon then
                -- Inside an instance, whether or not a position on its own map is recorded: once per
                -- instance, its entrances stand in for every spawn there, on the maps outside
                if not hasEntrances then
                    hasEntrances = addDungeonEntrances(places, isDungeon and parentZoneId or zoneId)
                end
                if point[1] >= 0 then
                    -- The spot itself as well, for the dungeon's own map while the player is inside; it is
                    -- filed under the dungeon, so the maps outside never show it
                    places[#places + 1] = { zoneId = zoneId, groupZoneId = parentZoneId, x = point[1], y = point[2], isInside = true }
                elseif not hasEntrances then
                    places[#places + 1] = { zoneId = zoneId, groupZoneId = parentZoneId, x = point[1], y = point[2] }
                end
            else
                -- Coordinates stay on the map of the zone they were recorded for
                places[#places + 1] = { zoneId = zoneId, groupZoneId = parentZoneId, x = point[1], y = point[2] }
            end
        end
    end
end

-- Places of a creature or object are built once and shared, so their measured world positions are kept
local npcPlaces, objectPlaces = {}, {}

local function addCachedPlaces(places, cache, id, getField)
    local cached = cache[id]
    if not cached then
        cached = {}
        addSpawns(cached, getField(id, "spawns"))
        if ns.Database.isAvailable() then
            cache[id] = cached
        end
    end
    for _, place in ipairs(cached) do
        places[#places + 1] = place
    end
end

local function addNpcPlaces(places, npcId)
    addCachedPlaces(places, npcPlaces, npcId, ns.Database.getNpcField)
end

local function addObjectPlaces(places, objectId)
    addCachedPlaces(places, objectPlaces, objectId, ns.Database.getObjectField)
end

Location.addNpcPlaces = addNpcPlaces -- where an item drops is worked out from them (Drops)
Location.addObjectPlaces = addObjectPlaces

---An item is found where the creatures and objects that drop it are; a vendor counts only without drops.
local function addItemPlaces(places, itemId)
    for _, npcId in ipairs(ns.Database.getItemField(itemId, "npcDrops") or {}) do
        addNpcPlaces(places, npcId)
    end
    for _, objectId in ipairs(ns.Database.getItemField(itemId, "objectDrops") or {}) do
        addObjectPlaces(places, objectId)
    end
    if #places == 0 then
        for _, npcId in ipairs(ns.Database.getItemField(itemId, "vendors") or {}) do
            addNpcPlaces(places, npcId)
        end
    end
end

---Places of one quest log objective.
---@param objectiveType string "monster", "object", "item" or another type the game reports
---@param typeIndex number Position among the quest's objectives of the same type
function Location.getObjectivePlaces(questId, objectiveType, typeIndex)
    local places = {}
    local objectives = ns.Database.getQuestField(questId, "objectives") or {}
    if objectiveType == "monster" then
        local creatures, killCredits = objectives[CREATURES] or {}, objectives[KILL_CREDITS] or {}
        local creature, killCredit = creatures[typeIndex], killCredits[typeIndex - #creatures]
        if creature then
            addNpcPlaces(places, creature[1])
        elseif killCredit then
            for _, npcId in ipairs(killCredit[1] or {}) do
                addNpcPlaces(places, npcId)
            end
        end
    elseif objectiveType == "object" then
        local object = (objectives[OBJECTS] or {})[typeIndex]
        if object then
            addObjectPlaces(places, object[1])
        end
    elseif objectiveType == "item" then
        local item = (objectives[ITEMS] or {})[typeIndex]
        if item then
            addItemPlaces(places, item[1])
        end
    else
        local triggerEnd = ns.Database.getQuestField(questId, "triggerEnd")
        addSpawns(places, triggerEnd and triggerEnd[2])
    end
    if #places == 0 then
        -- Nothing recorded, but the quest is filed under a dungeon: the objective is inside, so the way in
        -- is the place to go
        addDungeonEntrances(places, ns.Database.getQuestField(questId, "zoneOrSort") or 0)
    end
    return places
end

local patrolCache = {} -- [questId] = its creatures' patrols: the database does not change while playing
local npcPatrolCache = {} -- [npcId] = its patrols

---@return number[] npcIds Whom a quest is had from: the creatures that give it, and those that drop the item it starts
---from (The Runed Scroll, from Aean Swiftriver), each once
function Location.getStarterNpcIds(questId)
    local startedBy = ns.Database.getQuestField(questId, "startedBy") or {}
    local npcIds, isSeen = {}, {}
    local function add(npcId)
        if npcId and not isSeen[npcId] then
            isSeen[npcId], npcIds[#npcIds + 1] = true, npcId
        end
    end
    for _, npcId in ipairs(startedBy[1] or {}) do
        add(npcId)
    end
    for _, itemId in ipairs(startedBy[3] or {}) do
        for _, npcId in ipairs(ns.Database.getItemField(itemId, "npcDrops") or {}) do
            add(npcId)
        end
    end
    return npcIds
end

---The paths one creature walks, as the database records them; none for one that stands still.
---@return { npcId: number, zoneId: number, points: number[][] }[] patrols Each path's points on its zone's map (0 to 100)
function Location.getNpcPatrols(npcId)
    if npcPatrolCache[npcId] then
        return npcPatrolCache[npcId]
    end
    local patrols = {}
    for zoneId, paths in pairs(ns.Database.getNpcField(npcId, "waypoints") or {}) do
        for _, path in ipairs(type(paths) == "table" and paths or {}) do
            local points = {}
            for _, point in ipairs(path) do
                if type(point) == "table" and point[1] and point[1] >= 0 then
                    points[#points + 1] = point
                end
            end
            if #points >= 2 then
                patrols[#patrols + 1] = { npcId = npcId, zoneId = zoneId, points = points }
            end
        end
    end
    if ns.Database.isAvailable() then
        npcPatrolCache[npcId] = patrols
    end
    return patrols
end

---The paths the quest's creatures walk, as the database records them (Sharptalon round his part of Ashenvale): the
---creatures to kill, those giving kill credit, and those that drop its items. Each creature once.
---@return { npcId: number, zoneId: number, points: number[][] }[] patrols Each path's points on its zone's map (0 to 100)
function Location.getObjectivePatrols(questId)
    if patrolCache[questId] then
        return patrolCache[questId]
    end
    local objectives = ns.Database.getQuestField(questId, "objectives") or {}
    local npcIds, isSeen = {}, {}
    local function add(npcId)
        if npcId and not isSeen[npcId] then
            isSeen[npcId], npcIds[#npcIds + 1] = true, npcId
        end
    end
    for _, creature in ipairs(objectives[CREATURES] or {}) do
        add(creature[1])
    end
    for _, killCredit in ipairs(objectives[KILL_CREDITS] or {}) do
        for _, npcId in ipairs(killCredit[1] or {}) do
            add(npcId)
        end
    end
    for _, item in ipairs(objectives[ITEMS] or {}) do
        for _, npcId in ipairs(ns.Database.getItemField(item[1], "npcDrops") or {}) do
            add(npcId)
        end
    end
    local patrols = {}
    for _, npcId in ipairs(npcIds) do
        for _, patrol in ipairs(Location.getNpcPatrols(npcId)) do
            patrols[#patrols + 1] = patrol
        end
    end
    if ns.Database.isAvailable() then
        patrolCache[questId] = patrols
    end
    return patrols
end

---What one quest log objective is after: a creature to kill, or an item to collect.
---@return { npcId: number?, itemId: number? }? target nil for objects, events and anything the database lacks
function Location.getObjectiveTarget(questId, objectiveType, typeIndex)
    local objectives = ns.Database.getQuestField(questId, "objectives") or {}
    if objectiveType == "monster" then
        local creatures, killCredits = objectives[CREATURES] or {}, objectives[KILL_CREDITS] or {}
        local creature, killCredit = creatures[typeIndex], killCredits[typeIndex - #creatures]
        local npcId = creature and creature[1] or killCredit and (killCredit[1] or {})[1]
        return npcId and { npcId = npcId } or nil
    elseif objectiveType == "item" then
        local item = (objectives[ITEMS] or {})[typeIndex]
        return item and { itemId = item[1] } or nil
    end
    return nil
end

---@return table[] places, string? finisherName
---Leaves out the spots in the other faction's towns, where the player cannot go to talk to anyone (a Kirin Tor image
---that also stands in Southshore and Dalaran is met in Silverpine by the Horde). When every spot is in one, they are
---all kept, so the quest still has somewhere to go.
local function leaveOutHostileTowns(places)
    local reachable = {}
    for _, place in ipairs(places) do
        if not ns.Database.isInHostileTown(place.zoneId, place.x, place.y) then
            reachable[#reachable + 1] = place
        end
    end
    return #reachable > 0 and reachable or places
end

function Location.getFinisherPlaces(questId)
    local places, finisherName = {}, nil
    local finishedBy = ns.Database.getQuestField(questId, "finishedBy") or {}
    -- A quest both factions can do is handed in to one person on each side: only the player's side counts.
    -- When none is marked friendly, they are all kept, so the quest still has somewhere to go.
    local finisherNpcIds = {}
    for _, npcId in ipairs(finishedBy[1] or {}) do
        if ns.Database.isNpcFriendly(npcId) then
            finisherNpcIds[#finisherNpcIds + 1] = npcId
        end
    end
    if #finisherNpcIds == 0 then
        finisherNpcIds = finishedBy[1] or {}
    end
    for _, npcId in ipairs(finisherNpcIds) do
        addNpcPlaces(places, npcId)
        finisherName = finisherName or ns.Database.getNpcField(npcId, "name")
    end
    for _, objectId in ipairs(finishedBy[2] or {}) do
        addObjectPlaces(places, objectId)
        finisherName = finisherName or ns.Database.getObjectField(objectId, "name")
    end
    return leaveOutHostileTowns(places), finisherName
end

local DUNGEON_TAG_IDS = { [62] = true, [81] = true, [85] = true } -- raid, dungeon, heroic

---Whether the game itself labels the quest as one for a dungeon or raid.
local function hasDungeonTag(questId)
    return DUNGEON_TAG_IDS[ns.QuestState.getTagId(questId)] == true
end

---The dungeon a quest belongs to. The surest sign is the category the quest is filed under; failing that,
---a quest the game labels as a dungeon quest belongs to the dungeon most of its objectives are in.
---@param placeLists table[][] Places of each unfinished objective
---@return number? dungeonZoneId
function Location.getQuestDungeonId(questId, placeLists)
    local dungeon = ns.Database.getDungeon(ns.Database.getQuestField(questId, "zoneOrSort") or 0)
    if dungeon then
        return dungeon.areaId
    end
    if not hasDungeonTag(questId) then
        return nil
    end
    local counts, bestZoneId = {}, nil
    for _, places in ipairs(placeLists or {}) do
        local seenZones = {}
        for _, place in ipairs(places) do
            local zoneId = place.dungeonZoneId
            if zoneId and not seenZones[zoneId] then
                seenZones[zoneId] = true
                counts[zoneId] = (counts[zoneId] or 0) + 1
                if not bestZoneId or counts[zoneId] > counts[bestZoneId] or (counts[zoneId] == counts[bestZoneId] and zoneId < bestZoneId) then
                    bestZoneId = zoneId
                end
            end
        end
    end
    return bestZoneId
end

---@return table? dungeon The dungeon an area is, or lies inside
local function getAreaDungeon(zoneId)
    return ns.Database.getDungeon(zoneId) or ns.Database.getDungeon(ns.Database.getParentZoneId(zoneId) or 0)
end

local DUNGEON_MOUTH = 8 -- how near a dungeon's entrance, in map units, a place still counts as the dungeon's own

---@return boolean isAtMouth Every usable point of a spawn list in one zone lies at one of a dungeon's entrances,
---in its cave or right outside, where the data often puts creatures of the instance
local function isAtDungeonMouth(zoneId, points, dungeon)
    if not dungeon or type(points) ~= "table" then
        return false
    end
    local usablePoints = {}
    for _, point in ipairs(points) do
        if type(point) == "table" and type(point[1]) == "number" and type(point[2]) == "number" and point[1] >= 0 then
            usablePoints[#usablePoints + 1] = point
        end
    end
    if #usablePoints == 0 then
        return false
    end
    for _, entrance in ipairs(dungeon.entrances or {}) do
        if entrance.zoneId == zoneId or entrance.zoneId == ns.Database.getParentZoneId(zoneId) then
            local isNear = true
            for _, point in ipairs(usablePoints) do
                isNear = isNear and math.abs(point[1] - entrance.x) <= DUNGEON_MOUTH and math.abs(point[2] - entrance.y) <= DUNGEON_MOUTH
            end
            if isNear then
                return true
            end
        end
    end
    return false
end

-- Places the data gives only on a continent or world map (Overmaster Pyron of Blackrock Depths) are no place at
-- all: told by the map the area is drawn on, as the game types it
local CONTINENT_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
local isContinentAreaById = {}
local function isContinentArea(zoneId)
    if isContinentAreaById[zoneId] == nil then
        local uiMapId = ns.Database.getUiMapId(zoneId)
        local info = uiMapId and C_Map and C_Map.GetMapInfo and ns.Database.getMapInfo(uiMapId)
        isContinentAreaById[zoneId] = type(info) == "table" and type(info.mapType) == "number" and info.mapType <= CONTINENT_MAP_TYPE
    end
    return isContinentAreaById[zoneId]
end

---@return string? sentence What the quest's own text says about an objective: the sentence naming it (its label's
---words, as the game writes them), else the text's first sentence; nil when the quest has no text
function Location.getQuestTextHint(questId, label)
    local text = ns.Database.getQuestField(questId, "objectivesText")
    text = type(text) == "table" and table.concat(text, " ") or nil
    if not text or not text:match("%S") then
        return nil
    end
    local sentences = {}
    for sentence in (text .. " "):gmatch("(.-[%.!?])%s+") do
        sentences[#sentences + 1] = sentence
    end
    if #sentences == 0 then
        sentences[1] = text
    end
    local name = label and ns.QuestState.removeKillWording((label:gsub(":.*$", ""):gsub("%d+/%d+", ""))):match("^%s*(.-)%s*$")
    if name and #name > 2 then
        for _, sentence in ipairs(sentences) do
            if sentence:lower():find(name:lower(), 1, true) then
                return sentence
            end
        end
    end
    return sentences[1]
end

---The dungeon one objective lies in: only when every place its creatures, objects or drops spawn is inside a
---dungeon. A creature found in a dungeon and outside it, or an item that drops from creatures all over the
---world (Sharp Claws, from wolves everywhere and from the worgs of Shadowfang Keep), can be had outside: the
---objective is not the dungeon's. Sources in several dungeons make it the filed dungeon's when that is one of
---them (Black Dragonspawn Eyes, from Blackrock Spire and Blackwing Lair, for a Blackrock Spire quest), else no one's.
---@param spawnLists table[] Each source's spawns, by zone
---@param filedDungeon table? The dungeon the quest is filed under: places at its entrances count as inside it
---@return number? dungeonZoneId
local function getSpawnsDungeonId(spawnLists, filedDungeon)
    local dungeonId, isOneDungeon, isFiledAmong = nil, true, false
    for _, spawns in ipairs(spawnLists) do
        for zoneId, points in pairs(type(spawns) == "table" and spawns or {}) do
            if not isContinentArea(zoneId) then
                local dungeon = getAreaDungeon(zoneId)
                if not dungeon and isAtDungeonMouth(zoneId, points, filedDungeon) then
                    dungeon = filedDungeon
                end
                if not dungeon then
                    return nil
                end
                isOneDungeon = isOneDungeon and (dungeonId == nil or dungeonId == dungeon.areaId)
                isFiledAmong = isFiledAmong or (filedDungeon ~= nil and filedDungeon.areaId == dungeon.areaId)
                dungeonId = dungeonId or dungeon.areaId
            end
        end
    end
    if isOneDungeon then
        return dungeonId
    end
    return isFiledAmong and filedDungeon.areaId or nil
end

---The dungeons a quest's work lies in, read from where its creatures and objects spawn: a quest filed under the
---zone outside can still have all its work inside. Each objective that can only be done in one dungeon adds
---that dungeon, so a quest with work in two (the Orb of Soran'ruk, in Blackfathom Deeps and Shadowfang Keep) is
---both's; for a quest filed under a dungeon, places at its entrances count as inside (the data often puts the
---instance's creatures there), and work with no known place is taken to be inside. Cheap enough to ask of every
---quest.
---@return number[] dungeonZoneIds
function Location.getObjectivesDungeonIds(questId)
    local function getNpcSpawns(npcId)
        return ns.Database.getNpcField(npcId, "spawns")
    end
    local function getObjectSpawns(objectId)
        return ns.Database.getObjectField(objectId, "spawns")
    end
    local objectives = ns.Database.getQuestField(questId, "objectives") or {}
    local spawnListsByObjective = {}
    for _, creature in ipairs(objectives[CREATURES] or {}) do
        spawnListsByObjective[#spawnListsByObjective + 1] = { getNpcSpawns(creature[1]) }
    end
    for _, killCredit in ipairs(objectives[KILL_CREDITS] or {}) do
        local spawnLists = {}
        for _, npcId in ipairs(killCredit[1] or {}) do
            spawnLists[#spawnLists + 1] = getNpcSpawns(npcId)
        end
        spawnListsByObjective[#spawnListsByObjective + 1] = spawnLists
    end
    for _, object in ipairs(objectives[OBJECTS] or {}) do
        spawnListsByObjective[#spawnListsByObjective + 1] = { getObjectSpawns(object[1]) }
    end
    for _, item in ipairs(objectives[ITEMS] or {}) do
        local spawnLists = {}
        for _, npcId in ipairs(ns.Database.getItemField(item[1], "npcDrops") or {}) do
            spawnLists[#spawnLists + 1] = getNpcSpawns(npcId)
        end
        for _, objectId in ipairs(ns.Database.getItemField(item[1], "objectDrops") or {}) do
            spawnLists[#spawnLists + 1] = getObjectSpawns(objectId)
        end
        spawnListsByObjective[#spawnListsByObjective + 1] = spawnLists
    end
    local triggerEnd = ns.Database.getQuestField(questId, "triggerEnd")
    if triggerEnd and triggerEnd[2] then
        spawnListsByObjective[#spawnListsByObjective + 1] = { triggerEnd[2] }
    end
    -- A quest filed under a dungeon: its places at the dungeon's entrances count as inside, and work whose places
    -- are all unknown (a boss's drop the data does not place) is taken to be inside
    local filedDungeon = ns.Database.getDungeon(ns.Database.getQuestField(questId, "zoneOrSort") or 0)
    local hasKnownPlace, dungeonIds, isListed = false, {}, {}
    for _, spawnLists in ipairs(spawnListsByObjective) do
        local dungeonId = getSpawnsDungeonId(spawnLists, filedDungeon)
        if dungeonId and not isListed[dungeonId] then
            isListed[dungeonId] = true
            dungeonIds[#dungeonIds + 1] = dungeonId
        end
        for _, spawns in ipairs(spawnLists) do
            hasKnownPlace = hasKnownPlace or (type(spawns) == "table" and next(spawns) ~= nil)
        end
    end
    if filedDungeon and #spawnListsByObjective > 0 and not hasKnownPlace then
        dungeonIds[1] = filedDungeon.areaId
    end
    return dungeonIds
end

---@return number? dungeonZoneId The first dungeon a quest's work lies in (Location.getObjectivesDungeonIds)
function Location.getObjectivesDungeonId(questId)
    return Location.getObjectivesDungeonIds(questId)[1]
end

local function getNpcSpawnLists(npcIds)
    local spawnLists = {}
    for _, npcId in ipairs(npcIds or {}) do
        spawnLists[#spawnLists + 1] = ns.Database.getNpcField(npcId, "spawns")
    end
    return spawnLists
end

local function getObjectSpawnLists(objectIds)
    local spawnLists = {}
    for _, objectId in ipairs(objectIds or {}) do
        spawnLists[#spawnLists + 1] = ns.Database.getObjectField(objectId, "spawns")
    end
    return spawnLists
end

---@return number? dungeonZoneId The dungeon a quest is picked up in: its givers all stand there, or the object or
---item that starts it is found only there (for a quest filed under a dungeon, an item dropped at its entrance
---counts, as work there does); or, for a quest filed under a dungeon, whatever starts it is placed nowhere (Elder
---Knowledge's Titan Relic, Open the Maw's Deathstalker Agent). nil when it is picked up outside
function Location.getPickupDungeonId(questId)
    local startedBy = ns.Database.getQuestField(questId, "startedBy") or {}
    local filedDungeon = ns.Database.getDungeon(ns.Database.getQuestField(questId, "zoneOrSort") or 0)
    local startItemLists = {}
    for _, itemId in ipairs(startedBy[3] or {}) do
        for _, spawns in ipairs(getNpcSpawnLists(ns.Database.getItemField(itemId, "npcDrops"))) do
            startItemLists[#startItemLists + 1] = spawns
        end
        for _, spawns in ipairs(getObjectSpawnLists(ns.Database.getItemField(itemId, "objectDrops"))) do
            startItemLists[#startItemLists + 1] = spawns
        end
    end
    local starterLists = { getNpcSpawnLists(startedBy[1]), getObjectSpawnLists(startedBy[2]), startItemLists }
    for index, spawnLists in ipairs(starterLists) do
        -- A giver at the entrance is not inside (Hamuul Runetotem); a creature there dropping the item is
        local dungeonId = #spawnLists > 0 and getSpawnsDungeonId(spawnLists, index == 3 and filedDungeon or nil) or nil
        if dungeonId then
            return dungeonId
        end
    end
    if not filedDungeon then
        return nil
    end
    local hasStarter = false
    for _, spawnLists in ipairs(starterLists) do
        for _, spawns in ipairs(spawnLists) do
            if type(spawns) == "table" and next(spawns) ~= nil then
                return nil
            end
            hasStarter = true
        end
    end
    hasStarter = hasStarter or #(startedBy[1] or {}) + #(startedBy[2] or {}) + #(startedBy[3] or {}) > 0
    return hasStarter and filedDungeon.areaId or nil
end

---The dungeons a quest is really done in: those its work lies in (Location.getObjectivesDungeonIds), the one it is
---picked up in (its giver stands there, or the item that starts it is found only there) and the one it is handed
---in in. Being filed under a dungeon is not enough: Forever files whole Undercity storylines under the Ruins of
---Lordaeron. Each check holds only when every place it names is inside the one dungeon.
---@return number[] dungeonZoneIds
function Location.getInsideDungeonIds(questId)
    local dungeonIds, isListed = {}, {}
    local function addDungeon(dungeonId)
        if dungeonId and not isListed[dungeonId] then
            isListed[dungeonId] = true
            dungeonIds[#dungeonIds + 1] = dungeonId
        end
    end
    for _, dungeonId in ipairs(Location.getObjectivesDungeonIds(questId)) do
        addDungeon(dungeonId)
    end
    addDungeon(Location.getPickupDungeonId(questId))
    local finishedBy = ns.Database.getQuestField(questId, "finishedBy") or {}
    for _, spawnLists in ipairs({ getNpcSpawnLists(finishedBy[1]), getObjectSpawnLists(finishedBy[2]) }) do
        if #spawnLists > 0 then
            addDungeon(getSpawnsDungeonId(spawnLists))
        end
    end
    return dungeonIds
end

---@return number? dungeonZoneId The first dungeon a quest is really done in (Location.getInsideDungeonIds)
function Location.getInsideDungeonId(questId)
    return Location.getInsideDungeonIds(questId)[1]
end


---The zone to list under: the player's zone when part of the step is there, else the zone with the most
---objectives left, then the most places, then the lowest ID so the result is stable. A dungeon quest lists
---under its dungeon while anything is left to do in there, unless more of it waits where the player stands.
---A quest that can be done in several zones and not where the player is lists under its home zone, the one
---the game files it under, so it has a steady place.
local function getStepZoneId(placeLists, playerZoneId, dungeonZoneId, homeZoneId)
    local objectiveCounts, placeCounts = {}, {}
    for _, places in ipairs(placeLists) do
        local seenZones = {}
        for _, place in ipairs(places) do
            local zoneId = place.groupZoneId
            placeCounts[zoneId] = (placeCounts[zoneId] or 0) + 1
            if not seenZones[zoneId] then
                seenZones[zoneId] = true
                objectiveCounts[zoneId] = (objectiveCounts[zoneId] or 0) + 1
            end
        end
    end
    local hasDungeonWork = dungeonZoneId ~= nil and objectiveCounts[dungeonZoneId] ~= nil
    if playerZoneId and placeCounts[playerZoneId]
        and not (hasDungeonWork and objectiveCounts[dungeonZoneId] >= objectiveCounts[playerZoneId]) then
        return playerZoneId
    end
    if hasDungeonWork then
        return dungeonZoneId
    end
    if homeZoneId and objectiveCounts[homeZoneId] then
        return homeZoneId
    end
    local bestZoneId
    for zoneId, objectiveCount in pairs(objectiveCounts) do
        local bestObjectiveCount, bestPlaceCount = objectiveCounts[bestZoneId] or -1, placeCounts[bestZoneId] or -1
        if objectiveCount > bestObjectiveCount
            or (objectiveCount == bestObjectiveCount and placeCounts[zoneId] > bestPlaceCount)
            or (objectiveCount == bestObjectiveCount and placeCounts[zoneId] == bestPlaceCount and zoneId < bestZoneId) then
            bestZoneId = zoneId
        end
    end
    return bestZoneId
end

---@class QuestStep
---@field zoneId number Zone to list the quest under, UNKNOWN_ZONE_ID when nothing is known
---@field places table[] Places of the step inside that zone
---@field isTurnIn boolean The quest is done and only has to be handed in
---@field finisherName string? Who to hand it in to
---@field unlocatedCount number Unfinished objectives the database has no place for
---@field isEvent boolean? The quest has no objectives: something happens at its NPC, such as waiting for them
---@field allPlaces table[]? Places of the step in every zone, when it can be done in more than the one listed
---@field otherZoneIds number[]? The other zones the step can be done in

---@param quest { questId: number, isComplete: boolean, objectives: table[] } State from the quest log
---@param playerZoneId number?
---@return QuestStep
function Location.composeStep(quest, playerZoneId)
    local placeLists = {}
    local finisherPlaces, finisherName = Location.getFinisherPlaces(quest.questId)

    local unlocatedCount = 0
    if not quest.isComplete then
        local typeIndexes = {}
        for _, objective in ipairs(quest.objectives) do
            typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
            if not objective.isFinished then
                local places = Location.getObjectivePlaces(quest.questId, objective.type, typeIndexes[objective.type])
                local glyph = ns.QuestState.getObjectiveGlyph(objective)
                for _, place in ipairs(places) do
                    place.glyph = place.glyph or glyph -- what to do there, for the minimap's icons
                end
                if #places > 0 then
                    placeLists[#placeLists + 1] = places
                else
                    unlocatedCount = unlocatedCount + 1 -- the database does not say where this is
                end
            end
        end
    end

    local isTurnIn = quest.isComplete
    if not isTurnIn and #quest.objectives == 0 then
        -- Nothing to kill or collect: the quest happens where its NPC is, as waiting while Scooty calibrates
        -- the transponder in Booty Bay does, though the quest belongs to Gnomeregan
        local zoneId = getStepZoneId({ finisherPlaces }, playerZoneId)
        return {
            zoneId = zoneId or UNKNOWN_ZONE_ID, places = Location.getPlacesInZone(finisherPlaces, zoneId), isTurnIn = false,
            finisherName = finisherName, unlocatedCount = 0, isEvent = true,
        }
    end
    if #placeLists == 0 then
        local questZoneId = ns.Database.getQuestField(quest.questId, "zoneOrSort") or 0
        local dungeonPlaces = {}
        if not isTurnIn and addDungeonEntrances(dungeonPlaces, questZoneId) then
            -- A dungeon quest whose objectives have no recorded place: they are inside, so the way in is the place
            return { zoneId = dungeonPlaces[1].groupZoneId, places = dungeonPlaces, isTurnIn = false, finisherName = finisherName, unlocatedCount = 0 }
        end
        if not isTurnIn and questZoneId > 0 then
            -- An unfinished quest whose objectives have no known place stays in its own zone
            -- (a learned dungeon whose way in is not known yet has no zone above it: it is the group itself)
            return { zoneId = ns.Database.getParentZoneId(questZoneId) or questZoneId, places = {}, isTurnIn = false, finisherName = finisherName, unlocatedCount = unlocatedCount }
        end
        if not isTurnIn then
            -- One filed under a category (a profession, a class), its objectives nowhere to go (items to make or buy):
            -- listed under the zone of whom it is handed in to, but marked nowhere until it is ready to hand in
            local zoneId = getStepZoneId({ finisherPlaces }, playerZoneId)
            return { zoneId = zoneId or UNKNOWN_ZONE_ID, places = {}, isTurnIn = false, finisherName = finisherName, unlocatedCount = unlocatedCount }
        end
        placeLists[1] = finisherPlaces
    end

    local dungeonZoneId = not isTurnIn and Location.getQuestDungeonId(quest.questId, placeLists) or nil
    local questZoneId = ns.Database.getQuestField(quest.questId, "zoneOrSort") or 0
    local homeZoneId = questZoneId > 0 and ns.Database.getParentZoneId(questZoneId) or nil
    local zoneId = getStepZoneId(placeLists, playerZoneId, dungeonZoneId, homeZoneId)
    if not zoneId then
        -- Nowhere known to go (whom it is handed in to is not in the database): listed under the quest's own zone, as
        -- an unfinished one is, not under "Unknown location"
        zoneId = homeZoneId
    end
    local places, allPlaces, otherZoneIds, isOtherZone = {}, {}, {}, {}
    for _, placeList in ipairs(placeLists) do
        for _, place in ipairs(placeList) do
            allPlaces[#allPlaces + 1] = place
            if place.groupZoneId == zoneId then
                places[#places + 1] = place
            elseif not isOtherZone[place.groupZoneId] then
                isOtherZone[place.groupZoneId] = true
                otherZoneIds[#otherZoneIds + 1] = place.groupZoneId
            end
        end
    end
    table.sort(otherZoneIds, function(first, second)
        return ns.Database.getZoneName(first) < ns.Database.getZoneName(second)
    end)
    return {
        zoneId = zoneId or UNKNOWN_ZONE_ID, places = places, isTurnIn = isTurnIn, finisherName = finisherName,
        unlocatedCount = unlocatedCount, allPlaces = allPlaces, otherZoneIds = otherZoneIds,
    }
end

---Who or what starts a quest.
---@return table[] places
---@return string? starterName
---@return string? startType "npc" or "object"; nil when the quest starts from an item or nothing known
function Location.getStarterPlaces(questId)
    local places, starterName, startType = {}, nil, nil
    local startedBy = ns.Database.getQuestField(questId, "startedBy") or {}
    for _, npcId in ipairs(startedBy[1] or {}) do
        -- A quest giver of the other faction will not talk to the player, so it does not count
        if ns.Database.isNpcFriendly(npcId) then
            addNpcPlaces(places, npcId)
            starterName = starterName or ns.Database.getNpcField(npcId, "name")
            startType = startType or "npc"
        end
    end
    for _, objectId in ipairs(startedBy[2] or {}) do
        addObjectPlaces(places, objectId)
        starterName = starterName or ns.Database.getObjectField(objectId, "name")
        startType = startType or "object"
    end
    return leaveOutHostileTowns(places), starterName, startType
end

local MAX_ITEM_SOURCES = 15 -- an item with more kinds of source than this drops all over the world

---The item that starts a quest and where it comes from. An item that drops from creatures all over the world
---comes from nowhere in particular: it has no places and no named source.
---@return { itemId: number, itemName: string, sourceName: string?, places: table[], isWorldDrop: boolean }? source nil when no item starts the quest
function Location.getStartItemSource(questId)
    local startedBy = ns.Database.getQuestField(questId, "startedBy") or {}
    local itemId = (startedBy[3] or {})[1]
    if not itemId then
        return nil
    end
    local itemName = ns.Database.getItemField(itemId, "name") or ns.L("an item")
    local npcIds, objectIds = ns.Database.getItemField(itemId, "npcDrops") or {}, ns.Database.getItemField(itemId, "objectDrops") or {}
    if #npcIds + #objectIds > MAX_ITEM_SOURCES then
        return { itemId = itemId, itemName = itemName, places = {}, isWorldDrop = true }
    end
    local places = {}
    addItemPlaces(places, itemId)
    local npcId, objectId = npcIds[1], objectIds[1]
    local sourceName = npcId and ns.Database.getNpcField(npcId, "name") or objectId and ns.Database.getObjectField(objectId, "name") or nil
    return { itemId = itemId, itemName = itemName, sourceName = sourceName, places = places, isWorldDrop = false }
end

---@return table[] places The places that lie in the zone, a dungeon's entrance counting for the dungeon and
---for the zone it stands in
function Location.getPlacesInZone(places, zoneId)
    local zonePlaces = {}
    for _, place in ipairs(places) do
        if place.groupZoneId == zoneId or place.mapZoneId == zoneId then
            zonePlaces[#zonePlaces + 1] = place
        end
    end
    return zonePlaces
end

---Where one quest log objective is found, and in words what it comes from when that is not the objective
---itself: "Drops from ...", "Found in ...", "Sold by ...", or for an item players make, how to get it.
---@param label string? The objective as the game names it ("Lesser Troll's Blood Elixir"): finds the item by its
---name when the database's quest does not list it (a quest the game has changed since)
---@return table[] places
---@return string? sourceText
---@return boolean isCrafted The item is one players make, so it has no place on the map
---@param stillNeeded number? How many the objective still asks for: what a crafted item's price is for
function Location.getObjectiveInfo(questId, objectiveType, typeIndex, label, stillNeeded)
    local places = Location.getObjectivePlaces(questId, objectiveType, typeIndex)
    if objectiveType ~= "item" then
        return places, nil, false
    end
    local objectives = ns.Database.getQuestField(questId, "objectives") or {}
    local item = (objectives[ITEMS] or {})[typeIndex]
    local itemId = item and item[1] or ns.Database.getItemIdByName(label)
    if not itemId then
        return places, nil, false
    end
    local huntedSource = ns.Drops.getHuntedSource(itemId)
    local npcId = (ns.Database.getItemField(itemId, "npcDrops") or {})[1]
    local objectId = (ns.Database.getItemField(itemId, "objectDrops") or {})[1]
    local vendorId = (ns.Database.getItemField(itemId, "vendors") or {})[1]
    if huntedSource then
        return places, ns.L("Drops from %s", huntedSource.name)
    elseif npcId and ns.Database.getNpcField(npcId, "name") then
        return places, ns.L("Drops from %s", ns.Database.getNpcField(npcId, "name"))
    elseif objectId and ns.Database.getObjectField(objectId, "name") then
        return places, ns.L("Found in %s", ns.Database.getObjectField(objectId, "name"))
    elseif vendorId and ns.Database.getNpcField(vendorId, "name") then
        return places, ns.L("Sold by %s", ns.Database.getNpcField(vendorId, "name"))
    end
    -- Nowhere in the world: one players make says how to get it
    local craftedText = ns.Crafting.describe(itemId, stillNeeded)
    if craftedText then
        return places, craftedText, true
    end
    return places, nil, false
end
