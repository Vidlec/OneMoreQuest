-- Tests: the tracker's model: where each quest is listed, its places and steps, focus and tracking.

test("a delivery quest is listed where it is handed in, not where it started", function()
    local ns, state = createAddon()
    state.playerMapId = 1458 -- Undercity, where the quest was accepted
    setQuest(state, 101, true)
    local model = ns.Model.compose()
    expectEqual(#model.groups, 1, "group count")
    expectEqual(model.groups[1].zoneId, ORGRIMMAR, "zone")
    expectEqual(model.groups[1].zoneName, "Orgrimmar", "zone name")
    expectEqual(model.groups[1].entries[1].isTurnIn, true, "turn-in")
    expectEqual(model.groups[1].entries[1].finisherName, "Aide Rokka", "finisher")
end)

test("an unfinished kill quest is listed where its mobs are, then moves to the turn-in zone", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    expectEqual(ns.Model.compose().groups[1].zoneId, TIRISFAL, "zone while killing")
    state.questLog[201] = { isComplete = true, objectives = { killObjective(12, 12) } }
    local model = ns.Model.compose()
    expectEqual(model.groups[1].zoneId, UNDERCITY, "zone when complete")
    expectEqual(model.groups[1].entries[1].finisherName, "Envoy Maldrek", "finisher")
end)

test("spawns in a subzone count for the zone it belongs to", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(0, 12) })
    local group = getGroup(ns.Model.compose(), TIRISFAL)
    expectEqual(group ~= nil, true, "Tirisfal group exists")
    expectEqual(getGroup(ns.Model.compose(), 159), nil, "no Brill group")
end)

test("with objectives in two zones the quest follows what is left", function()
    local ns, state = createAddon()
    state.playerMapId = 1454 -- Orgrimmar, away from both
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    expectEqual(ns.Model.compose().groups[1].zoneId, SILVERPINE, "zone with the kill part done")
end)

test("with objectives in two zones the player's zone wins", function()
    local ns, state = createAddon()
    state.playerMapId = 1421 -- Silverpine Forest
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    expectEqual(ns.Model.compose().groups[1].zoneId, SILVERPINE, "zone in Silverpine")
    state.playerMapId = 1420
    expectEqual(ns.Model.compose().groups[1].zoneId, TIRISFAL, "zone in Tirisfal")
end)

test("an objective with no known place keeps the quest in its own zone", function()
    local ns, state = createAddon()
    setQuest(state, 401, false, { killObjective(0, 5) })
    expectEqual(ns.Model.compose().groups[1].zoneId, SILVERPINE, "zone")
end)

test("a quest of a category such as cooking is listed under the category, after the zones", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 606, false, { itemObjective(0, 4) })
    local groups = ns.Model.compose().groups
    local last = groups[#groups]
    expectEqual(last.zoneId, -304, "the cooking group")
    expectEqual(last.zoneName, "Cooking", "named as the game names it")
    expectEqual(last.isCategory, true, "a category, not a place")
    expectEqual(groups[1].zoneId ~= -304, true, "zones come first")
    expectEqual(#last.entries[1].places > 0, true, "its places are still the item's")
    expectEqual(ns.Database.getCategoryIcon(-304), "Interface\\Icons\\INV_Misc_Food_15", "cooking's own picture")
    CLASS_ICON_TCOORDS = { WARLOCK = { 0.75, 1, 0.25, 0.5 } }
    expectEqual(select(2, ns.Database.getCategoryIcon(-61))[1], 0.75, "a class's round icon")
    CLASS_ICON_TCOORDS = nil
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.refresh()
end)

test("chain steps are counted in both directions", function()
    local ns = createAddon()
    local index, total = ns.Chain.getStep(102)
    expectEqual(index, 2, "index of the middle quest")
    expectEqual(total, 3, "total")
    index, total = ns.Chain.getStep(101)
    expectEqual(index, 1, "index of the first quest")
    expectEqual(total, 3, "total from the first quest")
    expectEqual(ns.Chain.getStep(201), nil, "a quest outside a chain")
end)

test("distance and direction point at the nearest spawn", function()
    local ns, state = createAddon()
    state.playerX, state.playerY = 0.5, 0.5 -- 100 yards west of the spawn at 60, 50
    setQuest(state, 201, false, { killObjective(0, 12) })
    local entry = ns.Model.compose().groups[1].entries[1]
    expectEqual(math.floor(entry.distance + 0.5), 100, "distance")
    expectEqual(entry.direction, "east", "direction")
    state.playerX, state.playerY = 0.6, 0.8 -- 300 yards south of it
    entry = ns.Model.compose().groups[1].entries[1]
    expectEqual(math.floor(entry.distance + 0.5), 280, "distance to the Brill spawn at 61, 52")
    expectEqual(entry.direction, "north", "direction")
end)

test("no distance inside an instance or across continents", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(0, 12) })
    state.isInInstance = true
    expectEqual(ns.Model.compose().groups[1].entries[1].distance, nil, "distance in an instance")
    state.isInInstance = false
    state.playerMapId = 1454
    expectEqual(ns.Model.compose().groups[1].entries[1].distance, nil, "distance from another continent")
end)

test("the current zone comes first and other zones start collapsed", function()
    local ns, state = createAddon()
    state.playerMapId = 1420
    setQuest(state, 101, true) -- Orgrimmar, ready to hand in
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) }) -- Silverpine Forest
    setQuest(state, 201, false, { killObjective(5, 12) }) -- Tirisfal Glades
    local model = ns.Model.compose()
    expectEqual(model.groups[1].zoneId, TIRISFAL, "first group")
    expectEqual(model.groups[1].isCurrent, true, "first group is current")
    expectEqual(model.groups[1].isCollapsed, false, "current zone open")
    expectEqual(model.groups[2].zoneId, ORGRIMMAR, "zone with a turn-in second")
    expectEqual(model.groups[2].isCollapsed, false, "zone with a turn-in open")
    expectEqual(getGroup(model, SILVERPINE).isCollapsed, true, "other zone collapsed")
    expectEqual(model.activeQuestId, nil, "no quest is active until the player picks one")
end)

