--@login race=Tauren,class=WARRIOR,level=14
-- CurseForge gallery shot: minimap
local W, sim = require("widgets"), require("sim")
-- Prints the part of the screen a gallery shot shows: round the frames given, with a margin (src/cli/shots.ts crops to it)
local function crop(name, frames, margin, extraTop)
    local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
    for _, frame in ipairs(frames) do
        if frame and frame:IsVisible() then
            local rect = W.computeRect(frame)
            left, right = math.min(left, rect[1]), math.max(right, rect[3])
            top, bottom = math.min(top, sim.screenHeight - rect[4]), math.max(bottom, sim.screenHeight - rect[2])
        end
    end
    margin = margin or 10
    left, top = math.max(0, math.floor(left - margin)), math.max(0, math.floor(top - margin - (extraTop or 0)))
    right, bottom =
        math.min(sim.screenWidth, math.ceil(right + margin)), math.min(sim.screenHeight, math.ceil(bottom + margin))
    print(string.format("CROP\t%s\t%d,%d,%d,%d", name, left, top, right - left, bottom - top))
    saveScene(name)
end
local addon = require("addons").byName["onemorequest"].private
setProfile({ level = 14 })
moveTo(1413, 0.49, 0.27) -- The Barrens, among the quests north-west of the Crossroads
for _, questId in ipairs({ 844, 869, 855, 870 }) do
    accept(questId)
end
complete(869)
wait(1.5)
addon.Focus.set(869) -- its turn-in off the minimap: the arrow on the rim
zoomMinimap(0)
wait(1)
crop("minimap", { G.MinimapCluster or G.Minimap, G.TrailheadTracker }, 8)
