-- Tests: quests to pick up: what the character can take, why not, chains, and what givers offer.

test("a quest from an item that drops all over the world shows only once the item is in the bags", function()
    local ns = createAddon()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 517), nil, "not where the item might drop or be handed in")
    expectEqual(getQuest(getAvailableQuests(ns, SILVERPINE), 517), nil, "nor in any other zone its creatures live in")
    GetItemCount = function(itemId) return itemId == 7003 and 1 or 0 end
    local quest = getQuest(getAvailableQuests(ns, TIRISFAL), 517)
    expectEqual(quest ~= nil and quest.isHandedInHere, true, "with the item, it shows where it is handed in")
    expectEqual(getQuest(getAvailableQuests(ns, SILVERPINE), 517), nil, "and still not where the item drops")
    GetItemCount = nil
end)

test("a quest the player hides is offered no more until brought back; the Ahn'Qiraj War Effort's only when asked for", function()
    local ns = createAddon()
    ns.print = function() end
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501) ~= nil, true, "a plain quest")
    ns.QuestHiding.hide(501)
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501), nil, "hidden")
    local hidden = ns.QuestHiding.getHidden()
    expectEqual(#hidden == 1 and hidden[1].questId == 501, true, "in the list of hidden quests")
    ns.QuestHiding.unhide(501)
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501) ~= nil and #ns.QuestHiding.getHidden() == 0, true, "brought back")
    -- The War Effort's quests: a plain quest taken for one of theirs, hidden as Questie hides them, shown when asked
    ns.AQWarEffortQuests[501] = true
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501), nil, "a War Effort quest: hidden")
    ns.settings.shouldShowAQWarEffort = true
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501) ~= nil, true, "shown when asked for")
    ns.AQWarEffortQuests[501] = nil
    expectEqual(ns.AQWarEffortQuests[8815], true, "the cities' Commendation Signets are among them")
end)

test("repeatable and PvP quests are offered only when the settings ask for them", function()
    local ns = createAddon()
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 514), nil, "a repeatable quest is left out")
    expectEqual(getQuest(quests, 515), nil, "as is a daily one")
    expectEqual(getQuest(quests, 7813), nil, "and a cloth donation")
    expectEqual(getQuest(quests, 516), nil, "and a battleground's quest")
    ns.settings.shouldShowRepeatable = true
    quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 514) ~= nil, true, "repeatable quests come back")
    expectEqual(getQuest(quests, 515) ~= nil, true, "with the daily")
    expectEqual(getQuest(quests, 7813) ~= nil, true, "and the donation")
    expectEqual(getQuest(quests, 516), nil, "the battleground's quest has its own switch")
    ns.settings.shouldShowPvp = true
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 516) ~= nil, true, "which brings it back")
end)

test("the quests of a zone that can be picked up now are listed", function()
    local ns = createAddon()
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 501) ~= nil, true, "a plain quest")
    expectEqual(getQuest(quests, 501).starterName, "Deathguard Morris", "giver")
    expectEqual(getQuest(quests, 502), nil, "a quest whose earlier quest is not done")
    expectEqual(getQuest(quests, 504), nil, "a quest far above the player's level")
    expectEqual(getQuest(quests, 505), nil, "a quest for another race")
    expectEqual(getQuest(quests, 503).availableAtLevel, 12, "a quest two levels away is listed as coming soon")
    expectEqual(quests[#quests].questId, 503, "coming-soon quests go last")
end)

test("quests of the other faction and of other classes are not offered", function()
    local ns = createAddon()
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 512), nil, "a quest given by the other faction's officer")
    expectEqual(getQuest(quests, 513), nil, "another class's quest")
    expectEqual(getQuest(quests, 501) ~= nil, true, "a quest from a friendly giver")
end)

test("the same quests are offered to a character they are meant for", function()
    local ns, state = createAddon()
    state.playerFaction = "Alliance"
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 512) ~= nil, true, "the Alliance officer's quest, for an Alliance character")
    expectEqual(getQuest(quests, 501), nil, "the Horde guard's quests are gone")
end)

test("a quest both factions can do is handed in to someone on the player's side", function()
    local ns, state = createAddon()
    -- Like "Strahnbrad Mystery": one person to hand it in to in an Alliance town, one in a Horde town
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 501 and field == "finishedBy" then
                return { { 9005, 9003 } }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    local _, finisherName = ns.Location.getFinisherPlaces(501)
    expectEqual(finisherName, "Deathguard Morris", "a Horde character goes to the Horde side")
    state.playerFaction = "Alliance"
    _, finisherName = ns.Location.getFinisherPlaces(501)
    expectEqual(finisherName, "Captain Vance", "an Alliance character to the Alliance side")
end)

