local _, ns = ...

-- A waypoint on a quest's place: TomTom's arrow when TomTom is installed, the game's own waypoint otherwise.
-- Set by hand from the tracker's menu, or kept on the focused quest when the settings ask for it.
local Waypoints = {}
ns.Waypoints = Waypoints

local tomTomWaypoint -- the waypoint last given to TomTom, so it is replaced rather than piled up
local isGameWaypointOurs = false -- the game's waypoint was set by this addon, so this addon may take it away
local ourGameWaypoint -- { uiMapId, x, y } where this addon put the game's waypoint
local SAME_SPOT = 0.0005 -- of the map's width: the game's waypoint this near ours is still ours
local followedKey -- the quest and place the waypoint follows now; it is set again only when they change
local lastFocusKey = "" -- the focused quest's place as last seen ("": none focused)
local handSetFor -- that, when the player put a waypoint by hand: kept until the focus moves on (setByHand)

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

---@return boolean isTold The quest's place may be pointed at: nothing of it is held back (Spoilers), its objectives
---shown exactly, or, ready to hand in (or with nothing to do but be at the NPC), its turn-in shown. As the tracker asks.
function Waypoints.isPlaceTold(entry)
    if not ns.Spoilers.isActive() then
        return true
    end
    if entry.isTurnIn or entry.eventText then
        return ns.Model.isTurnInShown(entry.questId)
    end
    return ns.Spoilers.get("objectives", entry.questId) == "exact"
end

---@return table? place Where a quest's waypoint goes: its nearest place, or its first; none while it is held back
function Waypoints.getQuestPlace(entry)
    local place = entry and Waypoints.isPlaceTold(entry) and (entry.nearestPlace or entry.places[1])
    return place and place.x >= 0 and place or nil
end

---@return boolean isOurs The game's waypoint is still the one this addon set: the game has one, and the player may
---have put a pin of their own in its place since (a click on the map), which is theirs to keep
local function isGameWaypointStillOurs()
    if not isGameWaypointOurs then
        return false
    end
    if not C_Map.GetUserWaypoint or not ourGameWaypoint then
        return true -- (a game that cannot say where its waypoint is: taken as ours, as set)
    end
    local point = C_Map.GetUserWaypoint()
    local position = type(point) == "table" and point.position
    if type(position) ~= "table" then
        return false -- no waypoint now: the player cleared it already
    end
    local x, y = position.x, position.y
    if type(x) ~= "number" and position.GetXY then
        x, y = position:GetXY()
    end
    return point.uiMapID == ourGameWaypoint.uiMapId
        and type(x) == "number"
        and type(y) == "number"
        and math.abs(x - ourGameWaypoint.x) <= SAME_SPOT
        and math.abs(y - ourGameWaypoint.y) <= SAME_SPOT
end

---Takes away the waypoint this addon set, and only that one: a pin the player put down since is left alone.
function Waypoints.clear()
    if tomTomWaypoint and Waypoints.hasTomTom() and TomTom.RemoveWaypoint then
        TomTom:RemoveWaypoint(tomTomWaypoint)
    end
    tomTomWaypoint = nil
    if isGameWaypointStillOurs() and C_Map.ClearUserWaypoint then
        C_Map.ClearUserWaypoint()
    end
    isGameWaypointOurs = false
    ourGameWaypoint = nil
    followedKey = nil
end

---Puts a waypoint on a quest's place, replacing the one this addon set before.
---@param place table? Where; the quest's nearest place when nil
---@return boolean isSet False when the place is not known or no waypoint can be set there
function Waypoints.set(entry, place)
    if entry and not Waypoints.isPlaceTold(entry) then
        return false -- (where it is, held back: Spoilers)
    end
    local uiMapId, x, y = getTarget(place or Waypoints.getQuestPlace(entry))
    if not uiMapId then
        return false
    end
    Waypoints.clear()
    if Waypoints.hasTomTom() then
        tomTomWaypoint = TomTom:AddWaypoint(uiMapId, x, y, {
            title = entry.title,
            from = ns.ADDON_TITLE,
            persistent = false,
            minimap = true,
            world = true,
            crazy = true,
        })
        return tomTomWaypoint ~= nil
    end
    local canSet = C_Map.SetUserWaypoint
        and UiMapPoint
        and UiMapPoint.CreateFromCoordinates
        and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(uiMapId))
    if not canSet then
        return false
    end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(uiMapId, x, y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true) -- the game's arrow points at it
    end
    isGameWaypointOurs = true
    ourGameWaypoint = { uiMapId = uiMapId, x = x, y = y }
    return true
end

---A waypoint the player asked for (the tracker's menu): set as Waypoints.set does, and kept while the focused quest
---stays where it is, rather than moved back to it at the next drawing.
---@return boolean isSet
function Waypoints.setByHand(entry, place)
    local isSet = Waypoints.set(entry, place)
    if isSet then
        handSetFor = lastFocusKey
    end
    return isSet == true
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
    local key = place
        and string.format(
            "%s:%s:%s:%s",
            tostring(entry.questId),
            tostring(place.zoneId or place.groupZoneId),
            tostring(place.x),
            tostring(place.y)
        )
    lastFocusKey = key or ""
    if handSetFor ~= nil then
        if handSetFor == lastFocusKey then
            return -- (a waypoint the player chose from the tracker's menu stays while the focus stays)
        end
        handSetFor = nil
    end
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
