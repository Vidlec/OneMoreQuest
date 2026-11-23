local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

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

-- What the Spoilers choices let a quest's page tell (ns.Spoilers), worked out once as the page is drawn
-- (Spoiled.compose): Spoiled.view is nil in Guide, where everything is told as ever and nothing below asks again.
-- One table, so the page's functions keep their names few.
local Spoiled = {}

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
    local button = canvas:addButton(x, y, width, 20, handleClick, data)
    return width, button
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

local function hideTooltip()
    GameTooltip:Hide()
end

local function openChainStep(questId)
    Log.showQuestAnywhere(questId)
end

local function openDoneStep(questId)
    ns.ChroniclePage.openQuest(questId)
end

---Says that a step done opens in the chronicle, and when it was handed in.
local function showDoneStepTooltip(button, questId)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local entry = ns.ChroniclePage.findEntry(questId)
    GameTooltip:AddLine(ns.L(entry and "Click to read it in the Chronicle" or "Click to see it in the Chronicle"), 1, 1, 1)
    if entry and entry.turnedInAt then
        GameTooltip:AddLine(ns.L("Done %s", ns.Chronicle.formatShownDate("%d %b %Y", entry.turnedInAt)), 0.82, 0.77, 0.64)
    else
        GameTooltip:AddLine(ns.L("Done before the chronicle began"), 0.82, 0.77, 0.64, true)
    end
    GameTooltip:Show()
end

---Says where a step of the chain opens, and when it is not to be picked up yet, after which step.
local function showChainStepTooltip(button, questId)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local isInLog = ns.QuestState.isInLog(questId)
    GameTooltip:AddLine(ns.L(isInLog and "Click to open it in My quests" or "Click to open it on the Available tab"), 1, 1, 1)
    if not isInLog then
        local questIds = ns.Chain.getQuestIds(questId)
        for position, chainQuestId in ipairs(questIds) do
            local before = questIds[position - 1]
            if chainQuestId == questId and before and not ns.QuestState.isTurnedIn(before) then
                local name = ns.QuestText.getQuestName(before) or ("Quest " .. before)
                GameTooltip:AddLine(ns.L("Not to pick up yet: after %s", name), 0.82, 0.77, 0.64, true)
            end
        end
    end
    GameTooltip:Show()
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

---@return number[] color An item's name colour on the parchment: its quality's, darkened to read on the light page
---@return number[] color The rim round a reward's icon: its quality's colour from Uncommon up, else the page's dark rim
local function getPrizeRimColor(quality)
    local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if not color then
        return { 0.42, 0.29, 0.15 }
    end
    return { color.r, color.g, color.b }
end

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

local function showPrizeTooltip(button, item)
    if QuestPage.showRewardTooltip then
        QuestPage.showRewardTooltip(button, item)
    end
end

---The game's framed parchment panel (ParchmentPopup's art), drawn under what stands on it: its corners and edges in
---the gold-trimmed frame, its middle the darker parchment.
local BOX_CORNER, BOX_INSET = 24, 7
local function addParchmentBox(x, y, width, height)
    local page = State.detail
    local middle, side = width - 2 * BOX_CORNER, height - 2 * BOX_CORNER
    page:addImage(x + BOX_INSET, y + BOX_INSET, width - 2 * BOX_INSET, height - 2 * BOX_INSET, { atlas = "ParchmentPopup-Background" }, nil, nil, -4)
    for _, part in ipairs({
        { "ParchmentPopup-TopLeft", x, y, BOX_CORNER, BOX_CORNER }, { "ParchmentPopup-TopRight", x + width - BOX_CORNER, y, BOX_CORNER, BOX_CORNER },
        { "ParchmentPopup-BottomLeft", x, y + height - BOX_CORNER, BOX_CORNER, BOX_CORNER },
        { "ParchmentPopup-BottomRight", x + width - BOX_CORNER, y + height - BOX_CORNER, BOX_CORNER, BOX_CORNER },
        { "ParchmentPopup-Top", x + BOX_CORNER, y, middle, BOX_CORNER }, { "ParchmentPopup-Bottom", x + BOX_CORNER, y + height - BOX_CORNER, middle, BOX_CORNER },
        { "ParchmentPopup-Left", x, y + BOX_CORNER, BOX_CORNER, side }, { "ParchmentPopup-Right", x + width - BOX_CORNER, y + BOX_CORNER, BOX_CORNER, side },
    }) do
        page:addImage(part[2], part[3], part[4], part[5], { atlas = part[1] }, nil, nil, -3)
    end
end

