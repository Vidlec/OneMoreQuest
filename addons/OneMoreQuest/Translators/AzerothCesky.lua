local _, ns = ...

-- Azeroth česky (folder AzerothCesky): Czech quest texts for WoW: Forever. It offers them to other quest addons
-- through its public interface, AzerothCeskyAPI.GetInterface(1): a quest's title, its objectives' lines and its
-- map texts, each checked against the English the game shows, so a text it does not know is not guessed.
-- Its own settings decide: switched off, its tracker translation off or its quest titles set to English, it
-- answers nothing and the English stays.
local API_VERSION = 1

local api -- the interface, once found
local isOn = false -- from its state: ready and translating the quest texts companions ask for

local function readState(state)
    isOn = type(state) == "table" and state.ready == true and state.canTranslateTracker == true
end

---@return string? text Its translation, when the answer is one
local function getText(result)
    if type(result) == "table" and result.kind == "translated" and type(result.text) == "string" then
        return result.text
    end
    return nil
end

ns.QuestText.register({
    name = "AzerothCesky",
    label = "Azeroth česky",
    language = "cs", -- used only while OneMoreQuest speaks Czech
    about = "Czech quest titles and objectives, in every OneMoreQuest window.",

    detect = function()
        local entry = _G.AzerothCeskyAPI
        if not ns.isAddOnLoaded("AzerothCesky") or type(entry) ~= "table" or type(entry.GetInterface) ~= "function" then
            return false
        end
        local found = entry.GetInterface(API_VERSION)
        if type(found) ~= "table" or type(found.ResolveQuestTitle) ~= "function" then
            return false
        end
        api = found
        return true
    end,

    start = function(onChange)
        readState(api.GetState and api.GetState())
        -- Its settings, readiness or claims changed: its answers may have too
        if api.Subscribe then
            api.Subscribe(function(event)
                readState(event and event.state)
                onChange()
            end)
        end
    end,

    isOn = function()
        return isOn
    end,

    getTitle = function(questId, english, isInLog)
        -- A quest in the log is read from the game by the addon itself; one not taken yet is matched by its English
        local text = isInLog and getText(api.ResolveQuestTitle(questId))
        return text or getText(api.ResolveQuestMapField(questId, "title", english))
    end,

    getObjective = function(questId, text, fulfilled, required)
        return getText(api.ResolveTrackerObjective(questId, text, fulfilled, required))
    end,

    getObjectives = function(questId, english)
        return getText(api.ResolveQuestMapField(questId, "objectives", english))
    end,
})