test("a quest that cannot be picked up yet says why, and one never to be had is left out", function()
    local ns, state = createAddon()
    ns.Availability.prepare()
    local player = ns.Availability.getPlayer()
    local blocker = ns.Availability.getBlocker(502, player)
    expectEqual(blocker and blocker.kind, "quest", "a quest to do first")
    expectEqual(blocker and blocker.questId, 501, "the one before it")
    expectEqual(blocker and blocker.text, "After Fresh Start", "said in words")
    blocker = ns.Availability.getBlocker(504, player)
    expectEqual(blocker and blocker.text, "Needs level 30", "a level far off")
    expectEqual(ns.Availability.getBlocker(501, player), nil, "nothing holds back a quest that can be picked up")
    expectEqual(ns.Availability.getChainStart(528, player), 524, "the chain is followed back to where it starts")
    state.questLog[507] = { isComplete = false, objectives = {} }
    local _, isClosed = ns.Availability.getBlocker(508, player)
    expectEqual(isClosed, true, "the other choice of a pair is never to be had")
    local blockedIds, unlockTexts, order = {}, {}, {}
    for _, quest in ipairs(ns.Availability.getBlockedQuests(TIRISFAL)) do
        blockedIds[quest.questId] = quest.blocker.text
        unlockTexts[quest.questId] = quest.unlockText
        order[#order + 1] = quest.questId
    end
    expectEqual(unlockTexts[502], "Needs Fresh Start first: you can take it now", "what to do first, and that it can be done now")
    expectEqual(unlockTexts[504]:find("you are", 1, true) ~= nil, true, "a level, with the player's own")
    local position = {}
    for index, questId in ipairs(order) do
        position[questId] = index
    end
    expectEqual(position[502] < position[504], true, "a quest one step away comes before one levels away")
    expectEqual(blockedIds[502], "After Fresh Start", "listed as not yet, with why")
    expectEqual(blockedIds[504], "Needs level 30", "the far-off level too")
    expectEqual(blockedIds[503], nil, "a quest two levels away is among the quests to pick up instead")
    expectEqual(blockedIds[508], nil, "the closed choice is not listed")
    expectEqual(ns.Availability.getStartZoneId(501), TIRISFAL, "where a quest is picked up")
end)

test("a link to an earlier quest opens it where it is picked up", function()
    local ns = createAddon()
    ns.Availability.prepare()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showAvailable(502) -- not yet: its page names Fresh Start
    ns.Log.showQuestAnywhere(501)
    expectEqual(ns.Log.getSelectedAvailableQuestId(), 501, "the earlier quest is selected on the Available tab")
end)

test("a quest with no level requirement in the database is held to its own level", function()
    local ns, state = createAddon()
    -- "Too High" is a level 32 quest; pretend the database lost its level requirement
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 504 and field == "requiredLevel" then
                return 0
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 504), nil, "not offered to a level 10 character")
    state.playerLevel = 32
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL, { shouldShowLowLevel = true }), 504) ~= nil, true, "offered at its own level")
end)

test("quests on the not-in-the-game list are never offered", function()
    local ns = createAddon()
    ns.HiddenQuests[501] = true
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501), nil, "hidden quest")
    expectEqual(ns.HiddenQuests[787], true, "the list ships with Questie's entries")
end)

test("finishing a quest opens the next and removes the finished one", function()
    local ns, state = createAddon()
    state.turnedInQuestIds[501] = true
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 501), nil, "the finished quest")
    expectEqual(getQuest(quests, 502) ~= nil, true, "the follow-up")
end)

test("taking one of two either/or quests removes the other", function()
    local ns, state = createAddon()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 508) ~= nil, true, "both offered at first")
    state.questLog[507] = { isComplete = false, objectives = {} }
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 507), nil, "the one in the log")
    expectEqual(getQuest(quests, 508), nil, "the one it rules out")
end)

test("a quest from an item dropped in a dungeon shows where it is handed in", function()
    local ns = createAddon()
    local quest = getQuest(getAvailableQuests(ns, TIRISFAL), 506)
    expectEqual(quest ~= nil, true, "listed in the hand-in zone")
    expectEqual(quest.isHandedInHere, true, "handed in here")
    expectEqual(quest.startType, "item", "start type")
    expectEqual(quest.itemName, "Sealed Letter", "item")
    expectEqual(quest.starterName, "Keep Archivist", "who drops it")
    expectEqual(quest.sourceZoneName, "Shadowfang Keep", "where it drops")
    expectEqual(quest.finisherName, "Deathguard Morris", "who takes it")
    local dungeonQuest = getQuest(getAvailableQuests(ns, 209), 506)
    expectEqual(dungeonQuest ~= nil and dungeonQuest.isHandedInHere, false, "also listed where the item drops")
end)

test("a quest from an item far above the player is not offered until the item is in the bags", function()
    local ns = createAddon()
    -- Like a level 60 Craftsman's Writ that the database lets anyone start
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 506 and field == "questLevel" then
                return 60
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 506), nil, "not offered to a level 10 character")
    GetItemCount = function(itemId) return itemId == 7002 and 1 or 0 end
    ns.Availability.invalidate()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 506) ~= nil, true, "offered once the item is in the bags")
    GetItemCount = nil
end)

test("low-level quests are hidden and counted unless asked for", function()
    local ns, state = createAddon()
    state.playerLevel = 20
    local quests, hiddenCount = getAvailableQuests(ns, UNDERCITY)
    expectEqual(getQuest(quests, 511), nil, "hidden")
    expectEqual(hiddenCount > 0, true, "counted")
    quests = getAvailableQuests(ns, UNDERCITY, { shouldShowLowLevel = true })
    expectEqual(getQuest(quests, 511) ~= nil, true, "shown on request")
end)

test("a low-level quest opened through a link is listed and shows its page, hidden or not", function()
    local ns, state = createAddon()
    state.playerLevel = 20 -- "Fresh Start" (level 10) is low-level now
    ns.Availability.prepare()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showQuestAnywhere(501)
    local quest = ns.Log.getSelectedAvailableQuest()
    expectEqual(quest and quest.questId, 501, "its page is shown, not an empty one")
end)

