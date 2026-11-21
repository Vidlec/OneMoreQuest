local _, ns = ...

-- Tells the group in chat, as Questie can: when an objective is done ("Packaged Tonics 1/1 for [Ward Restocking]")
-- and when a quest is ready to hand in. Off until the player switches it on (Settings, Tracker): chat said for
-- them should be their choice. Each line starts with the raid star and the addon's name, so it reads as automatic.
-- Only progress seen happen is told: the quest log as found at login, or a quest just taken that is already done,
-- says nothing. A quest made ready by its last objective says only that it is ready. Playing alone, the lines can
-- be shown in the player's own chat window instead (shouldAnnounceSolo); nothing is sent then.
local Announce = {}
ns.Announce = Announce

local MARKER = "{rt1} "
local lastSeen -- [questId] = { isReady = boolean, finished = { [objectiveIndex] = boolean } }; nil until the first look

---@return string? channel The group's chat: "RAID", "INSTANCE_CHAT" or "PARTY"; nil outside a group
function Announce.getChannel()
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    end
    if IsInGroup and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function send(message)
    local channel = Announce.getChannel()
    if not channel then
        if ns.settings.shouldAnnounceSolo and DEFAULT_CHAT_FRAME then
            -- Only for the player: the chat window shows the star as text, so the line starts with the name alone
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. ns.ADDON_TITLE .. ":|r " .. message)
        end
        return
    end
    local text = MARKER .. ns.ADDON_TITLE .. ": " .. message
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, channel)
    elseif SendChatMessage then
        SendChatMessage(text, channel)
    end
end

local function getQuestLink(quest)
    return ns.QuestState.getChatLink(quest.questId) or ("[" .. (quest.englishTitle or quest.title or "?") .. "]")
end

---@return string line An objective as told: its name and count as the game words it, "Packaged Tonics 1/1"
function Announce.composeObjectiveText(objective)
    local label = objective.label or objective.text or ""
    if (objective.required or 0) > 1 or objective.type == "item" or objective.type == "monster" then
        return string.format("%s %d/%d", label, objective.fulfilled or 0, objective.required or 0)
    end
    return label
end

---@return boolean isTold Another addon already tells the group this kind of news (Questie's own announcements)
local function isToldElsewhere(kind)
    return ns.Compatibility.isAnnouncedByAddOn(kind)
end

---Looks at the quest log again and tells the group what moved since the last look.
function Announce.check()
    local isFirstLook = lastSeen == nil
    local seen = {}
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        local quest = ns.QuestState.getQuest(questId)
        local isReady = quest.isComplete == true
        local before = lastSeen and lastSeen[questId]
        local finished = {}
        local newlyDone = {}
        for index, objective in ipairs(quest.objectives) do
            finished[index] = objective.isFinished == true
            if before and finished[index] and before.finished[index] == false then
                newlyDone[#newlyDone + 1] = objective
            end
        end
        seen[questId] = { isReady = isReady, finished = finished }
        if before and not isFirstLook then
            if isReady and not before.isReady then
                if ns.settings.shouldAnnounceReady and not isToldElsewhere("ready") then
                    send(ns.L("%s is ready to hand in", getQuestLink(quest)))
                end
            elseif ns.settings.shouldAnnounceObjectives and not isToldElsewhere("objective") then
                for _, objective in ipairs(newlyDone) do
                    send(ns.L("%s for %s", Announce.composeObjectiveText(objective), getQuestLink(quest)))
                end
            end
        end
    end
    lastSeen = seen
end

---Forgets what was seen, for tests.
function Announce.reset()
    lastSeen = nil
end

ns.registerModule({
    name = "Announce",
    changes = {
        -- Read every time the log changes, switched on or not, so switching it on never tells old news; it never
        -- needs a redraw of its own
        QUEST_LOG_UPDATE = function()
            Announce.check()
            return false
        end,
    },
})
