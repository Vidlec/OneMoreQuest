local _, ns = ...

-- Quest dialogs taken care of, the player's choice: quests accepted as they are offered, and handed in when ready.
-- Holding Shift as the dialog opens leaves it to the player, that once. A reward to choose from is always left to
-- the player, as is a hand-in that costs money; a grey (low-level) quest is never accepted on its own.
local AutoQuest = {}
ns.AutoQuest = AutoQuest

---@return boolean isHeld The player holds Shift: this dialog is theirs to answer
local function isOverridden()
    return IsShiftKeyDown ~= nil and IsShiftKeyDown() == true
end

local function isAccepting()
    return ns.settings.shouldAutoAccept == true and not isOverridden()
end

local function isHandingIn()
    return ns.settings.shouldAutoTurnIn == true and not isOverridden()
end

---@return boolean isGrey The quest is so far below the player that the game greys it: the game's own word when it
---gives one, else its level against the game's grey range (Availability.getTrivialGap)
function AutoQuest.isGrey(questId)
    questId = tonumber(questId)
    if not questId or questId <= 0 then
        return false
    end
    if C_QuestLog and C_QuestLog.IsQuestTrivial then
        local isFine, isTrivial = pcall(C_QuestLog.IsQuestTrivial, questId)
        if isFine and type(isTrivial) == "boolean" then
            return isTrivial
        end
    end
    local questLevel = tonumber(ns.Database.getQuestField(questId, "questLevel")) or 0
    local playerLevel = UnitLevel and UnitLevel("player") or 0
    return questLevel > 0 and playerLevel - questLevel > ns.Availability.getTrivialGap(playerLevel, "player")
end

---A quest offered in full (its text and Accept button): accepted, unless it is grey. The dialog opens straight on
---the quest for an NPC with only one, an item that starts one, or a quest a party member shares, with no list to
---skip grey quests in, so the quest itself is looked at here.
function AutoQuest.handleDetail()
    if not isAccepting() then
        return
    end
    -- A quest the game itself accepts as it is shown (some escorts and shared quests) needs no answer
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        return
    end
    if AutoQuest.isGrey(GetQuestID and GetQuestID()) then
        return
    end
    if AcceptQuest then
        AcceptQuest()
    end
end

---A quest's hand-in asking for what it needs: continued when the quest is ready.
function AutoQuest.handleProgress()
    if isHandingIn() and IsQuestCompletable and IsQuestCompletable() and CompleteQuest then
        CompleteQuest()
    end
end

---The last page of a hand-in, with its rewards: taken when there is nothing to choose, and nothing to pay.
function AutoQuest.handleComplete()
    if not isHandingIn() or not GetQuestReward then
        return
    end
    local choiceCount = GetNumQuestChoices and GetNumQuestChoices() or 0
    local cost = GetQuestMoneyToGet and GetQuestMoneyToGet() or 0
    if choiceCount <= 1 and cost <= 0 then
        GetQuestReward(choiceCount == 1 and 1 or 0)
    end
end

---An NPC with several quests (the gossip window or the old quest greeting): the first ready one is opened to hand
---in, or else the first that is not grey to accept. One at a time; the dialog that follows carries on.
---@param active { isComplete: boolean }[] The quests to hand in, in the window's order
---@param available { isTrivial: boolean }[] The quests to pick up, in the window's order
---@return string? kind "active" or "available": which list to open the quest from
---@return number? index Its place in that list
function AutoQuest.choose(active, available)
    if isHandingIn() then
        for index, quest in ipairs(active) do
            if quest.isComplete then
                return "active", index
            end
        end
    end
    if isAccepting() then
        for index, quest in ipairs(available) do
            if not quest.isTrivial then
                return "available", index
            end
        end
    end
    return nil
end

function AutoQuest.handleGossip()
    if not (C_GossipInfo and C_GossipInfo.GetActiveQuests) then
        return
    end
    local active, available = C_GossipInfo.GetActiveQuests() or {}, C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}
    local kind, index = AutoQuest.choose(active, available)
    if kind == "active" and C_GossipInfo.SelectActiveQuest then
        C_GossipInfo.SelectActiveQuest(active[index].questID)
    elseif kind == "available" and C_GossipInfo.SelectAvailableQuest then
        C_GossipInfo.SelectAvailableQuest(available[index].questID)
    end
end

function AutoQuest.handleGreeting()
    local active, available = {}, {}
    for index = 1, GetNumActiveQuests and GetNumActiveQuests() or 0 do
        local _, isComplete = GetActiveTitle(index)
        active[index] = { isComplete = isComplete == true }
    end
    for index = 1, GetNumAvailableQuests and GetNumAvailableQuests() or 0 do
        local isTrivial = GetAvailableQuestInfo and GetAvailableQuestInfo(index)
        available[index] = { isTrivial = isTrivial == true }
    end
    local kind, index = AutoQuest.choose(active, available)
    if kind == "active" and SelectActiveQuest then
        SelectActiveQuest(index)
    elseif kind == "available" and SelectAvailableQuest then
        SelectAvailableQuest(index)
    end
end

ns.registerModule({
    name = "AutoQuest",
    events = {
        QUEST_DETAIL = AutoQuest.handleDetail,
        QUEST_PROGRESS = AutoQuest.handleProgress,
        QUEST_COMPLETE = AutoQuest.handleComplete,
        GOSSIP_SHOW = AutoQuest.handleGossip,
        QUEST_GREETING = AutoQuest.handleGreeting,
    },
})
