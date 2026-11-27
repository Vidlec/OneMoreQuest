local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: what a quest gives, on its page. The game's Rewards block pinned under the page
-- (State.rewardsBlock), the prize of the rest of its chain drawn over the chain's steps, and the worth of what its
-- objectives drop (the profit fold).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local BAR_HEIGHT, COLORS, LIST_WIDTH, PADDING, PAGE_CONTENT_WIDTH =
    Style.BAR_HEIGHT, Style.COLORS, Style.LIST_WIDTH, Style.PADDING, Style.PAGE_CONTENT_WIDTH
local addFold, hideTooltip, setAtlasIfKnown = QuestPage.addFold, QuestPage.hideTooltip, QuestPage.setAtlasIfKnown

local function showRewardTooltip(button, item)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if ns.QuestState.isInLog(item.questId) and GameTooltip.SetQuestLogItem then
        GameTooltip:SetQuestLogItem(item.rewardType, item.index, item.questId)
    elseif item.itemId and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(item.itemId) -- a quest not in the log has no quest-log tooltip
    else
        GameTooltip:AddLine(item.name, 1, 1, 1)
    end
    GameTooltip:Show()
end

local XP_ICON = "Interface\\Icons\\XP_Icon"

local REWARD_ICON_SIZE, REWARD_GAP = 30, 5
local MONEY_ICON = "Interface\\Icons\\INV_Misc_Coin_01" -- the coins the game's own quest rewards show
local REWARD_LABEL_COLOR = { 0.902, 0.788, 0.671 }

-- State.rewardsBlock: the game's "Rewards" block, pinned under the page; created with the window

---The height a piece of the game's art takes when stretched to a width, keeping its proportions.
local function getAtlasHeight(atlas, width, fallbackHeight)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if type(info) == "table" and type(info.width) == "number" and info.width > 0 and type(info.height) == "number" then
        return info.height * width / info.width
    end
    return fallbackHeight
end

---One reward in the strip: its icon in a black edge, with the count in the corner. The name and the rest
---are in its tooltip.
local function acquireRewardIcon(index)
    local button = State.rewardsBlock.icons[index]
    if not button then
        button = CreateFrame("Button", nil, State.rewardsBlock)
        button:SetSize(REWARD_ICON_SIZE, REWARD_ICON_SIZE)
        local edge = button:CreateTexture(nil, "BACKGROUND")
        edge:SetAllPoints(button)
        edge:SetColorTexture(0, 0, 0, 1)
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trims the icon's own border
        local hover = button:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(button.icon)
        hover:SetColorTexture(1, 1, 1, 0.18)
        button.count = ns.Widgets.createFontString(button, "OVERLAY", "NumberFontNormalSmall")
        button.count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 2)
        button:SetScript("OnEnter", function(self)
            if self.item then
                showRewardTooltip(self, self.item)
            elseif self.tooltipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.tooltipText, 1, 1, 1)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        State.rewardsBlock.icons[index] = button
    end
    return button
end

local function acquireRewardText(index)
    local text = State.rewardsBlock.texts[index]
    if not text then
        text = ns.Widgets.createFontString(State.rewardsBlock, "ARTWORK", "GameFontHighlight")
        State.rewardsBlock.texts[index] = text
    end
    return text
end

---Shows as much of the block as the page's scrolling has reached, the way the game's own quest page does:
---at first only its header and first row show under the page; over the last stretch of scrolling the block
---rises with the text until all of it is in view.
local function followPageScroll(scroll, maxScroll)
    if not State.rewardsBlock or not State.rewardsBlock:IsShown() then
        return
    end
    local hiddenHeight = State.rewardsBlock.fullHeight - State.rewardsBlock.peekHeight
    local revealed = math.max(0, math.min(hiddenHeight, scroll - (maxScroll - hiddenHeight)))
    State.rewardsBlock:SetHeight(State.rewardsBlock.peekHeight + revealed)
end

