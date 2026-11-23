local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Where the game's own herb and ore icons can stand on the minimap: the spawns of every herb and ore (GatheringNodes,
-- from QuestieDB) while Find Herbs or Find Minerals is on. The game draws those icons under everything an addon puts
-- on the minimap, so MinimapPins leaves out a mark that would sit on one of these spots: the icon always shows. A node
-- the player has just gathered is gone from the minimap, so its spot is given back to the marks until it can grow again.
--
-- Cheap by design. Which tracking is on is read only when the game says it changed. The spots of a kind are worked out
-- once, the first time that tracking is on, a few herbs or ores a frame (no frame pays for all of them): each zone's
-- map is placed in the world once, its spawns are put in it by arithmetic and filed in a grid of world cells. Asking
-- what is near the player reads a few cells.
local GatheringSpots = {}
ns.GatheringSpots = GatheringSpots

local FIND_SPELLS = { [2383] = "herb", [2580] = "ore" } -- Find Herbs, Find Minerals
local FIND_TEXTURES = { [133939] = "herb", [136025] = "ore" } -- their icons, where the client gives no spell
local CELL_YARDS = 200
local BUILD_MS_A_FRAME = 1 -- how long a frame spends building the spots (at least one herb or ore a frame)
local GATHERED_YARDS = 8 -- a node looted this near the player is the one gathered
local GROW_BACK_SECONDS = 600 -- how long a gathered node's spot is left to the marks (nodes grow back in minutes)

local tracked = { herb = false, ore = false }
local trackedKey = "" -- what is tracked, as text: MinimapPins asks again for the near spots when it changes
local builds = {} -- [kind] = { grid = { [continentId] = { [cellKey] = { north, west, ... } } }, nextIndex, isDone }
local gathered = {} -- { north, west, untilTime }: spots given back to the marks while their node grows again
local nodeKinds -- [objectId] = kind (from GatheringNodes, made on first use)
local builder -- the frame that builds a few objects a frame while it has work

---Reads which of the two the minimap shows now (the game's tracking menu).
function GatheringSpots.readTracking()
    tracked.herb, tracked.ore = false, false
    local minimap = C_Minimap
    if minimap and minimap.GetNumTrackingTypes and minimap.GetTrackingInfo then
        for index = 1, minimap.GetNumTrackingTypes() or 0 do
            local info = minimap.GetTrackingInfo(index)
            if info and info.active then
                local kind = FIND_SPELLS[info.spellID or 0] or FIND_TEXTURES[info.texture or 0]
                if kind then tracked[kind] = true end
            end
        end
    elseif GetTrackingTexture then
        local kind = FIND_TEXTURES[GetTrackingTexture() or 0]
        if kind then tracked[kind] = true end
    end
    trackedKey = (tracked.herb and "h" or "") .. (tracked.ore and "o" or "")
end

---@return string key What is tracked ("" for neither): the near spots are asked for again when it changes
function GatheringSpots.getTrackedKey()
    return trackedKey
end

-- A zone map's place in the world: its top left corner and its size in yards (nil off the world: an instance's)
local zoneWorlds = {}
local function getZoneWorld(zoneId)
    local world = zoneWorlds[zoneId]
    if world == nil then
        world = false
        local uiMapId = ns.Database.getUiMapId(zoneId)
        if uiMapId then
            local continentId, north, west = ns.Geometry.getWorldPosition(uiMapId, 0, 0)
            local _, southNorth, eastWest = ns.Geometry.getWorldPosition(uiMapId, 100, 100)
            if north and southNorth then
                world = { continentId = continentId, north = north, west = west, height = north - southNorth, width = west - eastWest }
            end
        end
        zoneWorlds[zoneId] = world
    end
    return world or nil
end

local function cellKey(north, west)
    return math.floor(north / CELL_YARDS) * 65536 + math.floor(west / CELL_YARDS)
end

