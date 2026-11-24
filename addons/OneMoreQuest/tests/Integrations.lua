-- Tests: other addons: compatibility providers, QuestieDB, TomTom, Questie, Spoken.

test("the waypoint follows the focused quest through TomTom, and goes when it is switched off", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    local added, removed = {}, 0
    TomTom = {
        AddWaypoint = function(_, uiMapId, x, y, options)
            added[#added + 1] = options.title
            return "waypoint" .. #added
        end,
        RemoveWaypoint = function()
            removed = removed + 1
        end,
    }
    ns.settings.shouldWaypointFocused = true
    ns.Tracker.create()
    ns.Focus.set(201)
    ns.Tracker.refresh()
    expectEqual(#added, 1, "one waypoint, however often the tracker is drawn")
    expectEqual(added[1], ns.Model.compose().groups[1].entries[1].title, "named after the quest")
    ns.settings.shouldWaypointFocused = false
    ns.Tracker.refresh()
    expectEqual(removed, 1, "switched off, its waypoint is taken away")
    TomTom = nil
end)

test("with Questie running, the player is asked once whether to turn it off", function()
    local ns = createAddon()
    local shown, disabled, reloaded
    C_AddOns = {
        IsAddOnLoaded = function(name)
            return name == "Questie"
        end,
        DisableAddOn = function(name)
            disabled = name
        end,
    }
    StaticPopupDialogs, StaticPopup_Show = {}, function(name)
        shown = name
    end
    ReloadUI = function()
        reloaded = true
    end
    ns.Compatibility.getProvider("Questie").ask()
    expectEqual(shown ~= nil, true, "asked")
    StaticPopupDialogs[shown].OnAccept()
    expectEqual(disabled, "Questie", "Questie, not QuestieDB, is turned off")
    expectEqual(reloaded, true, "and the game reloads so it takes effect")
    expectEqual(ns.Compatibility.getProvider("Questie").shouldAsk(), false, "not asked again")
    C_AddOns, StaticPopupDialogs, StaticPopup_Show, ReloadUI = nil, nil, nil, nil
end)

test("Spoken's place story and its tab stand beside the docked window, not over it", function()
    local ns = createAddon()
    local function makeFrame(right, width)
        local frame = { points = {}, right = right, width = width or 100, isShown = true }
        function frame:ClearAllPoints()
            self.points = {}
        end
        function frame:SetPoint(point, relative)
            self.points[#self.points + 1] = { point, relative }
        end
        function frame:GetRight()
            return self.right
        end
        function frame:GetWidth()
            return self.width
        end
        function frame:GetEffectiveScale()
            return 1
        end
        function frame:IsShown()
            return self.isShown
        end
        function frame:Show()
            self.isShown = true
        end
        function frame:Hide()
            self.isShown = false
        end
        function frame:SetShown(isShown)
            self.isShown = isShown == true
        end
        return frame
    end
    local saved = { _G.TrailheadLog, _G.WorldMapFrame, _G.UIParent, hooksecurefunc, _G.SpokenPlaces }
    local window, map, screen = makeFrame(1500), makeFrame(1000), makeFrame(2000)
    local panel, tab = makeFrame(nil, 380), makeFrame(nil, 40)
    _G.TrailheadLog, _G.WorldMapFrame, _G.UIParent = window, map, screen
    _G.SpokenPlacesPanel, _G.SpokenPlacesPanelToggle = panel, tab
    tab.isShown = false
    -- Spoken's own folding, as its tab and close button call it: the story shows unless folded
    local places = { isCollapsed = false }
    function places:RefreshPanel()
        panel:SetShown(not self.isCollapsed)
        tab:SetShown(self.isCollapsed)
    end
    function places:SetMapPanelCollapsed(isCollapsed)
        self.isCollapsed = isCollapsed
        self:RefreshPanel()
    end
    _G.SpokenPlaces = places
    hooksecurefunc = function(target, method, after)
        local original = target[method]
        target[method] = function(...)
            original(...)
            after(...)
        end
    end
    ns.Compatibility.getProvider("Spoken_Places").onDockChanged(true)
    expectEqual(tab.points[1][2], window, "the tab down the window's edge")
    expectEqual(
        panel.points[1][1] .. tostring(panel.points[1][2] == window),
        "TOPLEFTtrue",
        "room on the right: the story beside the window"
    )
    -- Spoken places them on the map's edge again: moved on at once
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", map)
    expectEqual(panel.points[#panel.points][2], window, "placed again by Spoken, moved beside the window again")
    -- No room right of the window: the story waits on its tab, the map uncovered, Spoken's setting untouched
    screen.right = 1600
    ns.Compatibility.getProvider("Spoken_Places").onDockChanged(true)
    expectEqual(tostring(panel:IsShown()) .. " " .. tostring(tab:IsShown()), "false true", "no room: folded to its tab")
    expectEqual(places.isCollapsed, false, "Spoken's own folding choice is left as it was")
    places:RefreshPanel() -- Spoken shows it again as the map changes: folded again
    expectEqual(panel:IsShown(), false, "shown again by Spoken unasked: folded again")
    -- The player opens it with its tab: over the map's right side, never over the window
    places:SetMapPanelCollapsed(false)
    expectEqual(panel:IsShown(), true, "opened by the player: shown")
    expectEqual(
        panel.points[1][1] .. tostring(panel.points[1][2] == map),
        "TOPRIGHTtrue",
        "no room: over the map's right side"
    )
    places:RefreshPanel()
    expectEqual(panel:IsShown(), true, "and it stays open as the map changes")
    places:SetMapPanelCollapsed(true)
    expectEqual(tostring(panel:IsShown()) .. " " .. tostring(tab:IsShown()), "false true", "closed again: its tab")
    -- The window undocked: back on the map's edge
    ns.Compatibility.getProvider("Spoken_Places").onDockChanged(false)
    expectEqual(tab.points[1][2], map, "undocked: the tab on the map's edge again")
    _G.TrailheadLog, _G.WorldMapFrame, _G.UIParent, hooksecurefunc, _G.SpokenPlaces =
        saved[1], saved[2], saved[3], saved[4], saved[5]
    _G.SpokenPlacesPanel, _G.SpokenPlacesPanelToggle = nil, nil
end)

test("compatibility providers: each runs only while its addon is loaded, and one failing stops no other", function()
    local ns = createAddon()
    local calls = {}
    ns.Compatibility.register({
        name = "BrokenAddon",
        onDockChanged = function()
            error("broken")
        end,
    })
    ns.Compatibility.register({
        name = "LoadedAddon",
        onDockChanged = function(isDocked)
            calls.loaded = isDocked
        end,
    })
    ns.Compatibility.register({
        name = "MissingAddon",
        onDockChanged = function()
            calls.missing = true
        end,
    })
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "LoadedAddon" or name == "BrokenAddon"
    end
    local savedHandler, reported = geterrorhandler, nil
    geterrorhandler = function()
        return function(problem)
            reported = problem
        end
    end
    ns.Compatibility.notify("onDockChanged", true)
    expectEqual(calls.loaded, true, "the loaded addon's provider ran")
    expectEqual(calls.missing, nil, "the missing addon's did not")
    expectEqual(tostring(reported):find("broken", 1, true) ~= nil, true, "the failure went to the game's error handler")
    geterrorhandler, _G.C_AddOns.IsAddOnLoaded = savedHandler, nil
end)

test("the About page lists the addons OneMoreQuest works with now, and whether each is used", function()
    local ns = createAddon()
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "QuestieDB" or name == "Spoken_Places" or name == "WowfCZ"
    end
    _G.WowfCZ_QuestData, _G.WowfCZ_DB = {}, {}
    ns.settings.language = "en"
    ns.QuestText.start()
    local labels = {}
    for _, integration in ipairs(ns.Compatibility.getIntegrations()) do
        labels[#labels + 1] = integration.label
    end
    table.sort(labels)
    expectEqual(
        table.concat(labels, ", "),
        "QuestieDB, Spoken Places",
        "the loaded addons OneMoreQuest has a provider for, and no others"
    )
    local wowf = ns.QuestText.getIntegrations()[1]
    expectEqual(wowf.label, "WoWF.cz", "the translation addon loaded")
    expectEqual(wowf.isInUse, false, "not used in English")
    expectEqual(wowf.text:find("Čeština", 1, true) ~= nil, true, "it says when it is used: in Czech")
    ns.Locale.setLanguage("cs")
    expectEqual(ns.QuestText.getIntegrations()[1].isInUse, true, "in Czech: in use")
    _G.WowfCZ_DB.enabled = false
    expectEqual(
        ns.QuestText.getIntegrations()[1].text:find(ns.L("Switched off in its own settings."), 1, true) ~= nil,
        true,
        "switched off in WoWF.cz: said so"
    )
    -- The page draws in both languages
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    for index, section in ipairs(ns.SettingsPage.SECTIONS) do
        if section.kind == "about" then
            ns.Log.openSettings(index)
            ns.Log.refresh()
            ns.Locale.setLanguage("en")
            ns.Log.refresh()
        end
    end
    _G.WowfCZ_QuestData, _G.WowfCZ_DB, _G.C_AddOns.IsAddOnLoaded = nil, nil, nil
end)

test("QuestieDB's drop corrections apply on top of the Wowhead rates, up to the flavor's expansion", function()
    local ns = createAddon()
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            if name == "QuestieClassicItemDrops" then
                return { wowheadData = "return { [725] = { [98] = 40, [117] = 30 }, [4054] = { [5] = 100 } }" }
            elseif name == "QuestieItemDropCorrections" then
                return {
                    Era = { [725] = { [98] = -1, [117] = -2 }, [4054] = { [5] = 20 }, [9999] = { [7] = 50 } },
                    Tbc = { [4054] = { [5] = 60 } }, -- a later expansion's: not for Classic rules
                }
            elseif name == "DropDB" then
                return { correctionKeys = { WOWHEAD = -1, PSERVER = -2 } }
            elseif name == "Expansions" then
                return { Era = 1, Classic = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5, Current = 1 }
            end
            return original(name)
        end
    end)(LibQuestieDB.Support.Get)
    expectEqual(ns.Database.getItemDropChance(4054, 5), 0.2, "a rate checked by hand replaces Wowhead's")
    expectEqual(ns.Database.getItemDropChance(725, 98), 0.4, "marked as Wowhead's: Wowhead's rate stays")
    expectEqual(
        ns.Database.getItemDropChance(725, 117),
        0.3,
        "marked as the server's: Wowhead's rate stays (no server table here)"
    )
    expectEqual(ns.Database.getItemDropChance(9999, 7), 0.5, "a drop only the corrections know is added")
end)

test("QuestieDB's contract is checked, and its source mode shown, on the About line and once in chat", function()
    local ns = createAddon()
    local printed = {}
    ns.print = function(message)
        printed[#printed + 1] = message
    end
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "QuestieDB"
    end
    LibQuestieDB.RequireContract = function(version)
        return version <= 4, version > 4 and "needs contract " .. version or nil
    end
    LibQuestieDB.readMode = "baked"
    expectEqual(ns.Database.checkContract(), true, "contract 4 supported")
    ns.Compatibility.notify("onLoginSettled")
    expectEqual(#printed, 0, "all well: nothing said")
    LibQuestieDB.RequireContract = function()
        return false, "contract 4 is newer than 3"
    end
    ns.Compatibility.notify("onLoginSettled")
    expectEqual(#printed, 1, "too old: said once in chat")
    expectEqual(
        ns.Compatibility.getIntegrations()[1].text:find("Too old for OneMoreQuest", 1, true) ~= nil,
        true,
        "and on its About line"
    )
    LibQuestieDB.RequireContract = function()
        return true
    end
    LibQuestieDB.readMode = "source"
    LibQuestieDB.ModeIndicator = {
        GetText = function()
            return "QuestieDB: SOURCE MODE (Classic)"
        end,
    }
    expectEqual(
        ns.Compatibility.getIntegrations()[1].text:find("SOURCE MODE (Classic)", 1, true) ~= nil,
        true,
        "source mode shown in its own words"
    )
    LibQuestieDB.RequireContract, LibQuestieDB.readMode, LibQuestieDB.ModeIndicator, _G.C_AddOns.IsAddOnLoaded =
        nil, nil, nil, nil
end)

test(
    "with Leatrix Maps keeping the map where it was moved, opening the window beside it leaves the map there",
    function()
        local ns = createAddon()
        local savedUpdate, savedAttribute, savedLoaded, savedHook =
            UpdateUIPanelPositions, SetUIPanelAttribute, ns.isAddOnLoaded, hooksecurefunc
        -- The game's window layout puts the map in its usual spot (on opening the map, and when asked)
        local function layOut(frame)
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
        end
        UpdateUIPanelPositions, SetUIPanelAttribute = layOut, function() end
        hooksecurefunc = function(target, name, after)
            if type(target) == "string" then -- (a global function: hooksecurefunc("Name", fn))
                target, name, after = _G, target, name
            end
            local original = target[name]
            rawset(target, name, function(...)
                original(...)
                after(...)
            end)
        end
        local function where()
            local _, _, _, x, y = WorldMapFrame:GetPoint(1)
            return x .. "," .. y
        end
        ns.MapDock.create()
        -- Without it: the game's layout places the map, as before
        layOut(WorldMapFrame)
        ns.MapDock.apply()
        expectEqual(where(), "16,-116", "without Leatrix Maps, the game's spot")
        -- With it: the player drags the map; Leatrix Maps anchors it there
        ns.isAddOnLoaded = function(name)
            return name == "Leatrix_Maps" or savedLoaded(name)
        end
        _G.LeaMapsDB = { UnlockMap = "On" }
        ns.Compatibility.notify("onLoginSettled")
        WorldMapFrame:ClearAllPoints()
        WorldMapFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 400, -90)
        WorldMapFrame:StopMovingOrSizing()
        -- Closed and opened again: the game's layout moves it to its spot, and the game's own quest panel (which would
        -- have Leatrix Maps put it back) stays closed
        layOut(WorldMapFrame)
        ns.MapDock.apply()
        expectEqual(where(), "400,-90", "back where the player dragged it")
        UpdateUIPanelPositions, SetUIPanelAttribute, ns.isAddOnLoaded, hooksecurefunc, _G.LeaMapsDB =
            savedUpdate, savedAttribute, savedLoaded, savedHook, nil
        rawset(WorldMapFrame, "StopMovingOrSizing", nil)
        rawset(WorldMapFrame, "SynchronizeDisplayState", nil)
        rawset(WorldMapFrame, "OnFrameSizeChanged", nil)
    end
)