test("a low quest whose chain climbs into the player's range is listed, saying where it leads", function()
    local ns, state = createAddon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 528 and field == "questLevel" then
                return 30 -- the chain's last step, in the player's range
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    state.playerLevel = 25
    ns.settings.shouldShowAnyLeadIns = true -- (kept for leading to any quest in range, not only a dungeon's)
    ns.Availability.prepare()
    local player = ns.Availability.getPlayer()
    local lead = ns.Availability.getChainLead(524, player)
    expectEqual(lead and lead.questId, 528, "the start leads to the step in range")
    expectEqual(lead and lead.stepCount, 3, "three steps on")
    expectEqual(ns.Availability.isLowLevel(524, player), false, "so the start is not left out as low-level")
    expectEqual(ns.Availability.getChainLead(525, player) ~= nil, true, "a fork's other branch leads there too")
    expectEqual(ns.Availability.isLowLevel(501, player), true, "a low quest that leads nowhere higher is still low")
    local quest = getQuest(getAvailableQuests(ns, TIRISFAL), 524)
    expectEqual(quest and quest.leadsTo and quest.leadsTo.questId, 528, "listed with where it leads")
    local blocked, hiddenCount = ns.Availability.getBlockedQuests(TIRISFAL)
    local blockedIds = {}
    for _, blockedQuest in ipairs(blocked) do
        blockedIds[blockedQuest.questId] = true
    end
    expectEqual(blockedIds[527], true, "a step not yet open whose chain climbs is still listed as not yet")
    expectEqual(blockedIds[502], nil, "a low step that leads nowhere higher is left out of not yet")
    expectEqual(hiddenCount > 0, true, "and counted as hidden")
end)

test("low-level lead-ins: by default only those leading to a dungeon's quest in range stay; the settings keep any or none", function()
    local ns, state = createAddon()
    addDungeon()
    local levels = { [527] = 25, [528] = 30 } -- "Down Below" (its work in Shadowfang Keep) and the step after it, in range
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if field == "questLevel" and levels[id] then
                return levels[id]
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    state.playerLevel = 25
    ns.Availability.prepare()
    local player = ns.Availability.getPlayer()
    expectEqual(ns.Availability.getLeadInMode(), "dungeon", "the dungeon's lead-ins kept, as it comes")
    local lead = ns.Availability.getChainLead(524, player)
    expectEqual(lead and lead.questId, 527, "the start leads to the dungeon's quest")
    expectEqual(ns.Availability.isLowLevel(524, player), false, "so it is not left out")
    local quest = getQuest(getAvailableQuests(ns, TIRISFAL), 524)
    expectEqual(quest and quest.leadsTo and quest.leadsTo.questId, 527, "listed, saying the dungeon's quest it leads to")

    levels[527] = 11 -- the dungeon's quest low too: only an ordinary step in range is left ahead
    ns.Availability.invalidate()
    expectEqual(ns.Availability.isLowLevel(524, player), true, "a chain climbing to no dungeon quest in range is low")
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 524), nil, "and left out")
    ns.settings.shouldShowAnyLeadIns = true
    ns.Availability.invalidate()
    expectEqual(ns.Availability.isLowLevel(524, player), false, "any quest in range: a lead to it keeps it")
    quest = getQuest(getAvailableQuests(ns, TIRISFAL), 524)
    expectEqual(quest and quest.leadsTo and quest.leadsTo.questId, 528, "saying where it leads")

    levels[527] = 25
    ns.settings.shouldShowAnyLeadIns, ns.settings.shouldShowDungeonLeadIns = false, false
    ns.Availability.invalidate()
    expectEqual(ns.Availability.isLowLevel(524, player), true, "neither: every low-level quest is low, the dungeon's lead-ins too")
    quest = getQuest(getAvailableQuests(ns, TIRISFAL, { shouldShowLowLevel = true }), 524)
    expectEqual(quest and quest.leadsTo and quest.leadsTo.questId, 527, "shown with all low-level ones, it still says where it leads")
    expectEqual(ns.Availability.isLowLevel(527, player), false, "a quest in range is never low")
end)

test("steps of one chain waiting together are drawn under the chain; a step named like the one before says which", function()
    local ns = createAddon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 527 and field == "name" then
                return "Patrols" -- named like the step before it, as the Elixir of Agony steps are
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    local blocker = ns.Availability.getBlocker(527, ns.Availability.getPlayer())
    expectEqual(blocker and blocker.text, "After Patrols 1/3", "the step before is told apart by its place in the chain")
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showQuestAnywhere(527) -- opens the not-yet part, where 526, 527 and 528 wait as one chain
    expectEqual(ns.Log.getSelectedAvailableQuestId(), 527, "a step inside a chain heading can be selected")
end)

test("a zone's summary says how many of the quests left are low-level", function()
    local ns, state = createAddon()
    ns.Availability.prepare()
    local summary = ns.Availability.getZoneSummary(TIRISFAL)
    expectEqual(summary.lowAvailable, 0, "nothing is low-level for a level 10 character")
    state.playerLevel = 30
    ns.Availability.invalidate()
    summary = ns.Availability.getZoneSummary(TIRISFAL)
    expectEqual(summary.available > 0 and summary.lowAvailable > 0, true, "at level 30 the level 10 quests are")
    expectEqual(summary.lowAvailable <= summary.available, true, "and they are among those left, not extra")
end)

test("quests can be grouped where they were picked up, as the game's own log does", function()
    local ns, state = createAddon()
    -- "Two Fronts" is filed under Tirisfal Glades; with its bandits done, its next step is the wolves in Silverpine
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    local function getGroupZoneId(model)
        for _, group in ipairs(model.groups) do
            for _, entry in ipairs(group.entries) do
                if entry.questId == 301 then
                    return group.zoneId
                end
            end
        end
    end
    expectEqual(getGroupZoneId(ns.Model.compose()), SILVERPINE, "by default under where its next step is")
    ns.settings.logGrouping = "pickup"
    expectEqual(getGroupZoneId(ns.Model.compose()), TIRISFAL, "switched, under the zone it belongs to")
    local entry = ns.Model.compose().groups[1].entries[1]
    expectEqual(entry.zoneId, SILVERPINE, "its step still points where to go")
end)

test("a zone's levels are the game's own when the client knows them, else its quests'", function()
    local ns = createAddon()
    ns.Availability.prepare()
    local minLevel = ns.Availability.getZoneLevels(TIRISFAL)
    expectEqual(minLevel ~= nil, true, "from its quests without the game's")
    C_Map.GetMapLevels = function(uiMapId) return uiMapId == 1420 and 1 or 0, uiMapId == 1420 and 10 or 0 end
    ns.Availability.invalidate()
    local gameMin, gameMax = ns.Availability.getZoneLevels(TIRISFAL)
    expectEqual(gameMin, 1, "the game's lowest")
    expectEqual(gameMax, 10, "and highest")
    C_Map.GetMapLevels = nil
end)

