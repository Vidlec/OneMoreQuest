--@addons QuestieDB
-- Writes GatheringNodes.lua: the object ids of the herbs and the ores QuestieDB knows, the places the game's Find
-- Herbs and Find Minerals can show (MinimapPins keeps its marks off them). A scenario of its own, outside the suite
-- (sim/tools is not the scenarios folder); run it from the WowAddons folder:
--   bun addonsim test sim/tools/gathering-nodes.lua        (the simulator's runner, with this project)
-- It needs QuestieDB installed in the game's AddOns folder, and writes addons/OneMoreQuest/GatheringNodes.lua.
-- Herbs: objects named as a herb item is (Trade Goods, Herb). Ores: objects named "... Vein", "... Deposit" or
-- "... Chunk" (the miner's nodes). Left out: objects a quest asks for by name (its object objectives), which are
-- that quest's own things, not nodes.
local game = require("game")
local Object, Quest = G.LibQuestieDB.Object, G.LibQuestieDB.Quest

local herbNames = {}
for _, item in pairs(game.items) do
    if item.classId == 7 and item.subclassId == 9 and item.name then
        herbNames[item.name] = true
    end
end

local questObjects = {}
for _, questId in ipairs(Quest.GetAllIds()) do
    local isRead, objectives = pcall(Quest.Get, questId, "objectives")
    for _, objective in ipairs(isRead and type(objectives) == "table" and objectives[2] or {}) do
        if type(objective) == "table" and objective[1] then
            questObjects[objective[1]] = true
        end
    end
end

local herbs, ores, counts = {}, {}, { herb = 0, ore = 0, left = 0 }
for _, id in ipairs(Object.GetAllIds()) do
    local name = Object.Get(id, "name")
    if type(name) == "string" then
        local isHerb = herbNames[name] == true
        local isOre = name:find(" Vein$") or name:find(" Deposit$") or name:find(" Chunk$")
        if (isHerb or isOre) and questObjects[id] then
            counts.left = counts.left + 1
            print("left out (a quest's own object): " .. id .. " " .. name)
        elseif isHerb then
            herbs[#herbs + 1] = id
        elseif isOre then
            ores[#ores + 1] = id
        end
    end
end
table.sort(herbs)
table.sort(ores)

local function list(ids)
    local lines, line = {}, {}
    for _, id in ipairs(ids) do
        line[#line + 1] = tostring(id)
        if #line == 16 then
            lines[#lines + 1] = "        " .. table.concat(line, ", ") .. ","
            line = {}
        end
    end
    if #line > 0 then
        lines[#lines + 1] = "        " .. table.concat(line, ", ") .. ","
    end
    return table.concat(lines, "\r\n")
end
local path = projectRoot .. "/addons/OneMoreQuest/GatheringNodes.lua"
local out = assert(io.open(path, "wb"))
out:write(table.concat({
    "local _, ns = ...",
    "",
    "-- The herbs and ores of the world, by their object ids in QuestieDB: where the game's Find Herbs and Find",
    "-- Minerals can show a node on the minimap. Made by tools/gathering-nodes.lua (run it again when the database",
    "-- grows); MinimapPins keeps its marks off these places while that tracking is on.",
    "ns.GatheringNodes = {",
    "    herb = {",
    list(herbs),
    "    },",
    "    ore = {",
    list(ores),
    "    },",
    "}",
    "",
}, "\r\n"))
out:close()
print(string.format("GatheringNodes.lua: %d herbs, %d ores, %d left out", #herbs, #ores, counts.left))
expect(#herbs > 20 and #ores > 20, "herbs and ores found")
