local _, ns = ...

-- The quest log window: the page on parchment (a quest's page, its header and rewards, a zone's page).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window = ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local selectQuest = Actions.selectQuest
local selectedQuestIds = State.selectedQuestIds
local BAR_HEIGHT, COLORS, DOT, ITEM_ICON, LIST_WIDTH, MAX_OPEN_CHAIN = Style.BAR_HEIGHT, Style.COLORS, Style.DOT, Style.ITEM_ICON, Style.LIST_WIDTH, Style.MAX_OPEN_CHAIN
local MEDIA, PADDING, PAGE_CONTENT_WIDTH, PAGE_TOP, PAPER_FILL, READY_ICON = Style.MEDIA, Style.PADDING, Style.PAGE_CONTENT_WIDTH, Style.PAGE_TOP, Style.PAPER_FILL, Style.READY_ICON
local SELECTED_EDGE, TAB_AVAILABLE = Style.SELECTED_EDGE, Style.TAB_AVAILABLE
local showPlace = Window.showPlace

-- The selected quest on parchment

---@return number y Below the heading
local function addHeading(y, text)
    local height = State.detail:addText(text, PADDING, y, { font = "QuestFont_Large", color = COLORS.ink, isSingleLine = true })
    return y + height + 6
end

---@return number y Below the text
local function addBody(y, text, color, indent)
    local height = State.detail:addText(text, PADDING + (indent or 0), y, {
        font = "QuestFont", color = color or COLORS.ink, width = State.detail.width - 2 * PADDING - (indent or 0),
    })
    return y + height + 4
end

---@param subLines string[] Short lines under the title
---@return number y Below the title block
local function addTitle(y, title, subLines)
    local width = State.detail.width - 2 * PADDING
    local height = State.detail:addText(title, PADDING, y, { font = "QuestFont_Huge", color = COLORS.ink, width = width })
    y = y + height + 3
    for _, line in ipairs(subLines) do
        height = State.detail:addText(line, PADDING, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width })
        y = y + height + 2
    end
    return y + 12
end

---A small button drawn on the parchment.
---@return number width
local function addPaperButton(canvas, right, y, text, handleClick, data)
    local width = #text * 6.5 + 18
    local x = right - width
    canvas:addRect(x, y, width, 20, COLORS.softInk, 4)
    canvas:addRect(x + 1, y + 1, width - 2, 18, PAPER_FILL, 5)
    canvas:addText(text, x, y + 4, { font = "GameFontHighlightSmall", color = COLORS.ink, width = width, justify = "CENTER", isSingleLine = true })
    canvas:addButton(x, y, width, 20, handleClick, data)
    return width
end

---Turns the map to a place named on the page, the place in the middle when the map is zoomed in. The
---Available tab keeps its list and its selected quest meanwhile.
---@param target { place: table }
local function showPlace(target)
    local place = target.place
    State.isMapFollowPaused = true
    ns.MapDock.showQuestPlace(place.mapZoneId or place.groupZoneId, place)
    State.isMapFollowPaused = false
end

