local _, ns = ...

-- WoWF.cz (folder WowfCZ, wowf.cz): Czech quest texts and voice for WoW: Forever. Its public API (WowfCZ.API) is
-- about the voice only, so OneMoreQuest reads what the addon keeps for everyone to see: its quest translations,
-- WowfCZ_QuestData[questId] = { Title, Description, Objective }, and its settings, WowfCZ_DB, which decide as
-- they decide for the addon itself: switched off, or a part set to English in /wowf, and that part stays English.
-- Its objective lines follow the addon's own rules, so OneMoreQuest's tracker reads as its tracker does.

local function getData(questId)
    local data = type(_G.WowfCZ_QuestData) == "table" and _G.WowfCZ_QuestData[questId]
    return type(data) == "table" and data or nil
end

local function getSettings()
    return type(_G.WowfCZ_DB) == "table" and _G.WowfCZ_DB or {}
end

-- Its parts, as the addon reads them: each is Czech unless set to "en"
local function isTitleCzech()
    return getSettings().titleLang ~= "en"
end
local function isTextCzech()
    return getSettings().questText ~= "en"
end
local function isObjectivesCzech()
    local settings = getSettings()
    return (settings.questObjectives or settings.questText) ~= "en" -- without its own choice, as the quest text
end

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

---Fills in the addon's placeholders as it does: $N name, $C class, $R race, $B a new line, $Gmale:female;
local function expand(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end
    local name = UnitName and UnitName("player") or ""
    local race = UnitRace and UnitRace("player") or ""
    local class = UnitClass and UnitClass("player") or ""
    local voice = _G.WowfCZVoice
    local isFemale = UnitSex and UnitSex("player") == 3
    if type(voice) == "table" and type(voice.PlayerFemale) == "function" then
        local isFine, answer = pcall(voice.PlayerFemale) -- its "address me as" choice
        if isFine and answer ~= nil then
            isFemale = answer == true
        end
    end
    text = text:gsub("%$[Gg]([^:;]*):([^;]*);", function(male, female)
        return trim(isFemale and female or male)
    end)
    text = text:gsub("%$N", name):gsub("%$n", name:lower()):gsub("%$[Bb]", "\n")
        :gsub("%$R", race):gsub("%$r", race:lower()):gsub("%$C", class):gsub("%$c", class:lower())
    return text
end

---Splits an objective's line as the addon does: "4/10 Bandit slain" or "Wolf Fang: 3/12" into its label and count
local function splitObjective(text)
    local body = text:match("^%s*(.-)%s*$")
    local count, label = body:match("^(%d+%s*/%s*%d+)%s+(.+)$")
    if not count then
        label, count = body:match("^(.-):%s*(%d+%s*/%s*%d+)$")
    end
    return label or body, count
end

-- Its narration: the addon's player (WowfCZVoice), as its own speaker buttons by quests use it. That player is not
-- its public interface (WowfCZ.API only tells what plays), so each function is looked for, and without any of them
-- there is no narration here.
local VOICE_FUNCTIONS = { "Enabled", "Listen", "FirstClip", "QuestState", "PlayQuestNow", "QueueQuest", "StopQuest" }

local function getPlayer()
    local player = _G.WowfCZVoice
    if type(player) ~= "table" then
        return nil
    end
    for _, name in ipairs(VOICE_FUNCTIONS) do
        if type(player[name]) ~= "function" then
            return nil
        end
    end
    return player
end

---@type QuestVoice
local voice = {
    isOn = function()
        local player = getPlayer()
        return player ~= nil and player.Enabled() == true
    end,
    start = function(onChange)
        getPlayer().Listen(onChange)
    end,
    hasRecording = function(questId)
        return getPlayer().FirstClip(questId) ~= nil
    end,
    getState = function(questId)
        local state, position = getPlayer().QuestState(questId)
        return state or "idle", position
    end,
    play = function(questId)
        getPlayer().PlayQuestNow(questId)
    end,
    queue = function(questId)
        getPlayer().QueueQuest(questId)
    end,
    stop = function(questId)
        getPlayer().StopQuest(questId)
    end,
}

ns.QuestText.register({
    name = "WowfCZ",
    label = "WoWF.cz",
    language = "cs", -- used only while OneMoreQuest speaks Czech
    about = "Czech quest titles, objectives and stories, and its Czech narration: Play and Queue on the quest page.",
    voice = voice,

    detect = function()
        return ns.isAddOnLoaded("WowfCZ") and type(_G.WowfCZ_QuestData) == "table"
    end,

    start = function() end, -- it announces no changes; getSettingsKey notices them

    isOn = function()
        return getSettings().enabled ~= false
    end,

    getSettingsKey = function()
        local settings = getSettings()
        return table.concat({ tostring(settings.enabled), tostring(settings.titleLang), tostring(settings.questText),
            tostring(settings.questObjectives), tostring(settings.addressSex) }, ",")
    end,

    getTitle = function(questId)
        local data = isTitleCzech() and getData(questId)
        return data and expand(data.Title)
    end,

    getObjective = function(questId, text, _, _, kind, objectiveCount)
        if not isObjectivesCzech() then
            return nil
        end
        local label, count = splitObjective(text)
        local data = getData(questId)
        local shown
        -- A quest with one objective and no count: its objective's sentence
        if not count and objectiveCount == 1 and data then
            shown = expand(data.Objective)
        end
        local person = label:match("^Speak with (.+)$") or label:match("^Speak to (.+)$")
        if not shown and person then
            shown = "Promluv si s " .. person:gsub("%.$", "") .. "."
        end
        if not shown and count then
            local creature = label:match("^(.-) slain$")
            if creature then
                shown = "Zabít " .. creature
            elseif kind == "item" then
                shown = "Získat " .. label
            end
        end
        if not shown then
            return nil
        end
        -- The count where the game puts it, so the line splits back the same way
        return count and (count .. " " .. shown) or shown
    end,

    getObjectives = function(questId)
        local data = isTextCzech() and getData(questId)
        return data and expand(data.Objective)
    end,

    getDescription = function(questId)
        local data = isTextCzech() and getData(questId)
        return data and expand(data.Description)
    end,
})
