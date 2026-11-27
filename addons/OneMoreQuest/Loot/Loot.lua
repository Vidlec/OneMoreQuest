local _, ns = ...

-- What creatures drop, read from the loot tables that the Tnny's Mob Loot addon ships as globals when it is
-- installed. OneMoreQuest bundles no loot data of its own.
--   TnnysMobLoot_Forever.npc[npcId] = { "name", "itemId:percent:drops:kills,..." }   (recorded Forever kills)
--   TnnysMobLoot_Starter.npc[npcId] = { "itemId:percent[:q],...", skinning, worldDrops, "Name", ... }   (Classic estimates)
local Loot = {}
ns.Loot = Loot

local MIN_FOREVER_KILLS = 20 -- fewer recorded kills than this say too little; the Classic estimate is used

local lootByNpcId = {}

---@return boolean hasData A loot table is installed
function Loot.hasData()
    return TnnysMobLoot_Forever ~= nil or TnnysMobLoot_Starter ~= nil
end

local function getForeverLoot(npcId)
    local raw = TnnysMobLoot_Forever and TnnysMobLoot_Forever.npc and TnnysMobLoot_Forever.npc[npcId]
    if not raw then
        return nil
    end
    local drops, maxKills = {}, 0
    for part in (raw[2] or ""):gmatch("[^,]+") do
        local itemId, percent, _, kills = part:match("^(%d+):([%d%.]+):(%d+):(%d+)$")
        if itemId then
            drops[tonumber(itemId)] = { chance = tonumber(percent) / 100, isQuestOnly = false }
            maxKills = math.max(maxKills, tonumber(kills))
        end
    end
    if maxKills < MIN_FOREVER_KILLS or not next(drops) then
        return nil
    end
    return { drops = drops, source = "forever", kills = maxKills }
end

---The Classic entry counts only when its name agrees with the creature's, so a creature Forever renumbered
---never gets another one's loot.
local function getClassicLoot(npcId, npcName)
    local raw = TnnysMobLoot_Starter and TnnysMobLoot_Starter.npc and TnnysMobLoot_Starter.npc[npcId]
    if not raw then
        return nil
    end
    if npcName and raw[4] and raw[4]:lower() ~= npcName:lower() then
        return nil
    end
    local drops = {}
    for part in (raw[1] or ""):gmatch("[^,]+") do
        local itemId, percent, questFlag = part:match("^(%d+):([%d%.]+):?(q?)$")
        if itemId then
            drops[tonumber(itemId)] = { chance = tonumber(percent) / 100, isQuestOnly = questFlag == "q" }
        end
    end
    if not next(drops) then
        return nil
    end
    return { drops = drops, source = "classic" }
end

---@return { drops: table<number, { chance: number, isQuestOnly: boolean }>, source: string, kills: number? }? loot
---nil when nothing is known about the creature
function Loot.getMobLoot(npcId)
    local loot = lootByNpcId[npcId]
    if loot == nil then
        loot = getForeverLoot(npcId) or getClassicLoot(npcId, ns.Database.getNpcField(npcId, "name")) or false
        lootByNpcId[npcId] = loot
    end
    return loot or nil
end

---Forgets what was read, for when the loot tables may have changed.
function Loot.reset()
    lootByNpcId = {}
end
