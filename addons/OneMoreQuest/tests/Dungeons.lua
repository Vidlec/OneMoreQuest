-- Tests: dungeons: quests filed under them, work inside, entrances, runs, and dungeons learned by playing.

test("an objective inside a dungeon is placed at the dungeon's entrance", function()
    local ns = createAddon()
    addDungeon()
    local places = ns.Location.getObjectivePlaces(506, "monster", 1) -- no such objective: nothing known
    expectEqual(#places, 0, "an objective the database cannot place")
    local source = ns.Location.getStartItemSource(506)
    expectEqual(#source.places, 1, "one entrance stands in for the dungeon's spawns")
    expectEqual(source.places[1].dungeonName, "Shadowfang Keep", "it names the dungeon")
    expectEqual(source.places[1].groupZoneId, 209, "it is filed under the dungeon")
    expectEqual(source.places[1].mapZoneId, SILVERPINE, "and drawn in the zone outside")
    expectEqual(source.places[1].x, 45, "at the entrance")
end)

test("a dungeon quest is listed under its dungeon and marked at the entrance", function()
    local ns, state = createAddon()
    addDungeon()
    setQuest(state, 601, false, { killObjective(0, 1) })
    local step = ns.Location.composeStep(ns.QuestState.getQuest(601), 85)
    expectEqual(step.zoneId, 209, "listed under the dungeon, not the zone outside")
    expectEqual(ns.Database.getZoneName(step.zoneId), "Shadowfang Keep", "under the dungeon's name")
    expectEqual(#step.places, 1, "with the entrance as the place to go")
    expectEqual(ns.Database.getMapZoneId(209), SILVERPINE, "its heading opens the map of the zone outside")
    ns.Tracker.create()
    expectEqual(#ns.MapMarks.compose(1421) > 0, true, "marked on the map of the zone the entrance is in")
    expectEqual(#ns.MapMarks.compose(1420), 0, "and on no other zone's map")
end)

test("a quest that starts inside a dungeon is listed under the dungeon; the zone of its entrance points there and marks it", function()
    local ns = createAddon()
    addDungeon()
    expectEqual(getQuest(getAvailableQuests(ns, 209), 506) ~= nil, true, "listed under the dungeon itself")
    expectEqual(getQuest(getAvailableQuests(ns, SILVERPINE), 506), nil, "not in the zone outside's list")
    local onMap = getQuest(getAvailableQuests(ns, SILVERPINE, { shouldIncludeEntrances = true }), 506)
    expectEqual(onMap ~= nil and #onMap.places, 1, "but on its map, at the entrance")
    expectEqual(onMap.places[1].dungeonName, "Shadowfang Keep", "which names the dungeon")
    local isCounted = false
    for _, questId in ipairs(ns.Availability.getZoneQuestIds(SILVERPINE)) do
        isCounted = isCounted or questId == 506
    end
    expectEqual(isCounted, false, "nor counted for the zone outside")
    local entrances = ns.Availability.getEntranceDungeons(SILVERPINE)
    expectEqual(entrances[1] and entrances[1].dungeonId, 209, "the zone's list points to the dungeon")
    expectEqual(entrances[1] and entrances[1].count >= 1, true, "with the quests to pick up inside")
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showZone(SILVERPINE) -- the zone's list draws its row for the keep
    ns.Log.refresh()
end)

test("a quest that can be done in several zones follows the player and names the other zones", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 5), itemObjective(0, 3) }) -- bandits in Tirisfal, fangs in Silverpine
    local quest = ns.QuestState.getQuest(301)
    local here = ns.Location.composeStep(quest, SILVERPINE)
    expectEqual(here.zoneId, SILVERPINE, "listed where the player is, when part of it is there")
    expectEqual(here.otherZoneIds[1], TIRISFAL, "and it knows the other zone")
    expectEqual(#here.allPlaces > #here.places, true, "with the places of every zone kept for the maps")
    local away = ns.Location.composeStep(quest, 1637)
    expectEqual(away.zoneId, TIRISFAL, "elsewhere, it lists under the zone the game files it under")
    expectEqual(ns.Model.composeOtherZonesText(away.otherZoneIds), "Also in Silverpine Forest", "and says where else")
    expectEqual(ns.Model.composeOtherZonesText({}), nil, "a quest with one zone has no such line")
    expectEqual(ns.Model.composeOtherZonesText({ TIRISFAL, SILVERPINE, 1637, 1497 }):find("and 2 more", 1, true) ~= nil, true, "many zones are counted, not listed")
end)

test("a dungeon with quests to pick up is a location of its own, marked as a dungeon", function()
    local ns = createAddon()
    addDungeon()
    local quest = getQuest(getAvailableQuests(ns, 209), 518)
    expectEqual(quest ~= nil, true, "a quest for the dungeon is listed under it though its giver is outside")
    expectEqual(quest.places[1].groupZoneId, TIRISFAL, "and still points at the giver")
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 518) ~= nil, true, "it stays in the giver's zone too")
    local dungeon, zone
    for _, listed in ipairs(ns.Availability.getZones()) do
        if listed.zoneId == 209 then dungeon = listed end
        if listed.zoneId == TIRISFAL then zone = listed end
    end
    expectEqual(dungeon ~= nil and dungeon.isDungeon, true, "the dungeon is among the locations, as a dungeon")
    expectEqual(dungeon.count, 5, "counting the quest for it, the one that starts inside, and two chains that lead in, one by two lead-ins")
    expectEqual(zone.isDungeon, false, "an ordinary zone is not")
end)

test("the Dungeons tab lists the dungeons with quests, and a dungeon's page has its way in", function()
    local ns = createAddon()
    addDungeon()
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Availability.prepare()
    ns.Log.showDungeon(209)
    expectEqual(ns.Log.getShownDungeonId(), 209, "the keep is open")
    expectEqual(ns.Log.getSelectedDungeonQuestId(), nil, "on its own page")
    local canvas = ns.Log.getListCanvas()
    local isListed = false
    for index = 1, canvas.pools.buttons.usedCount or 0 do
        isListed = isListed or canvas.pools.buttons[index].data == -209
    end
    expectEqual(isListed, true, "the keep has its row")
    ns.Log.showZone(SILVERPINE)
    expectEqual(ns.Log.getAvailableZoneId(), SILVERPINE, "a zone still opens on the Available tab")
end)

test("a spawn recorded by an area inside a dungeon is placed at the dungeon's entrance", function()
    local ns = createAddon()
    addDungeon()
    local places = ns.Location.getObjectivePlaces(604, "monster", 1)
    expectEqual(#places, 2, "the entrance, and the spot itself")
    expectEqual(places[1].dungeonName, "Shadowfang Keep", "the entrance names the dungeon")
    expectEqual(places[1].mapZoneId, SILVERPINE, "and is drawn on the map of the zone outside")
    expectEqual(places[2].isInside and places[2].groupZoneId, 209, "the spot inside is kept for the dungeon's own map")
    expectEqual(ns.Database.getDungeon(2090) ~= nil and ns.Database.getDungeon(2090).areaId, 209, "an area inside a dungeon belongs to it")
end)

test("inside a dungeon the player's location comes from the game's number for the instance", function()
    local ns = createAddon()
    addDungeon()
    IsInInstance = function() return true end
    GetInstanceInfo = function() return "Shadowfang Keep", "party", 1, "Normal", 5, 0, false, 33 end
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            local module = original(name)
            if name == "ZoneDB" then
                module.instanceIdToAreaId = { [33] = 209 }
            end
            return module
        end
    end)(LibQuestieDB.Support.Get)
    expectEqual(ns.Model.getPlayer().zoneId, 209, "the dungeon")
    IsInInstance, GetInstanceInfo = nil, nil
end)

test("a chain that goes into a dungeon is listed under the dungeon from its first quest", function()
    local ns = createAddon()
    addDungeon()
    local quests = getAvailableQuests(ns, 209)
    local first = getQuest(quests, 520)
    expectEqual(first ~= nil, true, "its first quest, picked up outside, is listed under the dungeon")
    expectEqual(first.dungeonStepTitle, "Into the Vault", "naming the quest that goes in")
    expectEqual(getQuest(quests, 521), nil, "the quest inside is not offered before the first is done")
    expectEqual(getQuest(getAvailableQuests(ns, TIRISFAL), 520).dungeonStepTitle, nil, "its own zone lists it as usual")
end)

test("a chain that forks before a dungeon is listed under the dungeon down every branch", function()
    local ns, state = createAddon()
    addDungeon()
    local quests = getAvailableQuests(ns, 209)
    for _, questId in ipairs({ 524, 525 }) do
        local quest = getQuest(quests, questId)
        expectEqual(quest ~= nil, true, "lead-in " .. questId .. " is listed under the dungeon")
        expectEqual(quest.dungeonStepTitle, "Down Below", "naming the quest that goes in")
    end
    state.turnedInQuestIds[524], state.turnedInQuestIds[525], state.turnedInQuestIds[526], state.turnedInQuestIds[527] = true, true, true, true
    ns.Availability.invalidate()
    local afterwards = getQuest(getAvailableQuests(ns, 209), 528)
    expectEqual(afterwards ~= nil, true, "the quest after the dungeon is listed too")
    expectEqual(afterwards.dungeonStepTitle, nil, "without claiming it leads there")
end)

test("a dungeon's bar in the quest log draws its gate mark", function()
    local ns, state = createAddon()
    addDungeon()
    setQuest(state, 602, false, { killObjective(0, 1) })
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.refresh()
    C_Texture = { GetAtlasInfo = function(atlas) return atlas == "Dungeon" and {} or nil end }
    ns.Log.refresh()
    C_Texture = nil
end)

test("a dungeon quest with no recorded places still points at the dungeon", function()
    local ns, state = createAddon()
    addDungeon()
    setQuest(state, 602, false, { killObjective(0, 1) })
    local step = ns.Location.composeStep(ns.QuestState.getQuest(602), 85)
    expectEqual(step.zoneId, 209, "the area it is filed under is one of the dungeon's")
    expectEqual(#step.places, 1, "so the entrance stands in")
    expectEqual(step.unlocatedCount, 0, "and it no longer counts as nowhere to be found")
    local places = ns.Location.getObjectiveInfo(602, "monster", 1)
    expectEqual(#places, 1, "the objective itself is placed at the entrance, for the quest page")
    ns.Tracker.create()
    expectEqual(#ns.MapMarks.compose(1421) > 0, true, "and the map of the zone outside marks it")
end)

test("a quest the game labels as a dungeon quest goes under the dungeon when part of it is inside", function()
    local ns, state = createAddon()
    addDungeon()
    setQuest(state, 603, false, { killObjective(0, 5), killObjective(0, 1) })
    local quest = ns.QuestState.getQuest(603)
    expectEqual(ns.Location.composeStep(quest, 85).zoneId, 85, "unlabelled, it stays where the player is")
    C_QuestLog.GetQuestTagInfo = function(questId)
        return questId == 603 and { tagID = 81, tagName = "Dungeon" } or nil
    end
    expectEqual(ns.Location.composeStep(quest, 85).zoneId, 209, "labelled, the dungeon comes first")
    quest.objectives[2].isFinished = true
    expectEqual(ns.Location.composeStep(quest, 85).zoneId, 85, "until the part inside is done")
end)

test("inside a dungeon the player's location is the dungeon", function()
    local ns = createAddon()
    addDungeon()
    C_Map.GetBestMapForUnit = function() return nil end
    IsInInstance = function() return true end
    GetRealZoneText = function() return "Shadowfang Keep" end
    expectEqual(ns.Model.getPlayer().zoneId, 209, "found by the instance's name")
    IsInInstance = nil
end)

test("an objective without a known place is counted, so the quest can say so", function()
    local ns, state = createAddon()
    setQuest(state, 401, false, { killObjective(0, 5) })
    local entry = ns.Model.compose().groups[1].entries[1]
    expectEqual(entry.unlocatedCount, 1, "objectives without a place")
    setQuest(state, 201, false, { killObjective(5, 12) })
    expectEqual(ns.Model.composeEntry(201, ns.Model.getPlayer()).unlocatedCount, 0, "a quest with known places")
end)

test("a quest is a dungeon's only when its work can be done nowhere else", function()
    local ns = createAddon()
    addDungeon()
    local drops = { 5004, 5002 } -- the vault's warden, inside the keep, and Silverpine's wolves outside
    LibQuestieDB.Item.Get = (function(original)
        return function(id, field)
            if id == 7001 and field == "npcDrops" then
                return drops
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Item.Get)
    -- "Turtle Soup" asks for the item and nothing else
    expectEqual(ns.Location.getObjectivesDungeonId(606), nil, "an item that drops outside too is not the dungeon's")
    drops = { 5004 }
    expectEqual(ns.Location.getObjectivesDungeonId(606), 209, "one that drops only inside is")
end)

test("a quest only filed under a dungeon is not counted for it; one done, picked up or handed in inside is, or its work unplaced", function()
    local ns = createAddon()
    addDungeon()
    expectEqual(ns.Location.getInsideDungeonId(601), 209, "its work is inside the keep")
    expectEqual(ns.Location.getInsideDungeonId(602), 209, "filed under the keep, with work the data does not place: taken to be inside")
    expectEqual(ns.Location.getInsideDungeonId(605), nil, "filed under the keep, but only waiting at the envoy outside")
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 605 and field == "finishedBy" then
                return { { 5003 } } -- handed in to the archivist, who stands inside
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(ns.Location.getInsideDungeonId(605), 209, "handed in inside, it is the dungeon's")
    ns.Availability.prepare()
    local questIds = {}
    for _, questId in ipairs(ns.Availability.getZoneQuestIds(209)) do
        questIds[questId] = true
    end
    expectEqual(questIds[601], true, "counted for the dungeon")
    expectEqual(questIds[520], nil, "a quest leading in is not")
end)

test("for a quest filed under a dungeon, places at its entrance count as inside; elsewhere in the zone they do not", function()
    local ns = createAddon()
    addDungeon() -- the keep's entrance is at Silverpine 45, 68
    local spawnsByNpcId = { [5002] = { [130] = { { 46, 67 }, { 44, 70 } } } } -- wolves at the keep's mouth
    LibQuestieDB.Npc.Get = (function(original)
        return function(id, field)
            if field == "spawns" and spawnsByNpcId[id] then
                return spawnsByNpcId[id]
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Npc.Get)
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 602 and field == "objectives" then
                return { { { 5002 } } }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(ns.Location.getObjectivesDungeonId(602), 209, "creatures at the entrance of the dungeon it is filed under")
    spawnsByNpcId[5002] = { [130] = { { 20, 20 } } }
    expectEqual(ns.Location.getObjectivesDungeonId(602), nil, "the same creatures across the zone are not the dungeon's")
end)

test("a dungeon's wing that the database also lists as a dungeon is the dungeon it lies in", function()
    local ns = createAddon()
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            local module = original(name)
            if name == "ZoneDB" then
                -- Dire Maul, and its West wing listed on its own as well as inside it
                module.private.dungeons = {
                    [2557] = { "Dire Maul", nil, 357, { { 357, 59.2, 45.1 } } },
                    [10025] = { "Dire Maul", nil, 357, { { 357, 60.3, 30.2 } } },
                }
                module.private.subZoneToParentZoneOverride = "return { [10025] = 2557 }"
            end
            return module
        end
    end)(LibQuestieDB.Support.Get)
    expectEqual(ns.Database.getDungeon(10025).areaId, 2557, "the West wing is Dire Maul")
    expectEqual(ns.Database.getDungeon(2557).areaId, 2557, "and Dire Maul itself")
end)

test("a quest with work in two dungeons counts for both, as the Orb of Soran'ruk does", function()
    local ns = createAddon()
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            local module = original(name)
            if name == "ZoneDB" then
                module.private.dungeons = {
                    [209] = { "Shadowfang Keep", nil, 130, { { 130, 45, 68 } } },
                    [719] = { "Blackfathom Deeps", nil, 331, { { 331, 14, 14 } } },
                }
            end
            return module
        end
    end)(LibQuestieDB.Support.Get)
    local spawnsByNpcId = { [5001] = { [209] = { { -1, -1 } } }, [5002] = { [719] = { { -1, -1 } } } }
    LibQuestieDB.Npc.Get = (function(original)
        return function(id, field)
            if field == "spawns" and spawnsByNpcId[id] then
                return spawnsByNpcId[id]
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Npc.Get)
    -- "Two Fronts": bandits to kill (in the keep, here) and wolf fangs (from the deeps, here)
    local dungeonIds = {}
    for _, dungeonId in ipairs(ns.Location.getInsideDungeonIds(301)) do
        dungeonIds[dungeonId] = true
    end
    expectEqual(dungeonIds[209], true, "the dungeon of one objective")
    expectEqual(dungeonIds[719], true, "and of the other")
end)

test("a dungeon's run lists every quest done inside by what to do about it, with the lead-ins that open them", function()
    local ns = createAddon()
    addDungeon()
    ns.Availability.prepare()
    local run = ns.Availability.getDungeonRun(209)
    local function find(list, questId)
        for _, quest in ipairs(list) do
            if quest.questId == questId then
                return quest
            end
        end
    end
    local behind = find(run.behindLeadIn, 521)
    expectEqual(behind ~= nil, true, "Into the Vault waits behind its lead-in")
    expectEqual(behind and behind.leadInIds[1], 520, "named: Rumours of the Vault")
    local leadIn = find(run.pickUp, 520)
    expectEqual(leadIn and leadIn.isLeadIn, true, "the lead-in is among the quests to pick up, as a lead-in")
    expectEqual(leadIn and leadIn.leadsToTitle, "Into the Vault", "saying what it opens")
    expectEqual(find(run.notYet, 601) and find(run.notYet, 601).blocker.text, "Needs level 22", "a quest done inside, out of reach for now, says why")
    expectEqual(run.totalCount >= 2, true, "lead-ins are not counted as the dungeon's quests")
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showZone(209) -- the Available tab on the keep draws its run
    ns.Log.showQuestAnywhere(521)
    expectEqual(ns.Log.getSelectedAvailableQuestId(), 521, "a quest behind a lead-in opens its page")
    ns.Log.toggleChronicle()
    ns.ChroniclePage.openZone(209)
    ns.Log.refresh()
end)

test("a dungeon's run keeps its done quests, so even an all-done dungeon still lists them", function()
    local ns, state = createAddon()
    addDungeon()
    state.turnedInQuestIds[601] = true
    ns.Availability.prepare()
    local run = ns.Availability.getDungeonRun(209)
    local done
    for _, quest in ipairs(run.done) do
        done = quest.questId == 601 and quest or done
    end
    expectEqual(done ~= nil, true, "the handed-in quest is listed as done")
    expectEqual(done and done.isDone, true, "marked so")
    expectEqual(#run.done, run.doneCount, "every done quest, as many as counted")
    -- Drawn on the Dungeons tab, opened, without error
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.LogState.selectedDungeonId = 209
    ns.LogState.selectedQuestIds[ns.LogStyle.TAB_DUNGEONS] = -209
    ns.LogState.selectedTab = ns.LogStyle.TAB_DUNGEONS
    ns.LogState.shownDungeon = nil
    ns.Log.refresh()
    expectEqual(ns.LogState.shownDungeon ~= nil, true, "its page, the run's plan, is drawn")
end)

test("a dungeon quest from an item the data places nowhere is found inside, and its page says where to go", function()
    local ns = createAddon()
    addDungeon()
    LibQuestieDB.Item.Get = (function(original)
        return function(id, field)
            if id == 7002 and field == "npcDrops" then
                return { 5999 } -- a creature the data has no place for
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Item.Get)
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 506 and field == "zoneOrSort" then
                return 236 -- filed under the keep
            end
            if id == 506 and field == "objectives" then
                return { nil, nil, { { 7002 } } } -- and the letter is its work too, so the quest is the keep's
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(ns.Location.getPickupDungeonId(506), 209, "picked up in the keep")
    ns.Availability.prepare()
    local run = ns.Availability.getDungeonRun(209)
    local isFoundInside = false
    for _, quest in ipairs(run.foundInside) do
        isFoundInside = isFoundInside or quest.questId == 506
    end
    expectEqual(isFoundInside, true, "listed as found inside, not as one to pick up before going")
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showZone(209)
    ns.Log.showAvailable(506) -- its page, with the dungeon and its entrance
end)

test("dungeon work ignores places given only on a continent map, and an unplaced giver of a dungeon's quest is inside", function()
    local ns = createAddon()
    addDungeon()
    LibQuestieDB.Npc.Get = (function(original)
        return function(id, field)
            if id == 5998 and field == "spawns" then
                return { [10074] = { { 50, 50 } }, [209] = { { 10, 10 } } } -- one on the continent map, one in the keep
            end
            if id == 5997 and field == "spawns" then
                return nil -- a giver the data places nowhere
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Npc.Get)
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 506 and field == "zoneOrSort" then
                return 236
            end
            if id == 506 and field == "objectives" then
                return { { { 5998 } } }
            end
            if id == 506 and field == "startedBy" then
                return { { 5997 } }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(ns.Location.getObjectivesDungeonIds(506)[1], 209, "the work is the keep's: the continent place is no place")
    expectEqual(ns.Location.getPickupDungeonId(506), 209, "picked up in the keep")
end)

test("a dungeon the database does not know is learned from a run: its entrance and the quests done inside", function()
    local ns, state = createAddon()
    local instanceId = 3001
    IsInInstance = function() return state.isInInstance == true end
    GetInstanceInfo = function() return "Alcaz Prison", "party", 1, "Normal", 5, 0, false, instanceId end
    GetTime = function() return 100 end
    ns.Availability.prepare()
    setQuest(state, 501, false, { killObjective(0, 5) })
    state.isInInstance = false
    ns.LearnedDungeons.notePlace() -- standing at the way in
    local entranceZoneId = ns.Database.getAreaId(state.playerMapId)
    state.isInInstance = true
    ns.LearnedDungeons.handleEvent("PLAYER_ENTERING_WORLD")
    state.questLog[501].objectives = { killObjective(2, 5) }
    ns.LearnedDungeons.handleEvent("QUEST_LOG_UPDATE")
    ns.LearnedDungeons.handleEvent("QUEST_ACCEPTED", 520)
    local areaId = ns.LearnedDungeons.getAreaId(instanceId)
    local dungeon = ns.Database.getDungeon(areaId)
    expectEqual(dungeon and dungeon.name, "Alcaz Prison", "the instance is a dungeon now")
    expectEqual(dungeon and dungeon.isLearned, true, "marked as learned")
    expectEqual(dungeon and dungeon.entrances[1] and dungeon.entrances[1].zoneId, entranceZoneId, "its entrance is where the player went in")
    expectEqual(ns.Database.getInstanceDungeonId(), areaId, "the player is inside it")
    local questIds = {}
    for _, questId in ipairs(ns.Availability.getZoneQuestIds(areaId)) do
        questIds[questId] = true
    end
    expectEqual(questIds[501], true, "a quest worked on inside is the dungeon's")
    expectEqual(questIds[520], true, "and one picked up inside")
    expectEqual(ns.LearnedDungeons.isPickedUpInside(areaId, 520), true, "found inside")
    expectEqual(ns.LearnedDungeons.isPickedUpInside(areaId, 501), false, "the other was brought in")
    ns.Availability.reset()
    ns.Availability.prepare()
    expectEqual(#ns.Availability.getZoneQuestIds(areaId) >= 2, true, "kept when the index is built again")
    expectEqual(ns.GameOffers.composeReport():find("Alcaz Prison", 1, true) ~= nil, true, "in the report for the database's makers")
    IsInInstance, GetInstanceInfo, GetTime = nil, nil, nil
end)

test("a dungeon's run lists a quest once, though it is also the lead-in to another of its quests", function()
    local ns = createAddon()
    addDungeon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 520 and field == "objectives" then
                return { nil, nil, { { 7002 } } } -- the lead-in's work is in the keep too: one of its quests
            end
            if id == 520 and field == "zoneOrSort" then
                return 236
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Availability.prepare()
    local run = ns.Availability.getDungeonRun(209)
    local count, listed = 0, nil
    for _, list in ipairs({ run.inLog, run.pickUp, run.foundInside, run.behindLeadIn, run.notYet }) do
        for _, quest in ipairs(list) do
            if quest.questId == 520 then
                count, listed = count + 1, quest
            end
        end
    end
    expectEqual(count, 1, "listed once")
    expectEqual(listed and listed.isLeadIn, nil, "as the dungeon's own quest, not as a lead-in")
    expectEqual(listed and listed.opensTitle, "Into the Vault", "saying what it opens")
end)

---A quest provider for the tests: a dungeon of its own and the fields it knows for quest 501
local function addTestProvider(ns, dungeonName)
    ns.Database.registerProvider({
        name = "Test",
        order = 20,
        getQuestField = function(questId, field)
            if questId == 501 and field == "zoneOrSort" then
                local dungeon = ns.Database.getDungeonByName(dungeonName)
                return dungeon and dungeon.areaId
            end
            if questId == 501 and field == "questLevel" then return 99 end
            if questId == 777777 and field == "name" then return "A Quest Only the Provider Has" end
            return nil
        end,
        getDungeons = function()
            return { { name = dungeonName, entrances = { { zoneId = 85, x = 40, y = 50 } }, isLearned = true } }
        end,
    })
end

test("quest providers: each field trickles down to the first provider that knows it", function()
    local ns = createAddon()
    addTestProvider(ns, "Test Hollow")
    expectEqual(ns.Database.getQuestFieldFrom("QuestieDB", 501, "zoneOrSort"), 0, "QuestieDB files the quest nowhere")
    local dungeon = ns.Database.getDungeonByName("Test Hollow")
    expectEqual(dungeon ~= nil and dungeon.isLearned, true, "the provider's dungeon is a dungeon")
    expectEqual(ns.Database.getQuestField(501, "zoneOrSort"), dungeon and dungeon.areaId, "the provider says where it belongs")
    expectEqual(ns.Database.getQuestField(501, "questLevel"), 10, "QuestieDB's own answer wins where it has one")
    expectEqual(ns.Database.getQuestField(501, "name"), "Fresh Start", "and its name stays QuestieDB's")
    expectEqual(ns.Database.getQuestField(777777, "name"), nil, "a quest QuestieDB lacks stays unknown, for the missed-quest report")
    expectEqual(ns.Database.getQuestField(501, "requiredSourceItems"), nil, "nobody knows it: QuestieDB's empty value")
end)

test("quest providers: a quest QuestieDB files nowhere goes under the provider's dungeon, marked at its way in", function()
    local ns = createAddon()
    addTestProvider(ns, "Test Hollow")
    local areaId = ns.Database.getDungeonByName("Test Hollow").areaId
    expectEqual(ns.Location.getQuestDungeonId(501), areaId, "the quest is the dungeon's")
    local entrance = ns.Database.getDungeon(areaId).entrances[1]
    expectEqual(entrance and entrance.zoneId, 85, "its way in, from the provider")
    expectEqual(ns.Database.getDungeonByName("Wailing Caverns") == nil or not ns.Database.getDungeonByName("Wailing Caverns").isLearned, true,
        "QuestieDB's own dungeons stay its own")
end)

test("quest providers: a dungeon a provider knows and the player later learns by playing is one dungeon", function()
    local ns, state = createAddon()
    addTestProvider(ns, "Alcaz Prison")
    local instanceId = 3001
    local providedId = ns.Database.getDungeonByName("Alcaz Prison").areaId
    IsInInstance = function() return state.isInInstance == true end
    GetInstanceInfo = function() return "Alcaz Prison", "party", 1, "Normal", 5, 0, false, instanceId end
    GetTime = function() return 100 end
    ns.Availability.prepare()
    setQuest(state, 501, false, { killObjective(0, 5) })
    state.isInInstance = true
    ns.LearnedDungeons.handleEvent("PLAYER_ENTERING_WORLD")
    ns.LearnedDungeons.handleEvent("QUEST_ACCEPTED", 520)
    expectEqual(ns.LearnedDungeons.getAreaId(instanceId), providedId, "the learned instance takes the provider's dungeon's ID")
    expectEqual(ns.Database.getInstanceDungeonId(), providedId, "inside, the player is in that one dungeon")
    expectEqual(ns.Database.getDungeon(providedId).entrances[1].zoneId, 85, "its way in stays the provider's")
    local isListed = false
    for _, questId in ipairs(ns.Availability.getZoneQuestIds(providedId)) do
        isListed = isListed or questId == 520
    end
    expectEqual(isListed, true, "a quest picked up inside is under the same dungeon")
    IsInInstance, GetInstanceInfo, GetTime = nil, nil, nil
end)

test("DungeonJournal: a quest giver QuestieDB has no place for stands where the journal says, and a quest ready to hand in to them lists under its own zone", function()
    local ns = createAddon()
    local Quest = LibQuestieDB.Quest
    _G.C_AddOns = _G.C_AddOns or {}
    local savedQuest, savedLoaded = Quest.Get, C_AddOns.IsAddOnLoaded
    -- The lead-in, picked up elsewhere and handed in to the agent outside the dig; the agent's quest, from the journal
    Quest.Get = function(id, field)
        if id == 9601 then return ({ name = "Rumors", questLevel = 31, requiredLevel = 24, zoneOrSort = 85, startedBy = { { 9003 } }, finishedBy = { { 9999 } }, nextQuestInChain = 9602 })[field] end
        if id == 9602 then return ({ name = "Open Up", questLevel = 31, requiredLevel = 24, zoneOrSort = 85, startedBy = { { 9999 } }, finishedBy = { { 9999 } }, preQuestSingle = { 9601 } })[field] end
        return savedQuest(id, field)
    end
    C_AddOns.IsAddOnLoaded = function(name) return name == "ForeverDungeonJournal" end
    _G.ForeverDungeonJournal_NS = { DB = { ["Test Dig"] = { quests = { {
        id = 9602, name = "Open Up", level = 31, requires = 24,
        startMap = { mapID = 1420, x = 0.514, y = 0.592, targetName = "Hidden Agent" },
    } } } } }
    expectEqual(ns.Database.getNpcField(9999, "name"), "Hidden Agent", "the journal names them")
    local spawns = ns.Database.getNpcField(9999, "spawns") or {}
    local zoneId, points = next(spawns)
    expectEqual(zoneId ~= nil and points[1][1] == 51.4 and points[1][2] == 59.2, true, "and says where they stand")
    expectEqual(#ns.Location.getFinisherPlaces(9601) > 0, true, "so the lead-in has somewhere to be handed in")
    expectEqual(ns.Database.getNpcField(9003, "name"), "Deathguard Morris", "QuestieDB's own creatures stay its own")
    Quest.Get, C_AddOns.IsAddOnLoaded, _G.ForeverDungeonJournal_NS = savedQuest, savedLoaded, nil
end)

test("a quest ready to hand in to someone nobody knows the place of lists under its own zone, not Unknown location", function()
    local ns, state = createAddon()
    local Quest = LibQuestieDB.Quest
    local savedQuest = Quest.Get
    Quest.Get = function(id, field)
        if id == 9601 then return ({ name = "Rumors", questLevel = 10, requiredLevel = 1, zoneOrSort = 85, startedBy = { { 9003 } }, finishedBy = { { 9999 } } })[field] end
        return savedQuest(id, field)
    end
    setQuest(state, 9601, true)
    local entry = ns.Model.composeEntry(9601, ns.Model.getPlayer())
    expectEqual(entry.zoneId, 85, "under the quest's own zone")
    Quest.Get = savedQuest
end)

test("a dungeon with no level known opens its page; its buttons leave with the chronicle; its quests are the map's", function()
    local ns = createAddon()
    addDungeon()
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Availability.prepare()
    ns.Availability.getZoneLevels = function() return nil, nil end -- no level known for it
    local entranceButton = ns.LogState.frame.entranceButton
    entranceButton.Hide = function(self) rawset(self, "isShownNow", false) end
    entranceButton.SetShown = function(self, isShown) rawset(self, "isShownNow", isShown == true) end
    ns.Log.showDungeon(209)
    expectEqual(ns.Log.getShownDungeonId(), 209, "the keep's page opens")
    expectEqual(rawget(entranceButton, "isShownNow"), true, "with Show entrance")
    ns.Log.toggleChronicle()
    expectEqual(rawget(entranceButton, "isShownNow"), false, "the chronicle takes the dungeon's buttons away")
    ns.Log.toggleChronicle()
    ns.Log.openSettings()
    expectEqual(rawget(entranceButton, "isShownNow"), false, "and so do the settings")
    -- A quest to pick up opened on the Dungeons tab is the one the map highlights, as on the Available tab
    ns.Log.showDungeon(209, 506)
    expectEqual(ns.Log.getSelectedDungeonQuestId(), 506, "the quest is open")
    expectEqual(ns.Log.getHighlightedAvailableQuestId(), 506, "the map highlights its giver")
    expectEqual(ns.Log.getSelectedAvailableQuestId(), 506, "and Show turn-in marks its turn-in")
    local quest = ns.Log.getSelectedAvailableQuest()
    expectEqual(quest and quest.questId, 506, "with its places")
    ns.Log.showDungeon(209)
    expectEqual(ns.Log.getHighlightedAvailableQuestId(), nil, "the dungeon's own page highlights no quest")
end)
