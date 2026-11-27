local _, ns = ...

-- The map's marks: ovals, a quest's areas as round patches, for the kept drawing of the world map (World) and the
-- minimap's areas (MinimapAreas): the ovals fitted round groups of spawns, and the pictures each is drawn with.
--
-- An area traced round its spawns is some ten pieces of fill and two dozen lines; a full quest log over a few zones
-- is a thousand of them and more, and the game draws every one at every frame the map stands open: with areas on,
-- that was most of what the open map cost. An oval is two pictures, a tinted disc and a ring, whatever its size:
-- each group of spawns gets the oval that holds it (turned along the way the spawns lie), a long or hollow group two
-- or more. A tenth of the pieces, none of them a line, and nothing to lay out again as the map zooms (an oval is
-- the same at every zoom; only its ring is changed for one of another thickness, to stay as wide on screen).
local Ovals = {}
ns.MapMarksOvals = Ovals

local MEDIA = "Interface\\AddOns\\OneMoreQuest\\Media\\"
local OVAL_DISC = MEDIA .. "AreaDisc"
local OVAL_SOFT = MEDIA .. "SoftDot" -- (solid in the middle, fading at the edge)
local SOFT_GROWTH = 1.3 -- a soft patch is drawn this much larger: its faded edge reaches as far as a disc's sharp one
local SOFT_EDGE_SHARE = 0.14 -- how much of the outline's strength a soft patch has, in place of a ring
local SOFT_FILL_SHARE = 0.7 -- and of the fill's
local SOFT_LONE_EDGE_SHARE = 0.4 -- (the outline's, for a patch that stands alone)
-- The rings: each a share of its picture's width thick (the first a 512 pixel picture, for an oval large on screen)
local OVAL_RINGS = {
    { MEDIA .. "AreaEdge1", 2 / 512 },
    { MEDIA .. "AreaEdge2", 2 / 256 },
    { MEDIA .. "AreaEdge3", 4 / 256 },
    { MEDIA .. "AreaEdge4", 8 / 256 },
    { MEDIA .. "AreaEdge5", 16 / 256 },
    { MEDIA .. "AreaEdge6", 32 / 256 },
}
Ovals.MAX_STRETCH = 2.5 -- an oval longer than this many times its width is two ovals
Ovals.MIN_COVER = 0.3 -- so is one whose spawns cover less than this share of it (a ring of camps, a bend)
Ovals.MAX_REACH = 0.16 -- and one longer than this share of its zone's width, each way from its middle
Ovals.MAX_SPLITS = 3 -- a group of spawns is halved at most this many times over (eight ovals)
Ovals.PADDING = 0.4 -- an oval reaches this share of an area's reach past its outermost spawns: room for their marks

---The points on the outside of a group (its hull), going round: an oval that holds these holds them all.
local function getHull(points)
    local sorted = {}
    for index = 1, #points do
        sorted[index] = points[index]
    end
    table.sort(sorted, function(first, second)
        if first[1] ~= second[1] then
            return first[1] < second[1]
        end
        return first[2] < second[2]
    end)
    local function turn(origin, first, second)
        return (first[1] - origin[1]) * (second[2] - origin[2]) - (first[2] - origin[2]) * (second[1] - origin[1])
    end
    local hull = {}
    for index = 1, #sorted do
        while #hull >= 2 and turn(hull[#hull - 1], hull[#hull], sorted[index]) <= 0 do
            hull[#hull] = nil
        end
        hull[#hull + 1] = sorted[index]
    end
    local lower = #hull + 1
    for index = #sorted - 1, 1, -1 do
        while #hull >= lower and turn(hull[#hull - 1], hull[#hull], sorted[index]) <= 0 do
            hull[#hull] = nil
        end
        hull[#hull + 1] = sorted[index]
    end
    hull[#hull] = nil -- (the first point again)
    return hull
end

---The smallest oval round some points (Khachiyan's way: the points weighed until the oval through the heaviest
---holds them all), as its middle, the way it lies and its two half widths; nil for points in a line or on a spot.
local function fitSmallestOval(points)
    local hull = getHull(points)
    local count = #hull
    if count < 3 then
        return nil
    end
    local weights = {}
    for index = 1, count do
        weights[index] = 1 / count
    end
    for _ = 1, 60 do
        -- X = the weighed sum of each point (x, y, 1) times itself; its inverse measures every point
        local a, b, c, d, e, f = 0, 0, 0, 0, 0, 0 -- [a b c; b d e; c e f]
        for index = 1, count do
            local x, y, weight = hull[index][1], hull[index][2], weights[index]
            a, b, c = a + weight * x * x, b + weight * x * y, c + weight * x
            d, e, f = d + weight * y * y, e + weight * y, f + weight
        end
        local determinant = a * (d * f - e * e) - b * (b * f - e * c) + c * (b * e - d * c)
        if math.abs(determinant) < 1e-30 then
            return nil
        end
        local i11, i12, i13 =
            (d * f - e * e) / determinant, (c * e - b * f) / determinant, (b * e - c * d) / determinant
        local i22, i23, i33 =
            (a * f - c * c) / determinant, (b * c - a * e) / determinant, (a * d - b * b) / determinant
        local worst, worstIndex = 0, 1
        for index = 1, count do
            local x, y = hull[index][1], hull[index][2]
            local measure = x * (i11 * x + i12 * y + i13) + y * (i12 * x + i22 * y + i23) + (i13 * x + i23 * y + i33)
            if measure > worst then
                worst, worstIndex = measure, index
            end
        end
        local step = (worst - 3) / (3 * (worst - 1))
        if step < 0.002 then
            break
        end
        for index = 1, count do
            weights[index] = weights[index] * (1 - step)
        end
        weights[worstIndex] = weights[worstIndex] + step
    end
    local middleX, middleY = 0, 0
    for index = 1, count do
        middleX, middleY = middleX + weights[index] * hull[index][1], middleY + weights[index] * hull[index][2]
    end
    local xx, xy, yy = 0, 0, 0
    for index = 1, count do
        local dx, dy, weight = hull[index][1] - middleX, hull[index][2] - middleY, weights[index]
        xx, xy, yy = xx + weight * dx * dx, xy + weight * dx * dy, yy + weight * dy * dy
    end
    -- (the oval's own two widths squared are twice the spread's along each of its axes)
    local angle = 0.5 * math.atan2(2 * xy, xx - yy)
    local ux, uy = math.cos(angle), math.sin(angle)
    local along = 2 * (xx * ux * ux + 2 * xy * ux * uy + yy * uy * uy)
    local across = 2 * (xx * uy * uy - 2 * xy * ux * uy + yy * ux * ux)
    if along <= 0 or across <= 0 then
        return nil
    end
    return middleX, middleY, ux, uy, math.sqrt(along), math.sqrt(across)
end

---The oval that holds some points, as tight as an oval can be: its middle, the way it lies, and its two half widths
---(a little past the outermost points, for their marks).
local function fitOval(points, reach)
    local count = #points
    local meanX, meanY, ux, uy, along, across = fitSmallestOval(points)
    if not meanX then
        -- In a line or on a spot: along the way they lie, by how far they spread
        meanX, meanY = 0, 0
        for index = 1, count do
            meanX, meanY = meanX + points[index][1], meanY + points[index][2]
        end
        meanX, meanY = meanX / count, meanY / count
        local xx, xy, yy = 0, 0, 0
        for index = 1, count do
            local dx, dy = points[index][1] - meanX, points[index][2] - meanY
            xx, xy, yy = xx + dx * dx, xy + dx * dy, yy + dy * dy
        end
        local angle = 0.5 * math.atan2(2 * xy, xx - yy)
        ux, uy = math.cos(angle), math.sin(angle)
        along, across = 0, 0
        for index = 1, count do
            local dx, dy = points[index][1] - meanX, points[index][2] - meanY
            along = math.max(along, math.abs(dx * ux + dy * uy))
            across = math.max(across, math.abs(dy * ux - dx * uy))
        end
    end
    local least = reach * 0.1
    along, across = math.max(along, least), math.max(across, least)
    -- (grown until the farthest point is in: the fitting stops a little short of it)
    local grow = 1
    for index = 1, count do
        local dx, dy = points[index][1] - meanX, points[index][2] - meanY
        local a, b = (dx * ux + dy * uy) / along, (dy * ux - dx * uy) / across
        grow = math.max(grow, math.sqrt(a * a + b * b))
    end
    local padding = reach * Ovals.PADDING
    return {
        x = meanX,
        y = meanY,
        ux = ux,
        uy = uy,
        along = along * grow + padding,
        across = across * grow + padding,
        points = points,
    }
end

---Fits ovals to a group of points: one, or (long, or mostly empty) each half's own.
---@param isAllSoft boolean? Every oval drawn soft, a camp's own too (the settings' "Shadows")
local function fitOvals(points, reach, depth, ovals, isAllSoft)
    local oval = fitOval(points, reach)
    local count = #points
    if depth < Ovals.MAX_SPLITS and count >= 4 then
        -- How much of the oval its spawns cover, each a patch of its reach
        local cells, covered = {}, 0
        for index = 1, count do
            local key = math.floor(points[index][1] / reach) * 65536 + math.floor(points[index][2] / reach)
            if not cells[key] then
                cells[key] = true
                covered = covered + 1
            end
        end
        local cover = covered * 3 * reach * reach / (math.pi * oval.along * oval.across)
        if oval.along / oval.across > Ovals.MAX_STRETCH or cover < Ovals.MIN_COVER or oval.along > Ovals.MAX_REACH then
            -- Halved across its long axis: the points nearer each end (two rounds of telling them apart)
            local lowX, lowY, highX, highY
            local low, high = math.huge, -math.huge
            for index = 1, count do
                local along = (points[index][1] - oval.x) * oval.ux + (points[index][2] - oval.y) * oval.uy
                if along < low then
                    low, lowX, lowY = along, points[index][1], points[index][2]
                end
                if along > high then
                    high, highX, highY = along, points[index][1], points[index][2]
                end
            end
            local first, second
            for _ = 1, 2 do
                first, second = {}, {}
                local sumLowX, sumLowY, sumHighX, sumHighY = 0, 0, 0, 0
                for index = 1, count do
                    local x, y = points[index][1], points[index][2]
                    if (x - lowX) ^ 2 + (y - lowY) ^ 2 <= (x - highX) ^ 2 + (y - highY) ^ 2 then
                        first[#first + 1] = points[index]
                        sumLowX, sumLowY = sumLowX + x, sumLowY + y
                    else
                        second[#second + 1] = points[index]
                        sumHighX, sumHighY = sumHighX + x, sumHighY + y
                    end
                end
                if #first == 0 or #second == 0 then
                    break
                end
                lowX, lowY = sumLowX / #first, sumLowY / #first
                highX, highY = sumHighX / #second, sumHighY / #second
            end
            if #first > 0 and #second > 0 then
                fitOvals(first, reach, depth + 1, ovals, isAllSoft)
                fitOvals(second, reach, depth + 1, ovals, isAllSoft)
                return
            end
        end
    end
    -- One of several a group was halved into: drawn soft, with no ring (their rings crossed each other; soft
    -- patches run into one another, darker where the spawns are thicker)
    oval.isPart = depth > 0
    oval.isSoft = oval.isPart or isAllSoft == true
    ovals[#ovals + 1] = oval
end

---The ovals for one group of points, for another drawing of them (the minimap's, in its own units).
---@param points { x: number, y: number }[]
---@return table[] ovals Each { x, y, ux, uy, along, across, isSoft, isPart }
function Ovals.fitGroupOvals(points, reach, isAllSoft)
    local places, ovals = {}, {}
    for index, point in ipairs(points) do
        places[index] = { point.x, point.y }
    end
    if #places > 0 then
        fitOvals(places, reach, 0, ovals, isAllSoft)
    end
    return ovals
end
local OVAL_SIGNS = { { -1, -1 }, { -1, 1 }, { 1, 1 }, { 1, -1 } }

---@return number x, number y One of an oval's four corners (1 to 4, going round), in the oval's own units: the corners
---of the picture drawn for it, a soft patch's a little further out than a disc's
function Ovals.getCorner(oval, corner)
    local grow = oval.isSoft and SOFT_GROWTH or 1
    local sign = OVAL_SIGNS[corner]
    local along, across = sign[1] * oval.along * grow, sign[2] * oval.across * grow
    return oval.x + along * oval.ux - across * oval.uy, oval.y + along * oval.uy + across * oval.ux
end

---@return string picture, number fillShare, number edgeShare What an oval is drawn with: its picture (a disc, or a
---soft patch) and how much of the look's fill and edge strength it has. A soft patch's "outline" is a second soft
---patch, fainter; one of a scatter's lies over others and is fainter still than a camp's own, which stands alone
function Ovals.getLook(oval)
    if not oval.isSoft then
        return OVAL_DISC, 1, 1
    end
    return OVAL_SOFT, oval.isPart and SOFT_FILL_SHARE or 1, oval.isPart and SOFT_EDGE_SHARE or SOFT_LONE_EDGE_SHARE
end

---@return string picture The ring whose thickness, on an oval so many pixels across on screen (both its half widths
---together), comes nearest an edge of so many pixels
function Ovals.getRing(acrossPixels, edgePixels)
    local wanted, best, bestGap = edgePixels / math.max(acrossPixels, 1), 1, math.huge
    for ringIndex, ring in ipairs(OVAL_RINGS) do
        local gap = math.abs(math.log(ring[2] / wanted))
        if gap < bestGap then
            best, bestGap = ringIndex, gap
        end
    end
    return OVAL_RINGS[best][1]
end

---Fits ovals to one group of places, added to `ovals`: one, or (long, or mostly empty) each half's own.
---@param places number[][] Each { x, y }, in any units
---@param isAllSoft boolean? Every oval drawn soft, a camp's own too (the settings' "Shadows")
function Ovals.addGroupOvals(places, reach, ovals, isAllSoft)
    fitOvals(places, reach, 0, ovals, isAllSoft)
end
