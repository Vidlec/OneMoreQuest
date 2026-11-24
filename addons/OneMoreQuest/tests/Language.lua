-- Tests: languages: Czech, translation addons and narration, and the game's own wording.

test("a creature's tooltip knows the creature from its GUID, and leaves players and secrets alone", function()
    local ns = createAddon()
    expectEqual(ns.UnitTooltip.getNpcId("Creature-0-4372-1-15-3244-00002B3C1D"), 3244, "a creature")
    expectEqual(ns.UnitTooltip.getNpcId("Vehicle-0-4372-1-15-27894-00002B3C1D"), 27894, "a vehicle")
    expectEqual(ns.UnitTooltip.getNpcId("Player-4372-0A1B2C3D"), nil, "not a player")
    expectEqual(ns.UnitTooltip.getNpcId("Pet-0-4372-1-15-416-01002B3C1D"), nil, "not a pet")
    expectEqual(ns.UnitTooltip.getNpcId(nil), nil, "nothing for no GUID")
    local secret = setmetatable({}, {
        __index = function()
            error("secret")
        end,
    })
    issecretvalue = function(value)
        return value == secret
    end
    expectEqual(ns.UnitTooltip.getNpcId(secret), nil, "a secret GUID is left alone")
    issecretvalue = nil
    expectEqual(#ns.UnitTooltip.compose(nil), 0, "no creature, no lines")
end)

test("a kill objective is told by the game's own kill wording, in the client's language", function()
    local ns = createAddon()
    expectEqual(ns.QuestState.isKillWording("Roadside Bandit slain"), true, "English")
    expectEqual(ns.QuestState.isKillWording("Find the Gnomish Tools"), false, "not a kill")
    QUEST_MONSTERS_KILLED = "%1$s getötet: %2$d/%3$d"
    expectEqual(
        ns.QuestState.isKillWording("Wassersucher der Grimmhauer getötet"),
        true,
        "German, from the game's string"
    )
    expectEqual(
        ns.QuestState.removeKillWording("Wassersucher der Grimmhauer getötet"):match("^%s*(.-)%s*$"),
        "Wassersucher der Grimmhauer",
        "the name without it"
    )
    QUEST_MONSTERS_KILLED = nil
end)

test("objective labels lose their counts", function()
    local ns = createAddon()
    expectEqual(ns.QuestState.getObjectiveLabel("5/12 Roadside Bandit slain"), "Roadside Bandit slain", "count first")
    expectEqual(ns.QuestState.getObjectiveLabel("Wolf Fang: 0/4"), "Wolf Fang", "count last")
    expectEqual(ns.QuestState.getObjectiveLabel("Speak with the envoy"), "Speak with the envoy", "no count")
end)

test("every Czech phrase fills in the same values as its English, and a count has all three forms", function()
    local ns = createAddon()
    local function getBlanks(text)
        local blanks = {}
        for blank in text:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*[sdfgxXc]") do
            blanks[#blanks + 1] = blank:gsub("[%-%+ #0%d%.]", "")
        end
        return table.concat(blanks, ",")
    end
    local count = 0
    for english, czech in pairs(ns.Locale.tables.cs) do
        count = count + 1
        if type(czech) == "table" then
            expectEqual(#czech, 3, "three forms for a count: " .. english)
            for _, form in ipairs(czech) do
                expectEqual(
                    getBlanks(form),
                    getBlanks(english),
                    'the same values in "' .. form .. '" as in "' .. english .. '"'
                )
            end
        else
            expectEqual(type(czech), "string", "a translation is text: " .. english)
            expectEqual(
                getBlanks(czech),
                getBlanks(english),
                'the same values in "' .. czech .. '" as in "' .. english .. '"'
            )
        end
    end
    -- The helpers: English unless Czech is chosen, a count's form by the Czech rule
    expectEqual(ns.Lp(1, "%d quest", "%d quests"), "1 quest", "English, one")
    expectEqual(ns.Lp(5, "%d quest", "%d quests"), "5 quests", "English, more")
    ns.Locale.add(
        "cs",
        { ["%d test quest"] = { "%d testovací quest", "%d testovací questy", "%d testovacích questů" } }
    )
    ns.settings.language = "cs"
    expectEqual(ns.Lp(1, "%d test quest", "%d test quests"), "1 testovací quest", "Czech, one")
    expectEqual(ns.Lp(3, "%d test quest", "%d test quests"), "3 testovací questy", "Czech, two to four")
    expectEqual(ns.Lp(7, "%d test quest", "%d test quests"), "7 testovacích questů", "Czech, five and more")
    expectEqual(ns.L("No such phrase %d", 4), "No such phrase 4", "a phrase without a translation stays English")
end)

test(
    "in Czech, text in the game's Friz Quadrata takes a look-alike with every Czech letter; other fonts stay",
    function()
        local ns = createAddon()
        local function makeFont(path)
            local font = { path = path, size = 12, flags = "" }
            function font:GetFont()
                return self.path, self.size, self.flags
            end
            function font:SetFont(newPath, size, flags)
                self.path, self.size, self.flags = newPath, size, flags
            end
            function font:CopyFontObject(other)
                self.path, self.size, self.flags = other:GetFont()
            end
            return font
        end
        local saved = { CreateFont, _G.TestGameFont, _G.TestOtherFont, _G.GameTooltipText }
        CreateFont = function()
            return makeFont()
        end
        _G.TestGameFont, _G.TestOtherFont =
            makeFont("Fonts\\FRIZQT__.TTF"), makeFont("Interface\\AddOns\\Czech\\Font.ttf")
        _G.GameTooltipText = makeFont("Fonts\\FRIZQT__.TTF")
        expectEqual(ns.Widgets.getFont("TestGameFont"), _G.TestGameFont, "in English, the game's own font")
        ns.settings.language = "cs"
        expectEqual(
            (ns.Widgets.getFont("TestGameFont"):GetFont()):find("Marcellus", 1, true) ~= nil,
            true,
            "in Czech, Marcellus for Friz Quadrata"
        )
        expectEqual(ns.Widgets.getFont("TestOtherFont"), _G.TestOtherFont, "a font another addon put in place stays")
        ns.Widgets.applyFonts()
        expectEqual(
            (_G.GameTooltipText:GetFont()):find("Marcellus", 1, true) ~= nil,
            true,
            "tooltips take the look-alike in Czech"
        )
        ns.settings.language = "en"
        ns.Widgets.applyFonts()
        expectEqual(_G.GameTooltipText:GetFont(), "Fonts\\FRIZQT__.TTF", "and the game's own again in English")
        CreateFont, _G.TestGameFont, _G.TestOtherFont, _G.GameTooltipText = saved[1], saved[2], saved[3], saved[4]
    end
)

test("every window draws without errors in Czech", function()
    local ns, state = createAddon()
    ns.settings.language = "cs"
    setQuest(state, 301, false, { killObjective(5, 12), itemObjective(1, 4) })
    setQuest(state, 302, true, {})
    ns.Tracker.create()
    ns.Tracker.refresh()
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.selectQuest(301)
    ns.Log.refresh()
    for index = 1, #ns.SettingsPage.SECTIONS do
        ns.Log.openSettings(index)
        ns.Log.refresh()
    end
    ns.Log.toggleChronicle()
    for index = 1, #ns.ChroniclePage.CHAPTERS do
        ns.ChroniclePage.chapterIndex = index
        ns.Log.refresh()
    end
    expectEqual(true, true, "drawn")
end)

test("with Azeroth česky on, quests show its Czech titles and objectives; English stays for matching", function()
    local ns, state = createAddon()
    local fake = installAzerothCesky(state)
    setQuest(state, 301, false, { killObjective(5, 12) })
    ns.settings.language = "cs" -- the Czech providers work only in Czech
    ns.QuestText.start()
    expectEqual(ns.QuestText.active and ns.QuestText.active.name, "AzerothCesky", "found at login")
    local quest = ns.QuestState.getQuest(301)
    expectEqual(quest.title, "Dvě fronty", "the title as shown")
    expectEqual(quest.englishTitle, "Two Fronts", "the English kept")
    expectEqual(quest.objectives[1].shownLabel, "zabitých banditů", "the objective as shown, count apart")
    expectEqual(quest.objectives[1].label, "Roadside Bandit slain", "the English label kept for matching")
    expectEqual(ns.QuestText.getQuestName(301), "Dvě fronty", "the database's name, as shown")
    expectEqual(ns.QuestText.getTitle(302, "Other Quest"), "Other Quest", "a quest it does not know stays English")
    local asked = fake.asked
    ns.QuestState.getQuest(301)
    expectEqual(fake.asked, asked, "answers are kept, not asked again on every drawing")
    -- Switched off in its settings: everything is English again, at once
    fake.change(false)
    expectEqual(ns.QuestState.getQuest(301).title, "Two Fronts", "switched off: English")
    fake.change(true)
    expectEqual(ns.QuestState.getQuest(301).title, "Dvě fronty", "switched on again: Czech")
    -- Every window draws with the translated texts
    ns.Tracker.create()
    ns.Tracker.refresh()
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.selectQuest(301)
    ns.Log.refresh()
    ns.Log.toggleChronicle()
    ns.Log.refresh()
    removeAzerothCesky()
end)

test("without a translation addon, or with a broken one, quest texts stay as the game gives them", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(5, 12) })
    ns.settings.language = "cs" -- the Czech providers work only in Czech
    ns.QuestText.start()
    expectEqual(ns.QuestText.active, nil, "nothing installed: no provider")
    expectEqual(ns.QuestState.getQuest(301).title, "Two Fronts", "English")
    -- Installed but answering with errors: OneMoreQuest carries on in English
    local ns2, state2 = createAddon()
    installAzerothCesky(state2)
    _G.AzerothCeskyAPI.GetInterface(1).ResolveQuestTitle = function()
        error("broken")
    end
    _G.AzerothCeskyAPI.GetInterface(1).ResolveQuestMapField = function()
        error("broken")
    end
    setQuest(state2, 301, false, { killObjective(5, 12) })
    ns2.settings.language = "cs" -- the Czech providers work only in Czech
    ns2.QuestText.start()
    expectEqual(ns2.QuestState.getQuest(301).title, "Two Fronts", "a failing answer: English")
    -- Installed but not loaded (turned off in the addon list): not used
    local ns3 = createAddon()
    installAzerothCesky()
    _G.C_AddOns.IsAddOnLoaded = function()
        return false
    end
    ns3.settings.language = "cs" -- the Czech providers work only in Czech
    ns3.QuestText.start()
    expectEqual(ns3.QuestText.active, nil, "turned off in the addon list: not used")
    removeAzerothCesky()
end)

test("with WoWF.cz on, quests show its Czech titles, objectives and story, following its own settings", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(5, 12), itemObjective(1, 4) })
    _G.WowfCZ_QuestData = {
        [301] = { Title = "Dvě fronty", Description = "Ahoj, $Ghrdino:hrdinko;!$BJdi.", Objective = "Zabij bandity." },
    }
    _G.WowfCZ_DB = {}
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "WowfCZ"
    end
    ns.settings.language = "cs" -- the Czech providers work only in Czech
    ns.QuestText.start()
    expectEqual(ns.QuestText.active and ns.QuestText.active.name, "WowfCZ", "found at login")
    local quest = ns.QuestState.getQuest(301)
    expectEqual(quest.title, "Dvě fronty", "its title")
    expectEqual(quest.objectives[1].shownLabel, "Zabít Roadside Bandit", "a kill line by its own rule")
    expectEqual(quest.objectives[1].label, "Roadside Bandit slain", "the English kept for matching")
    expectEqual(quest.objectives[2].shownLabel, "Získat Wolf Fang", "an item line by its own rule")
    expectEqual(ns.QuestText.getDescription(301, "Hello."), "Ahoj, hrdino!\nJdi.", "its story, placeholders filled in")
    expectEqual(ns.QuestText.getObjectives(301, "Kill bandits."), "Zabij bandity.", "what it asks")
    expectEqual(ns.QuestText.getTitle(999, "Unknown"), "Unknown", "a quest it has no translation of stays English")
    -- Its settings are read as they change, without a reload: quest titles in English, then the addon off
    _G.WowfCZ_DB.titleLang = "en"
    expectEqual(ns.QuestState.getQuest(301).title, "Two Fronts", "its titles set to English")
    expectEqual(
        ns.QuestState.getQuest(301).objectives[1].shownLabel,
        "Zabít Roadside Bandit",
        "objectives still Czech"
    )
    _G.WowfCZ_DB.enabled = false
    expectEqual(ns.QuestState.getQuest(301).objectives[1].shownLabel, "Roadside Bandit slain", "switched off: English")
    _G.WowfCZ_DB = { enabled = true }
    expectEqual(ns.QuestState.getQuest(301).title, "Dvě fronty", "on again: Czech")
    expectEqual(
        ns.QuestText.isTranslating(),
        true,
        "translating, so the fonts take Czech letters with OneMoreQuest in English"
    )
    _G.WowfCZ_QuestData, _G.WowfCZ_DB, _G.C_AddOns.IsAddOnLoaded = nil, nil, nil
