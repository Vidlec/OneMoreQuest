local _, ns = ...

-- OpenMap: one seamless world map, every zone joined onto the next. The game's map stays underneath and follows the
-- view, so on it OneMoreQuest's marks would show only that one zone's, however much of its neighbours is in view.
-- OpenMap's own API (OpenMapAPI, major version 1) places any zone's point on the map underneath, as its joined-on
-- art has it, and says which zone lies at a point. With those, the marks of every zone in view are drawn, each where
-- OpenMap draws its land; and as the view pans past what was drawn, they are drawn again. Only reads OpenMap's API:
-- nothing of OpenMap's is changed.
local OWNER = {} -- our key for OpenMap's callbacks
local ZONE_SAMPLES = 6 -- points across and down the view where OpenMap is asked which zone is there
local isHooked = false

local function getApi()
    local api = _G.OpenMapAPI
    if type(api) == "table" and api.major == 1 and type(api.IsStitched) == "function"
        and type(api.WorldFromMap) == "function" and type(api.MapFromWorld) == "function" then
        return api
    end
    return nil
end

---A point of one zone's map on the map underneath, through OpenMap's joined-on world.
local function project(placeMapId, x, y, mapId)
    local api = getApi()
    if not api then
        return nil, nil
    end
    local u, v = api.WorldFromMap(placeMapId, x, y)
    if not u or not v then
        return nil, nil
    end
    return api.MapFromWorld(mapId, u, v)
end

local ZONE_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local WORLD_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.World or 1
local zoneMapIdsByTop = {} -- every zone's map under a world map, worked out once

---@return number[]? mapIds Every zone's map in the world a map belongs to; nil where the game cannot list them
local function getWorldZoneMapIds(mapId)
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then
        return nil
    end
    -- Up to the world the map is part of
    local topId, info, steps = mapId, ns.Database.getMapInfo(mapId), 0
    while info and info.mapType and info.mapType > WORLD_MAP_TYPE and info.parentMapID and info.parentMapID > 0 and steps < 10 do
        topId, info, steps = info.parentMapID, ns.Database.getMapInfo(info.parentMapID), steps + 1
    end
    if not zoneMapIdsByTop[topId] then
        local mapIds = {}
        for _, child in ipairs(C_Map.GetMapChildrenInfo(topId, ZONE_MAP_TYPE, true) or {}) do
            mapIds[#mapIds + 1] = child.mapID
        end
        zoneMapIdsByTop[topId] = mapIds
    end
    return #zoneMapIdsByTop[topId] > 0 and zoneMapIdsByTop[topId] or nil
end

---The zones in view: every zone of the world whose map, placed as OpenMap draws it, reaches into the view; where
---the game cannot list the zones, OpenMap is asked which zone lies at points spread across it instead.
---@return number[] mapIds
local function getZoneMapIds(mapId, bounds)
    local api = getApi()
    local mapIds, isListed = {}, {}
    if not api then
        return mapIds
    end
    local worldZoneMapIds = getWorldZoneMapIds(mapId)
    if worldZoneMapIds then
        for _, zoneMapId in ipairs(worldZoneMapIds) do
            local left, top = project(zoneMapId, 0, 0, mapId)
            local right, bottom = project(zoneMapId, 1, 1, mapId)
            if left and top and right and bottom and left <= bounds.right and right >= bounds.left
                and top <= bounds.bottom and bottom >= bounds.top then
                mapIds[#mapIds + 1] = zoneMapId
            end
        end
        return mapIds
    end
    if type(api.MapAt) ~= "function" then
        return mapIds
    end
    for row = 0, ZONE_SAMPLES do
        for column = 0, ZONE_SAMPLES do
            local x = bounds.left + (bounds.right - bounds.left) * column / ZONE_SAMPLES
            local y = bounds.top + (bounds.bottom - bounds.top) * row / ZONE_SAMPLES
            local u, v = api.WorldFromMap(mapId, x, y)
            local zoneMapId = u and v and api.MapAt(u, v)
            if type(zoneMapId) == "number" and not isListed[zoneMapId] then
                isListed[zoneMapId] = true
                mapIds[#mapIds + 1] = zoneMapId
            end
        end
    end
    return mapIds
end

---@return number? mapId The zone whose land OpenMap draws at a point of the map underneath
local function getZoneMapIdAt(mapId, x, y)
    local api = getApi()
    if not api or type(api.MapAt) ~= "function" then
        return nil
    end
    local u, v = api.WorldFromMap(mapId, x, y)
    return u and v and api.MapAt(u, v) or nil
end

local VIEW = { project = project, getZoneMapIds = getZoneMapIds, getZoneMapIdAt = getZoneMapIdAt }

---Redraws as OpenMap's view pans or switches between its map and the game's.
local function hookOpenMap()
    local api = getApi()
    if isHooked or not api or type(api.RegisterCallback) ~= "function" then
        return
    end
    isHooked = true
    api.RegisterCallback(OWNER, "OpenMap_ViewChanged", function() ns.MapPins.handleViewMoved() end)
    api.RegisterCallback(OWNER, "OpenMap_StitchedChanged", function() ns.MapPins.queueRefresh() end)
end

ns.Compatibility.register({
    name = "OpenMap",
    label = "OpenMap",
    about = "Quest marks show on every zone in view on its joined-up map, not only the zone under it.",
    detect = function()
        return getApi() ~= nil
    end,
    onLoginSettled = hookOpenMap,
    getMapView = function(map)
        local api = getApi()
        if map ~= WorldMapFrame or not api or not api.IsStitched() then
            return nil
        end
        hookOpenMap() -- the map opened before the login settled
        return VIEW
    end,
})
