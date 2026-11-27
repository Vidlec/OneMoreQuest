--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- The spawn marks' size on screen and their number, frame by frame, through zooms in and out on OpenMap's joined-up
-- map (the map underneath changes on the way): a mark must stay the size it is and stay there. Prints every frame
-- where the sizes or the number shown changed.
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene = require("widgets"), require("sim"), require("scene")
local mapcost = require("mapcost")
setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(2548, 0.794, 0.527)
local accepted = mapcost.trackZoneQuests(accept, 8)
local addon = require("addons").byName["onemorequest"].private
wait(2)
local map = G.WorldMapFrame
key("M")
wait(4)
local world = addon.MapMarksWorld.worlds[map]
local view = W.computeRect(map.ScrollContainer)
local function read()
    local least, most, count = math.huge, 0, 0
    for tile in pairs(world.shownTiles) do
        local frame = tile.frame
        if frame and frame:IsVisible() then
            local scale = frame:GetEffectiveScale()
            for index = 1, #tile.points do
                local glyph = frame.glyphs[index]
                if glyph and glyph:IsShown() then
                    local rect = W.computeRect(glyph)
                    if
                        rect
                        and rect[3] >= view[1]
                        and rect[1] <= view[3]
                        and rect[4] >= view[2]
                        and rect[2] <= view[4]
                    then
                        local size = glyph:GetWidth() * scale
                        least, most, count = math.min(least, size), math.max(most, size), count + 1
                    end
                end
            end
        end
    end
    return count, count > 0 and least or 0, most
end
local cx, cy = (view[1] + view[3]) / 2 - 120, sim.screenHeight - (view[2] + view[4]) / 2 + 40
scene.input({ type = "move", x = cx, y = cy })
local function zoom(label, delta, notches)
    print("== " .. label)
    local lastText
    local frame = 0
    local function tick(count)
        for _ = 1, count do
            sim.tick(0.016)
            frame = frame + 1
            local count_, least, most = read()
            local text = string.format("%3d in view, %.1f to %.1f px", count_, least, most)
            if text ~= lastText then
                print(
                    string.format(
                        "   frame %3d  map %s zoom %.2f  %s",
                        frame,
                        tostring(map:GetMapID()),
                        map:GetCanvasScale(),
                        text
                    )
                )
                lastText = text
            end
        end
    end
    for _ = 1, notches do
        scene.input({ type = "wheel", x = cx, y = cy, delta = delta })
        tick(12)
    end
    tick(150)
end
zoom("wheel in x4", 1, 4)
zoom("wheel out x6", -1, 6)
zoom("wheel in x3", 1, 3)
