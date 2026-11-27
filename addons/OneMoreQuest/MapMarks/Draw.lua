local addonName, ns = ...

-- The map's marks: drawing on a map (other addons' pins, dungeon entrances, the party, and the drawing itself).
local MapMarks = ns.MapMarks
local Style, State = ns.MapMarksStyle, ns.MapMarksState
local Compose, Look, Layout, Shapes, Areas, Draw =
    ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw
local drawIcons, drawPatrols, drawQuestAreas = Areas.drawIcons, Areas.drawPatrols, Areas.drawQuestAreas
local ensureLayers, getRect = Layout.ensureLayers, Layout.getRect
local HALO_SIZE, MEMBER_CLEAR, PARTY_SECONDS, PLAYER_CLEAR, acquire =
    Look.HALO_SIZE, Look.MEMBER_CLEAR, Look.PARTY_SECONDS, Look.PLAYER_CLEAR, Look.acquire
local AREA_TINT_ALPHA, FOCUSED_AREA_TINT_ALPHA, QUEST_BLUE, QUEST_SHADES, SOFT_DOT =
    Style.AREA_TINT_ALPHA, Style.FOCUSED_AREA_TINT_ALPHA, Style.QUEST_BLUE, Style.QUEST_SHADES, Style.SOFT_DOT
local SPAWN_ROOM = Style.SPAWN_ROOM

local MAX_FOREIGN_PIN_SIZE = 48 -- anything bigger on the canvas is a layer or an overlay, not a pin
local FOREIGN_PIN_INSET = 0.2 -- a pin's frame is larger than its picture: this much of it, on each side, is room our marks may use

---Other addons' and the game's pins on the map, where they are in our mark layer's units: what our marks keep
---clear of. Our own layers, hidden pins and anything larger than a pin are left out.
---@return { left: number, top: number, right: number, bottom: number }[] rects
---@param skipped table? [frame] = true for pins to leave out: the entrance icons our dungeon marks sit on
function MapMarks.getForeignPins(canvas, skipped)
    local rects = {}
    if not State.markLayer or not canvas.GetChildren then
        return rects
    end
    local layerScale = State.markLayer:GetEffectiveScale()
    local canvasScale = canvas:GetEffectiveScale()
    local canvasLeft, canvasTop = canvas:GetLeft(), canvas:GetTop()
    if not canvasLeft or not canvasTop or not layerScale or layerScale <= 0 then
        return rects
    end
    for _, child in ipairs({ canvas:GetChildren() }) do
        -- Shown and seen: the game's own marks this addon made see-through take no room
        if
            child ~= State.markLayer
            and child ~= State.areaLayer
            and child:IsShown()
            and (child:GetAlpha() or 1) > 0.05
            and not (skipped and skipped[child])
        then
            local left, bottom, width, height = child:GetRect()
            local scale = child:GetEffectiveScale()
            if left and width and width > 0 then
                local layerWidth, layerHeight = width * scale / layerScale, height * scale / layerScale
                if layerWidth <= MAX_FOREIGN_PIN_SIZE and layerHeight <= MAX_FOREIGN_PIN_SIZE then
                    local layerLeft = (left * scale - canvasLeft * canvasScale) / layerScale
                    local layerTop = (canvasTop * canvasScale - (bottom + height) * scale) / layerScale
                    local insetX, insetY = layerWidth * FOREIGN_PIN_INSET, layerHeight * FOREIGN_PIN_INSET
                    rects[#rects + 1] = {
                        left = layerLeft + insetX,
                        top = layerTop + insetY,
                        right = layerLeft + layerWidth - insetX,
                        bottom = layerTop + layerHeight - insetY,
                    }
                end
            end
        end
    end
    return rects
end

local ENTRANCE_KINDS = { Dungeon = false, Raid = true, Dunraid = false } -- Leatrix Maps' entrance icons: is a raid
local MAX_ENTRANCE_DISTANCE = 0.03 -- how near, in map widths, an entrance icon must be to a dungeon's mark

