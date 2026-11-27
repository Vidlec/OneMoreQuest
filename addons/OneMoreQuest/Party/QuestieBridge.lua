local _, ns = ...

-- Questie's party messages, read and sent so a group mixing OneMoreQuest and Questie players sees one another's
-- counts. Questie's wire format is ported here from Questie's own source (QuestieComms, QuestieSerializer and
-- QuestieStreamLib, by the Questie team, GPL-3.0; and AceComm-3.0's way of splitting long messages): a binary
-- serializer whose bytes are kept clear of the zero byte, with the long messages split in AceComm's parts.
-- It is kept apart from this addon's own channel: should Questie change its format and anything here fail,
-- the bridge switches itself off for the session, silently, and OneMoreQuest's own messages carry on.
-- With Questie itself running on this client, the bridge stays off: Questie talks for itself.
--
-- A message Questie cannot read is not dropped quietly on its side: it prints an error in that player's chat
-- ("Error reading QuestieComm message"), once a message. So nothing is sent on a guess:
--   * nothing at all until a member of the group has been heard on Questie's channel (only then is there anyone
--     to talk to, and their Questie's version is known);
--   * to a Questie within the versions whose packets were read from their source (OLDEST_TESTED_VERSION to
--     TESTED_VERSION), the packets they all have (TESTED_PACKETS);
--   * to an older or a newer one, only the kinds of packet a Questie of that very version was heard to send itself (kept
--     with the settings from one session to the next), since a kind it sends is a kind it reads.
-- Should Questie drop or renumber a packet, the bridge falls silent towards it instead of raising its errors.
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
-- (10, the whole log quest by quest, and 14 are older Questies': read when they come, never sent. Questie 12
-- has neither, and says so in the other player's chat for every one it is sent.)
local PACKET_FULL_LOG, PACKET_REQUEST_LOG, PACKET_FULL_LOG_FLAT = 10, 11, 12
local PACKET_QUEST_UPDATE_FLAT = 14

-- The Questies whose packets were read from their own source (QuestieComms.lua, _QuestieComms.packets: 6.0, 6.2,
-- 7.0, 9.4, 10.0, 11.0 and 12.15), and the packets every one of them has, in one format throughout: a Questie
-- from the oldest to the newest of them is sent these; an older or a newer one only what it was heard to send.
-- (Asked for its log by a sender of a version below 6, as this one says it is, a Questie up to 11 answers with
-- packet 10 and a newer one with 12: both are read.)
local OLDEST_TESTED_VERSION = { 6, 0 }
local TESTED_VERSION = { 12, 15 }
local TESTED_PACKETS = {
    [PACKET_QUEST_UPDATE] = true,
    [PACKET_QUEST_REMOVE] = true,
    [PACKET_REQUEST_LOG] = true,
    [PACKET_FULL_LOG_FLAT] = true,
}
local peers = {} -- [name] = the version of Questie a member of the group was heard to run
local heardPackets = {} -- [version] = { [packet] = true }: what a Questie of that version sent, this session

local MAX_KEPT_VERSIONS = 6 -- Questie versions whose packets are remembered with the settings
local MAX_FAILURES = 3 -- messages that could not be read before the bridge gives up for the session
-- What a message may hold, so a crafted one cannot keep the client busy: Questie's own logs stay far below these
local MAX_MESSAGE_PARTS = 64 -- parts of one long message (about 16 KB)
local MAX_OBJECTIVES = 20 -- objectives of one quest
local MAX_QUEST_ID = 1000000
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
    [1] = function()
        return nil
    end,
    [2] = function(reader)
        return reader.readInt()
    end,
    [3] = function(reader)
        return -reader.readInt()
    end,
    [4] = function(reader)
        return reader.readLong()
    end,
    [5] = function(reader)
        return -reader.readLong()
    end,
    [6] = readFloat,
    [7] = function(reader)
        return reader.readString(reader.readByte())
    end,
    [8] = function(reader)
        return reader.readString(reader.readShort())
    end,
    [9] = function(reader, hashes)
        return hashes.byHash[reader.readInt()]
    end,
    [10] = function(reader, hashes)
        return readEntries(reader, hashes, reader.readByte(), true)
    end,
    [11] = function(reader, hashes)
        return readEntries(reader, hashes, reader.readShort(), true)
    end,
    [12] = function(reader)
        return reader.readByte()
    end,
    [13] = function(reader)
        return -reader.readByte()
    end,
    [14] = function(reader)
        return reader.readShort()
    end,
    [15] = function(reader)
        return -reader.readShort()
    end,
    [16] = function()
        return false
    end,
    [17] = function()
        return true
    end,
    [18] = function()
        return nil
    end,
    [19] = function()
        return nil
    end,
    [20] = function(reader, hashes)
        return readEntries(reader, hashes, reader.readByte(), false)
    end,
    [21] = function(reader, hashes)
        return readEntries(reader, hashes, reader.readShort(), false)
    end,
    [22] = function(reader, hashes)
        return readEntries(reader, hashes, reader.readInt(), false)
    end,
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
        local parts = partsBySender[sender]
        if parts and #parts < MAX_MESSAGE_PARTS then
            table.insert(parts, rest)
        else
            partsBySender[sender] = nil -- longer than any of Questie's: dropped
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

---@return number? questId A quest id from a message, nil when it is no plausible quest
local function readQuestId(value)
    local questId = tonumber(value)
    if questId and questId >= 1 and questId <= MAX_QUEST_ID and questId == math.floor(questId) then
        return questId
    end
    return nil
end

---Questie's objectives as this addon keeps them: in order, with their counts. Indexes past the most a quest has are
---left out, so a crafted index (a billion) cannot make the loop below run for minutes.
local function convertObjectives(objectives)
    local converted, count = {}, 0
    for index in pairs(type(objectives) == "table" and objectives or {}) do
        if type(index) == "number" and index >= 1 and index <= MAX_OBJECTIVES then
            count = math.max(count, math.floor(index))
        end
    end
    -- (a quest Questie sends no objectives for, an escort: not known to be done, so not said to be)
    local isComplete = count > 0
    for index = 1, count do
        local objective = type(objectives[index]) == "table" and objectives[index] or {}
        local fulfilled, required = tonumber(objective.ful) or 0, tonumber(objective.req) or 0
        local isFinished = objective.fin == true or (required > 0 and fulfilled >= required)
        converted[index] = { fulfilled = fulfilled, required = required, isFinished = isFinished }
        isComplete = isComplete and isFinished
    end
    return { objectives = converted, isComplete = isComplete }
end

local function addQuest(quest, sender)
    local questId = type(quest) == "table" and readQuestId(quest.id)
    if questId then
        ns.Comms.setRemoteQuest(sender, questId, convertObjectives(quest.objectives), "Questie")
    end
end

---Questie's flat lists: quest id, objective count, then four numbers per objective (id, type, have, need).
---@return number? position After the quest; nil when the list ends or says nonsense, so reading stops
local function addFlatQuest(list, position, sender)
    local questId, count = readQuestId(list[position]), tonumber(list[position + 1])
    if not questId or not count or count < 0 or count > MAX_OBJECTIVES then
        return nil
    end
    position = position + 2
    local objectives = {}
    for index = 1, count do
        objectives[index] = { ful = list[position + 2], req = list[position + 3] }
        position = position + 4
    end
    ns.Comms.setRemoteQuest(sender, questId, convertObjectives(objectives), "Questie")
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

---@return number? major, number? minor Of a Questie version as its messages give it ("12.15.0")
local function parseVersion(version)
    local major, minor = tostring(version):match("^(%d+)%.(%d+)")
    return tonumber(major), tonumber(minor)
end

---@return boolean isTested The version is no newer than the Questie whose packets were read from its source
local function isTestedVersion(version)
    local major, minor = parseVersion(version)
    if not major then
        return false
    end
    local isOldEnough = major < TESTED_VERSION[1] or (major == TESTED_VERSION[1] and minor <= TESTED_VERSION[2])
    local isNewEnough = major > OLDEST_TESTED_VERSION[1]
        or (major == OLDEST_TESTED_VERSION[1] and minor >= OLDEST_TESTED_VERSION[2])
    return isOldEnough and isNewEnough
end

---@return boolean isRead A Questie of that version reads that kind of packet, as far as is known for sure
local function isReadBy(version, packetId)
    if isTestedVersion(version) and TESTED_PACKETS[packetId] then
        return true
    end
    if heardPackets[version] and heardPackets[version][packetId] then
        return true
    end
    local kept = ns.settings and ns.settings.questiePackets
    return type(kept) == "table" and type(kept[version]) == "table" and kept[version][packetId] == true
end

---Whether a kind of packet may be sent: someone in the group runs Questie (they were heard), and every one of
---them who would get it is known to read it. Whispered, only the one it goes to counts.
---@param target string? The player it would be whispered to
---@return boolean canSend
function QuestieBridge.canSend(packetId, target)
    local members = ns.Comms.getGroupMembers()
    local hasPeer = false
    for name, version in pairs(peers) do
        if members[name] and (not target or ns.Comms.normalizeName(target) == name) then
            hasPeer = true
            if not isReadBy(version, packetId) then
                return false
            end
        end
    end
    return hasPeer
end

local function send(packet, channel, target)
    if not channel or not isActive() or not isSharing() or not QuestieBridge.canSend(packet.msgId, target) then
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

---A quest in Questie's flat list: its id, how many objectives, then four numbers an objective (the database's id
---or 0, its type's first letter as a byte, how many are had, how many are needed). No nil among them: a hole
---would shift every number after it.
---@return number count How many numbers were added
local function addFlatNumbers(list, questId)
    local quest = QuestieBridge.composeQuest(questId)
    local start = #list
    list[#list + 1], list[#list + 2] = questId, #quest.objectives
    for _, objective in ipairs(quest.objectives) do
        list[#list + 1] = tonumber(objective.id) or 0
        list[#list + 1] = string.byte(objective.typ ~= "" and objective.typ or "e")
        list[#list + 1] = tonumber(objective.ful) or 0
        list[#list + 1] = tonumber(objective.req) or 0
    end
    return #list - start
end

---@return table packet Quests in Questie's flat list (packet 12): how many, then each quest's numbers
local function composeFlatPacket(list, count)
    local packet = composePacket(PACKET_FULL_LOG_FLAT)
    list[1] = count
    packet[1] = list
    return packet
end

---One quest's counts, to the Questie players of the group.
function QuestieBridge.sendQuest(questId, channel)
    if not isActive() then
        return
    end
    if not QuestieBridge.canSend(PACKET_QUEST_UPDATE) then
        -- A Questie not known to read the update reads the flat list it sends itself: a list of the one quest
        pcall(function()
            local list = { 0 }
            addFlatNumbers(list, questId)
            send(composeFlatPacket(list, 1), channel)
        end)
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

---The whole log, in blocks that each fit one message, as Questie sends it: its flat list.
---@param target string? A player to whisper it to, else the whole group
function QuestieBridge.sendLog(channel, target)
    if not isActive() or not isSharing() or not QuestieBridge.canSend(PACKET_FULL_LOG_FLAT, target) then
        return
    end
    local isSuccess = pcall(function()
        local list, count = { 0 }, 0
        for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
            local added = addFlatNumbers(list, questId)
            count = count + 1
            if count > 1 and #QuestieBridge.serialize(composeFlatPacket(list, count)) > MAX_PACKET_LENGTH then
                -- One quest too many for a message: the block goes without it, and it starts the next
                for _ = 1, added do
                    list[#list] = nil
                end
                send(composeFlatPacket(list, count - 1), channel, target)
                list, count = { 0 }, 1
                addFlatNumbers(list, questId)
            end
        end
        if count > 0 then
            send(composeFlatPacket(list, count), channel, target)
        end
    end)
    if not isSuccess then
        isBroken = true
    end
end

local GROUP_CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true, WHISPER = true }

---@return boolean isSound A packet a Questie sent holds what its kind is known to hold: only then does it count
---as a kind that Questie reads (one renumbered or reshaped under the old number is not taken for the old one)
local function isSoundPacket(packet)
    local packetId = packet.msgId
    if packetId == PACKET_QUEST_UPDATE then
        return type(packet.quest) == "table"
            and readQuestId(packet.quest.id) ~= nil
            and type(packet.quest.objectives) == "table"
    elseif packetId == PACKET_QUEST_REMOVE then
        return readQuestId(packet.id) ~= nil
    elseif packetId == PACKET_REQUEST_LOG then
        return true
    elseif packetId == PACKET_FULL_LOG_FLAT then
        return type(packet[1]) == "table" and type(packet[1][1]) == "number"
    end
    return false
end

---A member of the group was heard on Questie's channel: they run Questie, of this version, and it sends this kind
---of packet (so it reads it).
---@return boolean isNews They were not known to run Questie yet, or a Questie newer than the tested one proved to
---read a kind of packet it was not known to
local function notePeer(name, packet)
    local version = type(packet.ver) == "string" and #packet.ver <= 20 and packet.ver or "?"
    local isNews = peers[name] ~= version
    peers[name] = version
    if isSoundPacket(packet) and not isReadBy(version, packet.msgId) then
        heardPackets[version] = heardPackets[version] or {}
        heardPackets[version][packet.msgId] = true
        isNews = true
        -- Kept from one session to the next, a few versions at most (the newest ones heard)
        if ns.settings then
            local kept = type(ns.settings.questiePackets) == "table" and ns.settings.questiePackets or {}
            ns.settings.questiePackets = kept
            kept[version] = type(kept[version]) == "table" and kept[version] or {}
            kept[version][packet.msgId] = true
            local count = 0
            for _ in pairs(kept) do
                count = count + 1
            end
            if count > MAX_KEPT_VERSIONS then
                ns.settings.questiePackets = { [version] = kept[version] }
            end
        end
    end
    return isNews
end

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
    if packet.ver == SENDER_VERSION then
        return -- another OneMoreQuest speaking Questie's format for a Questie in the group: heard on our own channel
    end
    local packetId = packet.msgId
    local isNews = notePeer(name, packet)
    if packetId == PACKET_QUEST_UPDATE then
        addQuest(packet.quest, name)
    elseif packetId == PACKET_QUEST_REMOVE then
        ns.Comms.removeRemoteQuest(name, tonumber(packet.id))
    elseif packetId == PACKET_FULL_LOG then
        for _, quest in pairs(type(packet.rawQuestList) == "table" and packet.rawQuestList or {}) do
            addQuest(quest, name)
        end
    elseif packetId == PACKET_REQUEST_LOG then
        QuestieBridge.sendLog("WHISPER", name)
    elseif packetId == PACKET_FULL_LOG_FLAT and type(packet[1]) == "table" then
        -- The count the list starts with is believed only as far as the list goes: a crafted one (two billion)
        -- would otherwise keep the client looping
        local list = packet[1]
        local position = 2
        for _ = 1, math.min(tonumber(list[1]) or 0, #list) do
            position = addFlatQuest(list, position, name)
            if not position then
                break
            end
        end
    elseif packetId == PACKET_QUEST_UPDATE_FLAT and type(packet[1]) == "table" then
        addFlatQuest(packet[1], 1, name)
    end
    if isNews then
        -- Someone runs Questie here (or theirs proved to read more): their log is asked for, and they get this one,
        -- unless they just asked for it themselves (it was whispered to them above)
        local channel = ns.Comms.getGroupChannel()
        QuestieBridge.requestLogs(channel)
        if packetId ~= PACKET_REQUEST_LOG then
            QuestieBridge.sendLog(channel)
        end
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
    peers, heardPackets = {}, {}
end

QuestieBridge.PREFIX = PREFIX
QuestieBridge.getHash = getHash
