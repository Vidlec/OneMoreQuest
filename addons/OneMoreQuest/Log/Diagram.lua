local addonName, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest diagram: a quest among every quest around it, in a window of its own opened from the quest's page, in
-- the quest window's look (the game's frame, the dark book of the list, the parchment page). On the left the tree,
-- from top to bottom: what the quest needs first and what those need, the quest itself, what it opens and what
-- those open, a box each, joined by lines (Chain.getDiagram). On the right the page of the quest clicked in the
-- tree: the quest window's own page, drawn by the same code (QuestPage), with its header and rewards.
-- A tree larger than its pane is drawn smaller, down to FIT_SCALE; past that it scrolls both ways: the wheel up and
-- down, Shift and the wheel sideways, a drag any way. Ctrl and the wheel, or the buttons over the tree, draw it
-- larger or smaller (Diagram.zoom). Made the first time it opens; drawn again while it is open.
local Diagram = ns.LogDiagram
local Log = ns.Log
local Style, State, QuestPage = ns.LogStyle, ns.LogState, ns.LogQuestPage

local MEDIA, COLORS, DOT, READY_ICON = Style.MEDIA, Style.COLORS, Style.DOT, Style.READY_ICON
local BAR_HEIGHT, PAGE_CONTENT_WIDTH = Style.BAR_HEIGHT, Style.PAGE_CONTENT_WIDTH
local SCROLL_BAR_WIDTH = ns.Widgets.SCROLL_BAR_WIDTH
local STRIP_HEIGHT, INSET = 21, 3 -- the game's window frame: its title strip, and how far its edge reaches in
-- The window's usual size (the tree's width beside the page, and the height), and how small and large its grip
-- makes it; the size the player dragged it to is kept (settings.diagramTreeWidth, diagramHeight)
local TREE_WIDTH, HEIGHT = 760, 640
local MIN_TREE_WIDTH, MAX_TREE_WIDTH, MIN_HEIGHT, MAX_HEIGHT = 360, 1800, 360, 1300
local PAGE_WIDTH = PAGE_CONTENT_WIDTH + SCROLL_BAR_WIDTH
local CAPTION_HEIGHT = 30 -- the line over the tree: how many quests, and how to move around
local NODE_WIDTH, NODE_HEIGHT, SLOT_GAP, LEVEL_GAP, PADDING = 156, 30, 14, 36, 18
local WRAP_FROM, WRAP_ACROSS, WRAP_GAP = 5, 3, 18 -- so many quests with nothing beyond them stand in rows of three
local FIT_SCALE = 0.8 -- a tree a little too large for its pane is drawn smaller, this much at most; a larger one scrolls
local LINE = { 0.62, 0.5, 0.24 }
local NODE_FILL, NODE_EDGE = { 0.15, 0.11, 0.065 }, { 0.4, 0.31, 0.19 }
local DONE_TEXT, LATER_TEXT = { 0.6, 0.6, 0.6 }, { 0.72, 0.68, 0.55 }
local ACTIVE_ICON = "Interface\\GossipFrame\\ActiveQuestIcon"

local window -- made the first time it opens
local createSizeGrip -- (below)

---@return string state Where the character stands with a quest: "done", "log" (in the quest log), "open" (to pick up
---now) or "later" (something is still in its way)
local function getState(questId)
    if ns.QuestState.isTurnedIn(questId) then
        return "done"
    elseif ns.QuestState.isInLog(questId) then
        return "log"
    end
    return ns.Availability.isEligible(questId, ns.Availability.getPlayer()) and "open" or "later"
end

local STATE_WORDS = { done = "Done", log = "In your log", open = "To pick up", later = "Not yet" }
local STATE_ORDER = { "done", "log", "open", "later" }

---A state's mark, as the lists have them: the green tick, the game's "?" and "!", the "!" greyed for a quest not
---to be had yet.
local function addStateIcon(canvas, x, y, size, state)
    if state == "done" then
        return canvas:addIcon(x, y, size, READY_ICON, nil, 4)
    end
    local icon = canvas:addIcon(x, y, size, state == "log" and ACTIVE_ICON or Style.GIVER_ICON, nil, 4)
    if state == "later" then
        icon:SetDesaturated(true)
        icon:SetAlpha(0.7)
    end
    return icon
end

