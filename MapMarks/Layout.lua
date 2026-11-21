local addonName, ns = ...

-- The map's marks: laying them out (each mark's footprint, keeping crowded marks apart).
local MapMarks = ns.MapMarks
local Style, State = ns.MapMarksStyle, ns.MapMarksState
local Compose, Look, Layout, Shapes, Areas, Draw = ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw
local BANG_SIZE, ITEM_MARK_REACH, MARK_GAP, MARK_SIZE, acquire = Look.BANG_SIZE, Look.ITEM_MARK_REACH, Look.MARK_GAP, Look.MARK_SIZE, Look.acquire
local FALLBACK_GROUP_LEVEL, FALLBACK_QUEST_BLOB_LEVEL, LEVELS_UNDER_GROUP = Style.FALLBACK_GROUP_LEVEL, Style.FALLBACK_QUEST_BLOB_LEVEL, Style.LEVELS_UNDER_GROUP

---@param map table? The map asked about; the world map when left out
---@return table drawn What a map shows now, for hovering: map, width, height, scale, areas (spawns and reach in the
---area layer's units) and squares (spawn marks in the mark layer's units), each with its questId
function MapMarks.getDrawn(map)
    MapMarks.useMap(map or WorldMapFrame)
    return State.drawn, State.markLayer, State.areaLayer
end

---@return number level The level our marks start at: under the level the map gives its group members
function MapMarks.getFrameLevel(map)
    local manager = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    local isRead, groupLevel = false, nil
    if manager and manager.GetFrameLevelStart then
        isRead, groupLevel = pcall(manager.GetFrameLevelStart, manager, "PIN_FRAME_LEVEL_GROUP_MEMBER")
    end
    if not isRead or type(groupLevel) ~= "number" or groupLevel <= LEVELS_UNDER_GROUP then
        groupLevel = FALLBACK_GROUP_LEVEL
    end
    return groupLevel - LEVELS_UNDER_GROUP
end

---@return number level Where the game draws its own quest areas (PIN_FRAME_LEVEL_QUEST_BLOB): under every pin,
---the game's and other addons', so our areas never tint them
function MapMarks.getAreaFrameLevel(map)
    local manager = map and map.GetPinFrameLevelsManager and map:GetPinFrameLevelsManager()
    local isRead, level = false, nil
    if manager and manager.GetFrameLevelStart then
        isRead, level = pcall(manager.GetFrameLevelStart, manager, "PIN_FRAME_LEVEL_QUEST_BLOB")
    end
    if not isRead or type(level) ~= "number" or level < 1 then
        level = FALLBACK_QUEST_BLOB_LEVEL
    end
    return level
end

local function ensureLayers(map, canvas)
    State.frameLevel = MapMarks.getFrameLevel(map)
    if not State.areaLayer then
        State.areaLayer = CreateFrame("Frame", nil, canvas)
        State.areaLayer:SetAllPoints(canvas)
        State.markLayer = CreateFrame("Frame", nil, canvas)
        State.markLayer:SetPoint("TOPLEFT", canvas, "TOPLEFT", 0, 0)
        State.markLayer:SetSize(1, 1)
    end
    State.areaLayer:SetFrameLevel(MapMarks.getAreaFrameLevel(map))
    State.markLayer:SetFrameLevel(State.frameLevel + 1)
end

---The room a mark takes on the map, the same whether or not it is in focus, so that picking a quest never
---moves the marks around it.
---@return number width, number height
---@return number raise How far its middle sits above its spot; a pin stands on its tip
function MapMarks.getFootprint(mark)
    if mark.kind == "zonePill" then
        local width, height = MapMarks.getPillFootprint(mark)
        return width, height, 0
    end
    if mark.kind == "giver" and mark.itemIcon then
        return ITEM_MARK_REACH * 2, ITEM_MARK_REACH * 2, 0 -- with its "!" badge
    end
    if mark.kind == "turnIn" and not mark.isPreview and (mark.offerCount or 0) > 0 then
        return (BANG_SIZE + 2) * 1.45, BANG_SIZE + 4, 0 -- "?!": the two signs side by side
    end
    if mark.kind == "giver" or (mark.kind == "turnIn" and not mark.isPreview) then
        return BANG_SIZE + 2, BANG_SIZE + 4, 0
    end
    if mark.kind == "dungeon" then
        local reach = MapMarks.getOrbitReach(mark)
        return reach * 2, reach * 2, 0
    end
    return MARK_SIZE, MARK_SIZE, 0
end

---The order marks keep within a group: the player's quests by their numbers, the selected quest's hand-in,
---then quest givers by quest. It never depends on what is selected.
local function isBeforeInGroup(first, second)
    local function getRank(mark)
        return mark.kind == "giver" and 3 or mark.isPreview and 2 or 1
    end
    local firstRank, secondRank = getRank(first.mark), getRank(second.mark)
    if firstRank ~= secondRank then
        return firstRank < secondRank
    end
    local firstNumber, secondNumber = first.mark.number or math.huge, second.mark.number or math.huge
    if firstNumber ~= secondNumber then
        return firstNumber < secondNumber
    end
    if (first.mark.questId or 0) ~= (second.mark.questId or 0) then
        return (first.mark.questId or 0) < (second.mark.questId or 0)
    end
    return first.index < second.index
