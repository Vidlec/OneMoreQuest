local _, ns = ...

-- Questie's party messages, read and sent so a group mixing OneMoreQuest and Questie players sees one another's
-- counts. Questie's wire format is ported here from Questie's own source (QuestieComms, QuestieSerializer and
-- QuestieStreamLib, by the Questie team, GPL-3.0; and AceComm-3.0's way of splitting long messages): a binary
-- serializer whose bytes are kept clear of the zero byte, with the long messages split in AceComm's parts.
-- It is kept apart from this addon's own channel: should Questie change its format and anything here fail,
-- the bridge switches itself off for the session, silently, and OneMoreQuest's own messages carry on.
-- With Questie itself running on this client, the bridge stays off: Questie talks for itself.
local QuestieBridge = {}
ns.QuestieBridge = QuestieBridge

local PREFIX = "questie"
local MESSAGE_VERSION = 5 -- Questie's commMessageVersion; messages of another whole number are not understood
-- Questie compares versions to suggest updates; an old one keeps that quiet, and makes Questie answer a request
-- for the quest log in the first format, the one with the fullest data
local SENDER_VERSION = "1.0.0"
local MAX_PART_LENGTH = 255
local MAX_PACKET_LENGTH = 240 -- a quest log block stays in one message

local PACKET_QUEST_UPDATE, PACKET_QUEST_REMOVE = 1, 2
local PACKET_FULL_LOG, PACKET_REQUEST_LOG, PACKET_FULL_LOG_FLAT = 10, 11, 12
local PACKET_QUEST_UPDATE_FLAT = 14

local MAX_FAILURES = 3 -- messages that could not be read before the bridge gives up for the session
local isBroken, failureCount = false, 0
local partsBySender = {} -- [sender] = the parts of a long message received so far

---------------------------------------------------------------------------------------------------------------
-- The stream: bytes, with 0, 237 and 238 written as escapes so a message never holds a zero byte

local ESCAPE, ZERO = 237, 238
local ESCAPED = { [1] = ESCAPE, [2] = ZERO }

local function createWriter()
    local writer = { bytes = {} }
    function writer.writeByte(value)
        local bytes = writer.bytes
        if value == ESCAPE then
            bytes[#bytes + 1], bytes[#bytes + 2] = ESCAPE, 1
        elseif value == ZERO then
            bytes[#bytes + 1], bytes[#bytes + 2] = ESCAPE, 2
        elseif value == 0 then
            bytes[#bytes + 1] = ZERO
        else
            bytes[#bytes + 1] = value
        end
    end
    function writer.writeShort(value)
        writer.writeByte(math.floor(value / 256) % 256)
        writer.writeByte(value % 256)
    end
    function writer.writeInt(value)
        writer.writeByte(math.floor(value / 16777216) % 256)
        writer.writeByte(math.floor(value / 65536) % 256)
        writer.writeByte(math.floor(value / 256) % 256)
        writer.writeByte(value % 256)
    end
    function writer.writeString(value)
        if #value > 254 then
            writer.writeShort(#value)
        else
            writer.writeByte(#value)
        end
        for index = 1, #value do
            writer.writeByte(value:byte(index))
        end
    end
    function writer.compose()
        local characters = {}
        for index, byte in ipairs(writer.bytes) do
            characters[index] = string.char(byte)
        end
        return table.concat(characters)
    end
    return writer
end

local function createReader(text)
    local reader = { text = text, position = 1 }
    function reader.readByte()
        local byte = text:byte(reader.position)
        if not byte then
            error("end of message")
        end
        reader.position = reader.position + 1
        if byte == ZERO then
            return 0
        elseif byte == ESCAPE then
            local escaped = text:byte(reader.position)
            reader.position = reader.position + 1
            return ESCAPED[escaped] or error("bad escape")
        end
        return byte
    end
    function reader.readShort()
        return reader.readByte() * 256 + reader.readByte()
    end
    function reader.readInt()
        return reader.readByte() * 16777216 + reader.readByte() * 65536 + reader.readByte() * 256 + reader.readByte()
    end
    function reader.readLong()
        local value = 0
        for _ = 1, 8 do
            value = value * 256 + reader.readByte()
        end
        return value
    end
    function reader.readString(length)
        local characters = {}
        for index = 1, length do
            characters[index] = string.char(reader.readByte())
        end
        return table.concat(characters)
    end
    return reader
end

---------------------------------------------------------------------------------------------------------------
-- The serializer: each value a type byte and its data; strings longer than four letters seen before in the
-- same message are sent as a 32-bit hash of themselves

---@return number hash Questie's string hash (djb2, times 31), kept to 32 bits
local function getHash(text)
    local hash = 5381
    for index = 1, #text do
        hash = (31 * hash + text:byte(index)) % 4294967296
    end
    return hash
end

local function createHashes()
    local hashes = { byText = {}, byHash = {} }
    function hashes.add(text)
        local hash = getHash(text)
        if hashes.byHash[hash] then
            return -- known, or a collision: the string is then always written out
        end
        hashes.byText[text], hashes.byHash[hash] = hash, text
    end
    return hashes
end

local function isArray(value)
    local index = 0
    for key in pairs(value) do
        index = index + 1
        if key ~= index then
            return false
        end
    end
    return true
end

local writeValue

local function writeNumber(writer, value)
    value = math.floor(value) -- only whole numbers are sent
    local sign = value < 0 and 1 or 0
    value = math.abs(value)
    if value > 2147483646 then
        error("number too large")
    elseif value < 222 and sign == 0 then
        writer.writeByte(32 + value) -- small numbers are their own type byte
    elseif value < 255 then
        writer.writeByte(12 + sign)
        writer.writeByte(value)
    elseif value < 65530 then
        writer.writeByte(14 + sign)
        writer.writeShort(value)
    else
        writer.writeByte(2 + sign)
        writer.writeInt(value)
    end
end

local function writeString(writer, hashes, value)
    if hashes.byText[value] and #value > 4 then
        writer.writeByte(9)
        writer.writeInt(hashes.byText[value])
    elseif #value > 254 then
        writer.writeByte(8)
        writer.writeString(value)
    else
        writer.writeByte(7)
        writer.writeString(value)
    end
end

local function writePair(writer, hashes, key, value)
    if not key or not value then
        return -- Questie leaves out false and nil values
    end
    writeValue(writer, hashes, key)
    if type(key) == "string" then
        hashes.add(key)
    end
    writeValue(writer, hashes, value)
    if type(value) == "string" then
        hashes.add(value)
    end
end

writeValue = function(writer, hashes, value)
    local valueType = type(value)
    if valueType == "number" then
        writeNumber(writer, value)
    elseif valueType == "string" then
        writeString(writer, hashes, value)
    elseif valueType == "boolean" then
        writer.writeByte(value and 17 or 16)
    elseif valueType == "table" then
        local count = 0
        for key, entry in pairs(value) do
            if key and entry then
                count = count + 1
            end
        end
        if isArray(value) then
            writer.writeByte(count > 254 and 21 or 20)
            if count > 254 then
                writer.writeShort(count)
            else
                writer.writeByte(count)
            end
            for _, entry in ipairs(value) do
                writeValue(writer, hashes, entry)
                if type(entry) == "string" then
                    hashes.add(entry)
                end
            end
        else
            writer.writeByte(count > 254 and 11 or 10)
            if count > 254 then
                writer.writeShort(count)
            else
                writer.writeByte(count)
            end
            for key, entry in pairs(value) do
                writePair(writer, hashes, key, entry)
            end
        end
    else
        writer.writeByte(1) -- anything else is sent as nil
    end
end

---@return string data A table in Questie's serialized form
function QuestieBridge.serialize(value)
    local writer, hashes = createWriter(), createHashes()
    writePair(writer, hashes, 1, value)
    return writer.compose()
end

local readValue

local function readEntries(reader, hashes, count, isKeyed)
    local result = {}
    for index = 1, count do
        local key = index
        if isKeyed then
            key = readValue(reader, hashes)
            if type(key) == "string" then
                hashes.add(key)
            end
        end
        local value = readValue(reader, hashes)
        if type(value) == "string" then
            hashes.add(value)
        end
        if key ~= nil then
            result[key] = value
        end
    end
    return result
end

local function readFloat(reader)
    local bits = reader.readInt()
    local sign = bits >= 2147483648 and -1 or 1
    local exponent = math.floor(bits / 8388608) % 256
    local mantissa = bits % 8388608
    if exponent == 0 and mantissa == 0 then
        return 0
    end
    return sign * math.ldexp(1 + mantissa / 8388608, exponent - 127)
end

local READERS = {
    [1] = function() return nil end,
    [2] = function(reader) return reader.readInt() end,
    [3] = function(reader) return -reader.readInt() end,
    [4] = function(reader) return reader.readLong() end,
    [5] = function(reader) return -reader.readLong() end,
    [6] = readFloat,
    [7] = function(reader) return reader.readString(reader.readByte()) end,
    [8] = function(reader) return reader.readString(reader.readShort()) end,
    [9] = function(reader, hashes) return hashes.byHash[reader.readInt()] end,
    [10] = function(reader, hashes) return readEntries(reader, hashes, reader.readByte(), true) end,
    [11] = function(reader, hashes) return readEntries(reader, hashes, reader.readShort(), true) end,
    [12] = function(reader) return reader.readByte() end,
    [13] = function(reader) return -reader.readByte() end,
    [14] = function(reader) return reader.readShort() end,
    [15] = function(reader) return -reader.readShort() end,
    [16] = function() return false end,
    [17] = function() return true end,
    [18] = function() return nil end,
    [19] = function() return nil end,
    [20] = function(reader, hashes) return readEntries(reader, hashes, reader.readByte(), false) end,
    [21] = function(reader, hashes) return readEntries(reader, hashes, reader.readShort(), false) end,
    [22] = function(reader, hashes) return readEntries(reader, hashes, reader.readInt(), false) end,
}

readValue = function(reader, hashes)
    local typeByte = reader.readByte()
    if typeByte > 31 then
        return typeByte - 32
    end
    local read = READERS[typeByte]
    if not read then
        error("unknown type " .. typeByte)
    end
    return read(reader, hashes)
end

---@return any value The table a Questie message holds
function QuestieBridge.deserialize(data)
    local entries = readEntries(createReader(data), createHashes(), 1, true)
    return entries[1]
end

---------------------------------------------------------------------------------------------------------------
-- AceComm's parts: a long message goes as a first part ("\001"), middle parts ("\002") and a last one ("\003")

---@return string[] parts The messages to send for one text
function QuestieBridge.splitMessage(text)
    if text:match("^[\001-\009]") then
        if #text + 1 <= MAX_PART_LENGTH then
            return { "\004" .. text }
        end
    elseif #text <= MAX_PART_LENGTH then
        return { text }
    end
    local parts, partLength = {}, MAX_PART_LENGTH - 1
    local position = 1
    while position <= #text do
        local chunk = text:sub(position, position + partLength - 1)
        local marker = position == 1 and "\001" or (position + partLength > #text and "\003" or "\002")
        parts[#parts + 1] = marker .. chunk
        position = position + partLength
    end
    return parts
end

---@return string? text The whole message once its last part has come; nil while parts are missing
function QuestieBridge.joinMessage(part, sender)
    local marker, rest = part:match("^([\001-\009])(.*)$")
    if not marker then
        return part
    elseif marker == "\004" then
        return rest
    elseif marker == "\001" then
        partsBySender[sender] = { rest }
    elseif marker == "\002" then
        if partsBySender[sender] then
            table.insert(partsBySender[sender], rest)
        end
    elseif marker == "\003" then
        local parts = partsBySender[sender]
        partsBySender[sender] = nil
        if parts then
            table.insert(parts, rest)
            return table.concat(parts)
        end
    end
    return nil
end

---------------------------------------------------------------------------------------------------------------
-- Questie's quests: { id, objectives = { [index] = { id, typ, fin, ful, req } } }

local function composePacket(packetId)
    return { ver = SENDER_VERSION, msgVer = MESSAGE_VERSION, msgId = packetId }
end

---@return table quest One quest of the log as Questie sends it
function QuestieBridge.composeQuest(questId)
    local quest = ns.QuestState.getQuest(questId)
    local objectives, typeIndexes = {}, {}
    for index, objective in ipairs(quest.objectives) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        local target = ns.Location.getObjectiveTarget(questId, objective.type, typeIndexes[objective.type])
        objectives[index] = {
            id = target and (target.npcId or target.itemId) or nil,
            typ = string.sub(objective.type or "", 1, 1),
            fin = objective.isFinished or nil,
            ful = objective.fulfilled,
            req = objective.required,
        }
    end
    return { id = questId, objectives = objectives }
end

---Questie's objectives as this addon keeps them: in order, with their counts.
local function convertObjectives(objectives)
    local converted, isComplete, count = {}, true, 0
    for index in pairs(objectives or {}) do
        if type(index) == "number" then
            count = math.max(count, index)
        end
    end
    for index = 1, count do
        local objective = objectives[index] or {}
        local fulfilled, required = tonumber(objective.ful) or 0, tonumber(objective.req) or 0
        local isFinished = objective.fin == true or (required > 0 and fulfilled >= required)
        converted[index] = { fulfilled = fulfilled, required = required, isFinished = isFinished }
        isComplete = isComplete and isFinished
    end
    return { objectives = converted, isComplete = isComplete }
end

local function addQuest(quest, sender)
    if type(quest) == "table" and tonumber(quest.id) then
        ns.Comms.setRemoteQuest(sender, tonumber(quest.id), convertObjectives(quest.objectives), "Questie")
    end
end

---Questie's flat lists: quest id, objective count, then four numbers per objective (id, type, have, need).
---@return number position After the quest
local function addFlatQuest(list, position, sender)
    local questId, count = list[position], list[position + 1] or 0
    position = position + 2
    local objectives = {}
    for index = 1, count do
        objectives[index] = { ful = list[position + 2], req = list[position + 3] }
        position = position + 4
    end
    if tonumber(questId) then
        ns.Comms.setRemoteQuest(sender, tonumber(questId), convertObjectives(objectives), "Questie")
    end
    return position
end

---------------------------------------------------------------------------------------------------------------
-- Sending and receiving

local function isQuestieRunning()
    return ns.isAddOnLoaded("Questie")
end

local function isActive()
    return not isBroken and not isQuestieRunning()
end

local function isSharing()
    return ns.settings == nil or ns.settings.shouldShareProgress ~= false
end

local function send(packet, channel, target)
    if not channel or not isActive() or not isSharing() then
        return
    end
    local isSuccess = pcall(function()
        for _, part in ipairs(QuestieBridge.splitMessage(QuestieBridge.serialize(packet))) do
            ns.Comms.queueMessage(PREFIX, part, channel, target)
        end
    end)
    if not isSuccess then
        isBroken = true
    end
end

---One quest's counts, to the Questie players of the group.
function QuestieBridge.sendQuest(questId, channel)
    if not isActive() then
        return
    end
    local isSuccess, quest = pcall(QuestieBridge.composeQuest, questId)
    if isSuccess then
        local packet = composePacket(PACKET_QUEST_UPDATE)
        packet.quest = quest
        send(packet, channel)
    end
end

---A quest left the log.
function QuestieBridge.sendRemoval(questId, channel)
    local packet = composePacket(PACKET_QUEST_REMOVE)
    packet.id = questId
    send(packet, channel)
end

---Asks the Questie players of the group for their logs.
function QuestieBridge.requestLogs(channel)
    send(composePacket(PACKET_REQUEST_LOG), channel)
end

---The whole log, in blocks that each fit one message, as Questie sends it.
---@param target string? A player to whisper it to, else the whole group
function QuestieBridge.sendLog(channel, target)
    if not isActive() or not isSharing() then
        return
    end
    local isSuccess = pcall(function()
        local block, count = {}, 0
        local function sendBlock()
            if count > 0 then
                local packet = composePacket(PACKET_FULL_LOG)
                packet.rawQuestList = block
                send(packet, channel, target)
            end
            block, count = {}, 0
        end
        for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
            local quest = QuestieBridge.composeQuest(questId)
            block[questId], count = quest, count + 1
            local packet = composePacket(PACKET_FULL_LOG)
            packet.rawQuestList = block
            if count > 1 and #QuestieBridge.serialize(packet) > MAX_PACKET_LENGTH then
                block[questId], count = nil, count - 1
                sendBlock()
                block[questId], count = quest, 1
            end
        end
        sendBlock()
    end)
    if not isSuccess then
        isBroken = true
    end
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }

local function readPacket(text, channel, sender)
    if not GROUP_CHANNELS[channel] then
        return -- yells and public channels carry strangers' progress
    end
    local name = ns.Comms.normalizeName(sender)
    if not ns.Comms.getGroupMembers()[name] then
        return
    end
    local whole = QuestieBridge.joinMessage(text, name)
    if not whole then
        return
    end
    local packet = QuestieBridge.deserialize(whole)
    if type(packet) ~= "table" or math.floor(tonumber(packet.msgVer) or 0) ~= MESSAGE_VERSION then
        return -- another version of Questie's format: not understood, so left alone
    end
    local packetId = packet.msgId
    if packetId == PACKET_QUEST_UPDATE then
        addQuest(packet.quest, name)
    elseif packetId == PACKET_QUEST_REMOVE then
        ns.Comms.removeRemoteQuest(name, tonumber(packet.id))
    elseif packetId == PACKET_FULL_LOG then
        for _, quest in pairs(packet.rawQuestList or {}) do
            addQuest(quest, name)
        end
    elseif packetId == PACKET_REQUEST_LOG then
        QuestieBridge.sendLog("WHISPER", name)
    elseif packetId == PACKET_FULL_LOG_FLAT and type(packet[1]) == "table" then
        local position = 2
        for _ = 1, packet[1][1] or 0 do
            position = addFlatQuest(packet[1], position, name)
        end
    elseif packetId == PACKET_QUEST_UPDATE_FLAT and type(packet[1]) == "table" then
        addFlatQuest(packet[1], 1, name)
    end
end

---A message on Questie's channel. Messages that keep failing to be read switch the bridge off for the session.
function QuestieBridge.handleMessage(text, channel, sender)
    if not isActive() or type(text) ~= "string" then
        return
    end
    local isSuccess = pcall(readPacket, text, channel, sender)
    if not isSuccess then
        failureCount = failureCount + 1
        isBroken = failureCount >= MAX_FAILURES
    end
end

---@return boolean isWorking The bridge is on: Questie is not running here and nothing has failed
function QuestieBridge.isWorking()
    return isActive()
end

function QuestieBridge.create()
    if isQuestieRunning() then
        return
    end
    local register = C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix or RegisterAddonMessagePrefix
    if register then
        pcall(register, PREFIX)
    end
end

---Back to working, as after a reload: for tests.
function QuestieBridge.reset()
    isBroken, failureCount, partsBySender = false, 0, {}
end

QuestieBridge.PREFIX = PREFIX
QuestieBridge.getHash = getHash
