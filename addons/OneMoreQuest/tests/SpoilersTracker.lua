-- Tests: what the tracker, the creature and quest tooltips, the nameplates, the kill counter and the profit estimate
-- tell under each spoiler choice (Spoilers), and that in Guide they tell everything, as before.

---@return table ns, table state The addon with its spoiler choices read, in the preset given
local function createWith(preset)
    local ns, state = createAddon()
    ns.Spoilers.create()
    -- Every zone open, so each quest's lines are drawn wherever the player is
    ns.settings.collapsedZones = setmetatable({}, { __index = function() return false end })
    if preset then
        ns.Spoilers.setPreset(preset)
    end
    return ns, state
end

---@return string text Every line the tracker drew, its left and right texts, one line each
local function drawTracker(ns)
    ns.Tracker.create()
    ns.Tracker.refresh()
    local texts = {}
    for _, line in ipairs(ns.Tracker.getDrawnLines()) do
        texts[#texts + 1] = line.left .. " | " .. line.right
    end
    return table.concat(texts, "\n")
end

local function findLine(ns, pattern)
    for _, line in ipairs(ns.Tracker.getDrawnLines()) do
        if line.left:find(pattern, 1, true) then
            return line
        end
    end
    return nil
end

---Catches what goes into the game's tooltip, as text, a line each.
local function catchTooltip()
    local lines = {}
    rawset(GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = tostring(text) end)
    rawset(GameTooltip, "AddDoubleLine", function(_, left, right) lines[#lines + 1] = tostring(left) .. " = " .. tostring(right) end)
    return function()
        return table.concat(lines, "\n")
    end
end

---The game's menu, kept to be looked at and clicked: buttons by their text, radios with what they choose.
local function catchMenu()
    local menu = { buttons = {}, radios = {} }
    local function createDescription()
        local description = {}
        description.CreateTitle = function() end
        description.CreateDivider = function() end
        description.SetEnabled = function() end
        description.CreateButton = function(_, text, handler)
            local button = createDescription()
            button.handler = handler
            menu.buttons[text] = button
            return button
        end
        description.CreateRadio = function(_, text, isSelected, setSelected, data)
            menu.radios[#menu.radios + 1] = { text = text, isSelected = isSelected(data), choose = function() setSelected(data) end, parent = description }
        end
        return description
    end
    local saved = MenuUtil
    MenuUtil = { CreateContextMenu = function(owner, generator) generator(owner, createDescription()) return {} end }
    menu.restore = function() MenuUtil = saved end
    return menu
end

local function getEntry(ns, questId)
    for _, group in ipairs(ns.Model.compose(nil).groups) do
        for _, entry in ipairs(group.entries) do
            if entry.questId == questId then
                return entry, group
            end
        end
    end
    return nil
end

test("in Guide the tracker tells everything as before: the drop chance, the turn-in, the chain, the zone", function()
    local ns, state = createWith(nil)
    addProfitData()
    state.playerMapId = 1454 -- Orgrimmar
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    setQuest(state, 101, true)
    local text = drawTracker(ns)
    expectEqual(text:find("(25%)", 1, true) ~= nil, true, "the fang's drop chance")
    expectEqual(text:find("Turn in to Aide Rokka", 1, true) ~= nil, true, "who to hand it in to")
    expectEqual(text:find("1 of 3", 1, true) ~= nil, true, "the chain's step")
    local _, group = getEntry(ns, 301)
    expectEqual(group.zoneId, SILVERPINE, "under the zone of its next step")
    local _, deliveryGroup = getEntry(ns, 101)
    expectEqual(deliveryGroup.zoneId, ORGRIMMAR, "the delivery under where it is handed in")
    expectEqual(ns.KillCounter.getDropChance(301, 2), 0.25, "the kill counter tells the chance")
    expectEqual(ns.Model.getStructureKey():find("~guide", 1, true) ~= nil, true, "the map's key, the same as ever in Guide")
    expectEqual(findLine(ns, ns.L("Need a hint?")), nil, "no hint offered")
    removeProfitData()
end)

test("with drops as names only, no chance and no kill estimate is told; the creatures' names are", function()
    local ns, state = createWith("hints")
    addProfitData()
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(1, 4) })
    local text = drawTracker(ns)
    expectEqual(text:find("%)", 1, true), nil, "no chance after the fang")
    expectEqual(ns.KillCounter.getDropChance(301, 2), nil, "the kill counter keeps the chance")
    expectEqual(ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2]), nil, "and its estimate of kills")
    expectEqual(ns.KillCounter.getProgressForEstimate(301, 2, ns.QuestState.getQuest(301).objectives[2]) ~= nil, true,
        "the profit estimate still counts its kills")
    local read = catchTooltip()
    ns.Tracker.showTooltip(findLine(ns, "Wolf Fang").row)
    local tooltip = read()
    expectEqual(tooltip:find("Silverpine Wolf", 1, true) ~= nil, true, "who drops it")
    expectEqual(tooltip:find("%", 1, true), nil, "without a chance")
    expectEqual(tooltip:find(ns.L("Kills for drops"), 1, true), nil, "and no kills to go")
    -- A hint's last step shows the chances for that quest
    ns.Spoilers.giveHint(301, ns.Spoilers.HINT_EXACT)
    expectEqual(drawTracker(ns):find("(25%)", 1, true) ~= nil, true, "the hint lifts the chance")
    removeProfitData()
end)

