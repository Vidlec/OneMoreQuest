local _, ns = ...

-- The quest in focus: the one the player picked to follow, shown in full in the tracker, opened in the quest log and
-- standing out on the map. It is the game's own focus too (its super-tracked quest, with the game's arrow): either
-- changing it changes both. Remembered per character, for a login without the game's.
--
-- The windows only show it: they ask Focus.get() and follow FOCUS_CHANGED. Focus also tells them when a quest
-- leaves the log or is untracked (QUEST_GONE), so each lets go of it.
local Focus = {}
ns.Focus = Focus

local pickedQuestId -- the quest the player put in focus; kept even while it cannot be shown (not tracked yet)
local formerQuestId, changedAt -- the quest in focus before the last change, and when that change was
local acceptedQuestId, acceptedAt -- the quest last accepted, and when, while the game may still put it in focus

-- How long after a quest is accepted the game putting it in focus counts as the game's doing (it does so as the
-- quest is accepted or as it is tracked, a moment later), not the player's
local ACCEPT_SECONDS = 2

local function getNow()
    return GetTime and GetTime() or 0
end

---@return number? questId The quest the game has in focus, when it is one in the log (not a map waypoint)
local function getGameFocus()
    local questId = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
    return questId and questId > 0 and ns.QuestState.isInLog(questId) and questId or nil
end

---@return string key The player's character, for what each character keeps of its own
local function getCharacterKey()
    local name = UnitName and UnitName("player") or "?"
    local realm = GetRealmName and GetRealmName() or "?"
    return tostring(name) .. "-" .. tostring(realm)
end

---@return number? questId The quest the player picked, whether or not it can be shown right now
function Focus.getPicked()
    return pickedQuestId
end

---@return number? questId The quest in focus: the one picked, while it is tracked; nil when none is
function Focus.get()
    if not pickedQuestId then
        return nil
    end
    for _, questId in ipairs(ns.QuestState.getWatchedQuestIds()) do
        if questId == pickedQuestId then
            return questId
        end
    end
    return nil
end

---The focus changes here and in the windows (FOCUS_CHANGED); the game's own is left as it is.
local function follow(questId)
    formerQuestId, changedAt = pickedQuestId, getNow()
    pickedQuestId = questId
    ns.settings.focusedQuestIds[getCharacterKey()] = questId
    ns.emit("FOCUS_CHANGED", questId)
end

---Puts a quest in focus, or none (nil): the game's focus follows, and so do the windows (FOCUS_CHANGED).
---Only for the player's own choices: setting the game's focus makes it update its tracker at once, inside this
---addon's code, where the game will not let it read the player's auras ("tainted by ForceTaint_Strong").
function Focus.set(questId)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        C_SuperTrack.SetSuperTrackedQuestID(questId or 0) -- 0 clears the game's arrow
    end
    follow(questId)
end

---The focus the game has (its super-tracked quest) wins, so a quest focused while this addon was off is kept; this
---addon's own memory of it is for when the game has none.
function Focus.create()
    pickedQuestId = getGameFocus() or ns.settings.focusedQuestIds[getCharacterKey()]
end

---The game's own focus changed (its quest log, its map, or another addon): this one follows, so both always agree.
---The game switching its arrow to a map waypoint (no quest) leaves the focus as it was.
local GAME_FOCUS_DELAY = 0.5 -- seconds

---With "Focus quests you accept" off: the focus goes back to the quest it was on (or none) at once; the game's arrow
---a moment later, outside the game's event (set inside one, the game updates its tracker in this addon's code, where
---reading the player's auras fails), and not in combat
local function keepFormer(keptQuestId)
    if keptQuestId and not ns.QuestState.isInLog(keptQuestId) then
        keptQuestId = nil
    end
    follow(keptQuestId)
    if C_Timer and C_Timer.After and ns.frameNumber > 0 then
        C_Timer.After(GAME_FOCUS_DELAY, function()
            local isInCombat = InCombatLockdown and InCombatLockdown()
            if not isInCombat and pickedQuestId == keptQuestId and getGameFocus() ~= keptQuestId
                and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(keptQuestId or 0)
            end
        end)
    end
end

---@return boolean isGames The game put a quest just accepted into focus, and the player wants it left out
local function isAcceptedFocus(questId)
    return ns.settings.shouldFocusAccepted == false and questId ~= nil and questId == acceptedQuestId
        and getNow() - (acceptedAt or 0) <= ACCEPT_SECONDS
end

function Focus.handleGameFocusChanged()
    local questId = getGameFocus()
    if questId and questId ~= Focus.get() then
        if isAcceptedFocus(questId) then
            keepFormer(pickedQuestId)
            return
        end
        follow(questId) -- the game has it already
    end
end

---A quest accepted: with "Focus quests you accept" off, the game putting it in focus is undone, whether it did so
---just before this (the focus followed it a moment ago) or does so in the next moments (handleGameFocusChanged)
function Focus.handleAccepted(questId)
    if ns.settings.shouldFocusAccepted ~= false or not questId then
        return
    end
    acceptedQuestId, acceptedAt = questId, getNow()
    if pickedQuestId == questId and changedAt and getNow() - changedAt <= ACCEPT_SECONDS then
        keepFormer(formerQuestId)
    end
end

---A quest untracked, by any means, or gone from the log: the windows let go of it, and the focus too if it was it.
---Gone from the log (turned in, abandoned), the game drops its own focus on it by itself; untracked but still in
---the log, the game's arrow is cleared here.
local function handleQuestGone(questId, isStillInLog)
    if questId == nil then
        return
    end
    ns.emit("QUEST_GONE", questId)
    if questId == pickedQuestId then
        if isStillInLog then
            Focus.set(nil)
        else
            follow(nil)
        end
    end
end

ns.registerModule({
    name = "Focus",
    create = Focus.create,
    events = {
        SUPER_TRACKING_CHANGED = Focus.handleGameFocusChanged,
        QUEST_ACCEPTED = function(questId, secondArg) Focus.handleAccepted(secondArg or questId) end,
        QUEST_WATCH_LIST_CHANGED = function(questId, isAdded)
            if isAdded == false then
                handleQuestGone(questId, ns.QuestState.isInLog(questId))
            end
        end,
        QUEST_REMOVED = function(questId) handleQuestGone(questId, false) end,
        QUEST_TURNED_IN = function(questId) handleQuestGone(questId, false) end,
    },
})
Focus.handleQuestGone = handleQuestGone
