local _, ns = ...

-- The map zoomed out so far that a mark's spot means nothing any more: a zone too small on screen for its marks to say
-- where anything is gets one pill instead, at its middle. The pill names the zone and counts what is there: a coin (the
-- map's own quest mark, the followed quest's when it is there) with how many of your quests have work there, the
-- game's "?" with how many are ready to hand in, and its "!" with how many quests can be picked up. Pointed at, it
-- lists them; clicked, the map turns to the zone, where the marks are back.
local MapMarks = ns.MapMarks

MapMarks.ARE_PILLS_ON = false -- tried and set aside for now: zoomed out, the marks are drawn smaller instead (Draw)
MapMarks.MIN_PILL_MARKS = 3 -- fewer marks in a zone stay as marks: a pill would hide more than it tidies
MapMarks.PILL_ZONE_PIXELS = 220 -- a zone narrower than this on screen is a pill (at 150 a busy zone such as Stranglethorn was still crowded)
local PILL_HEIGHT = 22
local PILL_SIDE = 8 -- room inside the pill's ends
local PILL_GAP = 4 -- between its parts
local COIN_SIZE = 15
local COIN_SCALE = COIN_SIZE / ns.Widgets.MARK_SIZE -- the map's coin, drawn at its own size, scaled down to this
local SIGN_SIZE = 14 -- the "?" and the "!"
local READY_SIGN, GIVER_SIGN = "Interface\\GossipFrame\\ActiveQuestIcon", "Interface\\GossipFrame\\AvailableQuestIcon"
local EDGE, HOT_EDGE, FILL = { 0.56, 0.45, 0.22 }, { 1, 0.82, 0 }, { 0.08, 0.055, 0.03, 0.88 }
local NAME_COLOR, COUNT_COLOR = { 1, 1, 1 }, { 0.96, 0.92, 0.82 }
local CHARACTER_WIDTH = 6.2 -- for laying the pills out before they are drawn; drawn, they take their real width

local getZoneBox

---The box a zone takes on the map being drawn, in its fractions: placed by another addon that joins zones together
---(OpenMap), else by the game.
---@return { left: number, top: number, right: number, bottom: number }? box
function MapMarks.getZoneBox(zoneMapId, mapId)
    return getZoneBox(zoneMapId, mapId)
end

getZoneBox = function(zoneMapId, mapId)
    if zoneMapId == mapId then
        return { left = 0, top = 0, right = 1, bottom = 1 }
    end
    local view = ns.MapPins.getView()
    if view then
        local isFine, left, top = pcall(view.project, zoneMapId, 0, 0, mapId)
        local isFineToo, right, bottom = pcall(view.project, zoneMapId, 1, 1, mapId)
        if isFine and isFineToo and left and top and right and bottom then
            return { left = left, top = top, right = right, bottom = bottom }
        end
    end
    if C_Map and C_Map.GetMapRectOnMap then
        local isFine, left, right, top, bottom = pcall(C_Map.GetMapRectOnMap, zoneMapId, mapId)
        if isFine and type(left) == "number" and type(right) == "number" and right > left then
            return { left = left, top = top, right = right, bottom = bottom }
        end
    end
    return nil
end

---@return number width A pill's width before it is drawn, from its text
local function estimateWidth(pill)
    local width = PILL_SIDE * 2 + #pill.name * CHARACTER_WIDTH
    for _, count in ipairs({ pill.questCount, pill.readyCount, pill.giverCount }) do
        if count > 0 then
            width = width + PILL_GAP + COIN_SIZE + 2 + #tostring(count) * CHARACTER_WIDTH
        end
    end
    return width
end

