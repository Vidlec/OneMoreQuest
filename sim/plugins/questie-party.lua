-- Questie's party protocol, for AddonSim's simulated party members (a plugin: addonsim.config.ts "plugins"), so
-- OneMoreQuest's QuestieBridge can be played against a member running Questie. The member's messages are made by
-- Questie's own code (questie/: QuestieSerializer, QuestieStream, and AceComm-3.0 to split long ones; see
-- questie/NOTICE.md for their licences), so what reaches the player's addons is what Questie sends.
-- The member sends, as Questie does: on joining, a request for everyone's quest log and its own log (packet 12, the
-- flat list, in blocks); on progress, the quest's counts (packet 1); on dropping a quest, its removal (packet 2);
-- and when asked for its log (packet 11), the log again, whispered.
-- It reads as Questie does too (QuestieComms.lua of Questie 12.15, _QuestieComms:OnCommReceived_unsafe): the packets
-- it has are 1, 2, 11 and 12. One of its message version with any other number is not dropped quietly: Questie
-- prints "Error reading QuestieComm message" in that player's chat. Here that goes to the game's chat and to
-- G.QuestieSimErrors, for a scenario to check that nothing the player's addon sent raised one; what the member
-- read of the player's quests is in G.QuestieSimQuests ([member][quest] = its objectives).
local plugins = require("plugins")

local PREFIX = "questie"
local MESSAGE_VERSION = 5
local QUESTIE_VERSION = "11.0.0"
local PACKET_QUEST_UPDATE, PACKET_QUEST_REMOVE, PACKET_REQUEST_LOG, PACKET_FULL_LOG = 1, 2, 11, 12
local MAX_BLOCK_LENGTH = 200 -- as Questie splits its log into blocks

-- This file's folder: Questie's code is beside it
local HERE = (debug.getinfo(1, "S").source:gsub("^@", ""):match("^(.*[/\\])") or "./")

local sandbox, serializer, aceComm
local sendingMember -- whose message AceComm is splitting right now

---Loads Questie's code once, in a sandbox of its own: its globals never reach the game's.
local function load()
    if sandbox then
        return
    end
    local modules = {}
    sandbox = setmetatable({}, { __index = plugins.gameGlobals() })
    sandbox._G = sandbox
    sandbox.QuestieLoader = {
        CreateModule = function(_, name)
            modules[name] = modules[name] or {}
            return modules[name]
        end,
        ImportModule = function(_, name)
            modules[name] = modules[name] or {}
            return modules[name]
        end,
    }
    -- AceComm sends through ChatThrottleLib; here each part goes straight out as the member's addon message
    sandbox.ChatThrottleLib = {
        SendAddonMessage = function(_, _, prefix, text, channel)
            plugins.sendFromMember(sendingMember, prefix, text, channel, 0.2)
        end,
    }
    for _, file in ipairs({
        "LibStub.lua",
        "CallbackHandler-1.0.lua",
        "AceComm-3.0.lua",
        "QuestieStream.lua",
        "QuestieSerializer.lua",
    }) do
        local chunk = assert(loadfile(HERE .. "questie/" .. file))
        setfenv(chunk, sandbox)
        chunk()
    end
    serializer = modules.QuestieSerializer
    aceComm = sandbox.LibStub("AceComm-3.0")
end

local function send(member, data, channel, target)
    load()
    data.ver, data.msgVer = QUESTIE_VERSION, MESSAGE_VERSION
    sendingMember = member
    aceComm:SendCommMessage(PREFIX, serializer:Serialize(data), channel, target, "BULK")
    sendingMember = nil
end

---A quest as Questie packs it: its id and each objective's database id, type letter, and counts.
local function composeQuest(questId, quest)
    local packed = { id = questId, objectives = {} }
    for index, objective in ipairs(quest.objectives) do
        packed.objectives[index] = {
            id = objective.id or 0,
            typ = (objective.kind or "m"):sub(1, 1),
            fin = objective.fulfilled >= objective.required,
            ful = objective.fulfilled,
            req = objective.required,
        }
    end
    return packed
end