end

local NUDGE_STEP = 2 -- how far apart the rings of spots a crowded mark tries are: fine, so it finds the nearest room
local NUDGE_ANGLES = 16
local MAX_NUDGE_RINGS = 40 -- beyond this the mark takes the spot where it overlaps least
local GRID_CELL = 32 -- placed marks are kept in a grid of this size, so a crowded map is still quick to lay out

local function getRect(left, top, width, height)
    return { left = left - width / 2, top = top - height / 2, right = left + width / 2, bottom = top + height / 2 }
end

local function getOverlap(first, second)
    local width = math.min(first.right, second.right) - math.max(first.left, second.left) + MARK_GAP
    local height = math.min(first.bottom, second.bottom) - math.max(first.top, second.top) + MARK_GAP
    if width <= 0 or height <= 0 then
        return 0
    end
    return width * height
end

---Placed rects, by the grid cells they cover.
local function createGrid()
    local grid = { cells = {} }
    function grid.add(rect)
        for column = math.floor(rect.left / GRID_CELL), math.floor(rect.right / GRID_CELL) do
            for row = math.floor(rect.top / GRID_CELL), math.floor(rect.bottom / GRID_CELL) do
                local key = column * 100000 + row
                grid.cells[key] = grid.cells[key] or {}
                table.insert(grid.cells[key], rect)
            end
        end
    end
    ---@return number overlap How much of what is placed the rect would cover (0: it is free)
    function grid.getOverlap(rect)
        local total, seen = 0, {}
        for column = math.floor((rect.left - MARK_GAP) / GRID_CELL), math.floor((rect.right + MARK_GAP) / GRID_CELL) do
            for row = math.floor((rect.top - MARK_GAP) / GRID_CELL), math.floor((rect.bottom + MARK_GAP) / GRID_CELL) do
                for _, placed in ipairs(grid.cells[column * 100000 + row] or {}) do
                    if not seen[placed] then
                        seen[placed] = true
                        total = total + getOverlap(rect, placed)
                    end
                end
            end
        end
        return total
    end
    return grid
end

---Places marks so that none covers another, each as near its own spot as it can be: in a fixed order (the
---player's quests by their numbers, the selected quest's hand-in, then quest givers), each takes its spot if it
---is free, else the nearest free spot on rings round it. Obstacles (marks drawn on their exact spots, other
---addons' pins) are kept clear too.
---@param items { spotLeft: number, spotTop: number, width: number, height: number, mark: table, index: number }[]
---@param obstacles { left: number, top: number, right: number, bottom: number }[]?
---@param bounds { left: number, top: number, right: number, bottom: number }? The map: no mark is pushed off it
---Each item gets left and top, the middle of its place.
-- Whether marks are moved apart where they would overlap (and spawn marks kept on a grid, off the marks). Off for
-- now: every mark stays on its spot and a zoom only scales it, so nothing moves or jumps as the map zooms.
MapMarks.IS_LAYOUT_ON = false

function MapMarks.arrangeMarks(items, obstacles, bounds)
    if not MapMarks.IS_LAYOUT_ON then
        -- Laid out off: every mark on its own spot, as the map zooms it only scales, never moves
        for _, item in ipairs(items) do
            item.left, item.top = item.spotLeft, item.spotTop
        end
        return
    end
    local grid = createGrid()
    for _, obstacle in ipairs(obstacles or {}) do
        grid.add(obstacle)
    end
    local ordered = {}
    for index, item in ipairs(items) do
        ordered[index] = item
    end
    table.sort(ordered, isBeforeInGroup)
    for _, item in ipairs(ordered) do
        local bestLeft, bestTop, bestOverlap = item.spotLeft, item.spotTop, math.huge
        local ring = 0
        while ring <= MAX_NUDGE_RINGS and bestOverlap > 0 do
            local angleCount = ring == 0 and 1 or NUDGE_ANGLES + ring * 2
            for step = 0, angleCount - 1 do
                -- From straight up round the clock, so the same crowd is always laid out the same way
                local angle = -math.pi / 2 + step * 2 * math.pi / angleCount
                local left = item.spotLeft + math.cos(angle) * ring * NUDGE_STEP
                local top = item.spotTop + math.sin(angle) * ring * NUDGE_STEP
                local overlap = grid.getOverlap(getRect(left, top, item.width, item.height))
                local isOnMap = not bounds or ring == 0 or (left - item.width / 2 >= bounds.left and left + item.width / 2 <= bounds.right
                    and top - item.height / 2 >= bounds.top and top + item.height / 2 <= bounds.bottom)
                if isOnMap and overlap < bestOverlap then
                    bestLeft, bestTop, bestOverlap = left, top, overlap
                    if overlap == 0 then
                        break
                    end
                end
            end
            ring = ring + 1
        end
        item.left, item.top = bestLeft, bestTop
        grid.add(getRect(bestLeft, bestTop, item.width, item.height))
    end
end

-- Shared with the other parts of the window
Layout.ensureLayers = ensureLayers
Layout.getRect = getRect
