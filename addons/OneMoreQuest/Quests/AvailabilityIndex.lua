local _, ns = ...

-- The index Availability reads its lists from, built once after login from every quest of the database: the quests
-- picked up and handed in in each zone, the quests of each dungeon and the chains that lead into it, the quests each
-- one opens, the steps done back to back, the city donations, and what each quest's availability reads (other
-- quests, reputations, skills, spells) so that a change forgets only the answers it bears on. Built in the
-- background, a frame's share of the clock at a time (AvailabilityIndex.build).
local AvailabilityIndex = {}
ns.AvailabilityIndex = AvailabilityIndex

local Availability = ns.Availability

local QUESTS_PER_STEP = 400 -- the most quests indexed in one frame, whatever the clock says
local INDEX_SLICE_MILLISECONDS = 4 -- a frame's share of the indexing after login, while nobody waits for it
local INDEX_WAITED_MILLISECONDS = 12 -- and while the quest window is open, which may be waiting for the lists
local INDEX_MIN_QUESTS = 10 -- at least this many a frame

-- A city donation is a quest of one name filed in this many capitals or more, asking only for items and paying
-- in reputation: "A Donation of Wool" to "A Donation of Runecloth", one at each city's quartermaster
local MIN_DONATION_CAPITALS = 3

-- The fields of a quest that name the other quests its availability reads (Availability's isClosedByOtherQuest and
-- haveEarlierQuestsOpened read exactly these): the index notes, for every quest, whose availability reads it
-- (index.dependents), so that a quest taken, dropped or handed in forgets only its own answer and theirs.
local DEPENDENCY_FIELDS = {
    "preQuestSingle",
    "preQuestGroup",
    "parentQuest",
    "nextQuestInChain",
    "breadcrumbForQuestId",
    "exclusiveTo",
    "disabledByQuest",
    "availableUntilCompleted",
    "availableStartingWith",
}
local PRE_QUEST_FIELDS = { "preQuestSingle", "preQuestGroup" } -- the quests asked for first
local REPUTATION_FIELDS = { "requiredMinRep", "requiredMaxRep" }

---Adds a value to the list kept under a key, the list made on first use.
local function appendTo(lists, key, value)
    lists[key] = lists[key] or {}
    table.insert(lists[key], value)
end

---A quest that starts inside a dungeon is filed under the dungeon and under the zone its entrance stands in,
---where the map marks it at the way in. Only the map: the zone's lists and counts leave it to the dungeon, as
---entranceQuestIds notes (Availability.getEntranceDungeons).
---@param entranceQuestIds table? [zoneId][questId] = dungeonId, for quests the zone holds only for its entrance
local function addToZones(questIdsByZoneId, places, questId, entranceQuestIds)
    local seenZones, outsideZones, entranceDungeons = {}, {}, {}
    for _, place in ipairs(places) do
        local dungeon = place.groupZoneId ~= place.mapZoneId and ns.Database.getDungeon(place.groupZoneId)
        if dungeon and place.mapZoneId then
            entranceDungeons[place.mapZoneId] = dungeon.areaId
        elseif not dungeon then
            for _, zoneId in ipairs({ place.mapZoneId, place.groupZoneId }) do
                outsideZones[zoneId] = true
            end
        end
        for _, zoneId in ipairs({ place.groupZoneId, place.mapZoneId }) do
            if not seenZones[zoneId] then
                seenZones[zoneId] = true
                appendTo(questIdsByZoneId, zoneId, questId)
            end
        end
    end
    for zoneId, dungeonId in pairs(entranceQuestIds and entranceDungeons or {}) do
        if not outsideZones[zoneId] then
            entranceQuestIds[zoneId] = entranceQuestIds[zoneId] or {}
            entranceQuestIds[zoneId][questId] = dungeonId
        end
    end
end

---@return table set The NPCs and objects a quest's field names, as "npc:id" and "object:id"
local function getHands(questId, field)
    local hands, list = {}, ns.Database.getQuestField(questId, field) or {}
    for _, npcId in ipairs(list[1] or {}) do
        hands["npc:" .. npcId] = true
    end
    for _, objectId in ipairs(list[2] or {}) do
        hands["object:" .. objectId] = true
    end
    return hands
end

