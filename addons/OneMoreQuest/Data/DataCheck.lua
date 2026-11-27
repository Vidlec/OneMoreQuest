local _, ns = ...

-- Where WoW: Forever's quests differ from the quest database (QuestieDB), noticed as the player plays: a quest it does
-- not have, a giver or a turn-in it does not list, item objectives of other names or another number (Forever renames
-- and changes quests). Each is kept with what the game showed and what the database says, for the report the player
-- can send (/omq missing), so the database's makers can bring it up to date.
--
-- Kept small: one line per quest and kind, at most MAX_QUESTS quests, and all of it dropped when QuestieDB updates
-- (its new version may have fixed them) or the report is cleared.
local DataCheck = {}
ns.DataCheck = DataCheck

local MAX_QUESTS = 300
local OBJECTIVES_DELAY = 2 -- seconds after a quest is taken, for the game to have its objectives

local ITEMS = 3 -- the database's item objectives, in its objectives table
local checkedObjectives = {} -- [questId] = true: compared this session
local turnInNpc = {} -- [questId] = { id, name }: the one the player is handing the quest in to

---@return table differences [questId] = { title, [kind] = { game, database } }, for this QuestieDB version
local function getDifferences()
    local saved = ns.settings.dataDifferences
    local version = ns.Database.getVersion()
    if type(saved) ~= "table" or saved.version ~= version or type(saved.quests) ~= "table" then -- (or damaged: started afresh)
        saved = { version = version, quests = {} }
        ns.settings.dataDifferences = saved
    end
    return saved.quests
end

---Notes one difference of a quest, once.
---@param kind string "quest", "giver", "turnIn" or "objectives"
function DataCheck.note(questId, kind, gameText, databaseText)
    local differences = getDifferences()
    local quest = differences[questId]
    if type(quest) ~= "table" then
        local count = 0
        for _ in pairs(differences) do
            count = count + 1
        end
        if count >= MAX_QUESTS then
            return
        end
        quest = {
            title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId)
                or ns.Database.getQuestField(questId, "name"),
        }
        differences[questId] = quest
    end
    quest[kind] = quest[kind] or { gameText, databaseText }
end

function DataCheck.clear()
    ns.settings.dataDifferences = nil
end

---@return { id: number, name: string }? npc The creature the player is talking to, nil for none (an item, a shared quest)
local function getDialogNpc()
    local npcId = UnitGUID and ns.Database.getNpcId(UnitGUID("npc"))
    return npcId and { id = npcId, name = UnitName and UnitName("npc") or "?" } or nil
end

---@return boolean isListed The database lists this creature among those of a quest's field ("startedBy", "finishedBy"),
---by its id or by its name (one creature under two ids is the same person)
local function isListed(questId, field, npc)
    for _, npcId in ipairs((ns.Database.getQuestField(questId, field) or {})[1] or {}) do
        if npcId == npc.id or ns.Database.getNpcField(npcId, "name") == npc.name then
            return true
        end
    end
    return false
end

