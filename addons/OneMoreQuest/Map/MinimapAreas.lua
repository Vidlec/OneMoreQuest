local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- "Icons and areas" on the minimap: each tracked quest's areas, exactly as on the world map (its fills and edges as
-- strong as there, in the look chosen there: MapMarks.getAreaLook), its patrols' dashes, and a "Rough" circle's
-- dashed ring. Chosen with the marks (MinimapCompose), drawn here at every move (MinimapPins.drawAreas): on a square
-- minimap that does not turn on a canvas laid out in the world's yards (one call a move), else piece by piece.
local MinimapPins = ns.MinimapPins
local Shared = MinimapPins.shared -- (what the minimap's files share: MinimapPins.lua)
local lastMove = Shared.lastMove
local glide = MinimapPins.glide

-- (light enough that your arrow and the party's dots, drawn under every addon's frame, show plainly through)
local AREA_EDGE_PIXELS, AREA_RIM_PIXELS = 1.5, 3
-- "Rough" (Spoilers): a circle's ring is drawn whatever the areas' outline is set to (it is all there is of its
-- quest), at these strengths
local Rough = { RIM_ALPHA = 0.3, FOCUSED_RIM_ALPHA = 0.6, EDGE_ALPHA = 0.6, FOCUSED_EDGE_ALPHA = 0.95 }

local areaFrame, areaMask
local isAreaMasked = true -- a round minimap: fills cut by a round mask; any other shape: by the frame's square
-- The areas when not traced (the settings' "Drawn as"): their discs, rings and shadows, and what places them
MinimapPins.ovals = { pieces = { usedCount = 0 } }
local triangles, lines = { usedCount = 0 }, { usedCount = 0 } -- lines: areas' edges and patrols' dashes
local fillCanvas, lineFrame -- the canvas of the fills and edges, and the frame of what is placed on the minimap itself
local drawnAreas, areDrawnAreasStale = {}, false -- what is under the pointer is worked out when asked for

---A texture of the areas' frame, for a piece of fill or an oval's picture. (It remembers: walked on, a piece keeps
---its colour, size and corners; only its place is given again.)
local function createPiece()
    return ns.Widgets.remember(glide(areaFrame:CreateTexture(nil, "ARTWORK", nil, 1)))
end

---@return table piece The pool's next piece (a fill's triangle or an oval's picture), shown
local function acquirePiece(pool)
    pool.usedCount = pool.usedCount + 1
    local piece = pool[pool.usedCount]
    if not piece then
        piece = createPiece()
        -- Fills are clipped to the round minimap by a mask; lines take no mask in the game, so their ends are cut
        -- at the rim before they are placed
        if isAreaMasked and piece.AddMaskTexture then
            piece:AddMaskTexture(areaMask)
        end
        pool[pool.usedCount] = piece
    end
    piece:Show()
    piece.isShownNow = true
    return piece
end

---Hides the pool's pieces from first on (only those not hidden already).
local function hidePiecesFrom(pool, first)
    for index = first, #pool do
        local piece = pool[index]
        if piece.isShownNow ~= false then
            piece:Hide()
            piece.isShownNow = false
        end
    end
end

---@return number x, number y A place in yards ({ x = west, y = north }) as pixels from the minimap's middle, up positive
local function toMinimap(vertex, position, viewRadius, radius, facing)
    local right = (position.west - vertex.x) / viewRadius
    local up = (vertex.y - position.north) / viewRadius
    if facing then
        local sine, cosine = math.sin(facing), math.cos(facing)
        right, up = right * cosine + up * sine, -right * sine + up * cosine
    end
    return right * radius, up * radius
end

---Round minimap: the areas' fills cut by a round mask; any other shape (a square minimap from a minimap addon): by
---the minimap's square, the frame clipping what it holds.
local function applyAreaClip()
    local quarters = MinimapPins.getShape()
    local isRound = quarters[1] and quarters[2] and quarters[3] and quarters[4]
    if isRound == isAreaMasked then
        return
    end
    isAreaMasked = isRound
    for _, pool in ipairs({ triangles, MinimapPins.ovals.pieces }) do
        for _, piece in ipairs(pool) do
            if isRound then
                piece:AddMaskTexture(areaMask)
            else
                piece:RemoveMaskTexture(areaMask)
            end
        end
    end
    if areaFrame.SetClipsChildren then
        areaFrame:SetClipsChildren(not isRound)
    end
end

---@return table? from, table? to The part of a line inside the square of this half width round the origin
function MinimapPins.clipToSquare(from, to, half)
    local enter, leave = 0, 1
    local dx, dy = to.x - from.x, to.y - from.y
    for _, edge in ipairs({
        { -dx, from.x + half },
        { dx, half - from.x },
        { -dy, from.y + half },
        { dy, half - from.y },
    }) do
        local p, q = edge[1], edge[2]
        if p == 0 then
            if q < 0 then
                return nil, nil
            end
        else
            local t = q / p
            if p < 0 then
                enter = math.max(enter, t)
            else
                leave = math.min(leave, t)
            end
        end
    end
    if enter >= leave then
        return nil, nil
    end
    return { x = from.x + dx * enter, y = from.y + dy * enter }, { x = from.x + dx * leave, y = from.y + dy * leave }
end

---@return table? from, table? to The part of a line inside a circle round the origin, or nil when none is
function MinimapPins.clipToCircle(from, to, circleRadius)
    local dx, dy = to.x - from.x, to.y - from.y
    local a = dx * dx + dy * dy
    local b = 2 * (from.x * dx + from.y * dy)
    local c = from.x * from.x + from.y * from.y - circleRadius * circleRadius
    if a == 0 then
        return c <= 0 and from or nil, c <= 0 and to or nil
    end
    local discriminant = b * b - 4 * a * c
    if discriminant <= 0 then
        return nil, nil
    end
    local root = math.sqrt(discriminant)
    local enter, leave = math.max(0, (-b - root) / (2 * a)), math.min(1, (-b + root) / (2 * a))
    if enter >= leave then
        return nil, nil
    end
    return { x = from.x + dx * enter, y = from.y + dy * enter }, { x = from.x + dx * leave, y = from.y + dy * leave }
end

---@return { from: table, to: table }[] pieces A line with the circles round the party and the player taken out
---@param clear { x: number, y: number, radius: number }[] Kept free, as MinimapPins.getClearPoints gives them
function MinimapPins.cutAround(from, to, clear)
    local pieces = { { from = from, to = to } }
    -- (a circle wholly to one side of the line cuts nothing: told before anything is made for it)
    local lineLeft, lineRight = math.min(from.x, to.x), math.max(from.x, to.x)
    local lineBottom, lineTop = math.min(from.y, to.y), math.max(from.y, to.y)
    for _, point in ipairs(clear) do
        local isApart = point.x + point.radius < lineLeft
            or point.x - point.radius > lineRight
            or point.y + point.radius < lineBottom
            or point.y - point.radius > lineTop
        if not isApart then
            local kept = {}
            for _, piece in ipairs(pieces) do
                local relativeFrom = { x = piece.from.x - point.x, y = piece.from.y - point.y }
                local relativeTo = { x = piece.to.x - point.x, y = piece.to.y - point.y }
                local enter, leave = MinimapPins.clipToCircle(relativeFrom, relativeTo, point.radius)
                if not enter then
                    kept[#kept + 1] = piece
                else
                    local inFrom = { x = enter.x + point.x, y = enter.y + point.y }
                    local inTo = { x = leave.x + point.x, y = leave.y + point.y }
                    if (inFrom.x - piece.from.x) ^ 2 + (inFrom.y - piece.from.y) ^ 2 > 0.25 then
                        kept[#kept + 1] = { from = piece.from, to = inFrom }
                    end
                    if (piece.to.x - inTo.x) ^ 2 + (piece.to.y - inTo.y) ^ 2 > 0.25 then
                        kept[#kept + 1] = { from = inTo, to = piece.to }
                    end
                end
            end
            pieces = kept
        end
    end
    return pieces
end

-- The fills and edges laid out on the canvas (fillCanvas: see the canvases, in MinimapPins.lua)
local fillSets = {} -- [an area's triangles] = { textures, red, green, blue, alpha }: laid out on the canvas
local freeFills = {} -- the canvas's textures free to use again
local edgeSets = {} -- [an area's edges] = its edge on the canvas: two lines a leg, a dark rim and the colour over it
local freeEdgeLines = {}
local drawnAreasKey -- what the areas were last drawn from, move by move: the same again draws nothing
local areasLaidFor, areasLaidAt -- the areas, and the zoom, the canvas's fills and edges were last laid out for
local areasLaidNorth, areasLaidWest -- where the player was then: the areas near there are on the canvas
local AREA_STEP_YARDS = 60 -- how far the player walks before the areas near them are looked for again

local function releaseFillSet(key)
    local set = fillSets[key]
    if set then
        for index = 1, #set.textures do
            local texture = set.textures[index]
            texture:Hide()
            freeFills[#freeFills + 1] = texture
        end
        fillSets[key] = nil
    end
end

local function releaseEdgeSet(key)
    local set = edgeSets[key]
    if set then
        for index = 1, #set.lines do
            local line = set.lines[index]
            line:Hide()
            freeEdgeLines[#freeEdgeLines + 1] = line
        end
        edgeSets[key] = nil
    end
end

---Everything laid out on the canvas leaves it (the canvas's corner moved: MinimapPins.ensureOrigin).
local function releaseCanvasAreas()
    for key in pairs(fillSets) do
        releaseFillSet(key)
    end
    for key in pairs(edgeSets) do
        releaseEdgeSet(key)
    end
    areasLaidFor = nil
end
MinimapPins.releaseCanvasAreas = releaseCanvasAreas

---A line of the pool placed on the minimap itself, shown; its look set only where it differs from what the line
---last had (the same lines draw the same edges move after move).
local function acquireLine(color, alpha, thickness, level)
    lines.usedCount = lines.usedCount + 1
    local line = lines[lines.usedCount]
    if not line then
        line = glide(lineFrame:CreateLine(nil, "ARTWORK"))
        lines[lines.usedCount] = line
    end
    if not line.isShownNow then
        line:Show()
        line.isShownNow = true
    end
    if line.level ~= level then
        line:SetDrawLayer("ARTWORK", level)
        line.level = level
    end
    if line.red ~= color[1] or line.green ~= color[2] or line.blue ~= color[3] or line.alpha ~= alpha then
        line:SetColorTexture(color[1], color[2], color[3], alpha)
        line.red, line.green, line.blue, line.alpha = color[1], color[2], color[3], alpha
    end
    if line.thickness ~= thickness then
        line:SetThickness(thickness)
        line.thickness = thickness
    end
    return line
end

local function hideUnusedLines()
    for index = lines.usedCount + 1, #lines do
        local line = lines[index]
        if line.isShownNow then
            line:Hide()
            line.isShownNow = false
        end
    end
end

---@return number rimAlpha, number edgeAlpha How strong an area's dark rim and its edge are drawn
function Rough.getEdgeAlphas(area, look)
    if area.isRough then
        return area.isFocused and Rough.FOCUSED_RIM_ALPHA or Rough.RIM_ALPHA,
            area.isFocused and Rough.FOCUSED_EDGE_ALPHA or Rough.EDGE_ALPHA
    end
    return area.isFocused and look.focusedRimAlpha or look.rimAlpha,
        area.isFocused and look.focusedEdgeAlpha or look.edgeAlpha
end

---@return boolean isNear An area with a spawn near enough to reach onto the minimap
local function isAreaNear(area, position, viewRadius, reachYards)
    local limit = viewRadius * 1.5 + reachYards + (area.hoverYards or 0) -- (a rough circle: its middle, and its radius)
    local points = area.points
    -- How far its spawns reach, kept with them: an area far from the player is told so by four comparisons, not by
    -- every spawn (asked of every area at every move)
    local bounds = points.bounds
    if not bounds then
        bounds = { north = -math.huge, south = math.huge, west = -math.huge, east = math.huge }
        for index = 1, #points do
            local point = points[index]
            bounds.north, bounds.south = math.max(bounds.north, point.y), math.min(bounds.south, point.y)
            bounds.west, bounds.east = math.max(bounds.west, point.x), math.min(bounds.east, point.x)
        end
        points.bounds = bounds
    end
    if
        position.north > bounds.north + limit
        or position.north < bounds.south - limit
        or position.west > bounds.west + limit
        or position.west < bounds.east - limit
    then
        return false
    end
    for index = 1, #points do
        local point = points[index]
        if ns.Geometry.getDistance(position.north, position.west, point.y, point.x) <= limit then
            return true
        end
    end
    return false
end

local NO_PIECES = {}

-- How the lines placed on the minimap itself are drawn, set once for each area (or patrol) before its lines: the
-- minimap's radius, the circles they are cut round, how they are cut at the rim (clip), the dark line under
-- (underColor, underAlpha, underWidth) and the line in colour over it (color, alpha, width). One table, filled again
-- each time.
local pen = {}

---An edge, or a dash of a walk, placed on the minimap itself as the pen says: cut at its rim (lines take no mask in
---the game) and round every circle kept clear, each piece a dark rim line under the line in its colour.
local function drawPieces(fromX, fromY, toX, toY)
    local radius = pen.radius
    local from, to = pen.clip({ x = fromX, y = fromY }, { x = toX, y = toY }, radius - 1)
    for _, piece in ipairs(from and MinimapPins.cutAround(from, to, pen.clear or NO_PIECES) or NO_PIECES) do
        local under = acquireLine(pen.underColor, pen.underAlpha, pen.underWidth, 2)
        under:SetStartPoint("TOPLEFT", areaFrame, piece.from.x + radius, piece.from.y - radius)
        under:SetEndPoint("TOPLEFT", areaFrame, piece.to.x + radius, piece.to.y - radius)
        local over = acquireLine(pen.color, pen.alpha, pen.width, 3)
        over:SetStartPoint("TOPLEFT", areaFrame, piece.from.x + radius, piece.from.y - radius)
        over:SetEndPoint("TOPLEFT", areaFrame, piece.to.x + radius, piece.to.y - radius)
    end
end

---A patrol as on the world map: dashes along it, a light line over a faint shadow, each cut at the minimap's rim
---and round the party's dots and the player's arrow. Placed at every move, on any minimap: its dashes are measured
---on screen.
local function drawPatrol(area, position, viewRadius, radius, facing, clear)
    local look = ns.MapMarks.getAreaLook()
    local color = area.color or ns.MapMarks.getQuestColor(area.number, area.questId)
    local points = {}
    for _, point in ipairs(area.points) do
        local x, y = toMinimap(point, position, viewRadius, radius, facing)
        points[#points + 1] = { x = x, y = y }
    end
    local dashAlpha = area.isFocused and look.focusedTrailAlpha or look.trailAlpha
    local light =
        { color[1] + (1 - color[1]) * 0.55, color[2] + (1 - color[2]) * 0.55, color[3] + (1 - color[3]) * 0.55 }
    pen.radius, pen.clear = radius, clear
    pen.clip = isAreaMasked and MinimapPins.clipToCircle or MinimapPins.clipToSquare
    pen.underColor, pen.underAlpha = look.rimColor, dashAlpha * ns.MapMarks.DASH_SHADOW_ALPHA
    pen.underWidth = ns.MapMarks.DASH_SHADOW_WIDTH
    pen.color, pen.alpha, pen.width = light, dashAlpha, ns.MapMarks.DASH_WIDTH
    for _, dash in ipairs(ns.MapMarks.composeDashes(points, ns.MapMarks.DASH_PIXELS, ns.MapMarks.DASH_GAP_PIXELS)) do
        drawPieces(dash.from.x, dash.from.y, dash.to.x, dash.to.y)
    end
end

---@return string key Everything the areas are drawn from, move by move: where the player is and faces, the zoom,
---the minimap's size, what is kept clear, and the areas themselves
local function getAreasKey(position, viewRadius, radius, facing, clear)
    if not position then
        return "-"
    end
    local key = string.format(
        "%s:%s:%.2f:%.2f:%s:%.2f:%.2f:%s:%s",
        ns.MapMarksWorld.getGeometry(),
        tostring(Shared.shownAreas),
        position.north,
        position.west,
        tostring(position.continentId),
        viewRadius,
        radius,
        tostring(facing),
        tostring(isAreaMasked)
    )
    for _, point in ipairs(clear or {}) do
        key = key .. string.format(":%.1f,%.1f,%.1f", point.x, point.y, point.radius)
    end
    return key
end

do
    local Ovals = MinimapPins.ovals
    Ovals.corners, Ovals.vertex = { {}, {}, {}, {} }, {}

    ---A picture of an oval, placed on the corners worked out for it (Ovals.corners).
    function Ovals.place(picture, level, color, alpha)
        local corners = Ovals.corners
        local piece = acquirePiece(Ovals.pieces)
        if piece.picture ~= picture then
            piece.picture = picture
            piece:SetTexture(picture)
        end
        if piece.level ~= level then
            piece.level = level
            piece:SetDrawLayer("ARTWORK", level)
        end
        piece:SetVertexColor(color[1], color[2], color[3], alpha)
        ns.MapMarks.setQuad(piece, corners[1], corners[2], corners[3], corners[4], areaFrame)
    end

    ---An area as the map draws it when not traced (the settings' "Drawn as"): soft shadows, or an oval round its
    ---spawns (a disc and a ring); fitted once to the area's spawns (in the world's yards) and placed at every move,
    ---two pictures each where the traced area was a dozen pieces of fill and two lines a leg of its edge. What an
    ---oval is (its corners, its pictures, how strong) is the map's to say (MapMarks/World).
    function Ovals.draw(area, geometry, position, viewRadius, radius, facing, look, color)
        local World = ns.MapMarksWorld
        if area.ovalsFor ~= geometry then
            area.ovalsFor = geometry
            area.ovals = World.fitGroupOvals(area.points, ns.MapMarks.AREA_REACH_YARDS, geometry == "soft")
        end
        local corners, vertex = Ovals.corners, Ovals.vertex
        local pixelsPerYard = radius / viewRadius
        local fillAlpha = area.isFocused and look.focusedFillAlpha or look.fillAlpha
        local edgeAlpha = area.isFocused and look.focusedEdgeAlpha or look.edgeAlpha
        local edgePixels = area.isFocused and look.focusedEdgePixels or look.edgePixels
        for _, oval in ipairs(area.ovals) do
            local left, right, bottom, top = math.huge, -math.huge, math.huge, -math.huge
            for corner = 1, 4 do
                vertex.x, vertex.y = World.getOvalCorner(oval, corner)
                local x, y = toMinimap(vertex, position, viewRadius, radius, facing)
                left, right, bottom, top = math.min(left, x), math.max(right, x), math.min(bottom, y), math.max(top, y)
                -- (from the minimap's upper left corner, y down)
                corners[corner].x, corners[corner].y = x + radius, radius - y
            end
            -- Only ovals on the minimap; the mask (or the square frame) cuts those across its edge
            if right > -radius and left < radius and top > -radius and bottom < radius then
                local picture, fillShare, edgeShare = World.getOvalLook(oval)
                if look.hasFill then
                    Ovals.place(picture, 1, color, fillAlpha * fillShare)
                end
                if look.hasEdges and oval.isSoft then
                    Ovals.place(picture, 2, color, edgeAlpha * edgeShare)
                elseif look.hasEdges then
                    local across = (oval.along + oval.across) * pixelsPerYard
                    Ovals.place(World.getOvalRing(across, edgePixels), 3, color, edgeAlpha)
                end
            end
        end
    end
end

-- What a drawing piece by piece is made for (drawAreasMoveByMove): where the player is and faces, the zoom (yards
-- from the middle to the edge: viewRadius), the minimap's radius in pixels, the circles kept clear, the areas' look
-- and geometry. One table, filled again at each drawing.
local moveView = {}
local fillCorners = { {}, {}, {} } -- a fill's triangle, from the minimap's upper left corner, y down (reused)

---A traced area's fill, piece by piece: only the pieces on the minimap; the mask (or the square frame) cuts those
---across its edge.
local function drawFillPieces(view, area, color)
    local position, viewRadius, radius, facing = view.position, view.viewRadius, view.radius, view.facing
    local alpha = area.isFocused and view.look.focusedFillAlpha or view.look.fillAlpha
    local first, second, third = fillCorners[1], fillCorners[2], fillCorners[3]
    for _, triangle in ipairs(area.triangles) do
        local ax, ay = toMinimap(triangle[1], position, viewRadius, radius, facing)
        local bx, by = toMinimap(triangle[2], position, viewRadius, radius, facing)
        local cx, cy = toMinimap(triangle[3], position, viewRadius, radius, facing)
        if
            math.max(ax, bx, cx) > -radius
            and math.min(ax, bx, cx) < radius
            and math.max(ay, by, cy) > -radius
            and math.min(ay, by, cy) < radius
        then
            local texture = acquirePiece(triangles)
            texture:SetColorTexture(color[1], color[2], color[3], alpha)
            first.x, first.y = ax + radius, radius - ay
            second.x, second.y = bx + radius, radius - by
            third.x, third.y = cx + radius, radius - cy
            ns.MapMarks.setTriangle(texture, first, second, third, areaFrame)
        end
    end
end

---An area's edge, piece by piece: each leg cut at the rim and round the circles kept clear.
local function drawEdgePieces(view, area, color)
    local position, viewRadius, radius, facing = view.position, view.viewRadius, view.radius, view.facing
    local look = view.look
    local rimAlpha, edgeAlpha = Rough.getEdgeAlphas(area, look)
    -- (the focused quest's edge thicker where the map's is: in the shapes look)
    local thicker = area.isFocused and look.focusedEdgePixels - look.edgePixels or 0
    pen.radius, pen.clear = radius, view.clear
    pen.clip = isAreaMasked and MinimapPins.clipToCircle or MinimapPins.clipToSquare
    pen.underColor, pen.underAlpha, pen.underWidth = look.rimColor, rimAlpha, AREA_RIM_PIXELS + thicker
    pen.color, pen.alpha, pen.width = color, edgeAlpha, AREA_EDGE_PIXELS + thicker
    for _, edge in ipairs(area.edges) do
        local fromX, fromY = toMinimap(edge[1], position, viewRadius, radius, facing)
        local toX, toY = toMinimap(edge[2], position, viewRadius, radius, facing)
        drawPieces(fromX, fromY, toX, toY)
    end
end

---One area near the player, piece by piece: shadows or an oval in place of the traced area's fill and edge, a walk
---and a rough circle as they are (a fill or an outline switched off: none of its pieces placed).
local function drawAreaPieces(view, area)
    local look = view.look
    local color = area.color or ns.MapMarks.getQuestColor(area.number, area.questId)
    local isOval = view.geometry ~= "traced" and not area.isPatrol and not area.isRough and area.points ~= nil
    if isOval then
        MinimapPins.ovals.draw(
            area,
            view.geometry,
            view.position,
            view.viewRadius,
            view.radius,
            view.facing,
            look,
            color
        )
    elseif look.hasFill then
        drawFillPieces(view, area, color)
    end
    if area.isPatrol then
        drawPatrol(area, view.position, view.viewRadius, view.radius, view.facing, view.clear)
    elseif not isOval and (look.hasEdges or area.isRough) then
        drawEdgePieces(view, area, color)
    end
end

---The areas placed piece by piece at every move: a round minimap (its fills cut by a mask, its edges at its rim
---here) and a turning one.
local function drawAreasMoveByMove(position, viewRadius, radius, facing, clear)
    -- Called at every move and once a second besides: with nothing it draws from changed, all stays as it is
    local key = getAreasKey(position, viewRadius, radius, facing, clear)
    if key == drawnAreasKey then
        return
    end
    drawnAreasKey = key
    triangles.usedCount, lines.usedCount, MinimapPins.ovals.pieces.usedCount = 0, 0, 0
    local view = moveView
    view.position, view.viewRadius, view.radius, view.facing, view.clear = position, viewRadius, radius, facing, clear
    view.geometry, view.look = ns.MapMarksWorld.getGeometry(), ns.MapMarks.getAreaLook()
    local reachYards = ns.MapMarks.AREA_REACH_YARDS
    for _, area in ipairs(position and areaFrame and Shared.shownAreas or NO_PIECES) do
        -- Only areas with a spawn near enough to reach onto the minimap
        if isAreaNear(area, position, viewRadius, reachYards) then
            drawAreaPieces(view, area)
        end
    end
    hidePiecesFrom(triangles, triangles.usedCount + 1)
    hidePiecesFrom(MinimapPins.ovals.pieces, MinimapPins.ovals.pieces.usedCount + 1)
    hideUnusedLines()
end

local canvasCorners = { {}, {}, {} } -- a fill's triangle on the canvas, in yards from its corner (reused)

---@return table set An area's fill on the canvas, laid out once: a texture a triangle, in yards from the canvas's
---corner (right is less west, down is less north)
local function layOutFill(triangleList, origin)
    local set = { textures = {} }
    local first, second, third = canvasCorners[1], canvasCorners[2], canvasCorners[3]
    for _, triangle in ipairs(triangleList) do
        local texture = freeFills[#freeFills]
        if texture then
            freeFills[#freeFills] = nil
        else
            texture = glide(fillCanvas:CreateTexture(nil, "ARTWORK", nil, 1))
        end
        first.x, first.y = origin.west - triangle[1].x, origin.north - triangle[1].y
        second.x, second.y = origin.west - triangle[2].x, origin.north - triangle[2].y
        third.x, third.y = origin.west - triangle[3].x, origin.north - triangle[3].y
        ns.MapMarks.setTriangle(texture, first, second, third, fillCanvas)
        texture:Show()
        set.textures[#set.textures + 1] = texture
    end
    return set
end

---An area's fill on the canvas, laid out where it is not yet and coloured where its colour changed.
local function placeFill(area, color, alpha, origin)
    local set = fillSets[area.triangles]
    if not set then
        set = layOutFill(area.triangles, origin)
        fillSets[area.triangles] = set
    end
    if set.red ~= color[1] or set.green ~= color[2] or set.blue ~= color[3] or set.alpha ~= alpha then
        for index = 1, #set.textures do
            set.textures[index]:SetColorTexture(color[1], color[2], color[3], alpha)
        end
        set.red, set.green, set.blue, set.alpha = color[1], color[2], color[3], alpha
    end
end

---@return table set An area's edge on the canvas, laid out once: two lines a leg; and how far the edge reaches (x
---west, y north), for finding the legs that cross a circle kept clear (drawCutEdges)
local function layOutEdge(edges, origin)
    local set = {
        lines = {},
        isCut = {},
        cutCount = 0,
        edges = edges,
        north = -math.huge,
        south = math.huge,
        west = -math.huge,
        east = math.huge,
    }
    for index, edge in ipairs(edges) do
        local fromX, fromY = origin.west - edge[1].x, origin.north - edge[1].y
        local toX, toY = origin.west - edge[2].x, origin.north - edge[2].y
        for layer = 1, 2 do
            -- (plain lines: each is given its ends once, and its look only when the look
            -- changes, by what is kept of the whole edge below; nothing more to remember)
            local line = freeEdgeLines[#freeEdgeLines]
            if line then
                freeEdgeLines[#freeEdgeLines] = nil
            else
                line = glide(fillCanvas:CreateLine(nil, "ARTWORK"))
            end
            line:SetStartPoint("TOPLEFT", fillCanvas, fromX, -fromY)
            line:SetEndPoint("TOPLEFT", fillCanvas, toX, -toY)
            line:Show()
            set.lines[index * 2 - 2 + layer] = line
        end
        set.north = math.max(set.north, edge[1].y, edge[2].y)
        set.south = math.min(set.south, edge[1].y, edge[2].y)
        set.west = math.max(set.west, edge[1].x, edge[2].x)
        set.east = math.min(set.east, edge[1].x, edge[2].x)
    end
    return set
end

---An area's edge on the canvas, laid out where it is not yet and restyled where its look or the zoom changed.
local function placeEdge(area, color, look, pixelsPerYard, origin)
    local set = edgeSets[area.edges]
    if not set then
        set = layOutEdge(area.edges, origin)
        edgeSets[area.edges] = set
    end
    local rimAlpha, edgeAlpha = Rough.getEdgeAlphas(area, look)
    -- (the focused quest's edge thicker where the map's is: in the shapes look)
    local thicker = area.isFocused and look.focusedEdgePixels - look.edgePixels or 0
    if
        set.color == color
        and set.rimAlpha == rimAlpha
        and set.edgeAlpha == edgeAlpha
        and set.thicker == thicker
        and set.pixelsPerYard == pixelsPerYard
    then
        return
    end
    set.color, set.rimAlpha, set.edgeAlpha, set.thicker, set.pixelsPerYard =
        color, rimAlpha, edgeAlpha, thicker, pixelsPerYard
    -- (a line's width is in the canvas's yards: as many as make its pixels at this zoom)
    for index = 1, #set.lines, 2 do
        local rim, line = set.lines[index], set.lines[index + 1]
        rim:SetDrawLayer("ARTWORK", 2)
        rim:SetColorTexture(look.rimColor[1], look.rimColor[2], look.rimColor[3], rimAlpha)
        rim:SetThickness((AREA_RIM_PIXELS + thicker) / pixelsPerYard)
        line:SetDrawLayer("ARTWORK", 3)
        line:SetColorTexture(color[1], color[2], color[3], edgeAlpha)
        line:SetThickness((AREA_EDGE_PIXELS + thicker) / pixelsPerYard)
    end
end

---The fills and edges of the areas near the player, on the canvas: laid out where they are not yet (once, in yards
---from the canvas's corner: right is less west, down is less north), restyled where their quest came into focus
---or left it or the zoom changed, taken off where no longer near or drawn.
local function layOutAreas(position, viewRadius, radius)
    local pixelsPerYard = radius / viewRadius
    local look = ns.MapMarks.getAreaLook()
    local origin = Shared.worldOrigin
    -- (laid out again once the player has walked AREA_STEP_YARDS on: every area that could show before then)
    local reachYards = ns.MapMarks.AREA_REACH_YARDS + AREA_STEP_YARDS * 1.5
    local isWanted = {} -- [an area's triangles or edges] = true for what is on the canvas this time
    for _, area in ipairs(Shared.shownAreas) do
        if not area.isPatrol and isAreaNear(area, position, viewRadius, reachYards) then
            local color = area.color or ns.MapMarks.getQuestColor(area.number, area.questId)
            -- (a fill or an outline switched off: nothing of it on the canvas, so what was there is taken off below)
            if look.hasFill and #area.triangles > 0 then
                placeFill(area, color, area.isFocused and look.focusedFillAlpha or look.fillAlpha, origin)
                isWanted[area.triangles] = true
            end
            if (look.hasEdges or area.isRough) and #area.edges > 0 then
                placeEdge(area, color, look, pixelsPerYard, origin)
                isWanted[area.edges] = true
            end
        end
    end
    -- Fills and edges of areas no longer near, or no longer drawn, leave the canvas
    for key in pairs(fillSets) do
        if not isWanted[key] then
            releaseFillSet(key)
        end
    end
    for key in pairs(edgeSets) do
        if not isWanted[key] then
            releaseEdgeSet(key)
        end
    end
end

---@return boolean isNear A line from a to b passes inside a circle (all in the same units)
local function isSegmentInCircle(ax, ay, bx, by, centerX, centerY, reach)
    local dx, dy = bx - ax, by - ay
    local lengthSquared = dx * dx + dy * dy
    local along = lengthSquared > 0 and ((centerX - ax) * dx + (centerY - ay) * dy) / lengthSquared or 0
    if along < 0 then
        along = 0
    elseif along > 1 then
        along = 1
    end
    local nearX, nearY = ax + dx * along - centerX, ay + dy * along - centerY
    return nearX * nearX + nearY * nearY < reach * reach
end

local circleWest, circleNorth, circleReach = {}, {}, {} -- the circles kept clear, in the world's yards (reused)
local nearCircles = {} -- which of them reach into the edge looked at (reused)

---The canvas's edges are cut by nothing but the minimap's frame. A leg that crosses a circle kept clear (round the
---player's arrow, the party's dots, another addon's pin) is drawn instead in pieces placed on the minimap itself,
---cut round the circle, and its canvas's lines hidden; clear of them all again, they are shown. Reckoned in Lua at
---every move: the game is asked only for the few legs that cross.
local function drawCutEdges(position, viewRadius, radius, clear)
    local pixelsPerYard = radius / viewRadius
    local look = ns.MapMarks.getAreaLook()
    local count = #clear
    for index = 1, count do
        local point = clear[index]
        circleWest[index] = position.west - point.x / pixelsPerYard
        circleNorth[index] = position.north + point.y / pixelsPerYard
        circleReach[index] = point.radius / pixelsPerYard
    end
    for _, set in pairs(edgeSets) do
        -- The circles that reach into the edge's bounds: its legs are tried against these alone (a minimap full of
        -- another addon's pins has dozens of circles, an edge is near one or two)
        local nearCount = 0
        for index = 1, count do
            local reach = circleReach[index]
            if
                circleWest[index] + reach >= set.east
                and circleWest[index] - reach <= set.west
                and circleNorth[index] + reach >= set.south
                and circleNorth[index] - reach <= set.north
            then
                nearCount = nearCount + 1
                nearCircles[nearCount] = index
            end
        end
        if nearCount > 0 or set.cutCount > 0 then
            local edges, isCut, setLines = set.edges, set.isCut, set.lines
            for edgeIndex = 1, #edges do
                local edge = edges[edgeIndex]
                local from, to = edge[1], edge[2]
                local isCrossing = false
                for near = 1, nearCount do
                    local index = nearCircles[near]
                    if
                        isSegmentInCircle(
                            from.x,
                            from.y,
                            to.x,
                            to.y,
                            circleWest[index],
                            circleNorth[index],
                            circleReach[index]
                        )
                    then
                        isCrossing = true
                        break
                    end
                end
                if isCrossing ~= (isCut[edgeIndex] == true) then
                    isCut[edgeIndex] = isCrossing or nil
                    set.cutCount = set.cutCount + (isCrossing and 1 or -1)
                    setLines[edgeIndex * 2 - 1]:SetShown(not isCrossing)
                    setLines[edgeIndex * 2]:SetShown(not isCrossing)
                end
                if isCrossing then
                    local fromX, fromY = toMinimap(from, position, viewRadius, radius, nil)
                    local toX, toY = toMinimap(to, position, viewRadius, radius, nil)
                    pen.radius, pen.clear, pen.clip = radius, clear, MinimapPins.clipToSquare
                    pen.underColor, pen.underAlpha, pen.underWidth =
                        look.rimColor, set.rimAlpha, AREA_RIM_PIXELS + set.thicker
                    pen.color, pen.alpha, pen.width = set.color, set.edgeAlpha, AREA_EDGE_PIXELS + set.thicker
                    drawPieces(fromX, fromY, toX, toY)
                end
            end
        end
    end
end

---@return boolean isOnCanvas The areas are drawn on their canvas: a square minimap (its frame cuts them) that does
---not turn, with the areas traced (shadows and ovals: a few pictures, placed at each move) and the canvas not
---switched off (off: every piece placed at every move, to compare the two ways)
local function isAreaCanvasUsed(position, facing)
    return position ~= nil
        and areaFrame ~= nil
        and fillCanvas ~= nil
        and not isAreaMasked
        and not facing
        and ns.MapMarksWorld.getGeometry() == "traced"
        and MinimapPins.isCanvasOff ~= true
end

---@return boolean isStale The canvas's areas are laid out again: when they are chosen, when the zoom changes, and
---once the player has walked on far enough for others to be near (those already there stay as they are)
local function areCanvasAreasStale(position, pixelsPerYard)
    return areasLaidFor ~= Shared.shownAreas
        or areasLaidAt ~= pixelsPerYard
        or not areasLaidNorth
        or math.abs(position.north - areasLaidNorth) > AREA_STEP_YARDS
        or math.abs(position.west - areasLaidWest) > AREA_STEP_YARDS
end

---Each tracked quest's areas, as on the world map: a light fill in the quest's colour, edged in it over a soft dark
---line, the quest in focus a little stronger; clipped to the minimap's edge. Follows the player each move.
---@param clear table[]? Circles round other addons' pins: no edge runs across them, only the light fill (the player's
---arrow and the party's dots are drawn again over everything of ours: edges run on under them)
function MinimapPins.drawAreas(position, viewRadius, radius, facing, clear)
    if areaFrame then
        applyAreaClip()
    end
    areDrawnAreasStale = true
    local isOnCanvas = isAreaCanvasUsed(position, facing)
    lastMove.isAreaCanvas = isOnCanvas
    if not isOnCanvas then
        if next(fillSets) or next(edgeSets) then
            releaseCanvasAreas()
        end
        MinimapPins.hideCanvas(fillCanvas)
        drawAreasMoveByMove(position, viewRadius, radius, facing, clear)
        return
    end
    if drawnAreasKey ~= nil then
        -- The pieces placed move by move, when last drawn that way, leave (the ovals too: else they stay put)
        drawnAreasKey = nil
        hidePiecesFrom(triangles, 1)
        hidePiecesFrom(MinimapPins.ovals.pieces, 1)
        triangles.usedCount, MinimapPins.ovals.pieces.usedCount = 0, 0
    end
    MinimapPins.ensureOrigin(position)
    local pixelsPerYard = radius / viewRadius
    MinimapPins.placeCanvas(fillCanvas, position.north, position.west, pixelsPerYard)
    if areCanvasAreasStale(position, pixelsPerYard) then
        areasLaidFor, areasLaidAt = Shared.shownAreas, pixelsPerYard
        areasLaidNorth, areasLaidWest = position.north, position.west
        layOutAreas(position, viewRadius, radius)
    end
    -- What is still placed on the minimap itself at a move: the legs that cross a circle kept clear, and the walks
    lines.usedCount = 0
    drawCutEdges(position, viewRadius, radius, clear or NO_PIECES)
    local reachYards = ns.MapMarks.AREA_REACH_YARDS
    for _, area in ipairs(Shared.shownAreas) do
        if area.isPatrol and isAreaNear(area, position, viewRadius, reachYards) then
            drawPatrol(area, position, viewRadius, radius, nil, clear)
        end
    end
    hideUnusedLines()
end

---@return table drawn An area as the minimap shows it now, in pixels from its middle (up positive), for hovering: its
---spawns, how far it reaches round them, and its quest; a walk with its legs
local function composeDrawnArea(area, position, reachYards)
    local viewRadius, radius, facing = lastMove.viewRadius, lastMove.radius, lastMove.facing
    local spawns = {}
    for index, point in ipairs(area.points) do
        local x, y = toMinimap(point, position, viewRadius, radius, facing)
        spawns[index] = { x = x, y = y }
    end
    -- (a rough circle answers the pointer anywhere inside it)
    local drawn = {
        points = spawns,
        reach = (area.hoverYards or reachYards) / viewRadius * radius,
        questId = area.questId,
        isFocused = area.isFocused,
        note = area.note,
    }
    if area.isPatrol then
        -- A patrol is a line, not an area: only the line itself answers the pointer
        drawn.isPatrol, drawn.segments, drawn.note = true, {}, area.note
        for _, edge in ipairs(area.edges) do
            local ax, ay = toMinimap(edge[1], position, viewRadius, radius, facing)
            local bx, by = toMinimap(edge[2], position, viewRadius, radius, facing)
            drawn.segments[#drawn.segments + 1] = { ax, ay, bx, by }
        end
    end
    return drawn
end

---@return table[] areas The areas near the player as the minimap shows them now, in pixels from its middle (up
---positive), for hovering. Worked out when asked for (the pointer on the minimap), not at every move.
function MinimapPins.getDrawnAreas()
    if not areDrawnAreasStale then
        return drawnAreas
    end
    areDrawnAreasStale = false
    drawnAreas = {}
    local position = lastMove.north and lastMove or nil
    if not position or not areaFrame then
        return drawnAreas
    end
    local reachYards = ns.MapMarks.AREA_REACH_YARDS
    for _, area in ipairs(Shared.shownAreas) do
        if isAreaNear(area, position, lastMove.viewRadius, reachYards) then
            drawnAreas[#drawnAreas + 1] = composeDrawnArea(area, position, reachYards)
        end
    end
    return drawnAreas
end

---Makes the areas' frames on the minimap: the quests' areas, over the land and under everything else of ours, cut
---to the minimap's round edge; in it the canvas of the areas' fills and edges (drawAreas), and over that the frame
---of what is placed on the minimap itself (the walks' dashes, an edge cut round the player): both the area frame's
---own, so its see-through look and, on a square minimap, its cut are theirs.
function MinimapPins.createAreaFrames()
    areaFrame = CreateFrame("Frame", nil, Minimap)
    areaFrame.isOurs = true -- (not another addon's pin to keep clear of)
    areaFrame:SetAllPoints(Minimap)
    areaFrame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 1)
    areaMask = areaFrame:CreateMaskTexture()
    areaMask:SetTexture(
        "Interface\\CharacterFrame\\TempPortraitAlphaMask",
        "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE"
    )
    areaMask:SetAllPoints(Minimap)
    fillCanvas = CreateFrame("Frame", nil, areaFrame)
    fillCanvas:SetSize(1, 1)
    fillCanvas:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 2)
    fillCanvas:Hide()
    Shared.fillCanvas = fillCanvas -- (slid every frame with the spawn icons' canvas: MinimapPins.slide)
    lineFrame = CreateFrame("Frame", nil, areaFrame)
    lineFrame:SetAllPoints(areaFrame)
    lineFrame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 3)
end
