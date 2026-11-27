--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- Putting another quest in focus, and hovering a quest in the quest window's list, with the map open: what of the
-- map's drawing blinks (shown, gone for a frame or more, shown again), frame by frame, and what the change costs.
-- A piece that goes and comes back is a flash the player sees. FLASH_QUESTS=<n> quests tracked (8).
if jit then
    jit.off()
    jit.flush()
end
local W, sim = require("widgets"), require("sim")
local mapcost = require("mapcost")
local RIVER_MAP = 2548
setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = mapcost.trackZoneQuests(accept, tonumber(mapcost.option("FLASH_QUESTS") or "8"))
local addon = require("addons").byName["onemorequest"].private
addon.Focus.set(accepted[1])
wait(2)
local map = G.WorldMapFrame
key("M")
wait(4)
addon.MapMarksWorld.finish(map)
wait(1)

mapcost.install()
mapcost.timeFunction(addon.MapPins, "refresh", "MAP REDRAW")
mapcost.timeFunction(addon.MapMarks, "compose", "compose")
mapcost.timeFunction(addon.MapMarksWorld, "update", "world.update")
mapcost.timeFunction(addon.MapMarksWorld, "setFeatures", "world.setFeatures")
mapcost.timeFunction(addon.MinimapPins, "refresh", "MINIMAP REDRAW")
mapcost.timeFunction(addon.Log, "refresh", "quest window")

-- Every region of ours on the map that shows (itself and every frame above it), by the layer it is on
local function readShown()
    local shown = {}
    local names = {}
    local drawn, markLayer, areaLayer = addon.MapMarks.getDrawn(map)
    names[markLayer or false], names[areaLayer or false] = "old marks' layer", "old areas' layer"
    names[drawn.pinLayer or false], names[drawn.glowLayer or false] = "marks", "marks' glows"
    for index, root in ipairs(addon.MapMarksWorld.getLayers(map)) do
        names[root] = index == 1 and "areas and spawn marks" or "kept " .. index
    end
    local function walk(frame, name)
        if not frame:IsShown() or (frame:GetAlpha() or 1) <= 0 then
            return
        end
        for _, region in ipairs(W.state[frame].regions or {}) do
            if region:IsShown() then
                shown[region] = name
            end
        end
        for _, child in ipairs(W.state[frame].children or {}) do
            walk(child, name)
        end
    end
    for _, layer in ipairs(mapcost.getLayers(addon, map)) do
        walk(layer, names[layer] or "other")
    end
    return shown
end

local function watch(name, seconds, body)
    local before = readShown()
    local gone, blinked, perFrame = {}, {}, {}
    mapcost.frameLog = {}
    mapcost.measure(name, function()
        local tick = sim.tick
        local frame = 0
        sim.tick = function(elapsed)
            local a, b = tick(elapsed)
            frame = frame + 1
            local now = readShown()
            local missing = {}
            for region, layer in pairs(before) do
                if not now[region] then
                    gone[region] = gone[region] or frame
                    missing[layer] = (missing[layer] or 0) + 1
                elseif gone[region] then
                    blinked[layer] = (blinked[layer] or 0) + 1
                    gone[region] = nil
                end
            end
            local parts = {}
            for layer, count in pairs(missing) do
                parts[#parts + 1] = layer .. " " .. count
            end
            table.sort(parts)
            local c = addon.MapMarksWorld.getCounts(map)
            local marks = 0
            for _, layer in pairs(now) do
                if layer == "marks" then
                    marks = marks + 1
                end
            end
            perFrame[frame] = string.format(
                "sets %d fills %d edges %d tiles %d spawn marks %d, marks' pieces %d, to do %d | gone: %s",
                c.setsShown or 0,
                c.fillsShown or 0,
                c.edgesShown or 0,
                c.tilesShown or 0,
                c.iconsShown or 0,
                marks,
                c.todo or 0,
                table.concat(parts, ", ")
            )
            return a, b
        end
        local isFine, problem = pcall(function()
            body()
            for _ = 1, math.floor(seconds / 0.016) do
                sim.tick(0.016) -- (frames as short as the game's: what lasts one of them is seen)
            end
        end)
        sim.tick = tick
        if not isFine then
            error(problem, 0)
        end
    end)
    local last
    for frame, text in ipairs(perFrame) do
        local log = mapcost.frameLog[frame]
        if text ~= last or (log and log.calls > 150) then
            print(
                string.format(
                    "   frame %2d  %4d calls  %s   %s",
                    frame,
                    log and log.calls or 0,
                    text,
                    log and log.ran ~= "" and ("[" .. log.ran .. "]") or ""
                )
            )
            last = text
        end
    end
    mapcost.frameLog = nil
    do
        -- (what a change of focus made the kept drawing do over: its spawn marks sorted again, or coloured again)
        local world = addon.MapMarksWorld.worlds[map]
        print(string.format("   STAMPS sorted %s, colours %s", tostring(world.stamp), tostring(world.colorStamp)))
    end
    local parts = {}
    for layer, count in pairs(blinked) do
        parts[#parts + 1] = layer .. " " .. count
    end
    table.sort(parts)
    print("   BLINKED (gone, then back): " .. (#parts > 0 and table.concat(parts, ", ") or "nothing"))
end

watch("another quest in focus", 1.5, function()
    addon.Focus.set(accepted[2])
end)
watch("the first in focus again", 1.5, function()
    addon.Focus.set(accepted[1])
end)
-- A quest pointed at in the quest window's list beside the map (it stands out on the map as the one in focus does),
-- and the pointer taken off it again
local title = G.C_QuestLog.GetTitleForQuestID(accepted[3])
watch("a quest hovered in the list", 1.2, function()
    hover(title)
end)
expect(addon.Log.getHoveredQuestId() == accepted[3], "the list's quest is hovered")
watch("the hover gone", 1.2, function()
    require("scene").input({ type = "move", x = 5, y = 5 })
end)
-- A quest clicked in the list (opened and put in focus, the map turned to it), and another
watch("a quest clicked in the list", 1.2, function()
    click(G.C_QuestLog.GetTitleForQuestID(accepted[4]))
end)
watch("another clicked", 1.2, function()
    click(G.C_QuestLog.GetTitleForQuestID(accepted[5]))
end)
