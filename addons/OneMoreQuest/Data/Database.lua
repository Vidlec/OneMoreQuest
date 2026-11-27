local _, ns = ...

-- Thin layer over the QuestieDB addon (global LibQuestieDB). Its getters return nil for unknown IDs, 0 for
-- missing numbers and nil for empty tables, except quest startedBy, finishedBy and objectives.
local Database = {}
ns.Database = Database

local zoneMaps

function Database.isAvailable()
    return type(LibQuestieDB) == "table" and LibQuestieDB.Quest ~= nil
end

-- The QuestieDB contract OneMoreQuest is written against: 4 brings the race and class masks it filters quests by
-- (Enum.raceMaskById, Enum.classKeys)
local CONTRACT = 4

---@return boolean isSupported The installed QuestieDB supports the contract OneMoreQuest needs
---@return string? problem Why not, in QuestieDB's own words
function Database.checkContract()
    if not Database.isAvailable() or type(LibQuestieDB.RequireContract) ~= "function" then
        return false, "QuestieDB is missing or too old"
    end
    local isSupported, problem = LibQuestieDB.RequireContract(CONTRACT)
    return isSupported == true, problem
end

---@return string? notice QuestieDB's own words when it reads its raw source data (slower, for development); nil
---for the built data it ships with. Its documentation asks addons to show this where players will see it.
function Database.getReadModeNotice()
    if not Database.isAvailable() or LibQuestieDB.readMode ~= "source" then
        return nil
    end
    local indicator = LibQuestieDB.ModeIndicator
    local text = indicator and type(indicator.GetText) == "function" and indicator.GetText()
    return type(text) == "string" and text or "QuestieDB: SOURCE MODE"
end