test("warnings name the lead-in quest, the either/or quest and a full log", function()
    local ns, state = createAddon()
    local warnings = ns.Warnings.getQuestWarnings(509)
    expectEqual(#warnings, 1, "lead-in warning count")
    expectEqual(warnings[1]:find("Lead-in", 1, true) ~= nil, true, "names the lead-in quest")
    warnings = ns.Warnings.getQuestWarnings(507)
    expectEqual(warnings[1]:find("\"Or\"", 1, true) ~= nil, true, "names the other quest")
    state.maxQuestCount = 0
    warnings = ns.Warnings.getQuestWarnings(501)
    expectEqual(warnings[#warnings], "Your quest log is full.", "full log")
    state.turnedInQuestIds[510] = true
    state.maxQuestCount = 25
    expectEqual(#ns.Warnings.getQuestWarnings(509), 0, "no warning once the lead-in is done")
end)

test("a chain lists its quests in order", function()
    local ns = createAddon()
    local questIds = ns.Chain.getQuestIds(102)
    expectEqual(table.concat(questIds, ","), "101,102,103", "chain")
    expectEqual(table.concat(ns.Chain.getQuestIds(201), ","), "201", "a quest outside a chain")
end)

test("a quest the game offers that the lists missed is added, noted, and drawn", function()
    local ns, state = createAddon()
    local uiMapId = ns.Database.getUiMapId(TIRISFAL)
    C_QuestLine = {
        RequestQuestLinesForMap = function() end,
        GetAvailableQuestLines = function(mapId)
            if mapId ~= uiMapId then
                return {}
            end
            return {
                { questID = 9999, questName = "Not in the Database", x = 0.5, y = 0.4, isHidden = false, startMapID = uiMapId },
                { questID = 504, questName = "Too High", x = 0.3, y = 0.3, isHidden = false, startMapID = uiMapId },
                { questID = 514, questName = "More Supplies", x = 0.3, y = 0.3, isHidden = false, startMapID = uiMapId },
                { questID = 503, questName = "High Road", x = 0.3, y = 0.3, isHidden = false, startMapID = uiMapId },
            }
        end,
    }
    state.playerLevel = 12
    ns.Availability.prepare()
    local quests = getAvailableQuests(ns, TIRISFAL)
    local unknown = getQuest(quests, 9999)
    expectEqual(unknown ~= nil and unknown.isFromGame, true, "a quest the database lacks is added")
    expectEqual(unknown.places[1].x, 50, "at the place of the game's mark")
    expectEqual(ns.settings.missedQuests[9999].reason, "not in the quest database", "and noted, with why")
    expectEqual(getQuest(quests, 504) ~= nil, true, "a quest the rules held back is added on the game's word")
    expectEqual(ns.settings.missedQuests[504].reason, "the addon's rules said it was not available", "noted as a rule's hole")
    expectEqual(getQuest(quests, 514), nil, "a repeatable quest stays out while the settings leave those out")
    expectEqual(ns.settings.missedQuests[503], nil, "a quest the lists already had is not noted")
    local count = 0
    for _, quest in ipairs(quests) do
        count = count + (quest.questId == 503 and 1 or 0)
    end
    expectEqual(count, 1, "nor listed twice")
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.showAvailable(9999)
    ns.MissedReport.printMissed()
    C_QuestLine = nil
end)

test("a quest a giver offers when talked to is learnt, listed, reported, and forgotten once no longer offered", function()
    local ns = createAddon()
    ns.Availability.prepare()
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-2-3-9003-0000ABCD" or nil end
    local originalUnitName = UnitName
    UnitName = function(unit) return unit == "npc" and "Deathguard Morris" or "Tester" end
    -- "Too High" is held back by the rules for a level 10 character, yet the giver offers it
    ns.GameOffers.learnOffers({ { questId = 504, title = "Too High" } }, true)
    local quest = getQuest(getAvailableQuests(ns, TIRISFAL), 504)
    expectEqual(quest ~= nil, true, "listed on the giver's word")
    expectEqual(ns.settings.missedQuests[504].reason:find("offered by Deathguard Morris", 1, true) ~= nil, true, "noted with who offered it")
    local report, count = ns.GameOffers.composeReport()
    expectEqual(count, 1, "one quest in the report")
    expectEqual(report:find("504 | Too High | Tirisfal Glades", 1, true) ~= nil, true, "a line to copy for it")
    expectEqual(report:find("Deathguard Morris (9003)", 1, true) ~= nil, true, "with the giver")
    local originalGetBuildInfo = GetBuildInfo
    GetBuildInfo = function() return "1.60.1", "70938", "Nov 1 2026", 16001 end
    expectEqual(ns.GameOffers.composeReport():find("client 1.60.1 (70938)", 1, true) ~= nil, true, "the client's version and build")
    GetBuildInfo = originalGetBuildInfo
    ns.MissedReport.show()
    ns.GameOffers.learnOffers({}, true) -- talked to again: no longer offered
    ns.GameOffers.reset()
    ns.Availability.invalidate()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 504), nil, "forgotten once the giver no longer offers it")
    UnitGUID, UnitName = nil, originalUnitName
end)

test("a quest handed in counts as done at once, before the game marks it completed", function()
    local ns = createAddon()
    local player = ns.Availability.getPlayer()
    expectEqual(ns.Availability.getBlocker(102, player) ~= nil, true, "before: waits for 101")
    -- The giver offers 102 the moment 101 is handed in; the game's completed mark for 101 comes later
    ns.QuestState.noteTurnedIn(101)
    ns.Availability.forgetLists()
    expectEqual(ns.QuestState.isTurnedIn(101), true, "101 is done")
    local blocker = ns.Availability.getBlocker(102, player)
    expectEqual(blocker and blocker.kind == "quest" and blocker.text or nil, nil, "102 no longer waits for 101 (only for its level)")
end)

test("a quest is low-level exactly when the game greys it", function()
    local ns = createAddon()
    local savedRange = UnitQuestTrivialLevelRange
    UnitQuestTrivialLevelRange = function() return 6 end -- the game's range for the player
    expectEqual(ns.Availability.getTrivialGap(33, "player"), 6, "the game's own range, not a rule of ours")
    UnitQuestTrivialLevelRange = nil
    expectEqual(ns.Availability.getTrivialGap(33, "player"), 8, "without the game's answer, the classic rule")
    UnitQuestTrivialLevelRange = savedRange
end)

test("a profession is read from the character's skill lines", function()
    local ns = createAddon()
    C_SkillInfo = { GetSkillLineInfoByID = function(skillId) return skillId == 164 and { rank = 151 } or nil end }
    expectEqual(ns.Availability.getSkillRank(164), 151, "blacksmithing, as the character sheet has it")
    expectEqual(ns.Availability.getSkillRank(171), 0, "a profession not learnt")
    C_SkillInfo = nil
end)

test("a giver friendly to both factions but only in the other faction's capital is out of reach", function()
    local ns, state = createAddon()
    -- Envoy Maldrek, marked for no faction, stands only in Undercity; "Childhood Chore" is hers
    expectEqual(ns.Database.isNpcFriendly(9002), true, "the Horde can reach her")
    expectEqual(getQuest(getAvailableQuests(ns, UNDERCITY, { shouldShowLowLevel = true }), 511) ~= nil, true, "and is offered her quest")
    state.playerFaction = "Alliance"
    expectEqual(ns.Database.isNpcFriendly(9002), false, "the Alliance cannot, in a Horde capital")
    ns.Availability.reset()
    ns.Availability.prepare()
    expectEqual(getQuest(getAvailableQuests(ns, UNDERCITY, { shouldShowLowLevel = true }), 511), nil, "so her quest is not offered to them")
end)

test("alternatives of one quest, which close each other, count once in a zone", function()
    local ns = createAddon()
    addDungeon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if (id == 521 or id == 601) and field == "name" then
                return "The Sparklematic 5200!"
            end
            if id == 521 and field == "exclusiveTo" then
                return { 601 }
            end
            if id == 601 and field == "exclusiveTo" then
                return { 521 }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    local count = 0
    for _, state in ipairs(ns.Availability.getZoneQuestStates(209)) do
        if state.questId == 521 or state.questId == 601 then
            count = count + 1
        end
    end
    expectEqual(count, 1, "one machine's quest stands for all")
    local warnings = table.concat(ns.Warnings.getQuestWarnings(521, true), "|")
    expectEqual(warnings:find("locks out", 1, true), nil, "no warning that it locks out a quest of its own name")
end)

test("a quest after a chain step and far above the player says both; its chain ticks only steps really done", function()
    local ns, state = createAddon()
    addDungeon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 521 and (field == "requiredLevel" or field == "questLevel") then
                return 60
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    local blocker = ns.Availability.getBlocker(521, ns.Availability.getPlayer())
    expectEqual(blocker and blocker.kind, "quest", "the chain step comes first")
    expectEqual(blocker and blocker.text:find("needs level 60", 1, true) ~= nil, true, "and the level is said too")
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showQuestAnywhere(521) -- its page, chain and all
    expectEqual(state.turnedInQuestIds[520], nil, "the step before is not done")
end)

test("a same-named step taken and handed straight back where the one before ends is one thing to do with it", function()
    local ns = createAddon()
    addDungeon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 601 and field == "name" then
                return "The Sparklematic 5200!" -- another quest of the name, a step of its own (as in Test of Lore)
            end
            if id == 520 or id == 521 then
                if field == "name" then
                    return "The Sparklematic 5200!"
                elseif field == "zoneOrSort" then
                    return 236
                elseif field == "startedBy" or field == "finishedBy" then
                    return { nil, { 9001 } } -- the machine
                elseif field == "objectives" then
                    return id == 520 and { nil, nil, { { 7002 } } } or nil -- the second step asks nothing
                elseif field == "preQuestSingle" then
                    return id == 521 and { 520 } or nil
                end
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    expectEqual(ns.Availability.getInstantSteps(520)[1], 521, "the second step goes with the first")
    expectEqual(#ns.Chain.getQuestIds(521), 1, "in a chain they are one step")
    expectEqual(ns.Chain.getStep(521), nil, "so the pair alone is no chain: no 1 of 2 badge")
    local listedCount, isOtherListed = 0, false
    for _, state in ipairs(ns.Availability.getZoneQuestStates(209)) do
        listedCount = listedCount + ((state.questId == 520 or state.questId == 521) and 1 or 0)
        isOtherListed = isOtherListed or state.questId == 601
    end
    expectEqual(listedCount, 1, "counted once")
    expectEqual(isOtherListed, true, "while another quest of the same name, not done back to back, keeps its own place")
    for _, quest in ipairs(ns.Availability.getBlockedQuests(209)) do
        expectEqual(quest.questId ~= 521, true, "the second step does not wait in the not-yet list")
    end
    local run = ns.Availability.getDungeonRun(209)
    for _, quest in ipairs(run.behindLeadIn) do
        expectEqual(quest.questId ~= 521, true, "nor behind a lead-in")
    end
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showZone(209)
    ns.Log.showQuestAnywhere(520) -- its page: how it goes, both steps
    ns.Log.refresh()
end)

test("same-named steps that ask something stay steps of their own, each told apart by what it asks", function()
    local ns = createAddon()
    addDungeon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 520 or id == 521 then
                if field == "name" then
                    return "Test of Lore"
                elseif field == "startedBy" or field == "finishedBy" then
                    return { { 4489 } } -- Braug Dimspirit, both
                elseif field == "objectives" then
                    return nil
                elseif field == "triggerEnd" then
                    return id == 521 and { "Answer Braug Dimspirit's question correctly", {} } or nil
                elseif field == "objectivesText" then
                    return id == 521 and { "Answer Braug Dimspirit's question successfully and then speak to him again." } or { "Find Braug." }
                elseif field == "preQuestSingle" then
                    return id == 521 and { 520 } or nil
                elseif field == "nextQuestInChain" then
                    return id == 520 and 521 or nil
                end
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    expectEqual(#ns.Availability.getInstantSteps(520), 0, "a quiz is something to do: not merged")
    local index, total = ns.Chain.getStep(521)
    expectEqual(total, 2, "two steps of the chain")
    expectEqual(index, 2, "the quiz is the second")
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showQuestAnywhere(521) -- its chain, each step with what it asks
    ns.Log.refresh()
end)

test("spell, specialization and availability-window requirements are read, not treated as unknown", function()
    local ns, state = createAddon()
    local known = {}
    IsPlayerSpell = function(spellId) return known[spellId] == true end
    local fields = {}
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 520 and fields[field] ~= nil then
                return fields[field]
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    local player = ns.Availability.getPlayer()
    local function check()
        ns.Availability.invalidate()
        return ns.Availability.isEligible(520, player), ns.Availability.getBlocker(520, player)
    end
    fields.requiredSpell = -2575 -- for those who do not know Mining yet (Camping 101)
    expectEqual((check()), true, "offered to one who does not know the spell")
    known[2575] = true
    local isEligible, blocker, isClosed = ns.Availability.isEligible(520, player), ns.Availability.getBlocker(520, player)
    expectEqual(isEligible, false, "not to one who knows it")
    expectEqual(blocker, nil, "and it never will be")
    fields.requiredSpell = 2575
    expectEqual((check()), true, "a spell to know, known")
    known[2575] = nil
    local _, spellBlocker = check()
    expectEqual(spellBlocker and spellBlocker.kind, "spell", "unknown: says what to learn")
    fields.requiredSpell = nil
    fields.requiredSpecialization = 202 -- engineering's choice still to make
    expectEqual((check()), true, "offered before choosing a specialization")
    known[20219] = true
    expectEqual((check()), false, "not once Gnomish Engineering is chosen")
    fields.requiredSpecialization = 20222 -- for Goblin engineers
    local _, specializationBlocker = check()
    expectEqual(specializationBlocker and specializationBlocker.kind, "spell", "a gnome is told what it needs")
    fields.requiredSpecialization = nil
    fields.availableUntilCompleted = 501
    expectEqual((check()), true, "available until the other quest is done")
    state.turnedInQuestIds[501] = true
    expectEqual((check()), false, "and not after")
    fields.availableUntilCompleted = nil
    fields.availableStartingWith = 503
    local isOpen, startBlocker = check()
    expectEqual(isOpen, false, "not before the quest it starts with is taken")
    expectEqual(startBlocker and startBlocker.kind, "quest", "which it names")
    IsPlayerSpell = nil
end)

test("a quest after any one of several names one the character can do, and says any one will do", function()
    local ns = createAddon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 520 and field == "preQuestSingle" then
                return { 505, 503, 502 } -- "Humans Only" first, then two the character can do
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    local blocker = ns.Availability.getBlocker(520, ns.Availability.getPlayer())
    expectEqual(blocker and blocker.kind, "quest", "waits for an earlier quest")
    expectEqual(blocker and blocker.questId ~= 505, true, "not the other race's version")
    expectEqual(blocker and blocker.text:find("(or 1 other)", 1, true) ~= nil, true, "and says another would do")
end)

test("an objective with no known place takes its hint from the quest's own sentence that names it", function()
    local ns = createAddon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 520 and field == "objectivesText" then
                return { "Fill the Empty Red Waterskin at Stonewatch Falls near the murlocs. Then return to Hervdana." }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(ns.Location.getQuestTextHint(520, "Empty Red Waterskin: 0/1"), "Fill the Empty Red Waterskin at Stonewatch Falls near the murlocs.", "the sentence naming it")
    expectEqual(ns.Location.getQuestTextHint(520, "Something Else"), "Fill the Empty Red Waterskin at Stonewatch Falls near the murlocs.", "else the first")
    expectEqual(ns.Location.getQuestTextHint(999999, "x"), nil, "none without text")
end)

test("a quest the game says it does not have is never offered (the database holds other versions' quests)", function()
    local ns = createAddon()
    local asked = {}
    local savedRequest, savedHave = C_QuestLog.RequestLoadQuestByID, HaveQuestData
    C_QuestLog.RequestLoadQuestByID = function(questId) asked[#asked + 1] = questId end
    HaveQuestData = function() return false end
    ns.QuestState.checkExists(93862)
    ns.QuestState.checkExists(93862)
    expectEqual(#asked, 1, "asked once")
    expectEqual(ns.QuestState.isMissingFromGame(93862), false, "not hidden before the game answers")
    expectEqual(ns.QuestState.handleQuestDataLoaded(93862, false), true, "the game has no such quest")
    expectEqual(ns.QuestState.isMissingFromGame(93862), true, "hidden from then on")
    ns.QuestState.checkExists(501)
    expectEqual(ns.QuestState.handleQuestDataLoaded(501, true), false, "a quest the game loads stays")
    expectEqual(ns.QuestState.isMissingFromGame(501), false, "and is offered")
    expectEqual(ns.QuestState.handleQuestDataLoaded(777, false), false, "an answer about a quest not asked about changes nothing")
    C_QuestLog.RequestLoadQuestByID, HaveQuestData = savedRequest, savedHave
end)

test("showing low-level quests redraws the map and the minimap too, not only the list", function()
    local ns = createAddon()
    ns.Availability.prepare()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showAvailable()
    local redraws = 0
    ns.registerModule({ name = "Counter", refresh = function() redraws = redraws + 1 end })
    local check = ns.LogState.lowLevelCheck
    expectEqual(check ~= nil and check:GetScript("OnClick") ~= nil, true, "the checkbox is there")
    check:GetScript("OnClick")(check)
    expectEqual(ns.settings.shouldShowLowLevel, true, "switched on")
    expectEqual(redraws > 0, true, "everything redrawn, the map's marks among it")
end)

test("the world's or a continent's map is no location: the Available list stays put and reads no offers there", function()
    local ns = createAddon()
    ns.Availability.prepare()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showZone(SILVERPINE)
    ns.Log.handleMapChanged(1415) -- the Eastern Kingdoms
    expectEqual(ns.Log.getAvailableZoneId(), SILVERPINE, "the list keeps its zone")
    expectEqual(ns.Database.isZoneMap(1415), false, "a continent's map is not a zone's")
    expectEqual(#ns.GameOffers.get(10074), 0, "and the game's offers all over it are not read as a zone's")
end)

test("a warning naming a lead-in says which quest, so the page can link its name", function()
    local ns = createAddon()
    ns.Availability.prepare()
    local warnings, links = ns.Warnings.getQuestWarnings(509)
    local found
    for index, warning in ipairs(warnings) do
        if links[index] then found = { warning = warning, link = links[index] } end
    end
    expectEqual(found ~= nil, true, "the lead-in warning carries its quest")
    expectEqual(found.link.questId, 510, "the lead-in")
    expectEqual(found.link.format:find("%s", 1, true) ~= nil, true, "with the format its name goes into")
end)

test("the page of a quest with a lead-in draws its warning with the lead-in's name as a link", function()
    local ns = createAddon()
    ns.Availability.prepare()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    local ok, err = pcall(ns.Log.showAvailable, 509)
    expectEqual(ok, true, "drawn without an error: " .. tostring(err))
end)

test("a quest its giver leaves out of what they offer is not listed to pick up until they offer it, or the player levels", function()
    local ns = createAddon()
    ns.Availability.prepare()
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-2-3-9003-0000ABCD" or nil end
    local originalUnitName = UnitName
    UnitName = function(unit) return unit == "npc" and "Deathguard Morris" or "Tester" end
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501) ~= nil, true, "Fresh Start is listed by the rules")
    ns.GameOffers.learnOffers({ { questId = 507, title = "Either" } }, true) -- his whole list, without it
    ns.Availability.invalidate()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501), nil, "not listed once he left it out")
    local blocker = ns.Availability.getBlocker(501, ns.Availability.getPlayer())
    expectEqual(blocker and blocker.kind, "refused", "said why")
    expectEqual(blocker and blocker.text:find("Deathguard Morris", 1, true) ~= nil, true, "naming him")
    ns.GameOffers.learnOffers({ { questId = 501, title = "Fresh Start" } }, false) -- he offers it after all
    ns.Availability.invalidate()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 501) ~= nil, true, "listed again once offered")
    UnitGUID, UnitName = nil, originalUnitName
end)

test("the Available tab's search keeps the quests whose title or giver matches, and names other zones with matches", function()
    local ns = createAddon()
    local quest = getQuest(getAvailableQuests(ns, TIRISFAL), 501)
    local word = quest.title:lower():match("%a+")
    expectEqual(ns.Availability.isSearchMatch(quest, word), true, "part of the title")
    expectEqual(ns.Availability.isSearchMatch(quest, quest.starterName:lower()), true, "the giver's name")
    expectEqual(ns.Availability.isSearchMatch(quest, "no such words here"), false, "anything else")
    expectEqual(ns.Availability.isSearchMatch(quest, ""), true, "an empty search keeps everything")
    local others = ns.Availability.findInOtherZones(quest.title:lower(), SILVERPINE, {})
    local found
    for _, zone in ipairs(others) do
        if zone.zoneId == TIRISFAL then
            found = zone
        end
    end
    expectEqual(found ~= nil, true, "searched from another zone, the quest's zone is named")
    expectEqual(found and found.titles[1], quest.title, "with the quest")
    for _, zone in ipairs(ns.Availability.findInOtherZones(quest.title:lower(), TIRISFAL, {})) do
        expectEqual(zone.zoneId ~= TIRISFAL, true, "the zone shown is not among the others")
    end
end)

test("an objective with no place says what can be done instead: the bank, the Auction House, its source", function()
    local ns = createAddon()
    local savedPrice, savedItem = ns.Prices.getAuctionPrice, C_Item
    ns.Prices.getAuctionPrice = function(itemId) return itemId == 9002 and 12050 or nil end
    C_Item = setmetatable({ GetItemCount = function(_, includeBank) return includeBank and 1 or 0 end }, { __index = savedItem })
    local text = ns.LogQuestPage.composeWaysToGet({ objective = { type = "item", label = "Wool Cloth" }, itemId = 9002, stillNeeded = 3 })
    expectEqual(text:find("1 in your bank", 1, true) ~= nil, true, "what waits in the bank")
    expectEqual(text:find("for 2 at the Auction House", 1, true) ~= nil, true, "the rest at the Auction House")
    expectEqual(text:find("Point at it", 1, true) ~= nil, true, "and where the quest's words are")
    local bare = ns.LogQuestPage.composeWaysToGet({ objective = { type = "monster", label = "Korrak the Bloodrager slain" } })
    expectEqual(bare:find("does not say where", 1, true) ~= nil, true, "nothing known: why there is no mark")
    ns.Prices.getAuctionPrice, C_Item = savedPrice, savedItem
end)

test("a quest giver's greeting window: each offered quest is read with its id", function()
    local ns = createAddon()
    local saved = { GetNumAvailableQuests, GetAvailableQuestInfo, GetAvailableTitle }
    GetNumAvailableQuests = function() return 2 end
    GetAvailableQuestInfo = function(index) return index == 2, 0, false, false, 500 + index end -- isTrivial, frequency, repeatable, legendary, questId
    GetAvailableTitle = function(index) return "Quest " .. index end
    local quests, isComplete = ns.GameOffers.readDialogOffers("QUEST_GREETING")
    expectEqual(isComplete, true, "the whole list")
    expectEqual(quests[1] and quests[1].questId, 501, "the quest's id, the fifth value")
    expectEqual(quests[2] and quests[2].isTrivial, true, "and whether it is grey")
    GetNumAvailableQuests, GetAvailableQuestInfo, GetAvailableTitle = saved[1], saved[2], saved[3]
end)

test("a quest the game offers stays out when the player's own choices leave it out: hidden, or of a kind turned off", function()
    local ns = createAddon()
    ns.print = function() end
    local uiMapId = ns.Database.getUiMapId(TIRISFAL)
    C_QuestLine = {
        RequestQuestLinesForMap = function() end,
        GetAvailableQuestLines = function(mapId)
            if mapId ~= uiMapId then
                return {}
            end
            return {
                { questID = 504, questName = "Too High", x = 0.3, y = 0.3, isHidden = false, startMapID = uiMapId },
                { questID = 9999, questName = "Not in the Database", x = 0.5, y = 0.4, isHidden = false, startMapID = uiMapId },
            }
        end,
    }
    ns.settings.hiddenQuestIds = { [504] = true, [9999] = true } -- (as QuestHiding.hide keeps them)
    ns.Availability.prepare()
    local quests = getAvailableQuests(ns, TIRISFAL)
    expectEqual(getQuest(quests, 504), nil, "a quest the player hid is not brought back by the game's word")
    expectEqual(getQuest(quests, 9999), nil, "nor one the database lacks")
    expectEqual(ns.settings.missedQuests[504], nil, "and neither is noted as missed")
    expectEqual(ns.settings.missedQuests[9999], nil, "(the rules missed nothing there)")
    ns.QuestHiding.unhide(504)
    ns.Availability.invalidate()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 504) ~= nil, true, "brought back: the game's word stands again")
    C_QuestLine = nil
