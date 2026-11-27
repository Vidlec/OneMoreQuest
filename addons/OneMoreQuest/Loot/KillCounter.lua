local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Kills of the creatures that drop a quest's items, against the kills an average player needs for the same
-- drops: drops ÷ drop chance. Before the first kill the chance is that of the likeliest creature where the
-- player would hunt; after it, the average chance of the creatures actually killed. Kept per character and per
-- quest, while the quest is in the log. A kill counts when a creature you or your group fought dies, and it
-- drops an item one of your quests still needs.
--
-- The game no longer lets addons read the combat log (it is secure only; CombatLogGetCurrentEventInfo is gone),
-- so kills are seen this way: while a creature is in combat and nobody else holds its tap, seen as the target,
-- the mouseover, a nameplate or a party member's target, it is noted as fought by your group; when the game
-- then says it died (UNIT_DIED, with its GUID), that is a kill. Values the game keeps secret are left alone.
-- A death counts once, however often the game tells it (seen through several units); one told a moment before the
-- creature was first seen in combat (killed in one blow) still counts; a creature later seen tagged by someone else
-- is theirs.
local KillCounter = {}
ns.KillCounter = KillCounter

local FOUGHT_SECONDS = 600 -- a creature fought this long ago and not seen dying is forgotten
local eventFrame
local foughtAt = {} -- [creature GUID] = when it was last seen fighting your group
local countedAt = {} -- [creature GUID] = when its death was counted: a death counts once, however often it is told
local diedAt = {} -- [creature GUID] = when it died before it was seen fighting your group (a one-shot kill: the game
-- may tell the death before the creature's first update in combat); a sighting soon after still claims it
local LATE_SIGHTING_SECONDS = 2
local COUNTED_SECONDS = 900 -- a death counted is remembered this long: its corpse is gone by then

local function getCharacterRecords()
    return ns.getCharacterRecords("killCounts")
end

---Calls `handle` for each objective of a quest in the log that asks for an item a creature drops.
local function forEachItemObjective(questId, handle)
    local quest = ns.QuestState.getQuest(questId)
    local typeIndexes = {}
    for index, objective in ipairs(quest and quest.objectives or {}) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if objective.type == "item" then
            local target = ns.Location.getObjectiveTarget(questId, "item", typeIndexes.item)
            if target and target.itemId then
                handle(index, objective, target.itemId)
            end
        end
    end
end

---@return number count Who a quest item's drops go round between: the player and every party member on the quest
---who still needs it (a member with all of it, or without the quest, takes no turn). A count unknown (no addon,
---inside a dungeon) counts as still needing it. A one-of-a-kind creature's drops go to everyone (Drops.isForEveryone),
---so for its kills the count is 1.
---@param npcId number? The creature killed or hunted
function KillCounter.getSharerCount(questId, objectiveIndex, npcId)
    local quest = ns.QuestState.getQuest(questId)
    if ns.Drops.isForEveryone(npcId) or not (quest and ns.Party) or #ns.Party.getMembers(questId) == 0 then
        return 1
    end
    local count = 1
    for _, member in ipairs(ns.Party.getProgress(questId, quest.objectives)) do
        local memberCount = member.isOnQuest and member.counts[objectiveIndex]
        if member.isOnQuest and not (memberCount and memberCount.isDone) then
            count = count + 1
        end
    end
    return count
end

---A drop came (the item's count rose since it was last seen): it came from the kill before, which ends the run of
---kills that gave nothing. The chronicle keeps the longest such run, and how often a drop came on the first kill.
local function closeDrySpell(record)
    local kills = record.killsSinceDrop or 0
    if kills == 0 then
        return -- not from a kill counted here (a chest, a trade)
    end
    if kills == 1 then
        record.firstKillDrops = (record.firstKillDrops or 0) + 1
    end
    record.longestDry = math.max(record.longestDry or 0, kills - 1)
    record.killsSinceDrop = 0
end

---A creature died to you or your group: it counts for every unfinished objective whose item it drops. Kills are
---the group's; a quest item's drop goes round between those who need it, so in a group of three needing it a
---kill is a third of a chance for the player.
function KillCounter.handleKill(npcId)
    local records = getCharacterRecords()
    local isCounted = false
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        forEachItemObjective(questId, function(index, objective, itemId)
            if objective.isFinished then
                return
            end
            local chance = ns.Drops.getChance(itemId, npcId)
            if not chance and not ns.Drops.isDroppedBy(itemId, npcId) then
                return
            end
            records[questId] = records[questId] or {}
            local record = records[questId][index]
            if not record then
                -- Counting starts now: the drops already in the bags were not counted for, so they are left out
                record = { kills = 0, knownKills = 0, chanceSum = 0, startFulfilled = objective.fulfilled }
                records[questId][index] = record
            end
            -- The item's count rose since the last kill: that kill dropped it. One that fell (an item destroyed or
            -- traded away) is followed down, so the next drop shows as a rise again
            local seen = record.seenFulfilled or record.startFulfilled
            if objective.fulfilled > seen then
                closeDrySpell(record)
                record.seenFulfilled = objective.fulfilled
            elseif objective.fulfilled < seen then
                record.seenFulfilled = objective.fulfilled
            end
            record.killsSinceDrop = (record.killsSinceDrop or 0) + 1
            record.kills = record.kills + 1
            record.lastNpcId = npcId
            -- For the chronicle: the item, how many were needed, and which creatures the kills were
            record.itemId, record.required = itemId, objective.required
            record.killsByNpcId = record.killsByNpcId or {}
            record.killsByNpcId[npcId] = (record.killsByNpcId[npcId] or 0) + 1
            if chance then
                record.knownKills = record.knownKills + 1
                -- The player's own chance from this kill (shared round), and the item's plain chance
                record.chanceSum = record.chanceSum + chance / KillCounter.getSharerCount(questId, index, npcId)
                record.plainChanceSum = (record.plainChanceSum or 0) + chance
            end
            isCounted = true
        end)
    end
    if isCounted then
        ns.Profit.invalidate() -- its kills still to go are the counter's
        ns.queueRefresh()
    end
end

---@return number? itemId The item an objective of a quest in the log asks for, when a creature drops it
local function getObjectiveItemId(questId, objectiveIndex)
    local itemId
    forEachItemObjective(questId, function(index, _, objectiveItemId)
        itemId = index == objectiveIndex and objectiveItemId or itemId
    end)
    return itemId
end

---@class KillProgress
---@field kills number Counted so far
---@field expected number What an average player needs for the drops got since counting began
---@field remaining number About how many kills the rest will take
---@field chance number The drop chance these are worked out with: the player's own, shared round the group
---@field sharerCount number Who the drops go round between now: the player and party members still needing it
---@field earlierDrops number Drops already in the bags when counting began
---@field earlierKills number About what those took
---@field npcId number? The creature being hunted: the one last killed, else the one worth hunting (Drops)

---Kills for an item objective. Before the first counted kill they are worked out from the creature worth
---hunting; after it, from the average chance of the creatures actually killed. The profit estimate takes its
---kills still to go from here too, so the two always agree.
---@return KillProgress? progress nil when no drop chance is known
local function composeProgress(questId, objectiveIndex, objective)
    local itemId = getObjectiveItemId(questId, objectiveIndex)
    if not itemId then
        return nil
    end
    local questRecords = getCharacterRecords()[questId]
    local record = questRecords and questRecords[objectiveIndex]
    local remainingDrops = math.max((objective.required or 0) - (objective.fulfilled or 0), 0)
    local huntedSource = ns.Drops.getHuntedSource(itemId)
    -- Kills still to go are for the group as it is now: the drops go round between those who still need them
    local huntedNpcId = record and record.lastNpcId or (huntedSource and huntedSource.npcId)
    local sharerCount = KillCounter.getSharerCount(questId, objectiveIndex, huntedNpcId)
    if not record or record.knownKills == 0 then
        local chance = huntedSource and huntedSource.chance and huntedSource.chance / sharerCount
        if not chance then
            return nil
        end
        -- Drops already in the bags before any kill was counted: their kills are only an estimate
        local earlierDrops = record and record.startFulfilled or (objective.fulfilled or 0)
        return {
            kills = record and record.kills or 0,
            expected = 0,
            drops = 0,
            isUnlucky = false,
            chance = chance,
            sharerCount = sharerCount,
            remaining = ns.Drops.getKillsFor(remainingDrops, chance),
            earlierDrops = earlierDrops,
            earlierKills = ns.Drops.getKillsFor(earlierDrops, chance),
            npcId = huntedSource.npcId,
        }
    end
    local averageChance = record.chanceSum / record.knownKills -- the player's own, each kill's shared round
    local plainChance = (record.plainChanceSum or record.chanceSum) / record.knownKills
    local drops = math.max((objective.fulfilled or 0) - record.startFulfilled, 0)
    local expected = ns.Drops.getKillsFor(drops, averageChance)
    -- Unlucky: past what an average player needs for the drops got; with none yet, for the first one
    local par = drops > 0 and expected or ns.Drops.getKillsFor(1, averageChance)
    return {
        kills = record.kills,
        chance = averageChance,
        drops = drops,
        isUnlucky = record.kills > par,
        expected = expected,
        sharerCount = sharerCount,
        remaining = ns.Drops.getKillsFor(remainingDrops, plainChance / sharerCount),
        earlierDrops = record.startFulfilled,
        earlierKills = ns.Drops.getKillsFor(record.startFulfilled, plainChance),
        npcId = record.lastNpcId or (huntedSource and huntedSource.npcId),
    }
end

---@return boolean isTold The drop chances, and so the kills an item takes, may be told for this quest: drops "with
---chances" (Spoilers), or a hint that showed them; always in Guide
local function isChanceTold(questId)
    return not ns.Spoilers.isActive() or ns.Spoilers.get("drops", questId) == "chances"
end

---Kills for an item objective, as the quest page, the tracker and their bars say them: only where the drop chances
---may be told (an estimate of kills to go says the chance as surely as a percentage).
---@return KillProgress? progress nil when no drop chance is known, or the chances are held back
function KillCounter.getProgress(questId, objectiveIndex, objective)
    if not isChanceTold(questId) then
        return nil
    end
    return composeProgress(questId, objectiveIndex, objective)
end

---The same, whatever is held back: for the profit estimate, whose coins say no chance (Profit hides its own numbers
---by the rewards' choice).
KillCounter.getProgressForEstimate = composeProgress

---The kills counted, as the quest page and the tooltip say them: "No kills counted yet", "3 kills, no drop yet",
---"8 kills for 2 drops · average 6" (the kills an average player needs for those drops).
---@param separator string Between the kills and the average
---@return string text
function KillCounter.formatKills(progress, separator)
    if progress.kills == 0 then
        return ns.L("No kills counted yet")
    elseif (progress.drops or 0) == 0 then
        return ns.Lp(progress.kills, "%d kill, no drop yet", "%d kills, no drop yet")
    end
    return ns.L(
        "%s for %s%saverage %d",
        ns.Lp(progress.kills, "%d kill", "%d kills"),
        ns.Lp(progress.drops, "%d drop", "%d drops"),
        separator,
        math.floor(progress.expected + 0.5)
    )
end

---@return number? chance How often an item objective's item drops where the player would hunt it; nil for other
---objectives, when no chance is known, or while the chances are held back
function KillCounter.getDropChance(questId, objectiveIndex)
    if not isChanceTold(questId) then
        return nil
    end
    local itemId = getObjectiveItemId(questId, objectiveIndex)
    local huntedSource = itemId and ns.Drops.getHuntedSource(itemId)
    return huntedSource and huntedSource.chance or nil
end

---Prints what has been counted, quest by quest, to see that kills arrive.
function KillCounter.printCounts()
    local count = 0
    for questId, objectives in pairs(getCharacterRecords()) do
        for index, record in pairs(objectives) do
            count = count + 1
            ns.print(
                ns.L(
                    "%s, objective %d: %d kills (%d with a known drop chance), counting from %d done",
                    ns.Database.getQuestField(questId, "name") or questId,
                    index,
                    record.kills,
                    record.knownKills,
                    record.startFulfilled
                )
            )
        end
    end
    if count == 0 then
        ns.print(
            ns.L(
                "no kills counted yet. Kills count when you or your group kill a creature that drops an item one of your quests needs."
            )
        )
    end
end

---What was counted for a quest's drop objectives, as the chronicle keeps it when the quest is handed in: each
---objective's item, the drops it took since counting began, the kills, the kills an average player would have
---needed for them, the kills of each creature, the longest run of kills before a drop and the drops that came on
---the first kill.
---@return { itemId: number?, drops: number, kills: number, expected: number?, killsByNpcId: table<number, number>, longestDry: number?, firstKillDrops: number? }[] objectives
function KillCounter.composeTurnIn(questId)
    local objectives = {}
    local questRecords = getCharacterRecords()[questId] or {}
    local indexes = {}
    for index in pairs(questRecords) do
        indexes[#indexes + 1] = index
    end
    table.sort(indexes)
    for _, index in ipairs(indexes) do
        local record = questRecords[index]
        local drops = math.max((record.required or 0) - (record.startFulfilled or 0), 0)
        local averageChance = record.knownKills > 0 and record.chanceSum / record.knownKills or nil
        -- The last drops came after the last kill seen: they end its run of kills
        if (record.required or 0) > (record.seenFulfilled or record.startFulfilled or 0) then
            closeDrySpell(record)
        end
        objectives[#objectives + 1] = {
            itemId = record.itemId,
            drops = drops,
            kills = record.kills,
            expected = averageChance and ns.Drops.getKillsFor(drops, averageChance) or nil,
            killsByNpcId = record.killsByNpcId or {},
            -- Only when there is something to say, to keep the entry small
            longestDry = (record.longestDry or 0) > 0 and record.longestDry or nil,
            firstKillDrops = (record.firstKillDrops or 0) > 0 and record.firstKillDrops or nil,
        }
    end
    return objectives
end

function KillCounter.forget(questId)
    getCharacterRecords()[questId] = nil
end

---@return boolean isReadable A value the game lets addons use: there, and not one it keeps secret
local function isReadable(value)
    return value ~= nil and not (issecretvalue and issecretvalue(value))
end

---Notes a creature as fought by your group: an enemy in combat whose tap nobody else holds.
function KillCounter.noteUnit(unit)
    if not UnitExists or not UnitExists(unit) or (UnitIsPlayer and UnitIsPlayer(unit)) then
        return
    end
    local isEnemy = UnitCanAttack and UnitCanAttack("player", unit)
    local isFighting = UnitAffectingCombat and UnitAffectingCombat(unit)
    local isTappedByOthers = UnitIsTapDenied and UnitIsTapDenied(unit)
    if not (isReadable(isEnemy) and isReadable(isFighting) and isReadable(isTappedByOthers)) then
        return
    end
    local guid = UnitGUID(unit)
    if not isReadable(guid) then
        return
    end
    if isTappedByOthers then
        foughtAt[guid] = nil -- someone else's: its death is theirs, though your group fought it before
    elseif isEnemy and isFighting then
        local now = GetTime and GetTime() or 0
        foughtAt[guid] = now
        -- It died a moment ago, before this first sight of it in combat (killed in one blow): the death is ours
        if diedAt[guid] and now - diedAt[guid] <= LATE_SIGHTING_SECONDS then
            diedAt[guid] = nil
            KillCounter.handleDeath(guid)
        end
    end
end

---A unit died: when it is a creature your group fought, it is a kill.
function KillCounter.handleDeath(guid)
    if not isReadable(guid) or countedAt[guid] then
        return -- each creature dies once: the game may say so more than once (seen through several units)
    end
    local now = GetTime and GetTime() or 0
    if not foughtAt[guid] then
        diedAt[guid] = now -- not seen fighting yet: a sighting in a moment may still show it was ours
        return
    end
    foughtAt[guid], countedAt[guid] = nil, now
    if ns.Ledger then
        ns.Ledger.handleKill()
    end
    local npcId = ns.Database.getNpcId(guid)
    if npcId then
        KillCounter.handleKill(npcId)
        ns.Spoilers.noteKill(npcId) -- (Explorer: a creature killed is one the player has found)
    end
end

local function forgetOldFights()
    local now = GetTime and GetTime() or 0
    for guid, time in pairs(foughtAt) do
        if now - time > FOUGHT_SECONDS then
            foughtAt[guid] = nil
        end
    end
    for guid, time in pairs(countedAt) do
        if now - time > COUNTED_SECONDS then
            countedAt[guid] = nil
        end
    end
    for guid, time in pairs(diedAt) do
        if now - time > LATE_SIGHTING_SECONDS then
            diedAt[guid] = nil
        end
    end
end

local function handleEvent(_, event, ...)
    if event == "UNIT_DIED" then
        KillCounter.handleDeath((...))
    elseif
        event == "UNIT_HEALTH"
        or event == "UNIT_FLAGS"
        or event == "UNIT_THREAT_LIST_UPDATE"
        or event == "NAME_PLATE_UNIT_ADDED"
    then
        KillCounter.noteUnit((...))
    elseif event == "PLAYER_TARGET_CHANGED" then
        KillCounter.noteUnit("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        KillCounter.noteUnit("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        KillCounter.noteUnit("focus")
    elseif event == "PLAYER_SOFT_ENEMY_CHANGED" then
        KillCounter.noteUnit("softenemy") -- the enemy the game picks for an action without a target
    elseif event == "UNIT_TARGET" then
        -- What a party member or the pet is fighting
        local unit = ...
        if unit == "pet" or (type(unit) == "string" and unit:match("^party%d$")) then
            KillCounter.noteUnit(unit .. "target")
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        forgetOldFights()
    elseif event == "QUEST_REMOVED" then
        -- A moment later: a quest handed in is removed too, and the chronicle reads its kills at the hand-in
        local questId = ...
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function()
                if not ns.QuestState.isInLog(questId) then -- (taken again meanwhile: its counts are the new one's)
                    KillCounter.forget(questId)
                end
            end)
        else
            KillCounter.forget(questId)
        end
    end
end

function KillCounter.create()
    if eventFrame or not CreateFrame then
        return
    end
    eventFrame = CreateFrame("Frame")
    for _, event in ipairs({
        "UNIT_DIED",
        "UNIT_HEALTH",
        "UNIT_FLAGS",
        "UNIT_THREAT_LIST_UPDATE",
        "NAME_PLATE_UNIT_ADDED",
        "PLAYER_TARGET_CHANGED",
        "UPDATE_MOUSEOVER_UNIT",
        "PLAYER_FOCUS_CHANGED",
        "PLAYER_SOFT_ENEMY_CHANGED",
        "UNIT_TARGET",
        "PLAYER_REGEN_ENABLED",
        "QUEST_REMOVED",
    }) do
        -- An event this client does not know must not stop the others from being registered
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if ns.Timing.isRecording then
            ns.Timing.measure("kill counter " .. event, handleEvent, self, event, ...)
        else
            handleEvent(self, event, ...)
        end
    end)
end

KillCounter.handleEvent = handleEvent -- for tests

ns.registerModule({
    name = "KillCounter",
    create = KillCounter.create,
    -- Kills counted are kept while their quest is in the log
    prune = function(isInLog)
        if not isInLog then
            return
        end
        local killCounts = ns.getCharacterRecords("killCounts")
        for questId in pairs(killCounts) do
            if not isInLog[questId] then
                killCounts[questId] = nil
            end
        end
    end,
})
