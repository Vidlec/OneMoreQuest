-- Tests: the core: the module registry, redraws, tidying saved data, and the QuestieDB report.

test(
    "saved data is tidied after login: retired settings, other builds, and what was kept for quests done with",
    function()
        local ns, state = createAddon()
        setQuest(state, 301, false, { killObjective(0, 12) })
        ns.settings.markStyle, ns.settings.minimapIcon = "metal", { hide = false }
        local savedGetBuildInfo = GetBuildInfo
        GetBuildInfo = function()
            return "1.60.1", "70009"
        end
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
        expectEqual(
            ns.settings.cycledQuestZones[779] == nil and ns.settings.cycledQuestZones[301] == 17,
            true,
            "zone choices of quests done gone"
        )
        GetBuildInfo = savedGetBuildInfo
    end
)

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
    expectEqual(
        table.concat(moments, " "),
        table.concat({
            "Locale(invalidate)",
            "QuestText(create)",
            "Crafting(BANKFRAME_OPENED,PLAYERBANKSLOTS_CHANGED,TRADE_SKILL_LIST_UPDATE,TRADE_SKILL_SHOW,TRADE_SKILL_UPDATE,prune)",
            "LearnedDungeons(create)",
            "QuestState(QUEST_DATA_LOAD_RESULT,QUEST_TURNED_IN,changes:BAG_UPDATE_DELAYED,changes:QUEST_DATA_LOAD_RESULT,changes:QUEST_LOG_UPDATE,invalidate,prune)",
            "Focus(QUEST_ACCEPTED,QUEST_REMOVED,QUEST_TURNED_IN,QUEST_WATCH_LIST_CHANGED,SUPER_TRACKING_CHANGED,create)",
            "Model(changes:ZONE_CHANGED,invalidate)",
            "Spoilers(GOSSIP_SHOW,LOOT_OPENED,MAP_EXPLORATION_UPDATED,PLAYER_ENTERING_WORLD,PLAYER_TARGET_CHANGED,QUEST_COMPLETE,QUEST_DETAIL,QUEST_GREETING,QUEST_PROGRESS,ZONE_CHANGED_NEW_AREA,create,invalidate,prune)",
            "Events(CALENDAR_UPDATE_EVENT_LIST,create,tick)",
            "GameOffers(create,prune)",
            "DataCheck(QUEST_ACCEPTED,QUEST_COMPLETE,QUEST_TURNED_IN,create)",
            "Availability(PLAYER_ENTERING_WORLD,SKILL_LINES_CHANGED,SPELLS_CHANGED,UPDATE_FACTION,ZONE_CHANGED_NEW_AREA,invalidate)",
            "Prices(changes:GET_ITEM_INFO_RECEIVED)",
            "Profit(invalidate)",
            "KillCounter(create,prune)",
            "UnitTooltip(create,invalidate)",
            "Chronicle(create,prune)",
            "Ledger(create)",
            "Comms(create)",
            "Party(changes:GROUP_ROSTER_UPDATE)",
            "Announce(changes:QUEST_LOG_UPDATE)",
            "AutoQuest(GOSSIP_SHOW,QUEST_COMPLETE,QUEST_DETAIL,QUEST_GREETING,QUEST_PROGRESS)",
            "Nameplates(NAME_PLATE_UNIT_ADDED,NAME_PLATE_UNIT_REMOVED,RAID_TARGET_UPDATE,UNIT_CLASSIFICATION_CHANGED,refresh)",
            "Widgets(create)",
            "QuestTooltip(MODIFIER_STATE_CHANGED)",
            "BlizzardTracker(afterCombat,create)",
            "Tracker(PLAYER_ENTERING_WORLD,afterCombat,create,refresh,tick)",
            "Log(UPDATE_BINDINGS,afterCombat,create,refresh)",
            "MapDock(create,prune,tick)",
            "Gamepad(INPUT_DEVICE_INTERFACE_TRANSITION,PLAYER_REGEN_DISABLED,afterCombat,create)",
            "GamepadMenu(INPUT_DEVICE_INTERFACE_TRANSITION)",
            "GamepadTracker(INPUT_DEVICE_INTERFACE_TRANSITION,PLAYER_REGEN_DISABLED,afterCombat,create)",
            "GamepadMap(INPUT_DEVICE_INTERFACE_TRANSITION,PLAYER_REGEN_DISABLED,create)",
            "MapPins(create,refresh)",
            "GatheringSpots(LOOT_OPENED,MINIMAP_UPDATE_TRACKING,create)",
            "MinimapPins(MINIMAP_UPDATE_ZOOM,create,refresh,tick)",
            "MapHover(create)",
            "Compatibility(create)",
            "SettingsPage(create)",
        }, " "),
        "the modules and their moments"
    )
