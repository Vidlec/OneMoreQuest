local _, ns = ...

-- How much OneMoreQuest tells: the player chooses, per character, from four presets (Guide, Hints, Explorer, Purist)
-- or by hand, for nine kinds of spoiler. Each part that shows something asks here first.
--
-- Explorer shows only what the player has found: givers and turn-ins met, places where an objective moved on,
-- creatures killed, what dropped from whom, dungeons entered. That memory is kept here, per character.
--
-- Wherever something is held back, "Need a hint?" shows it for one quest, a step at a time (Spoilers.getHint):
--   1 the zone, 2 roughly where (and the turn-in), 3 exactly where, with who drops it and the chances.
--
-- Cost: in Guide (the default) every question is answered by one flag (Spoilers.isActive() is false), so the parts
-- that draw skip all of this. Otherwise each answer is a table lookup; the memory is written only on rare events
-- (talking to someone, a kill, a loot, an objective moving on). Spoilers.getKey() changes whenever what is shown
-- may change, for the drawing parts' own "did anything change" keys.
local Spoilers = {}
ns.Spoilers = Spoilers

-- The nine kinds, each with its choices from the most shown to the least
local CATEGORIES = {
    { key = "pickup", choices = { "all", "met", "none" } },
    { key = "objectives", choices = { "exact", "rough", "found", "hidden" } },
    { key = "turnIn", choices = { "shown", "met", "hidden" } },
    { key = "drops", choices = { "chances", "names", "found", "hidden" } },
    { key = "creatures", choices = { "always", "killed", "hidden" } },
    { key = "chains", choices = { "all", "count", "hidden" } },
    { key = "rewards", choices = { "shown", "quest", "hidden" } },
    { key = "dungeons", choices = { "shown", "entered", "hidden" } },
    { key = "hints", choices = { "offered", "asked", "off" } },
}
Spoilers.CATEGORIES = CATEGORIES

local PRESETS = {
    guide = { pickup = "all", objectives = "exact", turnIn = "shown", drops = "chances", creatures = "always",
        chains = "all", rewards = "shown", dungeons = "shown", hints = "asked" },
    hints = { pickup = "all", objectives = "rough", turnIn = "shown", drops = "names", creatures = "always",
        chains = "count", rewards = "shown", dungeons = "shown", hints = "asked" },
    explorer = { pickup = "met", objectives = "found", turnIn = "met", drops = "found", creatures = "killed",
        chains = "count", rewards = "shown", dungeons = "entered", hints = "offered" },
    purist = { pickup = "none", objectives = "hidden", turnIn = "hidden", drops = "hidden", creatures = "hidden",
        chains = "hidden", rewards = "quest", dungeons = "hidden", hints = "asked" },
}
Spoilers.PRESETS = PRESETS
Spoilers.PRESET_ORDER = { "guide", "hints", "explorer", "purist" }

local HINT_ZONE, HINT_ROUGH, HINT_EXACT = 1, 2, 3
Spoilers.HINT_ZONE, Spoilers.HINT_ROUGH, Spoilers.HINT_EXACT = HINT_ZONE, HINT_ROUGH, HINT_EXACT
local OFFER_HINT_SECONDS = 20 * 60 -- in the quest's zone this long with no progress: "Need a hint?" offers itself
local MAX_FOUND_PER_OBJECTIVE = 12 -- places remembered for one objective
local FOUND_APART = 1.5 -- map percent: a place this near one remembered already is the same place

-- What the player chose, worked out once per change: [category] = choice; and each choice's rank (1 = most shown)
local chosen = {}
local rankOf = {}
for _, category in ipairs(CATEGORIES) do
    rankOf[category.key] = {}
    for rank, choice in ipairs(category.choices) do
        rankOf[category.key][choice] = rank
    end
end
local isActive = false -- anything held back at all
local choiceVersion, memoryVersion = 0, 0
local cachedKey, cachedKeyFor = "guide", nil

local function getRecord()
    return ns.getCharacterRecords("spoilers")
end

