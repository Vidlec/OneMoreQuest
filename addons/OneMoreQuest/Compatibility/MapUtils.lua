local _, ns = ...

-- MapUtils (D4KiR): the world map can be dragged by its border and sized by a grip. When OneMoreQuest's window docks
-- beside the map, the game lays its windows out again, which would put a moved map back at its usual spot; with
-- MapUtils loaded, the map is kept where it is (MapDock, placesMap). Its sizing is followed by itself: OneMoreQuest's
-- window stands at the map's edges and its marks scale with the map.
-- MapUtils also draws quest givers and turn-ins from its own data, as OneMoreQuest's "!" and "?" do; it leaves them
-- out for Questie, not for OneMoreQuest, so both would show. Once, a few seconds after logging in, the player is asked
-- whether to turn those two kinds of its pins off (its own settings, which it reads as it draws); the rest of
-- MapUtils, its entrances, flight points and boats, stays. Its dungeon entrances carry OneMoreQuest's dungeon marks
-- (MapMarks.getEntrancePins).
local POPUP = "ONE_MORE_QUEST_MAPUTILS"
-- Its two kinds of quest pins, by the keys of its saved settings (MAUTTAB); a kind is off when "<key>_ENABLED" is false
local QUEST_PIN_KEYS = { "QUESTGIVERWORLDMAPPINS", "QUESTTURNINWORLDMAPPINS" }

local MapUtils = {
    name = "MapUtils",
    label = "MapUtils",
    about = "On its one map, quest marks show on every zone in view. The map stays where you moved it when OneMoreQuest's window opens beside it, and its dungeon entrances carry OneMoreQuest's dungeon marks. Its own quest givers and turn-ins would double OneMoreQuest's: OneMoreQuest asks once whether to turn them off.",
}

---@return boolean isShown MapUtils draws quest givers or turn-ins of its own
function MapUtils.areQuestPinsShown()
    local settings = _G.MAUTTAB
    if type(settings) ~= "table" then
        return true -- not saved yet: its defaults show them
    end
    for _, key in ipairs(QUEST_PIN_KEYS) do
        if settings[key .. "_ENABLED"] ~= false and settings[key] ~= false then
            return true
        end
    end
    return false
end

function MapUtils.placesMap()
    return true
end

function MapUtils.getStatus()
    return MapUtils.areQuestPinsShown() and ns.L("Its quest givers are on.") or ns.L("Its quest givers are off.")
end

function MapUtils.ask()
    if
        ns.settings.hasAnsweredMapUtils
        or not MapUtils.areQuestPinsShown()
        or not StaticPopupDialogs
        or not StaticPopup_Show
    then
        return
    end
    StaticPopupDialogs[POPUP] = {
        text = ns.L(
            "%s: MapUtils draws quest givers and turn-ins on the map too, so you would see them twice.\n\nTurn off MapUtils' quest givers and turn-ins? Its other icons stay.",
            ns.ADDON_TITLE
        ),
        button1 = ns.L("Turn them off"),
        button2 = ns.L("Keep both"),
        OnAccept = function()
            ns.settings.hasAnsweredMapUtils = true
            _G.MAUTTAB = type(_G.MAUTTAB) == "table" and _G.MAUTTAB or {}
            for _, key in ipairs(QUEST_PIN_KEYS) do
                _G.MAUTTAB[key .. "_ENABLED"] = false -- as its own switch for the kind writes it
            end
            ns.print(ns.L("MapUtils' quest givers and turn-ins are off; they leave the map as it is drawn again."))
        end,
        OnCancel = function(_, _, reason)
            -- Only the button is an answer; Escape or another popup pushing this one away asks again next time
            if reason == "clicked" then
                ns.settings.hasAnsweredMapUtils = true
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(POPUP)
end

MapUtils.onLoginSettled = MapUtils.ask

-- Its "one map" (on unless switched off): the neighbouring zones drawn round the zone shown, each where the game puts it
-- in the world. OneMoreQuest's marks of those zones too, then, placed by the game's own reckoning, as far as the view
-- reaches (MapPins' view; as for OpenMap, whose joining is its own).
local ZONE_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
local WORLD_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.World or 1
local zoneMapIdsByTop = {}

---A point of one zone's map on the map shown, through the world: anywhere on the continent, past the map's edges too.
local function project(placeMapId, x, y, mapId)
    if placeMapId == mapId then
        return x, y
    end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then
        return nil, nil
    end
    local continentId, position = C_Map.GetWorldPosFromMapPos(placeMapId, CreateVector2D(x, y))
    if not position then
        return nil, nil
    end
    local _, onMap = C_Map.GetMapPosFromWorldPos(continentId, position, mapId)
    if not onMap then
        return nil, nil
    end
    return onMap:GetXY()
end

---@return number[] mapIds The zones whose maps reach into the view
local function getZoneMapIds(mapId, bounds)
    local mapIds = {}
    if not (C_Map.GetMapInfo and C_Map.GetMapChildrenInfo) then
        return mapIds
    end
    local topId, info, steps = mapId, ns.Database.getMapInfo(mapId), 0
    while
        info
        and info.mapType
        and info.mapType > WORLD_MAP_TYPE
        and info.parentMapID
        and info.parentMapID > 0
        and steps < 10
    do
        topId, info, steps = info.parentMapID, ns.Database.getMapInfo(info.parentMapID), steps + 1
    end
    if not zoneMapIdsByTop[topId] then
        local list = {}
        for _, child in ipairs(C_Map.GetMapChildrenInfo(topId, ZONE_MAP_TYPE, true) or {}) do
            list[#list + 1] = child.mapID
        end
        zoneMapIdsByTop[topId] = list
    end
    for _, zoneMapId in ipairs(zoneMapIdsByTop[topId]) do
        local left, top = project(zoneMapId, 0, 0, mapId)
        local right, bottom = project(zoneMapId, 1, 1, mapId)
        if
            left
            and right
            and left <= bounds.right
            and right >= bounds.left
            and top <= bounds.bottom
            and bottom >= bounds.top
        then
            mapIds[#mapIds + 1] = zoneMapId
        end
    end
    return mapIds
end

---@return number? mapId The zone whose land is at a point of the map shown, as the game says
local function getZoneMapIdAt(mapId, x, y)
    local info = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(mapId, x, y)
    return info and info.mapID or nil
end

local VIEW = { project = project, getZoneMapIds = getZoneMapIds, getZoneMapIdAt = getZoneMapIdAt }

---@return boolean isJoined Its one map is on
function MapUtils.isOneMap()
    local settings = _G.MAUTTAB
    return type(settings) ~= "table" or settings.ONEMAP ~= false -- (on unless switched off, as it starts)
end

function MapUtils.getMapView(map)
    if map ~= WorldMapFrame or not MapUtils.isOneMap() then
        return nil
    end
    return VIEW
end

ns.Compatibility.register(MapUtils)
