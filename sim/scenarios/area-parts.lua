-- The areas' fill and outline, each switched on or off and set in strength, on the map and the minimap: what is
-- off has no textures at all (fewer items), a strength changed only recolours (the same count).
G.GetMinimapShape = function()
    return "SQUARE"
end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29) -- Grom'gol Base Camp, Stranglethorn
for _, questId in ipairs({ 185, 186, 190, 194, 568 }) do
    pcall(accept, questId)
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local scene = require("scene")
addon.Focus.set(185)
key("M")
wait(2)

-- { name, fill on, outline on, fill strength, outline strength }
local PARTS = {
    { "both", true, true, 1, 1 },
    { "outline-only", false, true, 1, 1 },
    { "fill-only", true, false, 1, 1 },
    { "soft-fill-strong-edge", true, true, 0.4, 2 },
    { "neither", false, false, 1, 1 },
}
local function apply(part)
    local settings = addon.settings
    settings.areaStyle, settings.spawnMarker = "blob", "glyph"
    settings.shouldFillAreas, settings.shouldOutlineAreas, settings.areaFillStrength, settings.areaOutlineStrength =
        part[2], part[3], part[4], part[5]
    addon.SettingsPage.apply()
    wait(1.5)
end
for _, part in ipairs(PARTS) do
    apply(part)
    io.write(
        string.format(
            "PARTS %-22s items %5d  hasAreas %s\n",
            part[1],
            #scene.export(),
            tostring(addon.MapMarks.hasAreas())
        )
    )
    saveScene(part[1])
end
key("M")
wait(1)
moveTo(1434, 0.36, 0.115)
wait(2) -- among the tigers, north of Grom'gol
for _, part in ipairs(PARTS) do
    apply(part)
    io.write(string.format("PARTS mini-%-17s items %5d\n", part[1], #scene.export()))
    saveScene("mini-" .. part[1])
end
apply(PARTS[1])