test("with drops once found, only a creature that dropped the item is named; hidden, none", function()
    local ns, state = createWith("explorer")
    addProfitData()
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(1, 4) })
    drawTracker(ns)
    local read = catchTooltip()
    ns.Tracker.showTooltip(findLine(ns, "Wolf Fang").row)
    expectEqual(read():find("Silverpine Wolf", 1, true), nil, "not yet seen dropping it")
    ns.Spoilers.getMemory().drops[7001] = { [5002] = true }
    read = catchTooltip()
    ns.Tracker.showTooltip(findLine(ns, "Wolf Fang").row)
    expectEqual(read():find("Silverpine Wolf", 1, true) ~= nil, true, "named once it dropped one")
    ns.Spoilers.setChoice("drops", "hidden")
    read = catchTooltip()
    ns.Tracker.showTooltip(findLine(ns, "Wolf Fang").row)
    expectEqual(read():find("Silverpine Wolf", 1, true), nil, "hidden: nothing")
    removeProfitData()
end)

test("with objectives hidden a quest is listed where it was picked up, and the key of what is drawn moves on", function()
    local ns, state = createWith(nil)
    state.playerMapId = 1454 -- Orgrimmar
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    local guideKey = ns.Model.getStructureKey()
    ns.Spoilers.setPreset("purist")
    local _, group = getEntry(ns, 301)
    expectEqual(group.zoneId, TIRISFAL, "under where it was picked up, not where the fangs are")
    expectEqual(ns.Model.getStructureKey() ~= guideKey, true, "the map's key follows the choice")
    -- The zone's hint gives the zone back
    ns.Spoilers.giveHint(301, ns.Spoilers.HINT_ZONE)
    _, group = getEntry(ns, 301)
    expectEqual(group.zoneId, SILVERPINE, "the hint told the zone")
    -- With no zone it was picked up in: under "Quests"
    setQuest(state, 102, false, { killObjective(0, 3) })
    local _, loose = getEntry(ns, 102)
    expectEqual(loose.zoneName, ns.L("Quests"), "under no zone")
end)

test("the turn-in is told as chosen: hidden says only ready, met names them once met", function()
    local ns, state = createWith("purist")
    state.playerMapId = 1420
    setQuest(state, 101, true)
    local text = drawTracker(ns)
    expectEqual(text:find("Aide Rokka", 1, true), nil, "no name")
    expectEqual(text:find(ns.L("Ready to turn in"), 1, true) ~= nil, true, "only that it is ready")
    expectEqual(text:find("1 of 3", 1, true), nil, "no chain step while chains are hidden")
    local _, group = getEntry(ns, 101)
    expectEqual(group.zoneId, UNDERCITY, "under where it was picked up, not where it is handed in")
    ns.Spoilers.setPreset("explorer")
    expectEqual(drawTracker(ns):find("Aide Rokka", 1, true), nil, "not met yet")
    ns.Spoilers.getMemory().met[9001] = true
    expectEqual(drawTracker(ns):find("Turn in to Aide Rokka", 1, true) ~= nil, true, "met: named")
    expectEqual(drawTracker(ns):find("1 of 3", 1, true) ~= nil, true, "the chain's count is told")
    _, group = getEntry(ns, 101)
    expectEqual(group.zoneId, ORGRIMMAR, "and listed where it is handed in")
end)

