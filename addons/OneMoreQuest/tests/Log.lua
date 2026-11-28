-- Tests: the quest log window: its list, quest pages, settings, and the map docked beside it.

test("the window draws every state without errors", function()
    local ns, state = createAddon()
    setQuest(state, 101, true)
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    ns.Tracker.create()
    ns.Tracker.refresh()
    state.watchedQuestIds = {}
    ns.Tracker.refresh()
    ns.Tracker.queueRefresh()
    ns.Tracker.resetPosition()
    ns.BlizzardTracker.apply()
    ObjectiveTrackerFrame = UIParent
    ns.BlizzardTracker.apply()
    ObjectiveTrackerFrame = nil
end)

test("the quest log lists every quest, tracked or not, with zones open", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    state.questLog[301] = { isComplete = false, objectives = { killObjective(12, 12), itemObjective(0, 4) } }
    expectEqual(#ns.QuestState.getLogQuestIds(), 2, "log size")
    expectEqual(ns.QuestState.isWatched(301), false, "untracked quest")
    local model = ns.Model.compose(
        nil,
        { questIds = ns.QuestState.getLogQuestIds(), collapsedZones = {}, isExpandedByDefault = true }
    )
    expectEqual(model.questCount, 2, "quests in the model")
    expectEqual(getGroup(model, SILVERPINE).isCollapsed, false, "other zone open")
end)

test("beside a map whose border another addon redrew, the panels are as tall as the map seen", function()
    local ns = createAddon()
    local points = {}
    local createWidget = CreateFrame
    CreateFrame = function(kind, name, ...)
        local widget = createWidget(kind, name, ...)
        if name == "OneMoreQuestLog" then
            rawset(widget, "SetPoint", function(_, point, region, _, x, y)
                points[point] = { region = region, x = x, y = y }
            end)
        end
        return widget
    end
    local function createBox(left, top, right, bottom, isShown, regions)
        return {
            GetRegions = function()
                return unpack(regions or {})
            end,
            GetChildren = function() end,
            GetLeft = function()
                return left
            end,
            GetRight = function()
                return right
            end,
            GetTop = function()
                return top
            end,
            GetBottom = function()
                return bottom
            end,
            GetWidth = function()
                return right - left
            end,
            IsShown = function()
                return isShown ~= false
            end,
            GetAlpha = function()
                return 1
            end,
        }
    end
    -- The map's picture, the redrawn title bar right on top of it, its footer right under it, a button
    -- somewhere on the map that is no bar at all, and the game's invisible frame that holds the room above the
    -- map for its title
    local texture = createBox(0, 0, 0, 0)
    local container = createBox(0, 500, 700, 0)
    local children = {
        container,
        createBox(0, 522, 700, 500, true, { texture }),
        createBox(0, 0, 700, -20, true, { texture }),
        createBox(650, 40, 690, 0, true, { texture }),
        createBox(0, 560, 700, 500),
    }
    rawset(WorldMapFrame, "ScrollContainer", container)
    rawset(WorldMapFrame, "GetChildren", function()
        return unpack(children)
    end)
    rawset(WorldMapFrame, "BorderFrame", { NineSlice = createBox(0, 0, 0, 0, false) })
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    -- Like the map (the default): a title strip continuing the map's bar, 3 points of frame round the content
    expectEqual(points.TOPLEFT.region, container, "beside the map's picture")
    expectEqual(points.TOPLEFT.y - 3, 0, "the content starts level with the map's picture")
    expectEqual(points.TOPLEFT.y - 3 + 22, 22, "under a title strip level with the map's title bar")
    expectEqual(points.BOTTOMLEFT.y + 3, -20, "and ends level with the footer")
    -- Flat: no strip, so the content starts at the top of the title bar
    ns.settings.windowBorder = "flat"
    ns.MapDock.apply()
    expectEqual(points.TOPLEFT.y - 3, 22, "flat: the content starts at the title bar's top")
    expectEqual(points.BOTTOMLEFT.y + 3, -20, "flat: and ends level with the footer")
    -- Thin gold: a strip of its own, its top level with the map's title bar
    ns.settings.windowBorder = "gold"
    ns.MapDock.apply()
    expectEqual(points.TOPLEFT.y - 3 + 22, 22, "gold: the strip's top level with the title bar's")
    -- With the game's own border, the map window is what is seen
    ns.settings.windowBorder = "map"
    rawset(WorldMapFrame, "BorderFrame", { NineSlice = createBox(0, 0, 0, 0, true) })
    ns.MapDock.apply()
    expectEqual(points.TOPLEFT.region, WorldMapFrame, "beside the map window")
    CreateFrame = createWidget
end)

test("the arrow on the map folds the quest panels away, and asking for a quest brings them back", function()
    local ns = createAddon()
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    expectEqual(ns.Log.isOpen(), true, "the panels are out with the map")
    ns.settings.arePanelsHidden = true
    ns.MapDock.apply()
    expectEqual(ns.Log.isOpen(), false, "folded away, the map is alone")
    ns.Log.showAvailable(501)
    expectEqual(ns.Log.isOpen(), true, "opening a quest brings them out")
    expectEqual(ns.settings.arePanelsHidden, true, "for this opening: the arrow's choice stays")
    -- (the map's and the quest log's keys are played in the simulator, on a map that opens and closes:
    -- sim/scenarios/map-and-log-keys.lua)
end)

test("scroll areas use the game's slim scroll bar when the client has it", function()
    local ns = createAddon()
    local initialized
    ScrollUtil = {
        InitScrollFrameWithScrollBar = function(scrollFrame, scrollBar)
            initialized = { scrollFrame, scrollBar }
        end,
    }
    local canvas = ns.Widgets.createCanvas("TestCanvas", UIParent, 300, 200)
    expectEqual(initialized ~= nil and initialized[1] == canvas.frame, true, "the area is tied to the game's bar")
    expectEqual(canvas.frame.ScrollBar == initialized[2], true, "which is the bar the area shows and hides")
    canvas:finish(500) -- drawing and the scroll cues work with it
    canvas:setScroll(40)
    ScrollUtil = nil
end)

test(
    "switching low-level quests sets the game's own low-level tracking on the minimap, once, as it is switched",
    function()
        local ns = createAddon()
        local set = {}
        local tracking = {
            { name = "Find Minerals", active = true, filter = 1 },
            { name = "Low-Level Quests", active = false, filter = 7 },
        }
        Enum = Enum or {}
        local savedFilters = Enum.MinimapTrackingFilter
        Enum.MinimapTrackingFilter = { TrivialQuests = 7 }
        C_Minimap = {
            GetNumTrackingTypes = function()
                return #tracking
            end,
            GetTrackingInfo = function(index)
                return { name = tracking[index].name, active = tracking[index].active }
            end,
            GetTrackingFilter = function(index)
                return { filterID = tracking[index].filter }
            end,
            SetTracking = function(index, isOn)
                set[#set + 1] = index .. "=" .. tostring(isOn)
                tracking[index].active = isOn
            end,
        }
        local option
        for _, section in ipairs(ns.SettingsPage.SECTIONS) do
            for _, each in ipairs(ns.SettingsPage.getOptions(section)) do
                if each.key == "shouldShowLowLevel" then
                    option = each
                end
            end
        end
        ns.settings.shouldShowLowLevel = false
        ns.SettingsPage.toggle(option)
        expectEqual(table.concat(set, " "), "2=true", "switched on: the game's tracking of them too")
        ns.SettingsPage.toggle(option)
        expectEqual(table.concat(set, " "), "2=true 2=false", "and off again")
        ns.SettingsPage.apply()
        expectEqual(#set, 2, "nothing else sets it: a choice in the game's menu stands")
        C_Minimap, Enum.MinimapTrackingFilter = nil, savedFilters
    end
)

test("every switch on the settings page is a real setting with a default", function()
    local ns = createAddon()
    local source = readFile("Core/Settings.lua")
    local count = 0
    for key in source:gmatch('key = "([%w_]+)"') do
        count = count + 1
        expectEqual(type(ns.settings[key]), "boolean", "setting " .. key)
        -- Each one is read somewhere outside the settings page and the defaults, or it would switch nothing
        local isUsed = false
        for _, file in ipairs(FILES) do
            if
                file ~= "Core/Settings.lua"
                and file ~= "Core/Core.lua"
                and readFile(file):find("settings." .. key, 1, true)
            then
                isUsed = true
            end
        end
        expectEqual(isUsed, true, "something acts on " .. key)
    end
    -- Switches that set several settings together, such as this addon's tracker in place of the game's
    for keys in source:gmatch("keys = (%b{})") do
        for key in keys:gmatch('"([%w_]+)"') do
            count = count + 1
            expectEqual(type(ns.settings[key]), "boolean", "setting " .. key)
        end
    end
    expectEqual(count, 45, "settings switched on the page")
    -- Settings with several values: each one's values are what the code acts on (the options as the page has them:
    -- some are made by a helper, a colour for each kind of quest)
    for _, section in ipairs(ns.SettingsPage.SECTIONS) do
        for _, option in ipairs(ns.SettingsPage.getOptions(section)) do
            local key = option.choiceKey
            if key then
                expectEqual(type(ns.settings[key]), "string", "setting " .. key)
            end
            for _, choice in ipairs(key and option.choices or {}) do
                local value = choice.value
                local isUsed = value == ns.settings[key] or choice.choose ~= nil
                for _, file in ipairs(FILES) do
                    if
                        file ~= "Core/Settings.lua"
                        and file ~= "Core/Core.lua"
                        and readFile(file):find('"' .. value .. '"', 1, true)
                    then
                        isUsed = true
                    end
                end
                expectEqual(isUsed, true, "something acts on " .. key .. " = " .. value)
            end
        end
    end
end)

test("the game's own areas are the map marks switched off, and a part switched off greys out its settings", function()
    local ns = createAddon()
    local function findOption(sectionTitle, name)
        for _, section in ipairs(ns.SettingsPage.SECTIONS) do
            for _, option in ipairs(section.title == sectionTitle and ns.SettingsPage.getOptions(section) or {}) do
                if option.key == name or option.choiceKey == name or option.stepKey == name then
                    return option, section
                end
            end
        end
    end
    local look, mapSection = findOption("Map and minimap", "areaStyle")
    local gameTile
    for _, choice in ipairs(look.choices) do
        gameTile = choice.value == "game" and choice or gameTile
    end
    expectEqual(gameTile.isChosen(), false, "with this addon's marks on, the game's tile is not the one chosen")
    expectEqual(ns.SettingsPage.getSwitchedOffPart(mapSection), nil, "and the section has nothing switched off to say")
    -- Picking the game's own: the map marks go off, and the look of ours picked before is kept for later
    ns.settings.areaStyle = "none"
    gameTile.choose()
    expectEqual(
        ns.settings.shouldShowMapPins == false and ns.settings.shouldHideBuiltInMapPins == false,
        true,
        "the game's tile switches the map marks off"
    )
    expectEqual(ns.settings.areaStyle, "none", "the look of ours stays as it was")
    expectEqual(gameTile.isChosen(), true, "and the tile shows it: it mirrors the switch")
    expectEqual(ns.SettingsPage.getSwitchedOffPart(mapSection).name, "Map marks", "the section says which part is off")
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "mapMarkScale")),
        false,
        "the marks' size is greyed out"
    )
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "shouldShowMinimapPins")),
        false,
        "so are the minimap's marks"
    )
    expectEqual(ns.SettingsPage.isAvailable(look), true, "the look can still be picked: that is the way back")
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "shouldWaypointFocused")),
        true,
        "the waypoint needs no marks"
    )
    -- Picking a look of ours switches the marks back on
    look.handleChoose("filled")
    expectEqual(
        ns.settings.shouldShowMapPins == true and ns.settings.shouldHideBuiltInMapPins == true,
        true,
        "a look of ours switches the marks on"
    )
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "mapMarkScale")),
        true,
        "and their settings are back"
    )
    -- The other parts the same: the tracker's settings with the tracker, the lists' with the Available tab
    ns.settings.isShown = false
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Tracker", "trackerOrder")),
        false,
        "the tracker off: its order greyed out"
    )
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Tracker", "shouldHideDoneObjectives")),
        true,
        "what the quest page shares stays, with the quest log on"
    )
    ns.settings.shouldUseAvailableQuests = false
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Quests to pick up", "shouldShowPvp")),
        false,
        "quests to pick up off: their kinds greyed out"
    )
    -- The game's own "Quest Objectives" map filter (questPOI) follows the switch: on with the game's markers, off with ours
    local savedGet, savedSet = GetCVar, SetCVar
    local cvars = { questPOI = "0" }
    GetCVar = function(name)
        return cvars[name]
    end
    SetCVar = function(name, value)
        cvars[name] = tostring(value)
    end
    ns.settings.shouldHideBuiltInTracker = true
    gameTile.choose()
    ns.SettingsPage.apply()
    expectEqual(
        cvars.questPOI,
        "1",
        "the game's markers switched on: the game's own filter goes on, or the map shows nothing"
    )
    look.handleChoose("filled")
    ns.SettingsPage.apply()
    expectEqual(cvars.questPOI, "0", "ours switched on: the game's filter goes off")
    cvars.questPOI = "1"
    ns.SettingsPage.apply()
    expectEqual(cvars.questPOI, "1", "set by the player afterwards, it is left alone while nothing is switched")
    GetCVar, SetCVar = savedGet, savedSet
    -- A saved "game" look from before is the map marks off now
    local loaded = ns.loadSettings({ areaStyle = "game", shouldShowMapPins = true, shouldHideBuiltInMapPins = true })
    expectEqual(
        loaded.areaStyle ~= "game" and loaded.shouldShowMapPins == false and loaded.shouldHideBuiltInMapPins == false,
        true,
        "the look saved as the game's areas becomes the map marks switched off"
    )
    -- The looks from before the areas and the spawn markers were two choices: each is what it was, said in the two
    for old, now in pairs({
        icons = { "filled", "glyph" },
        spawns = { "none", "glyph" },
        shapes = { "filled", "none" },
        dots = { "none", "square" },
    }) do
        loaded = ns.loadSettings({ areaStyle = old })
        expectEqual(loaded.areaStyle .. " " .. loaded.spawnMarker, now[1] .. " " .. now[2], "the old look " .. old)
    end
    loaded = ns.loadSettings({ areaStyle = "none", spawnMarker = "plate" })
    expectEqual(loaded.areaStyle .. " " .. loaded.spawnMarker, "none plate", "what is saved in the two choices stays")
    -- The bold look there was ("Shapes") is the one look now, as strong as it was: said by the two strengths
    loaded = ns.loadSettings({ areaStyle = "blob", spawnMarker = "plate", areaOutlineStrength = 1 })
    expectEqual(
        loaded.areaStyle .. " " .. loaded.spawnMarker,
        "filled plate",
        "the bold look saved becomes the one look"
    )
    expectEqual(
        loaded.areaFillStrength .. " " .. loaded.areaOutlineStrength,
        "2 1.6",
        "its fill and outline as strong as the bold look's were"
    )
    -- The spawn markers' own settings follow the marker chosen
    ns.loadSettings({})
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "shouldGlowSpawnMarkers")),
        true,
        "a glyph has a glow to switch"
    )
    ns.settings.spawnMarker = "square"
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "shouldGlowSpawnMarkers")),
        false,
        "a square has none"
    )
    ns.settings.spawnMarker = "none"
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "spawnMarkerScale")),
        false,
        "no markers: no size to set"
    )
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "otherSpawnMarkers")),
        false,
        "nor the other quests' to choose"
    )
    ns.settings.areaStyle = "none"
    expectEqual(
        ns.SettingsPage.isAvailable(findOption("Map and minimap", "shouldShowFocusedAreasOnly")),
        false,
        "no areas: none to keep to the quest in focus"
    )
