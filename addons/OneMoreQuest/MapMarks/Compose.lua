local addonName, ns = ... -- the addon's folder, which its pictures are read from

-- What the world map shows for quests, built to be read at a glance:
--  * one mark per area of a quest, never one per spawn point;
--  * a tracked quest's mark carries the quest's number (the number it has in the tracker and the quest list),
--    in the look chosen in the settings: a gold coin, a map pin, or a ring that fills with progress; a quest
--    ready to turn in is the game's gold "?";
--  * each quest a giver offers is the game's gold "!", one per quest;
--  * nothing is merged: marks that would cover one another are set side by side, each tied to its own spot by
--    a short line;
--  * one quest is drawn in full (the one selected in the quest list while the panels are open, else the
--    tracker's active quest): its areas are washed and outlined, its spawn points dotted, its ring is larger,
--    and its mark's tooltip lists its objectives there with a symbol and count each.
local MapMarks = {}
ns.MapMarks = MapMarks

-- The map's marks are drawn by the files of MapMarks\, in this order: Compose (which marks a map gets), Look (how each
-- looks), Layout (keeping them apart), Shapes (the geometry of quest areas), Areas (drawing them) and Draw (drawing on a
-- map). What they share: constants (Style), what changes as they draw (State), and each part's own functions.
local Style, State = {}, {}
local Compose, Look, Layout, Shapes, Areas, Draw = {}, {}, {}, {}, {}, {}
ns.MapMarksStyle, ns.MapMarksState = Style, State
ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw =
    Compose, Look, Layout, Shapes, Areas, Draw

local LINK_DISTANCE = 0.06 -- places closer than this, as a fraction of the map, belong to one area
local AREA_PADDING = 0.016
local MIN_AREA_RADIUS = 0.02
-- Our marks are drawn just under the game's group members (PIN_FRAME_LEVEL_GROUP_MEMBER), where the game draws its
-- own quest pins: party members and the player are always over them. Six levels: the spawn layer, the mark layer,
-- the marks (givers, quests, the quest in focus) and their insides.
local LEVELS_UNDER_GROUP = 6
local FALLBACK_GROUP_LEVEL = 2765 -- what the game's world map gives group members with an ordinary quest log
local FALLBACK_QUEST_BLOB_LEVEL = 2007 -- and its own quest areas
State.frameLevel = FALLBACK_GROUP_LEVEL - LEVELS_UNDER_GROUP
local MAX_POINTS = 80
local MERGE_DISTANCE = 0.035 -- marks of the quest in focus closer than this become one mark with several labels

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local GLYPHS =
    { kill = MEDIA .. "GlyphKill", loot = MEDIA .. "GlyphLoot", use = MEDIA .. "GlyphUse", tick = MEDIA .. "GlyphTick" }
local SOFT_DOT = MEDIA .. "SoftDot" -- a round patch, solid in the middle, fading at the edge
local QUEST_BLUE = { 0.3, 0.62, 1 } -- the game's own shading of quest areas
MapMarks.QUEST_BLUE = QUEST_BLUE -- the minimap's spawn squares are the same blue
-- Shades of that blue for a quest with several objectives, near enough to read as one family
local FOCUS_GOLD = { 1, 0.86, 0.2 } -- the followed quest's ring and glow, like the game's highlighted buttons
local QUEST_SHADES = { { 0.3, 0.62, 1 }, { 0.62, 0.46, 1 }, { 0.2, 0.85, 0.85 }, { 0.5, 0.78, 1 } }
local SPAWN_PATCH = 0.05 -- a shape's disc on a spawn point, as a fraction of the map's width
-- A spawn point is a tiny square, on screen, with no edge: round marks are the game's for people (the player's
-- party), so nothing of a quest's is round and small, and the spawns read as texture under the marks
local FADED_ICON_ALPHA, FADED_ICON_GLOW_ALPHA = 0.6, 0.4 -- a tracked quest's spawn icons and their glow, fainter
local FOCUSED_ICON_GLOW_ALPHA = 1 -- the focused or highlighted quest's spawn icons glow at full strength, to stand out
MapMarks.FADED_ICON_ALPHA, MapMarks.FADED_ICON_GLOW_ALPHA = FADED_ICON_ALPHA, FADED_ICON_GLOW_ALPHA
MapMarks.FOCUSED_ICON_GLOW_ALPHA = FOCUSED_ICON_GLOW_ALPHA
local AREA_RING = MEDIA .. "AreaRing"
MapMarks.AREA_RING, MapMarks.SOFT_DOT = AREA_RING, MEDIA .. "SoftDot"
MapMarks.GLYPHS = GLYPHS

-- "Icons and areas": each tracked quest in a colour of its own (by its number), its areas filled lightly and
-- edged in that colour, so where quests overlap their fills add up; on every spawn, one to a cell, an icon of
-- what to do there with a glow in the quest's colour
-- Twelve, told apart on the map's greens and browns; none is the gold of quest givers and the quest in focus
local QUEST_COLORS = {
    { 0.3, 0.62, 1 },
    { 1, 0.56, 0.18 },
    { 0.38, 0.82, 0.42 },
    { 0.96, 0.42, 0.66 },
    { 0.66, 0.5, 1 },
    { 0.22, 0.86, 0.84 },
    { 0.95, 0.3, 0.25 },
    { 0.72, 0.92, 0.3 },
    { 0.5, 0.82, 1 },
    { 0.88, 0.38, 0.95 },
    { 1, 0.7, 0.55 },
    { 0.55, 0.96, 0.72 },
}
-- A quest's areas are muted, as its spawn icons are, until the quest is focused or highlighted
local AREA_FILL_ALPHA, FOCUSED_AREA_FILL_ALPHA = 0.08, 0.3
local AREA_EDGE_ALPHA, FOCUSED_AREA_EDGE_ALPHA = 0.5, 0.95
local AREA_RIM_COLOR, AREA_RIM_ALPHA, FOCUSED_AREA_RIM_ALPHA = { 0.04, 0.06, 0.12 }, 0.2, 0.6
local AREA_REACH = 0.022 -- how far an area reaches past its spawns, as a fraction of the map's width
local SPAWN_ROOM = 1 -- pixels kept between a quest mark (its gold ring included) and the spawn marks round it
local AREA_TINT_ALPHA = 0.45 -- a quest's mark, beside its coloured area: a faint glow in that colour links them
local FOCUSED_AREA_TINT_ALPHA = 0.8 -- the highlighted quest's: as strong as the gold glow it takes the place of
local AREA_MIN_POINTS = 2 -- a spawn on its own is no area: its icon alone shows where it is
-- Areas hug their spawns, measured in the world's yards so every zone looks alike, on the map and the minimap

local AREA_REACH_YARDS = 50 -- how far an area reaches past each spawn; rings that touch make one area
-- Spawns all within this of one another are one place, not an area: the quest's mark stands on them and says it
local ONE_PLACE_YARDS = 40
local AREA_EDGE_PIXELS, AREA_RIM_PIXELS = 2, 4 -- the edge line and the soft dark line under it, on screen
local ICON_SIZE = 11 -- an objective's icon on the map, kept the same size on screen
local ICON_GLOW_SIZE = 17
local ICON_CELL = 12 -- one icon to a cell of this grid (on screen): a pixel more than an icon, so they stand close but never overlap
-- What to do at a spawn: a sword to kill, a sack to loot, a pointing hand to use, a speech bubble to talk; cream with a
-- dark edge, so they read on any map art and any glow
local OBJECTIVE_ICONS =
    { kill = MEDIA .. "IconKill", loot = MEDIA .. "IconLoot", use = MEDIA .. "IconUse", talk = MEDIA .. "IconTalk" }
MapMarks.OBJECTIVE_ICONS = OBJECTIVE_ICONS

---Sets an objective's icon on a texture.
function MapMarks.setObjectiveIcon(texture, glyph)
    texture:SetTexture(OBJECTIVE_ICONS[glyph] or OBJECTIVE_ICONS.use)
end

