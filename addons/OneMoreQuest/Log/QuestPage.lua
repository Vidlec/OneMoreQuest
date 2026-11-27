local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: the page on parchment. This file holds what the page's parts share (its headings and body
-- text, paper buttons, links to places, the checkbox look, folds, step lines, the Spoiled view), and three pages: a
-- quest of the log's, a zone's, and the hint while nothing is selected. The page's other parts come after it, each
-- a file of its own: PageHeader, PageRewards, PageChain, PageToDo, PageParty, HintLadder and AvailablePage. Each
-- puts what it shares on QuestPage; a quest of the log's page reads theirs as it is drawn.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local selectQuest = Actions.selectQuest
local COLORS, DOT, ITEM_ICON, MEDIA, PADDING, PAPER_FILL, SELECTED_EDGE =
    Style.COLORS, Style.DOT, Style.ITEM_ICON, Style.MEDIA, Style.PADDING, Style.PAPER_FILL, Style.SELECTED_EDGE

-- What the Spoilers choices let a quest's page tell (ns.Spoilers), worked out once as the page is drawn
-- (Spoiled.compose): Spoiled.view is nil in Guide, where everything is told as ever and nothing below asks again.
-- One table, so the page's functions keep their names few.
local Spoiled = {}

-- The selected quest on parchment

---@return number y Below the heading
local function addHeading(y, text)
    local height =
        State.detail:addText(text, PADDING, y, { font = "QuestFont_Large", color = COLORS.ink, isSingleLine = true })
    return y + height + 6
end

---@return number y Below the text
local function addBody(y, text, color, indent)
    local height = State.detail:addText(text, PADDING + (indent or 0), y, {
        font = "QuestFont",
        color = color or COLORS.ink,
        width = State.detail.width - 2 * PADDING - (indent or 0),
    })
    return y + height + 4
end

---@param subLines string[] Short lines under the title
---@return number y Below the title block
local function addTitle(y, title, subLines)
    local width = State.detail.width - 2 * PADDING
    local height =
        State.detail:addText(title, PADDING, y, { font = "QuestFont_Huge", color = COLORS.ink, width = width })
    y = y + height + 3
    for _, line in ipairs(subLines) do
        height = State.detail:addText(
            line,
            PADDING,
            y,
            { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width }
        )
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
    canvas:addText(
        text,
        x,
        y + 4,
        { font = "GameFontHighlightSmall", color = COLORS.ink, width = width, justify = "CENTER", isSingleLine = true }
    )
    local button = canvas:addButton(x, y, width, 20, handleClick, data)
    return width, button
end

---Turns the map to a place named on the page, the place in the middle when the map is zoomed in. The
---Available tab keeps its list and its selected quest meanwhile.
---@param target { place: table }
local function showPlace(target)
    local place = target.place
    Actions.showPlaceOnMap(place.mapZoneId or place.groupZoneId, place)
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
        text = prefix,
        link = place.x >= 0 and string.format("%s %d, %d", zoneName, place.x, place.y) or zoneName,
        afterText = #after > 0 and (DOT:gsub("^ ", "") .. table.concat(after, DOT)) or nil,
        handleClick = options.handleClick or showPlace,
        data = options.data or { place = place },
    }
end

local TO_DO_LEAD = 26 -- the checkbox or turn-in mark in front of each line
local CHECKBOX_SIZE = 22
-- Forever's own checkbox, as its professions window has it: a small dark square with a fine rim, a gold tick
local CHECKBOX_IMAGE, CHECKBOX_TICK = { atlas = "checkbox-minimal" }, { atlas = "checkmark-minimal" }

local function hideTooltip()
    GameTooltip:Hide()
end

---Sets a texture to one of the game's own pieces of art, when this client has it.
---@return boolean isSet
local function setAtlasIfKnown(texture, atlas)
    if texture.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        ns.Widgets.setAtlas(texture, atlas)
        return true
    end
    return false
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
    local _, titleWidth = State.detail:addText(
        title,
        PADDING + 17,
        y + 6,
        { font = "QuestFont_Large", color = COLORS.ink, isSingleLine = true }
    )
    if noteText then
        State.detail:addText(noteText, PADDING + width - 90, y + 9, {
            font = "GameFontHighlightSmall",
            color = COLORS.softInk,
            width = 90,
            justify = "RIGHT",
            isSingleLine = true,
        })
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

