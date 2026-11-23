local addonName, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The map's marks: drawing quest areas and spawn icons (the game's own areas, the shapes worked out a slice a frame).
local MapMarks = ns.MapMarks
local Style, State = ns.MapMarksStyle, ns.MapMarksState
local Compose, Look, Layout, Shapes, Areas, Draw = ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw
local composePoints = Compose.composePoints
local acquire, createPools = Look.acquire, Look.createPools
local setTriangle = Shapes.setTriangle
local AREA_EDGE_ALPHA, AREA_EDGE_PIXELS, AREA_FILL_ALPHA, AREA_MIN_POINTS, AREA_REACH, AREA_REACH_YARDS = Style.AREA_EDGE_ALPHA, Style.AREA_EDGE_PIXELS, Style.AREA_FILL_ALPHA, Style.AREA_MIN_POINTS, Style.AREA_REACH, Style.AREA_REACH_YARDS
local AREA_RIM_ALPHA, AREA_RIM_COLOR, AREA_RIM_PIXELS, FADED_ICON_ALPHA, FADED_ICON_GLOW_ALPHA, FOCUSED_AREA_EDGE_ALPHA = Style.AREA_RIM_ALPHA, Style.AREA_RIM_COLOR, Style.AREA_RIM_PIXELS, Style.FADED_ICON_ALPHA, Style.FADED_ICON_GLOW_ALPHA, Style.FOCUSED_AREA_EDGE_ALPHA
local FOCUSED_AREA_FILL_ALPHA, FOCUSED_AREA_RIM_ALPHA, FOCUSED_ICON_GLOW_ALPHA, ICON_CELL, ICON_GLOW_SIZE, ICON_SIZE = Style.FOCUSED_AREA_FILL_ALPHA, Style.FOCUSED_AREA_RIM_ALPHA, Style.FOCUSED_ICON_GLOW_ALPHA, Style.ICON_CELL, Style.ICON_GLOW_SIZE, Style.ICON_SIZE
local SOFT_DOT, ZONE_MAP_TYPE = Style.SOFT_DOT, Style.ZONE_MAP_TYPE



-- Each map drawn on (the world map, the zone map) keeps its own layers, pools and what it drew; the module's
-- own values are those of the map being drawn on now
local mapStates, currentMapState = {}, nil

local switchMap

---Switches the drawing to a map's own layers, pools and drawing, so two maps never share pieces, and places points
---as that map was last drawn: with another addon's neighbours joined on (OpenMap), or the game's map alone.
function MapMarks.useMap(map)
    if not map then
        return
    end
    switchMap(map)
    ns.MapPins.setView(State.drawn.view, State.drawn.viewBounds, State.drawn.viewZones)
end

switchMap = function(map)
    local state = mapStates[map]
    if state and state == currentMapState then
        return
    end
    if currentMapState then
        currentMapState.areaLayer, currentMapState.markLayer, currentMapState.pools = State.areaLayer, State.markLayer, State.pools
        currentMapState.drawn, currentMapState.frameLevel = State.drawn, State.frameLevel
    elseif not state then
        -- The first map drawn on takes what was made at load
        mapStates[map] = { areaLayer = State.areaLayer, markLayer = State.markLayer, pools = State.pools, drawn = State.drawn, frameLevel = State.frameLevel }
        currentMapState = mapStates[map]
        return
    end
    if not state then
        state = { pools = createPools(), drawn = { squares = {}, areas = {} }, frameLevel = State.frameLevel }
        mapStates[map] = state
    end
    State.areaLayer, State.markLayer, State.pools = state.areaLayer, state.markLayer, state.pools
    State.drawn, State.frameLevel = state.drawn, state.frameLevel
    currentMapState = state
end

MapMarks.composePoints = composePoints -- places on one map, as the map puts them there (sub-zones included)
MapMarks.AREA_REACH = AREA_REACH
MapMarks.AREA_MIN_POINTS = AREA_MIN_POINTS
MapMarks.AREA_REACH_YARDS = AREA_REACH_YARDS
MapMarks.AREA_CELLS_PER_REACH = 3 -- the grid an area is traced on: this many cells to its reach
MapMarks.MIN_AREA_CELL = 0.008 -- but no finer than this much of the map's width: on a vast zone (the Barrens) finer
-- detail cannot be seen, and every piece more is one more the game moves as the map is dragged
MapMarks.EDGE_SMOOTHING = 2 -- times the edge's corners are cut (Chaikin), so it curves instead of bending
MapMarks.EDGE_TOLERANCE = 0.08 -- an edge's points that bend it by less than this much of a cell are left out

local mapYards = {} -- [uiMapId] = its width in yards, or false when the game cannot say

---@return number? yards How wide a map is in the world, from where its corners lie
function MapMarks.getMapYards(uiMapId)
    if mapYards[uiMapId] == nil then
        local _, _, west = ns.Geometry.getWorldPosition(uiMapId, 0, 0)
        local _, _, eastWest = ns.Geometry.getWorldPosition(uiMapId, 100, 100)
        mapYards[uiMapId] = west and eastWest and west - eastWest > 0 and west - eastWest or false
    end
    return mapYards[uiMapId] or nil
end
-- How a quest's areas are drawn, in each of the two looks (settings.areaStyle): "filled", a light wash in the quest's
-- colour under the spawn markers, the quest in focus stronger; "blob", the shapes, as the game draws its own quest
-- areas: plainly filled, with a bright edge, the quest in focus bolder still. The minimap's fills are a little
-- stronger than the map's: the land under them is darker.
local AREA_LOOKS = {
    filled = {
        fillAlpha = AREA_FILL_ALPHA, focusedFillAlpha = FOCUSED_AREA_FILL_ALPHA,
        edgeAlpha = AREA_EDGE_ALPHA, focusedEdgeAlpha = FOCUSED_AREA_EDGE_ALPHA,
        edgePixels = AREA_EDGE_PIXELS, focusedEdgePixels = AREA_EDGE_PIXELS,
        rimColor = AREA_RIM_COLOR, rimAlpha = AREA_RIM_ALPHA, focusedRimAlpha = FOCUSED_AREA_RIM_ALPHA,
    },
    blob = {
        fillAlpha = 0.2, focusedFillAlpha = 0.4,
        edgeAlpha = 0.8, focusedEdgeAlpha = 1,
        edgePixels = AREA_EDGE_PIXELS, focusedEdgePixels = AREA_EDGE_PIXELS + 1,
        rimColor = AREA_RIM_COLOR, rimAlpha = 0.3, focusedRimAlpha = 0.6,
    },
}

