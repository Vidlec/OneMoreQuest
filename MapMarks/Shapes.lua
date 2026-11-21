local addonName, ns = ...

-- The map's marks: the geometry of quest areas (their outline from the spawns, simplified and cut into triangles).
local MapMarks = ns.MapMarks
local Style, State = ns.MapMarksStyle, ns.MapMarksState
local Compose, Look, Layout, Shapes, Areas, Draw = ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw

local AREA_SOFTNESS = 0.85 -- how widely each spawn's glow spreads, against the reach: wider melts spawns together rounder

---@return number value How strongly a place lies in an area: each spawn's soft glow (a bell curve), added up, less
---what one spawn gives at the edge of its reach. Positive inside: a lone spawn's area is the circle of its reach;
---near spawns melt into one round shape.
local function getAreaValue(buckets, bucketSize, reach, x, y)
    local spread = AREA_SOFTNESS * reach
    local total = 0
    local bucketX, bucketY = math.floor(x / bucketSize), math.floor(y / bucketSize)
    for stepX = -1, 1 do
        for stepY = -1, 1 do
            for _, point in ipairs(buckets[(bucketX + stepX) .. ":" .. (bucketY + stepY)] or {}) do
                total = total + math.exp(-((point.x - x) ^ 2 + (point.y - y) ^ 2) / (2 * spread * spread))
            end
        end
    end
    return total - math.exp(-reach * reach / (2 * spread * spread))
end

---@return table buckets, number size The spawns sorted into squares as wide as a glow reaches, for quick lookups
local function bucketSpawns(points, reach)
    local size = 3 * AREA_SOFTNESS * reach -- past three spreads a glow adds nothing that shows
    local buckets = {}
    for _, point in ipairs(points) do
        local key = math.floor(point.x / size) .. ":" .. math.floor(point.y / size)
        buckets[key] = buckets[key] or {}
        table.insert(buckets[key], point)
    end
    return buckets, size
end