-- What was read of QuestieDB, kept. QuestieDB decodes a fresh table at every read of a table field (a creature's
-- spawns, a quest's objectives, its givers), so that a caller may change what it gets; and the lists, the map, the
-- minimap and the tracker read the same fields of the same quests and creatures over and over: a drawing of the map
-- read some 5,000 fields, a thousand of them tables, of which two thirds had been read moments before. Each was a
-- call into QuestieDB, a decode and a table for the garbage collector, whose work then came as hitches of its own.
-- Kept here they are read once. What is kept is shared: NOT TO BE CHANGED by a caller (copy first).
--
-- Two generations bound it: a value read goes in the young one; when that is full it becomes the old one and a new
-- young one starts, so what has not been read for a while goes, and what is read again moves back to the young.
-- (Reading the whole database, as the indexes built after login do, passes through without keeping it all.)
--
-- Kept only once frames run (ns.frameNumber): in the tests, where none do, every read is fresh, so a test may swap
-- the database under the addon, which no session can.
local CACHE_GENERATION_SIZE = 6000 -- values in a generation; twice this many are kept at most
Database.CACHE_GENERATION_SIZE = CACHE_GENERATION_SIZE
local NOTHING = {} -- stands for "the database has no value" in the cache
local youngCache, oldCache, youngCount = {}, {}, 0

local function getCached(cache, entity, field, id)
    local byField = cache[entity]
    local byId = byField and byField[field]
    if byId then
        return byId[id]
    end
    return nil
end

local function keep(entity, field, id, value)
    if youngCount >= CACHE_GENERATION_SIZE then
        oldCache, youngCache, youngCount = youngCache, {}, 0
    end
    local byField = youngCache[entity]
    if not byField then
        byField = {}
        youngCache[entity] = byField
    end
    local byId = byField[field]
    if not byId then
        byId = {}
        byField[field] = byId
    end
    byId[id] = value
    youngCount = youngCount + 1
end

---Forgets everything read of QuestieDB (for tests, and should its data ever change in a session).
function Database.forgetReads()
    youngCache, oldCache, youngCount = {}, {}, 0
end

---@return any value QuestieDB's own, read afresh: for what must not be kept (a pass over every creature) and for
---checking what is kept against it
local function readField(entity, id, field)
    if not Database.isAvailable() then
        return nil
    end
    return LibQuestieDB[entity].Get(id, field)
end

local isPassingThrough = false -- a pass over the whole database is under way (Database.passThrough): nothing new is kept

local function getField(entity, id, field)
    if id == nil or field == nil or ns.frameNumber == 0 then
        return readField(entity, id, field)
    end
    local value = getCached(youngCache, entity, field, id)
    if value == nil then
        value = getCached(oldCache, entity, field, id)
        if value == nil then
            if not Database.isAvailable() then
                return nil -- not kept: the database may yet come
            end
            value = LibQuestieDB[entity].Get(id, field)
            if value == nil then
                value = NOTHING
            end
        end
        if not isPassingThrough then
            keep(entity, field, id, value) -- read anew, or read again from the old generation: young now
        end
    end
    if value == NOTHING then
        return nil
    end
    return value
end

---Runs work that reads through the whole database (who can pick up every quest, worked out in the background)
---without keeping what it reads: kept, tens of thousands of values would push out, several times over, what the
---map and the lists read all the time, and leave it all to the collector.
function Database.passThrough(work, ...)
    local wasPassing = isPassingThrough
    isPassingThrough = true
    local isFine, problem = pcall(work, ...)
    isPassingThrough = wasPassing
    if not isFine then
        error(problem, 0)
    end
end

---Checks what is kept against QuestieDB itself: a kept table some caller changed would differ from a fresh read.
---For the tests and the simulator; it reads everything kept again.
---@return string[] problems One line for each kept value that is no longer what the database says
function Database.verifyReads()
    local problems = {}
    local function isSame(first, second, depth)
        if type(first) ~= type(second) then
            return false
        end
        if type(first) ~= "table" then
            return first == second
        end
        if depth > 8 then
            return true
        end
        for key, value in pairs(first) do
            if not isSame(value, second[key], depth + 1) then
                return false
            end
        end
        for key in pairs(second) do
            if first[key] == nil then
                return false
            end
        end
        return true
    end
    for _, cache in ipairs({ youngCache, oldCache }) do
        for entity, byField in pairs(cache) do
            for field, byId in pairs(byField) do
                for id, kept in pairs(byId) do
                    local fresh = readField(entity, id, field)
                    if kept == NOTHING then
                        kept = nil
                    end
                    if not isSame(kept, fresh, 0) then
                        problems[#problems + 1] = string.format("%s %s.%s", entity, tostring(id), tostring(field))
                    end
                end
            end
        end
    end
    return problems
end

-- Quest providers: where quest data comes from, asked in order (QuestieDB first, then the DungeonJournal addon,
-- then what OneMoreQuest learned by playing; more can come). Each field trickles down: the first provider with a
-- real answer gives it. The quests are QuestieDB's: the others fill in what it leaves out for a quest it knows (a
-- Forever quest it files nowhere), so a quest QuestieDB lacks stays a missed quest, reported to its makers.
---@class QuestProvider
---@field name string
---@field order number Lower is asked first
---@field getQuestField (fun(questId: number, field: string): any)? Only the fields it knows; nil for the rest
---@field questFields table<string, boolean>? The fields getQuestField may answer; with it, it is asked for those alone
---@field getDungeons (fun(): ProvidedDungeon[])? The dungeons it knows
---@field isAvailable (fun(): boolean)? Whether it can answer now (its addon is loaded)

---@class ProvidedDungeon
---@field name string As the game names the instance
---@field areaId number? Its own ID; without one it takes the ID of the dungeon of that name another provider gave,
---or one made from its name
---@field otherAreaIds number[]? Other area IDs of the same instance (wings, the ID its quests are filed under)
---@field entrances { zoneId: number, x: number, y: number }[]?
---@field isRaid boolean?
---@field isLearned boolean? Not QuestieDB's (shown as such, and its instance is not one QuestieDB knows)

local providers = {} ---@type QuestProvider[]

---@param provider QuestProvider
function Database.registerProvider(provider)
    providers[#providers + 1] = provider
    table.sort(providers, function(first, second)
        return first.order < second.order
    end)
    Database.forgetDungeons()
end

-- Whether each provider can answer, looked up once a frame (ns.frameNumber): a field QuestieDB leaves empty asks
-- every provider, tens of thousands of times as a list is worked out, and "is that addon loaded" is a call into the
-- game each time.
local providerAvailability, providerAvailabilityFrame = {}, nil

local function isProviderAvailable(provider)
    if not provider.isAvailable then
        return true
    end
    local frameNumber = ns.frameNumber
    if frameNumber > 0 and providerAvailabilityFrame == frameNumber then
        local known = providerAvailability[provider]
        if known ~= nil then
            return known
        end
    elseif providerAvailabilityFrame ~= frameNumber then
        providerAvailability, providerAvailabilityFrame = {}, frameNumber
    end
    local isFine, isAvailable = pcall(provider.isAvailable)
    local result = isFine and isAvailable == true
    providerAvailability[provider] = result
    return result
end

---@return string key Which sources of quest data answer now: QuestieDB, and each other addon that adds to it (one
---may load in the middle of a session). Another key: what was worked out from the database is worked out again.
function Database.getProvidersKey()
    local parts = { Database.isAvailable() and "1" or "0" }
    for index, provider in ipairs(providers) do
        parts[index + 1] = isProviderAvailable(provider) and "1" or "0"
    end
    return table.concat(parts)
end

---@return boolean canAnswer The provider may know this field of a quest (one that lists its fields is asked for
---those alone)
local function canProvideQuestField(provider, field)
    return provider.getQuestField ~= nil and (provider.questFields == nil or provider.questFields[field] == true)
end

local function isEmpty(value)
    return value == nil or value == 0 or value == "" or (type(value) == "table" and next(value) == nil)
end

function Database.getQuestField(questId, field)
    local value = getField("Quest", questId, field)
    if not isEmpty(value) or #providers == 0 then
        return value
    end
    -- Only the providers that may know the field are asked (most fields none does: nothing more to look up)
    local isAnyAble = false
    for index = 1, #providers do
        if canProvideQuestField(providers[index], field) then
            isAnyAble = true
            break
        end
    end
    if not isAnyAble then
        return value
    end
    if (field == "name" and value == nil) or (field ~= "name" and getField("Quest", questId, "name") == nil) then
        return value -- a quest QuestieDB does not have at all stays unknown (see above)
    end
    for _, provider in ipairs(providers) do
        if canProvideQuestField(provider, field) and isProviderAvailable(provider) then
            local isFine, provided = pcall(provider.getQuestField, questId, field)
            if isFine and not isEmpty(provided) then
                return provided
            end
        end
    end
    return value -- QuestieDB's own empty value (0, an empty table), as callers expect it
end

---@return any value What one provider alone says (the missed-quest report asks QuestieDB itself)
function Database.getQuestFieldFrom(providerName, questId, field)
    if providerName == "QuestieDB" then
        return getField("Quest", questId, field)
    end
    for _, provider in ipairs(providers) do
        if provider.name == providerName and provider.getQuestField and isProviderAvailable(provider) then
            local isFine, provided = pcall(provider.getQuestField, questId, field)
            return isFine and provided or nil
        end
    end
    return nil
end

---A creature's field: QuestieDB's, else the first provider's that has it (Forever's own quest givers QuestieDB lacks,
---such as the Deathstalker Agent outside the Excavation Site, whose place the journal records)
function Database.getNpcField(npcId, field)
    local value = getField("Npc", npcId, field)
    if not isEmpty(value) or #providers == 0 then
        return value
    end
    for _, provider in ipairs(providers) do
        if provider.getNpcField and isProviderAvailable(provider) then
            local isFine, provided = pcall(provider.getNpcField, npcId, field)
            if isFine and not isEmpty(provided) then
                return provided
            end
        end
    end
    return value
end

function Database.getObjectField(objectId, field)
    return getField("Object", objectId, field)
end

function Database.getItemField(itemId, field)
    return getField("Item", itemId, field)
end

---@return string version QuestieDB's version, from its TOC ("?" when it does not say)
function Database.getVersion()
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return getMetadata and getMetadata("QuestieDB", "Version") or "?"
end

---@return number? npcId The creature a unit's identifier names; nil for players, pets and objects
function Database.getNpcId(guid)
    -- (in an instance the game hands addons a creature's identifier as a secret value: it cannot be read, so no
    -- creature is named; Razorfen Downs' quest givers broke the data check on it)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
        return nil
    end
    local unitType, npcId = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil
    end
    return tonumber(npcId)
end

-- The capitals of each faction, where the other faction's characters cannot go about their business
local CAPITALS_BY_FACTION = {
    Alliance = { [1519] = true, [1537] = true, [1657] = true, [3557] = true }, -- Stormwind, Ironforge, Darnassus, the Exodar
    Horde = { [1637] = true, [1638] = true, [1497] = true, [3487] = true }, -- Orgrimmar, Thunder Bluff, Undercity, Silvermoon
}

---@return boolean isCapital The area is one of the faction capitals
function Database.isCapital(areaId)
    return CAPITALS_BY_FACTION.Alliance[areaId] == true or CAPITALS_BY_FACTION.Horde[areaId] == true
end

---@return boolean isOutOfReach The creature stands only in the other faction's capitals
local function isOnlyInHostileCapitals(npcId, playerFaction)
    local hostileCapitals =
        CAPITALS_BY_FACTION[playerFaction == "Horde" and "Alliance" or playerFaction == "Alliance" and "Horde" or ""]
    local spawns = hostileCapitals and getField("Npc", npcId, "spawns")
    if type(spawns) ~= "table" or next(spawns) == nil then
        return false
    end
    for zoneId in pairs(spawns) do
        if not hostileCapitals[zoneId] and not hostileCapitals[Database.getParentZoneId(zoneId) or 0] then
            return false
        end
    end
    return true
end

-- The other faction's towns (Southshore, Dalaran, Astranaar...), found from the database itself: where many people
-- friendly to one faction only stand together. Each zone's map in patches of TOWN_CELL percent across; a place is in a
-- faction's town when the patches round it hold at least TOWN_MIN_PEOPLE of that faction's people and TOWN_MAJORITY
-- times as many as of the other's (a camp of the player's own side among them is not the other's town).
local TOWN_CELL, TOWN_MIN_PEOPLE, TOWN_MAJORITY = 5, 8, 3
local townCells -- [zoneId][column .. ":" .. row] = { A = people, H = people }, built on first use

local function buildTownCells()
    if not Database.isAvailable() or type(LibQuestieDB.Npc.GetAllIds) ~= "function" then
        return -- (none kept: built once the database is there)
    end
    townCells = {}
    for _, npcId in ipairs(LibQuestieDB.Npc.GetAllIds()) do
        local faction = readField("Npc", npcId, "friendlyToFaction") -- read afresh: every creature passes, none to keep
        if faction == "A" or faction == "H" then
            for zoneId, points in pairs(readField("Npc", npcId, "spawns") or {}) do
                local cells = townCells[zoneId] or {}
                townCells[zoneId] = cells
                local counted = {} -- one person counts once in a patch, however many of their spots fall in it
                for _, point in ipairs(points) do
                    if point[1] >= 0 then
                        local key = math.floor(point[1] / TOWN_CELL) .. ":" .. math.floor(point[2] / TOWN_CELL)
                        if not counted[key] then
                            counted[key] = true
                            cells[key] = cells[key] or { A = 0, H = 0 }
                            cells[key][faction] = cells[key][faction] + 1
                        end
                    end
                end
            end
        end
    end
end

---@param zoneId number The zone the place's coordinates are on (as the database records spawns)
---@param x number 0 to 100
---@param y number 0 to 100
---@return boolean isHostile The place stands in a town of the faction the player is not
function Database.isInHostileTown(zoneId, x, y)
    local playerFaction = Database.getPlayerFaction()
    local hostile = playerFaction == "Horde" and "A" or playerFaction == "Alliance" and "H" or nil
    if not hostile or not zoneId or not x or x < 0 then
        return false
    end
    if not townCells then
        buildTownCells()
    end
    local cells = townCells and townCells[zoneId]
    if not cells then
        return false
    end
    local own = hostile == "A" and "H" or "A"
    local column, row = math.floor(x / TOWN_CELL), math.floor(y / TOWN_CELL)
    local hostileCount, ownCount = 0, 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cell = cells[(column + dx) .. ":" .. (row + dy)]
            if cell then
                hostileCount, ownCount = hostileCount + cell[hostile], ownCount + cell[own]
            end
        end
    end
    return hostileCount >= TOWN_MIN_PEOPLE and hostileCount >= TOWN_MAJORITY * ownCount
end

---Whether a creature will deal with the player's faction. The database marks creatures as friendly to the
---Alliance ("A"), the Horde ("H") or both ("AH"); unmarked ones are taken as friendly. One friendly to both that
---stands only in the other faction's capitals is out of reach all the same: an Argent Dawn officer in Darnassus
---is no use to the Horde.
function Database.isNpcFriendly(npcId)
    local friendlyTo = getField("Npc", npcId, "friendlyToFaction")
    local playerFaction = Database.getPlayerFaction()
    if playerFaction == "Alliance" and friendlyTo == "H" or playerFaction == "Horde" and friendlyTo == "A" then
        return false
    end
    -- Not one standing only in the other side's towns: a prisoner in an enemy fort (Gilthares in Northwatch Hold) or a
    -- farm full of the other side's people (Stanley in Hillsbrad Fields) is just where a quest sends the player. Only a
    -- town spot among others is left out, where a quest's places are listed (Location)
    return not isOnlyInHostileCapitals(npcId, playerFaction)
end

local getZoneMaps -- defined with the zone tables below
local dungeonsByAreaId, dungeonsByName

-- A dungeon a provider gives no ID of its own takes one made from its name, past any area ID the game uses, the
-- same every session (collapsed groups are kept by ID)
local NAMED_ID_BASE, NAMED_ID_SPAN = 1500000, 400000
local function getNamedAreaId(name)
    local hash = 5381
    for index = 1, #name do
        hash = (hash * 33 + name:byte(index)) % 2147483647
    end
    return NAMED_ID_BASE + hash % NAMED_ID_SPAN
end

---@return table[] dungeons What a provider gives as its dungeons (nothing when it is not there, or fails)
local function readProviderDungeons(provider)
    if not provider.getDungeons or not isProviderAvailable(provider) then
        return {}
    end
    local isFine, list = pcall(provider.getDungeons)
    return isFine and type(list) == "table" and list or {}
end

---@return table? provided A provider's dungeon fit to merge: one without a name is passed by, a broken way in
---dropped (from a damaged saved record or another addon)
local function checkProvided(provided)
    if type(provided) ~= "table" or type(provided.name) ~= "string" then
        return nil
    end
    if provided.entrances ~= nil and type(provided.entrances) ~= "table" then
        provided.entrances = nil
    end
    return provided
end

---Another provider's dungeon of a name already known fills in what the known one lacks: its way in, when unknown,
---and its own ID (a learned instance's ID leads to it as well).
local function mergeIntoExisting(existing, provided)
    if #existing.entrances == 0 and provided.entrances and #provided.entrances > 0 then
        existing.entrances = provided.entrances
    end
    if provided.areaId and not dungeonsByAreaId[provided.areaId] then
        dungeonsByAreaId[provided.areaId] = existing
    end
end

---@return table dungeon A provider's dungeon added as one of its own, by its ID and its name
local function addDungeon(provided)
    local areaId = provided.areaId or getNamedAreaId(provided.name)
    local dungeon = {
        areaId = areaId,
        name = provided.name,
        entrances = provided.entrances or {},
        isRaid = provided.isRaid == true,
        isLearned = provided.isLearned == true or nil,
    }
    dungeonsByAreaId[areaId] = dungeonsByAreaId[areaId] or dungeon
    -- Several entries can share a name (the wings of Dire Maul); the lowest ID keeps the answer stable
    local named = dungeonsByName[provided.name]
    if not named or areaId < named.areaId then
        dungeonsByName[provided.name] = dungeon
    end
    return dungeon
end

---Every provider's dungeons in one table. QuestieDB's keep their own IDs (each wing too); another provider's
---dungeon is the one of the same name if there is one (its way in filled in when unknown), else a dungeon of its own.
local function buildDungeons()
    dungeonsByAreaId, dungeonsByName = {}, {}
    for _, provider in ipairs(providers) do
        local others = {}
        for _, listed in ipairs(readProviderDungeons(provider)) do
            local provided = checkProvided(listed)
            local existing = provided and not provider.isPrimary and dungeonsByName[provided.name]
            if existing then
                mergeIntoExisting(existing, provided)
            elseif provided then
                others[#others + 1] = { addDungeon(provided), provided.otherAreaIds }
            end
        end
        -- The other IDs come second, so an ID that is a dungeon of its own is never taken over
        for _, pair in ipairs(others) do
            for _, otherAreaId in ipairs(pair[2] or {}) do
                dungeonsByAreaId[otherAreaId] = dungeonsByAreaId[otherAreaId] or pair[1]
            end
        end
    end
end

local dungeonsVersion = 0 -- raised whenever the dungeons are forgotten (Database.getDungeonsVersion)
local dungeonsProvidersKey, dungeonsCheckedFrame -- which providers answered when they were merged; the frame that last checked

---Forgets the merged dungeons: a provider came or its dungeons changed (one learned by playing).
function Database.forgetDungeons()
    dungeonsByAreaId, dungeonsByName = nil, nil
    dungeonsVersion = dungeonsVersion + 1
end

---@return number version Changes whenever the dungeons or their ways in may have: what was worked out from them (the
---places of creatures inside, at the entrances) is worked out again
function Database.getDungeonsVersion()
    return dungeonsVersion
end

---The dungeon or raid an area inside an instance belongs to, with its entrances in the open world. One
---instance goes by several area IDs (its wings, and the ID its quests are filed under); they all give the
---same dungeon, whose areaId is the one to group by.
---@return { areaId: number, name: string, entrances: { zoneId: number, x: number, y: number }[], isLearned: boolean? }? dungeon
function Database.getDungeon(areaId)
    -- A provider that answers now and did not when they were merged (an addon loaded on demand, the saved records once
    -- the settings are there): merged again. Looked at once a frame; in the tests, where no frames run, every time
    if dungeonsByAreaId and (ns.frameNumber == 0 or dungeonsCheckedFrame ~= ns.frameNumber) then
        dungeonsCheckedFrame = ns.frameNumber
        if Database.getProvidersKey() ~= dungeonsProvidersKey then
            Database.forgetDungeons()
        end
    end
    if not dungeonsByAreaId then
        if not Database.isAvailable() then
            return nil -- built once the quest database is there
        end
        buildDungeons()
        dungeonsProvidersKey, dungeonsCheckedFrame = Database.getProvidersKey(), ns.frameNumber
    end
    if not areaId then
        return nil
    end
    -- An area inside a dungeon (a wing, a cave) belongs to it as well. A wing the database also lists as a
    -- dungeon of its own (Dire Maul's North, West and East) is the dungeon it lies in: one Dire Maul, not three
    local parentAreaId = getZoneMaps().parentZoneIdByAreaId[areaId]
    return (parentAreaId and dungeonsByAreaId[parentAreaId]) or dungeonsByAreaId[areaId] or nil
end

---@return table[] dungeons Every dungeon and raid known, each once (Database.getDungeon's)
function Database.getDungeons()
    Database.getDungeon(0) -- builds the table
    local dungeons, isListed = {}, {}
    for _, dungeon in pairs(dungeonsByAreaId or {}) do
        if not isListed[dungeon] then
            isListed[dungeon] = true
            dungeons[#dungeons + 1] = dungeon
        end
    end
    return dungeons
end

-- QuestieDB's dungeons, the first provider of them
Database.registerProvider({
    name = "QuestieDB",
    order = 10,
    isPrimary = true,
    isAvailable = Database.isAvailable,
    getDungeons = function()
        local support = LibQuestieDB.Support and LibQuestieDB.Support.Get("ZoneDB")
        local dungeons = support and support.private and support.private.dungeons
        local list = {}
        -- Each entry is { name, other area IDs of the same instance, parent zone, { { area, x, y }, ... } }
        for dungeonAreaId, entry in pairs(type(dungeons) == "table" and dungeons or {}) do
            local entrances = {}
            for _, location in ipairs(entry[4] or {}) do
                entrances[#entrances + 1] = { zoneId = location[1], x = location[2], y = location[3] }
            end
            list[#list + 1] =
                { areaId = dungeonAreaId, name = entry[1], entrances = entrances, otherAreaIds = entry[2] }
        end
        return list
    end,
})

---@return number? areaId The known dungeon behind the game's number for an instance; nil for one the quest
---database does not know
function Database.getKnownInstanceDungeonId(instanceId)
    local support = Database.isAvailable() and LibQuestieDB.Support and LibQuestieDB.Support.Get("ZoneDB")
    local areaIds = support and (support.instanceIdToAreaId or (support.private and support.private.instanceIdToAreaId))
    local areaId = type(areaIds) == "table" and instanceId and areaIds[instanceId]
    local dungeon = areaId and Database.getDungeon(areaId)
    return dungeon and not dungeon.isLearned and dungeon.areaId or nil
end

---The dungeon the player is inside, from the game's own number for the instance.
---@return number? areaId The dungeon's area, nil outside a dungeon or when the instance is not known
function Database.getInstanceDungeonId()
    if not (IsInInstance and IsInInstance()) or not GetInstanceInfo then
        return nil
    end
    local instanceId = select(8, GetInstanceInfo())
    local knownAreaId = instanceId and Database.getKnownInstanceDungeonId(instanceId)
    if knownAreaId then
        return knownAreaId
    end
    local learnedAreaId = instanceId and ns.LearnedDungeons and ns.LearnedDungeons.getAreaId(instanceId)
    return learnedAreaId and Database.getDungeon(learnedAreaId) and learnedAreaId or nil
end

---The dungeon the game calls by this name, for when the game says where the player is only in words.
---@return table? dungeon
function Database.getDungeonByName(name)
    Database.getDungeon(0) -- builds the table
    return name and dungeonsByName and dungeonsByName[name] or nil
end

---@return number? experience What turning the quest in gives at the level it was designed for
---The game pays less experience for a quest the further the character has outlevelled it: full up to five
---levels above the quest, then a fifth less per level, down to a tenth. The amount is then rounded to the
---steps the game uses. The rule is the one Questie uses, taken from the CMaNGOS server.
---@param playerLevel number? Without it, the full amount is returned
---@return number? experience nil when the database has no amount for the quest
function Database.getQuestExperience(questId, playerLevel)
    local support = Database.isAvailable() and LibQuestieDB.Support and LibQuestieDB.Support.Get("QuestXP")
    local row = support and type(support.db) == "table" and support.db[questId]
    local questLevel, experience = row and row[1], row and row[2]
    if not experience or not playerLevel or not questLevel or questLevel <= 0 then
        return experience
    end
    local tenths = math.max(1, math.min(10, 2 * (questLevel - playerLevel) + 20))
    experience = experience * tenths / 10
    if experience <= 100 then
        return 5 * math.floor((experience + 2) / 5)
    elseif experience <= 500 then
        return 10 * math.floor((experience + 5) / 10)
    elseif experience <= 1000 then
        return 25 * math.floor((experience + 12) / 25)
    end
    return 50 * math.floor((experience + 25) / 50)
end

local dropPercentByItemId

-- The sections of QuestieDB's drop corrections, oldest first: each applies on top of the ones before, up to the
-- expansion whose rules the database follows (Forever's are Classic's: only Era's)
local DROP_CORRECTION_SECTIONS = { "Era", "Tbc", "Wotlk", "Cata", "MoP" }

---Applies QuestieDB's drop corrections to the drop rates, as Questie does: a rate checked by hand replaces
---Wowhead's; one marked as Wowhead's keeps it; one marked as the private server's keeps Wowhead's as well, since
---only Questie has that server's table.
local function applyDropCorrections(drops)
    local support = LibQuestieDB.Support
    local corrections = support.Get("QuestieItemDropCorrections")
    if type(corrections) ~= "table" then
        return
    end
    local expansions = support.Get("Expansions") or {}
    for _, sectionName in ipairs(DROP_CORRECTION_SECTIONS) do
        local section, order = corrections[sectionName], expansions[sectionName]
        local isApplying = not (expansions.Current and order) or order <= expansions.Current
        for itemId, rates in pairs(isApplying and type(section) == "table" and section or {}) do
            for npcId, rate in pairs(type(rates) == "table" and rates or {}) do
                if type(rate) == "number" and rate >= 0 then -- the reference keys (Wowhead's, the server's) are negative
                    drops[itemId] = drops[itemId] or {}
                    drops[itemId][npcId] = rate
                end
            end
        end
    end
end

---How often a creature drops a quest item, from the database's table of quest item drops and its corrections.
---@return number? chance Between 0 and 1; nil when the table has no rate for the pair
function Database.getItemDropChance(itemId, npcId)
    if not dropPercentByItemId then
        local support = Database.isAvailable()
            and LibQuestieDB.Support
            and LibQuestieDB.Support.Get("QuestieClassicItemDrops")
        if not support then
            return nil
        end
        -- The table ships as Lua source that returns it; it is read once
        local chunk = type(support.wowheadData) == "string" and loadstring(support.wowheadData)
        local isSuccess, value = pcall(chunk or error)
        dropPercentByItemId = isSuccess and type(value) == "table" and value or {}
        pcall(applyDropCorrections, dropPercentByItemId)
    end
    local percent = (dropPercentByItemId[itemId] or {})[npcId]
    return type(percent) == "number" and percent > 0 and percent / 100 or nil
end

---@return number? itemId The item the database calls by this name (the lowest id when several share it); nil when
---none does. QuestieDB builds its name index on the first call (a short pause, once a session).
function Database.getItemIdByName(name)
    if not name or name == "" or not Database.isAvailable() or type(LibQuestieDB.Item.IdsByName) ~= "function" then
        return nil
    end
    local itemIds = LibQuestieDB.Item.IdsByName(name)
    return itemIds and itemIds[1] or nil
end

---@return number[] questIds Every quest the database knows, ascending
function Database.getQuestIds()
    if not Database.isAvailable() or not LibQuestieDB.Quest.GetAllIds then
        return {}
    end
    return LibQuestieDB.Quest.GetAllIds()
end

---@return number? mask The bit a race occupies in a quest's requiredRaces
function Database.getRaceMask(raceId)
    local masks = Database.isAvailable() and LibQuestieDB.Enum and LibQuestieDB.Enum.raceMaskById
    return masks and masks[raceId] or nil
end

---@return number? mask The bit a class occupies in a quest's requiredClasses
function Database.getClassMask(classKey)
    local masks = Database.isAvailable() and LibQuestieDB.Enum and LibQuestieDB.Enum.classKeys
    return masks and masks[classKey] or nil
end

---The zone tables ship as Lua source strings that return a table.
local function decodeTable(source)
    if type(source) ~= "string" then
        return {}
    end
    local chunk = loadstring(source)
    local isSuccess, value = pcall(chunk or error)
    return isSuccess and type(value) == "table" and value or {}
end

local function composeMergedTable(base, override)
    local merged = decodeTable(base)
    for key, value in pairs(decodeTable(override)) do
        merged[key] = value
    end
    return merged
end

local NO_ZONE_MAPS = { uiMapIdByAreaId = {}, areaIdByUiMapId = {}, parentZoneIdByAreaId = {} } -- (never filled)

getZoneMaps = function()
    if zoneMaps then
        return zoneMaps
    end
    local support = Database.isAvailable() and LibQuestieDB.Support and LibQuestieDB.Support.Get("ZoneDB")
    if not support then
        -- Nothing kept before the database is there: empty tables kept then stood for the whole session
        return NO_ZONE_MAPS
    end
    local private = support.private or {}
    zoneMaps = {
        uiMapIdByAreaId = composeMergedTable(private.areaIdToUiMapId, private.areaIdToUiMapIdOverride),
        areaIdByUiMapId = composeMergedTable(private.uiMapIdToAreaId, private.uiMapIdToAreaIdOverride),
        parentZoneIdByAreaId = composeMergedTable(private.subZoneToParentZone, private.subZoneToParentZoneOverride),
    }
    return zoneMaps
end

local mapInfoById = {} -- [uiMapId] = the game's facts about a map, or false when it has none

---@return table? info The game's facts about a map (its kind, its parent, its name): they never change, so each map
---is asked about once. The game makes a new table at every asking, and a drawing asked a thousand times.
---Shared: to read, not to change.
function Database.getMapInfo(uiMapId)
    if not uiMapId or not (C_Map and C_Map.GetMapInfo) then
        return nil
    end
    if ns.frameNumber == 0 then
        return C_Map.GetMapInfo(uiMapId) -- before frames run (and in the tests): asked each time
    end
    local info = mapInfoById[uiMapId]
    if info == nil then
        info = C_Map.GetMapInfo(uiMapId) or false
        mapInfoById[uiMapId] = info
    end
    return info or nil
end

local playerFaction -- "Alliance" or "Horde", kept once the game says (it never changes)

---@return string? faction The player's side, as the game names it
function Database.getPlayerFaction()
    if ns.frameNumber == 0 then
        return UnitFactionGroup and UnitFactionGroup("player") or nil -- before frames run (and in the tests)
    end
    if not playerFaction and UnitFactionGroup then
        playerFaction = UnitFactionGroup("player") or nil
    end
    return playerFaction
end

---@return number? uiMapId The map the zone's coordinates are expressed on
function Database.getUiMapId(areaId)
    return getZoneMaps().uiMapIdByAreaId[areaId]
end

---@return boolean isZoneMap The map is a zone's, a city's or a dungeon's: not the world's or a continent's, which the
---quest database gives stand-in area numbers with no name (Azeroth 10089, Kalimdor 10073)
function Database.isZoneMap(uiMapId)
    local info = uiMapId and C_Map and C_Map.GetMapInfo and Database.getMapInfo(uiMapId)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    -- A map the game says nothing about is taken as a zone's: only the world and continents are left out
    return not (info and info.mapType and info.mapType < zoneType)
end

function Database.getAreaId(uiMapId)
    return getZoneMaps().areaIdByUiMapId[uiMapId]
end

---Subzones resolve to the zone they belong to, so a quest lists under "Tirisfal Glades", not "Brill".
---Every area of a dungeon resolves to the dungeon itself.
---Kept per area while the zone tables and the merged dungeons it comes from are the same: the maps ask it for every
---spawn of every quest at every drawing (a fifth of a drawing's time once).
local parentZoneIds, parentZoneSources = {}, {}

function Database.getParentZoneId(areaId)
    if areaId == nil then
        return nil
    end
    Database.getDungeon(nil) -- (the dungeons merged again first, when a provider came since)
    local sources = parentZoneSources
    if sources.zoneMaps ~= zoneMaps or sources.dungeons ~= dungeonsByAreaId or sources.version ~= dungeonsVersion then
        parentZoneIds = {}
        sources.zoneMaps, sources.dungeons, sources.version = zoneMaps, dungeonsByAreaId, dungeonsVersion
    end
    local known = parentZoneIds[areaId]
    if known ~= nil then
        return known
    end
    local parentZoneId = getZoneMaps().parentZoneIdByAreaId[areaId] or areaId
    local dungeon = Database.getDungeon(parentZoneId) or Database.getDungeon(areaId)
    local answer = dungeon and dungeon.areaId or parentZoneId
    -- (nothing kept before the quest database is there: its zone tables are not, and every answer is the area itself)
    if zoneMaps then
        parentZoneIds[areaId] = answer
    end
    return answer
end

function Database.getZoneName(areaId)
    local dungeon = areaId and Database.getDungeon(areaId)
    if dungeon then
        return dungeon.name
    end
    local name = areaId and areaId > 0 and C_Map.GetAreaInfo(areaId)
    return name or ns.L("Unknown location")
end

-- Quest categories the database files quests under instead of a zone, as the game's own quest log heads them
-- (QuestieDB's sortKeys). The game's own header names these in the player's language; this list is the
-- fallback.
local CATEGORY_NAMES = {
    [-1] = "Epic",
    [-22] = "Seasonal",
    [-23] = "Undercity",
    [-221] = "Treasure Map",
    [-284] = "Special",
    [-344] = "Legendary",
    [-364] = "Darkmoon Faire",
    [-366] = "Lunar Festival",
    [-367] = "Reputation",
    [-369] = "Midsummer",
    [-370] = "Brewfest",
    [-374] = "Noblegarden",
    [-376] = "Love is in the Air",
    [-378] = "Children's Week",
    [-21] = "Hallow's End",
    [-404] = "Feast of Winter Veil",
    [-1000] = "Special",
    [-61] = "Warlock",
    [-81] = "Warrior",
    [-82] = "Shaman",
    [-141] = "Paladin",
    [-161] = "Mage",
    [-162] = "Rogue",
    [-261] = "Hunter",
    [-262] = "Priest",
    [-263] = "Druid",
    [-24] = "Herbalism",
    [-101] = "Fishing",
    [-121] = "Blacksmithing",
    [-181] = "Alchemy",
    [-182] = "Leatherworking",
    [-201] = "Engineering",
    [-264] = "Tailoring",
    [-304] = "Cooking",
    [-324] = "First Aid",
    [-398] = "Riding",
}

-- The game's own pictures for categories: a profession's icon, a class's round icon, and a quest scroll for
-- the rest (holidays, reputation, special quests)
local ICONS = "Interface\\Icons\\"
local CATEGORY_ICONS = {
    [-24] = ICONS .. "Trade_Herbalism",
    [-101] = ICONS .. "Trade_Fishing",
    [-121] = ICONS .. "Trade_BlackSmithing",
    [-181] = ICONS .. "Trade_Alchemy",
    [-182] = ICONS .. "INV_Misc_ArmorKit_17",
    [-201] = ICONS .. "Trade_Engineering",
    [-264] = ICONS .. "Trade_Tailoring",
    [-304] = ICONS .. "INV_Misc_Food_15",
    [-324] = ICONS .. "Spell_Holy_SealOfSacrifice",
    [-398] = ICONS .. "Ability_Mount_RidingHorse",
}
local CATEGORY_CLASSES = {
    [-61] = "WARLOCK",
    [-81] = "WARRIOR",
    [-82] = "SHAMAN",
    [-141] = "PALADIN",
    [-161] = "MAGE",
    [-162] = "ROGUE",
    [-261] = "HUNTER",
    [-262] = "PRIEST",
    [-263] = "DRUID",
}
local CLASS_CIRCLES = "Interface\\TargetingFrame\\UI-Classes-Circles"
local OTHER_CATEGORY_ICON = ICONS .. "INV_Misc_Note_01"
local ICON_INNER = { 0.08, 0.92, 0.08, 0.92 } -- an icon without the dark rim the game draws round it

---@return string texture The picture that marks a category: its profession's or class's icon, or a quest scroll
---@return number[] texCoords The part of the picture to show
function Database.getCategoryIcon(categoryId)
    local classToken = CATEGORY_CLASSES[categoryId]
    local classCoords = classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    if classCoords then
        return CLASS_CIRCLES, classCoords
    end
    return CATEGORY_ICONS[categoryId] or OTHER_CATEGORY_ICON, ICON_INNER
end

---@return number? categoryId The quest's category, when the database files it under one instead of a zone:
---cooking, a class, a holiday and the like
function Database.getQuestCategoryId(questId)
    local zoneOrSort = Database.getQuestField(questId, "zoneOrSort")
    return type(zoneOrSort) == "number" and zoneOrSort < 0 and zoneOrSort or nil
end

---@param headerName string? The game's own quest log header over the quest, which is in the player's language
function Database.getCategoryName(categoryId, headerName)
    return headerName or (CATEGORY_NAMES[categoryId] and ns.L(CATEGORY_NAMES[categoryId])) or ns.L("Other quests")
end

---The zone whose map shows a zone: itself, or for a dungeon the zone its entrance is in. The database names
---a map for some dungeons, but the game has no picture for those and fails when asked to show one.
---@return number? zoneId
function Database.getMapZoneId(zoneId)
    local dungeon = zoneId and Database.getDungeon(zoneId)
    local entrance = dungeon and dungeon.entrances[1]
    return entrance and entrance.zoneId or zoneId
end
