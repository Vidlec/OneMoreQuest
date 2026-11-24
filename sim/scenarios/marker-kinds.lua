-- The quests' places in every look: the areas (a light wash, the bold shapes, none) and the spawn markers (a glyph on
-- a glow, on a plate, the game's own art, a square, none), each chosen on its own, on the map and the minimap alike.
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

---What the map and the minimap draw their spawn markers and areas from, counted: by texture, atlas and plain colour.
local function count()
    local found = { glyphs = 0, plates = 0, glows = 0, atlases = 0, items = 0 }
    for _, item in ipairs(scene.export()) do
        found.items = found.items + 1
        local texture = tostring(item.t or item.texture or "")
        if texture:find("Media.Icon") then
            found.glyphs = found.glyphs + 1
        end
        if texture:find("Plate", 1, true) then
            found.plates = found.plates + 1
        end
        if texture:find("SoftDot", 1, true) then
            found.glows = found.glows + 1
        end
        local atlas = tostring(item.a or item.atlas or ""):lower()
        if atlas == "dungeonskull" or atlas == "vignetteloot" or atlas == "vignetteevent" then
            found.atlases = found.atlases + 1
        end
    end
    return found
end

local LOOKS = {
    { "filled", "glyph" },
    { "blob", "glyph" },
    { "blob", "plate" },
    { "filled", "game" },
    { "blob", "square" },
    { "none", "plate" },
    { "blob", "none" },
    { "none", "none" },
}
for _, look in ipairs(LOOKS) do
    addon.settings.areaStyle, addon.settings.spawnMarker = look[1], look[2]
    addon.SettingsPage.apply()
    wait(1.5)
    local name = look[1] .. "-" .. look[2]
    local found = count()
    io.write(
        string.format(
            "LOOK %-14s items %5d  glyphs %3d  plates %3d  glows %3d  game art %3d\n",
            name,
            found.items,
            found.glyphs,
            found.plates,
            found.glows,
            found.atlases
        )
    )
    saveScene(name)
end
-- The minimap alone, the map closed: the same looks, as on the map
key("M")
wait(1)
moveTo(1434, 0.36, 0.115)
wait(2) -- among the tigers, north of Grom'gol
for _, look in ipairs(LOOKS) do
    addon.settings.areaStyle, addon.settings.spawnMarker = look[1], look[2]
    addon.SettingsPage.apply()
    wait(1.5)
    saveScene("mini-" .. look[1] .. "-" .. look[2])
end
key("M")
wait(1.5)
-- The other quests' markers hidden, and the glow off: fewer markers, no glows under the glyphs
addon.settings.areaStyle, addon.settings.spawnMarker = "filled", "glyph"
addon.settings.otherSpawnMarkers, addon.settings.shouldGlowSpawnMarkers = "hidden", false
addon.SettingsPage.apply()
wait(1.5)
local found = count()
io.write(
    string.format(
        "LOOK %-14s items %5d  glyphs %3d  plates %3d  glows %3d  game art %3d\n",
        "focus-no-glow",
        found.items,
        found.glyphs,
        found.plates,
        found.glows,
        found.atlases
    )
)
saveScene("focus-no-glow")
addon.settings.otherSpawnMarkers, addon.settings.shouldGlowSpawnMarkers = "faded", true
-- The settings page, with the two pickers
local mapSection
for index, section in ipairs(addon.SettingsPage.SECTIONS) do
    if section.title == "Map and minimap" then
        mapSection = index
    end
end
addon.settings.areaStyle, addon.settings.spawnMarker = "blob", "plate"
addon.Log.openSettings(mapSection)
wait(1)
local pageX, pageY
for _, item in ipairs(scene.export()) do
    if item.k == "s" and item.lines and item.lines[1] == "Marks" and item.cl then
        pageX, pageY = item.cl[1] + item.cl[3] / 2, item.cl[2] + item.cl[4] / 2
    end
end
for _ = 1, 6 do
    wheel({ pageX, pageY }, -1)
end
wait(0.5)
expectText("Spawn markers")
expectText("Plates")
saveScene("settings-pickers")
for _ = 1, 6 do
    wheel({ pageX, pageY }, -1)
end
wait(0.5)
saveScene("settings-pickers-lower")