---One line of text in a quest page's lists: plain text; or text after a coloured dot (a creature, in the colour of
---its spawn points on the map); or text with a place name in it to click, underlined as links are.
---@param line string|{ text: string?, dotColor: number[]?, link: string?, afterText: string?, handleClick: function?, data: any?, font: string?, color: number[]? }
---@return number height
local function addStepLine(y, line, textLeft, textWidth)
    local options = {
        font = type(line) == "table" and line.font or "QuestFont",
        color = type(line) == "table" and line.color or COLORS.softInk,
        width = textWidth,
    }
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
        local linkHeight, linkWidth, linkText = State.detail:addText(
            line.link,
            linkLeft,
            linkTop,
            { font = options.font, color = COLORS.brown, isSingleLine = true }
        )
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
            local afterHeight, afterWidth, afterText = State.detail:addText(
                line.afterText,
                afterLeft,
                afterTop,
                { font = options.font, color = options.color, isSingleLine = true }
            )
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

---Numbered-looking steps joined by a line: the first is the one to do now.
---@param steps { title: string, lines: (string|table)[] }[] A line is a text, or a table as addStepLine takes
---@return number y Below the steps
local function addSteps(y, steps)
    local textLeft = PADDING + 32
    local textWidth = State.detail.width - PADDING - textLeft
    for stepIndex, step in ipairs(steps) do
        local top = y
        local height = State.detail:addText(
            step.title,
            textLeft,
            y + 2,
            { font = "QuestFont", color = COLORS.ink, width = textWidth }
        )
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

-- The Spoilers choices on the page (Spoiled.view). Each is asked only while something is held back.

---@return table? view What the page may tell of the quest; nil in Guide
function Spoiled.compose(questId)
    if not ns.Spoilers.isActive() then
        return nil
    end
    local get = ns.Spoilers.get
    local view = {
        objectives = get("objectives", questId),
        drops = get("drops", questId),
        turnIn = get("turnIn", questId),
        chains = get("chains", questId),
        rewards = get("rewards", questId),
        hint = ns.Spoilers.getHint(questId),
        isTurnInShown = ns.Model.isTurnInShown(questId),
        isStoryHidden = ns.Availability.isLaterHidden("quest"),
        isDungeonHidden = ns.Availability.isLaterHidden("dungeon"),
    }
    view.isChanceHidden = view.drops ~= "chances"
    view.isRough = view.objectives == "rough"
    view.areZonesHidden = view.objectives == "found" or view.objectives == "hidden"
    return view
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
    State.detail:addText(
        ns.L("QUEST ITEM"),
        PADDING + 50,
        y + 7,
        { font = "GameFontNormalSmall", color = COLORS.softInk, isSingleLine = true }
    )
    State.detail:addText(
        item.name or ns.L("Quest item"),
        PADDING + 50,
        y + 21,
        { font = "QuestFont", color = COLORS.ink, width = width - 58, isSingleLine = true }
    )
    local note = (item.count and (ns.Lp(item.count, "%d left", "%d left") .. DOT) or "") .. ns.L("use from the tracker")
    State.detail:addText(
        note,
        PADDING + 50,
        y + 37,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width - 58, isSingleLine = true }
    )
    State.detail:addButton(PADDING, y, width, 54, nil, item, showItemTooltip)
    return y + 54 + 16
end

---@return string factsText The line under a log quest's title: its levels, its zone, its group
---@return table? zoneLink The zone in that line, to click (nil while where it is is held back)
local function composeLogFacts(entry, view, group)
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
    return factsText, zoneLink
end

