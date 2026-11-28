--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the quest areas drawn as Shadows (0.16.0): a soft tinted shadow where each quest's
-- spawns are, no rings and no lines, on the map beside the quest log.
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1109) -- Going, Going, Guano!
accept(1113) -- Hearts of Zeal
wait(1)
addon.settings.areaGeometry = "soft"
addon.SettingsPage.apply()
wait(1)

key("M")
wait(1.5)
expect(G.WorldMapFrame:IsShown(), "the map opens with M")
expect(addon.MapMarks.isShadowsOnly(), "the areas are drawn as Shadows")
saveScene("quest-areas-shadows", { only = { "WorldMapFrame", "OneMoreQuestLog" } })
