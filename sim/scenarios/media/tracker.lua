--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the tracker: a log full of the Barrens' quests, each tracked, grouped by zone and
-- numbered like their marks on the map, with chain steps, quest items to click and a quest ready to hand in. The map
-- is closed: the tracker as it stands while you play.
local G = require("sim").G

screen(1920, 1080)
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.31) -- The Barrens, by the Crossroads
-- The Barrens' quests for the level (zone 17 in the quest database), each taken and tracked
local quests, taken = G.LibQuestieDB.Quest, 0
for questId = 1, 9999 do
    local isRead, zone = pcall(quests.Get, questId, "zoneOrSort")
    if isRead and zone == 17 and taken < 8 then
        local level = quests.Get(questId, "questLevel") or 0
        if level >= 14 and level <= 22 and pcall(accept, questId) then
            taken = taken + 1
            G.C_QuestLog.AddQuestWatch(questId)
        end
    end
end
expect(taken >= 6, "a log of the Barrens' quests: " .. taken)
wait(2)
expect(G.OneMoreQuestTracker:IsVisible(), "the tracker stands in for the game's")
saveScene("tracker", { only = { "OneMoreQuestTracker" } })
