--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the quest log beside the map: quests grouped by where to go next, their marks and
-- areas on the map. (bun run media renders it to site/media/quest-log.png.)
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
saveScene("quest-log", { only = { "WorldMapFrame", "OneMoreQuestLog" } })