test("a chain told by its count names no step ahead", function()
    local ns, state = createWith("hints")
    setQuest(state, 101, true)
    drawTracker(ns)
    local read = catchTooltip()
    ns.Tracker.showTooltip(ns.Tracker.getDrawnLines()[2].row)
    local tooltip = read()
    expectEqual(tooltip:find("Back to Work", 1, true), nil, "the last step unnamed")
    expectEqual(tooltip:find("2 more steps", 1, true) ~= nil, true, "only how many")
end)

test("Need a hint? is in a quest's menu while something is held back, and offers itself after a while", function()
    local ns, state = createWith(nil)
    setQuest(state, 301, false, { killObjective(2, 12) })
    drawTracker(ns)
    local menu = catchMenu()
    ns.Tracker.openQuestMenu(getEntry(ns, 301), UIParent)
    expectEqual(menu.buttons[ns.L("Need a hint?")], nil, "not in Guide")
    ns.Spoilers.setPreset("purist")
    menu.buttons = {}
    ns.Tracker.openQuestMenu(getEntry(ns, 301), UIParent)
    expectEqual(menu.buttons[ns.L("Set a waypoint")], nil, "no waypoint to a place held back")
    local savedLadder = ns.Log.showHintLadder
    ns.Log.showHintLadder = nil
    menu.buttons[ns.L("Need a hint?")].handler()
    expectEqual(ns.Spoilers.getHint(301), 1, "without the log's ladder, the next step at once")
    local asked
    ns.Log.showHintLadder = function(questId) asked = questId end
    menu.buttons[ns.L("Need a hint?")].handler()
    expectEqual(asked, 301, "the log's ladder opens for it")
    ns.Log.showHintLadder = savedLadder
    menu.restore()
    -- "Offered": twenty minutes in the zone with no progress
    ns.Spoilers.setPreset("explorer")
    expectEqual(findLine(ns, ns.L("Need a hint?")), nil, "not offered yet")
    local savedTime = GetTime
    GetTime = function() return 5000 end
    ns.Tracker.tick()
    local cue = findLine(ns, ns.L("Need a hint?"))
    expectEqual(cue ~= nil and cue.isHint, true, "the tick drew the offer")
    GetTime = savedTime
end)