end)

test("a giver's offer learnt by talking holds until the quest closes; one closed already when offered stands", function()
    local ns, state = createAddon()
    ns.Availability.prepare()
    UnitGUID = function(unit) return unit == "npc" and "Creature-0-1-2-3-9003-0000ABCD" or nil end
    local originalUnitName = UnitName
    UnitName = function(unit) return unit == "npc" and "Deathguard Morris" or "Tester" end
    ns.GameOffers.learnOffers({ { questId = 507, title = "Either" } }, false)
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 507) ~= nil, true, "Either is listed")
    -- The other of the pair is taken: Either is closed, and what the giver offered then is offered no more
    state.questLog[508] = { isComplete = false, objectives = {} }
    ns.Availability.invalidate()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 507), nil, "not listed once the other choice is taken")
    expectEqual(ns.settings.missedQuests[507], nil, "nor noted as missed")
    expectEqual(ns.getCharacterRecords("learnedOffers")[507], nil, "and forgotten")
    -- Offered while the data already called it closed: a hole in the data, the giver's word stands
    ns.GameOffers.learnOffers({ { questId = 507, title = "Either" } }, false)
    ns.Availability.invalidate()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 507) ~= nil, true, "listed on the giver's word")
    expectEqual(ns.settings.missedQuests[507] ~= nil, true, "and noted as the rules' hole")
    UnitGUID, UnitName = nil, originalUnitName
