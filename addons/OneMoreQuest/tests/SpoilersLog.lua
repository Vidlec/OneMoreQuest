-- Tests: what the quest window tells under each Spoilers choice (its tabs, a quest's page, "Need a hint?").

---Opens the quest window docked beside the map, and catches what its page draws.
---@return function draw Draws the page of a quest of the log (or the window as it is, without one) and returns its text
local function openWindow(ns)
    ns.Spoilers.create()
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    local canvas = ns.Log.getPageCanvas()
    local texts = {}
    local addText = canvas.addText
    canvas.addText = function(self, text, ...)
        texts[#texts + 1] = tostring(text)
        return addText(self, text, ...)
    end
    return function(questId)
        texts = {}
        if questId then
            ns.Log.selectQuest(questId)
        end
        ns.Log.refresh()
        return table.concat(texts, "\n")
    end
end

local function has(text, part)
    return text:find(part, 1, true) ~= nil
end

---@return table[] rows The data of every button the list drew
local function getListData(ns)
    local canvas, data = ns.Log.getListCanvas(), {}
    for index = 1, canvas.pools.buttons.usedCount or 0 do
        data[#data + 1] = canvas.pools.buttons[index].data
    end
    return data
end

local function isListed(ns, value)
    for _, data in ipairs(getListData(ns)) do
        if data == value then
            return true
        end
    end
    return false
end

test("in Guide the quest window draws exactly as before, and a choice changed and taken back leaves no trace", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(2, 12), itemObjective(0, 4) })
    local draw = openWindow(ns)
    local before = draw(301)
    expectEqual(ns.Spoilers.isActive(), false, "nothing held back")
    expectEqual(has(before, "Need a hint?"), false, "no hint offered in Guide")
    expectEqual(has(before, "Turn in to"), true, "the turn-in")
    ns.Spoilers.setPreset("explorer")
    draw(301)
    ns.Spoilers.setPreset("guide")
    expectEqual(draw(301), before, "the same page again")
end)

test("objectives: exact as before, rough the zone alone, found the places found, hidden nothing", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(2, 12) })
    local draw = openWindow(ns)
    local exact = draw(201)
    local zoneName = ns.Database.getZoneName(TIRISFAL)
    ns.Spoilers.setChoice("objectives", "rough")
    local rough = draw(201)
    expectEqual(has(rough, zoneName), true, "rough: the zone")
    expectEqual(rough:find(zoneName .. " %d+, %d+") == nil, true, "rough: no spot in it")
    expectEqual(exact:find("%d+, %d+") ~= nil, true, "exact: the spot")
    ns.Spoilers.setChoice("objectives", "found")
    local found = draw(201)
    expectEqual(has(found, "You have not found any yet"), true, "found: nothing yet")
    local memory = ns.Spoilers.getMemory()
    memory.found[201] = { [1] = { { zoneId = TIRISFAL, x = 44.2, y = 31.6 } } }
    found = draw(201)
    expectEqual(has(found, "found by you"), true, "found: the place found")
    expectEqual(has(found, "44, 32"), true, "where")
    ns.Spoilers.setChoice("objectives", "hidden")
    ns.Spoilers.setChoice("turnIn", "hidden") -- (the turn-in's own place aside)
    local hidden = draw(201)
    expectEqual(hidden:find(" %d+, %d+") == nil, true, "hidden: no place")
    expectEqual(has(hidden, "You have not found"), false, "hidden: nothing about finding")
end)

test("drops: names lose their chances, found keeps only creatures that dropped it, hidden names none", function()
    local ns, state = createAddon()
    setQuest(state, 606, false, { itemObjective(0, 4) })
    local draw = openWindow(ns)
    local creature = ns.Database.getNpcField(5002, "name")
    local guide = draw(606)
    expectEqual(has(guide, creature), true, "Guide names the creature")
    ns.Spoilers.setChoice("drops", "names")
    local names = draw(606)
    expectEqual(has(names, creature), true, "names: the creature")
    expectEqual(has(names, "%"), false, "names: no chance")
    ns.Spoilers.setChoice("drops", "found")
    expectEqual(has(draw(606), creature), false, "found: not before it dropped")
    ns.Spoilers.getMemory().drops[7001] = { [5002] = true }
    expectEqual(has(draw(606), creature), true, "found: once it dropped")
    ns.Spoilers.setChoice("drops", "hidden")
    expectEqual(has(draw(606), creature), false, "hidden: none")
end)