---The quest's page, the things that matter first: what it is, what it gives, what is left to do and where.
---The story and the chain follow, each open unless folded.
---@return number height
local function drawLogQuest(entry)
    local view = Spoiled.compose(entry.questId) -- (nil in Guide)
    Spoiled.view = view
    local details = QuestPage.composeObjectiveDetails(entry)
    local factsText, zoneLink = composeLogFacts(entry, view, ns.QuestState.getGroupInfo(entry.questId))
    local isChainShown = not view or view.chains ~= "hidden"
    QuestPage.setPageHeader(
        entry.title,
        factsText,
        isChainShown and entry.chainIndex or nil,
        entry.chainTotal,
        zoneLink,
        entry.questId
    )
    local y = 12
    local rewardsExtraHeight = QuestPage.setPageRewards((not view or view.rewards ~= "hidden") and entry.questId or nil)
    y = addQuestItem(y, entry)
    y = QuestPage.addToDo(y, entry, details)
    if view and ns.Spoilers.canHint(entry.questId) then
        y = Spoiled.addHintButton(y - 4, entry.questId) + 4
    end
    y = QuestPage.addPartySection(y, entry)
    y = QuestPage.addProfitSection(y, entry.questId)

    local description = ns.QuestState.getDescription(entry.questId)
    if description then
        local isOpen
        y, isOpen = addFold(y, "story", entry.questId, ns.L("Story"), nil, true)
        if isOpen then
            y = addBody(y, description) + 10
        end
    end
    y = QuestPage.addChainSection(y, entry, isChainShown)
    y = QuestPage.addLinksAndDiagram(y, entry, view, false)
    return y + PADDING + rewardsExtraHeight
end

---A quest on the zone page: its name, and under it where it stands. Click opens the quest.
---@return number y Below the lines
local function addZoneLine(y, entry, noteText)
    local width = State.detail.width - 2 * PADDING
    State.detail:addText(
        string.format("[%d] %s", entry.level, entry.title),
        PADDING,
        y + 2,
        { font = "QuestFont", color = COLORS.ink, width = width, isSingleLine = true }
    )
    State.detail:addText(
        noteText,
        PADDING,
        y + 18,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width, isSingleLine = true }
    )
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
        text = (open.shownLabel or open.label)
            .. (open.required > 1 and string.format(" %d/%d", open.fulfilled, open.required) or "")
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
        y = addBody(
            y,
            ns.L(
                "Quests that start here: %d done, %d in your log, %d available, %d not yet",
                summary.done,
                summary.inLog,
                summary.available,
                summary.notYet
            ),
            COLORS.softInk
        ) + 12
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
            y = addZoneLine(
                y,
                entry,
                (entry.finisherName or ns.L("Turn in"))
                    .. (place and place.x >= 0 and string.format("%s%d, %d", DOT, place.x, place.y) or "")
            )
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
        local text = ns.Lp(
            summary.available,
            "%d more quest can be picked up in %s",
            "%d more quests can be picked up in %s",
            group.zoneName
        )
        local textHeight = State.detail:addText(
            text,
            PADDING + 10,
            y + 8,
            { font = "QuestFont", color = COLORS.ink, width = width - 20 }
        )
        local height = textHeight + 42
        State.detail:addRect(PADDING, y, width, height, COLORS.softInk)
        State.detail:addRect(PADDING + 1, y + 1, width - 2, height - 2, PAPER_FILL, 1)
        addPaperButton(
            State.detail,
            PADDING + 10 + 102,
            y + textHeight + 14,
            ns.L("See available"),
            Log.showZone,
            group.zoneId
        )
        y = y + height + 12
    end
    return y + PADDING
end

local pageHint = "" -- the words drawHintPage puts on the page, read by its one drawing function

local function drawPageHint()
    State.detail:addText(
        pageHint,
        PADDING,
        PADDING,
        { font = "QuestFont", color = COLORS.softInk, width = State.detail.width - 2 * PADDING }
    )
    return 80
end

---The page while no quest is selected: a line on what selecting one does (empty with nothing to select).
---@param hint string
function QuestPage.drawHintPage(hint)
    pageHint = hint
    State.frame.finishPage(drawPageHint)
end

-- Shared with the other parts of the window
QuestPage.Spoiled = Spoiled
QuestPage.CHECKBOX_IMAGE = CHECKBOX_IMAGE
QuestPage.CHECKBOX_SIZE = CHECKBOX_SIZE
QuestPage.CHECKBOX_TICK = CHECKBOX_TICK
QuestPage.TO_DO_LEAD = TO_DO_LEAD
QuestPage.addBody = addBody
QuestPage.addFold = addFold
QuestPage.addHeading = addHeading
QuestPage.addPaperButton = addPaperButton
QuestPage.addStepLine = addStepLine
QuestPage.addSteps = addSteps
QuestPage.composePlaceLine = composePlaceLine
QuestPage.composeProgress = composeProgress
QuestPage.drawLogQuest = drawLogQuest
QuestPage.drawZonePage = drawZonePage
QuestPage.hideTooltip = hideTooltip
QuestPage.setAtlasIfKnown = setAtlasIfKnown
QuestPage.showPlace = showPlace
