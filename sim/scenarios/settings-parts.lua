-- "Game's areas" is the game's own markers: the same as the Map marks switch off, which the tile mirrors; and a part
-- of the addon switched off greys out its settings, with the switch at hand on their page.
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({ 185, 186, 187, 188 }) do
    pcall(accept, questId)
end
wait(2)
local addon = require("addons").byName["onemorequest"].private
local mapSection
for index, section in ipairs(addon.SettingsPage.SECTIONS) do
    if section.title == "Map and minimap" then
        mapSection = index
    end
end
addon.Log.openSettings(mapSection)
wait(1)
-- The looks are further down the page: scrolled into view (the wheel over the page, found by a heading on it)
local scene = require("scene")
local pageX, pageY
for _, item in ipairs(scene.export()) do
    if item.k == "s" and item.lines and item.lines[1] == "Marks" and item.cl then
        pageX, pageY = item.cl[1] + item.cl[3] / 2, item.cl[2] + item.cl[4] / 2
    end
end
-- Down the page till a text is well inside it (the page grows as settings are added: no count of steps holds)
local function scrollToShow(text)
    for _ = 1, 40 do
        for _, item in ipairs(scene.export()) do
            if
                item.k == "s"
                and item.lines
                and item.lines[1] == text
                and item.cl
                and item.cl[2] > 200
                and item.cl[2] < 520
            then
                return
            end
        end
        wheel({ pageX, pageY }, -1)
        wait(0.05)
    end
end
scrollToShow("Game's areas")
wait(0.5)
expectText("Game's areas")
click("Game's areas")
wait(1)
expect(addon.settings.shouldShowMapPins == false, "the game's tile switched the map marks off")
expect(addon.settings.shouldHideBuiltInMapPins == false, "and the game's own markers are no longer hidden")
expectText("Map marks: switched off")
expectText("Switch on")
saveScene("settings-map-marks-off")
for _ = 1, 40 do
    wheel({ pageX, pageY }, 1)
end -- (it is at the top of the page)
wait(0.5)
saveScene("settings-map-marks-off-top")
click("Switch on")
wait(1)
expect(addon.settings.shouldShowMapPins == true, "the button on the page switches them back on")
scrollToShow("Game's areas")
wait(0.5)
click("Game's areas")
wait(1)
expect(addon.settings.shouldShowMapPins == false, "off again by the tile")
click("Shapes")
wait(1)
expect(
    addon.settings.shouldShowMapPins == true and addon.settings.areaStyle == "blob",
    "a look of ours switches the marks on"
)
click("Light areas")
wait(1)
expect(addon.settings.areaStyle == "filled", "back to the light areas")
