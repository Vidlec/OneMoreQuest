local _, ns = ...

-- A creature your quests still need shows it on its nameplate: a small icon at the plate's left, a sword for a kill
-- it counts as, a sack for an item it drops, white on a glow in the quest's own colour, as the map's and the
-- minimap's spawn icons are drawn. Worked out from the
-- quests in the log, as its tooltip is (UnitTooltip), and again whenever the log changes.
local Nameplates = {}
ns.Nameplates = Nameplates

local ICON_SIZE = 14
local GLOW_SIZE = 26
Nameplates.ICON_SIZE, Nameplates.GLOW_SIZE = ICON_SIZE, GLOW_SIZE -- for the settings' preview

local wantByNpcId = {} -- [npcId] = { kind, questId } or false: worked out once until the log changes

---@return string? kind "kill" when the creature counts as a kill still wanted, else "loot" when it drops an item
---still wanted; nil when no quest in the log needs it
---@return number? questId The quest that wants it, whose colour its icon glows in
function Nameplates.getKind(npcId)
    if not npcId then
        return nil
    end
    if wantByNpcId[npcId] == nil then
        local want = false
        for _, quest in ipairs(ns.UnitTooltip.compose(npcId)) do
            for _, line in ipairs(quest.lines) do
                -- A kill wins: it is what the player does to the creature either way
                if not line.isDone and (not want or (line.kind == "kill" and want.kind ~= "kill")) then
                    want = { kind = line.kind, questId = quest.questId }
                end
            end
        end
        wantByNpcId[npcId] = want
    end
    local want = wantByNpcId[npcId]
    if not want then
        return nil
    end
    return want.kind, want.questId
end

---@return table? plate The nameplate of a unit, when the game lets addons draw on it (not a friendly plate in a
---dungeon, which the game keeps to itself)
local function getPlate(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or (plate.IsForbidden and plate:IsForbidden()) then
        return nil
    end
    return plate
end

---The icon on a plate, made once per plate (the game reuses its plates for other units).
local function getMark(plate)
    if not plate.oneMoreQuestMark then
        local mark = CreateFrame("Frame", nil, plate)
        mark:SetSize(GLOW_SIZE, GLOW_SIZE)
        mark:SetFrameLevel((plate:GetFrameLevel() or 1) + 10)
        -- Two textures, one under and one over, dressed as a spawn's marker is on the maps (MapMarks.dressSpawnMarker)
        mark.glow = mark:CreateTexture(nil, "ARTWORK", nil, 1)
        mark.glow:SetPoint("CENTER", mark, "CENTER", 0, 0)
        mark.icon = mark:CreateTexture(nil, "OVERLAY", nil, 2)
        mark.icon:SetPoint("CENTER", mark, "CENTER", 0, 0)
        plate.oneMoreQuestMark = mark
    end
    return plate.oneMoreQuestMark
end

local GAP = 3 -- between the icon and what it stands beside
local VISIBLE_HALF = 8 -- half of what shows of the icon: its picture and the strong middle of its glow
local MAX_PART_HEIGHT = 60 -- taller parts of a plate (a selection glow round it all) are not what is drawn on it

---@return table frame What is drawn of a nameplate, which the game scales (nameplate size, the target's larger
---plate): its unit frame, or a nameplate addon's in its place (Plater's), else the plate itself
local function getUnitFrame(plate)
    -- A nameplate addon's frame while it shows (Plater keeps the game's hidden under its own)
    if type(plate.unitFrame) == "table" and plate.unitFrame.IsShown and plate.unitFrame:IsShown() then
        return plate.unitFrame
    end
    -- The game's own, shown or not yet: never the plate itself, which the game forbids measuring
    if type(plate.UnitFrame) == "table" then
        return plate.UnitFrame
    end
    return nil
end

---@return number? left, number? right, number? top, number? bottom A part's edges, or nil where the game will not tell
---(a restricted part of a plate cannot be measured, and asking is an error). In the units of the plate's own frame:
---a part tells its edges in its own, and some are drawn at a scale of their own (the elite and rare ornament is), so
---each is turned into the frame's by how much larger or smaller it is drawn.
---@param frameScale number? The scale the plate's frame is drawn at (its effective scale)
local function measure(region, frameScale)
    local isMeasured, left, right, top, bottom = pcall(function()
        return region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
    end)
    if not isMeasured or not (left and right and top and bottom) then
        return nil
    end
    -- Its scale asked apart: a part that will not tell it (or a kind of part that has none) keeps its edges as told
    local isScaled, scale = pcall(function()
        return region:GetEffectiveScale()
    end)
    local factor = 1
    if isScaled and type(scale) == "number" and scale > 0 and type(frameScale) == "number" and frameScale > 0 then
        factor = scale / frameScale
    end
    return left * factor, right * factor, top * factor, bottom * factor
end

---@return number? left, number? right, number? top The edges of what shows on the plate: its bar, its name, its level
---and anything else drawn on it, in the unit frame's units; nil before the plate is laid out
---@return table bar The health bar, which the icon lines up with
local function getDrawnEdges(unitFrame, mark)
    local bar = unitFrame.healthBar or unitFrame.HealthBarsContainer or unitFrame
    local left, right, top
    local isScaleKnown, frameScale = pcall(unitFrame.GetEffectiveScale, unitFrame)
    frameScale = isScaleKnown and frameScale or nil
    local function include(region)
        if region == mark or not (region.IsShown and region:IsShown()) then
            return
        end
        local regionLeft, regionRight, regionTop, regionBottom = measure(region, frameScale)
        if not (regionLeft and regionRight and regionTop and regionBottom) or regionTop - regionBottom > MAX_PART_HEIGHT then
            return
        end
        left, right = math.min(left or regionLeft, regionLeft), math.max(right or regionRight, regionRight)
        top = math.max(top or regionTop, regionTop)
    end
    include(bar)
    if unitFrame.name then
        include(unitFrame.name)
    end
    for _, child in ipairs({ unitFrame:GetChildren() }) do
        include(child)
    end
    -- The bar's own middle, which the icon is placed from, in the same units
    local barLeft, barRight, barTop, barBottom = measure(bar, frameScale)
    local barX, barY
    if barLeft and barBottom then
        barX, barY = (barLeft + barRight) / 2, (barTop + barBottom) / 2
    end
    return left, right, top, bar, barX, barY