---What this character remembers having found. Created whole on first use, a damaged saved one mended, then kept:
---it is asked for on every question about a quest (while the settings stay the same table: a reset makes new ones).
local cachedMemory, cachedMemoryFor = nil, nil
local function getMemory()
    if cachedMemory and cachedMemoryFor == ns.settings then
        return cachedMemory
    end
    local memory = ns.getCharacterRecords("discoveries")
    for _, key in ipairs({ "met", "killed", "found", "drops", "entered", "hints", "hinted" }) do
        if type(memory[key]) ~= "table" then
            memory[key] = {}
        end
    end
    if type(memory.peeks) ~= "number" then
        memory.peeks = 0
    end
    cachedMemory, cachedMemoryFor = memory, ns.settings
    return memory
end
Spoilers.getMemory = getMemory

---Works out the choices again from the saved record: the preset's, with the player's own changes over them.
local function readChoices()
    local record = getRecord()
    local preset = PRESETS[record.preset] or PRESETS.guide
    local own = type(record.choices) == "table" and record.choices or {}
    isActive = false
    for _, category in ipairs(CATEGORIES) do
        local choice = own[category.key]
        if not rankOf[category.key][choice] then
            choice = preset[category.key]
        end
        chosen[category.key] = choice
        -- (hints never hold anything back by themselves)
        if category.key ~= "hints" and rankOf[category.key][choice] > 1 then
            isActive = true
        end
    end
    choiceVersion = choiceVersion + 1
end

---@return boolean isActive Something is held back: false in Guide, where nothing needs asking
function Spoilers.isActive()
    return isActive
end

---@return string preset "guide", "hints", "explorer", "purist", or "custom" when changed by hand
function Spoilers.getPreset()
    local record = getRecord()
    if type(record.choices) == "table" and next(record.choices) then
        return "custom"
    end
    return PRESETS[record.preset] and record.preset or "guide"
end

---@return string choice The player's choice for a kind of spoiler, as chosen (no hint taken into account)
function Spoilers.getChoice(category)
    return chosen[category]
end

local function changed()
    readChoices()
    ns.emit("SPOILERS_CHANGED")
    ns.queueRefresh()
end

---Picks a preset: the player's own changes go.
function Spoilers.setPreset(preset)
    if not PRESETS[preset] then
        return
    end
    local record = getRecord()
    record.preset, record.choices = preset, nil
    changed()
end

---Changes one kind by hand; the same as the preset's choice takes the change back.
function Spoilers.setChoice(category, choice)
    if not rankOf[category] or not rankOf[category][choice] then
        return
    end
    local record = getRecord()
    local preset = PRESETS[record.preset] or PRESETS.guide
    if type(record.choices) ~= "table" then
        record.choices = {}
    end
    record.choices[category] = choice ~= preset[category] and choice or nil
    if not next(record.choices) then
        record.choices = nil
    end
    changed()
end

---@return string key Changes whenever what is shown may change (a choice, a hint, something found): for the drawing
---parts' keys. The same "guide" while nothing is held back.
function Spoilers.getKey()
    if not isActive then
        return "guide"
    end
    local version = choiceVersion * 100000 + memoryVersion
    if cachedKeyFor ~= version then
        cachedKey, cachedKeyFor = "s" .. version, version
    end
    return cachedKey
end

---A step of the hint ladder lifts one quest's choice: 2 at least a rough area and the turn-in, 3 everything.
local HINT_LIFTS = {
    [HINT_ROUGH] = { objectives = "rough", turnIn = "shown", drops = "names", creatures = "always" },
    [HINT_EXACT] = { objectives = "exact", turnIn = "shown", drops = "chances", creatures = "always", dungeons = "shown" },
}

---@param questId number? The quest it is for, whose hints count; nil for the choice alone
---@return string choice What to show of this kind for this quest: the choice, or more where a hint was taken
function Spoilers.get(category, questId)
    local choice = chosen[category]
    if not isActive or not questId then
        return choice
    end
    local hint = getMemory().hints[questId]
    local lift = hint and HINT_LIFTS[hint >= HINT_EXACT and HINT_EXACT or hint]
    local lifted = lift and lift[category]
    if lifted and rankOf[category][lifted] < rankOf[category][choice] then
        return lifted
    end
    return choice
end

---@return boolean isShown Some of this kind is shown for the quest (anything but "hidden" / "none" / "off")
function Spoilers.isShown(category, questId)
    local choice = Spoilers.get(category, questId)
    return choice ~= "hidden" and choice ~= "none" and choice ~= "off"
end

-- The memory: what the player has found

---@return boolean isMet The player talked to this creature, or had it targeted (a giver, a turn-in)
function Spoilers.hasMet(npcId)
    return npcId ~= nil and getMemory().met[npcId] == true
