local _, ns = ...

-- Questie, the addon OneMoreQuest grew out of, also draws quest marks and runs a tracker: with both on, everything
-- shows twice. Once, a few seconds after logging in, the player is asked whether to turn Questie off. QuestieDB,
-- which OneMoreQuest needs, stays on either way.
local QUESTIE_POPUP = "ONE_MORE_QUEST_QUESTIE"

local function disableQuestie()
    if C_AddOns and C_AddOns.DisableAddOn then
        C_AddOns.DisableAddOn("Questie") -- for every character; the game's AddOns list can turn it back on
    elseif DisableAddOn then
        DisableAddOn("Questie")
    end
end

local Questie = {
    name = "Questie",
    label = "Questie",
    about = "Draws the same quest marks and tracker, so you would see everything twice: OneMoreQuest asks once whether to turn it off.",
}

---@return boolean isAsking The question is to be shown: Questie is on and the player has not answered
function Questie.shouldAsk()
    return not ns.settings.hasAnsweredQuestie and ns.Compatibility.isAddOnLoaded("Questie")
end

function Questie.ask()
    if not Questie.shouldAsk() or not StaticPopupDialogs or not StaticPopup_Show then
        return
    end
    StaticPopupDialogs[QUESTIE_POPUP] = {
        text = ns.L(
            "%s: Questie is running too. Both put quest marks on the map and show a quest tracker, "
                .. "so you would see everything twice.\n\nTurn Questie off? QuestieDB stays on; %s needs it.",
            ns.ADDON_TITLE,
            ns.ADDON_TITLE
        ),
        button1 = ns.L("Turn off and reload"),
        button2 = ns.L("Keep both"),
        OnAccept = function()
            ns.settings.hasAnsweredQuestie = true
            Questie.importHistory() -- its journey kept before its saved data is gone with it
            disableQuestie()
            ReloadUI()
        end,
        OnCancel = function(_, _, reason)
            -- Only the button is an answer; Escape or another popup pushing this one away asks again next time
            if reason == "clicked" then
                ns.settings.hasAnsweredQuestie = true
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show(QUESTIE_POPUP)
end

-- Questie's journey: every quest the character accepted, completed or abandoned, and each level reached, with when
-- and at what level, kept by Questie for each character (QuestieConfig.char["Name - Realm"].journey). A history for
-- the chronicle (History) from before OneMoreQuest kept one. As Questie's saved data is there only while Questie is
-- on, what it holds is copied into the chronicle's book (imported.Questie) whenever it is: kept once Questie is
-- turned off, as the question below offers. Only when and at what level: Questie keeps no experience or money.

---@return table? journey Questie's journey for this character, while Questie is on
local function readJourney()
    local config = _G.QuestieConfig
    if type(config) ~= "table" or type(config.char) ~= "table" then
        return nil
    end
    -- Questie's AceDB keys a character as Forever names it, "Name Surname" (or "Name" without one); elsewhere
    -- "Name - Realm"
    local readName = UnitNameUnmodified or UnitName
    if not readName then
        return nil
    end
    local name, surname = readName("player") -- (called alone: an "and" would keep only the name)
    local realm = GetRealmName and GetRealmName()
    if not name then
        return nil
    end
    for _, key in ipairs({
        surname and surname ~= "" and name .. " " .. tostring(surname) or name,
        realm and name .. " - " .. realm,
        name,
    }) do
        local character = key and config.char[key]
        local journey = type(character) == "table" and character.journey
        if type(journey) == "table" then
            return journey
        end
    end
    return nil
end

---Copies Questie's journey into the chronicle's book, as quest IDs, times and levels: what the history needs.
function Questie.importHistory()
    local journey = readJourney()
    if not journey then
        return
    end
    local completions, levelUps, accepted = {}, {}, {}
    for _, step in ipairs(journey) do
        if type(step) == "table" and type(step.Timestamp) == "number" then
            if step.Event == "Quest" and type(step.Quest) == "number" then
                if step.SubType == "Accept" then
                    accepted[step.Quest] = step
                elseif step.SubType == "Complete" then
                    local accept = accepted[step.Quest]
                    -- { quest, handed in, level then, accepted, level then }
                    completions[#completions + 1] =
                        { step.Quest, step.Timestamp, step.Level, accept and accept.Timestamp, accept and accept.Level }
                    accepted[step.Quest] = nil
                end
            elseif step.Event == "Level" and type(step.NewLevel) == "number" then
                levelUps[#levelUps + 1] = { step.NewLevel, step.Timestamp }
            end
        end
    end
    local book = ns.Chronicle.getBook()
    book.imported = book.imported or {}
    book.imported.Questie = { completions = completions, levelUps = levelUps, at = ns.Chronicle.getNow() }
    ns.History.invalidate()
end

ns.History.registerProvider({
    name = "Questie",
    order = 20,
    isAvailable = function()
        local imported = ns.Chronicle.getBook().imported
        return type(imported) == "table" and type(imported.Questie) == "table"
    end,
    getCompletions = function()
        local records = {}
        for _, kept in ipairs(ns.Chronicle.getBook().imported.Questie.completions or {}) do
            records[#records + 1] = ns.Chronicle.readAsEntry({
                questId = kept[1],
                turnedInAt = kept[2],
                playerLevel = kept[3],
                acceptedAt = kept[4],
                acceptedLevel = kept[5],
            })
        end
        return records
    end,
    getLevelUps = function()
        local ups = {}
        for _, kept in ipairs(ns.Chronicle.getBook().imported.Questie.levelUps or {}) do
            ups[#ups + 1] = { level = kept[1], at = kept[2] }
        end
        return ups
    end,
})

-- Once settled after logging in: its journey copied (again, as it grows), then the question about turning it off
Questie.onLoginSettled = function()
    Questie.importHistory()
    Questie.ask()
end

---Questie can tell the group when an objective is done, as OneMoreQuest can: while its own announcing is on, the
---news is left to it, so nothing is said twice. Its "completed" is the hand-in, which OneMoreQuest does not tell.
function Questie.announces(kind)
    local isRead, profile = pcall(function()
        return _G.Questie.db.profile
    end)
    if not isRead or type(profile) ~= "table" then
        return false
    end
    local channel = profile.questAnnounceChannel
    if channel == nil or channel == "disabled" or profile.questieShutUp then
        return false
    end
    return kind == "objective" and profile.questAnnounceObjectives == true
end

ns.Compatibility.register(Questie)
