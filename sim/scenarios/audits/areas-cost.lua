--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest
-- What the quests' areas cost, apart from the rest of the marks: tracing each tracked objective's areas from cold (the
-- spawns' glows on a grid, the outline, its fill cut into triangles), and laying them out on the map (a texture for
-- each triangle, a line for each piece of edge). Riverglades' quests near the character's level, and the heaviest
-- quests (It Takes Guts, My First Alchemy Set, Ineptitude + Chemicals = Fun). AREAS_QUESTS=<n> Riverglades quests (20).
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene, game = require("widgets"), require("sim"), require("scene"), require("game")
local getinfo = debug.getinfo
local OURS = "@Interface/AddOns/OneMoreQuest/"
local TOP = tonumber(os.getenv("OPENMAP_COST_TOP") or "40")
local RIVER_MAP, RIVER_AREA = 2548, 16591

setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = {}
do
    local Q = G.LibQuestieDB.Quest
    local wanted = tonumber(os.getenv("AREAS_QUESTS") or "20")
    for questId = 1, 99999 do
        local isRead, zoneOrSort = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and zoneOrSort == RIVER_AREA and #accepted < wanted then
            local level = Q.Get(questId, "questLevel") or 0
            if level >= 34 and level <= 44 and pcall(accept, questId) then
                accepted[#accepted + 1] = questId
            end
        end
    end
    for _, questId in ipairs({ 95261, 92109, 1073 }) do
        if game.acceptQuest(questId) ~= false then
            accepted[#accepted + 1] = questId
        end
    end
end
for _, questId in ipairs(accepted) do
    if not G.C_QuestLog.GetQuestWatchType(questId) then
        G.C_QuestLog.AddQuestWatch(questId)
    end
end
print("AREAS quests tracked: " .. #accepted)
wait(3)
local addon = require("addons").byName["onemorequest"].private

local isCounting, widgetCalls, callTotal = false, {}, 0
for _, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if isCounting then
                    local info = getinfo(2, "S")
                    if info and info.source:sub(1, #OURS) == OURS then
                        widgetCalls[name] = (widgetCalls[name] or 0) + 1
                        callTotal = callTotal + 1
                    end
                end
                return method(...)
            end
        end
    end
end

-- Samples: every 1000 instructions, the innermost addon on the stack (or "game" when none), and every function of
-- ours on it
local byAddon, ourFunctions, samples = {}, {}, 0
local function sample()
    samples = samples + 1
    local owner, seen = nil, {}
    for level = 2, 80 do
        local info = getinfo(level, "Sn")
        if not info then
            break
        end
        local name = info.source:match("^@Interface/AddOns/([^/]+)/")
        if name and not owner then
            owner = name
        end
        if name == "OneMoreQuest" then
            local key = info.source:sub(#OURS + 1):gsub("%.lua$", "")
                .. ":"
                .. tostring(info.name or "?")
                .. "@"
                .. info.linedefined
            if not seen[key] then
                seen[key] = true
                ourFunctions[key] = (ourFunctions[key] or 0) + 1
            end
        end
    end
    owner = owner or "game"
    byAddon[owner] = (byAddon[owner] or 0) + 1
end

-- OneMoreQuest's big pieces of work, counted and timed (with what they call), and the map changing underneath
local timed = {}
local function timeFunction(owner, key, label)
    local original = owner[key]
    owner[key] = function(...)
        if not isCounting then
            return original(...)
        end
        local started, callsBefore = os.clock(), callTotal
        local a, b, c, d = original(...)
        local entry = timed[label] or { count = 0, ms = 0, calls = 0 }
        entry.count, entry.ms = entry.count + 1, entry.ms + (os.clock() - started) * 1000
        entry.calls = entry.calls + (callTotal - callsBefore)
        timed[label] = entry
        return a, b, c, d
    end
end
timeFunction(addon.MapPins, "refresh", "full redraw")
-- Who asked for each full redraw, and for each queued one: OneMoreQuest's functions on the stack
local function sayCallers(what)
    local chain = {}
    for level = 3, 30 do
        local info = getinfo(level, "Sln")
        if not info then
            break
        end
        if info.source:sub(1, #OURS) == OURS then
            chain[#chain + 1] = info.source:sub(#OURS + 1):gsub("%.lua$", "") .. ":" .. info.currentline
        end
    end
    print(string.format("     %.2f s %s from %s", G.GetTime(), what, table.concat(chain, " < ")))
end
for _, name in ipairs({ "refresh", "queueRefresh", "queueSettledRefresh" }) do
    local original = addon.MapPins[name]
    addon.MapPins[name] = function(...)
        if isCounting then
            sayCallers(name)
        end
        return original(...)
    end
end
do
    local original = addon.Log.refresh
    addon.Log.refresh = function(...)
        if isCounting then
            sayCallers("quest window")
        end
        return original(...)
    end
end
timeFunction(addon.MapMarks, "compose", "compose")
timeFunction(addon.MapMarks, "followZoom", "followZoom")
timeFunction(addon.MinimapPins, "refresh", "minimap redraw")
timeFunction(addon.Log, "refresh", "quest window")
local mapChanges = 0
G.hooksecurefunc(G.WorldMapFrame, "OnMapChanged", function()
    if isCounting then
        mapChanges = mapChanges + 1
    end
end)

local function sorted(counts)
    local rows, total = {}, 0
    for key, count in pairs(counts) do
        rows[#rows + 1] = { key, count }
        total = total + count
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    return rows, total
end

local function measure(name, body)
    widgetCalls, byAddon, ourFunctions, samples, timed, mapChanges = {}, {}, {}, 0, {}, 0
    collectgarbage("collect")
    local memory = collectgarbage("count")
    isCounting = true
    local started = os.clock()
    debug.sethook(sample, "", 1000)
    body()
    debug.sethook()
    local spent = (os.clock() - started) * 1000
    isCounting = false
    local calls, callTotal = sorted(widgetCalls)
    local top = {}
    for index = 1, math.min(6, #calls) do
        top[index] = calls[index][1] .. " " .. calls[index][2]
    end
    local addons = sorted(byAddon)
    local shares = {}
    for index = 1, math.min(4, #addons) do
        shares[index] =
            string.format("%s %d%%", addons[index][1], math.floor(addons[index][2] / math.max(samples, 1) * 100 + 0.5))
    end
    local ours = (byAddon.OneMoreQuest or 0) / math.max(samples, 1)
    print(
        string.format(
            "== %-36s %7.0f ms in all, OneMoreQuest ~%5.0f ms   widget calls %6d   [%s]",
            name,
            spent,
            spent * ours,
            callTotal,
            table.concat(top, ", ")
        )
    )
    print(
        "   by addon: "
            .. table.concat(shares, ", ")
            .. string.format("   (+%.0f KB in use)", collectgarbage("count") - memory)
    )
    local parts = {}
    for label, entry in pairs(timed) do
        parts[#parts + 1] = string.format("%s x%d %.0f ms %d calls", label, entry.count, entry.ms, entry.calls)
    end
    table.sort(parts)
    print(string.format("   map changed underneath x%d; %s", mapChanges, table.concat(parts, "; ")))
    local functions = sorted(ourFunctions)
    for index = 1, math.min(TOP, #functions) do
        print(
            string.format(
                "     %3d%%  %s",
                math.floor(functions[index][2] / math.max(samples, 1) * 100 + 0.5),
                functions[index][1]
            )
        )
    end
end

-- Every tracked objective's spawns on the zone's map, as the drawing gathers them
local groups = {}
for _, questId in ipairs(accepted) do
    local objectives = G.C_QuestLog.GetQuestObjectives(questId) or {}
    local counts = {}
    for _, objective in ipairs(objectives) do
        local kind = objective.type
        counts[kind] = (counts[kind] or 0) + 1
        local places = addon.Location.getObjectiveInfo(questId, kind, counts[kind])
        local points = addon.MapMarksCompose.composePoints(places, RIVER_MAP)
        if #points >= 2 then
            groups[#groups + 1] = { questId = questId, points = points }
        end
    end
end
local triangles, edges, areaCount, spawnCount = 0, 0, 0, 0
measure("areas traced from cold, every objective", function()
    for index, group in ipairs(groups) do
        -- (another quest id each time: nothing kept from before)
        local areas = addon.MapMarks.composeFittedShapes(900000 + index, RIVER_MAP, group.points, true)
        for _, area in ipairs(areas) do
            areaCount = areaCount + 1
            triangles, edges = triangles + #area.triangles, edges + #area.edges
        end
        spawnCount = spawnCount + #group.points
    end
end)
print(
    string.format(
        "AREAS %d objectives, %d spawns: %d areas, %d triangles of fill, %d pieces of edge",
        #groups,
        spawnCount,
        areaCount,
        triangles,
        edges
    )
)
local map = G.WorldMapFrame
measure("map opened (areas laid out)", function()
    key("M")
    wait(0.5)
    map:SetMapID(RIVER_MAP)
    wait(2)
end)
local store = addon.MapMarks.getDrawn(map)
local laidTriangles, laidLines = 0, 0
for _, set in pairs(store.areaSets or {}) do
    laidTriangles, laidLines =
        laidTriangles + #(set.triangles or {}), laidLines + #(set.edges or {}) + #(set.rims or {})
end
print(string.format("AREAS laid out: %d triangle textures, %d lines", laidTriangles, laidLines))
local rect = W.computeRect(map.ScrollContainer)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
scene.input({ type = "move", x = cx, y = cy })
wait(0.2)
measure("zoomed in a step (lines follow)", function()
    scene.input({ type = "wheel", x = cx, y = cy, delta = 1 })
    wait(1)
end)
measure("another quest focused (areas recoloured)", function()
    addon.Focus.set(accepted[2])
    wait(1)
end)
measure("1 s map open, mouse over the areas", function()
    for step = 1, 10 do
        scene.input({ type = "move", x = cx + step * 3, y = cy + step * 2 })
        wait(0.1)
    end
end)