---@return boolean asksNothing The quest has nothing to do: no objectives, no event to bring about, and nothing in
---its words
local function asksNothing(questId)
    local get = ns.Database.getQuestField
    -- No event to bring about either (Test of Lore's "answer Braug Dimspirit's question correctly" is one, a quiz,
    -- though it has no objectives)
    if next(get(questId, "objectives") or {}) ~= nil or get(questId, "triggerEnd") then
        return false
    end
    -- and nothing in its words: the data leaves out some work ("Defeat Kronk in the Bloodmaster's Ring", "Wait
    -- for Jordan Stilwell to finish forging"), which its text still asks for
    local objectivesText = get(questId, "objectivesText")
    return not (type(objectivesText) == "table" and table.concat(objectivesText, ""):match("%S"))
end

---A step done straight after the one before: the same name, nothing to do, taken and handed back where the
---step before was handed in (the Sparklematic 5200!'s second step, Restoring the Necklace's, Signal for Pickup's).
---@return number[] previousQuestIds The steps it follows: one, or each version of it (Summon Felsteed's, one
---per warlock trainer, all lead to the same second step)
local function getInstantStepsBefore(questId)
    local get = ns.Database.getQuestField
    local name, previousQuestIds = get(questId, "name"), {}
    if not name or not asksNothing(questId) then
        return previousQuestIds
    end
    local starters, finishers = getHands(questId, "startedBy"), getHands(questId, "finishedBy")
    for hand in pairs(starters) do
        if not finishers[hand] then
            return previousQuestIds
        end
    end
    for _, field in ipairs(PRE_QUEST_FIELDS) do
        for _, signedQuestId in ipairs(get(questId, field) or {}) do
            local previousQuestId = math.abs(signedQuestId)
            if get(previousQuestId, "name") == name then
                for hand in pairs(getHands(previousQuestId, "finishedBy")) do
                    if starters[hand] then
                        previousQuestIds[#previousQuestIds + 1] = previousQuestId
                        break
                    end
                end
            end
        end
    end
    return previousQuestIds
end

---@param requirements table [id] = { thresholds, questIds }: the quests asking for a standing or a rank, by faction or skill
local function addRequirement(requirements, id, threshold, questId)
    local requirement = requirements[id]
    if not requirement then
        requirement = { thresholds = {}, questIds = {} }
        requirements[id] = requirement
    end
    requirement.thresholds[#requirement.thresholds + 1] = threshold
    requirement.questIds[#requirement.questIds + 1] = questId
end

local function addDependent(dependents, otherQuestId, questId)
    if type(otherQuestId) == "number" and otherQuestId ~= 0 then
        appendTo(dependents, math.abs(otherQuestId), questId)
    end
end

---Whose availability reads this quest's: for forgetting, when one of those changes, only the answers it bears on
---(Availability's forgetQuests).
local function noteDependents(newIndex, questId)
    local get = ns.Database.getQuestField
    for _, field in ipairs(DEPENDENCY_FIELDS) do
        local value = get(questId, field)
        if type(value) == "table" then
            for _, otherQuestId in ipairs(value) do
                addDependent(newIndex.dependents, otherQuestId, questId)
            end
        else
            addDependent(newIndex.dependents, value, questId)
        end
    end
    -- An earlier quest's other side of a choice stands in for it (isDoneOrChosenOther): that one is read too
    for _, field in ipairs(PRE_QUEST_FIELDS) do
        for _, preQuestId in ipairs(get(questId, field) or {}) do
            for _, otherQuestId in ipairs(get(math.abs(preQuestId), "exclusiveTo") or {}) do
                appendTo(newIndex.dependents, otherQuestId, questId)
            end
        end
    end
end

---What of the character the quest asks for, its reputations, skill and spells: for forgetting, when one of those
---changes, only the answers it bears on (Availability's settleCharacterChanges).
local function noteRequirements(newIndex, questId)
    local get = ns.Database.getQuestField
    for _, field in ipairs(REPUTATION_FIELDS) do
        local requirement = get(questId, field)
        if type(requirement) == "table" and requirement[1] then
            addRequirement(newIndex.reputation, requirement[1], requirement[2] or 0, questId)
        end
    end
    local skill = get(questId, "requiredSkill")
    if type(skill) == "table" and skill[1] then
        addRequirement(newIndex.skill, skill[1], 1, questId) -- (learnt at all)
        addRequirement(newIndex.skill, skill[1], skill[2] or 0, questId)
    end
    if (get(questId, "requiredSpell") or 0) ~= 0 or (get(questId, "requiredSpecialization") or 0) ~= 0 then
        newIndex.spellStates[questId] = "unknown"
    end
end

---A candidate city donation: filed in a capital, asking only for items, paying in reputation. Counted by name, and
---by the capitals it is filed in (finishIndex keeps those in MIN_DONATION_CAPITALS or more).
local function noteDonationCandidate(newIndex, questId)
    local get = ns.Database.getQuestField
    local filedZoneId, objectives = get(questId, "zoneOrSort") or 0, get(questId, "objectives") or {}
    if
        filedZoneId <= 0
        or not ns.Database.isCapital(filedZoneId)
        or not objectives[3]
        or objectives[1]
        or objectives[2]
        or objectives[5]
        or not get(questId, "reputationReward")
    then
        return
    end
    local name = get(questId, "name") or ""
    local candidate = newIndex.donationCandidates[name] or { questIds = {}, capitals = {}, capitalCount = 0 }
    newIndex.donationCandidates[name] = candidate
    candidate.questIds[#candidate.questIds + 1] = questId
    if not candidate.capitals[filedZoneId] then
        candidate.capitals[filedZoneId], candidate.capitalCount = true, candidate.capitalCount + 1
    end
end

---The steps done back to back with this one (getInstantStepsBefore), both ways.
local function noteInstantSteps(newIndex, questId)
    for _, previousQuestId in ipairs(getInstantStepsBefore(questId)) do
        newIndex.instantStepAfter[previousQuestId] = questId
        newIndex.isInstantStep[questId] = newIndex.isInstantStep[questId] or previousQuestId
    end
end

---The quests each one opens: read off every quest's prerequisites, so chains that fork are followed forward.
local function noteFollowUps(newIndex, questId)
    for _, field in ipairs(PRE_QUEST_FIELDS) do
        for _, signedQuestId in ipairs(ns.Database.getQuestField(questId, field) or {}) do
            appendTo(newIndex.followUps, math.abs(signedQuestId), questId)
        end
    end
end

---A quest for a dungeon also counts for the dungeon, wherever its giver stands: one filed under the dungeon, or one
---whose work is all inside it.
local function fileUnderDungeons(newIndex, questId)
    -- Repeatable hand-ins (the Thorium Brotherhood's) and event quests (the Lunar Festival's elders, the Darkmoon
    -- Faire's fortunes) are not a dungeon's: they would swell its count with quests no run is for
    if not Availability.isForRun(questId) then
        return
    end
    local dungeonZoneId = ns.Location.getQuestDungeonId(questId) or ns.Location.getObjectivesDungeonId(questId)
    if dungeonZoneId then
        appendTo(newIndex.forDungeon, dungeonZoneId, questId)
    end
    -- Kept apart: the quests really done in a dungeon, the ones counted for it; one done in two counts for both
    -- (Location.getInsideDungeonIds)
    for _, insideDungeonId in ipairs(ns.Location.getInsideDungeonIds(questId)) do
        appendTo(newIndex.inDungeon, insideDungeonId, questId)
    end
end

---A quest started by an item, with no giver: filed where the item is found, and where it is handed in.
local function fileItemStart(newIndex, questId, starterPlaces)
    local itemSource = ns.Location.getStartItemSource(questId)
    if itemSource and #starterPlaces == 0 then
        addToZones(newIndex.startedInZone, itemSource.places, questId, newIndex.atEntrance)
        addToZones(newIndex.handedInZone, (ns.Location.getFinisherPlaces(questId)), questId)
    end
end

local function addQuestToIndex(newIndex, questId)
    noteDependents(newIndex, questId)
    noteRequirements(newIndex, questId)
    noteDonationCandidate(newIndex, questId)
    noteInstantSteps(newIndex, questId)
    noteFollowUps(newIndex, questId)
    local starterPlaces = ns.Location.getStarterPlaces(questId)
    addToZones(newIndex.startedInZone, starterPlaces, questId, newIndex.atEntrance)
    fileUnderDungeons(newIndex, questId)
    fileItemStart(newIndex, questId, starterPlaces)
end

---Adds a quest to a dungeon's lists, once: counted for it, and its chain led to it.
function AvailabilityIndex.addToDungeon(newIndex, dungeonId, questId)
    for _, lists in ipairs({ newIndex.inDungeon, newIndex.forDungeon }) do
        lists[dungeonId] = lists[dungeonId] or {}
        local isListed = false
        for _, listedQuestId in ipairs(lists[dungeonId]) do
            isListed = isListed or listedQuestId == questId
        end
        if not isListed then
            table.insert(lists[dungeonId], questId)
        end
    end
end

---A chain that leads into a dungeon belongs to the dungeon from its first quests on: every quest before a
---dungeon quest, down every branch of its prerequisites, and every quest after it counts for the dungeon too.
---The ones before remember which quest of the chain it is that goes in.
local function addChainsToDungeons(newIndex)
    newIndex.dungeonSteps = {}
    for dungeonZoneId, questIds in pairs(newIndex.forDungeon) do
        local steps, isListed = {}, {}
        local dungeonQuestIds = {}
        for _, questId in ipairs(questIds) do
            isListed[questId] = true
            steps[questId] = questId
            dungeonQuestIds[#dungeonQuestIds + 1] = questId
        end
        local function addChainQuest(chainQuestId)
            -- A prerequisite the database names but does not hold, such as 2955 before a Gnomeregan quest
            if not isListed[chainQuestId] and ns.Database.getQuestField(chainQuestId, "name") then
                isListed[chainQuestId] = true
                questIds[#questIds + 1] = chainQuestId
            end
        end
        for _, questId in ipairs(dungeonQuestIds) do
            local earlierQuestIds, laterQuestIds = ns.Chain.getConnectedQuestIds(questId)
            for _, earlierQuestId in ipairs(earlierQuestIds) do
                addChainQuest(earlierQuestId)
                steps[earlierQuestId] = steps[earlierQuestId] or questId
            end
            for _, laterQuestId in ipairs(laterQuestIds) do
                addChainQuest(laterQuestId)
            end
        end
        newIndex.dungeonSteps[dungeonZoneId] = steps
    end
end

---Once every quest is in: what is read off all of them together (the city donations, the dungeons learned by
---playing, the chains into dungeons, each quest's dungeon).
local function finishIndex(newIndex)
    for _, candidate in pairs(newIndex.donationCandidates) do
        for _, questId in ipairs(candidate.capitalCount >= MIN_DONATION_CAPITALS and candidate.questIds or {}) do
            newIndex.isCityDonation[questId] = true
        end
    end
    -- The dungeons learned by playing, which the database does not know
    for _, dungeonId in ipairs(ns.LearnedDungeons.getAreaIds()) do
        for _, questId in ipairs(ns.LearnedDungeons.getQuestIds(dungeonId)) do
            AvailabilityIndex.addToDungeon(newIndex, dungeonId, questId)
        end
    end
    addChainsToDungeons(newIndex)
    -- Each quest's dungeon, for a zone's list to say where it leads (the dungeon's own list has it all)
    newIndex.dungeonByQuestId = {}
    for dungeonId, questIds in pairs(newIndex.forDungeon) do
        for _, questId in ipairs(questIds) do
            local known = newIndex.dungeonByQuestId[questId]
            if not known or dungeonId < known then
                newIndex.dungeonByQuestId[questId] = dungeonId
            end
        end
    end
end

local function createIndex()
    return {
        startedInZone = {},
        handedInZone = {},
        forDungeon = {},
        inDungeon = {},
        followUps = {},
        atEntrance = {},
        instantStepAfter = {},
        isInstantStep = {},
        donationCandidates = {},
        isCityDonation = {},
        dependents = {},
        reputation = {},
        skill = {},
        spellStates = {},
    }
end

---@return number milliseconds A frame's share of the indexing: more while the quest window waits for the lists
local function getSliceBudget()
    return (ns.Log and ns.Log.isOpen and ns.Log.isOpen()) and INDEX_WAITED_MILLISECONDS or INDEX_SLICE_MILLISECONDS
end

---The first quest left out, said to the game's error handler (one is enough to tell the data has a hole).
local function reportSkippedQuest(questId, problem)
    if geterrorhandler then
        geterrorhandler()(
            "OneMoreQuest: quest " .. tostring(questId) .. " left out of the index: " .. tostring(problem)
        )
    end
end

---Builds the index from every quest of the database, a frame's share at a time, so the game never stalls.
---@param handleBuilt fun(newIndex: table) Called once with the index made
function AvailabilityIndex.build(handleBuilt)
    local questIds = ns.Database.getQuestIds()
    local newIndex = createIndex()
    local position, skippedCount = 0, 0
    local function step()
        -- A frame's share by the clock, not by a count: a count of 400 quests read some 20,000 fields of the database
        -- in one frame, a dozen frames running, and the first seconds after logging in stuttered. Where the game
        -- gives no clock (the tests), all at once.
        local started = debugprofilestop and debugprofilestop() or nil
        local budget = getSliceBudget()
        local done = 0
        while position < #questIds do
            position = position + 1
            -- (one quest's odd data skips that quest: an error here once left the index unmade for the session, and
            -- the Available tab and the givers' marks empty until a reload)
            local isIndexed, problem = pcall(addQuestToIndex, newIndex, questIds[position])
            if not isIndexed then
                skippedCount = skippedCount + 1
                if skippedCount == 1 then
                    reportSkippedQuest(questIds[position], problem)
                end
            end
            done = done + 1
            if
                done >= QUESTS_PER_STEP
                or (started and done >= INDEX_MIN_QUESTS and debugprofilestop() - started >= budget)
            then
                break
            end
        end
        if position < #questIds then
            C_Timer.After(0, step)
            return
        end
        finishIndex(newIndex)
        handleBuilt(newIndex)
    end
    step()
end
