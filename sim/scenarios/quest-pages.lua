--@login race=Scourge,class=WARRIOR,level=30
--@shards 4
-- Every quest's page opens without an error: the quests of several zones are taken, a batch at a time, and each
-- one's page is drawn, in the log. It catches what one quest's odd data breaks (as Elixir of Agony, whose first
-- objective has no place in the database and no source, once did).
setProfile({ level = 30 })
moveTo(1424, 0.62, 0.20)
local addon = require("addons").byName["onemorequest"].private
local game = require("game")
local Q = G.LibQuestieDB.Quest
local ZONES = { 17, 267, 40, 10, 33, 331, 406, 400, 130, 148 } -- Barrens, Hillsbrad, Westfall, Duskwood, Stranglethorn, Ashenvale, Stonetalon, Thousand Needles, Silverpine, Darkshore
local isWanted = {}
for _, zone in ipairs(ZONES) do
    isWanted[zone] = true
end
local questIds = {}
for questId = 1, 9500 do
    local isRead, zone = pcall(Q.Get, questId, "zoneOrSort")
    if isRead and isWanted[zone] and type(Q.Get(questId, "objectives")) == "table" then
        questIds[#questIds + 1] = questId
    end
end
expect(questIds[1] == 515 or #questIds > 100, "many quests to open (" .. #questIds .. ")")
-- (in 4 parts played side by side: each opens every 4th quest)
questIds = forShard(questIds)
key("M")
wait(0.5)
local opened, errorsBefore = 0, #require("sim").errors
-- In batches as large as the log holds: take them, open each page, drop them
local BATCH = 20
for first = 1, #questIds, BATCH do
    local batch = {}
    for index = first, math.min(first + BATCH - 1, #questIds) do
        if game.acceptQuest(questIds[index]) ~= false then
            batch[#batch + 1] = questIds[index]
        end
    end
    wait(0.2)
    for _, questId in ipairs(batch) do
        local isDrawn, problem = pcall(addon.Log.selectQuest, questId)
        if not isDrawn then
            expect(false, "quest " .. questId .. "'s page: " .. tostring(problem))
        else
            opened = opened + 1
        end
    end
    for _, questId in ipairs(batch) do
        game.abandonQuest(questId)
    end
    wait(0.1)
end
expect(#require("sim").errors == errorsBefore, "no Lua errors while drawing the pages")
print("opened " .. opened .. " quest pages")
