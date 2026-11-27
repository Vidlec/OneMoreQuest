local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: the quests around a quest, on its page. Its chain under a fold, step by step, with what
-- the rest of the chain gives (PageRewards) over it; the quests it needs first and those it unlocks; and the way to
-- the diagram of them all.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local COLORS, DOT, MAX_OPEN_CHAIN, MEDIA, PADDING =
    Style.COLORS, Style.DOT, Style.MAX_OPEN_CHAIN, Style.MEDIA, Style.PADDING
local Spoiled = QuestPage.Spoiled
local CHECKBOX_IMAGE, CHECKBOX_SIZE, CHECKBOX_TICK, TO_DO_LEAD =
    QuestPage.CHECKBOX_IMAGE, QuestPage.CHECKBOX_SIZE, QuestPage.CHECKBOX_TICK, QuestPage.TO_DO_LEAD
local addChainPrize, addFold, addHeading, addPaperButton, hideTooltip =
    QuestPage.addChainPrize, QuestPage.addFold, QuestPage.addHeading, QuestPage.addPaperButton, QuestPage.hideTooltip

local function toggleChain()
    State.isChainExpanded = not State.isChainExpanded
    Log.refresh()
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
    GameTooltip:AddLine(
        ns.L(entry and "Click to read it in the Chronicle" or "Click to see it in the Chronicle"),
        1,
        1,
        1
    )
    if entry and entry.turnedInAt then
        GameTooltip:AddLine(
            ns.L("Done %s", ns.Chronicle.formatShownDate("%d %b %Y", entry.turnedInAt)),
            0.82,
            0.77,
            0.64
        )
    else
        GameTooltip:AddLine(ns.L("Done before the chronicle began"), 0.82, 0.77, 0.64, true)
    end
    GameTooltip:Show()
end

