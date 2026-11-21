local _, ns = ...

-- A waypoint on a quest's place: TomTom's arrow when TomTom is installed, the game's own waypoint otherwise.
-- Set by hand from the tracker's menu, or kept on the focused quest when the settings ask for it.
local Waypoints = {}
ns.Waypoints = Waypoints

local tomTomWaypoint -- the waypoint last given to TomTom, so it is replaced rather than piled up
local isGameWaypointOurs = false -- the game's waypoint was set by this addon, so this addon may take it away
local followedKey -- the quest and place the waypoint follows now; it is set again only when they change

---@return boolean hasTomTom TomTom is installed and can take a waypoint
function Waypoints.hasTomTom()
    return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

---@return number? uiMapId, number? x, number? y Where a place is, as the map and TomTom take it (0 to 1)
local function getTarget(place)
    if not place or place.x < 0 then
        return nil
    end
    local uiMapId = ns.Database.getUiMapId(place.zoneId)
    return uiMapId, place.x / 100, place.y / 100
end

---@return table? place Where a quest's waypoint goes: its nearest place, or its first
function Waypoints.getQuestPlace(entry)
    local place = entry and (entry.nearestPlace or entry.places[1])
    return place and place.x >= 0 and place or nil
end

---Takes away the waypoint this addon set, and only that one.
function Waypoints.clear()
    if tomTomWaypoint and Waypoints.hasTomTom() and TomTom.RemoveWaypoint then
        TomTom:RemoveWaypoint(tomTomWaypoint)
    end
    tomTomWaypoint = nil
    if isGameWaypointOurs and C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    end
    isGameWaypointOurs = false
    followedKey = nil
end

---Puts a waypoint on a quest's place, replacing the one this addon set before.
---@param place table? Where; the quest's nearest place when nil
---@return boolean isSet False when the place is not known or no waypoint can be set there
function Waypoints.set(entry, place)
    local uiMapId, x, y = getTarget(place or Waypoints.getQuestPlace(entry))
    if not uiMapId then
        return false
    end
    Waypoints.clear()
    if Waypoints.hasTomTom() then
        tomTomWaypoint = TomTom:AddWaypoint(uiMapId, x, y, {
            title = entry.title, from = ns.ADDON_TITLE, persistent = false, minimap = true, world = true, crazy = true,
        })
        return tomTomWaypoint ~= nil
    end
    local canSet = C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(uiMapId))
    if not canSet then
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapId, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true) -- the game's arrow points at it
    end
    isGameWaypointOurs = true
    return true
end

---Keeps the waypoint on the focused quest's nearest place, when the settings ask for it. Called whenever the
---tracker is drawn; the waypoint moves only when the quest or its nearest place changes.
---@param entry table? The focused quest; nil when none is focused
function Waypoints.followFocusedQuest(entry)
    if not ns.settings.shouldWaypointFocused then
        if followedKey then
            Waypoints.clear() -- switched off: the waypoint it set goes with it
        end
        return
    end
    local place = Waypoints.getQuestPlace(entry)
    local key = place and string.format("%s:%s:%s:%s", tostring(entry.questId), tostring(place.zoneId or place.groupZoneId),
        tostring(place.x), tostring(place.y))
    if key == followedKey then
        return
    end
    if not key then
        Waypoints.clear()
        return
    end
    if Waypoints.set(entry, place) then
        followedKey = key
    end
end
