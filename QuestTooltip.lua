local _, ns = ...

-- What every quest tooltip says the same way: the experience a quest gives, at the right end of its title line, and,
-- while Shift is held, the quest's details under it (what it asks in one sentence, each objective with its count, the
-- rewards, where it is handed in; for a quest to pick up, the level it needs). Without Shift a grey line says Shift
-- shows more. Used by the marks on the world map and the minimap, the spawn and area tooltips, the tracker's rows and
-- creatures' tooltips. A tooltip that shows details is filled again the moment Shift goes down or up.
local QuestTooltip = {}
ns.QuestTooltip = QuestTooltip

local TITLE_COLOR = { 1, 0.82, 0 } -- the game's NORMAL_FONT_COLOR
local EXPERIENCE_COLOR = { 0.73, 0.64, 1 }
local TEXT_COLOR = { 1, 1, 1 }
local SENTENCE_COLOR = { 0.85, 0.81, 0.66 }
local HINT_COLOR = { 0.6, 0.6, 0.6 }
local TURN_IN_COLOR = { 0.25, 1, 0.25 }
local GROUP_COLOR = { 1, 0.69, 0.38 } -- the players icon's orange

---@return number? experience What the quest gives this character now, or nil: none, or the character cannot gain any
function QuestTooltip.getExperience(questId)
    if not questId then
        return nil
    end
    local level = UnitLevel and UnitLevel("player") or nil
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or nil
    if level and maxLevel and level >= maxLevel then
        return nil
    end
    local experience = 0
    if ns.QuestState.isInLog(questId) and GetQuestLogRewardXP then
        experience = GetQuestLogRewardXP(questId) or 0
    end
    if experience <= 0 then
        -- Not in the log (or the game has no amount yet): the database's, lowered as the game would for a quest the
        -- character has outlevelled
        experience = ns.Database.getQuestExperience(questId, level) or 0
    end
    return experience > 0 and experience or nil
end

