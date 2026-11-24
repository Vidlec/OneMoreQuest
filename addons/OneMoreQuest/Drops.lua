local _, ns = ...

-- Where a quest item drops and how often: the one place the quest page, the map, the tracker, the kill counter
-- and the profit estimate get it from, so they always agree. A drop chance is the quest database's rate for
-- quest items, else the loot table's (Tnny's Mob Loot). The creature worth hunting is the likeliest one in the
-- zone worth going to (the player's own, else the nearest that fits their level), not the likeliest anywhere,
-- which may be twenty levels up on another continent.
local Drops = {}
ns.Drops = Drops

local HIGH_LEVEL_MARGIN = 8 -- a zone whose weakest creature is more levels above the player than this is for later
local MAX_SHADED_SOURCES = 3 -- creatures in a zone with a colour each; the rest share one
local MIN_CHANCE = 0.01 -- for counting kills: a rarer drop than this would ask for an absurd number of them
local CACHE_SECONDS = 10

local zonesCache = {} -- [itemId:level:zoneId] = { zones, time }

---Chance that one kill of a creature drops an item: the quest database's rate for quest items, else the loot
---table's.
---@return number? chance 0 to 1; nil when not known
function Drops.getChance(itemId, npcId)
    local chance = ns.Database.getItemDropChance(itemId, npcId)
    if chance then
        return chance
    end
    local loot = ns.Loot.getMobLoot(npcId)
    local drop = loot and loot.drops[itemId]
    return drop and drop.chance or nil
end

local MAX_UNIQUE_SPAWNS = 2 -- a creature with no more spawn points than this is one of a kind (Fozruk, a boss)
local isUniqueCache = {}

---@return boolean isForEveryone A creature's quest drops go to every party member on the quest, not round them: so
---it is for a one-of-a-kind creature (a named one, a boss), or a group could never all finish its quest
function Drops.isForEveryone(npcId)
    if not npcId then
        return false
    end
    if isUniqueCache[npcId] == nil then
        -- Counted in the database's own spawns, not in places: a creature inside a dungeon has its spawns there as
        -- one place per entrance, so every creature in a dungeon looked one of a kind... and none shared its drops
        local count = 0
        for _, points in pairs(ns.Database.getNpcField(npcId, "spawns") or {}) do
            count = count + (type(points) == "table" and #points or 0)
        end
        local isUnique = count > 0 and count <= MAX_UNIQUE_SPAWNS
        if not ns.Database.isAvailable() then
            return isUnique -- (not kept until the database is there to ask)
        end
        isUniqueCache[npcId] = isUnique
    end
    return isUniqueCache[npcId]
end

---@return boolean isDropped The creature is one the database says drops the item
function Drops.isDroppedBy(itemId, npcId)
    for _, sourceNpcId in ipairs(ns.Database.getItemField(itemId, "npcDrops") or {}) do
        if sourceNpcId == npcId then
            return true
        end
    end
    return false
end

---@class DropSource
---@field npcId number? For a creature
---@field objectId number? For an object, such as a chest or a plant
---@field name string
---@field chance number? 0 to 1
---@field minLevel number?
---@field maxLevel number?
---@field places table[] Its spawn points; in a DropZone, only those in that zone
---@field shade number? In a DropZone: its colour there, 1 to 3, or 4 shared by the rest

---Each creature and object an item drops from, with its drop chance, levels and places.
---@return DropSource[] sources
function Drops.getSources(itemId)
    local sources = {}
    for _, npcId in ipairs(ns.Database.getItemField(itemId, "npcDrops") or {}) do
        local places = {}
        ns.Location.addNpcPlaces(places, npcId)
        sources[#sources + 1] = {
            npcId = npcId,
            name = ns.Database.getNpcField(npcId, "name") or ns.L("a creature"),
            places = places,
            chance = Drops.getChance(itemId, npcId),
            minLevel = ns.Database.getNpcField(npcId, "minLevel"),
            maxLevel = ns.Database.getNpcField(npcId, "maxLevel"),
        }
    end
    for _, objectId in ipairs(ns.Database.getItemField(itemId, "objectDrops") or {}) do
        local places = {}
        ns.Location.addObjectPlaces(places, objectId)
        sources[#sources + 1] = {
            objectId = objectId,
            name = ns.Database.getObjectField(objectId, "name") or ns.L("an object"),
            places = places,
        }
    end
    return sources
end

local function isLikelier(first, second)
    if (first.chance or -1) ~= (second.chance or -1) then
        return (first.chance or -1) > (second.chance or -1)
    end
    return first.name < second.name
end

---@class DropZone
---@field zoneId number
---@field name string
---@field sources DropSource[] Likeliest first
---@field places table[]
---@field minLevel number?
---@field maxLevel number?
---@field isPlayerZone boolean
---@field isTooHigh boolean Its creatures are well above the player
---@field isDungeon boolean
---@field distance number? Yards to its nearest place, nil on another continent

local function composeZones(itemId, player, playerLevel)
    local zonesById, zones = {}, {}
    for _, source in ipairs(Drops.getSources(itemId)) do
        local placesByZone = {}
        for _, place in ipairs(source.places) do
            local zoneId = place.groupZoneId
            if zoneId then
                placesByZone[zoneId] = placesByZone[zoneId] or {}
                table.insert(placesByZone[zoneId], place)
            end
        end
        for zoneId, places in pairs(placesByZone) do
            local zone = zonesById[zoneId]
            if not zone then
                zone = {
                    zoneId = zoneId,
                    name = ns.Database.getZoneName(zoneId),
                    sources = {},
                    places = {},
                    isDungeon = ns.Database.getDungeon(zoneId) ~= nil,
                }
                zonesById[zoneId] = zone
                zones[#zones + 1] = zone
            end
            zone.sources[#zone.sources + 1] = {
                npcId = source.npcId,
                objectId = source.objectId,
                name = source.name,
                chance = source.chance,
                minLevel = source.minLevel,
                maxLevel = source.maxLevel,
                places = places,
            }
            for _, place in ipairs(places) do
                zone.places[#zone.places + 1] = place
            end
            if source.minLevel then
                zone.minLevel = math.min(zone.minLevel or source.minLevel, source.minLevel)
                zone.maxLevel =
                    math.max(zone.maxLevel or source.maxLevel or source.minLevel, source.maxLevel or source.minLevel)
            end
        end
    end
    for _, zone in ipairs(zones) do
        table.sort(zone.sources, isLikelier)
        for index, source in ipairs(zone.sources) do
            source.shade = math.min(index, MAX_SHADED_SOURCES + 1)
        end
        zone.isPlayerZone = zone.zoneId == player.zoneId
        zone.isTooHigh = not zone.isPlayerZone and (zone.minLevel or 0) > playerLevel + HIGH_LEVEL_MARGIN
        zone.distance = ns.Geometry.getNearest(zone.places, player.position, ns.Database.getUiMapId)
    end
    table.sort(zones, function(first, second)
        if first.isPlayerZone ~= second.isPlayerZone then
            return first.isPlayerZone
        end
        if first.isTooHigh ~= second.isTooHigh then
            return second.isTooHigh
        end
        if first.isTooHigh then
            if (first.minLevel or 0) ~= (second.minLevel or 0) then
                return (first.minLevel or 0) < (second.minLevel or 0)
            end
        elseif (first.distance ~= nil) ~= (second.distance ~= nil) then
            return first.distance ~= nil
        elseif first.distance and first.distance ~= second.distance then
            return first.distance < second.distance
        end
        return first.name < second.name
    end)
    return zones
end

---The zones an item drops in, in the order worth going: the player's own zone, then zones whose creatures fit
---the player's level, nearest first, then zones for much higher levels, lowest first. In each zone its
---creatures, likeliest first, the first few with a colour each and the rest sharing one, as their spawn points
---are drawn on that zone's map. Kept for a few seconds, as the page, the map and the tracker all ask.
---@return DropZone[] zones
function Drops.getZones(itemId)
    local player = ns.Model.getPlayer()
    local playerLevel = UnitLevel and UnitLevel("player") or 1
    local cacheKey = itemId .. ":" .. playerLevel .. ":" .. tostring(player.zoneId)
    local now = GetTime and GetTime() or 0
    local cached = zonesCache[cacheKey]
    if cached and now - cached.time < CACHE_SECONDS then
        return cached.zones
    end
    local zones = composeZones(itemId, player, playerLevel)
    zonesCache[cacheKey] = { zones = zones, time = now }
    return zones
end

---The creature to hunt for an item: the likeliest with a known chance in the first zone worth going to; else
---the likeliest anywhere.
---@return DropSource? source With its npcId and chance; nil when no creature's chance is known
---@return boolean hasUnknownChance Creatures drop it, but how often is not known
function Drops.getHuntedSource(itemId)
    local zones = Drops.getZones(itemId)
    local best, hasCreature
    for _, zone in ipairs(zones) do
        for _, source in ipairs(zone.sources) do
            hasCreature = hasCreature or source.npcId ~= nil
            if source.npcId and source.chance then
                if not zone.isTooHigh then
                    return source, false
                end
                if not best or source.chance > best.chance then
                    best = source
                end
            end
        end
    end
    return best, best == nil and hasCreature == true
end

---@return number kills About how many kills a number of drops takes at a drop chance
function Drops.getKillsFor(dropCount, chance)
    return dropCount / math.max(chance, MIN_CHANCE)
end

---@return string text A drop chance as a player reads it: "25%", or "0.5%" for the rare ones
function Drops.formatChance(chance)
    if chance >= 0.01 then
        return string.format("%d%%", math.floor(chance * 100 + 0.5))
    end
    return string.format("%.1f%%", chance * 100)
end

---Forgets the zones worked out, for when loot tables or the player's place may have changed.
function Drops.reset()
    zonesCache, isUniqueCache = {}, {}
end