---An area that follows its spawns, smooth and round: each spawn glows softly, the glows of nearby spawns add up
---into one rounded shape, the land between groups left open; a lone spawn's area is the circle of its reach.
---Traced on a grid (marching squares), crossings placed where the glow fades out between grid points, so its
---edge curves smoothly.
---@param points { x: number, y: number }[] The spawns, in any units with y down
---@param reach number How far the area reaches past each spawn, in the same units
---@param cell number? The grid's spacing; a third of the reach when left out
---@return { triangles: table[], edges: table[] } shape Triangles that fill it ({ a, b, c }: whole stretches of grid
---inside as two each), and its edge as short lines ({ from, to }); all in the points' units
---@param shouldYield boolean? Run in slices: pause now and then (inside a coroutine), so a big shape spreads over frames
function MapMarks.composeAreaShape(points, reach, cell, shouldYield)
    cell = cell or reach / 3
    local triangles, edges = {}, {}
    if #points == 0 or reach <= 0 then
        return { triangles = triangles, edges = edges }
    end
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, point in ipairs(points) do
        minX, maxX = math.min(minX, point.x), math.max(maxX, point.x)
        minY, maxY = math.min(minY, point.y), math.max(maxY, point.y)
    end
    local buckets, bucketSize = bucketSpawns(points, reach)
    -- Room round the spawns for where glows add up past one spawn's reach
    local margin = 3 * AREA_SOFTNESS * reach + cell
    minX, minY = minX - margin, minY - margin
    local columns = math.ceil((maxX + margin - minX) / cell)
    local rows = math.ceil((maxY + margin - minY) / cell)
    local function getValue(x, y)
        return getAreaValue(buckets, bucketSize, reach, x, y)
    end
    local values = {}
    for row = 0, rows do
        if shouldYield and row % 8 == 0 then
            coroutine.yield()
        end
        local line = {}
        for column = 0, columns do
            line[column] = getValue(minX + column * cell, minY + row * cell)
        end
        values[row] = line
    end
    local function crossing(first, second, firstValue, secondValue)
        local t = firstValue / (firstValue - secondValue)
        return { x = first.x + (second.x - first.x) * t, y = first.y + (second.y - first.y) * t }
    end
    local function addPolygon(polygon)
        for index = 2, #polygon - 1 do
            triangles[#triangles + 1] = { polygon[1], polygon[index], polygon[index + 1] }
        end
    end
    -- Stretches of grid wholly inside, by their columns: the same stretch in the rows below grows into one
    -- rectangle, so a broad area is a few rectangles and not one strip per row
    local openRuns = {} -- ["from:to"] = { first row }
    local function addRectangle(fromColumn, toColumn, firstRow, lastRow)
        local left, right = minX + fromColumn * cell, minX + toColumn * cell
        local top, bottom = minY + firstRow * cell, minY + (lastRow + 1) * cell
        local corner = { x = left, y = top }
        triangles[#triangles + 1] = { corner, { x = right, y = top }, { x = right, y = bottom } }
        triangles[#triangles + 1] = { corner, { x = right, y = bottom }, { x = left, y = bottom } }
    end
    for row = 0, rows - 1 do
        if shouldYield and row % 16 == 0 then
            coroutine.yield()
        end
        local runStart
        local rowRuns = {}
        local function closeRun(endColumn)
            if runStart then
                rowRuns[runStart .. ":" .. endColumn] = { runStart, endColumn }
                runStart = nil
            end
        end
        for column = 0, columns - 1 do
            local x0, y0 = minX + column * cell, minY + row * cell
            local corners = {
                { x = x0, y = y0 }, { x = x0 + cell, y = y0 }, { x = x0 + cell, y = y0 + cell }, { x = x0, y = y0 + cell },
            }
            local cornerValues = { values[row][column], values[row][column + 1], values[row + 1][column + 1], values[row + 1][column] }
            local insideCount = 0
            for _, value in ipairs(cornerValues) do
                if value > 0 then insideCount = insideCount + 1 end
            end
            if insideCount == 4 then
                runStart = runStart or column
            else
                closeRun(column)
                if insideCount > 0 then
                    -- The crossing on each side of the cell (side n runs from corner n to the next)
                    local crossings = {}
                    for side = 1, 4 do
                        local nextSide = side % 4 + 1
                        if (cornerValues[side] > 0) ~= (cornerValues[nextSide] > 0) then
                            crossings[side] = crossing(corners[side], corners[nextSide], cornerValues[side], cornerValues[nextSide])
                        end
                    end
                    local isSaddle = insideCount == 2 and (cornerValues[1] > 0) == (cornerValues[3] > 0)
                    if isSaddle and getValue(x0 + cell / 2, y0 + cell / 2) <= 0 then
                        -- Two corners inside across from each other, not joined in the middle: a corner piece each
                        for corner = 1, 4 do
                            if cornerValues[corner] > 0 then
                                local before = crossings[(corner + 2) % 4 + 1] -- the side coming into this corner
                                local after = crossings[corner]
                                addPolygon({ corners[corner], after, before })
                                edges[#edges + 1] = { before, after }
                            end
                        end
                    else
                        -- One piece: the corners inside and the crossings, in order round the cell
                        local polygon = {}
                        for side = 1, 4 do
                            if cornerValues[side] > 0 then polygon[#polygon + 1] = corners[side] end
                            if crossings[side] then polygon[#polygon + 1] = crossings[side] end
                        end
                        addPolygon(polygon)
                        if isSaddle then
                            -- Joined in the middle: the edge cuts off each outside corner
                            for corner = 1, 4 do
                                if cornerValues[corner] <= 0 then
                                    edges[#edges + 1] = { crossings[(corner + 2) % 4 + 1], crossings[corner] }
                                end
                            end
                        else
                            local found = {}
                            for side = 1, 4 do
                                if crossings[side] then found[#found + 1] = crossings[side] end
                            end
                            edges[#edges + 1] = { found[1], found[2] }
                        end
                    end
                end
            end
        end
        closeRun(columns)
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
    for _, run in pairs(openRuns) do
        addRectangle(run.from, run.to, run.firstRow, rows - 1)
    end
    -- The smoothed outline, and its inside cut into triangles straight from it: far fewer pieces than the grid's
    -- strips and edge pieces, and the fill meets the smooth edge exactly. The grid's fill stays for a shape the
    -- cutting cannot do.
    local outline, loops = MapMarks.simplifyEdges(edges, cell * MapMarks.EDGE_TOLERANCE)
    if shouldYield then
        coroutine.yield()
    end
    -- An outline that closes into no loop cuts into nothing: the grid's fill then, never an edge with no inside
    local cut = MapMarks.triangulateLoops(loops)
    return { triangles = cut and #cut > 0 and cut or triangles, edges = outline }
end

---The edge's short pieces joined end to end into lines, then thinned: a point that bends the line by less than the
---tolerance is left out. The same curve with far fewer pieces to draw.
---@return table[] edges { from, to } pieces, as many as the curve needs
function MapMarks.simplifyEdges(edges, tolerance)
    local function keyOf(point)
        return string.format("%.3f:%.3f", point.x, point.y)
    end
    -- Each end's pieces, to walk from piece to piece
    local byEnd = {}
    for index, edge in ipairs(edges) do
        for _, point in ipairs(edge) do
            local key = keyOf(point)
            byEnd[key] = byEnd[key] or {}
            table.insert(byEnd[key], index)
        end
    end
    local isUsed, chains = {}, {}
    for index, edge in ipairs(edges) do
        if not isUsed[index] then
            isUsed[index] = true
            local chain = { edge[1], edge[2] }
            -- Grow it at its end, then at its start
            for _, atEnd in ipairs({ true, false }) do
                while true do
                    local tip = atEnd and chain[#chain] or chain[1]
                    local nextIndex
                    for _, candidate in ipairs(byEnd[keyOf(tip)] or {}) do
                        if not isUsed[candidate] then nextIndex = candidate break end
                    end
                    if not nextIndex then break end
                    isUsed[nextIndex] = true
                    local nextEdge = edges[nextIndex]
                    local other = keyOf(nextEdge[1]) == keyOf(tip) and nextEdge[2] or nextEdge[1]
                    if atEnd then chain[#chain + 1] = other else table.insert(chain, 1, other) end
                end
            end
            chains[#chains + 1] = chain
        end
    end
    -- Corners cut (Chaikin): each piece's quarter points kept, so the line curves smoothly through the grid's bends
    local function smooth(chain)
        local isLoop = #chain > 3 and keyOf(chain[1]) == keyOf(chain[#chain])
        for _ = 1, MapMarks.EDGE_SMOOTHING do
            local cut = {}
            if not isLoop then cut[1] = chain[1] end
            for index = 1, #chain - 1 do
                local a, b = chain[index], chain[index + 1]
                cut[#cut + 1] = { x = a.x * 0.75 + b.x * 0.25, y = a.y * 0.75 + b.y * 0.25 }
                cut[#cut + 1] = { x = a.x * 0.25 + b.x * 0.75, y = a.y * 0.25 + b.y * 0.75 }
            end
            if isLoop then cut[#cut + 1] = cut[1] else cut[#cut + 1] = chain[#chain] end
            chain = cut
        end
        return chain
    end
    for index, chain in ipairs(chains) do
        chains[index] = smooth(chain)
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
    for _, chain in ipairs(chains) do
        if #chain >= 2 then
            local kept = { chain[1] }
            -- A closed loop is thinned in two halves, so its ends are not one point
            local middle = math.floor(#chain / 2) + 1
            local isLoop = #chain > 3 and keyOf(chain[1]) == keyOf(chain[#chain])
            if isLoop then
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
        if point.x > hole[rightmost].x then rightmost = index end
    end
    local from = hole[rightmost]
    local candidates = {}
    for index, point in ipairs(outer) do
        candidates[#candidates + 1] = { index = index, distance = (point.x - from.x) ^ 2 + (point.y - from.y) ^ 2 }
    end
    table.sort(candidates, function(first, second) return first.distance < second.distance end)
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
            if not isClear then break end
        end
        if isClear then
            local joined = {}
            for index = 1, candidate.index do joined[#joined + 1] = outer[index] end
            for step = 0, #hole do joined[#joined + 1] = hole[(rightmost - 1 + step) % #hole + 1] end
            for index = candidate.index, #outer do joined[#joined + 1] = outer[index] end
            return joined
        end
    end
    return nil
end

---Cuts a simple loop into triangles by cutting off its ears one by one.
---@return table[]? triangles nil when the loop cannot be cut (it crosses itself)
local function cutEars(loop)
    local points = {}
    for index, point in ipairs(loop) do points[index] = point end
    if getSignedArea(points) < 0 then
        local reversed = {}
        for index = #points, 1, -1 do reversed[#reversed + 1] = points[index] end
        points = reversed
    end
    local function cross(a, b, c)
        return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    end
    local triangles, start, misses = {}, 1, 0
    while #points > 3 do
        local count = #points
        local index = (start - 1) % count + 1
        local a, b, c = points[(index - 2) % count + 1], points[index], points[index % count + 1]
        local isEar = cross(a, b, c) > 0
        if isEar then
            for other = 1, count do
                local point = points[other]
                if point ~= a and point ~= b and point ~= c then
                    if cross(a, b, point) >= 0 and cross(b, c, point) >= 0 and cross(c, a, point) >= 0 then
                        isEar = false
                        break
                    end
                end
            end
        end
        if isEar then
            triangles[#triangles + 1] = { a, b, c }
            table.remove(points, index)
            start, misses = index, 0
        else
            start, misses = index + 1, misses + 1
            if misses > count then
                return nil
            end
        end
    end
    triangles[#triangles + 1] = { points[1], points[2], points[3] }
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
            if other ~= index and isInsideLoop(around, loop[1].x, loop[1].y) then depth = depth + 1 end
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
                for step = #outer, 1, -1 do reversed[#reversed + 1] = outer[step] end
                outer = reversed
            end
            for other, hole in ipairs(loops) do
                if depths[other] == depths[index] + 1 and isInsideLoop(loop, hole[1].x, hole[1].y) then
                    local opposite = hole
                    if getSignedArea(hole) > 0 then
                        opposite = {}
                        for step = #hole, 1, -1 do opposite[#opposite + 1] = hole[step] end
                    end
                    holes[#holes + 1] = opposite
                end
            end
            -- Holes furthest right first, each joined into the loop as it then is
            table.sort(holes, function(first, second)
                local firstX, secondX = -math.huge, -math.huge
                for _, point in ipairs(first) do firstX = math.max(firstX, point.x) end
                for _, point in ipairs(second) do secondX = math.max(secondX, point.x) end
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
            for _, triangle in ipairs(cut) do triangles[#triangles + 1] = triangle end
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
local function setTriangle(texture, first, second, third, anchor)
    local left, right = math.min(first.x, second.x, third.x), math.max(first.x, second.x, third.x)
    local top, bottom = math.min(first.y, second.y, third.y), math.max(first.y, second.y, third.y)
    right, bottom = math.max(right, left + 0.01), math.max(bottom, top + 0.01)
    texture:ClearAllPoints()
    texture:SetPoint("TOPLEFT", anchor or State.areaLayer, "TOPLEFT", left, -top)
    texture:SetSize(right - left, bottom - top)
    -- Offsets from each corner's own place, y up: upper left, lower left, upper right, lower right
    texture:SetVertexOffset(1, first.x - left, top - first.y)
    texture:SetVertexOffset(2, second.x - left, bottom - second.y)
    texture:SetVertexOffset(3, third.x - right, top - third.y)
    texture:SetVertexOffset(4, third.x - right, bottom - third.y)
end

MapMarks.setTriangle = setTriangle

-- Shared with the other parts of the window
Shapes.setTriangle = setTriangle