---@return string names The creatures a quest's field lists, for the report: "Name (id), ..."
local function describeListed(questId, field)
    local names = {}
    for _, npcId in ipairs((ns.Database.getQuestField(questId, field) or {})[1] or {}) do
        names[#names + 1] = string.format("%s (%d)", ns.Database.getNpcField(npcId, "name") or "?", npcId)
    end
    return #names > 0 and table.concat(names, ", ") or "none"
end

---Compares a quest in the log: its item objectives, against the database's (their number, and on an English client
---their names, which are the database's own language).
function DataCheck.checkObjectives(questId)
    if
        checkedObjectives[questId]
        or not ns.QuestState.isInLog(questId)
        or not ns.Database.getQuestField(questId, "name")
    then
        return
    end
    checkedObjectives[questId] = true
    local gameItems = {}
    for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questId) or {}) do
        if objective.type == "item" then
            gameItems[#gameItems + 1] = ns.QuestState.getObjectiveLabel(objective.text)
        end
    end
    local databaseItems = {}
    for _, item in ipairs((ns.Database.getQuestField(questId, "objectives") or {})[ITEMS] or {}) do
        databaseItems[#databaseItems + 1] = ns.Database.getItemField(item[1], "name") or ("item " .. tostring(item[1]))
    end
    local isEnglish = not GetLocale or GetLocale() == "enUS" or GetLocale() == "enGB"
    local differs = #gameItems ~= #databaseItems
    for index = 1, math.min(#gameItems, #databaseItems) do
        differs = differs or (isEnglish and gameItems[index] ~= databaseItems[index])
    end
    if differs and (#gameItems > 0 or #databaseItems > 0) then
        DataCheck.note(
            questId,
            "objectives",
            "items: " .. table.concat(gameItems, ", "),
            "items: " .. table.concat(databaseItems, ", ")
        )
    end
end

---A quest taken: one the database does not have, or from a giver it does not list.
local function handleAccepted(...)
    -- The quest's id is the last argument (an older client passes the log index before it)
    local questId = select(select("#", ...), ...)
    if type(questId) ~= "number" then
        return
    end
    local npc = getDialogNpc()
    if not ns.Database.getQuestField(questId, "name") then
        DataCheck.note(
            questId,
            "quest",
            npc and string.format("given by %s (%d)", npc.name, npc.id) or "taken",
            "not in the database"
        )
    elseif npc and not isListed(questId, "startedBy", npc) then
        DataCheck.note(
            questId,
            "giver",
            string.format("%s (%d)", npc.name, npc.id),
            describeListed(questId, "startedBy")
        )
    end
    if C_Timer then
        C_Timer.After(OBJECTIVES_DELAY, function()
            DataCheck.checkObjectives(questId)
        end)
    end
end

---The reward panel: who the quest is being handed in to, for when it is.
local function handleComplete()
    local questId = GetQuestID and GetQuestID()
    if questId and questId > 0 then
        turnInNpc[questId] = getDialogNpc()
    end
end

---A quest handed in to someone the database does not list as its turn-in.
local function handleTurnedIn(questId)
    local npc = turnInNpc[questId]
    turnInNpc[questId] = nil
    if npc and ns.Database.getQuestField(questId, "name") and not isListed(questId, "finishedBy", npc) then
        DataCheck.note(
            questId,
            "turnIn",
            string.format("%s (%d)", npc.name, npc.id),
            describeListed(questId, "finishedBy")
        )
    end
end

local KIND_NAMES = { quest = "not in the database", giver = "giver", turnIn = "turn-in", objectives = "objectives" }
local KIND_ORDER = { "quest", "giver", "turnIn", "objectives" }

---@return string[] lines The differences, for the report: "quest | title | what | the game | QuestieDB"
function DataCheck.composeReportLines()
    local lines = {}
    for questId, quest in pairs(getDifferences()) do
        for _, kind in ipairs(type(questId) == "number" and type(quest) == "table" and KIND_ORDER or {}) do
            local difference = quest[kind]
            if type(difference) == "table" then
                lines[#lines + 1] = string.format(
                    "%d | %s | %s | %s | %s",
                    questId,
                    quest.title or "?",
                    KIND_NAMES[kind],
                    difference[1] or "?",
                    difference[2] or "?"
                )
            end
        end
    end
    table.sort(lines, function(first, second)
        return tonumber(first:match("^%d+")) < tonumber(second:match("^%d+"))
    end)
    return lines
end

ns.registerModule({
    name = "DataCheck",
    -- The quests already in the log, once the game has listed them
    create = function()
        if C_Timer then
            C_Timer.After(OBJECTIVES_DELAY * 5, function()
                for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
                    DataCheck.checkObjectives(questId)
                end
            end)
        end
    end,
    events = { QUEST_ACCEPTED = handleAccepted, QUEST_COMPLETE = handleComplete, QUEST_TURNED_IN = handleTurnedIn },
})
