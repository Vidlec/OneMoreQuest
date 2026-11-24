local _, ns = ...

-- A window that lists every quest in the quest log, highest estimated profit first, each with its breakdown.
local Window = {}
ns.Window = Window

local WIDTH, HEIGHT = 520, 560
local GREY, GREEN, GOLD = "|cffa0a0aa", "|cff8fe08a", "|cffffd100"

local frame, reportText, sourceButton
local isRefreshQueued = false

---@return number[] questIds Quests in the quest log, headers left out
local function getQuestLogQuestIds()
    local questIds = {}
    if C_QuestLog and C_QuestLog.GetInfo then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and info.questID then
                questIds[#questIds + 1] = info.questID
            end
        end
    elseif GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() do
            local _, _, _, isHeader, _, _, _, questId = GetQuestLogTitle(index)
            if not isHeader and questId then
                questIds[#questIds + 1] = questId
            end
        end
    end
    return questIds
end

local function composeQuestLines(profit, lines)
    local add = function(text)
        lines[#lines + 1] = text
    end
    add(
        string.format(
            "%s[%s] %s|r   ~%s",
            GOLD,
            tostring(profit.level or "?"),
            profit.name,
            ns.formatMoney(profit.total)
        )
    )

    add(GREY .. "  Rewards|r  " .. ns.formatMoney(profit.rewardValue))
    if profit.rewardMoney > 0 then
        add("    Money  " .. ns.formatMoney(profit.rewardMoney))
    end
    for _, rewardItem in ipairs(profit.rewardItems) do
        local note = ""
        if rewardItem.isChoice then
            note = rewardItem.isCounted and (GREEN .. "  best choice, counted|r")
                or (GREY .. "  other choice, not counted|r")
        end
        add(
            string.format(
                "    %s  %s%s",
                ns.Prices.getItemName(rewardItem.itemId),
                ns.formatMoney(rewardItem.value),
                note
            )
        )
    end

    for _, mob in ipairs(profit.mobs) do
        local source = mob.source == "forever" and "Forever data"
            or mob.source == "classic" and "Classic estimate"
            or "no loot data"
        add(
            string.format(
                "%s  %s|r  %d kills x %s = %s  %s(%s)|r",
                GREY,
                mob.name,
                math.ceil(mob.kills),
                ns.formatMoney(mob.perKill),
                ns.formatMoney(mob.lootValue),
                GREY,
                source
            )
        )
        for _, drop in ipairs(mob.drops) do
            add(
                string.format(
                    "    %s  %.1f%% x %s = %s",
                    ns.Prices.getItemName(drop.itemId),
                    drop.chance * 100,
                    ns.formatMoney(drop.value),
                    ns.formatMoney(drop.expected * mob.kills)
                )
            )
        end
    end
    if profit.hasUnknownKills then
        add(GREY .. "  Kill count unknown for some objective, its loot is not included|r")
    end
    add(" ")
end

local function composeReport()
    local profits, isPending = {}, false
    for _, questId in ipairs(getQuestLogQuestIds()) do
        local profit = ns.Calculator.composeQuestProfit(questId)
        if profit then
            profits[#profits + 1] = profit
            isPending = isPending or profit.isPending
        end
    end
    table.sort(profits, function(first, second)
        return first.total > second.total
    end)

    local lines, total = {}, 0
    for _, profit in ipairs(profits) do
        composeQuestLines(profit, lines)
        total = total + profit.total
    end
    if #profits == 0 then
        lines[#lines + 1] = GREY
            .. (ns.isReady and "No quests in the quest log." or "Questie is still loading.")
            .. "|r"
    else
        lines[#lines + 1] = "Whole quest log  " .. ns.formatMoney(total)
    end
    if not ns.Loot.hasData() then
        lines[#lines + 1] = GREY .. "Tnny's Mob Loot is not installed, so mob loot counts as 0.|r"
    end
    if ns.settings.priceSource == "auction" and not ns.Prices.hasAuctionData() then
        lines[#lines + 1] = GREY .. "Auctionator is not installed, vendor prices are used.|r"
    end
    lines[#lines + 1] = GREY .. "Coins dropped by mobs are not included.|r"
    return table.concat(lines, "\n"), isPending
end

local function getSourceLabel()
    return ns.settings.priceSource == "auction" and "Prices: Auctionator" or "Prices: vendor"
end

local function createWindow()
    frame = CreateFrame("Frame", "QuestieProfitWindow", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    if frame.TitleText then
        frame.TitleText:SetText("Quest profit")
    end
    tinsert(UISpecialFrames, "QuestieProfitWindow") -- closes on Escape

    sourceButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sourceButton:SetSize(160, 22)
    sourceButton:SetPoint("TOPLEFT", 12, -30)
    sourceButton:SetScript("OnClick", function()
        ns.setSetting("priceSource", ns.settings.priceSource == "auction" and "vendor" or "auction")
    end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 14, -60)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 12)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(WIDTH - 50, 1)
    scrollFrame:SetScrollChild(content)

    reportText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    reportText:SetPoint("TOPLEFT")
    reportText:SetWidth(WIDTH - 50)
    reportText:SetJustifyH("LEFT")
    reportText:SetSpacing(3)
    frame.content = content

    frame:SetScript("OnShow", Window.refresh)
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("QUEST_LOG_UPDATE")
    frame:SetScript("OnEvent", Window.queueRefresh)
end

function Window.refresh()
    if not frame or not frame:IsShown() then
        return
    end
    local report = composeReport()
    sourceButton:SetText(getSourceLabel())
    reportText:SetText(report)
    frame.content:SetHeight(reportText:GetStringHeight() + 10)
end

---Item data and quest log updates arrive in bursts, so they share one refresh.
function Window.queueRefresh()
    if isRefreshQueued or not frame or not frame:IsShown() then
        return
    end
    isRefreshQueued = true
    C_Timer.After(0.5, function()
        isRefreshQueued = false
        Window.refresh()
    end)
end

function Window.toggle()
    if not frame then
        createWindow()
        frame:Hide()
    end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

ns.addSettingsListener(Window.queueRefresh)