---The chain's prize and what is left in it, above the steps, in the game's framed parchment panel: each item as the
---game's quest window shows a reward (its icon in a frame on the reward name plate), two to a row, and what is left
---in one line of ink.
---@return number y Below it
local BOX_PADDING = 14
local XP_REWARD_ICON = "Interface\\Icons\\XP_Icon" -- the game's own experience icon, as on the quest's rewards
local function addChainPrize(y, questIds, index)
    local rest = composeChainRest(questIds, index)
    local boxTop = y
    local left, width = PADDING + BOX_PADDING, State.detail.width - 2 * PADDING - 2 * BOX_PADDING
    y = y + BOX_PADDING
    local last = rest.last
    local items = last and (#last.choices > 0 and last.choices or last.items) or {}
    if #items > 0 then
        local lastQuestId = questIds[#questIds]
        local name = ns.QuestText.getQuestName(lastQuestId) or ("Quest " .. lastQuestId)
        local label = #last.choices > 1 and ns.L("At the end, %s: choose one", name) or ns.L("At the end, %s:", name)
        y = y + State.detail:addText(label, left, y, { font = "QuestFont", color = COLORS.ink, width = width }) + 6
        -- Two to a row; one alone has the whole width, so its name fits on its plate
        local columnCount = #items == 1 and 1 or 2
        local columnWidth = math.floor((width - (columnCount - 1) * PRIZE_GAP) / columnCount)
        local nameWidth = columnWidth - PRIZE_ICON - 8
        for position, item in ipairs(items) do
            local column = (position - 1) % columnCount
            local x = left + column * (columnWidth + PRIZE_GAP)
            -- The icon in its frame, the item's quality on its rim; the name beside it on the parchment, in ink (or its
            -- quality's colour, darkened to read on the page), wrapping in the item's column
            local rim = getPrizeRimColor(item.quality)
            State.detail:addRect(x, y, PRIZE_ICON, PRIZE_ICON, rim, 1)
            State.detail:addRect(x + 1, y + 1, PRIZE_ICON - 2, PRIZE_ICON - 2, { 0, 0, 0 }, 2)
            State.detail:addIcon(x + 2, y + 2, PRIZE_ICON - 4, item.texture or "Interface\\Icons\\INV_Misc_QuestionMark", nil, 5, { 0.07, 0.93, 0.07, 0.93 })
            if item.count and item.count > 1 then
                State.detail:addText(tostring(item.count), x, y + PRIZE_ICON - 13, { font = "NumberFontNormal", color = COLORS.white, width = PRIZE_ICON - 3, justify = "RIGHT", isSingleLine = true, level = 6 })
            end
            -- (centred on the icon: placed, measured, then moved down by half what is left)
            local nameHeight, _, nameText = State.detail:addText(item.name, x + PRIZE_ICON + 5, y, {
                font = "QuestFont", color = getPrizeNameColor(item.quality), width = nameWidth,
            })
            local nameTop = y + math.max(0, math.floor((PRIZE_ICON - (nameHeight or 14)) / 2))
            if nameText and nameTop ~= y then
                ns.Widgets.place(nameText, "TOPLEFT", State.detail.content, "TOPLEFT", x + PRIZE_ICON + 5, -nameTop)
            end
            State.detail:addButton(x, y, columnWidth, PRIZE_ICON, nil, item, showPrizeTooltip, nil, hideTooltip)
            if column == columnCount - 1 or position == #items then
                y = y + PRIZE_ICON + 8
            end
        end
    end
    -- What is left, as pieces that flow and wrap whole: "Left in the chain:", the game's experience icon and the
    -- amount, the coins, each faction, the items still on the way
    local pieces = {}
    if rest.experience > 0 then
        pieces[#pieces + 1] = { icon = XP_REWARD_ICON, text = BreakUpLargeNumbers and BreakUpLargeNumbers(rest.experience) or tostring(rest.experience) }
    end
    if rest.money > 0 then
        pieces[#pieces + 1] = { text = ns.Widgets.formatMoney(rest.money) }
    end
    for _, factionId in ipairs(rest.factionOrder) do
        pieces[#pieces + 1] = { text = string.format("%s +%d", ns.Availability.getFactionName(factionId), rest.reputation[factionId]) }
    end
    if rest.itemsOnTheWay > 0 then
        pieces[#pieces + 1] = { text = ns.Lp(rest.itemsOnTheWay, "%d more item on the way", "%d more items on the way") }
    end
    if rest.isLoading then
        pieces[#pieces + 1] = { text = ns.L("(asking the game for the rest)") }
    end
    local lineHeight, right = 20, left + width
    local _, leadWidth = State.detail:addText(ns.L("Left in the chain:"), left, y + 2, { font = "QuestFont", color = COLORS.softInk, isSingleLine = true })
    local x = left + (leadWidth or 110) + 8
    for _, piece in ipairs(pieces) do
        local iconWidth = piece.icon and 20 or 0
        local textHeight, textWidth, text = State.detail:addText(piece.text, x + iconWidth, y + 2, { font = "QuestFont", color = COLORS.ink, isSingleLine = true })
        textWidth = textWidth or (#piece.text * 7)
        if x + iconWidth + textWidth > right and x > left then
            -- Not room on this line: the piece starts the next one
            x, y = left, y + lineHeight
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
    y = y + lineHeight + BOX_PADDING - 4
    addParchmentBox(PADDING, boxTop, State.detail.width - 2 * PADDING, y - boxTop)
    return y + 10
end

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
    -- A step still to come opens where it is: in the log on My quests, else on the Available tab; a step done opens
    -- in the chronicle, its story there
    if state == "done" or (state == "upcoming" and ns.QuestState.isTurnedIn(chainQuestId)) then
        State.detail:addButton(textLeft - 2, y - 2, State.detail.width - PADDING - textLeft + 4, textHeight + 4, openDoneStep, chainQuestId,
            showDoneStepTooltip, nil, hideTooltip)
    elseif state == "upcoming" then
        State.detail:addButton(textLeft - 2, y - 2, State.detail.width - PADDING - textLeft + 4, textHeight + 4, openChainStep, chainQuestId,
            showChainStepTooltip, nil, hideTooltip)
    end
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

---A chain told only by how long it is (Spoilers: chains "how many steps"): the steps done, by name; this quest; then
---"· · ·  3 more steps" and that a reward waits at the end, the later steps and the prize unnamed.
---@return number y Below the chain
function Spoiled.addCountedChain(y, questIds, index, total, isNameShared)
    if not index then
        return y
    end
    local doneIds = {}
    for position = 1, index - 1 do
        if ns.QuestState.isTurnedIn(questIds[position]) then
            doneIds[#doneIds + 1] = questIds[position]
        end
    end
    -- Many done: folded into "n quests before", as a long chain folds its ends
    local isFolded = #doneIds >= MAX_OPEN_CHAIN and not State.isChainExpanded
    if isFolded then
        y = addChainFold(y, ns.Lp(#doneIds, "%d quest before", "%d quests before"))
    end
    for _, doneId in ipairs(isFolded and {} or doneIds) do
        y = addChainStep(y, doneId, "done", isNameShared(doneId))
    end
    if #doneIds >= MAX_OPEN_CHAIN and not isFolded then
        y = addChainFold(y, ns.L("Show less"), true)
    end
    y = addChainStep(y, questIds[index], "current", isNameShared(questIds[index]))
    if index < total then
        State.detail:addText("\194\183 \194\183 \194\183", PADDING + 1, y, { font = "QuestFont", color = COLORS.softInk, isSingleLine = true })
        y = y + State.detail:addText(ns.Lp(total - index, "%d more step", "%d more steps"), PADDING + TO_DO_LEAD, y, {
            font = "QuestFont", color = COLORS.softInk, isSingleLine = true,
        }) + 8
        if not Spoiled.view or Spoiled.view.rewards ~= "hidden" then
            y = y + State.detail:addText(ns.L("A reward waits at the end of the chain."), PADDING, y, {
                font = "GameFontHighlightSmall", color = COLORS.softInk, width = State.detail.width - 2 * PADDING,
            }) + 6
        end
    end
    return y + 12
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
    local view = Spoiled.view
    if index and index < total and (not view or (view.chains == "all" and view.rewards == "shown")) then
        y = addChainPrize(y, questIds, index)
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
    if view and view.chains ~= "all" then
        return Spoiled.addCountedChain(y, questIds, index, total, isNameShared)
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

QuestPage.showRewardTooltip = showRewardTooltip -- (for the chain's prize, drawn above this)

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
        local left, right = 12, PAGE_CONTENT_WIDTH + (State.frame.pageExtra or 0) - 12
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
        -- (experience only where the Spoilers choice tells rewards whole, as the tooltips do)
        if rewards.experience > 0 and (type(questId) ~= "number" or ns.QuestTooltip.isExperienceShown(questId)) then
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
    State.detail.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", State.frame.pageLeft or LIST_WIDTH + 2, (State.frame.pageBottom or BAR_HEIGHT) + 2 + peekHeight) -- (over the bar, or at the foot with a controller)
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
    -- (Spoilers: with names only, no chances; with "found", only the creatures that dropped it for the player; a
    -- rough area, no spots; objectives found or hidden, no zones at all)
    local view = options.view
    local function getSources(zone)
        return view and Spoiled.keepSources(zone.sources, view, options.itemId) or zone.sources
    end
    local function getDotColor(source)
        if view and view.drops ~= "names" and view.drops ~= "chances" then
            return nil -- (the map colours a creature's places only where drops are named: no square to match)
        end
        return ns.MapMarks.getShadeColor(isByCreature and source.shade or options.objectiveShade, options.questId or (options.quest and options.quest.questId))
    end
    local function getClickData(zone)
        -- (a rough area: the map turns to the zone, not to a spot in it)
        return { zone = zone, place = not (view and view.isRough) and getDropZonePlace(zone) or nil, quest = options.quest, questId = options.questId }
    end
    local function formatSource(source)
        return source.name .. (source.chance and not (view and view.isChanceHidden) and (DOT .. ns.Drops.formatChance(source.chance)) or "")
    end
    local function addCreatures(zone, indent, firstPrefix)
        local zoneKey = foldKey .. ":" .. zone.zoneId
        local isOpen = dropFolds[zoneKey]
        local sources = getSources(zone)
        for index, source in ipairs(sources) do
            if index > MAX_ZONE_CREATURES and not isOpen then
                lines[#lines + 1] = { link = ns.Lp(#sources - MAX_ZONE_CREATURES, "+ %d more here", "+ %d more here"), handleClick = toggleDropFold, data = zoneKey, indent = indent + 14, isQuiet = true }
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
        if view and view.areZonesHidden then
            return lines
        end
        local data = getClickData(zone)
        local place = data.place
        lines[#lines + 1] = {
            text = place and place.dungeonName and ns.L("Inside %s, entrance in", place.dungeonName) or ns.L("in"),
            link = zone.name .. (place and place.x >= 0 and string.format(" %d, %d", place.x, place.y) or ""), handleClick = options.handleClick, data = data,
        }
        return lines
    end
    if view and view.areZonesHidden then
        return Spoiled.composeCreatureLines(zones, getSources, formatSource, getDotColor)
    end

    local creatureNames, creatureCount = {}, 0
    for _, zone in ipairs(zones) do
        for _, source in ipairs(getSources(zone)) do
            if not creatureNames[source.name] then
                creatureNames[source.name], creatureCount = true, creatureCount + 1
            end
        end
    end
    lines[1] = { text = creatureCount > 0 and ns.Lp(creatureCount, "Drops from %d creature in %d zones", "Drops from %d creatures in %d zones", #zones)
        or ns.Lp(#zones, "In %d zone", "In %d zones") }
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
    -- The same page opens on the Dungeons tab: there only the map turns, the Available tab's place and choice untouched
    if State.selectedTab ~= TAB_AVAILABLE then
        ns.MapPins.queueRefresh()
        return
    end
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

-- The Spoilers choices on the page (Spoiled.view). Each is asked only while something is held back.

---@return table? view What the page may tell of the quest; nil in Guide
function Spoiled.compose(questId)
    if not ns.Spoilers.isActive() then
        return nil
    end
    local get = ns.Spoilers.get
    local view = {
        objectives = get("objectives", questId), drops = get("drops", questId), turnIn = get("turnIn", questId),
        chains = get("chains", questId), rewards = get("rewards", questId), hint = ns.Spoilers.getHint(questId),
        isTurnInShown = ns.Model.isTurnInShown(questId),
        isStoryHidden = ns.Availability.isLaterHidden("quest"), isDungeonHidden = ns.Availability.isLaterHidden("dungeon"),
    }
    view.isChanceHidden = view.drops ~= "chances"
    view.isRough = view.objectives == "rough"
    view.areZonesHidden = view.objectives == "found" or view.objectives == "hidden"
    return view
end

---@return table[] sources The creatures (and objects) that drop an item that may be named: all of them with names or
---chances; with "found", those that dropped it for the player; none when hidden
function Spoiled.keepSources(sources, view, itemId)
    if view.drops == "names" or view.drops == "chances" or not view.drops then
        return sources
    end
    local kept = {}
    for _, source in ipairs(view.drops == "found" and itemId and sources or {}) do
        if ns.Spoilers.hasSeenDrop(itemId, source.npcId or source.objectId) then
            kept[#kept + 1] = source
        end
    end
    return kept
end

---@return string? text An objective's source in words ("Drops from ..."), as the drops choice lets it be told; how
---a crafted item is made is no spoiler and stays
function Spoiled.keepSourceText(detail, view)
    if detail.isCrafted or not detail.sourceText or view.drops == "names" or view.drops == "chances" then
        return detail.sourceText
    end
    if view.drops == "found" and detail.itemId and ns.Spoilers.hasSeenDrop(detail.itemId) then
        return detail.sourceText
    end
    return nil
end

---The creatures an item drops from, each once, with no zones: for objectives whose places are held back.
---@return table[] lines
local MAX_NAMED_CREATURES = 4
function Spoiled.composeCreatureLines(zones, getSources, formatSource, getDotColor)
    local lines, isNamed, count = {}, {}, 0
    for _, zone in ipairs(zones) do
        for _, source in ipairs(getSources(zone)) do
            if not isNamed[source.name] then
                isNamed[source.name], count = true, count + 1
                if count <= MAX_NAMED_CREATURES then
                    lines[#lines + 1] = { text = ns.L(count == 1 and "Drops from %s" or "or %s", formatSource(source)), dotColor = getDotColor(source) }
                end
            end
        end
    end
    if count > MAX_NAMED_CREATURES then
        local last = lines[#lines]
        last.text = last.text .. ns.Lp(count - MAX_NAMED_CREATURES, " and %d more", " and %d more")
    end
    return lines
end

---A zone named without a spot in it, as a link that turns the map to the zone: a rough area.
---@return table line
function Spoiled.composeZoneLine(questId, zoneId, prefix)
    return {
        text = prefix, link = ns.Database.getZoneName(zoneId) or ns.L("Unknown location"),
        handleClick = showObjectivePlace, data = { questId = questId, zone = { zoneId = zoneId } },
    }
end

local MAX_FOUND_PLACES = 3 -- the places found listed under an objective, the newest first

---@return table[] lines Where the player saw an objective move on, newest first, each a place to click; or the
---words saying they have not found any yet
function Spoiled.composeFoundLines(questId, objectiveIndex)
    local found = ns.Spoilers.getFoundPlaces(questId, objectiveIndex)
    if #found == 0 then
        return { ns.L("You have not found any yet") }
    end
    local lines = {}
    for index = #found, math.max(#found - MAX_FOUND_PLACES + 1, 1), -1 do
        local spot = found[index]
        local place = { mapZoneId = spot.zoneId, groupZoneId = spot.zoneId, x = math.floor(spot.x + 0.5), y = math.floor(spot.y + 0.5) }
        lines[#lines + 1] = composePlaceLine(place, { suffix = ns.L("found by you"), handleClick = showObjectivePlace, data = { questId = questId, place = place } })
    end
    if #found > MAX_FOUND_PLACES then
        lines[#lines + 1] = ns.Lp(#found - MAX_FOUND_PLACES, "and %d more place", "and %d more places")
    end
    return lines
end

---Where an objective is, as the objectives choice lets it be told: exactly (as in Guide), its zone alone (rough),
---the places the player found (found), or nothing but its source; a hint's first step adds the zone.
---@param zoneId number? The zone of the objective's places, when known
---@param exactLine table? The place as Guide tells it, for "exact"
---@return table lines For addLine: texts and lines, each under the objective
function Spoiled.composeWhere(view, questId, objectiveIndex, sourceText, zoneId, exactLine)
    if view.objectives == "exact" then
        return { exactLine or sourceText }
    end
    local lines = {}
    if view.objectives == "rough" and zoneId then
        lines[1] = Spoiled.composeZoneLine(questId, zoneId, sourceText and (sourceText .. DOT:gsub(" $", "")) or ns.L("in"))
        return lines
    end
    lines[1] = sourceText
    if view.objectives == "found" then
        for _, line in ipairs(Spoiled.composeFoundLines(questId, objectiveIndex)) do
            lines[#lines + 1] = line
        end
    end
    if zoneId and view.hint >= ns.Spoilers.HINT_ZONE then
        lines[#lines + 1] = Spoiled.composeZoneLine(questId, zoneId, ns.L("Somewhere in"))
    end
    return lines
end

---What is left to do, counts first, each line with where it is done, ending with the turn-in.
---@return number y Below the list
local function addToDo(y, entry, details)
    y = addHeading(y, ns.L("To do"))
    local textLeft, textWidth = PADDING + TO_DO_LEAD, State.detail.width - 2 * PADDING - TO_DO_LEAD
    local view = Spoiled.view
    ---@param where string|table? Under the line: a text, or a line for addStepLine, such as a place to click; or a list
    ---of those, one under the other
    local function addLine(text, color, where)
        local height = State.detail:addText(text, textLeft, y, { font = "QuestFont", color = color, width = textWidth })
        y = y + height + 2
        if type(where) == "table" and where.text == nil and where.link == nil then
            for _, line in ipairs(where) do -- (a list: its texts and lines, in order)
                if type(line) == "table" then
                    line.font = "GameFontHighlightSmall"
                    y = y + addStepLine(y, line, textLeft, textWidth) + 2
                elseif line ~= "" then
                    y = y + State.detail:addText(line, textLeft, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = textWidth }) + 2
                end
            end
        elseif type(where) == "table" then
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
            view = view, itemId = objectiveDetail.itemId,
        })
        if view and view.objectives ~= "exact" and view.objectives ~= "rough" then
            -- (the creatures' zones held back: the places found, or the zone a hint gave)
            local place = objectiveDetail.place
            for _, line in ipairs(Spoiled.composeWhere(view, entry.questId, objectiveIndex, nil, place and (place.mapZoneId or place.groupZoneId))) do
                lines[#lines + 1] = type(line) == "table" and line or { text = line }
            end
        end
        for _, line in ipairs(lines) do
            line.font = "GameFontHighlightSmall"
            y = y + addStepLine(y, line, textLeft, textWidth) + 3
        end
        y = y + 6
    end
    -- Done objectives left out as the tracker leaves them out, when the player chose that: the page and the tracker
    -- list the same steps. Each keeps its own number, which its colour on the map goes by.
    if view then
        for _, objectiveDetail in ipairs(details) do
            objectiveDetail.sourceText = Spoiled.keepSourceText(objectiveDetail, view)
        end
    end
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
                whereText = (not view or view.objectives == "exact") and composePlaceLine(place, {
                    prefix = sourceText and (sourceText .. DOT:gsub(" $", "")) or nil,
                    handleClick = showObjectivePlace, data = { questId = entry.questId, place = place },
                }) or nil
                if view then
                    whereText = Spoiled.composeWhere(view, entry.questId, objectiveIndex, sourceText, place.mapZoneId or place.groupZoneId, whereText)
                end
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
        if view and not view.isTurnInShown then
            eventPlace = nil -- (where it happens is the turn-in's place, held back)
        end
        local happensAt = entry.finisherName and ns.L("Happens at %s", entry.finisherName) or ns.L("Happens at the quest giver")
        addLine(entry.eventText, COLORS.ink, eventPlace and composePlaceLine(eventPlace, { prefix = happensAt .. "," }) or happensAt)
    end
    -- The turn-in closes the list: the last thing to do, or the only one left
    local finisherPlaces = ns.Location.getFinisherPlaces(entry.questId)
    local _, _, finisherPlace = ns.Geometry.getNearest(finisherPlaces, ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
    finisherPlace = finisherPlace or finisherPlaces[1]
    -- The map's turn-in mark: the game's "?", grey until the quest is ready, as the map shows it then
    State.detail:addMark(PADDING - 1, y - 1, 18, { kind = "turnIn", questId = entry.questId, isFocused = false, lines = {}, isPending = not entry.isTurnIn })
    local turnInWhere = finisherPlace and composePlaceLine(finisherPlace) or nil
    if view and view.turnIn == "met" and view.isTurnInShown and finisherPlace then
        turnInWhere = composePlaceLine(finisherPlace, { suffix = ns.L("you have met them") })
    elseif view and not view.isTurnInShown then
        -- Held back: the name alone (the game's own words say it too); "once you met them" says they are not met yet
        turnInWhere = view.turnIn == "met" and ns.L("Not met yet") or nil
    end
    addLine(entry.finisherName and ns.L("Turn in to %s", entry.finisherName) or ns.L("Turn in to the quest giver"), entry.isTurnIn and COLORS.darkGreen or COLORS.ink,
        turnInWhere)
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
    if entry.otherZonesText and not (view and view.areZonesHidden) then
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
local PARTY_FACE = 24 -- a member's face on their row (controller)
local PARTY_ROW_HEIGHT = 34

---@return string text Where a member is with the quest, in a few words: their first count not done ("5/7 Plainstrider
---Beak"), done, or why they are not on it
---@return number[] color
---@return boolean canTake They can take it: sharing it with the party would give it to them
local function describeMember(member)
    local status = member.status or {}
    if status.state == "has" then
        if member.share == 1 then
            return ns.L("Done, ready to turn in"), COLORS.darkGreen, false
        end
        for index, count in ipairs(member.counts or {}) do
            local objective = member.objectives and member.objectives[index]
            if count and not count.isDone and objective then
                return string.format("%d/%d %s", count.fulfilled, count.required, objective.shownLabel or objective.label), COLORS.ink, false
            end
        end
        return ns.L("On this quest"), COLORS.ink, false
    elseif status.state == "can" then
        return ns.L("Not on it, can take it"), COLORS.brown, true
    elseif status.state == "done" then
        return ns.L("Done it already"), COLORS.softInk, false
    elseif status.state == "cannot" then
        return status.reason or ns.L("Not on it"), COLORS.softInk, false -- (why, in a few words: a level, a quest before)
    end
    return ns.L("Not on it"), COLORS.softInk, false -- (nothing known yet: the tooltip says what could be the reason)
end

---A member's menu (Y on their row): whisper them; share the quest when they can take it.
local function openMemberMenu(member)
    if type(MenuUtil) ~= "table" or not MenuUtil.CreateContextMenu then
        return
    end
    local _, _, canTake = describeMember(member)
    ns.openMenu(nil, function(_, root)
        root:CreateTitle(member.name)
        root:CreateButton(ns.L("Whisper"), function()
            if ChatFrame_SendTell then
                ChatFrame_SendTell(member.fullName or member.name)
            end
        end)
        if canTake and member.questId then
            root:CreateButton(ns.L("Share with the party"), function() ns.Log.shareQuest(member.questId) end)
        end
    end)
end

local function showMemberTooltip(button, member)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    ns.Party.addMemberToTooltip(GameTooltip, member)
    GameTooltip:Show()
end

local function pressMember(member)
    local _, _, canTake = describeMember(member)
    if canTake and member.questId then
        ns.Log.shareQuest(member.questId)
    end
end

---The party as rows (with a controller): each member's face in its ring, their name, and where they are with the
---quest; the row is one stop for the cursor, its tooltip the faces' own, A shares the quest with a member who can
---take it, Y opens their menu.
---@return number y Below the rows
function QuestPage.addPartyRows(y, entry, members)
    local width = State.detail.width - 2 * PADDING
    for _, member in ipairs(members) do
        member.questId = entry.questId
        local text, color, canTake = describeMember(member)
        local faceTop = y + (PARTY_ROW_HEIGHT - ns.Widgets.getPortraitSize(PARTY_FACE)) / 2
        State.detail:addPortrait(PADDING, faceTop, PARTY_FACE, member)
        local textLeft = PADDING + ns.Widgets.getPortraitSize(PARTY_FACE) + 8
        State.detail:addText(member.name, textLeft, y + 3, { font = "GameFontNormal", color = COLORS.ink, width = width - textLeft, isSingleLine = true })
        State.detail:addText(text, textLeft, y + 18, { font = "GameFontHighlightSmall", color = color, width = width - textLeft + PADDING, isSingleLine = true })
        local button = State.detail:addButton(PADDING - 4, y, width + 8, PARTY_ROW_HEIGHT, pressMember, member, showMemberTooltip, openMemberMenu)
        button.canShareWith = canTake
        y = y + PARTY_ROW_HEIGHT + 2
    end
    return y
end

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
local HEADER_ART_RIM = 5 -- texels of darker rim on the left of the header's art
local HEADER_BADGE_FILL, HEADER_BADGE_TEXT = { 0.14, 0.12, 0.08 }, { 0.91, 0.86, 0.75 }

-- State.pageHeader: the bar pinned above the page; created with the window
local BADGE_HEIGHT = 18
local HEADER_FRINGE_SHARE = 9 / 52 -- the lower part of the header art that is a fringe over the page, as in the game's layout
local HEADER_FRINGE = 9 -- that fringe, texels and pixels: drawn at its own height however tall the header is
local PLAIN_PAGE_GAP = 6 -- between the header's shadow and a page that is not a quest's (settings, Chronicle)
local HEADER_CORNER = { 28, 23 } -- the gold flourishes in the header's lower corners (small: clear of the facts line)
local addHeaderOrnaments -- (below)
local HEADER_BOTTOM_PADDING = 15 -- room under the last line (the facts, or the narration's buttons) to the header art's lower edge
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
    -- The seal is a quest giver's: on a quest's page only, not on the settings, the Chronicle or a dungeon
    if type(State.pageHeader.seal) == "table" then
        State.pageHeader.seal:SetShown(questId ~= nil)
    end
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
    -- Only a quest's page runs up under the fringe: the settings and the Chronicle start below it, with room to
    -- breathe (their first line stood right against the header)
    local overlap = questId == nil and title and -PLAIN_PAGE_GAP or 0
    if title and questId ~= nil and State.pageHeader.hasArt then
        overlap = State.pageHeader.hasFringeApart == true and HEADER_FRINGE or math.floor(height * HEADER_FRINGE_SHARE)
    end
    State.detail.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", State.frame.pageLeft or LIST_WIDTH + 2, -PAGE_TOP - height + overlap)
end

---One piece of the game's art on the header, turned over (flipX, flipY) by its texture coordinates when asked.
---@return Texture? texture nil when this client has no such art
local function addOrnament(header, atlas, width, height, layer, flipX, flipY)
    local info = C_Texture.GetAtlasInfo(atlas)
    if not info then
        return nil
    end
    local texture = header:CreateTexture(nil, layer, nil, 2)
    texture:SetAtlas(atlas)
    texture:SetSize(width, height)
    if (flipX or flipY) and texture.SetTexCoord then
        local left, right, top, bottom = 0, 1, 0, 1 -- (the atlas's own coordinates)
        if flipX then
            left, right = right, left
        end
        if flipY then
            top, bottom = bottom, top
        end
        texture:SetTexCoord(left, right, top, bottom)
    end
    return texture
end

---The header's flair, all the game's own art, on its lower edge where it never covers the title, the facts, the
---narration's buttons or the chain's badge: a small gold filigree in the middle of the line between the wood and the
---parchment, gold flourishes in both lower corners (the game's parchment popups' corner, turned over), and the
---player's faction's wax seal pressed over the right corner, as on an order sealed by the quest giver. Drawn once.
addHeaderOrnaments = function(header)
    local filigree = addOrnament(header, "banner-smallfiligree", 61, 19, "ARTWORK")
    if filigree then
        filigree:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)
    end
    local leftCorner = addOrnament(header, "parchmentpopup-filigree", HEADER_CORNER[1], HEADER_CORNER[2], "ARTWORK", false, true)
    if leftCorner then
        leftCorner:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 1, HEADER_FRINGE - 2)
    end
    local rightCorner = addOrnament(header, "parchmentpopup-filigree", HEADER_CORNER[1], HEADER_CORNER[2], "ARTWORK", true, true)
    if rightCorner then
        rightCorner:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -1, HEADER_FRINGE - 2)
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local seal = faction == "Horde" and "quest-horde-waxseal" or faction == "Alliance" and "quest-alliance-waxseal" or nil
    header.seal = seal and addOrnament(header, seal, 50, 47, "OVERLAY")
    if header.seal then
        header.seal:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, -22) -- (over the right flourish's end, half on the page)
    end
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
        -- Its left 5 texels are a darker rim, which the game's own frame covers; here it stood beside the divider as
        -- a second edge, the top's light line starting a little off it. Trimmed, the art meets the divider
        -- (Coordinates given after an atlas are the atlas's own, 0 to 1 across it, as the game's own tabs turn theirs
        -- over with 0, 1, 1, 0: not the whole file's)
        local info = C_Texture.GetAtlasInfo("questlog-reward-top-frame")
        if info.width and info.width > 0 and info.height and info.height > HEADER_FRINGE and fill.SetTexCoord then
            -- Its last texels are a soft shadow over the page: drawn apart, always its own height, so a tall header
            -- (a long title, the narration's row) stretches the wood alone, and the shadow does not grow over the
            -- page's first lines
            local left, fringeTop = HEADER_ART_RIM / info.width, 1 - HEADER_FRINGE / info.height
            fill:SetTexCoord(left, 1, 0, fringeTop)
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            fill:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, HEADER_FRINGE)
            local fringe = header:CreateTexture(nil, "BACKGROUND")
            fringe:SetAtlas("questlog-reward-top-frame")
            fringe:SetTexCoord(left, 1, fringeTop, 1)
            fringe:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            fringe:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
            fringe:SetHeight(HEADER_FRINGE)
            header.hasFringeApart = true
        end
        addHeaderOrnaments(header)
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
        local canFocus = header.questId and ns.QuestState.getQuest(header.questId)
        if ns.Gamepad and ns.Gamepad.isGamepadUI() and GameTooltip_AddLineWithInputIcon and GAMEPAD_FACE_BOTTOM then
            -- The gamepad's cursor on the title: its buttons, with their icons, as the game's own map pins say them
            GameTooltip_AddLineWithInputIcon(GameTooltip, ns.L("Share to chat"), GREEN_FONT_COLOR, GAMEPAD_FACE_BOTTOM)
            if canFocus then
                GameTooltip_AddLineWithInputIcon(GameTooltip, CONTEXT_ACTION_LABEL_FOCUS or ns.L("Focus"), GREEN_FONT_COLOR, GAMEPAD_FACE_LEFT)
            end
        else
            GameTooltip:AddLine(ns.L("Shift-click to link it in chat"), 0.6, 0.6, 0.6)
            if canFocus then
                GameTooltip:AddLine(ns.L("Ctrl-click to focus it"), 0.6, 0.6, 0.6)
            end
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

-- "Need a hint?": the page's button, and the ladder it opens (the tracker opens the same one, Log.showHintLadder)

local HINT_GLOW_OUTER, HINT_GLOW_INNER = { 1, 0.82, 0.2, 0.22 }, { 1, 0.82, 0.2, 0.38 }

function Spoiled.openHintLadder(data)
    Log.showHintLadder(data.questId, data.button)
end

---The page's "Need a hint?" button, at the right: while a hint could show more of the quest. When it offers itself
---(Spoilers: hints "offered", stuck a while in the quest's zone) a soft gold glow round it.
---@return number y Below it
function Spoiled.addHintButton(y, questId)
    local text = ns.L("Need a hint?")
    local right = State.detail.width - PADDING
    if ns.Spoilers.isHintOffered(questId) then
        local width = #text * 6.5 + 18 -- (as addPaperButton measures it)
        State.detail:addRect(right - width - 5, y - 5, width + 10, 30, HINT_GLOW_OUTER, 2)
        State.detail:addRect(right - width - 2, y - 2, width + 4, 24, HINT_GLOW_INNER, 3)
    end
    local data = { questId = questId }
    local _, button = addPaperButton(State.detail, right, y, text, Spoiled.openHintLadder, data)
    data.button = button
    return y + 32
end

do
    local LADDER_WIDTH, STEP_HEIGHT, LADDER_TOP = 290, 42, 46
    local LADDER_EDGE, LADDER_BACK = { 0.42, 0.29, 0.13 }, { 0.03, 0.02, 0.01, 0.96 }
    local STEP_WORDS = {
        { title = "Which zone", note = "The zone its objectives are in" },
        { title = "Roughly where", note = "An area on the map, and where to hand it in" },
        { title = "Exactly where, and who drops it", note = "Every spawn, with chances" },
    }
    local DONE_COLOR, NEXT_COLOR, LATER_COLOR = { 0.85, 0.81, 0.66 }, { 1, 0.82, 0 }, { 0.5, 0.48, 0.44 }
    local ladder -- made the first time it opens

    local function setColor(text, color)
        text:SetTextColor(color[1], color[2], color[3])
    end

    ---Fills the ladder for its quest: each step done (a tick), the next (an arrow, to click), the later ones greyed.
    local function fillLadder()
        if not ladder or not ladder:IsShown() then
            return
        end
        local questId = ladder.questId
        local step = ns.Spoilers.getHint(questId)
        ladder.title:SetText(ns.L("Need a hint?"))
        ladder.questName:SetText(ns.QuestText.getQuestName(questId) or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId)) or ("Quest " .. questId))
        for index, words in ipairs(STEP_WORDS) do
            local row = ladder.rows[index]
            local isDone, isNext = index <= step, index == step + 1
            row.title:SetText(index .. DOT .. ns.L(words.title))
            local note = ns.L(words.note)
            if index == 1 and isDone then
                -- The first step's answer: the zone of the quest's next step
                local entry = ns.QuestState.isInLog(questId) and ns.Model.composeEntry(questId, ns.Model.getPlayer())
                note = entry and entry.zoneId and ns.Database.getZoneName(entry.zoneId) or ns.L("Unknown location")
            end
            row.note:SetText(note)
            setColor(row.title, isDone and DONE_COLOR or isNext and NEXT_COLOR or LATER_COLOR)
            setColor(row.note, isDone and DONE_COLOR or isNext and COLORS.white or LATER_COLOR)
            if isDone then
                row.mark:SetTexture(READY_ICON)
                row.mark:SetVertexColor(1, 1, 1)
                row.mark:SetSize(14, 14)
            elseif isNext then
                row.mark:SetTexture(MEDIA .. "ChevronRight")
                row.mark:SetVertexColor(NEXT_COLOR[1], NEXT_COLOR[2], NEXT_COLOR[3])
                row.mark:SetSize(12, 12)
            else
                row.mark:SetTexture("Interface\\Buttons\\WHITE8X8")
                row.mark:SetVertexColor(LATER_COLOR[1], LATER_COLOR[2], LATER_COLOR[3])
                row.mark:SetSize(4, 4)
            end
            row.isNext = isNext and ns.Spoilers.canHint(questId)
            row.hover:SetShown(row.isNext)
        end
        ladder.footnote:SetText(ns.L("A hint stays for this quest only. The Chronicle counts quests done with no hints."))
        local footHeight = ladder.footnote:GetStringHeight()
        ladder:SetHeight(LADDER_TOP + #STEP_WORDS * STEP_HEIGHT + 8 + (type(footHeight) == "number" and footHeight or 24) + 12)
    end

    local function createLadder()
        ladder = CreateFrame("Frame", "OneMoreQuestHintLadder", UIParent, "BackdropTemplate")
        ladder:SetWidth(LADDER_WIDTH)
        ladder:SetFrameStrata("FULLSCREEN_DIALOG") -- over the map and the quest window beside it
        ladder:SetToplevel(true)
        ladder:SetClampedToScreen(true)
        ladder:EnableMouse(true)
        ladder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        ladder:SetBackdropColor(LADDER_BACK[1], LADDER_BACK[2], LADDER_BACK[3], LADDER_BACK[4])
        ladder:SetBackdropBorderColor(LADDER_EDGE[1], LADDER_EDGE[2], LADDER_EDGE[3], 1)
        ladder.title = ns.Widgets.createFontString(ladder, "OVERLAY", "GameFontNormal")
        ladder.title:SetPoint("TOPLEFT", ladder, "TOPLEFT", 12, -10)
        ladder.questName = ns.Widgets.createFontString(ladder, "OVERLAY", "GameFontHighlightSmall")
        ladder.questName:SetPoint("TOPLEFT", ladder.title, "BOTTOMLEFT", 0, -3)
        ladder.questName:SetPoint("RIGHT", ladder, "RIGHT", -28, 0)
        ladder.questName:SetJustifyH("LEFT")
        ladder.questName:SetWordWrap(false)
        setColor(ladder.questName, DONE_COLOR)
        -- The flat cross the quest window's drawn parts use, lit on hover
        local close = CreateFrame("Button", nil, ladder)
        close:SetSize(14, 14)
        close:SetPoint("TOPRIGHT", ladder, "TOPRIGHT", -8, -8)
        local crossFile = MEDIA .. "Close"
        local cross = close:CreateTexture(nil, "ARTWORK")
        cross:SetAllPoints(close)
        cross:SetTexture(crossFile)
        cross:SetVertexColor(0.85, 0.85, 0.85)
        local lit = close:CreateTexture(nil, "HIGHLIGHT")
        lit:SetAllPoints(close)
        lit:SetTexture(crossFile)
        lit:SetBlendMode("ADD")
        lit:SetAlpha(0.5)
        close:SetScript("OnClick", function() ladder:Hide() end)
        ladder.rows = {}
        for index = 1, #STEP_WORDS do
            local row = CreateFrame("Button", nil, ladder)
            row:SetPoint("TOPLEFT", ladder, "TOPLEFT", 1, -LADDER_TOP - (index - 1) * STEP_HEIGHT)
            row:SetPoint("RIGHT", ladder, "RIGHT", -1, 0)
            row:SetHeight(STEP_HEIGHT)
            row.hover = row:CreateTexture(nil, "HIGHLIGHT")
            row.hover:SetAllPoints(row)
            row.hover:SetColorTexture(1, 0.82, 0.2, 0.1)
            row.mark = row:CreateTexture(nil, "ARTWORK")
            row.mark:SetPoint("CENTER", row, "TOPLEFT", 19, -14)
            row.title = ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlight")
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -6)
            row.note = ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlightSmall")
            row.note:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
            for _, text in ipairs({ row.title, row.note }) do
                text:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                text:SetJustifyH("LEFT")
                text:SetWordWrap(false)
            end
            -- Only the next step takes a click: one step at a time
            row:SetScript("OnClick", function(self)
                if self.isNext then
                    ns.Spoilers.giveHint(ladder.questId)
                end
            end)
            ladder.rows[index] = row
        end
        ladder.footnote = ns.Widgets.createFontString(ladder, "OVERLAY", "GameFontHighlightSmall")
        ladder.footnote:SetPoint("TOPLEFT", ladder, "TOPLEFT", 12, -LADDER_TOP - #STEP_WORDS * STEP_HEIGHT - 8)
        ladder.footnote:SetPoint("RIGHT", ladder, "RIGHT", -12, 0)
        ladder.footnote:SetJustifyH("LEFT")
        ladder.footnote:SetWordWrap(true)
        setColor(ladder.footnote, LATER_COLOR)
        ladder:Hide()
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "OneMoreQuestHintLadder") -- Escape closes it, as the game's own windows
        end
    end

    ---Opens "Need a hint?" for a quest, the ladder of three steps: the zone, roughly where, exactly where. The
    ---page's button and the tracker open it; under what opened it, else in the middle of the screen. Opened again
    ---for the same quest, it closes.
    ---@param anchorFrame table? What it opens under
    function Log.showHintLadder(questId, anchorFrame)
        if not questId or not CreateFrame or not UIParent then
            return
        end
        if not ladder then
            createLadder()
        end
        if ladder:IsShown() and ladder.questId == questId and ladder.anchorFrame == anchorFrame then
            ladder:Hide()
            return
        end
        ladder.questId, ladder.anchorFrame = questId, anchorFrame
        ladder:ClearAllPoints()
        -- Where it opens is fixed on the screen: the page's buttons are reused once it is drawn again
        local right, bottom = anchorFrame and anchorFrame.GetRight and anchorFrame:GetRight(), anchorFrame and anchorFrame.GetBottom and anchorFrame:GetBottom()
        local scale = type(right) == "number" and anchorFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if type(right) == "number" and type(bottom) == "number" and type(scale) == "number" then
            ladder:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * scale, bottom * scale - 4)
        else
            ladder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        ladder:Show()
        fillLadder()
    end

    ---@return table? ladder The ladder's frame, for the tests
    function Log.getHintLadder()
        return ladder
    end

    ns.on("SPOILERS_CHANGED", fillLadder) -- a step taken (here or in the tracker), a choice changed
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
    local view = Spoiled.compose(entry.questId) -- (nil in Guide)
    Spoiled.view = view
    local details = composeObjectiveDetails(entry)
    local group = ns.QuestState.getGroupInfo(entry.questId)
    local before = Log.formatLevelRange(entry.questId, entry.level, group ~= nil) .. DOT
    local zoneName = ns.Database.getZoneName(entry.zoneId)
    local factsText = before .. zoneName
    local zoneLink = { before = before, text = zoneName, handleClick = ns.MapDock.showQuest, data = entry }
    if view and ns.Model.isWhereHidden(entry) then
        -- Where its next step is, its zone too, is held back: the facts leave the zone out, as the list's heading does
        factsText, zoneLink = before:gsub("%s*\194\183%s*$", ""), nil
    end
    if group then
        factsText = factsText .. DOT .. ns.Widgets.formatGroup(group) .. " " .. group.kindText
    end
    local isChainShown = not view or view.chains ~= "hidden"
    setPageHeader(entry.title, factsText, isChainShown and entry.chainIndex or nil, entry.chainTotal, zoneLink, entry.questId)
    local y = 12
    local rewardsExtraHeight = setPageRewards((not view or view.rewards ~= "hidden") and entry.questId or nil)
    y = addQuestItem(y, entry)
    y = addToDo(y, entry, details)
    if view and ns.Spoilers.canHint(entry.questId) then
        y = Spoiled.addHintButton(y - 4, entry.questId) + 4
    end
    -- The party, a part that folds as the ones below it do; its note says how many of them are on the quest
    local partyMembers = ns.Party.getMembers(entry.questId)
    if #partyMembers > 0 then
        local onQuestCount = 0
        for _, member in ipairs(partyMembers) do
            onQuestCount = onQuestCount + (member.isOnQuest and 1 or 0)
        end
        local isPartyOpen
        y, isPartyOpen = addFold(y, "party", entry.questId, ns.L("Party"), ns.L("%d of %d on it", onQuestCount, #partyMembers), true)
        if isPartyOpen and ns.Gamepad.isGamepadUI() then
            -- With a controller: a row a member, its words saying where they are with the quest, for the cursor to
            -- stop on (the faces' hover is out of the pad's reach)
            local members = ns.Party.getProgress(entry.questId, entry.objectives, entry.eventText ~= nil and not entry.isTurnIn)
            y = QuestPage.addPartyRows(y, entry, members) + 6
        elseif isPartyOpen then
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
    if entry.chainIndex and isChainShown then
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

    -- The zone's summary counts the quests to pick up: not while the Spoilers choice names only some of them
    local isPickupAll = List.getPickupChoice() == "all"
    local isSpoiling = ns.Spoilers.isActive()
    local summary = ns.Availability.getZoneSummary(group.zoneId)
    if not isPickupAll then
        summary = { done = 0, inLog = 0, available = 0, notYet = 0 }
    end
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
            if isSpoiling and not ns.Model.isTurnInShown(entry.questId) then
                place = nil -- (where to hand it in is held back: the name alone)
            end
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
    local view = Spoiled.compose(quest.questId) -- (nil in Guide)
    Spoiled.view = view
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
    if quest.finisherPlace and (not view or view.isTurnInShown) then
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
    local isChainShown = not view or view.chains ~= "hidden"
    setPageHeader(quest.title, table.concat(facts, DOT), isChainShown and quest.chainIndex or nil, quest.chainTotal, zoneLink, quest.questId)
    local y = 12

    local warnings, warningLinks = ns.Warnings.getQuestWarnings(quest.questId)
    local linkByWarning = {}
    for index, link in pairs(warningLinks or {}) do
        linkByWarning[warnings[index]] = link
    end
    if quest.availableAtLevel then
        table.insert(warnings, 1, ns.L("Available at level %d", quest.availableAtLevel))
    elseif quest.blocker then
        table.insert(warnings, 1, ns.L("Not yet: %s", (ns.Availability.getShownReason(quest.blocker):gsub("^%u", string.lower))))
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
    local rewardsExtraHeight = setPageRewards((not view or view.rewards ~= "hidden") and quest.questId or nil)

    -- Steps done back to back are one thing to do, from the start to the last reward: "How it goes"
    y = addHeading(y, ns.L(#instantStepIds > 0 and "How it goes" or "How to start"))
    local place = quest.nearestPlace or quest.places[1]
    local steps = {}
    -- (Spoilers: who drops a starting item is named with names or chances, or once it dropped for the player)
    local isSourceNamed = not view or not view.isChanceHidden or view.drops == "names"
        or (view.drops == "found" and quest.itemId ~= nil and ns.Spoilers.hasSeenDrop(quest.itemId))
    if quest.startType == "item" then
        local source = quest.starterName and isSourceNamed and ns.L("Drops from %s", quest.starterName) or ns.L("Found")
        local sourcePlace = not quest.isHandedInHere and place or nil
        local isInInstance = quest.isHandedInHere or (sourcePlace and sourcePlace.x < 0)
        -- Where it drops, as one phrase with its zone when that is known
        local sourceText = source
        if quest.sourceZoneName then
            sourceText = quest.starterName and isSourceNamed and ns.L("Drops from %s in %s", quest.starterName, quest.sourceZoneName)
                or ns.L("Found in %s", quest.sourceZoneName)
        end
        steps[1] = { title = ns.L(quest.isItemInBags and "Use %s" or "Loot %s", quest.itemName), lines = {
            quest.isItemInBags and ns.L("It is in your bags; using it starts the quest") or sourceText,
        } }
        local dropZones = not quest.isItemInBags and quest.itemId and ns.Drops.getZones(quest.itemId) or {}
        if #dropZones > 0 then
            steps[1].lines = composeDropZoneLines(dropZones, "available:" .. quest.questId, {
                handleClick = showDropZone, quest = quest, itemId = quest.itemId,
                view = view and { drops = view.drops, isChanceHidden = view.isChanceHidden },
            })
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
    -- (not where the Spoilers choice keeps the story back: the lead-ins would name it)
    if quest.blocker and quest.blocker.kind == "quest" and not (view and view.isStoryHidden) then
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
        if view and not view.isTurnInShown then
            -- Where to hand it in is held back: the name alone; "once you met them" says they are not met yet
            finisherPlace = nil
            lines[1] = view.turnIn == "met" and ns.L("Not met yet") or nil
        end
        if finisherPlace then
            lines[1] = composePlaceLine(finisherPlace, { suffix = ns.L(finisherPlace.groupZoneId == zoneId and "in this location" or "not in this location") })
        end
        if #instantStepIds > 0 then
            -- What to bring before handing in: each item it asks for, and who drops it
            local objectives = ns.Database.getQuestField(quest.questId, "objectives") or {}
            for _, item in ipairs(objectives[3] or {}) do
                local source = ns.Drops.getHuntedSource(item[1])
                if view and view.isChanceHidden and not (view.drops == "names" or (view.drops == "found" and ns.Spoilers.hasSeenDrop(item[1]))) then
                    source = nil -- (who drops it is held back)
                end
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
    if blocker and blocker.kind == "quest" and view and view.isStoryHidden then
        -- The quest to do first is held back by the Spoilers choice: only that it is later in the story
        State.detail:addDot(PADDING + 2, y + 2, 10, COLORS.warning, 0)
        y = addBody(y, ns.Availability.getShownReason(blocker), COLORS.warning, 22)
    elseif blocker and blocker.kind == "quest" then
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
    if quest.chainIndex and isChainShown then
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
    -- With a controller, B does it: its icon before the words, as the page's own way back says it
    button:SetText(ns.Gamepad.isGamepadUI() and (ns.Log.getPadIconMarkup(GAMEPAD_FACE_RIGHT, 16) .. text) or text)
    button.handleClick = handleClick
    button:Show()
end
QuestPage.setPageRewards = setPageRewards
