local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Marks on the minimap, in the same language as the world map: each tracked quest's nearest place in range
-- has a small progress ring with the quest's number (the game's "?" for a turn-in), its other places in range
-- are tiny squares, as its spawn points are on the map (full for the quest in focus, fainter for the others),
-- and a quest giver is the game's "!". The nearest place
-- of the highlighted quest stays on the rim when it is out of range, so it always shows the way.
local MinimapPins = {}
ns.MinimapPins = MinimapPins

local MAX_PINS = 60
local MAX_SPOTS = 300
-- The minimap is laid out once for the land round the player, as the world map is for a zone: everything of the
-- tracked quests within what the minimap sees and this much further. Walking only slides it (MinimapPins.slide);
-- it is chosen again when the quests, the zoom or the zone change, or once the player has walked so far that
-- something left out could come into view (MinimapPins.isCompositionStale). With little about (the usual: a few
-- quests in a zone) nothing is left out, and it stands till the quests change.
local REGION_MARGIN_YARDS = 300
local VALID_SLACK_YARDS = 20 -- chosen again this much before a place left out could show (looked at once a second)
local MIN_VALID_YARDS = 8 -- with more near than are drawn at all (MAX_SPOTS), the nearest are chosen again this often
local BASE_MARK_SCALE = 0.6 -- the world map's marks, at 12 across (the map's 20, scaled)
local MARK_SCALE = BASE_MARK_SCALE -- times the size the player chose for minimap marks (set as they are drawn)
local NEAR_PLAYER_PIXELS = 22 -- a mark or spawn icon this close to the player's arrow is faded, when the player chose that
local NEAR_PLAYER_ALPHA = 0.35

---@return number alpha How much of something drawn at this place on the minimap shows: faded over the player's arrow,
---when the player chose that
local function getNearPlayerAlpha(x, y)
    if ns.settings.shouldFadeMarksNearPlayer and x * x + y * y < NEAR_PLAYER_PIXELS * NEAR_PLAYER_PIXELS then
        return NEAR_PLAYER_ALPHA
    end
    return 1