---Files one object's spawns in a grid.
local function fileObject(grid, objectId)
    for zoneId, points in pairs(ns.Database.getObjectField(objectId, "spawns") or {}) do
        local world = getZoneWorld(zoneId)
        if world then
            local cells = grid[world.continentId]
            if not cells then
                cells = {}
                grid[world.continentId] = cells
            end
            for _, point in ipairs(points) do
                local x, y = point[1], point[2]
                if x and y and x >= 0 then -- (a spawn inside an instance has no place outside)
                    local north, west = world.north - y / 100 * world.height, world.west - x / 100 * world.width
                    local key = cellKey(north, west)
                    local cell = cells[key]
                    if not cell then
                        cell = {}
                        cells[key] = cell
                    end
                    cell[#cell + 1] = north
                    cell[#cell + 1] = west
                end
            end
        end
    end
end

---Works out up to `budget` more of a kind's objects (all of them with no budget). Waits for the database.
---@return boolean isDone
local function build(kind, budget)
    local state = builds[kind]
    if not state then
        state = { grid = {}, nextIndex = 1, isDone = false }
        builds[kind] = state
    end
    if state.isDone or not ns.Database.isAvailable() then
        return state.isDone
    end
    local nodes = ns.GatheringNodes and ns.GatheringNodes[kind] or {}
    local last = budget and math.min(#nodes, state.nextIndex + budget - 1) or #nodes
    for index = state.nextIndex, last do
        fileObject(state.grid, nodes[index])
    end
    state.nextIndex = last + 1
    state.isDone = state.nextIndex > #nodes
    return state.isDone
end

local function stopBuilder()
    if builder then
        builder:SetScript("OnUpdate", nil)
    end
end

---The tracked kinds' spots are built a few a frame; once all are, the minimap's marks are placed again.
local function startBuilder()
    local hasWork = false
    for kind, isTracked in pairs(tracked) do
        if isTracked and not (builds[kind] and builds[kind].isDone) then hasWork = true end
    end
    if not hasWork or not CreateFrame then
        return
    end
    builder = builder or CreateFrame("Frame")
    builder:SetScript("OnUpdate", function()
        -- One kind at a time, one herb or ore after another until the frame's time is spent
        local startedAt = debugprofilestop and debugprofilestop() or 0
        for kind, isTracked in pairs(tracked) do
            while isTracked and not (builds[kind] and builds[kind].isDone) do
                build(kind, 1)
                if not ns.Database.isAvailable() or not debugprofilestop or debugprofilestop() - startedAt >= BUILD_MS_A_FRAME then
                    return
                end
            end
        end
        stopBuilder()
        if ns.MinimapPins and ns.MinimapPins.refresh then ns.MinimapPins.refresh() end
    end)
end

---Builds every tracked kind's spots at once (the tests, and anything that cannot wait a few frames).
function GatheringSpots.finishBuilding()
    for kind, isTracked in pairs(tracked) do
        if isTracked then build(kind, nil) end
    end
    stopBuilder()
end

---@return boolean isGiven A spot whose node was gathered a moment ago (given back to the marks meanwhile)
local function isGathered(north, west, now)
    for index = #gathered, 1, -1 do
        local record = gathered[index]
        if record.untilTime <= now then
            table.remove(gathered, index)
        else
            local awayNorth, awayWest = record.north - north, record.west - west
            if awayNorth * awayNorth + awayWest * awayWest < GATHERED_YARDS * GATHERED_YARDS then
                return true
            end
        end
    end
    return false
end

---The spots of the tracked kinds within a distance of a place, into a list made by the caller (north, west,
---north, west, ...), emptied first. Nothing when neither is tracked; while the spots are being built, those built.
---@return number count How many spots (pairs)
function GatheringSpots.collectNear(position, yards, out)
    for index = #out, 1, -1 do
        out[index] = nil
    end
    if trackedKey == "" or not position or not position.north then
        return 0
    end
    local count = 0
    local limit = yards * yards
    local now = GetTime and GetTime() or 0
    local hasGathered = #gathered > 0
    for kind, isTracked in pairs(tracked) do
        if isTracked and not builds[kind] then
            build(kind, 0) -- (begun: the builder works it out over the next frames)
            startBuilder()
        end
        local cells = isTracked and builds[kind] and builds[kind].grid[position.continentId]
        if cells then
            local firstNorth, lastNorth = math.floor((position.north - yards) / CELL_YARDS), math.floor((position.north + yards) / CELL_YARDS)
            local firstWest, lastWest = math.floor((position.west - yards) / CELL_YARDS), math.floor((position.west + yards) / CELL_YARDS)
            for cellNorth = firstNorth, lastNorth do
                for cellWest = firstWest, lastWest do
                    local cell = cells[cellNorth * 65536 + cellWest]
                    if cell then
                        for index = 1, #cell, 2 do
                            local north, west = cell[index], cell[index + 1]
                            local awayNorth, awayWest = north - position.north, west - position.west
                            if awayNorth * awayNorth + awayWest * awayWest <= limit
                                and not (hasGathered and isGathered(north, west, now)) then
                                out[count * 2 + 1], out[count * 2 + 2] = north, west
                                count = count + 1
                            end
                        end
                    end
                end
            end
        end
    end
    return count
end

---@return boolean isOn Something in a list of spots (as collectNear makes it) lies within a distance, in yards
function GatheringSpots.isNear(spots, count, north, west, yards)
    local limit = yards * yards
    for index = 1, count * 2, 2 do
        local awayNorth, awayWest = spots[index] - north, spots[index + 1] - west
        if awayNorth * awayNorth + awayWest * awayWest < limit then
            return true
        end
    end
    return false
end

---@return string? kind "herb" or "ore" for an object id of one
local function getNodeKind(objectId)
    if not nodeKinds then
        nodeKinds = {}
        for kind, ids in pairs(ns.GatheringNodes or {}) do
            for _, id in ipairs(ids) do nodeKinds[id] = kind end
        end
    end
    return nodeKinds[objectId]
end
GatheringSpots.getNodeKind = getNodeKind -- (the ledger tells a node from a chest by it)

---Loot is open: from a herb or an ore (its source a game object of those), the node beside the player is gathered
---and gone from the minimap, so its spot is the marks' again until it grows back.
function GatheringSpots.handleLootOpened()
    if trackedKey == "" or not GetNumLootItems or not GetLootSourceInfo then
        return
    end
    local isFromNode = false
    for slot = 1, GetNumLootItems() or 0 do
        local guid = GetLootSourceInfo(slot)
        local unitType, objectId
        if type(guid) == "string" then
            unitType, objectId = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
        end
        if unitType == "GameObject" and getNodeKind(tonumber(objectId)) then
            isFromNode = true
            break
        end
    end
    local position = isFromNode and ns.Geometry.getPlayerPosition()
    if not position then
        return
    end
    gathered[#gathered + 1] = { north = position.north, west = position.west, untilTime = (GetTime and GetTime() or 0) + GROW_BACK_SECONDS }
    if ns.MinimapPins and ns.MinimapPins.refresh then
        ns.MinimapPins.refresh()
    end
end

function GatheringSpots.create()
    GatheringSpots.readTracking()
end

ns.registerModule({
    name = "GatheringSpots", create = GatheringSpots.create,
    events = {
        -- Find Herbs or Find Minerals switched on or off: the minimap's marks are placed again
        MINIMAP_UPDATE_TRACKING = function()
            local before = trackedKey
            GatheringSpots.readTracking()
            if trackedKey ~= before and ns.MinimapPins and ns.MinimapPins.refresh then
                ns.MinimapPins.refresh()
            end
        end,
        LOOT_OPENED = function() GatheringSpots.handleLootOpened() end,
    },
})
