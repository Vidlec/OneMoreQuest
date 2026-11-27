local _, ns = ...

-- What the minimap shows, chosen for the land round the player (MinimapPins.compose): each tracked quest's marks at
-- the places the world map puts them, its spawns and its areas, its patrols, the quest givers' "!", and the quest
-- picked on the Available tab. Only the choosing: placing and drawing it is MinimapPins' and MinimapAreas'.
local MinimapPins = ns.MinimapPins

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
-- The game draws its own "?" for whom a quest is handed in to once the server has sent that creature to the client:
-- within its visibility range, the same everywhere and the same coming and going (120 yards, measured with /omq distance:
-- the game's came and went at 120). Inside the minimap's view but beyond that range, the turn-in has our mark. Whether
-- it shows is checked as often as marks move (MOVE_SECONDS), not once a second, so the two hand over within a step and
-- never stand over each other (their places differ by a few yards). Checked every frame.
local TURN_IN_HANDOVER_YARDS = 120
-- "Icons and areas": each tracked quest's areas, exactly as on the world map (worked out on the zone's map the same
-- way, then placed in the world)
local ZONE_MAP_TYPE = 3 -- the game's map types: continent 2, zone 3, then dungeons, towns and buildings inside
local GIVER_PATROL_COLOR = { 1, 0.86, 0.2 } -- the gold of a quest giver's "!"

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
function MinimapPins.getZoneMapId(uiMapId)
    local info = uiMapId and C_Map.GetMapInfo and ns.Database.getMapInfo(uiMapId)
    while info and info.mapType and info.mapType > ZONE_MAP_TYPE and info.parentMapID and info.parentMapID > 0 do
        uiMapId = info.parentMapID
        info = ns.Database.getMapInfo(uiMapId)
    end
    return uiMapId
end
local getZoneMapId = MinimapPins.getZoneMapId

