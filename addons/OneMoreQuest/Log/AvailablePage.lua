local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: the page of a quest to pick up (on the Available and Dungeons tabs): its header, what
-- holds it back, the steps to start and finish it, what it needs, then the same folds as a quest in the log.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local selectedQuestIds = State.selectedQuestIds
local COLORS, DOT, PADDING, READY_ICON, TAB_AVAILABLE =
    Style.COLORS, Style.DOT, Style.PADDING, Style.READY_ICON, Style.TAB_AVAILABLE
local Spoiled = QuestPage.Spoiled
local addBody, addFold, addHeading, addStepLine, addSteps, composePlaceLine, showPlace =
    QuestPage.addBody,
    QuestPage.addFold,
    QuestPage.addHeading,
    QuestPage.addStepLine,
    QuestPage.addSteps,
    QuestPage.composePlaceLine,
    QuestPage.showPlace
local addChainSection, addLinksAndDiagram, addProfitSection, composeDropZoneLines =
    QuestPage.addChainSection, QuestPage.addLinksAndDiagram, QuestPage.addProfitSection, QuestPage.composeDropZoneLines
local setPageHeader, setPageRewards = QuestPage.setPageHeader, QuestPage.setPageRewards

---Turns the map to where a quest's starting item drops, keeping the quest selected, so the map shows each
---creature's spawn points in its colour there.
---@param target { zone: DropZone, place: table?, quest: table }
local function showDropZone(target)
    local zoneId = target.zone.zoneId
    Actions.showPlaceOnMap(zoneId, target.place) -- the list moves to the zone itself, without letting go of the quest
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

