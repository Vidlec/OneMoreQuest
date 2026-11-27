-- The same play measured for one addon at a time, to compare them: a character with the same quests tracked, OpenMap's
-- joined-up map opened, left alone, zoomed out and in, dragged. For the addon named: its calls into the game a frame
-- (the mean, and the worst frame), and what stands on the map with it loaded (every shown region under the map's
-- canvas: take away what stands there with neither loaded, audits/compare-none.lua, for the addon's own).
local W, sim, scene = require("widgets"), require("sim"), require("scene")
local mapcost = require("mapcost")
local G = sim.G
local compare = {}

local function countCanvas(map)
    local counts = { frames = 0, regions = 0, texts = 0, lines = 0, masks = 0 }
    local function walk(frame)
        if not frame:IsShown() then
            return
        end
        counts.frames = counts.frames + 1
        for _, region in ipairs(W.state[frame].regions or {}) do
            if region:IsShown() then
                counts.regions = counts.regions + 1
                if region:IsObjectType("FontString") then
                    counts.texts = counts.texts + 1
                elseif region:IsObjectType("Line") then
                    counts.lines = counts.lines + 1
                elseif region:IsObjectType("MaskTexture") then
                    counts.masks = counts.masks + 1
                end
            end
        end
        for _, child in ipairs(W.state[frame].children or {}) do
            walk(child)
        end
    end
    walk(map.ScrollContainer.Child)
    return counts
end

function compare.run(env, addonName)
    local setProfile, moveTo, accept, wait, key = env.setProfile, env.moveTo, env.accept, env.wait, env.key
    if jit then
        jit.off()
        jit.flush()
    end
    setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
    moveTo(2548, 0.794, 0.527)
    local accepted = mapcost.trackZoneQuests(accept, 12)
    wait(6) -- (each addon's own start: its database, its first drawing)
    local map = G.WorldMapFrame
    key("M")
    wait(2)
    local frame = G.EnumerateFrames()
    while frame do
        if frame:IsObjectType("Button") and frame:IsVisible() and frame.GetText and frame:GetText() == "OpenMap" then
            frame:Click()
        end
        frame = G.EnumerateFrames(frame)
    end
    wait(5)
    print("COMPARE " .. (addonName or "neither addon") .. ": " .. #accepted .. " quests tracked")
    mapcost.install()
    if addonName then
        mapcost.setAddon(addonName)
    end
    local function say(label)
        local c = countCanvas(map)
        print(
            string.format(
                "   on the map %-12s %5d shown regions (%d texts, %d lines, %d masks) in %d frames",
                label,
                c.regions,
                c.texts,
                c.lines,
                c.masks,
                c.frames
            )
        )
    end
    local function phase(name, body)
        mapcost.frameLog = {}
        mapcost.measure(name, body)
        local frames, calls, worst = mapcost.frameLog, 0, 0
        mapcost.frameLog = nil
        for _, each in ipairs(frames) do
            calls, worst = calls + each.calls, math.max(worst, each.calls)
        end
        print(
            string.format(
                "   %d frames: %.0f calls a frame, worst frame %d calls",
                #frames,
                calls / math.max(#frames, 1),
                worst
            )
        )
    end
    local rect = W.computeRect(map.ScrollContainer)
    local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
    local function frames(count)
        for _ = 1, count do
            sim.tick(0.016)
        end
    end
    say("opened")
    scene.input({ type = "move", x = cx, y = cy })
    phase("left alone, 2 s", function()
        frames(120)
    end)
    local function wheel(label, delta, notches)
        phase(label, function()
            for _ = 1, notches do
                scene.input({ type = "wheel", x = cx, y = cy, delta = delta })
                frames(10)
            end
            frames(120)
        end)
    end
    wheel("wheel out x3", -1, 3)
    say("zoomed out")
    wheel("wheel in x3", 1, 3)
    phase("dragged", function()
        mapcost.drag(map, -300, -120)
        frames(90)
    end)
    phase("dragged back", function()
        mapcost.drag(map, 300, 120)
        frames(90)
    end)
    say("at the end")
end

return compare
