local _, ns = ...

-- DungeonJournal (folder ForeverDungeonJournal): a journal of every dungeon in WoW: Forever with its quests and the
-- way in, including the dungeons Forever added that QuestieDB does not know (the Drowned City, Blackmaw Hold...). It is
-- a quest provider (Database.registerProvider), asked after QuestieDB: for a quest QuestieDB files nowhere, the
-- journal's dungeon is where it belongs (Ancient Gurubashi Idol, the Drowned City), with its level and objective as
-- the journal has them. Only its data is read (the global table it shares, ForeverDungeonJournal_NS.DB); nothing of
-- the journal's is called or changed.

---@return table? journal The journal's dungeons by name, when the addon has loaded them
local function getJournal()
    local namespace = rawget(_G, "ForeverDungeonJournal_NS")
    local journal = type(namespace) == "table" and namespace.DB
    return type(journal) == "table" and journal or nil
end

local function isAvailable()
    return ns.isAddOnLoaded("ForeverDungeonJournal") and getJournal() ~= nil
end

local questsById -- questId -> { quest = the journal's entry, dungeonName = string }, built on first use
local function getQuests()
    if questsById then
        return questsById
    end
    questsById = {}
    for name, entry in pairs(getJournal() or {}) do
        for _, quest in
            ipairs(
                type(name) == "string" and type(entry) == "table" and type(entry.quests) == "table" and entry.quests
                    or {}
            )
        do
            if type(quest) == "table" and type(quest.id) == "number" and not questsById[quest.id] then
                questsById[quest.id] = { quest = quest, dungeonName = name }
            end
        end
    end
    return questsById
end

-- The quest fields the journal has, as QuestieDB names them
local FIELDS = {
    zoneOrSort = function(listed)
        local dungeon = ns.Database.getDungeonByName(listed.dungeonName)
        return dungeon and dungeon.areaId or nil
    end,
    questLevel = function(listed)
        return tonumber(listed.quest.level)
    end,
    requiredLevel = function(listed)
        return tonumber(listed.quest.requires)
    end,
    objectivesText = function(listed)
        return type(listed.quest.objective) == "string" and listed.quest.objective ~= "" and { listed.quest.objective }
            or nil
    end,
}

local npcsById -- npcId -> { name, spawns }, built on first use
---Who gives and takes the journal's quests, and where they stand: its quests' start and turn-in spots, each named,
---given to the creature QuestieDB says starts or ends that quest. QuestieDB is asked first, so only creatures it
---lacks (Forever's own) are filled in this way.
local function getNpcs()
    if npcsById then
        return npcsById
    end
    npcsById = {}
    local function add(spot, npcIds)
        local npcId = type(npcIds) == "table" and type(npcIds[1]) == "table" and npcIds[1][1]
        local zoneId = type(spot) == "table" and type(spot.mapID) == "number" and ns.Database.getAreaId(spot.mapID)
        if type(npcId) ~= "number" or not zoneId or type(spot.x) ~= "number" or type(spot.y) ~= "number" then
            return
        end
        local npc = npcsById[npcId]
        if not npc then
            npc = { name = type(spot.targetName) == "string" and spot.targetName or nil, spawns = {} }
            npcsById[npcId] = npc
        end
        local points = npc.spawns[zoneId] or {}
        npc.spawns[zoneId] = points
        local x, y = math.floor(spot.x * 1000 + 0.5) / 10, math.floor(spot.y * 1000 + 0.5) / 10
        for _, point in ipairs(points) do
            if point[1] == x and point[2] == y then
                return
            end
        end
        points[#points + 1] = { x, y }
    end
    for questId, listed in pairs(getQuests()) do
        add(listed.quest.startMap, ns.Database.getQuestField(questId, "startedBy"))
        add(listed.quest.turninMap, ns.Database.getQuestField(questId, "finishedBy"))
    end
    return npcsById
end

ns.Database.registerProvider({
    name = "DungeonJournal",
    order = 20,
    isAvailable = isAvailable,
    questFields = { zoneOrSort = true, questLevel = true, requiredLevel = true, objectivesText = true }, -- FIELDS' keys
    getQuestField = function(questId, field)
        local read, listed = FIELDS[field], getQuests()[questId]
        return read and listed and read(listed) or nil
    end,
    getNpcField = function(npcId, field)
        local npc = getNpcs()[npcId]
        return npc and (field == "name" or field == "spawns") and npc[field] or nil
    end,
    getDungeons = function()
        local list = {}
        for name, entry in pairs(getJournal() or {}) do
            if type(name) == "string" and type(entry) == "table" then
                local way, entrances = type(entry.entrance) == "table" and entry.entrance, {}
                local zoneId = way and type(way.mapID) == "number" and ns.Database.getAreaId(way.mapID)
                if zoneId and type(way.x) == "number" and type(way.y) == "number" then
                    entrances[1] = {
                        zoneId = zoneId,
                        x = math.floor(way.x * 1000 + 0.5) / 10,
                        y = math.floor(way.y * 1000 + 0.5) / 10,
                    }
                end
                list[#list + 1] = { name = name, entrances = entrances, isLearned = true }
            end
        end
        table.sort(list, function(first, second)
            return first.name < second.name
        end)
        return list
    end,
})

-- Opening the journal on a dungeon, for the Dungeons tab's button. Its own name matching finds the dungeon however
-- the game or QuestieDB spell it ("Deadmines", "The Deadmines"); its page is opened with its own function.
---@return string? key The journal's name for the dungeon
local function findJournalKey(name)
    local namespace = rawget(_G, "ForeverDungeonJournal_NS")
    if not isAvailable() or type(name) ~= "string" then
        return nil
    end
    local journal = namespace.DB
    if journal[name] then
        return name
    end
    if type(namespace.DungeonFromInstanceName) == "function" then
        local isFine, key = pcall(namespace.DungeonFromInstanceName, name)
        return isFine and type(key) == "string" and journal[key] and key or nil
    end
    return nil
end

ns.DungeonJournal = {
    ---@return boolean knows The journal has a page for the dungeon
    knows = function(name)
        return findJournalKey(name) ~= nil
    end,
    ---Opens the journal on the dungeon's page (its window is made the first time it opens).
    open = function(name)
        local key = findJournalKey(name)
        if not key then
            return
        end
        local namespace = rawget(_G, "ForeverDungeonJournal_NS")
        local frame = rawget(_G, "ForeverDungeonJournalFrame")
        if
            not (type(frame) == "table" and frame.IsShown and frame:IsShown())
            and type(rawget(_G, "ForeverDungeonJournal_Toggle")) == "function"
        then
            pcall(_G.ForeverDungeonJournal_Toggle)
        end
        if type(namespace.OpenBossPage) == "function" then
            pcall(namespace.OpenBossPage, key)
        end
    end,
}

-- Its line on the About page
ns.Compatibility.register({
    name = "ForeverDungeonJournal",
    label = "DungeonJournal",
    about = "Its dungeons and their quests fill in what the quest database lacks: Forever's own dungeons are listed with their quests and entrances from the start.",
    detect = isAvailable,
})
