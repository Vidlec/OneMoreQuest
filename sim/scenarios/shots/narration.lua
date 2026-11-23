--@login race=Scourge,class=MAGE,level=20
-- CurseForge gallery shot: narration
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
setProfile({ level = 20 })
moveTo(1413, 0.52, 0.30) -- The Barrens, Crossroads
-- A stand-in for Spoken's player (Spoken itself does not run in the simulator): OneMoreQuest's controls are its own
local queue, listeners = {}, {}
local function changed() for _, listener in ipairs(listeners) do listener() end end
G.Spoken = {
    IsCompatible = function(_, version) return version <= 1 end,
    GetQueue = function() return queue end, GetCurrent = function() return queue[1] end,
    GetNowPlaying = function() return queue[1] end, IsPaused = function() return false end,
    RegisterCallback = function(_, event, callback) if event == "AUDIO_CHANGED" then listeners[#listeners + 1] = callback end end,
}
G.VoiceOver = {
    Enums = { SoundEvent = { QuestAccept = 1 }, GUID = { CanHaveID = function() return true end, IsCreature = function() return true end } },
    Addon = { IsPartOn = function() return true end },
    Utils = { MakeGUID = function() return nil end },
    DataModules = { PrepareSound = function() return true end, GetQuestLogQuestGiverTypeAndID = function() return nil end, GetObjectName = function() return nil end },
    QuestOverlayUI = { QueuedLine = function(_, questId) for _, clip in ipairs(queue) do if clip.questID == questId then return clip end end end },
    Player = { PlayNow = function(_, line) table.insert(queue, 1, line) changed() end,
        Enqueue = function(_, line) queue[#queue + 1] = line changed() end, Remove = function() end },
}
local isLoaded = G.C_AddOns.IsAddOnLoaded
G.C_AddOns.IsAddOnLoaded = function(name) return name == "Spoken_Quests" or isLoaded(name) end
addon.QuestText.start()
for _, questId in ipairs({ 869, 865, 872, 891, 870, 871 }) do accept(questId) end
wait(1.5)
key("M")
wait(1)
addon.Log.selectQuest(891)
addon.QuestText.toggleVoiceQueue(870)
addon.QuestText.toggleVoice(891)
wait(1)
crop("narration", { G.TrailheadLog }, 6, 26)
