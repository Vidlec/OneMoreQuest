-- Soothing Turtle Bisque (Horde, 7321), start to finish: picked up from Christoph Jeffcoat in Tarren Mill,
-- 10 Turtle Meat from Snapjaws, Soothing Spices bought from him, handed back to him.
local QUEST, GIVER, SNAPJAW, MEAT, SPICES = 7321, 2393, 2408, 3712, 3713

local function getObjective(index)
    return (G.C_QuestLog.GetQuestObjectives(QUEST) or {})[index] or {}
end

local function findInTable(target, wanted, seen)
    seen = seen or {}
    if type(target) ~= "table" or seen[target] then return false end
    seen[target] = true
    for key, value in pairs(target) do
        if value == wanted and (key == "questId" or key == "questID") then return true end
        if findInTable(value, wanted, seen) then return true end
    end
    return false
end

setProfile({ level = 31, race = "Scourge", class = "MAGE" })
moveTo(1424, 0.62, 0.20) -- Hillsbrad Foothills, Tarren Mill
wait(1)

-- The giver offers it
talk(GIVER)
local isOffered = false
for _, offer in ipairs(G.C_GossipInfo.GetAvailableQuests()) do isOffered = isOffered or offer.questID == QUEST end
expect(isOffered, "Christoph Jeffcoat offers Soothing Turtle Bisque")
accept(QUEST)
closeDialog()
expect(G.C_QuestLog.IsOnQuest(QUEST), "in the log")
expect(getObjective(1).numRequired == 10, "it asks for 10 Turtle Meat (got " .. tostring(getObjective(1).numRequired) .. ")")
expect(getObjective(2).numRequired == 1, "and one Soothing Spices (got " .. tostring(getObjective(2).numRequired) .. ")")
wait(1) -- the tracker redraws a moment after the quest is accepted, as in the game
expectText("Soothing Turtle Bisque", "the tracker shows it")

-- Its page in OneMoreQuest's log
key("M")
wait(0.5)
click("Soothing Turtle Bisque")
expectText("Turtle Meat", "the page lists the meat")
expectText("Snapjaw", "and who drops it")
key("ESCAPE")

-- The hunt: ten Snapjaws, each looting a piece
for _ = 1, 10 do kill(SNAPJAW) end
expect(getObjective(1).numFulfilled == 10, "10 Turtle Meat (got " .. tostring(getObjective(1).numFulfilled) .. ")")
expect(not G.C_QuestLog.IsComplete(QUEST), "not done without the spices")
slash("/omq kills")

-- The spices, bought
loot(SPICES)
expect(G.C_QuestLog.IsComplete(QUEST), "complete with meat and spices")

-- Handed in
talk(GIVER)
local isReady = false
for _, active in ipairs(G.C_GossipInfo.GetActiveQuests()) do isReady = isReady or (active.questID == QUEST and active.isComplete) end
expect(isReady, "the giver takes it back")
turnIn(QUEST)
closeDialog()
wait(3)
expect(G.C_QuestLog.IsQuestFlaggedCompleted(QUEST), "handed in")
expect(not G.C_QuestLog.IsOnQuest(QUEST), "gone from the log")
expect(findInTable(G.OneMoreQuestDB, QUEST), "OneMoreQuest's chronicle has it")
draw()
