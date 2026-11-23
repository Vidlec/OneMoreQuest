local _, ns = ...

local Tooltip = {}
ns.Tooltip = Tooltip

local LABEL_COLOR = { 0.7, 0.7, 0.74 }
local TITLE_COLOR = { 0.56, 0.88, 0.54 }

local function addProfitLines(tooltip, questId)
    local profit = ns.Calculator.composeQuestProfit(questId)
    if not profit then
        return
    end
    local addRow = function(label, value)
        tooltip:AddDoubleLine(label, value, LABEL_COLOR[1], LABEL_COLOR[2], LABEL_COLOR[3], 1, 1, 1)
    end

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("Profit: " .. profit.name, "~" .. ns.formatMoney(profit.total), TITLE_COLOR[1], TITLE_COLOR[2], TITLE_COLOR[3], 1, 1, 1)
    addRow("  Rewards", ns.formatMoney(profit.rewardValue))
    if profit.kills > 0 then
        addRow(string.format("  Mob loot, about %d kills", math.ceil(profit.kills)), ns.formatMoney(profit.lootValue))
    end
    if profit.hasUnknownKills then
        tooltip:AddLine("  Kill count unknown, loot is not included", 0.63, 0.63, 0.67)
    elseif profit.kills > 0 and not ns.Loot.hasData() then
        tooltip:AddLine("  Install Tnny's Mob Loot for loot values", 0.63, 0.63, 0.67)
    end
    if profit.isPending then
        tooltip:AddLine("  Item data is loading, hover again", 0.63, 0.63, 0.67)
    end
    tooltip:Show()
end

---Questie redraws the tooltip through tooltip:_Rebuild (also on a modifier key), so the lines go in after it.
local function handleTooltipShown(icon, tooltip)
    if not ns.settings.shouldShowInTooltip or not tooltip or tooltip._owner ~= icon or not tooltip:IsShown() then
        return
    end
    local questId = icon.data and icon.data.Id
    if type(questId) ~= "number" then
        return
    end
    local rebuild = tooltip._Rebuild
    if rebuild and rebuild == tooltip.questieProfitRebuild then
        return -- Questie skipped this call, the lines are already there
    end
    if rebuild then
        local rebuildWithProfit = function(self, ...)
            rebuild(self, ...)
            addProfitLines(self, questId)
        end
        tooltip._Rebuild = rebuildWithProfit
        tooltip.questieProfitRebuild = rebuildWithProfit
    end
    addProfitLines(tooltip, questId)
end

function Tooltip.addHook()
    local MapIconTooltip = QuestieLoader:ImportModule("MapIconTooltip")
    if type(MapIconTooltip.ShowOnTooltip) ~= "function" then
        ns.print("this Questie version has a different map tooltip, so only /qprofit works.")
        return
    end
    hooksecurefunc(MapIconTooltip, "ShowOnTooltip", function(icon, tooltip)
        local isSuccess, message = pcall(handleTooltipShown, icon, tooltip)
        if not isSuccess then
            ns.print("tooltip error: " .. tostring(message))
        end
    end)
end