test("turn-in: shown as before, met once the finisher was met, hidden the name alone", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(2, 12) })
    local draw = openWindow(ns)
    ns.Spoilers.setChoice("turnIn", "met")
    local page = draw(201)
    expectEqual(has(page, "Not met yet"), true, "not met yet")
    ns.Spoilers.getMemory().met[9002] = true
    page = draw(201)
    expectEqual(has(page, "Not met yet"), false, "met")
    ns.Spoilers.setChoice("turnIn", "hidden")
    page = draw(201)
    expectEqual(has(page, "Turn in to"), true, "the name stays")
    expectEqual(has(page, "Not met yet"), false, "nothing about meeting")
end)

test("chains: count names the steps done and this one, then how many more; hidden has no chain at all", function()
    local ns, state = createAddon()
    state.turnedIn = state.turnedIn or {}
    setQuest(state, 101, false)
    local draw = openWindow(ns)
    local guide = draw(101)
    local nextName = ns.QuestText.getQuestName(102)
    expectEqual(has(guide, nextName), true, "Guide names the next step")
    ns.Spoilers.setChoice("chains", "count")
    local count = draw(101)
    expectEqual(has(count, nextName), false, "count: the next step unnamed")
    expectEqual(has(count, "2 more steps"), true, "count: how many more")
    expectEqual(has(count, "A reward waits at the end of the chain."), true, "count: a reward waits")
    expectEqual(has(count, "Left in the chain:"), false, "count: no prize panel")
    ns.Spoilers.setChoice("chains", "hidden")
    local hidden = draw(101)
    expectEqual(has(hidden, "more steps"), false, "hidden: no count")
    expectEqual(has(hidden, nextName), false, "hidden: no names")
end)

test("rewards: this quest only drops the chain's prize and the experience; hidden drops the rewards block", function()
    local ns, state = createAddon()
    setQuest(state, 101, false)
    local draw = openWindow(ns)
    local getRewards = ns.QuestState.getRewards
    ns.QuestState.getRewards = function() return { experience = 450, money = 120, items = {}, choices = {} } end
    local block = ns.LogState.rewardsBlock
    local guide = draw(101)
    expectEqual(has(guide, "Left in the chain:"), true, "Guide: the prize panel")
    local guideHeight = block.fullHeight
    expectEqual(guideHeight > 0, true, "Guide: the rewards block")
    ns.Spoilers.setChoice("rewards", "quest")
    expectEqual(has(draw(101), "Left in the chain:"), false, "this quest only: no chain totals")
    expectEqual(block.fullHeight > 0, true, "this quest only: its own rewards")
    ns.Spoilers.setChoice("rewards", "hidden")
    draw(101)
    expectEqual(block.fullHeight, 0, "hidden: no rewards block")
    ns.QuestState.getRewards = getRewards
end)

test("Need a hint? is on the page while a hint can help, and its ladder gives one step at a time", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(2, 12) })
    local draw = openWindow(ns)
    ns.Spoilers.setPreset("purist")
    expectEqual(has(draw(201), "Need a hint?"), true, "offered on the page")
    ns.Log.showHintLadder(201, nil)
    local ladder = ns.Log.getHintLadder()
    expectEqual(type(ladder) == "table" and ladder:IsShown() == true, true, "the ladder is open")
    expectEqual(ladder.rows[1].isNext, true, "the first step is next")
    expectEqual(ladder.rows[2].isNext, false, "the second waits")
    ladder.rows[2]:GetScript("OnClick")(ladder.rows[2])
    expectEqual(ns.Spoilers.getHint(201), 0, "a later step cannot be skipped to")
    ladder.rows[1]:GetScript("OnClick")(ladder.rows[1])
    expectEqual(ns.Spoilers.getHint(201), 1, "the zone given")
    expectEqual(ladder.rows[2].isNext, true, "the next step moves on")
    ladder.rows[2]:GetScript("OnClick")(ladder.rows[2])
    ladder.rows[3]:GetScript("OnClick")(ladder.rows[3])
    expectEqual(ns.Spoilers.getHint(201), 3, "all three")
    expectEqual(has(draw(201), "Need a hint?"), false, "nothing more to show: the button goes")
    ns.Spoilers.setChoice("hints", "off")
    expectEqual(has(draw(201), "Need a hint?"), false, "off: never offered")
end)

