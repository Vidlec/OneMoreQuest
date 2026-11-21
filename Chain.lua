local _, ns = ...

-- A quest's place in its chain, from the single prerequisite going back and the follow-up going forward.
-- Chains that fork or need several quests at once are cut at that point.
local Chain = {}
ns.Chain = Chain

local MAX_STEPS = 40

local function getPreviousQuestId(questId)
    local single = ns.Database.getQuestField(questId, "preQuestSingle")
    if single and #single == 1 then
        return single[1]
    end
    local group = ns.Database.getQuestField(questId, "preQuestGroup")
    if group and #group == 1 then
        return group[1]
    end
    return nil
end

local function getNextQuestId(questId)
    local nextQuestId = ns.Database.getQuestField(questId, "nextQuestInChain")
    return nextQuestId and nextQuestId ~= 0 and nextQuestId or nil
end

local function countSteps(questId, getNeighbourId)
    local count, seen = 0, { [questId] = true }
    local neighbourId = getNeighbourId(questId)
    while neighbourId and not seen[neighbourId] and count < MAX_STEPS do
        seen[neighbourId] = true
        count = count + 1
        neighbourId = getNeighbourId(neighbourId)
    end
    return count
end

---@return number? index Position of the quest in its chain, nil when it is not part of one; steps done back to
---back count as one
---@return number? total
function Chain.getStep(questId)
    local previousCount = countSteps(questId, getPreviousQuestId)
    local nextCount = countSteps(questId, getNextQuestId)
    if previousCount + nextCount == 0 then
        return nil
    end
    -- Steps done back to back are one step of the chain, as their row is one (Chain.getQuestIds)
    local questIds = Chain.getQuestIds(questId)
    if #questIds < 2 then
        return nil
    end
    local lastStepQuestId = questId
    for _, stepQuestId in ipairs(ns.Availability.getInstantSteps(questId)) do
        lastStepQuestId = stepQuestId
    end
    for position, chainQuestId in ipairs(questIds) do
        if chainQuestId == lastStepQuestId then
            return position, #questIds
        end
    end
    return previousCount + 1, previousCount + 1 + nextCount
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
            for _, previousQuestId in ipairs(ns.Database.getQuestField(current, field) or {}) do
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
    local questIds, seen = { questId }, { [questId] = true }
    local previousQuestId = getPreviousQuestId(questId)
    while previousQuestId and not seen[previousQuestId] and #questIds < MAX_STEPS do
        seen[previousQuestId] = true
        table.insert(questIds, 1, previousQuestId)
        previousQuestId = getPreviousQuestId(previousQuestId)
    end
    local nextQuestId = getNextQuestId(questId)
    while nextQuestId and not seen[nextQuestId] and #questIds < MAX_STEPS do
        seen[nextQuestId] = true
        questIds[#questIds + 1] = nextQuestId
        nextQuestId = getNextQuestId(nextQuestId)
    end
    -- A step done straight after the one before (Test of Lore's, taken and handed back at once) is one step
    -- with it, standing as the last of them: done when that is
    local steps = {}
    for position, chainQuestId in ipairs(questIds) do
        local isFollowedAtOnce = ns.Availability.getInstantStepBefore(questIds[position + 1] or 0) == chainQuestId
        if not isFollowedAtOnce then
            steps[#steps + 1] = chainQuestId
        end
    end
    return steps
end