local setPageRewards
do
    -- The strip being filled: its edges, where its next piece goes, and how many icons and texts it took. One
    -- table, reset at each drawing.
    local strip = { left = 0, right = 0, x = 0, y = 0, iconCount = 0, textCount = 0 }

    ---Puts the strip's next piece after the last one, at the start of the next row when it does not fit.
    local function placeInStrip(region, width)
        if strip.x + width > strip.right and strip.x > strip.left then
            strip.x, strip.y = strip.left, strip.y + REWARD_ICON_SIZE + REWARD_GAP
        end
        region:ClearAllPoints()
        region:SetPoint("LEFT", State.rewardsBlock, "TOPLEFT", strip.x, -(strip.y + REWARD_ICON_SIZE / 2))
        region:Show()
        strip.x = strip.x + width + REWARD_GAP
    end

    local function addStripIcon(texture, item, count, tooltipText)
        strip.iconCount = strip.iconCount + 1
        local button = acquireRewardIcon(strip.iconCount)
        button.icon:SetTexture(texture)
        button.count:SetText(count and count > 1 and count or "")
        button.item, button.tooltipText = item, tooltipText
        placeInStrip(button, REWARD_ICON_SIZE)
    end

    ---@param isLabel boolean? In the label colour (words about the rewards), else white (an amount)
    local function addStripText(content, isLabel)
        strip.textCount = strip.textCount + 1
        local text = acquireRewardText(strip.textCount)
        text:SetText(content)
        if isLabel then
            text:SetTextColor(REWARD_LABEL_COLOR[1], REWARD_LABEL_COLOR[2], REWARD_LABEL_COLOR[3])
        else
            text:SetTextColor(1, 1, 1)
        end
        local width = text:GetStringWidth()
        placeInStrip(text, type(width) == "number" and width or (#content * 7))
    end

    ---Lays the rewards out in the strip: experience and money as amounts, the items as icons, the choices after them.
    ---@return number height The block's full height
    local function fillStrip(rewards, questId, hasRewards)
        strip.left = 12
        strip.right = PAGE_CONTENT_WIDTH + (State.frame.pageExtra or 0) + (State.frame.pageStretch or 0) - 12
        strip.x, strip.y = strip.left, State.rewardsBlock.topHeight + 6
        if not hasRewards then
            addStripText(ns.L("Asking the game for this quest's rewards..."), true)
        end
        -- (experience only where the Spoilers choice tells rewards whole, as the tooltips do)
        if rewards.experience > 0 and (type(questId) ~= "number" or ns.QuestTooltip.isExperienceShown(questId)) then
            addStripIcon(XP_ICON, nil, nil, ns.L("Experience"))
            addStripText(
                BreakUpLargeNumbers and BreakUpLargeNumbers(rewards.experience) or tostring(rewards.experience)
            )
            strip.x = strip.x + 4
        end
        if rewards.money > 0 then
            -- As the game shows it: the pile of coins, then the amount
            addStripIcon(MONEY_ICON, nil, nil, ns.L("Money"))
            addStripText(ns.Widgets.formatMoney(rewards.money))
            strip.x = strip.x + 4
        end
        for _, item in ipairs(rewards.items) do
            addStripIcon(item.texture, item, item.count)
        end
        if #rewards.choices > 0 then
            strip.x = strip.x + 4
            addStripText(ns.L(strip.x > strip.left + 4 and "or one of" or "Choose one"), true)
            for _, item in ipairs(rewards.choices) do
                addStripIcon(item.texture, item, item.count)
            end
        end
        return strip.y + REWARD_ICON_SIZE + State.rewardsBlock.bottomHeight
    end

    local function hideFrom(regions, firstIndex)
        for index = firstIndex, #regions do
            regions[index]:Hide()
        end
    end

    ---Fills the pinned "Rewards" block for a quest, or takes it away. Everything sits in one strip: the
    ---experience and money as amounts, the items as icons, the ones to choose between set apart. However much a
    ---quest gives, the block stays small; a strip too long for one row runs on into the next. The game sends
    ---the details of a quest that is not in the log only when asked, so the first look may say it is still asking.
    ---@param questId number|table|nil The quest whose rewards to show; or rewards already added up (experience, money,
    ---items, choices, isLoading), for a page about several quests; nil hides the block
    ---@return number extraHeight What the page adds to its scrolling for the rest of the block to rise into view
    function setPageRewards(questId)
        local block = State.rewardsBlock
        if not block then
            return 0
        end
        block.title:SetText(ns.L("Rewards"))
        -- A page about several quests (a dungeon's run) gives their rewards added up, in the same shape
        local rewards = type(questId) == "table" and questId or (questId and ns.QuestState.getRewards(questId))
        local hasRewards = rewards
            and (rewards.money > 0 or rewards.experience > 0 or #rewards.items > 0 or #rewards.choices > 0)
        strip.iconCount, strip.textCount = 0, 0
        local height = 0
        if rewards and (hasRewards or rewards.isLoading) then
            height = fillStrip(rewards, questId, hasRewards)
        end
        -- Only the first row shows until the page is scrolled to its end; further rows rise then
        local peekHeight = math.min(height, block.topHeight + 6 + REWARD_ICON_SIZE + block.bottomHeight)
        block.fullHeight, block.peekHeight = height, peekHeight
        block:SetHeight(math.max(peekHeight, 1))
        hideFrom(block.icons, strip.iconCount + 1)
        hideFrom(block.texts, strip.textCount + 1)
        block:SetShown(height > 0)
        State.detail.frame:SetPoint(
            "BOTTOMLEFT",
            State.frame,
            "BOTTOMLEFT",
            State.frame.pageLeft or LIST_WIDTH + 2,
            (State.frame.pageBottom or BAR_HEIGHT) + 2 + peekHeight
        ) -- (over the bar, or at the foot with a controller)
        return height - peekHeight
    end
end

---Builds the block from the game's own pieces: the header with its flourishes, the dark tile, the bottom edge.
local function createRewardsBlock(parent, pageLeft)
    local block = CreateFrame("Frame", nil, parent)
    block:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", pageLeft, BAR_HEIGHT)
    block:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", pageLeft + PAGE_CONTENT_WIDTH, BAR_HEIGHT)
    block:SetHeight(100)
    local width = PAGE_CONTENT_WIDTH
    block.topHeight = getAtlasHeight("questlog-reward-header-top", width, 34)
    -- The game's bottom piece is a tall picture made for a block of fixed height; on a block that is only as
    -- tall as its rewards it would be mostly empty space, so the tile simply runs to the edge
    block.bottomHeight = 8
    local background = block:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(block)
    if not setAtlasIfKnown(background, "questlog-reward-tile-vertical") then
        background:SetColorTexture(0.16, 0.11, 0.07, 1)
    end
    local top = block:CreateTexture(nil, "BORDER")
    top:SetPoint("TOPLEFT", block, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0)
    top:SetHeight(block.topHeight)
    if not setAtlasIfKnown(top, "questlog-reward-header-top") then
        top:SetColorTexture(0.11, 0.07, 0.04, 1)
    end
    local title = ns.Widgets.createFontString(block, "ARTWORK", "QuestFont_Huge")
    title:SetPoint("CENTER", top, "CENTER", 0, -3)
    title:SetText(ns.L("Rewards"))
    title:SetTextColor(REWARD_LABEL_COLOR[1], REWARD_LABEL_COLOR[2], REWARD_LABEL_COLOR[3])
    block.title = title -- named again at each drawing, in the language of the moment
    block.icons, block.texts = {}, {}
    block.fullHeight, block.peekHeight = 0, 0
    -- It grows upward over the end of the page, showing only as much of itself as its height allows
    if block.SetClipsChildren then
        block:SetClipsChildren(true)
    end
    block:SetFrameLevel((parent:GetFrameLevel() or 1) + 30)
    block:EnableMouse(true) -- the page under the risen block must not take its clicks
    block:Hide()
    return block
end

-- What the rest of a chain gives (this quest and every step after it), above its steps: the last step's reward
-- large, as the reason to go on, and the totals in one line under it. Asked of the game as the page is drawn; a
-- step whose rewards it has not sent yet fills in at the next drawing.
local PRIZE_ICON, PRIZE_GAP = 39, 8 -- (the game's quest reward icon)

---@return { experience: number, money: number, reputation: table<number, number>, factionOrder: number[], itemsOnTheWay: number, last: table, isLoading: boolean } rest
local function composeChainRest(questIds, index)
    local rest = { experience = 0, money = 0, reputation = {}, factionOrder = {}, itemsOnTheWay = 0, isLoading = false }
    for position = index, #questIds do
        local questId = questIds[position]
        local rewards = ns.QuestState.getRewards(questId)
        rest.isLoading = rest.isLoading or rewards.isLoading == true
        rest.experience = rest.experience + (rewards.experience or 0)
        rest.money = rest.money + (rewards.money or 0)
        if position == #questIds then
            rest.last = rewards
        else
            -- A choice is one item won, whichever is chosen
            rest.itemsOnTheWay = rest.itemsOnTheWay + #rewards.items + (#rewards.choices > 0 and 1 or 0)
        end
        for _, entry in ipairs(ns.Database.getQuestField(questId, "reputationReward") or {}) do
            local factionId, amount = entry[1], entry[2]
            if type(factionId) == "number" and type(amount) == "number" and amount > 0 then
                if not rest.reputation[factionId] then
                    rest.factionOrder[#rest.factionOrder + 1] = factionId
                end
                rest.reputation[factionId] = (rest.reputation[factionId] or 0) + amount
            end
        end
    end
    return rest
end

---@return number[] color The rim round a reward's icon: its quality's colour from Uncommon up, else the page's dark rim
local function getPrizeRimColor(quality)
    local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not color then
        return { 0.42, 0.29, 0.15 }
    end
    return { color.r, color.g, color.b }
end

---@return number[] color An item's name colour on the parchment: its quality's, darkened to read on the light page
local function getPrizeNameColor(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not color or quality <= 1 then
        return COLORS.ink
    end
    local dark = { color.r * 0.5, color.g * 0.5, color.b * 0.5 }
    -- Still too light to read on the page (a white or grey quality): the page's ink
    if 0.3 * dark[1] + 0.59 * dark[2] + 0.11 * dark[3] > 0.32 then
        return COLORS.ink
    end
    return dark
end

local BOX_CORNER, BOX_INSET = 24, 7

---The game's framed parchment panel (ParchmentPopup's art), drawn under what stands on it: its corners and edges in
---the gold-trimmed frame, its middle the darker parchment.
local function addParchmentBox(x, y, width, height)
    local page = State.detail
    local middle, side = width - 2 * BOX_CORNER, height - 2 * BOX_CORNER
    page:addImage(
        x + BOX_INSET,
        y + BOX_INSET,
        width - 2 * BOX_INSET,
        height - 2 * BOX_INSET,
        { atlas = "ParchmentPopup-Background" },
        nil,
        nil,
        -4
    )
    for _, part in ipairs({
        { "ParchmentPopup-TopLeft", x, y, BOX_CORNER, BOX_CORNER },
        { "ParchmentPopup-TopRight", x + width - BOX_CORNER, y, BOX_CORNER, BOX_CORNER },
        { "ParchmentPopup-BottomLeft", x, y + height - BOX_CORNER, BOX_CORNER, BOX_CORNER },
        { "ParchmentPopup-BottomRight", x + width - BOX_CORNER, y + height - BOX_CORNER, BOX_CORNER, BOX_CORNER },
        { "ParchmentPopup-Top", x + BOX_CORNER, y, middle, BOX_CORNER },
        { "ParchmentPopup-Bottom", x + BOX_CORNER, y + height - BOX_CORNER, middle, BOX_CORNER },
        { "ParchmentPopup-Left", x, y + BOX_CORNER, BOX_CORNER, side },
        { "ParchmentPopup-Right", x + width - BOX_CORNER, y + BOX_CORNER, BOX_CORNER, side },
    }) do
        page:addImage(part[2], part[3], part[4], part[5], { atlas = part[1] }, nil, nil, -3)
    end
end

local BOX_PADDING = 14
local XP_REWARD_ICON = "Interface\\Icons\\XP_Icon" -- the game's own experience icon, as on the quest's rewards

local addChainPrize
do
    local ICON_GROUND = { 0, 0, 0 }
    local ICON_TRIM = { 0.07, 0.93, 0.07, 0.93 } -- (the icon's own border cut off)
    local REST_LINE_HEIGHT = 20

    ---@return number left The panel's inside, where its text and items start
    ---@return number width
    local function getPrizeColumn()
        return PADDING + BOX_PADDING, State.detail.width - 2 * PADDING - 2 * BOX_PADDING
    end

    ---One item of the prize: the icon in its frame, the item's quality on its rim; the name beside it on the
    ---parchment, in ink (or its quality's colour, darkened to read on the page), wrapping in the item's column.
    local function addPrizeItem(x, y, item, columnWidth)
        State.detail:addRect(x, y, PRIZE_ICON, PRIZE_ICON, getPrizeRimColor(item.quality), 1)
        State.detail:addRect(x + 1, y + 1, PRIZE_ICON - 2, PRIZE_ICON - 2, ICON_GROUND, 2)
        State.detail:addIcon(
            x + 2,
            y + 2,
            PRIZE_ICON - 4,
            item.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
            nil,
            5,
            ICON_TRIM
        )
        if item.count and item.count > 1 then
            State.detail:addText(tostring(item.count), x, y + PRIZE_ICON - 13, {
                font = "NumberFontNormal",
                color = COLORS.white,
                width = PRIZE_ICON - 3,
                justify = "RIGHT",
                isSingleLine = true,
            })
        end
        -- (centred on the icon: placed, measured, then moved down by half what is left)
        local nameHeight, _, nameText = State.detail:addText(item.name, x + PRIZE_ICON + 5, y, {
            font = "QuestFont",
            color = getPrizeNameColor(item.quality),
            width = columnWidth - PRIZE_ICON - 8,
        })
        local nameTop = y + math.max(0, math.floor((PRIZE_ICON - (nameHeight or 14)) / 2))
        if nameText and nameTop ~= y then
            ns.Widgets.place(nameText, "TOPLEFT", State.detail.content, "TOPLEFT", x + PRIZE_ICON + 5, -nameTop)
        end
        State.detail:addButton(x, y, columnWidth, PRIZE_ICON, nil, item, showRewardTooltip, nil, hideTooltip)
    end

    ---The last step's reward, large, as the reason to go on: "At the end, <quest>:" and its items, two to a row.
    ---@param last table? The last step's rewards
    ---@return number y Below them, unchanged when the last step gives no item
    local function addPrizeItems(y, questIds, last)
        local items = last and (#last.choices > 0 and last.choices or last.items) or {}
        if #items == 0 then
            return y
        end
        local left, width = getPrizeColumn()
        local lastQuestId = questIds[#questIds]
        local name = ns.QuestText.getQuestName(lastQuestId) or ("Quest " .. lastQuestId)
        local label = #last.choices > 1 and ns.L("At the end, %s: choose one", name) or ns.L("At the end, %s:", name)
        y = y + State.detail:addText(label, left, y, { font = "QuestFont", color = COLORS.ink, width = width }) + 6
        -- Two to a row; one alone has the whole width, so its name fits on its plate
        local columnCount = #items == 1 and 1 or 2
        local columnWidth = math.floor((width - (columnCount - 1) * PRIZE_GAP) / columnCount)
        for position, item in ipairs(items) do
            local column = (position - 1) % columnCount
            addPrizeItem(left + column * (columnWidth + PRIZE_GAP), y, item, columnWidth)
            if column == columnCount - 1 or position == #items then
                y = y + PRIZE_ICON + 8
            end
        end
        return y
    end

    ---What is left, as pieces that flow and wrap whole: the game's experience icon and the amount, the coins,
    ---each faction, the items still on the way.
    ---@return { text: string, icon: string? }[] pieces
    local function composeRestPieces(rest)
        local pieces = {}
        if rest.experience > 0 then
            pieces[#pieces + 1] = {
                icon = XP_REWARD_ICON,
                text = BreakUpLargeNumbers and BreakUpLargeNumbers(rest.experience) or tostring(rest.experience),
            }
        end
        if rest.money > 0 then
            pieces[#pieces + 1] = { text = ns.Widgets.formatMoney(rest.money) }
        end
        for _, factionId in ipairs(rest.factionOrder) do
            pieces[#pieces + 1] = {
                text = string.format("%s +%d", ns.Availability.getFactionName(factionId), rest.reputation[factionId]),
            }
        end
        if rest.itemsOnTheWay > 0 then
            pieces[#pieces + 1] =
                { text = ns.Lp(rest.itemsOnTheWay, "%d more item on the way", "%d more items on the way") }
        end
        if rest.isLoading then
            pieces[#pieces + 1] = { text = ns.L("(asking the game for the rest)") }
        end
        return pieces
    end

    ---"Left in the chain:" and the pieces after it, wrapping whole onto the next line where one does not fit.
    ---@return number y Below the last line
    local function addRestLine(y, pieces)
        local left, width = getPrizeColumn()
        local right = left + width
        local _, leadWidth = State.detail:addText(
            ns.L("Left in the chain:"),
            left,
            y + 2,
            { font = "QuestFont", color = COLORS.softInk, isSingleLine = true }
        )
        local x = left + (leadWidth or 110) + 8
        for _, piece in ipairs(pieces) do
            local iconWidth = piece.icon and 20 or 0
            local textHeight, textWidth, text = State.detail:addText(
                piece.text,
                x + iconWidth,
                y + 2,
                { font = "QuestFont", color = COLORS.ink, isSingleLine = true }
            )
            textWidth = textWidth or (#piece.text * 7)
            if x + iconWidth + textWidth > right and x > left then
                -- Not room on this line: the piece starts the next one
                x, y = left, y + REST_LINE_HEIGHT
                if text then
                    ns.Widgets.place(text, "TOPLEFT", State.detail.content, "TOPLEFT", x + iconWidth, -(y + 2))
                end
            end
            if piece.icon then
                -- Centred on the amount beside it: the middle of its text, not the top of its line
                local iconTop = y + 2 + math.floor(((textHeight or 16) - 16) / 2 + 0.5)
                State.detail:addFramedIcon(x + 1, iconTop, 16, piece.icon, 1)
            end
            x = x + iconWidth + textWidth + 14
        end
        return y + REST_LINE_HEIGHT
    end

    ---The chain's prize and what is left in it, above the steps, in the game's framed parchment panel: each item as
    ---the game's quest window shows a reward (its icon in a frame on the reward name plate), two to a row, and what
    ---is left in one line of ink.
    ---@return number y Below it
    function addChainPrize(y, questIds, index)
        local rest = composeChainRest(questIds, index)
        local boxTop = y
        y = addPrizeItems(y + BOX_PADDING, questIds, rest.last)
        y = addRestLine(y, composeRestPieces(rest)) + BOX_PADDING - 4
        addParchmentBox(PADDING, boxTop, State.detail.width - 2 * PADDING, y - boxTop)
        return y + 10
    end
end

local function formatCopper(copper)
    return ns.Widgets.formatMoney(math.floor(copper + 0.5))
end

---Which prices the estimate was made with, in a few words.
local function composePriceNote(profit)
    if not ns.Prices.hasAuctionData() then
        return ns.L("Vendor prices (the Auctionator addon is not installed)")
    elseif not ns.settings.shouldUseAuctionPrices then
        return ns.L("Vendor prices (auction prices are switched off)")
    elseif profit.pricedCount == 0 then
        return ns.L("Auction prices")
    elseif profit.auctionPricedCount == 0 then
        return ns.L("Vendor prices: Auctionator has seen none of these items yet")
    end
    return ns.L("Auction prices for %d of %d items, vendor for the rest", profit.auctionPricedCount, profit.pricedCount)
end

---The loot line's detail: each creature with its kills and what they are expected to drop, and the small print.
local function showLootTooltip(button, profit)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.Lp(math.floor(profit.kills + 0.5), "Loot from %d kill", "Loot from %d kills"), 1, 0.82, 0)
    for _, mob in ipairs(profit.mobs) do
        local kills = math.floor(mob.kills + 0.5)
        local value = mob.lootValue > 0 and formatCopper(mob.lootValue) or ns.L("no loot known")
        GameTooltip:AddDoubleLine(kills .. " " .. mob.name, value, 1, 1, 1, 1, 1, 1)
    end
    local notes = { ns.L("An estimate from drop rates.") }
    if profit.hasUnknownKills then
        notes[#notes + 1] = ns.L("Some kills could not be counted: a quest item's drop rate is not known.")
    end
    notes[#notes + 1] = ns.L("Coins dropped by creatures are not counted.")
    GameTooltip:AddLine(table.concat(notes, " "), 0.63, 0.63, 0.63, true)
    GameTooltip:AddLine(composePriceNote(profit) .. ".", 0.63, 0.63, 0.63, true)
    GameTooltip:Show()
end

---How the estimate is made, for the "?" beside the Profit heading.
local function showProfitHelp(button)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.L("How profit is estimated"), 1, 0.82, 0)
    GameTooltip:AddLine(ns.L("Quest money + best reward item + loot from the kills still needed."), 1, 1, 1, true)
    local parts = {
        { ns.L("Reward items"), ns.L("Items you always get, plus the most valuable of the ones you choose between.") },
        {
            ns.L("Kills"),
            ns.L("What is left on kill objectives. For items to collect: items left divided by the drop chance."),
        },
        {
            ns.L("Loot"),
            ns.L("Each thing a creature can drop, times its chance, times the kills. Quest-only drops are left out."),
        },
        {
            ns.L("Prices"),
            ns.L(
                "The vendor's, or the auction house's after its %d%% cut when Auctionator has seen the item and it pays more.",
                5
            ),
        },
    }
    for _, part in ipairs(parts) do
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(part[1], 1, 0.82, 0)
        GameTooltip:AddLine(part[2], 0.82, 0.82, 0.82, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(
        ns.L("Not counted: coins dropped by creatures, travel and repair costs."),
        0.63,
        0.63,
        0.63,
        true
    )
    GameTooltip:Show()
end

---Where the profit estimate comes from, in as few lines as it takes: the quest's money, the reward item that
---counts, and the loot of the kills still needed. Hovering the loot line names the creatures. It folds away
---like the story.
---@return number y Below the section, unchanged when there is nothing to estimate
local function addProfitSection(y, questId)
    if not ns.settings.shouldShowProfit then
        return y
    end
    local profit = ns.Profit.get(questId)
    local totalText = ns.Profit.format(profit, COLORS.softInk)
    if not totalText then
        return y
    end
    local isOpen
    y, isOpen = addFold(y, "profit", questId, ns.L("Profit"), totalText, true, showProfitHelp)
    if not isOpen then
        return y
    end
    local left, right = PADDING, State.detail.width - PADDING
    local function addLine(text, amountText)
        State.detail:addText(
            text,
            left,
            y,
            { font = "QuestFont", color = COLORS.ink, width = right - left - 96, isSingleLine = true }
        )
        State.detail:addText(
            amountText,
            right - 92,
            y,
            { font = "QuestFont", color = COLORS.ink, width = 92, justify = "RIGHT", isSingleLine = true }
        )
        y = y + 21
    end
    if profit.rewardMoney > 0 then
        addLine(ns.L("Quest money"), formatCopper(profit.rewardMoney))
    end
    for _, rewardItem in ipairs(profit.rewardItems) do
        if rewardItem.isCounted and rewardItem.value > 0 then
            addLine(
                rewardItem.count > 1 and (rewardItem.name .. " x" .. rewardItem.count) or rewardItem.name,
                formatCopper(rewardItem.value)
            )
        end
    end
    if profit.kills > 0 then
        local lootText = profit.hasLootData and formatCopper(profit.lootValue) or ns.L("not counted")
        State.detail:addButton(left - 4, y - 2, right - left + 8, 21, nil, profit, showLootTooltip)
        addLine(ns.Lp(math.floor(profit.kills + 0.5), "Loot from %d kill", "Loot from %d kills"), lootText)
    end
    -- One quiet line: which prices were used, or why something is missing
    local note = composePriceNote(profit)
    if not profit.hasLootData and profit.kills > 0 then
        note = ns.L("No loot table is installed (the Tnny's Mob Loot addon), so loot is left out")
    elseif profit.isPending then
        note = ns.L("Still loading item prices; the amount may rise")
    end
    local noteHeight = State.detail:addText(
        note,
        left,
        y,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, width = right - left }
    )
    return y + noteHeight + 12
end

-- Shared with the other parts of the window
QuestPage.addChainPrize = addChainPrize
QuestPage.addProfitSection = addProfitSection
QuestPage.createRewardsBlock = createRewardsBlock
QuestPage.followPageScroll = followPageScroll
QuestPage.setPageRewards = setPageRewards
