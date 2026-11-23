--@login race=Tauren,class=WARRIOR,level=12
-- CurseForge gallery shot: chronicle
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
    right, bottom = math.min(sim.screenWidth, math.ceil(right + margin)), math.min(sim.screenHeight, math.ceil(bottom + margin))
    print(string.format("CROP\t%s\t%d,%d,%d,%d", name, left, top, right - left, bottom - top))
    saveScene(name)
end
local addon = require("addons").byName["onemorequest"].private
setProfile({ level = 12 })
moveTo(1412, 0.47, 0.6) -- Mulgore
-- A day of questing: taken, done and handed in
for _, questId in ipairs({ 747, 750, 761, 743, 766, 745, 767, 3376, 744, 748 }) do
    accept(questId)
    for _ = 1, 4 do kill(2955) end -- Plainstriders on the way
    for _ = 1, 3 do kill(2958) end -- Prairie Wolves
    complete(questId)
    wait(20) -- a little time between quests
    turnIn(questId)
end
accept(749)
wait(1.5)
key("M")
wait(1)
addon.Log.toggleChronicle()
for index, chapter in ipairs({ "glance" }) do
    addon.ChroniclePage.chapterIndex = index
    addon.Log.refresh()
    wait(1)
    crop("chronicle", { G.TrailheadLog }, 6, 26)
end
-- The journal: every quest handed in, day by day, with its search and filters
addon.ChroniclePage.chapterIndex = 3
addon.Log.refresh()
wait(1)
crop("journal", { G.TrailheadLog }, 6, 26)