---@return string text "2,850 XP"
function QuestTooltip.formatExperience(experience)
    -- The game's grouping of thousands (as its own texts write them), else commas
    local number = BreakUpLargeNumbers and BreakUpLargeNumbers(experience)
        or tostring(math.floor(experience)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return ns.L("%s XP", number)
end

---@return number? level The quest's level: the log's for a quest in it, else the database's; nil when unknown
local function getLevel(questId)
    local quest = ns.QuestState.isInLog(questId) and ns.QuestState.getQuest(questId)
    local level = quest and quest.level or ns.Database.getQuestField(questId, "questLevel")
    return type(level) == "number" and level > 0 and level or nil
end

---@return string text The title as the quest lists write it: "[37] Name", a group quest "[37+] Name" with the players
---icon and how many it suggests. A title given with its level already ("[37] Name") keeps that level; whatever stands
---before it (a "!" or "?" icon) stays in front.
function QuestTooltip.formatTitle(text, questId)
    local prefix, level, name = text:match("^(.-)%[(%d+)%+?%] (.+)$")
    if not level then
        prefix, name, level = "", text, getLevel(questId)
    end
    level = tonumber(level)
    local group = ns.QuestState.getGroupInfo(questId)
    if level then
        return prefix .. ns.Widgets.formatQuestTitle(level, name, group)
    end
    return prefix .. (group and (name .. "  " .. ns.Widgets.formatGroup(group)) or name)
end

---A quest's title line: its level, a group quest's "+" and players icon, and the experience it gives at the right end.
---The tooltip's heading (not one of several quests a giver lists) also says what kind of group quest it is.
---@param color number[]? The title's colour; the game's gold when left out
---@param isListed boolean? One of several quests under a heading: the title alone
function QuestTooltip.addTitle(tooltip, text, questId, color, isListed)
    color = color or TITLE_COLOR
    text = questId and QuestTooltip.formatTitle(text, questId) or text
    local experience = QuestTooltip.getExperience(questId)
    if experience then
        tooltip:AddDoubleLine(text, QuestTooltip.formatExperience(experience), color[1], color[2], color[3],
            EXPERIENCE_COLOR[1], EXPERIENCE_COLOR[2], EXPERIENCE_COLOR[3])
    else
        tooltip:AddLine(text, color[1], color[2], color[3])
    end
    local group = questId and not isListed and ns.QuestState.getGroupInfo(questId)
    if group then
        tooltip:AddLine(group.kindText, GROUP_COLOR[1], GROUP_COLOR[2], GROUP_COLOR[3])
    end
end

---@return boolean isShowing The details are shown: Shift is held
function QuestTooltip.isShowingDetails()
    return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end

---@return string? sentence What the quest asks, in one sentence: the database's, in the player's language when a
---translation has it
function QuestTooltip.getSentence(questId)
    local text = ns.Database.getQuestField(questId, "objectivesText")
    if type(text) == "table" then
        text = table.concat(text, " ")
    end
    if type(text) ~= "string" or text == "" then
        return nil
    end
    return ns.QuestText.getObjectives(questId, text)
end

---@return string? text "Rewards: 2,850 XP · 45s", or nil when the quest gives nothing the game tells of
local function composeRewards(questId)
    local parts = {}
    local experience = QuestTooltip.getExperience(questId)
    if experience then
        parts[#parts + 1] = QuestTooltip.formatExperience(experience)
    end
    -- Money the game tells only for a quest in the log
    local money = ns.QuestState.isInLog(questId) and GetQuestLogRewardMoney and GetQuestLogRewardMoney(questId) or 0
    if money > 0 then
        parts[#parts + 1] = ns.Widgets.formatMoney(money)
    end
    if #parts == 0 then
        return nil
    end
    return ns.L("Rewards: %s", table.concat(parts, " · "))
end

---@return string? text "Turn in to Baron Revilgaz, Booty Bay"
local function composeTurnIn(questId)
    local places, name = ns.Location.getFinisherPlaces(questId)
    if not name then
        return nil
    end
    local place = places and places[1]
    local zoneName = place and place.zoneId and ns.Database.getZoneName(place.zoneId)
    if zoneName and zoneName ~= "" and zoneName ~= ns.L("Unknown location") then
        return ns.L("Turn in to %s, %s", name, zoneName)
    end
    return ns.L("Turn in to %s", name)
end

---The quest's details, while Shift is held; without it, the grey line that says so (once a tooltip: hasHint).
---@param options { hasObjectives: boolean?, hasTurnIn: boolean?, isBrief: boolean?, isHintShown: boolean? }?
---hasObjectives: the tooltip lists the objectives already; hasTurnIn: it says where to hand it in already;
---isBrief: one of several quests in the tooltip (a giver's): the sentence, the level it needs and the rewards
---@return boolean isShown The details were added
function QuestTooltip.addDetails(tooltip, questId, options)
    options = options or {}
    if not questId or not QuestTooltip.isShowingDetails() then
        return false
    end
    local isInLog = ns.QuestState.isInLog(questId)
    local sentence = QuestTooltip.getSentence(questId)
    if not options.isBrief then
        tooltip:AddLine(" ") -- set apart from what the tooltip says above
    end
    if sentence then
        tooltip:AddLine(sentence, options.isBrief and SENTENCE_COLOR[1] or TEXT_COLOR[1], options.isBrief and SENTENCE_COLOR[2] or TEXT_COLOR[2],
            options.isBrief and SENTENCE_COLOR[3] or TEXT_COLOR[3], true)
    end
    local quest = isInLog and not options.hasObjectives and not options.isBrief and ns.QuestState.getQuest(questId)
    if quest and #quest.objectives > 0 then
        tooltip:AddLine(" ")
        for _, objective in ipairs(quest.objectives) do
            local status = (objective.required or 0) > 0 and (objective.fulfilled .. "/" .. objective.required) or objective.isFinished and ns.L("done") or ""
            local shade = objective.isFinished and HINT_COLOR or TEXT_COLOR
            tooltip:AddDoubleLine(objective.shownLabel or objective.label or objective.text or "", status, shade[1], shade[2], shade[3], shade[1], shade[2], shade[3])
        end
    end
    local rewards = composeRewards(questId)
    if not isInLog then
        local required = ns.Database.getQuestField(questId, "requiredLevel")
        if type(required) == "number" and required > 1 then
            rewards = rewards and (ns.L("From level %d", required) .. " · " .. rewards) or ns.L("From level %d", required)
        end
    end
    if rewards then
        if not options.isBrief then
            tooltip:AddLine(" ")
        end
        tooltip:AddLine(rewards, TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3], true)
    end
    if not options.isBrief and not options.hasTurnIn then
        local turnIn = composeTurnIn(questId)
        if turnIn then
            tooltip:AddLine(turnIn, TURN_IN_COLOR[1], TURN_IN_COLOR[2], TURN_IN_COLOR[3], true)
        end
    end
    return true
end

---The grey line under a quest tooltip saying Shift shows more; nothing while Shift is held.
function QuestTooltip.addHint(tooltip)
    if not QuestTooltip.isShowingDetails() then
        tooltip:AddLine(ns.L("Hold Shift for details"), HINT_COLOR[1], HINT_COLOR[2], HINT_COLOR[3])
    end
end

-- The tooltip filled last, and how to fill it again: Shift going down or up fills it again while it is still up and
-- still that owner's. Kept in plain fields, the filling function and what it takes given apart, so a tooltip shown
-- makes no garbage (no closure each time).
local watchedTooltip, watchedOwner, watchedRefill, watchedArgument

---Fills it again when Shift goes down or up while it is shown for this owner: refill(argument).
---@param refill function Fills the tooltip again (owner, lines and Show, as the first time); a function made once
---@param argument any What refill takes (the button, the row, the quests under the cursor)
function QuestTooltip.watch(tooltip, owner, refill, argument)
    watchedTooltip, watchedOwner, watchedRefill, watchedArgument = tooltip, owner, refill, argument
end

---MODIFIER_STATE_CHANGED: a key press, never a frame; nothing done unless it is Shift and our tooltip is up.
function QuestTooltip.handleModifierChange(key)
    if not watchedRefill or type(key) ~= "string" or not key:find("SHIFT", 1, true) then
        return
    end
    if not watchedTooltip:IsShown() or watchedTooltip:GetOwner() ~= watchedOwner then
        watchedTooltip, watchedOwner, watchedRefill, watchedArgument = nil, nil, nil, nil -- (gone: forgotten)
        return
    end
    watchedRefill(watchedArgument)
end

ns.registerModule({
    name = "QuestTooltip",
    events = { MODIFIER_STATE_CHANGED = QuestTooltip.handleModifierChange },
})