---The marks of zones too small on screen to show them, each zone's gathered into one pill; the rest as they were.
---@param pixelsAcross number How many pixels the map's whole width takes on screen
---@return MapMark[] marks
function MapMarks.gatherZonePills(marks, mapId, pixelsAcross)
    if not MapMarks.ARE_PILLS_ON or type(pixelsAcross) ~= "number" or pixelsAcross < 2 * MapMarks.PILL_ZONE_PIXELS then
        return marks -- a map not laid out yet, or too small to tell: marks as they are
    end
    local pills, pillByZone, kept, boxes = {}, {}, {}, {}
    for _, mark in ipairs(marks) do
        local areaId = mark.zoneId and ns.Database.getParentZoneId(mark.zoneId) or mark.zoneId
        local zoneMapId = areaId and ns.Database.getUiMapId(areaId)
        local box
        if zoneMapId and mark.kind ~= "dungeon" and not mark.isPreview then
            if boxes[zoneMapId] == nil then
                boxes[zoneMapId] = getZoneBox(zoneMapId, mapId) or false
            end
            box = boxes[zoneMapId] or nil
        end
        if box and (box.right - box.left) * pixelsAcross < MapMarks.PILL_ZONE_PIXELS then
            local pill = pillByZone[areaId]
            if not pill then
                pill = {
                    kind = "zonePill", zoneId = areaId, zoneMapId = zoneMapId, name = ns.Database.getZoneName(areaId) or "?",
                    x = (box.left + box.right) / 2, y = (box.top + box.bottom) / 2,
                    questIds = {}, readyIds = {}, giverIds = {}, questCount = 0, readyCount = 0, giverCount = 0,
                    lines = {}, isFocused = false,
                }
                pillByZone[areaId] = pill
                pills[#pills + 1] = pill
            end
            pill.marks = pill.marks or {}
            pill.marks[#pill.marks + 1] = mark -- kept as they are when too few for a pill
            local questId = mark.questId
            if mark.kind == "giver" and questId and not pill.giverIds[questId] then
                pill.giverIds[questId], pill.giverCount = true, pill.giverCount + 1
            elseif mark.kind == "turnIn" and not mark.isPending and questId and not pill.readyIds[questId] then
                pill.readyIds[questId], pill.readyCount = true, pill.readyCount + 1
            elseif mark.kind == "objective" and questId and not pill.questIds[questId] then
                pill.questIds[questId], pill.questCount = true, pill.questCount + 1
            end
            -- (a grey "?", where a quest not yet done will be handed in, is no work there: not counted)
            -- The followed quest's coin stands for the zone's quests, and its pill is edged in gold
            if mark.isFocused and mark.kind ~= "giver" then
                pill.isFocused = true
                pill.glyph, pill.progress, pill.focusedQuestId = mark.glyph, mark.progress, questId
            elseif not pill.glyph and mark.kind == "objective" then
                pill.glyph, pill.progress = mark.glyph, mark.progress
            end
        else
            kept[#kept + 1] = mark
        end
    end
    for _, pill in ipairs(pills) do
        -- A pill only where it tidies something up: a zone with a mark or two keeps them, as they say more
        if #pill.marks >= MapMarks.MIN_PILL_MARKS and pill.questCount + pill.readyCount + pill.giverCount > 0 then
            pill.pillWidth = estimateWidth(pill)
            table.insert(kept, 1, pill) -- under the marks still shown, which are nearer and say more
        else
            for _, mark in ipairs(pill.marks) do
                kept[#kept + 1] = mark
            end
        end
    end
    return kept
end

-- A dungeon's entrance as the map draws it (the game's, or OpenMap's, with its level range under it), in screen
-- pixels round the entrance's spot: what a pill keeps clear of
local ENTRANCE_HALF_WIDTH, ENTRANCE_ABOVE, ENTRANCE_BELOW = 24, 14, 30

---Where the dungeon entrances lie on the map being drawn, each as the room its icon and level label take, for the
---pills to keep clear of; the quest marks keep their exact spots and do not.
---@param pixelsAcross number, pixelsDown number The map's whole width and height on screen
---@return { left: number, top: number, right: number, bottom: number }[] rects In the same units as the marks' places
function MapMarks.getEntranceRects(mapId, pixelsAcross, pixelsDown)
    local rects = {}
    for _, dungeon in ipairs(ns.Database.getDungeons()) do
        for _, entrance in ipairs(dungeon.entrances or {}) do
            local place = { zoneId = entrance.zoneId, x = entrance.x, y = entrance.y }
            local x, y = ns.MapPins.getMapPosition(place, mapId)
            if x then
                local left, top = x * pixelsAcross, y * pixelsDown
                rects[#rects + 1] = { left = left - ENTRANCE_HALF_WIDTH, right = left + ENTRANCE_HALF_WIDTH,
                    top = top - ENTRANCE_ABOVE, bottom = top + ENTRANCE_BELOW }
            end
        end
    end
    return rects
end

---@return number width, number height A pill's room on the map, for laying marks out
function MapMarks.getPillFootprint(mark)
    return mark.pillWidth or 80, PILL_HEIGHT
end

local function getQuestTitle(questId)
    return ns.QuestText.getQuestName(questId) or ("Quest " .. questId)
end

local function showPillTooltip(pill)
    local mark = pill.mark
    if not mark then
        return
    end
    GameTooltip:SetOwner(pill, "ANCHOR_RIGHT")
    GameTooltip:SetText(mark.name, 1, 0.82, 0)
    local function addQuests(ids, prefix, color)
        local titles = {}
        for questId in pairs(ids) do
            titles[#titles + 1] = getQuestTitle(questId)
        end
        table.sort(titles)
        for _, title in ipairs(titles) do
            GameTooltip:AddLine(prefix .. title, color[1], color[2], color[3])
        end
    end
    addQuests(mark.readyIds, "|T" .. READY_SIGN .. ":0|t ", { 1, 0.82, 0 })
    addQuests(mark.questIds, "", { 1, 1, 1 })
    if mark.giverCount > 0 then
        GameTooltip:AddLine(ns.Lp(mark.giverCount, "%d quest to pick up", "%d quests to pick up"), 0.85, 0.81, 0.66)
    end
    GameTooltip:AddLine(ns.L("Click to show the zone"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function handlePillClick(pill)
    local mark = pill.mark
    if mark and mark.zoneMapId and WorldMapFrame and WorldMapFrame.SetMapID then
        WorldMapFrame:SetMapID(mark.zoneMapId)
    end
end

---A count after its sign: the sign's picture and the number.
local function createCount(pill)
    local count = { icon = pill:CreateTexture(nil, "OVERLAY"), text = ns.Widgets.createFontString(pill, "OVERLAY", "GameFontHighlightSmall") }
    count.icon:SetSize(SIGN_SIZE, SIGN_SIZE)
    return count
end

---@return table pill A pill's frame, its parts made once and reused
function MapMarks.createPill(parent)
    local pill = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    pill:SetHeight(PILL_HEIGHT)
    if pill.SetBackdrop then
        pill:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
    end
    pill.name = ns.Widgets.createFontString(pill, "OVERLAY", "GameFontNormalSmall")
    pill.coin = MapMarks.createMarkButton(pill)
    pill.coin:EnableMouse(false)
    pill.coin:SetScale(COIN_SCALE)
    pill.questCount = ns.Widgets.createFontString(pill, "OVERLAY", "GameFontHighlightSmall")
    pill.ready, pill.givers = createCount(pill), createCount(pill)
    pill.ready.icon:SetTexture(READY_SIGN)
    pill.givers.icon:SetTexture(GIVER_SIGN)
    pill:SetScript("OnEnter", showPillTooltip)
    pill:SetScript("OnLeave", function() GameTooltip:Hide() end)
    pill:SetScript("OnClick", handlePillClick)
    return pill
end

---Dresses a pill for a zone: its name, then the coin with your quests there, the "?" and the "!" with theirs.
---@return number width, number height As drawn
function MapMarks.applyPillLook(pill, mark, frameLevel)
    pill.mark = mark
    if frameLevel then
        pill:SetFrameLevel(frameLevel)
    end
    if pill.SetBackdropColor then
        pill:SetBackdropColor(FILL[1], FILL[2], FILL[3], FILL[4])
        local edge = mark.isFocused and HOT_EDGE or EDGE
        pill:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
    end
    local x = PILL_SIDE
    local function place(region, width)
        region:ClearAllPoints()
        region:SetPoint("LEFT", pill, "LEFT", x, 0)
        region:Show()
        x = x + width
    end
    local function textWidth(fontString)
        local width = fontString:GetStringWidth()
        return type(width) == "number" and width or (#(fontString:GetText() or "") * CHARACTER_WIDTH)
    end
    pill.name:SetText(mark.name)
    pill.name:SetTextColor(NAME_COLOR[1], NAME_COLOR[2], NAME_COLOR[3])
    place(pill.name, textWidth(pill.name))
    -- Your quests: the map's coin, as on the map, then how many
    pill.coin:Hide()
    pill.questCount:Hide()
    if mark.questCount > 0 then
        x = x + PILL_GAP
        MapMarks.applyMarkLook(pill.coin, {
            kind = "objective", questId = mark.focusedQuestId, glyph = mark.glyph or "use", progress = mark.progress or 0,
            isFocused = false, lines = {},
        }, (pill:GetFrameLevel() or 1) + 1)
        -- The coin is scaled down: its offsets are in its own units
        pill.coin:ClearAllPoints()
        pill.coin:SetPoint("CENTER", pill, "LEFT", (x + COIN_SIZE / 2) / COIN_SCALE, 0)
        pill.coin:Show()
        x = x + COIN_SIZE + 2
        pill.questCount:SetText(mark.questCount)
        pill.questCount:SetTextColor(COUNT_COLOR[1], COUNT_COLOR[2], COUNT_COLOR[3])
        place(pill.questCount, textWidth(pill.questCount))
    end
    for _, part in ipairs({ { count = pill.ready, value = mark.readyCount }, { count = pill.givers, value = mark.giverCount } }) do
        part.count.icon:Hide()
        part.count.text:Hide()
        if part.value > 0 then
            x = x + PILL_GAP
            place(part.count.icon, SIGN_SIZE)
            part.count.text:SetText(part.value)
            part.count.text:SetTextColor(COUNT_COLOR[1], COUNT_COLOR[2], COUNT_COLOR[3])
            place(part.count.text, textWidth(part.count.text))
        end
    end
    local width = x + PILL_SIDE
    pill:SetWidth(width)
    return width, PILL_HEIGHT
end

MapMarks.PILL_HEIGHT = PILL_HEIGHT