end)

test("a frequent event that changed nothing drawn does not redraw", function()
    local ns, state = createAddon()
    local redraws = 0
    ns.registerModule({
        name = "Counter",
        refresh = function()
            redraws = redraws + 1
        end,
    })
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
    C_Item = setmetatable({
        GetItemCount = function()
            return carried
        end,
    }, { __index = savedItem })
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
    C_Item = setmetatable({
        RequestLoadItemDataByID = function()
            asked = asked + 1
        end,
    }, { __index = savedItem2 })
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
        if module.name == "DataCheck" then
            dataCheck = module
        end
    end
    local savedGuid, savedName, savedQuestId, savedMetadata = UnitGUID, UnitName, GetQuestID, C_AddOns.GetAddOnMetadata
    local talkingTo -- the creature in the dialog: { id, name }
    UnitGUID = function(unit)
        if unit == "npc" and talkingTo then
            return "Creature-0-0-0-0-" .. talkingTo.id .. "-0"
        end
        return savedGuid and savedGuid(unit)
    end
    UnitName = function(unit)
        if unit == "npc" then
            return talkingTo and talkingTo.name
        end
        return savedName(unit)
    end
    local questieVersion = "1.0"
    C_AddOns.GetAddOnMetadata = function(name, field)
        if name == "QuestieDB" and field == "Version" then
            return questieVersion
        end
        local fallback = savedMetadata or GetAddOnMetadata
        return fallback and fallback(name, field)
    end
    local function differences()
        return table.concat(ns.DataCheck.composeReportLines(), "\n")
    end
    -- A quest the database does not have, from a creature
    talkingTo = { id = 9003, name = "Deathguard Morris" }
    dataCheck.events.QUEST_ACCEPTED(9999)
    expectEqual(
        differences():find("9999 | ? | not in the database | given by Deathguard Morris (9003)", 1, true) ~= nil,
        true,
        "a quest it lacks"
    )
    -- One it has, from a giver it does not list; and its items under another name (renamed in Forever)
    state.questLog[301] = {
        isComplete = false,
        objectives = {
            killObjective(0, 8),
            { type = "item", text = "Fresh Wolf Fang: 0/8", numFulfilled = 0, numRequired = 8, finished = false },
        },
    }
    dataCheck.events.QUEST_ACCEPTED(301)
    local lines = differences()
    expectEqual(
        lines:find("301 | Two Fronts | giver | Deathguard Morris (9003) | none", 1, true) ~= nil,
        true,
        "a giver it does not list"
    )
    expectEqual(
        lines:find("301 | Two Fronts | objectives | items: Fresh Wolf Fang | items: Wolf Fang", 1, true) ~= nil,
        true,
        "items of another name"
    )
    -- Handed in to someone else than the database's turn-in, and one handed in where it says: only the first noted
    talkingTo = { id = 9001, name = "Aide Rokka" }
    GetQuestID = function()
        return 301
    end
    dataCheck.events.QUEST_COMPLETE()
    dataCheck.events.QUEST_TURNED_IN(301)
    expectEqual(
        differences():find("301 | Two Fronts | turn-in | Aide Rokka (9001) | Envoy Maldrek (9002)", 1, true) ~= nil,
        true,
        "a turn-in it does not list"
    )
    GetQuestID = function()
        return 101
    end
    dataCheck.events.QUEST_COMPLETE()
    dataCheck.events.QUEST_TURNED_IN(101)
    expectEqual(
        differences():find("^101 ") == nil and differences():find("\n101 ") == nil,
        true,
        "the database's own turn-in: nothing"
    )
    -- In the report, under its own heading; Clear empties it, and so does a new QuestieDB (it may have fixed them)
    expectEqual(
        ns.GameOffers.composeReport():find("Where the game differs from QuestieDB", 1, true) ~= nil,
        true,
        "in the report"
    )
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
test("a module that fails is reported and the modules after it still run", function()
    local ns = createAddon()
    local reported, ran = {}, {}
    local savedGet = geterrorhandler
    geterrorhandler = function()
        return function(message)
            reported[#reported + 1] = message
        end
    end
    ns.registerModule({
        name = "Broken",
        create = function()
            error("broken create")
        end,
        refresh = function()
            error("broken refresh")
        end,
        changes = {
            QUEST_LOG_UPDATE = function()
                error("broken check")
            end,
        },
    })
    ns.registerModule({
        name = "After",
        create = function()
            ran.create = true
        end,
        refresh = function()
            ran.refresh = (ran.refresh or 0) + 1
        end,
    })
    ns.on("QUEST_FACTS_CHANGED", function()
        error("broken listener")
    end)
    ns.on("QUEST_FACTS_CHANGED", function()
        ran.listener = true
    end)
    local isFine, problem = pcall(function()
        ns.handleEvent(nil, "PLAYER_LOGIN")
        expectEqual(ran.create, true, "the module after a failing create is created")
        local before = ran.refresh or 0
        ns.queueRefresh()
        expectEqual((ran.refresh or 0) - before, 1, "and drawn after a failing redraw")
        ns.emit("QUEST_FACTS_CHANGED")
        expectEqual(ran.listener, true, "a failing listener leaves the others told")
        before = ran.refresh
        ns.handleEvent(nil, "QUEST_LOG_UPDATE")
        expectEqual(ran.refresh - before, 1, "a check that fails cannot say nothing changed")
        expectEqual(#reported >= 4, true, "every failure is reported to the game's error handler")
        expectEqual(table.concat(reported, "|"):find("broken create", 1, true) ~= nil, true, "with its message")
    end)
    geterrorhandler = savedGet -- (put back first: errors in the tests after go on up again)
    assert(isFine, problem)
end)

test(
    "a damaged saved file does not stop the addon loading: what is of the wrong kind goes back to its default",
    function()
        local ns = createAddon()
        local settings = ns.loadSettings("not a table")
        expectEqual(settings.isShown, true, "a saved file that is no table: the defaults")
        settings = ns.loadSettings({ isShown = false, trackerScale = "big", collapsedZones = "zones", language = 5 })
        expectEqual(settings.isShown, false, "what is right is kept")
        expectEqual(settings.trackerScale, 1, "a number that is words: the default")
        expectEqual(type(settings.collapsedZones), "table", "a table that is not one: empty")
        expectEqual(settings.language, "en", "the language too")
        ns.settings.killCounts = 7
        expectEqual(
            type(ns.getCharacterRecords("killCounts")),
            "table",
            "a character's records under something else: started afresh"
        )
        OneMoreQuestDB = 42
        ns.handleEvent(nil, "ADDON_LOADED", "OneMoreQuest")
        expectEqual(type(OneMoreQuestDB), "table", "loaded all the same")
        OneMoreQuestDB = nil
    end
)

test(
    "the holidays follow the day: a calendar read once still says what runs after midnight and in another month",
    function()
        local ns = createAddon()
        local now = { year = 2026, month = 11, monthDay = 21, hour = 23, minute = 59 }
        local opened = 0
        local savedTime, savedCalendar, savedDate, savedClock = C_DateAndTime, C_Calendar, date, time
        C_DateAndTime = {
            GetCurrentCalendarTime = function()
                return now
            end,
        }
        date, time = os.date, os.time
        -- The realm's calendar for November: Hallow's End's last days, the 1st and the 21st (made up to test by)
        C_Calendar = {
            OpenCalendar = function()
                opened = opened + 1
            end,
            GetMonthInfo = function(offset)
                return offset == 0 and { month = 11, year = 2026, numDays = 30 }
                    or { month = 12, year = 2026, numDays = 31 }
            end,
            GetNumDayEvents = function(offset, day)
                return offset == 0 and (day == 1 or day == 21) and 1 or 0
            end,
            GetDayEvent = function()
                return { calendarType = "HOLIDAY", title = "Hallow's End" }
            end,
        }
        ns.handleEvent(nil, "CALENDAR_UPDATE_EVENT_LIST")
        expectEqual(ns.Events.isActive("hallowsEnd"), true, "runs on the 21st, as the calendar says")
        now = { year = 2026, month = 11, monthDay = 22, hour = 0, minute = 1 }
        ns.Events.update()
        expectEqual(ns.Events.isActive("hallowsEnd"), false, "past midnight it is over, with no word from the calendar")
        now = { year = 2026, month = 12, monthDay = 1, hour = 0, minute = 1 }
        ns.Events.update()
        expectEqual(
            ns.Events.isActive("hallowsEnd"),
            false,
            "November's holidays are not December's: the 1st of the next month is not the 1st of this one"
        )
        expectEqual(opened >= 2, true, "a new month asks the calendar again")
        C_DateAndTime, C_Calendar, date, time = savedTime, savedCalendar, savedDate, savedClock
    end
)

test("a damaged saved dungeon record does not break the dungeons", function()
    local ns = createAddon()
    ns.settings.learnedDungeons = { [5] = "junk", [7] = { name = 3, entrance = "here", questIds = "none" }, nine = {} }
    ns.Database.forgetDungeons()
    local dungeons = ns.Database.getDungeons()
    local learned
    for _, dungeon in ipairs(dungeons) do
        if dungeon.isLearned then
            learned = dungeon
        end
    end
    expectEqual(learned and learned.name, "Instance 7", "the record that could be mended, named by its number")
    expectEqual(#ns.LearnedDungeons.getQuestIds(learned.areaId), 0, "with no quests")
    expectEqual(#ns.LearnedDungeons.composeReportLines(), 1, "and in the report, the broken one gone")
end)

test("a dungeon's way in is not learned from the graveyard or the inn the player comes out at", function()
    local ns = createAddon()
    local savedInInstance, savedInfo, savedDead, savedResting =
        IsInInstance, GetInstanceInfo, UnitIsDeadOrGhost, IsResting
    local isInside, isGhost, isAtInn = true, false, false
    IsInInstance = function()
        return isInside
    end
    GetInstanceInfo = function()
        return "Alcaz Prison", "party", 1, "", 5, 0, false, 7777
    end
    UnitIsDeadOrGhost = function()
        return isGhost
    end
    IsResting = function()
        return isAtInn
    end
    ns.LearnedDungeons.reset()
    local function enterAndLeave()
        isInside = true
        ns.LearnedDungeons.handleEvent("PLAYER_ENTERING_WORLD")
        isInside = false
        ns.LearnedDungeons.handleEvent("PLAYER_ENTERING_WORLD")
    end
    local function getEntrance()
        return ns.settings.learnedDungeons[7777] and ns.settings.learnedDungeons[7777].entrance
    end
    isGhost = true -- died inside and released: set down at a graveyard
    enterAndLeave()
    expectEqual(getEntrance(), nil, "not the graveyard")
    isGhost, isAtInn = false, true -- hearthed out
    enterAndLeave()
    expectEqual(getEntrance(), nil, "not the inn")
    isAtInn = false -- walked out
    enterAndLeave()
    expectEqual(getEntrance() and getEntrance().zoneId, 85, "walked out, at the way in")
    IsInInstance, GetInstanceInfo, UnitIsDeadOrGhost, IsResting = savedInInstance, savedInfo, savedDead, savedResting
end)

test("a creature's places show each quest what that quest does there, not what the first quest to ask did", function()
    local ns = createAddon()
    local savedGet = LibQuestieDB.Quest.Get
    LibQuestieDB.Quest.Get = function(id, field)
        if id == 990 then -- the bandits' orders, from Roadside Bandits, to collect
            if field == "name" then
                return "Collect Orders"
            end
            if field == "objectives" then
                return { nil, nil, { { 7004 } } }
            end
            if field == "finishedBy" then
                return { { 9002 } }
            end
            return nil
        end
        return savedGet(id, field)
    end
    local kill = ns.Location.composeStep({
        questId = 201,
        isComplete = false,
        objectives = { { type = "monster", label = "Roadside Bandit slain", isFinished = false } },
    }, nil)
    local loot = ns.Location.composeStep({
        questId = 990,
        isComplete = false,
        objectives = { { type = "item", label = "Bandit Orders", isFinished = false } },
    }, nil)
    expectEqual(kill.allPlaces[1].glyph, "kill", "swords where the first quest kills them")
    expectEqual(loot.allPlaces[1].glyph, "loot", "a bag where the second loots them")
    kill = ns.Location.composeStep({
        questId = 201,
        isComplete = false,
        objectives = { { type = "monster", label = "Roadside Bandit slain", isFinished = false } },
    }, nil)
    expectEqual(kill.allPlaces[1].glyph, "kill", "and the first keeps its own")
    LibQuestieDB.Quest.Get = savedGet
end)

test("a chain is the same chain whichever of its quests is asked for", function()
    local ns = createAddon()
    -- 526 needs two quests at once: the chain is cut there, from either side
    for _, questId in ipairs({ 526, 527, 528 }) do
        expectEqual(table.concat(ns.Chain.getQuestIds(questId), ","), "526,527,528", "asked from " .. questId)
    end
    expectEqual(table.concat(ns.Chain.getQuestIds(524), ","), "524", "the lead-in alone is no chain")
    expectEqual(select(2, ns.Chain.getStep(527)), 3, "three steps from the middle")
    expectEqual(ns.Chain.getStep(526), 1, "the first of them")
    -- A step that names no next one: what follows it is read off the quests that need it
    local savedGet = LibQuestieDB.Quest.Get
    LibQuestieDB.Quest.Get = function(id, field)
        if id == 102 and field == "nextQuestInChain" then
            return 0
        end
        return savedGet(id, field)
    end
    ns.Availability.getFollowUps = function(questId)
        return ({ [101] = { 102 }, [102] = { 103 } })[questId] or {}
    end
    for _, questId in ipairs({ 101, 102, 103 }) do
        expectEqual(
            table.concat(ns.Chain.getQuestIds(questId), ","),
            "101,102,103",
            "followed forward from " .. questId
        )
    end
    LibQuestieDB.Quest.Get = savedGet
end)

test("a pre-quest is told apart from a chain: what a quest unlocks and what it followed", function()
    local ns, state = createAddon()
    -- A fork, for further down: the last step of a chain opens two quests (any one of two is enough for the second),
    -- and one more that is another race's
    local fields = {
        [201] = { preQuestSingle = { 103 } },
        [301] = { preQuestSingle = { 103, 520 } },
        [401] = { preQuestSingle = { 103 }, requiredRaces = 1 },
    }
    local savedGet = LibQuestieDB.Quest.Get
    LibQuestieDB.Quest.Get = function(id, field)
        if fields[id] and fields[id][field] ~= nil then
            return fields[id][field]
        end
        return savedGet(id, field)
    end
    ns.Availability.prepare()
    local function list(questIds)
        return table.concat(questIds, ",")
    end
    -- Patrols (526) needs The Sewer Key (524) and Break-In (525) at once: no chain joins them, so each is its pre-quest
    expectEqual(list(ns.Chain.getUnlockedQuestIds(524)), "526", "a lead-in unlocks the quest that needs it")
    expectEqual(list(ns.Chain.getUnlockedQuestIds(525)), "526", "and so does the other one")
    local requiredIds, isAnyEnough = ns.Chain.getRequiredQuestIds(526)
    expectEqual(list(requiredIds), "524,525", "which followed them both")
    expectEqual(isAnyEnough, false, "all of them, not any one")
    -- Steps of one chain are shown as the chain, not twice
    expectEqual(list(ns.Chain.getUnlockedQuestIds(526)), "", "the next step of its chain is no pre-quest link")
    expectEqual(list(ns.Chain.getRequiredQuestIds(527)), "", "nor the step before")
    expectEqual(list(ns.Chain.getUnlockedQuestIds(201)), "", "a quest nothing waits for")
    expectEqual(ns.Chain.composeUnlockText({ 526 }, true), "Unlocks Patrols", "one is named")
    expectEqual(ns.Chain.composeUnlockText({ 526 }, false), "Unlocks 1 quest", "unless the story is held back")
    expectEqual(ns.Chain.composeUnlockText({ 526, 527 }, true), "Unlocks 2 quests", "several are counted")
    expectEqual(ns.Chain.composeFollowText({ 524 }), "Follows The Sewer Key", "what it followed, by name")
    -- In the tracker's model, for the row's mark
    setQuest(state, 524, false)
    local entry = ns.Model.composeEntry(524, ns.Model.getPlayer())
    expectEqual(list(entry.unlockIds), "526", "the tracker's entry carries it")
    expectEqual(entry.chainIndex, nil, "with no chain step beside it")
    -- A quest unlocked already is not counted any more
    state.turnedInQuestIds[526] = true
    expectEqual(list(ns.Chain.getUnlockedQuestIds(524)), "", "done: nothing left to unlock")
    state.turnedInQuestIds[526] = nil

    -- The fork set up above: the last step of a chain opens two quests, the third is not this character's
    expectEqual(list(ns.Chain.getUnlockedQuestIds(103)), "201,301", "a fork unlocks each branch, not the other race's")
    expectEqual(select(2, ns.Chain.getStep(103)), 3, "and its own chain stays the chain")
    requiredIds, isAnyEnough = ns.Chain.getRequiredQuestIds(301)
    expectEqual(list(requiredIds), "103,520", "a quest that needs any one of two")
    expectEqual(isAnyEnough, true, "says any one is enough")
    -- The diagram: back along the chain, on into both branches, each quest once
    local diagram = ns.Chain.getDiagram(103)
    expectEqual(diagram.before[1].questId, 102, "the step before")
    expectEqual(diagram.before[1].children[1].questId, 101, "and the one before that")
    expectEqual(#diagram.after, 2, "both branches after")
    local boxes, slotCount = ns.LogDiagram.compose(103)
    expectEqual(#boxes, 5, "five boxes: two above, the quest, two below")
    expectEqual(slotCount, 2, "two slots across, for the two branches")
    local this = boxes[#boxes]
    expectEqual(this.depth == 0 and this.slot == 0.5, true, "the quest itself over the middle of its branches")
    local depths = {}
    for _, box in ipairs(boxes) do
        depths[box.questId] = box.depth
    end
    expectEqual(depths[101] == -2 and depths[102] == -1, true, "what comes before above it, the earliest highest")
    expectEqual(depths[201] == 1 and depths[301] == 1, true, "what it unlocks below it")
    LibQuestieDB.Quest.Get = savedGet
end)

test("a repeatable quest handed in is offered again; another counts as done at once", function()
    local ns = createAddon()
    ns.QuestState.noteTurnedIn(515) -- Daily Patrol
    expectEqual(ns.QuestState.isTurnedIn(515), false, "a repeatable one is not done for the session")
    ns.QuestState.noteTurnedIn(201)
    expectEqual(ns.QuestState.isTurnedIn(201), true, "another is done before the game's mark comes")
end)