test("a zone the player opened or closed by hand stays that way", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.settings.collapsedZones[TIRISFAL] = true
    expectEqual(ns.Model.compose().groups[1].isCollapsed, true, "collapsed by hand")
end)

test("a quest the player picked stays active while it is tracked", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    expectEqual(ns.Model.compose(301).activeQuestId, 301, "picked quest")
    expectEqual(ns.Model.compose(999).activeQuestId, nil, "an untracked pick means none is active")
end)

test("without QuestieDB quests still list, under an unknown location", function()
    local ns, state = createAddon()
    LibQuestieDB = nil
    setQuest(state, 201, false, { killObjective(5, 12) })
    local model = ns.Model.compose()
    expectEqual(model.groups[1].zoneId, 0, "zone")
    expectEqual(model.groups[1].zoneName, "Unknown location", "zone name")
end)

test("with the setting on, a quest moving on is not tracked by it: only taking it or tracking it does", function()
    local ns, state = createAddon()
    local isWatched = function(questId)
        for _, watchedQuestId in ipairs(state.watchedQuestIds) do
            if watchedQuestId == questId then
                return true
            end
        end
        return false
    end
    for _, questId in ipairs({ 501, 502, 503 }) do
        state.questLog[questId] = { isComplete = false, objectives = { killObjective(0, 5) } }
    end
    ns.QuestState.noteWatchEvent("QUEST_WATCH_LIST_CHANGED") -- (what is tracked, first seen: nothing)
    -- Off (as it comes): the game's way, a quest that moves on is tracked
    expectEqual(ns.settings.shouldKeepUntracked, false, "off unless the player turns it on")
    C_QuestLog.AddQuestWatch(501)
    ns.QuestState.noteWatchEvent("QUEST_WATCH_UPDATE", 501)
    expectEqual(isWatched(501), true, "off: the game's tracking of a quest that moved on stays")
    C_QuestLog.RemoveQuestWatch(501)
    ns.QuestState.noteWatchEvent("QUEST_WATCH_LIST_CHANGED")
    -- On: an item picked up for an untracked quest, the game tracks it (autoQuestWatch), then says it moved on
    ns.settings.shouldKeepUntracked = true
    C_QuestLog.AddQuestWatch(501)
    ns.QuestState.noteWatchEvent("QUEST_WATCH_UPDATE", 501)
    expectEqual(isWatched(501), false, "on: tracked by the game for moving on, untracked again")
    -- The player tracks a quest that just moved on: kept
    ns.QuestState.noteWatchEvent("QUEST_WATCH_UPDATE", 502)
    expectEqual(ns.QuestState.addWatch(502), true, "the player tracks it")
    ns.QuestState.noteWatchEvent("QUEST_WATCH_LIST_CHANGED")
    expectEqual(isWatched(502), true, "the player's own tracking stays")
    -- A quest just taken, tracked by the game as it is taken, moving on at once (its items already carried): kept
    ns.QuestState.noteWatchEvent("QUEST_ACCEPTED", 503)
    C_QuestLog.AddQuestWatch(503)
    ns.QuestState.noteWatchEvent("QUEST_WATCH_UPDATE", 503)
    expectEqual(isWatched(503), true, "a quest just taken keeps the tracking it was taken with")
end)

