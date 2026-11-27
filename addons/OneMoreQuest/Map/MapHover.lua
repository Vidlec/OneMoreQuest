local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Hovering a quest's area or one of its spawn marks, on the world map or the minimap, shows the quest's tooltip
-- as the game shows it for its own quest areas: the title, what kind of quest it is, then each objective still to
-- do, an item's with the creatures that drop it and their chances. A spawn mark adds what is there (the creature
-- that drops the item, and its chance). Where areas overlap,
-- each quest under the cursor is listed, the one in focus first. Alt-click on the world map puts the quest whose area
-- (or spawn mark) is under the cursor in focus; where several overlap, a menu asks which. (Not ctrl-click, as on a
-- mark: on the map that is the game's waypoint, and the areas cover much of the map.)
local MapHover = {}
ns.MapHover = MapHover

local TITLE_COLOR = { 1, 0.82, 0 } -- the game's NORMAL_FONT_COLOR
local LINE_COLOR = { 1, 1, 1 }
local NOTE_COLOR = { 0.7, 0.7, 0.7 }
local CHANCE_COLOR = { 0.55, 0.8, 1 } -- as on creatures' tooltips
local MAX_SOURCES = 3 -- creatures listed under an item objective; the rest are counted
local MAX_QUESTS = 4 -- listed under the cursor; past that the areas are too thick to point at one
local CHECK_SECONDS = 0.05
local MAX_PIN_SIZE = 48 -- a frame under the cursor this small is a pin, which shows its own tooltip

---Adds one quest's lines to a tooltip, in the game's words for a quest area.
---@param note string? What is at the spawn hovered
---@param isFirst boolean The tooltip's title line, or a quest below another
function MapHover.addQuestLines(tooltip, questId, note, isFirst)
    local isInLog = ns.QuestState.isInLog(questId)
    local quest = isInLog and ns.QuestState.getQuest(questId)
    local title = quest and quest.title
        or ns.QuestText.getTitle(questId, ns.Database.getQuestField(questId, "name") or ("Quest " .. questId))
    if not isFirst then
        tooltip:AddLine(" ")
    end
    ns.QuestTooltip.addTitle(tooltip, title, questId, TITLE_COLOR) -- (its level, a group quest's kind, its experience)
    local typeIndexes = {}
    for _, objective in ipairs(quest and quest.objectives or {}) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if not objective.isFinished then
            local text = objective.shownText or objective.text or objective.shownLabel or objective.label
            tooltip:AddLine("- " .. text, LINE_COLOR[1], LINE_COLOR[2], LINE_COLOR[3], true)
            -- An item: what drops it and how often, unless the spawn hovered already says
            if objective.type == "item" and not note then
                MapHover.addDropLines(tooltip, questId, typeIndexes.item)
            end
        end
    end
    if not isInLog then
        tooltip:AddLine(ns.L("Not picked up yet"), NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3])
    end
    if note then
        tooltip:AddLine(note, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true)
    end
    -- With Shift held: what it asks, its rewards, where it is handed in (its objectives are listed above already)
    ns.QuestTooltip.addDetails(tooltip, questId, { hasObjectives = isInLog })
end

---Under an item objective: the creatures (and objects) that drop it in the zone worth going to, likeliest first,
---each with its drop chance. As far as the player chose to know (Spoilers' drops, a hint for the quest lifting it):
---with chances; names alone; only those that dropped it for the player; nothing.
function MapHover.addDropLines(tooltip, questId, typeIndex)
    local choice = ns.Spoilers.isActive() and ns.Spoilers.get("drops", questId) or "chances"
    if choice == "hidden" then
        return
    end
    local target = ns.Location.getObjectiveTarget(questId, "item", typeIndex)
    local zone = target and target.itemId and ns.Drops.getZones(target.itemId)[1]
    local sources = zone and zone.sources or {}
    if choice == "found" then
        local found = {}
        for _, source in ipairs(sources) do
            if ns.Spoilers.hasSeenDrop(target.itemId, source.npcId or source.objectId) then
                found[#found + 1] = source
            end
        end
        sources = found
    end
    for index, source in ipairs(sources) do
        if index > MAX_SOURCES then
            tooltip:AddLine(
                ns.Lp(#sources - MAX_SOURCES, "   + %d more", "   + %d more"),
                NOTE_COLOR[1],
                NOTE_COLOR[2],
                NOTE_COLOR[3]
            )
            break
        end
        if source.chance and choice == "chances" then
            tooltip:AddDoubleLine(
                "   " .. source.name,
                ns.Drops.formatChance(source.chance),
                NOTE_COLOR[1],
                NOTE_COLOR[2],
                NOTE_COLOR[3],
                CHANCE_COLOR[1],
                CHANCE_COLOR[2],
                CHANCE_COLOR[3]
            )
        else
            tooltip:AddLine("   " .. source.name, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3])
        end
    end
end

local LINE_REACH = 4 -- how near a patrol's line, in pixels, the pointer must be

---@param segments number[][]? Each { x1, y1, x2, y2 }
---@return boolean isOn The point is on one of the lines, within a few pixels of it
function MapHover.isOnLine(segments, x, y)
    for _, segment in ipairs(segments or {}) do
        local ax, ay, bx, by = segment[1], segment[2], segment[3], segment[4]
        local dx, dy = bx - ax, by - ay
        local lengthSquared = dx * dx + dy * dy
        local share = lengthSquared > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / lengthSquared))
            or 0
        local nearX, nearY = ax + dx * share, ay + dy * share
        if (x - nearX) ^ 2 + (y - nearY) ^ 2 <= LINE_REACH * LINE_REACH then
            return true
        end
    end
    return false
end

---What is under a point: the spawn mark nearest it, if it is on one; otherwise every quest whose area holds it.
---@param spots { x: number, y: number, radius: number, questId: number?, note: string?, isFocused: boolean? }[]
---@param areas { points: table[], reach: number, questId: number?, isFocused: boolean? }[]
---@param spotX number The point in the spots' units (spotY too)
---@param spotY number
---@param areaX number The point in the areas' units (areaY too)
---@param areaY number
---@return { questId: number, note: string? }[] quests The focused one first, at most four
function MapHover.findQuests(spots, areas, spotX, spotY, areaX, areaY)
    local nearest, nearestDistance
    for _, spot in ipairs(spots or {}) do
        if spot.questId then
            local distance = math.sqrt((spot.x - spotX) ^ 2 + (spot.y - spotY) ^ 2)
            if distance <= (spot.radius or 4) and (not nearestDistance or distance < nearestDistance) then
                nearest, nearestDistance = spot, distance
            end
        end
    end
    if nearest then
        return { { questId = nearest.questId, note = nearest.note } }
    end
    local quests, isListed = {}, {}
    for _, area in ipairs(areas or {}) do
        local isUnder
        if area.isPatrol then
            isUnder = MapHover.isOnLine(area.segments, spotX, spotY) -- a line is measured on screen, as the spots are
        elseif area.isUnder ~= nil then
            isUnder = area.isUnder -- (the kept drawing's: looked at where it lies, MapMarks.World.findUnder)
        else
            isUnder = ns.MapMarks.isInsideArea(area, areaX, areaY)
        end
        if area.questId and not isListed[area.questId] and isUnder then
            isListed[area.questId] = true
            table.insert(quests, area.isFocused and 1 or #quests + 1, { questId = area.questId, note = area.note })
        end
    end
    while #quests > MAX_QUESTS do
        table.remove(quests)
    end
    return quests
end

---@return string key The same quests give the same key, so the tooltip is only filled again when they change
local function getKey(quests)
    local parts = {}
    for index, quest in ipairs(quests) do
        parts[index] = quest.questId .. (quest.note or "")
    end
    return table.concat(parts, ";")
end

---@return number[] questIds Of the quests listed, those in the log: what a ctrl-click can put in focus
local function getFocusable(quests)
    local questIds = {}
    for _, quest in ipairs(quests) do
        if ns.QuestState.isInLog(quest.questId) then
            questIds[#questIds + 1] = quest.questId
        end
    end
    return questIds
end

---@param isOnMap boolean? The world map's tooltip: it says what a ctrl-click does there
local function fillTooltip(tooltip, quests, isOnMap)
    for index, quest in ipairs(quests) do
        MapHover.addQuestLines(tooltip, quest.questId, quest.note, index == 1)
    end
    local focusable = isOnMap and #getFocusable(quests) or 0
    if focusable > 0 then
        if ns.Gamepad.isGamepadUI() then
            -- (the map's cursor: A opens it in the quest log, held A focuses it; said as on the marks, GamepadMap)
            ns.GamepadMap.addPressLines(tooltip, nil, getFocusable(quests))
        else
            local hint = focusable == 1 and "Alt-click to focus it" or "Alt-click to choose which to focus"
            tooltip:AddLine(ns.L(hint), NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true)
        end
    end
    ns.QuestTooltip.addHint(tooltip)
end

-- Our own tooltip of the quests under the cursor: where it is anchored, kept for filling it again when Shift goes
-- down or up (fields, not a closure made at each showing)
local shown = { owner = nil, anchor = nil, offsetX = nil, offsetY = nil, isOnMap = false }

---The tooltip's place: at the mouse, or with a controller beside the map's own cursor (PAD_ANCHOR), which the mouse's
---anchors know nothing of.
local PAD_ANCHOR = "PAD"
local function placeOwnTooltip()
    if shown.anchor == PAD_ANCHOR then
        GameTooltip:SetOwner(shown.owner, "ANCHOR_NONE")
        GameTooltip:ClearAllPoints()
        GameTooltip:SetPoint("TOPLEFT", _G.SoftCursor, "BOTTOMRIGHT", 6, -2)
    else
        GameTooltip:SetOwner(shown.owner, shown.anchor, shown.offsetX, shown.offsetY)
    end
end

local function fillOwnTooltip(quests)
    placeOwnTooltip()
    fillTooltip(GameTooltip, quests, shown.isOnMap)
    GameTooltip:Show()
end

local function showOwnTooltip(owner, anchor, offsetX, offsetY, quests)
    shown.owner, shown.anchor, shown.offsetX, shown.offsetY = owner, anchor, offsetX, offsetY
    shown.isOnMap = owner ~= Minimap
    fillOwnTooltip(quests)
    ns.QuestTooltip.watch(GameTooltip, owner, fillOwnTooltip, quests)
end

---Our tooltip of the quests under the cursor, for the map or the minimap (its owner): shown, filled again only when
---the quests changed, or taken away once there are none. Someone else's tooltip that is up (the game's own quest
---area's included) is left as it is.
---@param shownKey string? The quests the owner's tooltip shows now (getKey)
---@return string? key The quests it shows after
local function updateOwnTooltip(owner, shownKey, quests, anchor, offsetX, offsetY)
    if #quests == 0 and not shownKey then
        return nil -- nothing under the cursor and no tooltip of ours up (the map closed, most of the time)
    end
    local tooltipOwner = GameTooltip:GetOwner()
    if #quests == 0 then
        if shownKey and tooltipOwner == owner then
            GameTooltip:Hide()
        end
        return nil
    end
    if tooltipOwner and tooltipOwner ~= owner and GameTooltip:IsShown() then
        return shownKey -- someone else's tooltip
    end
    local key = getKey(quests)
    if key == shownKey and tooltipOwner == owner and GameTooltip:IsShown() then
        return shownKey
    end
    showOwnTooltip(owner, anchor, offsetX, offsetY, quests)
    return key
end

---@return table? frame What the cursor is over, as the game finds it
local function getMouseFocus()
    if GetMouseFoci then
        local foci = GetMouseFoci()
        return foci and foci[1]
    end
    return GetMouseFocus and GetMouseFocus() or nil
end

---@return boolean isPin The cursor is over a pin (ours, the game's or another addon's), which has its own tooltip
local function isOverPin(focus)
    if not focus or focus.mark then
        return focus ~= nil
    end
    if not focus.GetSize then
        return false
    end
    local width, height = focus:GetSize()
    return type(width) == "number" and width <= MAX_PIN_SIZE and type(height) == "number" and height <= MAX_PIN_SIZE
end

local isReporting = false -- /omq hover: say what the hover sees, to find out why a tooltip does not show
local lastReport = 0

---@return string text A frame, as a report names it: its name, or its kind and size
local function describeFrame(frame)
    if not frame then
        return "nothing"
    end
    local width, height
    if frame.GetSize then
        width, height = frame:GetSize()
    end
    local name = frame.GetName and frame:GetName() or (frame.GetObjectType and frame:GetObjectType()) or "?"
    return string.format("%s %dx%d%s", tostring(name), width or 0, height or 0, frame.mark and " (our mark)" or "")
end

---@return string text The spot nearest a point and how far it is, against how near counts
local function describeNearest(spots, x, y)
    local nearest, distance
    for _, spot in ipairs(spots or {}) do
        local d = math.sqrt((spot.x - x) ^ 2 + (spot.y - y) ^ 2)
        if not distance or d < distance then
            nearest, distance = spot, d
        end
    end
    if not nearest then
        return "no spawn marks"
    end
    return string.format(
        "nearest spawn %.1f away (counts within %.1f, quest %s)",
        distance,
        nearest.radius or 4,
        tostring(nearest.questId)
    )
end

local function report(text)
    local now = GetTime and GetTime() or 0
    if isReporting and now - lastReport >= 1 then
        lastReport = now
        ns.print(text)
    end
end

---`/omq hover`: the hover report on or off.
function MapHover.toggleReport()
    isReporting = not isReporting
    ns.print(
        isReporting and "hover report on: point at the map or the minimap; /omq hover again to stop."
            or "hover report off."
    )
end

local mapKey -- the quests the world map's tooltip shows now

---The world map's tooltip of the quests under the cursor filled again at the next look (what it says changed: a quest
---put in focus from it).
function MapHover.forgetShownMapQuests()
    mapKey = nil
end
local mapQuests = {} -- the quests under the cursor on the world map, as last looked (an alt-click takes them)
-- The pointer resting where it was, over the same drawing at the same zoom: what is under it is what was found there.
-- Looked at afresh this often all the same (the kept drawing brings spawn marks in under it a little each frame, and
-- other addons' pins come and go). Twenty looks a second each went over every pin on the map otherwise, four
-- questions a pin, for as long as the pointer lay on the map.
local REST_SECONDS = 0.5
local rest = {}
local MOVING_SECONDS = 0.15 -- the zoom changed this recently: the map is moving under the pointer
local isMapClickAdded = false -- (the alt-click's handler joined the map: addMapClick, below)
local addMapClick

---@return boolean isMoving The map is zooming or being dragged: nothing under the pointer is looked for meanwhile.
---It would be found anew at every look (the map moves under the pointer), for a tooltip nobody reads meanwhile.
local function isMapMoving(drawn, map, now)
    if isReporting or not map or not map:IsVisible() then
        return false
    end
    local isZooming = drawn.isFollowPending and now - (drawn.zoomMovedAt or 0) < MOVING_SECONDS
    local isDragging = IsMouseButtonDown ~= nil and IsMouseButtonDown("LeftButton") == true
    return isZooming or isDragging
end

---With a controller the map has a cursor of its own: our marks near it are pointed at as the game's pins are, and
---what is under it is asked about, not under the mouse.
---@return boolean isPad, boolean isPointing, boolean isOnPin The controller's cursor is used; it (or the mouse) is
---on the map's picture; it is on a pin, which shows its own tooltip
local function getMapPointer(map, container)
    local padX, padY
    if ns.GamepadMap then
        padX, padY = ns.GamepadMap.getPointer(map)
        ns.GamepadMap.pointAt(map, padX, padY)
    end
    if padX ~= nil then
        local isPointing = container ~= nil and ns.GamepadMap.isOver(container, padX, padY)
        local isOnPin = ns.GamepadMap.getMark() ~= nil or (map.GetHoveredPin ~= nil and map:GetHoveredPin() ~= nil)
        return true, isPointing, isOnPin
    end
    local isPointing = container ~= nil and container:IsMouseOver()
    return false, isPointing, isPointing and isOverPin(getMouseFocus())
end

---@return boolean isResting The pointer rests where it was last looked at, over the same drawing at the same zoom
local function isPointerResting(map, drawn, x, y, canvasScale, now)
    return not isReporting
        and rest.at ~= nil
        and now - rest.at < REST_SECONDS
        and rest.x == x
        and rest.y == y
        and rest.scale == canvasScale
        and rest.drawId == drawn.drawId
        and rest.map == map
end

---@return boolean isOnTheirPin On another addon's pin (or the game's), that pin is what is pointed at, though it may
---take no mouse (Leatrix Maps' zone arrows and entrances show their own tooltip from the cursor's place)
local function isOnForeignPin(map, cursorX, cursorY)
    for _, rect in ipairs(ns.MapMarks.getForeignPins(map:GetCanvas())) do
        if cursorX >= rect.left and cursorX <= rect.right and cursorY >= rect.top and cursorY <= rect.bottom then
            return true
        end
    end
    return false
end

---@return table[] areas The drawing's areas, and the patrols' trails as lines measured on screen
local function collectHoverAreas(drawn, scale)
    local areas = {}
    for _, area in ipairs(drawn.areas) do
        areas[#areas + 1] = area
    end
    for _, patrol in ipairs(drawn.patrols or {}) do
        local segments = {}
        for index = 2, #patrol.points do
            local from, to = patrol.points[index - 1], patrol.points[index]
            segments[#segments + 1] = { from.x * scale, from.y * scale, to.x * scale, to.y * scale }
        end
        areas[#areas + 1] = { isPatrol = true, segments = segments, questId = patrol.questId, note = patrol.note }
    end
    return areas
end

---The kept drawing's spawn marks and areas under the cursor, beside what this drawing made (the walks, where the
---quest selected to pick up starts): each spawn mark placed from the cursor, in the units the others are in.
---@param areas table[] The areas to hover, which the kept drawing's join
---@return table[] spots The spawn marks to hover
local function addKeptDrawingUnder(map, drawn, x, y, areas)
    local scale = drawn.scale or 1
    local cursorX, cursorY = x * (drawn.width or 1) * scale, y * (drawn.height or 1) * scale
    local spots = drawn.squares
    local keptSpots, keptAreas = ns.MapMarksWorld.findUnder(map, x, y)
    local nowScale = map.GetCanvasScale and map:GetCanvasScale() or scale
    local toDrawn = type(nowScale) == "number" and nowScale > 0 and scale / nowScale or 1
    if #keptSpots > 0 then
        spots = { unpack(drawn.squares) }
        for _, spot in ipairs(keptSpots) do
            spot.x, spot.y = cursorX + spot.x * toDrawn, cursorY + spot.y * toDrawn
            spot.radius = spot.radius * toDrawn
            spots[#spots + 1] = spot
        end
    end
    for _, area in ipairs(keptAreas) do
        areas[#areas + 1] = area
    end
    return spots
end

---@return table[] quests Under a point of the map (its fractions): its spawn marks and quest areas, none on a pin
local function findMapQuestsAt(map, drawn, x, y)
    local width, height, scale = drawn.width or 1, drawn.height or 1, drawn.scale or 1
    local cursorX, cursorY = x * width * scale, y * height * scale
    if isOnForeignPin(map, cursorX, cursorY) then
        if isReporting then
            report("map: the cursor is on another addon's or the game's pin; it shows its own tooltip")
        end
        return {}
    end
    local areas = collectHoverAreas(drawn, scale)
    local spots = drawn.squares
    if ns.MapMarksWorld.isOn() then
        spots = addKeptDrawingUnder(map, drawn, x, y, areas)
    end
    return MapHover.findQuests(spots, areas, cursorX, cursorY, x * width, y * height)
end

---@return table[]? quests Under the pointer on the map's picture (nil where the pointer is off it): what was found
---there while it rests, else looked for again
local function findQuestsUnderPointer(map, drawn, isPad, now)
    local x, y
    if isPad then
        x, y = map:GetNormalizedGamepadCursorPosition()
    else
        x, y = map:GetNormalizedCursorPosition()
    end
    local canvasScale = map.GetCanvasScale and map:GetCanvasScale()
    if isPointerResting(map, drawn, x, y, canvasScale, now) then
        return rest.quests -- (resting: what was found there)
    end
    if not (type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1) then
        return nil
    end
    rest.at, rest.x, rest.y, rest.scale, rest.drawId, rest.map = now, x, y, canvasScale, drawn.drawId, map
    local quests = findMapQuestsAt(map, drawn, x, y)
    rest.quests = quests
    if isReporting then
        local scale = drawn.scale or 1
        report(
            string.format(
                "map: cursor %.3f, %.3f; %d spawn marks, %d areas; %s; found %d; tooltip owner %s",
                x,
                y,
                #drawn.squares,
                #drawn.areas,
                describeNearest(drawn.squares, x * (drawn.width or 1) * scale, y * (drawn.height or 1) * scale),
                #quests,
                describeFrame(GameTooltip:GetOwner())
            )
        )
    end
    return quests
end

---The world map: while the cursor is on the map and not on a pin, the quest areas and spawn marks under it.
function MapHover.updateMap()
    if not isMapClickAdded then
        addMapClick()
    end
    local drawn, markLayer = ns.MapMarks.getDrawn()
    local map = drawn.map
    local now = GetTime and GetTime() or 0
    -- A tooltip of ours that is up while the map moves goes; the next look once the map is still finds what is there
    if isMapMoving(drawn, map, now) then
        if mapKey then
            if GameTooltip:GetOwner() == markLayer then
                GameTooltip:Hide()
            end
            mapKey = nil
        end
        mapQuests, rest.at = {}, nil
        return
    end
    local quests = {}
    mapQuests = quests
    local container = map and map.ScrollContainer
    local isPad, isPointing, isOnPin = getMapPointer(map, container)
    if map and markLayer and map:IsVisible() and container and isPointing and not isOnPin then
        quests = findQuestsUnderPointer(map, drawn, isPad, now) or quests
    elseif isReporting and map and map:IsVisible() and container and container:IsMouseOver() then
        report(
            "map: under the cursor is " .. describeFrame(getMouseFocus()) .. ", taken for a pin with its own tooltip"
        )
    end
    mapQuests = quests
    mapKey = updateOwnTooltip(markLayer, mapKey, quests, isPad and PAD_ANCHOR or "ANCHOR_CURSOR_RIGHT", 5, 2)
end

local lastGameMinimapTooltip = -1 -- when the game's minimap tooltip last ran (GetTime)

---@return table[] quests Under the cursor on the minimap: its spawn marks and quest areas
local function findMinimapQuests()
    if not Minimap or not ns.MinimapPins.getDrawn or not ns.settings.shouldShowMinimapPins then
        return {}
    end
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local centerX, centerY = Minimap:GetCenter()
    if not cursorX or not centerX or not scale or scale <= 0 then
        return {}
    end
    -- Pixels from the minimap's middle, up positive, as the minimap's marks are placed
    local x, y = cursorX / scale - centerX, cursorY / scale - centerY
    local half = Minimap:GetWidth() / 2
    if half <= 0 or ns.MinimapPins.getEdgeDistance(x / half, y / half) > 1 then
        report(
            string.format("minimap: cursor %.1f, %.1f from the middle is past its edge (half width %.1f)", x, y, half)
        )
        return {} -- outside its edge, round or square
    end
    local spots, areas = ns.MinimapPins.getDrawn()
    local quests = MapHover.findQuests(spots, areas, x, y, x, y)
    if isReporting then
        local ago = (GetTime and GetTime() or 0) - (lastGameMinimapTooltip or -1)
        report(
            string.format(
                "minimap: cursor %.1f, %.1f from the middle; %d spawn marks, %d areas; %s; found %d; under the cursor %s; game's minimap tooltip %s",
                x,
                y,
                #spots,
                #areas,
                describeNearest(spots, x, y),
                #quests,
                describeFrame(getMouseFocus()),
                ago < 0.5 and "runs" or "does not run"
            )
        )
    end
    return quests
end

-- The game's own "!" and "?" on the minimap name only the person. Its tooltip's words are kept from addons (secret),
-- so the person is found by place instead: the givers and turn-ins whose "!" or "?" the minimap hands to the game near
-- the player (MinimapPins), within reach of the cursor.
local GAME_MARK_PIXELS = 7 -- how near the cursor a "!" or "?" of the game's stands to be the one hovered
local OFFER_ICON = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t "
local HAND_IN_ICON = "|TInterface\\GossipFrame\\ActiveQuestIcon:0|t "
local OFFER_COLOR = { 1, 0.82, 0 }
local LOW_LEVEL_COLOR = { 0.6, 0.6, 0.6 }

---@return number? x, number? y The cursor in pixels from the minimap's middle, up positive; nil off the minimap
local function getMinimapCursor()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    local centerX, centerY = Minimap:GetCenter()
    if not cursorX or not centerX or not scale or scale <= 0 then
        return nil
    end
    return cursorX / scale - centerX, cursorY / scale - centerY
end

---@return string[] lines What the people under the cursor offer and take, a quest a line, icon first (the game's
---own tooltip names the person, so their name is not said again)
---@return table[] colors Each line's colour
---@return number[] questIds Each line's quest
function MapHover.composeGameMarkLines(marks)
    local lines, colors, questIds = {}, {}, {}
    local function add(icon, line, color, questId)
        lines[#lines + 1] = icon .. line:gsub(" %- .*$", "")
        colors[#colors + 1] = color
        questIds[#questIds + 1] = questId or false
    end
    for _, mark in ipairs(marks) do
        local isOffer, isHandIn = mark.kind == "giver", mark.kind == "turnIn"
        if isOffer or isHandIn then
            local icon = isOffer and OFFER_ICON or HAND_IN_ICON
            local color = isOffer and mark.isLowLevel and LOW_LEVEL_COLOR or OFFER_COLOR
            if mark.questIds and #mark.questIds > 0 then
                -- A line for each quest (a shared mark of the world map names the person first: left out)
                local offset = ns.MapMarks.getQuestLineOffset(mark)
                for index, questId in ipairs(mark.questIds) do
                    if mark.lines[index + offset] then
                        add(icon, mark.lines[index + offset], color, questId)
                    end
                end
            elseif mark.lines and mark.lines[1] then
                add(icon, mark.lines[1], color, mark.questId)
            end
        end
    end
    return lines, colors, questIds
end

---The minimap: added under whatever the game's own minimap tooltip lists, as it lists what is under the cursor.
function MapHover.addMinimapLines(tooltip)
    lastGameMinimapTooltip = GetTime and GetTime() or 0
    -- The people whose "!" or "?" of the game's is under the cursor: what they offer, and what is handed in to them
    local x, y = getMinimapCursor()
    local marks = x and ns.MinimapPins.findGameMarksAt and ns.MinimapPins.findGameMarksAt(x, y, GAME_MARK_PIXELS) or {}
    local lines, colors, questIds = MapHover.composeGameMarkLines(marks)
    if #lines > 0 then
        if not tooltip:IsShown() or not tooltip:GetOwner() then
            tooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        end
        -- Each quest with its level, group mark and experience; what it asks while Shift is held
        for index, line in ipairs(lines) do
            local questId = questIds[index] or nil
            ns.QuestTooltip.addTitle(tooltip, line, questId, colors[index], true)
            ns.QuestTooltip.addDetails(tooltip, questId, { isBrief = true })
        end
    end
    local quests = findMinimapQuests()
    if #quests == 0 then
        if #lines > 0 then
            ns.QuestTooltip.addHint(tooltip)
            tooltip:Show()
        end
        return
    end
    -- With nothing of its own under the cursor the game hides its tooltip, which lets go of the owner: it is set
    -- again, at the cursor as the game sets it, or nothing would show
    if not tooltip:IsShown() or not tooltip:GetOwner() then
        tooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    elseif tooltip:NumLines() > 0 then
        tooltip:AddLine(" ")
    end
    fillTooltip(tooltip, quests)
    tooltip:Show()
end

local minimapKey -- the quests our own minimap tooltip shows now

---The minimap, where the game's own minimap tooltip does not run (another addon took over the minimap's hovering,
---or this client has none): our tooltip at the cursor while the minimap itself, not a button on it, is hovered.
function MapHover.updateMinimap()
    -- (looked at 20 times a second: with the cursor elsewhere and no tooltip of ours up, one question and done)
    local isOver = Minimap ~= nil and Minimap:IsMouseOver() == true and Minimap:IsVisible() == true
    if not isOver and not minimapKey then
        return
    end
    local now = GetTime and GetTime() or 0
    if now - lastGameMinimapTooltip < 0.25 then
        return -- the game's runs, and ours goes under it
    end
    local quests = {}
    local focus = isOver and getMouseFocus() or nil
    if isOver and (focus == Minimap or focus == nil or not isOverPin(focus)) then
        quests = findMinimapQuests()
    elseif isReporting and isOver then
        report("minimap: under the cursor is " .. describeFrame(focus) .. ", taken for a pin with its own tooltip")
    end
    minimapKey = updateOwnTooltip(Minimap, minimapKey, quests, "ANCHOR_CURSOR", nil, nil)
end

local isMinimapHooked = false

-- Peek with Alt (Spoilers): while something is held back, Alt held with the pointer over the world map shows
-- everything there, as Guide does, until Alt is let go (or the map closes). Started by the key (MODIFIER_STATE_CHANGED:
-- a key press, never a frame); while it lasts, the hover's own check (below) looks whether to end it. Each peek counts
-- once, as a hint for every quest it showed (Spoilers.notePeek).
local isPeeking = false

local function endPeek()
    isPeeking = false
    ns.MapMarks.setPeeking(false)
    ns.MapPins.refresh() -- (with the map closed, only noted: drawn as the player chose when it opens)
end

local function startPeek()
    local map = WorldMapFrame
    local container = map and map.ScrollContainer
    if
        isPeeking
        or not ns.Spoilers.isActive()
        or not map
        or not map:IsVisible()
        or type(container) ~= "table"
        or not container.IsMouseOver
        or not container:IsMouseOver()
    then
        return
    end
    isPeeking = true
    ns.MapMarks.setPeeking(true)
    ns.MapPins.refresh()
    ns.Spoilers.notePeek(ns.MapMarks.getDrawnQuestIds())
end

---An Alt key went down or up.
function MapHover.handleModifierChange(key, isDown)
    if type(key) ~= "string" or not key:find("ALT", 1, true) then
        return
    end
    if isDown == 1 or isDown == true then
        startPeek()
    elseif isPeeking and not (IsAltKeyDown and IsAltKeyDown()) then
        endPeek()
    end
end

---The hover's look, 20 times a second: the world map's and the minimap's quests under the cursor.
function MapHover.updateBoth()
    -- (a peek ends once Alt is up or the map gone, should the key's letting go have been missed: one flag otherwise)
    if isPeeking and (not (IsAltKeyDown and IsAltKeyDown()) or not (WorldMapFrame and WorldMapFrame:IsVisible())) then
        endPeek()
    end
    MapHover.updateMap()
    MapHover.updateMinimap()
end

---Puts a quest in focus from the map, as a ctrl-click on its mark does (again on the focused one: let go).
local function focusFromMap(questId)
    local wasFocused = ns.Focus.get() == questId
    ns.Log.focusQuest(questId)
    -- Opened in the quest window beside the map too, on My quests whatever was showing there, as a click on its pin
    -- (not when the click took the focus off: it stays open, no longer shown as focused). Told by what the click
    -- did, not by asking for the focus after it: a quest not tracked until this click is tracked by it, and the
    -- focus does not say so until the game has, a moment later; the quest was focused and not opened.
    if ns.Log.isOpen() and not wasFocused and ns.QuestState.isInLog(questId) then
        ns.Log.selectQuest(questId)
    end
    ns.MapPins.queueRefresh()
end

---Which of several quests whose areas overlap under the cursor to put in focus: the game's menu, at the cursor.
local function openFocusMenu(owner, questIds)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        focusFromMap(questIds[1])
        return
    end
    ns.openMenu(owner, function(_, root)
        ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
        root:CreateTitle(ns.L("Focus"))
        local function isFocused(questId)
            return questId == ns.Focus.get()
        end
        local function choose(questId)
            if not isFocused(questId) then
                focusFromMap(questId)
            end
        end
        for _, questId in ipairs(questIds) do
            local quest = ns.QuestState.getQuest(questId)
            local title = quest and quest.title
                or ns.QuestText.getTitle(questId, ns.Database.getQuestField(questId, "name") or ("Quest " .. questId))
            root:CreateRadio(title, isFocused, choose, questId)
        end
        local focusedId = ns.Focus.get()
        for _, questId in ipairs(questIds) do
            if questId == focusedId then
                root:CreateDivider()
                root:CreateButton(ns.L("Unfocus"), function()
                    focusFromMap(focusedId)
                end)
                break
            end
        end
    end)
end

---A click on the bare map (not on a pin), before the game's own handlers: an Alt-click with a quest of the log
---under the cursor is ours; anything else goes on to the game (a ctrl-click: its waypoint).
local function handleMapClick(map, button)
    if button ~= "LeftButton" or not (IsAltKeyDown and IsAltKeyDown()) or (IsControlKeyDown and IsControlKeyDown()) then
        return false
    end
    return MapHover.focusUnderCursor(map)
end
MapHover.handleMapClick = handleMapClick

---The quest of the log whose area is under the cursor put in focus (or let go of), or with several there a menu to
---choose: the mouse's Alt-click, the controller's A on the map's cursor (GamepadMap).
---@return boolean isDone There was one
function MapHover.focusUnderCursor(map)
    MapHover.updateMap() -- (what is under the cursor now, not a moment ago)
    local questIds = getFocusable(MapHover.getMapQuests())
    if #questIds == 0 then
        return false
    end
    if #questIds == 1 then
        focusFromMap(questIds[1])
    else
        openFocusMenu(map.ScrollContainer or map, questIds)
    end
    return true
end
---@return { questId: number, note: string? }[] quests Under the cursor on the world map, as last looked
function MapHover.getMapQuests()
    return mapQuests
end

-- Before every other handler: map addons take every left click on the bare map for themselves (OpenMap zooms in
-- at 1000, MapUtils at 100; the game's waypoint is 90). Ours takes only an Alt-click on a quest of the log and passes
-- every other click on, so they keep theirs (OpenMap's Alt-clicks are on its own pins, not the map).
local CLICK_PRIORITY = 10000

---The click handler joins the map once the map is there (it may load after the addon: then at the first look).
addMapClick = function()
    if not isMapClickAdded and WorldMapFrame and WorldMapFrame.AddCanvasClickHandler then
        isMapClickAdded = true
        WorldMapFrame:AddCanvasClickHandler(handleMapClick, CLICK_PRIORITY)
    end
end

function MapHover.create()
    addMapClick()
    local frame = CreateFrame("Frame")
    -- (its own frame's event, so the modules' list stays as it is)
    frame:RegisterEvent("MODIFIER_STATE_CHANGED")
    frame:SetScript("OnEvent", function(_, _, key, isDown)
        MapHover.handleModifierChange(key, isDown)
    end)
    local elapsedSeconds = 0
    frame:SetScript("OnUpdate", function(_, elapsed)
        elapsedSeconds = elapsedSeconds + elapsed
        if elapsedSeconds >= CHECK_SECONDS then
            elapsedSeconds = 0
            ns.Timing.measure("hover checks (map, minimap)", MapHover.updateBoth)
        end
    end)
    -- The game rebuilds its minimap tooltip every frame the cursor is on the minimap (Minimap_OnUpdate): ours
    -- goes in after it each time, so the two never fight
    if not isMinimapHooked and type(Minimap_OnUpdate) == "function" and hooksecurefunc then
        isMinimapHooked = true
        hooksecurefunc("Minimap_OnUpdate", function()
            MapHover.addMinimapLines(GameTooltip)
        end)
    end
end

ns.registerModule({ name = "MapHover", create = MapHover.create })
