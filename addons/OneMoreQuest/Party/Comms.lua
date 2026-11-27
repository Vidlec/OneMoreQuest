local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Quest progress shared with the group, on this addon's own channel of hidden addon messages. Each member
-- running OneMoreQuest sends their quest log's counts; the others keep them, per player and per quest, for the
-- party rows of the tracker and the quest page. The game's own party progress is withheld inside dungeons;
-- these counts are not. Messages are short text, versioned, so a newer format can be told apart:
--   "1|H"                        hello: the player just joined (or logged in, or reloaded) and sends their log to
--                                the group; each member answers with theirs, whispered to the newcomer alone
--   "1|U|questId:f/r,f/r:c"      one quest's counts (fulfilled/required per objective; c = 1 when complete)
--   "1|L|1/2|entry;entry;..."    the whole log, entries as above, in numbered parts under 250 characters
--   "1|R|questId"                a quest left the log
--   "1|Q|questId"                asks the group: who of you has done this quest, or could take it?
--   "1|S|questId|s|short|reason" the answer, whispered back: s = d (done it), c (can take it), n (can't, why)
--   "1|T|questId|s|short|reason" the same answer, its reasons as phrases each says in their own language (sent after
--                                "S", which older versions read): key~arg~arg, an arg q<questId>, n<number> or t<text>
-- Questie's own messages are read and sent by QuestieBridge, which keeps the counts here too.
local Comms = {}
ns.Comms = Comms

local PREFIX = "OneMoreQuest"
local VERSION = "1"
local MAX_MESSAGE_LENGTH = 250
local MAX_TOKENS = 8 -- messages sent at once before the rest wait, one a second, so the server never throttles them
local UPDATE_DELAY_SECONDS = 1 -- quest log changes come in bursts: they are sent together a moment later

local remoteQuests = {} -- [player] = { [questId] = { objectives = { fulfilled, required, isFinished }[], isComplete, time, source } }
local remoteStatuses = {} -- [player] = { [questId] = { state, reason, shortReason, time } }: their answers to "1|Q|"
local askedTimes = {} -- [questId] = when the group was last asked about it
local ASK_INTERVAL_SECONDS = 60 -- a quest's question goes out again at most this often
local STATUS_SECONDS = 300 -- an answer is kept this long: levels go up, quests get done
local STATE_LETTERS = { done = "d", can = "c", cannot = "n" }
local LETTER_STATES = { d = "done", c = "can", n = "cannot" }
local sentEntries = {} -- [questId] = the entry last sent, so only changes go out
local queue, tokens, isFlushScheduled = {}, MAX_TOKENS, false
local isUpdateScheduled = false
local knownMembers = {} -- [player] = true: the group as last seen, to notice who joins and who leaves
local answeredHellos = {} -- [player] = when their hello was last answered: a hello repeated at once gets no second log
local HELLO_ANSWER_SECONDS = 10
-- Where a message from the group can come: its own channels, and whispers (answers) from its members
local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }
local eventFrame

---@return string name A player's name as messages give it: without the realm for the player's own realm
local function normalizeName(name)
    if type(name) ~= "string" then
        return ""
    end
    if Ambiguate then
        return Ambiguate(name, "none")
    end
    return name
end
Comms.normalizeName = normalizeName

---@return string? channel Where messages to the whole group go: "RAID", "PARTY", "INSTANCE_CHAT"; nil when solo
function Comms.getGroupChannel()
    if not IsInGroup or not IsInGroup() then
        return nil
    end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) and not IsInGroup(LE_PARTY_CATEGORY_HOME or 1) then
        return "INSTANCE_CHAT"
    end
    return IsInRaid and IsInRaid() and "RAID" or "PARTY"
end

---@return table<string, boolean> members Everyone in the group but the player, by name
function Comms.getGroupMembers()
    local members = {}
    local isRaid = IsInRaid and IsInRaid()
    local count = isRaid and 40 or 4
    for index = 1, count do
        local unit = (isRaid and "raid" or "party") .. index
        if UnitExists and UnitExists(unit) then
            local name = GetUnitName and GetUnitName(unit, true) or UnitName(unit)
            if type(name) == "string" and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
                members[normalizeName(name)] = true
            end
        end
    end
    return members
end

---------------------------------------------------------------------------------------------------------------
-- Sending, paced

local function scheduleFlush(flush)
    if isFlushScheduled or not C_Timer then
        return
    end
    isFlushScheduled = true
    C_Timer.After(1, function()
        isFlushScheduled = false
        tokens = math.min(tokens + 1, MAX_TOKENS) -- one more message allowed each second
        flush()
    end)