---Places a side of the tree: every quest a slot of its own unless it has quests further out, which it then stands
---in the middle of.
---Many quests with nothing beyond them (a quest that opens a dozen) do not stand in one long row: they wrap into
---rows of WRAP_ACROSS, one under the other (box.wrapRow), so a wide fan is a block the pane can show.
---@param boxes table[] Filled with { questId, depth, slot, parent, wrapRow?, wrapRows?, wrapSlot? }
---@return number? firstSlot, number? lastSlot The slots the nodes stand in
---@return number nextSlot The first slot still free
local function placeNodes(nodes, depth, step, nextSlot, parent, boxes)
    local firstSlot, lastSlot
    local isAllLeaves = #nodes >= WRAP_FROM
    for _, node in ipairs(nodes) do
        isAllLeaves = isAllLeaves and #node.children == 0
    end
    if isAllLeaves then
        local rowCount = math.ceil(#nodes / WRAP_ACROSS)
        for index, node in ipairs(nodes) do
            boxes[#boxes + 1] = {
                questId = node.questId,
                depth = depth,
                parent = parent,
                slot = nextSlot + (index - 1) % WRAP_ACROSS,
                wrapRow = math.floor((index - 1) / WRAP_ACROSS), -- 0 the row next to the quest they hang on
                wrapRows = rowCount,
                wrapSlot = nextSlot, -- the block's first slot, which its trunk runs beside
            }
        end
        return nextSlot, nextSlot + WRAP_ACROSS - 1, nextSlot + WRAP_ACROSS
    end
    for _, node in ipairs(nodes) do
        local box = { questId = node.questId, depth = depth, parent = parent }
        boxes[#boxes + 1] = box
        if #node.children > 0 then
            local first, last
            first, last, nextSlot = placeNodes(node.children, depth + step, step, nextSlot, box, boxes)
            box.slot = (first + last) / 2
        else
            box.slot, nextSlot = nextSlot, nextSlot + 1
        end
        firstSlot, lastSlot = firstSlot or box.slot, box.slot
    end
    return firstSlot, lastSlot, nextSlot
end

---@return table[] boxes Every quest of the diagram with its depth (0 the quest itself, below it what comes before,
---above it what it opens) and its slot across (which may be half a slot: between the quests it joins)
---@return number slotCount How many slots across the tree is
---@return table diagram Chain.getDiagram's answer
function Diagram.compose(questId)
    local diagram = ns.Chain.getDiagram(questId)
    local boxes = {}
    local this = { questId = questId, depth = 0, isThis = true }
    local beforeFirst, beforeLast, beforeSlots = placeNodes(diagram.before, -1, -1, 0, this, boxes)
    local beforeCount = #boxes
    local afterFirst, afterLast, afterSlots = placeNodes(diagram.after, 1, 1, 0, this, boxes)
    -- The quest itself in the middle of the wider side; the other side moved to be in line with it
    local beforeMiddle = beforeFirst and (beforeFirst + beforeLast) / 2 or 0
    local afterMiddle = afterFirst and (afterFirst + afterLast) / 2 or 0
    this.slot = math.max(beforeMiddle, afterMiddle)
    for index, box in ipairs(boxes) do
        box.slot = box.slot + this.slot - (index <= beforeCount and beforeMiddle or afterMiddle)
    end
    boxes[#boxes + 1] = this
    local slotCount = math.max(beforeSlots + this.slot - beforeMiddle, afterSlots + this.slot - afterMiddle, 1)
    return boxes, slotCount, diagram
end

-- The page: the quest window's own, drawn here. Its code draws on LogState's canvas, header and rewards block, and
-- places them on LogState's frame; for the time of a drawing those are this window's.

---Runs a piece of the quest page's code with the page's parts being the diagram's.
local function withPage(body, ...)
    local page = window.page
    local frame, detail, header, rewards = State.frame, State.detail, State.pageHeader, State.rewardsBlock
    local shownPlace, shownTurnInPlace = State.shownPlace, State.shownTurnInPlace
    State.frame, State.detail, State.pageHeader, State.rewardsBlock = page.host, page.canvas, page.header, page.rewards
    State.isDiagramPage = true
    local isFine, result = pcall(body, ...)
    State.frame, State.detail, State.pageHeader, State.rewardsBlock = frame, detail, header, rewards
    State.shownPlace, State.shownTurnInPlace = shownPlace, shownTurnInPlace
    State.isDiagramPage = nil
    if not isFine then
        error(result, 0)
    end
    return result
end

---@return table? quest The quest as the Available tab lists it (to pick up now, or not yet), nil when it lists it nowhere
local function findAvailableQuest(questId)
    local zoneId = ns.Availability.getStartZoneId(questId)
    if not zoneId then
        return nil
    end
    local options = { shouldShowLowLevel = true }
    for _, quests in ipairs({
        ns.Availability.getQuests(zoneId, options),
        ns.Availability.getBlockedQuests(zoneId, options),
    }) do
        for _, quest in ipairs(quests) do
            if quest.questId == questId then
                return quest, zoneId
            end
        end
    end
    return nil
end

---A quest with no page of its own in the quest window (done, or listed nowhere): what it was, what it asked, and
---the quests around it.
---@return number height
local function drawPlainPage(questId, state)
    local name = ns.QuestText.getQuestName(questId) or ns.L("Quest %s", questId)
    local level = ns.Database.getQuestField(questId, "questLevel") or 0
    local zoneId = ns.Availability.getStartZoneId(questId)
    local facts = Log.formatLevelRange(questId, level, false)
        .. (zoneId and DOT .. ns.Database.getZoneName(zoneId) or "")
    QuestPage.setPageHeader(name, facts, nil, nil, nil, questId)
    QuestPage.setPageRewards(nil)
    local y = 12
    y = QuestPage.addHeading(y, ns.L(STATE_WORDS[state]))
    if state == "done" then
        local entry = ns.ChroniclePage.findEntry(questId)
        y = QuestPage.addBody(
            y,
            entry and entry.turnedInAt and ns.L("Done %s", ns.Chronicle.formatShownDate("%d %b %Y", entry.turnedInAt))
                or ns.L("Done before the chronicle began"),
            COLORS.softInk
        )
    end
    local objectivesText = ns.Database.getQuestField(questId, "objectivesText")
    if type(objectivesText) == "table" and #objectivesText > 0 then
        y = QuestPage.addHeading(y + 10, ns.L("What it asks"))
        y = QuestPage.addBody(y, ns.QuestText.getObjectives(questId, table.concat(objectivesText, " ")))
    end
    local quest = { questId = questId, unlockIds = ns.Chain.getUnlockedQuestIds(questId) }
    quest.chainIndex = ns.Chain.getStep(questId)
    return QuestPage.addLinksAndDiagram(y + 12, quest, nil, false) + 14
end

---Draws the selected quest's page: the quest window's page for a quest in the log or one of the Available tab.
local function drawPage()
    local questId = window.selectedQuestId
    local state = getState(questId)
    local page = window.page
    page.canvas:clear()
    local height
    if state == "log" then
        height = QuestPage.drawLogQuest(ns.Model.composeEntry(questId, ns.Model.getPlayer()))
    else
        local quest, zoneId = nil, nil
        if state ~= "done" then
            quest, zoneId = findAvailableQuest(questId)
        end
        height = quest and QuestPage.drawAvailableQuest(quest, zoneId) or drawPlainPage(questId, state)
    end
    page.canvas:finish(height)
end

---Names the buttons under the page for the selected quest.
local function setBarButtons()
    local isDone = getState(window.selectedQuestId) == "done"
    Log.setButtonText(window.openButton, ns.L(isDone and "Read in the Chronicle" or "Open quest"))
    Log.setButtonText(window.rootButton, ns.L("Diagram from here"))
    window.rootButton:SetShown(window.selectedQuestId ~= window.questId)
end

-- The tree

local function showBoxTooltip(button, box)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local name = ns.QuestText.getQuestName(box.questId) or ns.L("Quest %s", box.questId)
    local level = ns.Database.getQuestField(box.questId, "questLevel") or 0
    ns.QuestTooltip.addTitle(GameTooltip, string.format("[%d] %s", level, name), box.questId)
    GameTooltip:AddLine(ns.L(STATE_WORDS[box.state]), COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
    local previousQuestIds, isAnyEnough = ns.Chain.getPreviousQuestIds(box.questId)
    if #previousQuestIds > 1 then
        GameTooltip:AddLine(
            isAnyEnough and ns.Lp(#previousQuestIds, "Needs any one of %d quest", "Needs any one of %d quests")
                or ns.Lp(#previousQuestIds, "Needs %d quest", "Needs all %d quests"),
            LATER_TEXT[1],
            LATER_TEXT[2],
            LATER_TEXT[3]
        )
    end
    if box.questId ~= window.selectedQuestId then
        GameTooltip:AddLine(ns.L("Click to see its page"), DONE_TEXT[1], DONE_TEXT[2], DONE_TEXT[3])
    end
    GameTooltip:Show()
end

local function hideTooltip()
    GameTooltip:Hide()
end

local function handleBoxClick(box)
    if window.selectedQuestId ~= box.questId then
        window.page.canvas:scrollToTop() -- (another quest's page starts at its top)
    end
    window.selectedQuestId = box.questId
    Diagram.fill()
end

---Where the tree is scrolled to sideways, no further than its edge; the thumb under the tree follows.
local function setSideScroll(scroll)
    local tree = window.tree
    scroll = math.max(0, math.min(scroll or 0, tree.maxSideScroll or 0))
    tree.sideScroll = scroll
    tree.canvas.frame:SetHorizontalScroll(scroll)
    local isScrolling = (tree.maxSideScroll or 0) > 0
    tree.sideThumb:SetShown(isScrolling)
    tree.sideTrack:SetShown(isScrolling)
    if isScrolling then
        local trackWidth = tree.paneWidth - 16
        local thumbWidth = math.max(24, trackWidth * tree.paneWidth / (tree.paneWidth + tree.maxSideScroll))
        tree.sideThumb:SetWidth(thumbWidth)
        tree.sideThumb:SetPoint(
            "LEFT",
            tree.sideTrack,
            "LEFT",
            (trackWidth - thumbWidth) * scroll / tree.maxSideScroll,
            0
        )
    end
end

---Moves the tree by a way across and a way down (a drag, the wheel): Diagram.pan(40, 0) shows what is further right.
function Diagram.pan(across, down)
    local tree = window.tree
    setSideScroll((tree.sideScroll or 0) + across)
    tree.canvas:setScroll(tree.canvas:getScroll() + down)
end

local drawTree -- (below)

local MIN_ZOOM, MAX_ZOOM = 0.5, 1.5

---Draws the tree larger or smaller by a step (Ctrl and the wheel, the caption's buttons), what is in the middle of
---the pane staying there; with no step, back to the size that fits the pane.
---@param step number? 0.1 for a step larger, -0.1 for one smaller; nil to fit
function Diagram.zoom(step)
    local tree = window.tree
    local canvas = tree.canvas
    local oldScale = tree.scale or 1
    local middleX = ((tree.sideScroll or 0) + tree.paneWidth / 2) / oldScale
    local middleY = (canvas:getScroll() + tree.paneHeight / 2) / oldScale
    if step then
        tree.zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, math.floor((oldScale + step) * 10 + 0.5) / 10))
    else
        tree.zoom, window.shouldCentre = nil, true
    end
    drawTree()
    if step then
        tree.sideScroll = middleX * tree.scale - tree.paneWidth / 2
        Diagram.pan(0, 0) -- (no further than the tree's edge)
        canvas:setScroll(middleY * tree.scale - tree.paneHeight / 2)
    end
end

-- Where drawTree puts the tree in its pane, for the functions that draw its parts: the left and top of the tree,
-- and the offset of its highest box
local treeLayout = { left = 0, top = 0, firstOffset = 0 }

---How far down a box stands from the quest itself (up: below zero): a level a depth, and within a wrapped block a
---row further out a row.
local function getOffset(box)
    local side = box.depth < 0 and -1 or 1
    return box.depth * (NODE_HEIGHT + LEVEL_GAP) + side * (box.wrapRow or 0) * (NODE_HEIGHT + WRAP_GAP)
end

---@return number x, number y The box's top left corner on the tree's canvas
local function getBoxPlace(box)
    return treeLayout.left + box.slot * (NODE_WIDTH + SLOT_GAP),
        treeLayout.top + getOffset(box) - treeLayout.firstOffset
end

-- One link being drawn, measured by measureLink for the functions that draw its pieces (one table, reused)
local link = {}

---Measures the line from a box to the quest it hangs on (see addLink) into link.
local function measureLink(box)
    local parent = box.parent
    link.isAfter = box.depth > parent.depth
    local x, y = getBoxPlace(box)
    link.y = y
    link.centre = math.floor(x + NODE_WIDTH / 2)
    local parentX, parentY = getBoxPlace(parent)
    link.parentY = parentY
    link.parentCentre = math.floor(parentX + NODE_WIDTH / 2)
    link.rim = parent.isThis and 3 or 0 -- (the gold frame round the quest itself)
    -- The crossing: the middle of the gap between the parent and the block's nearest row
    local nearY = y - (link.isAfter and 1 or -1) * (box.wrapRow or 0) * (NODE_HEIGHT + WRAP_GAP)
    link.crossY = link.isAfter and math.floor((parentY + NODE_HEIGHT + nearY) / 2)
        or math.floor((nearY + NODE_HEIGHT + parentY) / 2)
    link.trunkX = box.wrapSlot and math.floor(treeLayout.left + box.wrapSlot * (NODE_WIDTH + SLOT_GAP)) - 8
end

---The parent's own stem to the crossing: out of its foot, or into its head at an arrow's point.
local function addParentStem(canvas)
    if link.isAfter then
        local fromY = link.parentY + NODE_HEIGHT + link.rim
        canvas:addRect(link.parentCentre - 1, fromY, 2, link.crossY - fromY + 1, LINE, 1)
        return
    end
    canvas:addRect(link.parentCentre - 1, link.crossY, 2, link.parentY - link.rim - link.crossY - 5, LINE, 1)
    canvas:addIcon(link.parentCentre - 6, link.parentY - link.rim - 11, 12, MEDIA .. "ChevronDown", LINE, 2)
end

---The trunk down (or up) the left side of a wrapped block, from the crossing to its further rows.
local function addTrunk(canvas, box)
    local reach = (box.wrapRows - 1) * (NODE_HEIGHT + WRAP_GAP)
    canvas:addRect(link.trunkX, link.crossY, math.min(link.centre, link.parentCentre) - link.trunkX, 2, LINE, 1)
    if link.isAfter then
        canvas:addRect(link.trunkX, link.crossY, 2, reach + 2, LINE, 1)
    else
        canvas:addRect(link.trunkX, link.crossY - reach, 2, reach + 2, LINE, 1)
    end
end

---A box of a block's first row (or of no block): its stem to the crossing, the line across to the parent's centre;
---once for the parent, its own stem and the trunk of a block with more rows.
local function addFirstRowLink(canvas, box)
    local y, centre, crossY = link.y, link.centre, link.crossY
    if link.isAfter then
        canvas:addRect(centre - 1, crossY, 2, y - crossY - 5, LINE, 1)
        canvas:addIcon(centre - 6, y - 11, 12, MEDIA .. "ChevronDown", LINE, 2)
    else
        canvas:addRect(centre - 1, y + NODE_HEIGHT, 2, crossY - y - NODE_HEIGHT + 1, LINE, 1)
    end
    canvas:addRect(
        math.min(centre, link.parentCentre) - 1,
        crossY,
        math.abs(link.parentCentre - centre) + 2,
        2,
        LINE,
        1
    )
    if box.slot == (box.wrapSlot or box.slot) or centre == link.parentCentre then
        addParentStem(canvas)
    end
    if link.trunkX and box.slot == box.wrapSlot and box.wrapRows > 1 then
        addTrunk(canvas, box)
    end
end

---A further row of a block: from the trunk along the row's own line, then into (or out of) the box.
local function addFurtherRowLink(canvas)
    local y, centre = link.y, link.centre
    local rowY = link.isAfter and y - WRAP_GAP / 2 or y + NODE_HEIGHT + WRAP_GAP / 2
    canvas:addRect(link.trunkX, rowY, centre - link.trunkX + 1, 2, LINE, 1)
    if link.isAfter then
        canvas:addRect(centre - 1, rowY, 2, y - rowY - 5, LINE, 1)
        canvas:addIcon(centre - 6, y - 11, 12, MEDIA .. "ChevronDown", LINE, 2)
    else
        canvas:addRect(centre - 1, y + NODE_HEIGHT, 2, rowY - y - NODE_HEIGHT + 1, LINE, 1)
    end
end

---The line from a box to the quest it hangs on, always from the earlier quest down to the later: out of the
---earlier one's foot, across the gap's middle, into the later one's head at an arrow's point. A wrapped block's
---further rows reach that crossing by a trunk down the block's left side and a line of their own each.
local function addLink(canvas, box)
    measureLink(box)
    if (box.wrapRow or 0) == 0 then
        addFirstRowLink(canvas, box)
    else
        addFurtherRowLink(canvas)
    end
end

local THIS_GROUND = { 0.05, 0.035, 0.02 }
local FILIGREE = { atlas = "banner-smallfiligree" }

---The quest the diagram is of: a gold frame round it, and the game's small filigree over it.
local function addThisFrame(canvas, x, y)
    canvas:addRect(x - 3, y - 3, NODE_WIDTH + 6, NODE_HEIGHT + 6, Style.SELECTED_EDGE, 0)
    canvas:addRect(x - 2, y - 2, NODE_WIDTH + 4, NODE_HEIGHT + 4, THIS_GROUND, 1)
    if ns.LogList.hasGameArt("banner-smallfiligree") then
        canvas:addImage(x + NODE_WIDTH / 2 - 30, y - 15, 61, 19, FILIGREE, nil, nil, 5)
    end
end

---The quest whose page is shown: the game's glow, as on the list's chosen row.
local function addSelectedGlow(canvas, x, y)
    if ns.LogList.hasGameArt("questlog-quest-glow-yellow") then
        canvas:addImage(x - 4, y - 3, NODE_WIDTH + 8, NODE_HEIGHT + 6, ns.LogList.SELECTED_GLOW, nil, nil, 3)
    else
        canvas:addRect(x + 1, y + NODE_HEIGHT - 3, NODE_WIDTH - 2, 2, COLORS.gold, 4)
    end
end

---One quest's box: its frame, its state's mark and its title in the colour of where the character stands with it; a
---click opens its page beside the tree.
local function addBox(canvas, box, x, y)
    local isSelected = box.questId == window.selectedQuestId
    if box.isThis then
        addThisFrame(canvas, x, y)
    end
    canvas:addRect(x, y, NODE_WIDTH, NODE_HEIGHT, box.isThis and Style.SELECTED_EDGE or NODE_EDGE, 2)
    canvas:addRect(x + 1, y + 1, NODE_WIDTH - 2, NODE_HEIGHT - 2, box.isThis and Style.SELECTED_FILL or NODE_FILL, 3)
    if isSelected then
        addSelectedGlow(canvas, x, y)
    end
    addStateIcon(canvas, x + 6, y + 7, 16, box.state)
    local name = ns.QuestText.getQuestName(box.questId) or ns.L("Quest %s", box.questId)
    local level = ns.Database.getQuestField(box.questId, "questLevel") or 0
    local color = box.state == "done" and DONE_TEXT
        or box.state == "later" and LATER_TEXT
        or ns.Widgets.getDifficultyColor(level)
    canvas:addText(string.format("[%d] %s", level, name), x + 26, y + 9, {
        font = "GameFontHighlightSmall",
        color = (box.isThis or isSelected) and COLORS.white or color,
        width = NODE_WIDTH - 32,
        isSingleLine = true,
    })
    box.button = canvas:addButton(x, y, NODE_WIDTH, NODE_HEIGHT, handleBoxClick, box, showBoxTooltip, nil, hideTooltip)
end

---The line over the tree: how many quests there are each way, and how to move around a tree that scrolls.
local function setCaption(boxes, diagram)
    local beforeCount, afterCount = 0, 0
    for _, box in ipairs(boxes) do
        beforeCount, afterCount = beforeCount + (box.depth < 0 and 1 or 0), afterCount + (box.depth > 0 and 1 or 0)
    end
    local parts = {}
    if beforeCount > 0 then
        parts[#parts + 1] = ns.Lp(beforeCount, "%d quest before", "%d quests before")
    end
    if afterCount > 0 then
        parts[#parts + 1] = ns.Lp(afterCount, "%d quest after", "%d quests after")
    end
    window.caption:SetText(table.concat(parts, DOT))
    local tree = window.tree
    local canMove = tree.maxSideScroll > 0 or (tree.canvas.maxScroll or 0) > 0
    local hint = canMove and ns.L("Drag to move; Shift and the wheel go sideways, Ctrl zooms") or ""
    if diagram.isCutBefore or diagram.isCutAfter then
        hint = ns.L("More quests lie further out: Diagram from here on one at the edge")
    end
    window.hint:SetText(hint)
end

---Draws the tree for the window's quest, as large as its pane lets it be (or as the player chose: Diagram.zoom).
drawTree = function()
    local tree = window.tree
    local canvas = tree.canvas
    local boxes, slotCount, diagram = Diagram.compose(window.questId)
    local firstOffset, lastOffset = 0, 0
    for _, box in ipairs(boxes) do
        firstOffset, lastOffset = math.min(firstOffset, getOffset(box)), math.max(lastOffset, getOffset(box))
    end
    local width = slotCount * NODE_WIDTH + (slotCount - 1) * SLOT_GAP + 2 * PADDING
    local height = lastOffset - firstOffset + NODE_HEIGHT + 2 * PADDING
    -- A little too large: drawn smaller, whole. Too large for that to show all of it: full size, and it scrolls
    local paneWidth, paneHeight = tree.paneWidth, tree.paneHeight
    local fit = math.min(1, paneWidth / width, paneHeight / height)
    local scale = tree.zoom or (fit >= FIT_SCALE and fit or 1) -- (tree.zoom: the size the player chose, Diagram.zoom)
    tree.scale = scale
    canvas.content:SetScale(scale)
    canvas:clear()
    -- Smaller than the pane: in its middle
    treeLayout.left = PADDING + math.max(0, (paneWidth / scale - width) / 2)
    treeLayout.top = PADDING + math.max(0, (paneHeight / scale - height) / 2)
    treeLayout.firstOffset = firstOffset
    window.boxes = boxes
    local thisX, thisY = 0, 0
    for _, box in ipairs(boxes) do
        local x, y = getBoxPlace(box)
        box.state = getState(box.questId)
        if box.isThis then
            thisX, thisY = x + NODE_WIDTH / 2, y + NODE_HEIGHT / 2
        end
        addBox(canvas, box, x, y)
        if box.parent then
            addLink(canvas, box)
        end
    end
    canvas.content:SetWidth(width)
    canvas:finish(height * scale)
    tree.maxSideScroll = math.max(0, width * scale - paneWidth)
    window.zoomText:SetText(string.format("%d%%", math.floor(scale * 100 + 0.5)))
    if window.shouldCentre then
        -- As it opens, or turns to another quest: that quest in the middle of the pane
        window.shouldCentre = false
        setSideScroll(thisX * scale - paneWidth / 2)
        canvas:setScroll(thisY * scale - paneHeight / 2)
    else
        setSideScroll(tree.sideScroll)
    end
    setCaption(boxes, diagram)
end

---@return number treeWidth, number height The window's size as the player left it: the tree's width, and the height
local function getSize()
    local settings = ns.settings
    -- (0, or nothing kept: the usual size)
    local savedWidth, savedHeight = tonumber(settings.diagramTreeWidth) or 0, tonumber(settings.diagramHeight) or 0
    local treeWidth = math.floor(savedWidth > 0 and savedWidth or TREE_WIDTH)
    local height = math.floor(savedHeight > 0 and savedHeight or HEIGHT)
    return math.max(MIN_TREE_WIDTH, math.min(MAX_TREE_WIDTH, treeWidth)),
        math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, height))
end

---Gives the window its size and fits its parts to it: the tree's pane takes what the page leaves. A screen too
---small for the size (a large UI scale) has the window drawn smaller, whole.
local function layOut()
    local treeWidth, height = getSize()
    local width = INSET + treeWidth + 2 + PAGE_WIDTH + INSET
    window:SetSize(width, height)
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if type(screenWidth) == "number" and type(screenHeight) == "number" and screenWidth > 0 then
        window:SetScale(math.min(1, (screenWidth - 40) / width, (screenHeight - 60) / (height + STRIP_HEIGHT)))
    end
    local tree = window.tree
    local paneHeight = height - CAPTION_HEIGHT - 1 - BAR_HEIGHT - INSET - 10 -- (10: the sideways thumb's strip)
    tree.canvas:setWidth(treeWidth)
    tree.canvas.frame:SetHeight(paneHeight)
    tree.canvas.height = paneHeight
    tree.paneWidth, tree.paneHeight = tree.canvas.width, paneHeight
    tree.sideTrack:SetSize(tree.paneWidth - 16, 4)
end

---Draws the diagram again: the tree for the window's quest, the page for the selected one.
function Diagram.fill()
    if not window or not window:IsShown() then
        return
    end
    layOut()
    window.title:SetText(ns.L("Quest diagram"))
    drawTree()
    withPage(drawPage)
    setBarButtons()
    for index, state in ipairs(STATE_ORDER) do
        window.legend[index]:SetText(ns.L(STATE_WORDS[state]))
    end
end

---The game's own window frame round the diagram, with its title strip and close button; a drawn gold edge and a
---flat cross where this client lacks them.
local function createChrome()
    local chrome = CreateFrame("Frame", nil, window)
    chrome:SetAllPoints(window)
    chrome:SetFrameLevel((window:GetFrameLevel() or 1) + 42)
    local strip = window:CreateTexture(nil, "BACKGROUND")
    strip:SetColorTexture(Style.BAR_BACKGROUND[1], Style.BAR_BACKGROUND[2], Style.BAR_BACKGROUND[3], 1)
    strip:SetPoint("TOPLEFT", window, "TOPLEFT", INSET, STRIP_HEIGHT - INSET)
    strip:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", -INSET, 0)
    window.title = ns.Widgets.createFontString(chrome, "OVERLAY", "GameFontNormal")
    local close
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        local border = CreateFrame("Frame", nil, window, "NineSlicePanelTemplate")
        border:SetFrameLevel((window:GetFrameLevel() or 1) + 40)
        NineSliceUtil.ApplyLayoutByName(border, "ButtonFrameTemplateNoPortrait")
        border:SetPoint("TOPLEFT", window, "TOPLEFT", 0, STRIP_HEIGHT)
        border:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 0, 0)
        window.title:SetPoint("TOP", border, "TOP", 0, -5)
        local isCreated, button = pcall(CreateFrame, "Button", nil, chrome, "UIPanelCloseButton")
        if isCreated and type(button) == "table" then
            close = button
            close:SetPoint("TOPRIGHT", border, "TOPRIGHT", 1, 0)
        end
    else
        local edge = CreateFrame("Frame", nil, window, "BackdropTemplate")
        edge:SetPoint("TOPLEFT", window, "TOPLEFT", INSET - 1, STRIP_HEIGHT - INSET + 1)
        edge:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -INSET + 1, INSET - 1)
        edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        edge:SetBackdropBorderColor(Style.SELECTED_EDGE[1], Style.SELECTED_EDGE[2], Style.SELECTED_EDGE[3], 0.9)
        window.title:SetPoint("CENTER", window, "TOP", 0, STRIP_HEIGHT / 2 - INSET)
    end
    if not close then
        close = CreateFrame("Button", nil, chrome)
        close:SetSize(16, 16)
        close:SetPoint("RIGHT", window, "TOPRIGHT", -INSET - 5, STRIP_HEIGHT / 2 - INSET)
        for _, layer in ipairs({ "ARTWORK", "HIGHLIGHT" }) do
            local cross = close:CreateTexture(nil, layer)
            cross:SetAllPoints(close)
            cross:SetTexture(MEDIA .. "Close")
            cross:SetVertexColor(0.85, 0.85, 0.85)
        end
    end
    close:SetScript("OnClick", function()
        window:Hide()
    end)
    window.closeButton = close
    -- The title strip moves the window
    local handle = CreateFrame("Frame", nil, window)
    handle:SetFrameLevel((window:GetFrameLevel() or 1) + 41)
    handle:SetPoint("TOPLEFT", window, "TOPLEFT", 0, STRIP_HEIGHT)
    handle:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", 0, 0)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        window:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        window:StopMovingOrSizing()
    end)
    if window.SetHitRectInsets then
        window:SetHitRectInsets(0, 0, -STRIP_HEIGHT, 0)
    end
end

---The tree's pane: the dark book the quest list lies on, a line of words over it, the tree, and under it the bar
---that says what the marks mean.
local function createTreePane()
    local tree = { sideScroll = 0, maxSideScroll = 0 }
    window.tree = tree
    local ground = window:CreateTexture(nil, "BACKGROUND")
    ground:SetColorTexture(Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
    ground:SetPoint("TOPLEFT", window, "TOPLEFT", INSET, 0)
    ground:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -INSET - PAGE_WIDTH - 2, INSET)
    local art = window:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetAllPoints(ground)
    if not QuestPage.setAtlasIfKnown(art, "QuestLog-main-background") then
        art:Hide()
    end
    -- The line of words over the tree, on the list's heading bar
    local captionBar = window:CreateTexture(nil, "BORDER")
    captionBar:SetColorTexture(Style.HEADER_BAR_LOW[1], Style.HEADER_BAR_LOW[2], Style.HEADER_BAR_LOW[3], 0.92)
    captionBar:SetPoint("TOPLEFT", window, "TOPLEFT", INSET, 0)
    captionBar:SetPoint("BOTTOMRIGHT", window, "TOPRIGHT", -INSET - PAGE_WIDTH - 2, -CAPTION_HEIGHT)
    local captionRule = window:CreateTexture(nil, "ARTWORK")
    captionRule:SetColorTexture(COLORS.rule[1], COLORS.rule[2], COLORS.rule[3], 1)
    captionRule:SetPoint("TOPLEFT", captionBar, "BOTTOMLEFT", 0, 0)
    captionRule:SetPoint("BOTTOMRIGHT", captionBar, "BOTTOMRIGHT", 0, -1)
    window.caption = ns.Widgets.createFontString(window, "OVERLAY", "GameFontNormal")
    window.caption:SetPoint("LEFT", captionBar, "LEFT", 12, 0)
    -- At the line's right end: smaller, how large the tree is drawn (a click fits it to the pane again), larger
    local function createZoomButton(texture, step, tooltipText)
        local button = CreateFrame("Button", nil, window)
        button:SetSize(16, 16)
        for _, layer in ipairs({ "ARTWORK", "HIGHLIGHT" }) do
            local icon = button:CreateTexture(nil, layer)
            icon:SetAllPoints(button)
            if texture then
                icon:SetTexture(MEDIA .. texture)
                icon:SetVertexColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
            end
            if layer == "HIGHLIGHT" then
                icon:SetBlendMode("ADD")
                icon:SetAlpha(0.5)
            end
        end
        button:SetScript("OnClick", function()
            Diagram.zoom(step)
        end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(ns.L(tooltipText), 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        return button
    end
    window.zoomInButton = createZoomButton("Plus", 0.1, "Larger")
    window.zoomInButton:SetPoint("RIGHT", captionBar, "RIGHT", -10, 0)
    window.zoomFitButton = createZoomButton(nil, nil, "Fit the tree to the pane")
    window.zoomFitButton:SetSize(38, 16)
    window.zoomFitButton:SetPoint("RIGHT", window.zoomInButton, "LEFT", -2, 0)
    window.zoomText = ns.Widgets.createFontString(window.zoomFitButton, "OVERLAY", "GameFontHighlightSmall")
    window.zoomText:SetPoint("CENTER", window.zoomFitButton, "CENTER", 0, 0)
    window.zoomText:SetTextColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
    window.zoomOutButton = createZoomButton("Minus", -0.1, "Smaller")
    window.zoomOutButton:SetPoint("RIGHT", window.zoomFitButton, "LEFT", -2, 0)
    window.hint = ns.Widgets.createFontString(window, "OVERLAY", "GameFontHighlightSmall")
    window.hint:SetPoint("RIGHT", window.zoomOutButton, "LEFT", -10, 0)
    window.hint:SetPoint("LEFT", window.caption, "RIGHT", 12, 0)
    window.hint:SetJustifyH("RIGHT")
    window.hint:SetWordWrap(false)
    window.hint:SetTextColor(COLORS.grey[1], COLORS.grey[2], COLORS.grey[3])

    local paneHeight = HEIGHT - CAPTION_HEIGHT - 1 - BAR_HEIGHT - INSET - 10 -- (10: the sideways thumb's strip)
    tree.canvas = ns.Widgets.createCanvas("OneMoreQuestDiagramTree", window, TREE_WIDTH, paneHeight)
    tree.paneWidth, tree.paneHeight = tree.canvas.width, paneHeight
    local frame = tree.canvas.frame
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", window, "TOPLEFT", INSET, -CAPTION_HEIGHT - 1)
    -- The wheel scrolls up and down; with Shift, or where there is nothing to scroll that way, sideways
    frame:SetScript("OnMouseWheel", function(_, delta)
        if IsControlKeyDown and IsControlKeyDown() then
            Diagram.zoom(delta > 0 and 0.1 or -0.1)
            return
        end
        local isSideways = (IsShiftKeyDown and IsShiftKeyDown()) or (tree.canvas.maxScroll or 0) == 0
        Diagram.pan(isSideways and -delta * 40 or 0, isSideways and 0 or -delta * 40)
    end)
    -- A drag on the pane moves the tree with the mouse
    frame:EnableMouse(true)
    frame:SetScript("OnMouseDown", function(self)
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        tree.dragX, tree.dragY = x / scale, y / scale
        self:SetScript("OnUpdate", function()
            local nowX, nowY = GetCursorPosition()
            nowX, nowY = nowX / scale, nowY / scale
            Diagram.pan(tree.dragX - nowX, nowY - tree.dragY)
            tree.dragX, tree.dragY = nowX, nowY
        end)
    end)
    frame:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    -- Where the tree is sideways: a slim track under it with a gold thumb, shown only when it scrolls that way
    tree.sideTrack = window:CreateTexture(nil, "ARTWORK")
    tree.sideTrack:SetColorTexture(0, 0, 0, 0.45)
    tree.sideTrack:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 8, -3)
    tree.sideTrack:SetSize(tree.paneWidth - 16, 4)
    tree.sideThumb = window:CreateTexture(nil, "OVERLAY")
    tree.sideThumb:SetColorTexture(Style.SELECTED_EDGE[1], Style.SELECTED_EDGE[2], Style.SELECTED_EDGE[3], 0.9)
    tree.sideThumb:SetHeight(4)

    -- The bar under the tree: what each mark means, on the ground of the quest window's bar of buttons
    local legendBar = CreateFrame("Frame", nil, window)
    legendBar:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", INSET, INSET)
    legendBar:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -INSET - PAGE_WIDTH - 2, INSET)
    legendBar:SetHeight(BAR_HEIGHT)
    local fill = legendBar:CreateTexture(nil, "BORDER")
    fill:SetColorTexture(Style.BAR_BACKGROUND[1], Style.BAR_BACKGROUND[2], Style.BAR_BACKGROUND[3], 1)
    fill:SetAllPoints(legendBar)
    local rule = legendBar:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(COLORS.rule[1], COLORS.rule[2], COLORS.rule[3], 1)
    rule:SetPoint("TOPLEFT", legendBar, "TOPLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", legendBar, "TOPRIGHT", 0, -1)
    window.legend = {}
    local anchor
    for index, state in ipairs(STATE_ORDER) do
        local icon = legendBar:CreateTexture(nil, "OVERLAY")
        icon:SetSize(16, 16)
        icon:SetTexture(state == "done" and READY_ICON or state == "log" and ACTIVE_ICON or Style.GIVER_ICON)
        if state == "later" then
            icon:SetDesaturated(true)
            icon:SetAlpha(0.7)
        end
        if anchor then
            icon:SetPoint("LEFT", anchor, "RIGHT", 18, 0)
        else
            icon:SetPoint("LEFT", legendBar, "LEFT", 12, 0)
        end
        local text = ns.Widgets.createFontString(legendBar, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        text:SetTextColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
        window.legend[index] = text
        anchor = text
    end
end

---The page beside the tree, made of the quest window's own parts: the parchment, the header with its flourishes
---and seal, the scrolling page, the rewards pinned under it, and a bar of the game's red buttons.
local function createPage()
    local page = {}
    window.page = page
    local host = CreateFrame("Frame", nil, window)
    host:SetPoint("TOPRIGHT", window, "TOPRIGHT", -INSET, 0)
    host:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -INSET, INSET)
    host:SetWidth(PAGE_WIDTH)
    -- (what the page's code reads of the window it is drawn in: QuestPage's setPageHeader and setPageRewards)
    host.pageLeft, host.pageBottom, host.pageExtra = 0, BAR_HEIGHT, 0
    page.host = host
    local divider = window:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0, 0, 0, 1)
    divider:SetPoint("TOPLEFT", host, "TOPLEFT", -2, 0)
    divider:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", 0, 0)
    local strip = host:CreateTexture(nil, "BACKGROUND") -- (the scroll bar's strip, beside the parchment)
    strip:SetColorTexture(Style.BACKGROUND[1], Style.BACKGROUND[2], Style.BACKGROUND[3], 1)
    strip:SetAllPoints(host)
    local parchment = host:CreateTexture(nil, "BORDER")
    parchment:SetColorTexture(COLORS.parchment[1], COLORS.parchment[2], COLORS.parchment[3], 1)
    parchment:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    parchment:SetPoint("BOTTOMRIGHT", host, "BOTTOMLEFT", PAGE_CONTENT_WIDTH, BAR_HEIGHT)
    local parchmentArt = host:CreateTexture(nil, "BORDER", nil, 1)
    parchmentArt:SetAllPoints(parchment)
    if not QuestPage.setAtlasIfKnown(parchmentArt, "QuestDetailsBackgrounds") then
        parchmentArt:Hide()
    end
    page.canvas = ns.Widgets.createCanvas("OneMoreQuestDiagramPage", host, PAGE_WIDTH - 2, 400, 2)
    page.canvas.frame:ClearAllPoints()
    page.canvas.frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -Style.PAGE_TOP - 2)
    page.canvas.frame:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, BAR_HEIGHT + 2)
    page.header = QuestPage.createPageHeader(host, 0)
    page.rewards = QuestPage.createRewardsBlock(host, 0)
    page.canvas.handleScroll = function(scroll, maxScroll)
        withPage(QuestPage.followPageScroll, scroll, maxScroll)
    end

    local bar = CreateFrame("Frame", nil, host)
    bar:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, BAR_HEIGHT)
    bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
    local fill = bar:CreateTexture(nil, "BORDER")
    fill:SetColorTexture(Style.BAR_BACKGROUND[1], Style.BAR_BACKGROUND[2], Style.BAR_BACKGROUND[3], 1)
    fill:SetAllPoints(bar)
    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(COLORS.rule[1], COLORS.rule[2], COLORS.rule[3], 1)
    rule:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, -1)
    local function createButton(width, handleClick)
        local button = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        button:SetSize(width, 22)
        button.baseWidth = width
        button:SetScript("OnClick", handleClick)
        return button
    end
    -- The selected quest in the quest window (its page there, with its own buttons); one done, in the Chronicle
    window.openButton = createButton(96, function()
        local questId = window.selectedQuestId
        if ns.QuestState.isTurnedIn(questId) then
            ns.ChroniclePage.openQuest(questId)
        else
            Log.showQuestAnywhere(questId)
        end
    end)
    window.openButton:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    -- The diagram of the selected quest: the same window, turned to it
    window.rootButton = createButton(120, function()
        Diagram.show(window.selectedQuestId, true)
    end)
    window.rootButton:SetPoint("LEFT", bar, "LEFT", 10, 0)
end

---Sets the window's size (the tree's width and the height) and draws it again; nil for both: the usual size.
function Diagram.setSize(treeWidth, height)
    ns.settings.diagramTreeWidth, ns.settings.diagramHeight = treeWidth, height
    if window then
        window.shouldCentre = true
        Diagram.fill()
    end
end

---The grip in the window's lower right corner: dragged, the window is larger or smaller (the tree's pane takes the
---change; the page keeps its width); a right click puts the usual size back. The size is kept with the settings.
createSizeGrip = function()
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel((window:GetFrameLevel() or 1) + 60)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("RightButtonUp")
    grip:SetScript("OnClick", function()
        Diagram.setSize(nil, nil)
    end)
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then
            return
        end
        local scale = window:GetEffectiveScale()
        local startX, startY = GetCursorPosition()
        local startWidth, startHeight = getSize()
        -- (its top left corner stays where it is while it is dragged)
        local left, top = window:GetLeft(), window:GetTop()
        if left and top then
            window:ClearAllPoints()
            window:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top) -- (both in its own units, as SetPoint takes)
        end
        local sinceDrawn = 1
        self:SetScript("OnUpdate", function(_, elapsed)
            sinceDrawn = sinceDrawn + (elapsed or 0)
            if sinceDrawn < 0.03 then
                return -- (the tree is drawn again at each size: not more often than this)
            end
            sinceDrawn = 0
            local x, y = GetCursorPosition()
            Diagram.setSize(startWidth + (x - startX) / scale, startHeight + (startY - y) / scale)
        end)
    end)
    local function stop(self)
        self:SetScript("OnUpdate", nil)
    end
    grip:SetScript("OnMouseUp", stop)
    grip:SetScript("OnHide", stop)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(ns.L("Drag to resize"), 1, 1, 1)
        GameTooltip:AddLine(ns.L("Right-click for the usual size."), 0.85, 0.81, 0.66, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    window.sizeGrip = grip
end

local function createWindow()
    window = CreateFrame("Frame", "OneMoreQuestDiagram", UIParent)
    window:SetFrameStrata("FULLSCREEN_DIALOG") -- over the map and the quest window it opens from
    window:SetToplevel(true)
    window:SetClampedToScreen(true)
    window:EnableMouse(true)
    window:SetMovable(true)
    window:SetPoint("CENTER", UIParent, "CENTER", 0, -STRIP_HEIGHT / 2)
    createChrome()
    createTreePane()
    createPage()
    createSizeGrip()
    layOut()
    window:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "OneMoreQuestDiagram") -- Escape closes it, as the game's own windows
    end