test(
    "tracking past the game's limit is refused with the game's message, and unfocusing keeps the quest open",
    function()
        local ns, state = createAddon()
        local shown
        UIErrorsFrame = {
            AddMessage = function(_, text)
                shown = text
            end,
        }
        for questId = 1001, 1025 do
            state.watchedQuestIds[#state.watchedQuestIds + 1] = questId
        end
        state.questLog[201] = { isComplete = false, objectives = { killObjective(5, 12) } }
        expectEqual(ns.QuestState.addWatch(201), false, "the 26th quest is not tracked")
        expectEqual(shown ~= nil, true, "and the player is told why")
        state.watchedQuestIds = {}
        shown = nil
        expectEqual(ns.QuestState.addWatch(201), true, "with room, it is tracked")
        expectEqual(shown, nil, "without a message")
        ns.Tracker.create()
        ns.Log.create()
        ns.MapDock.create()
        ns.MapDock.apply()
        ns.Log.toggle()
        ns.Log.selectQuest(201)
        ns.Focus.set(201)
        ns.Focus.set(nil)
        expectEqual(ns.Log.getSelectedQuestId(), 201, "taking the focus off leaves the quest open")
        expectEqual(ns.MapMarks.getFocusedQuestId(), nil, "but the map no longer shows it as the one in focus")
        ns.Log.selectQuest(201)
        expectEqual(ns.MapMarks.getFocusedQuestId(), 201, "till it is picked again")
        state.watchedQuestIds = {}
        ns.Focus.handleQuestGone(201)
        expectEqual(ns.Log.getSelectedQuestId(), 201, "and so does untracking it")
        state.questLog[201] = nil
        ns.Focus.handleQuestGone(201)
        expectEqual(ns.Log.getSelectedQuestId(), nil, "a quest that left the log is let go")
        UIErrorsFrame = nil
    end
)

test("timed, failed and escort quests are recognised, and the tracker draws them", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    expectEqual(ns.QuestState.getTimeLeft(201), nil, "no time limit")
    C_QuestLog.GetTimeAllowed = function(questId)
        if questId == 201 then
            return 900, 300
        end
    end
    expectEqual(ns.QuestState.getTimeLeft(201), 600, "ten minutes left")
    C_QuestLog.IsFailed = function(questId)
        return questId == 201
    end
    expectEqual(ns.QuestState.isFailed(201), true, "failed")
    expectEqual(ns.QuestState.isEscort(201), false, "not an escort")
    ns.Tracker.create()
    ns.Tracker.refresh()
    C_QuestLog.IsFailed = nil
    ns.Tracker.refresh()
    -- Progress since the last look flashes; the first look only takes note
    state.questLog[201].objectives = { killObjective(6, 12) }
    ns.Tracker.refresh()
    state.questLog[201] = { isComplete = true, objectives = { killObjective(12, 12) } }
    ns.Tracker.refresh()
    C_QuestLog.GetTimeAllowed = nil
end)

test("hovering a quest in the tracker says what drops each item still to get", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    local entry = ns.Model.composeEntry(301, ns.Model.getPlayer())
    ns.Location.getObjectiveTarget = function(questId, kind)
        if kind == "item" then
            return { itemId = 5175 }
        end
    end
    ns.Drops.getZones = function()
        return { { sources = { { name = "Kraul Bat", chance = 0.09 }, { name = "Supply Crate" } } } }
    end
    local lines = {}
    local savedTooltip = GameTooltip
    GameTooltip = setmetatable({
        AddLine = function(_, text)
            lines[#lines + 1] = text
        end,
        AddDoubleLine = function(_, left, right)
            lines[#lines + 1] = left .. "|" .. tostring(right)
        end,
    }, {
        __index = function()
            return function() end
        end,
    })
    ns.Tracker.showTooltip({ entry = entry })
    local text = table.concat(lines, "\n")
    expectEqual(
        text:find("Kraul Bat|" .. ns.Drops.formatChance(0.09), 1, true) ~= nil,
        true,
        "the creature that drops it, with its chance"
    )
    expectEqual(text:find("Supply Crate", 1, true) ~= nil, true, "and an object that holds it")
    lines = {}
    entry.objectives[2].isFinished = true
    ns.Tracker.showTooltip({ entry = entry })
    expectEqual(table.concat(lines, "\n"):find("Kraul Bat", 1, true), nil, "nothing for an item already got")
    GameTooltip = savedTooltip
end)

test("a quest's usable item is offered until the quest is complete", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    local entry = ns.Model.compose().groups[1].entries[1]
    expectEqual(entry.item ~= nil, true, "item while the quest is open")
    expectEqual(entry.item.name, "Sampling Vial", "name")
    expectEqual(entry.item.itemId, 7003, "item ID")
    expectEqual(entry.item.count, 3, "charges")
    state.questLog[201] = { isComplete = true, objectives = { killObjective(12, 12) } }
    expectEqual(ns.Model.compose().groups[1].entries[1].item, nil, "no item once complete")
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    expectEqual(ns.Model.composeEntry(301, ns.Model.getPlayer()).item, nil, "a quest without an item")
end)

test("untracking the highlighted quest takes the highlight off", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    ns.Tracker.create()
    ns.Focus.set(201)
    ns.Focus.handleQuestGone(301)
    expectEqual(ns.Focus.get(), 201, "dropping another quest changes nothing")
    C_QuestLog.RemoveQuestWatch(201)
    ns.Focus.handleQuestGone(201)
    expectEqual(ns.Focus.get(), nil, "nothing highlighted")
    C_QuestLog.AddQuestWatch(201)
    ns.Tracker.refresh()
    expectEqual(ns.Focus.get(), nil, "tracking it again does not bring the highlight back")
end)

test("the focus is remembered, and taking it off leaves no quest highlighted", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    ns.Tracker.create()
    expectEqual(ns.Focus.get(), nil, "nothing in focus to begin with")
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "objective"), 1, "every quest is a quiet mark")
    ns.Focus.set(301)
    expectEqual(ns.Focus.get(), 301, "the picked quest")
    local savedSettings = ns.settings
    -- A reload: a fresh copy of the addon with the saved settings
    local reloaded = {}
    for _, file in ipairs(FILES) do
        assert(loadfile(file))("OneMoreQuest", reloaded)
    end
    reloaded.loadSettings(savedSettings)
    reloaded.Focus.create()
    expectEqual(reloaded.Focus.get(), 301, "still in focus after the reload")
    reloaded.Focus.set(nil)
    expectEqual(reloaded.Focus.get(), nil, "focus taken off")
    expectEqual(savedSettings.focusedQuestIds["nil-?"] or savedSettings.focusedQuestIds["?-?"], nil, "and forgotten")
end)

test("tracking a quest in the quest log leaves it where it is in its group", function()
    local ns, state = createAddon()
    state.questLog[201] = { isComplete = false, objectives = { killObjective(5, 12) } } -- level 13, untracked
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) }) -- level 14, tracked
    local before = ns.Model.compose(nil, { questIds = { 301, 201 } }).groups[1].entries
    expectEqual(before[1].questId, 201, "the lower level comes first, tracked or not")
    state.watchedQuestIds = { 201 }
    local after = ns.Model.compose(nil, { questIds = { 301, 201 } }).groups[1].entries
    expectEqual(after[1].questId, 201, "and the order is the same whichever one is tracked")
    expectEqual(after[2].questId, 301, "for both")
end)

test("a group quest gets the game's plus and a players mark with the suggested size", function()
    local ns = createAddon()
    expectEqual(ns.QuestState.getGroupInfo(201), nil, "an ordinary quest has no group mark")
    expectEqual(ns.Widgets.formatQuestTitle(13, "Bandit Trouble", nil), "[13] Bandit Trouble", "and reads as before")
    C_QuestLog.GetQuestTagInfo = function(questId)
        return { tagID = questId == 201 and 1 or 81 }
    end
    C_QuestLog.GetSuggestedGroupSize = function(questId)
        return questId == 201 and 3 or 0
    end
    local group = ns.QuestState.getGroupInfo(201)
    expectEqual(group.kindText, "Group quest", "the game's label")
    expectEqual(group.size, 3, "and its suggested size")
    expectEqual(ns.QuestState.getGroupInfo(301).size, 5, "a dungeon quest with no size given takes a party")
    local title = ns.Widgets.formatQuestTitle(13, "Bandit Trouble", group)
    expectEqual(title:find("[13+] Bandit Trouble", 1, true), 1, "the plus follows the level")
    expectEqual(title:find("GlyphPlayers", 1, true) ~= nil, true, "and the players icon follows the name")
    C_QuestLog.GetQuestTagInfo, C_QuestLog.GetSuggestedGroupSize = nil, nil
end)

test("quests keep their order as the player moves", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    setQuest(state, 201, false, { killObjective(5, 12) })
    state.playerX, state.playerY = 0.6, 0.5
    local before = ns.Model.compose().groups[1].entries
    state.playerX, state.playerY = 0.1, 0.9
    local after = ns.Model.compose().groups[1].entries
    expectEqual(before[1].questId, 301, "the quest tracked first comes first")
    expectEqual(after[1].questId, before[1].questId, "and stays first after moving")
    expectEqual(after[2].questId, before[2].questId, "as does the second")
end)