end)

test("a quest asked for first counts as done when the other side of its choice was done instead", function()
    local ns, state = createAddon()
    local fields = { [501] = { preQuestGroup = { 507 } }, [503] = { preQuestSingle = { 507 } } }
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if fields[id] and fields[id][field] ~= nil then
                return fields[id][field]
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    state.playerLevel = 12
    ns.Availability.prepare()
    local player = ns.Availability.getPlayer()
    expectEqual(ns.Availability.isEligible(501, player), false, "Fresh Start waits for Either")
    local blocker = ns.Availability.getBlocker(501, player)
    expectEqual(blocker and blocker.questId, 507, "and says so")
    state.turnedInQuestIds[508] = true -- "Or" done: "Either" will never be
    ns.Availability.invalidate()
    expectEqual(ns.Availability.isEligible(501, player), true, "the other choice done is as good (all of a group)")
    expectEqual(ns.Availability.isEligible(503, player), true, "and for any one of a list")
    blocker = ns.Availability.getBlocker(501, player)
    expectEqual(blocker == nil or blocker.kind ~= "quest", true, "no quest named as still to do")
end)

test("a quest the game offers that the rules hold back is one row, not again among those not yet to be had", function()
    local ns = createAddon()
    local uiMapId = ns.Database.getUiMapId(TIRISFAL)
    C_QuestLine = {
        RequestQuestLinesForMap = function() end,
        GetAvailableQuestLines = function(mapId)
            if mapId ~= uiMapId then
                return {}
            end
            return { { questID = 504, questName = "Too High", x = 0.3, y = 0.3, isHidden = false, startMapID = uiMapId } }
        end,
    }
    ns.Availability.prepare()
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 504) ~= nil, true, "listed on the game's word")
    expectEqual(getQuest(ns.Availability.getBlockedQuests(TIRISFAL, { shouldShowLowLevel = true }), 504) ~= nil, true,
        "while the rules still hold it back")
    -- The Available tab draws the two lists: the quest once
    local Canvas = getmetatable(ns.Widgets.createCanvas("OneMoreQuestOneRowTestCanvas", UIParent, 200, 100))
    local savedAddText, count = Canvas.addText, 0
    Canvas.addText = function(self, text, ...)
        count = count + ((tostring(text):find("Too High", 1, true)) and 1 or 0)
        return savedAddText(self, text, ...)
    end
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.showAvailable(501)
    ns.LogState.isUpcomingShown = true -- the quests not yet to be had unfolded
    count = 0
    ns.Log.refresh()
    Canvas.addText = savedAddText
    expectEqual(count, 1, "drawn once, not twice")
    C_QuestLine = nil
end)
