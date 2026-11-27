local _, ns = ...

-- A quest's place in its chain, from the single prerequisite going back and the follow-up going forward.
-- Chains that fork or need several quests at once are cut at that point.
local Chain = {}
ns.Chain = Chain

local MAX_STEPS = 40
local MAX_STEPS_BACK = 100 -- (a guard against a loop in the data: chains are far shorter)

---@return number? questId The one quest this one needs first: its prerequisite, when there is just one
local function getPreviousQuestId(questId)
    local single = ns.Database.getQuestField(questId, "preQuestSingle")
    if single and #single == 1 then
        return math.abs(single[1])
    end
    local group = ns.Database.getQuestField(questId, "preQuestGroup")
    if group and #group == 1 then
        return math.abs(group[1])
    end
    return nil
end

local function getNextQuestId(questId)
    local nextQuestId = ns.Database.getQuestField(questId, "nextQuestInChain")
    return nextQuestId and nextQuestId ~= 0 and nextQuestId or nil
end

local UNKNOWN = false -- what comes after a quest cannot be told yet (the quests each one opens are not indexed yet)

---@return number|false|nil questId The quest that comes after this one in its chain: the one the database names next,
---else the one quest that needs this one alone first; nil for none (or several: a fork), UNKNOWN while the quests
---each one opens are not known yet
local function getFollowingQuestId(questId)
    local nextQuestId = getNextQuestId(questId)
    if nextQuestId then
        return nextQuestId
    end
    local followUps = ns.Availability and ns.Availability.getFollowUps and ns.Availability.getFollowUps(questId)
    if type(followUps) ~= "table" then
        return UNKNOWN
    end
    local found
    for _, followUpQuestId in ipairs(followUps) do
        if followUpQuestId ~= found and getPreviousQuestId(followUpQuestId) == questId then
            if found then
                return nil -- two quests need it alone: a fork, where the chain stops
            end
            found = followUpQuestId
        end
    end
    return found
end

-- A step of a chain leads to the next only when both agree: the first names the second as what comes after it (or the
-- second is the one quest that needs it alone), and the second needs the first alone. Read from one side only, a
-- chain was one length and order asked from its first quest and another asked from a later one (one that needs two
-- quests at once, where the chain is cut): it is the same chain, however it is asked for, from either end.

---@return number? questId The quest after this one in its chain, nil at its end
local function getLaterQuestId(questId)
    local laterQuestId = getFollowingQuestId(questId)
    return laterQuestId and getPreviousQuestId(laterQuestId) == questId and laterQuestId or nil
end

---@return number? questId The quest before this one in its chain, nil at its start
local function getEarlierQuestId(questId)
    local earlierQuestId = getPreviousQuestId(questId)
    if not earlierQuestId then
        return nil
    end
    local following = getFollowingQuestId(earlierQuestId)
    -- (while the quests each one opens are not known, the prerequisite is taken at its word, as it always was)
    return (following == questId or following == UNKNOWN) and earlierQuestId or nil
end

