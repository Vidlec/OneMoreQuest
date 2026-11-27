local addonName, ns = ...

-- The map's marks: the geometry of quest areas (their outline from the spawns, simplified and cut into triangles).
local MapMarks = ns.MapMarks
local Style, State = ns.MapMarksStyle, ns.MapMarksState
local Compose, Look, Layout, Shapes, Areas, Draw =
    ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw

local AREA_SOFTNESS = 0.85 -- how widely each spawn's glow spreads, against the reach: wider melts spawns together rounder
local GLOW_RADIUS = 4 -- a spawn's glow is added onto the grid this many spreads round it (past it, under a thousandth)
-- Spawn buckets told by one number: their column and row, shifted to be positive
local BUCKET_OFFSET, BUCKET_SPAN = 32768, 65536
local NONE = {}

---@return number value How strongly a place lies in an area: each spawn's soft glow (a bell curve), added up, less
---what one spawn gives at the edge of its reach. Positive inside: a lone spawn's area is the circle of its reach;
---near spawns melt into one round shape.
local function getAreaValue(buckets, bucketSize, reach, x, y)
    local spread = AREA_SOFTNESS * reach
    local twoSpreadSquared = 2 * spread * spread
    local total = 0
    local bucketX, bucketY = math.floor(x / bucketSize), math.floor(y / bucketSize)
    for stepX = -1, 1 do
        for stepY = -1, 1 do
            local bucket = buckets[(bucketX + stepX + BUCKET_OFFSET) * BUCKET_SPAN + bucketY + stepY + BUCKET_OFFSET]
            if bucket then
                for index = 1, #bucket do
                    local point = bucket[index]
                    local dx, dy = point.x - x, point.y - y
                    total = total + math.exp(-(dx * dx + dy * dy) / twoSpreadSquared)
                end
            end
        end
    end
    return total - math.exp(-reach * reach / twoSpreadSquared)
end