---A place as a line for addStepLine: the zone and its spot as a link that turns the map there, the way there
---after it. "Inside <dungeon>, entrance at" goes before a dungeon's entrance.
---@param options { distance: number?, direction: string?, prefix: string?, suffix: string?, handleClick: function?, data: table? }?
---@return table line
local function composePlaceLine(place, options)
    options = options or {}
    local zoneName = ns.Database.getZoneName(place.mapZoneId or place.groupZoneId)
    local prefix = options.prefix
    if place.dungeonName then
        prefix = (prefix and (prefix .. " ") or "") .. ns.L("inside %s, entrance at", place.dungeonName)
        prefix = prefix:gsub("^%l", string.upper)
    end
    local after = {}
    if options.distance and options.direction then
        after[#after + 1] = ns.Widgets.formatDistance(options.distance) .. " " .. options.direction
    end
    if options.suffix then
        after[#after + 1] = options.suffix
    end
    return {
        text = prefix, link = place.x >= 0 and string.format("%s %d, %d", zoneName, place.x, place.y) or zoneName,
        afterText = #after > 0 and (DOT:gsub("^ ", "") .. table.concat(after, DOT)) or nil,
        handleClick = options.handleClick or showPlace, data = options.data or { place = place },
    }
end

---Where each objective of a quest is found.
---@return { objective: table, place: table?, distance: number?, sourceText: string? }[] details In the quest's order
local function composeObjectiveDetails(entry)
    local details, typeIndexes = {}, {}
    local position = ns.Geometry.getPlayerPosition()
    for _, objective in ipairs(entry.objectives) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        local stillNeeded = objective.required and objective.required > 0 and math.max(objective.required - (objective.fulfilled or 0), 0) or nil
        local places, sourceText, isCrafted = ns.Location.getObjectiveInfo(entry.questId, objective.type, typeIndexes[objective.type], objective.label, stillNeeded)
        local distance, _, place = ns.Geometry.getNearest(places, position, ns.Database.getUiMapId)
        -- For an item that drops, how often: the chance of its likeliest source, the one worth hunting
        -- For an item that drops: where, zone by zone, each creature with its chance (Drops)
        local zones
        local target = objective.type == "item" and ns.Location.getObjectiveTarget(entry.questId, "item", typeIndexes.item)
        if target and target.itemId then
            zones = ns.Drops.getZones(target.itemId)
        end
        details[#details + 1] = {
            objective = objective, place = place or places[1], distance = distance, sourceText = sourceText, isCrafted = isCrafted,
            zones = zones and #zones > 0 and zones or nil, itemId = target and target.itemId or nil, stillNeeded = stillNeeded,
        }
    end
    return details
end

---What can be done about an objective the database puts nowhere on the map: for an item, what waits in the bank,
---what the Auction House asks (with Auctionator) and where it comes from when that is known; for a crafted item, how
---it is made. Without any of these it says why the mark is missing. The quest's own words are on hover.
---@return string text Lines, under the objective
function QuestPage.composeWaysToGet(detail)
    if detail.isCrafted then
        return detail.sourceText or ""
    end
    local ways = {}
    local itemId = detail.objective.type == "item" and detail.itemId or nil
    if itemId then
        local inBank = ns.Crafting.getBankCount(itemId)
        if inBank > 0 then
            ways[#ways + 1] = ns.L("%d in your bank", inBank)
        end
        local toGet = math.max((detail.stillNeeded or 1) - inBank, 0)
        local price = toGet > 0 and ns.Prices.getAuctionPrice(itemId)
        if price then
            ways[#ways + 1] = toGet > 1 and ns.L("about %s for %d at the Auction House", ns.Widgets.formatMoney(price * toGet), toGet)
                or ns.L("about %s at the Auction House", ns.Widgets.formatMoney(price))
        end
    end
    if detail.sourceText then
        ways[#ways + 1] = detail.sourceText
    end
    local lines = { ns.L("Not on the map: the quest database does not say where") }
    if #ways > 0 then
        lines[1] = ns.L("Not on the map. Ways to get it:")
        for _, way in ipairs(ways) do
            lines[#lines + 1] = "- " .. way
        end
    end
    lines[#lines + 1] = "|cff8a7350" .. ns.L("Point at it for what the quest says") .. "|r"
    return table.concat(lines, "\n")
end

---The game's tooltip over an objective with no place: what the quest itself says, in the player's language when a
---translation addon gives it, and why there is no mark.
function QuestPage.showQuestWords(button, data)
    local english = ns.Database.getQuestField(data.questId, "objectivesText")
    english = type(english) == "table" and table.concat(english, " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or nil
    local words = english and english ~= "" and ns.QuestText.getObjectives(data.questId, english) or nil
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(data.title or "", 1, 1, 1)
    if words then
        GameTooltip:AddLine(ns.L("The quest says"), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(words, 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(ns.L("The quest says nothing about where"), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(ns.L("Its place is not in the quest database, so it has no mark on the map."), 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

local function showItemTooltip(button, item)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if item.link and item.link:find("|H", 1, true) then
        GameTooltip:SetHyperlink(item.link)
    elseif item.itemId and GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(item.itemId)
    else
        GameTooltip:AddLine(item.name or ns.L("Quest item"), 1, 1, 1)
    end
    GameTooltip:Show()
end

---The quest's usable item: its picture, name and how many are left. It is used from the button beside the
---tracker or from the bags; a button here could not follow the page as it scrolls during combat.
---@return number y Below the block, unchanged when the quest has no item
local function addQuestItem(y, entry)
    local item = entry.item
    if not item then
        return y
    end
    local width = State.detail.width - 2 * PADDING
    State.detail:addRect(PADDING, y, width, 54, COLORS.softInk)
    State.detail:addRect(PADDING + 1, y + 1, width - 2, 52, PAPER_FILL, 1)
    State.detail:addIcon(PADDING + 9, y + 11, 32, item.texture or ITEM_ICON)
    State.detail:addText(ns.L("QUEST ITEM"), PADDING + 50, y + 7, { font = "GameFontNormalSmall", color = COLORS.softInk, isSingleLine = true })
    State.detail:addText(item.name or ns.L("Quest item"), PADDING + 50, y + 21, { font = "QuestFont", color = COLORS.ink, width = width - 58, isSingleLine = true })
    local note = (item.count and (ns.Lp(item.count, "%d left", "%d left") .. DOT) or "") .. ns.L("use from the tracker")
    State.detail:addText(note, PADDING + 50, y + 37, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width - 58, isSingleLine = true })
    State.detail:addButton(PADDING, y, width, 54, nil, item, showItemTooltip)
    return y + 54 + 16
end

local function toggleChain()
    State.isChainExpanded = not State.isChainExpanded
    Log.refresh()
end

local TO_DO_LEAD = 26 -- the checkbox or turn-in mark in front of each line
local CHECKBOX_SIZE = 22
-- Forever's own checkbox, as its professions window has it: a small dark square with a fine rim, a gold tick
local CHECKBOX_IMAGE, CHECKBOX_TICK = { atlas = "checkbox-minimal" }, { atlas = "checkmark-minimal" }

---One step of a chain on its own line: a checkbox, ticked once done, or an arrow at this quest; and its name.
---@return number y Below the step
local function addChainStep(y, chainQuestId, state, isNameShared)
    local level = ns.Database.getQuestField(chainQuestId, "questLevel") or 0
    local name = ns.QuestText.getQuestName(chainQuestId) or ("Quest " .. chainQuestId)
    local textLeft = PADDING + TO_DO_LEAD
    local text = string.format("[%d] %s", level, name)
    -- One step of the chain that is several done back to back says so
    local stepCount, firstQuestId = 1, chainQuestId
    while ns.Availability.getInstantStepBefore(firstQuestId) and stepCount < 10 do
        firstQuestId, stepCount = ns.Availability.getInstantStepBefore(firstQuestId), stepCount + 1
    end
    if stepCount > 1 then
        text = text .. "  |cff7a6a4a(" .. ns.Lp(stepCount, "%d step, back to back", "%d steps, back to back") .. ")|r"
    end
    if state == "current" then
        -- Part of the same line, so it sits on the name's baseline however the name wraps
        text = text .. "  |cff7a4f00(" .. ns.L("this quest") .. ")|r"
    end
    local textHeight = State.detail:addText(text, textLeft, y, {
        font = "QuestFont", color = state == "current" and COLORS.ink or COLORS.softInk, width = State.detail.width - PADDING - textLeft,
    })
    -- Steps of one name (Test of Lore's six) are told apart by what each asks, its first sentence
    local objectivesText = isNameShared and ns.Database.getQuestField(chainQuestId, "objectivesText")
    -- In the player's language when a translation addon has it, as the step's title above it
    local asks = type(objectivesText) == "table" and ns.QuestText.getObjectives(chainQuestId, table.concat(objectivesText, " "))
    local firstSentence = asks and (asks:match("^%s*(.-[%.!?])%s") or asks)
    if firstSentence and firstSentence:match("%S") then
        textHeight = textHeight + 2 + State.detail:addText(firstSentence, textLeft, y + textHeight + 2, {
            font = "GameFontHighlightSmall", color = COLORS.softInk, width = State.detail.width - PADDING - textLeft,
        })
    end
    -- The To do list's checkbox: ticked for a quest done, empty for one to come; this quest gets a gold arrow
    if state == "current" then
        State.detail:addIcon(PADDING + 3, y + 1, 14, MEDIA .. "ChevronRight", COLORS.gold)
    else
        State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_IMAGE)
        if state == "done" then
            State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_TICK, nil, 1)
        end
    end
    return y + math.max(textHeight + 8, 24)
end

---A folded end of a long chain, "3 quests before" or "2 more quests", that opens the whole chain; with the
---chain open, "Show less" folds it again.
---@return number y Below the fold
local function addChainFold(y, text, isOpen)
    -- A line of the chain like the others: the game's +/- in the checkbox column, the words in soft ink
    State.detail:addIcon(PADDING + 1, y, 16, isOpen and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    local height = State.detail:addText(text, PADDING + TO_DO_LEAD, y, { font = "QuestFont", color = COLORS.softInk, isSingleLine = true })
    State.detail:addButton(PADDING - 4, y - 3, State.detail.width - 2 * PADDING + 8, height + 6, toggleChain)
    return y + math.max(height + 8, 24)
end

---The chain from top to bottom: done, this quest, still to come. A long chain shows this quest and the next
---and folds the rest into "n done" and "n more", which open the whole chain.
---@return number y Below the chain, unchanged when the quest is not in one
---@param isUnderFold boolean? The chain sits under a fold that already names it, so it needs no heading
local function addChain(y, questId, isUnderFold)
    local questIds = ns.Chain.getQuestIds(questId)
    if #questIds < 2 then
        return y
    end
    local index, total = ns.Chain.getStep(questId)
    if not isUnderFold then
        y = addHeading(y, ns.L("Quest chain  %d of %d", index, total))
    end
    -- Done only when the game says so: a quest that is not yet available has earlier steps still to do
    local nameCounts = {}
    for _, chainQuestId in ipairs(questIds) do
        local name = ns.Database.getQuestField(chainQuestId, "name") or ""
        nameCounts[name] = (nameCounts[name] or 0) + 1
    end
    local function isNameShared(chainQuestId)
        return (nameCounts[ns.Database.getQuestField(chainQuestId, "name") or ""] or 0) > 1
    end
    local function getState(position)
        if position == index then
            return "current"
        end
        return ns.QuestState.isTurnedIn(questIds[position]) and "done" or "upcoming"
    end

    if total > MAX_OPEN_CHAIN and not State.isChainExpanded then
        if index > 1 then
            y = addChainFold(y, ns.Lp(index - 1, "%d quest before", "%d quests before"))
        end
        y = addChainStep(y, questIds[index], "current", isNameShared(questIds[index]))
        if index < total then
            y = addChainStep(y, questIds[index + 1], "upcoming", isNameShared(questIds[index + 1]))
        end
        if total - index > 1 then
            y = addChainFold(y, ns.Lp(total - index - 1, "%d more quest", "%d more quests"))
        end
        return y + 12
    end

    for position, chainQuestId in ipairs(questIds) do
        y = addChainStep(y, chainQuestId, getState(position), isNameShared(chainQuestId))
    end
    if total > MAX_OPEN_CHAIN then
        y = addChainFold(y, ns.L("Show less"), true)
    end
    return y + 12
end

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

---Sets a texture to one of the game's own pieces of art, when this client has it.
---@return boolean isSet
local function setAtlasIfKnown(texture, atlas)
    if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        ns.Widgets.setAtlas(texture, atlas)
        return true
    end
    return false
end

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
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

---Fills the pinned "Rewards" block for a quest, or takes it away. Everything sits in one strip: the
---experience and money as amounts, the items as icons, the ones to choose between set apart. However much a
---quest gives, the block stays small; a strip too long for one row runs on into the next. The game sends
---the details of a quest that is not in the log only when asked, so the first look may say it is still asking.
---@param questId number|table|nil The quest whose rewards to show; or rewards already added up (experience, money,
---items, choices, isLoading), for a page about several quests; nil hides the block
---@return number extraHeight What the page adds to its scrolling for the rest of the block to rise into view
local function setPageRewards(questId)
    if not State.rewardsBlock then
        return 0
    end
    State.rewardsBlock.title:SetText(ns.L("Rewards"))
    -- A page about several quests (a dungeon's run) gives their rewards added up, in the same shape
    local rewards = type(questId) == "table" and questId or (questId and ns.QuestState.getRewards(questId))
    local hasRewards = rewards and (rewards.money > 0 or rewards.experience > 0 or #rewards.items > 0 or #rewards.choices > 0)
    local height, iconCount, textCount = 0, 0, 0
    if rewards and (hasRewards or rewards.isLoading) then
        local left, right = 12, PAGE_CONTENT_WIDTH - 12
        local x, y = left, State.rewardsBlock.topHeight + 6
        local function place(region, width)
            if x + width > right and x > left then
                x, y = left, y + REWARD_ICON_SIZE + REWARD_GAP
            end
            region:ClearAllPoints()
            region:SetPoint("LEFT", State.rewardsBlock, "TOPLEFT", x, -(y + REWARD_ICON_SIZE / 2))
            region:Show()
            x = x + width + REWARD_GAP
        end
        local function addIcon(texture, item, count, tooltipText)
            iconCount = iconCount + 1
            local button = acquireRewardIcon(iconCount)
            button.icon:SetTexture(texture)
            button.count:SetText(count and count > 1 and count or "")
            button.item, button.tooltipText = item, tooltipText
            place(button, REWARD_ICON_SIZE)
        end
        local function addText(content, isLabel)
            textCount = textCount + 1
            local text = acquireRewardText(textCount)
            text:SetText(content)
            if isLabel then
                text:SetTextColor(REWARD_LABEL_COLOR[1], REWARD_LABEL_COLOR[2], REWARD_LABEL_COLOR[3])
            else
                text:SetTextColor(1, 1, 1)
            end
            local width = text:GetStringWidth()
            place(text, type(width) == "number" and width or (#content * 7))
        end
        if not hasRewards then
            addText(ns.L("Asking the game for this quest's rewards..."), true)
        end
        if rewards.experience > 0 then
            addIcon(XP_ICON, nil, nil, ns.L("Experience"))
            addText(BreakUpLargeNumbers and BreakUpLargeNumbers(rewards.experience) or tostring(rewards.experience))
            x = x + 4
        end
        if rewards.money > 0 then
            -- As the game shows it: the pile of coins, then the amount
            addIcon(MONEY_ICON, nil, nil, ns.L("Money"))
            addText(ns.Widgets.formatMoney(rewards.money))
            x = x + 4
        end
        for _, item in ipairs(rewards.items) do
            addIcon(item.texture, item, item.count)
        end
        if #rewards.choices > 0 then
            x = x + 4
            addText(ns.L(x > left + 4 and "or one of" or "Choose one"), true)
            for _, item in ipairs(rewards.choices) do
                addIcon(item.texture, item, item.count)
            end
        end
        height = y + REWARD_ICON_SIZE + State.rewardsBlock.bottomHeight
    end
    -- Only the first row shows until the page is scrolled to its end; further rows rise then
    local peekHeight = math.min(height, State.rewardsBlock.topHeight + 6 + REWARD_ICON_SIZE + State.rewardsBlock.bottomHeight)
    State.rewardsBlock.fullHeight, State.rewardsBlock.peekHeight = height, peekHeight
    State.rewardsBlock:SetHeight(math.max(peekHeight, 1))
    for index = iconCount + 1, #State.rewardsBlock.icons do
        State.rewardsBlock.icons[index]:Hide()
    end
    for index = textCount + 1, #State.rewardsBlock.texts do
        State.rewardsBlock.texts[index]:Hide()
    end
    State.rewardsBlock:SetShown(height > 0)
    State.detail.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", State.frame.pageLeft or LIST_WIDTH + 2, BAR_HEIGHT + 2 + peekHeight)
    return height - peekHeight
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


---One line of text in a quest page's lists: plain text; or text after a coloured dot (a creature, in the colour of
---its spawn points on the map); or text with a place name in it to click, underlined as links are.
---@param line string|{ text: string?, dotColor: number[]?, link: string?, afterText: string?, handleClick: function?, data: any?, font: string?, color: number[]? }
---@return number height
local function addStepLine(y, line, textLeft, textWidth)
    local options = { font = type(line) == "table" and line.font or "QuestFont", color = type(line) == "table" and line.color or COLORS.softInk, width = textWidth }
    if type(line) == "string" then
        return (State.detail:addText(line, textLeft, y, options))
    end
    local spaceBefore = line.spaceBefore or 0
    y = y + spaceBefore
    local left = textLeft + (line.indent or 0)
    if line.dotColor then
        -- A small square centred on the first line of text, in proportion to the font: the spawn points' squares
        -- on the map, in the same colour, so a line here and its places there match
        local fontObject = ns.Widgets.getFont(options.font)
        local fontSize
        if fontObject and fontObject.GetFont then
            _, fontSize = fontObject:GetFont()
        end
        fontSize = type(fontSize) == "number" and fontSize or 12
        local dotSize = math.floor(fontSize * 0.45 + 0.5)
        local top = y + math.floor((fontSize - dotSize) / 2 + 0.5)
        State.detail:addRect(left, top - 1, dotSize + 2, dotSize + 2, COLORS.ink, 2)
        State.detail:addRect(left + 1, top, dotSize, dotSize, line.dotColor, 3)
        left = left + dotSize + 8
    end
    local height, width = 0, 0
    if line.text then
        options.width = textWidth - (left - textLeft)
        height, width = State.detail:addText(line.text, left, y, options)
    end
    if line.link then
        local right = textLeft + textWidth
        -- The link follows the text on its last line, or starts a line of its own when it does not fit there
        local linkLeft, linkTop = left + (line.text and width + 4 or 0), y
        local linkHeight, linkWidth, linkText = State.detail:addText(line.link, linkLeft, linkTop, { font = options.font, color = COLORS.brown, isSingleLine = true })
        if line.text and (height > linkHeight * 1.5 or linkLeft + linkWidth > right) then
            linkLeft, linkTop = left, y + height + 1
            linkText:ClearAllPoints()
            linkText:SetPoint("TOPLEFT", State.detail.content, "TOPLEFT", linkLeft, -linkTop)
        end
        if not line.isQuiet then
            State.detail:addRect(linkLeft, linkTop + linkHeight, linkWidth, 1, COLORS.brown, 1) -- a place: underlined, as links are
        end
        State.detail:addButton(linkLeft - 3, linkTop - 2, linkWidth + 6, linkHeight + 5, line.handleClick, line.data)
        local bottom = linkTop + linkHeight + 1
        if line.afterText then
            -- After the link on its line, or on the next line when it does not fit
            local afterLeft, afterTop = linkLeft + linkWidth + 3, linkTop
            local afterHeight, afterWidth, afterText = State.detail:addText(line.afterText, afterLeft, afterTop, { font = options.font, color = options.color, isSingleLine = true })
            if afterLeft + afterWidth > right then
                afterLeft, afterTop = left, bottom + 1
                afterText:ClearAllPoints()
                afterText:SetPoint("TOPLEFT", State.detail.content, "TOPLEFT", afterLeft, -afterTop)
                afterText:SetWidth(right - afterLeft)
                afterText:SetWordWrap(true)
                local wrappedHeight = afterText:GetStringHeight()
                afterHeight = type(wrappedHeight) == "number" and wrappedHeight or afterHeight
            end
            bottom = math.max(bottom, afterTop + afterHeight)
        end
        height = math.max(height, bottom - y)
    end
    return height + spaceBefore
end

local function showZonesTooltip(button, entry)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    ns.MapDock.addZonesToTooltip(GameTooltip, entry)
    GameTooltip:Show()
end

---The tooltip follows the click: the arrow moves to the zone now on the map. Turning the map draws the page
---again, which gives the quest a fresh entry, so the quest is known by its number; and once more on the next
---frame, after that drawing.
local function handleZonesClick(entry)
    local questId = entry.questId
    ns.MapDock.showNextQuestZone(entry)
    local function refreshTooltip()
        local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
        if owner and type(owner.data) == "table" and owner.data.questId == questId then
            showZonesTooltip(owner, owner.data)
        end
    end
    refreshTooltip()
    if C_Timer then
        C_Timer.After(0, refreshTooltip)
    end
end

local dropFolds = {} -- [fold key] = true while a folded part of a drop list is open

local function toggleDropFold(key)
    dropFolds[key] = not dropFolds[key] or nil
    Log.refresh()
end

---@return table? place Where to look first in one of an item's zones: its nearest place there with a known spot
local function getDropZonePlace(zone)
    local _, _, place = ns.Geometry.getNearest(zone.places, ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
    if place then
        return place
    end
    for _, zonePlace in ipairs(zone.places) do
        if zonePlace.x >= 0 then
            return zonePlace
        end
    end
    return zone.places[1]
end

local MAX_OPEN_DROP_ZONES = 4 -- zones listed before the rest fold away
local MAX_ZONE_CREATURES = 2 -- creatures listed in a zone before "+ N more here"

---Where an item drops, as lines for addStepLine. In one zone: each creature with its chance behind a dot in
---the colour of its spawn points on the map, then the zone to click. In several: zone by zone, in the order
---worth going (Drops.getZones), each zone a link with its levels, its likeliest creatures under it; the
---rest of the zones, and the zones for much higher levels, folded into a line each.
---@param zones DropZone[]
---@param foldKey string Names this list's folds, so each quest's stay as left
---@param options { handleClick: function, quest: table?, questId: number?, objectiveShade: number?, isByCreature: boolean? }
---@return table[] lines
local function composeDropZoneLines(zones, foldKey, options)
    local lines = {}
    local isByCreature = options.isByCreature ~= false
    local function getDotColor(source)
        return ns.MapMarks.getShadeColor(isByCreature and source.shade or options.objectiveShade, options.questId or (options.quest and options.quest.questId))
    end
    local function getClickData(zone)
        return { zone = zone, place = getDropZonePlace(zone), quest = options.quest, questId = options.questId }
    end
    local function formatSource(source)
        return source.name .. (source.chance and (DOT .. ns.Drops.formatChance(source.chance)) or "")
    end
    local function addCreatures(zone, indent, firstPrefix)
        local zoneKey = foldKey .. ":" .. zone.zoneId
        local isOpen = dropFolds[zoneKey]
        for index, source in ipairs(zone.sources) do
            if index > MAX_ZONE_CREATURES and not isOpen then
                lines[#lines + 1] = { link = ns.Lp(#zone.sources - MAX_ZONE_CREATURES, "+ %d more here", "+ %d more here"), handleClick = toggleDropFold, data = zoneKey, indent = indent + 14, isQuiet = true }
                return
            end
            -- The first creature after its lead ("Drops from %s"), the next ones after "or"
            local text = firstPrefix and ns.L(index == 1 and firstPrefix or "or %s", formatSource(source)) or formatSource(source)
            lines[#lines + 1] = { text = text, dotColor = getDotColor(source), indent = indent }
        end
        if isOpen then
            lines[#lines + 1] = { link = ns.L("Show fewer"), handleClick = toggleDropFold, data = zoneKey, indent = indent + 14, isQuiet = true }
        end
    end

    if #zones == 1 then
        local zone = zones[1]
        addCreatures(zone, 0, "Drops from %s")
        local data = getClickData(zone)
        local place = data.place
        lines[#lines + 1] = {
            text = place and place.dungeonName and ns.L("Inside %s, entrance in", place.dungeonName) or ns.L("in"),
            link = zone.name .. (place and place.x >= 0 and string.format(" %d, %d", place.x, place.y) or ""), handleClick = options.handleClick, data = data,
        }
        return lines
    end

    local creatureNames, creatureCount = {}, 0
    for _, zone in ipairs(zones) do
        for _, source in ipairs(zone.sources) do
            if not creatureNames[source.name] then
                creatureNames[source.name], creatureCount = true, creatureCount + 1
            end
        end
    end
    lines[1] = { text = ns.Lp(creatureCount, "Drops from %d creature in %d zones", "Drops from %d creatures in %d zones", #zones) }
    local shownZoneId = ns.MapDock.getShownZoneId()
    local function addZone(zone)
        local facts = {}
        if zone.minLevel then
            facts[#facts + 1] = zone.minLevel == zone.maxLevel and ns.L("level %d", zone.minLevel) or ns.L("levels %d-%d", zone.minLevel, zone.maxLevel)
        end
        if zone.isPlayerZone then
            facts[#facts + 1] = ns.L("you are here")
        elseif zone.zoneId == shownZoneId then
            facts[#facts + 1] = ns.L("on the map")
        elseif zone.isDungeon then
            facts[#facts + 1] = ns.L("dungeon")
        end
        lines[#lines + 1] = {
            link = zone.name, afterText = #facts > 0 and (DOT:gsub("^ ", "") .. table.concat(facts, DOT)) or nil,
            handleClick = options.handleClick, data = getClickData(zone), spaceBefore = 5,
        }
        addCreatures(zone, 10)
    end
    local fittingZones, highZones = {}, {}
    for _, zone in ipairs(zones) do
        table.insert(zone.isTooHigh and highZones or fittingZones, zone)
    end
    local moreKey, highKey = foldKey .. ":more", foldKey .. ":high"
    for index, zone in ipairs(fittingZones) do
        if index > MAX_OPEN_DROP_ZONES and not dropFolds[moreKey] then
            local names = {}
            for restIndex = index, #fittingZones do
                names[#names + 1] = fittingZones[restIndex].name
            end
            local count = #fittingZones - MAX_OPEN_DROP_ZONES
            lines[#lines + 1] = { link = ns.Lp(count, "+ %d more zone", "+ %d more zones"), afterText = table.concat(names, ", "), handleClick = toggleDropFold, data = moreKey, isQuiet = true, spaceBefore = 5 }
            break
        end
        addZone(zone)
    end
    if dropFolds[moreKey] then
        lines[#lines + 1] = { link = ns.L("Show fewer zones"), handleClick = toggleDropFold, data = moreKey, isQuiet = true, spaceBefore = 5 }
    end
    if #highZones > 0 then
        if dropFolds[highKey] then
            for _, zone in ipairs(highZones) do
                addZone(zone)
            end
            lines[#lines + 1] = { link = ns.L("Hide zones for higher levels"), handleClick = toggleDropFold, data = highKey, isQuiet = true, spaceBefore = 5 }
        else
            local lowest = highZones[1].minLevel
            lines[#lines + 1] = {
                link = ns.Lp(#highZones, "+ %d zone for higher levels", "+ %d zones for higher levels"),
                afterText = lowest and ns.L("(levels %d+)", lowest) or nil, handleClick = toggleDropFold, data = highKey, isQuiet = true, spaceBefore = 3,
            }
        end
    end
    return lines
end

---Turns the map to where a quest's starting item drops, keeping the quest selected, so the map shows each
---creature's spawn points in its colour there.
---@param target { zone: DropZone, place: table?, quest: table }
local function showDropZone(target)
    local zoneId = target.zone.zoneId
    State.isMapFollowPaused = true -- the list moves to the zone itself, without letting go of the quest
    ns.MapDock.showQuestPlace(zoneId, target.place)
    State.isMapFollowPaused = false
    State.pickedZoneId = zoneId ~= ns.Model.getPlayer().zoneId and zoneId or nil
    selectedQuestIds[TAB_AVAILABLE] = target.quest.questId
    State.scrollTargetQuestId = target.quest.questId
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---Turns the map to where an objective is done, the place in the middle when the map is zoomed in, and
---remembers the zone: the map returns there whenever the quest is chosen later.
---@param target { questId: number, place: table?, zone: DropZone? }
local function showObjectivePlace(target)
    local place = target.place
    local zoneId = target.zone and target.zone.zoneId or place and (place.mapZoneId or place.groupZoneId)
    if not zoneId then
        return
    end
    ns.settings.cycledQuestZones[target.questId] = zoneId
    ns.MapDock.showQuestPlace(place and (place.mapZoneId or place.groupZoneId) or zoneId, place)
end

---What is left to do, counts first, each line with where it is done, ending with the turn-in.
---@return number y Below the list
local function addToDo(y, entry, details)
    y = addHeading(y, ns.L("To do"))
    local textLeft, textWidth = PADDING + TO_DO_LEAD, State.detail.width - 2 * PADDING - TO_DO_LEAD
    ---@param where string|table? Under the line: a text, or a line for addStepLine, such as a place to click
    local function addLine(text, color, where)
        local height = State.detail:addText(text, textLeft, y, { font = "QuestFont", color = color, width = textWidth })
        y = y + height + 2
        if type(where) == "table" then
            where.font = "GameFontHighlightSmall"
            y = y + addStepLine(y, where, textLeft, textWidth) + 2
        elseif where and where ~= "" then
            local whereHeight = State.detail:addText(where, textLeft, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = textWidth })
            y = y + whereHeight + 2
        end
        y = y + 6
    end
    -- Kills for a dropped item: a bar the kills fill, a gold line where an average player would be for the drops
    -- got, and a faint part for what is still to come
    local function addKillBar(progress)
        local earlierKills = progress.earlierKills or 0
        local total = earlierKills + math.max(progress.expected, progress.kills) + progress.remaining
        if total <= 0 then
            return
        end
        local top, height = y - 4, 13
        local isUnlucky = progress.isUnlucky
        -- Drops collected before counting began: a muted start, as long as their kills would be on average; then
        -- the kills, and the kills still to go
        local innerLeft, innerTop, inner, innerHeight = State.detail:addStatBar(textLeft, top, textWidth, height, {
            { share = earlierKills / total, color = { 0.62, 0.55, 0.4 } },
            { share = progress.kills / total, color = isUnlucky and { 0.75, 0.25, 0.16 } or { 0.25, 0.62, 0.25 } },
            { share = progress.remaining / total, color = { 0.42, 0.36, 0.25 } },
        })
        if (progress.drops or 0) > 0 then
            -- Where an average player would be for the drops got
            local mark = State.detail:addImage(innerLeft + inner * (earlierKills + progress.expected) / total - 1, innerTop - 2, 2, innerHeight + 4, "Interface\\Buttons\\WHITE8X8", nil, nil, 3)
            mark:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        end
        local parts = { ns.KillCounter.formatKills(progress, DOT) }
        if (progress.earlierDrops or 0) > 0 then
            parts[#parts + 1] = ns.Lp(progress.earlierDrops, "%d collected earlier", "%d collected earlier")
        end
        if (progress.sharerCount or 1) > 1 then
            -- The drops go round between those who need them: the kills to go are for a turn of theirs each
            parts[#parts + 1] = ns.L("loot shared by %d", progress.sharerCount)
        end
        local textColor = isUnlucky and COLORS.warning or COLORS.softInk
        if progress.remaining >= 0.5 then
            parts[#parts + 1] = ns.Profit.formatEstimateSign(textColor) .. " " .. ns.Lp(math.floor(progress.remaining + 0.5), "%d kill to go", "%d kills to go")
        end
        local text = table.concat(parts, DOT)
        local textHeight = State.detail:addText(text, textLeft, top + height + 2, { font = "GameFontHighlightSmall", color = textColor, width = textWidth })
        y = top + height + 4 + (type(textHeight) == "number" and textHeight or 12) + 2
    end
    -- An item that drops: each creature with its chance, behind a dot in the colour of its spawn points on the
    -- map, then the place, to click to turn the map there
    local shades, _, sourceObjectiveIndex = ns.MapMarks.getObjectiveShades(entry)
    local function addSourceLines(objectiveIndex, objectiveDetail)
        local lines = composeDropZoneLines(objectiveDetail.zones, "log:" .. entry.questId .. ":" .. objectiveIndex, {
            handleClick = showObjectivePlace, questId = entry.questId,
            isByCreature = objectiveIndex == sourceObjectiveIndex, objectiveShade = shades[objectiveIndex],
        })
        for _, line in ipairs(lines) do
            line.font = "GameFontHighlightSmall"
            y = y + addStepLine(y, line, textLeft, textWidth) + 3
        end
        y = y + 6
    end
    -- Done objectives left out as the tracker leaves them out, when the player chose that: the page and the tracker
    -- list the same steps. Each keeps its own number, which its colour on the map goes by.
    local shownIndexes = {}
    for index, objectiveDetail in ipairs(entry.isTurnIn and {} or details) do
        if not (ns.settings.shouldHideDoneObjectives and objectiveDetail.objective.isFinished) then
            shownIndexes[#shownIndexes + 1] = index
        end
    end
    for _, objectiveIndex in ipairs(shownIndexes) do
        local objectiveDetail = details[objectiveIndex]
        local objective = objectiveDetail.objective
        local color = objective.isFinished and COLORS.softInk or COLORS.ink
        -- The game's own checkbox, ticked in gold once the objective is done
        State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_IMAGE)
        if objective.isFinished then
            State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_TICK, nil, 1)
        end
        local whereText, unplacedObjective
        local hasSourceLines = not objective.isFinished and objectiveDetail.zones ~= nil
        if not objective.isFinished and not hasSourceLines then
            -- Not an item that drops (those list their creatures by zone): what it is and where
            local place = objectiveDetail.place
            if place then
                local sourceText = objectiveDetail.sourceText
                whereText = composePlaceLine(place, {
                    prefix = sourceText and (sourceText .. DOT:gsub(" $", "")) or nil,
                    handleClick = showObjectivePlace, data = { questId = entry.questId, place = place },
                })
            else
                -- Nothing to mark on the map: what can be done instead, and the quest's own words on hover
                whereText = QuestPage.composeWaysToGet(objectiveDetail)
                unplacedObjective = objectiveDetail
            end
        end
        -- A count reads inside the line, as the game writes it: "4/10 Syndicate Footpad slain"
        local label = (objective.shownLabel or objective.label)
        if objective.required > 1 then
            local count = objective.fulfilled .. "/" .. objective.required
            label = objective.isFinished and (count .. " " .. label) or ("|cff6a3d00" .. count .. "|r " .. label)
        end
        if hasSourceLines then
            local height = State.detail:addText(label, textLeft, y, { font = "QuestFont", color = color, width = textWidth })
            y = y + height + 2
            addSourceLines(objectiveIndex, objectiveDetail)
        else
            local top = y
            addLine(label, color, whereText)
            if unplacedObjective then
                -- Pointed at, the objective shows what the quest itself says, as the game's tooltip
                State.detail:addButton(textLeft - TO_DO_LEAD, top - 2, textWidth + TO_DO_LEAD, math.max(y - top - 4, 14), nil,
                    { questId = entry.questId, title = entry.title, label = objective.label }, QuestPage.showQuestWords)
            end
        end
        local progress = ns.settings.shouldCountKills and not objective.isFinished and objective.type == "item"
            and ns.KillCounter.getProgress(entry.questId, objectiveIndex, objective)
        if progress then
            addKillBar(progress)
        end
    end
    if entry.eventText and not entry.isTurnIn then
        -- No objectives: what the quest asks (waiting, talking) is the one thing to do, at its NPC
        State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_IMAGE)
        local _, _, eventPlace = ns.Geometry.getNearest(ns.Location.getFinisherPlaces(entry.questId), ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
        local happensAt = entry.finisherName and ns.L("Happens at %s", entry.finisherName) or ns.L("Happens at the quest giver")
        addLine(entry.eventText, COLORS.ink, eventPlace and composePlaceLine(eventPlace, { prefix = happensAt .. "," }) or happensAt)
    end
    -- The turn-in closes the list: the last thing to do, or the only one left
    local finisherPlaces = ns.Location.getFinisherPlaces(entry.questId)
    local _, _, finisherPlace = ns.Geometry.getNearest(finisherPlaces, ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
    finisherPlace = finisherPlace or finisherPlaces[1]
    -- The map's turn-in mark: the game's "?", grey until the quest is ready, as the map shows it then
    State.detail:addMark(PADDING - 1, y - 1, 18, { kind = "turnIn", questId = entry.questId, isFocused = false, lines = {}, isPending = not entry.isTurnIn })
    addLine(entry.finisherName and ns.L("Turn in to %s", entry.finisherName) or ns.L("Turn in to the quest giver"), entry.isTurnIn and COLORS.darkGreen or COLORS.ink,
        finisherPlace and composePlaceLine(finisherPlace) or nil)
    -- Ready to hand in: what the drops took, each counted objective's item with its bar and kills against the
    -- kills an average player would have needed
    for objectiveIndex, objective in ipairs(entry.isTurnIn and ns.settings.shouldCountKills and entry.objectives or {}) do
        local progress = objective.type == "item" and ns.KillCounter.getProgress(entry.questId, objectiveIndex, objective)
        if progress and progress.kills > 0 then
            y = y + 2 + State.detail:addText((objective.shownLabel or objective.label), textLeft, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = textWidth, isSingleLine = true })
            y = y + 4
            addKillBar(progress)
        end
    end
    if entry.otherZonesText then
        local top = y
        y = addBody(y, ns.Widgets.formatMoreZones(entry.otherZonesText, "6a3d00"), COLORS.softInk)
        if entry.zoneIds then
            -- Under the mouse, every zone; a click turns the map to the next of them
            State.detail:addButton(PADDING - 4, top - 2, State.detail.width - 2 * PADDING + 8, y - top, handleZonesClick, entry, showZonesTooltip)
        end
    end
    return y + 10
end

local toggledFolds = {} -- [fold name] = the quest whose fold was switched from its usual state; another quest starts as usual

local function toggleFold(fold)
    toggledFolds[fold.name] = toggledFolds[fold.name] ~= fold.questId and fold.questId or nil
    Log.refresh()
end

---A part of the page that can be folded away: a ruled row with a chevron, a title and a short note.
---@param isOpenByDefault boolean Whether the part starts open
---@param showHelp fun(button: table)? Fills a tooltip that explains the part; it gets a "?" after the title
---@return number y Below the row
---@return boolean isOpen Whether the part's content should follow
local function addFold(y, name, questId, title, noteText, isOpenByDefault, showHelp)
    local width = State.detail.width - 2 * PADDING
    local isOpen = (toggledFolds[name] == questId) ~= isOpenByDefault
    local fold = { name = name, questId = questId }
    -- An engraved rule, as on the game's parchment: a brown line with a pale one under it
    State.detail:addRect(PADDING, y, width, 1, { 0.42, 0.29, 0.14, 0.75 })
    State.detail:addRect(PADDING, y + 1, width, 1, { 1, 0.95, 0.8, 0.45 })
    State.detail:addIcon(PADDING, y + 9, 11, MEDIA .. (isOpen and "ChevronDown" or "ChevronRight"), COLORS.softInk)
    local _, titleWidth = State.detail:addText(title, PADDING + 17, y + 6, { font = "QuestFont_Large", color = COLORS.ink, isSingleLine = true })
    if noteText then
        State.detail:addText(noteText, PADDING + width - 90, y + 9, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = 90, justify = "RIGHT", isSingleLine = true })
    end
    if not showHelp then
        State.detail:addButton(PADDING - 4, y + 1, width + 8, 28, toggleFold, fold)
        return y + 32, isOpen
    end
    -- The help mark has the row to itself where it stands; the rest of the row still folds
    local helpLeft = PADDING + 17 + titleWidth + 7
    -- The game's own gold "i" in its rim (its announcements'), level with the title
    State.detail:addIcon(helpLeft, y + 6, 18, { atlas = "glueannouncementpopup-icon-info" })
    State.detail:addButton(PADDING - 4, y + 1, helpLeft - PADDING + 2, 28, toggleFold, fold)
    State.detail:addButton(helpLeft - 2, y + 4, 19, 22, nil, nil, showHelp)
    State.detail:addButton(helpLeft + 19, y + 1, PADDING + width + 4 - helpLeft - 19, 28, toggleFold, fold)
    return y + 32, isOpen
end

local HEADER_FILL, HEADER_EDGE = { 0.2, 0.07, 0.05 }, { 0.54, 0.48, 0.29 }
local HEADER_BADGE_FILL, HEADER_BADGE_TEXT = { 0.14, 0.12, 0.08 }, { 0.91, 0.86, 0.75 }

-- State.pageHeader: the bar pinned above the page; created with the window
local BADGE_HEIGHT = 18
local HEADER_FRINGE_SHARE = 9 / 52 -- the lower part of the header art that is a fringe over the page, as in the game's layout
local HEADER_BOTTOM_PADDING = 17 -- room between the facts line and the header art's lower edge
local VOICE_ROW_HEIGHT = 26 -- the narration's buttons under the facts, with the gap above them

---The page's header in the look of the game's window titles: a dark red bar with the quest's name in gold,
---a line of facts under it, and for a quest in a chain the tracker's badge with its step. It is pinned
---above the scrolling page and spans it edge to edge, scroll bar included.
---@param title string? nil takes the header away, and the page starts at the top again
---@param zoneLink { before: string, text: string, handleClick: function, data: any }? A zone in the facts line to
---click, to turn the map there: `before` is the facts' text ahead of it
---@param questId number? The quest the page is about: shift-clicking its title links it in chat
local function setPageHeader(title, factsText, chainIndex, chainTotal, zoneLink, questId)
    if not State.pageHeader then
        return
    end
    State.pageHeader.backButton:Hide() -- shown by Log.setPageHeaderBack, after the header is set
    State.pageHeader.questId = questId
    State.pageHeader.titleButton:SetShown(questId ~= nil)
    local height = 0
    if title then
        State.pageHeader.badge:SetShown(chainIndex ~= nil)
        if chainIndex then
            State.pageHeader.badgeText:SetText(ns.L("%d of %d", chainIndex, chainTotal))
            local textWidth = State.pageHeader.badgeText:GetStringWidth()
            -- Edge, icon, gap, text, edge
            State.pageHeader.badge:SetWidth(12 + 4 + (type(textWidth) == "number" and textWidth or 36))
        end
        State.pageHeader.title:ClearAllPoints()
        State.pageHeader.title:SetPoint("TOPLEFT", State.pageHeader, "TOPLEFT", PADDING, -10)
        State.pageHeader.title:SetPoint("RIGHT", chainIndex and State.pageHeader.badge or State.pageHeader, chainIndex and "LEFT" or "RIGHT", chainIndex and -8 or -PADDING, 0)
        State.pageHeader.title:SetText(title)
        State.pageHeader.facts:SetText(factsText or "")
        -- The zone in the facts, underlined over a button of its own size, as the page's place links are
        local zoneButton = State.pageHeader.zoneButton
        zoneButton:SetShown(zoneLink ~= nil)
        zoneButton.underline:SetShown(zoneLink ~= nil)
        if zoneLink then
            State.pageHeader.measure:SetText(zoneLink.before)
            local beforeWidth = State.pageHeader.measure:GetStringWidth()
            State.pageHeader.measure:SetText(zoneLink.text)
            local linkWidth, lineHeight = State.pageHeader.measure:GetStringWidth(), State.pageHeader.measure:GetStringHeight()
            beforeWidth = type(beforeWidth) == "number" and beforeWidth or 0
            linkWidth = type(linkWidth) == "number" and linkWidth or 60
            lineHeight = type(lineHeight) == "number" and lineHeight or 12
            zoneButton:ClearAllPoints()
            zoneButton:SetPoint("TOPLEFT", State.pageHeader.facts, "TOPLEFT", beforeWidth - 2, 2)
            zoneButton:SetSize(linkWidth + 4, lineHeight + 4)
            zoneButton.underline:ClearAllPoints()
            zoneButton.underline:SetPoint("TOPLEFT", State.pageHeader.facts, "TOPLEFT", beforeWidth, -lineHeight)
            zoneButton.underline:SetSize(linkWidth, 1)
            zoneButton.handleClick, zoneButton.data = zoneLink.handleClick, zoneLink.data
        end
        local titleHeight, factsHeight = State.pageHeader.title:GetStringHeight(), State.pageHeader.facts:GetStringHeight()
        height = 10 + math.max(type(titleHeight) == "number" and titleHeight or 16, BADGE_HEIGHT)
            + 4 + (type(factsHeight) == "number" and factsHeight or 12) + HEADER_BOTTOM_PADDING
        -- A quest a translation addon has narrated: its buttons under the facts, and where the narration is
        local voice = State.pageHeader.voice
        local voiceState, voicePosition = ns.QuestText.getVoiceState(questId)
        voice:SetShown(voiceState ~= nil)
        voice.questId = questId
        if voiceState then
            local _, provider = ns.QuestText.getVoice()
            Log.setButtonText(voice.playButton, ns.L(voiceState == "playing" and "Stop" or "Play"))
            Log.setButtonText(voice.queueButton, ns.L(voiceState == "queued" and "Unqueue" or "Queue"))
            voice.queueButton:SetShown(voiceState ~= "playing")
            voice.text:SetPoint("LEFT", voiceState == "playing" and voice.playButton or voice.queueButton, "RIGHT", 8, 0)
            local stateText = voiceState == "playing" and ns.L("playing now") or voiceState == "paused" and ns.L("paused")
                or voiceState == "queued" and ns.L("number %d in the queue", voicePosition or 1) or nil
            -- Where it is, while it plays or waits; who narrates, while idle (the page is narrow for both)
            voice.text:SetText(stateText or ns.L("Narration by %s", provider and provider.label or "?"))
            height = height + VOICE_ROW_HEIGHT
        end
        State.pageHeader:SetHeight(height)
    end
    State.pageHeader:SetShown(title ~= nil)
    -- The header's art ends in a soft fringe over the page, as the game's own does; the page starts under
    -- that fringe, so its text and the "more above" shade run right up to the header
    local overlap = (title and State.pageHeader.hasArt) and math.floor(height * HEADER_FRINGE_SHARE) or 0
    State.detail.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", State.frame.pageLeft or LIST_WIDTH + 2, -PAGE_TOP - height + overlap)
end

local function createPageHeader(parent, pageLeft)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", pageLeft, -PAGE_TOP)
    header:SetPoint("TOPRIGHT", parent, "TOPLEFT", pageLeft + PAGE_CONTENT_WIDTH, -PAGE_TOP)
    header:SetHeight(50)
    header:SetFrameLevel((parent:GetFrameLevel() or 1) + 35) -- over the page and its "more above" shade
    local fill = header:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(header)
    -- The dark wood the game puts behind the top of its own quest page, when this client has it
    if fill.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("questlog-reward-top-frame") then
        fill:SetAtlas("questlog-reward-top-frame") -- the art has an edge of its own, so no line is drawn under it
        header.hasArt = true
    else
        fill:SetColorTexture(HEADER_FILL[1], HEADER_FILL[2], HEADER_FILL[3], 1)
        local edge = header:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(HEADER_EDGE[1], HEADER_EDGE[2], HEADER_EDGE[3], 1)
        edge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        edge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        edge:SetHeight(2)
    end
    header.title = ns.Widgets.createFontString(header, "OVERLAY", "GameFontNormalLarge")
    header.title:SetJustifyH("LEFT")
    header.title:SetJustifyV("TOP")
    header.title:SetWordWrap(true)
    header.facts = ns.Widgets.createFontString(header, "OVERLAY", "GameFontHighlightSmall")
    header.facts:SetJustifyH("LEFT")
    header.facts:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
    header.facts:SetPoint("RIGHT", header, "RIGHT", -PADDING, 0)
    header.facts:SetTextColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
    header.measure = ns.Widgets.createFontString(header, "OVERLAY", "GameFontHighlightSmall") -- measures the facts' parts
    -- Back to a list from one of its pages (the journal's quest stories): the game's red button at the right
    header.backButton = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    header.backButton:SetSize(110, 22)
    header.backButton:SetPoint("RIGHT", header, "RIGHT", -PADDING, 4)
    header.backButton:SetFrameLevel((header:GetFrameLevel() or 1) + 3)
    header.backButton:SetScript("OnClick", function(self)
        if self.handleClick then
            self.handleClick()
        end
    end)
    header.backButton:Hide()
    header.measure:Hide()
    -- Over the title: shift-click links the quest in chat
    header.titleButton = CreateFrame("Button", nil, header)
    header.titleButton:SetAllPoints(header.title)
    header.titleButton:SetFrameLevel((header:GetFrameLevel() or 1) + 2)
    header.titleButton:SetScript("OnClick", function()
        if header.questId and ns.QuestState.isLinkClick() then
            ns.QuestState.linkInChat(header.questId)
        elseif header.questId and ns.QuestState.isFocusClick() and ns.QuestState.getQuest(header.questId) then
            Log.focusQuest(header.questId) -- a quest of the log, put in focus or let go of
        end
    end)
    header.titleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:AddLine(ns.L("Shift-click to link it in chat"), 0.6, 0.6, 0.6)
        if header.questId and ns.QuestState.getQuest(header.questId) then
            GameTooltip:AddLine(ns.L("Ctrl-click to focus it"), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    header.titleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    header.titleButton:Hide()
    -- The narration's row, for a quest a translation addon has narrated: play now (or stop), queue (or take off
    -- the queue), then who narrates and where it is. Played by that addon, in its own player and queue.
    header.voice = CreateFrame("Frame", nil, header)
    header.voice:SetPoint("TOPLEFT", header.facts, "BOTTOMLEFT", 0, -6)
    header.voice:SetPoint("RIGHT", header, "RIGHT", -PADDING, 0)
    header.voice:SetHeight(20)
    header.voice:SetFrameLevel((header:GetFrameLevel() or 1) + 2)
    for _, part in ipairs({ { "playButton", ns.QuestText.toggleVoice }, { "queueButton", ns.QuestText.toggleVoiceQueue } }) do
        local button = CreateFrame("Button", nil, header.voice, "UIPanelButtonTemplate")
        button:SetSize(72, 20)
        button.baseWidth = 72
        button:SetScript("OnClick", function()
            part[2](header.voice.questId)
        end)
        header.voice[part[1]] = button
    end
    header.voice.playButton:SetPoint("LEFT", header.voice, "LEFT", 0, 0)
    header.voice.queueButton:SetPoint("LEFT", header.voice.playButton, "RIGHT", 4, 0)
    header.voice.text = ns.Widgets.createFontString(header.voice, "OVERLAY", "GameFontHighlightSmall")
    header.voice.text:SetPoint("LEFT", header.voice.queueButton, "RIGHT", 8, 0)
    header.voice.text:SetPoint("RIGHT", header.voice, "RIGHT", 0, 0)
    header.voice.text:SetJustifyH("LEFT")
    header.voice.text:SetWordWrap(false)
    header.voice.text:SetTextColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
    header.voice:Hide()
    header.zoneButton = CreateFrame("Button", nil, header)
    header.zoneButton:SetFrameLevel((header:GetFrameLevel() or 1) + 2)
    local zoneHover = header.zoneButton:CreateTexture(nil, "HIGHLIGHT")
    zoneHover:SetAllPoints(header.zoneButton)
    zoneHover:SetColorTexture(1, 1, 1, 0.1)
    header.zoneButton:SetScript("OnClick", function(self)
        if self.handleClick then
            self.handleClick(self.data)
        end
    end)
    header.zoneButton.underline = header:CreateTexture(nil, "OVERLAY")
    header.zoneButton.underline:SetColorTexture(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3], 0.8)
    header.zoneButton:Hide()
    -- The chain badge: the tracker's rounded outline around the chain icon and the step
    header.badge = CreateFrame("Frame", nil, header)
    header.badge:SetHeight(BADGE_HEIGHT)
    header.badge:SetPoint("TOPRIGHT", header, "TOPRIGHT", -PADDING, -10)
    header.badgeText = ns.Widgets.createFontString(header.badge, "OVERLAY", "GameFontHighlightSmall")
    header.badgeText:SetPoint("RIGHT", header.badge, "RIGHT", 0, 0) -- plain, as the game writes a step: no outline round it
    header.badgeText:SetTextColor(HEADER_BADGE_TEXT[1], HEADER_BADGE_TEXT[2], HEADER_BADGE_TEXT[3])
    local icon = header.badge:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "Chain")
    icon:SetSize(12, 12)
    icon:SetPoint("RIGHT", header.badgeText, "LEFT", -4, 0)
    icon:SetVertexColor(HEADER_BADGE_TEXT[1], HEADER_BADGE_TEXT[2], HEADER_BADGE_TEXT[3])
    header.badge:SetWidth(70) -- set to fit its text whenever the text changes; anchoring it to its own icon would be a loop
    header:Hide()
    return header
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
        { ns.L("Kills"), ns.L("What is left on kill objectives. For items to collect: items left divided by the drop chance.") },
        { ns.L("Loot"), ns.L("Each thing a creature can drop, times its chance, times the kills. Quest-only drops are left out.") },
        { ns.L("Prices"), ns.L("The vendor's, or the auction house's after its %d%% cut when Auctionator has seen the item and it pays more.", 5) },
    }
    for _, part in ipairs(parts) do
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(part[1], 1, 0.82, 0)
        GameTooltip:AddLine(part[2], 0.82, 0.82, 0.82, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.L("Not counted: coins dropped by creatures, travel and repair costs."), 0.63, 0.63, 0.63, true)
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
        State.detail:addText(text, left, y, { font = "QuestFont", color = COLORS.ink, width = right - left - 96, isSingleLine = true })
        State.detail:addText(amountText, right - 92, y, { font = "QuestFont", color = COLORS.ink, width = 92, justify = "RIGHT", isSingleLine = true })
        y = y + 21
    end
    if profit.rewardMoney > 0 then
        addLine(ns.L("Quest money"), formatCopper(profit.rewardMoney))
    end
    for _, rewardItem in ipairs(profit.rewardItems) do
        if rewardItem.isCounted and rewardItem.value > 0 then
            addLine(rewardItem.count > 1 and (rewardItem.name .. " x" .. rewardItem.count) or rewardItem.name, formatCopper(rewardItem.value))
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
    local noteHeight = State.detail:addText(note, left, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = right - left })
    return y + noteHeight + 12
end

---@return string text "Levels 25–33": from the level that can take the quest up to its own level; "Level 33" when
---it can be taken only at its own level, or nothing lower is known. "+" for a group quest.
function Log.formatLevelRange(questId, level, isGroup)
    local requiredLevel = ns.Database.getQuestField(questId, "requiredLevel") or 0
    local suffix = isGroup and "+" or ""
    if requiredLevel > 0 and level and requiredLevel < level then
        return ns.L("Levels %d\226\128\147%d%s", requiredLevel, level, suffix)
    end
    return ns.L("Level %d%s", level or requiredLevel, suffix)
end

---The quest's page, the things that matter first: what it is, what it gives, what is left to do and where.
---The story and the chain follow, each open unless folded.
---@return number height
local function drawLogQuest(entry)
    local details = composeObjectiveDetails(entry)
    local group = ns.QuestState.getGroupInfo(entry.questId)
    local before = Log.formatLevelRange(entry.questId, entry.level, group ~= nil) .. DOT
    local zoneName = ns.Database.getZoneName(entry.zoneId)
    local factsText = before .. zoneName
    if group then
        factsText = factsText .. DOT .. ns.Widgets.formatGroup(group) .. " " .. group.kindText
    end
    setPageHeader(entry.title, factsText, entry.chainIndex, entry.chainTotal, { before = before, text = zoneName, handleClick = ns.MapDock.showQuest, data = entry }, entry.questId)
    local y = 12
    local rewardsExtraHeight = setPageRewards(entry.questId)
    y = addQuestItem(y, entry)
    y = addToDo(y, entry, details)
    -- The party, a part that folds as the ones below it do; its note says how many of them are on the quest
    local partyMembers = ns.Party.getMembers(entry.questId)
    if #partyMembers > 0 then
        local onQuestCount = 0
        for _, member in ipairs(partyMembers) do
            onQuestCount = onQuestCount + (member.isOnQuest and 1 or 0)
        end
        local isPartyOpen
        y, isPartyOpen = addFold(y, "party", entry.questId, ns.L("Party"), ns.L("%d of %d on it", onQuestCount, #partyMembers), true)
        if isPartyOpen then
            -- Their faces across the row, large, each in a ring that fills with their progress; the rest on hover
            local members = ns.Party.getProgress(entry.questId, entry.objectives, entry.eventText ~= nil and not entry.isTurnIn)
            local rowWidth = State.detail.width - 2 * PADDING
            local slotWidth = rowWidth / math.max(#members, 1)
            local faceSize = math.min(52, math.floor(math.min(slotWidth, rowWidth / 4) - 22))
            local size = ns.Widgets.getPortraitSize(faceSize)
            for index, member in ipairs(members) do
                State.detail:addPortrait(PADDING + (index - 0.5) * slotWidth - size / 2, y + 2, faceSize, member)
            end
            y = y + size + 8
            y = y + State.detail:addText(ns.L("Hover a face for their name and progress, or why not"), PADDING, y, {
                font = "GameFontHighlightSmall", color = COLORS.softInk, width = rowWidth, justify = "CENTER", isSingleLine = true,
            }) + 10
        end
    end
    y = addProfitSection(y, entry.questId)

    local isOpen
    local description = ns.QuestState.getDescription(entry.questId)
    if description then
        y, isOpen = addFold(y, "story", entry.questId, ns.L("Story"), nil, true)
        if isOpen then
            y = addBody(y, description) + 10
        end
    end
    if entry.chainIndex then
        y, isOpen = addFold(y, "chain", entry.questId, ns.L("Quest chain"), ns.L("%d of %d", entry.chainIndex, entry.chainTotal), true)
        if isOpen then
            y = addChain(y + 2, entry.questId, true)
        end
    end
    return y + PADDING + rewardsExtraHeight
end

---A quest on the zone page: its name, and under it where it stands. Click opens the quest.
---@return number y Below the lines
local function addZoneLine(y, entry, noteText)
    local width = State.detail.width - 2 * PADDING
    State.detail:addText(string.format("[%d] %s", entry.level, entry.title), PADDING, y + 2, { font = "QuestFont", color = COLORS.ink, width = width, isSingleLine = true })
    State.detail:addText(noteText, PADDING, y + 18, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width, isSingleLine = true })
    State.detail:addButton(PADDING - 4, y, width + 8, 34, selectQuest, entry.questId)
    return y + 38
end

---What is left of a quest, in a few words, and how far along it is.
---@return string text
local function composeProgress(entry)
    if entry.isTurnIn then
        return entry.finisherName or ns.L("Ready to turn in") -- the zone is the heading the quest sits under
    end
    local doneCount, open = 0, nil
    for _, objective in ipairs(entry.objectives) do
        if objective.isFinished then
            doneCount = doneCount + 1
        else
            open = open or objective
        end
    end
    local total = #entry.objectives
    if total == 0 then
        return ""
    end
    local text
    if total - doneCount == 1 and open then
        text = (open.shownLabel or open.label) .. (open.required > 1 and string.format(" %d/%d", open.fulfilled, open.required) or "")
    else
        text = ns.L("%d of %d done", doneCount, total)
    end
    return text
end

---The zone itself in place of a quest: how far through it the character is, a turn-in round, what is open.
---@return number height
local function drawZonePage(group)
    local width = State.detail.width - 2 * PADDING
    local subLines = { ns.Lp(#group.entries, "%d quest with the next step here", "%d quests with the next step here") }
    if group.isCurrent then
        subLines[2] = ns.L("You are here")
    end
    local y = addTitle(PADDING, group.zoneName, subLines)

    local summary = ns.Availability.getZoneSummary(group.zoneId)
    local total = summary.done + summary.inLog + summary.available + summary.notYet
    if total > 0 then
        local parts = {
            { count = summary.done, color = COLORS.darkGreen },
            { count = summary.inLog, color = SELECTED_EDGE },
            { count = summary.available, color = { 0.96, 0.93, 0.82 } },
            { count = summary.notYet, color = { 0.54, 0.52, 0.47 } },
        }
        State.detail:addRect(PADDING, y, width, 10, COLORS.ink)
        local x = PADDING + 1
        for _, part in ipairs(parts) do
            local partWidth = (width - 2) * part.count / total
            if partWidth > 0 then
                State.detail:addRect(x, y + 1, partWidth, 8, part.color, 1)
                x = x + partWidth
            end
        end
        y = y + 15
        y = addBody(y, ns.L("Quests that start here: %d done, %d in your log, %d available, %d not yet", summary.done, summary.inLog, summary.available, summary.notYet), COLORS.softInk) + 12
    end

    local ready, open = {}, {}
    for _, entry in ipairs(group.entries) do
        table.insert(entry.isTurnIn and ready or open, entry)
    end
    if #ready > 0 then
        y = addHeading(y, ns.L("Ready to turn in"))
        for _, entry in ipairs(ready) do
            local place = entry.nearestPlace or entry.places[1]
            y = addZoneLine(y, entry, (entry.finisherName or ns.L("Turn in")) .. (place and place.x >= 0 and string.format("%s%d, %d", DOT, place.x, place.y) or ""))
        end
        y = y + 12
    end
    if #open > 0 then
        y = addHeading(y, ns.L("Still to do here"))
        for _, entry in ipairs(open) do
            y = addZoneLine(y, entry, composeProgress(entry))
        end
        y = y + 12
    end
    if summary.available > 0 then
        local text = ns.Lp(summary.available, "%d more quest can be picked up in %s", "%d more quests can be picked up in %s", group.zoneName)
        local textHeight = State.detail:addText(text, PADDING + 10, y + 8, { font = "QuestFont", color = COLORS.ink, width = width - 20 })
        local height = textHeight + 42
        State.detail:addRect(PADDING, y, width, height, COLORS.softInk)
        State.detail:addRect(PADDING + 1, y + 1, width - 2, height - 2, PAPER_FILL, 1)
        addPaperButton(State.detail, PADDING + 10 + 102, y + textHeight + 14, ns.L("See available"), Log.showZone, group.zoneId)
        y = y + height + 12
    end
    return y + PADDING
end

---Numbered-looking steps joined by a line: the first is the one to do now.
---@param steps { title: string, lines: (string|table)[] }[] A line is a text, or a table as addStepLine takes
---@return number y Below the steps
local function addSteps(y, steps)
    local textLeft = PADDING + 32
    local textWidth = State.detail.width - PADDING - textLeft
    for stepIndex, step in ipairs(steps) do
        local top = y
        local height = State.detail:addText(step.title, textLeft, y + 2, { font = "QuestFont", color = COLORS.ink, width = textWidth })
        y = y + height + 4
        for _, line in ipairs(step.lines) do
            height = addStepLine(y, line, textLeft, textWidth)
            y = y + height + 3
        end
        y = y + 10
        if stepIndex < #steps then
            State.detail:addRect(PADDING + 8.5, top + 10, 3, y - top, COLORS.sand)
        end
        if stepIndex == 1 then
            State.detail:addDot(PADDING, top, 20, COLORS.brown, 0)
            State.detail:addDot(PADDING + 4, top + 4, 12, SELECTED_EDGE, 1)
        else
            State.detail:addDot(PADDING, top, 20, COLORS.softInk, 0)
            State.detail:addDot(PADDING + 2, top + 2, 16, COLORS.parchment, 1)
        end
    end
    return y
end

---@return number height
local function drawAvailableQuest(quest, zoneId)
    local requiredLevel = ns.Database.getQuestField(quest.questId, "requiredLevel") or 0
    -- The same header as a quest in the log: name, a line of facts, the chain badge
    local group = ns.QuestState.getGroupInfo(quest.questId)
    local facts = { Log.formatLevelRange(quest.questId, quest.level, group ~= nil) }
    local instantStepIds = quest.instantStepIds or {}
    if #instantStepIds > 0 then
        facts[#facts + 1] = ns.Lp(#instantStepIds + 1, "%d step at one stop", "%d steps at one stop")
    end
    if quest.startType == "item" then
        facts[#facts + 1] = ns.L("starts from an item")
    end
    local zoneLink
    if quest.finisherPlace then
        local zoneName = ns.Database.getZoneName(quest.finisherPlace.groupZoneId)
        -- The zone is a link wherever the language puts it in the words: the text ahead of it is measured
        local endsText = ns.L("ends in %s", zoneName)
        local zoneStart = endsText:find(zoneName, 1, true) or (#endsText + 1)
        zoneLink = { before = table.concat(facts, DOT) .. DOT .. endsText:sub(1, zoneStart - 1), text = zoneName, handleClick = showPlace, data = { place = quest.finisherPlace } }
        facts[#facts + 1] = endsText
    end
    if group then
        facts[#facts + 1] = ns.Widgets.formatGroup(group) .. " " .. group.kindText
    end
    setPageHeader(quest.title, table.concat(facts, DOT), quest.chainIndex, quest.chainTotal, zoneLink, quest.questId)
    local y = 12

    local warnings, warningLinks = ns.Warnings.getQuestWarnings(quest.questId)
    local linkByWarning = {}
    for index, link in pairs(warningLinks or {}) do
        linkByWarning[warnings[index]] = link
    end
    if quest.availableAtLevel then
        table.insert(warnings, 1, ns.L("Available at level %d", quest.availableAtLevel))
    elseif quest.blocker then
        table.insert(warnings, 1, ns.L("Not yet: %s", (quest.blocker.text:gsub("^%u", string.lower))))
    end
    for _, warning in ipairs(warnings) do
        local link = linkByWarning[warning]
        local before, after
        if link then
            before, after = link.format:match("^(.-)%%s(.*)$")
        end
        local height
        if before then
            -- The quest it names is a link to its page, as the lead-in steps' names are
            height = addStepLine(y + 6, {
                text = before:gsub("\"?%s*$", ""), link = ns.QuestText.getQuestName(link.questId) or ("Quest " .. link.questId),
                afterText = after:gsub("^\"", ""):gsub("^%s+", ""), handleClick = Log.showQuestAnywhere, data = link.questId,
                color = COLORS.warning,
            }, PADDING + 10, State.detail.width - 2 * PADDING - 20)
        else
            height = State.detail:addText(warning, PADDING + 10, y + 6, { font = "QuestFont", color = COLORS.warning, width = State.detail.width - 2 * PADDING - 20 })
        end
        State.detail:addRect(PADDING, y, State.detail.width - 2 * PADDING, height + 12, { 0.79, 0.52, 0.15, 0.28 })
        State.detail:addRect(PADDING, y, 3, height + 12, COLORS.warning, 1)
        y = y + height + 18
    end
    if #warnings > 0 then
        y = y + 6
    end
    local rewardsExtraHeight = setPageRewards(quest.questId)

    -- Steps done back to back are one thing to do, from the start to the last reward: "How it goes"
    y = addHeading(y, ns.L(#instantStepIds > 0 and "How it goes" or "How to start"))
    local place = quest.nearestPlace or quest.places[1]
    local steps = {}
    if quest.startType == "item" then
        local source = quest.starterName and ns.L("Drops from %s", quest.starterName) or ns.L("Found")
        local sourcePlace = not quest.isHandedInHere and place or nil
        local isInInstance = quest.isHandedInHere or (sourcePlace and sourcePlace.x < 0)
        -- Where it drops, as one phrase with its zone when that is known
        local sourceText = source
        if quest.sourceZoneName then
            sourceText = quest.starterName and ns.L("Drops from %s in %s", quest.starterName, quest.sourceZoneName)
                or ns.L("Found in %s", quest.sourceZoneName)
        end
        steps[1] = { title = ns.L(quest.isItemInBags and "Use %s" or "Loot %s", quest.itemName), lines = {
            quest.isItemInBags and ns.L("It is in your bags; using it starts the quest") or sourceText,
        } }
        local dropZones = not quest.isItemInBags and quest.itemId and ns.Drops.getZones(quest.itemId) or {}
        if #dropZones > 0 then
            steps[1].lines = composeDropZoneLines(dropZones, "available:" .. quest.questId, { handleClick = showDropZone, quest = quest })
        elseif not quest.isItemInBags then
            -- Its source is placed nowhere, but the quest belongs to a dungeon: say so, and lead to the way in
            local pickupDungeon = ns.Database.getDungeon(ns.Location.getPickupDungeonId(quest.questId) or 0)
            local entrance = pickupDungeon and pickupDungeon.entrances[1]
            if pickupDungeon then
                steps[1].lines = { ns.L("%s, somewhere in %s: the quest database does not say where", source, pickupDungeon.name) }
            end
            if entrance then
                table.insert(steps[1].lines, composePlaceLine({ groupZoneId = entrance.zoneId, mapZoneId = entrance.zoneId, x = entrance.x, y = entrance.y }, { prefix = ns.L("Entrance at") }))
            end
        end
        if sourcePlace and not isInInstance and #dropZones == 0 then
            -- The drop list names its zones as links already; otherwise the place, with the way there
            table.insert(steps[1].lines, composePlaceLine(sourcePlace, { distance = quest.distance, direction = quest.direction }))
        end
        steps[2] = { title = ns.L("Use it from your bags to accept the quest"), lines = {} }
    else
        local isObject = quest.startType == "object"
        steps[1] = {
            title = quest.starterName and ns.L(isObject and "Use %s" or "Talk to %s", quest.starterName)
                or ns.L(isObject and "Use the quest giver" or "Talk to the quest giver"),
            lines = { place and composePlaceLine(place, { distance = quest.distance, direction = quest.direction }) or ns.L("Location not in the database") },
        }
    end
    -- Behind a lead-in: the lead-ins come first, each a link to its page, saying what kind of quest it is
    if quest.blocker and quest.blocker.kind == "quest" then
        local leadInIds = ns.Availability.getLeadIns(quest.questId, ns.Availability.getPlayer())
        local leadInSteps = {}
        for leadInIndex, leadInId in ipairs(leadInIds) do
            local isInLog = ns.QuestState.isInLog(leadInId)
            local leadInDungeon = ns.Database.getDungeon(ns.Location.getInsideDungeonIds(leadInId)[1] or 0)
            local startZoneId = ns.Availability.getStartZoneId(leadInId)
            local kindText = leadInDungeon and ns.L("a %s quest", leadInDungeon.name)
                or (startZoneId and ns.L("picked up in %s", ns.Database.getZoneName(startZoneId))) or nil
            local title
            if #leadInIds > 1 then
                title = ns.L(isInLog and "Finish lead-in %d of %d" or "Do lead-in %d of %d", leadInIndex, #leadInIds)
            else
                title = ns.L(isInLog and "Finish the lead-in" or "Do the lead-in")
            end
            leadInSteps[#leadInSteps + 1] = {
                title = title,
                lines = { {
                    link = ns.QuestText.getQuestName(leadInId) or ("Quest " .. leadInId),
                    afterText = kindText and (DOT:gsub("^ ", "") .. kindText .. (isInLog and DOT .. ns.L("in your log") or "")) or nil,
                    handleClick = Log.showQuestAnywhere, data = leadInId,
                } },
            }
        end
        for leadInIndex = #leadInSteps, 1, -1 do
            table.insert(steps, 1, leadInSteps[leadInIndex])
        end
    end
    if quest.finisherName then
        local finisherPlace = quest.isHandedInHere and place or quest.finisherPlace
        local lines = {}
        if finisherPlace then
            lines[1] = composePlaceLine(finisherPlace, { suffix = ns.L(finisherPlace.groupZoneId == zoneId and "in this location" or "not in this location") })
        end
        if #instantStepIds > 0 then
            -- What to bring before handing in: each item it asks for, and who drops it
            local objectives = ns.Database.getQuestField(quest.questId, "objectives") or {}
            for _, item in ipairs(objectives[3] or {}) do
                local source = ns.Drops.getHuntedSource(item[1])
                local itemName = ns.Database.getItemField(item[1], "name")
                steps[#steps + 1] = {
                    title = itemName and ns.L("Get %s", itemName) or ns.L("Get the item it asks for"),
                    lines = { source and source.name and ns.L("drops from %s", source.name) or ns.L("it asks for one") },
                }
            end
        end
        steps[#steps + 1] = { title = ns.L("Turn in to %s", quest.finisherName), lines = lines }
        State.shownTurnInPlace = finisherPlace
        for _, stepQuestId in ipairs(instantStepIds) do
            steps[#steps + 1] = {
                title = ns.L("Then take %s there and hand it straight back", ns.QuestText.getQuestName(stepQuestId) or ns.L("the next step")),
                lines = { ns.L("the next step of the same name: it asks nothing, the reward comes at once") },
            }
        end
        if (quest.versionCount or 1) > 1 then
            steps[#steps + 1] = {
                title = ns.L("Any one of the %d will do", quest.versionCount),
                lines = { ns.L("the same quest is at each; doing it at one closes the others") },
            }
        end
    end
    y = addSteps(y, steps) + 8
    State.shownPlace = not quest.isHandedInHere and place or nil

    y = addHeading(y, ns.L("Requirements"))
    local blocker = quest.blocker
    local isLevelMet = not quest.availableAtLevel and not (blocker and blocker.kind == "level")
    local requirement = requiredLevel > 1 and ns.L("Level %d or higher", requiredLevel) or ns.L("No level requirement")
    if isLevelMet then
        State.detail:addIcon(PADDING, y, 14, READY_ICON)
    else
        State.detail:addDot(PADDING + 2, y + 2, 10, COLORS.warning, 0)
    end
    y = addBody(y, requirement, isLevelMet and COLORS.ink or COLORS.warning, 22)
    if blocker and blocker.kind == "quest" then
        -- The quest to do first, and where its chain starts when that is further back: each a link to its page
        State.detail:addDot(PADDING + 2, y + 2, 10, COLORS.warning, 0)
        local textLeft, textWidth = PADDING + 22, State.detail.width - 2 * PADDING - 22
        local isInLog = ns.QuestState.isInLog(blocker.questId)
        y = y + addStepLine(y, { text = ns.L(isInLog and "Finish" or "Do"), link = blocker.name, afterText = ns.L("first"), handleClick = Log.showQuestAnywhere, data = blocker.questId }, textLeft, textWidth) + 6
        local chainStartQuestId = ns.Availability.getChainStart(quest.questId, ns.Availability.getPlayer())
        if chainStartQuestId and chainStartQuestId ~= blocker.questId then
            local chainStartName = ns.QuestText.getQuestName(chainStartQuestId) or ("Quest " .. chainStartQuestId)
            local startZoneId = ns.Availability.getStartZoneId(chainStartQuestId)
            y = y + addStepLine(y, {
                text = ns.L("The chain starts with"), link = chainStartName, handleClick = Log.showQuestAnywhere, data = chainStartQuestId,
                afterText = startZoneId and ns.L("in %s", ns.Database.getZoneName(startZoneId)) or nil,
            }, textLeft, textWidth) + 6
        end
    elseif blocker and blocker.kind ~= "level" then
        State.detail:addDot(PADDING + 2, y + 2, 10, COLORS.warning, 0)
        y = addBody(y, blocker.text, COLORS.warning, 22)
    end
    if quest.itemName then
        State.detail:addDot(PADDING + 2, y + 2, 10, COLORS.softInk, 0)
        State.detail:addDot(PADDING + 4, y + 4, 6, COLORS.parchment, 1)
        y = addBody(y, ns.L("%s in your bags", quest.itemName), COLORS.ink, 22)
    end
    y = y + 12

    y = addProfitSection(y, quest.questId)
    local isOpen
    local objectivesText = ns.Database.getQuestField(quest.questId, "objectivesText")
    local hasObjectives = next(ns.Database.getQuestField(quest.questId, "objectives") or {}) ~= nil
    if type(objectivesText) == "table" and #objectivesText > 0 then
        y, isOpen = addFold(y, "asks", quest.questId, ns.L("What it asks"), nil, true)
        if isOpen then
            y = addBody(y, ns.QuestText.getObjectives(quest.questId, table.concat(objectivesText, " "))) + 10
        end
    elseif not hasObjectives and quest.finisherName then
        -- No text and nothing to do (the Sparklematic 5200!'s second step): say so, not leave the player guessing
        y, isOpen = addFold(y, "asks", quest.questId, ns.L("What it asks"), nil, true)
        if isOpen then
            local isSameHands = quest.finisherName == quest.starterName
            y = addBody(y, ns.L(isSameHands and "Nothing in between: take it and hand it straight back to %s for the reward."
                or "Nothing to collect or kill: take it to %s.", quest.finisherName)) + 10
        end
    end
    if quest.chainIndex then
        y, isOpen = addFold(y, "chain", quest.questId, ns.L("Quest chain"), ns.L("%d of %d", quest.chainIndex, quest.chainTotal), true)
        if isOpen then
            y = addChain(y + 2, quest.questId, true)
        end
    end
    return y + PADDING + rewardsExtraHeight
end

-- Shared with the other parts of the window
QuestPage.CHECKBOX_IMAGE = CHECKBOX_IMAGE
QuestPage.CHECKBOX_SIZE = CHECKBOX_SIZE
QuestPage.CHECKBOX_TICK = CHECKBOX_TICK
QuestPage.TO_DO_LEAD = TO_DO_LEAD
QuestPage.addBody = addBody
QuestPage.addHeading = addHeading
QuestPage.addSteps = addSteps
QuestPage.addPaperButton = addPaperButton
QuestPage.composeProgress = composeProgress
QuestPage.createPageHeader = createPageHeader
QuestPage.createRewardsBlock = createRewardsBlock
QuestPage.drawAvailableQuest = drawAvailableQuest
QuestPage.drawLogQuest = drawLogQuest
QuestPage.drawZonePage = drawZonePage
QuestPage.followPageScroll = followPageScroll
QuestPage.setAtlasIfKnown = setAtlasIfKnown
QuestPage.composeObjectiveDetails = composeObjectiveDetails
QuestPage.setPageHeader = setPageHeader

---Puts a back button in the page's header, as the journal's quest stories have: after setPageHeader, which takes
---it away again.
function QuestPage.setPageHeaderBack(text, handleClick)
    local button = State.pageHeader and State.pageHeader.backButton
    if not button then
        return
    end
    button:SetText(text)
    button.handleClick = handleClick
    button:Show()
end
QuestPage.setPageRewards = setPageRewards