test("an item players make says how to get it: the profession, and the player's skill when they have it", function()
    local ns = createAddon()
    ns.CraftedItems[9001] = { 171, 0 } -- an alchemist's elixir, its recipe's skill not known
    ns.CraftedItems[9002] = { 164, 125 } -- a smith's piece, needing 125
    local ranks = {}
    ns.Availability.getSkillRank = function(skillId)
        return ranks[skillId] or 0
    end
    expectEqual(
        ns.Crafting.describe(9001),
        "Made with Alchemy · get it from a crafter or the Auction House",
        "no alchemy: where to get it"
    )
    ranks[171] = 165
    expectEqual(
        ns.Crafting.describe(9001),
        "Made with Alchemy · you can make it if you know the recipe (skill 165)",
        "an alchemist: they can make it"
    )
    ranks[164] = 90
    expectEqual(
        ns.Crafting.describe(9002),
        "Made with Blacksmithing 125 · you have 90",
        "not skilled enough yet: how far"
    )
    expectEqual(ns.Crafting.describe(7001), nil, "an item no one makes")
    -- With Auctionator's price: what it costs, for one who cannot make it
    local savedPrice = ns.Prices.getAuctionPrice
    ns.Prices.getAuctionPrice = function(itemId)
        return itemId == 9002 and 12050 or nil
    end
    ranks[164] = nil
    expectEqual(
        ns.Crafting.describe(9002),
        "Made with Blacksmithing 125 · get it from a crafter, or about "
            .. ns.Widgets.formatMoney(12050)
            .. " at the Auction House",
        "the auction price"
    )
    ns.Prices.getAuctionPrice = savedPrice
    -- The profession window lists the recipe: known from then on
    ranks[171] = 165
    local savedLine, savedCount, savedInfo, savedLink =
        GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillItemLink
    GetTradeSkillLine = function()
        return "Alchemy", 165, 300
    end
    GetNumTradeSkills = function()
        return 2
    end
    GetTradeSkillInfo = function(index)
        return index == 1 and "Elixirs" or "An Elixir", index == 1 and "header" or "optimal"
    end
    GetTradeSkillItemLink = function(index)
        return index == 2 and "|cffffffff|Hitem:9001::::::::|h[An Elixir]|h|r" or nil
    end
    expectEqual(ns.Crafting.readProfessionWindow(), true, "a recipe learnt from the window")
    expectEqual(ns.Crafting.readProfessionWindow(), false, "and not again")
    expectEqual(ns.Crafting.describe(9001), "Made with Alchemy · you know the recipe", "known: said so")
    GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillItemLink =
        savedLine, savedCount, savedInfo, savedLink
    ns.settings.knownRecipes = nil
    -- WoW: Forever's window, through C_TradeSkillUI: only the learnt recipe counts
    local savedUi = C_TradeSkillUI
    C_TradeSkillUI = {
        GetAllRecipeIDs = function()
            return { 101, 102 }
        end,
        GetRecipeInfo = function(recipeId)
            return { learned = recipeId == 101 }
        end,
        GetRecipeSchematic = function(recipeId)
            return { outputItemID = recipeId == 101 and 9001 or 9002 }
        end,
    }
    expectEqual(ns.Crafting.readProfessionWindow(), true, "read through C_TradeSkillUI")
    expectEqual(ns.Crafting.isRecipeKnown(9001), true, "the learnt recipe's item")
    expectEqual(ns.Crafting.isRecipeKnown(9002), false, "not one listed but not learnt")
    local savedPrice2 = ns.Prices.getAuctionPrice
    ns.Prices.getAuctionPrice = function()
        return 12050
    end
    expectEqual(
        ns.Crafting.describe(9001),
        "Made with Alchemy · you know the recipe · about " .. ns.Widgets.formatMoney(12050) .. " at the Auction House",
        "known, and its price to buy rather than make"
    )
    ns.Prices.getAuctionPrice = savedPrice2
    -- What the quest still asks for, less what waits in the bank: priced for the rest, the bank's said
    ns.Prices.getAuctionPrice = function()
        return 7399
    end
    local savedItem = C_Item
    local bags, bank = 0, 0
    C_Item = setmetatable({
        GetItemCount = function(_, includeBank)
            return bags + (includeBank and bank or 0)
        end,
    }, { __index = savedItem })
    expectEqual(
        ns.Crafting.describe(9001, 4),
        "Made with Alchemy · you know the recipe · about "
            .. ns.Widgets.formatMoney(7399 * 4)
            .. " for 4 at the Auction House",
        "four still needed: priced for four"
    )
    bank = 2
    expectEqual(
        ns.Crafting.describe(9001, 4),
        "Made with Alchemy · you know the recipe · about "
            .. ns.Widgets.formatMoney(7399 * 2)
            .. " for 2 at the Auction House · 2 in your bank",
        "two in the bank: the other two priced"
    )
    bank = 5
    expectEqual(
        ns.Crafting.describe(9001, 4),
        "Made with Alchemy · you know the recipe · 5 in your bank",
        "the bank has enough: no price"
    )
    C_Item = savedItem
    ns.Prices.getAuctionPrice = savedPrice2
    C_TradeSkillUI = savedUi
    ns.settings.knownRecipes = nil -- the rest asks as one who has not opened the window
    -- On the quest page's objective: found by its name when the database's quest does not list it, and said instead of
    -- "not on the map"
    local savedIdsByName = LibQuestieDB.Item.IdsByName
    LibQuestieDB.Item.IdsByName = function(name)
        return name == "Lesser Troll's Blood Elixir" and { 9001 } or nil
    end
    local _, text, isCrafted = ns.Location.getObjectiveInfo(201, "item", 9, "Lesser Troll's Blood Elixir")
    expectEqual(text, "Made with Alchemy · you can make it if you know the recipe (skill 165)", "found by its name")
    expectEqual(isCrafted, true, "and marked as made, so the page says this instead of where")
    LibQuestieDB.Item.IdsByName = savedIdsByName
    -- The real table holds the game's crafted items: the troll's blood elixir is alchemy's
    expectEqual(ns.CraftedItems[3388][1], 171, "Lesser Troll's Blood Elixir is made with Alchemy")
end)

