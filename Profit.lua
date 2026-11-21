local addonName, ns = ... -- the addon's folder, which its pictures are read from

-- What completing a quest is worth in coin: the money it pays, the best of its reward items, and what the
-- creatures killed on the way are expected to drop. It is an estimate, and it leaves out what cannot be
-- known: coins dropped by creatures, and loot when no loot table is installed.
local Profit = {}
ns.Profit = Profit

local MAX_LISTED_DROPS = 5

local mobValueByNpcId = {}

---Expected sale value of everything one kill drops, quest-only items left out.
---@return { perKill: number, drops: table[], source: string, isPending: boolean }? mobValue nil without loot data
local function getMobValue(npcId)
    local cached = mobValueByNpcId[npcId]
    if cached then
        return cached
    end
    local loot = ns.Loot.getMobLoot(npcId)
    if not loot then
        return nil
    end
    local mobValue = { perKill = 0, drops = {}, source = loot.source, isPending = false, pricedCount = 0, auctionPricedCount = 0 }
    for itemId, drop in pairs(loot.drops) do
        if not drop.isQuestOnly then
            local value, isPending, isAuctionPrice = ns.Prices.getItemValue(itemId)
            mobValue.isPending = mobValue.isPending or isPending
            if value > 0 then
                mobValue.pricedCount = mobValue.pricedCount + 1
                mobValue.auctionPricedCount = mobValue.auctionPricedCount + (isAuctionPrice and 1 or 0)
                local expected = drop.chance * value
                mobValue.perKill = mobValue.perKill + expected
                mobValue.drops[#mobValue.drops + 1] = { itemId = itemId, chance = drop.chance, value = value, expected = expected }
            end
        end
    end
    table.sort(mobValue.drops, function(first, second)
        if first.expected ~= second.expected then
            return first.expected > second.expected
        end
        return first.itemId < second.itemId
    end)
    for index = #mobValue.drops, MAX_LISTED_DROPS + 1, -1 do
        mobValue.drops[index] = nil
    end
    if not mobValue.isPending then
        mobValueByNpcId[npcId] = mobValue
    end
    return mobValue
end

---Creatures still to kill for a quest, with the expected number of kills of each.
---@return table<number, number> killsByNpcId
---@return boolean hasUnknownKills Some objective needs kills whose number cannot be worked out
local function composeKills(quest)
    local killsByNpcId, hasUnknownKills, typeIndexes = {}, false, {}
    for objectiveIndex, objective in ipairs(quest.objectives) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        local remaining = objective.required - objective.fulfilled
        local target = ns.Location.getObjectiveTarget(quest.questId, objective.type, typeIndexes[objective.type])
        local npcId, kills
        if objective.isFinished or remaining <= 0 or not target then
            -- Done, or nothing to kill for it
        elseif target.npcId then
            npcId, kills = target.npcId, remaining
        elseif target.itemId then
            -- The kill counter's kills still to go, so the estimate and the kill bar agree: from the creature
            -- worth hunting, or once kills are counted, from those actually killed
            local progress = ns.KillCounter.getProgress(quest.questId, objectiveIndex, objective)
            if progress and progress.npcId then
                npcId, kills = progress.npcId, progress.remaining
            else
                local _, hasUnknownChance = ns.Drops.getHuntedSource(target.itemId)
                hasUnknownKills = hasUnknownKills or hasUnknownChance
            end
        end
        if npcId and kills then
            -- Two objectives on the same creature are served by the same kills
            killsByNpcId[npcId] = math.max(killsByNpcId[npcId] or 0, kills)
        end
    end
    return killsByNpcId, hasUnknownKills
end

---Reward items with their values. Of the items to choose from, only the most valuable one is counted.
---@return table[] rewardItems, boolean isPending
local function composeRewardItems(rewards)
    local rewardItems, isPending, bestChoice = {}, false, nil
    local function addItems(items, isChoice)
        for _, item in ipairs(items) do
            local value, isValuePending, isAuctionPrice = 0, false, false
            if item.itemId and item.itemId ~= 0 then
                value, isValuePending, isAuctionPrice = ns.Prices.getItemValue(item.itemId)
            end
            isPending = isPending or isValuePending
            local rewardItem = {
                itemId = item.itemId, name = item.name, count = item.count or 1, value = value * (item.count or 1),
                isChoice = isChoice, isCounted = not isChoice, isAuctionPrice = isAuctionPrice,
            }
            rewardItems[#rewardItems + 1] = rewardItem
            if isChoice and (not bestChoice or rewardItem.value > bestChoice.value) then
                bestChoice = rewardItem
            end
        end
    end
    addItems(rewards.items, false)
    addItems(rewards.choices, true)
    if bestChoice then
        bestChoice.isCounted = true
    end
    return rewardItems, isPending
end

---@class QuestProfit
---@field questId number
---@field rewardMoney number Copper
---@field rewardItems table[] Each with itemId, name, count, value, isChoice, isCounted
---@field rewardValue number Money plus the counted reward items
---@field mobs table[] One per creature still to kill: npcId, name, kills, perKill, lootValue, drops, source
---@field lootValue number
---@field kills number
---@field total number The estimate for completing the quest from where it stands
---@field hasUnknownKills boolean Some objective needs kills whose number is not known
---@field hasLootData boolean A loot table is installed, so creature loot is counted
---@field isPending boolean Item data is still loading, so the values are too low for now
---@field pricedCount number How many different items went into the estimate
---@field auctionPricedCount number How many of them at an auction price; the rest at the vendor's

---@return QuestProfit
function Profit.compose(questId)
    local quest = ns.QuestState.getQuest(questId)
    local rewards = ns.QuestState.getRewards(questId)
    local rewardItems, isPending = composeRewardItems(rewards)
    local rewardValue = rewards.money
    local pricedCount, auctionPricedCount = 0, 0
    for _, rewardItem in ipairs(rewardItems) do
        if rewardItem.isCounted then
            rewardValue = rewardValue + rewardItem.value
            if rewardItem.value > 0 then
                pricedCount = pricedCount + 1
                auctionPricedCount = auctionPricedCount + (rewardItem.isAuctionPrice and 1 or 0)
            end
        end
    end

    local killsByNpcId, hasUnknownKills = composeKills(quest)
    local mobs, lootValue, totalKills = {}, 0, 0
    for npcId, kills in pairs(killsByNpcId) do
        local mobValue = getMobValue(npcId)
        local mob = {
            npcId = npcId, name = ns.Database.getNpcField(npcId, "name") or ns.L("Creature %d", npcId),
            kills = kills, perKill = 0, lootValue = 0, drops = {},
        }
        if mobValue then
            mob.perKill, mob.drops, mob.source = mobValue.perKill, mobValue.drops, mobValue.source
            mob.lootValue = mobValue.perKill * kills
            isPending = isPending or mobValue.isPending
            pricedCount = pricedCount + mobValue.pricedCount
            auctionPricedCount = auctionPricedCount + mobValue.auctionPricedCount
        end
        mobs[#mobs + 1] = mob
        lootValue = lootValue + mob.lootValue
        totalKills = totalKills + kills
    end
    table.sort(mobs, function(first, second)
        if first.lootValue ~= second.lootValue then
            return first.lootValue > second.lootValue
        end
        return first.npcId < second.npcId
    end)

    return {
        questId = questId,
        rewardMoney = rewards.money,
        rewardItems = rewardItems,
        rewardValue = rewardValue,
        mobs = mobs,
        lootValue = lootValue,
        kills = totalKills,
        total = rewardValue + lootValue,
        hasUnknownKills = hasUnknownKills,
        hasLootData = ns.Loot.hasData(),
        isPending = isPending or rewards.isLoading,
        pricedCount = pricedCount,
        auctionPricedCount = auctionPricedCount,
    }
end

local CACHE_SECONDS = 5
local cachedProfits = {} -- [questId] = { profit, time }

---The estimate for a quest, remembered for a few seconds so lists can ask for every row on every redraw.
---An estimate still waiting for item data is not kept, so it settles as soon as the data arrives.
---@return QuestProfit
function Profit.get(questId)
    local now = GetTime and GetTime() or 0
    local cached = cachedProfits[questId]
    if cached and now - cached.time < CACHE_SECONDS then
        return cached.profit
    end
    local profit = Profit.compose(questId)
    if not profit.isPending then
        cachedProfits[questId] = { profit = profit, time = now }
    end
    return profit
end

local TILDE = "Interface\\AddOns\\" .. addonName .. "\\Media\\Tilde"

---@return string sign The estimate sign "~" as a small picture on the text's middle line, for any estimate;
---the font's own sits high, above the numbers
---@param color number[]? Its colour, to match the text it stands in; a pale tan by default
function Profit.formatEstimateSign(color)
    color = color or { 0.85, 0.81, 0.66 }
    return string.format("|T%s:8:12:0:0:32:16:0:32:0:16:%d:%d:%d|t", TILDE,
        math.floor(color[1] * 255), math.floor(color[2] * 255), math.floor(color[3] * 255))
end

---The estimate as text: "~" and the amount in coins. nil when there is nothing to show.
---@param color number[]? The sign's colour, to match the text it stands in; a pale tan by default
---@return string? text
function Profit.format(profit, color)
    local total = math.floor(profit.total + 0.5)
    if total <= 0 then
        return nil
    end
    return Profit.formatEstimateSign(color) .. " " .. ns.Widgets.formatMoney(total)
end

---Forgets remembered estimates, for when a quest's progress changed.
function Profit.invalidate()
    cachedProfits = {}
end

---Forgets worked-out values too, for when prices or loot tables may have changed.
function Profit.reset()
    mobValueByNpcId, cachedProfits = {}, {}
    ns.Loot.reset()
    ns.Drops.reset()
end

ns.registerModule({ name = "Profit", invalidate = Profit.invalidate })