---Says where a step of the chain opens, and when it is not to be picked up yet, after which step.
local function showChainStepTooltip(button, questId)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local isInLog = ns.QuestState.isInLog(questId)
    GameTooltip:AddLine(
        ns.L(isInLog and "Click to open it in My quests" or "Click to open it on the Available tab"),
        1,
        1,
        1
    )
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
        font = "QuestFont",
        color = state == "current" and COLORS.ink or COLORS.softInk,
        width = State.detail.width - PADDING - textLeft,
    })
    -- A step still to come opens where it is: in the log on My quests, else on the Available tab; a step done opens
    -- in the chronicle, its story there
    if state == "done" or (state == "upcoming" and ns.QuestState.isTurnedIn(chainQuestId)) then
        State.detail:addButton(
            textLeft - 2,
            y - 2,
            State.detail.width - PADDING - textLeft + 4,
            textHeight + 4,
            openDoneStep,
            chainQuestId,
            showDoneStepTooltip,
            nil,
            hideTooltip
        )
    elseif state == "upcoming" then
        State.detail:addButton(
            textLeft - 2,
            y - 2,
            State.detail.width - PADDING - textLeft + 4,
            textHeight + 4,
            openChainStep,
            chainQuestId,
            showChainStepTooltip,
            nil,
            hideTooltip
        )
    end
    -- Steps of one name (Test of Lore's six) are told apart by what each asks, its first sentence
    local objectivesText = isNameShared and ns.Database.getQuestField(chainQuestId, "objectivesText")
    -- In the player's language when a translation addon has it, as the step's title above it
    local asks = type(objectivesText) == "table"
        and ns.QuestText.getObjectives(chainQuestId, table.concat(objectivesText, " "))
    local firstSentence = asks and (asks:match("^%s*(.-[%.!?])%s") or asks)
    if firstSentence and firstSentence:match("%S") then
        textHeight = textHeight
            + 2
            + State.detail:addText(firstSentence, textLeft, y + textHeight + 2, {
                font = "GameFontHighlightSmall",
                color = COLORS.softInk,
                width = State.detail.width - PADDING - textLeft,
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
    State.detail:addIcon(
        PADDING + 1,
        y,
        16,
        isOpen and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up"
    )
    local height = State.detail:addText(
        text,
        PADDING + TO_DO_LEAD,
        y,
        { font = "QuestFont", color = COLORS.softInk, isSingleLine = true }
    )
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
        State.detail:addText(
            "\194\183 \194\183 \194\183",
            PADDING + 1,
            y,
            { font = "QuestFont", color = COLORS.softInk, isSingleLine = true }
        )
        y = y
            + State.detail:addText(ns.Lp(total - index, "%d more step", "%d more steps"), PADDING + TO_DO_LEAD, y, {
                font = "QuestFont",
                color = COLORS.softInk,
                isSingleLine = true,
            })
            + 8
        if not Spoiled.view or Spoiled.view.rewards ~= "hidden" then
            y = y
                + State.detail:addText(ns.L("A reward waits at the end of the chain."), PADDING, y, {
                    font = "GameFontHighlightSmall",
                    color = COLORS.softInk,
                    width = State.detail.width - 2 * PADDING,
                })
                + 6
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

---The fold of a quest's chain, "Quest chain  2 of 5", and the chain under it while it is open. Nothing for a quest
---not in a chain, or where the Spoilers choice hides chains.
---@param quest table A quest of the log or of the Available tab (questId, chainIndex, chainTotal)
---@return number y Below it
local function addChainSection(y, quest, isChainShown)
    if not (quest.chainIndex and isChainShown) then
        return y
    end
    local isOpen
    y, isOpen = addFold(
        y,
        "chain",
        quest.questId,
        ns.L("Quest chain"),
        ns.L("%d of %d", quest.chainIndex, quest.chainTotal),
        true
    )
    if isOpen then
        y = addChain(y + 2, quest.questId, true)
    end
    return y
end

local addLinksAndDiagram
do
    local MAX_OPEN_LINKS = 6 -- a quest that opens more than these names the first of them and counts the rest

    local function openDiagram(questId)
        ns.LogDiagram.show(questId)
    end

    ---The quests around this one that are not its chain, under their own fold: what it needed first and what it unlocks,
    ---each a line as a chain's step is, to click as one; then the way to the diagram of them all.
    ---@param links { requiredIds: number[], unlockIds: number[], isAnyEnough: boolean, canNameLater: boolean, canNameEarlier: boolean }
    ---@return number y Below them
    local function addLinks(y, links)
        local function isNameShared()
            return false
        end
        local function addLabel(text)
            y = y
                + State.detail:addText(text, PADDING, y, {
                    font = "GameFontHighlightSmall",
                    color = COLORS.softInk,
                    width = State.detail.width - 2 * PADDING,
                })
                + 6
        end
        local function addQuests(questIds)
            for position = 1, math.min(#questIds, MAX_OPEN_LINKS) do
                local linkedQuestId = questIds[position]
                local state = ns.QuestState.isTurnedIn(linkedQuestId) and "done" or "upcoming"
                y = addChainStep(y, linkedQuestId, state, isNameShared())
            end
            if #questIds > MAX_OPEN_LINKS then
                addLabel(ns.Lp(#questIds - MAX_OPEN_LINKS, "and %d more quest", "and %d more quests"))
            end
            y = y + 6
        end
        if #links.requiredIds > 0 and links.canNameEarlier then
            addLabel(ns.L(links.isAnyEnough and "Needed first, any one of:" or "Needed first:"))
            addQuests(links.requiredIds)
        end
        if #links.unlockIds > 0 and links.canNameLater then
            addLabel(ns.L("Unlocks:"))
            addQuests(links.unlockIds)
        elseif #links.unlockIds > 0 then
            addLabel(ns.Chain.composeUnlockText(links.unlockIds, false)) -- (which ones is later in the story)
        end
        return y + 6
    end

    ---What the page says of a quest's links besides its chain, by what the Spoilers choices let tell: nothing with the
    ---chains held back, the quests it unlocks by name only with every chain step told and the story not held back.
    ---@param quest table A quest of the log or of the Available tab (unlockIds, requiredIds)
    ---@return table? links nil when there is nothing to say
    local function composeLinks(quest, view, isAvailable)
        if view and view.chains == "hidden" then
            return nil
        end
        local requiredIds, isAnyEnough = ns.Chain.getRequiredQuestIds(quest.questId)
        local links = {
            requiredIds = requiredIds,
            unlockIds = quest.unlockIds or {},
            isAnyEnough = isAnyEnough,
            canNameLater = not view or (view.chains == "all" and not view.isStoryHidden),
            -- (a quest to pick up may still wait for the earlier one: named only where the story is)
            canNameEarlier = not view or not isAvailable or not view.isStoryHidden,
        }
        if #links.unlockIds == 0 and (#requiredIds == 0 or not links.canNameEarlier) then
            return nil
        end
        return links
    end

    ---The way to the diagram, in the middle of the page: the game's red button, as the ones under the page are,
    ---with the branching mark before its words; the page's paper button where this client lacks that art.
    ---@return number y Below it
    local function addDiagramButton(y, questId)
        local page = State.detail
        local text = ns.L("Quest diagram")
        local hasArt = ns.LogList.hasGameArt("128-RedButton-Left") and ns.LogList.hasGameArt("_128-RedButton-Center")
        if not hasArt then
            addPaperButton(page, PADDING + #text * 6.5 + 18, y, text, openDiagram, questId)
            return y + 28
        end
        local height, glyphSize, sidePadding = 28, 14, 26
        local _, textWidth, fontString =
            page:addText(text, PADDING, y, { font = "GameFontNormal", color = COLORS.gold, isSingleLine = true })
        textWidth = math.ceil(textWidth or #text * 7)
        local width = sidePadding + glyphSize + 6 + textWidth + sidePadding
        local x = math.floor((page.width - width) / 2)
        -- The button's art in three pieces, its ends as wide as their pictures at this height
        local leftWidth, rightWidth = math.floor(height * 114 / 128), math.floor(height * 292 / 128)
        page:addImage(x, y, leftWidth, height, { atlas = "128-RedButton-Left" })
        page:addImage(x + leftWidth, y, width - leftWidth - rightWidth, height, { atlas = "_128-RedButton-Center" })
        page:addImage(x + width - rightWidth, y, rightWidth, height, { atlas = "128-RedButton-Right" })
        page:addIcon(x + sidePadding, y + (height - glyphSize) / 2 - 1, glyphSize, MEDIA .. "Unlock", COLORS.gold, 2)
        if fontString then
            ns.Widgets.place(
                fontString,
                "TOPLEFT",
                page.content,
                "TOPLEFT",
                x + sidePadding + glyphSize + 6,
                -(y + (height - 12) / 2 - 1)
            )
        end
        page:addButton(x, y, width, height, openDiagram, questId)
        return y + height + 8
    end

    ---The fold of a quest's links and, under it and the chain, the button that opens the diagram of the quests around
    ---it (only where their names may be told).
    ---@return number y Below them
    function addLinksAndDiagram(y, quest, view, isAvailable)
        local links = composeLinks(quest, view, isAvailable)
        if links then
            local notes = {}
            if #links.requiredIds > 0 and links.canNameEarlier then
                notes[#notes + 1] = ns.Lp(#links.requiredIds, "%d before", "%d before")
            end
            if #links.unlockIds > 0 then
                notes[#notes + 1] = ns.Lp(#links.unlockIds, "unlocks %d", "unlocks %d")
            end
            local isOpen
            y, isOpen = addFold(y, "links", quest.questId, ns.L("Before and after"), table.concat(notes, DOT), true)
            if isOpen then
                y = addLinks(y + 2, links)
            end
        end
        -- (not on the page the diagram's own window shows: State.isDiagramPage)
        local canShowDiagram = not State.isDiagramPage
            and (not view or (view.chains == "all" and not view.isStoryHidden))
            and (links ~= nil or quest.chainIndex ~= nil)
        if canShowDiagram then
            y = addDiagramButton(y + 4, quest.questId)
        end
        return y
    end
end

-- Shared with the other parts of the window
QuestPage.addChainSection = addChainSection
QuestPage.addLinksAndDiagram = addLinksAndDiagram