test("pickup: met lists only quests whose giver was met; none takes the Available tab away", function()
    local ns = createAddon()
    ns.Spoilers.create()
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 501) ~= nil, true, "a quest to pick up")
    expectEqual(#ns.LogList.keepToPickUp(quests, "all"), #quests, "all: every one")
    expectEqual(getQuest(ns.LogList.keepToPickUp(quests, "met"), 501), nil, "met: not before its giver was met")
    ns.Spoilers.setPreset("explorer")
    ns.Spoilers.getMemory().met[9003] = true
    expectEqual(getQuest(ns.LogList.keepToPickUp(quests, "met"), 501) ~= nil, true, "met: once met")
    expectEqual(#ns.LogList.keepToPickUp(quests, "none"), 0, "none: no quest")
    local draw = openWindow(ns)
    ns.Spoilers.setPreset("explorer")
    ns.Log.showAvailable()
    expectEqual(ns.Log.isShowingAvailable(), true, "met: the tab is there")
    ns.Spoilers.setChoice("pickup", "none")
    draw()
    expectEqual(ns.Log.isShowingAvailable(), false, "none: the window goes back to the log")
    ns.Log.showAvailable()
    expectEqual(ns.Log.isShowingAvailable(), false, "and cannot open on it")
end)

test("a reason naming an earlier quest says only later in the story while chains are held back", function()
    local ns = createAddon()
    ns.Spoilers.create()
    local blocker = { kind = "quest", text = "After Fresh Start", questId = 501 }
    expectEqual(ns.Availability.getShownReason(blocker), "After Fresh Start", "Guide: the quest named")
    ns.Spoilers.setPreset("explorer")
    expectEqual(ns.Availability.getShownReason(blocker), "Later in the story", "Explorer: later in the story")
    expectEqual(ns.Availability.getShownReason({ kind = "level", text = "Needs level 30" }), "Needs level 30", "a level is no spoiler")
    blocker.level = 30
    expectEqual(has(ns.Availability.getShownReason(blocker), "30"), true, "the level still to reach is said")
end)

test("warnings name no lead-in or other choice where the Spoilers choice keeps them back", function()
    local ns = createAddon()
    ns.Spoilers.create()
    ns.Availability.prepare()
    local guideWarnings, guideLinks = ns.Warnings.getQuestWarnings(509)
    expectEqual(next(guideLinks) ~= nil, true, "Guide links the lead-in")
    ns.Spoilers.setPreset("explorer")
    local warnings, links = ns.Warnings.getQuestWarnings(509)
    expectEqual(#warnings, #guideWarnings, "still warned")
    expectEqual(next(links), nil, "no quest to link")
    expectEqual(has(table.concat(warnings, " "), "Lead-in"), false, "the lead-in unnamed")
    local leadInWarnings = ns.Warnings.getQuestWarnings(510)
    expectEqual(has(table.concat(leadInWarnings, " "), "Main Quest"), false, "what a lead-in leads to unnamed")
    local choiceWarnings = ns.Warnings.getQuestWarnings(507)
    expectEqual(has(table.concat(choiceWarnings, " "), "1 other quest"), true, "a choice says how many it locks out")
end)

test("dungeons: entered lists only those entered or with the player's own quests; hidden takes the tab away", function()
    local ns = createAddon()
    addDungeon()
    local draw = openWindow(ns)
    ns.Availability.prepare()
    ns.Log.showDungeon(209)
    expectEqual(isListed(ns, -209), true, "Guide: the keep is listed")
    ns.Spoilers.setChoice("dungeons", "entered")
    draw()
    expectEqual(isListed(ns, -209), false, "entered: not before going in")
    ns.Spoilers.getMemory().entered[209] = true
    draw()
    expectEqual(isListed(ns, -209), true, "entered: once inside")
    ns.Spoilers.setChoice("dungeons", "hidden")
    draw()
    expectEqual(ns.Log.getShownDungeonId(), nil, "hidden: the window goes back to the log")
    ns.Log.showDungeon(209)
    expectEqual(ns.Log.getShownDungeonId(), nil, "and cannot open on it")
end)

test("the missed-quests report keeps quiet while quests to pick up are held back", function()
    local ns = createAddon()
    ns.Spoilers.create()
    ns.Spoilers.setPreset("explorer")
    local printed = {}
    local savedPrint = ns.print
    ns.print = function(text) printed[#printed + 1] = text end
    ns.MissedReport.printMissed()
    ns.print = savedPrint
    expectEqual(#printed, 1, "one line")
    expectEqual(has(printed[1], "waits"), true, "saying it waits")
end)

test("Purist: the window is still a log of the player's own quests", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(2, 12) })
    setQuest(state, 301, false, { killObjective(2, 12), itemObjective(0, 4) })
    local draw = openWindow(ns)
    ns.Spoilers.setPreset("purist")
    local page = draw(301)
    expectEqual(ns.Log.getSelectedQuestId(), 301, "its page is open")
    expectEqual(has(page, "To do"), true, "with what is left to do")
    expectEqual(page:find(" %d+, %d+") == nil, true, "and no place")
    expectEqual(isListed(ns, 201), true, "the other quest listed")
end)
