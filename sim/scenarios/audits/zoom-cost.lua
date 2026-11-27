--@login race=Troll,class=HUNTER,level=38
--@addons QuestieDB, OneMoreQuest, OpenMap
-- What a wheel step on the world map costs OneMoreQuest, with many quests' areas and spawns drawn (Stranglethorn
-- Vale, the quests of a report of lag on zooming): per step, the widget calls its code makes (by method), the time
-- in following the zoom and in full redraws, and how many full redraws the step brought.
-- bun run test:sim sim/scenarios/audits/zoom-cost.lua
setProfile({ level = 38 })
moveTo(1434, 0.32, 0.29) -- Grom'gol
for _, questId in ipairs({ 189, 605, 213, 190, 570, 194, 598, 201 }) do
    accept(questId)
end
wait(2)
key("M")
wait(3)

local W, sim, scene = require("widgets"), require("sim"), require("scene")
local addon = require("addons").byName["onemorequest"].private
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local getinfo = debug.getinfo
local clock = sim.clock

local counting, calls = false, {}
for _, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if counting then
                    local info = getinfo(2, "S")
                    if info and info.source:sub(1, #PREFIX) == PREFIX then
                        calls[name] = (calls[name] or 0) + 1
                    end
                end
                return method(...)
            end
        end
    end
end
local timed = {}
local function timeFunction(owner, key, label)
    local original = owner[key]
    owner[key] = function(...)
        local started = clock()
        local results = { original(...) }
        local entry = timed[label] or { count = 0, ms = 0 }
        entry.count, entry.ms = entry.count + 1, entry.ms + (clock() - started)
        timed[label] = entry
        return unpack(results)
    end
end
timeFunction(addon.MapMarks, "followZoom", "followZoom")
timeFunction(addon.MapMarks, "followAreaZoom", "followAreaZoom")
timeFunction(addon.MapMarks, "draw", "MapMarks.draw (full)")
timeFunction(addon.MapPins, "refresh", "MapPins.refresh")

local map = G.WorldMapFrame
local container = map.ScrollContainer
local rect = W.computeRect(container)
local x, y = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
scene.input({ type = "move", x = x, y = y })
wait(0.3)

local counts = {}
for name in pairs({ areaSets = true }) do
    counts[name] = 0
end
local store = addon.MapMarks.getAreaStore and addon.MapMarks.getAreaStore()
local lineCount, setCount = 0, 0
for _, set in pairs(store and store.areaSets or {}) do
    setCount = setCount + 1
    lineCount = lineCount + #(set.edges or {}) + #(set.rims or {})
end
print(string.format("area sets kept: %d, their edge and rim lines: %d", setCount, lineCount))

local function step(label, delta)
    calls, timed, counting = {}, {}, true
    scene.input({ type = "wheel", x = x, y = y, delta = delta })
    wait(0.6)
    counting = false
    local total, rows = 0, {}
    for name, count in pairs(calls) do
        total = total + count
        rows[#rows + 1] = { name, count }
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    local top = {}
    for index = 1, math.min(6, #rows) do
        top[#top + 1] = rows[index][1] .. " " .. rows[index][2]
    end
    local times = {}
    for name, entry in pairs(timed) do
        times[#times + 1] = string.format("%s x%d %.1f ms", name, entry.count, entry.ms)
    end
    table.sort(times)
    print(
        string.format(
            "%-10s scale %.2f  widget calls %6d  [%s]  %s",
            label,
            container:GetCanvasScale(),
            total,
            table.concat(top, ", "),
            table.concat(times, "; ")
        )
    )
end
for index = 1, 4 do
    step("in " .. index, 1)
end
for index = 1, 4 do
    step("out " .. index, -1)
end
