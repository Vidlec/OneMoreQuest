--@login race=Scourge,class=MAGE,level=33
-- CurseForge gallery shot: party
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
setProfile({ level = 33 })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1113) -- Hearts of Zeal
accept(1153)
wait(0.5)
joinParty({ name = "Garra", class = "HUNTER", level = 32 })
joinParty({ name = "Brakka Stone", class = "WARRIOR", level = 34, addon = "none" })
wait(1.5)
memberAccept("Garra", 1113)
memberAccept("Brakka Stone", 1113)
memberProgress("Garra", 1113, 1, 4)
memberProgress("Brakka Stone", 1113, 1, 2)
progress(1113, 1, 3)
wait(2)
addon.Focus.set(1113) -- the focused quest shows the party under its title
wait(1)
crop("party", { G.TrailheadTracker }, 12)
