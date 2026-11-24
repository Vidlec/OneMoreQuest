--@login race=Tauren,class=WARRIOR,level=14
-- CurseForge gallery shot: available
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
moveTo(1413, 0.52, 0.31) -- The Barrens, by the Crossroads
for _, questId in ipairs({ 869, 855 }) do
    accept(questId)
end
wait(1.5)
key("M")
wait(1)
addon.Log.showAvailable()
wait(1)
local quests = addon.Availability.getQuests(addon.Log.getAvailableZoneId())
addon.Log.showAvailable(quests[3] and quests[3].questId or quests[1].questId)
wait(1)
crop("available", { G.WorldMapFrame, G.TrailheadLog }, 6)