---@return number[] questIds Every quest of the chain in order, each of them, back-to-back steps too: the same list
---whichever of its quests is asked for
local function getLinkedQuestIds(questId)
    -- Back to where the chain starts, then forward from there
    local firstQuestId, seen, count = questId, { [questId] = true }, 0
    local earlierQuestId = getEarlierQuestId(questId)
    while earlierQuestId and not seen[earlierQuestId] and count < MAX_STEPS_BACK do
        seen[earlierQuestId], count = true, count + 1
        firstQuestId = earlierQuestId
        earlierQuestId = getEarlierQuestId(earlierQuestId)
    end
    local questIds, isListed = { firstQuestId }, { [firstQuestId] = true }
    local laterQuestId = getLaterQuestId(firstQuestId)
    while laterQuestId and not isListed[laterQuestId] and #questIds < MAX_STEPS do
        isListed[laterQuestId] = true
        questIds[#questIds + 1] = laterQuestId
        laterQuestId = getLaterQuestId(laterQuestId)
    end
    if not isListed[questId] then
        -- (a chain longer than the steps listed, asked from past them: from the quest itself on)
        questIds, laterQuestId = { questId }, getLaterQuestId(questId)
        while laterQuestId and not seen[laterQuestId] and #questIds < MAX_STEPS do
            seen[laterQuestId] = true
            questIds[#questIds + 1] = laterQuestId
            laterQuestId = getLaterQuestId(laterQuestId)
        end
    end
    return questIds
end

---@return number[] steps The chain's quests, a step done straight after the one before (Test of Lore's, taken and
---handed back at once) one step with it, standing as the last of them: done when that is
local function composeSteps(questIds)
    local steps = {}
    for position, chainQuestId in ipairs(questIds) do
        local isFollowedAtOnce = ns.Availability.getInstantStepBefore(questIds[position + 1] or 0) == chainQuestId
        if not isFollowedAtOnce then
            steps[#steps + 1] = chainQuestId
        end
    end
    return steps
end

---@return number? index Position of the quest in its chain, nil when it is not part of one; steps done back to
---back count as one
---@return number? total
function Chain.getStep(questId)
    local questIds = getLinkedQuestIds(questId)
    if #questIds < 2 then
        return nil
    end
    -- Steps done back to back are one step of the chain, as their row is one (Chain.getQuestIds)
    local steps = composeSteps(questIds)
    if #steps < 2 then
        return nil
    end
    local positionByQuestId = {}
    for position, stepQuestId in ipairs(steps) do
        positionByQuestId[stepQuestId] = position
    end
    local lastStepQuestId = questId
    for _, stepQuestId in ipairs(ns.Availability.getInstantSteps(questId)) do
        lastStepQuestId = stepQuestId
    end
    if positionByQuestId[lastStepQuestId] then
        return positionByQuestId[lastStepQuestId], #steps
    end
    -- A quest that goes with the step after it stands at that step
    local isPast = false
    for _, chainQuestId in ipairs(questIds) do
        isPast = isPast or chainQuestId == questId
        if isPast and positionByQuestId[chainQuestId] then
            return positionByQuestId[chainQuestId], #steps
        end
    end
    return nil
end

---Every quest that comes before this one, following each prerequisite back even where the chain forks or
---needs several quests at once, and the quests that follow it. Dalaran Patrols needs both Prison Break In and
---Key to the City: both come before Heart of Disruption, two steps later.
---@return number[] earlierQuestIds
---@return number[] laterQuestIds
function Chain.getConnectedQuestIds(questId)
    local earlierQuestIds, laterQuestIds, seen = {}, {}, { [questId] = true }
    local queue, position = { questId }, 1
    while queue[position] and #earlierQuestIds < MAX_STEPS do
        local current = queue[position]
        position = position + 1
        for _, field in ipairs({ "preQuestSingle", "preQuestGroup" }) do
            for _, signedQuestId in ipairs(ns.Database.getQuestField(current, field) or {}) do
                local previousQuestId = math.abs(signedQuestId) -- (negative: one of several to choose from)
                if not seen[previousQuestId] then
                    seen[previousQuestId] = true
                    earlierQuestIds[#earlierQuestIds + 1] = previousQuestId
                    queue[#queue + 1] = previousQuestId
                end
            end
        end
    end
    local nextQuestId = getNextQuestId(questId)
    while nextQuestId and not seen[nextQuestId] and #laterQuestIds < MAX_STEPS do
        seen[nextQuestId] = true
        laterQuestIds[#laterQuestIds + 1] = nextQuestId
        nextQuestId = getNextQuestId(nextQuestId)
    end
    return earlierQuestIds, laterQuestIds
end

---@return number[] questIds Every quest of the chain in order, just the quest itself when it is not in a chain
function Chain.getQuestIds(questId)
    return composeSteps(getLinkedQuestIds(questId))
end

-- Pre-quests: a quest that has to be done before another can be picked up, without the two being one chain (a
-- fork, where one quest opens several; a quest that needs several at once; a side quest off a chain's step). Read
-- from the same fields as the chain, both ways: what a quest needs first, and what needs it.

local MAX_DIAGRAM_DEPTH = 12 -- how far back and how far on the diagram follows a quest's links: all of them, short of
local MAX_DIAGRAM_SIDE = 60 -- a loop in the data; and how many quests it shows on each side

local function isOneOf(questIds, questId)
    for _, listedQuestId in ipairs(questIds) do
        if listedQuestId == questId then
            return true
        end
    end
    return false
end

---@return table<number, boolean> isLinked The quests shown as one chain with this one, itself among them
local function getChainSet(questId)
    local isLinked = {}
    for _, linkedQuestId in ipairs(getLinkedQuestIds(questId)) do
        isLinked[linkedQuestId] = true
    end
    return isLinked
end

---@return number[] questIds The quests this one needs first, as the database lists them: any one of preQuestSingle,
---else every one of preQuestGroup (the rule a quest becomes available by, Availability.getBlocker)
---@return boolean isAnyEnough One of several is enough
function Chain.getPreviousQuestIds(questId)
    local single = ns.Database.getQuestField(questId, "preQuestSingle")
    local isSingle = type(single) == "table" and #single > 0
    local list = isSingle and single or ns.Database.getQuestField(questId, "preQuestGroup")
    local questIds, seen = {}, { [questId] = true }
    for _, signedQuestId in ipairs(type(list) == "table" and list or {}) do
        local previousQuestId = math.abs(signedQuestId)
        if not seen[previousQuestId] then
            seen[previousQuestId] = true
            questIds[#questIds + 1] = previousQuestId
        end
    end
    return questIds, isSingle and #questIds > 1
end

---@return number[] questIds The quests that need this one first and are this character's to do (not the other
---faction's or another class's), the lowest level first; with them the next step of its chain. Empty while the
---quests each one opens are not indexed yet.
function Chain.getNextQuestIds(questId)
    local get = ns.Database.getQuestField
    local questIds, seen, isNameListed = {}, { [questId] = true }, {}
    local laterQuestId = getLaterQuestId(questId)
    if laterQuestId then
        seen[laterQuestId], isNameListed[get(laterQuestId, "name") or ""] = true, true
        questIds[1] = laterQuestId
    end
    local followUps = ns.Availability and ns.Availability.getFollowUps and ns.Availability.getFollowUps(questId)
    followUps = type(followUps) == "table" and { unpack(followUps) } or {}
    table.sort(followUps) -- (the same one of a quest's versions whatever order the index was built in)
    for _, followUpQuestId in ipairs(followUps) do
        local name = get(followUpQuestId, "name")
        -- A quest in several versions (one a profession, one a battleground bracket) is one quest opened
        if
            not seen[followUpQuestId]
            and name
            and not isNameListed[name]
            and ns.Availability.isForRaceAndClass(followUpQuestId)
            and isOneOf(Chain.getPreviousQuestIds(followUpQuestId), questId)
        then
            seen[followUpQuestId], isNameListed[name] = true, true
            questIds[#questIds + 1] = followUpQuestId
        end
    end
    local function getLevel(listedQuestId)
        return get(listedQuestId, "questLevel") or 0
    end
    table.sort(questIds, function(first, second)
        local firstLevel, secondLevel = getLevel(first), getLevel(second)
        if firstLevel ~= secondLevel then
            return firstLevel < secondLevel
        end
        return first < second
    end)
    return questIds
end

---@return number[] questIds The quests this one opens that are not shown as its chain and are still to do: what
---"unlocks 2 quests" counts
function Chain.getUnlockedQuestIds(questId)
    local isLinked, questIds = getChainSet(questId), {}
    for _, nextQuestId in ipairs(Chain.getNextQuestIds(questId)) do
        if not isLinked[nextQuestId] and not ns.QuestState.isTurnedIn(nextQuestId) then
            questIds[#questIds + 1] = nextQuestId
        end
    end
    return questIds
end

---@return number[] questIds The quests this one needed first that are not shown as its chain: what it follows
---@return boolean isAnyEnough One of several was enough
function Chain.getRequiredQuestIds(questId)
    local isLinked, questIds = getChainSet(questId), {}
    local previousQuestIds, isAnyEnough = Chain.getPreviousQuestIds(questId)
    for _, previousQuestId in ipairs(previousQuestIds) do
        if not isLinked[previousQuestId] then
            questIds[#questIds + 1] = previousQuestId
        end
    end
    return questIds, isAnyEnough and #questIds > 1
end

---Which quests a side of the diagram has room for: the nearest first, each once, however many ways lead to it.
---@return table<number, number[]> children [quest] = the quests drawn under it
---@return boolean isCut Some were left out (too far, or too many)
local function collectTree(rootQuestId, getChildren, seen)
    local children, isCut, count = {}, false, 0
    local queue, position = { { rootQuestId, 0 } }, 1
    while queue[position] do
        local current, depth = queue[position][1], queue[position][2]
        position = position + 1
        children[current] = {}
        for _, childQuestId in ipairs(getChildren(current)) do
            if not seen[childQuestId] then
                if depth < MAX_DIAGRAM_DEPTH and count < MAX_DIAGRAM_SIDE then
                    seen[childQuestId], count = true, count + 1
                    table.insert(children[current], childQuestId)
                    queue[#queue + 1] = { childQuestId, depth + 1 }
                else
                    isCut = true
                end
            end
        end
    end
    return children, isCut
end

---@class ChainDiagramNode
---@field questId number
---@field children ChainDiagramNode[] Before the quest: what this one needs first; after it: what this one opens

---A quest among the ones around it: what it needs first and what those need, going back, and what it opens and what
---those open, going on. Chain steps are among them, as any other link; each quest is there once.
---@return { questId: number, before: ChainDiagramNode[], after: ChainDiagramNode[], isCutBefore: boolean, isCutAfter: boolean } diagram
function Chain.getDiagram(questId)
    local seen = { [questId] = true }
    local before, isCutBefore = collectTree(questId, Chain.getPreviousQuestIds, seen)
    local after, isCutAfter = collectTree(questId, Chain.getNextQuestIds, seen)
    local function compose(children, current)
        local nodes = {}
        for _, childQuestId in ipairs(children[current]) do
            nodes[#nodes + 1] = { questId = childQuestId, children = compose(children, childQuestId) }
        end
        return nodes
    end
    return {
        questId = questId,
        before = compose(before, questId),
        after = compose(after, questId),
        isCutBefore = isCutBefore,
        isCutAfter = isCutAfter,
    }
end

---@return string text "Unlocks Sting of the Scorpid" for one quest that may be named, else "Unlocks 2 quests"
function Chain.composeUnlockText(questIds, canName)
    if #questIds == 1 and canName then
        return ns.L("Unlocks %s", ns.QuestText.getQuestName(questIds[1]) or ns.L("Quest %s", questIds[1]))
    end
    return ns.Lp(#questIds, "Unlocks %d quest", "Unlocks %d quests")
end

---@return string text "Follows Cutting Teeth" for one quest, else "Follows 2 quests"
function Chain.composeFollowText(questIds)
    if #questIds == 1 then
        return ns.L("Follows %s", ns.QuestText.getQuestName(questIds[1]) or ns.L("Quest %s", questIds[1]))
    end
    return ns.Lp(#questIds, "Follows %d quest", "Follows %d quests")
end
