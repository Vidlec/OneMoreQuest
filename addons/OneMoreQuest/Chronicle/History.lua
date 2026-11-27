local _, ns = ...

-- The character's quest history, from every source that keeps one: OneMoreQuest's own chronicle, other addons'
-- (Questie's journey), and the game's own record of completed quests. Each source is a provider; their records
-- are merged into one history, which the chronicle's pages read.
--
-- A quest found in more than one provider is one entry: the most trusted provider's record (the lowest order) is the
-- entry, and fields it has no value for are filled in from the others (when the quest was accepted, at what level).
-- A record with a date and another without (the game's list says only "done") are the same hand-in; two dated ones are
-- the same within MATCH_SECONDS of each other, else two hand-ins of a quest done again (a repeatable one).
local History = {}
ns.History = History

local MATCH_SECONDS = 15 * 60
-- What another provider may fill in on an entry that has no value for it; the rest is the entry's own
local FILLABLE = { "acceptedAt", "turnedInAt", "acceptedLevel", "playerLevel", "duration" }

---@class HistoryProvider
---@field name string The source's name: "OneMoreQuest", "Questie", "Game"
---@field order number Lower is more trusted: its record is the entry, the others only fill in
---@field isAvailable (fun(): boolean)? Whether it has anything now; without it, always
---@field getCompletions fun(): table[] Each hand-in: questId, and what it knows (turnedInAt, acceptedAt, playerLevel,
---acceptedLevel, duration, experience, money, ...); turnedInAt nil for one known only as done
---@field getLevelUps (fun(): { level: number, at: number }[])? When each level was reached

local providers = {} ---@type HistoryProvider[]
local merged -- { entries, undated, levelUps }, worked out when first asked after a change

---@param provider HistoryProvider
function History.registerProvider(provider)
    providers[#providers + 1] = provider
    table.sort(providers, function(first, second)
        return first.order < second.order
    end)
    merged = nil
end

---Forgets the merged history: a provider's records changed (a quest handed in, another addon's history read).
function History.invalidate()
    merged = nil
end

---@return HistoryProvider[] providers Those that have something now, most trusted first
local function getAvailableProviders()
    local available = {}
    for _, provider in ipairs(providers) do
        local isFine, isAvailable = true, true
        if provider.isAvailable then
            isFine, isAvailable = pcall(provider.isAvailable)
        end
        if isFine and isAvailable then
            available[#available + 1] = provider
        end
    end
    return available
end

-- A merged entry reads as its most trusted record, with the fields others filled in on top
local function createEntry(record, source)
    local entry = setmetatable({ sources = { source } }, { __index = record })
    entry.record = record
    return entry
end

---@return boolean isSame A record is the same hand-in as an entry already merged
local function isSameHandIn(entry, record)
    local first, second = entry.turnedInAt, record.turnedInAt
    if not first or not second then
        return true -- one of them knows only that it was done
    end
    return math.abs(first - second) <= MATCH_SECONDS
end

---@return table? entry The merged entry a provider's record is the same hand-in as, one that provider has not
---matched yet
local function findMatch(byQuest, record, providerName)
    for _, entry in ipairs(record.questId and byQuest[record.questId] or {}) do
        if not entry.isMatchedBy or not entry.isMatchedBy[providerName] then
            if isSameHandIn(entry, record) then
                return entry
            end
        end
    end
    return nil
end

---Known to a more trusted provider already: only what it lacks is taken from this one.
local function fillIn(match, record, providerName)
    for _, key in ipairs(FILLABLE) do
        if match[key] == nil and record[key] ~= nil then
            rawset(match, key, record[key])
        end
    end
    match.isMatchedBy = match.isMatchedBy or {}
    match.isMatchedBy[providerName] = true
    match.sources[#match.sources + 1] = providerName
end

---@return table[] records A provider's hand-ins, or none when it fails
local function readCompletions(provider)
    local isFine, records = pcall(provider.getCompletions)
    return isFine and type(records) == "table" and records or {}
end

---Every provider's records, merged into entries (and indexed by quest in byQuest), most trusted first.
---@return table[] entries
---@return table levelUps From the first provider that keeps them
local function mergeProviders()
    local entries, byQuest, levelUps = {}, {}, {}
    for _, provider in ipairs(getAvailableProviders()) do
        for _, record in ipairs(readCompletions(provider)) do
            local questId = record.questId
            local match = findMatch(byQuest, record, provider.name)
            if match then
                fillIn(match, record, provider.name)
            elseif questId then
                local entry = createEntry(record, provider.name)
                entry.isMatchedBy = { [provider.name] = true }
                byQuest[questId] = byQuest[questId] or {}
                table.insert(byQuest[questId], entry)
                entries[#entries + 1] = entry
            end
        end
        if provider.getLevelUps and #levelUps == 0 then
            local isRead, ups = pcall(provider.getLevelUps)
            levelUps = isRead and type(ups) == "table" and ups or levelUps
        end
    end
    return entries, levelUps
end

local function merge()
    local entries, levelUps = mergeProviders()
    local dated, undated = {}, {}
    for _, entry in ipairs(entries) do
        if entry.turnedInAt then
            dated[#dated + 1] = entry
        else
            undated[#undated + 1] = entry
        end
    end
    -- Oldest first, as the chronicle has always kept them; the same moment in the order the providers gave them
    for index, entry in ipairs(dated) do
        rawset(entry, "position", index)
    end
    table.sort(dated, function(first, second)
        if first.turnedInAt ~= second.turnedInAt then
            return first.turnedInAt < second.turnedInAt
        end
        return first.position < second.position
    end)
    return { entries = dated, undated = undated, levelUps = levelUps }
end

local function getMerged()
    merged = merged or merge()
    return merged
end

---@return table[] entries Every hand-in with a date, from all providers, oldest first. Each reads as its most trusted
---record (sources lists every provider that knew it; record is that most trusted one)
function History.getEntries()
    return getMerged().entries
end

---@return table[] entries Quests known only as done, without a date (the game's own record, for those no provider
---dates), each with its questId
function History.getUndated()
    return getMerged().undated
end

---@return { level: number, at: number }[] levelUps When each level was reached, from the first provider that keeps it
function History.getLevelUps()
    return getMerged().levelUps
end

---@return string[] names The providers that have something now, most trusted first
function History.getSourceNames()
    local names = {}
    for _, provider in ipairs(getAvailableProviders()) do
        names[#names + 1] = provider.name
    end
    return names
end

-- The game's own record: which quests are done, without dates. The least trusted: it only says "done"
History.registerProvider({
    name = "Game",
    order = 90,
    getCompletions = function()
        local records = {}
        if C_QuestLog and C_QuestLog.GetAllCompletedQuestIDs then
            for _, questId in ipairs(C_QuestLog.GetAllCompletedQuestIDs() or {}) do
                records[#records + 1] = { questId = questId }
            end
        elseif GetQuestsCompleted then
            for questId in pairs(GetQuestsCompleted() or {}) do
                records[#records + 1] = { questId = questId }
            end
        end
        return records
    end,
})