end

---Puts the icon where the player chose, beside what is drawn of the plate and in line with its bar: before it at the
---left, past its level at the right, or over its name; at the size chosen, on top of the game's own nameplate scale.
function Nameplates.place(mark, plate)
    local unitFrame = getUnitFrame(plate)
    if not unitFrame then
        -- No frame of the plate's own to stand on: beside the plate, by anchors alone (nothing measured)
        mark:ClearAllPoints()
        mark:SetPoint("RIGHT", plate, "LEFT", -GAP, 0)
        return
    end
    if mark:GetParent() ~= unitFrame then
        mark:SetParent(unitFrame) -- so it takes the plate's own scale
    end
    mark:SetFrameLevel((unitFrame:GetFrameLevel() or 1) + 10)
    local scale = math.max(0.5, math.min(2, tonumber(ns.settings.nameplateIconScale) or 1))
    mark:SetScale(scale)
    local left, right, top, bar, barX, barY = getDrawnEdges(unitFrame, mark)
    mark:ClearAllPoints()
    if not (left and barX) then
        mark:SetPoint("RIGHT", bar, "LEFT", -GAP, 0) -- not laid out yet: placed again on the next update
        return
    end
    -- In the icon's own units: what is measured on the plate, over the icon's size
    local side = ns.settings.nameplateIconSide
    if side == "right" then
        mark:SetPoint("CENTER", bar, "CENTER", (right - barX + GAP) / scale + VISIBLE_HALF, 0)
    elseif side == "top" then
        mark:SetPoint("CENTER", bar, "CENTER", 0, (top - barY + GAP) / scale + VISIBLE_HALF)
    else
        mark:SetPoint("CENTER", bar, "CENTER", (left - barX - GAP) / scale - VISIBLE_HALF, 0)
    end
end

---Places a plate's icon again on the next frame. A plate just given its unit is laid out by the game in the same
---moment (its bar sized, its level and its elite or rare ornament shown), in an order no addon has a say in: the
---icon is placed at once, by what is there, and once more when everything is.
local function placeLater(mark, plate)
    if mark.isPlacePending or not (C_Timer and C_Timer.After) then
        return
    end
    mark.isPlacePending = true
    C_Timer.After(0, function()
        mark.isPlacePending = false
        if mark:IsShown() and not (plate.IsForbidden and plate:IsForbidden()) then
            Nameplates.place(mark, plate)
        end
    end)
end

---Shows or hides the icon on one unit's plate.
---@param isNewPlate boolean? The plate was just given this unit (NAME_PLATE_UNIT_ADDED)
function Nameplates.update(unit, isNewPlate)
    local plate = getPlate(unit)
    if not plate then
        return
    end
    local kind, questId
    if ns.settings.shouldShowNameplateIcons and UnitGUID and not (UnitIsDead and UnitIsDead(unit)) then
        kind, questId = Nameplates.getKind(ns.UnitTooltip.getNpcId(UnitGUID(unit)))
    end
    if kind then
        local mark = getMark(plate)
        -- The quest's own colour, as its areas and spawn icons have on the map and the minimap
        local color = ns.MapMarks.getQuestColor(ns.QuestState.getWatchNumbers()[questId], questId)
        -- In the kind chosen for the spawn markers, so a creature's plate and its spawn on the map say the same; with
        -- no markers chosen, the glyph on its glow. A square is drawn larger here: it stands alone beside a plate.
        local marker = ns.MapMarks.getSpawnMarker()
        marker = marker == "none" and "glyph" or marker
        local hasUnder = ns.MapMarks.dressSpawnMarker(mark.glow, mark.icon, marker, kind, color, true,
            marker == "square" and ICON_SIZE * 1.6 or ICON_SIZE, GLOW_SIZE)
        mark.glow:SetShown(hasUnder)
        Nameplates.place(mark, plate)
        mark:Show()
        if isNewPlate then
            placeLater(mark, plate)
        end
    elseif plate.oneMoreQuestMark then
        plate.oneMoreQuestMark:Hide()
    end
end

---Every plate on screen again: the log changed, or the setting did.
function Nameplates.refresh()
    wantByNpcId = {}
    for _, plate in ipairs(C_NamePlate and C_NamePlate.GetNamePlates and C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or plate.unitToken or (type(plate.UnitFrame) == "table" and plate.UnitFrame.unit)
        if unit then
            Nameplates.update(unit)
        elseif plate.oneMoreQuestMark then
            plate.oneMoreQuestMark:Hide()
        end
    end
end

local function handleRemoved(unit)
    local plate = getPlate(unit)
    if plate and plate.oneMoreQuestMark then
        plate.oneMoreQuestMark:Hide()
    end
end

ns.registerModule({
    name = "Nameplates",
    events = {
        NAME_PLATE_UNIT_ADDED = function(unit) Nameplates.update(unit, true) end,
        NAME_PLATE_UNIT_REMOVED = handleRemoved,
    },
    -- Once the log has really changed (the game sends QUEST_LOG_UPDATE many times a second, mostly for nothing),
    -- with the rest's redraw: the icons follow
    refresh = Nameplates.refresh,
})