end

---Opens the diagram on a quest; opened again for the quest it shows, it closes.
---@param shouldStay boolean? Open already, it turns to the quest and stays (its own "Diagram from here")
function Diagram.show(questId, shouldStay)
    if not questId or not CreateFrame or not UIParent then
        return
    end
    if not window then
        createWindow()
    end
    if window:IsShown() and window.questId == questId and not shouldStay then
        window:Hide()
        return
    end
    window.questId, window.selectedQuestId, window.shouldCentre = questId, questId, true
    window.tree.zoom = nil -- (another tree: at the size that fits it)
    window.page.canvas:scrollToTop()
    window:Show()
    Diagram.fill()
end

---@return boolean canShow The quest has quests around it (ones it needs first or opens), and the Spoilers choice
---lets their names be told: as the quest page offers its "Quest diagram" button
function Diagram.canShow(questId)
    if ns.Spoilers.isActive() and ns.Spoilers.get("chains", questId) ~= "all" then
        return false
    elseif ns.Availability.isLaterHidden("quest") then
        return false
    end
    return #ns.Chain.getPreviousQuestIds(questId) > 0 or #ns.Chain.getNextQuestIds(questId) > 0
end

---Adds "Quest diagram" to a quest's menu (the quest list's, the tracker's), where the diagram may be shown.
function Diagram.addMenuItem(root, questId)
    if Diagram.canShow(questId) then
        root:CreateButton(ns.L("Quest diagram"), function()
            Diagram.show(questId, true)
        end)
    end
end

---@return table? window The diagram's frame (its boxes in window.boxes), for the tests and the simulator
function Diagram.getWindow()
    return window
end

-- Whatever redraws the quest window redraws the diagram while it is open: a fold of its page opened, a quest
-- handed in, the language changed
local refreshLog = Log.refresh
function Log.refresh(...)
    refreshLog(...)
    Diagram.fill()
end