---@return table buckets, number size The spawns sorted into squares as wide as a glow reaches, for quick lookups (a
---number for each square: no key text made for every lookup)
local function bucketSpawns(points, reach)
    local size = 3 * AREA_SOFTNESS * reach -- past three spreads a glow adds nothing that shows
    local buckets = {}
    for _, point in ipairs(points) do
        local key = (math.floor(point.x / size) + BUCKET_OFFSET) * BUCKET_SPAN
            + math.floor(point.y / size)
            + BUCKET_OFFSET
        local bucket = buckets[key]
        if not bucket then
            bucket = {}
            buckets[key] = bucket
        end
        bucket[#bucket + 1] = point
    end
    return buckets, size
end

---An area that follows its spawns, smooth and round: each spawn glows softly, the glows of nearby spawns add up
---into one rounded shape, the land between groups left open; a lone spawn's area is the circle of its reach.
---Traced on a grid (marching squares), crossings placed where the glow fades out between grid points, so its
---edge curves smoothly.
---
---Made to cost what the shape's size does, not its spawns, and to leave little behind: each spawn's glow is added
---onto the grid points near it (a bell curve is a row's curve times a column's: a few dozen exp() a spawn), the grid
---is one list of numbers, each crossing is made once and shared by the two pieces of edge that meet there, and the
---grid's own fill (rectangles and corner pieces) is made only when the outline cannot be cut into triangles. Before,
---every grid point looked its spawns up by key text, and every cell made tables of its corners: some 240 MB of
---garbage for twenty quests' areas.
---@param points { x: number, y: number }[] The spawns, in any units with y down
---@param reach number How far the area reaches past each spawn, in the same units
---@param cell number? The grid's spacing; a third of the reach when left out
---@return { triangles: table[], edges: table[] } shape Triangles that fill it ({ a, b, c }: whole stretches of grid
---inside as two each), and its edge as short lines ({ from, to }); all in the points' units
---@param shouldYield boolean? Run in slices: pause now and then (inside a coroutine), so a big shape spreads over frames
function MapMarks.composeAreaShape(points, reach, cell, shouldYield)
    cell = cell or reach / 3
    if #points == 0 or reach <= 0 then
        return { triangles = {}, edges = {} }
    end
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, point in ipairs(points) do
        minX, maxX = math.min(minX, point.x), math.max(maxX, point.x)
        minY, maxY = math.min(minY, point.y), math.max(maxY, point.y)
    end
    local spread = AREA_SOFTNESS * reach
    local twoSpreadSquared = 2 * spread * spread
    -- Room round the spawns for where glows add up past one spawn's reach
    local margin = 3 * AREA_SOFTNESS * reach + cell
    minX, minY = minX - margin, minY - margin
    local columns = math.ceil((maxX + margin - minX) / cell)
    local rows = math.ceil((maxY + margin - minY) / cell)
    local width = columns + 1 -- grid points across

    -- The glow on the grid: each spawn's added onto the points within GLOW_RADIUS spreads of it (past it a spawn adds
    -- under a thousandth of the edge's value), its curve along the row and the column worked out once each
    local values = {}
    local threshold = math.exp(-reach * reach / twoSpreadSquared)
    for index = 1, (rows + 1) * width do
        values[index] = -threshold
    end
    local radius = GLOW_RADIUS * spread
    local alongColumns = {}
    for pointIndex, point in ipairs(points) do
        if shouldYield and pointIndex % 200 == 0 then
            coroutine.yield()
        end
        local firstColumn = math.max(0, math.ceil((point.x - radius - minX) / cell))
        local lastColumn = math.min(columns, math.floor((point.x + radius - minX) / cell))
        local firstRow = math.max(0, math.ceil((point.y - radius - minY) / cell))
        local lastRow = math.min(rows, math.floor((point.y + radius - minY) / cell))
        for column = firstColumn, lastColumn do
            local dx = minX + column * cell - point.x
            alongColumns[column] = math.exp(-dx * dx / twoSpreadSquared)
        end
        for row = firstRow, lastRow do
            local dy = minY + row * cell - point.y
            local alongRow = math.exp(-dy * dy / twoSpreadSquared)
            local base = row * width + 1
            for column = firstColumn, lastColumn do
                local at = base + column
                values[at] = values[at] + alongRow * alongColumns[column]
            end
        end
    end
    local function valueAt(row, column)
        return values[row * width + column + 1]
    end

    -- Where the edge crosses a side of a cell: made once for each side of the grid, shared by both cells along it
    local crossings = {}
    local function crossingOn(sideId, x1, y1, v1, x2, y2, v2)
        local point = crossings[sideId]
        if not point then
            local t = v1 / (v1 - v2)
            point = { x = x1 + (x2 - x1) * t, y = y1 + (y2 - y1) * t }
            crossings[sideId] = point
        end
        return point
    end
    -- The four sides of a cell: 1 top (its upper corners), 2 right, 3 bottom, 4 left
    local function sideCrossing(row, column, side)
        local x0, y0 = minX + column * cell, minY + row * cell
        if side == 1 then
            return crossingOn(
                (row * width + column) * 2,
                x0,
                y0,
                valueAt(row, column),
                x0 + cell,
                y0,
                valueAt(row, column + 1)
            )
        elseif side == 2 then
            return crossingOn(
                (row * width + column + 1) * 2 + 1,
                x0 + cell,
                y0,
                valueAt(row, column + 1),
                x0 + cell,
                y0 + cell,
                valueAt(row + 1, column + 1)
            )
        elseif side == 3 then
            return crossingOn(
                ((row + 1) * width + column) * 2,
                x0,
                y0 + cell,
                valueAt(row + 1, column),
                x0 + cell,
                y0 + cell,
                valueAt(row + 1, column + 1)
            )
        end
        return crossingOn(
            (row * width + column) * 2 + 1,
            x0,
            y0,
            valueAt(row, column),
            x0,
            y0 + cell,
            valueAt(row + 1, column)
        )
    end
    local buckets, bucketSize -- (for a saddle's middle: made when the first one needs it)
    local function isMiddleInside(row, column)
        if not buckets then
            buckets, bucketSize = bucketSpawns(points, reach)
        end
        return getAreaValue(buckets, bucketSize, reach, minX + (column + 0.5) * cell, minY + (row + 0.5) * cell) > 0
    end

    -- The cells the edge runs through, and, only when asked for (the outline would not cut), the grid's own fill
    local function march(isFillWanted)
        local edges, triangles = {}, {}
        local openRuns = {} -- ["from:to"] = { first row }: stretches wholly inside, grown down into rectangles
        local function addRectangle(fromColumn, toColumn, firstRow, lastRow)
            local left, right = minX + fromColumn * cell, minX + toColumn * cell
            local top, bottom = minY + firstRow * cell, minY + (lastRow + 1) * cell
            local corner = { x = left, y = top }
            triangles[#triangles + 1] = { corner, { x = right, y = top }, { x = right, y = bottom } }
            triangles[#triangles + 1] = { corner, { x = right, y = bottom }, { x = left, y = bottom } }
        end
        local function addPolygon(polygon)
            for index = 2, #polygon - 1 do
                triangles[#triangles + 1] = { polygon[1], polygon[index], polygon[index + 1] }
            end
        end
        local function corner(row, column, number) -- 1 upper left, 2 upper right, 3 lower right, 4 lower left
            local x0, y0 = minX + column * cell, minY + row * cell
            if number == 1 then
                return { x = x0, y = y0 }
            elseif number == 2 then
                return { x = x0 + cell, y = y0 }
            elseif number == 3 then
                return { x = x0 + cell, y = y0 + cell }
            end
            return { x = x0, y = y0 + cell }
        end
        for row = 0, rows - 1 do
            if shouldYield and row % 16 == 0 then
                coroutine.yield()
            end
            local runStart
            local rowRuns = isFillWanted and {} or nil
            for column = 0, columns - 1 do
                local v1, v2 = valueAt(row, column), valueAt(row, column + 1)
                local v3, v4 = valueAt(row + 1, column + 1), valueAt(row + 1, column)
                local in1, in2, in3, in4 = v1 > 0, v2 > 0, v3 > 0, v4 > 0
                local insideCount = (in1 and 1 or 0) + (in2 and 1 or 0) + (in3 and 1 or 0) + (in4 and 1 or 0)
                if insideCount == 4 then
                    runStart = runStart or column
                else
                    if runStart and rowRuns then
                        rowRuns[runStart .. ":" .. column] = { runStart, column }
                    end
                    runStart = nil
                    if insideCount > 0 then
                        local inside = { in1, in2, in3, in4 }
                        -- The sides the edge crosses (side n runs from corner n to the next)
                        local crossed = {}
                        for side = 1, 4 do
                            if inside[side] ~= inside[side % 4 + 1] then
                                crossed[side] = sideCrossing(row, column, side)
                            end
                        end
                        local isSaddle = insideCount == 2 and in1 == in3
                        if isSaddle and not isMiddleInside(row, column) then
                            -- Two corners inside across from each other, not joined in the middle: a corner piece each
                            for number = 1, 4 do
                                if inside[number] then
                                    local before = crossed[(number + 2) % 4 + 1] -- the side coming into this corner
                                    local after = crossed[number]
                                    if isFillWanted then
                                        addPolygon({ corner(row, column, number), after, before })
                                    end
                                    edges[#edges + 1] = { before, after }
                                end
                            end
                        else
                            if isFillWanted then
                                -- One piece: the corners inside and the crossings, in order round the cell
                                local polygon = {}
                                for side = 1, 4 do
                                    if inside[side] then
                                        polygon[#polygon + 1] = corner(row, column, side)
                                    end
                                    if crossed[side] then
                                        polygon[#polygon + 1] = crossed[side]
                                    end
                                end
                                addPolygon(polygon)
                            end
                            if isSaddle then
                                -- Joined in the middle: the edge cuts off each outside corner
                                for number = 1, 4 do
                                    if not inside[number] then
                                        edges[#edges + 1] = { crossed[(number + 2) % 4 + 1], crossed[number] }
                                    end
                                end
                            else
                                local first, second
                                for side = 1, 4 do
                                    if crossed[side] then
                                        if first then
                                            second = crossed[side]
                                        else
                                            first = crossed[side]
                                        end
                                    end
                                end
                                edges[#edges + 1] = { first, second }
                            end
                        end
                    end
                end
            end
            if isFillWanted then
                if runStart then
                    rowRuns[runStart .. ":" .. columns] = { runStart, columns }
                end
                -- Runs that stop here become rectangles; the rest carry on into the next row
                for key, run in pairs(openRuns) do
                    if not rowRuns[key] then
                        addRectangle(run.from, run.to, run.firstRow, row - 1)
                        openRuns[key] = nil
                    end
                end
                for key, columnsOfRun in pairs(rowRuns) do
                    openRuns[key] = openRuns[key] or { from = columnsOfRun[1], to = columnsOfRun[2], firstRow = row }
                end
            end
        end
        for _, run in pairs(openRuns) do
            addRectangle(run.from, run.to, run.firstRow, rows - 1)
        end
        return edges, triangles
    end

    -- The smoothed outline, and its inside cut into triangles straight from it: far fewer pieces than the grid's
    -- strips and edge pieces, and the fill meets the smooth edge exactly
    local pieces = march(false)
    local outline, loops = MapMarks.simplifyEdges(pieces, cell * MapMarks.EDGE_TOLERANCE)
    if shouldYield then
        coroutine.yield()
    end
    -- An outline that closes into no loop cuts into nothing: the grid's fill then, never an edge with no inside
    local cut = MapMarks.triangulateLoops(loops)
    if cut and #cut > 0 then
        -- (loops: the outline's closed rings, for drawing it with fewer pieces: MapMarks.thinLoops)
        return { triangles = cut, edges = outline, pieces = MapMarks.pairTriangles(cut), loops = loops }
    end
    local _, gridTriangles = march(true)
    return { triangles = gridTriangles, edges = outline, pieces = MapMarks.pairTriangles(gridTriangles) }
end

---An outline's rings thinned further (Douglas-Peucker, as simplifyEdges thins them): the same shape drawn with
---fewer pieces of edge, a point that bends a ring by less than the tolerance left out. A ring is never thinned to
---fewer than four points (a small round area stays an area).
---@param loops { x: number, y: number }[][] Closed rings (composeAreaShape's `loops`)
---@return table[] edges { from, to } pieces
function MapMarks.thinLoops(loops, tolerance)
    local edges = {}
    local function thin(ring, first, last, kept)
        local a, b = ring[first], ring[last]
        local dx, dy = b.x - a.x, b.y - a.y
        local length = math.sqrt(dx * dx + dy * dy)
        local farthest, farthestIndex = 0, nil
        for index = first + 1, last - 1 do
            local point = ring[index]
            local distance = length > 0 and math.abs(dy * (point.x - a.x) - dx * (point.y - a.y)) / length
                or math.sqrt((point.x - a.x) ^ 2 + (point.y - a.y) ^ 2)
            if distance > farthest then
                farthest, farthestIndex = distance, index
            end
        end
        if farthestIndex and farthest > tolerance then
            thin(ring, first, farthestIndex, kept)
            thin(ring, farthestIndex, last, kept)
        else
            kept[#kept + 1] = b
        end
    end
    for _, loop in ipairs(loops) do
        -- Closed again (its first point at its end), and thinned in two halves, so its ends are not one point
        local ring = {}
        for index = 1, #loop do
            ring[index] = loop[index]
        end
        ring[#ring + 1] = loop[1]
        local kept = { ring[1] }
        local middle = math.floor(#ring / 2) + 1
        thin(ring, 1, middle, kept)
        thin(ring, middle, #ring, kept)
        if #kept < 5 then
            kept = ring -- (thinned to a sliver: as it was)
        end
        for index = 1, #kept - 1 do
            edges[#edges + 1] = { kept[index], kept[index + 1] }
        end
    end
    return edges
end

---The fill's triangles as fewer pieces to draw: two triangles sharing a side whose four corners make a convex shape
---are one piece of four (a texture takes four corners: half the textures for the same fill). Convex only, so the
---shape is the same however the game splits a texture's corners into its own two triangles.
---@return table[] pieces Each three or four points, round the piece
function MapMarks.pairTriangles(triangles)
    local ids, nextId = {}, 0
    local function idOf(point)
        local id = ids[point]
        if not id then
            nextId = nextId + 1
            id = nextId
            ids[point] = id
        end
        return id
    end
    local function sideKey(a, b)
        local first, second = idOf(a), idOf(b)
        if first > second then
            first, second = second, first
        end
        return first * 1048576 + second
    end
    -- The triangles on each side
    local bySide = {}
    for index, triangle in ipairs(triangles) do
        for corner = 1, 3 do
            local key = sideKey(triangle[corner], triangle[corner % 3 + 1])
            local list = bySide[key]
            if not list then
                list = {}
                bySide[key] = list
            end
            list[#list + 1] = index
        end
    end
    local function isConvex(ring)
        local sign = 0
        for index = 1, 4 do
            local a, b, c = ring[index], ring[index % 4 + 1], ring[(index + 1) % 4 + 1]
            local turn = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            if turn ~= 0 then
                if sign == 0 then
                    sign = turn > 0 and 1 or -1
                elseif (turn > 0 and 1 or -1) ~= sign then
                    return false
                end
            else
                return false -- (three in a line: a triangle in disguise, kept as one)
            end
        end
        return true
    end
    local isPaired, pieces = {}, {}
    for index, triangle in ipairs(triangles) do
        if not isPaired[index] then
            isPaired[index] = true
            local piece = triangle
            for corner = 1, 3 do
                local u, v, w = triangle[corner], triangle[corner % 3 + 1], triangle[(corner + 1) % 3 + 1]
                for _, other in ipairs(bySide[sideKey(u, v)]) do
                    if not isPaired[other] then
                        local otherTriangle = triangles[other]
                        local far -- the other triangle's corner off the shared side
                        for otherCorner = 1, 3 do
                            local point = otherTriangle[otherCorner]
                            if point ~= u and point ~= v then
                                far = point
                            end
                        end
                        local ring = far and { w, u, far, v }
                        if ring and isConvex(ring) then
                            isPaired[other], piece = true, ring
                            break
                        end
                    end
                end
                if piece ~= triangle then
                    break
                end
            end
            pieces[#pieces + 1] = piece
        end
    end
    return pieces
end

---The edge's short pieces joined end to end into lines, then thinned: a point that bends the line by less than the
---tolerance is left out. The same curve with far fewer pieces to draw.
---@return table[] edges { from, to } pieces, as many as the curve needs
function MapMarks.simplifyEdges(edges, tolerance)
    -- A point's place as one number (to a thousandth of a unit): pieces meeting there are joined. The tracing shares
    -- each crossing between its two pieces; pieces from elsewhere meet by place
    local function keyOf(point)
        return math.floor(point.x * 1000 + 0.5) * 1e8 + math.floor(point.y * 1000 + 0.5)
    end
    -- Each end's pieces, to walk from piece to piece
    local byEnd = {}
    for index, edge in ipairs(edges) do
        for side = 1, 2 do
            local key = keyOf(edge[side])
            local list = byEnd[key]
            if not list then
                list = {}
                byEnd[key] = list
            end
            list[#list + 1] = index
        end
    end
    local isUsed, chains = {}, {}
    for index, edge in ipairs(edges) do
        if not isUsed[index] then
            isUsed[index] = true
            -- Grown at its end, and at its start in a list of its own (put before it at the end, not one by one)
            local forward, backward = { edge[1], edge[2] }, {}
            for _, atEnd in ipairs({ true, false }) do
                local chain = atEnd and forward or backward
                while true do
                    local tip = chain[#chain] or forward[1]
                    local tipKey = keyOf(tip)
                    local nextIndex
                    for _, candidate in ipairs(byEnd[tipKey] or NONE) do
                        if not isUsed[candidate] then
                            nextIndex = candidate
                            break
                        end
                    end
                    if not nextIndex then
                        break
                    end
                    isUsed[nextIndex] = true
                    local nextEdge = edges[nextIndex]
                    chain[#chain + 1] = keyOf(nextEdge[1]) == tipKey and nextEdge[2] or nextEdge[1]
                end
            end
            local chain = {}
            for step = #backward, 1, -1 do
                chain[#chain + 1] = backward[step]
            end
            for step = 1, #forward do
                chain[#chain + 1] = forward[step]
            end
            chains[#chains + 1] = chain
        end
    end
    -- Corners cut (Chaikin): each piece's quarter points kept, so the line curves smoothly through the grid's bends
    local function smooth(chain)
        local isLoop = #chain > 3 and keyOf(chain[1]) == keyOf(chain[#chain])
        for _ = 1, MapMarks.EDGE_SMOOTHING do
            local cut = {}
            if not isLoop then
                cut[1] = chain[1]
            end
            for index = 1, #chain - 1 do
                local a, b = chain[index], chain[index + 1]
                cut[#cut + 1] = { x = a.x * 0.75 + b.x * 0.25, y = a.y * 0.75 + b.y * 0.25 }
                cut[#cut + 1] = { x = a.x * 0.25 + b.x * 0.75, y = a.y * 0.25 + b.y * 0.75 }
            end
            if isLoop then
                cut[#cut + 1] = cut[1]
            else
                cut[#cut + 1] = chain[#chain]
            end
            chain = cut
        end
        return chain, isLoop
    end
    -- Douglas-Peucker: keep the point furthest from the straight line between the ends while it is far enough
    local function thin(chain, first, last, kept)
        local a, b = chain[first], chain[last]
        local dx, dy = b.x - a.x, b.y - a.y
        local length = math.sqrt(dx * dx + dy * dy)
        local farthest, farthestIndex = 0, nil
        for index = first + 1, last - 1 do
            local point = chain[index]
            local distance = length > 0 and math.abs(dy * (point.x - a.x) - dx * (point.y - a.y)) / length
                or math.sqrt((point.x - a.x) ^ 2 + (point.y - a.y) ^ 2)
            if distance > farthest then
                farthest, farthestIndex = distance, index
            end
        end
        if farthestIndex and farthest > tolerance then
            thin(chain, first, farthestIndex, kept)
            thin(chain, farthestIndex, last, kept)
        else
            kept[#kept + 1] = b -- each piece's end; the chain's start is put in first
        end
    end
    local simplified, loops = {}, {}
    for _, rough in ipairs(chains) do
        local chain, isLoop = smooth(rough)
        if #chain >= 2 then
            local kept = { chain[1] }
            -- A closed loop is thinned in two halves, so its ends are not one point
            if isLoop then
                local middle = math.floor(#chain / 2) + 1
                thin(chain, 1, middle, kept)
                thin(chain, middle, #chain, kept)
            else
                thin(chain, 1, #chain, kept)
            end
            for index = 1, #kept - 1 do
                simplified[#simplified + 1] = { kept[index], kept[index + 1] }
            end
            if isLoop then
                kept[#kept] = nil -- the last point is the first again
                if #kept >= 3 then
                    loops[#loops + 1] = kept
                end
            end
        end
    end
    return simplified, loops
end

---@return number area Twice the signed area of a loop (positive when its points run clockwise on screen, y down)
local function getSignedArea(loop)
    local total = 0
    for index = 1, #loop do
        local a, b = loop[index], loop[index % #loop + 1]
        total = total + (a.x * b.y - b.x * a.y)
    end
    return total
end

local function isInsideLoop(loop, x, y)
    local isIn = false
    for index = 1, #loop do
        local a, b = loop[index], loop[index % #loop + 1]
        if (a.y > y) ~= (b.y > y) and x < a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y) then
            isIn = not isIn
        end
    end
    return isIn
end

---@return boolean isCrossing Two segments cross each other (touching at an end does not count)
local function isCrossing(a, b, c, d)
    local function side(p, q, r)
        return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
    end
    local d1, d2, d3, d4 = side(c, d, a), side(c, d, b), side(a, b, c), side(a, b, d)
    return ((d1 > 0 and d2 < 0) or (d1 < 0 and d2 > 0)) and ((d3 > 0 and d4 < 0) or (d3 < 0 and d4 > 0))
end

---Joins a hole into the loop round it with a thin cut from the hole's rightmost point to a point of the loop it
---can see, so the two make one loop to cut into triangles.
---@return table? joined nil when no such cut is found
local function joinHole(outer, hole, others)
    local rightmost = 1
    for index, point in ipairs(hole) do
        if point.x > hole[rightmost].x then
            rightmost = index
        end
    end
    local from = hole[rightmost]
    local candidates = {}
    for index, point in ipairs(outer) do
        candidates[#candidates + 1] = { index = index, distance = (point.x - from.x) ^ 2 + (point.y - from.y) ^ 2 }
    end
    table.sort(candidates, function(first, second)
        return first.distance < second.distance
    end)
    for _, candidate in ipairs(candidates) do
        local to = outer[candidate.index]
        local isClear = true
        for _, loop in ipairs(others) do
            for index = 1, #loop do
                local a, b = loop[index], loop[index % #loop + 1]
                if a ~= from and b ~= from and a ~= to and b ~= to and isCrossing(from, to, a, b) then
                    isClear = false
                    break
                end
            end
            if not isClear then
                break
            end
        end
        if isClear then
            local joined = {}
            for index = 1, candidate.index do
                joined[#joined + 1] = outer[index]
            end
            for step = 0, #hole do
                joined[#joined + 1] = hole[(rightmost - 1 + step) % #hole + 1]
            end
            for index = candidate.index, #outer do
                joined[#joined + 1] = outer[index]
            end
            return joined
        end
    end
    return nil
end

---Cuts a simple loop into triangles by cutting off its ears one by one.
---@return table[]? triangles nil when the loop cannot be cut (it crosses itself)
local function cutEars(loop)
    local points = {}
    for index, point in ipairs(loop) do
        points[index] = point
    end
    if getSignedArea(points) < 0 then
        local reversed = {}
        for index = #points, 1, -1 do
            reversed[#reversed + 1] = points[index]
        end
        points = reversed
    end
    local function cross(a, b, c)
        return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    end
    -- The loop as a ring (each point's neighbours), so cutting an ear off takes nothing from a list; and its corners
    -- that bend inwards apart: only those can stand inside an ear, so only those are looked at (a smooth area has few,
    -- where every point was looked at for every ear)
    local count = #points
    local before, after, isInward = {}, {}, {}
    for index = 1, count do
        before[index], after[index] = (index - 2) % count + 1, index % count + 1
    end
    local function setBend(index)
        isInward[index] = cross(points[before[index]], points[index], points[after[index]]) <= 0 or nil
    end
    for index = 1, count do
        setBend(index)
    end
    local function isEar(index)
        if isInward[index] then
            return false
        end
        local a, b, c = points[before[index]], points[index], points[after[index]]
        for other in pairs(isInward) do
            local point = points[other]
            if
                point ~= a
                and point ~= b
                and point ~= c
                and cross(a, b, point) >= 0
                and cross(b, c, point) >= 0
                and cross(c, a, point) >= 0
            then
                return false
            end
        end
        return true
    end
    local triangles, index, misses, left = {}, 1, 0, count
    while left > 3 do
        if isEar(index) then
            local previous, following = before[index], after[index]
            triangles[#triangles + 1] = { points[previous], points[index], points[following] }
            after[previous], before[following] = following, previous
            isInward[index] = nil
            left = left - 1
            setBend(previous)
            setBend(following)
            index, misses = following, 0
        else
            index, misses = after[index], misses + 1
            if misses > left then
                return nil
            end
        end
    end
    triangles[#triangles + 1] = { points[before[index]], points[index], points[after[index]] }
    return triangles
end

---Fills an area's outline with as few triangles as its points need: each outer loop with the holes inside it.
---@return table[]? triangles nil when it cannot be done, for the grid's fill to be used instead
function MapMarks.triangulateLoops(loops)
    -- How many loops each lies in: an even number, an outer edge; odd, a hole
    local depths = {}
    for index, loop in ipairs(loops) do
        local depth = 0
        for other, around in ipairs(loops) do
            if other ~= index and isInsideLoop(around, loop[1].x, loop[1].y) then
                depth = depth + 1
            end
        end
        depths[index] = depth
    end
    local triangles = {}
    for index, loop in ipairs(loops) do
        if depths[index] % 2 == 0 then
            -- Its holes: the loops one deeper inside it
            local outer, holes = loop, {}
            if getSignedArea(outer) < 0 then
                local reversed = {}
                for step = #outer, 1, -1 do
                    reversed[#reversed + 1] = outer[step]
                end
                outer = reversed
            end
            for other, hole in ipairs(loops) do
                if depths[other] == depths[index] + 1 and isInsideLoop(loop, hole[1].x, hole[1].y) then
                    local opposite = hole
                    if getSignedArea(hole) > 0 then
                        opposite = {}
                        for step = #hole, 1, -1 do
                            opposite[#opposite + 1] = hole[step]
                        end
                    end
                    holes[#holes + 1] = opposite
                end
            end
            -- Holes furthest right first, each joined into the loop as it then is
            table.sort(holes, function(first, second)
                local firstX, secondX = -math.huge, -math.huge
                for _, point in ipairs(first) do
                    firstX = math.max(firstX, point.x)
                end
                for _, point in ipairs(second) do
                    secondX = math.max(secondX, point.x)
                end
                return firstX > secondX
            end)
            for _, hole in ipairs(holes) do
                outer = joinHole(outer, hole, { outer, unpack(holes) })
                if not outer then
                    return nil
                end
            end
            local cut = cutEars(outer)
            if not cut then
                return nil
            end
            for _, triangle in ipairs(cut) do
                triangles[#triangles + 1] = triangle
            end
        end
    end
    return triangles
end

---@return boolean isInside A place lies in an area: its spawns' glows, added up, are strong enough there (the same
---rule its shape is drawn by)
function MapMarks.isInsideArea(area, x, y)
    if not area.buckets then
        area.buckets, area.bucketSize = bucketSpawns(area.points or {}, area.reach)
    end
    return getAreaValue(area.buckets, area.bucketSize, area.reach, x, y) > 0
end

---A triangle of colour: a texture whose corners are moved onto the three points (the last two corners meet).
---@param anchor table? The frame whose upper left corner the points are measured from (y down); the area layer
-- Its shape is measured from its upper left corner in hundredths of a unit: the same triangle moved (a round minimap's
-- areas as the player walks) has the very same size and corners, which a remembering texture then need not be given
-- again (Widgets.remember); only its place changes
local function toHundredths(value)
    return math.floor(value * 100 + 0.5) / 100
end

local function setTriangle(texture, first, second, third, anchor)
    local left = math.min(first.x, second.x, third.x)
    local top = math.min(first.y, second.y, third.y)
    local firstX, firstY = toHundredths(first.x - left), toHundredths(first.y - top)
    local secondX, secondY = toHundredths(second.x - left), toHundredths(second.y - top)
    local thirdX, thirdY = toHundredths(third.x - left), toHundredths(third.y - top)
    local width = math.max(firstX, secondX, thirdX, 0.01)
    local height = math.max(firstY, secondY, thirdY, 0.01)
    ns.Widgets.place(texture, "TOPLEFT", anchor or State.areaLayer, "TOPLEFT", left, -top)
    texture:SetSize(width, height)
    -- Offsets from each corner's own place, y up: upper left, lower left, upper right, lower right
    texture:SetVertexOffset(1, firstX, -firstY)
    texture:SetVertexOffset(2, secondX, height - secondY)
    texture:SetVertexOffset(3, thirdX - width, -thirdY)
    texture:SetVertexOffset(4, thirdX - width, height - thirdY)
end

---A piece of four corners (MapMarks.pairTriangles), round it: a texture whose corners are moved onto them.
local function setQuad(texture, first, second, third, fourth, anchor)
    local left = math.min(first.x, second.x, third.x, fourth.x)
    local top = math.min(first.y, second.y, third.y, fourth.y)
    local firstX, firstY = toHundredths(first.x - left), toHundredths(first.y - top)
    local secondX, secondY = toHundredths(second.x - left), toHundredths(second.y - top)
    local thirdX, thirdY = toHundredths(third.x - left), toHundredths(third.y - top)
    local fourthX, fourthY = toHundredths(fourth.x - left), toHundredths(fourth.y - top)
    local width = math.max(firstX, secondX, thirdX, fourthX, 0.01)
    local height = math.max(firstY, secondY, thirdY, fourthY, 0.01)
    ns.Widgets.place(texture, "TOPLEFT", anchor or State.areaLayer, "TOPLEFT", left, -top)
    texture:SetSize(width, height)
    -- Round the piece: upper left, lower left, lower right, upper right (y up)
    texture:SetVertexOffset(1, firstX, -firstY)
    texture:SetVertexOffset(2, secondX, height - secondY)
    texture:SetVertexOffset(4, thirdX - width, height - thirdY)
    texture:SetVertexOffset(3, fourthX - width, -fourthY)
end

MapMarks.setTriangle = setTriangle
MapMarks.setQuad = setQuad

-- Shared with the other parts of the window
Shapes.setTriangle = setTriangle
Shapes.setQuad = setQuad
