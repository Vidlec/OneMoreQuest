--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the spoiler settings: how much OneMoreQuest tells you, four presets and each kind of
-- spoiler by hand.
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1109) -- Going, Going, Guano!
wait(1)
key("M")
wait(1)
expect(addon.Log.openSettings(2), "the settings open on the quest window's page")
wait(0.5)
expectText("How much to tell")
saveScene("spoilers", { only = { "OneMoreQuestLog" } })
