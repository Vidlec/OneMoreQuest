local _, ns = ...

-- A creature's tooltip (hovered in the world, on its nameplate, or on the target's portrait) says what it is
-- worth to your quests: for each quest in your log it counts for, the quest's name, then each unfinished
-- objective it helps with: an item it drops, with the count and the drop chance, or a kill, with the count.
local UnitTooltip = {}
ns.UnitTooltip = UnitTooltip

local CREATURES, KILL_CREDITS = 1, 5 -- the quest database's objective lists: creatures, and kill credit groups
local TITLE_COLOR = { 1, 0.82, 0 }
local LINE_COLOR = { 0.9, 0.9, 0.9 }
local CHANCE_COLOR = { 0.55, 0.8, 1 }
local DONE_COLOR = { 0.5, 0.5, 0.5 }

---@return number? npcId The creature a unit GUID belongs to ("Creature-0-…-npcId-spawn"); nil for players, pets,
---objects, and a GUID the game keeps secret
function UnitTooltip.getNpcId(guid)
    if type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) then
        return nil
    end
    local kind, npcId = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
    if kind ~= "Creature" and kind ~= "Vehicle" then
        return nil
    end
    return tonumber(npcId)
end

---@return boolean isTarget The creature is one a kill objective asks for: itself, or one of its kill credit group
local function isKillTarget(questId, typeIndex, npcId)
    local objectives = ns.Database.getQuestField(questId, "objectives") or {}
    local creatures, killCredits = objectives[CREATURES] or {}, objectives[KILL_CREDITS] or {}
    local creature = creatures[typeIndex]
    if creature then
        return creature[1] == npcId
    end
    local killCredit = killCredits[typeIndex - #creatures]
    for _, creditNpcId in ipairs(killCredit and killCredit[1] or {}) do
        if creditNpcId == npcId then
            return true
        end
    end
    return false
end

---@class UnitTooltipQuest
---@field questId number
---@field title string "[12] Plainstrider Menace"
---@field lines { text: string, chance: number?, isDone: boolean, kind: string }[] What the creature gives towards it:

---What a creature is worth to the quests in the log.
---@return UnitTooltipQuest[] quests In the log's order; empty when it counts for none
function UnitTooltip.compose(npcId)
    local quests = {}
    if not npcId then
        return quests
    end
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        local quest = ns.QuestState.getQuest(questId)
        local lines = {}
        local typeIndexes = {}
        for _, objective in ipairs(quest and not quest.isComplete and quest.objectives or {}) do
            typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
            local count = (objective.required or 0) > 1 and string.format(" %d/%d", objective.fulfilled or 0, objective.required) or ""
            if objective.type == "item" then
                local target = ns.Location.getObjectiveTarget(questId, "item", typeIndexes.item)
                local itemId = target and target.itemId
                local chance = itemId and ns.Drops.getChance(itemId, npcId)
                if itemId and (chance or ns.Drops.isDroppedBy(itemId, npcId)) then
                    lines[#lines + 1] = { text = (objective.shownLabel or objective.label) .. count, chance = chance, isDone = objective.isFinished == true, kind = "loot" }
                end
            elseif objective.type == "monster" and isKillTarget(questId, typeIndexes.monster, npcId) then
                lines[#lines + 1] = { text = (objective.shownLabel or objective.label) .. count, isDone = objective.isFinished == true, kind = "kill" }
            end
        end
        -- Only quests it still helps with: a finished objective is shown only beside one that is not
        local hasOpen = false
        for _, line in ipairs(lines) do
            hasOpen = hasOpen or not line.isDone
        end
        if hasOpen then
            local level = quest.level or ns.Database.getQuestField(questId, "questLevel")
            local title = quest.title or ns.QuestText.getTitle(questId, ns.Database.getQuestField(questId, "name") or ("Quest " .. questId))
            -- The database gives 0 for a level it does not know: then no level is shown
            local hasLevel = type(level) == "number" and level > 0
            quests[#quests + 1] = { questId = questId, title = hasLevel and string.format("[%d] %s", level, title) or title, lines = lines }
        end
    end
    return quests
end

---Adds the lines for a creature to a tooltip.
function UnitTooltip.addLines(tooltip, npcId)
    local quests = UnitTooltip.compose(npcId)
    if #quests == 0 then
        return false
    end
    tooltip:AddLine(" ")
    for _, quest in ipairs(quests) do
        ns.QuestTooltip.addTitle(tooltip, quest.title, quest.questId, TITLE_COLOR)
        for _, line in ipairs(quest.lines) do
            local color = line.isDone and DONE_COLOR or LINE_COLOR
            if line.chance then
                tooltip:AddDoubleLine("  " .. line.text, ns.Drops.formatChance(line.chance), color[1], color[2], color[3],
                    CHANCE_COLOR[1], CHANCE_COLOR[2], CHANCE_COLOR[3])
            else
                tooltip:AddLine("  " .. line.text, color[1], color[2], color[3])
            end
        end
    end
    tooltip:Show() -- to fit the new lines
    return true
end

local addedTo = {} -- [tooltip] = the creature whose lines it shows, until the game clears it

---@return boolean isShowing Questie runs with its own quest lines on creatures' tooltips: ours would repeat them
local function isQuestieShowingTooltips()
    local isLoaded = ns.isAddOnLoaded("Questie")
    if not isLoaded then
        return false
    end
    local isRead, isEnabled = pcall(function() return Questie.db.profile.enableTooltips end)
    return not isRead or isEnabled ~= false -- when its setting cannot be read, it is taken to be on
end
UnitTooltip.isQuestieShowingTooltips = isQuestieShowingTooltips

local function handleUnitTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not ns.settings.shouldShowUnitQuests or isQuestieShowingTooltips() then
        return
    end
    local guid = data and data.guid
    if not guid and tooltip.GetUnit then
        local _, unit = tooltip:GetUnit()
        if unit and not (issecretvalue and issecretvalue(unit)) and UnitGUID then
            guid = UnitGUID(unit)
        end
    end
    local npcId = UnitTooltip.getNpcId(guid)
    -- The game can run the post-call again for the same tooltip without clearing it: the lines go in once
    if not npcId or addedTo[tooltip] == npcId then
        return
    end
    if UnitTooltip.addLines(tooltip, npcId) then
        addedTo[tooltip] = npcId
    end
end

---Hooks creature tooltips: the game's tooltip data post-call for units, or, on an older client, the tooltip's
---own OnTooltipSetUnit.
function UnitTooltip.create()
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipCleared", function(tooltip) addedTo[tooltip] = nil end)
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, handleUnitTooltip)
    elseif GameTooltip and GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) handleUnitTooltip(tooltip) end)
    end
end

ns.registerModule({ name = "UnitTooltip", create = UnitTooltip.create })