end

local function flush()
    while tokens > 0 and #queue > 0 do
        local message = table.remove(queue, 1)
        tokens = tokens - 1
        local send = C_ChatInfo and C_ChatInfo.SendAddonMessage or SendAddonMessage
        if send then
            pcall(send, message.prefix, message.text, message.channel, message.target)
        end
    end
    if #queue > 0 then
        scheduleFlush(flush)
    elseif tokens < MAX_TOKENS then
        scheduleFlush(flush) -- keeps refilling until the allowance is whole again
    end
end

---Sends an addon message once the pace allows: a few at once, then one a second.
---@param channel string "PARTY", "RAID", "INSTANCE_CHAT" or "WHISPER"
---@param target string? The player, for a whisper
function Comms.queueMessage(prefix, text, channel, target)
    if not channel then
        return
    end
    queue[#queue + 1] = { prefix = prefix, text = text, channel = channel, target = target }
    flush()
end

---------------------------------------------------------------------------------------------------------------
-- The format

---@param quest { objectives: { fulfilled: number, required: number }[], isComplete: boolean }
---@return string entry "questId:f/r,f/r:c"
function Comms.composeEntry(questId, quest)
    local counts = {}
    for index, objective in ipairs(quest.objectives or {}) do
        counts[index] = string.format("%d/%d", objective.fulfilled or 0, objective.required or 0)
    end
    return string.format("%d:%s:%d", questId, table.concat(counts, ","), quest.isComplete and 1 or 0)
end

---@return number? questId, table? quest The quest's id and counts; nil for a malformed entry
function Comms.parseEntry(entry)
    local questText, countsText, completeText = (entry or ""):match("^(%d+):([%d/,]*):([01])$")
    local questId = tonumber(questText)
    if not questId then
        return nil
    end
    local objectives = {}
    for fulfilledText, requiredText in countsText:gmatch("(%d+)/(%d+)") do
        local fulfilled, required = tonumber(fulfilledText), tonumber(requiredText)
        objectives[#objectives + 1] = { fulfilled = fulfilled, required = required, isFinished = fulfilled >= required }
    end
    return questId, { objectives = objectives, isComplete = completeText == "1" }
end

---The whole log as messages, as many entries in each as fit.
---@param entries string[]
---@return string[] messages
function Comms.composeLogMessages(entries)
    local bodies, current = {}, nil
    local room = MAX_MESSAGE_LENGTH - 12 -- for "1|L|12/12|"
    for _, entry in ipairs(entries) do
        if current and #current + 1 + #entry > room then
            bodies[#bodies + 1] = current
            current = nil
        end
        current = current and (current .. ";" .. entry) or entry
    end
    bodies[#bodies + 1] = current or "" -- an empty log is still news: everything was dropped
    local messages = {}
    for index, body in ipairs(bodies) do
        messages[index] = string.format("%s|L|%d/%d|%s", VERSION, index, #bodies, body)
    end
    return messages
end

---@return string text A member's words shown as words: no escape codes of theirs, pictures or links, in our
---tooltips; "" for none
local function cleanReceivedReason(text)
    return type(text) == "string" and text:gsub("|", "/") or ""
end

---"S" and "T": a member's answer about a quest, its reasons as text ("S") or as phrases ("T").
local function parseStatusMessage(kind, body)
    local questText, letter, shortReason, reason = body:match("^(%d+)|(%l)|([^|]*)|?(.*)$")
    if kind == "T" then
        shortReason, reason = Comms.readPhrase(shortReason), Comms.readPhrase(reason)
    end
    shortReason, reason = cleanReceivedReason(shortReason), cleanReceivedReason(reason)
    local questId, state = tonumber(questText), LETTER_STATES[letter or ""]
    if not (questId and state) then
        return nil
    end
    return {
        kind = kind,
        questId = questId,
        state = state,
        shortReason = shortReason ~= "" and shortReason or nil,
        reason = reason ~= "" and reason or nil,
    }
end

---"U" and "L": one quest's counts, or a part of the whole log.
local function parseCountsMessage(kind, body)
    local part
    if kind == "L" then
        local partText, rest = body:match("^(%d+)/%d+|(.*)$")
        part, body = tonumber(partText), rest
        if not part then
            return nil
        end
    end
    local entries = {}
    for entry in body:gmatch("[^;]+") do
        entries[#entries + 1] = entry
    end
    return { kind = kind, entries = entries, part = part }
end

---"R" and "Q": a quest left the log, or a question about it.
local function parseQuestMessage(kind, body)
    local questId = tonumber(body)
    return questId and { kind = kind, questId = questId } or nil
end

local MESSAGE_PARSERS = {
    H = function(kind)
        return { kind = kind }
    end,
    R = parseQuestMessage,
    Q = parseQuestMessage,
    S = parseStatusMessage,
    T = parseStatusMessage,
    U = parseCountsMessage,
    L = parseCountsMessage,
}

---@return { kind: string, entries: string[]?, questId: number?, part: number? }? message What a message says; nil
---when it is of another version or malformed. A log's part says which of its messages it is, 1 for the first.
function Comms.parseMessage(text)
    local version, kind, body = (text or ""):match("^(%d+)|(%u)|?(.*)$")
    if version ~= VERSION then
        return nil
    end
    local parse = MESSAGE_PARSERS[kind]
    return parse and parse(kind, body) or nil
end

---------------------------------------------------------------------------------------------------------------
-- What the group has

---Keeps a member's counts for a quest.
---@param source string "OneMoreQuest" or "Questie": whose message brought them
function Comms.setRemoteQuest(player, questId, quest, source)
    player = normalizeName(player)
    remoteQuests[player] = remoteQuests[player] or {}
    quest.time, quest.source = GetTime and GetTime() or 0, source
    remoteQuests[player][questId] = quest
    if ns.queueRefresh then
        ns.queueRefresh()
    end
end

function Comms.removeRemoteQuest(player, questId)
    player = normalizeName(player)
    if remoteQuests[player] then
        remoteQuests[player][questId] = nil
        if ns.queueRefresh then
            ns.queueRefresh()
        end
    end
end

---@return { objectives: { fulfilled: number, required: number, isFinished: boolean }[], isComplete: boolean, time: number, source: string }? quest
---A member's counts for a quest, as their addon last sent them; nil when none came
function Comms.getRemoteQuest(player, questId)
    local quests = remoteQuests[normalizeName(player)]
    return quests and quests[questId] or nil
end

---@return { state: string, reason: string?, shortReason: string? }? status A member's own answer about a quest
---they are not on: "done", "can" or "cannot" and why; nil when none came lately
function Comms.getRemoteStatus(player, questId)
    local statuses = remoteStatuses[normalizeName(player)]
    local status = statuses and statuses[questId]
    if status and (GetTime and GetTime() or 0) - status.time > STATUS_SECONDS then
        return nil
    end
    return status
end

---Keeps a member's answer about a quest.
function Comms.setRemoteStatus(player, questId, status)
    player = normalizeName(player)
    remoteStatuses[player] = remoteStatuses[player] or {}
    status.time = GetTime and GetTime() or 0
    remoteStatuses[player][questId] = status
    if ns.queueRefresh then
        ns.queueRefresh()
    end
end

---@param phrase { key: string, args: any[] }? A reason as Availability phrases it
---@return string text It written for a message: key~arg~arg (Comms.readPhrase reads it back)
function Comms.writePhrase(phrase)
    if not phrase then
        return ""
    end
    local function clean(text)
        return (tostring(text):gsub("[|~]", "/"))
    end
    local parts = { clean(phrase.key) }
    for _, arg in ipairs(phrase.args or {}) do
        if type(arg) == "table" and arg.questId then
            parts[#parts + 1] = "q" .. arg.questId
        elseif type(arg) == "number" then
            parts[#parts + 1] = "n" .. arg
        else
            parts[#parts + 1] = "t" .. clean(arg)
        end
    end
    return (table.concat(parts, "~"):sub(1, 120))
end

---@return string? text A phrase from a message said in this player's language, quests by their titles here
function Comms.readPhrase(text)
    if not text or text == "" then
        return nil
    end
    local parts = {}
    for part in (text .. "~"):gmatch("([^~]*)~") do
        parts[#parts + 1] = part
    end
    local args = {}
    for index = 2, #parts do
        local kind, value = parts[index]:sub(1, 1), parts[index]:sub(2)
        if kind == "q" and tonumber(value) then
            local questId = tonumber(value)
            args[#args + 1] =
                ns.QuestText.getTitle(questId, ns.Database.getQuestField(questId, "name") or ("quest " .. questId))
        elseif kind == "n" then
            args[#args + 1] = tonumber(value) or 0
        else
            args[#args + 1] = value
        end
    end
    local isFine, said = pcall(ns.L, parts[1], unpack(args))
    return isFine and said or parts[1]
end

---@return string message The same answer, its reasons as phrases ("1|T|")
function Comms.composePhraseMessage(questId, state, reasonPhrase, shortPhrase)
    return string.format(
        "%s|T|%d|%s|%s|%s",
        VERSION,
        questId,
        STATE_LETTERS[state],
        Comms.writePhrase(shortPhrase),
        Comms.writePhrase(reasonPhrase)
    )
end

---@return string message The player's answer about a quest: done it, can take it, or can't and why
function Comms.composeStatusMessage(questId, state, reason, shortReason)
    local function clean(text)
        return ((text or ""):gsub("|", "/"):sub(1, 120))
    end
    return string.format("%s|S|%d|%s|%s|%s", VERSION, questId, STATE_LETTERS[state], clean(shortReason), clean(reason))
end

---Asks the group about a quest some of them are not on, at most once a minute: each member running OneMoreQuest
---answers whether they did it already, could take it, or can't and why.
function Comms.askStatus(questId)
    local now = GetTime and GetTime() or 0
    if askedTimes[questId] and now - askedTimes[questId] < ASK_INTERVAL_SECONDS then
        return
    end
    local channel = Comms.getGroupChannel()
    if not channel then
        return
    end
    askedTimes[questId] = now
    Comms.queueMessage(PREFIX, VERSION .. "|Q|" .. questId, channel)
end

---Forgets everything a player sent: they left the group.
function Comms.forgetPlayer(player)
    remoteQuests[normalizeName(player)] = nil
    remoteStatuses[normalizeName(player)] = nil
end

---Forgets everyone, as when leaving the group.
function Comms.reset()
    remoteQuests, sentEntries, knownMembers = {}, {}, {}
    remoteStatuses, askedTimes, answeredHellos = {}, {}, {}
    queue, tokens = {}, MAX_TOKENS
end

---------------------------------------------------------------------------------------------------------------
-- Talking to the group

local function isSharing()
    return ns.settings == nil or ns.settings.shouldShareProgress ~= false
end

---@return table<number, string> entries [questId] = entry, for every quest in the log
local function composeLogEntries()
    local entries = {}
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        entries[questId] = Comms.composeEntry(questId, ns.QuestState.getQuest(questId))
    end
    return entries
end

---Sends the whole log to the group, and to the Questie players in it in Questie's own words; or, as the answer
---to one member's hello, to that member alone.
---@param target string? The member who said hello
function Comms.sendLog(target)
    local channel = Comms.getGroupChannel()
    if not channel or not isSharing() then
        return
    end
    if target then
        channel = "WHISPER"
    end
    local entries, list = composeLogEntries(), {}
    for questId, entry in pairs(entries) do
        list[#list + 1] = entry
        sentEntries[questId] = entry
    end
    table.sort(list)
    for _, message in ipairs(Comms.composeLogMessages(list)) do
        Comms.queueMessage(PREFIX, message, channel, target)
    end
    if ns.QuestieBridge and not target then
        ns.QuestieBridge.sendLog(channel)
    end
end

---Sends what changed since the last time: counts that moved, quests that left the log.
function Comms.sendChanges()
    local channel = Comms.getGroupChannel()
    if not channel or not isSharing() then
        return
    end
    local entries = composeLogEntries()
    for questId, entry in pairs(entries) do
        if sentEntries[questId] ~= entry then
            sentEntries[questId] = entry
            Comms.queueMessage(PREFIX, VERSION .. "|U|" .. entry, channel)
            if ns.QuestieBridge then
                ns.QuestieBridge.sendQuest(questId, channel)
            end
        end
    end
    for questId in pairs(sentEntries) do
        if not entries[questId] then
            Comms.sendRemoval(questId)
        end
    end
end

---Tells the group a quest left the log.
function Comms.sendRemoval(questId)
    sentEntries[questId] = nil
    local channel = Comms.getGroupChannel()
    if not channel or not isSharing() then
        return
    end
    Comms.queueMessage(PREFIX, VERSION .. "|R|" .. questId, channel)
    if ns.QuestieBridge then
        ns.QuestieBridge.sendRemoval(questId, channel)
    end
end

---@return boolean isMember The player is in the group now: the roster as last seen, else as it is this moment (a
---newcomer's hello can come before the game tells of them joining)
local function isGroupMember(player)
    if player == "" then
        return false
    end
    return knownMembers[player] == true or Comms.getGroupMembers()[player] == true
end

---A member said hello: answered once, whispered to the newcomer alone (the rest of the group has the log already).
local function answerHello(sender)
    local name, now = normalizeName(sender), GetTime and GetTime() or 0
    if not answeredHellos[name] or now - answeredHellos[name] >= HELLO_ANSWER_SECONDS then
        answeredHellos[name] = now
        Comms.sendLog(name)
    end
end

---A member asked about a quest: answered only while sharing, and not about a quest in the log (the log's counts
---say that already).
local function answerQuestion(questId, sender)
    local state, reason, shortReason, reasonPhrase, shortPhrase = ns.Availability.getOwnStatus(questId)
    if not (isSharing() and STATE_LETTERS[state]) then
        return
    end
    Comms.queueMessage(PREFIX, Comms.composeStatusMessage(questId, state, reason, shortReason), "WHISPER", sender)
    if reasonPhrase then
        -- Then the same in phrases, for members who read another language (older versions skip it)
        Comms.queueMessage(
            PREFIX,
            Comms.composePhraseMessage(questId, state, reasonPhrase, shortPhrase),
            "WHISPER",
            sender
        )
    end
end

---A member's counts: one quest's, or a part of their whole log.
local function keepCounts(message, sender)
    if message.part == 1 then
        remoteQuests[normalizeName(sender)] = nil -- a whole log begins: anything not in it has gone
    end
    for _, entry in ipairs(message.entries) do
        local questId, quest = Comms.parseEntry(entry)
        if questId then
            Comms.setRemoteQuest(sender, questId, quest, "OneMoreQuest")
        end
    end
end

---A message on this addon's channel. Only the group is listened to: a whisper or a message on any other channel
---from someone outside it is let go, so strangers can neither pull the player's log nor plant counts.
---@param channel string The channel it came on: "PARTY", "RAID", "INSTANCE_CHAT" or "WHISPER"
function Comms.handleMessage(text, sender, channel)
    if not GROUP_CHANNELS[channel or ""] or not isGroupMember(normalizeName(sender)) then
        return
    end
    local message = Comms.parseMessage(text)
    if not message then
        return
    end
    local kind = message.kind
    if kind == "H" then
        answerHello(sender)
    elseif kind == "R" then
        Comms.removeRemoteQuest(sender, message.questId)
    elseif kind == "Q" then
        answerQuestion(message.questId, sender)
    elseif kind == "S" or kind == "T" then
        local status = { state = message.state, reason = message.reason, shortReason = message.shortReason }
        Comms.setRemoteStatus(sender, message.questId, status)
    else
        keepCounts(message, sender)
    end
end

---The group changed: forget who left. When the player is the one who joined (they were alone before, or have just
---logged in or reloaded), they say hello and send their log; every member answers the hello with their own log,
---to the player alone. Someone else joining needs nothing from here but that answer, so traffic grows with the
---group, not with its square.
function Comms.handleGroupChange()
    local members = Comms.getGroupMembers()
    local wasAlone = next(knownMembers) == nil
    for name in pairs(knownMembers) do
        if not members[name] then
            Comms.forgetPlayer(name)
            answeredHellos[name] = nil
        end
    end
    knownMembers = members
    if not next(members) then
        remoteQuests, sentEntries = {}, {}
        return
    end
    if wasAlone then
        local channel = Comms.getGroupChannel()
        Comms.queueMessage(PREFIX, VERSION .. "|H", channel)
        if ns.QuestieBridge then
            ns.QuestieBridge.requestLogs(channel)
        end
        Comms.sendLog()
    end
end

local function handleEvent(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, text, channel, sender = ...
        if normalizeName(sender) == normalizeName(UnitName and UnitName("player")) then
            return -- the player's own message, echoed back
        end
        if prefix == PREFIX then
            pcall(Comms.handleMessage, text, sender, channel)
        elseif ns.QuestieBridge and prefix == ns.QuestieBridge.PREFIX then
            ns.QuestieBridge.handleMessage(text, channel, sender)
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if not isUpdateScheduled and C_Timer then
            isUpdateScheduled = true
            C_Timer.After(UPDATE_DELAY_SECONDS, function()
                isUpdateScheduled = false
                pcall(Comms.sendChanges)
            end)
        end
    elseif event == "QUEST_REMOVED" then
        pcall(Comms.sendRemoval, (...))
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        pcall(Comms.handleGroupChange)
    end
end

function Comms.create()
    if eventFrame or not CreateFrame then
        return
    end
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if register then
        pcall(register, PREFIX)
    end
    if ns.QuestieBridge then
        ns.QuestieBridge.create()
    end
    eventFrame = CreateFrame("Frame")
    for _, event in ipairs({
        "CHAT_MSG_ADDON",
        "QUEST_LOG_UPDATE",
        "QUEST_REMOVED",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_ENTERING_WORLD",
    }) do
        eventFrame:RegisterEvent(event)
    end
    eventFrame:SetScript("OnEvent", handleEvent)
end

Comms.PREFIX = PREFIX
Comms.handleEvent = handleEvent -- for tests

ns.registerModule({ name = "Comms", create = Comms.create })
