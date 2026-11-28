--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the Dungeons tab: every dungeon with quests for the character, by level.
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
click("Dungeons")
wait(0.5)
expectText("Wailing Caverns")
click("Wailing Caverns") -- its page: the way in, what to pick up before going
wait(0.5)
saveScene("dungeons", { only = { "OneMoreQuestLog" } })
