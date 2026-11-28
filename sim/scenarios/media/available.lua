--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the Available tab: the quests to pick up in the zone, their givers on the map.
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
click("Available")
wait(0.5)
expectText("Select a quest to see how to start it", "the Available tab lists what can be picked up")
click("[33] The Swarm Grows") -- its page: how to start it, its giver marked on the map
wait(0.5)
expectNoText("Select a quest to see how to start it", "the quest's page opened")
saveScene("available", { only = { "WorldMapFrame", "OneMoreQuestLog" } })