-- How the quests' places are shown is two choices of the player's, each on its own (the settings' Map and minimap):
--   the areas round a quest's spawns (settings.areaStyle): "filled", a light wash in the quest's colour; "blob", the
--     shapes, bold as the game draws its own quest areas; "none"
--   the marker on each spawn (settings.spawnMarker): "glyph", what to do there on a glow in the quest's colour;
--     "plate", the glyph on a small dark plate edged in that colour; "game", the game's own skull, chest and star;
--     "square", a small square in that colour; "none"
local AREA_STYLES = { filled = true, blob = true, none = true }
local SPAWN_MARKERS = { glyph = true, plate = true, game = true, square = true, none = true }

---@return string style "filled", "blob" or "none"
function MapMarks.getAreaStyle()
    local style = ns.settings.areaStyle
    return AREA_STYLES[style] and style or "filled"
end

---@return string marker "glyph", "plate", "game", "square" or "none"
function MapMarks.getSpawnMarker()
    local marker = ns.settings.spawnMarker
    return SPAWN_MARKERS[marker] and marker or "glyph"
end

---@return boolean hasColours Each quest's places are drawn in its own colour (areas, markers or both): its mark's
---glow takes that colour too, tying the two together
function MapMarks.hasQuestColours()
    return MapMarks.hasAreas() or MapMarks.getSpawnMarker() ~= "none"
end

local colorsKey, colorIndexByQuestId -- the tracked quests the colours were last shared out for, and the share
local colorsWatchKey -- the tracked quests as last looked at (QuestState.getWatchKey), in tracking order

---@return number[] color The colour of a quest, from its number alone, so it is the same in every session and
---nothing is saved: each quest's own colour is its ID's place in the palette. Two tracked quests whose own colours
---match are told apart: the lower ID keeps it, the other takes the next colour no tracked quest has. So a quest's
---colour changes only when a quest wanting the same colour is tracked or untracked. Without a quest, the colour is
---the number's.
function MapMarks.getQuestColor(number, questId)
    if not questId then
        return QUEST_COLORS[((number or 1) - 1) % #QUEST_COLORS + 1]
    end
    -- Asked for every area, icon and mark drawn: while the same quests are tracked (one cheap look), nothing is
    -- worked out again
    local watchKey = ns.QuestState.getWatchKey()
    if watchKey == colorsWatchKey and colorIndexByQuestId then
        return QUEST_COLORS[colorIndexByQuestId[questId] or (questId % #QUEST_COLORS + 1)]
    end
    colorsWatchKey = watchKey
    local sorted = ns.QuestState.getWatchedQuestIds()
    table.sort(sorted)
    local key = table.concat(sorted, ",")
    if key ~= colorsKey then
        -- Shared out again only when what is tracked changed: lowest ID first, each its own colour when free
        colorsKey, colorIndexByQuestId = key, {}
        local isTaken = {}
        for _, trackedId in ipairs(sorted) do
            local own = trackedId % #QUEST_COLORS + 1
            local index = own
            for step = 0, #QUEST_COLORS - 1 do
                local candidate = (own - 1 + step) % #QUEST_COLORS + 1
                if not isTaken[candidate] then
                    index = candidate
                    break
                end
            end
            isTaken[index] = true
            colorIndexByQuestId[trackedId] = index
        end
    end
    return QUEST_COLORS[colorIndexByQuestId[questId] or (questId % #QUEST_COLORS + 1)]
end

---@return string glyph What a quest wants next: the icon of its first unfinished objective ("use" when none)
function MapMarks.getQuestGlyph(questId, objectives)
    local quest = not objectives and ns.QuestState.getQuest(questId)
    for _, objective in ipairs(objectives or quest and quest.objectives or {}) do
        if not objective.isFinished then
            return MapMarks.getObjectiveGlyph(objective)
        end
    end
    return "use"
end

---@return string glyph What to do for an objective: "kill", "loot" or "use"
MapMarks.getObjectiveGlyph = ns.QuestState.getObjectiveGlyph -- what an objective asks, as its icon shows it
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

local GOLD, DARK = { 1, 0.82, 0 }, { 0.09, 0.07, 0.04 }

---------------------------------------------------------------------------------------------------------------
-- Working out what to show

---Groups points into areas: points in the same or neighbouring cells of a grid belong together.
---@param points { x: number, y: number }[] Fractions of the map
---@param linkDistance number? How near counts as together, as a fraction of the map; the area distance if omitted
---@return { x: number, y: number, radiusX: number, radiusY: number, points: table[] }[] areas Largest first
function MapMarks.composeAreas(points, linkDistance)
    linkDistance = linkDistance or LINK_DISTANCE
    local cells, parents = {}, {}
    local function getRoot(key)
        while parents[key] ~= key do
            parents[key] = parents[parents[key]]
            key = parents[key]
        end
        return key
    end
    for _, point in ipairs(points) do
        local column, row = math.floor(point.x / linkDistance), math.floor(point.y / linkDistance)
        local key = column .. ":" .. row
        if not cells[key] then
            cells[key] = { column = column, row = row, points = {} }
            parents[key] = key
        end
        table.insert(cells[key].points, point)
    end
    for key, cell in pairs(cells) do
        for columnOffset = -1, 1 do
            for rowOffset = -1, 1 do
                local neighbourKey = (cell.column + columnOffset) .. ":" .. (cell.row + rowOffset)
                if cells[neighbourKey] and neighbourKey ~= key then
                    parents[getRoot(neighbourKey)] = getRoot(key)
                end
            end
        end
    end

    local areasByRoot, areas = {}, {}
    for key, cell in pairs(cells) do
        local root = getRoot(key)
        local area = areasByRoot[root]
        if not area then
            area = { points = {} }
            areasByRoot[root] = area
            areas[#areas + 1] = area
        end
        for _, point in ipairs(cell.points) do
            area.points[#area.points + 1] = point
        end
    end
    for _, area in ipairs(areas) do
        local minX, maxX, minY, maxY, sumX, sumY = 1, 0, 1, 0, 0, 0
        for _, point in ipairs(area.points) do
            minX, maxX = math.min(minX, point.x), math.max(maxX, point.x)
            minY, maxY = math.min(minY, point.y), math.max(maxY, point.y)
            sumX, sumY = sumX + point.x, sumY + point.y
        end
        -- The mark sits in the middle of the area; the shading reaches a little past its outermost points
        area.x, area.y = (minX + maxX) / 2, (minY + maxY) / 2
        area.radiusX = math.max((maxX - minX) / 2 + AREA_PADDING, MIN_AREA_RADIUS)
        area.radiusY = math.max((maxY - minY) / 2 + AREA_PADDING, MIN_AREA_RADIUS)
        area.centroidX, area.centroidY = sumX / #area.points, sumY / #area.points
    end
    table.sort(areas, function(first, second)
        if #first.points ~= #second.points then
            return #first.points > #second.points
        end
        if first.x ~= second.x then
            return first.x < second.x
        end
        return first.y < second.y
    end)
    return areas
end

-- Areas in the world, worked out once from a list of places, whatever map shows them: spawns closer than LINK_DISTANCE
-- of their zone's width (in that zone's yards) belong together, as they did on the zone's own map. As neither the
-- map's zoom nor its view changes that, a quest's mark never moves.
local DEFAULT_ZONE_YARDS = 3500 -- for a zone whose size the game does not give
local worldPositions = setmetatable({}, { __mode = "k" }) -- place -> { continent, north, west }, or false
-- Key from the places -> { areaOf = { [position in the list] = index }, anchors = { [index] = position in the list },
-- sizes }. Kept by the places' positions in the list, never by the place tables themselves: the key is made from
-- where they are, so the same spawns in new tables (the quest's places worked out again) find the same areas.
local worldAreaCache = {}
local worldAreaCacheCount = 0
local WORLD_AREA_CACHE_LIMIT = 400 -- lists kept; the cache starts over past this

---@return table|false position { continent, north, west } of a place in the world; false where it has none (a dungeon)
local function getWorldPlace(place)
    local position = worldPositions[place]
    if position == nil then
        local uiMapId = place.zoneId and ns.Database.getUiMapId(place.zoneId)
        local continent, north, west = ns.Geometry.getWorldPosition(uiMapId, place.x, place.y)
        position = north and { continent, north, west } or false
        worldPositions[place] = position
    end
    return position
end

---@return string key The same for the same list of places, in the same order, cheaply: its length and two sums
---over its places, each weighted by its position (two, so that two different lists hardly ever meet)
local function getPlacesKey(places)
    local sum, otherSum = 0, 0
    for index, place in ipairs(places) do
        local x, y, zoneId = place.x or 0, place.y or 0, place.zoneId or 0
        sum = sum + x * index + y * 0.37 + zoneId * 0.001
        otherSum = otherSum + y * index + x * 0.61 + zoneId * index * 0.013
    end
    return #places .. ":" .. string.format("%.4f:%.4f", sum, otherSum)
end

---Groups places into areas in the world: places within WORLD_LINK_YARDS of each other, on one continent, belong
---together. Each area's anchor is its place nearest its middle: a real spawn, where the creatures are, never an
---empty middle (inside a ring of camps, or in the lake between two shores). Places are told by their position in
---the list: areaOf[position] is the area of places[position], anchors[area] the position of its anchor.
---@return { areaOf: table<number, number>, anchors: table<number, number>, sizes: number[] } areas
local function getWorldAreas(places)
    local key = getPlacesKey(places)
    local cached = worldAreaCache[key]
    if cached then
        return cached
    end
    local cells, parents, positions = {}, {}, {}
    -- How near counts as together: as on the first place's zone map, in its yards
    local firstZone = places[1] and places[1].zoneId
    local firstMapId = firstZone and ns.Database.getUiMapId(firstZone)
    local zoneYards = firstMapId and MapMarks.getMapYards(firstMapId) or DEFAULT_ZONE_YARDS
    local WORLD_LINK_YARDS = LINK_DISTANCE * zoneYards
    local function getRoot(cellKey)
        while parents[cellKey] ~= cellKey do
            parents[cellKey] = parents[parents[cellKey]]
            cellKey = parents[cellKey]
        end
        return cellKey
    end
    for placeIndex, place in ipairs(places) do
        local position = getWorldPlace(place)
        if position then
            positions[#positions + 1] = { placeIndex = placeIndex, position = position }
            local column, row = math.floor(position[3] / WORLD_LINK_YARDS), math.floor(position[2] / WORLD_LINK_YARDS)
            local cellKey = position[1] .. ":" .. column .. ":" .. row
            if not cells[cellKey] then
                cells[cellKey] = { continent = position[1], column = column, row = row }
                parents[cellKey] = cellKey
            end
        end
    end
    for cellKey, cell in pairs(cells) do
        for columnOffset = -1, 1 do
            for rowOffset = -1, 1 do
                local neighbourKey = cell.continent
                    .. ":"
                    .. (cell.column + columnOffset)
                    .. ":"
                    .. (cell.row + rowOffset)
                if cells[neighbourKey] and neighbourKey ~= cellKey then
                    parents[getRoot(neighbourKey)] = getRoot(cellKey)
                end
            end
        end
    end
    local indexByRoot, members = {}, {}
    local result = { areaOf = {}, anchors = {}, sizes = {} }
    for _, item in ipairs(positions) do
        local position = item.position
        local root = getRoot(
            position[1]
                .. ":"
                .. math.floor(position[3] / WORLD_LINK_YARDS)
                .. ":"
                .. math.floor(position[2] / WORLD_LINK_YARDS)
        )
        local index = indexByRoot[root]
        if not index then
            index = #members + 1
            indexByRoot[root] = index
            members[index] = {}
        end
        members[index][#members[index] + 1] = item
        result.areaOf[item.placeIndex] = index
    end
    for index, list in ipairs(members) do
        local sumNorth, sumWest = 0, 0
        for _, item in ipairs(list) do
            sumNorth, sumWest = sumNorth + item.position[2], sumWest + item.position[3]
        end
        local middleNorth, middleWest = sumNorth / #list, sumWest / #list
        local anchor, nearest = nil, math.huge
        for _, item in ipairs(list) do
            local distance = (item.position[2] - middleNorth) ^ 2 + (item.position[3] - middleWest) ^ 2
            if distance < nearest then
                anchor, nearest = item.placeIndex, distance
            end
        end
        result.anchors[index], result.sizes[index] = anchor, #list
    end
    if worldAreaCacheCount >= WORLD_AREA_CACHE_LIMIT then
        worldAreaCache, worldAreaCacheCount = {}, 0
    end
    worldAreaCache[key] = result
    worldAreaCacheCount = worldAreaCacheCount + 1
    return result
end

-- Spawn icons thinned out in the world, as Questie does, but in nested steps of doubling squares (thinPoints): a
-- coarser step's spawns are always among a finer one's, so zooming in only adds icons and zooming out only takes some
-- away, none ever moves; and every map, the minimap and every view keep the same ones.
MapMarks.SPAWN_SPACINGS = { 0, 25, 50, 100, 200, 400 } -- yards between shown spawns, finest first
local SPAWN_SPACING_PIXELS = ICON_SIZE + 1 -- shown spawns are at least an icon apart on screen (at the marks' size)
local SPAWN_SPACING_SLACK = 1.15 -- the zoom must go this far past a step's edge to change step: no flicker at the edge

local spawnRanks = setmetatable({}, { __mode = "k" }) -- place -> its fixed rank, from where it is

---@return number rank A spawn's own rank, from its place alone: the same on the map, the minimap and in every view
local function getSpawnRank(place)
    local rank = spawnRanks[place]
    if not rank then
        local seed = (place.x or 0) * 12.9898 + (place.y or 0) * 78.233 + (place.zoneId or 0) * 37.719
        rank = (math.sin(seed) * 43758.5453) % 1
        spawnRanks[place] = rank
    end
    return rank
end

---@return table[] points The spawns shown at a spacing (yards): the world cut into squares of that size, in each the
---spawn of the lowest rank. Each step's squares are four of the next finer step's, so the spawn kept in a big square
---is kept in its small one too: zooming in only adds spawns, never moves one. As a spawn's rank is its own, the
---same spawns are kept whichever list they come in: on the map, on the minimap, in every view.
function MapMarks.thinPoints(points, spacing)
    if not spacing or spacing <= 0 or #points < 2 then
        return points
    end
    local best, bestRank, kept = {}, {}, {}
    for _, point in ipairs(points) do
        local position = point.place and getWorldPlace(point.place)
        if position then
            local cell = position[1]
                .. ":"
                .. math.floor(position[3] / spacing)
                .. ":"
                .. math.floor(position[2] / spacing)
            local rank = getSpawnRank(point.place)
            if not bestRank[cell] or rank < bestRank[cell] then
                best[cell], bestRank[cell] = point, rank
            end
        else
            kept[#kept + 1] = point -- (no place in the world: always shown)
        end
    end
    local isBest = {}
    for _, point in pairs(best) do
        isBest[point] = true
    end
    for _, point in ipairs(points) do
        if isBest[point] then
            kept[#kept + 1] = point
        end
    end
    return kept
end

---@return number spacing Yards between the spawns shown at a zoom (pixels a yard), the finest step whose spawns stand
---SPAWN_SPACING_PIXELS apart on screen; past a step's edge only by SPAWN_SPACING_SLACK, so a zoom held at the edge
---never flickers between two steps
---@param current number? The step shown now
---@param markScale number? How large the marks are drawn at this zoom (Draw's getMarkScale): smaller icons need less room
function MapMarks.chooseSpawnSpacing(pixelsPerYard, current, markScale)
    local minPixels = SPAWN_SPACING_PIXELS * (markScale or 1)
    local function choose(perYard)
        for _, spacing in ipairs(MapMarks.SPAWN_SPACINGS) do
            -- (every spawn, the finest step, while the map is close enough for a spawn's own icon at 12 yards)
            local yards = spacing > 0 and spacing or 12
            if yards * perYard >= minPixels then
                return spacing
            end
        end
        return MapMarks.SPAWN_SPACINGS[#MapMarks.SPAWN_SPACINGS]
    end
    if not pixelsPerYard or pixelsPerYard <= 0 then
        return current or 0
    end
    local chosen = choose(pixelsPerYard)
    if current and chosen ~= current then
        -- Only once past the edge by the slack, whichever way the zoom went
        local further =
            choose(chosen < current and pixelsPerYard / SPAWN_SPACING_SLACK or pixelsPerYard * SPAWN_SPACING_SLACK)
        if further ~= chosen then
            return current
        end
    end
    return chosen
end

---Areas as composeAreas gives them, but from the world: grouped once in yards (getWorldAreas), the mark on each
---area's anchor spawn. So a quest's mark stays on one spot at every zoom, in every view, on every map that shows it;
---the map only decides which of its points are drawn. Points without a place in the world (inside a dungeon)
---are grouped on the map as before.
---@param points { x: number, y: number, place: table }[] From composePoints
---@return table[] areas Largest first (in the world), each with x, y (its anchor), radiusX, radiusY, centroidX, centroidY, points
function MapMarks.composeStableAreas(points)
    local places, loose, placeIndexOf = {}, {}, {}
    for _, point in ipairs(points) do
        if point.place and getWorldPlace(point.place) then
            places[#places + 1] = point.place
            placeIndexOf[point] = #places
        else
            loose[#loose + 1] = point
        end
    end
    local areas = {}
    if #places > 0 then
        local world = getWorldAreas(places)
        local groups = {}
        for _, point in ipairs(points) do
            local index = placeIndexOf[point] and world.areaOf[placeIndexOf[point]]
            if index then
                groups[index] = groups[index] or {}
                table.insert(groups[index], point)
            end
        end
        local order = {}
        for index in pairs(groups) do
            order[#order + 1] = index
        end
        table.sort(order, function(first, second)
            if world.sizes[first] ~= world.sizes[second] then
                return world.sizes[first] > world.sizes[second]
            end
            return first < second
        end)
        for _, index in ipairs(order) do
            local group = groups[index]
            local anchorIndex = world.anchors[index]
            local anchor
            local minX, maxX, minY, maxY, sumX, sumY = math.huge, -math.huge, math.huge, -math.huge, 0, 0
            for _, point in ipairs(group) do
                anchor = placeIndexOf[point] == anchorIndex and point or anchor
                minX, maxX = math.min(minX, point.x), math.max(maxX, point.x)
                minY, maxY = math.min(minY, point.y), math.max(maxY, point.y)
                sumX, sumY = sumX + point.x, sumY + point.y
            end
            if not anchor then
                -- Its anchor is not on this map (the area runs over a zone's edge): the point of it nearest its middle here
                local middleX, middleY, nearest = sumX / #group, sumY / #group, math.huge
                for _, point in ipairs(group) do
                    local distance = (point.x - middleX) ^ 2 + (point.y - middleY) ^ 2
                    if distance < nearest then
                        anchor, nearest = point, distance
                    end
                end
            end
            areas[#areas + 1] = {
                points = group,
                x = anchor.x,
                y = anchor.y,
                centroidX = anchor.x,
                centroidY = anchor.y,
                shadeX = (minX + maxX) / 2,
                shadeY = (minY + maxY) / 2, -- the shading round the whole area
                radiusX = math.max((maxX - minX) / 2 + AREA_PADDING, MIN_AREA_RADIUS),
                radiusY = math.max((maxY - minY) / 2 + AREA_PADDING, MIN_AREA_RADIUS),
            }
        end
    end
    for _, area in ipairs(#loose > 0 and MapMarks.composeAreas(loose) or {}) do
        areas[#areas + 1] = area
    end
    return areas
end

local ZONE_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3

---Whether a place belongs on a map. A zone's map also shows the edges of its neighbours, and a place over
---there could be drawn on it; it is left out, since that part of the quest belongs to the other zone and is
---marked on that zone's own map. Continent and world maps, which belong to no single zone, show everything.
local function isOnMapZone(place, mapId)
    -- A map another addon joins its neighbours onto (OpenMap) shows every zone in view, each where it is
    if ns.MapPins.isViewJoined() then
        return true
    end
    -- The database gives continents and the world an area of their own, so the game is asked what kind of
    -- map this is: only a zone's map, or one inside it, is limited to its own places
    local info = C_Map.GetMapInfo and ns.Database.getMapInfo(mapId)
    if info and info.mapType and info.mapType < ZONE_MAP_TYPE then
        return true
    end
    local areaId = ns.Database.getAreaId(mapId)
    if not areaId then
        return true
    end
    -- A dungeon's entrance is drawn in the zone it stands in, though its quest is filed under the dungeon
    return (place.mapZoneId or place.groupZoneId) == ns.Database.getParentZoneId(areaId)
end

---@return number? zoneId The zone a place is listed under, as zones are told apart here (a dungeon's entrance:
---the zone it stands in)
local function getPlaceZone(place)
    local zoneId = place.mapZoneId or place.groupZoneId or place.zoneId
    return zoneId and ns.Database.getParentZoneId(zoneId) or zoneId
end

---On a map that joins zones together (OpenMap), the zones a list of places is listed under, when more than one:
---the quest database often lists the same spawns twice near a border, once in each zone's map, and joined up both
---would be drawn, a few pixels apart. nil when there is no such doubling to look out for.
---@param zoneIds (number|nil)[] Each place's zone
---@return table<number, boolean>? listedZones
local function getListedZones(zoneIds)
    if not ns.MapPins.isViewJoined() then
        return nil
    end
    local listed, count = {}, 0
    for _, zoneId in pairs(zoneIds) do
        if zoneId and not listed[zoneId] then
            listed[zoneId] = true
            count = count + 1
        end
    end
    return count > 1 and listed or nil
end

---Whether a place is the other zone's copy of a spawn: its point lies in another zone's land, and that zone lists
---its own copy (listedZones). A place over the border with no copy there (a patrol walking across it) is kept.
local function isShadowed(zoneId, x, y, mapId, listedZones)
    if not listedZones or not zoneId then
        return false
    end
    local view = ns.MapPins.getView()
    if not view or not view.getZoneMapIdAt then
        return false
    end
    local isFine, zoneMapId = pcall(view.getZoneMapIdAt, mapId, x, y)
    local areaId = isFine and type(zoneMapId) == "number" and ns.Database.getAreaId(zoneMapId)
    local zoneUnder = areaId and ns.Database.getParentZoneId(areaId)
    return zoneUnder ~= nil and zoneUnder ~= zoneId and listedZones[zoneUnder] == true
end

local function composePoints(places, mapId)
    local points = {}
    local placeZones = {}
    for index, place in ipairs(places) do
        placeZones[index] = getPlaceZone(place)
    end
    local listedZones = getListedZones(placeZones)
    for index, place in ipairs(places) do
        local x, y
        if isOnMapZone(place, mapId) then
            x, y = ns.MapPins.getMapPosition(place, mapId)
        end
        if x and isShadowed(placeZones[index], x, y, mapId, listedZones) then
            x, y = nil, nil
        end
        if x then
            points[#points + 1] =
                { x = x, y = y, dungeonName = place.dungeonName, zoneId = place.groupZoneId, place = place }
        end
    end
    return points
end

-- A tracked quest's spawns on a map, and its areas, kept from one drawing to the next: every drawing (a hover, the
-- focus moving, the map opened again, the minimap walked on) worked them all out anew, a table for every spawn of
-- every quest, most of a drawing's garbage. Kept by quest, objective and map, while where quests lead stays what it
-- was (Model.getWordsGeneration: the words of quests, the sources of their data, a dungeon learned) and the dungeons
-- with it. On a map another addon joins its neighbours onto (OpenMap) what is in view decides too: kept for that view
-- (MapPins.getViewKey), which a kill or a hover leaves as it was and a pan or a zoom does not; only the latest such
-- view's are kept, beside the game's own maps'. The points are shared by the drawings: what a drawing sets on them
-- (the icon, the shade of the quest in focus, the quest) it sets every time.
local keptByView, keptGeneration, keptDungeons, joinedViewKey = {}, nil, nil, nil
local MAX_KEPT_OBJECTIVES = 300 -- objectives a store keeps (quests tracked over a long evening, the maps crossed) before starting afresh

local function newKeptStore()
    -- points: [quest:kind:index:map] = { points, areas }; places: [a list of places kept itself (a step's)] = { [map] = areas }
    return { points = {}, count = 0, places = setmetatable({}, { __mode = "k" }) }
end

---@return table? store What is kept for the view the marks are being worked out for; nil when nothing is kept
local function getKeptStore()
    if ns.frameNumber == 0 then
        return nil -- (in the tests, where no frames run, every drawing works them out)
    end
    local generation, dungeons = ns.Model.getWordsGeneration(), ns.Database.getDungeonsVersion()
    if generation ~= keptGeneration or dungeons ~= keptDungeons then
        keptByView, keptGeneration, keptDungeons, joinedViewKey = {}, generation, dungeons, nil
    end
    local viewKey = ns.MapPins.getViewKey() or ""
    local store = keptByView[viewKey]
    if not store then
        if viewKey ~= "" then
            if joinedViewKey then
                keptByView[joinedViewKey] = nil -- (a view panned or zoomed away from: let go)
            end
            joinedViewKey = viewKey
        end
        store = newKeptStore()
        keptByView[viewKey] = store
    end
    return store
end

---@return table[] points, table[] areas An objective's spawns on a map (composePoints) and its areas (composeStableAreas)
local function getObjectivePoints(questId, objectiveType, typeIndex, mapId)
    local store = getKeptStore()
    local key = store and (questId .. ":" .. objectiveType .. ":" .. typeIndex .. ":" .. mapId)
    local kept = store and store.points[key]
    if not kept then
        local points = composePoints((ns.Location.getObjectiveInfo(questId, objectiveType, typeIndex)), mapId)
        kept = { points = points, areas = MapMarks.composeStableAreas(points) }
        if store then
            if store.count >= MAX_KEPT_OBJECTIVES then
                store.points, store.count = {}, 0
            end
            store.points[key] = kept
            store.count = store.count + 1
        end
    end
    return kept.points, kept.areas
end

---@return table[] areas The areas of a list of places that is kept itself (a quest's step, Model), on a map
local function getPlaceAreas(places, mapId)
    local store = places and getKeptStore()
    local byMap = store and store.places[places]
    if store and not byMap then
        byMap = {}
        store.places[places] = byMap
    end
    local areas = byMap and byMap[mapId]
    if not areas then
        areas = MapMarks.composeStableAreas(composePoints(places, mapId))
        if byMap then
            byMap[mapId] = areas
        end
    end
    return areas
end

---@class MapMark
---@field kind string "objective", "turnIn" or "giver"
---@field x number Fraction of the map's width
---@field y number Fraction of the map's height
---@field questId number
---@field isFocused boolean Belongs to the quest in focus
---@field isPreview boolean? The turn-in of a quest not accepted yet, shown for the quest selected on the Available tab
---@field number number? The quest's number in the tracker; nil for a quest that is not tracked
---@field progress number? How far along the quest is, 0 to 1
---@field labels { text: string, glyph: string }[]? What to do there, on the main marks of the quest in focus
---@field areas table[]? Shaded regions, each with x, y, radiusX and radiusY, for the quest in focus
---@field points table[]? Spawn points to dot, for the quest in focus
---@field lines string[] Tooltip lines

---How far along a quest is, from 0 to 1: the average of its objectives.
function MapMarks.getProgress(entry)
    local sum = 0
    for _, objective in ipairs(entry.objectives) do
        sum = sum
            + (
                objective.required > 0 and math.min(objective.fulfilled / objective.required, 1)
                or (objective.isFinished and 1 or 0)
            )
    end
    return #entry.objectives > 0 and sum / #entry.objectives or 0
end

---@return table copy A list's items in a new list (a loop, as a quest may have more spawns than unpack takes)
local function copyList(list)
    local copy = {}
    for index = 1, #list do
        copy[index] = list[index]
    end
    return copy
end

---Adds a mark of the quest in focus. Two objectives in nearly the same spot would sit on top of each other,
---so a mark close to an earlier one of the quest joins it: one mark, both labels, both shaded areas.
local function addFocusedMark(marks, mark, firstIndex)
    for markIndex = firstIndex, #marks do
        local other = marks[markIndex]
        if math.abs(other.x - mark.x) <= MERGE_DISTANCE and math.abs(other.y - mark.y) <= MERGE_DISTANCE then
            for _, label in ipairs(mark.labels) do
                other.labels[#other.labels + 1] = label
            end
            for _, area in ipairs(mark.areas) do
                other.areas[#other.areas + 1] = area
            end
            for _, point in ipairs(mark.points) do
                other.points[#other.points + 1] = point
            end
            for _, point in ipairs(mark.spawnPoints or {}) do
                other.spawnPoints[#other.spawnPoints + 1] = point
            end
            for _, circle in ipairs(mark.roughCircles or {}) do
                other.roughCircles[#other.roughCircles + 1] = circle -- (a rough mark joins only another: Spoilers)
            end
            other.lines[#other.lines + 1] = mark.lines[2]
            for _, counted in ipairs(mark.counted or {}) do
                counted.lineIndex = #other.lines
                other.counted[#other.counted + 1] = counted
            end
            return
        end
    end
    marks[#marks + 1] = mark
end

---How a quest's open objectives are coloured on the map, and so on its page. With more than one objective left,
---each has its own shade. With one left, an item that several creatures drop, each creature has its own shade
---instead, so it is plain who drops it where.
---@return table<number, number?> shades By objective index; nil is the quest's one blue
---@return DropZone[]? zones For the one objective coloured by creature: where its item drops (Drops.getZones)
---@return number? sourceObjectiveIndex That objective
function MapMarks.getObjectiveShades(entry)
    local openCount = 0
    for _, objective in ipairs(entry.objectives or {}) do
        openCount = openCount + (objective.isFinished and 0 or 1)
    end
    local shades, typeIndexes, shadeIndex = {}, {}, 0
    for index, objective in ipairs(entry.objectives or {}) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if not objective.isFinished then
            shadeIndex = shadeIndex + 1
            shades[index] = openCount > 1 and ((shadeIndex - 1) % #QUEST_SHADES + 1) or nil
            if openCount == 1 and objective.type == "item" then
                local target = ns.Location.getObjectiveTarget(entry.questId, "item", typeIndexes.item)
                local zones = target and target.itemId and ns.Drops.getZones(target.itemId)
                local creatureCount = 0
                for _, zone in ipairs(zones or {}) do
                    creatureCount = creatureCount + #zone.sources
                end
                if creatureCount > 1 then
                    return shades, zones, index
                end
            end
        end
    end
    return shades
end

---@return string text An objective as a mark's tooltip says it: its words, how far along it is, and the dungeon
---it is inside
local function getObjectiveText(objective, dungeonName)
    local text = (objective.shownLabel or objective.label)
        .. (objective.required > 1 and string.format(" %d/%d", objective.fulfilled, objective.required) or "")
    return dungeonName and ns.L("%s (in %s)", text, dungeonName) or text
end

---What a mark says of its quest's counts, brought up to date: how far along the quest is, and each objective's
---line and row ("Kobolds slain 3/8"). The maps' marks stay as drawn while only counts change (a kill, a loot: no
---mark, icon or area moves for it), so their words are read from the quest as it stands when they are asked for,
---as a tooltip opens. A dungeon's mark: each of its quests' marks.
function MapMarks.refreshMarkTexts(mark)
    for _, member in ipairs(mark.members or {}) do
        MapMarks.refreshMarkTexts(member)
    end
    if not mark.counted or not mark.questId or not ns.QuestState.isInLog(mark.questId) then
        return
    end
    local quest = ns.QuestState.getQuest(mark.questId)
    mark.progress = MapMarks.getProgress(quest)
    for _, counted in ipairs(mark.counted) do
        local objective = quest.objectives[counted.objectiveIndex]
        if objective then
            local text = getObjectiveText(objective, counted.dungeonName)
            if counted.lineIndex and mark.lines[counted.lineIndex] ~= nil then
                mark.lines[counted.lineIndex] = text
            end
            if counted.label then
                counted.label.text = text
            end
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- What the player chose to be shown (Spoilers.lua): quests to pick up, where objectives are, where to hand in, what
-- drops the items, dungeons. A composing asks once whether anything is held back at all (MapMarks.getSpoilers): in
-- Guide, the default, the answer is no and nothing below runs.

local NONE = {}
local isPeeking = false -- Alt held over the world map: everything shown there for a moment (MapHover)

---Alt held over the world map shows everything there, as Guide does, until it is let go (MapHover).
function MapMarks.setPeeking(isOn)
    isPeeking = isOn == true
end

---@return boolean isPeeking Alt is held over the world map: it shows everything for now
function MapMarks.isPeeking()
    return isPeeking
end

---@param isPeekIgnored boolean? For the minimap, the zone map and the waypoint, which a peek at the world map leaves
---as they are
---@return table? spoilers ns.Spoilers while something is held back for this drawing; nil when everything is shown
function MapMarks.getSpoilers(isPeekIgnored)
    local spoilers = ns.Spoilers
    if not spoilers or not spoilers.isActive() or (isPeeking and not isPeekIgnored) then
        return nil
    end
    return spoilers
end

---@return boolean isExact The player climbed the hint ladder to its top for this quest: everything of it shows, the
---map's fog too
local function isExactHint(spoilers, questId)
    return questId ~= nil and spoilers.getHint(questId) >= spoilers.HINT_EXACT
end

---@return boolean isSeen The place lies in land the player has explored (the map's fog). A place with no spot of its
---own (inside an instance) is never in fog.
local function isPlaceUnfogged(spoilers, place)
    if not place or not place.zoneId or not place.x or place.x < 0 then
        return true
    end
    return spoilers.isExplored(place.zoneId, place.x, place.y)
end

---@param places table[] Places, or points that carry their place
---@return boolean isSeen Any of them lies in explored land, or the quest's hint shows it exactly
local function isAnyUnfogged(spoilers, questId, places)
    if isExactHint(spoilers, questId) then
        return true
    end
    for _, item in ipairs(places) do
        if isPlaceUnfogged(spoilers, item.place or item) then
            return true
        end
    end
    return false
end

---@return boolean isShown A dungeon may be named and its quests shown: by the player's choice of dungeons (shown, those
---entered, hidden), a hint for the quest lifting it
function MapMarks.isDungeonShown(spoilers, dungeonId, questId)
    if not spoilers or not dungeonId then
        return true
    end
    local choice = spoilers.get("dungeons", questId)
    return choice == "shown" or (choice == "entered" and spoilers.hasEntered(dungeonId))
end

---@return boolean isMet Someone the quest is had from was met: an NPC who gives it talked to or targeted, or the item it
---starts from seen to drop, or a creature that drops it killed. A quest from an object alone (a poster, a book) needs
---no meeting: it stands there to be seen, and the map's fog decides.
local function isStarterMet(spoilers, questId)
    local startedBy = ns.Database.getQuestField(questId, "startedBy")
    if type(startedBy) ~= "table" then
        return true
    end
    local hasSomeone = false
    for _, npcId in ipairs(startedBy[1] or NONE) do
        hasSomeone = true
        if spoilers.hasMet(npcId) then
            return true
        end
    end
    for _, itemId in ipairs(startedBy[3] or NONE) do
        hasSomeone = true
        if spoilers.hasSeenDrop(itemId) then
            return true
        end
        for _, npcId in ipairs(ns.Database.getItemField(itemId, "npcDrops") or NONE) do
            if spoilers.hasKilled(npcId) then
                return true
            end
        end
    end
    return not hasSomeone
end

---@return boolean isShown A quest to pick up may have its "!" at all, by the player's choice: all of them, those whose
---giver was met, none
function MapMarks.isGiverQuestShown(spoilers, questId)
    if not spoilers then
        return true
    end
    local choice = spoilers.get("pickup", questId)
    if choice == "none" then
        return false
    end
    return choice ~= "met" or isStarterMet(spoilers, questId)
end

---@return boolean isShown One place where a quest starts may have its "!": not in the map's fog, and not inside a
---dungeon held back
function MapMarks.isGiverPlaceShown(spoilers, questId, place)
    if not spoilers then
        return true
    end
    if place.dungeonZoneId and not MapMarks.isDungeonShown(spoilers, place.dungeonZoneId, questId) then
        return false
    end
    return isExactHint(spoilers, questId) or isPlaceUnfogged(spoilers, place)
end

---@param points table[] An area's points, each with its place
---@return boolean isShown An area where a quest starts may have its "!": a place of it may (MapMarks.isGiverPlaceShown)
local function isGiverAreaShown(spoilers, questId, points)
    for _, point in ipairs(points) do
        if MapMarks.isGiverPlaceShown(spoilers, questId, point.place or point) then
            return true
        end
    end
    return false
end

---@return boolean isShown Where a quest is handed in may be shown, by the player's choice (shown, once its NPC was met,
---hidden), a hint lifting it: as the tracker and the quest page tell it (Model.isTurnInShown)
function MapMarks.isTurnInShown(spoilers, questId)
    return not spoilers or ns.Model.isTurnInShown(questId)
end

---@return string choice What of an item's drops may be said: "chances" (who, and how often), "names" (who), "found"
---(only who dropped it for the player), "hidden"
function MapMarks.getDropsChoice(spoilers, questId)
    return spoilers and spoilers.get("drops", questId) or "chances"
end

---@return boolean isNamed Who drops what may be named, so spawns may be coloured by creature
local function isDropNamed(spoilers, questId)
    local choice = MapMarks.getDropsChoice(spoilers, questId)
    return choice == "chances" or choice == "names"
end

local MAX_DROP_NAMES = 3

---@return string? text Who drops an item, as far as the player chose to know ("Dropped by Greater Plainstrider"), with
---the chances only when chosen; nil when nothing may be said
local function getDropText(spoilers, questId, itemId)
    local choice = MapMarks.getDropsChoice(spoilers, questId)
    if choice == "hidden" then
        return nil
    end
    local zone = ns.Drops.getZones(itemId)[1]
    local names = {}
    for _, source in ipairs(zone and zone.sources or NONE) do
        if #names >= MAX_DROP_NAMES then
            break
        end
        if choice ~= "found" or spoilers.hasSeenDrop(itemId, source.npcId or source.objectId) then
            local chance = choice == "chances" and source.chance and ns.Drops.formatChance(source.chance)
            names[#names + 1] = source.name .. (chance and (" " .. chance) or "")
        end
    end
    return #names > 0 and ns.L("Dropped by %s", table.concat(names, ", ")) or nil
end

-- Explorer's places: where the player saw an objective move on (Spoilers.getFoundPlaces), read only and saved; the
-- maps use copies, which they may add to (a place's world position is kept on it), filed under their zone as quest
-- places are
local foundCopies = setmetatable({}, { __mode = "k" })

---@return table[] places Where the player found this objective, those out of the map's fog, as quest places are
local function getFoundPlaces(spoilers, questId, objectiveIndex)
    local found = {}
    local isExact = isExactHint(spoilers, questId)
    for _, place in ipairs(spoilers.getFoundPlaces(questId, objectiveIndex)) do
        if isExact or isPlaceUnfogged(spoilers, place) then
            local copy = foundCopies[place]
            if not copy then
                copy = {
                    zoneId = place.zoneId,
                    groupZoneId = ns.Database.getParentZoneId(place.zoneId),
                    x = place.x,
                    y = place.y,
                    isFound = true,
                }
                foundCopies[place] = copy
            end
            found[#found + 1] = copy
        end
    end
    return found
end

-- "Rough" (Spoilers): a dashed circle round each area of an objective's places instead of its spawns and shapes. Its
-- middle is moved off the area's own middle by a step fixed by the quest, so the circle does not give the middle away,
-- and its reach covers the whole area with room to spare.
local ROUGH_MIN_YARDS = 90 -- a circle is never smaller round than this: a lone spawn's would point at it
local ROUGH_REACH_YARDS = 40 -- how far past an area's outermost places it reaches, before the step
local ROUGH_SHIFT = 0.45 -- the step off the area's middle, a share of its size
local ROUGH_CACHE_LIMIT = 200 -- objectives' circles kept; the cache starts over past this
local roughCache, roughCacheCount = {}, 0
local zoneYards = {} -- [uiMapId] = { width, height } of its map in yards, or false where the game gives none

---@return number width, number height A zone map's size in the world's yards (a guess where the game gives none)
local function getZoneYards(uiMapId)
    local yards = uiMapId and zoneYards[uiMapId]
    if yards == nil and uiMapId then
        local _, north, west = ns.Geometry.getWorldPosition(uiMapId, 0, 0)
        local _, southNorth, eastWest = ns.Geometry.getWorldPosition(uiMapId, 100, 100)
        yards = north
                and southNorth
                and west - eastWest > 0
                and north - southNorth > 0
                and { west - eastWest, north - southNorth }
            or false
        zoneYards[uiMapId] = yards
    end
    if not yards then
        return DEFAULT_ZONE_YARDS, DEFAULT_ZONE_YARDS * 2 / 3
    end
    return yards[1], yards[2]
end

---@return table[] circles An objective's rough circles, one for each of its places' areas (grouped in the world, as the
---map groups them), largest first: each { place = its middle (zoneId, x, y 0-100, as quest places are), radiusYards,
---size = how many places it holds, places = those places }. Worked out once for an objective's places; read only.
function MapMarks.getRoughCircles(questId, objectiveIndex, places)
    places = places or NONE
    local key = questId .. ":" .. objectiveIndex .. ":" .. getPlacesKey(places)
    local cached = roughCache[key]
    if cached then
        return cached
    end
    local circles = {}
    local world = #places > 0 and getWorldAreas(places) or nil
    local members = {}
    for placeIndex, index in pairs(world and world.areaOf or NONE) do
        members[index] = members[index] or {}
        table.insert(members[index], places[placeIndex])
    end
    for index, list in ipairs(members) do
        local anchor = places[world.anchors[index]]
        local uiMapId = ns.Database.getUiMapId(anchor.zoneId)
        -- How far the area reaches on its anchor's own map (places over a zone's edge left out of the measure)
        local minX, maxX, minY, maxY = anchor.x, anchor.x, anchor.y, anchor.y
        for _, place in ipairs(list) do
            if place.x and place.x >= 0 and ns.Database.getUiMapId(place.zoneId) == uiMapId then
                minX, maxX = math.min(minX, place.x), math.max(maxX, place.x)
                minY, maxY = math.min(minY, place.y), math.max(maxY, place.y)
            end
        end
        local widthYards, heightYards = getZoneYards(uiMapId)
        local halfWidth, halfHeight = (maxX - minX) / 2 * widthYards / 100, (maxY - minY) / 2 * heightYards / 100
        local reach =
            math.max(math.sqrt(halfWidth * halfWidth + halfHeight * halfHeight) + ROUGH_REACH_YARDS, ROUGH_MIN_YARDS)
        -- The step's direction, from where the area is alone: the same in every session, and the same for every
        -- objective and every quest hunting there, so their circles lie on one another (a fan of circles shifted
        -- each its own way was clutter, and where they all overlapped gave the middle away)
        local seed = (anchor.zoneId or 0) * 12.9898
            + math.floor(anchor.x + 0.5) * 78.233
            + math.floor(anchor.y + 0.5) * 37.719
        local angle = ((math.sin(seed) * 43758.5453) % 1) * 2 * math.pi
        local shift = reach * ROUGH_SHIFT
        local x = (minX + maxX) / 2 + shift * math.cos(angle) / widthYards * 100
        local y = (minY + maxY) / 2 - shift * math.sin(angle) / heightYards * 100
        circles[#circles + 1] = {
            place = {
                zoneId = anchor.zoneId,
                groupZoneId = anchor.groupZoneId,
                mapZoneId = anchor.mapZoneId,
                x = math.max(0, math.min(100, x)),
                y = math.max(0, math.min(100, y)),
                dungeonName = anchor.dungeonName,
                dungeonZoneId = anchor.dungeonZoneId,
            },
            radiusYards = reach + shift,
            size = world.sizes[index],
            places = list,
            order = index,
        }
    end
    table.sort(circles, function(first, second)
        if first.size ~= second.size then
            return first.size > second.size
        end
        return first.order < second.order
    end)
    if roughCacheCount >= ROUGH_CACHE_LIMIT then
        roughCache, roughCacheCount = {}, 0
    end
    roughCache[key] = circles
    roughCacheCount = roughCacheCount + 1
    return circles
end

---@return boolean isSeen A rough circle may be drawn: some of its area lies out of the map's fog (kept on the circle
---until anything the player found or chose changes, Spoilers.getKey)
local function isCircleSeen(spoilers, questId, circle)
    local key = spoilers.getKey()
    if circle.seenKey ~= key then
        circle.seenKey, circle.isSeen = key, isAnyUnfogged(spoilers, questId, circle.places)
    end
    return circle.isSeen
end

---@return { x: number, y: number, radius: number, zoneId: number? }? circle A rough circle on a map: its middle in
---fractions of the map, its radius a fraction of the map's width; nil when its middle is not on this map
local function placeRoughCircle(circle, mapId)
    local point = composePoints({ circle.place }, mapId)[1]
    local mapYards = point and MapMarks.getMapYards and MapMarks.getMapYards(mapId)
    if not point or not mapYards then
        return nil
    end
    return { x = point.x, y = point.y, radius = circle.radiusYards / mapYards, zoneId = point.zoneId }
end

local HIDDEN_STEP = { isHidden = true, places = NONE, spawns = NONE } -- (shared: read only)

---@return boolean isInside Every place of what is left of the quest is inside a dungeon (placed at its entrances)
local function isLeftInDungeons(entry)
    local typeIndexes, isAny = {}, false
    for _, objective in ipairs(entry.objectives or NONE) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if not objective.isFinished then
            for _, place in
                ipairs(ns.Location.getObjectiveInfo(entry.questId, objective.type, typeIndexes[objective.type]) or NONE)
            do
                if not place.dungeonZoneId then
                    return false
                end
                isAny = true
            end
        end
    end
    return isAny
end

---@return string choice Where a quest's objectives show (Spoilers): "rough" is "exact" for one done inside a dungeon,
---whose only place on the map is the entrance; that says no more than "in this dungeon" (the Dungeons choice decides
---whether the dungeon shows at all), and circles round an entrance said nothing
local function getObjectivesChoice(spoilers, entry)
    local choice = spoilers.get("objectives", entry.questId)
    if choice == "rough" and isLeftInDungeons(entry) then
        return "exact"
    end
    return choice
end

---What of a quest's step may be shown while something is held back, for the minimap (the world map
---draws the same from MapMarks.compose).
---@return table? step nil when all of it shows as it is. Else { isHidden = nothing of it shows, places = where its
---pointer may lead (the rough circles' middles, the places found), spawns = places to mark (found),
---circles = its rough circles (rough only) }
function MapMarks.getShownStep(entry, spoilers)
    if not spoilers then
        return nil
    end
    local questId = entry.questId
    if entry.isTurnIn or entry.eventText then
        return not MapMarks.isTurnInShown(spoilers, questId) and HIDDEN_STEP or nil
    end
    local choice = getObjectivesChoice(spoilers, entry)
    if choice == "exact" then
        return nil
    elseif choice == "hidden" then
        return HIDDEN_STEP
    end
    local step = { places = {}, spawns = {}, circles = choice == "rough" and {} or nil }
    local typeIndexes = {}
    for objectiveIndex, objective in ipairs(entry.objectives or NONE) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if not objective.isFinished then
            if step.circles then
                local places = ns.Location.getObjectiveInfo(questId, objective.type, typeIndexes[objective.type])
                for _, circle in ipairs(MapMarks.getRoughCircles(questId, objectiveIndex, places)) do
                    if isCircleSeen(spoilers, questId, circle) then
                        step.circles[#step.circles + 1] = circle
                        step.places[#step.places + 1] = circle.place
                    end
                end
            else
                for _, place in ipairs(getFoundPlaces(spoilers, questId, objectiveIndex)) do
                    step.places[#step.places + 1] = place
                    step.spawns[#step.spawns + 1] = place
                end
            end
        end
    end
    step.isHidden = #step.places == 0
    return step
end

---"Rough": the quest's marks at the middles of its rough circles, each saying "Somewhere here" and who drops the item
---as far as the player chose, and no spawn or exact area. Out of focus one mark, every circle drawn.
local function addRoughMarks(marks, entry, mapId, isFocused, number, spoilers, title)
    local typeIndexes, quiet, samePlace = {}, {}, {}
    local firstFocusedMark = #marks + 1
    local progress = MapMarks.getProgress(entry)
    local somewhere = ns.L("Somewhere here")
    for objectiveIndex, objective in ipairs(entry.objectives) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if not objective.isFinished then
            local typeIndex = typeIndexes[objective.type]
            local glyph = MapMarks.getObjectiveGlyph(objective)
            local dropText
            if objective.type == "item" then
                local target = ns.Location.getObjectiveTarget(entry.questId, "item", typeIndex)
                dropText = target and target.itemId and getDropText(spoilers, entry.questId, target.itemId)
            end
            local places = ns.Location.getObjectiveInfo(entry.questId, objective.type, typeIndex)
            for _, circle in ipairs(MapMarks.getRoughCircles(entry.questId, objectiveIndex, places)) do
                local placed = isCircleSeen(spoilers, entry.questId, circle) and placeRoughCircle(circle, mapId)
                local text = placed and getObjectiveText(objective, circle.place.dungeonName)
                -- Another objective's circle in the same spot (the same creatures, the same area): one mark for both
                local same = placed and samePlace[string.format("%.1f:%.1f", placed.x * 100, placed.y * 100)]
                if same then
                    table.insert(same.lines, 2, text)
                    for _, line in ipairs(same.counted) do
                        line.lineIndex = line.lineIndex + 1
                    end
                    same.counted[#same.counted + 1] =
                        { objectiveIndex = objectiveIndex, dungeonName = circle.place.dungeonName, lineIndex = 2 }
                    if same.labels and isFocused then
                        same.labels[#same.labels + 1] = { text = text, glyph = glyph }
                    end
                    same.roughCircles[1].radius = math.max(same.roughCircles[1].radius, placed.radius)
                    placed = nil
                end
                if placed then
                    local mark = {
                        kind = "objective",
                        x = placed.x,
                        y = placed.y,
                        questId = entry.questId,
                        isFocused = isFocused,
                        glyph = glyph,
                        zoneId = placed.zoneId or entry.zoneId,
                        number = number,
                        progress = progress,
                        isRough = true,
                        lines = { title, text, somewhere, dropText },
                        -- (no spawns and no areas: the circle is all there is to see)
                        labels = {},
                        areas = {},
                        points = {},
                        roughCircles = { placed },
                        size = circle.size,
                        counted = {
                            { objectiveIndex = objectiveIndex, dungeonName = circle.place.dungeonName, lineIndex = 2 },
                        },
                    }
                    samePlace[string.format("%.1f:%.1f", placed.x * 100, placed.y * 100)] = mark
                    if isFocused then
                        mark.labels[1] = { text = text, glyph = glyph }
                        mark.counted[1].label = mark.labels[1]
                        addFocusedMark(marks, mark, firstFocusedMark)
                    else
                        quiet[#quiet + 1] = mark
                    end
                end
            end
        end
    end
    if #quiet > 0 then
        local largest, circles = quiet[1], {}
        for _, mark in ipairs(quiet) do
            if mark.size > largest.size then
                largest = mark
            end
            circles[#circles + 1] = mark.roughCircles[1]
        end
        largest.roughCircles, largest.labels, largest.areas, largest.points = circles, nil, nil, nil
        marks[#marks + 1] = largest
    end
end

local function addQuestMarks(marks, entry, mapId, isFocused, number, spoilers)
    local title = string.format("[%d] %s", entry.level, entry.title)
    if entry.isTurnIn or entry.eventText then
        if spoilers and not MapMarks.isTurnInShown(spoilers, entry.questId) then
            return -- (where to hand in, held back)
        end
        -- At the NPC: to hand the quest in, or for a quest with nothing to do but be there (waiting, talking)
        local areas = getPlaceAreas(entry.places, mapId)
        local text = entry.eventText or ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver"))
        if areas[1] then
            marks[#marks + 1] = {
                kind = entry.isTurnIn and "turnIn" or "objective",
                x = areas[1].centroidX,
                y = areas[1].centroidY,
                questId = entry.questId,
                isFocused = isFocused,
                glyph = "talk", -- nothing to do but be there
                zoneId = areas[1].points[1].zoneId or entry.zoneId,
                number = number,
                progress = entry.isTurnIn and 1 or 0,
                labels = isFocused and { { text = text, glyph = entry.isTurnIn and "tick" or "use" } } or {},
                lines = { title, text },
            }
        end
        return
    end

    -- Where the objectives are, as the player chose (Spoilers): exact (below), rough circles, where found, nothing
    local choice = spoilers and getObjectivesChoice(spoilers, entry) or "exact"
    if choice == "hidden" then
        return
    elseif choice == "rough" then
        addRoughMarks(marks, entry, mapId, isFocused, number, spoilers, title)
        return
    end
    local foundNote = choice == "found" and ns.L("Found by you") or nil -- (only the places found: Explorer)
    local typeIndexes, quietAreas = {}, {}
    local firstFocusedMark = #marks + 1
    local progress = MapMarks.getProgress(entry)
    -- With more than one objective left, each gets its own shade of blue, its tooltip row the same shade, so
    -- it is plain which patches belong to which; one item left that several creatures drop: a shade each
    local shades, dropZones, sourceObjectiveIndex = {}, nil, nil
    if isFocused then
        shades, dropZones, sourceObjectiveIndex = MapMarks.getObjectiveShades(entry)
        if spoilers and (foundNote or not isDropNamed(spoilers, entry.questId)) then
            dropZones, sourceObjectiveIndex = nil, nil -- (who drops it is not to be told by their colours)
        end
    end
    for objectiveIndex, objective in ipairs(entry.objectives) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if not objective.isFinished then
            local shade = shades[objectiveIndex]
            local isBySource = objectiveIndex == sourceObjectiveIndex
            local points, sourceLabels, areas
            if isBySource then
                points, sourceLabels =
                    MapMarks.composeSourcePoints(dropZones, mapId, MapMarks.getDropsChoice(spoilers, entry.questId))
            elseif foundNote then
                points = composePoints(getFoundPlaces(spoilers, entry.questId, objectiveIndex), mapId)
                for _, point in ipairs(points) do
                    point.note = foundNote -- (for its spawn mark's tooltip)
                end
            else
                points, areas = getObjectivePoints(entry.questId, objective.type, typeIndexes[objective.type], mapId)
            end
            areas = areas or MapMarks.composeStableAreas(points)
            local glyph = MapMarks.getObjectiveGlyph(objective)
            for _, point in ipairs(points) do
                point.glyph = glyph -- the icon of what to do there
                if not isBySource then
                    point.shade = nil -- (kept points: the shade of the quest in focus, set below, only while it is)
                end
            end
            for areaIndex, area in ipairs(areas) do
                -- A mark at a dungeon's entrance says which dungeon the objective is inside
                local dungeonName = area.points[1].dungeonName
                local text = getObjectiveText(objective, dungeonName)
                if isFocused then
                    if not isBySource then
                        for _, point in ipairs(area.points) do
                            point.shade = shade
                        end
                    end
                    -- The objective's row, then, when coloured by creature, a row for each creature and its chance
                    local labels = {}
                    if areaIndex == 1 then
                        labels[1] = { text = text, glyph = glyph, shade = shade }
                        for _, label in ipairs(sourceLabels or {}) do
                            labels[#labels + 1] = label
                        end
                    end
                    addFocusedMark(marks, {
                        kind = "objective",
                        x = area.x,
                        y = area.y,
                        questId = entry.questId,
                        isFocused = true,
                        glyph = glyph,
                        zoneId = area.points[1].zoneId or entry.zoneId,
                        number = number,
                        progress = progress,
                        labels = labels,
                        areas = {
                            {
                                x = area.shadeX or area.x,
                                y = area.shadeY or area.y,
                                radiusX = area.radiusX,
                                radiusY = area.radiusY,
                                shade = shade,
                            },
                        },
                        -- Lists of the mark's own, not the area's: a mark joined by another (addFocusedMark) adds
                        -- that one's spawns to each, and one list in both places would hold them twice
                        points = #area.points > 1 and copyList(area.points) or {},
                        -- Every spawn, a lone one too: the squares look draws a lone spawn as its circle (areas),
                        -- "icons and areas" needs them all for the quest's area and icons
                        spawnPoints = copyList(area.points),
                        lines = { title, text, foundNote },
                        -- (what of this follows the objective's count: MapMarks.refreshMarkTexts)
                        counted = {
                            {
                                objectiveIndex = objectiveIndex,
                                dungeonName = dungeonName,
                                lineIndex = 2,
                                label = labels[1],
                            },
                        },
                    }, firstFocusedMark)
                else
                    quietAreas[#quietAreas + 1] = {
                        area = area,
                        text = text,
                        glyph = glyph,
                        objectiveIndex = objectiveIndex,
                        dungeonName = dungeonName,
                    }
                end
            end
        end
    end
    -- A quest out of focus is one mark: its largest area
    local largest
    for _, quiet in ipairs(quietAreas) do
        if not largest or #quiet.area.points > #largest.area.points then
            largest = quiet
        end
    end
    if largest then
        -- Its spawn points come along, drawn fainter than the focused quest's
        local fadedPoints = {}
        for _, quiet in ipairs(quietAreas) do
            for _, point in ipairs(quiet.area.points) do
                fadedPoints[#fadedPoints + 1] = point
            end
        end
        marks[#marks + 1] = {
            kind = "objective",
            x = largest.area.x,
            y = largest.area.y,
            questId = entry.questId,
            isFocused = false,
            glyph = largest.glyph,
            zoneId = largest.area.points[1].zoneId or entry.zoneId,
            number = number,
            progress = progress,
            lines = { title, largest.text, foundNote },
            counted = { { objectiveIndex = largest.objectiveIndex, dungeonName = largest.dungeonName, lineIndex = 2 } },
            fadedPoints = #fadedPoints > 1 and fadedPoints or nil,
        }
    end
end

---Quest givers: one "!" for each quest in each area where it starts. Quests are never merged with one another;
---where their marks would overlap, drawing sets them side by side.
---@return string|number? icon The icon of the item a quest starts from, when it starts from a dropped item
local function getStartItemIcon(quest)
    if quest.startType ~= "item" or not quest.itemId then
        return nil
    end
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(quest.itemId)
        or GetItemIcon and GetItemIcon(quest.itemId) -- luacheck: ignore 113 (an older client's fallback)
    return icon or "Interface\\Icons\\INV_Misc_Note_01"
end
MapMarks.getStartItemIcon = getStartItemIcon

---@return number[] color The colour (red, green, blue) of one of a quest's shades, as its tooltip rows are drawn;
---the quest page uses it too, so a line there and its row on the map's tooltip match
function MapMarks.getShadeColor(shade)
    local color = QUEST_SHADES[shade] or QUEST_BLUE
    return { color[1], color[2], color[3] }
end

---The spawn points of an item's creatures on one map, each in its creature's shade in that zone, and a tooltip
---row for each creature with points there: its name and drop chance; creatures past the third share a row.
---@param zones DropZone[] From Drops.getZones
---@param drops string? What of the drops may be said (MapMarks.getDropsChoice): "names" leaves the chances out
---@return table[] points, { text: string, glyph: string, shade: number }[] labels
function MapMarks.composeSourcePoints(zones, mapId, drops)
    local points, labels, otherCount = {}, {}, 0
    local isChanceShown = drops == nil or drops == "chances"
    for _, zone in ipairs(zones) do
        for _, source in ipairs(zone.sources) do
            local sourcePoints = composePoints(source.places, mapId)
            local chance = isChanceShown and source.chance and ns.Drops.formatChance(source.chance)
            for _, point in ipairs(sourcePoints) do
                point.shade = source.shade
                point.note = source.name .. (chance and (ns.Widgets.MIDDLE_DOT .. chance) or "") -- for its tooltip
                points[#points + 1] = point
            end
            if #sourcePoints > 0 then
                if source.shade <= 3 then
                    labels[#labels + 1] = {
                        text = source.name .. (chance and (ns.Widgets.MIDDLE_DOT .. chance) or ""),
                        glyph = "loot",
                        shade = source.shade,
                    }
                else
                    otherCount = otherCount + 1
                end
            end
        end
    end
    if otherCount > 0 then
        labels[#labels + 1] =
            { text = ns.Lp(otherCount, "%d other creature", "%d other creatures"), glyph = "loot", shade = 4 }
    end
    return points, labels
end

---The quests to pick up shown on a map: the zone's, and on a map another addon joins its neighbours onto (OpenMap)
---those of every zone in view too, each quest once.
---@return AvailableQuest[] quests
local function getMapGiverQuests(mapId)
    local areaId = ns.Database.getAreaId(mapId)
    local zoneIds, isListed = {}, {}
    local function addZone(zoneAreaId)
        local zoneId = zoneAreaId and ns.Database.getParentZoneId(zoneAreaId)
        if zoneId and not isListed[zoneId] then
            isListed[zoneId] = true
            zoneIds[#zoneIds + 1] = zoneId
        end
    end
    addZone(areaId)
    local view, bounds = ns.MapPins.getView()
    if view then
        local isFine, mapIds = pcall(view.getZoneMapIds, mapId, bounds)
        for _, zoneMapId in ipairs(isFine and type(mapIds) == "table" and mapIds or {}) do
            addZone(ns.Database.getAreaId(zoneMapId))
        end
    end
    local quests, isQuestListed = {}, {}
    local options = { shouldShowLowLevel = ns.settings.shouldShowLowLevel, shouldIncludeEntrances = true }
    for _, zoneId in ipairs(zoneIds) do
        for _, quest in ipairs(ns.Availability.getQuests(zoneId, options)) do
            if not isQuestListed[quest.questId] then
                isQuestListed[quest.questId] = true
                quests[#quests + 1] = quest
            end
        end
    end
    return quests
end

local function addGiverMarks(marks, mapId, spoilers)
    if not ns.Availability.isReady() or not ns.Availability.isShownOnMap() then
        return
    end
    if spoilers and spoilers.get("pickup") == "none" then
        return -- (no quests to pick up shown: Spoilers)
    end
    local selectedQuestId = ns.Log.getHighlightedAvailableQuestId()
    -- Hidden by the "!" button on the map (MapDock): none but the quest selected on the Available tab
    local isHidden = ns.settings.areMapGiversHidden == true
    local givers = {} -- one mark per quest first; then the quests of one giver share theirs (mergeGivers)
    for _, quest in ipairs(getMapGiverQuests(mapId)) do
        if
            not quest.availableAtLevel
            and not quest.isHandedInHere
            and (not isHidden or quest.questId == selectedQuestId)
            and (not spoilers or MapMarks.isGiverQuestShown(spoilers, quest.questId))
        then
            local line = string.format("[%d] %s", quest.level, quest.title)
                .. (quest.starterName and (" - " .. quest.starterName) or "")
            local hasLabels = quest.questId ~= selectedQuestId
            -- One "!" for each area the quest starts in: a giver is one spot, but a quest that starts from
            -- an item dropped by creatures would otherwise put a "!" on every spawn point
            for _, area in ipairs(MapMarks.composeStableAreas(composePoints(quest.places, mapId))) do
                -- (only where it starts out of the map's fog and outside a dungeon held back: Spoilers)
                if not spoilers or isGiverAreaShown(spoilers, quest.questId, area.points) then
                    local mark = {
                        kind = "giver",
                        x = area.centroidX,
                        y = area.centroidY,
                        questId = quest.questId,
                        isFocused = quest.questId == selectedQuestId,
                        lines = { line },
                        itemIcon = getStartItemIcon(quest),
                        zoneId = area.points[1].zoneId,
                        isLowLevel = quest.isLowLevel == true,
                        isRepeatable = ns.Availability.isRepeatable(quest.questId),
                    }
                    local sourceLabels
                    if
                        mark.isFocused
                        and quest.startType == "item"
                        and quest.itemId
                        and not quest.isHandedInHere
                        and (not spoilers or isDropNamed(spoilers, quest.questId))
                    then
                        -- The selected quest starts from an item creatures drop: each creature's spawn points in its
                        -- own colour, the same as its dot on the quest page, and the mark's tooltip names them with
                        -- their chance, so it is plain where to hunt and who is likeliest to drop it. Drawn once, on
                        -- the mark that carries the labels.
                        if not hasLabels then
                            mark.points, sourceLabels = MapMarks.composeSourcePoints(
                                ns.Drops.getZones(quest.itemId),
                                mapId,
                                MapMarks.getDropsChoice(spoilers, quest.questId)
                            )
                            for _, point in ipairs(mark.points or {}) do
                                point.glyph = "loot" -- the item is looted from them
                            end
                        end
                    elseif mark.isFocused and #area.points > 1 then
                        -- The selected quest starts from creatures (an item they drop): their spawn points are
                        -- shown as the quest's own objectives are, so it is plain where to hunt
                        -- (copies: the area's points are kept for every quest that starts at the same spots, and
                        -- one that starts from an item and one from a talk mark them differently)
                        local glyph = quest.startType == "item" and "loot" or "talk"
                        mark.points = {}
                        for index, point in ipairs(area.points) do
                            local copy = {}
                            for key, value in pairs(point) do
                                copy[key] = value
                            end
                            copy.glyph = point.glyph or glyph
                            mark.points[index] = copy
                        end
                    end
                    if not hasLabels then
                        -- Where the selected quest starts: the place to go first, so its tooltip says so, once
                        mark.labels = sourceLabels and #sourceLabels > 0 and sourceLabels
                            or { { text = ns.L("Start: %s", quest.starterName or ns.L("quest giver")), glyph = "use" } }
                        hasLabels = true
                    end
                    mark.starterName, mark.level = quest.starterName, quest.level
                    givers[#givers + 1] = mark
                end
            end
        end
    end
    for _, mark in ipairs(MapMarks.mergeGivers(givers)) do
        marks[#marks + 1] = mark
    end
end

local SAME_SPOT = 0.002 -- marks of one NPC this close on the map (a fraction of it) are one place of theirs

---@return string? key Who gives a quest ("startedBy") or takes it in ("finishedBy"): its NPCs' and objects' IDs, the
---same for two quests of one NPC; nil when the database names no one. Marks share only with the same key, so two
---NPCs standing close, or seen from far out, keep their own marks.
local function getHandsKey(questId, field)
    local hands = questId and ns.Database.getQuestField(questId, field)
    if type(hands) ~= "table" then
        return nil
    end
    local parts = {}
    for _, npcId in ipairs(hands[1] or {}) do
        parts[#parts + 1] = "n" .. npcId
    end
    for _, objectId in ipairs(hands[2] or {}) do
        parts[#parts + 1] = "o" .. objectId
    end
    if #parts == 0 then
        return nil
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

---@return boolean isSame Two marks stand for the same NPC at the same place
local function isSameHands(first, second, firstKey, secondKey)
    return firstKey ~= nil
        and firstKey == secondKey
        and math.abs(first.x - second.x) <= SAME_SPOT
        and math.abs(first.y - second.y) <= SAME_SPOT
end

---@return string[] titles A shared or single mark's quest lines, without the NPC heading a shared one's tooltip
local function getQuestLines(mark)
    if mark.questIds then
        local lines = {}
        for index = 2, #mark.questIds + 1 do
            lines[#lines + 1] = mark.lines[index]
        end
        return lines
    end
    return { ((mark.lines[1] or ""):gsub(" %- .*$", "")) }
end

---One mark for an NPC who both takes quests in and gives new ones, as the game marks such an NPC: with a quest ready
---there, its "?" (what to go there for) with a small "!" badge, its tooltip listing what is offered too; with only
---quests not ready yet, the "!", its tooltip saying what will be handed in there. The quest selected to pick up
---keeps its own "!", so it still stands out.
---@return MapMark[] marks
function MapMarks.joinGiversAndTurnIns(marks)
    local givers = {}
    for _, mark in ipairs(marks) do
        if mark.kind == "giver" and not mark.itemIcon and not mark.isFocused then
            mark.handsKey = mark.handsKey or getHandsKey(mark.questId, "startedBy")
            givers[#givers + 1] = mark
        elseif mark.kind == "turnIn" then
            mark.handsKey = mark.handsKey or getHandsKey(mark.questId, "finishedBy")
        end
    end
    if #givers == 0 then
        return marks
    end
    local absorbed, kept = {}, {}
    for _, mark in ipairs(marks) do
        if mark.kind == "turnIn" and not mark.isPreview then
            for _, giver in ipairs(givers) do
                if not absorbed[giver] and isSameHands(giver, mark, giver.handsKey, mark.handsKey) then
                    local offered = getQuestLines(giver)
                    if mark.isPending then
                        -- Nothing ready: the "!" stands, and says what will be handed in here later
                        giver.lines = { unpack(giver.lines) }
                        giver.lines[#giver.lines + 1] = ns.L("Later, hand in here:")
                        for _, line in ipairs(getQuestLines(mark)) do
                            giver.lines[#giver.lines + 1] = line
                        end
                        absorbed[mark] = true
                    else
                        -- A quest ready: the "?" stands, with the "!" as its badge and the offers in its tooltip
                        mark.offerCount = giver.questIds and #giver.questIds or 1
                        mark.offerQuestIds = giver.questIds or { giver.questId }
                        mark.lines = { unpack(mark.lines) }
                        mark.lines[#mark.lines + 1] = ns.L("Also offers:")
                        for _, line in ipairs(offered) do
                            mark.lines[#mark.lines + 1] = line
                        end
                        absorbed[giver] = true
                    end
                    break
                end
            end
        end
    end
    for _, mark in ipairs(marks) do
        if not absorbed[mark] then
            kept[#kept + 1] = mark
        end
    end
    return kept
end

---One "?" for each NPC quests are handed in to, as one "!" for each giver: the quests ready there share a mark that
---counts them, and pointing at it says who takes them and lists them; the ones not ready yet (the grey "?") share
---another. The followed quest's goes first. A turn-in shown for a quest not taken yet keeps its own mark.
---@return MapMark[] marks All the marks, the turn-ins merged, in their order
function MapMarks.mergeTurnIns(marks)
    local spots, kept = {}, {}
    for _, mark in ipairs(marks) do
        if mark.kind == "turnIn" and not mark.isPreview then
            mark.handsKey = getHandsKey(mark.questId, "finishedBy")
            local spot
            for _, other in ipairs(spots) do
                if
                    other.isPending == (mark.isPending == true)
                    and isSameHands(other, mark, other.handsKey, mark.handsKey)
                then
                    spot = other
                    break
                end
            end
            if spot then
                spot.members[#spot.members + 1] = mark
            else
                spot = {
                    x = mark.x,
                    y = mark.y,
                    handsKey = mark.handsKey,
                    isPending = mark.isPending == true,
                    members = { mark },
                }
                spots[#spots + 1] = spot
                kept[#kept + 1] = spot
            end
        else
            kept[#kept + 1] = mark
        end
    end
    for index, item in ipairs(kept) do
        if item.members then
            local members = item.members
            if #members == 1 then
                kept[index] = members[1]
            else
                table.sort(members, function(first, second)
                    if (first.isFocused == true) ~= (second.isFocused == true) then
                        return first.isFocused == true
                    end
                    return first.questId < second.questId
                end)
                local mark = {}
                for key, value in pairs(members[1]) do
                    mark[key] = value
                end
                -- Who takes them heads the tooltip ("Turn in to ..."), then each quest
                mark.questIds, mark.lines = {}, { members[1].lines[2] or ns.L("Turn in") }
                for _, member in ipairs(members) do
                    mark.questIds[#mark.questIds + 1] = member.questId
                    mark.lines[#mark.lines + 1] = member.lines[1] or ""
                    mark.isFocused = mark.isFocused or member.isFocused
                end
                if item.isPending then
                    mark.lines[#mark.lines + 1] = ns.L("Not ready to hand in yet")
                end
                kept[index] = mark
            end
        end
    end
    return kept
end

---One "!" for each quest giver: the quests one NPC (or one spot) offers share a mark, which counts them and lists
---them all when pointed at; the selected quest's goes first, else the lowest. A quest that starts from a dropped
---item keeps its own mark, the item's picture.
---@return MapMark[] marks
function MapMarks.mergeGivers(givers)
    local merged, spots = {}, {}
    for _, mark in ipairs(givers) do
        local spot
        if not mark.itemIcon then
            mark.handsKey = getHandsKey(mark.questId, "startedBy")
            for _, other in ipairs(spots) do
                if isSameHands(other, mark, other.handsKey, mark.handsKey) then
                    spot = other
                    break
                end
            end
        end
        if spot then
            spot.members[#spot.members + 1] = mark
        else
            local entry = { x = mark.x, y = mark.y, handsKey = mark.handsKey, members = { mark } }
            if not mark.itemIcon then
                spots[#spots + 1] = entry
            end
            merged[#merged + 1] = entry
        end
    end
    local marks = {}
    for _, entry in ipairs(merged) do
        local members = entry.members
        if #members == 1 then
            marks[#marks + 1] = members[1]
        else
            table.sort(members, function(first, second)
                if (first.isFocused == true) ~= (second.isFocused == true) then
                    return first.isFocused == true
                end
                if (first.level or 0) ~= (second.level or 0) then
                    return (first.level or 0) < (second.level or 0)
                end
                return first.questId < second.questId
            end)
            local lead = members[1]
            local mark = {}
            for key, value in pairs(lead) do
                mark[key] = value
            end
            -- The giver's name heads its tooltip, then each quest
            mark.questIds, mark.lines = {}, { lead.starterName or ns.L("quest giver") }
            mark.isLowLevel, mark.isRepeatable = true, true
            for _, member in ipairs(members) do
                mark.questIds[#mark.questIds + 1] = member.questId
                mark.lines[#mark.lines + 1] = (member.lines[1] or ""):gsub(" %- .*$", "")
                mark.isLowLevel = mark.isLowLevel and member.isLowLevel == true
                mark.isRepeatable = mark.isRepeatable and member.isRepeatable == true
                mark.isFocused = mark.isFocused or member.isFocused
            end
            marks[#marks + 1] = mark
        end
    end
    return marks
end

---For the quest selected on the Available tab, once its "Show turn-in" is pressed: where it will be handed in,
---as a green ring whose tooltip says so. It has no number, not being in the log,
---and is kept quieter than the quest's start.
---The followed or highlighted quest's turn-in while it is not ready: the game's "?" in grey, as the game shows over a quest
---giver whose quest is not finished, so the player knows where it ends. Not on the minimap, where the game never shows a
---grey "?", and not for other quests, which would crowd the map.
local function addPendingTurnIn(marks, entry, mapId, spoilers)
    if entry.isTurnIn or (spoilers and not MapMarks.isTurnInShown(spoilers, entry.questId)) then
        return
    end
    local places = ns.Location.getFinisherPlaces(entry.questId)
    local lines = {
        string.format("[%d] %s", entry.level, entry.title),
        ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver")),
        ns.L("Not ready to hand in yet"),
    }
    for _, place in ipairs(places) do
        local x, y
        if isOnMapZone(place, mapId) then
            x, y = ns.MapPins.getMapPosition(place, mapId)
        end
        if x then
            marks[#marks + 1] = {
                kind = "turnIn",
                isPending = true,
                x = x,
                y = y,
                questId = entry.questId,
                isFocused = false,
                progress = 0,
                labels = {},
                lines = lines,
            }
        end
    end
end

local function addTurnInPreview(marks, mapId, spoilers)
    local quest = ns.Log.getSelectedAvailableQuest()
    -- Selecting a quest to pick up shows where it starts; its turn-in only once "Show turn-in" is pressed for it
    if
        not quest
        or ns.Log.turnInShownQuestId ~= quest.questId
        or (spoilers and not MapMarks.isTurnInShown(spoilers, quest.questId))
    then
        return
    end
    local place = quest.finisherPlace
    if not place then
        return
    end
    local x, y
    if isOnMapZone(place, mapId) then
        x, y = ns.MapPins.getMapPosition(place, mapId)
    end
    if not x then
        return
    end
    local text = ns.L("Turn in to %s", quest.finisherName or ns.L("the quest giver"))
    -- Shown at ordinary size without a glow: the start is the place to go first, this is where it ends
    marks[#marks + 1] = {
        kind = "turnIn",
        isPreview = true,
        x = x,
        y = y,
        questId = quest.questId,
        isFocused = false,
        progress = 1,
        labels = { { text = ns.L("Then: %s", quest.finisherName or ns.L("turn in")), glyph = "tick" } },
        lines = { string.format("[%d] %s", quest.level, quest.title), text, ns.L("Not accepted yet") },
    }
end

---@return number? questId The quest drawn in full. While the quest panels are open the map shows exactly what
---the quest list does: the quest highlighted there, or none; on the Available tab none, since there the
---selected quest giver is the thing to look at. With the panels closed it is the tracker's active quest.
function MapMarks.getFocusedQuestId()
    if ns.Log.isOpen() then
        local selected = ns.Log.getSelectedQuestId()
        if selected and ns.Log.isUnfocusedSelection(selected) then
            selected = nil -- (open still, its focus taken off: not shown as focused)
        end
        return ns.Log.getHoveredQuestId() or selected
    end
    return ns.Focus.get()
end

---Marks that fall on a dungeon's entrance, two or more, become one: the dungeon's mark with how many quests
---of the log are inside and how many are to pick up there. Hovering it lists them, the focused one first, and
---clicking it opens the dungeon's run plan. On the dungeon's own map its marks stay apart.
---While something is held back (Spoilers), a dungeon held back gets no mark of its own: its quests' marks stay apart.
local function groupDungeonMarks(marks, mapId, spoilers)
    local areaId = ns.Database.getAreaId(mapId)
    local shownZoneId = areaId and ns.Database.getParentZoneId(areaId)
    local groups, order = {}, {}
    for index, mark in ipairs(marks) do
        local dungeon = mark.zoneId and ns.Database.getDungeon(mark.zoneId)
        if
            dungeon
            and dungeon.areaId ~= shownZoneId
            and (not spoilers or MapMarks.isDungeonShown(spoilers, dungeon.areaId))
        then
            if not groups[dungeon.areaId] then
                groups[dungeon.areaId] = { dungeon = dungeon, indexes = {} }
                order[#order + 1] = dungeon.areaId
            end
            table.insert(groups[dungeon.areaId].indexes, index)
        end
    end
    local isMerged = {}
    local merged = {}
    for _, dungeonId in ipairs(order) do
        local group = groups[dungeonId]
        if #group.indexes >= 2 then
            local members, x, y, logQuests, logCount, giverCount, focused, isRaid = {}, 0, 0, {}, 0, 0, nil, false
            for _, index in ipairs(group.indexes) do
                local mark = marks[index]
                isMerged[index] = true
                members[#members + 1] = mark
                x, y = x + mark.x, y + mark.y
                if mark.kind == "giver" then
                    giverCount = giverCount + 1
                elseif not logQuests[mark.questId] and not mark.isPreview then
                    logQuests[mark.questId] = true
                    logCount = logCount + 1
                end
                if mark.isFocused and not focused then
                    focused = mark
                end
                local group = mark.questId and ns.QuestState.getGroupInfo(mark.questId)
                isRaid = isRaid or (group ~= nil and group.isRaid == true) -- the game tags raid quests
            end
            table.sort(members, function(first, second)
                if (first.isFocused == true) ~= (second.isFocused == true) then
                    return first.isFocused == true
                end
                if (first.kind == "giver") ~= (second.kind == "giver") then
                    return second.kind == "giver"
                end
                return (first.number or 99) < (second.number or 99)
            end)
            merged[#merged + 1] = {
                kind = "dungeon",
                dungeonId = dungeonId,
                x = x / #group.indexes,
                y = y / #group.indexes,
                questId = focused and focused.questId or members[1].questId,
                isFocused = focused ~= nil,
                logCount = logCount,
                giverCount = giverCount,
                members = members,
                isRaid = isRaid,
                labels = focused and focused.labels or nil,
                lines = { group.dungeon.name },
            }
        end
    end
    if #merged == 0 then
        return marks
    end
    local kept = {}
    for index, mark in ipairs(marks) do
        if not isMerged[index] then
            kept[#kept + 1] = mark
        end
    end
    -- The dungeon's mark drawn last when it holds the quest in focus, as a focused mark is
    for _, mark in ipairs(merged) do
        if mark.isFocused then
            kept[#kept + 1] = mark
        else
            table.insert(kept, 1, mark)
        end
    end
    return kept
end

---Everything to show on a map, in drawing order: quiet marks first, the quest in focus last. While something is held
---back (Spoilers), only what the player chose to see.
---@param isPeekIgnored boolean? Not the world map (the minimap, the zone map): Alt held over the world map shows
---everything there alone
---@return MapMark[] marks
function MapMarks.compose(mapId, isPeekIgnored)
    local spoilers = MapMarks.getSpoilers(isPeekIgnored) -- (asked once: nil in Guide)
    local marks = {}
    local player = ns.Model.getPlayer()
    local focusedQuestId = MapMarks.getFocusedQuestId()
    local numbers = ns.QuestState.getWatchNumbers()
    local questIds = ns.QuestState.getShownOnMapQuestIds() -- (tracked, and any ready to hand in)
    if focusedQuestId and not numbers[focusedQuestId] and ns.QuestState.isInLog(focusedQuestId) then
        questIds[#questIds + 1] = focusedQuestId -- selected in the quest list without being tracked
    end

    local focusedEntry
    local followedQuestId = ns.Focus.get()
    local pendingEntries = {} -- the followed quest and the highlighted one: where each will be handed in, in grey
    for _, questId in ipairs(questIds) do
        local entry = ns.Model.composeEntry(questId, player)
        if questId == followedQuestId or questId == focusedQuestId then
            pendingEntries[#pendingEntries + 1] = entry
        end
        if questId == focusedQuestId then
            focusedEntry = entry
        else
            addQuestMarks(marks, entry, mapId, false, numbers[questId], spoilers)
        end
    end
    addGiverMarks(marks, mapId, spoilers)
    addTurnInPreview(marks, mapId, spoilers)
    if focusedEntry then
        addQuestMarks(marks, focusedEntry, mapId, true, numbers[focusedQuestId], spoilers)
    end
    for _, entry in ipairs(pendingEntries) do
        addPendingTurnIn(marks, entry, mapId, spoilers)
    end
    return groupDungeonMarks(MapMarks.joinGiversAndTurnIns(MapMarks.mergeTurnIns(marks)), mapId, spoilers)
end

-- Shared with the other parts of the window
Style.AREA_EDGE_ALPHA = AREA_EDGE_ALPHA
Style.AREA_EDGE_PIXELS = AREA_EDGE_PIXELS
Style.AREA_FILL_ALPHA = AREA_FILL_ALPHA
Style.AREA_MIN_POINTS = AREA_MIN_POINTS
Style.AREA_REACH = AREA_REACH
Style.AREA_REACH_YARDS = AREA_REACH_YARDS
Style.ONE_PLACE_YARDS = ONE_PLACE_YARDS
Style.AREA_RIM_ALPHA = AREA_RIM_ALPHA
Style.AREA_RIM_COLOR = AREA_RIM_COLOR
Style.AREA_RIM_PIXELS = AREA_RIM_PIXELS
Style.AREA_RING = AREA_RING
Style.AREA_TINT_ALPHA = AREA_TINT_ALPHA
Style.CIRCLE_MASK = CIRCLE_MASK
Style.DARK = DARK
Style.FADED_ICON_ALPHA = FADED_ICON_ALPHA
Style.FADED_ICON_GLOW_ALPHA = FADED_ICON_GLOW_ALPHA
Style.FALLBACK_GROUP_LEVEL = FALLBACK_GROUP_LEVEL
Style.FALLBACK_QUEST_BLOB_LEVEL = FALLBACK_QUEST_BLOB_LEVEL
Style.FOCUSED_AREA_EDGE_ALPHA = FOCUSED_AREA_EDGE_ALPHA
Style.FOCUSED_AREA_FILL_ALPHA = FOCUSED_AREA_FILL_ALPHA
Style.FOCUSED_AREA_RIM_ALPHA = FOCUSED_AREA_RIM_ALPHA
Style.FOCUSED_AREA_TINT_ALPHA = FOCUSED_AREA_TINT_ALPHA
Style.FOCUSED_ICON_GLOW_ALPHA = FOCUSED_ICON_GLOW_ALPHA
Style.FOCUS_GOLD = FOCUS_GOLD
Style.GLYPHS = GLYPHS
Style.GOLD = GOLD
Style.ICON_CELL = ICON_CELL
Style.ICON_GLOW_SIZE = ICON_GLOW_SIZE
Style.ICON_SIZE = ICON_SIZE
Style.LEVELS_UNDER_GROUP = LEVELS_UNDER_GROUP
Style.MAX_POINTS = MAX_POINTS
Style.MEDIA = MEDIA
Style.QUEST_BLUE = QUEST_BLUE
Style.QUEST_SHADES = QUEST_SHADES
Style.SOFT_DOT = SOFT_DOT
Style.SPAWN_PATCH = SPAWN_PATCH
Style.SPAWN_ROOM = SPAWN_ROOM
Style.ZONE_MAP_TYPE = ZONE_MAP_TYPE
---@return { x: number, y: number }[][] lines The quest's creatures' patrols on a map, each a line of points (fractions
---of the map), for those parts of them on it
function MapMarks.getQuestPatrolLines(questId, mapId)
    return MapMarks.getPatrolLines(ns.Location.getObjectivePatrols(questId), mapId)
end

---@return { x: number, y: number }[][] lines Patrols on a map, each a line of points (fractions of the map)
function MapMarks.getPatrolLines(patrols, mapId)
    local lines = {}
    local patrolZones = {}
    for index, patrol in ipairs(patrols) do
        patrolZones[index] = patrol.zoneId and ns.Database.getParentZoneId(patrol.zoneId)
    end
    -- The same walk listed in two zones' maps (near a border) is drawn once: the copy whose path lies mostly in
    -- the other zone's land is left out
    local listedZones = getListedZones(patrolZones)
    for patrolIndex, patrol in ipairs(patrols) do
        local line, shadowedCount = {}, 0
        local groupZoneId = patrolZones[patrolIndex] -- the zone it belongs to, as spawns' places say
        for _, point in ipairs(patrol.points) do
            local place = { zoneId = patrol.zoneId, groupZoneId = groupZoneId, x = point[1], y = point[2] }
            local x, y
            if isOnMapZone(place, mapId) then
                x, y = ns.MapPins.getMapPosition(place, mapId)
            end
            if x then
                line[#line + 1] = { x = x, y = y }
                if isShadowed(groupZoneId, x, y, mapId, listedZones) then
                    shadowedCount = shadowedCount + 1
                end
            end
        end
        if shadowedCount * 2 > #line then
            line = {}
        end
        if #line >= 2 then
            line.npcId = patrol.npcId -- whose walk it is, for its tooltip
            lines[#lines + 1] = line
        end
    end
    return lines
end

---@return { x: number, y: number }[][] lines The paths of whom a quest is had from (its givers, the creatures that drop the
---item it starts from) on a map: drawn while the pointer is on its "!" (MapMarks.showHoverPatrols)
function MapMarks.getQuestStarterPatrolLines(questId, mapId)
    local lines = {}
    for _, npcId in ipairs(ns.Location.getStarterNpcIds(questId)) do
        for _, line in ipairs(MapMarks.getPatrolLines(ns.Location.getNpcPatrols(npcId), mapId)) do
            lines[#lines + 1] = line
        end
    end
    return lines
end

---@return { points: { x: number, y: number }[], isFocused: boolean }[] lines The paths of the quest givers on a map who
---walk about (a "!" at one spot of theirs shows where they were seen, not where they will be), for the quest selected
---on the Available tab, with whom it is handed in to. Others' only while pointed at (getQuestStarterPatrolLines): drawn
---for every giver, they ran together on shared roads. While something is held back (Spoilers), only the walks of
---givers and of whom it is handed in to that may be shown.
---@param isPeekIgnored boolean? (as for MapMarks.compose)
function MapMarks.getGiverPatrolLines(mapId, isPeekIgnored)
    local result = {}
    if not ns.Availability.isReady() or not ns.Availability.isShownOnMap() then
        return result
    end
    local spoilers = MapMarks.getSpoilers(isPeekIgnored)
    local selectedQuestId = ns.Log.getHighlightedAvailableQuestId()
    local isDrawn = {}
    for _, quest in ipairs(getMapGiverQuests(mapId)) do
        if
            quest.questId == selectedQuestId
            and not quest.availableAtLevel
            and not quest.isHandedInHere
            and (not spoilers or MapMarks.isGiverQuestShown(spoilers, quest.questId))
        then
            local isSelected = true
            local npcIds = ns.Location.getStarterNpcIds(quest.questId)
            if isSelected and (not spoilers or MapMarks.isTurnInShown(spoilers, quest.questId)) then
                for _, npcId in ipairs((ns.Database.getQuestField(quest.questId, "finishedBy") or {})[1] or {}) do
                    npcIds[#npcIds + 1] = npcId
                end
            end
            for _, npcId in ipairs(npcIds) do
                local key = npcId .. (isSelected and ":selected" or "")
                if not isDrawn[key] then
                    isDrawn[key] = true
                    for _, line in ipairs(MapMarks.getPatrolLines(ns.Location.getNpcPatrols(npcId), mapId)) do
                        result[#result + 1] = { points = line, isFocused = isSelected, questId = quest.questId }
                    end
                end
            end
        end
    end
    return result
end

Compose.composePoints = composePoints