end)

test("switching the quest panels off hands the map back, and on again takes it over", function()
    local ns = createAddon()
    local calls = {}
    SetUIPanelAttribute = function(_, name, value)
        calls[#calls + 1] = name .. "=" .. tostring(value)
    end
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.apply()
    expectEqual(ns.Log.isOpen(), true, "panels shown with the setting on")
    ns.settings.shouldReplaceQuestLog = false
    ns.MapDock.apply()
    expectEqual(ns.Log.isOpen(), false, "panels gone with the setting off")
    expectEqual(calls[#calls], "extraWidth=0", "the width reserved beside the map is given back")
    ns.settings.shouldReplaceQuestLog = true
    ns.MapDock.apply()
    expectEqual(ns.Log.isOpen(), true, "panels back with the setting on again")
end)

test("the settings page and the scrolling tracker build without errors", function()
    local ns, state = createAddon()
    Settings = {
        RegisterCanvasLayoutCategory = function()
            return {
                GetID = function()
                    return 1
                end,
            }
        end,
        RegisterAddOnCategory = function() end,
        OpenToCategory = function() end,
    }
    for questId = 201, 201 do
        setQuest(state, questId, false, { killObjective(5, 12) })
    end
    ns.Tracker.create()
    ns.Log.create()
    ns.SettingsPage.create()
    expectEqual(ns.SettingsPage.open(), true, "the page opens")
    ns.settings.isLocked = true
    ns.resetSettings()
    expectEqual(ns.settings.isLocked, false, "reset puts a switch back")
    Settings = nil
end)

test("the settings open on the quest page, in every border, and opening a quest leaves them", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    expectEqual(ns.SettingsPage.open(), true, "they open")
    expectEqual(ns.Log.isShowingSettings(), true, "on the page beside the list")
    for _, style in ipairs(ns.WindowBorder.STYLES) do
        ns.settings.windowBorder = style
        ns.SettingsPage.apply()
        ns.Log.refresh()
    end
    -- Every page draws: the overview, the previews, the pictures of each choice in every look, and About
    for sectionIndex in ipairs(ns.SettingsPage.SECTIONS) do
        for _, look in ipairs({
            { "filled", "glyph" },
            { "filled", "plate" },
            { "none", "game" },
            { "filled", "square" },
            { "filled", "none" },
        }) do
            ns.settings.areaStyle, ns.settings.spawnMarker = look[1], look[2]
            ns.Log.openSettings(sectionIndex)
        end
    end
    for index, setup in ipairs(ns.SettingsPage.QUICK_SETUPS) do
        if index < 3 then -- the third hands everything back to the game, closing the panels
            setup.apply()
            expectEqual(
                ns.SettingsPage.getQuickSetupIndex(),
                index,
                "quick setup " .. setup.title .. " is the one shown as current"
            )
        end
    end
    for _, section in ipairs(ns.SettingsPage.SECTIONS) do
        for _, option in ipairs(ns.SettingsPage.getOptions(section)) do
            local key = option.key or option.choiceKey or option.stepKey
            if key then
                ns.settings[key] = nil
                ns.resetSettings()
                expectEqual(ns.settings[key] ~= nil, true, "a default for " .. key)
            end
        end
    end
    ns.Log.selectQuest(201)
    expectEqual(ns.Log.isShowingSettings(), false, "a quest chosen on the map takes the page back")
    ns.settings.shouldReplaceQuestLog = false
    expectEqual(ns.Log.openSettings(), false, "with the panels off there is nowhere to show them")
end)

test("a zone listed for the first time is open only with a tracked quest, then keeps its state", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) }) -- tracked
    state.questLog[606] = { isComplete = false, objectives = { itemObjective(0, 4) } } -- in the log, not tracked
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.refresh()
    local collapsedZones = ns.settings.collapsedLogZones
    expectEqual(collapsedZones[TIRISFAL], false, "the zone with the tracked quest is open")
    expectEqual(collapsedZones[-304], true, "the one without is shut")
    state.watchedQuestIds[#state.watchedQuestIds + 1] = 606
    ns.Log.refresh()
    expectEqual(collapsedZones[-304], true, "tracking a quest later does not open a zone already seen")
end)

test("a quest done in several zones lists them all, and a click turns the map to the next", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    local entry = ns.Model.compose().groups[1].entries[1]
    expectEqual(entry.zoneIds ~= nil and #entry.zoneIds, 2, "both zones, the one it lists under first")
    expectEqual(entry.zoneIds[1], entry.zoneId, "the listed zone first")
    local shownZoneIds = {}
    ns.MapDock.showQuestPlace = function(zoneId)
        shownZoneIds[#shownZoneIds + 1] = zoneId
    end
    ns.MapDock.getShownZoneId = function()
        return entry.zoneIds[1]
    end
    ns.MapDock.showNextQuestZone(entry)
    expectEqual(shownZoneIds[1], entry.zoneIds[2], "from the first zone to the second")
    ns.MapDock.getShownZoneId = function()
        return entry.zoneIds[2]
    end
    ns.MapDock.showNextQuestZone(entry)
    expectEqual(shownZoneIds[2], entry.zoneIds[1], "and from the last back to the first")
    -- Chosen again later, the quest's map goes back to the zone last cycled to
    ns.MapDock.showQuestPlace = function(zoneId)
        shownZoneIds[#shownZoneIds + 1] = zoneId
    end
    ns.MapDock.showQuest(entry)
    expectEqual(shownZoneIds[#shownZoneIds], entry.zoneIds[1], "the zone last cycled to")
    ns.MapDock.getShownZoneId = function()
        return entry.zoneIds[1]
    end
    ns.MapDock.showNextQuestZone(entry)
    ns.MapDock.showQuest(entry)
    expectEqual(shownZoneIds[#shownZoneIds], entry.zoneIds[2], "and after another click, that one")
    local lineCount = 0
    local tooltip = {
        AddLine = function()
            lineCount = lineCount + 1
        end,
        AddDoubleLine = function()
            lineCount = lineCount + 1
        end,
    }
    ns.MapDock.addZonesToTooltip(tooltip, entry)
    expectEqual(lineCount, #entry.zoneIds + 2, "a heading, every zone, and the hint")
    expectEqual(
        ns.Widgets.formatMoreZones("Also in A, B and 7 more", "ffd100"),
        "Also in A, B and |cffffd1007 more|r",
        "the count coloured"
    )
end)

test("everything goes back to the game's own in one switch, and each part comes back on its own", function()
    local ns = createAddon()
    ns.SettingsPage.useGameOwn()
    for _, option in ipairs(ns.SettingsPage.REPLACEMENTS) do
        expectEqual(ns.SettingsPage.isOn(option), false, option.label .. " is off")
    end
    expectEqual(ns.settings.shouldHideBuiltInTracker, false, "the game's tracker is back")
    expectEqual(ns.settings.shouldHideBuiltInMapPins, false, "the game's quest markers are back")
    ns.SettingsPage.toggle(ns.SettingsPage.REPLACEMENTS[2])
    expectEqual(
        ns.settings.isShown and ns.settings.shouldHideBuiltInTracker,
        true,
        "this addon's tracker in place of the game's again"
    )
    expectEqual(ns.settings.shouldReplaceQuestLog, false, "the rest stays the game's")
end)

test("with the quests to pick up switched off, the tab goes and the game's own marks are left alone", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Availability.prepare()
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "giver") > 0, true, "givers marked while it is on")
    ns.SettingsPage.toggle(ns.SettingsPage.REPLACEMENTS[4])
    expectEqual(ns.Availability.isShownOnMap(), false, "off")
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "giver"), 0, "no giver marks of this addon")
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.showAvailable()
    expectEqual(ns.Log.isShowingAvailable(), false, "the panels open on the quests in the log instead")
end)

test(
    "the tracker's Open in the quest log opens the quest's page and turns the map to it, as a click in the list",
    function()
        local ns, state = createAddon()
        setQuest(state, 201, false, { killObjective(5, 12) })
        setQuest(state, 301, false, { killObjective(2, 12) })
        ns.Tracker.create()
        ns.Log.create()
        ns.MapDock.create()
        -- The game's menu: the tracker's entries, kept to be clicked
        local buttons = {}
        local root = {
            CreateTitle = function() end,
            CreateDivider = function() end,
            CreateButton = function(_, text, handler)
                local button = { handler = handler, SetEnabled = function() end }
                buttons[text] = button
                return button
            end,
        }
        local savedMenu = MenuUtil
        MenuUtil = {
            CreateContextMenu = function(owner, generator)
                generator(owner, root)
            end,
        }
        local shownQuestId
        local savedShowQuest = ns.MapDock.showQuest
        ns.MapDock.showQuest = function(entry)
            shownQuestId = entry.questId
        end
        local entry
        for _, group in ipairs(ns.Model.compose(nil).groups) do
            for _, candidate in ipairs(group.entries) do
                entry = candidate.questId == 301 and candidate or entry
            end
        end
        ns.Tracker.openQuestMenu(entry, UIParent)
        buttons[ns.L("Open in the quest log")].handler()
        expectEqual(ns.Log.getSelectedQuestId(), 301, "its page is open in the quest log")
        expectEqual(shownQuestId, 301, "and the map turned and panned to it")
        MenuUtil, ns.MapDock.showQuest = savedMenu, savedShowQuest
    end
)

test(
    "a zone's Track all and Untrack all track and untrack its quests, each offered only when it changes something",
    function()
        local ns, state = createAddon()
        setQuest(state, 201, false, { killObjective(5, 12) })
        setQuest(state, 301, false, { killObjective(2, 12) })
        ns.Tracker.create()
        ns.Log.create()
        local buttons
        local root = {
            CreateButton = function(_, text, handler)
                buttons[text] = handler
                return {}
            end,
        }
        local function openMenu(questIds)
            buttons = {}
            ns.Log.addTrackMenuItems(root, questIds)
        end
        state.watchedQuestIds = {}
        openMenu({ 201, 301 })
        expectEqual(buttons[ns.L("Untrack all")], nil, "nothing tracked: no Untrack all")
        buttons[ns.L("Track all")]()
        expectEqual(ns.QuestState.countWatched({ 201, 301 }), 2, "both tracked")
        openMenu({ 201, 301 })
        expectEqual(buttons[ns.L("Track all")], nil, "all tracked: no Track all")
        buttons[ns.L("Untrack all")]()
        expectEqual(ns.QuestState.countWatched({ 201, 301 }), 0, "both untracked, still in the log")
        expectEqual(ns.QuestState.getLogSize(), 2, "the log keeps them")
    end
)

test("opening the quest log opens the focused quest's group to bring it into view", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) }) -- its next step is in Silverpine
    ns.Tracker.create()
    ns.Tracker.refresh()
    ns.Focus.set(301)
    ns.settings.collapsedLogZones[SILVERPINE] = true -- folded by hand earlier
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    expectEqual(ns.settings.collapsedLogZones[SILVERPINE], false, "its group is opened on the way in")
end)

test(
    "a dungeon's quest given elsewhere: on the Dungeons tab under the dungeon, picking it turns the map to its giver",
    function()
        local ns = createAddon()
        addDungeon()
        ns.Availability.prepare()
        ns.Log.create()
        ns.MapDock.create()
        ns.MapDock.apply()
        ns.Log.toggle()
        ns.Log.showZone(209) -- Shadowfang Keep, as its gate on the map opens it
        expectEqual(ns.Log.getShownDungeonId(), 209, "the Dungeons tab opens on the keep")
        local canvas = ns.Log.getListCanvas()
        local leadInButton
        for index = 1, canvas.pools.buttons.usedCount or 0 do
            local button = canvas.pools.buttons[index]
            if button.data == 520 then
                leadInButton = button
            end
        end
        expectEqual(leadInButton ~= nil, true, "the lead-in has its row under the keep")
        leadInButton.handleClick(leadInButton.data)
        expectEqual(ns.MapDock.getShownZoneId(), TIRISFAL, "the map shows its giver, in Tirisfal")
        expectEqual(ns.Log.getShownDungeonId(), 209, "the tab stays on the keep")
        expectEqual(ns.Log.getSelectedDungeonQuestId(), 520, "with the lead-in's page open")
    end
)

test(
    "a quest clicked on the map: a dungeon's opens on the Dungeons tab; a lead-in given in a zone opens in that zone's list",
    function()
        local ns = createAddon()
        addDungeon()
        ns.Availability.prepare()
        ns.Log.create()
        ns.MapDock.create()
        ns.MapDock.apply()
        ns.Log.toggle()
        ns.Log.showZone(SILVERPINE)
        ns.Log.showAvailable(506) -- the keep's quest, picked up inside, clicked on the Silverpine map
        expectEqual(ns.Log.getShownDungeonId(), 209, "the Dungeons tab opens on the keep")
        expectEqual(ns.Log.getSelectedDungeonQuestId(), 506, "with the quest open")
        ns.Log.showAvailable(520) -- a lead-in to the keep, picked up in Tirisfal
        expectEqual(ns.Log.getAvailableZoneId(), TIRISFAL, "listed where it is picked up")
        expectEqual(ns.Log.getSelectedAvailableQuestId(), 520, "and opened there")
        local isLeadNamed = false
        for _, quest in ipairs((ns.Availability.getQuests(TIRISFAL, { shouldShowLowLevel = true }))) do
            isLeadNamed = isLeadNamed or (quest.questId == 520 and quest.leadsToDungeonName == "Shadowfang Keep")
        end
        expectEqual(isLeadNamed, true, "it says it leads to the keep")
    end
)

test("a quest's page names its level range: from the level that can take it to its own", function()
    local ns = createAddon()
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if field == "requiredLevel" then
                return ({ [701] = 25, [702] = 33, [703] = 0 })[id] or original(id, field)
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    expectEqual(ns.Log.formatLevelRange(701, 33), "Levels 25\226\128\14733", "a range")
    expectEqual(ns.Log.formatLevelRange(701, 33, true), "Levels 25\226\128\14733+", "a group quest")
    expectEqual(ns.Log.formatLevelRange(702, 33), "Level 33", "taken only at its own level")
    expectEqual(ns.Log.formatLevelRange(703, 33), "Level 33", "nothing lower known")
end)

test("a region that remembers passes on to the game only what differs from what it has", function()
    local ns = createAddon()
    -- A region as the game's are: a table whose methods come from its kind's own table; each call is noted
    local calls, methods = {}, {}
    for _, name in ipairs({
        "Show",
        "Hide",
        "SetShown",
        "SetPoint",
        "ClearAllPoints",
        "SetAllPoints",
        "SetSize",
        "SetWidth",
        "SetHeight",
        "SetAlpha",
        "SetText",
        "SetTextColor",
        "SetFontObject",
        "SetFont",
        "SetTexture",
        "SetAtlas",
        "SetColorTexture",
        "SetTexCoord",
        "SetVertexColor",
        "SetDesaturated",
        "SetWordWrap",
        "SetJustifyH",
        "SetDrawLayer",
    }) do
        methods[name] = function()
            calls[#calls + 1] = name
        end
    end
    methods.GetStringHeight = function()
        calls[#calls + 1] = "GetStringHeight"
        return 14
    end
    methods.GetStringWidth = function()
        calls[#calls + 1] = "GetStringWidth"
        return 50
    end
    methods.IsShown = function()
        return true
    end
    local function create()
        return ns.Widgets.remember(setmetatable({}, { __index = methods }))
    end
    local function count(name)
        local total = 0
        for _, call in ipairs(calls) do
            if call == name then
                total = total + 1
            end
        end
        return total
    end
    local parent = {}

    local text = create()
    text:SetText("Wolves 3/8")
    text:SetText("Wolves 3/8")
    expectEqual(count("SetText"), 1, "the same words again are not set again")
    text:SetText("Wolves 4/8")
    expectEqual(count("SetText"), 2, "other words are")
    ns.Widgets.place(text, "TOPLEFT", parent, "TOPLEFT", 10, -20)
    ns.Widgets.place(text, "TOPLEFT", parent, "TOPLEFT", 10, -20)
    expectEqual(count("ClearAllPoints") .. " " .. count("SetPoint"), "1 1", "put where it already is: nothing asked")
    ns.Widgets.place(text, "TOPLEFT", parent, "TOPLEFT", 10, -34)
    expectEqual(count("ClearAllPoints") .. " " .. count("SetPoint"), "1 2", "moved on the same point: set, not cleared")
    ns.Widgets.place(text, "CENTER", parent, "TOPLEFT", 10, -34)
    expectEqual(count("ClearAllPoints") .. " " .. count("SetPoint"), "2 3", "another point: cleared and set")
    -- Its size: asked of the game once in a frame, once more in a later frame, and kept once the two agree
    local frame = 1
    GetTime = function()
        return frame
    end
    expectEqual(text:GetStringHeight(), 14, "its size, as the game measures it")
    text:GetStringHeight()
    expectEqual(count("GetStringHeight"), 1, "asked once in a frame")
    frame = 2
    text:GetStringHeight()
    expectEqual(
        count("GetStringHeight"),
        2,
        "and once more in a later frame: the first answer may come before its font is ready"
    )
    frame = 3
    text:GetStringHeight()
    frame = 4
    text:GetStringHeight()
    expectEqual(count("GetStringHeight"), 2, "the same twice: kept from here on, while nothing it comes from changes")
    text:SetText("Wolves 5/8")
    text:GetStringHeight()
    expectEqual(count("GetStringHeight"), 3, "other words: measured again")
    text:SetWidth(120)
    text:SetWidth(120)
    text:GetStringHeight()
    expectEqual(count("SetWidth") .. " " .. count("GetStringHeight"), "1 4", "another width: measured again")
    ns.Widgets.forgetMeasures()
    text:GetStringHeight()
    expectEqual(count("GetStringHeight"), 5, "the fonts or the scale changed: every text is measured again")
    text:SetTextColor(1, 1, 1)
    text:SetTextColor(1, 1, 1)
    expectEqual(count("SetTextColor"), 1, "the same colour again is not set again")
    text:SetFontObject({})
    text:SetTextColor(1, 1, 1)
    text:GetStringHeight()
    expectEqual(
        count("SetTextColor") .. " " .. count("GetStringHeight"),
        "2 6",
        "a font given may bring its own colour and size: both asked again"
    )
    text:SetPoint("RIGHT", parent, "RIGHT", 0, 0)
    text:GetStringHeight()
    text:GetStringHeight()
    expectEqual(
        count("GetStringHeight"),
        8,
        "held by a point of its own setting, its width is the points' to say: measured each time"
    )
    GetTime = nil

    calls = {}
    local texture = create()
    for _ = 1, 2 do
        texture:SetTexture("first")
        texture:SetVertexColor(1, 0, 0, 1)
        texture:SetDesaturated(true)
        texture:SetSize(12, 12)
        texture:SetAlpha(0.5)
    end
    expectEqual(#calls, 5, "the same picture, tint, greying, size and alpha again: nothing asked")
    texture:SetTexture("second")
    texture:SetVertexColor(1, 0, 0, 1)
    texture:SetDesaturated(true)
    expectEqual(
        count("SetTexture") .. count("SetVertexColor") .. count("SetDesaturated"),
        "222",
        "another picture: its tint and greying are given again with it"
    )
    ns.Widgets.setAtlas(texture, "QuestNormal")
    local atlasCalls = count("SetAtlas")
    ns.Widgets.setAtlas(texture, "QuestNormal")
    expectEqual(count("SetAtlas"), atlasCalls, "the atlas it shows is not set again")
    texture:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    ns.Widgets.setAtlas(texture, "QuestNormal")
    expectEqual(count("SetAtlas"), atlasCalls + 1, "shown cropped since: the atlas is set again")

    calls = {}
    texture:Show()
    texture:Show()
    expectEqual(count("Show"), 1, "shown once")
    ns.Widgets.hideLater(texture)
    expectEqual(texture:IsShown(), false, "a part whose hiding waits reads as hidden")
    texture:Show()
    ns.Widgets.hideWaiting(texture)
    expectEqual(
        count("Hide") .. " " .. count("Show"),
        "0 1",
        "hidden and shown again while dressed anew: nothing asked"
    )
    ns.Widgets.hideLater(texture)
    ns.Widgets.hideWaiting(texture)
    expectEqual(count("Hide"), 1, "left out by the new look: hidden")

    -- A stand-in whose methods are no table (the other tests') is left as it is, and placed in full
    local plain = setmetatable({}, {
        __index = function(_, key)
            return function()
                calls[#calls + 1] = key
            end
        end,
    })
    expectEqual(ns.Widgets.remember(plain), plain, "given back unchanged")
    calls = {}
    ns.Widgets.place(plain, "CENTER", parent, "CENTER", 0, 0)
    ns.Widgets.place(plain, "CENTER", parent, "CENTER", 0, 0)
    expectEqual(count("SetPoint"), 2, "and set every time")
end)

test("a quest chosen on the map or in the tracker is shown though a search or filter left over hid it", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(0, 5) })
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.LogState.searchText = "no quest is called this"
    ns.Log.refresh()
    ns.Log.selectQuest(301)
    expectEqual(ns.Log.getSelectedQuestId(), 301, "the quest stays selected")
    expectEqual(ns.LogState.searchText, "", "the search gave way to it")
    ns.Log.refresh()
    expectEqual(ns.Log.getSelectedQuestId(), 301, "and stays so on the next drawing")
    ns.LogState.logFilter = "ready" -- neither is ready to hand in
    ns.Log.refresh()
    ns.Log.selectQuest(201)
    expectEqual(ns.Log.getSelectedQuestId(), 201, "a filter gives way too")
    expectEqual(ns.LogState.logFilter, "all", "back to every quest")
    ns.LogState.searchText = "zzz"
    ns.Log.refresh()
    expectEqual(ns.Log.getSelectedQuestId(), nil, "a search typed afterwards still lets go of a quest it hides")
end)

test(
    "quest details on a page of their own: one pane, a click opens the page in the list's place, Back the list",
    function()
        local ns, state = createAddon()
        setQuest(state, 201, false, { killObjective(5, 12) })
        setQuest(state, 301, false, { killObjective(2, 12) })
        ns.Tracker.create()
        ns.Log.create()
        ns.MapDock.create()
        ns.MapDock.apply()
        ns.Log.toggle()
        local twoPanes = ns.Log.getPanelWidth()
        ns.settings.questDetails = "own"
        ns.Log.refresh()
        expectEqual(ns.Log.isNarrow(), true, "the window is one pane")
        expectEqual(ns.Log.getPanelWidth() < twoPanes * 0.6, true, "about half as wide")
        expectEqual(ns.Log.isPageSpread(), false, "it shows the list, though the focused quest is selected")
        local frame = ns.Log.getWindow()
        local function findRow(questId)
            local canvas = ns.Log.getListCanvas()
            for index = 1, canvas.pools.buttons.usedCount or 0 do
                local button = canvas.pools.buttons[index]
                if button.isQuestRow == true and button.data == questId then -- (the fake game answers any field)
                    return button
                end
            end
        end
        local row = findRow(301)
        expectEqual(row ~= nil, true, "the quest has its row")
        row.handleClick(row.data)
        expectEqual(ns.Log.getSelectedQuestId(), 301, "a click opens the quest")
        expectEqual(ns.Log.isPageSpread(), true, "its page in the list's place")
        frame.backStrip:GetScript("OnClick")(frame.backStrip, "LeftButton")
        expectEqual(ns.Log.isPageSpread(), false, "Back shows the list again")
        expectEqual(ns.Log.getSelectedQuestId(), 301, "the quest still the highlighted one")
        row = findRow(301)
        row.handleClick(row.data)
        expectEqual(
            ns.Log.isPageSpread() and ns.Log.getSelectedQuestId() == 301,
            true,
            "a click on it again opens it, not closes it"
        )
        frame.backStrip:GetScript("OnClick")(frame.backStrip, "LeftButton")

        ns.Log.handleActiveQuestChanged(201)
        expectEqual(ns.Log.isPageSpread(), false, "the focus moving selects its quest in the list, no page opened")
        ns.Log.selectQuest(301)
        expectEqual(ns.Log.isPageSpread(), true, "a quest opened from the map or the tracker opens on its page")
        ns.LogState.selectedQuestIds[ns.LogStyle.TAB_QUESTS] = nil -- (its quest abandoned)
        ns.Log.refresh()
        expectEqual(ns.Log.isPageSpread(), false, "with nothing open, the list again")

        ns.settings.questDetails = "beside"
        ns.Log.refresh()
        expectEqual(ns.Log.getPanelWidth(), twoPanes, "beside the list: both panes again")
        expectEqual(ns.Log.isNarrow() or ns.Log.isPageSpread(), false, "with no page in the list's place")
        -- (what shows, the way back and the bar under the page, is checked in the simulator: the fake game shows all)
    end
)

test("every quest's Wowhead link: Classic's page, in the game's language where Wowhead has a site in it", function()
    local ns = createAddon()
    expectEqual(ns.WowheadLink.getUrl(518), "https://www.wowhead.com/classic/quest=518", "English without a language")
    local gameLocale = GetLocale
    for locale, url in pairs({
        enUS = "https://www.wowhead.com/classic/quest=518",
        deDE = "https://www.wowhead.com/classic/de/quest=518",
        esMX = "https://www.wowhead.com/classic/mx/quest=518",
        zhTW = "https://www.wowhead.com/classic/tw/quest=518",
    }) do
        GetLocale = function()
            return locale
        end
        expectEqual(ns.WowheadLink.getUrl(518), url, locale)
    end
    GetLocale = gameLocale
end)
