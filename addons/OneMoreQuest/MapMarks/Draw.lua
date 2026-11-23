local addonName, ns = ...

-- The map's marks: drawing on a map (other addons' pins, dungeon entrances, the party, and the drawing itself).
local MapMarks = ns.MapMarks
local Style, State = ns.MapMarksStyle, ns.MapMarksState
local Compose, Look, Layout, Shapes, Areas, Draw = ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw
local drawIcons, drawPatrols, drawQuestAreas = Areas.drawIcons, Areas.drawPatrols, Areas.drawQuestAreas
local ensureLayers, getRect = Layout.ensureLayers, Layout.getRect
local HALO_SIZE, MEMBER_CLEAR, PARTY_SECONDS, PLAYER_CLEAR, acquire = Look.HALO_SIZE, Look.MEMBER_CLEAR, Look.PARTY_SECONDS, Look.PLAYER_CLEAR, Look.acquire
local AREA_TINT_ALPHA, FOCUSED_AREA_TINT_ALPHA, MAX_POINTS, QUEST_BLUE, QUEST_SHADES, SOFT_DOT = Style.AREA_TINT_ALPHA, Style.FOCUSED_AREA_TINT_ALPHA, Style.MAX_POINTS, Style.QUEST_BLUE, Style.QUEST_SHADES, Style.SOFT_DOT
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
        if child ~= State.markLayer and child ~= State.areaLayer and child:IsShown() and (child:GetAlpha() or 1) > 0.05 and not (skipped and skipped[child]) then
            local left, bottom, width, height = child:GetRect()
            local scale = child:GetEffectiveScale()
            if left and width and width > 0 then
                local layerWidth, layerHeight = width * scale / layerScale, height * scale / layerScale
                if layerWidth <= MAX_FOREIGN_PIN_SIZE and layerHeight <= MAX_FOREIGN_PIN_SIZE then
                    local layerLeft = (left * scale - canvasLeft * canvasScale) / layerScale
                    local layerTop = (canvasTop * canvasScale - (bottom + height) * scale) / layerScale
                    local insetX, insetY = layerWidth * FOREIGN_PIN_INSET, layerHeight * FOREIGN_PIN_INSET
                    rects[#rects + 1] = { left = layerLeft + insetX, top = layerTop + insetY, right = layerLeft + layerWidth - insetX, bottom = layerTop + layerHeight - insetY }
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
        local x, y = pin.GetCenter and pin:GetCenter()
        local left, top = canvas:GetLeft(), canvas:GetTop()
        local width, height = canvas:GetWidth(), canvas:GetHeight()
        if not (x and y and left and top and width and height) or width <= 0 or height <= 0 then
            return nil, nil
        end
        local pinScale, canvasScale = pin:GetEffectiveScale(), canvas:GetEffectiveScale()
        return (x * pinScale - left * canvasScale) / (width * canvasScale), (top * canvasScale - y * pinScale) / (height * canvasScale)
    end
    for _, child in ipairs(canvas and canvas.GetChildren and { canvas:GetChildren() } or {}) do
        local data = child.isLeaMapsPin and type(child.data) == "table" and child.data
        if data and ENTRANCE_KINDS[data[1]] ~= nil and type(data[2]) == "number" and type(data[3]) == "number" and child:IsShown() then
            entrances[#entrances + 1] = { x = data[2] / 100, y = data[3] / 100, isRaid = ENTRANCE_KINDS[data[1]], frame = child }
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
                if distance <= MAX_ENTRANCE_DISTANCE and not attached[entrance.frame] and (not nearest or distance < nearestDistance) then
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
                clear[#clear + 1] = { x = x * State.drawn.width * State.drawn.scale, y = y * State.drawn.height * State.drawn.scale, radius = radius, isMember = unit ~= "player" }
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
    State.pools.halos.usedCount = 0
    for _, point in ipairs(clear) do
        if point.isMember then
            -- With the areas, over their fill and under every pin: it darkens the map under the dot, nothing else
            local halo = acquire(State.pools.halos, function() return State.areaLayer:CreateTexture(nil, "OVERLAY", nil, 7) end)
            halo:SetTexture(SOFT_DOT)
            halo:SetVertexColor(0, 0, 0, 0.75)
            halo:SetSize(HALO_SIZE / State.drawn.scale, HALO_SIZE / State.drawn.scale)
            halo:ClearAllPoints()
            halo:SetPoint("CENTER", State.areaLayer, "TOPLEFT", point.x / State.drawn.scale, -point.y / State.drawn.scale)
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
    -- Times the size the player chose for map marks
    local chosen = math.max(0.5, math.min(2, tonumber(ns.settings.mapMarkScale) or 1))
    local yards = mapId and MapMarks.getMapYards(mapId)
    if not yards or yards <= 0 or not pixelsAcross or pixelsAcross <= 0 then
        return chosen
    end
    local pixelsPerYard = pixelsAcross / yards
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
end

-- The spawn marks on the mark layer: each keeps its size on screen as the map zooms (all anchored by their middle)
local FOLLOWED_POOLS = { "dots", "icons", "glows" }

local ZOOM_STILL_SECONDS = 0.12 -- how long the zoom stays put before the lines and spawn marks catch up with it

---The map zoomed a step: every mark keeps its spot on the map and its size on screen, at once and cheaply, with
---nothing laid out again (that waits until the zoom settles, MapPins). The mark layer scales with the map, so each
---mark is drawn smaller by as much as the map grew since the marks were laid out, its place given in its own units.
---@param isMoving boolean? The zoom is still on its way (a wheel step, OpenMap's glide over several frames): only the
---quest marks follow it now; the spawn marks, the areas' lines and the walks' dashes scale with the map meanwhile and
---catch up once the zoom has stayed put (MapMarks' OnUpdate), each once rather than at every frame of the glide
function MapMarks.followZoom(map, isMoving)
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
    local function rememberSize(region)
        if region.followDrawId ~= drawn.drawId then
            region.followDrawId = drawn.drawId
            region.baseWidth, region.baseHeight = region:GetWidth() or 0, region:GetHeight() or 0
        end
    end
    local pools = State.pools
    for index = 1, pools.marks.usedCount do
        local button = pools.marks[index]
        local place = button.mark and button.mark.place
        if place then
            local buttonScale = markScale * ratio
            button:SetScale(buttonScale)
            button.zoomScale = buttonScale
            -- (the map opening sets its zoom a few times over, mostly to what it was: nothing passed on then)
            ns.Widgets.place(button, "CENTER", State.markLayer, "TOPLEFT", place.left / buttonScale, -place.top / buttonScale)
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
    if isMoving then
        drawn.isFollowPending, drawn.zoomMovedAt = true, GetTime and GetTime() or 0
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
        local line = acquire(pools.trailLines, function() return State.areaLayer:CreateLine(nil, "ARTWORK") end)
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
            fill:SetVertexColor(color[1], color[2], color[3], isFocused and FOCUSED_ROUGH_FILL_ALPHA or ROUGH_FILL_ALPHA)
            fill:SetSize(radius * 2, radius * 2)
            ns.Widgets.place(fill, "CENTER", State.areaLayer, "TOPLEFT", x, -y)
            local steps = math.max(24, math.min(96, math.floor(2 * math.pi * radius * scale / ROUGH_DASH_PIXELS)))
            local points = {}
            for step = 0, steps do
                local angle = step / steps * 2 * math.pi
                points[step + 1] = { x = x + radius * math.cos(angle), y = y + radius * math.sin(angle) }
            end
            MapMarks.paintDashes(points, makeLine, color, isFocused and Style.FOCUSED_AREA_EDGE_ALPHA or Style.AREA_EDGE_ALPHA, scale)
            State.drawn.areas[#State.drawn.areas + 1] = { points = { { x = x, y = y } }, reach = radius, questId = mark.questId,
                isFocused = isFocused, note = note }
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

function MapMarks.draw(map)
    MapMarks.useMap(map)
    local canvas, mapId = map:GetCanvas(), map:GetMapID()
    ensureLayers(map, canvas)
    State.markLayer:Show()
    State.areaLayer:Show()
    State.drawn.drawId = (State.drawn.drawId or 0) + 1 -- what the zoom follows (followZoom) is this drawing's
    if State.pools.pills then
        for index = 1, #State.pools.pills do
            State.pools.pills[index]:SetScale(1) -- a pill the last zoom shrank is drawn at its size again
        end
    end
    if not State.markLayer:GetScript("OnUpdate") then
        local elapsedSeconds = 0
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
                ns.MapPins.queueRefresh()
                return
            end
            if type(canvasScale) == "number" and canvasScale ~= drawn.followedScale then
                MapMarks.followZoom(map, true)
            elseif drawn.isFollowPending and (GetTime and GetTime() or 0) - (drawn.zoomMovedAt or 0) >= ZOOM_STILL_SECONDS
                and not (map == WorldMapFrame and ns.MapPins.isRedrawComing()) then
                -- (not while the marks are about to be drawn again anyway, for this zoom: a zoom out over OpenMap's
                -- joined-up map that showed ground they were not drawn for, or the map underneath changing)
                -- The zoom has stayed put: the rest catches up, once
                MapMarks.followZoom(map)
                -- The zoom crossed a step of the spawns' thinning: drawn again, adding or taking away spawns, none moved
                local mapYards = drawn.mapId and MapMarks.getMapYards(drawn.mapId)
                local liveMarkScale = map == WorldMapFrame and drawn.width and MapMarks.getMarkScale(drawn.mapId, drawn.width * canvasScale) or 1
                liveMarkScale = liveMarkScale * MapMarks.getSpawnMarkerRoom(ns.settings.spawnMarkerScale) -- (as the drawing reckons it)
                if mapYards and drawn.width and MapMarks.chooseSpawnSpacing(drawn.width * canvasScale / mapYards, drawn.spawnSpacing, liveMarkScale) ~= drawn.spawnSpacing then
                    -- (on a joined-up view, once another map can have come underneath it: drawn once, for that)
                    if drawn.view and map == WorldMapFrame then
                        ns.MapPins.queueSettledRefresh()
                    else
                        ns.MapPins.queueRefresh()
                    end
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
    for _, pool in pairs(State.pools) do
        pool.usedCount = 0
    end
    State.areasDrawn = false -- set by the areas' drawing; drawn without them, the areas kept are let go (below)
    local scale = map:GetCanvasScale()
    scale = type(scale) == "number" and scale > 0 and scale or 1
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    width, height = type(width) == "number" and width or 1, type(height) == "number" and height or 1
    State.markLayer:SetScale(1 / scale)
    State.drawn.map, State.drawn.width, State.drawn.height, State.drawn.scale = map, width, height, scale
    State.drawn.mapId, State.drawn.followedScale = mapId, scale -- what the marks stand for; the zoom is followed from here
    State.drawn.isFollowPending = false -- (laid out at this zoom: nothing to catch up)
    State.drawn.caughtUpScale = scale -- (every line and spawn mark is drawn for this zoom: followZoom's catching up)
    -- The step the spawns are thinned to at this zoom, kept from the last drawing near a step's edge
    local mapYards = mapId and MapMarks.getMapYards(mapId)
    local spacingMarkScale = map == WorldMapFrame and MapMarks.getMarkScale(mapId, width * scale) or 1
    spacingMarkScale = spacingMarkScale * MapMarks.getSpawnMarkerRoom(ns.settings.spawnMarkerScale)
    State.drawn.spawnSpacing = MapMarks.chooseSpawnSpacing(mapYards and width * scale / mapYards, State.drawn.spawnSpacing, spacingMarkScale)
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
    State.drawn.squares = {} -- filled again by whichever look draws spawns
    State.drawn.areas = {} -- filled by "icons and areas"

    -- A continent's or the world's map left clean, the player's choice
    local isHiddenHere = ns.settings.shouldHideMarksOnContinents and MapMarks.isAboveZones(mapId)
    -- What the player chose to see (Spoilers; nil in Guide): Alt held over the world map shows it everything
    local isPeekIgnored = map ~= WorldMapFrame
    local spoilers = MapMarks.getSpoilers(isPeekIgnored)
    local marks = mapId and ns.settings.shouldShowMapPins and not isHiddenHere and MapMarks.compose(mapId, isPeekIgnored) or {}
    if map == WorldMapFrame then
        -- Zoomed out past where a mark's spot means anything: a pill for each zone too small on screen
        marks = MapMarks.gatherZonePills(marks, mapId, width * scale)
    end
    local attachedEntrances = MapMarks.attachToEntrances(marks, MapMarks.getEntrancePins(map, canvas))
    local markRects = {}
    -- Where each mark goes: its own spot, or its place in a tidy block with the marks it would cover
    -- Only the marks that are there whatever is selected take part: the quest in focus has a mark for each of
    -- its areas, but only the one it has out of focus (its largest area) is laid out with the others; its other
    -- marks, and the selected quest's hand-in, sit on their exact spots over the rest
    local mainFocused
    for _, mark in ipairs(marks) do
        if mark.isFocused and mark.kind ~= "giver" and not mark.isPreview
            and (not mainFocused or #(mark.points or {}) > #(mainFocused.points or {})) then
            mainFocused = mark
        end
    end
    local items, arranged, onTop, pinned, pills = {}, {}, {}, {}, {}
    -- Zoomed out, the marks are drawn smaller, so they cover less of the map they stand on (the pills keep their
    -- size: their names must stay readable)
    local markScale = map == WorldMapFrame and MapMarks.getMarkScale(mapId, width * scale) or 1
    State.drawn.markScale = markScale
    for index, mark in ipairs(marks) do
        local markWidth, markHeight, raise = MapMarks.getFootprint(mark)
        if mark.kind ~= "zonePill" then
            markWidth, markHeight, raise = markWidth * markScale, markHeight * markScale, raise * markScale
        end
        items[index] = {
            mark = mark, index = index, width = markWidth, height = markHeight, raise = raise,
            spotLeft = mark.x * width * scale, spotTop = mark.y * height * scale - raise,
        }
        -- (a dungeon is laid out with the rest whatever quest is selected, so selecting one never moves it)
        local isOnTop = mark.isPreview or (mark.isFocused and mark.kind ~= "giver" and mark.kind ~= "dungeon" and mark ~= mainFocused)
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
        bounds = { left = viewBounds.left * width * scale, top = viewBounds.top * height * scale,
            right = viewBounds.right * width * scale, bottom = viewBounds.bottom * height * scale }
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
            local pill = acquire(State.pools.pills, function() return MapMarks.createPill(State.markLayer) end)
            local pillWidth, pillHeight = MapMarks.applyPillLook(pill, mark, (State.markLayer:GetFrameLevel() or 1) + 1)
            ns.Widgets.place(pill, "CENTER", State.markLayer, "TOPLEFT", mark.place.left, -mark.place.top)
            markRects[#markRects + 1] = { left = mark.place.left - pillWidth / 2, right = mark.place.left + pillWidth / 2,
                top = mark.place.top - pillHeight / 2, bottom = mark.place.top + pillHeight / 2 }
        else
            order[#order + 1] = mark
        end
    end
    local questGroups, groupByQuest, giverAreaGroups = {}, {}, {}
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
                    group = { questId = key, hoverQuestId = mark.questId, color = QUEST_SHADES[shade] or QUEST_BLUE, isFocused = true, points = {} }
                    groupByQuest[key] = group
                    questGroups[#questGroups + 1] = group
                    -- The giver's glow takes the colour of its (first) area
                    giverAreaGroups[mark.questId] = giverAreaGroups[mark.questId] or group
                end
                group.points[#group.points + 1] = point
            end
        end
        -- Each tracked quest's places together, in the quest's colour, for "icons and areas"
        if mark.questId and mark.kind == "objective" and not mark.isRough and (mark.spawnPoints or mark.points or mark.fadedPoints) then
            local group = groupByQuest[mark.questId]
            if not group then
                group = { questId = mark.questId, color = MapMarks.getQuestColor(mark.number, mark.questId), isFocused = mark.isFocused == true, points = {} }
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
        local button = acquire(State.pools.marks, MapMarks.createMarkButton)
        -- A quest with a coloured area: its mark's glow, the same size as the gold one, is in the area's colour,
        -- tying the two together while the mark itself stays gold; faint out of focus, as strong as the gold glow
        -- when highlighted, its gold ring saying it is the one highlighted
        local areaGroup = MapMarks.hasQuestColours() and (mark.kind == "objective" and groupByQuest[mark.questId]
            or mark.kind == "giver" and giverAreaGroups[mark.questId])
        if areaGroup then
            local color = areaGroup.color
            button.glowRed, button.glowGreen, button.glowBlue = color[1], color[2], color[3]
            button.glowAlpha = mark.isFocused and FOCUSED_AREA_TINT_ALPHA or AREA_TINT_ALPHA
        else
            button.glowRed, button.glowGreen, button.glowBlue, button.glowAlpha = nil, nil, nil, nil
        end
        -- The focused quest's glow lies with the areas, under every mark and every other pin, never over one; that
        -- layer is not scaled against the zoom, so the glow's size is turned into its units
        button.glowScale = markScale / scale
        local drawnWidth, drawnHeight = MapMarks.applyMarkLook(button, mark)
        if button.glow and button.glowLayer ~= State.areaLayer then
            button.glowLayer = State.areaLayer
            button.glow:SetParent(State.areaLayer)
            button.glow:SetDrawLayer("OVERLAY")
        end
        local place = mark.place
        -- Drawn at the zoom's size; its place is in the layer's units, so it is given in the scaled mark's own
        button:SetScale(markScale)
        ns.Widgets.place(button, "CENTER", State.markLayer, "TOPLEFT", place.left / markScale, -place.top / markScale)
        -- What the mark covers, so no spawn mark is drawn under it: the mark as drawn, with its gold ring when in
        -- focus, and a little room; its soft glow may lie under spawn marks, which then sit close round it
        local coverWidth = math.max((drawnWidth or place.width) * markScale, place.width) + 2 * SPAWN_ROOM
        local coverHeight = math.max((drawnHeight or place.height) * markScale, place.height) + 2 * SPAWN_ROOM
        if button.focusRing and button.focusRing:IsShown() then
            coverWidth = math.max(coverWidth, (button.focusRing:GetWidth() or 0) * markScale + 2 * SPAWN_ROOM)
            coverHeight = math.max(coverHeight, (button.focusRing:GetHeight() or 0) * markScale + 2 * SPAWN_ROOM)
        end
        markRects[#markRects + 1] = { left = place.left - coverWidth / 2, right = place.left + coverWidth / 2,
            top = place.top - coverHeight / 2, bottom = place.top + coverHeight / 2, questId = mark.questId }
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
    drawPatrols(questGroups, MapMarks.getGiverPatrolLines(mapId, isPeekIgnored), width, height, scale, mapId) -- in every look
    if spoilers then
        drawRoughCircles(order, width, height, scale) -- (objectives "rough": Spoilers)
    end
    if not State.areasDrawn then
        MapMarks.releaseAreas() -- a look without areas (or nothing to mark here): the kept ones are taken off the map
    end
    for name, pool in pairs(State.pools) do
        if name ~= "halos" then
            for index = pool.usedCount + 1, #pool do
                pool[index]:Hide()
                if pool == State.pools.marks and pool[index].glow then
                    pool[index].glow:Hide() -- it lies on the mark layer, apart from its mark
                end
            end
        end
    end
    MapMarks.updateParty()
end
