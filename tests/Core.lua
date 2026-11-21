-- Tests: the core: the module registry, redraws, tidying saved data, and the QuestieDB report.

test("saved data is tidied after login: retired settings, other builds, and what was kept for quests done with", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12) })
    ns.settings.markStyle, ns.settings.minimapIcon = "metal", { hide = false }
    local savedGetBuildInfo = GetBuildInfo
    GetBuildInfo = function() return "1.60.1", "70009" end
    ns.settings.questsNotInGame = { ["1"] = { [5] = true }, ["70009"] = { [6] = true } }
    local killCounts = ns.getCharacterRecords("killCounts")
    killCounts[301], killCounts[777] = { {} }, { {} }
    local open = ns.Chronicle.getBook().open
    open[301], open[778] = { deaths = 0 }, { deaths = 1 }
    local offers = ns.getCharacterRecords("learnedOffers")
    state.turnedInQuestIds[779] = true
    offers[779], offers[780] = { title = "done" }, { title = "abandoned, offered again" }
    ns.settings.cycledQuestZones = { [779] = 17, [301] = 17 }
    ns.tidySavedData()
    expectEqual(ns.settings.markStyle == nil and ns.settings.minimapIcon == nil, true, "retired settings gone")
    expectEqual(ns.settings.questsNotInGame["1"], nil, "another build's answers gone")
    expectEqual(next(ns.settings.questsNotInGame) ~= nil, true, "this build's kept")
    expectEqual(killCounts[777] == nil and killCounts[301] ~= nil, true, "kills kept only for quests in the log")
    expectEqual(open[778] == nil and open[301] ~= nil, true, "the chronicle's open quests likewise")
    expectEqual(offers[779] == nil and offers[780] ~= nil, true, "offers of quests done gone, of the rest kept")
    expectEqual(ns.settings.cycledQuestZones[779] == nil and ns.settings.cycledQuestZones[301] == 17, true, "zone choices of quests done gone")
    GetBuildInfo = savedGetBuildInfo
end)

