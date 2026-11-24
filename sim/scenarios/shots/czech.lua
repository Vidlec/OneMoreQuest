--@login race=Scourge,class=MAGE,level=20
-- CurseForge gallery shot: czech
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
setProfile({ level = 20 })
moveTo(1413, 0.52, 0.30) -- The Barrens, Crossroads
-- WoWF.cz's real Czech quest titles and stories, from its own data file, as the game would load it
local wowfData = assert(loadfile([[R:\World of Warcraft\_forever_\Interface\AddOns\WowfCZ\Data\QuestData.lua]]))
setfenv(wowfData, G)
wowfData()
G.WowfCZ_DB = {}
local isLoaded = G.C_AddOns.IsAddOnLoaded
G.C_AddOns.IsAddOnLoaded = function(name)
    return name == "WowfCZ" or isLoaded(name)
end
addon.QuestText.start()
for _, questId in ipairs({ 869, 865, 872, 891, 870, 871 }) do
    accept(questId)
end
complete(869)
addon.Locale.setLanguage("cs")
wait(1.5)
key("M")
wait(1)
addon.Log.selectQuest(870)
wait(1)
crop("czech", { G.WorldMapFrame, G.TrailheadLog }, 6)
