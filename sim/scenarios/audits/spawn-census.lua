--@addons QuestieDB, OneMoreQuest
-- Which quests have the most spawns: every quest in the database, each objective's places as OneMoreQuest gathers
-- them for its marks (Location.getObjectivePlaces: a creature's spawns, an item's droppers' and containers' spawns, an
-- object's), counted with the zones they spread over. The biggest are what the map marks must stay fast for.
-- CENSUS_TOP=<n> quests listed (40).
local TOP = tonumber(os.getenv("CENSUS_TOP") or "40")
local addon = require("addons").byName["onemorequest"].private
local Q = G.LibQuestieDB.Quest
local CREATURES, OBJECTS, ITEMS, KILL_CREDITS = 1, 2, 3, 5

local quests, objectives, started = {}, {}, os.clock()
local buckets = { 100, 500, 1000, 2000, 5000 }
local overBucket = {}
for questId = 1, 99999 do
    local isRead, list = pcall(Q.Get, questId, "objectives")
    if isRead and type(list) == "table" then
        local total, zones, worst = 0, {}, 0
        local function count(kind, index, label)
            local places = addon.Location.getObjectivePlaces(questId, kind, index)
            for _, place in ipairs(places) do
                zones[place.zoneId or 0] = true
            end
            total = total + #places
            worst = math.max(worst, #places)
            objectives[#objectives + 1] = { questId = questId, label = label, count = #places }
        end
        for index, creature in ipairs(list[CREATURES] or {}) do
            count("monster", index, "kill " .. tostring(creature[1]))
        end
        for index, killCredit in ipairs(list[KILL_CREDITS] or {}) do
            count("monster", #(list[CREATURES] or {}) + index, "credit " .. tostring((killCredit[1] or {})[1]))
        end
        for index, object in ipairs(list[OBJECTS] or {}) do
            count("object", index, "object " .. tostring(object[1]))
        end
        for index, item in ipairs(list[ITEMS] or {}) do
            count("item", index, "item " .. tostring(item[1]))
        end
        if total > 0 then
            local zoneCount = 0
            for _ in pairs(zones) do
                zoneCount = zoneCount + 1
            end
            quests[#quests + 1] = {
                questId = questId,
                name = Q.Get(questId, "name") or "?",
                level = Q.Get(questId, "questLevel") or 0,
                total = total,
                worst = worst,
                zones = zoneCount,
            }
            for _, limit in ipairs(buckets) do
                if total > limit then
                    overBucket[limit] = (overBucket[limit] or 0) + 1
                end
            end
        end
    end
end
table.sort(quests, function(a, b)
    return a.total > b.total
end)
print(string.format("CENSUS %d quests with places, %.1f s", #quests, os.clock() - started))
for _, limit in ipairs(buckets) do
    print(string.format("CENSUS   over %5d places: %d quests", limit, overBucket[limit] or 0))
end
for index = 1, math.min(TOP, #quests) do
    local quest = quests[index]
    print(
        string.format(
            "CENSUS %5d places (%5d in one objective, %2d zones)  %5d  L%-2d %s",
            quest.total,
            quest.worst,
            quest.zones,
            quest.questId,
            quest.level,
            quest.name
        )
    )
end
