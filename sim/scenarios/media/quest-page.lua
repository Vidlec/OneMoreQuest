--@addons QuestieDB, OneMoreQuest
-- The product page's picture of a quest's page beside the list: what to do, where, and its chain.
screen(1920, 1080)
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1109) -- Going, Going, Guano!
accept(1113) -- Hearts of Zeal
wait(1)

key("M")
wait(0.5)
expect(G.WorldMapFrame:IsShown(), "the map opens with M")
expect(G.OneMoreQuestLog and G.OneMoreQuestLog:IsShown(), "OneMoreQuest's quest log stands beside it")
expectText("My quests")
local addon = require("addons").byName["onemorequest"].private
addon.Log.selectQuest(1113) -- Hearts of Zeal
wait(0.5)
expectText("To do", "the quest's page opens")
expect(addon.Log.getSelectedQuestId() == 1113, "Hearts of Zeal's page is the one open")
saveScene("quest-page", { only = { "OneMoreQuestLog" } })
