--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the settings: on the quest window's page beside the map, "At a glance" first (whole
-- parts switched on or off, quick setups).
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1109) -- Going, Going, Guano!
wait(1)
key("M")
wait(1)
expect(addon.Log.openSettings(1), "the settings open on the quest window's page")
wait(0.5)
expectText("At a glance")
saveScene("settings", { only = { "OneMoreQuestLog" } })