-- A quest to pick up, on the Available tab: its header, what holds it back, the steps to start and finish it, what
-- it needs, then the same folds as a quest in the log.
local drawAvailableQuest
do
    local NO_STEPS = {} -- (read only: a quest with no steps done back to back)
    local WARNING_FILL = { 0.79, 0.52, 0.15, 0.28 }

    ---The same header as a quest in the log: its levels, the steps at one stop, how it starts, where it ends (a link
    ---to the zone), its group.
    ---@return string factsText
    ---@return table? zoneLink
    local function composeAvailableFacts(quest, view, group)
        local facts = { Log.formatLevelRange(quest.questId, quest.level, group ~= nil) }
        local instantStepIds = quest.instantStepIds or NO_STEPS
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
            zoneLink = {
                before = table.concat(facts, DOT) .. DOT .. endsText:sub(1, zoneStart - 1),
                text = zoneName,
                handleClick = showPlace,
                data = { place = quest.finisherPlace },
            }
            facts[#facts + 1] = endsText
        end
        if group then
            facts[#facts + 1] = ns.Widgets.formatGroup(group) .. " " .. group.kindText
        end
        return table.concat(facts, DOT), zoneLink
    end

    ---One warning in its amber band; the quest it names (link.questId) a link to its page.
    ---@param link { format: string, questId: number }? How the warning names a quest
    ---@return number y Below it
    local function addWarning(y, warning, link)
        local before, after
        if link then
            before, after = link.format:match("^(.-)%%s(.*)$")
        end
        local textWidth = State.detail.width - 2 * PADDING - 20
        local height
        if before then
            -- The quest it names is a link to its page, as the lead-in steps' names are
            height = addStepLine(y + 6, {
                text = before:gsub('"?%s*$', ""),
                link = ns.QuestText.getQuestName(link.questId) or ("Quest " .. link.questId),
                afterText = after:gsub('^"', ""):gsub("^%s+", ""),
                handleClick = Log.showQuestAnywhere,
                data = link.questId,
                color = COLORS.warning,
            }, PADDING + 10, textWidth)
        else
            height = State.detail:addText(
                warning,
                PADDING + 10,
                y + 6,
                { font = "QuestFont", color = COLORS.warning, width = textWidth }
            )
        end
        State.detail:addRect(PADDING, y, State.detail.width - 2 * PADDING, height + 12, WARNING_FILL)
        State.detail:addRect(PADDING, y, 3, height + 12, COLORS.warning, 1)
        return y + height + 18
    end

    ---What stands in the way first: the level it opens at, or why not yet; then the quest's warnings.
    ---@return number y Below them
    local function addWarnings(y, quest)
        local warnings, warningLinks = ns.Warnings.getQuestWarnings(quest.questId)
        local linkByWarning = {}
        for index, link in pairs(warningLinks or {}) do
            linkByWarning[warnings[index]] = link
        end
        if quest.availableAtLevel then
            table.insert(warnings, 1, ns.L("Available at level %d", quest.availableAtLevel))
        elseif quest.blocker then
            table.insert(
                warnings,
                1,
                ns.L("Not yet: %s", (ns.Availability.getShownReason(quest.blocker):gsub("^%u", string.lower)))
            )
        end
        for _, warning in ipairs(warnings) do
            y = addWarning(y, warning, linkByWarning[warning])
        end
        if #warnings > 0 then
            y = y + 6
        end
        return y
    end

    ---A starting item whose source is placed nowhere, in a quest that belongs to a dungeon: say so, and lead to the
    ---way in.
    ---@return table lines The lines given, unless the dungeon is known
    local function composeDungeonSourceLines(quest, source, lines)
        local pickupDungeon = ns.Database.getDungeon(ns.Location.getPickupDungeonId(quest.questId) or 0)
        if not pickupDungeon then
            return lines
        end
        lines = { ns.L("%s, somewhere in %s: the quest database does not say where", source, pickupDungeon.name) }
        local entrance = pickupDungeon.entrances[1]
        if entrance then
            table.insert(
                lines,
                composePlaceLine(
                    { groupZoneId = entrance.zoneId, mapZoneId = entrance.zoneId, x = entrance.x, y = entrance.y },
                    { prefix = ns.L("Entrance at") }
                )
            )
        end
        return lines
    end

    ---@return boolean isNamed Who drops a starting item may be named (Spoilers: with names or chances, or once it
    ---dropped for the player)
    local function isStartSourceNamed(quest, view)
        return not view
            or not view.isChanceHidden
            or view.drops == "names"
            or (view.drops == "found" and quest.itemId ~= nil and ns.Spoilers.hasSeenDrop(quest.itemId))
    end

    ---@return string source Who drops a starting item, as the Spoilers choice lets it be told ("Found" when not)
    ---@return string sourceText Where it drops, as one phrase with its zone when that is known
    local function composeItemSource(quest, view)
        local isSourceNamed = isStartSourceNamed(quest, view)
        local source = quest.starterName and isSourceNamed and ns.L("Drops from %s", quest.starterName) or ns.L("Found")
        if not quest.sourceZoneName then
            return source, source
        end
        return source,
            quest.starterName and isSourceNamed and ns.L("Drops from %s in %s", quest.starterName, quest.sourceZoneName)
                or ns.L("Found in %s", quest.sourceZoneName)
    end

    ---A quest that starts from an item: loot it (where it drops) or use it from the bags, then accept the quest.
    ---@return table[] steps
    local function composeItemStartSteps(quest, view, place)
        local source, sourceText = composeItemSource(quest, view)
        local sourcePlace = not quest.isHandedInHere and place or nil
        local isInInstance = quest.isHandedInHere or (sourcePlace and sourcePlace.x < 0)
        local firstStep = {
            title = ns.L(quest.isItemInBags and "Use %s" or "Loot %s", quest.itemName),
            lines = {
                quest.isItemInBags and ns.L("It is in your bags; using it starts the quest") or sourceText,
            },
        }
        local dropZones = not quest.isItemInBags and quest.itemId and ns.Drops.getZones(quest.itemId) or {}
        if #dropZones > 0 then
            firstStep.lines = composeDropZoneLines(dropZones, "available:" .. quest.questId, {
                handleClick = showDropZone,
                quest = quest,
                itemId = quest.itemId,
                view = view and { drops = view.drops, isChanceHidden = view.isChanceHidden },
            })
        elseif not quest.isItemInBags then
            firstStep.lines = composeDungeonSourceLines(quest, source, firstStep.lines)
        end
        if sourcePlace and not isInInstance and #dropZones == 0 then
            -- The drop list names its zones as links already; otherwise the place, with the way there
            table.insert(
                firstStep.lines,
                composePlaceLine(sourcePlace, { distance = quest.distance, direction = quest.direction })
            )
        end
        return { firstStep, { title = ns.L("Use it from your bags to accept the quest"), lines = {} } }
    end

    ---A quest given by a creature or an object: talk to it (or use it), where it stands.
    ---@return table step
    local function composeGiverStep(quest, place)
        local isObject = quest.startType == "object"
        return {
            title = quest.starterName and ns.L(isObject and "Use %s" or "Talk to %s", quest.starterName)
                or ns.L(isObject and "Use the quest giver" or "Talk to the quest giver"),
            lines = {
                place and composePlaceLine(place, { distance = quest.distance, direction = quest.direction })
                    or ns.L("Location not in the database"),
            },
        }
    end

    ---One lead-in as a step: a link to its page, saying what kind of quest it is.
    ---@return table step
    local function composeLeadInStep(leadInId, leadInIndex, leadInCount)
        local isInLog = ns.QuestState.isInLog(leadInId)
        local leadInDungeon = ns.Database.getDungeon(ns.Location.getInsideDungeonIds(leadInId)[1] or 0)
        local startZoneId = ns.Availability.getStartZoneId(leadInId)
        local kindText = leadInDungeon and ns.L("a %s quest", leadInDungeon.name)
            or (startZoneId and ns.L("picked up in %s", ns.Database.getZoneName(startZoneId)))
            or nil
        local title
        if leadInCount > 1 then
            title = ns.L(isInLog and "Finish lead-in %d of %d" or "Do lead-in %d of %d", leadInIndex, leadInCount)
        else
            title = ns.L(isInLog and "Finish the lead-in" or "Do the lead-in")
        end
        return {
            title = title,
            lines = {
                {
                    link = ns.QuestText.getQuestName(leadInId) or ("Quest " .. leadInId),
                    afterText = kindText
                            and (DOT:gsub("^ ", "") .. kindText .. (isInLog and DOT .. ns.L("in your log") or ""))
                        or nil,
                    handleClick = Log.showQuestAnywhere,
                    data = leadInId,
                },
            },
        }
    end

    ---Behind a lead-in: the lead-ins come first, each a link to its page, saying what kind of quest it is (not where
    ---the Spoilers choice keeps the story back: the lead-ins would name it).
    local function insertLeadInSteps(steps, quest, view)
        if not (quest.blocker and quest.blocker.kind == "quest") or (view and view.isStoryHidden) then
            return
        end
        local leadInIds = ns.Availability.getLeadIns(quest.questId, ns.Availability.getPlayer())
        local leadInSteps = {}
        for leadInIndex, leadInId in ipairs(leadInIds) do
            leadInSteps[#leadInSteps + 1] = composeLeadInStep(leadInId, leadInIndex, #leadInIds)
        end
        for leadInIndex = #leadInSteps, 1, -1 do
            table.insert(steps, 1, leadInSteps[leadInIndex])
        end
    end

    ---@return table lines Under the turn-in: where to hand it in, as the Spoilers choice lets it be told
    ---@return table? finisherPlace
    local function composeFinisherLines(quest, view, place, zoneId)
        local finisherPlace = quest.isHandedInHere and place or quest.finisherPlace
        local lines = {}
        if view and not view.isTurnInShown then
            -- Where to hand it in is held back: the name alone; "once you met them" says they are not met yet
            finisherPlace = nil
            lines[1] = view.turnIn == "met" and ns.L("Not met yet") or nil
        end
        if finisherPlace then
            lines[1] = composePlaceLine(
                finisherPlace,
                { suffix = ns.L(finisherPlace.groupZoneId == zoneId and "in this location" or "not in this location") }
            )
        end
        return lines, finisherPlace
    end

    ---What to bring before handing in: each item it asks for, and who drops it.
    local function addAskedItemSteps(steps, quest, view)
        local objectives = ns.Database.getQuestField(quest.questId, "objectives") or {}
        for _, item in ipairs(objectives[3] or {}) do
            local source = ns.Drops.getHuntedSource(item[1])
            if
                view
                and view.isChanceHidden
                and not (view.drops == "names" or (view.drops == "found" and ns.Spoilers.hasSeenDrop(item[1])))
            then
                source = nil -- (who drops it is held back)
            end
            local itemName = ns.Database.getItemField(item[1], "name")
            steps[#steps + 1] = {
                title = itemName and ns.L("Get %s", itemName) or ns.L("Get the item it asks for"),
                lines = { source and source.name and ns.L("drops from %s", source.name) or ns.L("it asks for one") },
            }
        end
    end

    ---The steps after the start: the items to bring, the turn-in, the steps handed straight back, and that any one
    ---of the quest's versions will do. Remembers where it is handed in (State.shownTurnInPlace).
    local function addFinishSteps(steps, quest, view, place, zoneId)
        if not quest.finisherName then
            return
        end
        local instantStepIds = quest.instantStepIds or NO_STEPS
        local lines, finisherPlace = composeFinisherLines(quest, view, place, zoneId)
        if #instantStepIds > 0 then
            addAskedItemSteps(steps, quest, view)
        end
        steps[#steps + 1] = { title = ns.L("Turn in to %s", quest.finisherName), lines = lines }
        State.shownTurnInPlace = finisherPlace
        for _, stepQuestId in ipairs(instantStepIds) do
            steps[#steps + 1] = {
                title = ns.L(
                    "Then take %s there and hand it straight back",
                    ns.QuestText.getQuestName(stepQuestId) or ns.L("the next step")
                ),
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

    ---@return table[] steps From the start (or the lead-ins before it) to the last reward, for addSteps
    local function composeSteps(quest, view, place, zoneId)
        local steps
        if quest.startType == "item" then
            steps = composeItemStartSteps(quest, view, place)
        else
            steps = { composeGiverStep(quest, place) }
        end
        insertLeadInSteps(steps, quest, view)
        addFinishSteps(steps, quest, view, place, zoneId)
        return steps
    end

    local function addWarningDot(y)
        State.detail:addDot(PADDING + 2, y + 2, 10, COLORS.warning, 0)
    end

    ---The quest to do first, and where its chain starts when that is further back: each a link to its page.
    ---@return number y Below them
    local function addQuestBlocker(y, quest, blocker)
        addWarningDot(y)
        local textLeft, textWidth = PADDING + 22, State.detail.width - 2 * PADDING - 22
        local isInLog = ns.QuestState.isInLog(blocker.questId)
        y = y
            + addStepLine(y, {
                text = ns.L(isInLog and "Finish" or "Do"),
                link = blocker.name,
                afterText = ns.L("first"),
                handleClick = Log.showQuestAnywhere,
                data = blocker.questId,
            }, textLeft, textWidth)
            + 6
        local chainStartQuestId = ns.Availability.getChainStart(quest.questId, ns.Availability.getPlayer())
        if not chainStartQuestId or chainStartQuestId == blocker.questId then
            return y
        end
        local chainStartName = ns.QuestText.getQuestName(chainStartQuestId) or ("Quest " .. chainStartQuestId)
        local startZoneId = ns.Availability.getStartZoneId(chainStartQuestId)
        return y
            + addStepLine(y, {
                text = ns.L("The chain starts with"),
                link = chainStartName,
                handleClick = Log.showQuestAnywhere,
                data = chainStartQuestId,
                afterText = startZoneId and ns.L("in %s", ns.Database.getZoneName(startZoneId)) or nil,
            }, textLeft, textWidth)
            + 6
    end

    ---What holds the quest back besides the level, as a requirement not met.
    ---@return number y Below it
    local function addBlockerRequirement(y, quest, view)
        local blocker = quest.blocker
        if not blocker or blocker.kind == "level" then
            return y
        end
        if blocker.kind == "quest" and view and view.isStoryHidden then
            -- The quest to do first is held back by the Spoilers choice: only that it is later in the story
            addWarningDot(y)
            return addBody(y, ns.Availability.getShownReason(blocker), COLORS.warning, 22)
        elseif blocker.kind == "quest" then
            return addQuestBlocker(y, quest, blocker)
        end
        addWarningDot(y)
        return addBody(y, blocker.text, COLORS.warning, 22)
    end

    ---The requirements: the level (ticked once met), what holds it back, the starting item in the bags.
    ---@return number y Below them
    local function addRequirements(y, quest, view)
        y = addHeading(y, ns.L("Requirements"))
        local blocker = quest.blocker
        local requiredLevel = ns.Database.getQuestField(quest.questId, "requiredLevel") or 0
        local isLevelMet = not quest.availableAtLevel and not (blocker and blocker.kind == "level")
        local requirement = requiredLevel > 1 and ns.L("Level %d or higher", requiredLevel)
            or ns.L("No level requirement")
        if isLevelMet then
            State.detail:addIcon(PADDING, y, 14, READY_ICON)
        else
            addWarningDot(y)
        end
        y = addBody(y, requirement, isLevelMet and COLORS.ink or COLORS.warning, 22)
        y = addBlockerRequirement(y, quest, view)
        if quest.itemName then
            State.detail:addDot(PADDING + 2, y + 2, 10, COLORS.softInk, 0)
            State.detail:addDot(PADDING + 4, y + 4, 6, COLORS.parchment, 1)
            y = addBody(y, ns.L("%s in your bags", quest.itemName), COLORS.ink, 22)
        end
        return y + 12
    end

    ---The fold of what the quest asks: its own words; with none and nothing to do, that it asks nothing.
    ---@return number y Below it
    local function addAsksSection(y, quest)
        local objectivesText = ns.Database.getQuestField(quest.questId, "objectivesText")
        local hasObjectives = next(ns.Database.getQuestField(quest.questId, "objectives") or {}) ~= nil
        local isOpen
        if type(objectivesText) == "table" and #objectivesText > 0 then
            y, isOpen = addFold(y, "asks", quest.questId, ns.L("What it asks"), nil, true)
            if isOpen then
                y = addBody(y, ns.QuestText.getObjectives(quest.questId, table.concat(objectivesText, " "))) + 10
            end
            return y
        end
        if hasObjectives or not quest.finisherName then
            return y
        end
        -- No text and nothing to do (the Sparklematic 5200!'s second step): say so, not leave the player guessing
        y, isOpen = addFold(y, "asks", quest.questId, ns.L("What it asks"), nil, true)
        if not isOpen then
            return y
        end
        local isSameHands = quest.finisherName == quest.starterName
        return addBody(
            y,
            ns.L(
                isSameHands and "Nothing in between: take it and hand it straight back to %s for the reward."
                    or "Nothing to collect or kill: take it to %s.",
                quest.finisherName
            )
        ) + 10
    end

    ---@return number height
    function drawAvailableQuest(quest, zoneId)
        local view = Spoiled.compose(quest.questId) -- (nil in Guide)
        Spoiled.view = view
        -- The same header as a quest in the log: name, a line of facts, the chain badge
        local factsText, zoneLink = composeAvailableFacts(quest, view, ns.QuestState.getGroupInfo(quest.questId))
        local isChainShown = not view or view.chains ~= "hidden"
        setPageHeader(
            quest.title,
            factsText,
            isChainShown and quest.chainIndex or nil,
            quest.chainTotal,
            zoneLink,
            quest.questId
        )
        local y = addWarnings(12, quest)
        local rewardsExtraHeight = setPageRewards((not view or view.rewards ~= "hidden") and quest.questId or nil)

        -- Steps done back to back are one thing to do, from the start to the last reward: "How it goes"
        local instantStepIds = quest.instantStepIds or NO_STEPS
        y = addHeading(y, ns.L(#instantStepIds > 0 and "How it goes" or "How to start"))
        local place = quest.nearestPlace or quest.places[1]
        y = addSteps(y, composeSteps(quest, view, place, zoneId)) + 8
        State.shownPlace = not quest.isHandedInHere and place or nil

        y = addRequirements(y, quest, view)
        y = addProfitSection(y, quest.questId)
        y = addAsksSection(y, quest)
        y = addChainSection(y, quest, isChainShown)
        y = addLinksAndDiagram(y, quest, view, true)
        return y + PADDING + rewardsExtraHeight
    end
end

-- Shared with the other parts of the window
QuestPage.drawAvailableQuest = drawAvailableQuest
