--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=6
-- The grip at the quest window's corner resizes the map and the quest window together. Dragged down, the map is
-- made larger (its frame's size, as the game sizes it itself: nothing is scaled) and the window stands as tall
-- beside it at its own text size, with more rows; what the grip goes sideways beyond the map's own growing widens
-- the window's page. With Shift, the window is scaled as well, its text too. A right click puts the usual size
-- back. The size is kept with the settings; the full-screen map stays the game's own.
screen(1920, 1080)
setProfile({ level = 6, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68)
local addon = require("addons").byName["onemorequest"].private
accept(788)
wait(2.5)
key("M")
wait(1)
addon.Log.selectQuest(788)
wait(0.5)
local map, window, MapDock = G.WorldMapFrame, addon.Log.getWindow(), addon.MapDock
local grip = MapDock.getResizeGrip()
expect(grip ~= nil and grip:IsVisible(), "the grip stands at the window's corner beside the map")
local function getHeight()
    return window:GetTop() - window:GetBottom()
end
local usualMapWidth, usualMapHeight = map:GetWidth(), map:GetHeight()
local usualWidth, usualHeight = window:GetWidth(), getHeight()
local usualList = addon.Log.getListCanvas().frame:GetHeight()
expect(addon.settings.mapSize == 1 and addon.settings.pageStretch == 0, "the usual size at first")

-- Resized: 200 down and 420 to the right
MapDock.startResize(false)
MapDock.resizeTo(420, 200)
MapDock.stopResize()
wait(0.5)
local mapGrowth, mapRise = map:GetWidth() - usualMapWidth, map:GetHeight() - usualMapHeight
expect(math.abs(mapRise - 200) < 4, "the map is 200 taller: " .. mapRise)
expect(mapGrowth > 250, "and as much wider as its shape asks: " .. mapGrowth)
expect(map:GetScale() == 1 and window:GetScale() == 1, "nothing is scaled: the text stays the size it was")
expect(
    math.abs(getHeight() - usualHeight - mapRise) < 2,
    "the window is as much taller: " .. (getHeight() - usualHeight)
)
expect(addon.Log.getListCanvas().frame:GetHeight() > usualList + 150, "its list has that much more room for rows")
expect(
    math.abs(addon.settings.pageStretch - (420 - mapGrowth)) <= 1,
    "what the grip went beyond the map's growing widens the page: " .. addon.settings.pageStretch
)
expect(math.abs(window:GetWidth() - usualWidth - addon.settings.pageStretch) < 1, "the window as much wider")
local resizedSize = addon.settings.mapSize
expect(resizedSize > 1.2, "kept with the settings: " .. resizedSize)
saveScene("resized")

-- Closed and opened again, and back from the full-screen map: the size is as it was left
key("M")
wait(0.5)
key("M")
wait(1)
expect(math.abs(map:GetWidth() - usualMapWidth - mapGrowth) < 1, "the size stays for the next opening")
map:HandleUserActionMaximizeSelf()
wait(0.5)
expect(addon.settings.mapSize == resizedSize, "the full-screen map is the game's own")
map:HandleUserActionMinimizeSelf()
wait(0.5)
expect(math.abs(map:GetWidth() - usualMapWidth - mapGrowth) < 1, "back in its window, the map has its size again")

-- Scaled, with Shift: the window's own size goes with the map's, text too
MapDock.startResize(true)
MapDock.resizeTo(0, -150)
MapDock.stopResize()
wait(0.5)
expect(addon.settings.mapSize < resizedSize, "dragged up with Shift, the map is smaller")
expect(window:GetScale() < 0.95, "and the window scaled down with it, text too: " .. window:GetScale())
saveScene("scaled")

-- A right click on the grip: the usual size and scale
click(grip, "RightButton")
wait(0.5)
expect(addon.settings.mapSize == 1 and addon.settings.pageStretch == 0, "a right click: the usual size")
expect(addon.settings.windowScale == 1 and window:GetScale() == 1, "and the usual scale, text too")
expect(
    math.abs(map:GetWidth() - usualMapWidth) < 1 and math.abs(map:GetHeight() - usualMapHeight) < 1,
    "the map the game's size"
)
expect(
    window:GetWidth() == usualWidth and math.abs(getHeight() - usualHeight) < 2,
    "the window as wide and tall as usual"
)
