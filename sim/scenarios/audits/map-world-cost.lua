--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- The map with many quests tracked, on OpenMap's joined-up world: what each thing a player does with it costs. Twenty
-- of Riverglades' quests and the three heaviest of the world (It Takes Guts, My First Alchemy Set, Ineptitude +
-- Chemicals = Fun: thousands of spawns over both continents). Opening, opening again, zooming out to the world and
-- back in, a drag, a drag into the next zone, another quest in focus, and a second of nothing.
-- MAPCOST_TOP=<n> lists OneMoreQuest's top functions of each step; WORLD_QUESTS=<n> the Riverglades quests (20);
-- WORLD_HEAVY=0 leaves the three heavy quests out (a few quests' marks alone).
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene, game = require("widgets"), require("sim"), require("scene"), require("game")
local mapcost = require("mapcost")
local RIVER_MAP, RIVER_AREA = 2548, 16591

setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = {}
do
    local Q = G.LibQuestieDB.Quest
    local wanted = tonumber(mapcost.option("WORLD_QUESTS") or "20")
    for questId = 1, 99999 do
        local isRead, zoneOrSort = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and zoneOrSort == RIVER_AREA and #accepted < wanted then
            local level = Q.Get(questId, "questLevel") or 0
            if level >= 34 and level <= 44 and pcall(accept, questId) then
                accepted[#accepted + 1] = questId
            end
        end
    end
    local heavy = mapcost.option("WORLD_HEAVY") == "0" and {} or { 95261, 92109, 1073 }
    for _, questId in ipairs(heavy) do
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
print("WORLD quests tracked: " .. #accepted)
local addon = require("addons").byName["onemorequest"].private
if mapcost.option("WORLD_RENDERER") then
    addon.settings.mapRenderer = mapcost.option("WORLD_RENDERER") -- "classic": the drawing before the kept one, to compare
end
wait(tonumber(mapcost.option("WORLD_IDLE") or "3"))

mapcost.install()
mapcost.timeFunction(addon.MapPins, "refresh", "full redraw")
mapcost.timeFunction(addon.MapMarks, "compose", "compose")
mapcost.timeFunction(addon.MapMarks, "draw", "draw")
mapcost.timeFunction(addon.MapMarks, "followZoom", "followZoom")
mapcost.timeFunction(addon.MinimapPins, "refresh", "minimap")
mapcost.timeFunction(addon.Log, "refresh", "quest window")
local measure, countRegions = mapcost.measure, mapcost.countRegions

local map = G.WorldMapFrame
do
    -- What was made ready with the map closed
    local counts = addon.MapMarksWorld.getCounts(map)
    print(
        string.format(
            "WORLD made ready while closed: %s pieces kept, %s spawn marks, %s spaces, %s to do",
            tostring(counts.kept),
            tostring(counts.keptIcons),
            tostring(counts.spaces),
            tostring(counts.todo)
        )
    )
end
measure("map opened (first)", function()
    key("M")
    wait(1.5)
end)
expect(G.OpenMapAPI and G.OpenMapAPI.IsStitched(), "OpenMap's joined-up map shows")
countRegions("opened")
measure("map closed", function()
    key("M")
    wait(0.5)
end)
measure("map opened again", function()
    key("M")
    wait(1.5)
end)
countRegions("opened again")
local rect = W.computeRect(map.ScrollContainer)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
scene.input({ type = "move", x = cx, y = cy })
wait(0.2)
local function wheel(delta, steps, label)
    for step = 1, steps do
        measure(label .. " " .. step, function()
            scene.input({ type = "wheel", x = cx, y = cy, delta = delta })
            wait(1.2)
        end)
        countRegions(string.format("%s %d (map %s)", label, step, tostring(map:GetMapID())))
    end
end
local function drag(name, dx, dy)
    local movedX, movedY
    measure(name, function()
        movedX, movedY = mapcost.drag(map, dx, dy)
        wait(1.5)
    end)
    print(string.format("   %s: the view went %.2f, %.2f of the map", name, movedX, movedY))
    countRegions(string.format("%s (map %s)", name, tostring(map:GetMapID())))
end
wheel(1, 3, "zoomed in")
drag("dragged", -300, -120)
drag("dragged back", 300, 120)
wheel(-1, 9, "zoomed out")
wheel(1, 6, "zoomed back in")
drag("dragged far", -600, 0)
drag("dragged far again", -600, 0)
measure("another quest in focus", function()
    addon.Focus.set(accepted[2])
    wait(1)
end)
measure("the first in focus again", function()
    addon.Focus.set(accepted[1])
    wait(1)
end)
measure("1 s, nothing happening", function()
    wait(1)
end)
countRegions("at the end")

-- The sum, and the worst frame of all: what to compare between two ways of drawing
local totalMs, totalOurs, totalCalls, worstMs, worstCalls, worstName = 0, 0, 0, 0, 0, ""
for name, result in pairs(mapcost.results) do
    totalMs, totalOurs, totalCalls = totalMs + result.ms, totalOurs + result.ours, totalCalls + result.calls
    if result.worstMs > worstMs then
        worstMs, worstName = result.worstMs, name
    end
    worstCalls = math.max(worstCalls, result.worstCalls)
end
print(
    string.format(
        "WORLD in all: %.0f ms, OneMoreQuest ~%.0f ms, %d widget calls; worst frame %.0f ms (%s), most calls in a frame %d",
        totalMs,
        totalOurs,
        totalCalls,
        worstMs,
        worstName,
        worstCalls
    )
)