---The member's whole log, in blocks small enough for one message each, as Questie sends it: a flat list of how
---many quests, then each one's id, objective count, and four numbers an objective (its id, its type's letter as a
---byte, how many are had, how many are needed).
local function sendLog(member, channel, target)
    local questIds = {}
    for questId in pairs(member.quests) do
        questIds[#questIds + 1] = questId
    end
    table.sort(questIds)
    load()
    local blocks, list, count = {}, { 0 }, 0
    for _, questId in ipairs(questIds) do
        local packed = composeQuest(questId, member.quests[questId])
        list[#list + 1], list[#list + 2] = questId, #packed.objectives
        for _, objective in ipairs(packed.objectives) do
            list[#list + 1], list[#list + 2] = objective.id, string.byte(objective.typ)
            list[#list + 1], list[#list + 2] = objective.ful, objective.req
        end
        count = count + 1
        if #serializer:Serialize(list) > MAX_BLOCK_LENGTH then
            list[1] = count
            blocks[#blocks + 1] = list
            list, count = { 0 }, 0
        end
    end
    if count > 0 then
        list[1] = count
        blocks[#blocks + 1] = list
    end
    for _, block in ipairs(blocks) do
        send(member, { msgId = PACKET_FULL_LOG, [1] = block }, channel, target)
    end
end

local function sendChange(member, questId)
    local quest = member.quests[questId]
    if quest then
        send(member, { msgId = PACKET_QUEST_UPDATE, quest = composeQuest(questId, quest) }, "PARTY")
    else
        send(member, { msgId = PACKET_QUEST_REMOVE, id = questId }, "PARTY")
    end
end

-- What Questie 12.15 has a reader for
local KNOWN_PACKETS = {
    [PACKET_QUEST_UPDATE] = true,
    [PACKET_QUEST_REMOVE] = true,
    [PACKET_REQUEST_LOG] = true,
    [PACKET_FULL_LOG] = true,
}
local partsByMember = {} -- [member name] = the parts of a long message from the player so far (AceComm's)

---AceComm's parts put together: the whole message once its last part came, nil until then.
local function joinParts(member, text)
    local marker, rest = text:match("^([\001-\004])(.*)$")
    if not marker then
        return text
    elseif marker == "\004" then
        return rest
    elseif marker == "\001" then
        partsByMember[member.name] = { rest }
    elseif marker == "\002" then
        table.insert(partsByMember[member.name] or {}, rest)
    else
        local parts = partsByMember[member.name] or {}
        partsByMember[member.name] = nil
        parts[#parts + 1] = rest
        return table.concat(parts)
    end
    return nil
end

---The player's addon sent something on Questie's channel: read as Questie reads it.
local function readFromPlayer(member, message)
    load()
    local G = plugins.gameGlobals()
    local text = type(message.text) == "string" and joinParts(member, message.text)
    if not text then
        return
    end
    -- (Questie's whole reader runs in a pcall: a message its serializer cannot read is dropped quietly)
    local isRead, data = pcall(serializer.Deserialize, serializer, text)
    if not isRead or type(data) ~= "table" or not data.msgVer then
        return
    end
    if math.floor(data.msgVer) ~= math.floor(MESSAGE_VERSION) then
        return -- (another message version: Questie warns of it once, another matter)
    end
    if not (data.msgId and KNOWN_PACKETS[data.msgId]) then
        local problem = "Questie: [ERROR] Error reading QuestieComm message (If it persist try updating) Player: "
            .. plugins.playerName()
            .. " PacketLength: "
            .. #text
        G.QuestieSimErrors = G.QuestieSimErrors or {}
        table.insert(G.QuestieSimErrors, problem .. " (packet " .. tostring(data.msgId) .. ")")
        if G.DEFAULT_CHAT_FRAME then
            G.DEFAULT_CHAT_FRAME:AddMessage(problem)
        end
        return
    end
    G.QuestieSimQuests = G.QuestieSimQuests or {}
    G.QuestieSimQuests[member.name] = G.QuestieSimQuests[member.name] or {}
    local seen = G.QuestieSimQuests[member.name]
    if data.msgId == PACKET_REQUEST_LOG then
        sendLog(member, "WHISPER", plugins.playerName())
    elseif data.msgId == PACKET_QUEST_UPDATE then
        -- (QuestieComms:InsertQuestDataPacket)
        local quest = data.quest
        if quest and quest.objectives and quest.id then
            local objectives = {}
            for index, objective in pairs(quest.objectives) do
                objectives[index] = { fulfilled = objective.ful, required = objective.req }
            end
            seen[quest.id] = objectives
        end
    elseif data.msgId == PACKET_QUEST_REMOVE then
        seen[data.id] = nil
    elseif data.msgId == PACKET_FULL_LOG then
        -- (QuestieComms:InsertQuestDataPacketV2, as it walks the flat list)
        local list, offset = data[1], 2
        for _ = 1, list[1] do
            if list[1 + offset] then
                local questId, objectiveCount = list[offset], list[offset + 1]
                local objectives, index = {}, 0
                offset = offset + 2
                while index < objectiveCount and list[offset + 1] do
                    index = index + 1
                    objectives[index] = { fulfilled = list[offset + 2], required = list[offset + 3] }
                    string.char(list[offset + 1]) -- (the type's letter: an error here is Questie's too)
                    offset = offset + 4
                end
                seen[questId] = objectives
            end
        end
    end
end

plugins.registerPartyAddon("Questie", {
    label = "Questie",
    note = "Shares its log and progress on its own channel (Questie's serializer)",
    color = "warning",
    onJoin = function(member)
        send(member, { msgId = PACKET_REQUEST_LOG }, "PARTY")
        sendLog(member, "PARTY")
    end,
    onQuestChanged = sendChange,
    onMessage = function(member, message)
        if message.prefix == PREFIX then
            readFromPlayer(member, message)
        end
    end,
})
