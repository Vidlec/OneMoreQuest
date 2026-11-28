--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the quest window resized with the map (0.16.0): the grip at its corner dragged down
-- and to the right, the map larger and the window as tall beside it, with more rows and a wider page.
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1109) -- Going, Going, Guano!
accept(1113) -- Hearts of Zeal
wait(1)

key("M")
wait(1)
addon.Log.selectQuest(1113) -- Hearts of Zeal: a long page, which the wider window shows more of
wait(0.5)
local map, MapDock = G.WorldMapFrame, addon.MapDock
local usualHeight = map:GetHeight()
MapDock.startResize(false)
MapDock.resizeTo(260, 160)
MapDock.stopResize()
wait(0.5)
expect(map:GetHeight() - usualHeight > 120, "the map is larger: " .. (map:GetHeight() - usualHeight))
saveScene("resize", { only = { "WorldMapFrame", "OneMoreQuestLog" } })