test("a crafted item's price on the quest page is for how many the quest still asks for", function()
    local ns, state = createAddon()
    local Quest = LibQuestieDB.Quest
    local savedQuest, savedPrice = Quest.Get, ns.Prices.getAuctionPrice
    Quest.Get = function(id, field)
        if id == 9400 then
            return ({
                name = "On Bronze Pauldrons",
                questLevel = 32,
                zoneOrSort = -121,
                finishedBy = { { 9002 } },
                objectives = { nil, nil, { { 9401 } } },
            })[field]
        end
        return savedQuest(id, field)
    end
    ns.CraftedItems[9401] = { 164, 0 }
    ns.Prices.getAuctionPrice = function(itemId)
        return itemId == 9401 and 7399 or nil
    end
    state.questLog[9400] = { isComplete = false, objectives = { itemObjective(1, 4) } }
    local entry = ns.Model.composeEntry(9400, ns.Model.getPlayer())
    local details = ns.LogQuestPage.composeObjectiveDetails(entry)
    expectEqual(
        details[1].sourceText:find(
            "about " .. ns.Widgets.formatMoney(7399 * 3) .. " for 3 at the Auction House",
            1,
            true
        ) ~= nil,
        true,
        "1 of 4 made: the other three priced"
    )
    Quest.Get, ns.Prices.getAuctionPrice = savedQuest, savedPrice
end)