test("every module registers the moments it takes part in, in the TOC's order", function()
    local ns = createAddon()
    local moments = {}
    for _, module in ipairs(ns.getModules()) do
        local names = {}
        for _, moment in ipairs({ "create", "invalidate", "refresh", "tick", "afterCombat", "prune" }) do
            if module[moment] ~= nil then
                expectEqual(type(module[moment]), "function", module.name .. "." .. moment .. " is a function")
                names[#names + 1] = moment
            end
        end
        for event, handler in pairs(module.events or {}) do
            expectEqual(type(handler), "function", module.name .. " handles " .. event)
            names[#names + 1] = event
        end
        for event, check in pairs(module.changes or {}) do
            expectEqual(type(check), "function", module.name .. " checks " .. event)
            names[#names + 1] = "changes:" .. event
        end
        table.sort(names)
        moments[#moments + 1] = module.name .. "(" .. table.concat(names, ",") .. ")"
    end
    expectEqual(table.concat(moments, " "), table.concat({
        "QuestText(create)", "Crafting(BANKFRAME_OPENED,PLAYERBANKSLOTS_CHANGED,TRADE_SKILL_LIST_UPDATE,TRADE_SKILL_SHOW,TRADE_SKILL_UPDATE,prune)", "LearnedDungeons(create)", "QuestState(QUEST_DATA_LOAD_RESULT,QUEST_TURNED_IN,changes:BAG_UPDATE_DELAYED,changes:QUEST_DATA_LOAD_RESULT,changes:QUEST_LOG_UPDATE,invalidate,prune)",
        "Focus(QUEST_REMOVED,QUEST_TURNED_IN,QUEST_WATCH_LIST_CHANGED,SUPER_TRACKING_CHANGED,create)", "Model(changes:ZONE_CHANGED,invalidate)", "Events(CALENDAR_UPDATE_EVENT_LIST,create,tick)", "GameOffers(create,prune)", "DataCheck(QUEST_ACCEPTED,QUEST_COMPLETE,QUEST_TURNED_IN,create)",
        "Availability(PLAYER_ENTERING_WORLD,SKILL_LINES_CHANGED,SPELLS_CHANGED,UPDATE_FACTION,ZONE_CHANGED_NEW_AREA,invalidate)", "Prices(changes:GET_ITEM_INFO_RECEIVED)", "Profit(invalidate)", "KillCounter(create,prune)", "UnitTooltip(create)",
        "Chronicle(create,prune)", "Ledger(create)", "Comms(create)", "Party(changes:GROUP_ROSTER_UPDATE)", "Announce(changes:QUEST_LOG_UPDATE)", "AutoQuest(GOSSIP_SHOW,QUEST_COMPLETE,QUEST_DETAIL,QUEST_GREETING,QUEST_PROGRESS)", "Nameplates(NAME_PLATE_UNIT_ADDED,NAME_PLATE_UNIT_REMOVED,refresh)", "Widgets(create)", "QuestTooltip(MODIFIER_STATE_CHANGED)", "BlizzardTracker(afterCombat,create)",
        "Tracker(afterCombat,create,refresh,tick)",
        "Log(UPDATE_BINDINGS,afterCombat,create,refresh)", "MapDock(create,prune,tick)", "MapPins(create,refresh)",
        "MinimapPins(MINIMAP_UPDATE_ZOOM,create,refresh,tick)", "MapHover(create)", "Compatibility(create)", "SettingsPage(create)",
    }, " "), "the modules and their moments")
end)

test("a frequent event that changed nothing drawn does not redraw", function()
    local ns, state = createAddon()
    local redraws = 0
    ns.registerModule({ name = "Counter", refresh = function() redraws = redraws + 1 end })
    local function redrawsAfter(event, ...)
        local before = redraws
        ns.handleEvent(nil, event, ...)
        return redraws - before
    end
    -- The quest log: a kill of a quest's mob redraws, a QUEST_LOG_UPDATE with nothing new does not
    state.questLog[201] = { isComplete = false, objectives = { killObjective(1, 12) } }
    redrawsAfter("QUEST_LOG_UPDATE")
    expectEqual(redrawsAfter("QUEST_LOG_UPDATE"), 0, "the log as it was: no redraw")
    state.questLog[201] = { isComplete = false, objectives = { killObjective(2, 12) } }
    expectEqual(redrawsAfter("QUEST_LOG_UPDATE"), 1, "a kill counted: redrawn")
    -- The bags: only a change in the number of an item something drawn depends on
    local carried = 0
    local savedItem = C_Item
    C_Item = setmetatable({ GetItemCount = function() return carried end }, { __index = savedItem })
    expectEqual(redrawsAfter("BAG_UPDATE_DELAYED"), 0, "no item counted yet: no redraw")
    ns.QuestState.getItemCount(5555)
    carried = 1
    expectEqual(redrawsAfter("BAG_UPDATE_DELAYED"), 1, "an item that matters picked up: redrawn")
    expectEqual(redrawsAfter("BAG_UPDATE_DELAYED"), 0, "and not again for the next loot")
    C_Item = savedItem
    -- Walking between subzones, and a group update with the same people
    redrawsAfter("ZONE_CHANGED")
    expectEqual(redrawsAfter("ZONE_CHANGED"), 0, "the same zone: no redraw")
    redrawsAfter("GROUP_ROSTER_UPDATE")
    expectEqual(redrawsAfter("GROUP_ROSTER_UPDATE"), 0, "the same group: no redraw")
    -- Events no module checks still redraw every time; data arriving redraws once it settles
    expectEqual(redrawsAfter("QUEST_ACCEPTED", 201), 1, "a quest taken: redrawn")
    -- The game answers every addon's asking about items and quests: only answers to this addon's own redraw
    expectEqual(redrawsAfter("GET_ITEM_INFO_RECEIVED", 2589, true), 0, "another addon's item arrived: no redraw")
    local savedItem2 = C_Item
    local asked = 0
    C_Item = setmetatable({ RequestLoadItemDataByID = function() asked = asked + 1 end }, { __index = savedItem2 })
    ns.Prices.requestItem(2590)
    ns.Prices.requestItem(2590)
    expectEqual(asked, 1, "an item is asked for once")
    expectEqual(redrawsAfter("GET_ITEM_INFO_RECEIVED", 2590, true), 1, "an item asked for arrived: redrawn")
    ns.Prices.requestItem(2591)
    expectEqual(redrawsAfter("GET_ITEM_INFO_RECEIVED", 2591, false), 0, "the game has no such item: no redraw")
    ns.Prices.requestItem(2591)
    expectEqual(asked, 2, "and it is not asked for again")
    C_Item = savedItem2
    expectEqual(redrawsAfter("QUEST_DATA_LOAD_RESULT", 777, true), 0, "another addon's quest details: no redraw")
end)

test("where the game's quests differ from the database is noted for the report", function()
    local ns, state = createAddon()
    local dataCheck
    for _, module in ipairs(ns.getModules()) do
        if module.name == "DataCheck" then dataCheck = module end
    end
    local savedGuid, savedName, savedQuestId, savedMetadata = UnitGUID, UnitName, GetQuestID, C_AddOns.GetAddOnMetadata
    local talkingTo -- the creature in the dialog: { id, name }
    UnitGUID = function(unit)
        if unit == "npc" and talkingTo then return "Creature-0-0-0-0-" .. talkingTo.id .. "-0" end
        return savedGuid and savedGuid(unit)
    end
    UnitName = function(unit)
        if unit == "npc" then return talkingTo and talkingTo.name end
        return savedName(unit)
    end
    local questieVersion = "1.0"
    C_AddOns.GetAddOnMetadata = function(name, field)
        if name == "QuestieDB" and field == "Version" then return questieVersion end
        local fallback = savedMetadata or GetAddOnMetadata
        return fallback and fallback(name, field)
    end
    local function differences()
        return table.concat(ns.DataCheck.composeReportLines(), "\n")
    end
    -- A quest the database does not have, from a creature
    talkingTo = { id = 9003, name = "Deathguard Morris" }
    dataCheck.events.QUEST_ACCEPTED(9999)
    expectEqual(differences():find("9999 | ? | not in the database | given by Deathguard Morris (9003)", 1, true) ~= nil, true, "a quest it lacks")
    -- One it has, from a giver it does not list; and its items under another name (renamed in Forever)
    state.questLog[301] = { isComplete = false, objectives = { killObjective(0, 8), { type = "item", text = "Fresh Wolf Fang: 0/8", numFulfilled = 0, numRequired = 8, finished = false } } }
    dataCheck.events.QUEST_ACCEPTED(301)
    local lines = differences()
    expectEqual(lines:find("301 | Two Fronts | giver | Deathguard Morris (9003) | none", 1, true) ~= nil, true, "a giver it does not list")
    expectEqual(lines:find("301 | Two Fronts | objectives | items: Fresh Wolf Fang | items: Wolf Fang", 1, true) ~= nil, true, "items of another name")
    -- Handed in to someone else than the database's turn-in, and one handed in where it says: only the first noted
    talkingTo = { id = 9001, name = "Aide Rokka" }
    GetQuestID = function() return 301 end
    dataCheck.events.QUEST_COMPLETE()
    dataCheck.events.QUEST_TURNED_IN(301)
    expectEqual(differences():find("301 | Two Fronts | turn-in | Aide Rokka (9001) | Envoy Maldrek (9002)", 1, true) ~= nil, true, "a turn-in it does not list")
    GetQuestID = function() return 101 end
    dataCheck.events.QUEST_COMPLETE()
    dataCheck.events.QUEST_TURNED_IN(101)
    expectEqual(differences():find("^101 ") == nil and differences():find("\n101 ") == nil, true, "the database's own turn-in: nothing")
    -- In the report, under its own heading; Clear empties it, and so does a new QuestieDB (it may have fixed them)
    expectEqual(ns.GameOffers.composeReport():find("Where the game differs from QuestieDB", 1, true) ~= nil, true, "in the report")
    questieVersion = "1.1"
    expectEqual(differences(), "", "a new QuestieDB starts afresh")
    talkingTo = { id = 9003, name = "Deathguard Morris" }
    dataCheck.events.QUEST_ACCEPTED(9999)
    ns.GameOffers.clearMissed()
    expectEqual(differences(), "", "cleared with the report")
    UnitGUID, UnitName, GetQuestID, C_AddOns.GetAddOnMetadata = savedGuid, savedName, savedQuestId, savedMetadata
end)

test("what is read of the quest database is kept once frames run, bounded, and checked against the database", function()
    local ns = createAddon()
    local reads = 0
    local spawns = { [17] = { { 50, 50 } } }
    local savedGet = LibQuestieDB.Npc.Get
    LibQuestieDB.Npc.Get = function(id, field)
        reads = reads + 1
        if field == "spawns" and id == 4242 then
            return { [17] = { { 50, 50 } } } -- a fresh table at every read, as QuestieDB gives
        end
        if field == "name" and id == 4242 then
            return "Somebody"
        end
        return nil
    end
    -- No frames yet (as in every other test): each asking reads the database
    ns.Database.getNpcField(4242, "name")
    ns.Database.getNpcField(4242, "name")
    expectEqual(reads, 2, "before frames run nothing is kept")
    -- Frames run: read once, then kept, the absence of a value too
    ns.frameNumber = 1
    reads = 0
    local first = ns.Database.getNpcField(4242, "spawns")
    local second = ns.Database.getNpcField(4242, "spawns")
    expectEqual(reads, 1, "a table field is decoded once")
    expectEqual(first == second, true, "and the same table is given again")
    reads = 0
    ns.Database.getObjectField(77, "name")
    local afterFirst = reads
    ns.Database.getObjectField(77, "name")
    expectEqual(reads, afterFirst, "that the database has nothing is kept too")
    expectEqual(#ns.Database.verifyReads(), 0, "what is kept is what the database says")
    -- A caller that changes a kept table is found out
    first[17][1][1] = 99
    expectEqual(#ns.Database.verifyReads(), 1, "a kept table a caller changed no longer matches")
    first[17][1][1] = 50
    -- Bounded: reading far more than a generation holds does not keep it all, and what is read again stays
    reads = 0
    for id = 1, ns.Database.CACHE_GENERATION_SIZE * 3 do
        ns.Database.getNpcField(100000 + id, "name")
        if id % 1000 == 0 then
            ns.Database.getNpcField(4242, "spawns") -- read now and then: it stays
        end
    end
    reads = 0
    ns.Database.getNpcField(4242, "spawns")
    expectEqual(reads, 0, "what keeps being read is still kept")
    ns.Database.getNpcField(100001, "name")
    expectEqual(reads, 1, "what was read long ago was let go")
    ns.Database.forgetReads()
    ns.Database.getNpcField(4242, "spawns")
    expectEqual(reads, 2, "forgotten on demand")
    LibQuestieDB.Npc.Get = savedGet
    ns.frameNumber = 0
end)