---Dungeon entrances other addons draw on the map: Leatrix Maps' icons (frames on the canvas that take no mouse,
---each with its row of data: kind, x and y in percent) and the game's own entrance pins.
---@return { x: number, y: number, isRaid: boolean, frame: table }[] entrances In the map's 0 to 1 units
function MapMarks.getEntrancePins(map, canvas)
    local entrances = {}
    -- Where a pin stands on the canvas, as fractions of it, from where it is drawn: for an addon whose pins keep their
    -- own map's coordinates
    local function getCanvasPosition(pin)
        -- (both values: "pin.GetCenter and pin:GetCenter()" kept only the first, so y was always nil and no pin was
        -- ever placed; luacheck's W221 found it)
        local x, y
        if pin.GetCenter then
            x, y = pin:GetCenter()
        end
        local left, top = canvas:GetLeft(), canvas:GetTop()
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        if not (x and y and left and top and width and height) or width <= 0 or height <= 0 then
            return nil, nil
        end
        local pinScale, canvasScale = pin:GetEffectiveScale(), canvas:GetEffectiveScale()
        return (x * pinScale - left * canvasScale) / (width * canvasScale),
            (top * canvasScale - y * pinScale) / (height * canvasScale)
    end
    for _, child in ipairs(canvas and canvas.GetChildren and { canvas:GetChildren() } or {}) do
        local data = child.isLeaMapsPin and type(child.data) == "table" and child.data
        if
            data
            and ENTRANCE_KINDS[data[1]] ~= nil
            and type(data[2]) == "number"
            and type(data[3]) == "number"
            and child:IsShown()
        then
            entrances[#entrances + 1] =
                { x = data[2] / 100, y = data[3] / 100, isRaid = ENTRANCE_KINDS[data[1]], frame = child }
        end
        -- MapUtils' entrance icons: its world-map pins (worldMap) whose entry is a dungeon
        local entry = child.worldMap == true and type(child.entry) == "table" and child.entry
        if entry and entry.kind == "dungeon" and child:IsShown() then
            local x, y = getCanvasPosition(child)
            if x then
                entrances[#entrances + 1] = { x = x, y = y, isRaid = entry.entrance == "raid", frame = child }
            end
        end
    end
    if map and map.EnumeratePinsByTemplate then
        local isRead, pins = pcall(map.EnumeratePinsByTemplate, map, "DungeonEntrancePinTemplate")
        for pin in isRead and pins or function() end do
            local x, y
            if pin.GetPosition then
                x, y = pin:GetPosition()
            end
            if type(x) == "number" and type(y) == "number" and pin:IsShown() then
                entrances[#entrances + 1] = { x = x, y = y, isRaid = pin.isRaid == true, frame = pin }
            end
        end
    end
    return entrances
end

---Puts each dungeon's mark on the entrance icon another addon draws near it, so the entrance has one mark:
---theirs, circled by our quests.
---@return table attached [frame] = true for each icon a mark now sits on, so it is no obstacle to our marks
function MapMarks.attachToEntrances(marks, entrances)
    local attached = {}
    for _, mark in ipairs(marks) do
        if mark.kind == "dungeon" then
            local nearest, nearestDistance
            for _, entrance in ipairs(entrances) do
                local distance = math.sqrt((entrance.x - mark.x) ^ 2 + (entrance.y - mark.y) ^ 2)
                if
                    distance <= MAX_ENTRANCE_DISTANCE
                    and not attached[entrance.frame]
                    and (not nearest or distance < nearestDistance)
                then
                    nearest, nearestDistance = entrance, distance
                end
            end
            if nearest then
                mark.x, mark.y, mark.entrancePin = nearest.x, nearest.y, nearest.frame
                mark.isRaid = mark.isRaid or nearest.isRaid
                attached[nearest.frame] = true
            end
        end
    end
    return attached
end

---Keeps the party plain to see on the map: a soft dark patch under each member's dot (the game draws the dots
---over our marks), and no square near a member or the player. Runs after each drawing and a few times a second
---while the map is open, as the party moves.
function MapMarks.updateParty()
    local map = State.drawn.map
    if not map or not State.markLayer or not State.drawn.width then
        return
    end
    local mapId = map:GetMapID()
    local clear = {}
    local function addUnit(unit, radius)
        local position = mapId and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapId, unit)
        if position then
            local x, y = position:GetXY()
            if x and y and (x ~= 0 or y ~= 0) then
                clear[#clear + 1] = {
                    x = x * State.drawn.width * State.drawn.scale,
                    y = y * State.drawn.height * State.drawn.scale,
                    radius = radius,
                    isMember = unit ~= "player",
                    mapX = x,
                    mapY = y,
                }
            end
        end
    end
    addUnit("player", PLAYER_CLEAR)
    if not (IsInGroup and not IsInGroup()) then -- (alone, nobody to look up)
        for _, unit in ipairs(ns.Party.getUnits()) do
            addUnit(unit, MEMBER_CLEAR)
        end
    end
    -- Nobody moved (to half a pixel) since the last look at this drawing: nothing to do. This runs a few times a
    -- second while the map is open, and went over every spawn's icon each time.
    local key = tostring(State.drawn.drawId)
    for _, point in ipairs(clear) do
        key = key .. string.format(":%.0f,%.0f", point.x * 2, point.y * 2)
    end
    if key == State.drawn.partyKey then
        return
    end
    State.drawn.partyKey = key
    if MapMarks.World.isOn() then
        MapMarks.World.clearNear(map, clear) -- (the kept drawing's spawn marks: each where it is on the map)
    end
    State.pools.halos.usedCount = 0
    for _, point in ipairs(clear) do
        if point.isMember then
            -- With the areas, over their fill and under every pin: it darkens the map under the dot, nothing else
            local halo = acquire(State.pools.halos, function()
                return State.areaLayer:CreateTexture(nil, "OVERLAY", nil, 7)
            end)
            halo:SetTexture(SOFT_DOT)
            halo:SetVertexColor(0, 0, 0, 0.75)
            halo:SetSize(HALO_SIZE / State.drawn.scale, HALO_SIZE / State.drawn.scale)
            halo:ClearAllPoints()
            halo:SetPoint(
                "CENTER",
                State.areaLayer,
                "TOPLEFT",
                point.x / State.drawn.scale,
                -point.y / State.drawn.scale
            )
        end
    end
    for index = State.pools.halos.usedCount + 1, #State.pools.halos do
        State.pools.halos[index]:Hide()
    end
    for _, square in ipairs(State.drawn.squares) do
        local isClear = true
        for _, point in ipairs(clear) do
            if (square.x - point.x) ^ 2 + (square.y - point.y) ^ 2 < point.radius * point.radius then
                isClear = false
                break
            end
        end
        -- Only an icon whose turn it is to hide or show is touched (each is shown as it is drawn)
        if isClear ~= (square.isClear ~= false) then
            square.isClear = isClear
            if square.glow then
                square.glow:SetShown(isClear)
                square.glyph:SetShown(isClear)
            else
                for _, texture in ipairs(square.textures or { square.texture }) do
                    texture:SetShown(isClear)
                end
            end
        end
    end
end

---Draws the marks of the map now showing. The quest's shapes grow with the map as it zooms; marks keep
---their size on screen.
-- The marks' size against the zoom: full size while the map shows ground at this many pixels a yard or more (a
-- zone's own map), smaller as it shows more, down to MIN_MARK_SCALE; by the square root, so they shrink gently
local FULL_SIZE_PIXELS_PER_YARD = 0.12 -- the Barrens, the widest zone, on its own windowed map
local MIN_MARK_SCALE = 0.4 -- with no pills to gather them, far out they are drawn this small

---@return number scale How large the marks are drawn on a map at its zoom: 1 at a zone's own size, smaller zoomed out
---@param pixelsAcross number The map's whole width on screen
function MapMarks.getMarkScale(mapId, pixelsAcross)
    local yards = mapId and MapMarks.getMapYards(mapId)
    if not yards or yards <= 0 or not pixelsAcross or pixelsAcross <= 0 then
        return MapMarks.getMarkScaleAt(nil)
    end
    return MapMarks.getMarkScaleAt(pixelsAcross / yards)
end

---@return number scale As MapMarks.getMarkScale, for a map drawn at so many pixels a yard on screen (measured off the
---screen itself, whatever map is underneath)
function MapMarks.getMarkScaleAt(pixelsPerYard)
    -- Times the size the player chose for map marks
    local chosen = math.max(0.5, math.min(2, tonumber(ns.settings.mapMarkScale) or 1))
    if not pixelsPerYard or pixelsPerYard <= 0 then
        return chosen
    end
    return chosen * math.max(MIN_MARK_SCALE, math.min(1, math.sqrt(pixelsPerYard / FULL_SIZE_PIXELS_PER_YARD)))
end

---@return boolean isAboveZones The map shows more than a zone: a continent, the world, the cosmos
function MapMarks.isAboveZones(mapId)
    local info = mapId and C_Map and C_Map.GetMapInfo and ns.Database.getMapInfo(mapId)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    return type(info) == "table" and type(info.mapType) == "number" and info.mapType < zoneType
end

---The map underneath changed (a new zone, or OpenMap's view crossing into one): the marks still laid out for the
---last map are hidden at once, so none stands in a wrong place until they are drawn again for this one.
function MapMarks.hideUntilDrawn(map)
    MapMarks.useMap(map)
    if State.markLayer then
        State.markLayer:Hide()
    end
    if State.areaLayer then
        State.areaLayer:Hide()
    end
    if State.drawn.pinLayer then
        State.drawn.pinLayer:Hide()
        State.drawn.glowLayer:Hide()
    end
end

---The layers of marks held to their spots (with the kept drawing): the marks' own, and under it their glows'. Both
---lie on the map and are sized against its zoom as a whole, each mark placed on its layer in the layer's units (a
---mark's own). Nothing of them is touched while the map is dragged or zooms: they grow with it through a zoom, as
---all of the kept drawing does, and are sized and placed for the zoom once it has settled (MapMarks.followZoom).
---(They hung on anchors of the map before, one a mark, to keep their size through a zoom: every anchor was one
---more thing the game laid out again at every frame of a drag.)
local function ensurePinLayers(map, canvas)
    local drawn = State.drawn
    if not drawn.pinLayer then
        for _, name in ipairs({ "glowLayer", "pinLayer" }) do
            local layer = ns.CreateFrame("Frame", nil, canvas)
            layer:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
            layer:SetSize(1, 1)
            drawn[name] = layer
        end
    end
    MapMarks.setLayerLevel(drawn.glowLayer, MapMarks.getAreaFrameLevel(map) + 5)
    MapMarks.setLayerLevel(drawn.pinLayer, State.frameLevel + 1)
    MapMarks.showLayer(drawn.glowLayer)
    MapMarks.showLayer(drawn.pinLayer)
end

-- A mark is a dozen regions (its glow, ring, text, icon, a coin's rim, face and gleam...), most of them hidden for
-- any one kind of mark: a quest giver's "!" shows one. The game lays out again, on every frame of a drag or a zoom,
-- whatever hangs from the map, hidden or not; so a mark's parts that do not show let go of it (their anchors kept
-- aside), and hang back as they were the moment they are shown or placed again, whoever does it: while a part
-- rests, its own showing and placing are stood in for (RESTING_METHODS), and what Widgets.place knows of its place
-- is watched (Widgets.place sets a part's points past its own methods).
local RESTING_METHODS = { "Show", "SetShown", "ClearAllPoints", "SetPoint", "SetAllPoints" }
local standIns = {}

---@return function own A resting part's own method under the one standing in for it: its remembering one
---(Widgets.remember), or the game's
local function getOwn(part, saved, name)
    return saved[name] or getmetatable(part).__index[name]
end

---@return boolean isKept What Widgets.place knows of a resting part's place is what it knew as the part went to
---rest: Widgets.place has not placed it since
local function isPlaceKept(part, saved)
    return part.omqPoint == saved.keptPoint
        and part.omqRelativeTo == saved.keptRelativeTo
        and part.omqRelativePoint == saved.keptRelativePoint
        and part.omqX == saved.keptX
        and part.omqY == saved.keptY
end

---Gives a resting part its anchors back, unless it was placed anew meanwhile (it stands where it was put then).
local function hangBack(part, saved)
    if not saved.isLetGo then
        return
    end
    saved.isLetGo = false
    if saved.count > 0 and isPlaceKept(part, saved) then
        local raw = part.omqRaw
        local setPoint = type(raw) == "table" and raw.SetPoint or getOwn(part, saved, "SetPoint")
        for position = 1, saved.count * 5, 5 do
            setPoint(
                part,
                saved[position],
                saved[position + 1],
                saved[position + 2],
                saved[position + 3],
                saved[position + 4]
            )
        end
    end
end

local function wakePart(part)
    local saved = part.omqRest
    if not saved or not saved.isResting then
        return
    end
    saved.isResting = false
    for index = 1, #RESTING_METHODS do
        local name = RESTING_METHODS[index]
        part[name] = saved[name] -- (its own again; nil: the game's)
    end
    hangBack(part, saved)
end

function standIns.Show(self)
    local saved = self.omqRest
    wakePart(self)
    return getOwn(self, saved, "Show")(self)
end

function standIns.SetShown(self, isShown)
    local saved = self.omqRest
    if isShown then
        wakePart(self)
    end
    return getOwn(self, saved, "SetShown")(self, isShown)
end

-- (cleared by its owner while it rests: there is nothing to hang back)
function standIns.ClearAllPoints(self)
    local saved = self.omqRest
    saved.isLetGo = false
    return getOwn(self, saved, "ClearAllPoints")(self)
end

-- (a point set while it rests: set among the points it had, as its owner means it; let go again at the next
-- drawing if it still does not show)
function standIns.SetPoint(self, ...)
    local saved = self.omqRest
    hangBack(self, saved)
    return getOwn(self, saved, "SetPoint")(self, ...)
end

function standIns.SetAllPoints(self, ...)
    local saved = self.omqRest
    saved.isLetGo = false -- (takes the place of every point it had)
    return getOwn(self, saved, "SetAllPoints")(self, ...)
end

---Lets a hidden part go of what it hangs from, its anchors kept for when it shows again. At rest already and not
---placed since, nothing is asked of the game.
local function restPart(part)
    local saved = part.omqRest
    if saved and saved.isResting and saved.isLetGo and isPlaceKept(part, saved) then
        return
    end
    local count = part:GetNumPoints()
    if type(count) ~= "number" then
        return
    end
    if not saved then
        saved = { count = 0 }
        part.omqRest = saved
    end
    if not saved.isResting then
        saved.isResting = true
        for index = 1, #RESTING_METHODS do
            local name = RESTING_METHODS[index]
            saved[name] = rawget(part, name)
            part[name] = standIns[name]
        end
    end
    if count > 0 or not saved.isLetGo then
        saved.count = count
        for position = 1, count do
            local point, relativeTo, relativePoint, x, y = part:GetPoint(position)
            local base = (position - 1) * 5
            saved[base + 1], saved[base + 2], saved[base + 3], saved[base + 4], saved[base + 5] =
                point, relativeTo, relativePoint, x, y
        end
        local raw = part.omqRaw
        if type(raw) == "table" then
            -- The game's own clearing: what Widgets.place knows of the part's place is kept, not forgotten, so
            -- placing it where it was asks nothing and leaves it at rest. Set point by point and held by one, that
            -- point is what is known of it from now on (it is where the part stands again when it wakes).
            raw.ClearAllPoints(part)
            if count == 1 and type(part.omqPoint) ~= "string" then
                part.omqPoint, part.omqRelativeTo, part.omqRelativePoint, part.omqX, part.omqY =
                    saved[1], saved[2], saved[3], saved[4], saved[5]
            end
        elseif count > 0 then
            getOwn(part, saved, "ClearAllPoints")(part)
        end
    end
    saved.isLetGo = true
    saved.keptPoint, saved.keptRelativeTo, saved.keptRelativePoint, saved.keptX, saved.keptY =
        part.omqPoint, part.omqRelativeTo, part.omqRelativePoint, part.omqX, part.omqY
end

---@return boolean isHidden A part does not show (a remembering part knows without asking the game)
local function isPartHidden(part)
    if type(part.omqRaw) == "table" and not part.omqHideWaits then
        local isShown = part.omqShown
        if isShown == nil then
            isShown = part:IsShown() == true -- (never shown or hidden through its own methods yet: asked once)
            part.omqShown = isShown
        end
        return not isShown
    end
    return not part:IsShown()
end

local needStamp = 0

---Marks what a part hangs from, of its own mark's parts, as needed: a part that shows needs those it hangs from to
---keep their place, hidden or not (a coin's face is set against its rim).
local function needAnchorsOf(part, button)
    local function need(target)
        if type(target) == "table" and target.omqPartOf == button and target.omqNeededAt ~= needStamp then
            target.omqNeededAt = needStamp
            needAnchorsOf(target, button)
        end
    end
    if type(part.omqPoint) == "string" then
        need(part.omqRelativeTo) -- (placed by Widgets.place: its one point)
    else
        local saved = part.omqRest
        if saved and saved.isResting and saved.isLetGo then
            for position = 2, saved.count * 5, 5 do
                need(saved[position])
            end
        else
            for index = 1, #(part.omqHeldBy or {}) do
                need(part.omqHeldBy[index])
            end
        end
    end
end

---Lists a mark's parts: its own regions, its glow (which lies on the glows' layer) and the frames within it (a
---dungeon's mark's quests). Listed again when Look makes more of them (it lets go of button.omqParts then).
local function listParts(button)
    local regionCount = button.GetNumRegions and button:GetNumRegions()
    if type(regionCount) ~= "number" then
        return false -- (the tests' stand-ins)
    end
    local parts = {}
    local function add(part)
        -- (a mask shows nothing by itself, and hangs from its picture; a line has no anchors to let go this way)
        if not part then
            return
        end
        local isListed = rawget(part, "omqIsListed") -- (what it is never changes: asked of the game once)
        if isListed == nil then
            isListed = not part:IsObjectType("MaskTexture") and not part:IsObjectType("Line")
            part.omqIsListed = isListed
        end
        if isListed then
            parts[#parts + 1] = part
            part.omqPartOf = button
        end
    end
    for _, region in ipairs({ button:GetRegions() }) do
        add(region)
    end
    for _, child in ipairs({ button:GetChildren() }) do
        add(child)
    end
    if button.glow and button.glow:GetParent() ~= button then
        add(button.glow)
    end
    -- What each is held by as it was made (point by point; Widgets.place's one point is read from what it keeps)
    for _, part in ipairs(parts) do
        local saved = part.omqRest
        if not (saved and saved.isResting and saved.isLetGo) then
            local heldBy
            for position = 1, part:GetNumPoints() or 0 do
                local _, relativeTo = part:GetPoint(position)
                if type(relativeTo) == "table" and relativeTo ~= button then
                    heldBy = heldBy or {}
                    heldBy[#heldBy + 1] = relativeTo
                end
            end
            part.omqHeldBy = heldBy
        end
    end
    parts.glow = button.glow
    return parts
end

---Lets a drawn mark's hidden parts go of it (restPart), but for those a part that shows hangs from.
local function restHiddenParts(button)
    local parts = rawget(button, "omqParts") -- (its own field: the tests' stand-ins answer any name)
    if parts == nil or (parts and parts.glow ~= button.glow) then
        parts = listParts(button)
        button.omqParts = parts
    end
    if not parts then
        return
    end
    needStamp = needStamp + 1
    for index = 1, #parts do
        local part = parts[index]
        part.omqIsHidden = isPartHidden(part)
        if not part.omqIsHidden then
            needAnchorsOf(part, button)
        end
    end
    for index = 1, #parts do
        local part = parts[index]
        if part.omqIsHidden then
            if part.omqNeededAt == needStamp then
                local saved = part.omqRest
                if saved and saved.isResting then
                    hangBack(part, saved) -- (hidden still, and at its place again: a part that shows hangs from it)
                end
            else
                restPart(part)
            end
        end
    end
end

-- The spawn marks on the mark layer: each keeps its size on screen as the map zooms (all anchored by their middle)
local FOLLOWED_POOLS = { "dots", "icons", "glows" }

local finishGivers, keepButtons -- (below, with the drawing)

---@return boolean isNothing The last drawing put no mark on the map, and the view is still inside the ground it was
---drawn for (zoomed in on a part of the map with nothing of the quests): laying the marks out again for another zoom
---would lay out none. Zoomed out or dragged past that ground, marks may have come into view: laid out then.
local function isNothingToLayOut(map)
    MapMarks.useMap(map)
    local pools, drawn = State.pools, State.drawn
    if pools.marks.usedCount > 0 or (pools.pills and pools.pills.usedCount > 0) then
        return false
    end
    -- (drawn for the whole map: there is no mark on it)
    return drawn.viewBounds == nil or ns.MapPins.isViewWithin(map, drawn.viewBounds)
end
local ZOOM_STILL_SECONDS = 0.12 -- how long the zoom stays put before the lines and spawn marks catch up with it
-- What is drawn reaches this far past the view on each side (of its width and height): a pan finds marks there, and
-- once it shows past them they are drawn again for the new view (MapPins.isViewCovered)
MapMarks.CULL_MARGIN = 0.25
local EASE_SECONDS = 0.15 -- how long the marks take to reach the size a settled zoom gives them
local WARM_SECONDS = 0.05 -- a zone's quests to pick up are worked out ahead this often at most (warmGivers)
local PAN_CHECK_SECONDS = 0.25 -- how often a pan of the game's own map is looked at (OpenMap's says so itself)
local MARKS_AGAIN_RATIO = 1.2 -- with the kept drawing, the quests' marks are laid out again once the zoom changed by this much

---The map zoomed a step: every mark keeps its spot on the map and its size on screen, at once and cheaply, with
---nothing laid out again (that waits until the zoom settles, MapPins). The mark layer scales with the map, so each
---mark is drawn smaller by as much as the map grew since the marks were laid out, its place given in its own units.
---@param isMoving boolean? The zoom is still on its way (a wheel step, OpenMap's glide over several frames): only the
---quest marks follow it now; the spawn marks, the areas' lines and the walks' dashes scale with the map meanwhile and
---catch up once the zoom has stayed put (MapMarks' OnUpdate), each once rather than at every frame of the glide
---@param isStill boolean? Said with isMoving: the zoom has stayed put, but the rest is not to catch up yet (a drawing
---is coming); the marks held to their spots are placed for it whatever their number
---@param easedMarkScale number? The marks' size for this frame, on its way to the settled zoom's (the easing below)
function MapMarks.followZoom(map, isMoving, isStill, easedMarkScale)
    MapMarks.useMap(map)
    local drawn = State.drawn
    local scale = map and map.GetCanvasScale and map:GetCanvasScale()
    if not drawn.scale or not drawn.drawId or type(scale) ~= "number" or scale <= 0 then
        return
    end
    drawn.followedScale = scale -- (followed for this frame: the mark layer's own check need not again)
    local ratio = drawn.scale / scale
    -- The quest marks take the size the new zoom gives them at once; only the spawn marks wait for it to settle
    local markScale = drawn.markScale or 1
    if map == WorldMapFrame and drawn.width then
        markScale = MapMarks.getMarkScale(map:GetMapID(), drawn.width * scale)
    end
    local glowScale = ratio * markScale / (drawn.markScale or 1)
    local isPinned = drawn.isPinned == true
    -- While the zoom is on its way the marks keep the very size on screen they have (the size the new zoom gives
    -- them waits for it to stay put): a mark whose size on screen changes has its text drawn anew by the game, every
    -- letter of it, and through a zoom that was every mark's at every frame, whatever else the map showed
    local isHeld = isMoving and not isStill
    if isHeld then
        markScale = drawn.pinMarkScale or drawn.markScale or markScale
        drawn.ease = nil
    elseif easedMarkScale then
        markScale = easedMarkScale
    elseif
        isPinned
        and drawn.pinMarkScale
        and drawn.pinnedScale == scale
        and math.abs(markScale / drawn.pinMarkScale - 1) > 0.02
        and GetTime
    then
        -- The zoom has stayed put and gives the marks another size: they glide to it over a few frames (the
        -- markLayer's OnUpdate), where they jumped. Their texts are drawn anew for those few frames, once a zoom,
        -- not at every frame of it.
        drawn.ease = { from = drawn.pinMarkScale, to = markScale, startedAt = GetTime() }
        markScale = drawn.pinMarkScale
    end
    if
        isPinned
        and drawn.pinLayer
        and (drawn.pinnedScale ~= scale or (not isHeld and drawn.pinMarkScale ~= markScale))
    then
        -- Held to their spots: the two layers sized against the zoom, and each mark placed on its spot again, by as
        -- far as the laying out moved it from there (one call a mark), at every frame of a zoom: they keep their
        -- size and spot all through it
        local pinScale = markScale / scale
        drawn.pinScale, drawn.pinnedScale, drawn.pinMarkScale = pinScale, scale, markScale
        drawn.pinLayer:SetScale(pinScale)
        drawn.glowLayer:SetScale(pinScale)
        local marks = State.pools.marks
        for index = 1, marks.usedCount do
            local button = marks[index]
            if button.pinX then
                ns.Widgets.place(
                    button,
                    "CENTER",
                    drawn.pinLayer,
                    "TOPLEFT",
                    (button.pinX * scale + button.pinLeft) / markScale,
                    -(button.pinY * scale + button.pinTop) / markScale
                )
            end
        end
    end
    local function rememberSize(region)
        if region.followDrawId ~= drawn.drawId then
            region.followDrawId = drawn.drawId
            region.baseWidth, region.baseHeight = region:GetWidth() or 0, region:GetHeight() or 0
        end
    end
    local pools = State.pools
    for index = 1, (isPinned and 0 or pools.marks.usedCount) do
        local button = pools.marks[index]
        local place = button.mark and button.mark.place
        if place then
            local buttonScale = markScale * ratio
            button:SetScale(buttonScale)
            button.zoomScale = buttonScale
            -- (the map opening sets its zoom a few times over, mostly to what it was: nothing passed on then)
            ns.Widgets.place(
                button,
                "CENTER",
                State.markLayer,
                "TOPLEFT",
                place.left / buttonScale,
                -place.top / buttonScale
            )
            if button.glow and button.glow:IsShown() then
                rememberSize(button.glow)
                button.glow:SetSize(button.glow.baseWidth * glowScale, button.glow.baseHeight * glowScale)
            end
        end
    end
    -- The soft dark patches under the party's dots lie on the areas' layer, which grows with the zoom: kept their own
    -- size on screen (they were blown up into a big dark blot for a moment when zooming in from far)
    local haloSize = HALO_SIZE / scale
    for index = 1, (pools.halos and pools.halos.usedCount or 0) do
        pools.halos[index]:SetSize(haloSize, haloSize)
    end
    for index = 1, (pools.pills and pools.pills.usedCount or 0) do
        local pill = pools.pills[index]
        local place = pill.mark and pill.mark.place
        if place then
            pill:SetScale(ratio)
            ns.Widgets.place(pill, "CENTER", State.markLayer, "TOPLEFT", place.left / ratio, -place.top / ratio)
        end
    end
    drawn.isPinSizeSettled = not isHeld
    if isMoving then
        if not isStill then
            drawn.isFollowPending, drawn.zoomMovedAt = true, GetTime and GetTime() or 0
        end
        return
    end
    drawn.isFollowPending = false
    -- The zoom came back to where the rest was last sized for (the map opening, OpenMap's opening glide, a wheel step
    -- there and back): every line and spawn already has that size, and going over them all again is thousands of
    -- calls into the game for nothing
    if drawn.caughtUpScale == scale then
        return
    end
    drawn.caughtUpScale = scale
    -- Lines on the area layer (the areas' edges, the walks' dashes) keep their width on screen
    MapMarks.followAreaZoom(ratio)
    local trailLines = pools.trailLines
    for index = 1, (trailLines and trailLines.usedCount or 0) do
        local line = trailLines[index]
        if line.baseThickness then
            line:SetThickness(line.baseThickness * ratio)
        end
    end
    for _, name in ipairs(FOLLOWED_POOLS) do
        local pool = pools[name]
        for index = 1, (pool and pool.usedCount or 0) do
            local region = pool[index]
            rememberSize(region)
            region:SetSize(region.baseWidth * glowScale, region.baseHeight * glowScale) -- as the marks: the new zoom's size
        end
    end
end

-- "Rough" (Spoilers): a dashed circle round where an objective is, in its quest's colour on a faint wash of it, as a
-- walk's dashes (MapMarks.paintDashes, on the walks' lines, which keep their width on screen as the map zooms)
local ROUGH_FILL_ALPHA, FOCUSED_ROUGH_FILL_ALPHA = 0.07, 0.14
local ROUGH_DASH_PIXELS = 8 -- the circle is drawn as straight legs this long on screen, at least 24, at most 96
local NONE = {}

local function createRoughFill()
    local fill = ns.Widgets.remember(State.areaLayer:CreateTexture(nil, "ARTWORK", nil, 0))
    fill:SetTexture(Style.CIRCLE_MASK) -- (the round mask is a white disc)
    return fill
end

---Draws the rough circles of the marks drawn (and of a dungeon's marks' quests), and keeps each for hovering:
---pointed at anywhere inside, its quest's tooltip says "Somewhere here".
local function drawRoughCircles(marks, width, height, scale)
    local pools = State.pools
    pools.trailLines = pools.trailLines or { usedCount = 0 }
    pools.roughFills = pools.roughFills or { usedCount = 0 }
    local function makeLine(sublevel)
        local line = acquire(pools.trailLines, function()
            return State.areaLayer:CreateLine(nil, "ARTWORK")
        end)
        line:SetDrawLayer("ARTWORK", 3 + sublevel) -- (as the walks: over the areas' edges)
        return line
    end
    local note = ns.L("Somewhere here")
    local function drawCircles(mark)
        local color = MapMarks.getQuestColor(mark.number, mark.questId)
        local isFocused = mark.isFocused == true
        for _, circle in ipairs(mark.roughCircles) do
            local x, y, radius = circle.x * width, circle.y * height, circle.radius * width
            local fill = acquire(pools.roughFills, createRoughFill)
            fill:SetVertexColor(
                color[1],
                color[2],
                color[3],
                isFocused and FOCUSED_ROUGH_FILL_ALPHA or ROUGH_FILL_ALPHA
            )
            fill:SetSize(radius * 2, radius * 2)
            ns.Widgets.place(fill, "CENTER", State.areaLayer, "TOPLEFT", x, -y)
            local steps = math.max(24, math.min(96, math.floor(2 * math.pi * radius * scale / ROUGH_DASH_PIXELS)))
            local points = {}
            for step = 0, steps do
                local angle = step / steps * 2 * math.pi
                points[step + 1] = { x = x + radius * math.cos(angle), y = y + radius * math.sin(angle) }
            end
            MapMarks.paintDashes(
                points,
                makeLine,
                color,
                isFocused and Style.FOCUSED_AREA_EDGE_ALPHA or Style.AREA_EDGE_ALPHA,
                scale
            )
            State.drawn.areas[#State.drawn.areas + 1] = {
                points = { { x = x, y = y } },
                reach = radius,
                questId = mark.questId,
                isFocused = isFocused,
                note = note,
            }
        end
    end
    for _, mark in ipairs(marks) do
        if mark.roughCircles then
            drawCircles(mark)
        end
        for _, member in ipairs(mark.members or NONE) do
            if member.roughCircles then
                drawCircles(member)
            end
        end
    end
end

---@return table[] areas, table[] spots The quest areas and spawn marks a map shows now, whichever drawing made them
---(this one's State.drawn.areas and .squares, the kept drawing's own): for the tests and the simulator's scenarios
function MapMarks.listDrawn(map)
    MapMarks.useMap(map or WorldMapFrame)
    local drawn = State.drawn
    if not MapMarks.World.isOn() then
        return drawn.areas, drawn.squares
    end
    local areas, spots = MapMarks.World.list(map or WorldMapFrame, drawn.scale or 1)
    for _, area in ipairs(drawn.areas) do
        areas[#areas + 1] = area
    end
    for _, square in ipairs(drawn.squares) do
        spots[#spots + 1] = square
    end
    return areas, spots
end

---@return number[] questIds The quests the world map's marks show now, each once: for counting a peek (Alt held over
---the map, MapHover) as a hint for each
function MapMarks.getDrawnQuestIds()
    local questIds, isListed = {}, {}
    local function add(questId)
        if questId and not isListed[questId] then
            isListed[questId] = true
            questIds[#questIds + 1] = questId
        end
    end
    local function addMark(mark)
        add(mark.questId)
        for _, questId in ipairs(mark.questIds or NONE) do
            add(questId)
        end
        for _, member in ipairs(mark.members or NONE) do
            addMark(member)
        end
    end
    MapMarks.useMap(WorldMapFrame)
    local pool = State.pools.marks
    for index = 1, pool.usedCount do
        if pool[index].mark then
            addMark(pool[index].mark)
        end
    end
    return questIds
end

---@return string key What a mark is, whatever map it is drawn on and wherever it is laid out: its kind, its quest,
---and who or what it stands for (the giver, the dungeon, which of the quest's objectives, its picture)
local function getMarkKey(mark)
    return tostring(mark.kind)
        .. ":"
        .. tostring(mark.questId)
        .. ":"
        .. tostring(mark.handsKey or mark.dungeonId or mark.number or "")
        .. ":"
        .. tostring(mark.itemIcon or mark.glyph or "")
end

---The buttons for the marks of a drawing, each mark on the button that showed it at the last drawing where one did.
---A button's parts remember what they show (Widgets.remember), so a mark drawn again on its own button asks nothing
---of the game but its place. Handed out by their place in the list instead, as they were, a zoom or a pan that
---brought one mark into view or took one out put every mark after it on another's button, each dressed anew from
---nothing: most of what a drawing of the marks cost. The pool is put in the new order (its used buttons first).
---@param marksBefore number How many of the pool's buttons the last drawing used
---@return table[] buttons One for each mark, in the marks' order
keepButtons = function(marks, marksBefore)
    local pool = State.pools.marks
    local byKey = {}
    for index = 1, math.min(marksBefore, #pool) do
        local button = pool[index]
        local key = rawget(button, "omqMarkKey")
        if key then
            local list = byKey[key]
            if not list then
                list = {}
                byKey[key] = list
            end
            list[#list + 1] = button
        end
    end
    local buttons, isTaken = {}, {}
    for index, mark in ipairs(marks) do
        local key = getMarkKey(mark)
        mark.buttonKey = key
        local list = byKey[key]
        local button = list and table.remove(list, 1)
        if button then
            buttons[index], isTaken[button] = button, true
        end
    end
    -- The marks new to this drawing: on the buttons no mark kept, those of the last drawing's first
    local free = {}
    for index = 1, #pool do
        if not isTaken[pool[index]] then
            free[#free + 1] = pool[index]
        end
    end
    local nextFree = 1
    for index, mark in ipairs(marks) do
        local button = buttons[index]
        if not button then
            button = free[nextFree]
            nextFree = nextFree + 1
            if not button then
                button = MapMarks.createMarkButton()
            end
            buttons[index] = button
        end
        button.omqMarkKey = mark.buttonKey
        if button.omqLoose ~= false then
            button.omqLoose = false -- (let go of the map while unused; whoever takes it places it)
            button:Show()
        end
    end
    for index = 1, #marks do
        pool[index] = buttons[index]
    end
    for index = nextFree, #free do
        pool[#marks + index - nextFree + 1] = free[index]
    end
    pool.usedCount = #marks
    return buttons
end

local SPARE_MARKS, SPARE_AT_ONCE = 150, 2 -- marks made ahead on a joined-up map, in all and at a time
local SPARE_MARK = { kind = "giver", questId = 0, lines = { "" }, isFocused = false }

---Makes a couple of marks ahead, while a joined-up map is open and still, until the map has some to spare: each made,
---dressed as a quest to pick up (what most of a far view's marks are), its hidden parts let go, and put away. Zooming
---out to a continent asks for a hundred marks at once; made and dressed in that one drawing they were most of its
---longest frame. A mark made ahead and then given a quest to pick up asks almost nothing of the game.
---@return boolean isMade
function MapMarks.makeSpareButtons(map)
    MapMarks.useMap(map)
    local pool, drawn = State.pools.marks, State.drawn
    if #pool >= SPARE_MARKS or not drawn.isPinned or not drawn.pinLayer then
        return false
    end
    for _ = 1, SPARE_AT_ONCE do
        local button = MapMarks.createMarkButton()
        button.omqParent = drawn.pinLayer
        button:SetParent(drawn.pinLayer)
        button.glowScale = 1
        MapMarks.applyMarkLook(button, SPARE_MARK)
        if button.glow and button.glowLayer ~= drawn.glowLayer then
            button.glowLayer = drawn.glowLayer
            button.glow:SetParent(drawn.glowLayer)
            button.glow:SetDrawLayer("OVERLAY")
        end
        button:SetScale(1)
        restHiddenParts(button)
        button.mark = nil -- (no quest's mark: nothing points at it or reads it until a drawing takes it)
        button.omqLoose = true
        button:Hide()
        button:ClearAllPoints()
        if button.glow then
            button.glow:Hide()
        end
        pool[#pool + 1] = button
    end
    return true
end

local isFinishingGivers = false

---A drawing left some zones' quests to pick up for later (Compose's pacing: MapMarks.areGiversIncomplete). They are
---worked out a few zones each frame, for whatever map shows by then, and the marks drawn again once: drawn again
---after every few zones, a continent's forty were ten drawings of every mark in a row.
finishGivers = function(map)
    if not C_Timer or map ~= WorldMapFrame then
        ns.MapPins.queueRefresh()
        return
    end
    if isFinishingGivers then
        return
    end
    isFinishingGivers = true
    local function step()
        MapMarks.useMap(map)
        local drawn = State.drawn
        local mapId = map:IsShown() and map:GetMapID()
        if not mapId then
            isFinishingGivers = false -- (closed: the map's next drawing asks again)
            return
        end
        if drawn.mapId == mapId then
            ns.MapPins.setView(drawn.view, drawn.viewBounds, drawn.viewZones) -- (the zones the drawing was for)
        end
        if MapMarks.finishGivers(mapId) then
            isFinishingGivers = false
            ns.MapPins.queueRefresh()
        else
            C_Timer.After(0, step)
        end
    end
    C_Timer.After(0, step)
end

local MAX_KEPT_MAPS = 6 -- how many maps' worked-out marks are kept at once

---What was worked out for the maps a view passed over is let go: the quests changed in something they show.
function MapMarks.forgetKeptMarks(map)
    MapMarks.useMap(map)
    State.drawn.keptMarks = nil
end

---@param isSwapOnly boolean? Nothing changed but the map underneath the view (OpenMap's, as it is zoomed and dragged
---across zones): where this map's marks were worked out before, since the last drawing asked for by anything else,
---they are drawn as they are. Zooming in and out over the same ground puts the same two or three maps underneath
---over and over, each working out a hundred marks from the quests each time.
---@param isZoomOnly boolean? Nothing changed but the zoom (the kept drawing's marks, laid out again once a zoom
---settles): the marks worked out at the last drawing are laid out as they are, nothing worked out anew
function MapMarks.draw(map, isZoomOnly, isSwapOnly)
    MapMarks.useMap(map)
    if not isZoomOnly and not isSwapOnly then
        State.drawn.keptMarks = nil -- (drawn for a change of the quests, or of what the player wants shown)
    end
    local canvas, mapId = map:GetCanvas(), map:GetMapID()
    ensureLayers(map, canvas)
    MapMarks.showLayer(State.markLayer)
    MapMarks.showLayer(State.areaLayer)
    State.drawn.drawId = (State.drawn.drawId or 0) + 1 -- what the zoom follows (followZoom) is this drawing's
    if State.pools.pills then
        for index = 1, #State.pools.pills do
            State.pools.pills[index]:SetScale(1) -- a pill the last zoom shrank is drawn at its size again
        end
    end
    if not State.markLayer:GetScript("OnUpdate") then
        local elapsedSeconds, sincePanCheck, sinceWarmed = 0, 0, 0
        local follow
        State.markLayer:SetScript("OnUpdate", function(_, elapsed)
            ns.Timing.measure("marks follow the map (each frame)", follow, elapsed)
        end)
        follow = function(elapsed)
            -- Every frame, whatever moved the map (a wheel, OpenMap's glide, a pan across a zone's edge) and in
            -- whatever order the map said so: the marks follow its zoom at once, and once it shows another map
            -- underneath than they were drawn for, they hide till drawn again, never a frame in a wrong place
            local drawn = MapMarks.getDrawn(map)
            local canvasScale = map.GetCanvasScale and map:GetCanvasScale()
            if map.GetMapID and drawn.mapId and map:GetMapID() ~= drawn.mapId then
                MapMarks.hideUntilDrawn(map)
                ns.MapPins.queueRefresh(map == WorldMapFrame) -- (another map underneath, nothing else)
                return
            end
            if type(canvasScale) == "number" and canvasScale ~= drawn.followedScale then
                MapMarks.followZoom(map, true)
            elseif drawn.ease then
                -- The marks on their way to the size the settled zoom gives them (followZoom): a smooth step
                local ease = drawn.ease
                local share = math.min(1, ((GetTime and GetTime() or 0) - ease.startedAt) / EASE_SECONDS)
                if share >= 1 then
                    drawn.ease = nil
                end
                local smooth = share * share * (3 - 2 * share)
                MapMarks.followZoom(map, true, true, ease.from + (ease.to - ease.from) * smooth)
            elseif
                drawn.isFollowPending
                and drawn.isPinned
                and not drawn.isPinSizeSettled
                and (GetTime and GetTime() or 0) - (drawn.zoomMovedAt or 0) >= ZOOM_STILL_SECONDS
            then
                -- The zoom has stayed put with the marks at the size they had before it: the size this zoom gives
                -- them now, once, whether or not they are about to be laid out again (on a joined-up map that waits
                -- most of a second, for the map that may come underneath)
                MapMarks.followZoom(map, true, true)
            elseif
                drawn.isFollowPending
                and (GetTime and GetTime() or 0) - (drawn.zoomMovedAt or 0) >= ZOOM_STILL_SECONDS
                and not (map == WorldMapFrame and ns.MapPins.isRedrawComing())
            then
                -- (not while the marks are about to be drawn again anyway, for this zoom: a zoom out over OpenMap's
                -- joined-up map that showed ground they were not drawn for, or the map underneath changing)
                -- The zoom has stayed put: the rest catches up, once
                MapMarks.followZoom(map)
                -- The zoom crossed a step of the spawns' thinning: drawn again, adding or taking away spawns, none moved
                local mapYards = drawn.mapId and MapMarks.getMapYards(drawn.mapId)
                local liveMarkScale = map == WorldMapFrame
                        and drawn.width
                        and MapMarks.getMarkScale(drawn.mapId, drawn.width * canvasScale)
                    or 1
                liveMarkScale = liveMarkScale * MapMarks.getSpawnMarkerRoom(ns.settings.spawnMarkerScale) -- (as the drawing reckons it)
                local isRedrawDue
                if MapMarks.World.isOn() then
                    -- The kept drawing shows the spawns and areas of the new zoom by itself. Only the quests' marks
                    -- are laid out again, and only after a real change of zoom: which stand side by side, which
                    -- zones' gather into pills
                    local ratio = drawn.scale and canvasScale / drawn.scale or 1
                    isRedrawDue = ratio > MARKS_AGAIN_RATIO or ratio < 1 / MARKS_AGAIN_RATIO
                else
                    isRedrawDue = mapYards
                        and drawn.width
                        and MapMarks.chooseSpawnSpacing(
                                drawn.width * canvasScale / mapYards,
                                drawn.spawnSpacing,
                                liveMarkScale
                            )
                            ~= drawn.spawnSpacing
                end
                if isRedrawDue and MapMarks.World.isOn() and map == WorldMapFrame and isNothingToLayOut(map) then
                    isRedrawDue = false -- (no mark where the view is, and none can have come into it)
                end
                if isRedrawDue and MapMarks.World.isOn() and map == WorldMapFrame then
                    -- (the marks alone, as they were worked out: laid out for this zoom. On a joined-up view once
                    -- another map can have come underneath it, which draws them anyway: laid out before that, every
                    -- zoom across a zone's edge laid them out twice, a third of a second apart)
                    if drawn.view then
                        ns.MapPins.queueSettledRefresh(true, drawn.zoomMovedAt)
                    else
                        ns.MapPins.queueRearrange()
                    end
                elseif isRedrawDue then
                    -- (on a joined-up view, once another map can have come underneath it: drawn once, for that)
                    if drawn.view and map == WorldMapFrame then
                        ns.MapPins.queueSettledRefresh()
                    else
                        ns.MapPins.queueRefresh()
                    end
                end
            end
            -- A joined-up map open and still: the quests to pick up of the zones round it worked out ahead, a zone at
            -- a time and twenty a second at most (MapMarks.warmGivers), never in a fight
            sinceWarmed = sinceWarmed + elapsed
            if
                sinceWarmed >= WARM_SECONDS
                and map == WorldMapFrame
                and drawn.view
                and not drawn.isFollowPending
                and not ns.MapPins.isRedrawComing()
                and not (InCombatLockdown and InCombatLockdown())
            then
                sinceWarmed = 0
                ns.MapPins.setView(drawn.view, drawn.viewBounds, drawn.viewZones)
                if not ns.Timing.measure("quests to pick up worked out ahead", MapMarks.warmGivers, drawn.mapId) then
                    ns.Timing.measure("marks made ahead", MapMarks.makeSpareButtons, map)
                end
            end
            -- The game's own map dragged past what was drawn: drawn again for the new view once it stays put
            sincePanCheck = sincePanCheck + elapsed
            if sincePanCheck >= PAN_CHECK_SECONDS then
                sincePanCheck = 0
                if map == WorldMapFrame and drawn.cullBounds and not drawn.view then
                    ns.MapPins.handleViewMoved()
                end
            end
            elapsedSeconds = elapsedSeconds + elapsed
            if elapsedSeconds >= PARTY_SECONDS then
                elapsedSeconds = 0
                MapMarks.useMap(map)
                MapMarks.updateParty()
            end
        end
    end
    local marksBefore = State.pools.marks.usedCount -- (the marks drawn last: each keeps its button, keepButtons)
    for _, pool in pairs(State.pools) do
        pool.usedCount = 0
    end
    State.areasDrawn = false -- set by the areas' drawing; drawn without them, the areas kept are let go (below)
    local scale = map:GetCanvasScale()
    scale = type(scale) == "number" and scale > 0 and scale or 1
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    width, height = type(width) == "number" and width or 1, type(height) == "number" and height or 1
    MapMarks.setLayerScale(State.markLayer, 1 / scale)
    State.drawn.map, State.drawn.width, State.drawn.height, State.drawn.scale = map, width, height, scale
    State.drawn.mapId, State.drawn.followedScale = mapId, scale -- what the marks stand for; the zoom is followed from here
    State.drawn.isFollowPending = false -- (laid out at this zoom: nothing to catch up)
    State.drawn.caughtUpScale = scale -- (every line and spawn mark is drawn for this zoom: followZoom's catching up)
    -- The step the spawns are thinned to at this zoom, kept from the last drawing near a step's edge
    local mapYards = mapId and MapMarks.getMapYards(mapId)
    local spacingMarkScale = map == WorldMapFrame and MapMarks.getMarkScale(mapId, width * scale) or 1
    spacingMarkScale = spacingMarkScale * MapMarks.getSpawnMarkerRoom(ns.settings.spawnMarkerScale)
    State.drawn.spawnSpacing =
        MapMarks.chooseSpawnSpacing(mapYards and width * scale / mapYards, State.drawn.spawnSpacing, spacingMarkScale)
    -- Another addon joining the neighbouring zones onto the world map (OpenMap): their marks too, placed as it
    -- draws them, as far as the view reaches and a margin past it
    local view = map == WorldMapFrame and ns.Compatibility.getMapView(map) or nil
    local viewBounds = view and ns.MapPins.getVisibleBounds(map, ns.MapPins.VIEW_MARGIN) or nil
    if view and not viewBounds then
        -- The view not laid out yet (a frame after the map changed): a generous reach rather than the game's map
        -- alone, so the marks never switch between the two ways of placing them
        viewBounds = { left = -1, top = -1, right = 2, bottom = 2 }
    end
    local viewZones = view and ns.MapPins.getViewZones(view, mapId, viewBounds) or nil
    State.drawn.view, State.drawn.viewBounds, State.drawn.viewZones = view, viewBounds, viewZones
    ns.MapPins.setView(view, viewBounds, viewZones)
    -- What is drawn: the part of the map in view and a margin round it (CULL_MARGIN of the view on each side), the
    -- areas, spawns and walks out there left out; drawn again once a pan or zoom shows past it (MapPins). Kept from
    -- the last drawing while the view is still inside it, so a drawing that moved nothing lays nothing out again.
    -- Zoomed out to where the whole map shows, nothing is left out.
    local cull
    local visible = map == WorldMapFrame and ns.MapPins.getVisibleBounds(map, 0) or nil
    if visible and (visible.left > 0 or visible.top > 0 or visible.right < 1 or visible.bottom < 1 or view) then
        local kept = State.drawn.cullBounds
        if
            kept
            and State.drawn.cullMapId == mapId
            and State.drawn.cullScale == scale
            and visible.left >= kept.left
            and visible.right <= kept.right
            and visible.top >= kept.top
            and visible.bottom <= kept.bottom
        then
            cull = kept
        else
            cull = ns.MapPins.getVisibleBounds(map, MapMarks.CULL_MARGIN)
        end
    end
    -- The kept drawing (World) draws the tracked quests' areas and spawn marks: laid out once in the world and only
    -- moved by the map, so nothing of them is cut to the view here or drawn again for it. What is left to this
    -- drawing (the quests' marks, the walks, where the quest selected to pick up starts) is little, and drawn whole.
    local isKept = MapMarks.World.isOn()
    if isKept then
        cull = nil
    else
        MapMarks.World.hide(map)
    end
    State.drawn.cullBounds, State.drawn.cullMapId, State.drawn.cullScale = cull, mapId, scale
    State.drawn.squares = {} -- filled again by whichever look draws spawns
    State.drawn.areas = {} -- filled by "icons and areas"

    -- A continent's or the world's map left clean, the player's choice
    local isHiddenHere = ns.settings.shouldHideMarksOnContinents and MapMarks.isAboveZones(mapId)
    -- What the player chose to see (Spoilers; nil in Guide): Alt held over the world map shows it everything
    local isPeekIgnored = map ~= WorldMapFrame
    local spoilers = MapMarks.getSpoilers(isPeekIgnored)
    local marks
    local composedKey = tostring(mapId) .. "|" .. tostring(ns.MapPins.getViewKey()) .. "|" .. tostring(isHiddenHere)
    local keptMarks = State.drawn.keptMarks
    if not keptMarks then
        keptMarks = { count = 0, byKey = {} }
        State.drawn.keptMarks = keptMarks
    end
    local kept = isSwapOnly and State.drawn.features and keptMarks.byKey[composedKey]
    if kept then
        -- This map's marks as they were worked out when it was last underneath: drawn as a zoom's are, below
        State.drawn.composed, State.drawn.composedKey = kept, composedKey
        isZoomOnly = true
    end
    if isZoomOnly and State.drawn.composed and State.drawn.composedKey == composedKey then
        -- The same marks as last drawn, where they were worked out to stand (an entrance icon's mark is set on its
        -- icon again below)
        marks = State.drawn.composed
        for _, mark in ipairs(marks) do
            mark.x, mark.y, mark.entrancePin = mark.composedX, mark.composedY, nil
        end
    else
        isZoomOnly = false
        marks = mapId and ns.settings.shouldShowMapPins and not isHiddenHere and MapMarks.compose(mapId, isPeekIgnored)
            or {}
        for _, mark in ipairs(marks) do
            mark.composedX, mark.composedY = mark.x, mark.y
        end
        State.drawn.composed, State.drawn.composedKey = marks, composedKey
        if MapMarks.areGiversIncomplete then
            -- (the quests to pick up of the zones not worked out yet: a few more each frame with nothing drawn, then
            -- drawn once with all of them)
            MapMarks.areGiversIncomplete = false
            State.drawn.composedKey = nil
            finishGivers(map)
        elseif not keptMarks.byKey[composedKey] then
            if keptMarks.count >= MAX_KEPT_MAPS then
                keptMarks.count, keptMarks.byKey = 0, {}
            end
            keptMarks.count = keptMarks.count + 1
            keptMarks.byKey[composedKey] = marks
        else
            keptMarks.byKey[composedKey] = marks
        end
    end
    if map == WorldMapFrame then
        -- Zoomed out past where a mark's spot means anything: a pill for each zone too small on screen
        marks = MapMarks.gatherZonePills(marks, mapId, width * scale)
    end
    if isKept and viewBounds then
        -- (with the kept drawing, a quest to pick up is worked out for every zone it starts in, in view or not: those
        -- that stand outside what is drawn are left out here)
        local inBounds = {}
        for _, mark in ipairs(marks) do
            if
                mark.x >= viewBounds.left
                and mark.x <= viewBounds.right
                and mark.y >= viewBounds.top
                and mark.y <= viewBounds.bottom
            then
                inBounds[#inBounds + 1] = mark
            end
        end
        marks = inBounds
    end
    local attachedEntrances = MapMarks.attachToEntrances(marks, MapMarks.getEntrancePins(map, canvas))
    local markRects = {}
    -- Where each mark goes: its own spot, or its place in a tidy block with the marks it would cover
    -- Only the marks that are there whatever is selected take part: the quest in focus has a mark for each of
    -- its areas, but only the one it has out of focus (its largest area) is laid out with the others; its other
    -- marks, and the selected quest's hand-in, sit on their exact spots over the rest
    local mainFocused
    for _, mark in ipairs(marks) do
        if
            mark.isFocused
            and mark.kind ~= "giver"
            and not mark.isPreview
            and (
                not mainFocused
                or (mark.spawnCount or #(mark.points or {}))
                    > (mainFocused.spawnCount or #(mainFocused.points or {}))
            )
        then
            mainFocused = mark
        end
    end
    local items, arranged, onTop, pinned, pills = {}, {}, {}, {}, {}
    -- Zoomed out, the marks are drawn smaller, so they cover less of the map they stand on (the pills keep their
    -- size: their names must stay readable)
    local markScale = map == WorldMapFrame and MapMarks.getMarkScale(mapId, width * scale) or 1
    State.drawn.markScale = markScale
    -- With the kept drawing the marks are held to their spots too (ensurePinLayers)
    local isPinned = isKept
    State.drawn.isPinned = isPinned
    if isPinned then
        ensurePinLayers(map, canvas)
        State.drawn.pinScale, State.drawn.pinnedScale = markScale / scale, scale
        State.drawn.pinMarkScale, State.drawn.isPinSizeSettled, State.drawn.ease = markScale, true, nil
        MapMarks.setLayerScale(State.drawn.pinLayer, State.drawn.pinScale)
        MapMarks.setLayerScale(State.drawn.glowLayer, State.drawn.pinScale)
    elseif State.drawn.pinLayer then
        State.drawn.pinLayer:Hide()
        State.drawn.glowLayer:Hide()
    end
    local markParent = isPinned and State.drawn.pinLayer or State.markLayer
    local glowParent = isPinned and State.drawn.glowLayer or State.areaLayer
    local pinnedButtons = {}
    for index, mark in ipairs(marks) do
        local markWidth, markHeight, raise = MapMarks.getFootprint(mark)
        if mark.kind ~= "zonePill" then
            markWidth, markHeight, raise = markWidth * markScale, markHeight * markScale, raise * markScale
        end
        items[index] = {
            mark = mark,
            index = index,
            width = markWidth,
            height = markHeight,
            raise = raise,
            spotLeft = mark.x * width * scale,
            spotTop = mark.y * height * scale - raise,
        }
        -- (a dungeon is laid out with the rest whatever quest is selected, so selecting one never moves it)
        local isOnTop = mark.isPreview
            or (mark.isFocused and mark.kind ~= "giver" and mark.kind ~= "dungeon" and mark ~= mainFocused)
        if mark.entrancePin then
            -- A dungeon's mark on another addon's entrance icon stays on it, whatever else is near (that addon's
            -- own pins, such as Leatrix Maps' zone arrows, included); the other marks keep clear of it
            pinned[#pinned + 1] = items[index]
        elseif isOnTop then
            onTop[#onTop + 1] = items[index]
        elseif mark.kind == "zonePill" then
            pills[#pills + 1] = items[index]
        else
            arranged[#arranged + 1] = items[index]
        end
    end
    -- The focused quest's other marks and the hand-in first, as near their exact spots as other addons' (and the
    -- game's) pins allow; then the rest, clear of all of those
    local obstacles = MapMarks.getForeignPins(canvas, attachedEntrances)
    local pinRects = { unpack(obstacles) } -- other addons' pins only, for the dungeon marks' quests to keep off
    for _, item in ipairs(pinned) do
        item.left, item.top = item.spotLeft, item.spotTop
        -- Its quests' places now, round the other addon's pins, so the other marks keep clear of them
        item.mark.orbitAngles = MapMarks.chooseOrbitAngles(item.mark, item, obstacles)
        item.width, item.height = MapMarks.getFootprint(item.mark)
        obstacles[#obstacles + 1] = getRect(item.left, item.top, item.width, item.height)
    end
    -- Laid out within the map, or within what is drawn of the joined-on view
    local bounds = { left = 0, top = 0, right = width * scale, bottom = height * scale }
    if viewBounds then
        bounds = {
            left = viewBounds.left * width * scale,
            top = viewBounds.top * height * scale,
            right = viewBounds.right * width * scale,
            bottom = viewBounds.bottom * height * scale,
        }
    end
    MapMarks.arrangeMarks(onTop, obstacles, bounds)
    for _, item in ipairs(onTop) do
        obstacles[#obstacles + 1] = getRect(item.left, item.top, item.width, item.height)
    end
    if #pills > 0 then
        -- The zones' pills keep clear of the dungeon entrances and their level labels as well, which other marks
        -- are drawn round; laid out first, they push the marks round them aside rather than the other way round
        local pillObstacles = { unpack(obstacles) }
        for _, rect in ipairs(MapMarks.getEntranceRects(mapId, width * scale, height * scale)) do
            pillObstacles[#pillObstacles + 1] = rect
        end
        MapMarks.arrangeMarks(pills, pillObstacles, bounds)
        for _, item in ipairs(pills) do
            obstacles[#obstacles + 1] = getRect(item.left, item.top, item.width, item.height)
        end
    end
    MapMarks.arrangeMarks(arranged, obstacles, bounds)
    -- No square under another addon's pin either
    for _, rect in ipairs(obstacles) do
        markRects[#markRects + 1] = rect
    end
    local order = {}
    for index, mark in ipairs(marks) do
        mark.place = items[index]
        if mark.kind == "zonePill" then
            -- A zone too small on screen for its marks: its pill, laid out with the marks, drawn on its own
            local pill = acquire(State.pools.pills, function()
                return MapMarks.createPill(State.markLayer)
            end)
            local pillWidth, pillHeight = MapMarks.applyPillLook(pill, mark, (State.markLayer:GetFrameLevel() or 1) + 1)
            ns.Widgets.place(pill, "CENTER", State.markLayer, "TOPLEFT", mark.place.left, -mark.place.top)
            markRects[#markRects + 1] = {
                left = mark.place.left - pillWidth / 2,
                right = mark.place.left + pillWidth / 2,
                top = mark.place.top - pillHeight / 2,
                bottom = mark.place.top + pillHeight / 2,
            }
        else
            order[#order + 1] = mark
        end
    end
    local questGroups, groupByQuest, giverAreaGroups, featureByQuest = {}, {}, {}, {}
    -- With the kept drawing: what the quests show, worked out here (a zoom alone keeps the last drawing's), and each
    -- quest's own for its mark's glow in its area's colour
    local features
    if isKept then
        features = isZoomOnly and State.drawn.features
        -- (a map left clean, a continent's by the player's choice or with the marks off: the kept drawing is hidden
        -- there as it is, and shown again on the next map as it was)
        local isShownHere = mapId and ns.settings.shouldShowMapPins and not isHiddenHere
        if isShownHere then
            MapMarks.World.show(map)
        else
            MapMarks.World.hide(map)
        end
        if not features then
            isZoomOnly = false
            features = isShownHere and MapMarks.composeFeatures(isPeekIgnored) or NONE
        end
        State.drawn.features, State.drawn.isKeptShown = features, isShownHere
        for _, feature in ipairs(features) do
            featureByQuest[feature.questId] = feature
        end
    end
    local markButtons, buttonIndex = nil, 0
    for _, mark in ipairs(order) do
        -- (on continent and world maps too: areas are fitted onto them cheaply, the spawns thinned to the zoom)
        -- Each spawn knows its quest, for its tooltip
        for _, point in ipairs(mark.points or {}) do
            point.questId = point.questId or mark.questId
        end
        for _, point in ipairs(mark.fadedPoints or {}) do
            point.questId = point.questId or mark.questId
        end
        for _, point in ipairs(mark.spawnPoints or {}) do
            point.questId = point.questId or mark.questId
        end
        -- The selected quest to pick up: where it starts (the creatures that drop its item), each creature in its
        -- own shade, as its dot on the quest page
        if mark.kind == "giver" and mark.isFocused and mark.points and #mark.points > 0 then
            for _, point in ipairs(mark.points) do
                local shade = point.shade or 0
                local key = mark.questId * 10 + shade
                local group = groupByQuest[key]
                if not group then
                    group = {
                        questId = key,
                        hoverQuestId = mark.questId,
                        color = QUEST_SHADES[shade] or QUEST_BLUE,
                        isFocused = true,
                        points = {},
                    }
                    groupByQuest[key] = group
                    questGroups[#questGroups + 1] = group
                    -- The giver's glow takes the colour of its (first) area
                    giverAreaGroups[mark.questId] = giverAreaGroups[mark.questId] or group
                end
                group.points[#group.points + 1] = point
            end
        end
        -- Each tracked quest's places together, in the quest's colour, for "icons and areas" (the kept drawing takes
        -- them from the quests themselves: MapMarks.composeFeatures)
        if
            not isKept
            and mark.questId
            and mark.kind == "objective"
            and not mark.isRough
            and (mark.spawnPoints or mark.points or mark.fadedPoints)
        then
            local group = groupByQuest[mark.questId]
            if not group then
                group = {
                    questId = mark.questId,
                    color = MapMarks.getQuestColor(mark.number, mark.questId),
                    isFocused = mark.isFocused == true,
                    points = {},
                }
                -- (where its creatures walk only with its objectives shown exactly: Spoilers)
                group.hasNoPatrols = spoilers ~= nil and spoilers.get("objectives", mark.questId) ~= "exact"
                groupByQuest[mark.questId] = group
                questGroups[#questGroups + 1] = group
            end
            for _, point in ipairs(mark.spawnPoints or mark.points or {}) do
                group.points[#group.points + 1] = point
            end
            for _, point in ipairs(mark.fadedPoints or {}) do
                group.points[#group.points + 1] = point
            end
        end
        if mark.kind == "dungeon" and not mark.entrancePin then
            mark.orbitAngles = MapMarks.chooseOrbitAngles(mark, mark.place, pinRects)
        end
        markButtons = markButtons or keepButtons(order, marksBefore)
        buttonIndex = buttonIndex + 1
        local button = markButtons[buttonIndex]
        if button.omqParent ~= markParent then
            button.omqParent = markParent
            button:SetParent(markParent)
        end
        -- A quest with a coloured area: its mark's glow, the same size as the gold one, is in the area's colour,
        -- tying the two together while the mark itself stays gold; faint out of focus, as strong as the gold glow
        -- when highlighted, its gold ring saying it is the one highlighted
        local areaGroup = MapMarks.hasQuestColours()
            and (
                mark.kind == "objective" and (featureByQuest[mark.questId] or groupByQuest[mark.questId])
                or mark.kind == "giver" and giverAreaGroups[mark.questId]
            )
        if areaGroup then
            local color = areaGroup.color
            button.glowRed, button.glowGreen, button.glowBlue = color[1], color[2], color[3]
            button.glowAlpha = mark.isFocused and FOCUSED_AREA_TINT_ALPHA or AREA_TINT_ALPHA
        else
            button.glowRed, button.glowGreen, button.glowBlue, button.glowAlpha = nil, nil, nil, nil
        end
        -- The focused quest's glow lies with the areas, under every mark and every other pin, never over one; that
        -- layer is not scaled against the zoom, so the glow's size is turned into its units
        button.glowScale = isPinned and 1 or markScale / scale -- (the glows' own layer is sized as the marks' is)
        local drawnWidth, drawnHeight = MapMarks.applyMarkLook(button, mark)
        if button.glow and button.glowLayer ~= glowParent then
            button.glowLayer = glowParent
            button.glow:SetParent(glowParent)
            button.glow:SetDrawLayer("OVERLAY")
        end
        local place = mark.place
        if isPinned then
            -- On the marks' own layer, which lies on the map and is sized against its zoom: its place in the layer's
            -- units (the mark's own size's). Kept: its spot on the map (in the map's units) and how far the laying
            -- out moved it from there (in pixels), for placing it again once a zoom has settled (followZoom)
            button:SetScale(1)
            button.zoomScale = nil
            button.pinX, button.pinY = mark.x * width, mark.y * height
            button.pinLeft, button.pinTop = place.left - button.pinX * scale, place.top - button.pinY * scale
            ns.Widgets.place(button, "CENTER", markParent, "TOPLEFT", place.left / markScale, -place.top / markScale)
            pinnedButtons[#pinnedButtons + 1] = button
        else
            -- Drawn at the zoom's size; its place is in the layer's units, so it is given in the scaled mark's own
            button.pinX = nil
            button:SetScale(markScale)
            ns.Widgets.place(
                button,
                "CENTER",
                State.markLayer,
                "TOPLEFT",
                place.left / markScale,
                -place.top / markScale
            )
        end
        -- What the mark covers, so no spawn mark is drawn under it: the mark as drawn, with its gold ring when in
        -- focus, and a little room; its soft glow may lie under spawn marks, which then sit close round it
        local coverWidth = math.max((drawnWidth or place.width) * markScale, place.width) + 2 * SPAWN_ROOM
        local coverHeight = math.max((drawnHeight or place.height) * markScale, place.height) + 2 * SPAWN_ROOM
        if button.focusRing and button.focusRing:IsShown() then
            coverWidth = math.max(coverWidth, (button.focusRing:GetWidth() or 0) * markScale + 2 * SPAWN_ROOM)
            coverHeight = math.max(coverHeight, (button.focusRing:GetHeight() or 0) * markScale + 2 * SPAWN_ROOM)
        end
        markRects[#markRects + 1] = {
            left = place.left - coverWidth / 2,
            right = place.left + coverWidth / 2,
            top = place.top - coverHeight / 2,
            bottom = place.top + coverHeight / 2,
            questId = mark.questId,
        }
    end
    -- The quests' places, as chosen in the settings: the areas round their spawns (a light wash, the shapes, or
    -- none) and a marker on each spawn (of one of the kinds, or none). The quest in focus last, over the others.
    table.sort(questGroups, function(first, second)
        if first.isFocused ~= second.isFocused then
            return second.isFocused
        end
        return first.questId < second.questId
    end)
    if MapMarks.hasAreas() then
        drawQuestAreas(questGroups, width, height, scale, mapId)
    end
    if MapMarks.getSpawnMarker() ~= "none" then
        drawIcons(questGroups, width, height, scale, markRects)
    end
    local patrolGroups = questGroups
    if isKept then
        patrolGroups = NONE -- (the tracked quests' walks are the kept drawing's too; the givers' stay here)
        if not isZoomOnly and State.drawn.isKeptShown then -- (a zoom it follows by itself)
            MapMarks.World.draw(map, features)
        end
    end
    drawPatrols(patrolGroups, MapMarks.getGiverPatrolLines(mapId, isPeekIgnored), width, height, scale, mapId) -- in every look
    if spoilers then
        drawRoughCircles(order, width, height, scale) -- (objectives "rough": Spoilers)
    end
    if not State.areasDrawn then
        MapMarks.releaseAreas() -- a look without areas (or nothing to mark here): the kept ones are taken off the map
    end
    -- What the pools hold and this drawing did not use: hidden, and let go of the map (the game lays out again, on
    -- every frame of a drag or a zoom, whatever hangs from it, hidden or not; each is placed anew when next used)
    for name, pool in pairs(State.pools) do
        if name ~= "halos" then
            for index = pool.usedCount + 1, #pool do
                local item = pool[index]
                if item.omqLoose ~= true then
                    item.omqLoose = true
                    item:Hide()
                    item:ClearAllPoints()
                    if pool == State.pools.marks and item.glow then
                        item.glow:Hide() -- it lies on the mark layer, apart from its mark
                    end
                end
            end
        end
    end
    -- The marks drawn: their parts that do not show let go of them (once all is dressed and shown as it will be)
    for _, button in ipairs(pinnedButtons) do
        restHiddenParts(button)
    end
    MapMarks.updateParty()
end
