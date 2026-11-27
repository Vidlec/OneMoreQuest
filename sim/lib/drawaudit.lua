-- The audit of everything OneMoreQuest draws on the world map and the minimap, and what keeping it up costs while
-- the player does things with them: opens the map, leaves it open, drags it, zooms it, walks, turns, zooms the
-- minimap. For each: OneMoreQuest's calls into the game a frame (the mean and the worst frame), which of its
-- functions ran and how often, and what of its own on screen changed size in a frame (a text that changes size is
-- drawn again by the game, letter by letter: the cost the simulator does not time). Before them, what stands there:
-- every shown piece by its layer and kind. One body for the game's own map and for OpenMap's joined-up one
-- (sim/scenarios/audits/draw-audit.lua, draw-audit-openmap.lua). AUDIT_QUESTS=<n> quests tracked (8).
local W, sim, scene = require("widgets"), require("sim"), require("scene")
local mapcost = require("mapcost")
local G = sim.G

local audit = {}

local KINDS = { "FontString", "MaskTexture", "Line", "Texture" }
local function kindOf(region)
    for _, kind in ipairs(KINDS) do
        if region:IsObjectType(kind) then
            return kind
        end
    end
    return "other"
end

---Every shown region under some frames, with its frame's size on screen (its effective scale).
local function readShown(roots)
    local sizes, frames = {}, 0
    local function walk(frame)
        if not frame:IsShown() then
            return
        end
        frames = frames + 1
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
    for _, root in ipairs(roots) do
        walk(root)
    end
    return sizes, frames
end

