--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- Zooming into a part of OpenMap's joined-up map where none of the quests' marks are (the sea off Riverglades), with
-- quests to pick up, areas and spawn markers all on: what OneMoreQuest still keeps on the map and still works on,
-- frame by frame. Nothing of it is in view, so anything kept there or made there is for nothing.
-- EMPTY_QUESTS=<n> quests tracked (12).
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene = require("widgets"), require("sim"), require("scene")
local mapcost = require("mapcost")
local RIVER_MAP = 2548
setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = mapcost.trackZoneQuests(accept, tonumber(mapcost.option("EMPTY_QUESTS") or "12"))
local addon = require("addons").byName["onemorequest"].private
wait(2)
local map = G.WorldMapFrame
key("M")
wait(4)
expect(G.OpenMapAPI and G.OpenMapAPI.IsStitched(), "OpenMap's joined-up map shows")
mapcost.install()
mapcost.timeFunction(addon.MapPins, "refresh", "MAP REDRAW")
mapcost.timeFunction(addon.MapMarksWorld, "update", "world.update")
mapcost.timeFunction(addon.MapPins, "queueSettledRefresh", "asked: settled")
mapcost.timeFunction(addon.MapPins, "queueRearrange", "asked: rearrange")
mapcost.timeFunction(addon.MapMarks, "hideUntilDrawn", "asked: map changed")

local rect = W.computeRect(map.ScrollContainer)
-- (the right edge of the view, a little above the middle: open sea, east of everything the quests mark)
local x, y = rect[3] - 40, sim.screenHeight - (rect[2] + rect[4]) / 2 - 120
scene.input({ type = "move", x = x, y = y })
wait(0.5)

local function say(label)
    local c = addon.MapMarksWorld.getCounts(map)
    print(
        string.format(
            "   %-12s kept drawing shown: %d sets, %d fills, %d edges, %d tiles, %d spawn marks; to do %d; kept in all %d pieces (map %s, zoom %.2f)",
            label,
            c.setsShown or 0,
            c.fillsShown or 0,
            c.edgesShown or 0,
            c.tilesShown or 0,
            c.iconsShown or 0,
            c.todo or 0,
            c.kept or 0,
            tostring(map:GetMapID()),
            map:GetCanvasScale()
        )
    )
    mapcost.sayHanging(map, label)
end
say("before")
for step = 1, tonumber(mapcost.option("EMPTY_STEPS") or "8") do
    mapcost.frameLog = {}
    mapcost.measure("wheel in " .. step .. " (over the sea)", function()
        scene.input({ type = "wheel", x = x, y = y, delta = 1 })
        for _ = 1, 90 do
            sim.tick(0.016)
        end
    end)
    local busy, calls = 0, 0
    for _, frame in ipairs(mapcost.frameLog) do
        calls = calls + frame.calls
        if frame.calls > 40 then
            busy = busy + 1
        end
    end
    mapcost.frameLog = nil
    print(string.format("   90 frames: %d with more than 40 calls, %d calls in all", busy, calls))
    say("after " .. step)
end
