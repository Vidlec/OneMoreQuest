--@login race=Orc,class=WARRIOR,level=40
--@addons QuestieDB, OneMoreQuest
-- What OneMoreQuest costs on the world map in a zone of many spawns (Riverglades, Forever's own: a player there saw
-- thousands of spawn icons and the game slow down): its quests near the character's level taken, the map opened on
-- the zone, then standing, zooming in and out and panning with it open. Each line: the time, OneMoreQuest's share,
-- its widget calls; then how many of its spawn icons show. RIVER_QUESTS=<n> quests taken (20).
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene = require("widgets"), require("sim"), require("scene")
local getinfo = debug.getinfo
local OURS = "@Interface/AddOns/OneMoreQuest/"
local TOP = tonumber(os.getenv("OPENMAP_COST_TOP") or "8")

local RIVER_MAP, RIVER_AREA = 2548, 16591
local WANTED = tonumber(os.getenv("RIVER_QUESTS") or "20")

setProfile({ level = 40, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = {}
do
    local Q = G.LibQuestieDB.Quest
    for questId = 1, 99999 do
        local isRead, zoneOrSort = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and zoneOrSort == RIVER_AREA and #accepted < WANTED then
            local level = Q.Get(questId, "questLevel") or 0
            if level >= 34 and level <= 44 and pcall(accept, questId) then
                accepted[#accepted + 1] = questId
            end
        end
    end
end
print("RIVER quests taken: " .. #accepted)
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

-- OneMoreQuest's textures shown on the map's canvas (the spawn icons are most of them)
local function countShown()
    local canvas = G.WorldMapFrame.ScrollContainer.Child
    local textures, frames = 0, 0
    local function walk(frame)
        if not frame:IsShown() then
            return
        end
        frames = frames + 1
        for _, region in ipairs({ frame:GetRegions() }) do
            if region:IsObjectType("Texture") and region:IsShown() then
                textures = textures + 1
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            walk(child)
        end
    end
    walk(canvas)
    print(string.format("RIVER shown on the map's canvas: %d frames, %d textures", frames, textures))
end

local map = G.WorldMapFrame
measure("map opened (first time)", function()
    key("M")
    wait(1.5)
end)
expect(map:IsShown(), "the world map is open")
map:SetMapID(RIVER_MAP)
wait(1)
countShown()
local container = map.ScrollContainer
local rect = W.computeRect(container)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
scene.input({ type = "move", x = cx, y = cy })
wait(0.3)
measure("1 s map open, nothing happening", function()
    wait(1)
end)
measure("zoomed in (3 wheel steps)", function()
    for _ = 1, 3 do
        scene.input({ type = "wheel", x = cx, y = cy, delta = 1 })
        wait(0.2)
    end
    wait(0.6)
end)
countShown()
measure("1 s zoomed in, nothing happening", function()
    wait(1)
end)
measure("panned (a drag across the map)", function()
    scene.input({ type = "down", x = cx, y = cy, button = "LeftButton" })
    for step = 1, 10 do
        scene.input({ type = "move", x = cx - step * 20, y = cy - step * 8 })
        wait(0.05)
    end
    scene.input({ type = "up", x = cx - 200, y = cy - 80, button = "LeftButton" })
    wait(0.6)
end)
measure("zoomed out again", function()
    for _ = 1, 3 do
        scene.input({ type = "wheel", x = cx, y = cy, delta = -1 })
        wait(0.2)
    end
    wait(0.6)
end)
countShown()
measure("a kill that counts, map open", function()
    progress(accepted[1], 1, 1)
    wait(0.6)
end)