-- The look as drawn: the chosen one's strengths times the player's (settings.areaFillStrength and
-- areaOutlineStrength, 1 = the look as it comes), none where fill or outline is switched off. Worked out again only
-- when one of those changes, in this one table: asked for at every minimap move, it makes no garbage.
local shownLook, shownFrom = { version = 0 }, {}
local NONE = {} -- (nothing to go through: a part switched off)
local MIN_STRENGTH, MAX_STRENGTH = 0.1, 2

---@return number share A strength as saved, kept to the steppers' range (anything else saved reads as 1)
local function getStrength(value)
    value = tonumber(value) or 1
    return math.max(MIN_STRENGTH, math.min(MAX_STRENGTH, value))
end

---@return table look The areas' look as the player chose it (AREA_LOOKS) and set its strengths, with its name as
---`style`, `hasFill` and `hasEdges` for what is drawn of it, and `version`, which changes with any of these
function MapMarks.getAreaLook()
    local settings = ns.settings
    local style = MapMarks.getAreaStyle()
    local hasFill, hasEdges = settings.shouldFillAreas ~= false, settings.shouldOutlineAreas ~= false
    local fillShare, edgeShare = getStrength(settings.areaFillStrength), getStrength(settings.areaOutlineStrength)
    local from = shownFrom
    if from.style ~= style or from.hasFill ~= hasFill or from.hasEdges ~= hasEdges or from.fillShare ~= fillShare or from.edgeShare ~= edgeShare then
        from.style, from.hasFill, from.hasEdges, from.fillShare, from.edgeShare = style, hasFill, hasEdges, fillShare, edgeShare
        local base = AREA_LOOKS[style] or AREA_LOOKS.filled
        local look = shownLook
        local fill, edge = hasFill and fillShare or 0, hasEdges and edgeShare or 0
        look.style, look.hasFill, look.hasEdges = style, hasFill, hasEdges
        look.fillAlpha, look.focusedFillAlpha = math.min(1, base.fillAlpha * fill), math.min(1, base.focusedFillAlpha * fill)
        look.edgeAlpha, look.focusedEdgeAlpha = math.min(1, base.edgeAlpha * edge), math.min(1, base.focusedEdgeAlpha * edge)
        look.rimAlpha, look.focusedRimAlpha = math.min(1, base.rimAlpha * edge), math.min(1, base.focusedRimAlpha * edge)
        look.edgePixels, look.focusedEdgePixels, look.rimColor = base.edgePixels, base.focusedEdgePixels, base.rimColor
        -- (walks are no areas: their dashes keep the look's own strength, outline or none)
        look.trailAlpha, look.focusedTrailAlpha = base.edgeAlpha, base.focusedEdgeAlpha
        look.version = look.version + 1
    end
    return shownLook
end

---@return boolean hasAreas Areas are drawn: a look of ours is chosen, with its fill or its outline (or both) on
function MapMarks.hasAreas()
    return MapMarks.getAreaStyle() ~= "none" and (ns.settings.shouldFillAreas ~= false or ns.settings.shouldOutlineAreas ~= false)
end

local shapeCache = {} -- [key] = a quest's area shapes on a map, in map widths (x across, y down), with their spawns
local pendingShapes, shapeJobs = {}, {} -- shapes being worked out, a slice a frame
local SHAPE_SLICE_MILLISECONDS = 4 -- time each frame may spend on them
local shapeJobFrame, startShapeJobs

---@return number milliseconds A clock to measure slices by
local function getMilliseconds()
    return debugprofilestop and debugprofilestop() or (GetTime and GetTime() or 0) * 1000
end

---Works on the shapes waiting, a few milliseconds a frame; each one done, the map and minimap are drawn again.
local function runShapeJobs()
    local started, isAnyDone = getMilliseconds(), false
    while shapeJobs[1] and getMilliseconds() - started < SHAPE_SLICE_MILLISECONDS do
        local job = shapeJobs[1]
        local isRunning, problem = coroutine.resume(job.routine)
        if not isRunning or coroutine.status(job.routine) == "dead" then
            table.remove(shapeJobs, 1)
            pendingShapes[job.key] = nil
            if not isRunning then
                shapeCache[job.key] = {} -- no area rather than trying again every frame
                if geterrorhandler then geterrorhandler()(problem) end
            end
            isAnyDone = true
        end
    end
    -- Drawn again once every shape waiting is done, not after each: each drawing of the marks costs a frame its time
    if isAnyDone and not shapeJobs[1] then
        ns.MapPins.queueRefresh()
        if ns.MinimapPins and ns.MinimapPins.refresh then
            ns.MinimapPins.refresh()
        end
    end
    if not shapeJobs[1] and shapeJobFrame then
        shapeJobFrame:Hide()
    end
end

startShapeJobs = function()
    if not shapeJobFrame then
        shapeJobFrame = CreateFrame("Frame")
        shapeJobFrame:SetScript("OnUpdate", function() ns.Timing.measure("areas worked out", runShapeJobs) end)
    end
    shapeJobFrame:Show()
end

---@return boolean isOnePlace The spawns stand all in one spot (within ONE_PLACE_YARDS of one another, as the reach
---measures yards on this map): one place, which the quest's mark shows, not an area round it
---@param points { x: number, y: number }[] Fractions of the map
---@param aspect number The map's height against its width (y is measured in widths for this)
function MapMarks.isOnePlace(points, reach, aspect)
    local span = reach * Style.ONE_PLACE_YARDS / AREA_REACH_YARDS
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, point in ipairs(points) do
        minX, maxX = math.min(minX, point.x), math.max(maxX, point.x)
        minY, maxY = math.min(minY, point.y * aspect), math.max(maxY, point.y * aspect)
    end
    return (maxX - minX) ^ 2 + (maxY - minY) ^ 2 <= span * span
end

---A quest's areas on a map: its spawns grouped where their rings touch, each group of two or more one shape that
---follows them. Kept until the spawns change.
---@param points { x: number, y: number }[] Fractions of the map
---@param reach number How far an area reaches past its spawns, as a fraction of the map's width
---@param aspect number The map's height against its width
---@return { shape: table, points: table[] }[] areas In map widths (y measured in widths too)
---@param shouldWait boolean? Work it out at once, however long it takes, instead of over the next frames
---@return table[]? areas nil while it is still being worked out; the map and minimap are drawn again when it is
function MapMarks.composeQuestShapes(questId, mapId, points, reach, aspect, shouldWait)
    if #points == 0 then
        return {}
    end
    local key = table.concat({ questId or 0, mapId or 0, #points, points[1].x, points[1].y, points[#points].x, points[#points].y,
        reach, string.format("%.3f", aspect), MapMarks.MIN_AREA_CELL, MapMarks.AREA_CELLS_PER_REACH }, ":")
    if shapeCache[key] then
        return shapeCache[key]
    end
    local function compose(shouldYield)
        local areas = {}
        for _, group in ipairs(MapMarks.composeAreas(points, 2 * reach)) do
            if #group.points >= AREA_MIN_POINTS and not MapMarks.isOnePlace(group.points, reach, aspect) then
                local inWidths = {}
                for index, point in ipairs(group.points) do
                    inWidths[index] = { x = point.x, y = point.y * aspect }
                end
                local cell = math.max(reach / MapMarks.AREA_CELLS_PER_REACH, MapMarks.MIN_AREA_CELL)
                areas[#areas + 1] = { shape = MapMarks.composeAreaShape(inWidths, reach, cell, shouldYield), points = inWidths }
            end
        end
        shapeCache[key] = areas
        return areas
    end
    if shouldWait or not CreateFrame then
        return compose(false)
    end
    -- Worked out a slice a frame, so a big zone's areas never hold the game up; drawn when ready
    if not pendingShapes[key] then
        pendingShapes[key] = true
        table.insert(shapeJobs, { key = key, routine = coroutine.create(function() compose(true) end) })
        startShapeJobs()
    end
    return nil
end

local ZONE_MAP_ASPECT = 2 / 3 -- a zone's map, height against width (the game draws them all at this shape)

---A quest's areas, worked out once on each zone's own map and kept (composeQuestShapes, by the zone, not the map
---shown), then fitted onto the map shown by where the zone lies on it: a stretch and a shift of each corner. So the
---map underneath changing (OpenMap crossing a zone's edge), a pan or a zoom never works a shape out again, and
---continent and world maps show the areas too.
---@param points table[] The quest's spawns, each with its place (Compose's composePoints)
---@return { triangles: table[], edges: table[], points: table[], reach: number }[]? areas In the map's fractions; nil
---while a zone's shapes are still being worked out (drawn when they are)
function MapMarks.composeFittedShapes(questId, mapId, points, shouldWait)
    local byZone, order, loose = {}, {}, {}
    for _, point in ipairs(points) do
        local place = point.place
        local zoneMapId = place and place.zoneId and place.x and place.x >= 0 and ns.Database.getUiMapId(place.zoneId)
        if zoneMapId then
            if not byZone[zoneMapId] then
                byZone[zoneMapId] = {}
                order[#order + 1] = zoneMapId
            end
            local zonePoints = byZone[zoneMapId]
            zonePoints[#zonePoints + 1] = { x = place.x / 100, y = place.y / 100 }
        else
            loose[#loose + 1] = point
        end
    end
    local fitted, isPending = {}, false
    for _, zoneMapId in ipairs(order) do
        local box = MapMarks.getZoneBox(zoneMapId, mapId)
        if box then
            local yards = MapMarks.getMapYards(zoneMapId)
            local reach = yards and MapMarks.AREA_REACH_YARDS / yards or AREA_REACH
            local shapes = MapMarks.composeQuestShapes(questId, zoneMapId, byZone[zoneMapId], reach, ZONE_MAP_ASPECT, shouldWait)
            if not shapes then
                isPending = true
            else
                local width, height = box.right - box.left, box.bottom - box.top
                local function fit(point) -- zone widths (y in widths) to the map shown's fractions
                    return { x = box.left + point.x * width, y = box.top + point.y / ZONE_MAP_ASPECT * height }
                end
                for _, area in ipairs(shapes) do
                    local triangles, edges, areaPoints = {}, {}, {}
                    for index, triangle in ipairs(area.shape.triangles) do
                        triangles[index] = { fit(triangle[1]), fit(triangle[2]), fit(triangle[3]) }
                    end
                    for index, edge in ipairs(area.shape.edges) do
                        edges[index] = { fit(edge[1]), fit(edge[2]) }
                    end
                    for index, point in ipairs(area.points) do
                        areaPoints[index] = fit(point)
                    end
                    fitted[#fitted + 1] = { triangles = triangles, edges = edges, points = areaPoints, reach = reach * width }
                end
            end
        end
    end
    if #loose >= AREA_MIN_POINTS then
        -- Spawns with no zone map (inside a dungeon): worked out on the map shown, as before
        local yards = mapId and MapMarks.getMapYards(mapId)
        local reach = yards and MapMarks.AREA_REACH_YARDS / yards or AREA_REACH
        local aspect = State.drawn.height and State.drawn.width and State.drawn.height / State.drawn.width or ZONE_MAP_ASPECT
        local shapes = MapMarks.composeQuestShapes(questId, mapId, loose, reach, aspect)
        for _, area in ipairs(shapes or {}) do
            local function fit(point) return { x = point.x, y = point.y / aspect } end
            local triangles, edges, areaPoints = {}, {}, {}
            for index, triangle in ipairs(area.shape.triangles) do triangles[index] = { fit(triangle[1]), fit(triangle[2]), fit(triangle[3]) } end
            for index, edge in ipairs(area.shape.edges) do edges[index] = { fit(edge[1]), fit(edge[2]) } end
            for index, point in ipairs(area.points) do areaPoints[index] = fit(point) end
            fitted[#fitted + 1] = { triangles = triangles, edges = edges, points = areaPoints, reach = reach }
        end
        isPending = isPending or shapes == nil
    end
    return fitted, isPending
end

-- The quests' areas are kept on the map between drawings, each quest's by itself (State.drawn.areaSets). An area is
-- some eighty triangles of fill and ninety lines of edge, each its own texture, and twenty quests' areas are over
-- three thousand: laid out anew at every drawing (thirty thousand calls into the game) they were what drawing the
-- map cost, a tenth of a second at a time. Kept, a drawing touches only what changed:
--   the same quest on the same spawns, map and size: nothing;
--   in or out of focus, or another colour: its fills and edges recoloured, nothing laid out;
--   another zoom: its lines' thickness;
--   other spawns (an objective done), another map or size: that quest's areas laid out again, the others kept.
-- A big laying out (the first of a session, another map) is done over a few frames, the quest in focus first.

-- Draw sublevels on the area layer (ARTWORK): the order the areas were always drawn in, now said outright, since a
-- kept texture's turn no longer says it. The other quests' fills, the focused quest's fill over them, its dark rim,
-- the other quests' edges, the focused quest's edge over all (the walks' dashes above: drawPatrols).
local FILL_LEVEL, FOCUSED_FILL_LEVEL, RIM_LEVEL, EDGE_LEVEL, FOCUSED_EDGE_LEVEL = 0, 1, 2, 3, 4
-- Textures and lines laid out in one frame; the rest wait for the next. Each is some ten calls into the game: 300 keep a
-- frame near 3,000 (500 made the frames after a map opened or OpenMap's map switched 5,000-6,000 each); a zone's areas
-- still fill in within a few frames
local MAX_REGIONS_PER_FRAME = 300

---@return table drawn The map's own record, with its kept areas and the textures free to use again
local function getAreaStore()
    local drawn = State.drawn
    if not drawn.areaSets then
        drawn.areaSets, drawn.freeTriangles, drawn.freeLines = {}, {}, {}
    end
    return drawn
end

-- A quest's areas laid out again (another map underneath, a new spawn, a new zoom's thinning) take back their own
-- textures and lines first, in the order they had them (reserveSet): each piece then has the colour and layer it is
-- given already, which a remembering region (Widgets.remember) is not given again; only its place and shape are.
---@param reserve table? The quest's own pieces, set aside for it: { triangles = {...}, lines = {...} }, last first
local function takeFrom(reserved, free)
    local count = reserved and #reserved or 0
    if count > 0 then
        local region = reserved[count]
        reserved[count] = nil
        return region
    end
    count = #free
    local region = free[count]
    if region then
        free[count] = nil
    end
    return region
end

local function takeTriangle(store, reserve)
    local texture = takeFrom(reserve and reserve.triangles, store.freeTriangles)
        or ns.Widgets.remember(State.areaLayer:CreateTexture(nil, "ARTWORK", nil, FILL_LEVEL))
    texture:Show()
    return texture
end

local function takeLine(store, reserve)
    local line = takeFrom(reserve and reserve.lines, store.freeLines) or ns.Widgets.remember(State.areaLayer:CreateLine(nil, "ARTWORK"))
    line:Show()
    return line
end

local function release(free, regions)
    for index = 1, #regions do
        local region = regions[index]
        region:Hide()
        free[#free + 1] = region
    end
end

---Takes a quest's kept areas off the map; their textures are free to use again.
local function releaseSet(store, key)
    local set = store.areaSets[key]
    if set then
        release(store.freeTriangles, set.triangles)
        release(store.freeLines, set.edges)
        release(store.freeLines, set.rims)
        store.areaSets[key] = nil
    end
end

---Takes a quest's kept areas off the map, to be laid out again: hidden, and set aside for it (takeTriangle), last first.
local function reserveSet(store, key)
    local set = store.areaSets[key]
    if not set then
        return
    end
    local triangles, lines = {}, {}
    for index = #set.triangles, 1, -1 do
        set.triangles[index]:Hide()
        triangles[#triangles + 1] = set.triangles[index]
    end
    -- (laid out edges first, then the rims: so taken back)
    for index = #set.rims, 1, -1 do
        set.rims[index]:Hide()
        lines[#lines + 1] = set.rims[index]
    end
    for index = #set.edges, 1, -1 do
        set.edges[index]:Hide()
        lines[#lines + 1] = set.edges[index]
    end
    store.reserved = store.reserved or {}
    store.reserved[key] = { triangles = triangles, lines = lines }
    store.areaSets[key] = nil
end

---What a quest's areas did not take back of their own goes to every quest's use (already hidden).
local function freeReserve(store, key)
    local reserve = store.reserved and store.reserved[key]
    if reserve then
        for index = 1, #reserve.triangles do
            store.freeTriangles[#store.freeTriangles + 1] = reserve.triangles[index]
        end
        for index = 1, #reserve.lines do
            store.freeLines[#store.freeLines + 1] = reserve.lines[index]
        end
        store.reserved[key] = nil
    end
end

local function freeReserves(store)
    for key in pairs(store.reserved or {}) do
        freeReserve(store, key)
    end
end

---Takes every kept area off the map: drawn in a look without areas, their turn is over.
function MapMarks.releaseAreas()
    local store = getAreaStore()
    for key in pairs(store.areaSets) do
        releaseSet(store, key)
    end
    freeReserves(store)
    store.areaJob = nil
end

local function setLine(line, fromX, fromY, toX, toY, color, alpha, pixels, scale, level)
    line:SetDrawLayer("ARTWORK", level)
    line:SetColorTexture(color[1], color[2], color[3], alpha)
    line.pixels = pixels
    line.baseThickness = pixels / scale -- what the zoom follows (MapMarks.followZoom)
    line:SetThickness(line.baseThickness)
    line:SetStartPoint("TOPLEFT", State.areaLayer, fromX, -fromY)
    line:SetEndPoint("TOPLEFT", State.areaLayer, toX, -toY)
end

---The dark line under each edge, for the quest in focus alone: muted, it would hardly show, and it doubles the
---lines the game has to move as the map is dragged.
local function addRims(store, set, scale, reserve)
    local ends = set.edgeEnds
    local look = MapMarks.getAreaLook()
    for index = 1, #ends, 4 do
        local line = takeLine(store, reserve)
        setLine(line, ends[index], ends[index + 1], ends[index + 2], ends[index + 3], look.rimColor, look.focusedRimAlpha, AREA_RIM_PIXELS, scale, RIM_LEVEL)
        set.rims[#set.rims + 1] = line
    end
end

---@return string key What a quest's areas are laid out from: the map, its size, and the quest's spawns
local function getGeometryKey(group, mapId, mapWidth, mapHeight)
    local sum = 0
    local points = group.points or {}
    for index = 1, #points do
        local point = points[index]
        sum = sum + (point.x or 0) * 7919 + (point.y or 0)
    end
    return string.format("%s:%.2f:%.2f:%d:%.6f", tostring(mapId), mapWidth, mapHeight, #points, sum)
end

---@return string key Whose areas a group's are: a quest's, or the creatures a quest to pick up starts from
local function getSetKey(group)
    return (group.hoverQuestId and "start:" or "quest:") .. tostring(group.questId)
end

---Lays a quest's areas out: a texture for each triangle of fill, a line for each piece of edge.
---@return number count The textures and lines laid out
---@return boolean isPending A shape is still being worked out: what is there is drawn, the rest when it is done
local function layOutSet(store, set, group, mapId, mapWidth, mapHeight, scale, reserve)
    local color, isFocused = group.color, group.isFocused == true
    local look = MapMarks.getAreaLook()
    local fillAlpha = isFocused and look.focusedFillAlpha or look.fillAlpha
    local edgeAlpha = isFocused and look.focusedEdgeAlpha or look.edgeAlpha
    local edgePixels = isFocused and look.focusedEdgePixels or look.edgePixels
    local questId = group.hoverQuestId or group.questId
    local fitted, isPending = MapMarks.composeFittedShapes(group.questId, mapId, group.points)
    local triangles, edges, edgeEnds, areas = {}, {}, {}, {}
    local first, second, third = {}, {}, {}
    for _, area in ipairs(fitted) do
        for _, triangle in ipairs(look.hasFill and area.triangles or NONE) do
            local texture = takeTriangle(store, reserve)
            texture:SetDrawLayer("ARTWORK", isFocused and FOCUSED_FILL_LEVEL or FILL_LEVEL)
            texture:SetColorTexture(color[1], color[2], color[3], fillAlpha)
            -- (the map's fractions to the area layer's units)
            first.x, first.y = triangle[1].x * mapWidth, triangle[1].y * mapHeight
            second.x, second.y = triangle[2].x * mapWidth, triangle[2].y * mapHeight
            third.x, third.y = triangle[3].x * mapWidth, triangle[3].y * mapHeight
            setTriangle(texture, first, second, third)
            triangles[#triangles + 1] = texture
        end
        for _, edge in ipairs(look.hasEdges and area.edges or NONE) do
            local fromX, fromY = edge[1].x * mapWidth, edge[1].y * mapHeight
            local toX, toY = edge[2].x * mapWidth, edge[2].y * mapHeight
            local line = takeLine(store, reserve)
            setLine(line, fromX, fromY, toX, toY, color, edgeAlpha, edgePixels, scale, isFocused and FOCUSED_EDGE_LEVEL or EDGE_LEVEL)
            edges[#edges + 1] = line
            local count = #edgeEnds
            edgeEnds[count + 1], edgeEnds[count + 2], edgeEnds[count + 3], edgeEnds[count + 4] = fromX, fromY, toX, toY
        end
        -- Kept for hovering: its spawns and reach, in the area layer's units, and whose it is
        local inLayer = {}
        for index, point in ipairs(area.points) do
            inLayer[index] = { x = point.x * mapWidth, y = point.y * mapHeight }
        end
        areas[#areas + 1] = { points = inLayer, reach = area.reach * mapWidth, questId = questId, isFocused = isFocused }
    end
    set.triangles, set.edges, set.edgeEnds, set.areas, set.rims = triangles, edges, edgeEnds, areas, {}
    set.red, set.green, set.blue, set.isFocused, set.scale, set.style = color[1], color[2], color[3], isFocused, scale, look.style
    set.lookVersion, set.hasFill, set.hasEdges = look.version, look.hasFill, look.hasEdges
    if isFocused and look.hasEdges then
        addRims(store, set, scale, reserve)
    end
    return #triangles + #edges + #set.rims, isPending == true
end

---A kept quest's areas in another colour or look, or in or out of focus: recoloured where they lie, nothing laid out.
local function restyleSet(store, set, group, scale)
    local color, isFocused = group.color, group.isFocused == true
    local isRelevelled = isFocused ~= set.isFocused
    local look = MapMarks.getAreaLook()
    local fillAlpha = isFocused and look.focusedFillAlpha or look.fillAlpha
    local edgeAlpha = isFocused and look.focusedEdgeAlpha or look.edgeAlpha
    local edgePixels = isFocused and look.focusedEdgePixels or look.edgePixels
    for index = 1, #set.triangles do
        local texture = set.triangles[index]
        texture:SetColorTexture(color[1], color[2], color[3], fillAlpha)
        if isRelevelled then
            texture:SetDrawLayer("ARTWORK", isFocused and FOCUSED_FILL_LEVEL or FILL_LEVEL)
        end
    end
    for index = 1, #set.edges do
        local line = set.edges[index]
        line:SetColorTexture(color[1], color[2], color[3], edgeAlpha)
        if line.pixels ~= edgePixels then -- (another look, or in or out of focus in the bolder one: its width on screen)
            line.pixels = edgePixels
            line.baseThickness = edgePixels / (set.scale or scale)
            line:SetThickness(line.baseThickness)
        end
        if isRelevelled then
            line:SetDrawLayer("ARTWORK", isFocused and FOCUSED_EDGE_LEVEL or EDGE_LEVEL)
        end
    end
    if #set.rims > 0 and (not isFocused or set.lookVersion ~= look.version) then
        release(store.freeLines, set.rims) -- (a rim of another look or strength is drawn again in this one's)
        set.rims = {}
    end
    if isFocused and #set.rims == 0 and look.hasEdges then
        addRims(store, set, set.scale or scale)
    end
    set.style, set.lookVersion = look.style, look.version
    for index = 1, #set.areas do
        set.areas[index].isFocused = isFocused
    end
    set.red, set.green, set.blue, set.isFocused = color[1], color[2], color[3], isFocused
end

---A kept quest's lines at another zoom: their thickness on screen stays what it is.
local function rescaleSet(set, scale)
    for _, lines in ipairs({ set.edges, set.rims }) do
        for index = 1, #lines do
            local line = lines[index]
            line.baseThickness = line.pixels / scale
            line:SetThickness(line.baseThickness)
        end
    end
    set.scale = scale
end

---The zoom changed a step: every kept line keeps its width on screen (MapMarks.followZoom).
---@param ratio number The zoom the areas were drawn at, against the zoom now
function MapMarks.followAreaZoom(ratio)
    for _, set in pairs(getAreaStore().areaSets) do
        for _, lines in ipairs({ set.edges, set.rims }) do
            for index = 1, #lines do
                local line = lines[index]
                line:SetThickness(line.baseThickness * ratio)
            end
        end
    end
end

local areaJobFrame

---Lays out the areas still waiting (MAX_REGIONS_PER_FRAME a frame), and says which are on the map.
---@param budget number? How many textures and lines this turn may lay out (it finishes the quest it is on)
---@return boolean isDone Nothing is left waiting
local function continueAreas(job, budget)
    local store = getAreaStore()
    budget = budget or MAX_REGIONS_PER_FRAME
    while job.index <= #job.groups and budget > 0 do
        local group = job.groups[job.index]
        job.index = job.index + 1
        local key = getSetKey(group)
        local set = { geometryKey = getGeometryKey(group, job.mapId, job.mapWidth, job.mapHeight) }
        local reserve = store.reserved and store.reserved[key]
        local count, isPending = layOutSet(store, set, group, job.mapId, job.mapWidth, job.mapHeight, job.scale, reserve)
        freeReserve(store, key) -- (what it did not take back: to every quest's use)
        if isPending then
            set.geometryKey = nil -- laid out again once its shapes are worked out
        end
        store.areaSets[key] = set
        for _, area in ipairs(set.areas) do
            State.drawn.areas[#State.drawn.areas + 1] = area
        end
        budget = budget - count
    end
    return job.index > #job.groups
end

local function runAreaJob()
    -- Each map's own (the world map, the zone map): the one whose areas wait
    for map, job in pairs(areaJobFrame.jobs) do
        MapMarks.useMap(map)
        if State.drawn.areaJob ~= job or continueAreas(job) then
            areaJobFrame.jobs[map] = nil
            if State.drawn.areaJob == job then
                State.drawn.areaJob = nil
            end
        end
    end
    if next(areaJobFrame.jobs) == nil then
        areaJobFrame:Hide()
    end
end

---Each tracked quest's areas in its own colour, following its spawns: filled lightly (so where quests overlap their
---fills add up, as on the game's map), edged with a line in the quest's colour over a soft dark one. The quest in
---focus lies over the others and is a little stronger. Lines keep their thickness on screen at any zoom.
---@param mapId number? The map drawn on, whose size in yards sets how far areas reach
local function drawQuestAreas(groups, mapWidth, mapHeight, scale, mapId)
    scale = scale or 1
    -- Only the quest in focus has its areas drawn, when the player chose that: the others keep their icons
    if ns.settings.shouldShowFocusedAreasOnly then
        local focused = {}
        for _, group in ipairs(groups) do
            if group.isFocused then focused[#focused + 1] = group end
        end
        groups = focused
    end
    State.areasDrawn = true
    local store = getAreaStore()
    store.areaJob = nil -- what an earlier drawing left waiting is looked at afresh here
    freeReserves(store) -- (and the pieces set aside for it, to every quest's use)
    -- What is kept and still right stays; what changed colour or focus is recoloured; the rest is laid out, the quest
    -- in focus first
    local isWanted, waiting = {}, {}
    local keptCount, restyledCount = 0, 0
    -- (a fill or an outline switched on or off is laid out again: what is off has no textures at all; a strength
    -- changed is only recoloured)
    local look = MapMarks.getAreaLook()
    for _, group in ipairs(groups) do
        local key = getSetKey(group)
        isWanted[key] = true
        local set = store.areaSets[key]
        if set and set.geometryKey == getGeometryKey(group, mapId, mapWidth, mapHeight) and set.hasFill == look.hasFill and set.hasEdges == look.hasEdges then
            if set.red ~= group.color[1] or set.green ~= group.color[2] or set.blue ~= group.color[3] or set.isFocused ~= (group.isFocused == true)
                or set.lookVersion ~= look.version then
                restyleSet(store, set, group, scale)
                restyledCount = restyledCount + 1
            else
                keptCount = keptCount + 1
            end
            if set.scale ~= scale then
                rescaleSet(set, scale)
            end
            for _, area in ipairs(set.areas) do
                State.drawn.areas[#State.drawn.areas + 1] = area
            end
        else
            -- Other spawns, another map or size (or never laid out): not left showing meanwhile, its pieces set aside
            -- for it to take back
            reserveSet(store, key)
            table.insert(waiting, group.isFocused and 1 or #waiting + 1, group)
        end
    end
    for key in pairs(store.areaSets) do
        if not isWanted[key] then
            releaseSet(store, key) -- a quest no longer drawn
        end
    end
    if ns.Timing.isRecording then
        ns.Timing.noteCause("areas", string.format("%d kept, %d recoloured, %d laid out", keptCount, restyledCount, #waiting))
    end
    if #waiting == 0 then
        return
    end
    local job = { groups = waiting, index = 1, mapId = mapId, mapWidth = mapWidth, mapHeight = mapHeight, scale = scale }
    if ns.frameNumber == 0 then
        while not continueAreas(job) do end -- (where no frames run, all at once)
        return
    end
    -- With this drawing (which has laid out every mark and icon already): the quest in focus alone, or, when nothing
    -- much waits (a quest whose spawns changed), all of it. The rest over the next frames.
    local isSmall = #waiting <= 2
    if continueAreas(job, (isSmall or waiting[1].isFocused) and (isSmall and MAX_REGIONS_PER_FRAME or 1) or 0) then
        return
    end
    store.areaJob = job
    if not areaJobFrame then
        areaJobFrame = CreateFrame("Frame")
        areaJobFrame.jobs = {}
        areaJobFrame:SetScript("OnUpdate", function() ns.Timing.measure("areas laid out (a frame's share)", runAreaJob) end)
    end
    areaJobFrame.jobs[State.drawn.map] = job
    areaJobFrame:Show()
end

-- A walk drawn as a dashed line, as a trail on a paper map: a light dash over a faint shadow, no marks at its bends,
-- its width and dashes kept on screen (pixels) at any zoom
MapMarks.DASH_PIXELS, MapMarks.DASH_GAP_PIXELS = 7, 6
MapMarks.DASH_WIDTH, MapMarks.DASH_SHADOW_WIDTH, MapMarks.DASH_SHADOW_ALPHA = 2.2, 4.4, 0.3

---The dashes along a path: pieces of it dash long with gaps between, carried on round its bends.
---@param points { x: number, y: number }[] The path, in any units
---@return { from: table, to: table }[] dashes
function MapMarks.composeDashes(points, dash, gap)
    local dashes = {}
    local isDrawing, left = true, dash
    for index = 2, #points do
        local from, to = points[index - 1], points[index]
        local length = math.sqrt((to.x - from.x) ^ 2 + (to.y - from.y) ^ 2)
        local along = 0
        while length > 0 and along < length do
            local step = math.min(left, length - along)
            if isDrawing then
                local startShare, endShare = along / length, (along + step) / length
                dashes[#dashes + 1] = {
                    from = { x = from.x + (to.x - from.x) * startShare, y = from.y + (to.y - from.y) * startShare },
                    to = { x = from.x + (to.x - from.x) * endShare, y = from.y + (to.y - from.y) * endShare },
                }
            end
            along, left = along + step, left - step
            if left <= 0 then
                isDrawing = not isDrawing
                left = isDrawing and dash or gap
            end
        end
    end
    return dashes
end

---Draws a walk as dashes: each a light line over a faint dark one, from lines makeLine gives (on a layer scaled with
---the map: widths and lengths in its units, pixels / scale).
---@param makeLine fun(sublevel: number): table A line, its draw layer set
function MapMarks.paintDashes(points, makeLine, color, alpha, scale)
    local light = { color[1] + (1 - color[1]) * 0.55, color[2] + (1 - color[2]) * 0.55, color[3] + (1 - color[3]) * 0.55 }
    for _, dash in ipairs(MapMarks.composeDashes(points, MapMarks.DASH_PIXELS / scale, MapMarks.DASH_GAP_PIXELS / scale)) do
        for _, piece in ipairs({
            { 1, AREA_RIM_COLOR, alpha * MapMarks.DASH_SHADOW_ALPHA, MapMarks.DASH_SHADOW_WIDTH },
            { 2, light, alpha, MapMarks.DASH_WIDTH },
        }) do
            local line = makeLine(piece[1])
            line:SetColorTexture(piece[2][1], piece[2][2], piece[2][3], piece[3])
            line.baseThickness = piece[4] / scale -- what the zoom follows (MapMarks.followZoom)
            line:SetThickness(line.baseThickness)
            line:SetStartPoint("TOPLEFT", line:GetParent(), dash.from.x, -dash.from.y)
            line:SetEndPoint("TOPLEFT", line:GetParent(), dash.to.x, -dash.to.y)
            line:Show()
        end
    end
end

---Where the tracked quests' creatures walk, as Questie shows (Sharptalon round his part of Ashenvale): each patrol a
---dashed line in a light shade of its quest's colour over a faint shadow (MapMarks.paintDashes), brighter while the
---quest is in focus. In every look of the marks. Dashes keep their size on screen at any zoom.
---Quest givers who walk about (giverLines, from MapMarks.getGiverPatrolLines) are drawn the same way in the gold of
---their "!", faint unless their quest is the one selected on the Available tab.
local function drawPatrols(groups, giverLines, mapWidth, mapHeight, scale, mapId)
    scale = scale or 1
    State.pools.trailLines = State.pools.trailLines or { usedCount = 0 }
    local function makeLine(sublevel)
        local line = acquire(State.pools.trailLines, function() return State.areaLayer:CreateLine(nil, "ARTWORK") end)
        line:SetDrawLayer("ARTWORK", 3 + sublevel) -- over the areas' edges (FOCUSED_EDGE_LEVEL)
        return line
    end
    State.drawn.patrols = {} -- each drawn trail's path, in the layer's units, for pointing at it
    local function drawTrail(patrol, color, alpha, questId)
        local points = {}
        for index, point in ipairs(patrol) do
            points[index] = { x = point.x * mapWidth, y = point.y * mapHeight }
        end
        MapMarks.paintDashes(points, makeLine, color, alpha, scale)
        local name = patrol.npcId and ns.Database.getNpcField(patrol.npcId, "name")
        State.drawn.patrols[#State.drawn.patrols + 1] = { points = points, questId = questId, note = name and ns.L("%s walks here", name) or nil }
    end
    for _, group in ipairs(groups) do
        -- (none for a quest whose objectives are not shown exactly: Spoilers)
        for _, patrol in ipairs(not group.hasNoPatrols and MapMarks.getQuestPatrolLines(group.questId, mapId) or {}) do
            drawTrail(patrol, group.color, group.isFocused and FOCUSED_AREA_EDGE_ALPHA or AREA_EDGE_ALPHA, group.questId)
        end
    end
    for _, giverLine in ipairs(giverLines or {}) do
        drawTrail(giverLine.points, Style.FOCUS_GOLD, giverLine.isFocused and FOCUSED_AREA_EDGE_ALPHA or AREA_EDGE_ALPHA, giverLine.questId)
    end
end
---Places the icons: one to a cell of a grid (the quest in focus first, then the others in their order), none
---under a mark. An icon under another quest's mark or another addon's pin steps aside to the nearest free cell;
---one under its own quest's mark is left out, as the mark already shows the quest there (zoomed out, an area may
---be no bigger than its mark, and icons pushed round it would stand outside the area).
---@return { x: number, y: number, glyph: string, color: number[], isFocused: boolean }[] icons In the mark layer's units
MapMarks.MIN_ICON_SIZE = 7 -- a spawn's icon with the map zoomed out fully; it grows to its full size as the map zooms in
-- The cells round a spawn's own, nearest first, two deep: far enough to clear a pin the size of Leatrix Maps' arrows
local NEIGHBOUR_CELLS = {}
for column = -2, 2 do
    for row = -2, 2 do
        if column ~= 0 or row ~= 0 then
            NEIGHBOUR_CELLS[#NEIGHBOUR_CELLS + 1] = { column, row }
        end
    end
end
table.sort(NEIGHBOUR_CELLS, function(first, second)
    local firstDistance, secondDistance = first[1] ^ 2 + first[2] ^ 2, second[1] ^ 2 + second[2] ^ 2
    if firstDistance ~= secondDistance then return firstDistance < secondDistance end
    return first[1] * 10 + first[2] < second[1] * 10 + second[2]
end)

---@param iconSize number? The icons' size now (smaller zoomed out), else the full size
function MapMarks.placeIcons(groups, markRects, cell, iconSize)
    cell = cell or ICON_CELL
    local isTaken, icons = {}, {}
    if not MapMarks.IS_LAYOUT_ON then
        -- Laid out off: an icon on every spawn, on its own spot, so zooming only scales them
        for _, group in ipairs(groups) do
            for _, point in ipairs(group.points) do
                icons[#icons + 1] = {
                    x = point.x, y = point.y, glyph = point.glyph or "use", color = group.color, isFocused = group.isFocused,
                    isStrong = group.isStrong, questId = point.questId, note = point.note,
                }
            end
        end
        return icons
    end
    local half = (iconSize or ICON_SIZE) / 2 + 1 -- the icon itself keeps off marks and other addons' pins; its soft glow may reach under them
    local function isOnRects(x, y)
        for _, rect in ipairs(markRects) do
            if x + half > rect.left and x - half < rect.right and y + half > rect.top and y - half < rect.bottom then
                return true
            end
        end
        return false
    end
    for _, group in ipairs(groups) do
        for _, point in ipairs(group.points) do
            local column, row = math.floor(point.x / cell), math.floor(point.y / cell)
            local key = column .. ":" .. row
            if not isTaken[key] then
                isTaken[key] = true
                local x, y = (column + 0.5) * cell, (row + 0.5) * cell
                local isCovered, isUnderOwnMark = false, false
                for _, rect in ipairs(markRects) do
                    if x + half > rect.left and x - half < rect.right and y + half > rect.top and y - half < rect.bottom then
                        isCovered = true
                        isUnderOwnMark = isUnderOwnMark or (rect.questId ~= nil and rect.questId == point.questId)
                    end
                end
                if isCovered and not isUnderOwnMark then
                    -- Under a mark or another addon's pin: the nearest free cell beside it, so the spawn still shows
                    for _, step in ipairs(NEIGHBOUR_CELLS) do
                        local nextColumn, nextRow = column + step[1], row + step[2]
                        local nextKey = nextColumn .. ":" .. nextRow
                        local nextX, nextY = (nextColumn + 0.5) * cell, (nextRow + 0.5) * cell
                        if not isTaken[nextKey] and not isOnRects(nextX, nextY) then
                            isTaken[nextKey] = true
                            x, y, isCovered = nextX, nextY, false
                            break
                        end
                    end
                end
                if not isCovered then
                    icons[#icons + 1] = {
                        x = x, y = y, glyph = point.glyph or "use", color = group.color, isFocused = group.isFocused,
                        isStrong = group.isStrong, questId = point.questId, note = point.note,
                    }
                end
            end
        end
    end
    return icons
end

-- A spawn's glow and its icon remember what they were last given (Widgets.remember): drawn again where they are,
-- as they are (a kill counted, a quest hovered), they ask nothing of the game
local function createIconGlow()
    return ns.Widgets.remember(State.markLayer:CreateTexture(nil, "ARTWORK", nil, 1))
end

local function createIconGlyph()
    return ns.Widgets.remember(State.markLayer:CreateTexture(nil, "ARTWORK", nil, 2))
end

---The icons on the map: a glow in the quest's colour, the icon of what to do over it.
local function drawIcons(groups, mapWidth, mapHeight, scale, markRects)
    -- Zoomed out, a spawn's icon is smaller, on a finer grid: the spots stay as close as the spawns are. Zoomed in
    -- fully, it is its full size.
    local map = State.drawn and State.drawn.map
    local zoom = map and map.GetCanvasZoomPercent and map:GetCanvasZoomPercent()
    zoom = math.max(math.min(type(zoom) == "number" and zoom or 1, 1), 0)
    local iconSize = MapMarks.MIN_ICON_SIZE + (ICON_SIZE - MapMarks.MIN_ICON_SIZE) * zoom
    if not MapMarks.IS_LAYOUT_ON then
        -- Laid out off: sized as the marks are, by how much of the world the map shows, so a zoom only scales them
        iconSize = ICON_SIZE * (State.drawn.markScale or 1)
    end
    -- (and as large as the player chose for the spawn markers alone)
    iconSize = iconSize * math.max(0.5, math.min(2, tonumber(ns.settings.spawnMarkerScale) or 1))
    local glowSize = iconSize * ICON_GLOW_SIZE / ICON_SIZE
    local place = ns.Widgets.place
    local kind = MapMarks.getSpawnMarker()
    if not MapMarks.IS_LAYOUT_ON then
        -- Laid out off (as it ships): every spawn's icon on its own spot, straight from the thinned spawns, the quest in
        -- focus first as below; one table a spawn (its square, for pointing at it), not four, at every drawing
        local inOrder = {}
        for _, group in ipairs(groups) do
            table.insert(inOrder, group.isFocused and 1 or #inOrder + 1, group)
        end
        local squares, radius = {}, glowSize / 2
        State.drawn.squares = squares
        for _, group in ipairs(inOrder) do
            local isShown, isStrong = MapMarks.getSpawnMarkerStrength(group.isFocused == true)
            local shownSize = group.isFocused and iconSize + 2 or iconSize
            for _, point in ipairs(isShown and MapMarks.thinPoints(group.points, State.drawn.spawnSpacing) or NONE) do
                local x, y = point.x * mapWidth * scale, point.y * mapHeight * scale
                local glow = acquire(State.pools.glows, createIconGlow)
                local glyph = acquire(State.pools.icons, createIconGlyph)
                local hasUnder = MapMarks.dressSpawnMarker(glow, glyph, kind, point.glyph or "use", group.color, isStrong, shownSize, glowSize)
                glow:SetShown(hasUnder)
                place(glow, "CENTER", State.markLayer, "TOPLEFT", x, -y)
                place(glyph, "CENTER", State.markLayer, "TOPLEFT", x, -y)
                squares[#squares + 1] = { glow = glow, glyph = glyph, x = x, y = y, questId = point.questId, note = point.note,
                    isFocused = group.isFocused, radius = radius }
            end
        end
        return
    end
    local ordered = {}
    for _, group in ipairs(groups) do
        -- The quest in focus always; the others fainter, as strong, or not at all, as the player chose
        local isShown, isStrong = MapMarks.getSpawnMarkerStrength(group.isFocused == true)
        local points = {}
        -- Thinned in the world to the zoom's step: never moved, only some left out (MapMarks.thinPoints)
        for index, point in ipairs(isShown and MapMarks.thinPoints(group.points, State.drawn.spawnSpacing) or {}) do
            points[index] = { x = point.x * mapWidth * scale, y = point.y * mapHeight * scale, glyph = point.glyph, questId = point.questId, note = point.note }
        end
        table.insert(ordered, group.isFocused and 1 or #ordered + 1, { points = points, color = group.color, isFocused = group.isFocused, isStrong = isStrong })
    end
    State.drawn.squares = {}
    local footprint = MapMarks.getSpawnMarkerFootprint(kind, iconSize)
    for _, icon in ipairs(MapMarks.placeIcons(ordered, markRects, footprint + 1, footprint)) do
        -- Two textures a spawn, one under and one over, in the kind the player chose (MapMarks.dressSpawnMarker)
        local glow = acquire(State.pools.glows, createIconGlow)
        local glyph = acquire(State.pools.icons, createIconGlyph)
        -- The focused quest's a little larger, so its spawns stand out from the others'
        local shownSize = icon.isFocused and iconSize + 2 or iconSize
        local hasUnder = MapMarks.dressSpawnMarker(glow, glyph, kind, icon.glyph, icon.color, icon.isStrong, shownSize, glowSize)
        glow:SetShown(hasUnder)
        place(glow, "CENTER", State.markLayer, "TOPLEFT", icon.x, -icon.y)
        place(glyph, "CENTER", State.markLayer, "TOPLEFT", icon.x, -icon.y)
        State.drawn.squares[#State.drawn.squares + 1] = { textures = { glow, glyph }, x = icon.x, y = icon.y, questId = icon.questId, note = icon.note, isFocused = icon.isFocused, radius = glowSize / 2 }
    end
end

-- Shared with the other parts of the window
Areas.drawIcons = drawIcons
Areas.drawQuestAreas = drawQuestAreas
-- The path of a quest giver pointed at: its own lines on the area layer, drawn and taken away with the pointer, so the
-- map is not drawn again under it (that would make the mark under the pointer anew)
local hoverLines = {}

---Draws where whom a quest is had from walks, while the pointer is on its "!".
---@return number legs How many legs of paths were drawn
function MapMarks.showHoverPatrols(questId)
    MapMarks.hideHoverPatrols()
    local drawn = State.drawn
    local map = drawn and drawn.map
    if not map or not State.areaLayer or not drawn.width or not map.GetMapID then
        return 0
    end
    -- At the zoom now (the map may have zoomed since it was drawn), so the dashes are their size on screen
    local scale = map.GetCanvasScale and map:GetCanvasScale() or drawn.scale or 1
    local count, legs = 0, 0
    local function makeLine(sublevel)
        count = count + 1
        local line = hoverLines[count]
        if not line or line:GetParent() ~= State.areaLayer then
            line = State.areaLayer:CreateLine(nil, "ARTWORK")
            hoverLines[count] = line
        end
        line:SetDrawLayer("ARTWORK", 5 + math.min(sublevel, 2)) -- over the walks drawn all the time
        return line
    end
    for _, patrol in ipairs(MapMarks.getQuestStarterPatrolLines(questId, map:GetMapID())) do
        local points = {}
        for index, point in ipairs(patrol) do
            points[index] = { x = point.x * drawn.width, y = point.y * drawn.height }
        end
        legs = legs + math.max(#points - 1, 0)
        MapMarks.paintDashes(points, makeLine, Style.FOCUS_GOLD, FOCUSED_AREA_EDGE_ALPHA, scale)
    end
    for index = count + 1, #hoverLines do
        hoverLines[index]:Hide()
    end
    return legs
end

function MapMarks.hideHoverPatrols()
    for _, line in ipairs(hoverLines) do
        line:Hide()
    end
end
Areas.drawPatrols = drawPatrols