end

---@return boolean isKilled The player killed one of these creatures
function Spoilers.hasKilled(npcId)
    return npcId ~= nil and getMemory().killed[npcId] == true
end

---@return boolean isSeen This creature (or object) dropped this item for the player
function Spoilers.hasSeenDrop(itemId, sourceId)
    local sources = itemId and getMemory().drops[itemId]
    return sources ~= nil and (sourceId == nil or sources[sourceId] == true)
end

---@return boolean isEntered The player was inside this dungeon
function Spoilers.hasEntered(dungeonId)
    return dungeonId ~= nil and getMemory().entered[dungeonId] == true
end

---@return { zoneId: number, x: number, y: number }[] places Where the player saw this objective move on (one list
---per objective, in the order of the quest's objectives); empty when none. Read only.
local NO_PLACES = {}
function Spoilers.getFoundPlaces(questId, objectiveIndex)
    local quest = getMemory().found[questId]
    return quest and quest[objectiveIndex] or NO_PLACES
end

---@return boolean isFound The player saw any objective of the quest move on somewhere
function Spoilers.hasFoundAny(questId)
    local quest = getMemory().found[questId]
    return quest ~= nil and next(quest) ~= nil
end

local function remembered()
    memoryVersion = memoryVersion + 1
end

local function noteMet(npcId)
    if npcId and isActive then
        local met = getMemory().met
        if not met[npcId] then
            met[npcId] = true
            remembered()
            ns.queueRefresh()
        end
    end
end

---A creature the player killed (KillCounter tells, once per kill).
function Spoilers.noteKill(npcId)
    if npcId and isActive then
        local killed = getMemory().killed
        if not killed[npcId] then
            killed[npcId] = true
            remembered()
            if chosen.creatures == "killed" then
                ns.queueRefresh() -- (the first of its kind: its nameplates and tooltips may name it now)
            end
        end
    end
end

local function getUnitNpcId(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if not guid or (issecretvalue and issecretvalue(guid)) then
        return nil
    end
    return ns.Database.getNpcId(guid)
end

-- Where each log objective stood when last looked: [questId] = { [objectiveIndex] = fulfilled }
local lastCounts = {}
local lastProgressAt = {} -- [questId] = time the quest last moved on (this session)

---The player's place on the zone's map, as quest places are given: { zoneId, x, y } (0-100), or nil (an instance).
local function getPlayerPlace()
    local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local position = uiMapId and C_Map.GetPlayerMapPosition(uiMapId, "player")
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    local areaId = ns.Database.getAreaId(uiMapId)
    if not areaId or not x or (x == 0 and y == 0) then
        return nil
    end
    return { zoneId = areaId, x = math.floor(x * 1000 + 0.5) / 10, y = math.floor(y * 1000 + 0.5) / 10 }
end

local function noteFound(questId, objectiveIndex, place)
    local found = getMemory().found
    found[questId] = found[questId] or {}
    local places = found[questId][objectiveIndex] or {}
    found[questId][objectiveIndex] = places
    for _, known in ipairs(places) do
        if known.zoneId == place.zoneId and math.abs(known.x - place.x) < FOUND_APART and math.abs(known.y - place.y) < FOUND_APART then
            return
        end
    end
    if #places >= MAX_FOUND_PER_OBJECTIVE then
        table.remove(places, 1) -- the oldest goes: the newest are likelier where the player hunts now
    end
    places[#places + 1] = place
    remembered()
end

---After each change of the quest log: an objective that moved on is remembered where the player stands.
---Only the counts are read (the game's own list), and only while something is held back.
local function lookAtProgress()
    if not isActive then
        return
    end
    local now = GetTime and GetTime() or 0
    local isInLog = {}
    local place -- (read once, the first time it is needed)
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        isInLog[questId] = true
        local counts = lastCounts[questId]
        local objectives = C_QuestLog.GetQuestObjectives(questId) or NO_PLACES
        if not counts then
            counts = {}
            lastCounts[questId] = counts
            for index, objective in ipairs(objectives) do
                counts[index] = objective.numFulfilled or 0
            end
        else
            for index, objective in ipairs(objectives) do
                local fulfilled = objective.numFulfilled or 0
                if fulfilled > (counts[index] or 0) then
                    place = place or getPlayerPlace() or false
                    if place then
                        noteFound(questId, index, place)
                    end
                    lastProgressAt[questId] = now
                end
                counts[index] = fulfilled
            end
        end
    end
    for questId in pairs(lastCounts) do
        if not isInLog[questId] then
            lastCounts[questId], lastProgressAt[questId] = nil, nil
        end
    end
end

local ITEM_CLASS_QUEST = 12

---The loot window opened: a quest item from a creature or an object is remembered as dropped by it.
local function lookAtLoot()
    if not isActive or not GetNumLootItems or not GetLootSourceInfo then
        return
    end
    local drops = getMemory().drops
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local itemId = link and tonumber(link:match("item:(%d+)"))
        local classId = itemId and GetItemInfoInstant and select(6, GetItemInfoInstant(itemId))
        if itemId and classId == ITEM_CLASS_QUEST then
            local guid = GetLootSourceInfo(slot)
            local sourceId = guid and not (issecretvalue and issecretvalue(guid)) and tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
            if sourceId then
                drops[itemId] = drops[itemId] or {}
                if not drops[itemId][sourceId] then
                    drops[itemId][sourceId] = true
                    remembered()
                end
            end
        end
    end
end

local function lookAtInstance()
    if not isActive then
        return
    end
    local dungeonId = ns.Database.getInstanceDungeonId()
    local entered = getMemory().entered
    if dungeonId and not entered[dungeonId] then
        entered[dungeonId] = true
        remembered()
        ns.queueRefresh()
    end
end

-- Hints

---@return number step How far the hint ladder was climbed for this quest: 0 none, 1 zone, 2 rough, 3 exact
function Spoilers.getHint(questId)
    return questId and getMemory().hints[questId] or 0
end

---One more step of the ladder for this quest (or the step given). The quest is marked as done with hints.
function Spoilers.giveHint(questId, step)
    local memory = getMemory()
    local current = memory.hints[questId] or 0
    step = math.min(HINT_EXACT, step or current + 1)
    if step <= current then
        return
    end
    memory.hints[questId] = step
    memory.hinted[questId] = true
    remembered()
    ns.emit("SPOILERS_CHANGED")
    ns.queueRefresh()
end

---@return boolean isHinted A hint was taken for this quest (the Chronicle marks those done without)
function Spoilers.wasHinted(questId)
    return getMemory().hinted[questId] == true
end

---Alt held over the map shows everything for a moment: counted, and each quest it showed counts as hinted.
function Spoilers.notePeek(questIds)
    local memory = getMemory()
    memory.peeks = memory.peeks + 1
    for _, questId in ipairs(questIds or NO_PLACES) do
        memory.hinted[questId] = true
    end
end

---@return boolean isNeeded Something of this quest is held back that a hint could show
function Spoilers.canHint(questId)
    if not isActive or chosen.hints == "off" then
        return false
    end
    return Spoilers.getHint(questId) < HINT_EXACT
end

---@return boolean isOffered "Need a hint?" offers itself for this quest: the player chose "Offered", has been in the
---quest's zone a while (OFFER_HINT_SECONDS) and the quest has not moved on since
local zoneEnteredAt, enteredZoneId = 0, nil
function Spoilers.isHintOffered(questId)
    if not isActive or chosen.hints ~= "offered" or not Spoilers.canHint(questId) then
        return false
    end
    local now = GetTime and GetTime() or 0
    local since = math.max(zoneEnteredAt, lastProgressAt[questId] or 0)
    return now - since >= OFFER_HINT_SECONDS
end

local function lookAtZone()
    local zoneId = ns.Model.getPlayer().zoneId
    if zoneId ~= enteredZoneId then
        enteredZoneId, zoneEnteredAt = zoneId, GetTime and GetTime() or 0
    end
end

-- The map's fog: what the player has explored of a zone, as the game draws it

local exploredRects = {} -- [uiMapId] = { { left, top, right, bottom } in 0-100 }, or false where the game has no fog
local function readExplored(uiMapId)
    if not (C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures and C_Map.GetMapArtLayers) then
        return false
    end
    local layers = C_Map.GetMapArtLayers(uiMapId)
    local layer = layers and layers[1]
    local textures = C_MapExplorationInfo.GetExploredMapTextures(uiMapId)
    if not layer or not layer.layerWidth or layer.layerWidth == 0 or not textures then
        return false
    end
    local rects = {}
    for _, texture in ipairs(textures) do
        local left = texture.offsetX / layer.layerWidth * 100
        local top = texture.offsetY / layer.layerHeight * 100
        rects[#rects + 1] = { left, top, left + texture.textureWidth / layer.layerWidth * 100, top + texture.textureHeight / layer.layerHeight * 100 }
    end
    return rects
end

---@return boolean isExplored The player has explored this spot of the zone's map (always true where the game keeps
---no fog, or with nothing held back)
function Spoilers.isExplored(zoneId, x, y)
    if not isActive then
        return true
    end
    local uiMapId = ns.Database.getUiMapId(zoneId)
    if not uiMapId then
        return true
    end
    local rects = exploredRects[uiMapId]
    if rects == nil then
        rects = readExplored(uiMapId)
        exploredRects[uiMapId] = rects
    end
    if rects == false then
        return true -- (the game keeps no fog for this map)
    end
    for _, rect in ipairs(rects) do
        if x >= rect[1] and x <= rect[3] and y >= rect[2] and y <= rect[4] then
            return true
        end
    end
    return false
end

-- Commands and life

local PRESET_WORDS = { guide = "guide", hints = "hints", explorer = "explorer", purist = "purist" }

---/omq spoilers [guide|hints|explorer|purist]: picks a preset, or says which one is on.
function Spoilers.handleCommand(word)
    word = word and word:lower() or ""
    if PRESET_WORDS[word] then
        Spoilers.setPreset(word)
        ns.print(ns.L("Spoilers: %s", ns.L(Spoilers.getPresetName(word))))
    else
        ns.print(ns.L("Spoilers: %s", ns.L(Spoilers.getPresetName(Spoilers.getPreset()))) .. "  (/omq spoilers guide | hints | explorer | purist)")
    end
end

local PRESET_NAMES = { guide = "Guide", hints = "Hints", explorer = "Explorer", purist = "Purist", custom = "Custom" }
---@return string name The preset's English name, to translate with ns.L
function Spoilers.getPresetName(preset)
    return PRESET_NAMES[preset] or PRESET_NAMES.guide
end

function Spoilers.create()
    cachedMemory = nil -- (another character's, after a test or a reload)
    readChoices()
end

---For the tests: the session's own memory forgotten (what is saved stays).
function Spoilers.reset()
    lastCounts, lastProgressAt, exploredRects = {}, {}, {}
    zoneEnteredAt, enteredZoneId = 0, nil
    cachedMemory = nil
    readChoices()
end

ns.registerModule({
    name = "Spoilers",
    create = Spoilers.create,
    -- Each redraw (a quiet one too: a count went up) looks at what moved on, while something is held back
    invalidate = function()
        if isActive then
            lookAtProgress()
            lookAtZone()
        end
    end,
    events = {
        GOSSIP_SHOW = function() noteMet(getUnitNpcId("npc")) end,
        QUEST_GREETING = function() noteMet(getUnitNpcId("npc")) end,
        QUEST_DETAIL = function() noteMet(getUnitNpcId("npc")) end,
        QUEST_PROGRESS = function() noteMet(getUnitNpcId("npc")) end,
        QUEST_COMPLETE = function() noteMet(getUnitNpcId("npc")) end,
        PLAYER_TARGET_CHANGED = function()
            if isActive and UnitExists and UnitExists("target") and not (UnitCanAttack and UnitCanAttack("player", "target")) then
                noteMet(getUnitNpcId("target"))
            end
        end,
        LOOT_OPENED = lookAtLoot,
        PLAYER_ENTERING_WORLD = lookAtInstance,
        ZONE_CHANGED_NEW_AREA = lookAtInstance,
        MAP_EXPLORATION_UPDATED = function() exploredRects = {} remembered() end,
    },
    -- What was found for a quest goes once it leaves the log; met, killed, drops and dungeons stay (they are few)
    prune = function(isInLog)
        if not isInLog then
            return
        end
        local memory = getMemory()
        for questId in pairs(memory.found) do
            if not isInLog[questId] then
                memory.found[questId] = nil
            end
        end
        for questId in pairs(memory.hints) do
            if not isInLog[questId] then
                memory.hints[questId] = nil
            end
        end
        -- (the Chronicle copies "hinted" into its own record at the hand-in)
        for questId in pairs(memory.hinted) do
            if not isInLog[questId] then
                memory.hinted[questId] = nil
            end
        end
    end,
})