end
local MARK_PACKING = 0.8 -- how far marks keep apart, against their drawn half size: below 1, their rims overlap a little, so each stands nearer its place
-- A spawn's marker, smaller than on the map (the minimap is small) and otherwise the same: the kind the player
-- chose, as strong, its glow as large against it (MapMarks.dressSpawnMarker dresses both maps')
local ICON_SIZE = 7
local ICON_GLOW_SIZE = ICON_SIZE * 17 / 11
local ICON_GAP = 3
-- Zoomed out the icons are drawn smaller, on the same grid (as many spawns, more room round each): full size from
-- ICON_FULL_YARDS of view in, ZOOMED_OUT_ICON_SCALE of it at ICON_SMALLEST_YARDS (the minimap fully zoomed out)
local ZOOMED_OUT_ICON_SCALE, ICON_FULL_YARDS, ICON_SMALLEST_YARDS = 0.75, 150, 233
-- (The spawn markers and the areas were once drawn half see-through, for the game's own gathering blips under them to
-- show; they then looked unlike the world map's, washed out, and a quest's place could not be told at a glance. They
-- are as on the map now: an area's fill is light anyway, and a marker covers a few pixels.)
local RIM = 0.94 -- how far out a rim pin sits, as a fraction of the radius
local MOVE_SECONDS = 0.05 -- how often to check whether anything the minimap shows has changed
local FULL_MOVE_SECONDS = 1 -- and placed again in any case, as often as this
local STATE_STEP_PIXELS = 0.5 -- the player's moves, as the minimap shows them, that place the marks again
-- The minimap's shape, from GetMinimapShape (minimap addons provide it; the game's minimap is round): for each
-- quarter whether its edge is round. Quarters as LibDBIcon and HereBeDragons number them, up positive: 1 lower
-- right, 2 lower left, 3 upper right, 4 upper left.
local SHAPES = {
    ROUND = { true, true, true, true },
    SQUARE = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}
-- The game draws party members and the player's arrow into the minimap itself, under every addon's frame: we draw
-- them again over ours (the arrow, and each member's party icon in their class colour), so our marks need not
-- step aside for them
local MEMBER_CLEAR = 10 -- pixels round a party member's dot (14 across): where area edges are cut
local PLAYER_CLEAR = 12 -- round the player's arrow
local MEMBER_ICON_SIZE = 14 -- the game's party icon on the minimap
local PLAYER_ARROW_SIZE = 32 -- the game's minimap arrow (Interface\Minimap\MinimapArrow), its art the middle 20
local MAX_FOREIGN_PIN_SIZE = 30 -- other addons' frames on the minimap up to this size are pins to keep clear of
local DEFAULT_VIEW_RADIUS = 233 -- yards, the outdoor minimap fully zoomed out
-- The game draws its own "?" for whom a quest is handed in to once the server has sent that creature to the client:
-- within its visibility range, the same everywhere and the same coming and going (120 yards, measured with /omq distance:
-- the game's came and went at 120). Inside the minimap's view but beyond that range, the turn-in has our mark. Whether
-- it shows is checked as often as marks move (MOVE_SECONDS), not once a second, so the two hand over within a step and
-- never stand over each other (their places differ by a few yards). Checked every frame.
local TURN_IN_HANDOVER_YARDS = 120
-- Ours then looks just as the game's: its own "?" art, as large against the minimap as the game draws it (measured: the
-- game's icon, its whole 32 pixel cell, spans 6.4% of the minimap's width), no ring, no glow
local GAME_ICON_SHARE = 0.064
-- "Icons and areas": each tracked quest's areas, exactly as on the world map (worked out on the zone's map the same
-- way, then placed in the world)
local ZONE_MAP_TYPE = 3 -- the game's map types: continent 2, zone 3, then dungeons, towns and buildings inside
-- (their fills and edges as strong as on the map, in the look chosen there: MapMarks.getAreaLook; light enough that
-- your arrow and the party's dots, drawn under every addon's frame, show plainly through)
local AREA_EDGE_PIXELS, AREA_RIM_PIXELS = 1.5, 3
local SPOT_HOVER_RADIUS = 6 -- how near the cursor must be to a spawn mark for its tooltip

local pins, spots, members = {}, {}, {}
local gamePins = {} -- the turn-ins in view, drawn as the game's own "?"
local areaFrame, areaMask
local isAreaMasked = true -- a round minimap: fills cut by a round mask; any other shape: by the frame's square
local triangles, lines = { usedCount = 0 }, { usedCount = 0 } -- lines: areas' edges and patrols' dashes
local shownAreas = {} -- { questId, number, isFocused, outline }: outlines in yards ({ x = west, y = north })
local drawnSpots, drawnAreas = {}, {} -- what is on the minimap now, in pixels from its middle (up positive)
local ringFrame
local playerArrow -- the player's arrow, drawn again over our marks
local shownPlaces = {} -- { place, data, isKeptOnRim }
local shownSpots = {} -- { place, isFocused }: places drawn as squares
local frame
local elapsedSeconds = 0
-- The canvases a minimap that does not turn draws on (see the areas' drawing, below, for what rides them)
local fillCanvas, lineFrame, spotCanvas
local worldOrigin -- { continentId, north, west }: the place in the world the canvases' corner stands for
local spotsLaidFor, spotsLaidKey -- the spots, and the marks on the minimap, the canvas's icons were last laid out for
local lastMove = {} -- north, west, viewRadius, radius, facing: what the marks were last placed for (hovering asks)
local areDrawnSpotsStale, areDrawnAreasStale = false, false -- what is under the pointer is worked out when asked for
local ensureOrigin, placeCanvas, hideCanvas -- (written with the areas' drawing)
-- What is near enough to show before the player has walked on a little, told from what is far once every
-- NEAR_STEP_YARDS (partitionNear): at a move only the near are looked at, however much the land holds
local NEAR_STEP_YARDS = 30
local NEAR_SLACK_YARDS = 10 -- (an icon's own size, and the step a player takes between two looks)
local nearPlaces, nearSpots = {}, {} -- the near marks and spawn icons, by their indexes
-- The game's herb and ore icons near the player while it tracks them (GatheringSpots): the game draws them under
-- everything of ours, so a mark or spawn icon that would lie on one is left out. Told with what is near
-- (partitionNear); an icon's answer is kept until then, so a move asks nothing of them but the few marks.
local NODE_RADIUS = 6 -- the game's icon, half across, in the minimap's pixels
local nearNodes, nearNodeCount, nodeGeneration = {}, 0, 0 -- north, west, north, west... of the near ones
local nodeX, nodeY = {}, {} -- the near ones in view, in pixels from the middle, at this move
local nodePlace = {} -- (one place, to ask where a node is on a turning minimap)
local isIconOnNode -- (written with partitionNear, read where the icons are placed)
local nearHandovers = {} -- the near marks that the game's own "!" or "?" takes over from, themselves
-- The land is slid every frame by where the player is. The game says that in plain numbers by one call
-- (UnitPosition), where the map's own reckoning (Geometry.getPlayerPosition) is five calls and two tables a frame:
-- used once the two are found to agree, checked again at every move (checkUnitPosition), the map's otherwise.
local unitOffsetNorth, unitOffsetWest, unitContinentId -- the map's reckoning less UnitPosition's, and its continent, as last checked
local unitMismatchCount, MAX_UNIT_MISMATCHES = 0, 5 -- found not to agree with the map this often running: never used again
local UNIT_POSITION_TOLERANCE_YARDS = 0.5
local framePositionAt, frameNorth, frameWest, frameContinentId -- where the player is, read once a frame (getFramePosition)

---Where the player is, for what is asked every frame (the land sliding, the game's own marks taking over): by the
---game's one call that says it in plain numbers, where that was found to agree with the map's reckoning
---(checkUnitPosition); else by the map's, which makes tables for the collector at each asking.
---@return number? north, number? west, number? continentId nil where the game does not say (inside an instance)
local function getFramePosition()
    local frameNumber = ns.frameNumber
    if frameNumber > 0 and framePositionAt == frameNumber then
        return frameNorth, frameWest, frameContinentId
    end
    framePositionAt, frameNorth, frameWest, frameContinentId = frameNumber, nil, nil, nil
    if unitOffsetNorth then
        local north, west, _, continentId = UnitPosition("player")
        if
            type(north) == "number"
            and continentId == unitContinentId
            and not (issecretvalue and issecretvalue(north))
        then
            frameNorth, frameWest, frameContinentId =
                north + unitOffsetNorth, west + unitOffsetWest, lastMove.continentId
            return frameNorth, frameWest, frameContinentId
        end
    end
    local position = ns.Geometry.getPlayerPosition()
    if position then
        frameNorth, frameWest, frameContinentId = position.north, position.west, position.continentId
    end
    return frameNorth, frameWest, frameContinentId
end

---What is drawn on the minimap stands where it is to a fraction of a pixel, never snapped to whole ones: the land
---under it slides smoothly, and a picture snapped to pixels twitches against the land and against its neighbours,
---each jumping to its next pixel at a moment of its own.
---@return table region The same region
local function glide(region)
    if region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
    end
    if region.SetTexelSnappingBias then
        region:SetTexelSnappingBias(0)
    end
    return region
end

---Every part of a mark glides (glide): asked of its parts once, and again when it has got more of them (a mark's
---coin and its item ring are made when a mark first is one).
local function glidePin(pin)
    local count = pin.GetNumRegions and pin:GetNumRegions() or 0
    if type(count) ~= "number" or pin.glidingCount == count then
        return
    end
    pin.glidingCount = count
    for index = 1, count do
        local region = select(index, pin:GetRegions())
        if type(region) == "table" then
            glide(region)
        end
    end
end

-- Whether the minimap turns with the player (the game's setting) is asked for every frame: read 20 times a second
-- (MinimapPins.hasStateChanged) and when the marks are chosen, and kept between; where no frames run (the tests),
-- at every asking.
local isRotatingKept = false

local function readRotating()
    isRotatingKept = GetCVar ~= nil and GetCVar("rotateMinimap") == "1"
    return isRotatingKept
end

local function isMinimapRotating()
    if ns.frameNumber == 0 then
        return readRotating()
    end
    return isRotatingKept
end

local shapeAt, shapeQuarters, shapeName -- the minimap's shape as asked this frame (asked for every mark at every move)

---@return table quarters, string name The minimap's shape: which quarters have a round edge
function MinimapPins.getShape()
    local frameNumber = ns.frameNumber
    if frameNumber > 0 and shapeAt == frameNumber then
        return shapeQuarters, shapeName
    end
    local name = GetMinimapShape and GetMinimapShape() or "ROUND"
    shapeAt, shapeQuarters, shapeName = frameNumber, SHAPES[name] or SHAPES.ROUND, SHAPES[name] and name or "ROUND"
    return shapeQuarters, shapeName
end

---@return number reach How far out a point is, against the minimap's edge in its direction: 1 on the edge. Round
---quarters measure along the radius, square ones by the larger of across and up.
function MinimapPins.getEdgeDistance(right, up)
    local quarter = 1
    if right < 0 then
        quarter = quarter + 1
    end
    if up > 0 then
        quarter = quarter + 2
    end
    if MinimapPins.getShape()[quarter] then
        return math.sqrt(right * right + up * up)
    end
    return math.max(math.abs(right), math.abs(up))
end

---@return number yards How far from the player the minimap can show anything: its radius, or into the corners of a
---square minimap (Forever's own is square), which see further than its radius. What is picked to draw goes this far;
---getOffset then says what is really inside the shape, so nothing pops in well inside a corner as the player nears it.
function MinimapPins.getReach(viewRadius)
    for _, isRound in ipairs(MinimapPins.getShape()) do
        if not isRound then
            return viewRadius * RIM * math.sqrt(2)
        end
    end
    return viewRadius * RIM
end

---Where a place sits on the minimap relative to its centre, in fractions of the radius.
---@param facing number? The player's facing in radians, set when the minimap rotates with the player
---@return number? right, number? up nil when out of range and not kept on the rim
---@return boolean isOnRim
function MinimapPins.getOffset(player, place, viewRadius, facing, isKeptOnRim)
    local right = (player.west - place.west) / viewRadius
    local up = (place.north - player.north) / viewRadius
    if facing then
        local sine, cosine = math.sin(facing), math.cos(facing)
        right, up = right * cosine + up * sine, -right * sine + up * cosine
    end
    local length = MinimapPins.getEdgeDistance(right, up) -- in the minimap's own shape
    if length <= RIM then
        return right, up, false
    end
    if not isKeptOnRim then
        return nil, nil, false
    end
    return right / length * RIM, up / length * RIM, true
end

---@return number scale How large the spawn icons are drawn at a zoom (yards from the middle to the edge), against
---their full size: smaller zoomed out, so the many there leave the map readable
function MinimapPins.getIconScale(viewRadius)
    local share = (viewRadius - ICON_FULL_YARDS) / (ICON_SMALLEST_YARDS - ICON_FULL_YARDS)
    share = math.max(0, math.min(1, share))
    return 1 - (1 - ZOOMED_OUT_ICON_SCALE) * share
end

local function getViewRadius()
    return C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() or DEFAULT_VIEW_RADIUS
end

local areaCache = {} -- [key] = outlines in yards, for a quest's places on one zone map
local areaCacheCount, MAX_CACHED_AREAS = 0, 300

---@return { north: number, west: number, width: number, height: number }? world Where a zone map lies in the world,
---in yards: its upper left corner, and how far it reaches east and south
local function getMapWorld(uiMapId)
    local continentId, north, west = ns.Geometry.getWorldPosition(uiMapId, 0, 0)
    local _, southNorth, eastWest = ns.Geometry.getWorldPosition(uiMapId, 100, 100)
    if not north or not southNorth then
        return nil
    end
    return {
        continentId = continentId,
        north = north,
        west = west,
        width = west - eastWest,
        height = north - southNorth,
    }
end

---@return number? uiMapId The zone map the player is on, as the world map opens to it: a building's, a cave's or
---a town's own small map counts as the zone it lies in
local function getZoneMapId(uiMapId)
    local info = uiMapId and C_Map.GetMapInfo and ns.Database.getMapInfo(uiMapId)
    while info and info.mapType and info.mapType > ZONE_MAP_TYPE and info.parentMapID and info.parentMapID > 0 do
        uiMapId = info.parentMapID
        info = ns.Database.getMapInfo(uiMapId)
    end
    return uiMapId
end

---A quest's areas where the player is, exactly the shapes the world map draws for the player's zone: its places
---put on that zone's map as the map puts them (sub-zones included), the same shapes that follow them, placed in
---the world.
---@return { triangles: table[], edges: table[], points: table[] }[] areas In yards: x west, y north
---@param kind string? What the places are, when not the quest's objectives ("start": where it starts), so each
---kind of a quest's places keeps its own areas
function MinimapPins.composeQuestAreas(questId, places, position, kind)
    local uiMapId = getZoneMapId(position.uiMapId)
    local world = uiMapId and getMapWorld(uiMapId)
    if not world or world.width <= 0 then
        return {}
    end
    -- Kept by what they are made from (the quest, the zone map, the places themselves), so a redraw that changed
    -- none of that gets the very same tables again: the fills laid out for them on the minimap's canvas stay
    local sum = 0
    for index = 1, #places do
        local place = places[index]
        sum = sum + (place.x or 0) * 7919 + (place.y or 0) * 31 + (place.zoneId or 0)
    end
    local cacheKey = string.format("%s:%s:%d:%d:%.4f", kind or "objectives", tostring(questId), uiMapId, #places, sum)
    if areaCache[cacheKey] then
        return areaCache[cacheKey]
    end
    areaCacheCount = areaCacheCount + 1
    if areaCacheCount > MAX_CACHED_AREAS then
        areaCache, areaCacheCount = {}, 1 -- (each other set of places a quest has had is one more: let go together)
    end
    local points = ns.MapMarks.composePoints(places, uiMapId)
    if #points == 0 then
        areaCache[cacheKey] = {}
        return {}
    end
    -- The world map's very shapes (worked out once on each zone's own map), fitted onto this zone's map, then put in
    -- the world: the minimap's areas are the map's
    local shapes, isPending = ns.MapMarks.composeFittedShapes(questId, uiMapId, points)
    local function toYards(point) -- the zone map's fractions to the world's yards
        return { x = world.west - point.x * world.width, y = world.north - point.y * world.height }
    end
    local placed = {}
    for _, area in ipairs(shapes or {}) do
        local triangles, edges, spawns = {}, {}, {}
        for index, triangle in ipairs(area.triangles) do
            triangles[index] = { toYards(triangle[1]), toYards(triangle[2]), toYards(triangle[3]) }
        end
        for index, edge in ipairs(area.edges) do
            edges[index] = { toYards(edge[1]), toYards(edge[2]) }
        end
        for index, point in ipairs(area.points) do
            spawns[index] = toYards(point)
        end
        placed[#placed + 1] = { triangles = triangles, edges = edges, points = spawns }
    end
    if not isPending then
        areaCache[cacheKey] = placed -- one still being worked out is composed again when it is done
    end
    return placed
end

---@return table<number, table[]> places [quest] = where the world map puts its marks on the player's zone map, in
---the world: the minimap puts them there too, so a mark stays put as the player moves, as on the map
local mapMarkPlacesCache = {} -- [zone map and quest in focus] = composeMapMarkPlaces: the whole zone's marks worked
-- out, kept till the quests next change (MinimapPins.refresh), not again every few yards walked

local function composeMapMarkPlaces(position)
    local placesByQuestId = {}
    local uiMapId = getZoneMapId(position.uiMapId)
    if not uiMapId then
        return placesByQuestId
    end
    local cacheKey = uiMapId
        .. ":"
        .. tostring(ns.Focus.get())
        .. ":"
        .. tostring(ns.MapMarks.getFocusedQuestId and ns.MapMarks.getFocusedQuestId())
        .. ":"
        .. ns.Spoilers.getKey()
    if mapMarkPlacesCache[cacheKey] then
        return mapMarkPlacesCache[cacheKey]
    end
    mapMarkPlacesCache[cacheKey] = placesByQuestId
    for _, mark in ipairs(ns.MapMarks.compose(uiMapId, true)) do -- (a peek at the world map is the world map's alone)
        if mark.kind == "objective" and mark.questId and mark.x and mark.y then
            local continentId, north, west = ns.Geometry.getWorldPosition(uiMapId, mark.x * 100, mark.y * 100)
            if north then
                placesByQuestId[mark.questId] = placesByQuestId[mark.questId] or {}
                table.insert(placesByQuestId[mark.questId], { continentId = continentId, north = north, west = west })
            end
        end
    end
    return placesByQuestId
end

---@return number? distance How far a place is from the player, in yards; nil for one not on their continent. A
---place keeps its world position from the first time it is measured.
local function getPlaceDistance(place, player)
    if place.north == nil then
        local continentId, north, west =
            ns.Geometry.getWorldPosition(ns.Database.getUiMapId(place.zoneId), place.x, place.y)
        place.continentId, place.north, place.west = continentId, north or false, west
    end
    if place.north and place.continentId == player.continentId then
        return ns.Geometry.getDistance(player.north, player.west, place.north, place.west)
    end
    return nil
end

---The places within a distance of the player, each a candidate for a mark or a spawn icon.
---@param limitYards number? Further off than this they are left out (nil: all of them)
---@return number nearestBeyond How near the nearest place left out is (math.huge when none was)
local function addPlaces(candidates, places, data, player, isSpawnOnly, limitYards)
    local nearestBeyond = math.huge
    for _, place in ipairs(places) do
        local distance = getPlaceDistance(place, player)
        if distance then
            if not limitYards or distance <= limitYards then
                candidates[#candidates + 1] =
                    { place = place, data = data, distance = distance, isSpawnOnly = isSpawnOnly }
            elseif distance < nearestBeyond then
                nearestBeyond = distance
            end
        end
    end
    return nearestBeyond
end

---@return boolean isHandedOver A turn-in's mark whose place is near enough that the game shows its own "?" there now
function MinimapPins.isHandedOver(shown, position)
    return shown.handoverYards ~= nil
        and ns.Geometry.getDistance(position.north, position.west, shown.place.north, shown.place.west)
            <= shown.handoverYards
end

---@return table[] marks The givers and turn-ins whose place is handed to the game's own "!" or "?" right now and
---stands within radius pixels of a point on the minimap (pixels from its middle, up positive): what the game's mark
---there stands for, which its tooltip only names
function MinimapPins.findGameMarksAt(x, y, radius)
    local position = ns.Geometry.getPlayerPosition()
    if not position or not Minimap then
        return {}
    end
    local viewRadius = getViewRadius()
    local half = (Minimap:GetWidth() or 140) / 2
    local facing = isMinimapRotating() and GetPlayerFacing and GetPlayerFacing() or nil
    local found = {}
    for _, shown in ipairs(shownPlaces) do
        if MinimapPins.isHandedOver(shown, position) then
            local right, up = MinimapPins.getOffset(position, shown.place, viewRadius, facing, false)
            if right and (right * half - x) ^ 2 + (up * half - y) ^ 2 <= radius * radius then
                found[#found + 1] = shown.data
            end
        end
    end
    return found
end

---@return number bits Which marks near the player are handed to the game's "!" or "?" now, a bit each: read every
---frame, so a number, not a string (nothing made each frame for the garbage collector), and only of the marks near
---enough to matter (partitionNear): a far one is neither ours nor the game's to show
function MinimapPins.getHandoverBits()
    if #nearHandovers == 0 then
        return 0 -- (nobody near to hand over to: where the player is need not be asked)
    end
    local north, west = getFramePosition()
    if not north then
        return -1
    end
    local bits, bit = 0, 1
    for index = 1, #nearHandovers do
        local shown = nearHandovers[index]
        local place = shown.place
        local awayNorth, awayWest = place.north - north, place.west - west
        if awayNorth * awayNorth + awayWest * awayWest <= shown.handoverYards * shown.handoverYards then
            bits = bits + bit
        end
        bit = bit * 2
    end
    return bits
end
function MinimapPins.getHandoverKey()
    local bits = MinimapPins.getHandoverBits()
    return bits < 0 and "" or tostring(bits)
end

---The tooltip of a "?" or "!" drawn in the game's look: as any mark's (MapMarks.addMarkLines), its quests with their
---level, group mark and experience, the details while Shift is held. (No clicks: it has no click hint.)
local function showGamePinTooltip(pin)
    if not pin.mark then
        return
    end
    GameTooltip:SetOwner(pin, "ANCHOR_LEFT")
    ns.MapMarks.addMarkLines(GameTooltip, pin.mark)
    ns.QuestTooltip.addHint(GameTooltip)
    GameTooltip:Show()
    ns.QuestTooltip.watch(GameTooltip, pin, showGamePinTooltip, pin) -- Shift down or up: filled again
end

---A turn-in's mark in view, as the game draws its own: the "?" art alone, sized against the minimap.
function MinimapPins.acquireGamePin(index, data)
    local pin = gamePins[index]
    if not pin then
        pin = ns.Widgets.remember(CreateFrame("Frame", nil, Minimap))
        pin.isOurs = true -- not another addon's pin to keep clear of (it would step away from itself)
        pin.icon = ns.Widgets.remember(glide(pin:CreateTexture(nil, "ARTWORK"))) -- (dressed at every placing: the same again is free)
        pin.icon:SetAllPoints(pin)
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", showGamePinTooltip)
        pin:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        gamePins[index] = pin
    end
    -- The size the player chose, which may have changed since it was made. (A new one too: left at the game's size
    -- the first time it was used, it stood beside its place, further off the further the player had walked.)
    -- The game's own size against the minimap, times the size the player chose (MARK_SCALE is that over the base: the
    -- marks' own scale; dividing by it alone undid the choice)
    pin:SetScale(MARK_SCALE)
    local size = (Minimap:GetWidth() or 140) * GAME_ICON_SHARE / BASE_MARK_SCALE
    pin:SetSize(size, size)
    pin:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 6)
    -- A turn-in's "?", or a quest giver's "!", in the colour chosen for its kind of quest
    local isTurnIn = data.kind ~= "giver"
    ns.MapMarks.dressQuestIcon(pin.icon, ns.MapMarks.getIconColour(ns.MapMarks.getIconKind(data, isTurnIn)), isTurnIn)
    pin.drawnSize, pin.raise, pin.mark = size, 0, data
    return pin
end

---`/omq distance`: how far the followed quest's place is, and how far the minimap sees: for measuring where the game's
---own "?" comes and goes (TURN_IN_HANDOVER_YARDS)
function MinimapPins.printDistance()
    local questId = ns.Focus.get()
    local entry = questId and ns.Model.composeEntry(questId, ns.Model.getPlayer())
    if not entry or not entry.distance then
        ns.print(ns.L("follow a quest first: its nearest place is measured."))
        return
    end
    local viewRadius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius() or DEFAULT_VIEW_RADIUS
    ns.print(
        string.format(
            "%s: %d yards; the minimap sees %d yards round you.",
            entry.title,
            math.floor(entry.distance + 0.5),
            math.floor(viewRadius * RIM + 0.5)
        )
    )
end

---Picks the places worth a mark: everything in range, nearest first, plus the highlighted quest's nearest place.
---@return { place: table, data: table, isKeptOnRim: boolean }[] places Each with the mark to draw as data
---@return { place: table, isFocused: boolean }[] spots The other places of tracked quests in range, drawn as squares
---@return table[] areas Each tracked quest's areas near the player, for "icons and areas"
local GIVER_PATROL_COLOR = { 1, 0.86, 0.2 } -- the gold of a quest giver's "!"

---Patrols as areas with nothing inside: each path's legs as edges, in yards, drawn the way areas' edges are (cut at
---the rim, round the party's dots), its points for being near enough to draw and to hover.
---@param base table What each area carries besides: questId, number, isFocused, color (the quest's when left out)
local function addPatrolAreas(composedAreas, patrols, position, base)
    for _, patrol in ipairs(patrols) do
        local edges, points, last = {}, {}, nil
        for _, point in ipairs(patrol.points) do
            local continentId, north, west =
                ns.Geometry.getWorldPosition(ns.Database.getUiMapId(patrol.zoneId), point[1], point[2])
            local here = north and continentId == position.continentId and { x = west, y = north } or nil
            if here and last then
                edges[#edges + 1] = { last, here }
            end
            points[#points + 1] = here
            last = here
        end
        if #edges > 0 then
            local name = patrol.npcId and ns.Database.getNpcField(patrol.npcId, "name")
            composedAreas[#composedAreas + 1] = {
                questId = base.questId,
                number = base.number,
                isFocused = base.isFocused,
                color = base.color,
                isPatrol = true,
                triangles = {},
                edges = edges,
                points = points,
                note = name and ns.L("%s walks here", name) or nil,
            }
        end
    end
end

-- "Rough" (Spoilers) on the minimap: each circle an area with no fill, its edge a ring of dashes (every other leg of a
-- round of LEGS), in the world's yards; made once a circle, so the canvas keeps what it laid out for it. Its ring is
-- drawn whatever the areas' outline is set to (it is all there is of its quest), at these strengths.
-- (One table: the file's main chunk is near Lua's limit of local names.)
local Rough = {
    LEGS = 40,
    RIM_ALPHA = 0.3,
    FOCUSED_RIM_ALPHA = 0.6,
    EDGE_ALPHA = 0.6,
    FOCUSED_EDGE_ALPHA = 0.95,
    areas = setmetatable({}, { __mode = "k" }), -- [a circle] = its area, or false off any map
}

---@return table? area A rough circle as the minimap's areas are: { triangles, edges, points (its middle), continentId,
---hoverYards (its radius) }
function Rough.getArea(circle)
    local roughAreas, ROUGH_LEGS = Rough.areas, Rough.LEGS
    local area = roughAreas[circle]
    if area == nil then
        local place = circle.place
        local continentId, north, west =
            ns.Geometry.getWorldPosition(ns.Database.getUiMapId(place.zoneId), place.x, place.y)
        area = false
        if north then
            local radius, edges, previous = circle.radiusYards, {}, nil
            for leg = 0, ROUGH_LEGS do
                local angle = leg / ROUGH_LEGS * 2 * math.pi
                local point = { x = west + radius * math.cos(angle), y = north + radius * math.sin(angle) }
                if previous and leg % 2 == 1 then
                    edges[#edges + 1] = { previous, point }
                end
                previous = point
            end
            area = {
                triangles = {},
                edges = edges,
                points = { { x = west, y = north } },
                continentId = continentId,
                hoverYards = radius,
            }
        end
        roughAreas[circle] = area
    end
    return area or nil
end

---One tracked quest's marks, spawns and areas on the minimap: as on the world map, or, while something is held back
---(Spoilers), only what may show of it (shownStep: MapMarks.getShownStep).
---@return number nearestLeftOut How near the nearest of its places left out is (math.huge when none was)
local function addQuestPlaces(
    candidates,
    composed,
    composedAreas,
    entry,
    shownStep,
    mapMarkPlaces,
    position,
    numbers,
    isActive,
    regionYards,
    gatherYards
)
    local questId = entry.questId
    local nearestLeftOut = math.huge
    -- Where its pointer and its marks may lead, and which places are its spawns: its own, or what may show of them
    local nearestPlace, nearestOf, spawnPlaces = entry.nearestPlace, entry.places, entry.allPlaces
    if shownStep then
        nearestOf, spawnPlaces = shownStep.places, shownStep.spawns
        nearestPlace = select(3, ns.Geometry.getNearest(nearestOf, position, ns.Database.getUiMapId))
    end
    local title = string.format("[%d] %s", entry.level, entry.title)
    local mark = {
        kind = entry.isTurnIn and "turnIn" or "objective",
        questId = questId,
        isFocused = isActive,
        glyph = ns.MapMarks.getQuestGlyph(questId, entry.objectives),
        number = numbers[questId],
        progress = entry.isTurnIn and 1 or ns.MapMarks.getProgress(entry),
        lines = {
            title,
            entry.isTurnIn and ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver")) or nil,
        },
        counted = not entry.isTurnIn and {} or nil, -- how far along it is, read afresh as its tooltip opens (MapMarks.refreshMarkTexts)
    }
    if isActive and nearestPlace then
        -- The followed quest's nearest place has a pointer on the rim while it is out of view. Which place is
        -- the nearest, and whether it is in view, follow the player (MinimapPins.move, .followNearest)
        composed[#composed + 1] = { place = nearestPlace, data = mark, isKeptOnRim = true, nearestOf = nearestOf }
    end
    local fixedPlaces = not entry.isTurnIn and mapMarkPlaces[questId]
    if entry.isTurnIn then
        -- Whom it is handed in to has the game's own "?" on the minimap once near: ours points the way from the rim
        -- for the followed quest (above), and stands at the place in view until the game's has surely come
        -- Always composed: whether its place is in view is the minimap's own shape's to say (a square one sees
        -- further in its corners than its radius), checked as it moves
        if nearestPlace and nearestPlace.continentId == position.continentId then
            composed[#composed + 1] = {
                place = nearestPlace,
                data = mark,
                isKeptOnRim = false,
                handoverYards = TURN_IN_HANDOVER_YARDS,
                isGameLook = true,
                nearestOf = nearestOf,
            }
        end
    elseif fixedPlaces then
        -- Its mark where the world map has it, every spawn an icon of its own
        for _, place in ipairs(fixedPlaces) do
            if place.continentId == position.continentId then
                local distance = ns.Geometry.getDistance(position.north, position.west, place.north, place.west)
                if distance <= regionYards then
                    composed[#composed + 1] = { place = place, data = mark, isKeptOnRim = false, distance = distance }
                else
                    nearestLeftOut = math.min(nearestLeftOut, distance)
                end
            end
        end
        nearestLeftOut = math.min(nearestLeftOut, addPlaces(candidates, spawnPlaces, mark, position, true, gatherYards))
    else
        -- Not drawn on this zone's map (a dungeon's quest, a place over the zone's edge): its mark at the
        -- nearest of its places
        nearestLeftOut = math.min(
            nearestLeftOut,
            addPlaces(candidates, shownStep and nearestOf or entry.allPlaces, mark, position, false, gatherYards)
        )
    end
    if entry.isTurnIn then
        return nearestLeftOut
    end
    if shownStep and shownStep.circles then
        -- Rough: a dashed ring round each area, no spawn and no shape
        for _, circle in ipairs(shownStep.circles) do
            local area = Rough.getArea(circle)
            if area and area.continentId == position.continentId then
                composedAreas[#composedAreas + 1] = {
                    questId = questId,
                    number = numbers[questId],
                    isFocused = isActive,
                    isRough = true,
                    hoverYards = area.hoverYards,
                    triangles = area.triangles,
                    edges = area.edges,
                    points = area.points,
                    note = ns.L("Somewhere here"),
                }
            end
        end
        return nearestLeftOut
    end
    for _, area in
        ipairs(MinimapPins.composeQuestAreas(questId, spawnPlaces or {}, position, shownStep and "found" or nil))
    do
        composedAreas[#composedAreas + 1] = {
            questId = questId,
            number = numbers[questId],
            isFocused = isActive,
            triangles = area.triangles,
            edges = area.edges,
            points = area.points,
        }
    end
    -- Where its creatures walk: each patrol drawn as an area's edge with nothing inside, in every look (only with its
    -- objectives shown exactly)
    if not shownStep then
        addPatrolAreas(
            composedAreas,
            ns.Location.getObjectivePatrols(questId),
            position,
            { questId = questId, number = numbers[questId], isFocused = isActive }
        )
    end
    return nearestLeftOut
end

---@return number validYards How far the player may walk from here before something left out could come into view:
---all of it holds till then (math.huge: nothing was left out)
function MinimapPins.compose(viewRadius)
    local position = ns.Geometry.getPlayerPosition()
    if not position then
        return {}, {}, {}, math.huge
    end
    local player = ns.Model.getPlayer()
    local activeQuestId = ns.Focus.get()
    local numbers = ns.QuestState.getWatchNumbers()
    local candidates, composed, composedAreas = {}, {}, {}
    local mapMarkPlaces = composeMapMarkPlaces(position)
    -- What is chosen: everything within what the minimap sees and a margin past it (REGION_MARGIN_YARDS). How near
    -- the nearest place left out is says how far the player may walk before the choosing is done again.
    local reach = MinimapPins.getReach(viewRadius)
    local regionYards = reach + REGION_MARGIN_YARDS
    local nearestLeftOut = math.huge
    -- The spawns thinned as on the world map, in the same world squares, to the minimap's zoom: the same spawns kept,
    -- each on its own spot, whichever map shows them. (Spawns are gathered a square past the region: which of a
    -- square's spawns is kept is then the same wherever the region's edge cuts it.)
    local minimapRadius = Minimap and Minimap.GetWidth and (Minimap:GetWidth() or 0) / 2 or 0
    local spacing = minimapRadius > 0
            and viewRadius > 0
            and ns.MapMarks.chooseSpawnSpacing(
                minimapRadius / viewRadius,
                MinimapPins.spawnSpacing,
                ns.MapMarks.getSpawnMarkerRoom(ns.settings.minimapSpawnMarkerScale)
            )
        or 0
    MinimapPins.spawnSpacing = spacing
    local gatherYards = regionYards + spacing * 1.5

    -- What the player chose to see (Spoilers; nil in Guide, where all of it shows)
    local spoilers = ns.MapMarks.getSpoilers(true)
    for _, questId in ipairs(ns.QuestState.getShownOnMapQuestIds()) do -- (tracked, and any ready to hand in)
        local entry = ns.Model.composeEntry(questId, player)
        -- While something is held back: what of its step may show (nil: all of it), nothing at all when none may
        local shownStep = spoilers and ns.MapMarks.getShownStep(entry, spoilers)
        if not (shownStep and shownStep.isHidden) then
            nearestLeftOut = math.min(
                nearestLeftOut,
                addQuestPlaces(
                    candidates,
                    composed,
                    composedAreas,
                    entry,
                    shownStep,
                    mapMarkPlaces,
                    position,
                    numbers,
                    questId == activeQuestId,
                    regionYards,
                    gatherYards
                )
            )
        end
    end

    if
        player.zoneId
        and ns.Availability.isReady()
        and ns.Availability.isShownOnMap()
        and not (spoilers and spoilers.get("pickup") == "none")
    then
        -- A giver with several quests is one mark: its quests share the same place, and its tooltip lists them
        local markByPlace, giverPlaces = {}, {}
        -- A quest giver has the game's own "!" on the minimap, with its arrow: ours only for what the game cannot
        -- show, a quest that starts from a dropped item, and the quest selected on the Available tab
        -- (kept with the quest log closed, so it shows while the player walks there)
        local selectedQuestId = ns.Log.getChosenAvailableQuestId and ns.Log.getChosenAvailableQuestId()
        local isPatrolDrawn = {}
        for _, quest in
            ipairs(
                ns.Availability.getQuests(
                    player.zoneId,
                    { shouldShowLowLevel = ns.settings.shouldShowLowLevel, shouldIncludeEntrances = true }
                )
            )
        do
            -- (while something is held back, only the quests the player chose to see: Spoilers)
            local isOffered = not quest.availableAtLevel
                and not quest.isHandedInHere
                and (not spoilers or ns.MapMarks.isGiverQuestShown(spoilers, quest.questId))
            -- The selected quest's giver, and whom it is handed in to, when they walk about: their paths in gold
            if quest.questId == selectedQuestId and isOffered then
                local isSelected = true
                local npcIds = ns.Location.getStarterNpcIds(quest.questId)
                if isSelected and (not spoilers or ns.MapMarks.isTurnInShown(spoilers, quest.questId)) then
                    for _, npcId in ipairs((ns.Database.getQuestField(quest.questId, "finishedBy") or {})[1] or {}) do
                        npcIds[#npcIds + 1] = npcId
                    end
                end
                for _, npcId in ipairs(npcIds) do
                    local key = npcId .. (isSelected and ":selected" or "")
                    if not isPatrolDrawn[key] then
                        isPatrolDrawn[key] = true
                        addPatrolAreas(
                            composedAreas,
                            ns.Location.getNpcPatrols(npcId),
                            position,
                            { questId = quest.questId, isFocused = isSelected, color = GIVER_PATROL_COLOR }
                        )
                    end
                end
            end
            if quest.questId == selectedQuestId and isOffered then
                -- Where the selected quest starts when that is creatures (an item they drop, or several givers about):
                -- their spawns and areas, as the world map shows them, in the gold of the quest's "!"
                local itemSource = quest.startType == "item" and ns.Location.getStartItemSource(quest.questId)
                local startPlaces = itemSource and itemSource.places or quest.places or {}
                if #startPlaces > 1 then
                    local spawnMark = {
                        kind = "objective",
                        questId = quest.questId,
                        isFocused = true,
                        lines = {},
                        color = GIVER_PATROL_COLOR,
                    }
                    local spawns = {}
                    for index, place in ipairs(startPlaces) do
                        local copy = {}
                        for key, value in pairs(place) do
                            copy[key] = value
                        end
                        copy.glyph = copy.glyph or (quest.startType == "item" and "loot" or "talk")
                        spawns[index] = copy
                    end
                    nearestLeftOut =
                        math.min(nearestLeftOut, addPlaces(candidates, spawns, spawnMark, position, true, gatherYards))
                    for _, area in ipairs(MinimapPins.composeQuestAreas(quest.questId, spawns, position, "start")) do
                        composedAreas[#composedAreas + 1] = {
                            questId = quest.questId,
                            isFocused = true,
                            color = GIVER_PATROL_COLOR,
                            triangles = area.triangles,
                            edges = area.edges,
                            points = area.points,
                        }
                    end
                end
            end
            if isOffered then
                local line = string.format("[%d] %s", quest.level, quest.title)
                    .. (quest.starterName and (" - " .. quest.starterName) or "")
                -- Only the nearest place of each quest: one that starts from a dropped item would otherwise
                -- mark every creature around (and while something is held back, one out of the map's fog, outside a
                -- dungeon held back)
                local place = quest.nearestPlace or quest.places[1]
                if place and (not spoilers or ns.MapMarks.isGiverPlaceShown(spoilers, quest.questId, place)) then
                    local mark = markByPlace[place]
                    if not mark then
                        mark = {
                            kind = "giver",
                            questId = quest.questId,
                            isFocused = false,
                            count = 0,
                            questIds = {},
                            lines = {},
                            itemIcon = ns.MapMarks.getStartItemIcon(quest),
                            isLowLevel = true,
                            isRepeatable = true,
                            isGameLook = true,
                        }
                        markByPlace[place] = mark
                        giverPlaces[#giverPlaces + 1] = place
                    end
                    -- The game's own "!" is drawn only for a giver standing there; one that starts from a dropped
                    -- item, and the selected quest, keep our mark
                    if quest.startType == "item" or quest.questId == selectedQuestId then
                        mark.isGameLook = false
                    end
                    mark.count = mark.count + 1
                    -- Grey or blue only when every quest of the giver is
                    mark.isLowLevel = mark.isLowLevel and quest.isLowLevel == true
                    mark.isRepeatable = mark.isRepeatable and ns.Availability.isRepeatable(quest.questId)
                    mark.questIds[mark.count], mark.lines[mark.count] = quest.questId, line
                end
            end
        end
        for _, place in ipairs(giverPlaces) do
            local mark = markByPlace[place]
            if mark.isGameLook then
                -- A giver standing there has the game's own "!" once the server has sent them (as a turn-in's "?",
                -- TURN_IN_HANDOVER_YARDS); further out, in view, ours, drawn just like it, so the zone's givers show
                -- before the game's come
                local distance = getPlaceDistance(place, position)
                if distance and distance <= regionYards then
                    composed[#composed + 1] = {
                        place = place,
                        data = mark,
                        isKeptOnRim = false,
                        handoverYards = TURN_IN_HANDOVER_YARDS,
                        isGameLook = true,
                        distance = distance,
                    }
                elseif distance then
                    nearestLeftOut = math.min(nearestLeftOut, distance)
                end
            else
                nearestLeftOut =
                    math.min(nearestLeftOut, addPlaces(candidates, { place }, mark, position, false, gatherYards))
            end
        end
    end

    if spacing > 0 then
        local spawnsByData, isKept = {}, {}
        for _, candidate in ipairs(candidates) do
            if candidate.isSpawnOnly then
                spawnsByData[candidate.data] = spawnsByData[candidate.data] or {}
                table.insert(spawnsByData[candidate.data], { place = candidate.place, candidate = candidate })
            end
        end
        for _, spawns in pairs(spawnsByData) do
            for _, point in ipairs(ns.MapMarks.thinPoints(spawns, spacing)) do
                isKept[point.candidate] = true
            end
        end
        local thinned = {}
        for _, candidate in ipairs(candidates) do
            if not candidate.isSpawnOnly or isKept[candidate] then
                thinned[#thinned + 1] = candidate
            end
        end
        candidates = thinned
    end
    -- Nearest first: a quest's nearest place gets its mark, the rest of its places are squares
    table.sort(candidates, function(first, second)
        return first.distance < second.distance
    end)
    local isMarked, composedSpots = {}, {}
    for _, candidate in ipairs(candidates) do
        if candidate.distance > regionYards then
            nearestLeftOut = math.min(nearestLeftOut, candidate.distance) -- (gathered past the region for the thinning only)
            break
        end
        local data = candidate.data
        local isSpot = candidate.isSpawnOnly or (data.kind ~= "giver" and isMarked[data])
        if not isSpot then
            isMarked[data] = true
            composed[#composed + 1] =
                { place = candidate.place, data = data, isKeptOnRim = false, distance = candidate.distance }
        end
        -- (a mark does not take its place's spawn icon: the spawn keeps it, and the mark steps beside it)
        if isSpot or data.kind == "objective" then
            if #composedSpots < MAX_SPOTS then
                composedSpots[#composedSpots + 1] = {
                    place = candidate.place,
                    isFocused = data.isFocused == true,
                    number = data.number,
                    questId = data.questId,
                    color = candidate.isSpawnOnly and data.color or nil,
                }
            else
                nearestLeftOut = math.min(nearestLeftOut, candidate.distance)
            end
        end
    end
    -- More marks than are drawn: the furthest go (never the rim's pointer, nor whom a quest is handed in to)
    local droppable = {}
    for _, shown in ipairs(composed) do
        if shown.distance then
            droppable[#droppable + 1] = shown.distance
        end
    end
    if #composed > MAX_PINS and #droppable > 0 then
        table.sort(droppable)
        local limit = droppable[math.max(1, #droppable - (#composed - MAX_PINS) + 1)]
        local kept = {}
        for _, shown in ipairs(composed) do
            if shown.distance and shown.distance >= limit then
                nearestLeftOut = math.min(nearestLeftOut, shown.distance)
            else
                kept[#kept + 1] = shown
            end
        end
        composed = kept
    end
    local validYards = nearestLeftOut == math.huge and math.huge
        or math.max(MIN_VALID_YARDS, nearestLeftOut - reach - VALID_SLACK_YARDS)
    return composed, composedSpots, composedAreas, validYards
end

---Chooses the pins again. Runs about once a second and when quests change.
local isBuiltInAreaHidden = false

---The game draws its own quest areas on the minimap itself; with this addon's marks replacing the game's (as on
---the world map), they are made fully see-through. The game has no way to read their look back, so once hidden
---they return only with a reload.
function MinimapPins.applyBuiltInAreas()
    if not Minimap or not Minimap.SetQuestBlobInsideAlpha then
        return
    end
    local shouldHide = ns.settings.shouldShowMapPins
        and ns.settings.shouldHideBuiltInMapPins
        and ns.settings.shouldShowMinimapPins
    if shouldHide and not isBuiltInAreaHidden then
        isBuiltInAreaHidden = true
        Minimap:SetQuestBlobInsideAlpha(0)
        Minimap:SetQuestBlobOutsideAlpha(0)
        Minimap:SetQuestBlobRingAlpha(0)
    elseif not shouldHide and isBuiltInAreaHidden then
        isBuiltInAreaHidden = false
        ns.print(ns.L("the game's own quest areas come back on the minimap after a /reload."))
    end
end

local refreshNow

---Chooses and draws the minimap's marks again. On the game's own placing, whatever view the world map has set
---(OpenMap's joined-on zones are the world map's alone), so the minimap's marks are the zone map's.
function MinimapPins.refresh()
    mapMarkPlacesCache = {} -- the quests, or the settings, changed: where their marks stand is worked out again
    ns.MapPins.withoutView(refreshNow)
end

-- { zoneMapId, north, west, viewRadius, width, choices, isOnCanvas, validYards, dataKey }: where the player was, and
-- what the marks followed, when they were last chosen
local composedAt
local isComposing = false -- while the marks just chosen are being placed
local areMarksShown = true -- the minimap's marks are switched on (as last chosen: refreshNow)

---The redraw of everything. A quiet one (nothing asked for it but the quest log's news, Core's Module.refresh) with
---the quests standing where they did keeps the minimap as it is laid out: a kill or a loot counted changes nothing
---on it, and its marks' words are read afresh as a tooltip opens (MapMarks.refreshMarkTexts).
function MinimapPins.refreshAfterChange(isQuiet)
    if
        isQuiet
        and frame
        and composedAt
        and not ns.MapPins.isKeepingOff
        and composedAt.dataKey == ns.MapPins.getDataKey()
    then
        MinimapPins.keptCount = (MinimapPins.keptCount or 0) + 1 -- (how often: read by the simulator's audits)
        return
    end
    MinimapPins.refresh()
end

---@return number? facing Where the player faces, when the minimap turns with them
local function getFacing()
    return isMinimapRotating() and GetPlayerFacing and GetPlayerFacing() or nil
end

---@return boolean isOnCanvas The spawn icons ride their canvas (see the areas' drawing): the player's place is known,
---the minimap does not turn with them, and it has a size and a zoom to scale the canvas by
local function isSpotCanvasUsed(position, facing)
    return position ~= nil
        and spotCanvas ~= nil
        and not facing
        and MinimapPins.isCanvasOff ~= true
        and (Minimap:GetWidth() or 0) > 0
        and getViewRadius() > 0
end

---@return string choices What the marks follow that changes with no redraw of its own: the quest in focus, the
---quest picked on the Available tab, and whether the quest givers are known yet
local function getShownChoices()
    local chosenAvailable = ns.Log and ns.Log.getChosenAvailableQuestId and ns.Log.getChosenAvailableQuestId()
    -- The quest in focus as the maps take it: the one selected in the quest window while it is open, else the followed one
    local focused = ns.MapMarks.getFocusedQuestId and ns.MapMarks.getFocusedQuestId()
    return tostring(ns.Focus.get())
        .. ":"
        .. tostring(focused)
        .. ":"
        .. tostring(chosenAvailable)
        .. ":"
        .. tostring(ns.Availability.isReady())
end

---@return boolean isStale The zoom, the zone's map or the minimap's size changed since the minimap was laid out, or
---the player has walked so far from where it was that something left out could come into view (validYards: as far
---as the land was laid out; for good where nothing was left out). Otherwise all of it stands.
function MinimapPins.isCompositionStale(position, viewRadius, width)
    if not composedAt then
        return true
    end
    if not position then
        return composedAt.zoneMapId ~= nil
    end
    return getZoneMapId(position.uiMapId) ~= composedAt.zoneMapId
        or viewRadius ~= composedAt.viewRadius
        or width ~= composedAt.width
        or ns.Geometry.getDistance(position.north, position.west, composedAt.north, composedAt.west)
            >= composedAt.validYards
end

local partitionedAt -- where the player was when what is near was last told from what is far (partitionNear)

---A mark that stands at the nearest of several places (the followed quest's pointer on the rim, whom a quest is
---handed in to where they stand in more than one place) moves to another of them once that is the nearest.
---@return boolean hasChanged One of them moved
function MinimapPins.followNearest(position)
    local hasChanged = false
    for index = 1, #shownPlaces do
        local shown = shownPlaces[index]
        local places = shown.nearestOf
        if places and #places > 1 then
            local nearest, nearestDistance = shown.place, nil
            for placeIndex = 1, #places do
                local place = places[placeIndex]
                local distance = getPlaceDistance(place, position)
                if distance and (not nearestDistance or distance < nearestDistance) then
                    nearest, nearestDistance = place, distance
                end
            end
            if nearest ~= shown.place then
                shown.place, hasChanged = nearest, true
            end
        end
    end
    return hasChanged
end

---Every second: the minimap laid out again once the player has left the land it was laid out for (or the zoom, the
---zone or what is selected changed); within it, only whichever of a quest's places is the nearest is looked at.
function MinimapPins.tick()
    if not frame then
        return
    end
    local position = ns.Geometry.getPlayerPosition()
    if
        MinimapPins.isCompositionStale(position, getViewRadius(), Minimap:GetWidth() or 0)
        or getShownChoices() ~= (composedAt and composedAt.choices)
    then
        ns.MapPins.withoutView(refreshNow)
    elseif position and MinimapPins.followNearest(position) then
        partitionedAt = nil
        ns.Timing.measure("minimap marks placed", MinimapPins.move)
    end
end

---@return number key A place in the world as one number, to an eighth of a yard: what a mark or an icon stood for
local function getPlaceKey(place)
    return math.floor((place.north or 0) * 8 + 0.5) * 2097152 + math.floor((place.west or 0) * 8 + 0.5)
end

local function getSpotSecond(shown)
    return shown.questId or 0
end

local function getPinSecond(shown)
    return (shown.data.questId or 0) * 2 + (shown.isKeptOnRim and 1 or 0)
end

local matchScratch = {}

---Puts a pool of marks or icons in the order of what it is to show now, each thing keeping the object that showed
---it last (told by its place and a number of its own: shownFor, shownSecond), so that choosing again changes only
---what really changed: a spawn's icon stays the very textures it was, dressed and standing on its spot. What is new
---takes the objects left over; where none are left the pool has a gap, which the caller fills with a new one.
local function matchPool(pool, shownList, getSecond)
    local poolCount, shownCount = #pool, #shownList
    local byKey = {}
    for index = poolCount, 1, -1 do -- (backwards: of two with one key, the earlier is found first)
        local item = pool[index]
        item.isMatched = false
        local key = item.shownFor
        -- (every field written before it is read, and never nil: the tests' stand-ins answer for what they lack)
        item.nextSame = false
        if type(key) == "number" then
            item.nextSame = byKey[key] or false
            byKey[key] = item
        end
    end
    local ordered = matchScratch
    for index = 1, shownCount do
        local shown = shownList[index]
        local second = getSecond(shown)
        local item = byKey[getPlaceKey(shown.place)]
        while item and (item.isMatched or item.shownSecond ~= second) do
            item = item.nextSame
        end
        if item then
            item.isMatched = true
        end
        ordered[index] = item or false
    end
    local free = 1
    for index = 1, shownCount do
        if not ordered[index] then
            while free <= poolCount and pool[free].isMatched do
                free = free + 1
            end
            if free <= poolCount then
                pool[free].isMatched = true
                ordered[index] = pool[free]
            end
        end
    end
    local count = shownCount -- those left over come after: the caller hides them
    for index = 1, poolCount do
        local item = pool[index]
        if not item.isMatched then
            count = count + 1
            ordered[count] = item
        end
    end
    for index = 1, math.max(count, poolCount) do
        pool[index] = ordered[index] or nil
        ordered[index] = nil
    end
end

---Chooses the marks, spawn icons and areas (none when isShown is false) and dresses the pools for them: what was
---shown before and is not now is hidden.
local function chooseAndDress(isShown)
    MinimapPins.applyBuiltInAreas()
    MARK_SCALE = BASE_MARK_SCALE * math.max(0.5, math.min(2, tonumber(ns.settings.minimapMarkScale) or 1))
    shownPlaces, shownSpots, shownAreas = {}, {}, {}
    partitionedAt = nil -- what is near is told again for what is chosen now (by the placing this ends with)
    if isShown then
        shownPlaces, shownSpots, shownAreas, composedAt.validYards = MinimapPins.compose(getViewRadius())
        if not ns.MapMarks.hasAreas() then
            -- No areas; patrols in every look
            local patrols = {}
            for _, area in ipairs(shownAreas) do
                if area.isPatrol then
                    patrols[#patrols + 1] = area
                end
            end
            shownAreas = patrols
        elseif ns.settings.shouldShowFocusedAreasOnly then
            -- As on the world map: only the quest in focus has its areas; patrols stay
            local kept = {}
            for _, area in ipairs(shownAreas) do
                if area.isPatrol or area.isFocused then
                    kept[#kept + 1] = area
                end
            end
            shownAreas = kept
        end
        -- The focused quest's markers first: they claim their cells of the grid before the others'; and the
        -- others' only when the player has not hidden them (or all markers)
        local focused, others = {}, {}
        local hasMarkers = ns.MapMarks.getSpawnMarker() ~= "none"
        local hasOthers = ns.MapMarks.getSpawnMarkerStrength(false)
        for _, shown in ipairs(hasMarkers and shownSpots or {}) do
            if shown.isFocused or hasOthers then
                table.insert(shown.isFocused and focused or others, shown)
            end
        end
        for _, shown in ipairs(others) do
            focused[#focused + 1] = shown
        end
        shownSpots = focused
    end
    local kind = ns.MapMarks.getSpawnMarker()
    local iconScale = MinimapPins.getIconScale(getViewRadius())
        * math.max(0.5, math.min(2, tonumber(ns.settings.minimapSpawnMarkerScale) or 1))
    -- Where the icons ride their canvas they are its own, and their sizes are in its units, yards: as many as make
    -- their pixels at this zoom. (A change of the zoom, or of the way they are placed, chooses the marks again.)
    local spotParent, unit = frame, 1
    if composedAt.isOnCanvas then
        spotParent, unit = spotCanvas, getViewRadius() / ((Minimap:GetWidth() or 140) / 2)
    end
    local remember = ns.Widgets.remember
    matchPool(spots, shownSpots, getSpotSecond)
    for spotIndex = 1, #shownSpots do
        local spot = spots[spotIndex]
        if not spot then
            -- Two textures, one under and one over (a glow and a glyph, a plate and a glyph, a square and its
            -- edge), moved together. Each remembers what it was last given: the same spot chosen again as it was
            -- asks nothing of the game.
            spot = {
                under = remember(glide(spotParent:CreateTexture(nil, "ARTWORK"))),
                over = remember(glide(spotParent:CreateTexture(nil, "ARTWORK"))),
                parent = spotParent,
            }
            spot.bothTextures, spot.overTextures = { spot.under, spot.over }, { spot.over }
            spots[spotIndex] = spot
        end
        if spot.parent ~= spotParent then
            spot.parent = spotParent
            for _, texture in ipairs(spot.bothTextures) do
                texture:SetParent(spotParent)
                texture.omqLayer = nil -- its layer is given again below, on its new frame
            end
        end
        local shown = shownSpots[spotIndex]
        spot.shownFor, spot.shownSecond = getPlaceKey(shown.place), getSpotSecond(shown)
        local color = shown.color or ns.MapMarks.getQuestColor(shown.number, shown.questId)
        local _, isStrong = ns.MapMarks.getSpawnMarkerStrength(shown.isFocused == true)
        -- The focused quest's spawns a little larger, and over the others'
        local size = (ICON_SIZE + (shown.isFocused and 2 or 0)) * iconScale * unit
        local hasUnder = ns.MapMarks.dressSpawnMarker(
            spot.under,
            spot.over,
            kind,
            shown.place.glyph or "use",
            color,
            isStrong,
            size,
            ICON_GLOW_SIZE * iconScale * unit
        )
        spot.under:SetDrawLayer("ARTWORK", shown.isFocused and 3 or 1)
        spot.over:SetDrawLayer("ARTWORK", shown.isFocused and 4 or 2)
        if not hasUnder then
            spot.under:Hide() -- (a glyph with its glow switched off)
        end
        spot.textures = hasUnder and spot.bothTextures or spot.overTextures
        -- (whether its parts show, and where, is the placing's to say: MinimapPins.move)
    end
    for spotIndex = #shownSpots + 1, #spots do
        local spot = spots[spotIndex]
        spot.isIn = false
        spot.under:Hide()
        spot.over:Hide()
    end
    local gameCount = 0
    matchPool(pins, shownPlaces, getPinSecond)
    for pinIndex, shown in ipairs(shownPlaces) do
        local pin = pins[pinIndex]
        if not pin then
            pin = ns.MapMarks.createMarkButton(Minimap)
            pins[pinIndex] = pin
        end
        pin.shownFor, pin.shownSecond = getPlaceKey(shown.place), getPinSecond(shown)
        pin:SetScale(MARK_SCALE) -- every time: the size the player chose may have changed since it was made
        shown.frame = nil
        if shown.isGameLook then
            gameCount = gameCount + 1
            shown.frame = MinimapPins.acquireGamePin(gameCount, shown.data)
        end
        -- The focused quest's glow lies under every mark, never over a neighbour; on the full-size layer it is
        -- drawn at the marks' smaller scale
        pin.glowScale = MARK_SCALE
        local drawnWidth, drawnHeight, raise =
            ns.MapMarks.applyMarkLook(pin, shown.data, (Minimap:GetFrameLevel() or 1) + 6)
        pin.raise = raise or 0 -- a pin stands on its tip, so its middle sits above the spot
        pin.drawnSize = math.max(drawnWidth or 0, drawnHeight or 0)
        if pin.glow and pin.glowLayer ~= frame then
            pin.glowLayer = frame
            pin.glow:SetParent(frame)
            pin.glow:SetDrawLayer("BACKGROUND")
            glide(pin.glow)
        end
        glidePin(pin)
        -- Drawn as the game's "?" instead: our own mark for this place, and its glow, stay hidden
        if shown.frame then
            pin:Hide()
            if pin.glow then
                pin.glow:Hide()
            end
        end
        -- Whether its glow is part of it (the followed quest's, in gold: the look's to say), for when it comes back
        -- into view after being hidden (MinimapPins.move)
        pin.isGlowWanted = not shown.frame and type(pin.glow) == "table" and pin.glow:IsShown() == true
        pin.isGlowHidden = nil
    end
    for pinIndex = #shownPlaces + 1, #pins do
        pins[pinIndex]:Hide()
        if pins[pinIndex].glow then
            pins[pinIndex].glow:Hide()
        end
    end
    for index = gameCount + 1, #gamePins do
        gamePins[index]:Hide()
    end
end

refreshNow = function()
    if not frame then
        return
    end
    readRotating()
    local position = ns.Geometry.getPlayerPosition()
    composedAt = {
        zoneMapId = position and getZoneMapId(position.uiMapId) or nil,
        north = position and position.north,
        west = position and position.west,
        viewRadius = getViewRadius(),
        width = Minimap:GetWidth() or 0,
        choices = getShownChoices(),
        isOnCanvas = isSpotCanvasUsed(position, getFacing()),
        validYards = math.huge,
        dataKey = ns.MapPins.getDataKey(),
    }
    local isShown = ns.settings.shouldShowMapPins == true and ns.settings.shouldShowMinimapPins == true
    -- With the marks off nothing of ours is on the minimap: not the player's arrow and the party's dots either, drawn
    -- again only to lie over our marks (the game's own show), and nothing is placed at every frame (the OnUpdate)
    areMarksShown = isShown
    if ringFrame then
        ringFrame:SetShown(isShown)
    end
    local isChosen, chooseProblem = pcall(chooseAndDress, isShown)
    if not isChosen then
        -- Failed part way (an error in a quest's data): what was drawn before is taken off rather than left standing
        -- for marks that are no longer chosen; the error is still told, below
        pcall(chooseAndDress, false)
    end
    -- (placed for what was just chosen: the placing does not choose again)
    isComposing = true
    local isFine, problem = pcall(MinimapPins.move)
    isComposing = false
    if not isChosen then
        error(chooseProblem, 0)
    end
    if not isFine then
        error(problem, 0)
    end
end

local FOREIGN_SCAN_SECONDS = 0.5 -- how often other addons' pins are looked for
local foreignPins, foreignCount = {}, 0 -- other addons' pins as last looked for: { x, y, radius, west, north } each
local foreignScannedAt, foreignScannedFor -- when (GetTime), and at what zoom (pixels a yard), they were looked for
local clearPoints, playerPoint, partyPoints = {}, { x = 0, y = 0, radius = PLAYER_CLEAR, unit = "player" }, {}
local memberPlace = {} -- a party member's place in the world, while it is put on the minimap (reused)

---Other addons' pins among the minimap's children: small frames that are shown and can be seen. Ours (the frames
---and every mark) are passed over before anything is asked of the game.
local function addForeignPins(scale, centerX, centerY, ...)
    for index = 1, select("#", ...) do
        local child = select(index, ...)
        if
            child
            and child ~= frame
            and child ~= ringFrame
            and not child.mark
            and not child.isOurs
            and child:IsShown()
        then
            -- Only what can be seen: a frame shown but see-through (an empty holder) takes no room
            local alpha = child.GetEffectiveAlpha and child:GetEffectiveAlpha() or child:GetAlpha() or 1
            if alpha > 0.05 then
                local childX, childY = child:GetCenter()
                local childScale = child:GetEffectiveScale()
                local size = math.max(child:GetWidth() or 0, child:GetHeight() or 0) * childScale / scale
                if childX and size > 2 and size <= MAX_FOREIGN_PIN_SIZE then
                    foreignCount = foreignCount + 1
                    local pin = foreignPins[foreignCount]
                    if not pin then
                        pin = { isPin = true }
                        foreignPins[foreignCount] = pin
                    end
                    pin.x, pin.y, pin.radius =
                        childX * childScale / scale - centerX, childY * childScale / scale - centerY, size / 2 + 1
                end
            end
        end
    end
end

---What our marks keep clear of on the minimap, in pixels from its middle: the player's arrow, each party member in
---range (the game draws both under every addon's frame), and other addons' pins. Those are looked for twice a
---second, not at every move (a minimap full of another addon's pins is hundreds of questions to the game), and
---reckoned to stand on the land meanwhile; on a minimap that turns, and where no frames run (the tests), every time.
---@return { x: number, y: number, radius: number, unit: string?, isPin: boolean? }[] points The same table at every
---call, filled anew: to be read before the next
function MinimapPins.getClearPoints(position, viewRadius, radius, facing)
    local points = clearPoints
    for index = #points, 1, -1 do
        points[index] = nil
    end
    points[1] = playerPoint
    local count = 1
    local isAlone = IsInGroup and not IsInGroup()
    local uiMapId = not isAlone and position and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if uiMapId then
        local memberCount = 0
        for _, unit in ipairs(ns.Party.getUnits()) do
            local mapPosition = C_Map.GetPlayerMapPosition(uiMapId, unit)
            local x, y
            if mapPosition then
                x, y = mapPosition:GetXY()
            end
            if x and y and (x ~= 0 or y ~= 0) then
                local continentId, north, west = ns.Geometry.getWorldPosition(uiMapId, x * 100, y * 100)
                if north and continentId == position.continentId then
                    memberPlace.north, memberPlace.west = north, west
                    local right, up = MinimapPins.getOffset(position, memberPlace, viewRadius, facing, false)
                    if right then
                        memberCount = memberCount + 1
                        local point = partyPoints[memberCount]
                        if not point then
                            point = { radius = MEMBER_CLEAR }
                            partyPoints[memberCount] = point
                        end
                        point.x, point.y, point.unit = right * radius, up * radius, unit
                        count = count + 1
                        points[count] = point
                    end
                end
            end
        end
    end
    -- Other addons' pins: small frames on the minimap that are not ours
    local pixelsPerYard = viewRadius > 0 and radius / viewRadius or 0
    local now = GetTime and GetTime() or 0
    local isKept = ns.frameNumber > 0
        and not facing
        and position ~= nil
        and pixelsPerYard > 0
        and foreignScannedAt ~= nil
        and foreignScannedFor == pixelsPerYard
        and now >= foreignScannedAt
        and now - foreignScannedAt < FOREIGN_SCAN_SECONDS
    if isKept then
        for index = 1, foreignCount do
            local pin = foreignPins[index]
            pin.x, pin.y = (position.west - pin.west) * pixelsPerYard, (pin.north - position.north) * pixelsPerYard
        end
    else
        foreignCount = 0
        local scale = Minimap:GetEffectiveScale()
        local centerX, centerY = Minimap:GetCenter()
        if centerX and Minimap.GetChildren then
            addForeignPins(scale, centerX, centerY, Minimap:GetChildren())
        end
        foreignScannedAt, foreignScannedFor = nil, nil
        if position and pixelsPerYard > 0 and not facing then
            foreignScannedAt, foreignScannedFor = now, pixelsPerYard
            for index = 1, foreignCount do
                local pin = foreignPins[index]
                pin.west, pin.north = position.west - pin.x / pixelsPerYard, position.north + pin.y / pixelsPerYard
            end
        end
    end
    for index = 1, foreignCount do
        count = count + 1
        points[count] = foreignPins[index]
    end
    return points
end
---@return boolean isFree A mark of this radius at x, y lies in none of the spaces to keep clear
local function isFree(x, y, markRadius, clear)
    for index = 1, #clear do
        local point = clear[index]
        local needed = point.radius + markRadius
        local awayX, awayY = x - point.x, y - point.y
        if awayX * awayX + awayY * awayY < needed * needed then
            return false
        end
    end
    return true
end

local SEARCH_RINGS, SEARCH_STEP = 24, 1 -- how far, in pixels, a mark looks round its place for room

---A mark at x, y (pixels from the middle) moved to the nearest spot where it lies in no clear space: tried in
---widening circles round its place, so among many spawn icons it finds the gap nearest its own place.
---@return number x, number y
function MinimapPins.stepClear(x, y, markRadius, clear)
    if isFree(x, y, markRadius, clear) then
        return x, y
    end
    for ring = 1, SEARCH_RINGS do
        local distance = ring * SEARCH_STEP
        local count = 8 + ring * 4
        for index = 0, count - 1 do
            -- Upwards first: a mark above its place reads as standing on it
            local angle = math.pi / 2 + (index % 2 == 0 and 1 or -1) * math.floor((index + 1) / 2) * 2 * math.pi / count
            local candidateX, candidateY = x + math.cos(angle) * distance, y + math.sin(angle) * distance
            if isFree(candidateX, candidateY, markRadius, clear) then
                return candidateX, candidateY
            end
        end
    end
    -- No room nearby: stepped straight out of what it lies in, as near as it gets
    for _ = 1, 10 do
        local isMoved = false
        for _, point in ipairs(clear) do
            local dx, dy = x - point.x, y - point.y
            local distance = math.sqrt(dx * dx + dy * dy)
            local needed = point.radius + markRadius
            if distance < needed then
                if distance < 0.01 then
                    dx, dy, distance = 0, 1, 1 -- right on it: step up
                end
                x, y = point.x + dx / distance * needed, point.y + dy / distance * needed
                isMoved = true
            end
        end
        if not isMoved then
            break
        end
    end
    return x, y
end

---Turns the player's arrow drawn over our marks to where the player faces (every frame, as the game turns its own).
---Where the game keeps the facing from addons (inside some instances), the arrow is left out: the game's own, under
---our marks, still shows.
function MinimapPins.turnArrow()
    if not playerArrow then
        return
    end
    local isRotating = isMinimapRotating()
    local facing = GetPlayerFacing and GetPlayerFacing()
    -- (every frame: the game is asked to turn, show or hide it only when that changes)
    if not isRotating and type(facing) ~= "number" then
        if playerArrow.isShownNow ~= false then
            playerArrow.isShownNow = false
            playerArrow:Hide()
        end
        return
    end
    -- A minimap turning with the player keeps the arrow pointing up
    local turn = isRotating and 0 or facing
    if playerArrow.turn ~= turn then
        playerArrow.turn = turn
        playerArrow:SetRotation(turn)
    end
    if playerArrow.isShownNow ~= true then
        playerArrow.isShownNow = true
        playerArrow:Show()
    end
end

---Over everything of ours, so nothing hides them and nothing steps aside for them: the player's arrow, and each
---party member in range as the game draws them (its party icon, in their class colour).
function MinimapPins.drawParty(clear)
    if not ringFrame then
        return
    end
    MinimapPins.turnArrow()
    local count = 0
    for _, point in ipairs(clear) do
        if point.unit and point.unit ~= "player" then
            count = count + 1
            local member = members[count]
            if not member then
                -- (it remembers what it was last given: a member standing still asks nothing of the game)
                member = ns.Widgets.remember(glide(ringFrame:CreateTexture(nil, "OVERLAY", nil, 2)))
                ns.Widgets.setAtlas(member, "PlayerPartyBlip")
                members[count] = member
            end
            local red, green, blue = 1, 1, 1
            local _, classFile = UnitClass(point.unit)
            local color = classFile
                and (
                    C_ClassColor and C_ClassColor.GetClassColor(classFile)
                    or RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
                )
            if color then
                red, green, blue = color.r, color.g, color.b
            end
            member:SetVertexColor(red, green, blue, 1)
            member:SetSize(MEMBER_ICON_SIZE, MEMBER_ICON_SIZE)
            ns.Widgets.place(member, "CENTER", Minimap, "CENTER", point.x, point.y)
            member:Show()
        end
    end
    for index = count + 1, #members do
        members[index]:Hide()
    end
end

---@return number distance How far out a point is against the minimap's edge in its direction (getEdgeDistance), for
---a shape looked up once: asked for every spawn icon at every move
local function getEdgeDistanceIn(quarters, right, up)
    local quarter = 1
    if right < 0 then
        quarter = quarter + 1
    end
    if up > 0 then
        quarter = quarter + 2
    end
    if quarters[quarter] then
        return math.sqrt(right * right + up * up)
    end
    return math.max(math.abs(right), math.abs(up))
end

---The spawn icons put on their canvas, once for the spots chosen. Where they stand does not change as the player
---walks: the canvas is slid under the minimap, and nothing is asked of the game for any one of them.
---As on the world map (MapMarks.IS_LAYOUT_ON, off): every icon stands on its own spawn and none is moved, so the
---minimap shows the spawns where they are, the same ones the map shows. With the laying out on: each on a cell of
---a grid laid in the world's yards, its cells as far apart on screen as two icons need, so they never touch (the
---first to claim a cell has it: the quest in focus comes first), and one under another addon's pin, or under a
---mark, steps beside it to the nearest room, as far in the world as that is on screen.
---@param foreignPins table[] Other addons' pins, in pixels from the minimap's middle
---@param markCircles table[] The marks as just placed, in pixels from the middle
local function layOutSpots(position, viewRadius, radius, foreignPins, markCircles)
    MinimapPins.layoutCount = (MinimapPins.layoutCount or 0) + 1 -- (how often: read by the simulator's audits)
    local footprint = ns.MapMarks.getSpawnMarkerFootprint(ns.MapMarks.getSpawnMarker(), ICON_SIZE)
    local pixelsPerYard = radius / viewRadius
    local place = ns.Widgets.place
    if not ns.MapMarks.IS_LAYOUT_ON then
        for spotIndex, shown in ipairs(shownSpots) do
            local spot = spots[spotIndex]
            spot.isLaid = true
            spot.cellNorth, spot.cellWest = shown.place.north, shown.place.west
            spot.north, spot.west = shown.place.north, shown.place.west
            -- From the canvas's corner: right is less west, down is less north
            local canvasX, canvasY = worldOrigin.west - spot.west, worldOrigin.north - spot.north
            for _, texture in ipairs(spot.textures or {}) do
                place(texture, "CENTER", spotCanvas, "TOPLEFT", canvasX, -canvasY)
            end
            spot.isIn, spot.alphaNow = nil, nil -- shown or not by the move that follows
        end
        return
    end
    local cellYards = (footprint + ICON_GAP) / pixelsPerYard
    local half = footprint / 2
    local isTaken, laid = {}, {}
    for spotIndex, shown in ipairs(shownSpots) do
        local spot = spots[spotIndex]
        local row, column = math.floor(shown.place.north / cellYards), math.floor(shown.place.west / cellYards)
        local key = row * 2000003 + column
        spot.isLaid = false
        if not isTaken[key] then
            isTaken[key] = true
            spot.isLaid = true
            -- Inside the minimap's edge or not by its cell, as when each was placed move by move; drawn where it
            -- stands after stepping aside
            spot.cellNorth, spot.cellWest = (row + 0.5) * cellYards, (column + 0.5) * cellYards
            local x, y =
                (position.west - spot.cellWest) * pixelsPerYard, (spot.cellNorth - position.north) * pixelsPerYard
            x, y = MinimapPins.stepClear(x, y, half, foreignPins)
            laid[#laid + 1] = { spot = spot, x = x, y = y }
        end
    end
    -- A spawn icon under a mark steps beside it, to the nearest room clear of the marks, other addons' pins and the
    -- icons already placed: every spawn shows
    local iconRoom = {}
    for _, circle in ipairs(markCircles) do
        iconRoom[#iconRoom + 1] = circle
    end
    for _, point in ipairs(foreignPins) do
        iconRoom[#iconRoom + 1] = point
    end
    for _, item in ipairs(laid) do
        local isUnderMark = false
        for _, circle in ipairs(markCircles) do
            if (item.x - circle.x) ^ 2 + (item.y - circle.y) ^ 2 < (circle.radius + half) ^ 2 then
                isUnderMark = true
            end
        end
        if isUnderMark then
            item.x, item.y = MinimapPins.stepClear(item.x, item.y, half, iconRoom)
        end
        iconRoom[#iconRoom + 1] = { x = item.x, y = item.y, radius = half }
        -- Its place in the world, and from the canvas's corner (right is less west, down is less north)
        local spot = item.spot
        spot.west, spot.north = position.west - item.x / pixelsPerYard, position.north + item.y / pixelsPerYard
        local canvasX, canvasY = worldOrigin.west - spot.west, worldOrigin.north - spot.north
        for _, texture in ipairs(spot.textures or {}) do
            place(texture, "CENTER", spotCanvas, "TOPLEFT", canvasX, -canvasY)
        end
    end
    for spotIndex = 1, #shownSpots do
        spots[spotIndex].isIn, spots[spotIndex].alphaNow = nil, nil -- shown or not by the move that follows
    end
end

---@return boolean isUnder An icon at x, y (pixels from the minimap's middle) lies under a mark kept on the rim
local function isUnderRimMark(x, y, half, rimCircles)
    for index = 1, #rimCircles do
        local circle = rimCircles[index]
        local needed = circle.radius + half
        if (x - circle.x) ^ 2 + (y - circle.y) ^ 2 < needed * needed then
            return true
        end
    end
    return false
end

---The canvas's spawn icons at a move: which of the near ones are inside the minimap's edge now, and which are
---faded over the player's arrow. Reckoned here; an icon is shown, hidden or faded only when that changes.
---@param rimCircles table[] The marks kept on the rim, in pixels from the middle: an icon under one is hidden
local function updateSpots(position, viewRadius, radius, rimCircles, half)
    local pixelsPerYard = radius / viewRadius
    local quarters = MinimapPins.getShape()
    local hasRimMarks = #rimCircles > 0
    for nearIndex = 1, #nearSpots do
        local spot = spots[nearSpots[nearIndex]]
        local isIn, alpha = false, 1
        if spot.isLaid then
            local right, up =
                (position.west - spot.cellWest) / viewRadius, (spot.cellNorth - position.north) / viewRadius
            isIn = getEdgeDistanceIn(quarters, right, up) <= RIM
            if isIn then
                local x, y = (position.west - spot.west) * pixelsPerYard, (spot.north - position.north) * pixelsPerYard
                if nearNodeCount > 0 and isIconOnNode(spot, spot.north, spot.west, 1 / pixelsPerYard, half) then
                    isIn = false -- on a herb or ore the game may show: left out, so its icon shows
                elseif hasRimMarks and isUnderRimMark(x, y, half, rimCircles) then
                    isIn = false
                else
                    alpha = getNearPlayerAlpha(x, y)
                end
            end
        end
        if spot.isIn ~= isIn or (isIn and spot.alphaNow ~= alpha) then
            spot.isIn, spot.alphaNow = isIn, alpha
            for _, texture in ipairs(spot.textures or {}) do
                if isIn then
                    texture:SetAlpha(alpha)
                    texture:Show()
                else
                    texture:Hide()
                end
            end
        end
    end
end

---@return boolean isWithin A place lies within a distance of the player (one with no spot in the world: never)
local function isPlaceWithin(place, position, yards)
    local north = place.north
    if not north or (place.continentId ~= nil and place.continentId ~= position.continentId) then
        return false
    end
    local awayNorth, awayWest = north - position.north, place.west - position.west
    return awayNorth * awayNorth + awayWest * awayWest <= yards * yards
end

---Tells what is near enough to show before the player has walked on another NEAR_STEP_YARDS from what is not: at a
---move only the near are looked at, however much the land round the player holds. What is far is hidden here,
---once. (The followed quest's pointer is always near: it shows on the rim however far its place.)
local function partitionNear(position, viewRadius)
    -- (told again once the player is NEAR_STEP_YARDS north, south, east or west of here: half as far again askew)
    local limit = MinimapPins.getReach(viewRadius) + NEAR_STEP_YARDS * 1.5 + NEAR_SLACK_YARDS
    local isEveryNear = ns.MapMarks.IS_LAYOUT_ON -- (laid out on a grid, each icon's cell follows every other's)
    local placeCount, handoverCount, spotCount = 0, 0, 0
    for index = 1, #shownPlaces do
        local shown = shownPlaces[index]
        if position and (shown.isKeptOnRim or isPlaceWithin(shown.place, position, limit)) then
            placeCount = placeCount + 1
            nearPlaces[placeCount] = index
            if shown.handoverYards then
                handoverCount = handoverCount + 1
                nearHandovers[handoverCount] = shown
            end
        else
            local pin = shown.frame or pins[index]
            if pin then
                pin:Hide()
                if type(pin.glow) == "table" then
                    pin.glow:Hide()
                    pin.isGlowHidden = true -- (shown again with its mark: MinimapPins.move)
                end
            end
        end
    end
    for index = #nearPlaces, placeCount + 1, -1 do
        nearPlaces[index] = nil
    end
    for index = #nearHandovers, handoverCount + 1, -1 do
        nearHandovers[index] = nil
    end
    for index = 1, #shownSpots do
        local spot = spots[index]
        if position and (isEveryNear or isPlaceWithin(shownSpots[index].place, position, limit)) then
            spotCount = spotCount + 1
            nearSpots[spotCount] = index
        elseif spot and spot.isIn ~= false then
            spot.isIn = false
            for _, texture in ipairs(spot.textures or {}) do
                texture:Hide()
            end
        end
    end
    for index = #nearSpots, spotCount + 1, -1 do
        nearSpots[index] = nil
    end
    nearNodeCount = ns.GatheringSpots.collectNear(position, limit, nearNodes)
    nodeGeneration = nodeGeneration + 1
    partitionedAt = partitionedAt or {}
    partitionedAt.trackedKey = ns.GatheringSpots.getTrackedKey()
    partitionedAt.hasPosition, partitionedAt.viewRadius = position ~= nil, viewRadius
    partitionedAt.continentId = position and position.continentId
    partitionedAt.north, partitionedAt.west = position and position.north, position and position.west
end

---@return boolean isOnNode A spawn icon standing at this place in the world lies on a herb or ore the game may show
---there. Kept on the icon until what is near is told again (or the zoom changes): its place never moves meanwhile.
isIconOnNode = function(holder, north, west, yardsPerPixel, half)
    if nearNodeCount == 0 or not north then
        return false
    end
    if holder.nodeGeneration ~= nodeGeneration or holder.nodeYardsPerPixel ~= yardsPerPixel then
        holder.nodeGeneration, holder.nodeYardsPerPixel = nodeGeneration, yardsPerPixel
        holder.isOnNode =
            ns.GatheringSpots.isNear(nearNodes, nearNodeCount, north, west, (half + NODE_RADIUS) * yardsPerPixel)
    end
    return holder.isOnNode
end

---@return number count The near herbs and ores in view at this move, put in nodeX and nodeY (pixels from the middle)
local function placeNodes(position, viewRadius, radius, facing)
    local count = 0
    if nearNodeCount == 0 or not position then
        return 0
    end
    local pixelsPerYard = radius / viewRadius
    local reach = radius + NODE_RADIUS
    for index = 1, nearNodeCount do
        local north, west = nearNodes[index * 2 - 1], nearNodes[index * 2]
        local x, y
        if facing then
            nodePlace.north, nodePlace.west = north, west
            local right, up = MinimapPins.getOffset(position, nodePlace, viewRadius, facing, false)
            if right then
                x, y = right * radius, up * radius
            end
        else
            x, y = (position.west - west) * pixelsPerYard, (north - position.north) * pixelsPerYard
            if x > reach or x < -reach or y > reach or y < -reach then
                x = nil
            end
        end
        if x then
            count = count + 1
            nodeX[count], nodeY[count] = x, y
        end
    end
    return count
end

---@return boolean isOnNode A mark of this drawn half size at x, y (pixels from the middle) lies on a herb or ore icon
local function isMarkOnNode(x, y, half, count)
    local reach = (half + NODE_RADIUS) * (half + NODE_RADIUS)
    for index = 1, count do
        local awayX, awayY = x - nodeX[index], y - nodeY[index]
        if awayX * awayX + awayY * awayY < reach then
            return true
        end
    end
    return false
end

---Where a mark chosen for the minimap shows now, in fractions of its radius: at its place while that is in view; on
---the rim, for the followed quest's pointer, while its place is out of view (in view the place has its own mark and
---icons, and the pointer is not drawn); nowhere while the game's own "!" or "?" stands there.
---@return number? right, number? up, boolean isOnRim
function MinimapPins.getMarkOffset(shown, position, viewRadius, facing)
    if MinimapPins.isHandedOver(shown, position) then
        return nil, nil, false
    end
    local right, up, isOnRim = MinimapPins.getOffset(position, shown.place, viewRadius, facing, shown.isKeptOnRim)
    if right and shown.isKeptOnRim and not isOnRim then
        return nil, nil, false
    end
    return right, up, isOnRim
end

---@return number key What crowds a mark at x, y: every circle near enough to bear on where it steps to, each by where
---it lies from the mark (to an eighth of a pixel) and its size. The same key: the same step aside.
local function getCrowdKey(x, y, markRadius, clear)
    local key = 0
    local reach = markRadius + SEARCH_RINGS * SEARCH_STEP + 1
    for index = 1, #clear do
        local point = clear[index]
        local awayX, awayY = point.x - x, point.y - y
        local near = reach + point.radius
        if awayX > -near and awayX < near and awayY > -near and awayY < near then
            key = (
                key * 31
                + math.floor(awayX * 8 + 0.5) * 7
                + math.floor(awayY * 8 + 0.5) * 13
                + math.floor(point.radius * 8 + 0.5)
            ) % 2147483647
        end
    end
    return key
end

-- What the marks cover at a move, in pixels from the minimap's middle: tables used again at every move
local circlePool, circleCount = {}, 0
local takenCircles, markCircles, rimCircles, foreignList = {}, {}, {}, {}

local function clearList(list)
    for index = #list, 1, -1 do
        list[index] = nil
    end
end

local function takeCircle(x, y, circleRadius)
    circleCount = circleCount + 1
    local circle = circlePool[circleCount]
    if not circle then
        circle = {}
        circlePool[circleCount] = circle
    end
    circle.x, circle.y, circle.radius = x, y, circleRadius
    return circle
end

---Whether the game's own word for where the player is (UnitPosition) agrees with the map's reckoning, which
---everything on the land was placed by: within half a yard, it slides the land between moves (MinimapPins.slide);
---further off than that it is not the same reckoning on this client, and is never used.
local function checkUnitPosition(position)
    unitOffsetNorth = nil
    framePositionAt = nil -- (what was read this frame is read again: by the map's reckoning unless they agree)
    if unitMismatchCount >= MAX_UNIT_MISMATCHES or not position or not UnitPosition then
        return
    end
    local isFine, north, west, _, continentId = pcall(UnitPosition, "player")
    if
        not isFine
        or type(north) ~= "number"
        or type(west) ~= "number"
        or (issecretvalue and (issecretvalue(north) or issecretvalue(west)))
    then
        return -- (not told here: inside an instance)
    end
    local offsetNorth, offsetWest = position.north - north, position.west - west
    if
        math.abs(offsetNorth) > UNIT_POSITION_TOLERANCE_YARDS
        or math.abs(offsetWest) > UNIT_POSITION_TOLERANCE_YARDS
    then
        unitMismatchCount = unitMismatchCount + 1 -- (once may be a moment between two maps; every time, another reckoning)
        return
    end
    unitMismatchCount = 0
    unitOffsetNorth, unitOffsetWest, unitContinentId = offsetNorth, offsetWest, continentId
end

---Places what follows the player, a few times a second while they move: which marks and spawn icons of the land
---are inside the minimap's edge and which are faded over the player's arrow, the followed quest's pointer on the
---rim, the party's dots, the area edges cut round all of these. The land itself, with everything that stands on
---it, is slid every frame (MinimapPins.slide) and laid out only when it is chosen (refreshNow).
function MinimapPins.move()
    local position = ns.Geometry.getPlayerPosition()
    local viewRadius = getViewRadius()
    local width = Minimap:GetWidth()
    local radius = (width or 140) / 2
    local facing = getFacing()
    local isOnCanvas = isSpotCanvasUsed(position, facing)
    -- The marks were chosen, and the spawn icons sized, for a zoom, a size of the minimap and a way of placing them:
    -- when one of these has changed since, they are chosen again at once (which ends by placing them)
    if
        composedAt
        and not isComposing
        and frame
        and (
            viewRadius ~= composedAt.viewRadius
            or (width or 0) ~= composedAt.width
            or isOnCanvas ~= composedAt.isOnCanvas
        )
    then
        ns.MapPins.withoutView(refreshNow)
        return
    end
    lastMove.north, lastMove.west = position and position.north or nil, position and position.west or nil
    lastMove.continentId = position and position.continentId or nil
    lastMove.viewRadius, lastMove.radius, lastMove.facing = viewRadius, radius, facing
    lastMove.isOnCanvas = isOnCanvas
    checkUnitPosition(position)
    -- What is near told from what is far, again once the player has walked on a little
    local told = partitionedAt
    if
        not told
        or told.hasPosition ~= (position ~= nil)
        or told.viewRadius ~= viewRadius
        or told.trackedKey ~= ns.GatheringSpots.getTrackedKey()
        or (
            position
            and (
                told.continentId ~= position.continentId
                or math.abs(told.north - position.north) > NEAR_STEP_YARDS
                or math.abs(told.west - position.west) > NEAR_STEP_YARDS
            )
        )
    then
        partitionNear(position, viewRadius)
    end
    local clear = MinimapPins.getClearPoints(position, viewRadius, radius, facing)
    -- The player and the party are drawn over everything of ours (drawParty), so nothing steps aside for them;
    -- other addons' pins are kept clear of
    clearList(foreignList)
    for index = 1, #clear do
        local point = clear[index]
        if point.isPin then
            foreignList[#foreignList + 1] = point
        end
    end
    local nodeCount = placeNodes(position, viewRadius, radius, facing)
    local footprint = ns.MapMarks.getSpawnMarkerFootprint(ns.MapMarks.getSpawnMarker(), ICON_SIZE)
    local half = footprint / 2
    local spotPlaces -- [spot index] = { x, y } in pixels from the middle, when drawn: only where placed move by move
    if isOnCanvas then
        ensureOrigin(position)
        placeCanvas(spotCanvas, position.north, position.west, radius / viewRadius)
    else
        hideCanvas(spotCanvas)
        spotPlaces = {}
        local cellYards = (footprint + ICON_GAP) * viewRadius / radius
        local isTaken = {}
        for nearIndex = 1, position and #nearSpots or 0 do
            local spotIndex = nearSpots[nearIndex]
            local shown = shownSpots[spotIndex]
            if not ns.MapMarks.IS_LAYOUT_ON then
                -- As on the world map (MapMarks.IS_LAYOUT_ON, off): every spawn's icon on its own spot, none moved
                local right, up = MinimapPins.getOffset(position, shown.place, viewRadius, facing, false)
                if right then
                    spotPlaces[spotIndex] =
                        { x = right * radius, y = up * radius, north = shown.place.north, west = shown.place.west }
                end
            else
                -- With the laying out on: each on a cell of a grid laid in world yards, its cells as far apart on
                -- screen as two icons need: they never touch, and stay put as the land slides under them
                local north = (math.floor(shown.place.north / cellYards) + 0.5) * cellYards
                local west = (math.floor(shown.place.west / cellYards) + 0.5) * cellYards
                local key = math.floor(north / cellYards) .. ":" .. math.floor(west / cellYards)
                if not isTaken[key] then
                    isTaken[key] = true
                    local right, up =
                        MinimapPins.getOffset(position, { north = north, west = west }, viewRadius, facing, false)
                    if right then
                        -- Under another addon's pin, the spawn steps beside it rather than going missing
                        local x, y = MinimapPins.stepClear(right * radius, up * radius, half, foreignList)
                        spotPlaces[spotIndex] = { x = x, y = y, north = north, west = west }
                    end
                end
            end
        end
    end
    -- Marks stay where the world map has them: they only keep clear of other addons' pins and of each other (each
    -- placed mark is kept clear of by the next). The marks that stand at their places, which the spawn icons step
    -- aside for (with the laying out on); and those kept on the rim, which point the way to a place out of view:
    -- the land slides under these, and an icon under one is hidden meanwhile
    clearList(takenCircles)
    clearList(markCircles)
    clearList(rimCircles)
    circleCount = 0
    for index = 1, #foreignList do
        takenCircles[index] = foreignList[index]
    end
    local marksKey = 0 -- which marks stand at their places on the minimap now
    for nearIndex = 1, #nearPlaces do
        local pinIndex = nearPlaces[nearIndex]
        local shown = shownPlaces[pinIndex]
        local pin = shown.frame or pins[pinIndex]
        local right, up, isOnRim
        if position then
            right, up, isOnRim = MinimapPins.getMarkOffset(shown, position, viewRadius, facing)
        end
        local size, pinRadius, x, y
        if right then
            -- Packed close: the round mark as drawn, so neighbours just touch; a glow may lie under a neighbour,
            -- as on the world map
            size = shown.pinSize
            if not size then -- (asked of the game once for each mark chosen)
                size = math.max(pin.drawnSize or 0, pin:GetWidth() or 0)
                shown.pinSize = size
            end
            pinRadius = size * MARK_SCALE / 2 * MARK_PACKING
            x, y = right * radius, up * radius + (pin.raise or 0) * MARK_SCALE
            if not isFree(x, y, pinRadius, takenCircles) then
                -- Among others: stepped to the nearest room. Looking for it is the dearest thing a move does, and
                -- marks that stand on the land keep their places to one another as it slides: looked for again
                -- only when what crowds the mark, told from the mark itself, is not what it was (getCrowdKey)
                local crowdKey = getCrowdKey(x, y, pinRadius, takenCircles)
                if shown.crowdKey == crowdKey then
                    x, y = x + shown.crowdAside, y + shown.crowdAbove
                else
                    local steppedX, steppedY = MinimapPins.stepClear(x, y, pinRadius, takenCircles)
                    shown.crowdKey, shown.crowdAside, shown.crowdAbove = crowdKey, steppedX - x, steppedY - y
                    x, y = steppedX, steppedY
                end
            end
            -- On a herb or ore the game may show there: left out, so its icon shows
            if nodeCount > 0 and isMarkOnNode(x, y, size * MARK_SCALE / 2, nodeCount) then
                right = nil
            end
        end
        if right then
            local circle = takeCircle(x, y, pinRadius)
            takenCircles[#takenCircles + 1] = circle
            if isOnRim then
                rimCircles[#rimCircles + 1] = circle
            else
                markCircles[#markCircles + 1] = circle
                marksKey = (marksKey * 33 + pinIndex) % 1000000007
            end
            if isOnCanvas and not isOnRim then
                -- A mark at its place on the land hangs on the canvas's corner, which slides with the land every
                -- frame (MinimapPins.slide): from the corner to its place is the same at every move (told from the
                -- world, where the player is cancels out), so it is set once and the mark never trails the land.
                -- Stepped aside, by as much as that (to a sixteenth of a pixel, so the sums give the same again).
                local raise = (pin.raise or 0) * MARK_SCALE
                local aside = math.floor((x - right * radius) * 16 + 0.5) / 16
                local above = math.floor((y - (up * radius + raise)) * 16 + 0.5) / 16
                local pixelsPerYard = radius / viewRadius
                ns.Widgets.place(
                    pin,
                    "CENTER",
                    spotCanvas,
                    "TOPLEFT",
                    ((worldOrigin.west - shown.place.west) * pixelsPerYard + aside) / MARK_SCALE,
                    ((shown.place.north - worldOrigin.north) * pixelsPerYard + above) / MARK_SCALE + (pin.raise or 0)
                )
            else
                -- On the rim (it points the way to a place out of view), or on a minimap that turns: placed from
                -- the minimap's middle at every move. Drawn smaller than on the world map, so its offsets are in
                -- its own, smaller units.
                ns.Widgets.place(
                    pin,
                    "CENTER",
                    Minimap,
                    "CENTER",
                    x / MARK_SCALE,
                    (y - (pin.raise or 0) * MARK_SCALE) / MARK_SCALE + (pin.raise or 0)
                )
            end
            -- Over the player's arrow it is faded, the player's choice, so the arrow shows through; its glow too
            local nearAlpha = getNearPlayerAlpha(x, y)
            pin:SetAlpha(math.min(nearAlpha, isOnRim and 0.75 or 1))
            if type(pin.glow) == "table" then -- the game's own "?" in our place has none
                pin.glow:SetAlpha(nearAlpha)
                if pin.isGlowHidden then
                    -- Back in view: its glow with it, when it has one (hidden with it, it would stay hidden for good)
                    pin.isGlowHidden = nil
                    if pin.isGlowWanted then
                        pin.glow:Show()
                    end
                end
            end
            pin:Show()
        else
            pin:Hide()
            if type(pin.glow) == "table" then
                pin.glow:Hide()
                pin.isGlowHidden = true
            end
        end
    end
    if isOnCanvas then
        -- The icons stand on their canvas, laid out once for the spots chosen and the marks they step aside for
        -- (a mark coming onto the minimap, or leaving it, lays them out again); here only which of them show
        if not ns.MapMarks.IS_LAYOUT_ON then
            marksKey = 0 -- (every icon on its own spawn: the marks move none of them)
        end
        if spotsLaidFor ~= shownSpots or spotsLaidKey ~= marksKey then
            spotsLaidFor, spotsLaidKey = shownSpots, marksKey
            layOutSpots(position, viewRadius, radius, foreignList, markCircles)
        end
        updateSpots(position, viewRadius, radius, rimCircles, half)
        areDrawnSpotsStale = true
    else
        spotsLaidFor = nil
        -- A spawn icon under a mark steps beside it, to the nearest room clear of the marks, other addons' pins and the
        -- icons already placed: every spawn shows
        local iconRoom = {}
        if ns.MapMarks.IS_LAYOUT_ON then
            for _, circle in ipairs(markCircles) do
                iconRoom[#iconRoom + 1] = circle
            end
            for _, point in ipairs(foreignList) do
                iconRoom[#iconRoom + 1] = point
            end
        end
        for nearIndex = 1, #nearSpots do
            local spotIndex = nearSpots[nearIndex]
            local place = spotPlaces[spotIndex]
            if place and isUnderRimMark(place.x, place.y, half, rimCircles) then
                spotPlaces[spotIndex], place = nil, nil -- under a mark kept on the rim: hidden while it is
            elseif
                place
                and nearNodeCount > 0
                and isIconOnNode(shownSpots[spotIndex], place.north, place.west, viewRadius / radius, half)
            then
                spotPlaces[spotIndex], place = nil, nil -- on a herb or ore the game may show: left out, so its icon shows
            end
            if place and ns.MapMarks.IS_LAYOUT_ON then
                local isUnderMark = false
                for _, circle in ipairs(markCircles) do
                    if (place.x - circle.x) ^ 2 + (place.y - circle.y) ^ 2 < (circle.radius + half) ^ 2 then
                        isUnderMark = true
                    end
                end
                if isUnderMark then
                    place.x, place.y = MinimapPins.stepClear(place.x, place.y, half, iconRoom)
                end
                iconRoom[#iconRoom + 1] = { x = place.x, y = place.y, radius = half }
            end
        end
        -- The spawn icons where they were worked out above
        drawnSpots = {}
        areDrawnSpotsStale = false
        for nearIndex = 1, #nearSpots do
            local spotIndex = nearSpots[nearIndex]
            local shown = shownSpots[spotIndex]
            local spot = spots[spotIndex]
            local place = spotPlaces[spotIndex]
            spot.isIn = place ~= nil
            for _, texture in ipairs(spot.textures or {}) do
                if place then
                    ns.Widgets.place(texture, "CENTER", Minimap, "CENTER", place.x, place.y)
                    texture:SetAlpha(getNearPlayerAlpha(place.x, place.y))
                    texture:Show()
                else
                    texture:Hide()
                end
            end
            if place then
                drawnSpots[#drawnSpots + 1] = {
                    x = place.x,
                    y = place.y,
                    radius = SPOT_HOVER_RADIUS,
                    questId = shown.questId,
                    isFocused = shown.isFocused,
                }
            end
        end
    end
    -- (edges run on under the player's arrow and the party's dots, drawn again over them: cut round other addons'
    -- pins alone)
    MinimapPins.drawAreas(position, viewRadius, radius, facing, foreignList)
    MinimapPins.drawParty(clear)
end
local function acquire(pool, create)
    pool.usedCount = pool.usedCount + 1
    local item = pool[pool.usedCount]
    if not item then
        item = create()
        -- Fills are clipped to the round minimap by a mask; lines take no mask in the game, so their ends are cut
        -- at the rim before they are placed
        if isAreaMasked and item.AddMaskTexture and item:GetObjectType() ~= "Line" then
            item:AddMaskTexture(areaMask)
        end
        pool[pool.usedCount] = item
    end
    item:Show()
    item.isShownNow = true
    return item
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
    for _, triangle in ipairs(triangles) do
        if isRound then
            triangle:AddMaskTexture(areaMask)
        else
            triangle:RemoveMaskTexture(areaMask)
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

-- On a minimap that does not turn, what lies on the land rides canvases laid out in the world's yards, each scaled
-- to the zoom and slid under the minimap as the player walks: one call a move, where every piece used to be placed
-- anew (thousands of calls a second while walking).
--   spotCanvas: the spawn icons (or squares), on a minimap of any shape. Which of them are inside its edge, and
--     which are faded over the player's arrow, is reckoned in Lua and set only when it changes.
--   fillCanvas: the areas' fills and edges, on a square minimap, whose own frame cuts them at its edge. A round
--     minimap cuts fills by a mask and lines not at all: there, and on a turning minimap, every triangle and edge
--     is still placed at every move, as before.
-- (The canvases, their corner and what was laid out on them are kept with the rest of what the minimap shows, at
-- the top.)
local CANVAS_SPAN_YARDS = 4000 -- further from the corner than this, the canvases are laid out again round the player
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

local function releaseCanvasAreas()
    for key in pairs(fillSets) do
        releaseFillSet(key)
    end
    for key in pairs(edgeSets) do
        releaseEdgeSet(key)
    end
    areasLaidFor = nil
end

---The canvases' corner: a place in the world, moved only when the player is far from it (another continent, or
---thousands of yards on); everything on them is then laid out again.
function ensureOrigin(position)
    if
        worldOrigin
        and worldOrigin.continentId == position.continentId
        and math.abs(position.north - worldOrigin.north) <= CANVAS_SPAN_YARDS
        and math.abs(position.west - worldOrigin.west) <= CANVAS_SPAN_YARDS
    then
        return
    end
    releaseCanvasAreas()
    worldOrigin = { continentId = position.continentId, north = position.north, west = position.west }
    spotsLaidFor = nil
end

---Scales a canvas to the zoom and slides its corner to where its place in the world shows on the minimap.
---@param north number Where the player is, in the world's yards
---@param west number
function placeCanvas(canvas, north, west, pixelsPerYard)
    if not (pixelsPerYard > 0) then
        return hideCanvas(canvas) -- (no size or no zoom to scale it by: the game takes no scale of nothing)
    end
    if canvas.pixelsPerYard ~= pixelsPerYard then
        canvas.pixelsPerYard = pixelsPerYard
        canvas:SetScale(pixelsPerYard) -- a yard of the canvas is as many pixels as the zoom shows it
    end
    -- (in the canvas's own units, yards: right is less west, up is more north)
    local x, y = west - worldOrigin.west, worldOrigin.north - north
    if canvas.placedX ~= x or canvas.placedY ~= y then
        canvas.placedX, canvas.placedY = x, y
        canvas:SetPoint("TOPLEFT", Minimap, "CENTER", x, y) -- its one point, set again
    end
    if canvas.isShownNow ~= true then
        canvas.isShownNow = true
        canvas:Show()
    end
end

function hideCanvas(canvas)
    if canvas and canvas.isShownNow ~= false then
        canvas.isShownNow = false
        canvas:Hide()
    end
end

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

---An edge, or a dash of a walk, placed on the minimap itself: cut at its rim (lines take no mask in the game) and
---round every circle kept clear, each piece a dark rim line under the line in its colour.
local function drawPieces(
    fromX,
    fromY,
    toX,
    toY,
    radius,
    clear,
    clip,
    underColor,
    underAlpha,
    underWidth,
    color,
    alpha,
    width
)
    local from, to = clip({ x = fromX, y = fromY }, { x = toX, y = toY }, radius - 1)
    for _, piece in ipairs(from and MinimapPins.cutAround(from, to, clear or NO_PIECES) or NO_PIECES) do
        local under = acquireLine(underColor, underAlpha, underWidth, 2)
        under:SetStartPoint("TOPLEFT", areaFrame, piece.from.x + radius, piece.from.y - radius)
        under:SetEndPoint("TOPLEFT", areaFrame, piece.to.x + radius, piece.to.y - radius)
        local over = acquireLine(color, alpha, width, 3)
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
    local clip = isAreaMasked and MinimapPins.clipToCircle or MinimapPins.clipToSquare
    local points = {}
    for _, point in ipairs(area.points) do
        local x, y = toMinimap(point, position, viewRadius, radius, facing)
        points[#points + 1] = { x = x, y = y }
    end
    local dashAlpha = area.isFocused and look.focusedTrailAlpha or look.trailAlpha
    local light =
        { color[1] + (1 - color[1]) * 0.55, color[2] + (1 - color[2]) * 0.55, color[3] + (1 - color[3]) * 0.55 }
    for _, dash in ipairs(ns.MapMarks.composeDashes(points, ns.MapMarks.DASH_PIXELS, ns.MapMarks.DASH_GAP_PIXELS)) do
        drawPieces(
            dash.from.x,
            dash.from.y,
            dash.to.x,
            dash.to.y,
            radius,
            clear,
            clip,
            look.rimColor,
            dashAlpha * ns.MapMarks.DASH_SHADOW_ALPHA,
            ns.MapMarks.DASH_SHADOW_WIDTH,
            light,
            dashAlpha,
            ns.MapMarks.DASH_WIDTH
        )
    end
end

---@return string key Everything the areas are drawn from, move by move: where the player is and faces, the zoom,
---the minimap's size, what is kept clear, and the areas themselves
local function getAreasKey(position, viewRadius, radius, facing, clear)
    if not position then
        return "-"
    end
    local key = string.format(
        "%s:%.2f:%.2f:%s:%.2f:%.2f:%s:%s",
        tostring(shownAreas),
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

---The areas placed piece by piece at every move: a round minimap (its fills cut by a mask, its edges at its rim
---here) and a turning one.
local function drawAreasMoveByMove(position, viewRadius, radius, facing, clear)
    -- Called at every move and once a second besides: with nothing it draws from changed, all stays as it is
    local key = getAreasKey(position, viewRadius, radius, facing, clear)
    if key == drawnAreasKey then
        return
    end
    drawnAreasKey = key
    triangles.usedCount, lines.usedCount = 0, 0
    local look = ns.MapMarks.getAreaLook()
    local reachYards = ns.MapMarks.AREA_REACH_YARDS
    local function toCorner(x, y)
        return { x = x + radius, y = radius - y } -- from the minimap's upper left corner, y down
    end
    local clip = isAreaMasked and MinimapPins.clipToCircle or MinimapPins.clipToSquare
    for _, area in ipairs(position and areaFrame and shownAreas or {}) do
        -- Only areas with a spawn near enough to reach onto the minimap
        if isAreaNear(area, position, viewRadius, reachYards) then
            local color = area.color or ns.MapMarks.getQuestColor(area.number, area.questId)
            local alpha = area.isFocused and look.focusedFillAlpha or look.fillAlpha
            -- (a fill or an outline switched off: none of its pieces placed)
            for _, triangle in ipairs(look.hasFill and area.triangles or NO_PIECES) do
                local ax, ay = toMinimap(triangle[1], position, viewRadius, radius, facing)
                local bx, by = toMinimap(triangle[2], position, viewRadius, radius, facing)
                local cx, cy = toMinimap(triangle[3], position, viewRadius, radius, facing)
                -- Only pieces on the minimap; the mask (or the square frame) cuts those across its edge
                if
                    math.max(ax, bx, cx) > -radius
                    and math.min(ax, bx, cx) < radius
                    and math.max(ay, by, cy) > -radius
                    and math.min(ay, by, cy) < radius
                then
                    -- (remembering: walked on, a piece keeps its colour, size and corners; only its place is given again)
                    local texture = acquire(triangles, function()
                        return ns.Widgets.remember(glide(areaFrame:CreateTexture(nil, "ARTWORK", nil, 1)))
                    end)
                    texture:SetColorTexture(color[1], color[2], color[3], alpha)
                    ns.MapMarks.setTriangle(texture, toCorner(ax, ay), toCorner(bx, by), toCorner(cx, cy), areaFrame)
                end
            end
            if area.isPatrol then
                drawPatrol(area, position, viewRadius, radius, facing, clear)
            else
                local rimAlpha, edgeAlpha = Rough.getEdgeAlphas(area, look)
                -- (the focused quest's edge thicker where the map's is: in the shapes look)
                local thicker = area.isFocused and look.focusedEdgePixels - look.edgePixels or 0
                for _, edge in ipairs((look.hasEdges or area.isRough) and area.edges or NO_PIECES) do
                    local fromX, fromY = toMinimap(edge[1], position, viewRadius, radius, facing)
                    local toX, toY = toMinimap(edge[2], position, viewRadius, radius, facing)
                    drawPieces(
                        fromX,
                        fromY,
                        toX,
                        toY,
                        radius,
                        clear,
                        clip,
                        look.rimColor,
                        rimAlpha,
                        AREA_RIM_PIXELS + thicker,
                        color,
                        edgeAlpha,
                        AREA_EDGE_PIXELS + thicker
                    )
                end
            end
        end
    end
    for index = triangles.usedCount + 1, #triangles do
        local triangle = triangles[index]
        if triangle.isShownNow ~= false then -- (only those not hidden already)
            triangle:Hide()
            triangle.isShownNow = false
        end
    end
    hideUnusedLines()
end

---The fills and edges of the areas near the player, on the canvas: laid out where they are not yet (once, in yards
---from the canvas's corner: right is less west, down is less north), restyled where their quest came into focus
---or left it or the zoom changed, taken off where no longer near or drawn.
local function layOutAreas(position, viewRadius, radius)
    local pixelsPerYard = radius / viewRadius
    local look = ns.MapMarks.getAreaLook()
    -- (laid out again once the player has walked AREA_STEP_YARDS on: every area that could show before then)
    local reachYards = ns.MapMarks.AREA_REACH_YARDS + AREA_STEP_YARDS * 1.5
    local isWanted = {} -- [an area's triangles or edges] = true for what is on the canvas this time
    local first, second, third = {}, {}, {}
    for _, area in ipairs(shownAreas) do
        if not area.isPatrol and isAreaNear(area, position, viewRadius, reachYards) then
            local color = area.color or ns.MapMarks.getQuestColor(area.number, area.questId)
            local alpha = area.isFocused and look.focusedFillAlpha or look.fillAlpha
            -- (a fill or an outline switched off: nothing of it on the canvas, so what was there is taken off below)
            if look.hasFill and #area.triangles > 0 then
                local set = fillSets[area.triangles]
                if not set then
                    set = { textures = {} }
                    for _, triangle in ipairs(area.triangles) do
                        local texture = freeFills[#freeFills]
                        if texture then
                            freeFills[#freeFills] = nil
                        else
                            texture = glide(fillCanvas:CreateTexture(nil, "ARTWORK", nil, 1))
                        end
                        first.x, first.y = worldOrigin.west - triangle[1].x, worldOrigin.north - triangle[1].y
                        second.x, second.y = worldOrigin.west - triangle[2].x, worldOrigin.north - triangle[2].y
                        third.x, third.y = worldOrigin.west - triangle[3].x, worldOrigin.north - triangle[3].y
                        ns.MapMarks.setTriangle(texture, first, second, third, fillCanvas)
                        texture:Show()
                        set.textures[#set.textures + 1] = texture
                    end
                    fillSets[area.triangles] = set
                end
                if set.red ~= color[1] or set.green ~= color[2] or set.blue ~= color[3] or set.alpha ~= alpha then
                    for index = 1, #set.textures do
                        set.textures[index]:SetColorTexture(color[1], color[2], color[3], alpha)
                    end
                    set.red, set.green, set.blue, set.alpha = color[1], color[2], color[3], alpha
                end
                isWanted[area.triangles] = true
            end
            if (look.hasEdges or area.isRough) and #area.edges > 0 then
                local set = edgeSets[area.edges]
                if not set then
                    -- Two lines a leg; and how far the edge reaches (x west, y north), for finding the legs that
                    -- cross a circle kept clear (drawCutEdges)
                    set = {
                        lines = {},
                        isCut = {},
                        cutCount = 0,
                        edges = area.edges,
                        north = -math.huge,
                        south = math.huge,
                        west = -math.huge,
                        east = math.huge,
                    }
                    for index, edge in ipairs(area.edges) do
                        local fromX, fromY = worldOrigin.west - edge[1].x, worldOrigin.north - edge[1].y
                        local toX, toY = worldOrigin.west - edge[2].x, worldOrigin.north - edge[2].y
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
                    edgeSets[area.edges] = set
                end
                local rimAlpha, edgeAlpha = Rough.getEdgeAlphas(area, look)
                -- (the focused quest's edge thicker where the map's is: in the shapes look)
                local thicker = area.isFocused and look.focusedEdgePixels - look.edgePixels or 0
                if
                    set.color ~= color
                    or set.rimAlpha ~= rimAlpha
                    or set.edgeAlpha ~= edgeAlpha
                    or set.thicker ~= thicker
                    or set.pixelsPerYard ~= pixelsPerYard
                then
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
                    drawPieces(
                        fromX,
                        fromY,
                        toX,
                        toY,
                        radius,
                        clear,
                        MinimapPins.clipToSquare,
                        look.rimColor,
                        set.rimAlpha,
                        AREA_RIM_PIXELS + set.thicker,
                        set.color,
                        set.edgeAlpha,
                        AREA_EDGE_PIXELS + set.thicker
                    )
                end
            end
        end
    end
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
    -- On the canvas: a square minimap (its frame cuts them) that does not turn
    local isOnCanvas = position ~= nil
        and areaFrame ~= nil
        and fillCanvas ~= nil
        and not isAreaMasked
        and not facing
        and MinimapPins.isCanvasOff ~= true -- (off: every piece placed at every move, to compare the two ways)
    lastMove.isAreaCanvas = isOnCanvas
    if not isOnCanvas then
        if next(fillSets) or next(edgeSets) then
            releaseCanvasAreas()
        end
        hideCanvas(fillCanvas)
        drawAreasMoveByMove(position, viewRadius, radius, facing, clear)
        return
    end
    if drawnAreasKey ~= nil then
        -- The pieces placed move by move, when last drawn that way, leave
        drawnAreasKey = nil
        for index = 1, #triangles do
            local triangle = triangles[index]
            if triangle.isShownNow ~= false then
                triangle:Hide()
                triangle.isShownNow = false
            end
        end
    end
    ensureOrigin(position)
    local pixelsPerYard = radius / viewRadius
    placeCanvas(fillCanvas, position.north, position.west, pixelsPerYard)
    -- The areas near the player are on the canvas: laid out when they are chosen, when the zoom changes, and again
    -- once the player has walked on far enough for others to be near (those already there stay as they are)
    if
        areasLaidFor ~= shownAreas
        or areasLaidAt ~= pixelsPerYard
        or not areasLaidNorth
        or math.abs(position.north - areasLaidNorth) > AREA_STEP_YARDS
        or math.abs(position.west - areasLaidWest) > AREA_STEP_YARDS
    then
        areasLaidFor, areasLaidAt = shownAreas, pixelsPerYard
        areasLaidNorth, areasLaidWest = position.north, position.west
        layOutAreas(position, viewRadius, radius)
    end
    -- What is still placed on the minimap itself at a move: the legs that cross a circle kept clear, and the walks
    lines.usedCount = 0
    drawCutEdges(position, viewRadius, radius, clear or NO_PIECES)
    local reachYards = ns.MapMarks.AREA_REACH_YARDS
    for _, area in ipairs(shownAreas) do
        if area.isPatrol and isAreaNear(area, position, viewRadius, reachYards) then
            drawPatrol(area, position, viewRadius, radius, nil, clear)
        end
    end
    hideUnusedLines()
end

---@return table[] areas The areas near the player as the minimap shows them now, in pixels from its middle (up
---positive), for hovering: each with its spawns, how far it reaches round them, and its quest; a walk with its legs
local function composeDrawnAreas()
    local position = lastMove.north and lastMove or nil
    local composed = {}
    if not position or not areaFrame then
        return composed
    end
    local viewRadius, radius, facing = lastMove.viewRadius, lastMove.radius, lastMove.facing
    local reachYards = ns.MapMarks.AREA_REACH_YARDS
    for _, area in ipairs(shownAreas) do
        if isAreaNear(area, position, viewRadius, reachYards) then
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
            composed[#composed + 1] = drawn
        end
    end
    return composed
end

---@return table[] spots The spawn icons of the canvas that are inside the minimap's edge now, in pixels from its
---middle (up positive), for hovering
local function composeDrawnSpots()
    local composed = {}
    if not lastMove.north then
        return composed
    end
    local pixelsPerYard = lastMove.radius / lastMove.viewRadius
    for spotIndex, shown in ipairs(shownSpots) do
        local spot = spots[spotIndex]
        if spot and spot.isIn then
            composed[#composed + 1] = {
                x = (lastMove.west - spot.west) * pixelsPerYard,
                y = (spot.north - lastMove.north) * pixelsPerYard,
                radius = SPOT_HOVER_RADIUS,
                questId = shown.questId,
                isFocused = shown.isFocused,
            }
        end
    end
    return composed
end

---Every frame: the canvases slid to where the land is now. Everything that stands on the land hangs on them (the
---spawn icons, the areas, the marks at their places), so all of it moves with the land, exactly and together, for
---one or two calls a frame while the player moves and none while they stand. What changes with where the player
---is (which icons are inside the edge, what is faded, the rim's pointer) is still looked at a few times a second
---(MinimapPins.move).
function MinimapPins.slide()
    if not lastMove.isOnCanvas or not worldOrigin then
        return
    end
    local north, west, continentId = getFramePosition()
    if not north or continentId ~= worldOrigin.continentId then
        return
    end
    local pixelsPerYard = lastMove.radius / lastMove.viewRadius
    placeCanvas(spotCanvas, north, west, pixelsPerYard)
    if lastMove.isAreaCanvas then
        placeCanvas(fillCanvas, north, west, pixelsPerYard)
    end
end

---@return table? spot A spawn icon of the pool as it stands: its textures, its cell and its place in the world (for
---the tests and the simulator's audits)
function MinimapPins.getSpot(index)
    return spots[index]
end

---@return table[] pool, table[] shown The spawn icons' objects and what each shows (for the tests and the simulator)
function MinimapPins.getSpotPool()
    return spots, shownSpots
end

---@return table[] spots, table[] areas What the minimap shows now, in pixels from its middle (up positive), each
---with its questId, for hovering. Worked out when asked for (the pointer on the minimap), not at every move.
function MinimapPins.getDrawn()
    if areDrawnSpotsStale then
        areDrawnSpotsStale = false
        drawnSpots = composeDrawnSpots()
    end
    if areDrawnAreasStale then
        areDrawnAreasStale = false
        drawnAreas = composeDrawnAreas()
    end
    return drawnSpots, drawnAreas
end

---@return string key What the minimap's marks depend on: where the player is and faces, the zoom, the minimap's
---size and shape, and where the party is. The same key: nothing to place again.
-- What the minimap's marks were last placed for (MinimapPins.hasStateChanged), as plain numbers and strings kept
-- here: compared 20 times a second without making anything new
local lastState = {}
local NO_UNITS = {} -- shared, never filled: alone, no table is made
local SLOW_STATE_LOOKS = 5 -- of so many looks, one also asks what seldom changes
local slowStateCount = SLOW_STATE_LOOKS

---@return boolean changed Something the marks depend on changed since the last look: where the player is (in steps
---of half a pixel of the minimap, so walking places them a few times a second, not every frame), where they face on
---a turning minimap, the zoom, the minimap's size, scale and shape, and where the party is.
function MinimapPins.hasStateChanged()
    local changed = false
    -- What seldom changes, the minimap's size, scale, shape and zoom and whether it turns, is asked a few times a
    -- second (the zoom says so itself besides: MINIMAP_UPDATE_ZOOM); where no frames run (the tests), every time
    slowStateCount = slowStateCount + 1
    if slowStateCount >= SLOW_STATE_LOOKS or ns.frameNumber == 0 then
        slowStateCount = 0
        local width = Minimap:GetWidth() or 0
        local viewRadius = getViewRadius()
        local scale = Minimap:GetEffectiveScale() or 0
        local _, shape = MinimapPins.getShape()
        local isRotating = readRotating()
        changed = viewRadius ~= lastState.viewRadius
            or width ~= lastState.width
            or scale ~= lastState.scale
            or shape ~= lastState.shape
            or isRotating ~= lastState.isRotating
        lastState.viewRadius, lastState.width, lastState.scale, lastState.shape, lastState.isRotating =
            viewRadius, width, scale, shape, isRotating
    end
    -- Where the player is, and where they face on a minimap that turns: at every look
    local width, viewRadius = lastState.width, lastState.viewRadius
    local radius = (width > 0 and width or 140) / 2
    local step = viewRadius * STATE_STEP_PIXELS / radius
    local playerNorth, playerWest = getFramePosition()
    local north = playerNorth and math.floor(playerNorth / step + 0.5) or false
    local west = playerNorth and math.floor(playerWest / step + 0.5) or false
    local facing = lastState.isRotating and GetPlayerFacing and math.floor((GetPlayerFacing() or 0) * 1000 + 0.5)
        or false
    changed = changed or north ~= lastState.north or west ~= lastState.west or facing ~= lastState.facing
    lastState.north, lastState.west, lastState.facing = north, west, facing
    -- The party's places, a member at a time (alone, nothing looked up)
    local units = IsInGroup and not IsInGroup() and NO_UNITS or ns.Party.getUnits()
    local uiMapId = #units > 0 and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local count = 0
    for _, unit in ipairs(uiMapId and units or {}) do
        local mapPosition = C_Map.GetPlayerMapPosition(uiMapId, unit)
        local x, y = 0, 0
        if mapPosition then
            x, y = mapPosition:GetXY()
        end
        x, y = math.floor((x or 0) * 10000 + 0.5), math.floor((y or 0) * 10000 + 0.5)
        count = count + 1
        if lastState[count * 2 + 100] ~= x or lastState[count * 2 + 101] ~= y then
            changed = true
            lastState[count * 2 + 100], lastState[count * 2 + 101] = x, y
        end
    end
    if count ~= lastState.partyCount then
        changed, lastState.partyCount = true, count
    end
    return changed
end

function MinimapPins.create()
    if not Minimap then
        return
    end
    -- The quests' areas, over the land and under everything else of ours, cut to the minimap's round edge
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
    -- The canvas of the areas' fills and edges (drawAreas), and over it the frame of what is placed on the minimap
    -- itself (the walks' dashes, an edge cut round the player): both the area frame's own, so its see-through look
    -- and, on a square minimap, its cut are theirs
    fillCanvas = CreateFrame("Frame", nil, areaFrame)
    fillCanvas:SetSize(1, 1)
    fillCanvas:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 2)
    fillCanvas:Hide()
    lineFrame = CreateFrame("Frame", nil, areaFrame)
    lineFrame:SetAllPoints(areaFrame)
    lineFrame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 3)
    frame = CreateFrame("Frame", nil, Minimap)
    frame:SetAllPoints(Minimap) -- the spawn squares are drawn on it; a frame with no place draws nothing
    frame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 4) -- over the land and the areas, under the marks
    -- The spawn icons' canvas (MinimapPins.move): over the marks' glows, which lie on the frame above, and under the marks
    spotCanvas = CreateFrame("Frame", nil, frame)
    spotCanvas:SetSize(1, 1)
    spotCanvas:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 5)
    spotCanvas:Hide()
    ringFrame = CreateFrame("Frame", nil, Minimap)
    ringFrame.isOurs = true
    ringFrame:SetAllPoints(Minimap)
    ringFrame:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 20) -- over every mark of ours
    playerArrow = ringFrame:CreateTexture(nil, "OVERLAY", nil, 3)
    playerArrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    playerArrow:SetSize(PLAYER_ARROW_SIZE, PLAYER_ARROW_SIZE)
    playerArrow:SetPoint("CENTER", Minimap, "CENTER", 0, 0)
    local sinceFullMove, lastHandover = 0, nil
    frame:SetScript(
        "OnUpdate",
        ns.Timing.timed("minimap follows the player (each frame)", function(_, elapsed)
            if not areMarksShown then
                return -- (switched off: nothing of ours to turn, slide or place)
            end
            MinimapPins.turnArrow()
            MinimapPins.slide()
            -- A turn-in handed to the game's own "?", or taken back, in the same frame the distance crosses: no flash
            local handover = MinimapPins.getHandoverBits()
            if handover ~= lastHandover then
                lastHandover = handover
                ns.Timing.measure("minimap marks placed", MinimapPins.move)
            end
            elapsedSeconds = elapsedSeconds + elapsed
            sinceFullMove = sinceFullMove + elapsed
            if elapsedSeconds >= MOVE_SECONDS then
                elapsedSeconds = 0
                -- Placed again only when something it shows changed, as HereBeDragons does, and once a second anyway
                if MinimapPins.hasStateChanged() or sinceFullMove >= FULL_MOVE_SECONDS then
                    sinceFullMove = 0
                    ns.Timing.measure("minimap marks placed", MinimapPins.move)
                end
            end
        end)
    )
    MinimapPins.refresh()
    -- The quest givers come once the database is read (a moment after login): the marks are chosen again then, also
    -- for a player standing still (moving is what chooses them again otherwise)
    ns.Availability.prepare(MinimapPins.refresh)
end

ns.on("FOCUS_CHANGED", function()
    MinimapPins.refresh()
end) -- the quest in focus stands out at once, its areas and spawns
ns.registerModule({
    name = "MinimapPins",
    create = MinimapPins.create,
    refresh = MinimapPins.refreshAfterChange,
    tick = MinimapPins.tick,
    events = {
        -- The minimap zoomed (the wheel, its buttons, going indoors): everything follows at the next frame
        MINIMAP_UPDATE_ZOOM = function()
            slowStateCount = SLOW_STATE_LOOKS
            elapsedSeconds = MOVE_SECONDS
        end,
    },
})
