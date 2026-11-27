-- OneMoreQuest's party protocol, for AddonSim's simulated party members (a plugin: addonsim.config.ts "plugins").
-- A member running OneMoreQuest talks to the player's addon on its channel the way the addon itself does (Comms.lua):
--   joining:              "1|H" (hello) and its whole log, "1|L|1/1|<entries>"
--   a quest changed:      "1|U|<entry>"; dropped: "1|R|<questId>"
--   the player's hello:   its whole log again, whispered
--   the player's "1|Q|<questId>" (who did this quest, or could take it): members not on it answer, whispered,
--                         "1|S|<questId>|d||" when they handed it in, else "1|S|<questId>|c||"
-- An entry is "<questId>:<fulfilled>/<required>,...:<1 when complete, else 0>". Members joining without an addon
-- named run OneMoreQuest (isDefault), as in the project's scenarios.
local plugins = require("plugins")

local PREFIX = "OneMoreQuest"

local function composeEntry(questId, quest)
    local counts = {}
    for index, objective in ipairs(quest.objectives) do
        counts[index] = string.format("%d/%d", objective.fulfilled, objective.required)
    end
    return string.format("%d:%s:%d", questId, table.concat(counts, ","), quest.isComplete and 1 or 0)
end

local function sendLog(member, channel)
    if not member.isOnline then
        return
    end
    local entries = {}
    for questId, quest in pairs(member.quests) do
        entries[#entries + 1] = composeEntry(questId, quest)
    end
    table.sort(entries)
    plugins.sendFromMember(member, PREFIX, "1|L|1/1|" .. table.concat(entries, ";"), channel or "PARTY")
end

local function hasDone(member, questId)
    for _, doneQuestId in ipairs(member.doneQuestIds) do
        if doneQuestId == questId then
            return true
        end
    end
    return false
end

plugins.registerPartyAddon("OneMoreQuest", {
    label = "OneMoreQuest",
    note = "Sends exact counts on its channel, in dungeons too",
    color = "accent",
    isDefault = true,
    onJoin = function(member)
        plugins.sendFromMember(member, PREFIX, "1|H", "PARTY")
        sendLog(member, "PARTY")
    end,
    onQuestChanged = function(member, questId)
        local quest = member.quests[questId]
        plugins.sendFromMember(
            member,
            PREFIX,
            quest and ("1|U|" .. composeEntry(questId, quest)) or ("1|R|" .. questId),
            "PARTY",
            0.1
        )
    end,
    onMessage = function(member, message)
        if message.prefix ~= PREFIX then
            return
        end
        local askedQuestId = tonumber(message.text:match("^1|Q|(%d+)$"))
        if askedQuestId and not member.quests[askedQuestId] then
            local answer = hasDone(member, askedQuestId) and "d" or "c"
            plugins.sendFromMember(member, PREFIX, string.format("1|S|%d|%s||", askedQuestId, answer), "WHISPER", 0.1)
        elseif message.text == "1|H" then
            sendLog(member, "WHISPER")
        end
    end,
})