end)

test(
    "with Azeroth česky loaded but switched off, WoWF.cz translates; switched back on, Azeroth česky does",
    function()
        local ns, state = createAddon()
        setQuest(state, 301, false, { killObjective(5, 12) })
        local fake = installAzerothCesky(state)
        _G.WowfCZ_QuestData = { [301] = { Title = "Dvě fronty (WoWF)" } }
        _G.WowfCZ_DB = {}
        _G.C_AddOns.IsAddOnLoaded = function(name)
            return name == "AzerothCesky" or name == "WowfCZ"
        end
        fake.isOn = false
        ns.settings.language = "cs" -- the Czech providers work only in Czech
        ns.QuestText.start()
        expectEqual(ns.QuestState.getQuest(301).title, "Dvě fronty (WoWF)", "Azeroth česky off: WoWF.cz's")
        fake.change(true)
        expectEqual(ns.QuestState.getQuest(301).title, "Dvě fronty", "Azeroth česky on: its own, first")
        _G.WowfCZ_QuestData, _G.WowfCZ_DB = nil, nil
        removeAzerothCesky()
    end
)

test("WoWF.cz's narration: a quest with a recording plays, queues and stops through its own player", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(5, 12) })
    local player = { queue = {}, listeners = {}, enabled = true }
    local function notify()
        for _, listener in ipairs(player.listeners) do
            listener()
        end
    end
    _G.WowfCZVoice = {
        Enabled = function()
            return player.enabled
        end,
        Listen = function(callback)
            player.listeners[#player.listeners + 1] = callback
        end,
        FirstClip = function(questId)
            return questId == 301 and "m-301-accept" or nil
        end,
        QuestState = function(questId)
            if player.current == questId then
                return "playing"
            end
            for index, queued in ipairs(player.queue) do
                if queued == questId then
                    return "queued", index
                end
            end
            return nil
        end,
        PlayQuestNow = function(questId)
            player.current = questId
            notify()
        end,
        QueueQuest = function(questId)
            player.queue[#player.queue + 1] = questId
            notify()
        end,
        StopQuest = function(questId)
            if player.current == questId then
                player.current = nil
            end
            for index = #player.queue, 1, -1 do
                if player.queue[index] == questId then
                    table.remove(player.queue, index)
                end
            end
            notify()
        end,
    }
    _G.WowfCZ_QuestData, _G.WowfCZ_DB = {}, { enabled = false } -- texts off: the narration stands on its own
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "WowfCZ"
    end
    ns.settings.language = "cs" -- the Czech providers work only in Czech
    ns.QuestText.start()
    expectEqual(#player.listeners, 1, "listens to its player")
    expectEqual(ns.QuestText.getVoiceState(301), "idle", "has a recording, not playing")
    expectEqual(ns.QuestText.getVoiceState(302), nil, "no recording: no button")
    ns.QuestText.toggleVoice(301)
    expectEqual(ns.QuestText.getVoiceState(301), "playing", "plays now")
    ns.QuestText.toggleVoice(301)
    expectEqual(ns.QuestText.getVoiceState(301), "idle", "the same click stops it")
    ns.QuestText.toggleVoiceQueue(301)
    local queued, position = ns.QuestText.getVoiceState(301)
    expectEqual(queued .. position, "queued1", "queued, first in line")
    ns.QuestText.toggleVoiceQueue(301)
    expectEqual(ns.QuestText.getVoiceState(301), "idle", "taken off the queue")
    -- The quest page's row, the list's mark and the tracker's speaker draw in each state, in both languages
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.selectQuest(301)
    for _, language in ipairs({ "en", "cs" }) do
        ns.settings.language = language
        for _, step in ipairs({ "idle", "play", "queue" }) do
            player.current, player.queue = nil, {}
            if step == "play" then
                ns.QuestText.toggleVoice(301)
            elseif step == "queue" then
                ns.QuestText.toggleVoiceQueue(301)
            end
            ns.Tracker.refresh()
            ns.Log.refresh()
        end
    end
    ns.settings.language = "en"
    player.current, player.queue = nil, {}
    player.enabled = false
    expectEqual(ns.QuestText.getVoiceState(301), nil, "its narration turned off: no button")
    _G.WowfCZVoice, _G.WowfCZ_QuestData, _G.WowfCZ_DB, _G.C_AddOns.IsAddOnLoaded = nil, nil, nil, nil
end)

test("translation addons work only in their language; one with a narration only leaves the texts to others", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(5, 12) })
    _G.WowfCZ_QuestData, _G.WowfCZ_DB = { [301] = { Title = "Dvě fronty" } }, {}
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "WowfCZ"
    end
    -- An English voice pack: a narration only, no texts
    local isEnglishPlaying = false
    ns.QuestText.register({
        name = "EnglishVoices",
        label = "English Voices",
        language = "en",
        detect = function()
            return true
        end,
        voice = {
            isOn = function()
                return true
            end,
            start = function() end,
            hasRecording = function(questId)
                return questId == 301
            end,
            getState = function()
                return isEnglishPlaying and "playing" or "idle"
            end,
            play = function()
                isEnglishPlaying = true
            end,
            queue = function() end,
            stop = function()
                isEnglishPlaying = false
            end,
        },
    })
    ns.settings.language = "en"
    ns.QuestText.start()
    expectEqual(ns.QuestState.getQuest(301).title, "Two Fronts", "OneMoreQuest in English: no Czech titles")
    local _, provider = ns.QuestText.getVoice()
    expectEqual(provider and provider.name, "EnglishVoices", "in English, the English narration")
    ns.QuestText.toggleVoice(301)
    expectEqual(ns.QuestText.getVoiceState(301), "playing", "it plays")
    ns.Locale.setLanguage("cs")
    expectEqual(ns.QuestState.getQuest(301).title, "Dvě fronty", "switched to Czech: WoWF.cz's titles")
    expectEqual(
        ns.QuestText.getVoice(),
        nil,
        "no Czech narration here (WoWF.cz's voice is not installed), and not the English one"
    )
    ns.Locale.setLanguage("en")
    expectEqual(ns.QuestState.getQuest(301).title, "Two Fronts", "back to English: English titles")
    _G.WowfCZ_QuestData, _G.WowfCZ_DB, _G.C_AddOns.IsAddOnLoaded = nil, nil, nil
end)

