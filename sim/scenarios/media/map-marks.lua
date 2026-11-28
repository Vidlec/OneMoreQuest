--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the map marks: a log full of the Barrens' quests, each tracked, their givers, turn-ins,
-- spawn marks and areas on the map, beside the quest log.
local G = require("sim").G

screen(1920, 1080)
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.31) -- The Barrens, by the Crossroads
-- The Barrens' quests for the level (zone 17 in the quest database), each taken and tracked
local quests, taken = G.LibQuestieDB.Quest, 0
for questId = 1, 9999 do
    local isRead, zone = pcall(quests.Get, questId, "zoneOrSort")
    if isRead and zone == 17 and taken < 10 then
        local level = quests.Get(questId, "questLevel") or 0
        if level >= 14 and level <= 22 and pcall(accept, questId) then
            taken = taken + 1
            G.C_QuestLog.AddQuestWatch(questId)
        end
    end
end
expect(taken >= 6, "a log of the Barrens' quests: " .. taken)
wait(2)
key("M")
wait(1.5)
expect(G.WorldMapFrame:IsShown(), "the map opens with M")
saveScene("map-marks", { only = { "WorldMapFrame", "OneMoreQuestLog" } })
