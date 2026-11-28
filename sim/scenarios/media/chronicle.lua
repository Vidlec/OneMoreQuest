--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the chronicle: the character's own story of quests done, by chapter. A quest killed
-- for, looted and handed in first, so there is a story to tell.
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1109) -- Going, Going, Guano!
accept(1113) -- Hearts of Zeal
wait(1)
kill(4538) -- a Kraul Bat, which drops the guano
expect(G.C_QuestLog.IsComplete(1109), "the guano is looted")
talk(2055) -- Master Apothecary Faranell
turnIn(1109)
closeDialog()
wait(1)
key("M")
wait(1)
addon.Log.toggleChronicle()
wait(1)
expect(addon.LogState.view == "chronicle", "the chronicle is on the quest window's page")
saveScene("chronicle", { only = { "OneMoreQuestLog" } })