test("Spoken's English narration: plays, queues and stops through Spoken's queue, only in English", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(5, 12) })
    -- Spoken's player: one queue, the head speaking unless paused
    local queue, isPaused, listeners = {}, false, {}
    local function changed()
        for _, listener in ipairs(listeners) do
            listener()
        end
    end
    local source = {
        PlayNow = function(_, clip)
            for index, queued in ipairs(queue) do
                if queued == clip then
                    table.remove(queue, index)
                    break
                end
            end
            table.insert(queue, #queue > 0 and 2 or 1, clip)
            changed()
        end,
    }
    _G.Spoken = {
        IsCompatible = function(_, version)
            return version <= 1
        end,
        GetQueue = function()
            local copy = {}
            for index, clip in ipairs(queue) do
                copy[index] = clip
            end
            return copy
        end,
        GetCurrent = function()
            return queue[1]
        end,
        GetNowPlaying = function()
            return not isPaused and queue[1] or nil
        end,
        IsPaused = function()
            return isPaused
        end,
        TogglePause = function()
            isPaused = not isPaused
            changed()
        end,
        RegisterCallback = function(_, event, callback)
            if event == "AUDIO_CHANGED" then
                listeners[#listeners + 1] = callback
            end
        end,
    }
    local isPartOn = true
    _G.VoiceOver = {
        Enums = {
            SoundEvent = { QuestAccept = 1 },
            GUID = {
                CanHaveID = function()
                    return true
                end,
                IsCreature = function()
                    return true
                end,
            },
        },
        Addon = {
            IsPartOn = function()
                return isPartOn
            end,
        },
        Utils = {
            MakeGUID = function(_, kind, id)
                return "Creature-0-0-0-0-" .. id
            end,
        },
        DataModules = {
            PrepareSound = function(_, line)
                return line.questID == 301
            end,
            GetQuestLogQuestGiverTypeAndID = function()
                return "Creature", 9002
            end,
            GetObjectName = function()
                return "Giver"
            end,
        },
        QuestOverlayUI = {
            QueuedLine = function(_, questId)
                for _, clip in ipairs(queue) do
                    if clip.questID == questId then
                        return clip
                    end
                end
            end,
        },
        Player = {
            source = source,
            PlayNow = function(_, line)
                source:PlayNow(line)
            end,
            Enqueue = function(_, line)
                queue[#queue + 1] = line
                changed()
            end,
            Remove = function(_, clip)
                for index, queued in ipairs(queue) do
                    if queued == clip then
                        table.remove(queue, index)
                        break
                    end
                end
                changed()
            end,
        },
    }
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "Spoken_Quests" or name == "Spoken"
    end
    ns.settings.language = "en"
    ns.QuestText.start()
    expectEqual(#listeners, 1, "listens to Spoken's queue")
    expectEqual(ns.QuestText.getVoiceState(301), "idle", "a recording, nothing playing")
    expectEqual(ns.QuestText.getVoiceState(302), nil, "no recording: no button")
    ns.QuestText.toggleVoice(301)
    expectEqual(ns.QuestText.getVoiceState(301), "playing", "plays when nothing speaks")
    expectEqual(
        queue[1].name .. queue[1].unitGUID,
        "GiverCreature-0-0-0-0-9002",
        "in its giver's voice, as Spoken's own Play asks"
    )
    ns.QuestText.toggleVoice(301)
    expectEqual(ns.QuestText.getVoiceState(301), "idle", "the same click stops it")
    queue[1] = { questID = 999 } -- another line speaks
    ns.QuestText.toggleVoiceQueue(301)
    local queued, position = ns.QuestText.getVoiceState(301)
    expectEqual(queued .. position, "queued1", "waits first behind the line speaking")
    ns.QuestText.toggleVoiceQueue(301)
    expectEqual(ns.QuestText.getVoiceState(301), "idle", "taken off the queue")
    isPartOn = false
    expectEqual(ns.QuestText.getVoiceState(301), nil, "Spoken Quests switched off: no button")
    isPartOn = true
    ns.Locale.setLanguage("cs")
    expectEqual(ns.QuestText.getVoiceState(301), nil, "OneMoreQuest in Czech: not the English narration")
    _G.Spoken, _G.VoiceOver, _G.C_AddOns.IsAddOnLoaded = nil, nil, nil
end)

test(
    "in Czech, the game's menus draw OneMoreQuest's entries in a font with Czech letters, then give it back",
    function()
        local ns = createAddon()
        local function makeRoot()
            local root = {}
            function root:CreateButton()
                local description = { initializers = {}, resetters = {} }
                function description:AddInitializer(callback)
                    self.initializers[#self.initializers + 1] = callback
                end
                function description:AddResetter(callback)
                    self.resetters[#self.resetters + 1] = callback
                end
                root.last = description
                return description
            end
            return root
        end
        local function makeFont(path)
            local font = { path = path }
            function font:GetFont()
                return self.path, 14, ""
            end
            function font:SetFont(newPath)
                self.path = newPath
            end
            function font:CopyFontObject(other)
                self.path = other.path
            end
            return font
        end
        local gameFont = makeFont("Fonts\\FRIZQT__.TTF")
        -- As the game's menu texts: SetFont is refused, a font object is taken
        local text = { fontObject = gameFont }
        function text:GetFont()
            return self.fontObject:GetFont()
        end
        function text:GetFontObject()
            return self.fontObject
        end
        function text:SetFontObject(font)
            self.fontObject = font
        end
        function text:SetFont()
            error("Use of function 'SetFont' is disallowed.")
        end
        local button = { fontString = text }
        local savedCreateFont = CreateFont
        CreateFont = function()
            return makeFont()
        end
        ns.settings.language = "cs"
        local root = makeRoot()
        ns.Widgets.setMenuFonts(root)
        root:CreateButton("Otevřít v quest logu")
        root.last.initializers[1](button)
        expectEqual(
            (text:GetFont()):find("Marcellus", 1, true) ~= nil,
            true,
            "the entry in the look-alike, through a font object"
        )
        root.last.resetters[1](button)
        expectEqual(text:GetFontObject(), gameFont, "the reused button gets the game's font back")
        CreateFont = savedCreateFont
        ns.settings.language = "en"
        local englishRoot = makeRoot()
        ns.Widgets.setMenuFonts(englishRoot)
        englishRoot:CreateButton("Open in the quest log")
        expectEqual(#englishRoot.last.initializers, 0, "in English the menu is left as the game draws it")
    end
)

test("a quest not taken yet is narrated too: Play and Queue on its page on the Available tab", function()
    local ns = createAddon()
    -- Fresh Start, on the Available tab and in no quest log, has a recording in WoWF.cz's player
    local played
    _G.WowfCZVoice = {
        Enabled = function()
            return true
        end,
        Listen = function() end,
        FirstClip = function(questId)
            return questId == 501 and "m-501-accept" or nil
        end,
        QuestState = function(questId)
            return played == questId and "playing" or nil
        end,
        PlayQuestNow = function(questId)
            played = questId
        end,
        QueueQuest = function() end,
        StopQuest = function()
            played = nil
        end,
    }
    _G.WowfCZ_QuestData, _G.WowfCZ_DB = {}, { enabled = false }
    local savedLoaded = _G.C_AddOns and _G.C_AddOns.IsAddOnLoaded
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "WowfCZ"
    end
    ns.settings.language = "cs"
    ns.QuestText.start()
    expectEqual(ns.QuestState.isInLog(501), false, "not taken")
    expectEqual(ns.QuestText.getVoiceState(501), "idle", "its narration is there all the same")
    ns.Availability.prepare()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showAvailable(501)
    local voice = ns.LogState.pageHeader.voice
    expectEqual(voice:IsShown() and voice.questId, 501, "its page on the Available tab offers Play and Queue")
    ns.QuestText.toggleVoice(501)
    expectEqual(played, 501, "and plays it before it is taken")
    _G.WowfCZVoice, _G.WowfCZ_QuestData, _G.WowfCZ_DB = nil, nil, nil
    _G.C_AddOns.IsAddOnLoaded = savedLoaded
end)

test("a language set from the settings (the dropdown, a reset) is told to everything that draws in it", function()
    local ns = createAddon()
    local told = 0
    ns.on("LANGUAGE_CHANGED", function()
        told = told + 1
    end)
    ns.SettingsPage.apply()
    ns.settings.language = "cs" -- as the dropdown sets it
    ns.SettingsPage.apply()
    expectEqual(told, 1, "the change is told once")
    ns.SettingsPage.apply()
    expectEqual(told, 1, "nothing new, nothing told")
    ns.resetSettings() -- back to English
    ns.SettingsPage.apply()
    expectEqual(told, 2, "a reset to defaults is told too")
end)
test("the first language switch of a session is told, though nothing was applied before it", function()
    local ns = createAddon()
    local told = 0
    ns.on("LANGUAGE_CHANGED", function()
        told = told + 1
    end)
    ns.settings.language = "cs" -- as the dropdown sets it, the first thing done after logging in
    ns.SettingsPage.apply()
    expectEqual(told, 1, "the switch is told")
    ns.SettingsPage.apply()
    expectEqual(told, 1, "and only once")
    expectEqual(ns.Locale.applyLanguage(), false, "nothing left to tell")
end)