-- The places' squares of the world (Squares.of, below) and their sums (MinimapPins.composeQuestAreas)
local Squares = {
    YARDS = 500,
    MIN_PLACES = 64,
    NONE = {},
    byPlaces = setmetatable({}, { __mode = "k" }),
    sums = setmetatable({}, { __mode = "k" }), -- [places] = { count, sum } (MinimapPins.composeQuestAreas)
}

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
    -- (the places' sum kept with their list: worked out for every one of thousands at every composing before)
    local summed = Squares.sums[places]
    if not summed or summed[1] ~= #places then
        local sum = 0
        for index = 1, #places do
            local place = places[index]
            sum = sum + (place.x or 0) * 7919 + (place.y or 0) * 31 + (place.zoneId or 0)
        end
        summed = { #places, sum }
        Squares.sums[places] = summed
    end
    local cacheKey =
        string.format("%s:%s:%d:%d:%.4f", kind or "objectives", tostring(questId), uiMapId, #places, summed[2])
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
    if isPending then
        ns.MapMarks.isMinimapAwaitingShapes = true -- (drawn again when they are worked out: Areas' job)
    end
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

local mapMarkPlacesCache = {} -- [zone map and quest in focus] = composeMapMarkPlaces: the whole zone's marks worked
-- out, kept till the quests next change (MinimapPins.refresh), not again every few yards walked

---Where the world map's marks stand is worked out again at the next choosing: the quests, or the settings, changed.
function MinimapPins.forgetMapMarkPlaces()
    mapMarkPlacesCache = {}
end

---@return table<number, table[]> places [quest] = where the world map puts its marks on the player's zone map, in
---the world: the minimap puts them there too, so a mark stays put as the player moves, as on the map
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

---Gives a place its world position (continentId, north, west; north false where it has none), the first time it is
---measured: it keeps it from then on.
function Squares.locate(place)
    if place.north == nil then
        local continentId, north, west =
            ns.Geometry.getWorldPosition(ns.Database.getUiMapId(place.zoneId), place.x, place.y)
        place.continentId, place.north, place.west = continentId, north or false, west
    end
end

---@return number? distance How far a place is from the player, in yards; nil for one not on their continent
local function getPlaceDistance(place, player)
    Squares.locate(place)
    if place.north and place.continentId == player.continentId then
        return ns.Geometry.getDistance(player.north, player.west, place.north, place.west)
    end
    return nil
end
MinimapPins.getPlaceDistance = getPlaceDistance

-- A long list of places (a quest's spawns: thousands, all over the world) sorted into squares of the world once,
-- so what is near the player is found in the squares round them, not by measuring every place at every composing
-- (My First Alchemy Set's 14,794, twice at a focus change). Squares.YARDS across; lists shorter than MIN_PLACES are
-- measured place by place. byPlaces: [places] = { count, squares = { [square] = places } }

---@return number key A square of the world as one number: its continent, and its column and row
function Squares.key(continentId, column, row)
    return ((continentId or 0) * 4096 + column + 2048) * 4096 + row + 2048
end

---@return table<number, table[]> squares [square] = the places in it, sorted once for a list of places (again when
---the list grows)
function Squares.of(places)
    local index = Squares.byPlaces[places]
    if index and index.count == #places then
        return index.squares
    end
    local squares = {}
    for _, place in ipairs(places) do
        Squares.locate(place)
        if place.north then
            local key = Squares.key(
                place.continentId,
                math.floor(place.north / Squares.YARDS),
                math.floor(place.west / Squares.YARDS)
            )
            local square = squares[key]
            if not square then
                square = {}
                squares[key] = square
            end
            square[#square + 1] = place
        end
    end
    Squares.byPlaces[places] = { count = #places, squares = squares }
    return squares
end

---The places within a distance of the player, each a candidate for a mark or a spawn icon.
---@param limitYards number? Further off than this they are left out (nil: all of them)
---@return number nearestBeyond How near the nearest place left out is (math.huge when none was)
local function addPlaces(candidates, places, data, player, isSpawnOnly, limitYards)
    local nearestBeyond = math.huge
    if limitYards and #places >= Squares.MIN_PLACES and player.north then
        -- The squares within the limit and one square more: the places in any other square are further off than that
        local span = math.ceil(limitYards / Squares.YARDS) + 1
        local column, row = math.floor(player.north / Squares.YARDS), math.floor(player.west / Squares.YARDS)
        local squares = Squares.of(places)
        for columnStep = -span, span do
            for rowStep = -span, span do
                local square = squares[Squares.key(player.continentId, column + columnStep, row + rowStep)]
                for _, place in ipairs(square or Squares.NONE) do
                    local distance = getPlaceDistance(place, player)
                    if distance then
                        if distance <= limitYards then
                            candidates[#candidates + 1] =
                                { place = place, data = data, distance = distance, isSpawnOnly = isSpawnOnly }
                        elseif distance < nearestBeyond then
                            nearestBeyond = distance
                        end
                    end
                end
            end
        end
        return math.min(nearestBeyond, span * Squares.YARDS)
    end
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
-- drawn whatever the areas' outline is set to (it is all there is of its quest: MinimapAreas draws it).
local Rough = {
    LEGS = 40,
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

---@return number spacing How far apart the spawns are kept at this zoom: thinned as on the world map, in the same
---world squares, to the minimap's zoom, so the same spawns are kept, each on its own spot, whichever map shows them
local function chooseSpawnSpacing(viewRadius)
    local minimapRadius = Minimap and Minimap.GetWidth and (Minimap:GetWidth() or 0) / 2 or 0
    return minimapRadius > 0
            and viewRadius > 0
            and ns.MapMarks.chooseSpawnSpacing(
                minimapRadius / viewRadius,
                MinimapPins.spawnSpacing,
                ns.MapMarks.getSpawnMarkerRoom(ns.settings.minimapSpawnMarkerScale)
            )
        or 0
end

---@return table choosing One choosing of what the minimap shows: what it is made for (where the player is, the
---quests' numbers, how far it reaches) and the lists it fills: candidates (places that may get a mark or an icon,
---nearest first once sorted), composed (the marks), composedAreas, and how near the nearest place left out is
local function startChoosing(position, viewRadius)
    local choosing = {
        position = position,
        player = ns.Model.getPlayer(),
        activeQuestId = ns.Focus.get(),
        numbers = ns.QuestState.getWatchNumbers(),
        candidates = {},
        composed = {},
        composedAreas = {},
        nearestLeftOut = math.huge,
    }
    choosing.mapMarkPlaces = composeMapMarkPlaces(position)
    -- What is chosen: everything within what the minimap sees and a margin past it (REGION_MARGIN_YARDS). How near
    -- the nearest place left out is says how far the player may walk before the choosing is done again.
    choosing.reach = MinimapPins.getReach(viewRadius)
    choosing.regionYards = choosing.reach + REGION_MARGIN_YARDS
    -- (Spawns are gathered a square past the region: which of a square's spawns is kept is then the same wherever
    -- the region's edge cuts it.)
    choosing.spacing = chooseSpawnSpacing(viewRadius)
    MinimapPins.spawnSpacing = choosing.spacing
    choosing.gatherYards = choosing.regionYards + choosing.spacing * 1.5
    -- What the player chose to see (Spoilers; nil in Guide, where all of it shows)
    choosing.spoilers = ns.MapMarks.getSpoilers(true)
    return choosing
end

local function noteLeftOut(choosing, yards)
    choosing.nearestLeftOut = math.min(choosing.nearestLeftOut, yards)
end

---The places within the gathering's reach become candidates for a mark (or, isSpawnOnly, a spawn icon).
local function addCandidates(choosing, places, mark, isSpawnOnly)
    noteLeftOut(
        choosing,
        addPlaces(choosing.candidates, places, mark, choosing.position, isSpawnOnly, choosing.gatherYards)
    )
end

---@return table mark What a tracked quest's marks show: its number and glyph, its progress ring, its tooltip's lines
local function makeQuestMark(entry, number, isActive)
    local title = string.format("[%d] %s", entry.level, entry.title)
    return {
        kind = entry.isTurnIn and "turnIn" or "objective",
        questId = entry.questId,
        isFocused = isActive,
        glyph = ns.MapMarks.getQuestGlyph(entry.questId, entry.objectives),
        number = number,
        progress = entry.isTurnIn and 1 or ns.MapMarks.getProgress(entry),
        lines = {
            title,
            entry.isTurnIn and ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver")) or nil,
        },
        counted = not entry.isTurnIn and {} or nil, -- how far along it is, read afresh as its tooltip opens (MapMarks.refreshMarkTexts)
    }
end

---Whom a quest is handed in to has the game's own "?" on the minimap once near: ours points the way from the rim for
---the followed quest (addQuestPlaces), and stands at the place in view until the game's has surely come. Always
---composed: whether its place is in view is the minimap's own shape's to say (a square one sees further in its
---corners than its radius), checked as it moves.
local function addTurnInMark(choosing, mark, nearestPlace, nearestOf)
    if nearestPlace and nearestPlace.continentId == choosing.position.continentId then
        local composed = choosing.composed
        composed[#composed + 1] = {
            place = nearestPlace,
            data = mark,
            isKeptOnRim = false,
            handoverYards = TURN_IN_HANDOVER_YARDS,
            isGameLook = true,
            nearestOf = nearestOf,
        }
    end
end

---A quest's marks where the world map has them, within the region chosen.
local function addMapMarks(choosing, mark, fixedPlaces)
    local position, composed = choosing.position, choosing.composed
    for _, place in ipairs(fixedPlaces) do
        if place.continentId == position.continentId then
            local distance = ns.Geometry.getDistance(position.north, position.west, place.north, place.west)
            if distance <= choosing.regionYards then
                composed[#composed + 1] = { place = place, data = mark, isKeptOnRim = false, distance = distance }
            else
                noteLeftOut(choosing, distance)
            end
        end
    end
end

---A tracked quest's areas: as on the world map, or while "Rough" (Spoilers) a dashed ring round each area, no spawn
---and no shape. Where its creatures walk: each patrol drawn as an area's edge with nothing inside, in every look
---(only with its objectives shown exactly).
local function addQuestAreas(choosing, questId, shownStep, spawnPlaces, isActive)
    local position, composedAreas, number = choosing.position, choosing.composedAreas, choosing.numbers[questId]
    if shownStep and shownStep.circles then
        for _, circle in ipairs(shownStep.circles) do
            local area = Rough.getArea(circle)
            if area and area.continentId == position.continentId then
                composedAreas[#composedAreas + 1] = {
                    questId = questId,
                    number = number,
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
        return
    end
    for _, area in
        ipairs(MinimapPins.composeQuestAreas(questId, spawnPlaces or {}, position, shownStep and "found" or nil))
    do
        composedAreas[#composedAreas + 1] = {
            questId = questId,
            number = number,
            isFocused = isActive,
            triangles = area.triangles,
            edges = area.edges,
            points = area.points,
        }
    end
    if not shownStep then
        addPatrolAreas(
            composedAreas,
            ns.Location.getObjectivePatrols(questId),
            position,
            { questId = questId, number = number, isFocused = isActive }
        )
    end
end

---One tracked quest's marks, spawns and areas on the minimap: as on the world map, or, while something is held back
---(Spoilers), only what may show of it (shownStep: MapMarks.getShownStep).
local function addQuestPlaces(choosing, entry, shownStep)
    local questId = entry.questId
    local isActive = questId == choosing.activeQuestId
    -- Where its pointer and its marks may lead, and which places are its spawns: its own, or what may show of them
    local nearestPlace, nearestOf, spawnPlaces = entry.nearestPlace, entry.places, entry.allPlaces
    if shownStep then
        nearestOf, spawnPlaces = shownStep.places, shownStep.spawns
        nearestPlace = select(3, ns.Geometry.getNearest(nearestOf, choosing.position, ns.Database.getUiMapId))
    end
    local mark = makeQuestMark(entry, choosing.numbers[questId], isActive)
    if isActive and nearestPlace then
        -- The followed quest's nearest place has a pointer on the rim while it is out of view. Which place is
        -- the nearest, and whether it is in view, follow the player (MinimapPins.move, .followNearest)
        local composed = choosing.composed
        composed[#composed + 1] = { place = nearestPlace, data = mark, isKeptOnRim = true, nearestOf = nearestOf }
    end
    if entry.isTurnIn then
        addTurnInMark(choosing, mark, nearestPlace, nearestOf)
        return
    end
    local fixedPlaces = choosing.mapMarkPlaces[questId]
    if fixedPlaces then
        -- Its mark where the world map has it, every spawn an icon of its own
        addMapMarks(choosing, mark, fixedPlaces)
        addCandidates(choosing, spawnPlaces, mark, true)
    else
        -- Not drawn on this zone's map (a dungeon's quest, a place over the zone's edge): its mark at the
        -- nearest of its places
        addCandidates(choosing, shownStep and nearestOf or entry.allPlaces, mark, false)
    end
    addQuestAreas(choosing, questId, shownStep, spawnPlaces, isActive)
end

---@return boolean isShown The quest givers have marks on the minimap: the player's zone known, the givers read, shown
---on the map, and not all held back (Spoilers)
local function areGiversShown(choosing)
    local spoilers = choosing.spoilers
    return choosing.player.zoneId
        and ns.Availability.isReady()
        and ns.Availability.isShownOnMap()
        and not (spoilers and spoilers.get("pickup") == "none")
end

---The selected quest's giver, and whom it is handed in to, when they walk about: their paths in gold.
---@param isPatrolDrawn table<number, boolean> The creatures whose paths are drawn already
local function addSelectedPatrols(choosing, questId, isPatrolDrawn)
    local spoilers = choosing.spoilers
    local npcIds = ns.Location.getStarterNpcIds(questId)
    if not spoilers or ns.MapMarks.isTurnInShown(spoilers, questId) then
        for _, npcId in ipairs((ns.Database.getQuestField(questId, "finishedBy") or {})[1] or {}) do
            npcIds[#npcIds + 1] = npcId
        end
    end
    for _, npcId in ipairs(npcIds) do
        if not isPatrolDrawn[npcId] then
            isPatrolDrawn[npcId] = true
            addPatrolAreas(
                choosing.composedAreas,
                ns.Location.getNpcPatrols(npcId),
                choosing.position,
                { questId = questId, isFocused = true, color = GIVER_PATROL_COLOR }
            )
        end
    end
end

---Where the selected quest starts when that is creatures (an item they drop, or several givers about): their spawns
---and areas, as the world map shows them, in the gold of the quest's "!".
local function addSelectedStart(choosing, quest)
    local itemSource = quest.startType == "item" and ns.Location.getStartItemSource(quest.questId)
    local startPlaces = itemSource and itemSource.places or quest.places or {}
    if #startPlaces <= 1 then
        return
    end
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
    addCandidates(choosing, spawns, spawnMark, true)
    local composedAreas = choosing.composedAreas
    for _, area in ipairs(MinimapPins.composeQuestAreas(quest.questId, spawns, choosing.position, "start")) do
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

---A quest to pick up joins its giver's mark: a giver with several quests is one mark, its quests sharing the same
---place, and its tooltip lists them. Only the nearest place of each quest: one that starts from a dropped item would
---otherwise mark every creature around (and while something is held back, one out of the map's fog, outside a
---dungeon held back).
---@param givers { markByPlace: table, places: table[] } The givers' marks so far, by place and in order
local function addGiverQuest(givers, quest, selectedQuestId, spoilers)
    local place = quest.nearestPlace or quest.places[1]
    if not place or (spoilers and not ns.MapMarks.isGiverPlaceShown(spoilers, quest.questId, place)) then
        return
    end
    local line = string.format("[%d] %s", quest.level, quest.title)
        .. (quest.starterName and (" - " .. quest.starterName) or "")
    local mark = givers.markByPlace[place]
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
        givers.markByPlace[place] = mark
        givers.places[#givers.places + 1] = place
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

---The givers' marks placed: a giver standing there has the game's own "!" once the server has sent them (as a
---turn-in's "?", TURN_IN_HANDOVER_YARDS); further out, in view, ours, drawn just like it, so the zone's givers show
---before the game's come. The others are candidates as any quest's places.
local function addGiverMarks(choosing, givers)
    local composed = choosing.composed
    for _, place in ipairs(givers.places) do
        local mark = givers.markByPlace[place]
        if mark.isGameLook then
            local distance = getPlaceDistance(place, choosing.position)
            if distance and distance <= choosing.regionYards then
                composed[#composed + 1] = {
                    place = place,
                    data = mark,
                    isKeptOnRim = false,
                    handoverYards = TURN_IN_HANDOVER_YARDS,
                    isGameLook = true,
                    distance = distance,
                }
            elseif distance then
                noteLeftOut(choosing, distance)
            end
        else
            addCandidates(choosing, { place }, mark, false)
        end
    end
end

---The quest givers of the zone. A quest giver has the game's own "!" on the minimap, with its arrow: ours only for
---what the game cannot show, a quest that starts from a dropped item, and the quest selected on the Available tab
---(kept with the quest log closed, so it shows while the player walks there).
local function addGivers(choosing)
    local spoilers = choosing.spoilers
    local givers = { markByPlace = {}, places = {} }
    local selectedQuestId = ns.Log.getChosenAvailableQuestId and ns.Log.getChosenAvailableQuestId()
    local isPatrolDrawn = {}
    for _, quest in
        ipairs(
            ns.Availability.getQuests(
                choosing.player.zoneId,
                { shouldShowLowLevel = ns.settings.shouldShowLowLevel, shouldIncludeEntrances = true }
            )
        )
    do
        -- (while something is held back, only the quests the player chose to see: Spoilers)
        local isOffered = not quest.availableAtLevel
            and not quest.isHandedInHere
            and (not spoilers or ns.MapMarks.isGiverQuestShown(spoilers, quest.questId))
        if isOffered then
            if quest.questId == selectedQuestId then
                addSelectedPatrols(choosing, quest.questId, isPatrolDrawn)
                addSelectedStart(choosing, quest)
            end
            addGiverQuest(givers, quest, selectedQuestId, spoilers)
        end
    end
    addGiverMarks(choosing, givers)
end

---@return table[] candidates The candidates with each mark's spawns thinned to the spacing, in the same world squares
---as on the world map (MapMarks.thinPoints)
local function thinSpawns(candidates, spacing)
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
    return thinned
end

local function isNearer(first, second)
    return first.distance < second.distance
end

---Nearest first: a quest's nearest place gets its mark, the rest of its places are squares.
---@return { place: table, isFocused: boolean, number: number?, questId: number?, color: table? }[] spots
local function chooseMarksAndSpots(choosing)
    local candidates, composed = choosing.candidates, choosing.composed
    table.sort(candidates, isNearer)
    local isMarked, composedSpots = {}, {}
    for _, candidate in ipairs(candidates) do
        if candidate.distance > choosing.regionYards then
            noteLeftOut(choosing, candidate.distance) -- (gathered past the region for the thinning only)
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
                noteLeftOut(choosing, candidate.distance)
            end
        end
    end
    return composedSpots
end

---More marks than are drawn: the furthest go (never the rim's pointer, nor whom a quest is handed in to).
local function dropFurthestMarks(choosing)
    local composed = choosing.composed
    local droppable = {}
    for _, shown in ipairs(composed) do
        if shown.distance then
            droppable[#droppable + 1] = shown.distance
        end
    end
    if #composed <= MAX_PINS or #droppable == 0 then
        return
    end
    table.sort(droppable)
    local limit = droppable[math.max(1, #droppable - (#composed - MAX_PINS) + 1)]
    local kept = {}
    for _, shown in ipairs(composed) do
        if shown.distance and shown.distance >= limit then
            noteLeftOut(choosing, shown.distance)
        else
            kept[#kept + 1] = shown
        end
    end
    choosing.composed = kept
end

---Picks what the minimap shows round the player: every tracked quest's marks, spawns and areas, and the quest
---givers', within what it sees and a margin past it (REGION_MARGIN_YARDS), plus the followed quest's nearest place.
---@return { place: table, data: table, isKeptOnRim: boolean }[] places Each with the mark to draw as data
---@return { place: table, isFocused: boolean }[] spots The other places of tracked quests in range, drawn as squares
---@return table[] areas Each tracked quest's areas near the player, for "icons and areas"
---@return number validYards How far the player may walk from here before something left out could come into view:
---all of it holds till then (math.huge: nothing was left out)
function MinimapPins.compose(viewRadius)
    local position = ns.Geometry.getPlayerPosition()
    if not position then
        return {}, {}, {}, math.huge
    end
    local choosing = startChoosing(position, viewRadius)
    for _, questId in ipairs(ns.QuestState.getShownOnMapQuestIds()) do -- (tracked, and any ready to hand in)
        local entry = ns.Model.composeEntry(questId, choosing.player)
        -- While something is held back: what of its step may show (nil: all of it), nothing at all when none may
        local shownStep = choosing.spoilers and ns.MapMarks.getShownStep(entry, choosing.spoilers)
        if not (shownStep and shownStep.isHidden) then
            addQuestPlaces(choosing, entry, shownStep)
        end
    end
    if areGiversShown(choosing) then
        addGivers(choosing)
    end
    if choosing.spacing > 0 then
        choosing.candidates = thinSpawns(choosing.candidates, choosing.spacing)
    end
    local composedSpots = chooseMarksAndSpots(choosing)
    dropFurthestMarks(choosing)
    local nearestLeftOut = choosing.nearestLeftOut
    local validYards = nearestLeftOut == math.huge and math.huge
        or math.max(MIN_VALID_YARDS, nearestLeftOut - choosing.reach - VALID_SLACK_YARDS)
    return choosing.composed, composedSpots, choosing.composedAreas, validYards
end
