local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The map's marks: the kept drawing of the quests' areas, walks and spawn marks.
--
-- Two things cost on a map that is dragged and zoomed all the time (OpenMap's joined-up world most of all):
--   * What OneMoreQuest does in Lua when the view changes. Drawn as before (Areas), every piece was laid out on the
--     map shown, for the part in view, at its zoom: a drag past what was drawn, a zoom across a step of detail, or
--     another map coming underneath laid all of it out again.
--   * What the game does by itself on EVERY FRAME of a drag or a zoom: it lays out again everything that hangs from
--     the map by its anchors, shown or hidden (OpenMap's own notes, measured in the game; some five to ten
--     microseconds a region). Thousands of regions kept on the map, most of them hidden, are tens of milliseconds a
--     frame whatever Lua does. This is the cost that counts, and the simulator does not show it: its audits count
--     what hangs from the map instead (sim/lib/mapcost.lua's countHanging).
--
-- So the drawing is kept, and kept light:
--   * A "space" is a map whose own coordinates things are kept in: a zone's map, or (zoomed far out) the map shown
--     itself. Each has a frame on the canvas, placed and scaled to where its map lies on the map shown. A drag moves
--     nothing of ours; a zoom scales it with the canvas; another map underneath places each space's frame again.
--   * A quest's areas in a space are a set of pieces laid out once in the space's units, at a level of detail the
--     space's size on screen asks for. Its walks likewise. Spawn marks are thinned in the world in nested steps (as
--     Compose's thinPoints) and kept in tiles, squares of the space; a view shows the tiles under it.
--   * Every set and tile hangs from the map by ONE frame. Not in view, not wanted, or kept for later, that frame
--     lets go of its anchors, and all it holds costs the game nothing. Nothing hidden is left hanging.
--   * Lines and spawn marks lie in the spaces, so they grow with the map while it zooms; once the zoom has settled
--     their widths and sizes are set for it (the one thing done per piece, and only for what shows).
--   * On a joined-up map, where the dragging never stops, less is drawn: only the quest in focus has its walks
--     shown, a quest spread over much of a zone has its edge thinned to a budget of pieces (a generous one: an
--     area keeps its round shape), and fewer spawn marks show. Every quest's areas are filled, as on any map.
--   * What is missing for the view is worked on a little each frame, the quest in focus and what is nearest the
--     middle of the view first; what was shown stays up meanwhile, so nothing blinks. With the map closed, the
--     player's own zone is made ready the same way, a little slower.
local MapMarks = ns.MapMarks
local Style = ns.MapMarksStyle
local Compose, Shapes, Ovals = ns.MapMarksCompose, ns.MapMarksShapes, ns.MapMarksOvals
local World = {}
ns.MapMarksWorld = World
MapMarks.World = World
-- The ovals' geometry and pictures (Ovals), as the minimap's areas read them here too
World.fitGroupOvals, World.getOvalCorner = Ovals.fitGroupOvals, Ovals.getCorner
World.getOvalLook, World.getOvalRing = Ovals.getLook, Ovals.getRing

local remember, place = ns.Widgets.remember, ns.Widgets.place
local setTriangle, setQuad = Shapes.setTriangle, Shapes.setQuad
local getWorldPlace, getSpawnRank = Compose.getWorldPlace, Compose.getSpawnRank

local UNITS = 1000 -- a space's width in its frame's own units
local ASPECT = MapMarks.ZONE_MAP_ASPECT -- every map is this shape, height against width
local NONE = {}
local DEFAULT_YARDS = 3500 -- for a map whose size the game does not give

-- Levels of detail: level 0 is a zone's own map's grain (a 50 yard reach on a grid of MapMarks.MIN_AREA_CELL), each
-- level above it twice as coarse. A space takes the finest level whose grid cell is at least this wide on screen.
World.MIN_CELL_PIXELS = 4
World.MAX_LOD = 6
local LOD_SLACK = 1.12 -- a size must pass a level's edge by this much to change level: none flickers at the edge
-- A map showing the world at fewer pixels a yard than this (a continent some 1,400 pixels across) has its quests'
-- areas traced on itself, one set a quest, however many zones it is spread over; nearer, each zone in view has its own
World.WIDE_BELOW_PER_YARD = 0.038
local WIDE_SLACK = 1.1

World.VIEW_MARGIN = 0.3 -- what is made ready reaches this far past the view on each side (of its width and height)
-- A map never opened yet is made ready as if it were this wide (the game's maps are) at this zoom (a windowed map's)
World.CANVAS_WIDTH, World.OPENING_SCALE = 1002, 0.7
World.TILE_CELLS = 8 -- a tile is this many of its level's squares across
World.FINEST_YARDS = 12 -- the finest level's square: a spawn's own icon
-- Spawn marks in view at once (past it the next coarser level shows): on the game's own map, and on a joined-up one
World.MAX_ICONS, World.MAX_ICONS_JOINED = 800, 400
-- On a joined-up map a quest's edge in a zone is thinned until it has this many pieces at most. Generous: at 48 a
-- quest of a dozen areas had four or five straight lines round each, rough polygons. The same for the quest in focus
-- as for the others: with a budget of its own, putting a quest in focus (or pointing at it in the quest window's
-- list) laid its areas out anew, and the one let go of too, their fill gone from the map meanwhile
World.MAX_EDGES = 400
World.MAX_RIM_EDGES = 150 -- the focused quest's dark rim doubles its edge's pieces: only under an edge this short
-- A quest with more spawns than this is heavy: sorted (into spaces, into levels) after the other quests' areas and
-- spawn marks are up, unless it is the one in focus
World.HEAVY_FROM = 1000
-- What is laid out and not in view is kept for coming back to (let go of the map: it costs nothing there), up to
-- this many pieces; then the longest unseen go
World.MAX_KEPT_REGIONS = 9000
World.MAX_KEPT_ICONS = 2500
-- Each frame's share of the work: with the map open, and with it closed (the player's zone made ready ahead). In
-- milliseconds, and in pieces of work (a piece: a texture or line laid out, or a handful of spawns sorted; some ten
-- microseconds of the game's time), whichever runs out first: the pieces keep a frame's share the same on every
-- machine, the clock catches what turns out slower than reckoned.
World.OPEN_MILLISECONDS, World.CLOSED_MILLISECONDS = 3, 1
World.OPEN_PIECES, World.CLOSED_PIECES = 300, 100
local SETTLE_SECONDS = 0.12 -- a view that moved is looked at again once it has stayed put this long...
local MAX_WAIT_SECONDS = 0.3 -- ...or after this long of moving
local VIEW_CHECK_SECONDS = 0.1 -- how often a drag is looked for
local WIDTH_SLACK = 0.02 -- lines are given their width again once the zoom changed it on screen by this much

-- A quest's places sorted into spaces and levels (splitFeature, rankFeature) and its walks, kept by the quest for
-- every map that draws it (the world map and the zone map each have their own world): sorted once, not once a map
local sortedFeatures = {} -- [feature key] = the feature last sorted for it
local worlds = {} -- [map] = its world: the spaces on it, what they hold, and what of it shows
World.worlds = worlds -- (read by the tests and the simulator's audits)
local driver -- the frame whose OnUpdate keeps the worlds up
local now = 0 -- the driver's clock (GetTime)

---@return boolean isOn The kept drawing draws the areas and spawn marks (else Areas does, as before). On wherever
---frames run, unless the player chose the old drawing (/omq drawing); the tests, where none run, switch it on.
function World.isOn()
    if World.isForced ~= nil then
        return World.isForced
    end
    return ns.settings.mapRenderer ~= "classic" and ns.frameNumber > 0
end

local function getMilliseconds()
    return debugprofilestop and debugprofilestop() or (GetTime and GetTime() or 0) * 1000
end

-- The work of a frame stops when its share is used up and goes on in the next (a coroutine): said at every few
-- steps of a long loop, with how many pieces of work they were. Never inside a pcall or a comparison function, which
-- a coroutine cannot be left from.
local deadline, allowance = math.huge, math.huge
local function spend(pieces)
    allowance = allowance - pieces
    if (allowance <= 0 or getMilliseconds() >= deadline) and coroutine.running() then
        coroutine.yield()
    end
end

---@return number lod The level of detail for a space this wide on screen, kept from the one it has near an edge
function World.chooseLod(pixels, current)
    local function choose(width)
        local lod = 0
        while MapMarks.MIN_AREA_CELL * 2 ^ lod * width < World.MIN_CELL_PIXELS and lod < World.MAX_LOD do
            lod = lod + 1
        end
        return lod
    end
    local chosen = choose(pixels)
    if current and chosen ~= current then
        -- (coarser only once it would be even a little larger, finer only once even a little smaller)
        if choose(chosen > current and pixels * LOD_SLACK or pixels / LOD_SLACK) ~= chosen then
            return current
        end
    end
    return chosen
end

---------------------------------------------------------------------------------------------------------------
-- A world: one map's own (the world map, the zone map)

local function getWorld(map)
    local world = worlds[map]
    if not world then
        world = {
            map = map,
            spaces = {}, -- [key] = space
            spaceList = {},
            features = {}, -- in their order
            featureByKey = {},
            todo = {},
            shownTiles = {}, -- [tile] = true
            keptSets = {}, -- every set laid out, for letting the longest unseen go
            keptTiles = {},
            keptTrails = {},
            regionCount = 0,
            iconCount = 0,
            freeFillFrames = {},
            freeLineFrames = {},
            freeOvalFrames = {},
            freeTileFrames = {},
            cleared = {}, -- spawn marks taken off near the player and the party: { tile, index }
            stamp = 0,
        }
        worlds[map] = world
    end
    return world
end

local function ensureRoots(world)
    if world.areaRoot then
        return true
    end
    local map = world.map
    local canvas = map.GetCanvas and map:GetCanvas()
    if not canvas or not CreateFrame then
        return false
    end
    world.canvas = canvas
    -- The one frame all of it is on: on the canvas, growing with it
    world.areaRoot = CreateFrame("Frame", nil, canvas)
    world.areaRoot:SetAllPoints(canvas)
    return true
end

---@return table[] layers A map's frames of the kept drawing, for the simulator's audits
function World.getLayers(map)
    local world = worlds[map]
    return world and world.areaRoot and { world.areaRoot } or {}
end

---------------------------------------------------------------------------------------------------------------
-- Hanging from the map, and let go of it

-- The game lays out again, on every frame of a drag or a zoom, everything that hangs from the map by its anchors:
-- shown or hidden alike. So whatever does not show lets go of its anchors: a set's or a tile's one frame (all it
-- holds hangs from that frame, and with it from nothing), a pooled region by itself.

---Hangs a frame at its parent's upper left corner, and shows it.
local function attach(frame, parent)
    if frame.omqParent ~= parent then
        frame.omqParent = parent
        frame:SetParent(parent)
    end
    if not frame.isAttached then
        frame.isAttached = true
        frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    end
    frame:Show()
end

---Hides a frame and lets it go of what it hung from.
local function detach(frame)
    if frame.isAttached then
        frame.isAttached = false
        frame:ClearAllPoints()
    end
    frame:Hide()
end

---A region of a frame that is not used now: hidden, with no anchors.
local function rest(region)
    if not region.isResting then
        region.isResting = true
        region:Hide()
        region:ClearAllPoints()
    end
end

-- A set's or tile's frames by what they hold (textures, or lines), made once and used again: a frame keeps its
-- regions. Taken let go and hidden; hung up when what it holds shows.
local function acquireFrame(free, parent)
    local frame = free[#free]
    if frame then
        free[#free] = nil
        if frame.omqParent ~= parent then
            frame.omqParent = parent
            frame:SetParent(parent)
        end
    else
        frame = CreateFrame("Frame", nil, parent)
        frame:SetSize(1, 1)
        frame:Hide()
        frame.regions = {} -- a set's lines or fills
        frame.glows, frame.glyphs = {}, {} -- a tile's spawn marks: under and over
        frame.omqParent = parent
    end
    return frame
end

local function releaseFrame(free, frame)
    if frame then
        detach(frame)
        free[#free + 1] = frame
    end
end

local function takeTexture(frame, index)
    local texture = frame.regions[index]
    if not texture then
        texture = remember(frame:CreateTexture(nil, "ARTWORK"))
        frame.regions[index] = texture
    end
    texture.isResting = nil
    texture:Show()
    return texture
end

local function takeLine(frame, index)
    local line = frame.regions[index]
    if not line then
        line = remember(frame:CreateLine(nil, "ARTWORK"))
        frame.regions[index] = line
    end
    line.isResting = nil
    line:Show()
    return line
end

---A frame's regions past those in use: at rest.
local function restFrom(frame, index)
    local regions = frame.regions
    for position = index, #regions do
        rest(regions[position])
    end
end

---@return boolean isSame A line's width was set for this size of its space on screen, or near enough. (Another map
---coming underneath gives every space another scale and the map another zoom; on screen each is as large as it
---was, give or take the rounding: no line needs its width set again then, and there are hundreds.)
local areWidthsHeld = false -- another map is coming underneath: no line's width is set until it has (below)
local function isSameWidth(sizedFor, lineScale)
    if areWidthsHeld and sizedFor ~= nil then
        return true
    end
    return sizedFor ~= nil and math.abs(sizedFor / lineScale - 1) <= WIDTH_SLACK
end

---------------------------------------------------------------------------------------------------------------
-- Spaces

local function createSpace(world, key, mapId, zoneId, isWide)
    local frame = CreateFrame("Frame", nil, world.areaRoot)
    frame:SetSize(UNITS, UNITS * ASPECT)
    frame:Hide()
    local space = {
        key = key,
        mapId = mapId,
        zoneId = zoneId, -- the zone its places count for (a zone's own map shows only its own)
        isWide = isWide, -- the map shown's own, for its quests' areas traced on it
        frame = frame,
        yards = MapMarks.getMapYards(mapId),
        sets = {}, -- [feature key] = { [level of detail and kind] = set, shown = set }
        trails = {}, -- [feature key] = { [dash level and way of placing] = the walks' set, shown = set, level }
        overlays = {}, -- [feature key] = the spawn marks of that quest in focus
        isShown = false,
    }
    world.spaces[key] = space
    world.spaceList[#world.spaceList + 1] = space
    return space
end

---Works out where a space's map lies on the map shown.
---@return boolean isOnMap false when the map shown has no place for it
local function measureSpace(world, space)
    local left, top, right, bottom
    if space.mapId == world.hostMapId and not world.isJoined then
        left, top, right, bottom = 0, 0, 1, 1
    else
        left, top, right, bottom = ns.MapPins.getZoneRect(space.mapId, world.hostMapId)
        if not left and space.mapId == world.hostMapId then
            left, top, right, bottom = 0, 0, 1, 1
        end
    end
    if not left or right <= left or bottom <= top then
        space.left = nil
        return false
    end
    space.left, space.top, space.right, space.bottom = left, top, right, bottom
    space.pixels = (right - left) * world.width * world.scale
    return true
end

---Puts a space's frame where its map lies (measureSpace), and shows it.
local function showSpace(world, space)
    -- One scale for both ways (maps lie on one another without a stretch, to a thousandth: that is split evenly)
    local width, height = (space.right - space.left) * world.width, (space.bottom - space.top) * world.height
    local scale = width / UNITS
    if space.scale ~= scale then
        space.scale = scale
        space.frame:SetScale(scale)
    end
    -- (a frame's place is given in its own scaled units)
    local x = space.left * world.width / scale
    local y = -(space.top * world.height + (height - scale * UNITS * ASPECT) / 2) / scale
    if not space.isAttached or space.placedX ~= x or space.placedY ~= y then
        space.isAttached, space.placedX, space.placedY = true, x, y
        space.frame:ClearAllPoints()
        space.frame:SetPoint("TOPLEFT", world.areaRoot, "TOPLEFT", x, y)
    end
    if not space.isShown then
        space.isShown = true
        space.frame:Show()
    end
end

---Takes a space off the map: hidden, and let go, so nothing in it hangs from the map.
local function hideSpace(space)
    if space.isAttached then
        space.isAttached = false
        space.frame:ClearAllPoints()
    end
    if space.isShown then
        space.isShown = false
        space.frame:Hide()
    end
end

---------------------------------------------------------------------------------------------------------------
-- Features: what a quest shows, sorted into spaces

---@return number? key, number? mapId, number? zoneId The space a place lies in: the map its coordinates are of, and
---the zone it counts for (as a zone's map tells its own places: Compose's isOnMapZone)
local function getPlaceSpace(place)
    if not place.x or place.x < 0 or place.dungeonName then
        return nil -- (inside a dungeon: on no map; a dungeon's entrance: the dungeon's mark stands there)
    end
    local mapId = place.zoneId and ns.Database.getUiMapId(place.zoneId)
    if not mapId then
        return nil
    end
    local zoneId = place.mapZoneId or place.groupZoneId or 0
    return mapId * 100000 + zoneId, mapId, zoneId
end

---Sorts a feature's places into the spaces they lie in: each a point of its space (x across, y down, 0 to 1).
local function splitFeature(feature)
    local parts, list = {}, {}
    local count = 0
    for _, source in ipairs(feature.sources) do
        local glyph, note, places = source.glyph, source.note, source.places
        for index = 1, #places do
            local spawn = places[index]
            local key, mapId, zoneId = getPlaceSpace(spawn)
            if key then
                local part = parts[key]
                if not part then
                    part = { key = key, mapId = mapId, zoneId = zoneId, points = {} }
                    parts[key] = part
                    list[#list + 1] = part
                end
                local points = part.points
                points[#points + 1] =
                    { x = spawn.x / 100, y = spawn.y / 100, place = spawn, glyph = glyph, note = note }
            end
            count = count + 1
            if count % 64 == 0 then
                spend(3)
            end
        end
    end
    feature.parts, feature.partList = parts, list
end

---Gives each of a feature's points its level: the coarsest step of the thinning at which it still shows (Compose's
---thinPoints: the world in squares of the step's yards, in each the spawn of the lowest rank; each step's squares
---four of the finer one's, so who shows at a step shows at every finer one). All its spaces together: the squares
---are the world's, not a zone's.
local function rankFeature(feature)
    local spacings = MapMarks.SPAWN_SPACINGS
    local survivors, count = {}, 0
    for _, part in ipairs(feature.partList) do
        for _, point in ipairs(part.points) do
            if getWorldPlace(point.place) then
                point.level = 1
                survivors[#survivors + 1] = point
            else
                point.level = #spacings -- (no place in the world: always shown)
            end
        end
    end
    for level = 2, #spacings do
        local spacing = spacings[level]
        local best, bestRank = {}, {}
        for index = 1, #survivors do
            local point = survivors[index]
            local position = getWorldPlace(point.place)
            local cell = (position[1] * 4096 + math.floor(position[3] / spacing) + 2048) * 4096
                + math.floor(position[2] / spacing)
                + 2048
            local rank = getSpawnRank(point.place)
            if not bestRank[cell] or rank < bestRank[cell] then
                best[cell], bestRank[cell] = point, rank
            end
            count = count + 1
            if count % 64 == 0 then
                spend(8)
            end
        end
        survivors = {}
        for _, point in pairs(best) do
            point.level = level
            survivors[#survivors + 1] = point
        end
    end
    feature.isRanked = true
end

---A feature's points on a map zoomed far out (for its areas traced there): every zone's, placed as that map
---places the zone.
local function composeWidePoints(feature, mapId)
    local points = {}
    for _, part in ipairs(feature.partList) do
        local left, top, right, bottom
        if part.mapId == mapId then
            left, top, right, bottom = 0, 0, 1, 1
        else
            left, top, right, bottom = ns.MapPins.getZoneRect(part.mapId, mapId)
        end
        if left then
            local width, height = right - left, bottom - top
            for index, point in ipairs(part.points) do
                points[#points + 1] = { x = left + point.x * width, y = top + point.y * height }
                if index % 64 == 0 then
                    spend(4)
                end
            end
        end
    end
    return points
end

---------------------------------------------------------------------------------------------------------------
-- Areas: a quest's set of pieces in a space, at a level of detail

---@return number reach, number minCell How far a set's areas reach past their spawns and its grid's cell at least,
---of the space's width
local function getGrain(space, lod)
    local reach = space.yards and Style.AREA_REACH_YARDS / space.yards or Style.AREA_REACH
    if space.isWide then
        reach = math.max(reach, MapMarks.WIDE_REACH)
    end
    return reach * 2 ^ lod, MapMarks.MIN_AREA_CELL * 2 ^ lod
end

---@return number kind, number? maxEdges How a quest's areas are drawn on this map: as they are (0), or on a
---joined-up map with their edge thinned to a budget of pieces (1). Never by whether the quest is in focus: that
---changes how a set is coloured, not what is laid out
local function getSetKind(world)
    if not world.isJoined then
        return 0, nil
    end
    return 1, World.MAX_EDGES
end

---Takes a set off the map for good: its frames are free for other sets.
local function releaseSet(world, set)
    if set.isReleased then
        return
    end
    if set.isLaying then
        set.isDoomed = true -- (the worker is laying it out, over frames: let go as it finishes)
        return
    end
    set.isReleased, set.isShown = true, false
    local space = set.space
    if set.isOval then
        releaseFrame(world.freeOvalFrames, set.lineFrame)
        releaseFrame(world.freeOvalFrames, set.fillFrame)
    else
        releaseFrame(world.freeLineFrames, set.lineFrame)
        releaseFrame(world.freeFillFrames, set.fillFrame)
        releaseFrame(world.freeLineFrames, set.rimFrame)
    end
    world.regionCount = world.regionCount - (set.regionCount or 0)
    world.keptSets[set] = nil
    local byKind = space.sets[set.featureKey]
    if byKind then
        if byKind[set.key] == set then
            byKind[set.key] = nil
        end
        if byKind.shown == set then
            byKind.shown = nil
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- Ovals: a quest's areas as round patches (their geometry and pictures: Ovals), laid out in the spaces

---@return string geometry How areas are drawn (the settings' "Drawn as"): "ovals" (an oval with a ring a camp, soft
---patches for a scatter), "soft" (soft patches alone) or "traced" (round their spawns, as before; and where no
---frames run, the tests)
function World.getGeometry()
    if World.geometryForced ~= nil then
        return World.geometryForced
    end
    if ns.frameNumber == 0 then
        return "traced"
    end
    local geometry = ns.settings.areaGeometry
    return (geometry == "traced" or geometry == "ovals") and geometry or "soft"
end

---A quest's ovals in a space: its spawns grouped where their reaches touch, each group of two or more given its
---ovals. All in the space's widths (y too).
---@return table[] ovals, table[] areas The areas as the traced ones are kept for pointing at: { points, reach }
local function composeOvals(points, reach, isAllSoft)
    local link = reach * 2
    local cells, parents, places = {}, {}, {}
    local function getRoot(index)
        while parents[index] ~= index do
            parents[index] = parents[parents[index]]
            index = parents[index]
        end
        return index
    end
    for index, point in ipairs(points) do
        local x, y = point.x, point.y * ASPECT
        places[index] = { x, y, point }
        parents[index] = index
        local column, row = math.floor(x / link), math.floor(y / link)
        for stepColumn = -1, 1 do
            for stepRow = -1, 1 do
                for _, other in ipairs(cells[(column + stepColumn) * 65536 + row + stepRow] or NONE) do
                    local place = places[other]
                    if (place[1] - x) ^ 2 + (place[2] - y) ^ 2 <= link * link then
                        local first, second = getRoot(index), getRoot(other)
                        if first ~= second then
                            parents[first] = second
                        end
                    end
                end
            end
        end
        local key = column * 65536 + row
        local cell = cells[key]
        if not cell then
            cell = {}
            cells[key] = cell
        end
        cell[#cell + 1] = index
        if index % 64 == 0 then
            spend(4)
        end
    end
    local groups, order = {}, {}
    for index = 1, #places do
        local root = getRoot(index)
        local group = groups[root]
        if not group then
            group = {}
            groups[root] = group
            order[#order + 1] = group
        end
        group[#group + 1] = places[index]
    end
    local ovals, areas = {}, {}
    for _, group in ipairs(order) do
        if #group >= Style.AREA_MIN_POINTS then
            -- (all on one spot: a creature listed many times over is no area)
            local first, isSpread = group[1], false
            for index = 2, #group do
                if
                    math.abs(group[index][1] - first[1]) > reach * 0.05
                    or math.abs(group[index][2] - first[2]) > reach * 0.05
                then
                    isSpread = true
                    break
                end
            end
            if isSpread then
                Ovals.addGroupOvals(group, reach, ovals, isAllSoft)
                local own = {}
                for index, place in ipairs(group) do
                    own[index] = { x = place[1], y = place[2] }
                end
                areas[#areas + 1] = { points = own, reach = reach }
                spend(2)
            end
        end
    end
    return ovals, areas
end

---Lays a set out as ovals: a disc and a ring for each, on a frame each kind.
local function layOutOvals(world, set, ovals, areas)
    local space = set.space
    local fillFrame = acquireFrame(world.freeOvalFrames, space.frame)
    local lineFrame = acquireFrame(world.freeOvalFrames, space.frame)
    set.fillFrame, set.lineFrame, set.isLaying = fillFrame, lineFrame, true
    local corners = { {}, {}, {}, {} }
    for index, oval in ipairs(ovals) do
        for corner = 1, 4 do
            local x, y = World.getOvalCorner(oval, corner)
            corners[corner].x, corners[corner].y = x * UNITS, y * UNITS
        end
        local picture, fillShare, edgeShare = World.getOvalLook(oval)
        local disc = takeTexture(fillFrame, index)
        if disc.picture ~= picture then
            disc.picture = picture
            disc:SetTexture(picture)
        end
        local ring = takeTexture(lineFrame, index)
        -- (a soft patch's outline is the soft picture; a disc's ring is chosen for the zoom: styleOvals)
        if oval.isSoft and ring.picture ~= picture then
            ring.picture = picture
            ring:SetTexture(picture)
        end
        ring.isSoft, ring.share, disc.share = oval.isSoft, edgeShare, fillShare
        setQuad(disc, corners[1], corners[2], corners[3], corners[4], fillFrame)
        setQuad(ring, corners[1], corners[2], corners[3], corners[4], lineFrame)
        spend(2)
    end
    restFrom(fillFrame, #ovals + 1)
    restFrom(lineFrame, #ovals + 1)
    set.ovals, set.areas = ovals, areas
    set.lineCount, set.fillCount, set.rimCount, set.ends = #ovals, #ovals, nil, nil
    set.red, set.edgePixels, set.lineScale = nil, nil, nil -- (coloured and sized by styleOvals)
    set.regionCount = #ovals * 2
    world.regionCount = world.regionCount + set.regionCount
    world.keptSets[set] = true
    set.isLaid, set.isLaying = true, nil
    if set.isDoomed then
        releaseSet(world, set)
    end
end

---A set's edge, on its frame of lines: over the fills at the focus's level and strength (the other quests' fills,
---the focused quest's over them, its dark rim, the others' edges, its edge over all: the order the areas were always
---drawn in), hanging from the map only where the look has edges.
local function styleEdgeFrame(world, set, look, isFocused)
    local lineFrame = set.lineFrame
    lineFrame:SetFrameLevel(world.areaLevel + (isFocused and 4 or 3))
    lineFrame:SetAlpha(isFocused and look.focusedEdgeAlpha or look.edgeAlpha)
    if look.hasEdges then
        attach(lineFrame, set.space.frame)
    else
        detach(lineFrame)
    end
end

---A set of ovals in its quest's colour: each disc and ring (soft patches lie over one another: each a little fainter,
---so a thick scatter is no solid wash).
local function colorOvals(set, color)
    local lineFrame, fillFrame = set.lineFrame, set.fillFrame
    set.red, set.green, set.blue = color[1], color[2], color[3]
    for index = 1, set.lineCount do
        local ring = lineFrame.regions[index]
        ring:SetVertexColor(color[1], color[2], color[3], ring.share or 1)
        local disc = fillFrame.regions[index]
        disc:SetVertexColor(color[1], color[2], color[3], disc.share or 1)
    end
end

---Each ring of a set of ovals the picture as thick on screen as the look's edge.
local function sizeOvalRings(set, pixels, lineScale)
    local lineFrame, space = set.lineFrame, set.space
    set.edgePixels, set.lineScale = pixels, lineScale
    for index = 1, set.lineCount do
        local oval = set.ovals[index]
        local region = lineFrame.regions[index]
        if not region.isSoft then
            local picture = World.getOvalRing((oval.along + oval.across) * (space.pixels or 1), pixels)
            if region.picture ~= picture then
                region.picture = picture
                region:SetTexture(picture)
            end
        end
    end
end

---Gives a set of ovals its look: its quest's colour, each ring the picture as thick on screen as the look's edge,
---the frames' alpha and level. What does not show (no fill, no outline) lets go of the map.
local function styleOvals(world, set, feature)
    local look = MapMarks.getAreaLook()
    local isFocused = feature.isFocused == true
    local color = feature.color
    local space = set.space
    local base = world.areaLevel
    local fillFrame = set.fillFrame
    if set.red ~= color[1] or set.green ~= color[2] or set.blue ~= color[3] then
        colorOvals(set, color)
    end
    local pixels = isFocused and look.focusedEdgePixels or look.edgePixels
    local lineScale = (space.scale or 1) * world.scale
    if set.edgePixels ~= pixels or not isSameWidth(set.lineScale, lineScale) then
        sizeOvalRings(set, pixels, lineScale)
    end
    styleEdgeFrame(world, set, look, isFocused)
    set.wantsFill = look.hasFill
    fillFrame:SetFrameLevel(base + (isFocused and 1 or 0))
    fillFrame:SetAlpha(isFocused and look.focusedFillAlpha or look.fillAlpha)
    if look.hasFill then
        attach(fillFrame, space.frame)
    else
        detach(fillFrame)
    end
    set.isFocused, set.lookVersion, set.isJoined, set.isShown = isFocused, look.version, world.isJoined, true
end

---A set's fill: a texture for each piece of its areas, on a frame of its own (so it can let go by itself, where
---the look has no fill).
local function layOutFills(world, set)
    local space = set.space
    local frame = acquireFrame(world.freeFillFrames, space.frame)
    set.fillFrame, set.isLaying = frame, true
    local first, second, third, fourth = {}, {}, {}, {}
    local fills = 0
    for _, area in ipairs(set.shapes) do
        for _, piece in ipairs(area.shape.pieces or area.shape.triangles) do
            fills = fills + 1
            local texture = takeTexture(frame, fills)
            first.x, first.y = piece[1].x * UNITS, piece[1].y * UNITS
            second.x, second.y = piece[2].x * UNITS, piece[2].y * UNITS
            third.x, third.y = piece[3].x * UNITS, piece[3].y * UNITS
            if piece[4] then
                fourth.x, fourth.y = piece[4].x * UNITS, piece[4].y * UNITS
                setQuad(texture, first, second, third, fourth, frame)
            else
                setTriangle(texture, first, second, third, frame)
            end
            spend(1)
        end
    end
    restFrom(frame, fills + 1)
    set.fillCount, set.isFillColored = fills, false
    set.regionCount = set.regionCount + fills
    world.regionCount = world.regionCount + fills
    set.isLaying = nil
    if set.isDoomed then
        releaseSet(world, set)
    end
end

---A set's dark rim under its edge, for the quest in focus: its own lines, where the edge's are.
local function layOutRims(world, set)
    local frame = acquireFrame(world.freeLineFrames, set.space.frame)
    set.rimFrame = frame
    local color = MapMarks.getAreaLook().rimColor
    local ends, count = set.ends, 0
    for index = 1, #ends, 4 do
        count = count + 1
        local line = takeLine(frame, count)
        line:SetColorTexture(color[1], color[2], color[3], 1)
        line:SetStartPoint("TOPLEFT", frame, ends[index], ends[index + 1])
        line:SetEndPoint("TOPLEFT", frame, ends[index + 2], ends[index + 3])
    end
    restFrom(frame, count + 1)
    set.rimCount, set.rimScale = count, nil
    set.regionCount = set.regionCount + count
    world.regionCount = world.regionCount + count
end

---A set's lines in its quest's colour (its fill is coloured again with them, when it next shows).
local function colorLines(set, color)
    local lineFrame = set.lineFrame
    set.red, set.green, set.blue = color[1], color[2], color[3]
    for index = 1, set.lineCount do
        lineFrame.regions[index]:SetColorTexture(color[1], color[2], color[3], 1)
    end
    set.isFillColored = false
end

---A set's fill, where the look has one and it is laid out: coloured if it is not yet, at the focus's level and
---strength, hanging from the map; else let go of it.
local function styleFill(world, set, look, isFocused, color)
    local fillFrame = set.fillFrame
    if not (look.hasFill and set.fillCount) then
        if fillFrame then
            detach(fillFrame)
        end
        return
    end
    if not set.isFillColored then
        set.isFillColored = true
        for index = 1, set.fillCount do
            fillFrame.regions[index]:SetColorTexture(color[1], color[2], color[3], 1)
        end
    end
    fillFrame:SetFrameLevel(world.areaLevel + (isFocused and 1 or 0))
    fillFrame:SetAlpha(isFocused and look.focusedFillAlpha or look.fillAlpha)
    attach(fillFrame, set.space.frame)
end

---The dark rim under the edge of the quest in focus (laid out the first time it shows), its lines as wide on screen as
---the look's rim; let go of the map for any other quest, or an edge too long to double.
local function styleRim(world, set, look, isFocused, lineScale)
    if not (isFocused and look.hasEdges and set.lineCount <= World.MAX_RIM_EDGES) then
        if set.rimFrame then
            detach(set.rimFrame)
        end
        return
    end
    if not set.rimCount then
        layOutRims(world, set)
    end
    local rimFrame = set.rimFrame
    if not isSameWidth(set.rimScale, lineScale) then
        set.rimScale = lineScale
        for index = 1, set.rimCount do
            rimFrame.regions[index]:SetThickness(Style.AREA_RIM_PIXELS / lineScale)
        end
    end
    rimFrame:SetFrameLevel(world.areaLevel + 2)
    rimFrame:SetAlpha(look.focusedRimAlpha)
    attach(rimFrame, set.space.frame)
end

---Shows a laid-out set in the look it has now: in or out of focus, the areas' look and strengths, its quest's
---colour, its lines' width at this zoom. A frame's alpha and level for all its pieces at once; each piece is touched
---only for another colour or width. What of it does not show (no fill out of focus on a joined-up map, no rim) lets
---go of the map.
local function styleSet(world, set, feature)
    if set.isOval then
        return styleOvals(world, set, feature)
    end
    local look = MapMarks.getAreaLook()
    local isFocused = feature.isFocused == true
    local color = feature.color
    local lineFrame = set.lineFrame
    if set.red ~= color[1] or set.green ~= color[2] or set.blue ~= color[3] then
        colorLines(set, color)
    end
    -- (the lines lie in the space, which grows with the map: their width on screen is set for the zoom)
    local pixels = isFocused and look.focusedEdgePixels or look.edgePixels
    local lineScale = (set.space.scale or 1) * world.scale
    if set.edgePixels ~= pixels or not isSameWidth(set.lineScale, lineScale) then
        set.edgePixels, set.lineScale = pixels, lineScale
        for index = 1, set.lineCount do
            lineFrame.regions[index]:SetThickness(pixels / lineScale)
        end
    end
    styleEdgeFrame(world, set, look, isFocused)
    set.wantsFill = look.hasFill
    styleFill(world, set, look, isFocused, color)
    styleRim(world, set, look, isFocused, lineScale)
    set.isFocused, set.lookVersion, set.isJoined, set.isShown = isFocused, look.version, world.isJoined, true
end

---Lays a set's edge out in its space: a line for each piece, thinned to the set's budget of pieces where it has
---one. Its fill is laid out apart, when it shows one (layOutFills).
---@param shapes table[] Its areas (MapMarks.composeQuestShapes), in the space's widths
---@param cell number The grid's cell the shapes were traced on
local function layOutSet(world, set, shapes, reach, cell)
    local space = set.space
    local frame = acquireFrame(world.freeLineFrames, space.frame)
    set.lineFrame, set.isLaying, set.shapes = frame, true, shapes
    -- Each area's edge as traced; over the budget, every outline thinned further (a point that bends it by less than
    -- the tolerance left out) until the set is within it: small round areas stay as they are, a long ragged edge
    -- loses its smallest bends
    local edgeLists, total = {}, 0
    for index, area in ipairs(shapes) do
        edgeLists[index] = area.shape.edges
        total = total + #area.shape.edges
    end
    if set.maxEdges then
        local tolerance, tries = cell * MapMarks.EDGE_TOLERANCE, 0
        while total > set.maxEdges and tries < 8 do
            tries, tolerance, total = tries + 1, tolerance * 1.5, 0
            for index, area in ipairs(shapes) do
                if area.shape.loops then
                    edgeLists[index] = MapMarks.thinLoops(area.shape.loops, tolerance)
                end
                total = total + #edgeLists[index]
            end
            spend(4)
        end
    end
    local ends, areas, lines = {}, {}, 0
    for index, area in ipairs(shapes) do
        for _, edge in ipairs(edgeLists[index]) do
            lines = lines + 1
            local line = takeLine(frame, lines)
            local fromX, fromY = edge[1].x * UNITS, -edge[1].y * UNITS
            local toX, toY = edge[2].x * UNITS, -edge[2].y * UNITS
            line:SetStartPoint("TOPLEFT", frame, fromX, fromY)
            line:SetEndPoint("TOPLEFT", frame, toX, toY)
            local count = #ends
            ends[count + 1], ends[count + 2], ends[count + 3], ends[count + 4] = fromX, fromY, toX, toY
            spend(1)
        end
        -- Kept for pointing at: its spawns and reach, in the space's widths (MapMarks.isInsideArea)
        areas[#areas + 1] = { points = area.points, reach = reach }
    end
    restFrom(frame, lines + 1)
    set.lineCount, set.ends, set.areas = lines, ends, areas
    set.red, set.edgePixels, set.lineScale = nil, nil, nil -- (coloured and sized by styleSet)
    set.fillCount, set.rimCount = nil, nil
    set.regionCount = lines
    world.regionCount = world.regionCount + lines
    world.keptSets[set] = true
    set.isLaid, set.isLaying = true, nil
    if set.isDoomed then
        releaseSet(world, set)
    end
end

---------------------------------------------------------------------------------------------------------------
-- Walks: where a quest's creatures walk, as dashed lines

World.DASH_PIXELS_ACROSS = 512 -- a walk's dashes of level 0 are their size on screen on a space this wide
local TRAIL_COPY_YARDS = 25 -- two walks starting and ending this near are one walk, listed in two zones' maps

---Sorts where a quest's creatures walk into the spaces they lie in: each walk a line of points of its space (in
---widths), with the box it lies in. One the database lists in two zones' maps (near a border) is told as a copy:
---on a joined-up map, which shows both zones, it is drawn once.
local function composeTrails(feature)
    local trails, starts = {}, {}
    for _, patrol in ipairs(ns.Location.getObjectivePatrols(feature.questId)) do
        local mapId = patrol.zoneId and ns.Database.getUiMapId(patrol.zoneId)
        local points = patrol.points
        if mapId and points and #points >= 2 then
            local zoneId = ns.Database.getParentZoneId(patrol.zoneId) or 0
            local key = mapId * 100000 + zoneId
            local list = trails[key]
            if not list then
                list = { mapId = mapId, zoneId = zoneId }
                trails[key] = list
            end
            local walk = { npcId = patrol.npcId, points = {} }
            local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
            for index, point in ipairs(points) do
                local x, y = point[1] / 100, point[2] / 100 * ASPECT
                walk.points[index] = { x = x, y = y }
                left, right, top, bottom = math.min(left, x), math.max(right, x), math.min(top, y), math.max(bottom, y)
            end
            walk.left, walk.top, walk.right, walk.bottom = left, top, right, bottom
            local first, last = points[1], points[#points]
            local continent, north, west = ns.Geometry.getWorldPosition(mapId, first[1], first[2])
            local _, lastNorth, lastWest = ns.Geometry.getWorldPosition(mapId, last[1], last[2])
            if north and lastNorth then
                local column, row = math.floor(west / TRAIL_COPY_YARDS), math.floor(north / TRAIL_COPY_YARDS)
                for stepColumn = -1, 1 do
                    for stepRow = -1, 1 do
                        local cell = (continent * 8192 + column + stepColumn + 4096) * 8192 + row + stepRow + 4096
                        for _, other in ipairs(starts[cell] or NONE) do
                            if
                                other.zoneId ~= zoneId
                                and math.abs(other.north - north) <= TRAIL_COPY_YARDS
                                and math.abs(other.west - west) <= TRAIL_COPY_YARDS
                                and math.abs(other.lastNorth - lastNorth) <= TRAIL_COPY_YARDS
                                and math.abs(other.lastWest - lastWest) <= TRAIL_COPY_YARDS
                            then
                                walk.isCopy = true
                            end
                        end
                    end
                end
                if not walk.isCopy then
                    local cell = (continent * 8192 + column + 4096) * 8192 + row + 4096
                    starts[cell] = starts[cell] or {}
                    table.insert(
                        starts[cell],
                        { zoneId = zoneId, north = north, west = west, lastNorth = lastNorth, lastWest = lastWest }
                    )
                end
            end
            list[#list + 1] = walk
        end
    end
    feature.trails = trails
end

---@return number level The dashes' level for a space this wide on screen: each level's dashes half the one below's,
---so they stay near their size on screen; kept from the one it has near an edge
local function chooseDashLevel(pixels, current)
    local exact = math.log(math.max(pixels, 1) / World.DASH_PIXELS_ACROSS) / math.log(2)
    if current and math.abs(exact - current) < 0.6 then
        return current
    end
    return math.floor(exact + 0.5)
end

local function releaseTrail(world, trail)
    if trail.isLaying then
        trail.isDoomed = true
        return
    end
    if trail.isReleased then
        return
    end
    trail.isReleased, trail.isShown = true, false
    releaseFrame(world.freeLineFrames, trail.frame)
    world.regionCount = world.regionCount - trail.lineCount
    world.keptTrails[trail] = nil
    local byLevel = trail.space.trails[trail.featureKey]
    if byLevel then
        if byLevel[trail.key] == trail then
            byLevel[trail.key] = nil
        end
        if byLevel.shown == trail then
            byLevel.shown = nil
        end
    end
end

---Gives a walk's set the look it has now: its quest's colour, in or out of focus, its lines' width at this zoom.
local function styleTrail(world, trail, feature)
    local color = feature.color
    local frame = trail.frame
    local lineScale = (trail.space.scale or 1) * world.scale
    if
        trail.red ~= color[1]
        or trail.green ~= color[2]
        or trail.blue ~= color[3]
        or not isSameWidth(trail.lineScale, lineScale)
    then
        trail.red, trail.green, trail.blue, trail.lineScale = color[1], color[2], color[3], lineScale
        -- A light dash of the quest's colour over a faint dark one, as a trail on a paper map
        local red, green, blue =
            color[1] + (1 - color[1]) * 0.55, color[2] + (1 - color[2]) * 0.55, color[3] + (1 - color[3]) * 0.55
        local rim = Style.AREA_RIM_COLOR
        for index = 1, trail.lineCount, 2 do
            local under, over = frame.regions[index], frame.regions[index + 1]
            under:SetColorTexture(rim[1], rim[2], rim[3], MapMarks.DASH_SHADOW_ALPHA)
            under:SetThickness(MapMarks.DASH_SHADOW_WIDTH / lineScale)
            over:SetColorTexture(red, green, blue, 1)
            over:SetThickness(MapMarks.DASH_WIDTH / lineScale)
        end
    end
    local isFocused = feature.isFocused == true
    frame:SetFrameLevel(world.areaLevel + 4)
    frame:SetAlpha(isFocused and Style.FOCUSED_AREA_EDGE_ALPHA or Style.AREA_EDGE_ALPHA)
    trail.isFocused = isFocused
end

---Adds walks to a set: for each a row of dashes, two lines a dash (a faint dark one under a light one).
local function layOutTrail(world, trail, walks)
    local space = trail.space
    if not trail.frame then
        trail.frame = acquireFrame(world.freeLineFrames, space.frame)
        world.keptTrails[trail] = true
    end
    trail.isLaying = true
    local frame = trail.frame
    local across = World.DASH_PIXELS_ACROSS * 2 ^ trail.level
    local dash, gap = MapMarks.DASH_PIXELS / across, MapMarks.DASH_GAP_PIXELS / across
    local count = trail.lineCount
    for _, walk in ipairs(walks) do
        if not trail.included[walk] then
            trail.included[walk] = true
            trail.walks[#trail.walks + 1] = walk
            for _, piece in ipairs(MapMarks.composeDashes(walk.points, dash, gap)) do
                local fromX, fromY = piece.from.x * UNITS, -piece.from.y * UNITS
                local toX, toY = piece.to.x * UNITS, -piece.to.y * UNITS
                for sublevel = 1, 2 do
                    count = count + 1
                    local line = takeLine(frame, count)
                    line:SetDrawLayer("ARTWORK", sublevel)
                    line:SetStartPoint("TOPLEFT", frame, fromX, fromY)
                    line:SetEndPoint("TOPLEFT", frame, toX, toY)
                end
                spend(2)
            end
        end
    end
    restFrom(frame, count + 1)
    world.regionCount = world.regionCount + count - trail.lineCount
    trail.lineCount = count
    trail.red = nil -- (the new lines' colour and width: styleTrail)
    trail.isLaying = nil
    if trail.isDoomed then
        releaseTrail(world, trail)
    end
end

---------------------------------------------------------------------------------------------------------------
-- Spawn marks: thinned in the world, kept in tiles

---@return number yards A level's square in the world
local function getLevelYards(level)
    local spacing = MapMarks.SPAWN_SPACINGS[level]
    return spacing > 0 and spacing or World.FINEST_YARDS
end

local QUARTER_CLASS = { 1, 3, 4, 2 } -- [the quarter: column and row odd or even] = its class

---@return number key The square of a spot grid a point lies in (the world's yards, or its own space's where it has
---no place in the world)
local function getSpotKey(point, space, spot)
    local position = getWorldPlace(point.place)
    if position then
        return (position[1] * 16384 + math.floor(position[3] / spot) + 8192) * 16384
            + math.floor(position[2] / spot)
            + 8192
    end
    local yards = space.yards or DEFAULT_YARDS
    return math.floor(point.x * yards / spot) * 16384 + math.floor(point.y * ASPECT * yards / spot)
end

local function addToTile(index, space, level, point, feature)
    local levels = index.levels
    local byLevel = levels[level]
    if not byLevel then
        byLevel =
            { size = World.TILE_CELLS * getLevelYards(level) / (space.yards or DEFAULT_YARDS), tiles = {}, count = 0 }
        levels[level] = byLevel
    end
    local column, row = math.floor(point.x / byLevel.size), math.floor(point.y * ASPECT / byLevel.size)
    local key = column * 65536 + row
    local tile = byLevel.tiles[key]
    if not tile then
        tile = { space = space, level = level, column = column, row = row, points = {}, features = {}, index = index }
        tile.classes, tile.classCounts = {}, { 0, 0, 0, 0 }
        byLevel.tiles[key] = tile
        byLevel.count = byLevel.count + 1
    end
    tile.points[#tile.points + 1] = point
    tile.features[#tile.features + 1] = feature
    -- Which quarter of the next coarser step's square the point lies in (the world's squares), as a class 1 to 4:
    -- a level's marks come in a class at a time when not all of them fit (World.updateIcons), each class spread
    -- evenly (the same corner of every square, then the corner across from it, then the other two)
    local class = 1
    local position = getWorldPlace(point.place)
    if position then
        local yards = getLevelYards(level)
        class = QUARTER_CLASS[math.floor(position[3] / yards) % 2 * 2 + math.floor(position[2] / yards) % 2 + 1]
    end
    tile.classes[#tile.points] = class
    tile.classCounts[class] = tile.classCounts[class] + 1
    index.count = index.count + 1
end

---@return string? key What a feature shows when its quest is not in focus (feature.steadyKey, Compose): what it shows
---now where nothing else is said; none (false) for one that shows only while in focus
local function getSteadyKey(feature)
    if feature.steadyKey == nil then
        return feature.contentKey
    end
    return feature.steadyKey or nil
end

---What a space's sorting of spawn marks is made of: its own quests (those with spawns in it) and the places each
---shows out of focus, in their order. The same text, the same sorting: nothing to do again. A quest not sorted into
---levels yet (taken over anew, or showing other places) counts as it stands in the space's sorting now, so its marks
---stay up meanwhile and the space is sorted once, when it is ready.
---@param features table[] Every quest shown, in their order
---@return string wanted The sorting the space should have now
---@return string ready The sorting that can be made now (the quests ready for it only)
---@return table ids [feature key] = its text in the ready one
local function getIndexKey(space, features)
    local wanted, ready, ids = {}, {}, {}
    local key, known = space.key, space.indexIds or NONE
    for _, feature in ipairs(features) do
        local steadyKey = getSteadyKey(feature)
        if steadyKey then
            local id = feature.key .. "=" .. steadyKey
            if feature.parts and feature.isRanked then
                local part = feature.parts[key]
                if part and part.points and #part.points > 0 then
                    wanted[#wanted + 1], ready[#ready + 1], ids[feature.key] = id, id, id
                end
            elseif known[feature.key] then
                wanted[#wanted + 1] = known[feature.key]
            end
        end
    end
    return table.concat(wanted, ";"), table.concat(ready, ";"), ids
end

---The spawn marks of a space, every quest's together: each point in the tile of the coarsest level it shows at.
---A quest's own thinning says how far out each of its spawns shows (rankFeature); among the quests, one mark to a
---spot (half a square of the level), the quests in their order: twenty quests after one creature stacked twenty
---marks on it, only the top one seen. Worked from the coarsest level down, so who shows at a level shows at every
---finer one.
---@param features table[] The quests whose marks show out of focus, in their order
local function buildIndex(space, features)
    local index = { levels = {}, count = 0 }
    local spacings = MapMarks.SPAWN_SPACINGS
    local byLevel, steps = {}, 0
    for order, feature in ipairs(features) do
        local part = feature.parts[space.key]
        for _, point in ipairs(part and part.points or NONE) do
            local list = byLevel[point.level]
            if not list then
                list = {}
                byLevel[point.level] = list
            end
            list[#list + 1] = point
            list[#list + 1] = order
        end
    end
    local placed, waiting = {}, {} -- (points and the order of their quests, in pairs)
    for level = #spacings, 1, -1 do
        local spot = getLevelYards(level) / 2
        local taken = {}
        for position = 1, #placed do
            taken[getSpotKey(placed[position], space, spot)] = true
        end
        -- Those a coarser level had no room for, then this level's own; the quests in their order within each
        local candidates = waiting
        local own = byLevel[level]
        for position = 1, #(own or NONE) do
            candidates[#candidates + 1] = own[position]
        end
        waiting = {}
        for position = 1, #candidates, 2 do
            local point, order = candidates[position], candidates[position + 1]
            local key = getSpotKey(point, space, spot)
            if taken[key] then
                waiting[#waiting + 1], waiting[#waiting + 2] = point, order
            else
                taken[key] = true
                placed[#placed + 1] = point
                addToTile(index, space, level, point, features[order])
            end
            steps = steps + 1
            if steps % 64 == 0 then
                spend(8)
            end
        end
    end
    return index
end

---The spawn marks of one quest in a space, by its own thinning alone: the quest in focus shows all of its own, over
---the others'.
local function buildOverlay(space, feature)
    local index = { levels = {}, count = 0, isOverlay = true }
    local part = feature.parts[space.key]
    for position, point in ipairs(part and part.points or NONE) do
        addToTile(index, space, point.level, point, feature)
        if position % 64 == 0 then
            spend(4)
        end
    end
    return index
end

---How the spawn marks look now, as one text: a tile laid out in another look is laid out again.
local function getIconStyle()
    local settings = ns.settings
    return table.concat({
        MapMarks.getSpawnMarker(),
        tostring(settings.spawnMarkerScale),
        tostring(settings.shouldGlowSpawnMarkers),
        tostring(settings.otherSpawnMarkers),
    }, ":")
end

---@return number unit How long a pixel of a spawn mark is in a space's units at the zoom now: the marks lie in the
---space, which grows with the map, and are sized against it
local function getIconUnit(world, space)
    return (world.markScale or 1) / ((space.scale or 1) * world.scale)
end

---Puts one of a tile's spawn marks on its spot (its glow, where its kind has one, and its icon).
local function placeIcon(tile, index)
    local frame, point = tile.frame, tile.points[index]
    local x, y = point.x * UNITS, -point.y * ASPECT * UNITS
    local glow, glyph = frame.glows[index], frame.glyphs[index]
    if (tile.classes[index] or 1) > (tile.shownShare or 4) then
        rest(glow) -- (of a class its level does not show yet: the view has no room for all of the level)
        rest(glyph)
        return
    end
    if tile.hasUnder then
        glow.isResting = nil
        place(glow, "CENTER", frame, "TOPLEFT", x, y)
        glow:Show()
    else
        rest(glow)
    end
    glyph.isResting = nil
    place(glyph, "CENTER", frame, "TOPLEFT", x, y)
    glyph:Show()
end

local releaseTile, followIcons

---Lays a tile's spawn marks out (or, laid out already, sizes them for the zoom now): for each a glow and an icon
---on the tile's frame, in the space's units.
local function layOutTile(world, tile)
    local space = tile.space
    local frame = tile.frame
    local isNew = not tile.isLaid
    if not frame then
        frame = acquireFrame(world.freeTileFrames, space.frame)
        tile.frame = frame
    end
    tile.isLaying = true
    tile.shownShare = tile.wantedShare or 4
    local isOverlay = tile.index.isOverlay == true
    local kind = MapMarks.getSpawnMarker()
    local unit = getIconUnit(world, space)
    local size = Style.ICON_SIZE * math.max(0.5, math.min(2, tonumber(ns.settings.spawnMarkerScale) or 1))
    local glowSize = size * Style.ICON_GLOW_SIZE / Style.ICON_SIZE
    local _, isStrong = MapMarks.getSpawnMarkerStrength(isOverlay)
    if isOverlay then
        size = size + 2 -- the focused quest's a little larger, so its spawns stand out from the others'
    end
    local points, features = tile.points, tile.features
    for index = 1, #points do
        local glow, glyph = frame.glows[index], frame.glyphs[index]
        if not glow then
            glow = remember(frame:CreateTexture(nil, "ARTWORK", nil, 1))
            glyph = remember(frame:CreateTexture(nil, "ARTWORK", nil, 2))
            frame.glows[index], frame.glyphs[index] = glow, glyph
        end
        tile.hasUnder = MapMarks.dressSpawnMarker(
            glow,
            glyph,
            kind,
            points[index].glyph or "use",
            features[index].color,
            isStrong,
            size * unit,
            glowSize * unit,
            nil,
            unit
        )
        if not (tile.cleared and tile.cleared[index]) then
            placeIcon(tile, index)
        end
        -- (its sizes at this zoom, for keeping it as large on screen all through the next one: World.follow)
        glow.baseWidth, glow.baseHeight = glow:GetSize()
        glyph.baseWidth, glyph.baseHeight = glyph:GetSize()
        spend(isNew and 4 or 1) -- (a spawn mark is some twenty calls into the game when new, a few when only sized)
    end
    for index = #points + 1, #frame.glows do
        rest(frame.glows[index])
        rest(frame.glyphs[index])
    end
    frame:SetFrameLevel(world.iconLevel + (isOverlay and 1 or 0))
    if isNew then
        world.iconCount = world.iconCount + #points
    end
    tile.radius, tile.unit = glowSize / 2, unit
    tile.isLaid, tile.style, tile.colors = true, world.iconStyle, world.colorStamp
    tile.isLaying, tile.followed = nil, nil
    world.isFollowDue = true
    world.keptTiles[tile] = true
    if tile.isDoomed then
        releaseTile(world, tile)
    end
end

releaseTile = function(world, tile)
    if tile.isLaying then
        tile.isDoomed = true -- (the worker is laying it out: let go as it finishes)
        return
    end
    if not tile.isLaid then
        return
    end
    tile.isLaid, tile.cleared = false, nil
    releaseFrame(world.freeTileFrames, tile.frame)
    tile.frame = nil
    world.iconCount = world.iconCount - #tile.points
    world.keptTiles[tile] = nil
    world.shownTiles[tile] = nil
end

---Lets a space's tiles of an index go (the index is made again: other quests, other places).
local function releaseIndex(world, index)
    for _, byLevel in pairs(index and index.levels or NONE) do
        for _, tile in pairs(byLevel.tiles) do
            releaseTile(world, tile)
        end
    end
end

---The tiles of an index under a part of its space, of the levels from `level` up, each given to `visit`.
---@param view { left: number, top: number, right: number, bottom: number } In the space's widths
---@return boolean isIn Some spawn of a tile lies in a view. A coarse level's tile is a large square of the zone with
---a few spawns in it: zoomed in on another corner of the square, the tile hung from the map with none of them near.
local function isTileInView(tile, view)
    local count = #tile.points
    if tile.boundsCount ~= count then
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for index = 1, count do
            local point = tile.points[index]
            local x, y = point.x, point.y * ASPECT
            minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x), math.min(minY, y), math.max(maxY, y)
        end
        tile.minX, tile.maxX, tile.minY, tile.maxY, tile.boundsCount = minX, maxX, minY, maxY, count
    end
    return tile.maxX >= view.left and tile.minX <= view.right and tile.maxY >= view.top and tile.minY <= view.bottom
end

---Calls visit(tile, context) for each tile of a sorting under a view, of its levels from `level` up (a file's own
---visitor and a context it is handed, so no closure is made for a visit).
local function visitTiles(index, view, level, visit, context)
    for tileLevel, byLevel in pairs(index.levels) do
        if tileLevel >= level then
            local size = byLevel.size
            local firstColumn, lastColumn = math.floor(view.left / size), math.floor(view.right / size)
            local firstRow, lastRow = math.floor(view.top / size), math.floor(view.bottom / size)
            if (lastColumn - firstColumn + 1) * (lastRow - firstRow + 1) < byLevel.count then
                for column = firstColumn, lastColumn do
                    for row = firstRow, lastRow do
                        local tile = byLevel.tiles[column * 65536 + row]
                        if tile and isTileInView(tile, view) then
                            visit(tile, context)
                        end
                    end
                end
            else
                for _, tile in pairs(byLevel.tiles) do
                    if
                        tile.column >= firstColumn
                        and tile.column <= lastColumn
                        and tile.row >= firstRow
                        and tile.row <= lastRow
                        and isTileInView(tile, view)
                    then
                        visit(tile, context)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- What the quests show

---Takes what the quests show now (MapMarks.composeFeatures). A quest showing the places it did keeps all that was
---made of them; only its focus and colour are taken over.
function World.setFeatures(map, features)
    local world = getWorld(map)
    local byKey = {}
    for order, feature in ipairs(features) do
        local known = world.featureByKey[feature.key]
        if known and known.contentKey == feature.contentKey then
            if
                known.color ~= feature.color
                and (
                    known.color[1] ~= feature.color[1]
                    or known.color[2] ~= feature.color[2]
                    or known.color[3] ~= feature.color[3]
                )
            then
                world.colorStamp = (world.colorStamp or 0) + 1 -- (the spawn marks' colours: their tiles again)
            end
            known.color, known.isFocused, known.hasNoPatrols = feature.color, feature.isFocused, feature.hasNoPatrols
            known.steadyKey = feature.steadyKey
            features[order] = known
            feature = known
        else
            if known then
                known.isGone = true
            end
            -- (sorted for another map already, the same places: taken over as they are, shared and read only)
            local twin = sortedFeatures[feature.key]
            if twin and twin.contentKey == feature.contentKey and twin.parts then
                feature.parts, feature.partList, feature.placeCount = twin.parts, twin.partList, twin.placeCount
                feature.isRanked, feature.trails = twin.isRanked, twin.trails
            end
        end
        byKey[feature.key] = feature
    end
    for key, known in pairs(world.featureByKey) do
        if byKey[key] ~= known then
            known.isGone = true
            -- What was made of it is taken off the map: every space's
            for _, space in ipairs(world.spaceList) do
                local byKind = space.sets[key]
                if byKind then
                    for setKey, set in pairs(byKind) do
                        if setKey ~= "shown" then
                            releaseSet(world, set)
                        end
                    end
                    space.sets[key] = nil
                end
                local overlay = space.overlays[key]
                if overlay then
                    releaseIndex(world, overlay)
                    space.overlays[key] = nil
                end
                local byLevel = space.trails[key]
                if byLevel then
                    for trailKey, trail in pairs(byLevel) do
                        if type(trail) == "table" and trailKey ~= "shown" then
                            releaseTrail(world, trail)
                        end
                    end
                    space.trails[key] = nil
                end
            end
        end
    end
    world.features, world.featureByKey = features, byKey
    world.isDirty, world.dirtyAt = true, -math.huge
end

---------------------------------------------------------------------------------------------------------------
-- The view: what shows, and what is still to make

local function isInBounds(left, top, right, bottom, bounds)
    return right >= bounds.left and left <= bounds.right and bottom >= bounds.top and top <= bounds.bottom
end

local function addTask(world, task)
    world.todo[#world.todo + 1] = task
end

---@return number distance How far a space's middle is from the view's, for what to make first
local function getDistance(world, space)
    local view = world.visible or world.cull
    local x, y = (space.left + space.right) / 2, (space.top + space.bottom) / 2
    return math.abs(x - (view.left + view.right) / 2) + math.abs(y - (view.top + view.bottom) / 2)
end

---Shows a set, in the look it has now (styled again only when something of that changed).
local function showSet(world, set, feature)
    local look = MapMarks.getAreaLook()
    local color = feature.color
    if
        not set.isShown
        or set.lookVersion ~= look.version
        or set.isFocused ~= (feature.isFocused == true)
        or set.isJoined ~= world.isJoined
        or set.red ~= color[1]
        or set.green ~= color[2]
        or set.blue ~= color[3]
        or not isSameWidth(set.lineScale, (set.space.scale or 1) * world.scale)
        or (set.wantsFill and set.fillCount and not set.fillFrame.isAttached)
    then
        styleSet(world, set, feature)
    end
    set.seenAt = now
end

---Takes a set off the map: its frames hidden and let go.
local function hideSet(set)
    if set.isShown then
        set.isShown = false
        detach(set.lineFrame)
        if set.fillFrame then
            detach(set.fillFrame)
        end
        if set.rimFrame then
            detach(set.rimFrame)
        end
    end
end

---@return boolean isOut Where a quest's places lie in a space, against what of the space is in view (and its margin):
---none of them near it, nothing of its set hangs from the map and nothing of it is made. A zone has a set for every
---quest in it, and zoomed in on one corner of the zone (or on open sea beside it) all of them hung there, each piece
---many times the screen's size, their lines given a width again at every step of the zoom.
local function isPartOutOfView(world, feature, space, lod)
    local part = not space.isWide and feature.parts and feature.parts[space.key]
    local view = space.view
    if not (part and view and not world.isHolding) then
        return false
    end
    local bounds = part.bounds
    if not bounds then
        bounds = { left = math.huge, top = math.huge, right = -math.huge, bottom = -math.huge }
        for _, point in ipairs(part.points) do
            local x, y = point.x, point.y * ASPECT
            bounds.left, bounds.right = math.min(bounds.left, x), math.max(bounds.right, x)
            bounds.top, bounds.bottom = math.min(bounds.top, y), math.max(bounds.bottom, y)
        end
        part.bounds = bounds
    end
    local reach = getGrain(space, lod) * 2 -- (an area reaches past its spawns; twice that, to be sure of it)
    return bounds.right + reach < view.left
        or bounds.left - reach > view.right
        or bounds.bottom + reach < view.top
        or bounds.top - reach > view.bottom
end

---@return table set A quest's set in a space at a level of detail, in the geometry drawn now (made, not laid out, the
---first time it is asked for)
local function getSet(world, feature, space, lod, byKind)
    local kind, maxEdges = getSetKind(world, feature)
    local geometry = World.getGeometry()
    local isOval = geometry ~= "traced"
    local key = lod * 4 + kind
    if isOval then
        -- (ovals, or soft patches alone: one set a space, the same at every zoom)
        lod, maxEdges, key = 0, nil, geometry == "soft" and -2 or -1
    end
    local set = byKind[key]
    if not set then
        set = { space = space, featureKey = feature.key, lod = lod, key = key, maxEdges = maxEdges, isOval = isOval }
        set.isAllSoft = geometry == "soft"
        byKind[key] = set
    end
    return set
end

---A quest's areas in a space: the set of the level wanted shown if it is laid out, else asked for, whatever shows
---of it now left up meanwhile.
---@param isHeld boolean? Not shown yet though laid out: another way of drawing the same ground stands in until all
---of this way's are (the map's own set, while its zones' sets are made)
---@return boolean isReady The wanted set shows, or can
local function wantSet(world, feature, space, lod, priority, isHeld)
    local byKind = space.sets[feature.key]
    if not byKind then
        byKind = {}
        space.sets[feature.key] = byKind
    end
    if isPartOutOfView(world, feature, space, lod) then
        -- (what showed of it is taken off and remembered: it stands in again when the view comes back to it)
        if byKind.shown then
            hideSet(byKind.shown)
        end
        return true
    end
    local set = getSet(world, feature, space, lod, byKind)
    if set.isEmpty then
        if byKind.shown then
            hideSet(byKind.shown)
            byKind.shown = nil
        end
        return true -- (too few spawns for an area at this grain: nothing to show)
    end
    if set.isLaid then
        if isHeld then
            return true
        end
        set.isWanted = world.pass
        if byKind.shown and byKind.shown ~= set then
            hideSet(byKind.shown)
        end
        byKind.shown = set
        showSet(world, set, feature)
        if set.wantsFill and not set.fillCount then
            addTask(world, { kind = "fills", set = set, feature = feature, priority = priority })
        end
        return true
    end
    if byKind.shown and not isHeld then
        byKind.shown.isWanted = world.pass -- (stands in until the wanted one is laid out)
        showSet(world, byKind.shown, feature)
    end
    addTask(world, { kind = "set", set = set, feature = feature, priority = priority })
    return false
end

---@return number? hostMapId The map shown (closed: the one it opens on, the player's own zone); nil when there is
---nothing to make ready for
---@return number width, number height, number scale, boolean isOpen The canvas's size, the zoom, and whether it shows
local function readHost(world, map)
    local canvas = world.canvas
    local hostMapId = map.GetMapID and map:GetMapID()
    local isOpen = map.IsVisible ~= nil and map:IsVisible()
    if not isOpen and C_Map and C_Map.GetBestMapForUnit then
        -- Closed: made ready for the map it opens on, the player's own zone
        hostMapId = C_Map.GetBestMapForUnit("player") or hostMapId
    end
    local width, height = canvas:GetWidth(), canvas:GetHeight()
    local scale = map.GetCanvasScale and map:GetCanvasScale()
    local hasSize = type(width) == "number" and width > 0 and type(height) == "number" and height > 0
    if not isOpen and not (hasSize and type(scale) == "number" and scale > 0) then
        -- Never opened yet (its canvas has no size before it shows a map): made ready for the size the game's maps
        -- have and the zoom a zone's own map opens at; placed anew as it opens
        width, height, scale = World.CANVAS_WIDTH, World.CANVAS_WIDTH * ASPECT, world.scale or World.OPENING_SCALE
        hasSize = true
    end
    if not hostMapId or not hasSize then
        return nil
    end
    scale = type(scale) == "number" and scale > 0 and scale or 1
    return hostMapId, width, height, scale, isOpen
end

---Placed as this map places zones: with another addon's neighbours joined on (OpenMap), or the game's own way.
---@return boolean isJoined Another addon joins zones onto the map
local function setUpJoin(world, map, isOpen)
    local view = map == WorldMapFrame and ns.Compatibility.getMapView(map) or nil
    if isOpen then
        world.lastView = view
    elseif not view then
        view = world.lastView -- (closed: as it last showed zones; another addon's joined-up way says none then)
    end
    ns.MapPins.setView(view, view and { left = -1, top = -1, right = 2, bottom = 2 } or nil, nil)
    local isJoined = view ~= nil
    if world.isJoined ~= isJoined then
        world.isJoined = isJoined
        for _, feature in ipairs(world.features) do
            feature.wide = nil -- (a far map's points are placed as the map places its zones)
        end
    end
    return isJoined
end

---What of the map is in view, and a margin round it (world.visible, world.cull).
local function setUpWorldCull(world, map, isOpen, isJoined)
    local hostMapId = world.hostMapId
    local visible = isOpen and ns.MapPins.getVisibleBounds(map, 0) or nil
    if visible then
        local extraX = (visible.right - visible.left) * World.VIEW_MARGIN
        local extraY = (visible.bottom - visible.top) * World.VIEW_MARGIN
        world.visible = visible
        world.cull = {
            left = visible.left - extraX,
            top = visible.top - extraY,
            right = visible.right + extraX,
            bottom = visible.bottom + extraY,
        }
    elseif not world.cull or world.cullMapId ~= hostMapId then
        -- Not laid out, or closed on another map than it last showed: the whole map, and on a joined-up one a margin
        -- round it (its view reaches past the map underneath)
        local margin = isJoined and 0.5 or 0
        world.visible = nil
        world.cull = { left = -margin, top = -margin, right = 1 + margin, bottom = 1 + margin }
    end
    world.cullMapId, world.cullScale = hostMapId, world.scale
end

---@return number? hostZone A zone's own map shows that zone's places alone; a continent's, the world's and a joined-up
---one, every zone's (nil)
local function getHostZone(hostMapId, isJoined)
    if isJoined or MapMarks.isAboveZones(hostMapId) then
        return nil
    end
    local areaId = ns.Database.getAreaId(hostMapId)
    return areaId and ns.Database.getParentZoneId(areaId)
end

---The spaces the quests have places in, made where missing; a quest not yet sorted into spaces asks for that (the
---quest in focus first; a quest of thousands of spawns after the others' areas are laid out).
local function askForSpaces(world)
    for _, feature in ipairs(world.features) do
        if not feature.parts then
            local count = 0
            for _, source in ipairs(feature.sources) do
                count = count + #source.places
            end
            feature.placeCount = count
            addTask(world, {
                kind = "split",
                feature = feature,
                priority = feature.isFocused and -2 or (count > World.HEAVY_FROM and 35 or 9) + count / 1000000,
            })
        else
            for _, part in ipairs(feature.partList) do
                if not world.spaces[part.key] then
                    createSpace(world, part.key, part.mapId, part.zoneId, false)
                end
            end
            for key, walks in pairs(feature.trails or NONE) do
                if not world.spaces[key] then
                    createSpace(world, key, walks.mapId, walks.zoneId, false)
                end
            end
        end
    end
end

---A space on the map shown and in view (or held while another map comes underneath) is placed and shown, its level of
---detail chosen and the part of it in view kept (in its own widths); any other is taken off.
local function lookAtSpace(world, space, hostZone)
    local cull = world.cull
    local isOnMap
    if space.isWide then
        isOnMap = space.mapId == world.hostMapId -- (the map shown's own: all of it)
    else
        isOnMap = not hostZone or space.zoneId == hostZone
    end
    if
        not isOnMap
        or not measureSpace(world, space)
        or not (
            isInBounds(space.left, space.top, space.right, space.bottom, cull) or (world.isHolding and space.isShown)
        )
    then
        hideSpace(space)
        return
    end
    showSpace(world, space)
    space.lod = World.chooseLod(space.pixels, space.lod)
    local spaceWidth, spaceHeight = space.right - space.left, space.bottom - space.top
    local spaceView = space.view or {}
    spaceView.left = math.max(0, (cull.left - space.left) / spaceWidth)
    spaceView.right = math.min(1, (cull.right - space.left) / spaceWidth)
    spaceView.top = math.max(0, (cull.top - space.top) / spaceHeight) * ASPECT
    spaceView.bottom = math.min(1, (cull.bottom - space.top) / spaceHeight) * ASPECT
    space.view = spaceView
end

-- Zoomed far out (few pixels a yard: a continent's map, the world's, a joined-up map showing a continent), a quest's
-- areas are traced on the map shown itself, every zone's spawns together: one set a quest, at a grain the screen
-- shows, however many zones it is spread over. Nearer, each zone in view has its own.
---@return table? wide The map shown's own space (made the first time it is wanted)
---@return boolean isWideMode The areas are traced on it
local function chooseWideSpace(world, isJoined, hostZone)
    local hostMapId = world.hostMapId
    local hostYards = MapMarks.getMapYards(hostMapId)
    local perYard = hostYards and world.width * world.scale / hostYards
    local isWideMode = false
    if perYard and (isJoined or MapMarks.isAboveZones(hostMapId)) then
        isWideMode = perYard < World.WIDE_BELOW_PER_YARD * (world.isWideMode and WIDE_SLACK or 1 / WIDE_SLACK)
    end
    world.isWideMode = isWideMode
    local wideKey = "wide:" .. hostMapId
    local wide = world.spaces[wideKey]
    if isWideMode and not wide then
        wide = createSpace(world, wideKey, hostMapId, nil, true)
        lookAtSpace(world, wide, hostZone)
    end
    return wide, isWideMode
end

---Zoomed far out: a quest's set on the map shown; until it is laid out, the zones' sets that showed stay up.
local function wantWideAreas(world, feature, wide, base)
    if wantSet(world, feature, wide, wide.lod, base) then
        return
    end
    for _, part in ipairs(feature.partList) do
        local space = world.spaces[part.key]
        local shown = space and space.isShown and space.sets[feature.key]
        shown = shown and shown.shown
        if shown then
            shown.isWanted = world.pass
            showSet(world, shown, feature)
        end
    end
end

---Nearer: a quest's set in each zone in view. Coming in from far out, the map's own set stays up until every zone's
---is laid out, then they all show at once.
local function wantZoneAreas(world, feature, wide, base)
    local wideShown = wide and wide.sets[feature.key] and wide.sets[feature.key].shown
    local isEveryReady, held = true, {}
    for _, part in ipairs(feature.partList) do
        local space = world.spaces[part.key]
        if space and space.isShown then
            local isReady =
                wantSet(world, feature, space, space.lod, base + getDistance(world, space), wideShown ~= nil)
            isEveryReady = isEveryReady and isReady
            held[#held + 1] = space
        end
    end
    if not wideShown then
        return
    end
    if isEveryReady then
        for _, space in ipairs(held) do
            wantSet(world, feature, space, space.lod, 0) -- (every zone's is laid out: shown, all at once)
        end
    elseif wide.left then
        wideShown.isWanted = world.pass
        showSpace(world, wide)
        showSet(world, wideShown, feature)
    end
end

---The areas: each quest's sets for what is in view. Changing from one way to the other, the old way's sets stay up
---until the new way's are all laid out, so the areas never blink out.
local function wantAreas(world, wide, isWideMode)
    if not MapMarks.hasAreas() then
        return
    end
    local isFocusedOnly = ns.settings.shouldShowFocusedAreasOnly
    for _, feature in ipairs(world.features) do
        if feature.parts and (feature.isFocused or not isFocusedOnly) then
            local base = feature.isFocused and 0 or 10
            if not isWideMode then
                wantZoneAreas(world, feature, wide, base)
            elseif wide.isShown then
                wantWideAreas(world, feature, wide, base)
            end
        end
    end
end

---The walks: each quest's in every space in view, those under the view laid out. On a joined-up map only the quest
---in focus': a walk is a row of dashes, two lines each, and twenty quests' were hundreds.
local function wantTrails(world, isJoined)
    for _, feature in ipairs(world.features) do
        if not feature.hasNoPatrols and feature.parts and (feature.isFocused or not isJoined) then
            if not feature.trails then
                addTask(world, { kind = "trails", feature = feature, priority = 11 })
            else
                for key, walks in pairs(feature.trails) do
                    local space = world.spaces[key]
                    if space and space.isShown and not space.isWide then
                        World.wantTrail(world, feature, space, walks)
                    end
                end
            end
        end
    end
end

---The sets that show and are not wanted any more: taken off, unless the view is held.
local function takeOffUnwantedSets(world)
    for set in pairs(world.keptSets) do
        if set.isShown and set.isWanted ~= world.pass and not world.isHolding then
            hideSet(set)
            local byKind = set.space.sets[set.featureKey]
            if byKind and byKind.shown == set then
                byKind.shown = nil
            end
        end
    end
end

local function takeOffUnwantedTrails(world)
    for trail in pairs(world.keptTrails) do
        if trail.isShown and trail.isWanted ~= world.pass and not world.isHolding then
            trail.isShown = false
            detach(trail.frame)
            local byLevel = trail.space.trails[trail.featureKey]
            if byLevel and byLevel.shown == trail then
                byLevel.shown = nil
            end
        end
    end
end

local function isTaskFirst(first, second)
    return first.priority < second.priority
end

---Looks at the map as it shows now: places the spaces, shows what is made for the view, lets go what is not in it,
---and lists what is still to make. Asks nothing heavy of the game and works nothing out: that is the worker's.
function World.update(map)
    local world = getWorld(map)
    if not ensureRoots(world) then
        return
    end
    world.isDirty, world.updatedAt = false, now
    local hostMapId, width, height, scale, isOpen = readHost(world, map)
    if not hostMapId then
        return
    end
    local isJoined = setUpJoin(world, map, isOpen)
    world.hostMapId, world.width, world.height, world.scale = hostMapId, width, height, scale
    if isOpen then
        world.followedScale = scale
    end
    -- The spawn marks are drawn smaller as the map shows more of the world, as the quests' marks are (Draw)
    world.markScale = map == WorldMapFrame and MapMarks.getMarkScale(hostMapId, width * scale) or 1
    world.pass = (world.pass or 0) + 1
    world.todo = {}
    local areaLevel, iconLevel = MapMarks.getAreaFrameLevel(map), MapMarks.getFrameLevel(map)
    if world.areaLevel ~= areaLevel or world.iconLevel ~= iconLevel then
        world.areaLevel, world.iconLevel = areaLevel, iconLevel
        world.areaRoot:SetFrameLevel(areaLevel)
    end
    setUpWorldCull(world, map, isOpen, isJoined)
    local hostZone = getHostZone(hostMapId, isJoined)
    askForSpaces(world)
    for _, space in ipairs(world.spaceList) do
        lookAtSpace(world, space, hostZone)
    end
    local wide, isWideMode = chooseWideSpace(world, isJoined, hostZone)
    wantAreas(world, wide, isWideMode)
    takeOffUnwantedSets(world)
    wantTrails(world, isJoined)
    takeOffUnwantedTrails(world)
    World.updateIcons(world, world.cull)
    world.isFollowDue = true -- (spaces placed anew, other tiles shown: their marks' sizes looked at)
    table.sort(world.todo, isTaskFirst)
    MapMarks.useMap(map) -- (the marks' own view of this map again: MapPins)
    if driver then
        driver:Show()
    end
end

---@return table trail A quest's walks in a space at the dashes' level its size on screen asks for (made, empty, the
---first time it is asked for)
local function getTrail(world, feature, space, byLevel)
    byLevel.level = chooseDashLevel(space.pixels, byLevel.level)
    local key = byLevel.level * 2 + (world.isJoined and 1 or 0)
    local trail = byLevel[key]
    if not trail then
        trail = {
            space = space,
            featureKey = feature.key,
            level = byLevel.level,
            key = key,
            included = {},
            walks = {},
            lineCount = 0,
        }
        byLevel[key] = trail
    end
    return trail
end

---@return table[]? missing The walks under the view a trail has not laid out yet. A walk shorter on screen than a few
---dashes says nothing; one out of view waits for the view to come to it
local function findMissingWalks(world, trail, walks, view)
    local minExtent = MapMarks.MIN_PATROL_PIXELS / (World.DASH_PIXELS_ACROSS * 2 ^ trail.level)
    local missing
    for _, walk in ipairs(walks) do
        if
            not trail.included[walk]
            and not (world.isJoined and walk.isCopy)
            and math.max(walk.right - walk.left, walk.bottom - walk.top) >= minExtent
            and walk.right >= view.left
            and walk.left <= view.right
            and walk.bottom >= view.top
            and walk.top <= view.bottom
        then
            missing = missing or {}
            missing[#missing + 1] = walk
        end
    end
    return missing
end

---Shows a laid-out trail in its quest's look now (styled again only when something of that changed).
local function showTrail(world, trail, feature, space)
    trail.isWanted, trail.seenAt = world.pass, now
    local color = feature.color
    if
        trail.red ~= color[1]
        or trail.green ~= color[2]
        or trail.blue ~= color[3]
        or trail.isFocused ~= (feature.isFocused == true)
        or not isSameWidth(trail.lineScale, (space.scale or 1) * world.scale)
    then
        styleTrail(world, trail, feature)
    end
    if not trail.isShown then
        trail.isShown = true
        attach(trail.frame, space.frame)
    end
end

---A quest's walks in a space: those under the view at the dashes' level its size on screen asks for, shown once
---laid out; the level shown before stays up meanwhile.
function World.wantTrail(world, feature, space, walks)
    local byLevel = space.trails[feature.key]
    if not byLevel then
        byLevel = {}
        space.trails[feature.key] = byLevel
    end
    local trail = getTrail(world, feature, space, byLevel)
    local missing = findMissingWalks(world, trail, walks, space.view)
    if missing then
        addTask(world, {
            kind = "trail",
            trail = trail,
            walks = missing,
            priority = (feature.isFocused and 2 or 12) + getDistance(world, space),
        })
    end
    local shown = byLevel.shown
    if missing and shown and shown ~= trail and not shown.isReleased then
        trail = shown -- (the level before stands in until this one's walks in view are laid out)
    elseif shown and shown ~= trail and shown.isShown then
        shown.isShown = false
        detach(shown.frame)
    end
    if trail.frame and trail.lineCount > 0 and not trail.isLaying then
        byLevel.shown = trail
        showTrail(world, trail, feature, space)
    end
end

---@return boolean isCurrent A tile's marks are laid out in the spawn markers' kind and the quests' colours now (their
---size on screen is kept at every frame: followIcons)
local function isTileCurrent(world, tile)
    return tile.isLaid and tile.style == world.iconStyle and tile.colors == world.colorStamp
end

---@return number distance How far a tile's middle is from the view's, for what to make first
local function getTileDistance(world, tile, cull)
    local space = tile.space
    local size = tile.index.levels[tile.level].size
    local x = space.left + (tile.column + 0.5) * size * (space.right - space.left)
    local y = space.top + (tile.row + 0.5) * size / ASPECT * (space.bottom - space.top)
    local visible = world.visible or cull
    return math.abs(x - (visible.left + visible.right) / 2) + math.abs(y - (visible.top + visible.bottom) / 2)
end

---@return number level, number zoomShare The step of the spawns' thinning the zoom has room for (Compose's rule, by
---the pixels a yard: its place among MapMarks.SPAWN_SPACINGS), and how many of the finer step's classes it has room
---for besides
local function chooseIconLevel(world)
    local hostYards = MapMarks.getMapYards(world.hostMapId)
    local markScale = (world.markScale or 1) * MapMarks.getSpawnMarkerRoom(ns.settings.spawnMarkerScale)
    -- (kept as it is while another map comes underneath: the zoom is not that map's yet, and a step chosen for a zoom
    -- never shown stuck, by the slack a step has at its edges; marks went missing until the next zoom)
    if not (world.isHolding and world.spacing) then
        local spacing =
            MapMarks.chooseSpawnSpacing(hostYards and world.width * world.scale / hostYards, world.spacing, markScale)
        world.spacing = spacing
    end
    local level = 1
    for index, spacing in ipairs(MapMarks.SPAWN_SPACINGS) do
        if spacing == world.spacing then
            level = index
        end
    end
    -- Between two steps the finer one's marks come in a class at a time (addToTile), as the zoom makes room: with one
    -- class the marks stand half again as close as the coarser step's alone, with two as close as... so a zoom fills
    -- the gaps bit by bit where a whole step, four times the marks, came in at once
    local zoomShare = 0
    if level > 1 then
        local room = MapMarks.getSpawnRoom(
            hostYards and world.width * world.scale / hostYards,
            MapMarks.SPAWN_SPACINGS[level],
            markScale
        )
        zoomShare = room >= 1.732 and 2 or (room >= 1.414 and 1 or 0)
    end
    return level, zoomShare
end

---@return table[] others, table? focused The quests whose marks show out of focus, and the one in focus (its own over
---the others'). A quest not ranked yet asks for that (one of thousands of spawns after the others' marks are up: the
---marks are sorted again then).
local function listIconFeatures(world, isOthersShown)
    local others, focused = {}, nil
    for _, feature in ipairs(world.features) do
        if not feature.parts then -- luacheck: ignore 542 (not sorted into spaces yet: no marks of it)
        elseif not feature.isRanked then
            local isHeavy = (feature.placeCount or 0) > World.HEAVY_FROM
            addTask(world, {
                kind = "rank",
                feature = feature,
                priority = feature.isFocused and 4 or (isHeavy and 40 or 18),
            })
        else
            -- (sorted with the others by what it shows out of focus; what shows only in focus is the overlay's)
            local steadyKey = getSteadyKey(feature)
            if steadyKey and isOthersShown then
                others[#others + 1] = feature
            end
            if feature.isFocused then
                focused = feature
            end
        end
    end
    return others, focused
end

---Adds a tile's marks of each class to its level's counts (addToTile's classes).
local function countClasses(into, tile)
    local own = into[tile.level]
    if not own then
        own = { 0, 0, 0, 0 }
        into[tile.level] = own
    end
    for class = 1, 4 do
        own[class] = own[class] + tile.classCounts[class]
    end
end

-- A visit's context (visitTiles): refilled for each visit, so a visit makes no closure
local tileVisit = {}

---A tile under the view: listed, its marks counted by level and by class (into tileVisit's list and counts).
local function collectTile(tile, into)
    local list = into.list
    list[#list + 1] = tile
    into.counts[tile.level] = (into.counts[tile.level] or 0) + #tile.points
    countClasses(into.classCounts, tile)
end

---@return table[] list A sorting's tiles under a space's view, their marks counted into the tally's counts
local function collectTiles(index, view, visitLevel, counts, classCounts)
    local list = {}
    tileVisit.list, tileVisit.counts, tileVisit.classCounts = list, counts, classCounts
    visitTiles(index, view, visitLevel, collectTile, tileVisit)
    tileVisit.list, tileVisit.counts, tileVisit.classCounts = nil, nil, nil
    return list
end

---A space's spawn marks under the view: its sorting asked for where it is not the one wanted (it stands in until the
---new one is done), its tiles listed and counted into the tally; the quest in focus's own over the others'.
local function gatherSpaceTiles(world, space, tally, visitLevel, isOthersShown)
    local view = space.view
    -- Sorted for the quests ready now that have spawns in this space; again as the others come (a quest of thousands
    -- takes a while). Only this space's own quests count (getIndexKey): a quest taken, done or sorted elsewhere
    -- leaves this space's marks as they stand.
    local wantedKey, readyKey, ids = getIndexKey(space, isOthersShown and world.features or NONE)
    space.wantedIndexKey, space.readyIndexKey = wantedKey, readyKey
    if (space.indexKey or "") ~= wantedKey then
        addTask(world, {
            kind = "index",
            space = space,
            features = tally.others,
            stamp = readyKey,
            ids = ids,
            priority = 20 + getDistance(world, space),
        })
    end
    tally.lists[space] = space.index and collectTiles(space.index, view, visitLevel, tally.counts, tally.classCounts)
        or {}
    local focused = tally.focused
    if not (focused and focused.parts[space.key]) then
        return
    end
    local overlay = space.overlays[focused.key]
    if not overlay then
        tally.isFocusComing = true
        addTask(world, { kind = "overlay", space = space, feature = focused, priority = 5 + getDistance(world, space) })
        return
    end
    tally.focusedLists[space] = collectTiles(overlay, view, visitLevel, tally.focusedCounts, tally.focusedClassCounts)
end

---@return number total The marks counted at a level and coarser
local function countFrom(counts, level)
    local total = 0
    for tileLevel, count in pairs(counts) do
        total = total + (tileLevel >= level and count or 0)
    end
    return total
end

---More than the screen takes (than a joined-up map can carry while it is dragged): the next coarser level, until it
---does. The quest in focus' own marks, drawn over the others', are counted apart from them: they stand on the very
---spots the others' do, and counted with them, putting a quest in focus put the view over what it takes and thinned
---every quest's marks a step, the others' gone from half their spots.
---@return number level, number partShare The level shown, and how many classes of the finer one show with it
local function thinToFit(world, tally, level, zoomShare)
    local most = world.isJoined and World.MAX_ICONS_JOINED or World.MAX_ICONS
    local counts, focusedCounts = tally.counts, tally.focusedCounts
    local total, focusedTotal = countFrom(counts, level), countFrom(focusedCounts, level)
    local roomiest = level -- (the step the zoom itself has room for)
    while (total > most or focusedTotal > most) and level < #MapMarks.SPAWN_SPACINGS do
        total = total - (counts[level] or 0)
        focusedTotal = focusedTotal - (focusedCounts[level] or 0)
        level = level + 1
    end
    -- Thinned a step for the view's sake, the step left out is four times the marks of the one shown: all or nothing
    -- of it, a zoom changed the whole pattern at once. As many of its classes as still fit are shown with the coarser
    -- step (each class a quarter of the squares, spread evenly: addToTile), so zooming in fills the gaps between the
    -- marks that stand, a class at a time, and none of those moves.
    local partShare = 0
    if level > 1 then
        local own, focusedOwn = tally.classCounts[level - 1] or NONE, tally.focusedClassCounts[level - 1] or NONE
        local sum, focusedSum = total, focusedTotal
        -- (thinned for the view's sake: as many classes as fit; else as many as the zoom has room for)
        for class = 1, level > roomiest and 3 or zoomShare do
            sum, focusedSum = sum + (own[class] or 0), focusedSum + (focusedOwn[class] or 0)
            if sum > most or focusedSum > most then
                break
            end
            partShare = class
        end
    end
    return level, partShare
end

---@return number? share How many classes of a tile's marks show (4: all); nil, none of them
local function getTileShare(world, tile)
    local level, partShare = world.iconLevel0, world.iconPartShare
    if tile.level >= level then
        return 4
    end
    return tile.level == level - 1 and partShare > 0 and partShare or nil
end

---An old sorting's tile that shows stays up (tileVisit.world, .isWanted).
local function keepShownTile(tile, into)
    if into.world.shownTiles[tile] then
        into.isWanted[tile] = true
    end
end

---A space's tiles wanted, and asked for where they are not current (once its sorting is the one wanted). The sorting
---before this one: its tiles stay up until this one's are laid out, so none blinks out.
local function wantSpaceTiles(world, space, list, isWanted, cull)
    local isAllLaid = (space.indexKey or "") == space.wantedIndexKey
    for _, tile in ipairs(list) do
        local share = getTileShare(world, tile)
        if share then
            isWanted[tile], tile.wantedShare = true, share
            if not isTileCurrent(world, tile) then
                isAllLaid = false
                if (space.indexKey or "") == space.wantedIndexKey then
                    addTask(world, { kind = "tile", tile = tile, priority = 30 + getTileDistance(world, tile, cull) })
                end
            end
        end
    end
    if not space.oldIndex then
        return
    end
    if isAllLaid then
        releaseIndex(world, space.oldIndex)
        space.oldIndex = nil
        return
    end
    tileVisit.world, tileVisit.isWanted = world, isWanted
    visitTiles(space.oldIndex, space.view, 1, keepShownTile, tileVisit)
    tileVisit.world, tileVisit.isWanted = nil, nil
end

---The quest in focus's tiles in a space wanted, and asked for (before the others') where they are not current.
---@return boolean isFocusComing Some are still to be laid out
local function wantFocusedTiles(world, list, isWanted, cull)
    local isFocusComing = false
    for _, tile in ipairs(list) do
        local share = getTileShare(world, tile)
        if share then
            isWanted[tile], tile.wantedShare = true, share
            if not isTileCurrent(world, tile) then
                isFocusComing = true
                addTask(world, { kind = "tile", tile = tile, priority = 6 + getTileDistance(world, tile, cull) })
            end
        end
    end
    return isFocusComing
end

---The tiles of the spawn marks wanted for the view, put in isWanted, and what is missing of them asked for.
---@return boolean isFocusComing The quest in focus' own spawn marks are still being made for some of the view
local function wantIcons(world, cull, isWanted)
    local level, zoomShare = chooseIconLevel(world)
    local visitLevel = math.max(1, level - 1) -- (the finer step's tiles too: some of their classes may show)
    local isOthersShown = MapMarks.getSpawnMarkerStrength(false)
    local tally = {
        lists = {},
        focusedLists = {},
        counts = {},
        focusedCounts = {},
        classCounts = {}, -- [level] = how many of each class (addToTile)
        focusedClassCounts = {},
        isFocusComing = false,
    }
    tally.others, tally.focused = listIconFeatures(world, isOthersShown)
    for _, space in ipairs(world.spaceList) do
        if space.isShown and not space.isWide then
            gatherSpaceTiles(world, space, tally, visitLevel, isOthersShown)
        end
    end
    local partShare
    level, partShare = thinToFit(world, tally, level, zoomShare)
    world.iconLevel0, world.iconPartShare = level, partShare
    for space, list in pairs(tally.lists) do
        wantSpaceTiles(world, space, list, isWanted, cull)
    end
    local isFocusComing = tally.isFocusComing
    for _, list in pairs(tally.focusedLists) do
        if wantFocusedTiles(world, list, isWanted, cull) then
            isFocusComing = true
        end
    end
    return isFocusComing
end

---The wanted tiles that are laid out hang from the map; each shows the share of its marks wanted (those of the
---classes shown now placed, the rest put by).
---@return boolean isAnyNew A tile was not showing before
local function showWantedTiles(world, isWanted)
    local isAnyNew = false
    for tile in pairs(isWanted) do
        if tile.isLaid and tile.frame and (not tile.isLaying or world.shownTiles[tile]) then
            if not world.shownTiles[tile] then
                world.shownTiles[tile] = true
                attach(tile.frame, tile.space.frame)
                isAnyNew = true
            end
            if tile.wantedShare and tile.shownShare ~= tile.wantedShare and not tile.isLaying then
                tile.shownShare = tile.wantedShare
                for index = 1, #tile.points do
                    if not (tile.cleared and tile.cleared[index]) then
                        placeIcon(tile, index)
                    end
                end
                tile.followed, world.isFollowDue = nil, true
            end
            tile.seenAt = now
        end
    end
    return isAnyNew
end

---The tiles that show and are not wanted: taken off. The spawn marks of the quest that was in focus stay up until the
---new one's are made, a frame or a few: the two change places at once, with no moment of neither.
local function takeOffUnwantedTiles(world, isWanted, isFocusComing)
    for tile in pairs(world.shownTiles) do
        if
            not isWanted[tile]
            and not world.isHolding
            and not (isFocusComing and tile.index and tile.index.isOverlay)
        then
            world.shownTiles[tile] = nil
            if tile.frame then
                detach(tile.frame)
            end
        end
    end
end

---The spawn marks: the tiles under the view of the levels its zoom has room for.
function World.updateIcons(world, cull)
    world.iconStyle = getIconStyle()
    local isWanted = {}
    local isFocusComing = false
    if MapMarks.getSpawnMarker() ~= "none" and #world.features > 0 then
        isFocusComing = wantIcons(world, cull, isWanted)
    end
    local isAnyNew = showWantedTiles(world, isWanted)
    takeOffUnwantedTiles(world, isWanted, isFocusComing)
    if isAnyNew and world.clearPoints then
        World.clearNear(world.map, world.clearPoints) -- (none of the new ones under the player or the party)
    end
end

---@return number|false unit How many of a space's units a mark's unit is now (as layOutTile's: sizes are so many of
---these): how many of the screen's pixels one of the space's units is, and with it how large the marks are drawn at
---this zoom (smaller far out, as the quests' marks are). False while the space's frame has no scale.
local function getMarkUnit(space, containerScale, map)
    local spaceScale = space.frame:GetEffectiveScale()
    if type(spaceScale) ~= "number" or spaceScale <= 0 then
        return false
    end
    local perUnit = spaceScale / containerScale
    local markScale = 1
    if map == WorldMapFrame then
        markScale = MapMarks.getMarkScaleAt(perUnit * UNITS / (space.yards or DEFAULT_YARDS))
    end
    return markScale / perUnit
end

---Each of a tile's marks (its glow and its icon) its own size times the share, where it is placed.
local function sizeTileMarks(tile, frame, share)
    local glows, glyphs = frame.glows, frame.glyphs
    for index = 1, #tile.points do
        local glow, glyph = glows[index], glyphs[index]
        if glow and glow.baseWidth and not glow.isResting then
            glow:SetSize(glow.baseWidth * share, glow.baseHeight * share)
        end
        if glyph and glyph.baseWidth and not glyph.isResting then
            glyph:SetSize(glyph.baseWidth * share, glyph.baseHeight * share)
        end
    end
end

---The spawn marks in view are the size on screen they are meant to be, at every frame: each mark's two pictures
---given the size that makes them so, reckoned from how large their space is drawn on screen at this moment (asked
---of the game: its frame's scale), not from what the map last said of its zoom. A zoom and another map coming
---underneath both pass through moments where the two disagree; sized from the map's word, marks grew and shrank
---with the zoom and jumped back after it, or were left a fraction of their size once the map underneath changed.
---Looked at each frame the map is open (a question a space), and sized only when the answer changed: two calls a
---mark, no text among them, and only for the marks that show.
followIcons = function(world, map)
    local container = map.ScrollContainer
    local containerScale = container and container.GetEffectiveScale and container:GetEffectiveScale()
    if type(containerScale) ~= "number" or containerScale <= 0 then
        return
    end
    -- (nothing moved and nothing new laid out since the last look: one question, and done)
    local canvasScale = world.canvas and world.canvas:GetEffectiveScale()
    if not world.isFollowDue and canvasScale == world.followedCanvasScale then
        return
    end
    world.isFollowDue, world.followedCanvasScale = false, canvasScale
    local pass = world.followPass or {}
    world.followPass = pass
    for key in pairs(pass) do
        pass[key] = nil
    end
    for tile in pairs(world.shownTiles) do
        local frame, space = tile.frame, tile.space
        if frame and tile.isLaid and not tile.isLaying and tile.unit and tile.unit > 0 and space.frame then
            local wanted = pass[space]
            if wanted == nil then
                wanted = getMarkUnit(space, containerScale, map)
                pass[space] = wanted
            end
            local share = wanted and wanted / tile.unit
            if share and (not tile.followed or math.abs(share / tile.followed - 1) > 0.004) then
                tile.followed = share
                sizeTileMarks(tile, frame, share)
            end
        end
    end
end

---The map zoomed a step. Nothing of the kept drawing is touched while it zooms (it lies in the spaces, and grows
---with the map); the view is looked at again once the zoom has settled, and what shows then is sized for it.
function World.follow(map)
    local world = worlds[map]
    if not world or not world.areaRoot then
        return
    end
    local scale = map.GetCanvasScale and map:GetCanvasScale()
    if type(scale) ~= "number" or scale <= 0 then
        return
    end
    if world.followedScale ~= scale then
        if world.followedScale ~= nil then
            world.isDirty, world.dirtyAt = true, now -- (other levels of detail, other tiles, other sizes)
            world.zoomedAt = now
            if driver then
                driver:Show()
            end
        end
        world.followedScale = scale
    end
end

---------------------------------------------------------------------------------------------------------------
-- The worker: what is still to make, a frame's share at a time

---Lets the longest unseen of what is kept go, once more is kept than the game should carry.
local function trim(world)
    local function letGo(kept, isShown, release, isOver)
        if not isOver(1) then
            return
        end
        local hidden = {}
        for item in pairs(kept) do
            if not isShown(item) then
                hidden[#hidden + 1] = item
            end
        end
        table.sort(hidden, function(first, second)
            return (first.seenAt or 0) < (second.seenAt or 0)
        end)
        for _, item in ipairs(hidden) do
            if not isOver(0.8) then
                break
            end
            release(world, item)
        end
    end
    local function isOverRegions(share)
        return world.regionCount > World.MAX_KEPT_REGIONS * share
    end
    local function isSetShown(item)
        return item.isShown
    end
    letGo(world.keptSets, isSetShown, releaseSet, isOverRegions)
    letGo(world.keptTrails, isSetShown, releaseTrail, isOverRegions)
    letGo(
        world.keptTiles,
        function(tile)
            return world.shownTiles[tile] == true
        end,
        releaseTile,
        function(share)
            return world.iconCount > World.MAX_KEPT_ICONS * share
        end
    )
end

---@return table[] points A quest's places in a space: on the map shown's own (zoomed far out), every zone's together,
---placed as the map places zones (worked out once a map); in a zone's, its part there
local function getSetPoints(feature, space)
    if not space.isWide then
        local part = feature.parts[space.key]
        return part and part.points or NONE
    end
    feature.wide = feature.wide or {}
    local points = feature.wide[space.mapId]
    if not points then
        points = composeWidePoints(feature, space.mapId)
        feature.wide[space.mapId] = points
    end
    return points
end

---Lays a quest's set of areas out in its space: as ovals, or traced (its shapes worked out first).
---@return boolean isChanged
local function runSetTask(world, task)
    local set, feature = task.set, task.feature
    if set.isLaid or set.isLaying or set.isReleased or feature.isGone then
        return false
    end
    local space = set.space
    local points = getSetPoints(feature, space)
    local reach, minCell = getGrain(space, set.lod)
    if set.isOval then
        local ovals, areas = composeOvals(points, reach, set.isAllSoft)
        if #ovals == 0 then
            set.isEmpty = true
            return true
        end
        layOutOvals(world, set, ovals, areas)
        return true
    end
    -- (worked out over the next frames by Areas' own job, a slice each; laid out when it says they are ready)
    -- (told by the quest, as the minimap's are: a zone's own grain worked out for one serves the other)
    local shapes = MapMarks.composeQuestShapes(
        feature.questId or feature.key,
        space.mapId,
        points,
        reach,
        ASPECT,
        World.isImmediate == true or ns.frameNumber == 0,
        minCell
    )
    if not shapes then
        world.isWaitingForShapes = true
        return false
    end
    if #shapes == 0 then
        set.isEmpty = true -- (too few spawns for an area, or all in one spot: nothing to lay out)
        return true
    end
    layOutSet(world, set, shapes, reach, math.max(reach / MapMarks.AREA_CELLS_PER_REACH, minCell))
    return true
end

---Sorts a space's spawn marks for the quests it was asked for, unless asked for once more meanwhile or the quests
---changed meanwhile (nothing to sort for then).
local function runIndexTask(world, task)
    local space = task.space
    local stamp = task.stamp
    if (space.indexKey or "") ~= space.wantedIndexKey and stamp == space.readyIndexKey then
        local index = buildIndex(space, task.features)
        if stamp == space.readyIndexKey then -- (the quests did not change while it was sorted)
            -- (the one before stays up until this one's tiles are laid out: World.updateIcons)
            releaseIndex(world, space.oldIndex)
            space.oldIndex = space.index
            space.index, space.indexKey, space.indexIds = index, stamp, task.ids
            space.wantedIndexKey = stamp
            world.stamp = world.stamp + 1 -- (how many times a space was sorted: the audits read it)
        end
    end
    return true
end

-- Each kind of work: function(world, task) returning whether the view is to be looked at again (something new can
-- show)
local TASKS = {
    split = function(_, task)
        if not task.feature.parts then
            splitFeature(task.feature)
            sortedFeatures[task.feature.key] = task.feature
        end
        return true
    end,
    rank = function(_, task)
        if not task.feature.isRanked then
            rankFeature(task.feature)
            sortedFeatures[task.feature.key] = task.feature
        end
        return true
    end,
    trails = function(_, task)
        if not task.feature.trails then
            composeTrails(task.feature)
            sortedFeatures[task.feature.key] = task.feature
        end
        return true
    end,
    trail = function(world, task)
        if not task.trail.isReleased and not task.trail.isLaying then
            layOutTrail(world, task.trail, task.walks)
            return true
        end
        return false
    end,
    set = runSetTask,
    fills = function(world, task)
        local set = task.set
        if set.isLaid and not set.fillCount and not set.isReleased and not set.isLaying then
            layOutFills(world, set)
            return true
        end
        return false
    end,
    index = runIndexTask,
    overlay = function(_, task)
        local space, feature = task.space, task.feature
        if not space.overlays[feature.key] and not feature.isGone then
            space.overlays[feature.key] = buildOverlay(space, feature)
        end
        return true
    end,
    tile = function(world, task)
        local tile = task.tile
        if
            not tile.isLaying
            and (
                tile.index == tile.space.index
                or tile.space.overlays[tile.features[1] and tile.features[1].key] == tile.index
            )
        then
            layOutTile(world, tile)
            return true
        end
        return false
    end,
}

---Does one piece of work. @return boolean isChanged The view is to be looked at again (something new can show)
local function runTask(world, task)
    local run = TASKS[task.kind]
    return run ~= nil and run(world, task) == true
end

local function work(world)
    while true do
        local todo = world.todo
        local position = 1
        while todo == world.todo and todo[position] do
            local task = todo[position]
            position = position + 1
            if World.onTask then
                World.onTask(task, true) -- (the simulator's audits time each piece of work)
            end
            if runTask(world, task) then
                -- Looked at again at the next frame (cheap): what was just made shows, what it makes possible is
                -- listed. The list is then a new one, and the work goes on with it.
                world.isDirty, world.dirtyAt = true, -math.huge
            end
            if World.onTask then
                World.onTask(task, false)
            end
            spend(1)
        end
        if todo == world.todo then
            world.todo = {}
            trim(world)
            coroutine.yield("done")
        end
    end
end

---Runs a world's work for a frame's share: of time, and of pieces of work.
local function runWorker(world, milliseconds, pieces)
    if not world.worker or coroutine.status(world.worker) == "dead" then
        world.worker = coroutine.create(work)
    end
    deadline, allowance = getMilliseconds() + milliseconds, pieces
    -- (placed as this map places zones while it works: a far map's points)
    local view = world.isJoined
            and world.map == WorldMapFrame
            and (ns.Compatibility.getMapView(world.map) or world.lastView)
        or nil
    ns.MapPins.setView(view, view and { left = -1, top = -1, right = 2, bottom = 2 } or nil, nil)
    local isFine, result = coroutine.resume(world.worker, world)
    deadline, allowance = math.huge, math.huge
    MapMarks.useMap(world.map)
    if not isFine then
        world.worker = nil
        world.todo = {}
        if geterrorhandler then
            geterrorhandler()(result)
        else
            error(result, 0) -- (the tests: said, not swallowed)
        end
    end
    return result == "done"
end

---A quest's shapes are worked out (Areas' job): laid out by the worker at its next turn.
function World.handleShapesReady()
    for _, world in pairs(worlds) do
        if world.isWaitingForShapes then
            world.isWaitingForShapes = false
            world.isDirty, world.dirtyAt = true, -math.huge
        end
    end
    if driver then
        driver:Show()
    end
end

---The map shows another map underneath (a zone picked, OpenMap crossing into one): every space is placed for it
---at once, in the same frame, and nothing of the kept drawing is hidden meanwhile.
function World.handleMapChanged(map)
    local world = worlds[map]
    if world and world.areaRoot and not world.isHidden then
        -- (The map says so before its zoom is the new map's: another addon's joined-up view sets that a step later.
        -- The lines' widths, which go by the zoom, wait for it: set now they were set for a zoom never shown, all of
        -- them, and again a moment later.)
        -- (And what of the map is in view is reckoned from that zoom too: nothing that shows is taken off for it.
        -- Taken off by a view that was never shown, spawn marks and areas went missing for a moment at every
        -- change of the map underneath, some until the map next moved.)
        areWidthsHeld, world.isHolding = true, true
        World.update(map)
        areWidthsHeld, world.isHolding = false, false
        world.isDirty, world.dirtyAt = true, now -- (looked at again once it has settled: the widths, if they changed)
    end
end

---The map opened: looked at as it shows now, at once (made ready for the player's zone while it was closed, it may
---open on another map, or with another addon's view), and its clock runs again. Its marks may well be kept from the
---last opening (MapPins), with nothing drawn that would start it.
function World.handleMapShown(map)
    local world = worlds[map]
    if world and world.areaRoot and not world.isHidden then
        now = GetTime and GetTime() or now
        World.update(map)
    end
end

---@return boolean isMoved The view shows past what was last looked at (a drag), or at another zoom
local function hasViewMoved(world)
    local map = world.map
    if world.cullMapId ~= map:GetMapID() then
        return true
    end
    local visible = ns.MapPins.getVisibleBounds(map, 0)
    local cull = world.cull
    if not visible or not cull then
        return false
    end
    return visible.left < cull.left
        or visible.right > cull.right
        or visible.top < cull.top
        or visible.bottom > cull.bottom
        -- (zoomed in far past what was looked at: the margin is many views wide now, most of it for nothing)
        or (visible.right - visible.left) * (1 + 2 * World.VIEW_MARGIN) < (cull.right - cull.left) * 0.6
end

---An open map's frame: the zoom followed, the spawn marks' size on screen kept (whatever moved the map), and now and
---then a look at whether a drag moved the view past what was looked at.
local function followOpenWorld(world, map, elapsed)
    World.follow(map)
    followIcons(world, map)
    world.sinceViewCheck = (world.sinceViewCheck or 0) + elapsed
    if world.sinceViewCheck >= VIEW_CHECK_SECONDS then
        world.sinceViewCheck = 0
        if not world.isDirty and hasViewMoved(world) then
            world.isDirty, world.dirtyAt = true, now
        end
    end
end

---A world that changed is looked at again once it has stayed put (or moved for too long). Looked at while a zoom is
---still on its way, for the areas and tiles it brings into view: the lines' widths wait for it to stay put, hundreds
---of them set at every look otherwise, each for a zoom passed through.
local function updateIfSettled(world, map)
    if
        not world.isDirty
        or not world.areaRoot
        or (now - (world.dirtyAt or 0) < SETTLE_SECONDS and now - (world.updatedAt or 0) < MAX_WAIT_SECONDS)
    then
        return
    end
    local isZoomOnItsWay = now - (world.zoomedAt or -math.huge) < SETTLE_SECONDS
    areWidthsHeld = isZoomOnItsWay
    World.update(map)
    areWidthsHeld = false
    if isZoomOnItsWay then
        world.isDirty, world.dirtyAt = true, world.zoomedAt
    end
end

---A frame's share of a world's work: not while a zoom is on its way (what it passes through would be made for
---nothing), nor in a fight with the map closed.
local function workIfDue(world, isOpen)
    local isZooming = now - (world.zoomedAt or -math.huge) < SETTLE_SECONDS
    if world.todo[1] and not isZooming and not (not isOpen and InCombatLockdown and InCombatLockdown()) then
        runWorker(
            world,
            isOpen and World.OPEN_MILLISECONDS or World.CLOSED_MILLISECONDS,
            isOpen and World.OPEN_PIECES or World.CLOSED_PIECES
        )
    end
end

---The kept drawing's frame, for every map: followed, looked at again, worked on; the driver sleeps when none is busy.
local function drive(elapsed)
    now = GetTime and GetTime() or (now + elapsed)
    local isAnyBusy = false
    for map, world in pairs(worlds) do
        local isOpen = world.areaRoot ~= nil and not world.isHidden and map.IsVisible ~= nil and map:IsVisible()
        if isOpen then
            isAnyBusy = true
            followOpenWorld(world, map, elapsed)
        end
        updateIfSettled(world, map)
        if world.todo[1] or world.isDirty then
            isAnyBusy = true
        end
        workIfDue(world, isOpen)
    end
    -- (what the worker laid out in this frame is sized for the screen before the frame is drawn)
    for map, world in pairs(worlds) do
        if world.isFollowDue and world.areaRoot and not world.isHidden and map.IsVisible and map:IsVisible() then
            followIcons(world, map)
        end
    end
    if not isAnyBusy and driver then
        driver:Hide()
    end
end

---Starts the kept drawing's own clock (its frame's OnUpdate): made with the first map it draws on.
local function ensureDriver()
    if not driver and CreateFrame then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", function(_, elapsed)
            ns.Timing.measure("kept map drawing (a frame's share)", drive, elapsed)
        end)
    end
    if driver then
        driver:Show()
    end
end

---Draws a map's quests' areas and spawn marks: takes what the quests show and looks at the view. Called with the
---marks' drawing (MapMarks.draw), and by itself when only the view changed.
function World.draw(map, features)
    ensureDriver()
    now = GetTime and GetTime() or now
    World.setFeatures(map, features)
    World.update(map)
    if ns.frameNumber == 0 then
        World.finish(map) -- (where no frames run, all at once)
    end
end

---Does all the work waiting, at once: for the tests, and for the simulator's pictures.
function World.finish(map)
    local world = worlds[map]
    if not world then
        return
    end
    local wasImmediate = World.isImmediate
    World.isImmediate = true -- (the shapes too: worked out at once, not over frames)
    for _ = 1, 50 do
        if not world.todo[1] and not world.isDirty then
            break
        end
        if world.isDirty then
            World.update(map)
        end
        if world.todo[1] then
            runWorker(world, math.huge, math.huge)
        end
    end
    World.isImmediate = wasImmediate
end

---The quests changed with the map closed: what they show is taken now, and the player's zone made ready a little
---each frame, so the map opens on areas and spawn marks already laid out.
function World.prepare(map, features)
    local world = getWorld(map)
    if not ensureRoots(world) then
        return
    end
    ensureDriver()
    World.setFeatures(map, features)
end

---------------------------------------------------------------------------------------------------------------
-- Pointing at them

---The quests whose shown areas in a space hold a point (in the space's widths), added to `areas`.
local function findAreasUnder(world, space, localX, localY, areas)
    for featureKey, byKind in pairs(space.sets) do
        local set = byKind.shown
        local feature = world.featureByKey[featureKey]
        if set and set.isShown and feature then
            for _, area in ipairs(set.areas) do
                if MapMarks.isInsideArea(area, localX, localY) then
                    areas[#areas + 1] =
                        { isUnder = true, questId = feature.questId, isFocused = feature.isFocused == true }
                    break
                end
            end
        end
    end
end

---The quests whose shown walks in a space pass within a few pixels of a point, added to `areas`.
local function findWalksUnder(world, space, localX, localY, areas)
    local lineReach = 4 / (space.pixels or 1)
    for featureKey, byLevel in pairs(space.trails) do
        local trail, feature = byLevel.shown, world.featureByKey[featureKey]
        for _, walk in ipairs(trail and trail.isShown and feature and trail.walks or NONE) do
            if
                localX >= walk.left - lineReach
                and localX <= walk.right + lineReach
                and localY >= walk.top - lineReach
                and localY <= walk.bottom + lineReach
                and World.isOnWalk(walk, localX, localY, lineReach)
            then
                local name = walk.npcId and ns.Database.getNpcField(walk.npcId, "name")
                areas[#areas + 1] = {
                    isUnder = true,
                    questId = feature.questId,
                    isFocused = feature.isFocused == true,
                    note = name and ns.L("%s walks here", name) or nil,
                }
                break
            end
        end
    end
end

-- A visit's context for the spawn marks under a point (findSpotsUnder): refilled for each, so a visit makes no
-- closure
local spotVisit = {}

---A shown tile's spawn marks the point is on, each by how far it is from it on screen, added to spotVisit's spots.
local function collectSpots(tile, into)
    if not into.world.shownTiles[tile] then
        return
    end
    local localX, localY, perWidth, spots = into.localX, into.localY, into.perWidth, into.spots
    local radius = (tile.radius or 8) * (into.world.markScale or 1)
    for index, point in ipairs(tile.points) do
        local offsetX, offsetY = (point.x - localX) * perWidth, (point.y * ASPECT - localY) * perWidth
        if
            offsetX * offsetX + offsetY * offsetY <= radius * radius
            and not (tile.cleared and tile.cleared[index])
            and (tile.classes[index] or 1) <= (tile.shownShare or 4)
        then
            spots[#spots + 1] = {
                x = offsetX,
                y = offsetY,
                radius = radius,
                questId = tile.features[index].questId,
                note = point.note,
                isFocused = tile.index.isOverlay == true,
            }
        end
    end
end

---The spawn marks of a zone's space round a point, added to `spots`.
local function findSpotsUnder(world, space, localX, localY, spots)
    local level = world.iconLevel0 or 1
    local perWidth = space.pixels -- pixels a width of the space
    local reach = 12 / perWidth
    local view = { left = localX - reach, right = localX + reach, top = localY - reach, bottom = localY + reach }
    spotVisit.world, spotVisit.localX, spotVisit.localY, spotVisit.perWidth, spotVisit.spots =
        world, localX, localY, perWidth, spots
    if space.index then
        visitTiles(space.index, view, math.max(1, level - 1), collectSpots, spotVisit)
    end
    for _, overlay in pairs(space.overlays) do
        visitTiles(overlay, view, math.max(1, level - 1), collectSpots, spotVisit)
    end
    spotVisit.world, spotVisit.spots = nil, nil
end

---What of the kept drawing lies under a point of the map: the spawn marks near it and the quests whose areas hold
---it, as MapHover's findQuests takes them.
---@param x number The point, as a fraction of the map's width (y of its height)
---@return table[] spots { x, y, radius, questId, note, isFocused }: each spawn mark the point is on, its place from
---the point and its reach, in the canvas's units times its zoom now (pixels, as far as the map's own scale goes)
---@return table[] areas { isUnder = true, questId, isFocused }
function World.findUnder(map, x, y)
    local world = worlds[map]
    local spots, areas = {}, {}
    if not world or not world.areaRoot or not world.width then
        return spots, areas
    end
    for _, space in ipairs(world.spaceList) do
        if space.isShown and x >= space.left and x <= space.right and y >= space.top and y <= space.bottom then
            local localX = (x - space.left) / (space.right - space.left)
            local localY = (y - space.top) / (space.bottom - space.top) * ASPECT
            findAreasUnder(world, space, localX, localY, areas)
            findWalksUnder(world, space, localX, localY, areas)
            if not space.isWide and space.pixels then
                findSpotsUnder(world, space, localX, localY, spots)
            end
        end
    end
    return spots, areas
end

---@return boolean isOn A point lies within reach of a walk's line (all in the space's widths)
function World.isOnWalk(walk, x, y, reach)
    local points = walk.points
    for index = 2, #points do
        local from, to = points[index - 1], points[index]
        local dx, dy = to.x - from.x, to.y - from.y
        local lengthSquared = dx * dx + dy * dy
        local share = lengthSquared > 0
                and math.max(0, math.min(1, ((x - from.x) * dx + (y - from.y) * dy) / lengthSquared))
            or 0
        local nearX, nearY = from.x + dx * share, from.y + dy * share
        if (x - nearX) ^ 2 + (y - nearY) ^ 2 <= reach * reach then
            return true
        end
    end
    return false
end

---Keeps the player and the party plain to see: the spawn marks near each are taken off, and put back once they
---have moved on.
---@param points { mapX: number, mapY: number, radius: number }[] Each a fraction of the map across and down, its
---radius in pixels
function World.clearNear(map, points)
    local world = worlds[map]
    if not world or not world.areaRoot or not world.width then
        return
    end
    -- Put back: those taken off at the last look
    for _, entry in ipairs(world.cleared) do
        local tile, index = entry[1], entry[2]
        if tile.cleared and tile.cleared[index] then
            tile.cleared[index] = nil
            if tile.isLaid and tile.frame then
                placeIcon(tile, index)
            end
        end
    end
    world.cleared = {}
    world.clearPoints = points -- (looked at again as other tiles come up: World.updateIcons)
    local level = world.iconLevel0 or 1
    for _, point in ipairs(points) do
        local x, y = point.mapX, point.mapY
        for _, space in ipairs(world.spaceList) do
            if
                space.isShown
                and not space.isWide
                and x >= space.left
                and x <= space.right
                and y >= space.top
                and y <= space.bottom
            then
                local localX = (x - space.left) / (space.right - space.left)
                local localY = (y - space.top) / (space.bottom - space.top) * ASPECT
                local reach = point.radius * (world.markScale or 1) / space.pixels
                local view =
                    { left = localX - reach, right = localX + reach, top = localY - reach, bottom = localY + reach }
                local function visit(tile)
                    if world.shownTiles[tile] and tile.isLaid and tile.frame then
                        for index, spawn in ipairs(tile.points) do
                            if (spawn.x - localX) ^ 2 + (spawn.y * ASPECT - localY) ^ 2 < reach * reach then
                                tile.cleared = tile.cleared or {}
                                if not tile.cleared[index] then
                                    tile.cleared[index] = true
                                    rest(tile.frame.glows[index])
                                    rest(tile.frame.glyphs[index])
                                    world.cleared[#world.cleared + 1] = { tile, index }
                                end
                            end
                        end
                    end
                end
                if space.index then
                    visitTiles(space.index, view, math.max(1, level - 1), visit)
                end
                for _, overlay in pairs(space.overlays) do
                    visitTiles(overlay, view, math.max(1, level - 1), visit)
                end
            end
        end
    end
end

---What the kept drawing shows on a map now, listed as the other drawing lists its own (its State.drawn.areas and
---.squares): for the tests and the simulator's scenarios, which look at what is drawn.
---@param pixelScale number The zoom the spawn marks' places are given at (the other drawing's: its canvas's)
---@return table[] areas Each { points, reach, questId, isFocused }, in the canvas's units
---@return table[] spots Each { x, y, radius, questId, note, isFocused }, in the canvas's units times pixelScale
function World.list(map, pixelScale)
    local world = worlds[map]
    local areas, spots = {}, {}
    if not world or not world.areaRoot or not world.width then
        return areas, spots
    end
    for _, space in ipairs(world.spaceList) do
        if space.isShown then
            local across, down = (space.right - space.left) * world.width, (space.bottom - space.top) * world.height
            local left, top = space.left * world.width, space.top * world.height
            for featureKey, byKind in pairs(space.sets) do
                local set, feature = byKind.shown, world.featureByKey[featureKey]
                for _, area in ipairs(set and set.isShown and feature and set.areas or NONE) do
                    local points = {}
                    for index, point in ipairs(area.points) do
                        points[index] = { x = left + point.x * across, y = top + point.y / ASPECT * down }
                    end
                    areas[#areas + 1] = {
                        points = points,
                        reach = area.reach * across,
                        questId = feature.questId,
                        isFocused = feature.isFocused == true,
                    }
                end
            end
        end
    end
    for tile in pairs(world.shownTiles) do
        local space = tile.space
        local across, down = (space.right - space.left) * world.width, (space.bottom - space.top) * world.height
        for index, point in ipairs(tile.points) do
            if not (tile.cleared and tile.cleared[index]) and (tile.classes[index] or 1) <= (tile.shownShare or 4) then
                spots[#spots + 1] = {
                    x = (space.left * world.width + point.x * across) * pixelScale,
                    y = (space.top * world.height + point.y * down) * pixelScale,
                    radius = (tile.radius or 8) * (world.markScale or 1),
                    questId = tile.features[index].questId,
                    note = point.note,
                    isFocused = tile.index.isOverlay == true,
                }
            end
        end
    end
    return areas, spots
end

---Takes everything of the kept drawing off a map (the other drawing chosen, or a map left clean): hidden and let
---go of the map, so none of it costs there; kept for coming back to.
function World.hide(map)
    local world = worlds[map]
    if world and world.areaRoot and not world.isHidden then
        world.isHidden = true
        world.areaRoot:Hide()
        world.areaRoot:ClearAllPoints()
    end
end

---Puts a map's kept drawing back (World.hide).
function World.show(map)
    local world = worlds[map]
    if world and world.isHidden then
        world.isHidden = false
        world.areaRoot:SetAllPoints(world.canvas)
        world.areaRoot:Show()
    end
end

---@return table counts For the simulator's audits and /omq cpu: what a map's kept drawing holds and shows now
function World.getCounts(map)
    local world = worlds[map]
    if not world then
        return {}
    end
    local counts = {
        spaces = #world.spaceList,
        spacesShown = 0,
        sets = 0,
        setsShown = 0,
        fillsShown = 0,
        edgesShown = 0,
        walksShown = 0,
        tiles = 0,
        tilesShown = 0,
        iconsShown = 0,
        kept = world.regionCount,
        keptIcons = world.iconCount,
        todo = #world.todo,
        level = world.iconLevel0,
        wide = 0,
    }
    for _, space in ipairs(world.spaceList) do
        counts.spacesShown = counts.spacesShown + (space.isShown and 1 or 0)
    end
    for set in pairs(world.keptSets) do
        counts.sets = counts.sets + 1
        if set.isShown then
            counts.setsShown = counts.setsShown + 1
            if set.fillFrame and set.fillFrame.isAttached then
                counts.fillsShown = counts.fillsShown + (set.fillCount or 0)
            end
            counts.edgesShown = counts.edgesShown + set.lineCount
            if set.rimFrame and set.rimFrame.isAttached then
                counts.edgesShown = counts.edgesShown + (set.rimCount or 0)
            end
            counts.wide = counts.wide + (set.space.isWide and 1 or 0)
        end
    end
    for trail in pairs(world.keptTrails) do
        if trail.isShown then
            counts.walksShown = counts.walksShown + trail.lineCount
        end
    end
    for _ in pairs(world.keptTiles) do
        counts.tiles = counts.tiles + 1
    end
    for tile in pairs(world.shownTiles) do
        counts.tilesShown = counts.tilesShown + 1
        for class = 1, tile.shownShare or 4 do
            counts.iconsShown = counts.iconsShown + tile.classCounts[class]
        end
    end
    return counts
end

-- The pieces the drawing is made of, for the tests
World.internals = {
    splitFeature = splitFeature,
    rankFeature = rankFeature,
    buildIndex = buildIndex,
    composeTrails = composeTrails,
    chooseDashLevel = chooseDashLevel,
}
