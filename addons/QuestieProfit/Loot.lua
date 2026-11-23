local _, ns = ...

-- Reads the loot tables that Tnny's Mob Loot ships as globals:
--   TnnysMobLoot_Forever.npc[npcId] = { "name", "itemId:percent:drops:kills,..." }   (Everloot, real Forever kills)
--   TnnysMobLoot_Starter.npc[npcId] = { "itemId:percent[:q],...", skinning, worldDrops, "Name", ... }   (CMaNGOS Classic)
local Loot = {}
ns.Loot = Loot

local lootCache = {}

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
    if maxKills < ns.settings.minForeverKills or not next(drops) then
        return nil
    end
    return { drops = drops, source = "forever", kills = maxKills }
end

---The Classic entry counts only when its name agrees with the mob's name, so a renumbered Forever mob never
---gets another mob's loot.
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

---@param npcId number
---@param npcName string? Name of the mob as Questie knows it
---@return { drops: table<number, { chance: number, isQuestOnly: boolean }>, source: string, kills: number? }?
function Loot.getMobLoot(npcId, npcName)
    local cached = lootCache[npcId]
    if cached == nil then
        cached = getForeverLoot(npcId) or getClassicLoot(npcId, npcName) or false
        lootCache[npcId] = cached
    end
    return cached or nil
end

ns.addSettingsListener(function(key)
    if key == "minForeverKills" then
        lootCache = {}
    end
end)
