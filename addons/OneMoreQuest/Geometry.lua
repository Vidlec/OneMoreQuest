local _, ns = ...

-- World positions are in yards: north grows northwards, west grows westwards, as the game reports them.
local Geometry = {}
ns.Geometry = Geometry

local DIRECTIONS = { "north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west" }

---@param x number 0-100 across the map
---@param y number 0-100 down the map
---@return number? continentId, number? north, number? west
local mapPoint -- one vector, reused for every conversion: hundreds a drawing, each a table for the garbage collector

function Geometry.getWorldPosition(uiMapId, x, y)
    if not uiMapId or not x or x < 0 or y < 0 then
        return nil
    end
    if mapPoint and mapPoint.SetXY then
        mapPoint:SetXY(x / 100, y / 100)
    else
        mapPoint = CreateVector2D(x / 100, y / 100)
    end
    local continentId, position = C_Map.GetWorldPosFromMapPos(uiMapId, mapPoint)
    if not position then
        return nil
    end
    local north, west = position:GetXY()
    return continentId, north, west
end

-- The player's position is asked for many times a frame (the minimap, the hover, the marks): worked out once a frame
-- and shared (ns.frameNumber; in tests, where no frames run, every call works it out). Read only.
local cachedPosition, cachedPositionFrame = nil, nil

local function readPlayerPosition()
    local uiMapId = C_Map.GetBestMapForUnit("player")
    local mapPosition = uiMapId and C_Map.GetPlayerMapPosition(uiMapId, "player")
    if not mapPosition then
        return nil
    end
    local x, y = mapPosition:GetXY()
    local continentId, north, west = Geometry.getWorldPosition(uiMapId, x * 100, y * 100)
    if not north then
        return nil
    end
    return { uiMapId = uiMapId, continentId = continentId, north = north, west = west }
end

---@return { uiMapId: number, continentId: number, north: number, west: number }? player nil inside instances. The
---same table for the whole frame: not to be changed.
function Geometry.getPlayerPosition()
    local frameNumber = ns.frameNumber
    if frameNumber > 0 and cachedPositionFrame == frameNumber then
        return cachedPosition
    end
    local position = readPlayerPosition()
    cachedPosition, cachedPositionFrame = position, frameNumber
    return position
end

function Geometry.getDistance(fromNorth, fromWest, toNorth, toWest)
    local north, west = toNorth - fromNorth, toWest - fromWest
    return math.sqrt(north * north + west * west)
end

---@return string direction One of eight compass names
function Geometry.getDirection(fromNorth, fromWest, toNorth, toWest)
    local north, east = toNorth - fromNorth, fromWest - toWest
    local degrees = math.deg(math.atan2(east, north)) % 360
    return ns.L(DIRECTIONS[math.floor((degrees + 22.5) / 45) % 8 + 1])
end

---Nearest of the places to the player. A place caches its world position the first time it is measured.
---@param places { zoneId: number, x: number, y: number }[]
---@return number? distance Yards, nil when no place can be measured from here
---@return string? direction
---@return table? place The nearest place
function Geometry.getNearest(places, player, getUiMapId)
    local nearestDistance, nearestPlace
    if not player then
        return nil
    end
    for _, place in ipairs(places) do
        if place.north == nil then
            local continentId, north, west = Geometry.getWorldPosition(getUiMapId(place.zoneId), place.x, place.y)
            place.continentId, place.north, place.west = continentId, north or false, west
        end
        if place.north and place.continentId == player.continentId then
            local distance = Geometry.getDistance(player.north, player.west, place.north, place.west)
            if not nearestDistance or distance < nearestDistance then
                nearestDistance, nearestPlace = distance, place
            end
        end
    end
    if not nearestPlace then
        return nil
    end
    return nearestDistance,
        Geometry.getDirection(player.north, player.west, nearestPlace.north, nearestPlace.west),
        nearestPlace
end