test("the band's sort menu switches the spoiler preset", function()
    local ns = createWith(nil)
    ns.Tracker.create()
    local menu = catchMenu()
    -- (the sort button's click: the band's one button that is neither a filter nor the resize button)
    local created = {}
    local savedCreate = CreateFrame
    CreateFrame = function(...) local widget = savedCreate(...) created[#created + 1] = widget return widget end
    local bar = ns.Tracker.createFilterBar()
    CreateFrame = savedCreate
    for _, widget in ipairs(created) do
        local scripts = rawget(widget, "scripts")
        if scripts and scripts.OnClick and widget ~= bar.resize and not rawget(widget, "filter") then
            scripts.OnClick(widget)
        end
    end
    local presets = {}
    for _, radio in ipairs(menu.radios) do
        if radio.text == ns.L("Purist") then
            radio.choose()
        end
        presets[radio.text] = radio.isSelected
    end
    expectEqual(presets[ns.L("Guide")], true, "the one on, checked")
    expectEqual(ns.Spoilers.getPreset(), "purist", "picked from the menu")
    menu.restore()
end)

test("a creature's tooltip and nameplate follow the creatures' choice", function()
    local ns, state = createWith(nil)
    addProfitData()
    setQuest(state, 301, false, { killObjective(2, 12), itemObjective(1, 4) })
    expectEqual(#ns.UnitTooltip.compose(5001), 1, "in Guide the bandit is for the quest")
    expectEqual(ns.UnitTooltip.compose(5002)[1].lines[1].chance, 0.25, "and the wolf drops its fang, with the chance")
    expectEqual(ns.Nameplates.getKind(5001), "kill", "the bandit's plate")
    ns.Spoilers.setPreset("explorer")
    expectEqual(#ns.UnitTooltip.compose(5001), 0, "after the first kill only")
    expectEqual(ns.Nameplates.getKind(5001), nil, "no icon yet")
    ns.Spoilers.noteKill(5001)
    expectEqual(#ns.UnitTooltip.compose(5001), 1, "killed one: told")
    expectEqual(ns.Nameplates.getKind(5001), "kill", "and its plate has the icon")
    ns.Spoilers.setChoice("creatures", "always")
    ns.Spoilers.setChoice("drops", "names")
    expectEqual(ns.UnitTooltip.compose(5002)[1].lines[1].chance, nil, "names only: no chance")
    ns.Spoilers.setPreset("purist")
    expectEqual(#ns.UnitTooltip.compose(5001), 0, "hidden")
    expectEqual(ns.Nameplates.getKind(5001), nil, "no icon")
    removeProfitData()
end)

test("experience, money and the profit estimate follow the rewards' choice", function()
    local ns, state = createWith(nil)
    setQuest(state, 201, false, { killObjective(5, 12) })
    GetQuestLogRewardXP = function() return 850 end
    GetQuestLogRewardMoney = function() return 300 end
    local read = catchTooltip()
    ns.QuestTooltip.addTitle(GameTooltip, "Bandit Trouble", 201)
    expectEqual(read():find("850", 1, true) ~= nil, true, "the experience on the title in Guide")
    local profit = ns.Profit.compose(201)
    expectEqual(ns.Profit.format(profit) ~= nil, true, "the estimate")
    ns.Spoilers.setPreset("purist") -- (rewards: this quest only)
    read = catchTooltip()
    ns.QuestTooltip.addTitle(GameTooltip, "Bandit Trouble", 201)
    expectEqual(read():find("850", 1, true), nil, "no experience")
    expectEqual(ns.Profit.format(profit), nil, "no estimate")
    local savedShift = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    read = catchTooltip()
    ns.QuestTooltip.addDetails(GameTooltip, 201)
    local details = read()
    expectEqual(details:find(ns.Widgets.formatMoney(300), 1, true) ~= nil, true, "the quest's own money")
    expectEqual(details:find("Envoy Maldrek", 1, true), nil, "and no turn-in held back")
    ns.Spoilers.setChoice("rewards", "hidden")
    read = catchTooltip()
    ns.QuestTooltip.addDetails(GameTooltip, 201)
    expectEqual(read():find(ns.Widgets.formatMoney(300), 1, true), nil, "hidden: no money either")
    IsShiftKeyDown = savedShift
    GetQuestLogRewardXP, GetQuestLogRewardMoney = nil, nil
end)

test("a dungeon quest's tooltip names its dungeon, unless the dungeons' choice keeps it back", function()
    local ns, state = createWith(nil)
    addDungeon()
    setQuest(state, 601, false, { killObjective(0, 1) })
    C_QuestLog.GetQuestTagInfo = function(questId) return questId == 601 and { tagID = 81 } or nil end
    local read = catchTooltip()
    ns.QuestTooltip.addTitle(GameTooltip, "The Archivist's Notes", 601)
    expectEqual(read():find("Dungeon quest · Shadowfang Keep", 1, true) ~= nil, true, "in Guide: the kind and the dungeon")
    ns.Spoilers.setChoice("dungeons", "entered")
    read = catchTooltip()
    ns.QuestTooltip.addTitle(GameTooltip, "The Archivist's Notes", 601)
    local text = read()
    expectEqual(text:find("Dungeon quest", 1, true) ~= nil and text:find("Shadowfang", 1, true) == nil, true,
        "a dungeon not entered yet: the kind alone")
    read = catchTooltip()
    ns.QuestTooltip.addTitle(GameTooltip, "Bandit Trouble", 201)
    expectEqual(read():find("Dungeon quest", 1, true), nil, "an ordinary quest: no kind at all")
end)

test("the party's counts still show with everything held back", function()
    local ns, state = createWith("purist")
    installGroup(state)
    setQuest(state, 201, false, { killObjective(5, 12) })
    receive(ns, "OneMoreQuest", "1|U|201:7/12:0", "Mira Dawnfield")
    local read = catchTooltip()
    ns.Party.addProgressToTooltip(GameTooltip, 201, ns.QuestState.getQuest(201).objectives)
    expectEqual(read():find("7/12", 1, true) ~= nil, true, "their count")
    local savedAddOns = C_AddOns -- (kept for the tests after these)
    removeGroup()
    C_AddOns = savedAddOns
end)
