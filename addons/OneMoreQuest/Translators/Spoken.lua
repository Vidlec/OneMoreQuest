local _, ns = ...

-- Spoken (folders Spoken and Spoken_Quests, spoken.quest): English voice-over of quests for WoW: Forever, played in
-- Spoken's own player and queue. A narration only: the quest texts stay the game's.
--
-- Spoken's public interface (the global Spoken, API version 1) tells what plays, what waits and when that changes;
-- playing a quest is Spoken_Quests' own, done here exactly as its quest log's Play button does it, through the
-- environment its voice packs also call into (the global VoiceOver). Each part is looked for, and without any of
-- them there is no narration here.
local API_VERSION = 1
local PARTS = { "QuestOverlayUI", "DataModules", "Player", "Enums", "Addon", "Utils" }

local recordings = {} -- [questId] = whether a voice pack voices the quest; asked again once the packs have loaded

---@return table? quests Spoken_Quests' environment, when it and Spoken have what is used here
---@return table? spoken
local function getParts()
    local quests, spoken = _G.VoiceOver, _G.Spoken
    if
        type(quests) ~= "table"
        or type(spoken) ~= "table"
        or type(spoken.IsCompatible) ~= "function"
        or not spoken:IsCompatible(API_VERSION)
    then
        return nil
    end
    for _, name in ipairs(PARTS) do
        if type(rawget(quests, name)) ~= "table" then
            return nil
        end
    end
    local soundEvents = type(quests.Enums.SoundEvent) == "table" and quests.Enums.SoundEvent
    if
        not (
            soundEvents
            and soundEvents.QuestAccept
            and quests.QuestOverlayUI.QueuedLine
            and quests.DataModules.PrepareSound
            and quests.Player.PlayNow
            and quests.Player.Enqueue
            and quests.Player.Remove
            and quests.Addon.IsPartOn
            and spoken.GetQueue
            and spoken.GetCurrent
            and spoken.GetNowPlaying
            and spoken.IsPaused
            and spoken.RegisterCallback
        )
    then
        return nil
    end
    return quests, spoken
end

---A quest's accept line, as Spoken_Quests' Play button asks for it: the giver's voice where its data knows the giver.
local function makeLine(quests, questId)
    local line = {
        event = quests.Enums.SoundEvent.QuestAccept,
        questID = questId,
        name = "Unknown Name",
        title = ns.Database.getQuestField(questId, "name"),
        origin = "OneMoreQuest",
    }
    local isFound, giverType, giverId =
        pcall(quests.DataModules.GetQuestLogQuestGiverTypeAndID, quests.DataModules, questId)
    if isFound and giverId then
        local guid = quests.Enums.GUID
        line.name = quests.DataModules:GetObjectName(giverType, giverId) or line.name
        line.unitGUID = guid and guid:CanHaveID(giverType) and quests.Utils:MakeGUID(giverType, giverId) or nil
        line.unitIsObjectOrItem = guid and not guid:IsCreature(giverType) or false
    end
    return line
end

---@type QuestVoice
local voice = {
    isOn = function()
        local quests = getParts()
        return quests ~= nil and quests.Addon:IsPartOn() == true
    end,
    start = function(onChange)
        local _, spoken = getParts()
        spoken:RegisterCallback("AUDIO_CHANGED", onChange)
        spoken:RegisterCallback("VOICE_PACKS_LOADED", function()
            recordings = {}
            onChange()
        end)
    end,
    hasRecording = function(questId)
        if recordings[questId] == nil then
            local quests = getParts()
            local line = { event = quests.Enums.SoundEvent.QuestAccept, questID = questId }
            local isFine, isFound = pcall(quests.DataModules.PrepareSound, quests.DataModules, line)
            recordings[questId] = isFine and isFound and true or false
        end
        return recordings[questId]
    end,
    getState = function(questId)
        local quests, spoken = getParts()
        local clip = quests.QuestOverlayUI:QueuedLine(questId)
        if not clip then
            return "idle"
        end
        local current = spoken:GetCurrent()
        if current == clip then
            if spoken:IsPaused() then
                return "paused"
            end
            return spoken:GetNowPlaying() == clip and "playing" or "queued", 1
        end
        -- Its place among the lines waiting behind the one speaking
        for index, queued in ipairs(spoken:GetQueue()) do
            if queued == clip then
                return "queued", current and index - 1 or index
            end
        end
        return "idle"
    end,
    -- As Spoken's own Play: at once when nothing speaks, else straight after the line speaking
    play = function(questId)
        local quests, spoken = getParts()
        local clip = quests.QuestOverlayUI:QueuedLine(questId)
        if clip and spoken:GetCurrent() == clip and spoken:IsPaused() then
            spoken:TogglePause() -- stopped at the head: replayed
        elseif clip and quests.Player.source then
            quests.Player.source:PlayNow(clip) -- waiting: brought forward
        elseif not clip then
            quests.Player:PlayNow(makeLine(quests, questId))
        end
    end,
    queue = function(questId)
        local quests = getParts()
        quests.Player:Enqueue(makeLine(quests, questId), true) -- asked for, so read in a battleground too
    end,
    stop = function(questId)
        local quests = getParts()
        local clip = quests.QuestOverlayUI:QueuedLine(questId)
        if clip then
            quests.Player:Remove(clip)
        end
    end,
}

ns.QuestText.register({
    name = "Spoken",
    label = "Spoken",
    language = "en", -- used only while OneMoreQuest speaks English
    about = "English narration of quests in Spoken's queue: Play and Queue on the quest page.",
    detect = function()
        return ns.isAddOnLoaded("Spoken_Quests") and getParts() ~= nil
    end,
    voice = voice,
})
