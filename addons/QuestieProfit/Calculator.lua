local _, ns = ...

local Calculator = {}
ns.Calculator = Calculator

local MIN_DROP_CHANCE = 0.01
local MAX_LISTED_DROPS = 5

local QuestieDB
local mobValueCache = {}

local function getQuestieDB()
    QuestieDB = QuestieDB or QuestieLoader:ImportModule("QuestieDB")
    return QuestieDB
end

local function getNpcName(npcId)
    local isSuccess, name = pcall(getQuestieDB().QueryNPCSingle, npcId, "name")
    return isSuccess and name or nil
end

---Expected sale value of everything one kill drops, quest-only items left out.
---@return { perKill: number, drops: table[], source: string, isPending: boolean }?
local function getMobValue(npcId, npcName)
    local cached = mobValueCache[npcId]
    if cached then
        return cached
    end
    local loot = ns.Loot.getMobLoot(npcId, npcName)
    if not loot then
        return nil
    end
    local mobValue = { perKill = 0, drops = {}, source = loot.source, isPending = false }
    for itemId, drop in pairs(loot.drops) do
        if not drop.isQuestOnly then
            local value, isPending = ns.Prices.getItemValue(itemId)
            mobValue.isPending = mobValue.isPending or isPending
            if value > 0 then
                local expected = drop.chance * value
                mobValue.perKill = mobValue.perKill + expected
                mobValue.drops[#mobValue.drops + 1] = { itemId = itemId, chance = drop.chance, value = value, expected = expected }
            end
        end
    end
    table.sort(mobValue.drops, function(first, second) return first.expected > second.expected end)
    for index = #mobValue.drops, MAX_LISTED_DROPS + 1, -1 do
        mobValue.drops[index] = nil
    end
    if not mobValue.isPending then
        mobValueCache[npcId] = mobValue
    end
    return mobValue
end

---Chance that one kill of the mob drops the quest item, from Questie's drop rates or else from the loot tables.
local function getDropChance(itemId, npcId)
    local isSuccess, dropRate = pcall(getQuestieDB().GetItemDroprate, itemId, npcId)
    if isSuccess and dropRate and tonumber(dropRate[1]) then
        return tonumber(dropRate[1]) / 100
    end
    local loot = ns.Loot.getMobLoot(npcId, getNpcName(npcId))
    local drop = loot and loot.drops[itemId]
    return drop and drop.chance or nil
end

---The mob that drops the quest item most often, the one a player would farm.
---@return number? npcId, number? chance
local function getBestItemSource(itemId)
    local item = getQuestieDB():GetItem(itemId)
    local bestNpcId, bestChance
    for _, source in ipairs(item and item.Sources or {}) do
        if source.Type == "monster" and not source.Vendor then
            local chance = getDropChance(itemId, source.Id)
            if chance and (not bestChance or chance > bestChance) then
                bestNpcId, bestChance = source.Id, chance
            end
        end
    end
    return bestNpcId, bestChance
end

local function isSameObjectiveType(dataType, objectiveType)
    return dataType == objectiveType or (dataType == "killcredit" and objectiveType == "monster")
end

---Questie's data for a quest log objective: the same index when the types agree, else the first unused of the type.
local function getObjectiveData(quest, objective, index, usedIndexes)
    local objectiveData = quest.ObjectiveData or {}
    local data = objectiveData[index]
    if data and not usedIndexes[index] and isSameObjectiveType(data.Type, objective.type) then
        usedIndexes[index] = true
        return data
    end
    for dataIndex, candidate in ipairs(objectiveData) do
        if not usedIndexes[dataIndex] and isSameObjectiveType(candidate.Type, objective.type) then
            usedIndexes[dataIndex] = true
            return candidate
        end
    end
    return nil
end

---Mobs still to kill for the quest, with the expected number of kills of each.
---@return table<number, number> killsByNpcId, boolean hasUnknownKills
local function composeKills(quest)
    local killsByNpcId, hasUnknownKills, usedIndexes = {}, false, {}
    local objectives = (C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(quest.Id)) or {}
    if #objectives == 0 and quest.ObjectiveData and #quest.ObjectiveData > 0 then
        hasUnknownKills = true
    end

    for index, objective in ipairs(objectives) do
        local remaining = (objective.numRequired or 0) - (objective.numFulfilled or 0)
        local data = getObjectiveData(quest, objective, index, usedIndexes)
        local npcId, kills
        if not data or remaining <= 0 then
            -- Finished, or an objective Questie has no data for
        elseif data.Type == "monster" then
            npcId, kills = data.Id, remaining
        elseif data.Type == "killcredit" then
            npcId, kills = data.IdList and data.IdList[1], remaining
        elseif data.Type == "item" then
            local chance
            npcId, chance = getBestItemSource(data.Id)
            if npcId then
                kills = remaining / math.max(chance, MIN_DROP_CHANCE)
            else
                local item = getQuestieDB():GetItem(data.Id)
                for _, source in ipairs(item and item.Sources or {}) do
                    -- A mob drops it, but no drop rate is known
                    hasUnknownKills = hasUnknownKills or (source.Type == "monster" and not source.Vendor)
                end
            end
        end
        if npcId and kills then
            killsByNpcId[npcId] = math.max(killsByNpcId[npcId] or 0, kills)
        end
    end
    return killsByNpcId, hasUnknownKills
end

---Reward items of the quest. Of the items to choose from, only the most valuable one is counted.
---@return table[] rewardItems, boolean isPending
local function composeRewardItems(questId)
    local rewardItems, isPending = {}, false
    local addItem = function(itemId, count, isChoice)
        if not itemId or itemId == 0 then
            return
        end
        local value, isValuePending = ns.Prices.getItemValue(itemId)
        isPending = isPending or isValuePending
        rewardItems[#rewardItems + 1] = { itemId = itemId, count = count or 1, value = value * (count or 1), isChoice = isChoice, isCounted = not isChoice }
    end

    if GetNumQuestLogRewards and GetQuestLogRewardInfo then
        for index = 1, GetNumQuestLogRewards(questId) or 0 do
            local _, _, count, _, _, itemId = GetQuestLogRewardInfo(index, questId)
            addItem(itemId, count, false)
        end
    end
    if GetNumQuestLogChoices and GetQuestLogChoiceInfo then
        for index = 1, GetNumQuestLogChoices(questId, false) or 0 do
            local _, _, count, _, _, itemId = GetQuestLogChoiceInfo(index, questId)
            addItem(itemId, count, true)
        end
    end

    local bestChoice
    for _, rewardItem in ipairs(rewardItems) do
        if rewardItem.isChoice and (not bestChoice or rewardItem.value > bestChoice.value) then
            bestChoice = rewardItem
        end
    end
    if bestChoice then
        bestChoice.isCounted = true
    end
    return rewardItems, isPending
end

---@class QuestProfit
---@field questId number
---@field name string
---@field level number?
---@field rewardMoney number
---@field rewardItems table[]
---@field rewardValue number Money plus the counted reward items
---@field mobs table[] One entry per mob: npcId, name, kills, perKill, lootValue, drops, source
---@field lootValue number
---@field kills number
---@field total number Estimated profit for completing the quest
---@field hasUnknownKills boolean Some objective needs kills, but their number is unknown
---@field isPending boolean Item data is still loading, so the values are too low

---@param questId number
---@return QuestProfit?
function Calculator.composeQuestProfit(questId)
    if not ns.isReady then
        return nil
    end
    local quest = getQuestieDB().GetQuest(questId)
    if not quest then
        return nil
    end
    if C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        C_QuestLog.RequestLoadQuestByID(questId)
    end

    local rewardMoney = (GetQuestLogRewardMoney and GetQuestLogRewardMoney(questId)) or 0
    local rewardItems, isPending = composeRewardItems(questId)
    local rewardValue = rewardMoney
    for _, rewardItem in ipairs(rewardItems) do
        if rewardItem.isCounted then
            rewardValue = rewardValue + rewardItem.value
        end
    end

    local killsByNpcId, hasUnknownKills = composeKills(quest)
    local mobs, lootValue, totalKills = {}, 0, 0
    for npcId, kills in pairs(killsByNpcId) do
        local name = getNpcName(npcId)
        local mobValue = getMobValue(npcId, name)
        local mob = { npcId = npcId, name = name or ("npc " .. npcId), kills = kills, perKill = 0, lootValue = 0, drops = {} }
        if mobValue then
            mob.perKill, mob.drops, mob.source = mobValue.perKill, mobValue.drops, mobValue.source
            mob.lootValue = mobValue.perKill * kills
            isPending = isPending or mobValue.isPending
        end
        mobs[#mobs + 1] = mob
        lootValue = lootValue + mob.lootValue
        totalKills = totalKills + kills
    end
    table.sort(mobs, function(first, second) return first.lootValue > second.lootValue end)

    local total = rewardValue + lootValue
    return {
        questId = questId,
        name = quest.name or ("quest " .. questId),
        level = quest.level,
        rewardMoney = rewardMoney,
        rewardItems = rewardItems,
        rewardValue = rewardValue,
        mobs = mobs,
        lootValue = lootValue,
        kills = totalKills,
        total = total,
        hasUnknownKills = hasUnknownKills,
        isPending = isPending,
    }
end

ns.addSettingsListener(function(key)
    if key == "priceSource" or key == "minForeverKills" then
        mobValueCache = {}
    end
end)