test("a profession quest whose items have nowhere to go is listed by its turn-in's zone but marked nowhere", function()
    local ns, state = createAddon()
    -- Filed under Blacksmithing (a category, below 0), asking for an item no creature, vendor or object gives
    local Quest = LibQuestieDB.Quest
    local savedQuest = Quest.Get
    Quest.Get = function(id, field)
        if id == 9400 then
            return ({
                name = "On Bronze Pauldrons",
                questLevel = 32,
                zoneOrSort = -121,
                finishedBy = { { 9002 } },
                objectives = { nil, nil, { { 9401 } } },
            })[field]
        end
        return savedQuest(id, field)
    end
    state.questLog[9400] = { isComplete = false, objectives = { itemObjective(0, 4) } }
    local entry = ns.Model.composeEntry(9400, ns.Model.getPlayer())
    expectEqual(entry.zoneId, 1497, "listed under Undercity, where it is handed in")
    expectEqual(#entry.places, 0, "but no place to mark: the turn-in is not the next step")
    expectEqual(entry.nearestPlace, nil, "so no minimap mark either")
    local function pendingMarks()
        local count = 0
        for _, mark in ipairs(ns.MapMarks.compose(1458)) do
            count = count + (mark.isPending and 1 or 0)
        end
        return count
    end
    state.watchedQuestIds = { 9400 }
    expectEqual(pendingMarks(), 0, "not focused: no grey ? on the map")
    ns.Focus.set(9400)
    expectEqual(pendingMarks(), 1, "focused: the game's ? in grey where it will be handed in")
    ns.Focus.set(nil)
    local savedOpen, savedSelected, savedUnfocused =
        ns.Log.isOpen, ns.Log.getSelectedQuestId, ns.Log.isUnfocusedSelection
    ns.Log.isOpen, ns.Log.getSelectedQuestId =
        function()
            return true
        end, function()
            return 9400
        end
    ns.Log.isUnfocusedSelection = function()
        return false
    end -- (picked in the log, not just unfocused)
    expectEqual(pendingMarks(), 1, "highlighted in the open quest log, not followed: grey ? too")
    ns.Log.isOpen, ns.Log.getSelectedQuestId, ns.Log.isUnfocusedSelection = savedOpen, savedSelected, savedUnfocused
    ns.Focus.set(9400)
    state.questLog[9400] = { isComplete = true, objectives = { itemObjective(4, 4) } }
    expectEqual(#ns.Model.composeEntry(9400, ns.Model.getPlayer()).places > 0, true, "ready: the turn-in is marked")
    expectEqual(pendingMarks(), 0, "and no longer grey")
    Quest.Get = savedQuest
end)

test("a quest's people are not sent to in the other faction's towns, when they stand somewhere else too", function()
    local ns, state = createAddon()
    -- A town of the Alliance in zone 85 (ten of its people round 20,20), and a Kirin Tor image friendly to both sides
    -- standing there and out by a lake at 80,80; a quest handed in to her
    local Npc, Quest = LibQuestieDB.Npc, LibQuestieDB.Quest
    local savedNpc, savedIds, savedQuest = Npc.Get, Npc.GetAllIds, Quest.Get
    local extraNpcs = {
        [9100] = {
            name = "Image of an Archmage",
            friendlyToFaction = "AH",
            spawns = { [85] = { { 20, 20 }, { 80, 80 } } },
        },
    }
    for index = 1, 10 do
        extraNpcs[9200 + index] =
            { name = "Town guard", friendlyToFaction = "A", spawns = { [85] = { { 18 + index % 4, 19 + index % 3 } } } }
    end
    Npc.Get = function(id, field)
        if extraNpcs[id] then
            return extraNpcs[id][field]
        end
        return savedNpc(id, field)
    end
    Npc.GetAllIds = function()
        local ids = savedIds()
        for id in pairs(extraNpcs) do
            ids[#ids + 1] = id
        end
        return ids
    end
    Quest.Get = function(id, field)
        if id == 9300 then
            return ({ name = "Shrewd Talk", finishedBy = { { 9100 } } })[field]
        end
        if id == 9301 then
            return ({ name = "Free From the Fort", finishedBy = { { 9101 } } })[field]
        end
        return savedQuest(id, field)
    end
    state.playerFaction = "Horde"
    local places = ns.Location.getFinisherPlaces(9300)
    expectEqual(#places, 1, "the Horde: one place, not the Alliance town")
    expectEqual(places[1].x, 80, "the one by the lake")
    expectEqual(ns.Database.isNpcFriendly(9100), true, "she still deals with the Horde")
    state.playerFaction = "Alliance"
    expectEqual(#ns.Location.getFinisherPlaces(9300), 2, "the Alliance: both")
    -- Standing only in the other side's town (a prisoner in an enemy fort), the place is kept: somewhere to go
    extraNpcs[9101] = { name = "Prisoner", friendlyToFaction = "AH", spawns = { [85] = { { 20, 20 } } } }
    state.playerFaction = "Horde"
    local prisonPlaces = ns.Location.getFinisherPlaces(9301)
    expectEqual(#prisonPlaces == 1 and prisonPlaces[1].x, 20, "only in the town: kept")
    Npc.Get, Npc.GetAllIds, Quest.Get = savedNpc, savedIds, savedQuest
end)

test("the tracker's focus is the game's own: kept from the game at login, and following it after", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(0, 8) })
    setQuest(state, 301, false, { killObjective(0, 5) })
    local superTracked = 301
    local saved = C_SuperTrack
    C_SuperTrack = {
        GetSuperTrackedQuestID = function()
            return superTracked
        end,
        SetSuperTrackedQuestID = function(questId)
            superTracked = questId
        end,
    }
    ns.settings.focusedQuestIds = { ["nil-?"] = 201, ["?-?"] = 201 } -- this addon's own memory, for either fake name
    ns.Focus.create()
    ns.Tracker.create()
    ns.Tracker.refresh()
    expectEqual(ns.Focus.get(), 301, "the game's focus, though this addon remembered another")
    superTracked = 201
    ns.Focus.handleGameFocusChanged()
    expectEqual(ns.Focus.get(), 201, "the game's focus changed: the tracker's follows")
    superTracked = 0 -- the game's arrow on a map waypoint
    ns.Focus.handleGameFocusChanged()
    expectEqual(ns.Focus.get(), 201, "a waypoint is not a quest: the focus stays")
    C_SuperTrack = saved
end)

test("the game's focus is set only for the player's own choices, never from the game's events", function()
    -- Setting it inside an event makes the game update its tracker in this addon's code, where reading the player's
    -- auras fails ("tainted by ForceTaint_Strong", on handing in The Den)
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(0, 8) })
    local superTracked, calls = 201, 0
    local saved = C_SuperTrack
    C_SuperTrack = {
        GetSuperTrackedQuestID = function()
            return superTracked
        end,
        SetSuperTrackedQuestID = function(questId)
            superTracked = questId
            calls = calls + 1
        end,
    }
    ns.Focus.create()
    ns.Focus.handleGameFocusChanged()
    expectEqual(calls, 0, "following the game's focus does not set it back")
    ns.handleEvent(nil, "QUEST_TURNED_IN", 201)
    expectEqual(calls, 0, "a quest handed in: the game drops its own focus")
    expectEqual(ns.Focus.getPicked(), nil, "and this addon lets go of it too")
    ns.Focus.set(201)
    expectEqual(calls, 1, "the player's own choice sets the game's focus")
    C_SuperTrack = saved
end)

test(
    'with "Focus quests you accept" off, the game focusing a quest just accepted leaves the focus where it was',
    function()
        local ns, state = createAddon()
        setQuest(state, 201, false, { killObjective(0, 8) })
        setQuest(state, 301, false, { killObjective(0, 8) })
        local superTracked = 201
        local saved = C_SuperTrack
        C_SuperTrack = {
            GetSuperTrackedQuestID = function()
                return superTracked
            end,
            SetSuperTrackedQuestID = function(questId)
                superTracked = questId
            end,
        }
        ns.Focus.create()
        -- On: the game's focus on the new quest is followed
        ns.handleEvent(nil, "QUEST_ACCEPTED", 301)
        superTracked = 301
        ns.Focus.handleGameFocusChanged()
        expectEqual(ns.Focus.getPicked(), 301, "on: the quest accepted goes into focus")
        -- Off, the game focusing it after the quest is accepted
        ns.Focus.set(201)
        ns.settings.shouldFocusAccepted = false
        ns.handleEvent(nil, "QUEST_ACCEPTED", 301)
        superTracked = 301
        ns.Focus.handleGameFocusChanged()
        expectEqual(ns.Focus.getPicked(), 201, "off: the quest in focus stays")
        -- Off, the game focusing it before the event comes (the older clients' order: log index, then the quest)
        ns.Focus.set(201)
        superTracked = 301
        ns.Focus.handleGameFocusChanged()
        ns.handleEvent(nil, "QUEST_ACCEPTED", 3, 301)
        expectEqual(ns.Focus.getPicked(), 201, "off, either order: the quest in focus stays")
        -- The player's own choice is never undone
        ns.Focus.set(301)
        expectEqual(ns.Focus.getPicked(), 301, "the player can still focus it")
        C_SuperTrack = saved
    end
)

test("a category's group opens when a quest's next step is where the player is, and stays folded elsewhere", function()
    local ns, state = createAddon()
    setQuest(state, 606, false, { itemObjective(0, 4) }) -- a cooking quest
    local function getCookingGroup()
        for _, group in ipairs(ns.Model.compose().groups) do
            if group.zoneId == -304 then
                return group
            end
        end
    end
    local stepZoneId = getCookingGroup().entries[1].zoneId
    local stepMapId = ns.Database.getUiMapId(stepZoneId)
    expectEqual(stepMapId ~= nil, true, "the quest's next step is on a map")
    state.playerMapId = stepMapId == 1420 and 1421 or 1420 -- elsewhere
    expectEqual(getCookingGroup().isCollapsed, true, "folded while the player is elsewhere")
    state.playerMapId = stepMapId -- where its work is
    expectEqual(getCookingGroup().isCollapsed, false, "open where the player hunts for it")
end)

test(
    "the group hears in chat when an objective is done and when a quest is ready, once the player switches it on",
    function()
        local ns, state = createAddon()
        installGroup(state)
        local said = {}
        C_ChatInfo.SendChatMessage = function(text, channel)
            said[#said + 1] = channel .. " " .. text
        end
        state.questLog[301] = { isComplete = false, objectives = { killObjective(0, 12), itemObjective(3, 4) } }
        ns.Announce.reset()
        ns.Announce.check() -- the log as found: nothing to tell
        state.questLog[301].objectives[1] = killObjective(12, 12)
        ns.Announce.check()
        expectEqual(#said, 0, "off until switched on")
        ns.settings.shouldAnnounceObjectives, ns.settings.shouldAnnounceReady = true, true
        ns.Announce.check()
        expectEqual(#said, 0, "switching it on tells no old news")
        state.questLog[301] = { isComplete = false, objectives = { killObjective(12, 12), itemObjective(3, 5) } }
        ns.Announce.check()
        state.questLog[301].objectives[2] = itemObjective(5, 5)
        state.questLog[301].isComplete = true
        ns.Announce.check()
        expectEqual(#said, 1, "the last objective makes it ready: one line, not two")
        expectEqual(
            said[1]:find("^PARTY {rt1} OneMoreQuest: ") ~= nil,
            true,
            "in party chat, with the star and the name"
        )
        expectEqual(said[1]:find("is ready to hand in", 1, true) ~= nil, true, "ready to hand in")
        state.questLog[501] = { isComplete = false, objectives = { killObjective(1, 2), itemObjective(0, 1) } }
        ns.Announce.check() -- just taken
        state.questLog[501].objectives[2] = itemObjective(1, 1)
        ns.Announce.check()
        expectEqual(#said, 2, "an objective done on a quest not yet ready")
        expectEqual(
            said[2]:find("Wolf Fang 1/1 for ", 1, true) ~= nil,
            true,
            "names the objective and its count, then the quest"
        )
        removeGroup()
        state.questLog[501].objectives[1] = killObjective(2, 2)
        state.questLog[501].isComplete = true
        ns.Announce.check()
        expectEqual(#said, 2, "outside a group nothing is said")

        local shown = {}
        DEFAULT_CHAT_FRAME = {
            AddMessage = function(_, text)
                shown[#shown + 1] = text
            end,
        }
        ns.settings.shouldAnnounceSolo = true
        state.questLog[502] = { isComplete = false, objectives = { itemObjective(0, 1) } }
        ns.Announce.check()
        state.questLog[502].objectives[1] = itemObjective(1, 1)
        state.questLog[502].isComplete = true
        ns.Announce.check()
        expectEqual(#said, 2, "playing alone, still nothing is sent")
        expectEqual(#shown, 1, "but the player sees it in their own chat")
        expectEqual(
            shown[1]:find("OneMoreQuest:", 1, true) ~= nil and shown[1]:find("{rt1}", 1, true) == nil,
            true,
            "named, without the raid star"
        )
        DEFAULT_CHAT_FRAME = nil
    end
)

test("as the log fills, grey quests and ones taken days ago are suggested for dropping; never a ready one", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12) })
    setQuest(state, 302, false, { killObjective(0, 5) })
    setQuest(state, 303, true, { killObjective(5, 5) })
    local savedSize = ns.QuestState.getLogSize
    ns.QuestState.getLogSize = function()
        return 10, 25
    end
    expectEqual(#ns.Warnings.getDropSuggestions(), 0, "nothing while the log has room")
    ns.QuestState.getLogSize = function()
        return 22, 25
    end
    state.playerLevel = 60
    local suggestions = ns.Warnings.getDropSuggestions()
    local byQuestId = {}
    for _, suggestion in ipairs(suggestions) do
        byQuestId[suggestion.questId] = suggestion.reason
    end
    expectEqual(byQuestId[301] ~= nil and byQuestId[301]:find("Grey", 1, true) ~= nil, true, "a grey quest, said why")
    expectEqual(byQuestId[303], nil, "a quest ready to hand in is never suggested")
    state.playerLevel = 1
    ns.Chronicle.getBook().open[302] = { deaths = 0, acceptedAt = ns.Chronicle.getNow() - 5 * 86400 }
    suggestions = ns.Warnings.getDropSuggestions()
    expectEqual(suggestions[1] and suggestions[1].questId, 302, "one taken five days ago")
    expectEqual(suggestions[1] and suggestions[1].reason, "Taken 5 days ago", "said how long ago")
    ns.QuestState.getLogSize = savedSize
end)

test("the tracker can order a zone's quests by how much of each is done", function()
    local ns = createAddon()
    expectEqual(ns.Model.getDoneShare({ objectives = { { fulfilled = 3, required = 12 } } }), 0.25, "a quarter done")
    expectEqual(ns.Model.getDoneShare({ isTurnIn = true, objectives = {} }), 1, "ready is all of it")
    expectEqual(
        ns.Model.getDoneShare({ objectives = { { fulfilled = 1, required = 1 }, { fulfilled = 0, required = 4 } } }),
        0.5,
        "objectives count alike"
    )
end)

test("the tracker folds or hides in combat and in dungeons only as the player chose", function()
    local ns = createAddon()
    ns.Tracker.create()
    expectEqual(ns.Tracker.getSituation(), nil, "shown as it is out of combat")
    ns.Tracker.handleCombatEvent(nil, "PLAYER_REGEN_DISABLED")
    expectEqual(ns.Tracker.getSituation(), nil, "nothing chosen: shown in combat too")
    ns.settings.trackerInCombat = "fold"
    expectEqual(ns.Tracker.getSituation(), "fold", "folded in combat")
    ns.settings.trackerInDungeons = "hide"
    local savedInstance = IsInInstance
    IsInInstance = function()
        return true, "party"
    end
    expectEqual(ns.Tracker.getSituation(), "hide", "hiding wins over folding")
    IsInInstance = savedInstance
    ns.Tracker.handleCombatEvent(nil, "PLAYER_REGEN_ENABLED")
    expectEqual(ns.Tracker.getSituation(), nil, "back once the fight is over")
end)

test(
    "quest dialogs: a ready quest is handed in first, a grey one never accepted, Shift leaves it to the player",
    function()
        local ns = createAddon()
        local active = { { isComplete = false }, { isComplete = true } }
        local available = { { isTrivial = true }, { isTrivial = false } }
        expectEqual(ns.AutoQuest.choose(active, available), nil, "switched off: nothing")
        ns.settings.shouldAutoAccept, ns.settings.shouldAutoTurnIn = true, true
        local kind, index = ns.AutoQuest.choose(active, available)
        expectEqual(kind == "active" and index == 2, true, "the ready quest first")
        kind, index = ns.AutoQuest.choose({ { isComplete = false } }, available)
        expectEqual(kind == "available" and index == 2, true, "then the first quest that is not grey")
        local savedShift = IsShiftKeyDown
        IsShiftKeyDown = function()
            return true
        end
        expectEqual(ns.AutoQuest.choose(active, available), nil, "Shift held: the player answers")
        IsShiftKeyDown = savedShift
    end
)

test("a nameplate shows a kill over a drop, and nothing for a creature no quest needs", function()
    local ns = createAddon()
    local saved = ns.UnitTooltip.compose
    ns.UnitTooltip.compose = function(npcId)
        if npcId == 1 then
            return {
                { questId = 10, lines = { { kind = "loot", isDone = false } } },
                { questId = 20, lines = { { kind = "kill", isDone = false } } },
            }
        elseif npcId == 2 then
            return { { lines = { { kind = "loot", isDone = false }, { kind = "kill", isDone = true } } } }
        end
        return {}
    end
    expectEqual(ns.Nameplates.getKind(1), "kill", "a kill wins")
    expectEqual(
        select(2, ns.Nameplates.getKind(1)),
        20,
        "its icon glows in the colour of the quest that wants the kill"
    )
    expectEqual(ns.Nameplates.getKind(2), "loot", "a kill already done does not count")
    expectEqual(ns.Nameplates.getKind(3), nil, "nothing wanted")
    ns.UnitTooltip.compose = saved
end)
test("a quest shown straight away in its dialog is accepted, unless it is grey", function()
    local ns, state = createAddon()
    ns.settings.shouldAutoAccept = true
    local accepted, shownQuestId = 0, 9001
    local savedAccept, savedGetQuestId, savedGet = AcceptQuest, GetQuestID, ns.Database.getQuestField
    AcceptQuest = function()
        accepted = accepted + 1
    end
    GetQuestID = function()
        return shownQuestId
    end
    ns.Database.getQuestField = function(questId, field)
        if field == "questLevel" and (questId == 9001 or questId == 9002) then
            return questId == 9001 and 10 or 58
        end
        return savedGet(questId, field)
    end
    state.playerLevel = 60
    ns.AutoQuest.handleDetail()
    expectEqual(accepted, 0, "a level 10 quest at level 60 is grey: left to the player")
    shownQuestId = 9002
    ns.AutoQuest.handleDetail()
    expectEqual(accepted, 1, "a level 58 quest is accepted")
    state.playerLevel = 1
    AcceptQuest, GetQuestID, ns.Database.getQuestField = savedAccept, savedGetQuestId, savedGet
end)

test("the tracker stays where it was put across logins at any size", function()
    local function createTrackedFrame()
        local savedCreate = CreateFrame
        CreateFrame = function(kind, name, ...)
            local widget = savedCreate(kind, name, ...)
            if name == "OneMoreQuestTracker" then
                local scale = 1
                rawset(widget, "SetScale", function(_, value)
                    scale = value
                end)
                rawset(widget, "GetScale", function()
                    return scale
                end)
                -- Pinned by its top right corner to the screen's bottom left: its edges are the offsets, in its own units
                rawset(widget, "GetRight", function(self)
                    local point = rawget(self, "points")[1]
                    return point[4]
                end)
                rawset(widget, "GetTop", function(self)
                    local point = rawget(self, "points")[1]
                    return point[5]
                end)
            end
            return widget
        end
        return function()
            CreateFrame = savedCreate
        end
    end
    local ns = createAddon()
    ns.settings.trackerScale = 1.5
    ns.settings.position = { "TOPRIGHT", "BOTTOMLEFT", 800, 600 }
    local restore = createTrackedFrame()
    ns.Tracker.create()
    ns.Tracker.refresh()
    restore()
    expectEqual(ns.settings.position[3] .. "," .. ns.settings.position[4], "800,600", "the place kept as saved")
    -- The size changed by the player keeps the corner on the screen, in the new size's units
    ns.settings.trackerScale = 1
    ns.Tracker.applySize()
    expectEqual(
        ns.settings.position[3] .. "," .. ns.settings.position[4],
        "1200,900",
        "a new size keeps it on the screen"
    )
end)

test("folded for a fight, the fold button unfolds it for that fight, and the next one folds it again", function()
    local ns = createAddon()
    ns.settings.trackerInCombat = "fold"
    ns.Tracker.create()
    ns.Tracker.handleCombatEvent(nil, "PLAYER_REGEN_DISABLED")
    expectEqual(ns.Tracker.isFolded(), true, "folded in the fight")
    ns.Tracker.toggleFold()
    expectEqual(ns.Tracker.isFolded(), false, "the button unfolds it")
    expectEqual(ns.settings.isTrackerFolded, false, "and the player's own fold is not turned on by it")
    ns.Tracker.toggleFold()
    expectEqual(ns.Tracker.isFolded(), true, "and folds it again")
    ns.Tracker.toggleFold()
    ns.Tracker.handleCombatEvent(nil, "PLAYER_REGEN_ENABLED")
    expectEqual(ns.Tracker.isFolded(), false, "shown after the fight")
    ns.Tracker.handleCombatEvent(nil, "PLAYER_REGEN_DISABLED")
    expectEqual(ns.Tracker.isFolded(), true, "the next fight folds it again")
    ns.Tracker.handleCombatEvent(nil, "PLAYER_REGEN_ENABLED")
    ns.Tracker.toggleFold()
    expectEqual(ns.settings.isTrackerFolded, true, "out of a fight the button is the player's own fold")
    ns.Tracker.toggleFold()
    expectEqual(ns.Tracker.isFolded(), false, "and unfolds it")
end)

test("a quest made ready while the tracker is folded still rings", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(5, 12) })
    local savedPlay, savedKit = PlaySound, SOUNDKIT
    local played = 0
    PlaySound = function()
        played = played + 1
    end
    SOUNDKIT = { IG_QUEST_LIST_COMPLETE = 1 }
    ns.settings.shouldPlayReadySound = true
    ns.settings.isTrackerFolded = true
    ns.Tracker.create()
    ns.Tracker.refresh()
    state.questLog[301] = { isComplete = true, objectives = { killObjective(12, 12) } }
    ns.Model.forgetEntries()
    ns.Tracker.refresh()
    expectEqual(played, 1, "the ready sound, with nothing drawn")
    ns.Model.forgetEntries()
    ns.Tracker.refresh()
    expectEqual(played, 1, "once")
    PlaySound, SOUNDKIT = savedPlay, savedKit
end)
