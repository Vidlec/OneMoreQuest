local _, ns = ...

-- Hovering a quest's area or one of its spawn marks, on the world map or the minimap, shows the quest's tooltip
-- as the game shows it for its own quest areas: the title, what kind of quest it is, then each objective still to
-- do, an item's with the creatures that drop it and their chances. A spawn mark adds what is there (the creature
-- that drops the item, and its chance). Where areas overlap,
-- each quest under the cursor is listed, the one in focus first.
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
    local title = quest and quest.title or ns.QuestText.getTitle(questId, ns.Database.getQuestField(questId, "name") or ("Quest " .. questId))
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
---each with its drop chance.
function MapHover.addDropLines(tooltip, questId, typeIndex)
    local target = ns.Location.getObjectiveTarget(questId, "item", typeIndex)
    local zone = target and target.itemId and ns.Drops.getZones(target.itemId)[1]
    local sources = zone and zone.sources or {}
    for index, source in ipairs(sources) do
        if index > MAX_SOURCES then
            tooltip:AddLine(ns.Lp(#sources - MAX_SOURCES, "   + %d more", "   + %d more"), NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3])
            break
        end
        if source.chance then
            tooltip:AddDoubleLine("   " .. source.name, ns.Drops.formatChance(source.chance), NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3],
                CHANCE_COLOR[1], CHANCE_COLOR[2], CHANCE_COLOR[3])
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
        local share = lengthSquared > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / lengthSquared)) or 0
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

local function fillTooltip(tooltip, quests)
    for index, quest in ipairs(quests) do
        MapHover.addQuestLines(tooltip, quest.questId, quest.note, index == 1)
    end
    ns.QuestTooltip.addHint(tooltip)
end

-- Our own tooltip of the quests under the cursor: where it is anchored, kept for filling it again when Shift goes
-- down or up (fields, not a closure made at each showing)
local shown = { owner = nil, anchor = nil, offsetX = nil, offsetY = nil }

local function fillOwnTooltip(quests)
    GameTooltip:SetOwner(shown.owner, shown.anchor, shown.offsetX, shown.offsetY)
    fillTooltip(GameTooltip, quests)
    GameTooltip:Show()
end

local function showOwnTooltip(owner, anchor, offsetX, offsetY, quests)
    shown.owner, shown.anchor, shown.offsetX, shown.offsetY = owner, anchor, offsetX, offsetY
    fillOwnTooltip(quests)
    ns.QuestTooltip.watch(GameTooltip, owner, fillOwnTooltip, quests)
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
    return string.format("nearest spawn %.1f away (counts within %.1f, quest %s)", distance, nearest.radius or 4, tostring(nearest.questId))
end

local function report(text)
    local now = GetTime and GetTime() or 0
    if isReporting and now - lastReport >= 1 then
        lastReport = now
        ns.print(text)
    end
end

function MapHover.toggleReport()
    isReporting = not isReporting
    ns.print(isReporting and "hover report on: point at the map or the minimap; /omq hover again to stop."
        or "hover report off.")
end

local mapKey -- the quests the world map's tooltip shows now

---The world map: while the cursor is on the map and not on a pin, the quest areas and spawn marks under it.
function MapHover.updateMap()
    local drawn, markLayer = ns.MapMarks.getDrawn()
    local map = drawn.map
    local quests = {}
    local container = map and map.ScrollContainer
    if map and markLayer and map:IsVisible() and container and container:IsMouseOver() and not isOverPin(getMouseFocus()) then
        local x, y = map:GetNormalizedCursorPosition()
        if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
            local width, height, scale = drawn.width or 1, drawn.height or 1, drawn.scale or 1
            -- On another addon's pin (or the game's), that pin is what is pointed at, though it may take no mouse
            -- (Leatrix Maps' zone arrows and entrances show their own tooltip from the cursor's place)
            local isOnTheirPin = false
            local cursorX, cursorY = x * width * scale, y * height * scale
            for _, rect in ipairs(ns.MapMarks.getForeignPins(map:GetCanvas())) do
                if cursorX >= rect.left and cursorX <= rect.right and cursorY >= rect.top and cursorY <= rect.bottom then
                    isOnTheirPin = true
                    break
                end
            end
            if not isOnTheirPin then
                -- The areas, and the patrols' trails as lines measured on screen
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
                quests = MapHover.findQuests(drawn.squares, areas, cursorX, cursorY, x * width, y * height)
            elseif isReporting then
                report("map: the cursor is on another addon's or the game's pin; it shows its own tooltip")
            end
            if isReporting then
                report(string.format("map: cursor %.3f, %.3f; %d spawn marks, %d areas; %s; found %d; tooltip owner %s",
                    x, y, #drawn.squares, #drawn.areas, describeNearest(drawn.squares, x * width * scale, y * height * scale), #quests,
                    describeFrame(GameTooltip:GetOwner())))
            end
        end
    elseif isReporting and map and map:IsVisible() and container and container:IsMouseOver() then
        report("map: under the cursor is " .. describeFrame(getMouseFocus()) .. ", taken for a pin with its own tooltip")
    end
    if #quests == 0 and not mapKey then
        return -- nothing under the cursor and no tooltip of ours up (the map closed, most of the time): nothing to do
    end
    local owner = GameTooltip:GetOwner()
    if #quests == 0 then
        if mapKey and owner == markLayer then
            GameTooltip:Hide()
        end
        mapKey = nil
        return
    end
    if owner and owner ~= markLayer and GameTooltip:IsShown() then
        return -- someone else's tooltip, the game's own quest area included
    end
    local key = getKey(quests)
    if key == mapKey and owner == markLayer and GameTooltip:IsShown() then
        return
    end
    mapKey = key
    showOwnTooltip(markLayer, "ANCHOR_CURSOR_RIGHT", 5, 2, quests)
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
        report(string.format("minimap: cursor %.1f, %.1f from the middle is past its edge (half width %.1f)", x, y, half))
        return {} -- outside its edge, round or square
    end
    local spots, areas = ns.MinimapPins.getDrawn()
    local quests = MapHover.findQuests(spots, areas, x, y, x, y)
    if isReporting then
        local ago = (GetTime and GetTime() or 0) - (lastGameMinimapTooltip or -1)
        report(string.format("minimap: cursor %.1f, %.1f from the middle; %d spawn marks, %d areas; %s; found %d; under the cursor %s; game's minimap tooltip %s",
            x, y, #spots, #areas, describeNearest(spots, x, y), #quests, describeFrame(getMouseFocus()),
            ago < 0.5 and "runs" or "does not run"))
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
    local owner = GameTooltip:GetOwner()
    if #quests == 0 then
        if minimapKey and owner == Minimap then
            GameTooltip:Hide()
        end
        minimapKey = nil
        return
    end
    if owner and owner ~= Minimap and GameTooltip:IsShown() then
        return
    end
    local key = getKey(quests)
    if key == minimapKey and owner == Minimap and GameTooltip:IsShown() then
        return
    end
    minimapKey = key
    showOwnTooltip(Minimap, "ANCHOR_CURSOR", nil, nil, quests)
end

local isMinimapHooked = false

function MapHover.updateBoth()
    MapHover.updateMap()
    MapHover.updateMinimap()
end

function MapHover.create()
    local frame = CreateFrame("Frame")
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
