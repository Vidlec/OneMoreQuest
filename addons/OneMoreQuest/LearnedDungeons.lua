local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

---Dungeons the quest database does not know (Forever's Alcaz Prison, Blackmaw Hold, Krol'dok Stronghold, the
---Shaper's Terrace, the Drowned City), learned as the player runs them: their name and entrance, and every
---quest picked up, worked on or handed in inside. Kept for the whole account, as the world is the same for every
---character. They take area IDs past any the game uses, so the rest of the addon treats them as dungeons.
local LearnedDungeons = {}
ns.LearnedDungeons = LearnedDungeons

local AREA_ID_BASE = 1000000 -- a learned dungeon's own area ID is this plus the game's number for the instance
local SAMPLE_SECONDS = 2 -- how often the player's place outside is noted, to know the entrance once inside
local ENTRANCE_MAX_AGE_SECONDS = 120 -- a place noted longer before going in is not the way in

local lastOutside -- { zoneId, x, y, time }: where the player last stood outside an instance
local learningInstanceId -- the unknown instance the player is inside
local isLeavingToEntrance = false -- left an unknown instance with no entrance yet: the next place outside is it
local fulfilledByQuestId = {} -- the objectives done of each quest in the log, at the last look inside

---@class LearnedDungeonRecord
---@field name string
---@field isRaid boolean?
---@field entrance { zoneId: number, x: number, y: number }?
---@field questIds table<number, boolean> Every quest seen done inside
---@field pickedUpQuestIds table<number, boolean> The ones picked up inside

---@return boolean isPlace A saved entrance that can be used: a zone and a spot on its map
local function isPlace(place)
    return type(place) == "table"
        and type(place.zoneId) == "number"
        and type(place.x) == "number"
        and type(place.y) == "number"
end

---Mends what a damaged saved file left of the records, so every login does not fail on them: a record not a table, or
---keyed by no instance number, goes; a missing name, quest list or way in is made good.
local function repairRecords(records)
    for instanceId, record in pairs(records) do
        if type(instanceId) ~= "number" or type(record) ~= "table" then
            records[instanceId] = nil -- (removing during the walk is allowed for the key just visited)
        else
            if type(record.name) ~= "string" or record.name == "" then
                record.name = "Instance " .. instanceId
            end
            record.questIds = type(record.questIds) == "table" and record.questIds or {}
            record.pickedUpQuestIds = type(record.pickedUpQuestIds) == "table" and record.pickedUpQuestIds or {}
            if record.entrance ~= nil and not isPlace(record.entrance) then
                record.entrance = nil -- learned again on the next way in
            end
            if record.isRaid ~= nil and type(record.isRaid) ~= "boolean" then
                record.isRaid = nil
            end
        end
    end
end

local repairedRecords -- the saved table last mended: mended once, not at every reading

---@return table<number, LearnedDungeonRecord> records By the game's number for the instance
local function getRecords()
    if type(ns.settings.learnedDungeons) ~= "table" then
        ns.settings.learnedDungeons = {}
    end
    local records = ns.settings.learnedDungeons
    if repairedRecords ~= records then
        repairedRecords = records
        repairRecords(records)
    end
    return records
end

---@return number areaId The dungeon's area ID: the one of the same name another provider gave (the DungeonJournal
---addon's Drowned City), so a dungeon listed from the start and later learned by playing is one dungeon; else its own
function LearnedDungeons.getAreaId(instanceId)
    local dungeon = ns.Database.getDungeon(AREA_ID_BASE + instanceId)
    return dungeon and dungeon.areaId or AREA_ID_BASE + instanceId
end

---@return LearnedDungeonRecord[] records The records learned by playing behind a dungeon's area ID
local function getRecordsForAreaId(areaId)
    local found = {}
    for instanceId, record in pairs(type(areaId) == "number" and getRecords() or {}) do
        if LearnedDungeons.getAreaId(instanceId) == areaId then
            found[#found + 1] = record
        end
    end
    return found
end

---@return number[] areaIds Every learned dungeon
function LearnedDungeons.getAreaIds()
    local areaIds, isAdded = {}, {}
    for instanceId in pairs(getRecords()) do
        local areaId = LearnedDungeons.getAreaId(instanceId)
        if not isAdded[areaId] then
            areaIds[#areaIds + 1], isAdded[areaId] = areaId, true
        end
    end
    table.sort(areaIds)
    return areaIds
end

---@return number[] questIds The quests seen done inside a learned dungeon
function LearnedDungeons.getQuestIds(areaId)
    local questIds, isAdded = {}, {}
    for _, record in ipairs(getRecordsForAreaId(areaId)) do
        for questId in pairs(record.questIds) do
            if not isAdded[questId] then
                questIds[#questIds + 1], isAdded[questId] = questId, true
            end
        end
    end
    table.sort(questIds)
    return questIds
end

---@return boolean isPickedUpInside The quest was seen picked up inside the learned dungeon
function LearnedDungeons.isPickedUpInside(areaId, questId)
    for _, record in ipairs(getRecordsForAreaId(areaId)) do
        if record.pickedUpQuestIds[questId] then
            return true
        end
    end
    return false
end

local instanceIdByQuestId -- the learned instance each quest was seen done in, forgotten whenever the records change
local function getQuestInstanceId(questId)
    if not instanceIdByQuestId then
        instanceIdByQuestId = {}
        for instanceId, record in pairs(getRecords()) do
            for listedQuestId in pairs(record.questIds) do
                instanceIdByQuestId[listedQuestId] = instanceIdByQuestId[listedQuestId] or instanceId
            end
        end
    end
    return instanceIdByQuestId[questId]
end

-- What was learned by playing is a quest provider too, asked after QuestieDB and the DungeonJournal addon: the
-- dungeons, with their way in, and for a quest QuestieDB files nowhere, the dungeon it was seen done in
ns.Database.registerProvider({
    name = "Learned",
    order = 30,
    isAvailable = function()
        return ns.settings ~= nil
    end,
    questFields = { zoneOrSort = true },
    getQuestField = function(questId, field)
        local instanceId = field == "zoneOrSort" and getQuestInstanceId(questId)
        return instanceId and LearnedDungeons.getAreaId(instanceId) or nil
    end,
    getDungeons = function()
        local list = {}
        for instanceId, record in pairs(getRecords()) do
            list[#list + 1] = {
                name = record.name,
                areaId = AREA_ID_BASE + instanceId,
                entrances = record.entrance and { record.entrance } or {},
                isRaid = record.isRaid == true,
                isLearned = true,
            }
        end
        table.sort(list, function(first, second)
            return first.areaId < second.areaId
        end)
        return list
    end,
})

---@return number? instanceId, string? name, boolean? isRaid The dungeon or raid instance the player is in, when the
---quest database does not know it
local function getUnknownInstance()
    if not (IsInInstance and IsInInstance()) or not GetInstanceInfo then
        return nil
    end
    local name, instanceType, _, _, _, _, _, instanceId = GetInstanceInfo()
    if
        (instanceType ~= "party" and instanceType ~= "raid")
        or not instanceId
        or ns.Database.getKnownInstanceDungeonId(instanceId)
    then
        return nil
    end
    return instanceId, name, instanceType == "raid"
end

---@return { zoneId: number, x: number, y: number }? place Where the player stands, as the database writes places
local function getPlayerPlace()
    local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local position = uiMapId and C_Map.GetPlayerMapPosition(uiMapId, "player")
    local zoneId = uiMapId and ns.Database.getAreaId(uiMapId)
    if not position or not zoneId then
        return nil
    end
    local x, y = position:GetXY()
    if not x or (x == 0 and y == 0) then
        return nil
    end
    return { zoneId = zoneId, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
end

---A group the game's dungeon finder made is carried in and out, never through the entrance.
local function isCarriedByFinder()
    return IsInGroup ~= nil and LE_PARTY_CATEGORY_INSTANCE ~= nil and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) == true
end

---@return boolean isResting The player is at rest: at an inn or in a city, where a hearthstone, a portal or a summons
---from there sets them down, never a dungeon's way in
local function isResting()
    return IsResting ~= nil and IsResting() == true
end

---@return boolean isElsewhere Where the player came out of an instance is surely not its way in: as a ghost (set
---down at a graveyard after dying inside) or at rest (an inn, after a hearthstone). Entrances were once learned from
---the graveyard or the inn the player came out at.
local function isAwayFromEntrance()
    return (UnitIsDeadOrGhost ~= nil and UnitIsDeadOrGhost("player") == true) or isResting()
end

local function handleChange()
    instanceIdByQuestId = nil
    ns.Database.forgetDungeons()
    if ns.Model and ns.Model.forgetSteps then
        ns.Model.forgetSteps() -- where a quest leads may be into the dungeon just learned
    end
    ns.queueRefresh()
end

---Notes a quest done inside the instance being learned.
---@param isPickup boolean? It was picked up there
local function learnQuest(questId, isPickup)
    local record = learningInstanceId and getRecords()[learningInstanceId]
    if not record or not ns.Database.getQuestField(questId, "name") or not ns.Availability.isForRun(questId) then
        return
    end
    local isNew = not record.questIds[questId]
    record.questIds[questId] = true
    if isPickup and not record.pickedUpQuestIds[questId] then
        record.pickedUpQuestIds[questId] = true
        isNew = true
    end
    if isNew then
        ns.Availability.addLearnedQuest(LearnedDungeons.getAreaId(learningInstanceId), questId)
        handleChange()
    end
end

---@return table<number, number> fulfilledByQuestId The objectives done of every quest in the log
local function readFulfilled()
    local fulfilled = {}
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        local count = 0
        for _, objective in ipairs(ns.QuestState.getQuest(questId).objectives) do
            count = count + (objective.fulfilled or 0) + (objective.isFinished and 1 or 0)
        end
        fulfilled[questId] = count
    end
    return fulfilled
end

---Any quest whose objectives moved on while inside is the dungeon's.
local function learnProgress()
    local fulfilled = readFulfilled()
    for questId, count in pairs(fulfilled) do
        if fulfilledByQuestId[questId] and count > fulfilledByQuestId[questId] then
            learnQuest(questId)
        end
    end
    fulfilledByQuestId = fulfilled
end

---Entering or leaving an instance: start or stop learning, and note the entrance the first time.
local function handleWorldEntered()
    local instanceId, name, isRaid = getUnknownInstance()
    if instanceId then
        local records = getRecords()
        local record = records[instanceId]
        if not record then
            record =
                { name = name or ("Instance " .. instanceId), isRaid = isRaid, questIds = {}, pickedUpQuestIds = {} }
            records[instanceId] = record
            handleChange()
        end
        local isFresh = lastOutside and GetTime and GetTime() - lastOutside.time <= ENTRANCE_MAX_AGE_SECONDS
        if not record.entrance and isFresh and not lastOutside.isAway and not isCarriedByFinder() then
            record.entrance = { zoneId = lastOutside.zoneId, x = lastOutside.x, y = lastOutside.y }
            handleChange()
        end
        learningInstanceId = instanceId
        fulfilledByQuestId = readFulfilled()
        return
    end
    if learningInstanceId then
        local record = getRecords()[learningInstanceId]
        isLeavingToEntrance = record ~= nil and not record.entrance and not isCarriedByFinder()
        if isLeavingToEntrance then
            local leftInstanceId = learningInstanceId
            -- Walking out puts the player at the way in, once the world has its map again
            C_Timer.After(SAMPLE_SECONDS, function()
                -- (not dead, a ghost or at an inn: one who died or hearthed out is not at the way in)
                local place = isLeavingToEntrance and not isAwayFromEntrance() and getPlayerPlace()
                local left = getRecords()[leftInstanceId]
                if place and left and not left.entrance then
                    left.entrance = place
                    handleChange()
                end
                isLeavingToEntrance = false
            end)
        end
    end
    learningInstanceId = nil
end

---Reacts to the game: going in or out of an instance, quests picked up, handed in or moved on while inside.
function LearnedDungeons.handleEvent(event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        handleWorldEntered()
    elseif not learningInstanceId then
        return
    elseif event == "QUEST_ACCEPTED" then
        local first, second = ...
        learnQuest(second or first, true) -- the quest's ID comes second on older clients
    elseif event == "QUEST_TURNED_IN" then
        learnQuest((...))
    elseif event == "QUEST_LOG_UPDATE" then
        learnProgress()
    end
end

---Notes the place outside every few seconds, so the entrance is known on going in.
function LearnedDungeons.notePlace()
    if IsInInstance and IsInInstance() then
        return
    end
    local place = getPlayerPlace()
    if place then
        place.time = GetTime and GetTime() or 0
        -- A place at an inn or in a city is no way in: summoned in from there, the entrance is not where the player was
        -- (a ghost walking back in is at the way in, so that counts)
        place.isAway = isResting() or nil
        lastOutside = place
    end
end

function LearnedDungeons.create()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE" }) do
        pcall(frame.RegisterEvent, frame, event)
    end
    frame:SetScript("OnEvent", function(_, event, ...)
        LearnedDungeons.handleEvent(event, ...)
    end)
    C_Timer.NewTicker(SAMPLE_SECONDS, LearnedDungeons.notePlace)
    handleWorldEntered() -- logged in inside an instance
end

---The learned dungeons, for the missed-quest report: what the quest database lacks, to pass on to its makers.
---@return string[] lines
function LearnedDungeons.composeReportLines()
    local lines = {}
    for instanceId, record in pairs(getRecords()) do
        local entrance = record.entrance
                and string.format(
                    "%s %.1f, %.1f",
                    ns.Database.getZoneName(record.entrance.zoneId),
                    record.entrance.x,
                    record.entrance.y
                )
            or "-"
        local questIds = {}
        for questId in pairs(record.questIds) do
            questIds[#questIds + 1] = tostring(questId) .. (record.pickedUpQuestIds[questId] and "*" or "")
        end
        table.sort(questIds)
        lines[#lines + 1] = string.format(
            "%d | %s | %s | %s",
            instanceId,
            record.name,
            entrance,
            #questIds > 0 and table.concat(questIds, ", ") or "-"
        )
    end
    table.sort(lines)
    return lines
end

---Forgets the cached dungeons and the state of a run, for tests.
function LearnedDungeons.reset()
    lastOutside, learningInstanceId, isLeavingToEntrance, fulfilledByQuestId, instanceIdByQuestId =
        nil, nil, false, {}, nil
    ns.Database.forgetDungeons()
end

ns.registerModule({ name = "LearnedDungeons", create = LearnedDungeons.create })
