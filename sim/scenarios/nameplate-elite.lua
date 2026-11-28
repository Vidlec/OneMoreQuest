--@login race=Orc,class=WARRIOR,level=37
-- A quest creature's nameplate icon stands before the bar without hiding anything the game draws there: before an
-- elite's ornament, its whole glow clear of it (it used to cover the ornament), and before a plain creature's bar.
-- The client lets no addon measure a nameplate's parts ("can't measure restricted regions"), so the icon is placed
-- by anchors alone: here the plates refuse to be measured while the icons are placed, as they do in the game, and
-- are measured only afterwards, by the scenario, to see where everything stands.
G.SetCVar("nameplateShowEnemies", "1")
setProfile({ level = 37, race = "Orc", class = "WARRIOR" })
local addon = require("addons").byName["onemorequest"].private
local GAP = 3 -- (UI/Nameplates.lua: between the icon's glow and what it stands beside)
local MEASURES = { "GetLeft", "GetRight", "GetTop", "GetBottom", "GetRect", "GetSize", "GetWidth", "GetHeight" }

local function refuseMeasuring(region, isRefused)
    for _, method in ipairs(MEASURES) do
        region[method] = isRefused
                and function()
                    error("Action[FrameMeasurement] failed because[Can't measure restricted regions]", 2)
                end
            or nil
    end
end

---Every part of every plate refuses to be measured (or may be measured again)
local function refuseOnPlates(isRefused)
    for _, plate in ipairs(G.C_NamePlate.GetNamePlates()) do
        local unitFrame = plate.UnitFrame
        for _, region in ipairs({
            unitFrame,
            unitFrame.healthBar,
            unitFrame.HealthBarsContainer,
            unitFrame.ClassificationFrame,
            unitFrame.RaidTargetFrame,
            unitFrame.name,
        }) do
            refuseMeasuring(region, isRefused)
        end
    end
end

---@return table? seen The plate of the creature of that name: our icon's edges, the ornament's and the bar's, in the
---plate frame's units
local function readPlate(name)
    for _, plate in ipairs(G.C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken
        if unit and G.UnitName(unit) == name then
            local unitFrame = plate.UnitFrame
            local frameScale = unitFrame:GetEffectiveScale()
            local function edges(region)
                local factor = region:GetEffectiveScale() / frameScale
                return region:GetLeft() * factor, region:GetRight() * factor
            end
            local mark = plate.oneMoreQuestMark
            local _, markRight = edges(mark)
            return {
                isMarkShown = mark:IsShown(),
                markRight = markRight,
                isOrnamentShown = unitFrame.ClassificationFrame:IsShown(),
                ornamentLeft = edges(unitFrame.ClassificationFrame),
                barLeft = edges(unitFrame.HealthBarsContainer),
            }
        end
    end
    return nil
end

-- An elite a quest wants killed (The Crown of Will asks for Crushridge Maulers), and a plain one (Cutting Teeth's boars)
accept(518)
accept(788)
wait(0.5)
local boarId = G.LibQuestieDB.Quest.Get(788, "objectives")[1][1][1]
local boarName = G.LibQuestieDB.Npc.Get(boarId, "name")
spawn(2254, { distance = 12, bearing = 0 })
spawn(boarId, { distance = 12, bearing = 180 })
wait(0.5)

for _, iconScale in ipairs({ 1, 2 }) do
    refuseOnPlates(true)
    addon.settings.nameplateIconScale = iconScale
    addon.Nameplates.refresh()
    wait(0.5)
    refuseOnPlates(false)
    local elite = readPlate("Crushridge Mauler")
    expect(elite and elite.isMarkShown, "the elite quest creature's plate has our icon (size " .. iconScale .. ")")
    expect(elite and elite.isOrnamentShown, "and the game's elite ornament")
    if elite then
        expect(
            math.abs(elite.markRight - (elite.ornamentLeft - GAP)) < 0.5,
            string.format(
                "size %d: the icon's glow ends %.1f before the ornament (%d wanted), never over it",
                iconScale,
                elite.ornamentLeft - elite.markRight,
                GAP
            )
        )
    end
    local plain = readPlate(boarName)
    expect(plain and plain.isMarkShown, "the plain quest creature's plate has our icon (size " .. iconScale .. ")")
    expect(plain and not plain.isOrnamentShown, "and no ornament")
    if plain then
        expect(
            math.abs(plain.markRight - (plain.barLeft - GAP)) < 0.5,
            string.format(
                "size %d: before a plain bar the icon's glow ends %.1f before it (%d wanted)",
                iconScale,
                plain.barLeft - plain.markRight,
                GAP
            )
        )
    end
end
addon.settings.nameplateIconScale = 1
addon.Nameplates.refresh()