---@return table[] roots OneMoreQuest's frames on the minimap: its unnamed children (the game's own are named, and
---the audit loads no other addon that puts frames there)
local function getMinimapRoots()
    local roots = {}
    for _, child in ipairs(W.state[G.Minimap].children or {}) do
        if not child:GetName() then
            roots[#roots + 1] = child
        end
    end
    return roots
end

local function getRoots(addon, map)
    local roots = {}
    if map:IsShown() then
        for _, layer in ipairs(mapcost.getLayers(addon, map)) do
            roots[#roots + 1] = layer
        end
    end
    for _, root in ipairs(getMinimapRoots()) do
        roots[#roots + 1] = root
    end
    return roots
end

---Prints what stands on a set of frames: the shown regions by kind.
function audit.sayInventory(label, roots)
    local sizes, frames = readShown(roots)
    local counts, total = {}, 0
    for region in pairs(sizes) do
        local kind = kindOf(region)
        counts[kind], total = (counts[kind] or 0) + 1, total + 1
    end
    local parts = {}
    for _, kind in ipairs({ "Texture", "Line", "FontString", "MaskTexture", "other" }) do
        if counts[kind] then
            parts[#parts + 1] = kind .. " " .. counts[kind]
        end
    end
    print(
        string.format(
            "   on %-24s %5d shown regions in %4d frames | %s",
            label,
            total,
            frames,
            table.concat(parts, ", ")
        )
    )
end

---Runs a piece of play and prints what it cost, frame by frame summed up.
function audit.phase(addon, map, name, body)
    mapcost.frameLog = {}
    local resized = { frames = 0, texts = 0, others = 0, mostTexts = 0, mostOthers = 0 }
    mapcost.measure(name, function()
        local tick = sim.tick
        sim.tick = function(elapsed)
            local before = readShown(getRoots(addon, map))
            local a, b = tick(elapsed)
            local texts, others = 0, 0
            for region, scale in pairs((readShown(getRoots(addon, map)))) do
                local was = before[region]
                if was and math.abs(scale / was - 1) > 0.001 then
                    if region:IsObjectType("FontString") then
                        texts = texts + 1
                    else
                        others = others + 1
                    end
                end
            end
            resized.frames = resized.frames + ((texts + others) > 0 and 1 or 0)
            resized.texts, resized.others = resized.texts + texts, resized.others + others
            resized.mostTexts, resized.mostOthers =
                math.max(resized.mostTexts, texts), math.max(resized.mostOthers, others)
            return a, b
        end
        local isFine, problem = pcall(body)
        sim.tick = tick
        if not isFine then
            error(problem, 0)
        end
    end)
    local frames = mapcost.frameLog
    mapcost.frameLog = nil
    local calls, busy, worst, worstRan = 0, 0, 0, ""
    for _, frame in ipairs(frames) do
        calls = calls + frame.calls
        if frame.calls > 0 then
            busy = busy + 1
        end
        if frame.calls > worst then
            worst, worstRan = frame.calls, frame.ran
        end
    end
    print(
        string.format(
            "   %d frames: %.0f calls a frame, %d frames with any, worst %d (%s) | resized on screen: texts %d in all (most %d a frame), others %d (most %d), in %d frames",
            #frames,
            calls / math.max(#frames, 1),
            busy,
            worst,
            worstRan,
            resized.texts,
            resized.mostTexts,
            resized.others,
            resized.mostOthers,
            resized.frames
        )
    )
end

---The whole audit, in a game logged in and standing in Riverglades.
function audit.run(env)
    local setProfile, moveTo, accept, wait, key, hold, zoomMinimap, expect =
        env.setProfile, env.moveTo, env.accept, env.wait, env.key, env.hold, env.zoomMinimap, env.expect
    if jit then
        jit.off()
        jit.flush()
    end
    local RIVER_MAP = 2548
    setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
    moveTo(RIVER_MAP, 0.794, 0.527)
    local accepted = mapcost.trackZoneQuests(accept, tonumber(mapcost.option("AUDIT_QUESTS") or "8"))
    local addon = require("addons").byName["onemorequest"].private
    addon.Focus.set(accepted[1])
    wait(3)
    local map = G.WorldMapFrame
    local isJoined = G.OpenMapAPI ~= nil
    print(
        "DRAW AUDIT: "
            .. #accepted
            .. " quests tracked, "
            .. (isJoined and "OpenMap's joined-up map" or "the game's own map")
    )

    mapcost.install()
    mapcost.timeFunction(addon.MapPins, "refresh", "MAP REDRAW")
    mapcost.timeFunction(addon.MapMarks, "followZoom", "followZoom")
    mapcost.timeFunction(addon.MapMarksWorld, "update", "world.update")
    mapcost.timeFunction(addon.MapPins, "handleViewMoved", "viewMoved")
    mapcost.timeFunction(addon.MinimapPins, "refresh", "MINIMAP REDRAW")
    mapcost.timeFunction(addon.MinimapPins, "move", "minimap.move")
    mapcost.timeFunction(addon.MinimapPins, "slide", "minimap.slide")
    mapcost.timeFunction(addon.MapMarks, "updateParty", "party dots")
    mapcost.timeFunction(addon.Log, "refresh", "quest window")
    local function phase(name, body)
        audit.phase(addon, map, name, body)
    end

    print("-- the minimap, the map closed")
    audit.sayInventory("the minimap", getMinimapRoots())
    phase("standing still, 2 s", function()
        wait(2)
    end)
    phase("running, 3 s", function()
        hold("W", 3)
    end)
    phase("turning, 2 s", function()
        hold("A", 2)
    end)
    G.SetCVar("rotateMinimap", "1")
    wait(1)
    phase("turning, the minimap rotating, 2 s", function()
        hold("A", 2)
    end)
    phase("running, the minimap rotating, 3 s", function()
        hold("W", 3)
    end)
    G.SetCVar("rotateMinimap", "0")
    wait(1)
    phase("the minimap zoomed in a step", function()
        zoomMinimap(3)
        wait(1)
    end)
    phase("the minimap zoomed out again", function()
        zoomMinimap(0)
        wait(1)
    end)

    print("-- the world map")
    phase("map opened", function()
        key("M")
        wait(2.5)
    end)
    if isJoined then
        expect(G.OpenMapAPI.IsStitched(), "OpenMap's joined-up map shows")
    end
    audit.sayInventory("the world map", mapcost.getLayers(addon, map))
    mapcost.sayHanging(map, "open")
    local rect = W.computeRect(map.ScrollContainer)
    local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
    scene.input({ type = "move", x = 5, y = 5 })
    phase("open, the pointer away, 2 s", function()
        wait(2)
    end)
    scene.input({ type = "move", x = cx, y = cy })
    phase("open, the pointer on the map, 2 s", function()
        wait(2)
    end)
    phase("the pointer moving over the map, 1 s", function()
        for step = 1, 20 do
            scene.input({ type = "move", x = cx - 150 + step * 15, y = cy - 60 + step * 6 })
            sim.tick(0.05)
        end
    end)
    phase("running with the map open, 3 s", function()
        hold("W", 3)
    end)
    local function wheel(label, delta, notches)
        phase(label, function()
            for _ = 1, notches do
                scene.input({ type = "wheel", x = cx, y = cy, delta = delta })
                wait(0.15)
            end
            wait(2)
        end)
    end
    wheel("wheel in x3", 1, 3)
    phase("dragged", function()
        mapcost.drag(map, -300, -120)
        wait(1.5)
    end)
    phase("dragged back", function()
        mapcost.drag(map, 300, 120)
        wait(1.5)
    end)
    wheel("wheel out x3", -1, 3)
    if isJoined then
        wheel("wheel out x4 more", -1, 4)
        phase("dragged far", function()
            mapcost.drag(map, -500, 0)
            wait(1.5)
        end)
        wheel("wheel in x7", 1, 7)
    end
    audit.sayInventory("the world map, at the end", mapcost.getLayers(addon, map))
    mapcost.sayHanging(map, "at the end")
    phase("map closed", function()
        key("M")
        wait(1)
    end)
end

return audit
