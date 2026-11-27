--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- Zooming OpenMap's joined-up map with a few quests tracked, frame by frame: a wheel turned notch after notch (one
-- every ZOOM_GAP seconds, 0.15), out and back in, and what OneMoreQuest does in each frame of it and of the second
-- after. A zoom's lag is its worst frames, and what runs between the notches. ZOOM_QUESTS=<n> quests tracked (3).
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene = require("widgets"), require("sim"), require("scene")
local mapcost = require("mapcost")
local RIVER_MAP = 2548

setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = mapcost.trackZoneQuests(accept, tonumber(mapcost.option("ZOOM_QUESTS") or "3"))
local addon = require("addons").byName["onemorequest"].private
-- ZOOM_AREAS=none, ZOOM_SPAWNS=none: the quests' marks alone, no areas and no spawn markers (the settings' choices)
if mapcost.option("ZOOM_AREAS") then
    addon.settings.areaStyle = mapcost.option("ZOOM_AREAS")
end
if mapcost.option("ZOOM_SPAWNS") then
    addon.settings.spawnMarker = mapcost.option("ZOOM_SPAWNS")
end
wait(3)

mapcost.install()
mapcost.timeFunction(addon.MapPins, "refresh", "REDRAW")
mapcost.timeFunction(addon.MapMarks, "compose", "compose")
mapcost.timeFunction(addon.MapMarks, "followZoom", "followZoom")
mapcost.timeFunction(addon.MapMarksWorld, "update", "world.update")
mapcost.timeFunction(addon.MapMarksWorld, "handleMapChanged", "mapChanged")
mapcost.timeFunction(addon.Log, "refresh", "quest window")

local map = G.WorldMapFrame
key("M")
wait(2.5)
expect(G.OpenMapAPI and G.OpenMapAPI.IsStitched(), "OpenMap's joined-up map shows")
local rect = W.computeRect(map.ScrollContainer)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
scene.input({ type = "move", x = cx, y = cy })
wait(0.5)
local gap = tonumber(mapcost.option("ZOOM_GAP") or "0.15")

-- What the game itself has to do again for a frame of a zoom, which the simulator does not time: every text whose
-- size on screen changed is drawn again at the new size (its letters rendered anew), every picture laid out again.
-- Counted for OneMoreQuest's shown regions on the map: how many changed size on screen in a frame, by kind.
local function readSizes()
    local sizes = {}
    local function walk(frame)
        if not frame:IsShown() then
            return
        end
        local scale = frame:GetEffectiveScale()
        for _, region in ipairs(W.state[frame].regions or {}) do
            if region:IsShown() then
                sizes[region] = scale
            end
        end
        for _, child in ipairs(W.state[frame].children or {}) do
            walk(child)
        end
    end
    for _, layer in ipairs(mapcost.getLayers(addon, map)) do
        walk(layer)
    end
    return sizes
end
local function countResized(before, after, counts)
    local texts, others = 0, 0
    for region, scale in pairs(after) do
        local was = before[region]
        if was and math.abs(scale / was - 1) > 0.001 then
            if region:IsObjectType("FontString") then
                texts = texts + 1
            else
                others = others + 1
            end
        end
    end
    counts.frames = counts.frames + ((texts + others) > 0 and 1 or 0)
    counts.texts, counts.others = counts.texts + texts, counts.others + others
    counts.mostTexts, counts.mostOthers = math.max(counts.mostTexts, texts), math.max(counts.mostOthers, others)
end

local function zoom(name, delta, notches)
    mapcost.frameLog = {}
    local resized = { frames = 0, texts = 0, others = 0, mostTexts = 0, mostOthers = 0 }
    mapcost.measure(name, function()
        local tick = sim.tick
        sim.tick = function(elapsed)
            local before = readSizes()
            local a, b = tick(elapsed)
            countResized(before, readSizes(), resized)
            return a, b
        end
        for _ = 1, notches do
            scene.input({ type = "wheel", x = cx, y = cy, delta = delta })
            wait(gap)
        end
        wait(2)
        sim.tick = tick
    end)
    print(
        string.format(
            "   resized on screen: in %d frames, texts %d (most in a frame %d), other regions %d (most %d)",
            resized.frames,
            resized.texts,
            resized.mostTexts,
            resized.others,
            resized.mostOthers
        )
    )
    local frames, busy, busyMs, busyCalls = mapcost.frameLog, 0, 0, 0
    mapcost.frameLog = nil
    local quiet = math.huge
    for _, frame in ipairs(frames) do
        quiet = math.min(quiet, frame.ms)
    end
    for index, frame in ipairs(frames) do
        if frame.calls > 60 or frame.ran:find("REDRAW") or frame.ran:find("world") then
            busy, busyMs, busyCalls = busy + 1, busyMs + frame.ms - quiet, busyCalls + frame.calls
            print(string.format("   frame %3d  %5.1f ms  %5d calls  %s", index, frame.ms, frame.calls, frame.ran))
        end
    end
    print(
        string.format(
            "   %s: %d frames, %d busy, +%.0f ms over a quiet frame's %.1f, %d calls in them (map %s)",
            name,
            #frames,
            busy,
            busyMs,
            quiet,
            busyCalls,
            tostring(map:GetMapID())
        )
    )
    mapcost.sayHanging(map, name)
end
zoom("wheel out x6", -1, 6)
zoom("wheel in x6", 1, 6)
zoom("wheel out x3", -1, 3)
zoom("wheel in x3", 1, 3)
