local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- OneMoreQuest's settings. They are shown on the quest panels' page, opened by the cog in the panels' title (see
-- Log\SettingsView); this file holds the list of them and carries a change out everywhere. The game's own settings
-- window (Escape, Options, AddOns) keeps a short OneMoreQuest page that opens them, with the one switch that
-- brings the panels back when they are off.
local SettingsPage = {}
ns.SettingsPage = SettingsPage

local function resetTrackerPosition()
    ns.settings.position = nil
    ns.settings.trackerWidth = nil -- its width too, as it started
    ns.settings.trackerHeightShare = 0 -- and as tall as fits
    ns.Tracker.resetPosition()
    ns.Tracker.refresh()
end

local ICONS = "Interface\\Icons\\"

---@return string text A size as the settings show it: "130%"
local function formatPercent(value)
    return string.format("%d%%", math.floor(value * 100 + 0.5))
end

---A size setting: 70% to 160% in tenths, unless a range is given
local function sizeOption(key, label, note, min, max)
    return {
        stepKey = key,
        label = label,
        note = note,
        min = min or 0.7,
        max = max or 1.6,
        step = 0.1,
        default = 1,
        format = formatPercent,
    }
end

-- What this addon puts in place of the game's own. Each can be switched back on its own, and all at once; the
-- game's settings window (Options, AddOns) has the same switches, as the way back once the panels are off.
local REPLACEMENTS = {
    {
        key = "shouldReplaceQuestLog",
        label = "Use " .. ns.ADDON_TITLE .. "'s quest log",
        name = "Quest log",
        icon = ICONS .. "INV_Misc_Book_09",
        ours = "Grouped by zone, beside the map, with chains and drops.",
        game = "The game's own quest log.",
        note = "Off: the map shows the game's own quest panel, and the quest log key opens it.",
    },
    {
        keys = { "isShown", "shouldHideBuiltInTracker" },
        label = "Use " .. ns.ADDON_TITLE .. "'s tracker",
        name = "Tracker",
        icon = ICONS .. "INV_Scroll_03",
        ours = "Grouped by zone, with chains and quest items.",
        game = "The game's own quest tracker.",
        note = "Off: the game's own quest tracker comes back.",
    },
    {
        keys = { "shouldShowMapPins", "shouldHideBuiltInMapPins" },
        label = "Use " .. ns.ADDON_TITLE .. "'s map marks",
        name = "Map marks",
        icon = ICONS .. "INV_Misc_Map_01",
        ours = "Quest marks, objective areas, waypoints.",
        game = "The game's own quest markers.",
        note = "Off: the game's own quest markers come back on the map and the minimap.",
    },
    {
        keys = { "shouldUseAvailableQuests", "shouldShowAvailableOnMap" },
        label = "Use " .. ns.ADDON_TITLE .. "'s quests to pick up",
        name = "Quests to pick up",
        icon = ICONS .. "INV_Misc_Note_01",
        ours = 'The Available tab and its "!" marks.',
        game = 'The game\'s own "!" marks.',
        note = "Off: the Available tab goes, and the map shows the game's own marks for quests you can pick up.",
    },
}
SettingsPage.REPLACEMENTS = REPLACEMENTS

---Switches this addon's map marks on or off (the third of the parts above): the game's own come back when off.
local function setMapMarks(isOn)
    for _, key in ipairs(REPLACEMENTS[3].keys) do
        ns.settings[key] = isOn
    end
end

-- What a setting needs switched on to do anything: a whole section names it once (`needs`), a setting may name
-- another or none (`needs = false`). While it is off the setting is greyed out and takes no click
-- (SettingsPage.isAvailable), and its section says which part to switch on (SettingsPage.getSwitchedOffPart).
local NEEDS = {
    questLog = {
        isMet = function()
            return ns.settings.shouldReplaceQuestLog == true
        end,
        part = REPLACEMENTS[1],
    },
    tracker = {
        isMet = function()
            return ns.settings.isShown == true
        end,
        part = REPLACEMENTS[2],
    },
    mapMarks = {
        isMet = function()
            return ns.settings.shouldShowMapPins == true
        end,
        part = REPLACEMENTS[3],
    },
    available = {
        isMet = function()
            return ns.settings.shouldUseAvailableQuests == true
        end,
        part = REPLACEMENTS[4],
    },
    questLogOrTracker = {
        isMet = function()
            return ns.settings.shouldReplaceQuestLog == true or ns.settings.isShown == true
        end,
    },
    mapMarksAndAvailable = {
        isMet = function()
            return ns.settings.shouldShowMapPins == true and ns.settings.shouldUseAvailableQuests == true
        end,
    },
}

local function setReplacements(isQuestLogOn, isRestOn)
    for index, option in ipairs(REPLACEMENTS) do
        for _, key in ipairs(option.keys or { option.key }) do
            ns.settings[key] = index == 1 and isQuestLogOn or isRestOn
        end
    end
end

-- Whole setups in one click, on the first page of the settings
SettingsPage.QUICK_SETUPS = {
    {
        title = "Everything",
        note = "All of " .. ns.ADDON_TITLE .. ".",
        apply = function()
            setReplacements(true, true)
            SettingsPage.apply()
        end,
    },
    {
        title = "Just the log",
        note = "The quest log; the game does the rest.",
        apply = function()
            setReplacements(true, false)
            SettingsPage.apply()
        end,
    },
    {
        title = "Game's own",
        note = "Back to the game, all of it.",
        apply = function()
            SettingsPage.useGameOwn()
        end,
    },
}

---@return number? index The quick setup the switches match now, if any
function SettingsPage.getQuickSetupIndex()
    local isQuestLogOn = SettingsPage.isOn(REPLACEMENTS[1])
    local areOthersOn, areOthersOff = true, true
    for index = 2, #REPLACEMENTS do
        local isOn = SettingsPage.isOn(REPLACEMENTS[index])
        areOthersOn, areOthersOff = areOthersOn and isOn, areOthersOff and not isOn
    end
    if isQuestLogOn and areOthersOn then
        return 1
    elseif isQuestLogOn and areOthersOff then
        return 2
    elseif not isQuestLogOn and areOthersOff then
        return 3
    end
    return nil
end

-- The settings, section by section, each in groups under a carved title plate. A section with a preview shows a
-- small picture over its groups that follows them; choices are drawn as pictures to pick from, or as a row of
-- tiles (see Log\SettingsView). An option with `isAvailable` is greyed out, indented under the one it needs,
-- while that says no.

local function isSettingOn(key)
    return function()
        return ns.settings[key] == true
    end
end

-- The colours a kind of quest's "!" and "?" may take (MapMarks.dressQuestIcon), each tile showing both
local function iconColourOption(kind, label, note)
    return {
        choiceKey = "questIcon" .. kind,
        label = label,
        note = note,
        choices = {
            { value = "gold", label = "Gold" },
            { value = "blue", label = "Blue" },
            { value = "green", label = "Green" },
            { value = "orange", label = "Orange" },
            { value = "purple", label = "Purple" },
            { value = "pink", label = "Pink" },
            { value = "red", label = "Red" },
            { value = "grey", label = "Grey" },
        },
    }
end

-- How a quest in the log of a kind shows its coin (MapMarks.getMarkStyle), each tile the coin itself
local function questMarkOption(kind, label)
    return {
        choiceKey = "questMark" .. kind,
        label = label,
        choices = {
            { value = "plain", label = "As now", note = "What to do there, on the gold coin." },
            {
                value = "colour",
                label = "Its colour",
                note = 'The coin in the colour of the kind\'s "!" and "?" (Quests to pick up, Quest icons).',
            },
            {
                value = "icon",
                label = "Its icon",
                note = "The game's own icon for the kind on the coin, in place of what to do.",
            },
            { value = "both", label = "Both", note = "Its icon on a coin in its colour." },
        },
    }
end

---Every kind's quest mark the plain gold coin again.
local function usePlainMarks()
    for _, setting in pairs(ns.MapMarks.MARK_SETTINGS) do
        ns.settings[setting] = "plain"
    end
    ns.SettingsPage.apply()
    ns.Log.refresh()
end

---Every kind's icon colour as the game has them: gold, a grey "!" far below your level, blue repeatable.
local function useGameIconColours()
    for kind, setting in pairs(ns.MapMarks.ICON_SETTINGS) do
        ns.settings[setting] = ns.MapMarks.GAME_ICON_COLOURS[kind]
    end
    ns.SettingsPage.apply()
    ns.Log.refresh()
end

---The game's own minimap tracking of low-level quests (its grey "!" over an NPC near you, which no addon can hide one
---by one) set as OneMoreQuest's switch is: once, as the switch is flipped, so a choice made in the game's tracking
---menu afterwards stands. Found by its filter, whatever the client's language; by its English name on a client
---without filters.
local function setGameLowLevelTracking(isOn)
    local minimap = C_Minimap
    if not (minimap and minimap.GetNumTrackingTypes and minimap.GetTrackingInfo and minimap.SetTracking) then
        return
    end
    local wanted = Enum and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter.TrivialQuests
    for index = 1, minimap.GetNumTrackingTypes() or 0 do
        local info = minimap.GetTrackingInfo(index)
        local filter = wanted and minimap.GetTrackingFilter and minimap.GetTrackingFilter(index)
        local isLowLevel = (filter and filter.filterID == wanted)
            or (not wanted and info and info.name == "Low-Level Quests")
        if isLowLevel then
            if info and info.active ~= isOn then
                minimap.SetTracking(index, isOn)
            end
            return
        end
    end
end

---@return boolean isOn A look of ours is chosen for the areas (and the map marks are on): its fill and outline apply
local function hasAreaLook()
    return ns.settings.areaStyle ~= "none" and ns.settings.shouldShowMapPins == true
end

---@return boolean isShadows The areas are drawn as soft shadows alone: no fill and outline to set apart
local function isShadowsOnly()
    return ns.MapMarks.isShadowsOnly()
end

local function isNotShadowsOnly()
    return not isShadowsOnly()
end

---An area part's strength, 10% to 200%: greyed out while that part, or the areas, are off.
---@param partKey string? The setting that switches the part on; nil for a strength with no switch of its own
local function strengthOption(key, label, note, partKey)
    local option = sizeOption(key, label, note, 0.1, 2)
    option.isAvailable = function()
        return hasAreaLook() and (partKey == nil or ns.settings[partKey] ~= false)
    end
    return option
end

---An option that is on the page only while something holds (isShown): one that has no meaning otherwise is left
---out, not greyed.
local function hiddenUnless(isShown, option)
    option.isHidden = function()
        return not isShown()
    end
    return option
end

-- Show, fold or hide the tracker at a time: in combat, or in a dungeon or raid
local function trackerMoment(key, label)
    return {
        choiceKey = key,
        label = label,
        choices = {
            { value = "show", label = "Show", note = "As it is." },
            {
                value = "fold",
                label = "Fold",
                note = 'Down to its title, so it takes no room; click its "+" to look.',
            },
            { value = "hide", label = "Hide", note = "Gone, its quest item buttons too." },
        },
    }
end

-- Spoilers (Spoilers.lua): four presets drawn as cards, then each kind of spoiler by hand. The choices are the
-- character's own, kept by Spoilers, not in ns.settings: each option reads and sets them through getValue and
-- setValue. The words for each kind and each of its choices, in the order Spoilers.CATEGORIES gives them.
SettingsPage.SPOILER_PRESET_NOTES = {
    guide = "Everything: quests to pick up, exact spawns, drop chances, whole chains, rewards.",
    hints = "Where to look, not what you will find: rough areas, which creatures drop items (no %), how many steps a chain has.",
    explorer = "Only what you have found: givers and turn-ins you met, places you hunted, creatures you killed. The map fills in as you play.",
    purist = "Your log and the tracker's counts. Nothing on the map, no Available tab, no hints unless you ask.",
}

local SPOILER_WORDS = {
    pickup = {
        label = "Quests to pick up",
        note = 'The Available tab, "!" on the map and the minimap.',
        choices = { all = "All", met = "Givers you met", none = "None" },
    },
    objectives = {
        label = "Where objectives are",
        note = 'Areas, spawn markers, "Also in" zones.',
        choices = { exact = "Exact spawns", rough = "Rough area", found = "Where you found them", hidden = "Hidden" },
    },
    turnIn = {
        label = "Where to hand in",
        note = '"?" marks, and whom to turn in to and where.',
        choices = { shown = "Shown", met = "Once you met them", hidden = "Hidden" },
    },
    drops = {
        label = "What drops the items",
        note = 'Drop sources, chances, "about 28 kills".',
        choices = { chances = "With chances", names = "Names only", found = "Once one dropped it", hidden = "Hidden" },
    },
    creatures = {
        label = "Creatures you need",
        note = "Nameplate icons, creature tooltips.",
        choices = { always = "Always", killed = "After the first kill", hidden = "Hidden" },
    },
    chains = {
        label = "Quest chains",
        note = "The steps ahead, their names, the prize.",
        choices = { all = "Every step and the prize", count = "How many steps", hidden = "Hidden" },
    },
    rewards = {
        label = "Rewards and numbers",
        note = "Experience, money, item values, chain totals.",
        choices = { shown = "Shown", quest = "This quest only", hidden = "Hidden" },
    },
    dungeons = {
        label = "Dungeons and lead-ins",
        note = 'The Dungeons tab, "leads to a dungeon".',
        choices = { shown = "Shown", entered = "Dungeons you entered", hidden = "Hidden" },
    },
    hints = {
        label = "Hints when stuck",
        note = '"Need a hint?" on the quest\'s page and in the tracker.',
        choices = { offered = "Offered", asked = "Only when asked", off = "Off" },
    },
}

---@return table[] options One row of choices for each kind of spoiler, read from and set in Spoilers
local function composeSpoilerOptions()
    local options = {}
    for _, category in ipairs(ns.Spoilers.CATEGORIES) do
        local words = SPOILER_WORDS[category.key]
        local choices = {}
        for index, value in ipairs(category.choices) do
            choices[index] = { value = value, label = words.choices[value] }
        end
        local name = category.key
        options[#options + 1] = {
            spoilerCategory = name,
            label = words.label,
            note = words.note,
            choices = choices,
            needs = false,
            getValue = function()
                return ns.Spoilers.getChoice(name)
            end,
            setValue = function(value)
                ns.Spoilers.setChoice(name, value)
            end,
        }
    end
    return options
end

SettingsPage.SECTIONS = {
    {
        title = "At a glance",
        subtitle = "Switch whole parts, or pick a quick setup.",
        icon = ICONS .. "Spell_Holy_BorrowedTime",
        kind = "overview",
    },
    {
        title = "Spoilers",
        subtitle = "How much OneMoreQuest tells you. The quest's own text is never touched.",
        icon = ICONS .. "Spell_Holy_MindVision",
        groups = {
            {
                title = "How much to tell",
                options = { { isSpoilerPresets = true, needs = false } }, -- the four presets' cards (Log\SettingsView)
            },
            {
                title = "Fine-tune",
                note = 'Changing any of these makes the choice above "Custom".',
                options = composeSpoilerOptions(),
                footnote = 'Wherever something is held back, "Need a hint?" can still show it for one quest, a step at a time.',
            },
        },
    },
    {
        title = "Quest window",
        subtitle = "The panels beside the map. Every change shows at once.",
        icon = ICONS .. "INV_Misc_Book_11",
        needs = "questLog",
        groups = {
            {
                title = "Window",
                options = {
                    {
                        choiceKey = "windowBorder",
                        label = "Border",
                        note = "How the panels are framed beside the map.",
                        choices = {
                            {
                                value = "map",
                                label = "Like the map",
                                note = "Matches the map's frame: the game's own, or the one a map addon such as Leatrix Maps draws.",
                            },
                            {
                                value = "game",
                                label = "Game's frame",
                                note = "The metal border of the game's windows.",
                            },
                            { value = "gold", label = "Thin gold", note = "A thin gold line and a quiet title strip." },
                            {
                                value = "flat",
                                label = "Flat",
                                note = "A black edge and no title strip, which leaves more room for the list.",
                            },
                        },
                    },
                    {
                        choiceKey = "questDetails",
                        label = "Quest details",
                        note = "Where a quest's page opens.",
                        choices = {
                            {
                                value = "beside",
                                label = "Beside the list",
                                note = "The list and the open quest's page side by side: everything at a glance.",
                            },
                            {
                                value = "own",
                                label = "On a page of their own",
                                note = "As the game's own quest log: a click on a quest opens its page in the list's place, and Back returns to the list. The window is half as wide.",
                            },
                        },
                    },
                    sizeOption(
                        "windowScale",
                        "Size",
                        "Text and all. Larger suits a big or ultrawide screen at a small UI scale."
                    ),
                },
            },
            {
                title = "Quest lists",
                options = {
                    {
                        key = "shouldSuggestDrops",
                        label = "Suggest quests to drop",
                        note = "As the quest log fills up, a box over the list names the quests worth abandoning.",
                    },
                    {
                        choiceKey = "logGrouping",
                        label = "Group quests",
                        note = "In the quest log and the tracker.",
                        needs = "questLogOrTracker",
                        choices = {
                            {
                                value = "step",
                                label = "Where to go next",
                                note = "Each quest under the zone where its next step is done: what you can do here is together, wherever you got it.",
                            },
                            {
                                value = "pickup",
                                label = "Where picked up",
                                note = "As the game's own quest log: each quest under the zone it belongs to, mostly where you got it. It stays put as you do it.",
                            },
                        },
                    },
                },
            },
        },
    },
    {
        title = "Tracker",
        subtitle = "The picture follows what you switch.",
        icon = ICONS .. "INV_Scroll_03",
        preview = "tracker",
        needs = "tracker",
        groups = {
            {
                title = "What it shows",
                options = {
                    {
                        choiceKey = "trackerOrder",
                        label = "Order in a zone",
                        choices = {
                            {
                                value = "number",
                                label = "As tracked",
                                note = "In the order you tracked them: nothing moves as you walk.",
                            },
                            {
                                value = "distance",
                                label = "Nearest",
                                note = "The quest whose next place is nearest comes first; the order changes as you move.",
                            },
                            { value = "level", label = "By level", note = "Lowest level first." },
                            {
                                value = "progress",
                                label = "Most done",
                                note = "Ready to hand in first, then the quests closest to done.",
                            },
                        },
                    },
                    {
                        key = "shouldCollapseReady",
                        label = "Ready quests on one line",
                        note = 'Its title alone; the gold "?" says it is ready. The quest in focus keeps its lines.',
                    },
                    {
                        key = "shouldHideDoneObjectives",
                        label = "Hide objectives that are done",
                        note = "Only what is still to do is listed, in the tracker and on the quest's page.",
                        needs = "questLogOrTracker",
                    },
                    {
                        key = "shouldFlashProgress",
                        label = "Light up a quest when it moves on",
                        note = "Gold for progress, green when it is ready to hand in.",
                    },
                    {
                        key = "shouldPlayReadySound",
                        label = "Play a sound when a quest is ready",
                        note = "The game's own quest-complete sound.",
                    },
                    {
                        key = "shouldFocusAccepted",
                        label = "Focus quests you accept",
                        note = "The game puts a quest you accept into focus. Off: the quest you were on stays in focus.",
                        needs = false,
                    },
                    {
                        key = "shouldKeepUntracked",
                        label = "Quests you untrack stay untracked",
                        note = "The game tracks a quest whenever it moves on (an item picked up, a kill). On: only accepting a quest or tracking it yourself does.",
                        needs = false,
                    },
                },
            },
            {
                title = "Look and place",
                options = {
                    sizeOption(
                        "trackerScale",
                        "Size",
                        "Text and all. Larger suits a big or ultrawide screen at a small UI scale."
                    ),
                    {
                        stepKey = "trackerHeightShare",
                        label = "Height",
                        note = "The most of the screen it takes; past that it scrolls. The resize button on its title band sets it too.",
                        min = 0,
                        max = 0.9,
                        step = 0.1,
                        default = 0,
                        format = function(value)
                            return value <= 0 and ns.L("Auto") or string.format("%d%%", math.floor(value * 100 + 0.5))
                        end,
                    },
                    (function()
                        local option = sizeOption(
                            "trackerOpacity",
                            "Opacity",
                            "The whole tracker, its item buttons too. Lower lets more of the world show through.",
                            0.2,
                            1
                        )
                        return option
                    end)(),
                    {
                        choiceKey = "trackerBackground",
                        label = "Dark background",
                        note = "Easier to read over bright ground, leaves and snow.",
                        choices = {
                            {
                                value = "off",
                                label = "Off",
                                note = "Nothing behind the text: the world shows through.",
                            },
                            { value = "box", label = "Dark box", note = "All of the tracker on a dark ground." },
                            {
                                value = "bands",
                                label = "Soft bands",
                                note = "Dark only behind each zone and quest, fading out at the ends.",
                            },
                            {
                                value = "hover",
                                label = "On hover",
                                note = "The dark box while the pointer is on the tracker.",
                            },
                        },
                    },
                    (function()
                        local option = sizeOption(
                            "trackerBackgroundOpacity",
                            "Background opacity",
                            "How dark the ground behind it is.",
                            0.1,
                            1
                        )
                        option.default = 0.5
                        option.isAvailable = function()
                            return ns.Tracker.getBackgroundMode() ~= "off"
                        end
                        return option
                    end)(),
                    {
                        key = "isLocked",
                        label = "Lock in place",
                        note = "Unlocked, it moves by dragging its title. Its size: the resize button on the title band, shown on hover.",
                    },
                    {
                        label = "Position and size",
                        note = "Where it started, at the right of the screen, as wide and as tall as it was.",
                        buttonText = "Put back",
                        handleClick = resetTrackerPosition,
                    },
                },
            },
            {
                title = "Text",
                options = {
                    {
                        choiceKey = "trackerFont",
                        label = "Font",
                        isDropdown = true,
                        choices = ns.TrackerLook.FONTS,
                        getChoices = function()
                            return ns.TrackerLook.getFontChoices()
                        end,
                    },
                    {
                        choiceKey = "trackerOutline",
                        label = "Outline",
                        note = "A black edge round every letter: the easiest to read over grass, leaves and rock.",
                        choices = {
                            { value = "none", label = "None" },
                            { value = "thin", label = "Thin" },
                            { value = "thick", label = "Thick", note = "The boldest; a little heavy at small sizes." },
                        },
                    },
                    {
                        choiceKey = "trackerShadow",
                        label = "Shadow",
                        choices = {
                            { value = "off", label = "Off" },
                            { value = "soft", label = "Soft", note = "The game's own: a thin shadow down and right." },
                            { value = "strong", label = "Strong", note = "A darker shadow, further out." },
                        },
                    },
                    {
                        key = "isTrackerHighContrast",
                        label = "High-contrast text",
                        note = "White objectives and brighter titles.",
                    },
                    sizeOption("trackerTitleSize", "Title size", "The quests' titles."),
                    sizeOption("trackerTextSize", "Objective size", "Objectives, zones and the lines under a title."),
                },
            },
            {
                title = "In combat and dungeons",
                options = {
                    trackerMoment("trackerInCombat", "In combat"),
                    trackerMoment("trackerInDungeons", "In dungeons and raids"),
                },
            },
        },
    },
    {
        title = "Map and minimap",
        subtitle = "The picture follows what you switch.",
        icon = ICONS .. "INV_Misc_Spyglass_02",
        preview = "map",
        needs = "mapMarks",
        groups = {
            {
                title = "Marks",
                options = {
                    {
                        key = "shouldShowAvailableOnMap",
                        label = "Show quests you can pick up",
                        note = 'The "!" marks of quest givers. Off: the game\'s own marks for them show instead.',
                        needs = "mapMarksAndAvailable",
                    },
                    sizeOption(
                        "mapMarkScale",
                        "Size on the map",
                        "Quest marks and quest givers on the world map.",
                        0.5,
                        2
                    ),
                    {
                        key = "shouldHideMarksOnContinents",
                        label = "No marks on continent and world maps",
                        note = "Those maps stay clean; a zone's map shows everything.",
                    },
                    { key = "shouldShowMinimapPins", label = "Show quest marks on the minimap" },
                    (function()
                        local option = sizeOption("minimapMarkScale", "Size on the minimap", nil, 0.5, 2)
                        option.isAvailable = isSettingOn("shouldShowMinimapPins")
                        return option
                    end)(),
                    {
                        key = "shouldFadeMarksNearPlayer",
                        label = "Fade them over your arrow",
                        note = "So the arrow always shows.",
                        isAvailable = isSettingOn("shouldShowMinimapPins"),
                    },
                },
            },
            {
                title = "Your quests' marks",
                -- A quest in the log of a kind, on the map, the minimap, in the tracker and the log: the "!" and "?" stay
                -- the game's own (their colours under Quests to pick up)
                options = {
                    questMarkOption("Dungeon", "Dungeon quests"),
                    questMarkOption("Raid", "Raid quests"),
                    questMarkOption("PvP", "PvP quests"),
                    questMarkOption("Event", "Event quests"),
                    questMarkOption("Repeatable", "Repeatable quests"),
                    {
                        label = "As it was",
                        note = "The gold coin for every quest.",
                        buttonText = "Put back",
                        handleClick = usePlainMarks,
                    },
                },
            },
            {
                title = "Where objectives are",
                options = {
                    {
                        -- The areas round a quest's spawns. "Game's areas" is no look of ours but the game's own
                        -- markers, which is the Map marks switch off (At a glance): the tile shows that switch and
                        -- sets it, and picking a look of ours switches the marks on
                        choiceKey = "areaStyle",
                        label = "Areas",
                        needs = false,
                        handleChoose = function()
                            setMapMarks(true)
                        end,
                        choices = {
                            -- (one look of ours: there were two, a light one and a bold one, alike but for how
                            -- strong each was, which the two strengths below set)
                            {
                                value = "filled",
                                label = "Quest areas",
                                note = "Each quest's areas in its own colour, round where its creatures and things are, so the map under them stays readable. Spawns all in one spot get no area: the quest's mark stands on them.",
                            },
                            {
                                value = "none",
                                label = "No areas",
                                note = "Nothing round the spawns: the map stays clear, and the spawn markers alone show where to go.",
                            },
                            {
                                value = "game",
                                label = "Game's areas",
                                note = "The game's own quest markers and areas, nothing of OneMoreQuest's: the same as switching Map marks off.",
                                isChosen = function()
                                    return ns.settings.shouldShowMapPins ~= true
                                end,
                                choose = function()
                                    setMapMarks(false)
                                end,
                            },
                        },
                    },
                    -- How an area is drawn on the world map (MapMarks/World): ovals and soft shadows are a couple of
                    -- pictures an area; traced round the spawns, as it was, dozens of pieces
                    {
                        choiceKey = "areaGeometry",
                        label = "Drawn as",
                        note = "How each area is drawn on the map and the minimap.",
                        needs = false,
                        isAvailable = hasAreaLook,
                        choices = {
                            {
                                value = "soft",
                                label = "Shadows",
                                note = "A soft tinted shadow where each quest's spawns are, no rings and no lines: the quietest on the map and the lightest for the game to draw.",
                            },
                            {
                                value = "ovals",
                                label = "Ovals",
                                note = "An oval with a ring round each camp, and soft shadows where a quest's spawns are scattered.",
                            },
                            {
                                value = "traced",
                                label = "Traced",
                                note = "Each area traced round its spawns: the most exact, and by far the heaviest for the game to draw with many quests tracked.",
                            },
                        },
                    },
                    -- Shadows are one thing: how strong they are, and no more (they have no line round them, and
                    -- switched off they are "No areas")
                    hiddenUnless(
                        isShadowsOnly,
                        strengthOption(
                            "areaFillStrength",
                            "Shadow strength",
                            "How dark the shadows are: 100% is the look as it comes; the quest in focus stays the strongest.",
                            nil
                        )
                    ),
                    -- Ovals and traced areas: what of each is drawn, and how strongly (a share of the look chosen:
                    -- 100% is it as it comes); both off is the same as no areas
                    hiddenUnless(isNotShadowsOnly, {
                        key = "shouldFillAreas",
                        label = "Fill",
                        note = "Each area filled in its quest's colour. Off: the outlines alone.",
                        isAvailable = hasAreaLook,
                    }),
                    hiddenUnless(
                        isNotShadowsOnly,
                        strengthOption(
                            "areaFillStrength",
                            "Fill strength",
                            "100% is the look as it comes; the quest in focus stays the strongest.",
                            "shouldFillAreas"
                        )
                    ),
                    hiddenUnless(isNotShadowsOnly, {
                        key = "shouldOutlineAreas",
                        label = "Outline",
                        note = "A line round each area in its quest's colour. Off: the fill alone.",
                        isAvailable = hasAreaLook,
                    }),
                    hiddenUnless(
                        isNotShadowsOnly,
                        strengthOption(
                            "areaOutlineStrength",
                            "Outline strength",
                            "100% is the look as it comes.",
                            "shouldOutlineAreas"
                        )
                    ),
                    {
                        key = "shouldShowFocusedAreasOnly",
                        label = "Areas only for the quest in focus",
                        note = "The other quests keep their marks and spawn markers.",
                        isAvailable = function()
                            return ns.MapMarks.hasAreas() and ns.settings.shouldShowMapPins == true
                        end,
                    },
                },
            },
            {
                title = "Spawn markers",
                options = {
                    {
                        choiceKey = "spawnMarker",
                        label = "On each spawn",
                        note = "What stands where a quest's creatures and things are.",
                        choices = {
                            {
                                value = "glyph",
                                label = "Icons",
                                note = "What to do there, on a glow in the quest's colour: a sword to kill, a sack to loot, a hand to use, a speech bubble to talk.",
                            },
                            {
                                value = "plate",
                                label = "Plates",
                                note = "The same icons on small dark plates edged in the quest's colour: the plainest to read on a busy map.",
                            },
                            {
                                value = "game",
                                label = "Game's art",
                                note = "The game's own skull, chest and star, on a glow in the quest's colour.",
                            },
                            {
                                value = "square",
                                label = "Squares",
                                note = "A small square in the quest's colour on every spawn; round dots stay your party's.",
                            },
                            { value = "none", label = "None", note = "No markers: the quests' marks and areas alone." },
                        },
                    },
                    (function()
                        local option = sizeOption("spawnMarkerScale", "Size on the map", nil, 0.5, 2)
                        option.isAvailable = function()
                            return ns.settings.spawnMarker ~= "none" and ns.settings.shouldShowMapPins == true
                        end
                        return option
                    end)(),
                    (function()
                        local option = sizeOption("minimapSpawnMarkerScale", "Size on the minimap", nil, 0.5, 2)
                        option.isAvailable = function()
                            return ns.settings.spawnMarker ~= "none"
                                and ns.settings.shouldShowMapPins == true
                                and ns.settings.shouldShowMinimapPins == true
                        end
                        return option
                    end)(),
                    {
                        key = "shouldGlowSpawnMarkers",
                        label = "Glow in the quest's colour",
                        note = "Under the icons and the game's art. Off: the icons alone, plainer, and a quest's colour is told by its areas.",
                        isAvailable = function()
                            return (ns.settings.spawnMarker == "glyph" or ns.settings.spawnMarker == "game")
                                and ns.settings.shouldShowMapPins == true
                        end,
                    },
                    {
                        choiceKey = "otherSpawnMarkers",
                        label = "Quests not in focus",
                        note = "The markers of the tracked quests you are not on just now.",
                        isAvailable = function()
                            return ns.settings.spawnMarker ~= "none" and ns.settings.shouldShowMapPins == true
                        end,
                        choices = {
                            { value = "faded", label = "Fainter" },
                            { value = "full", label = "As the focused quest's" },
                            { value = "hidden", label = "Hidden" },
                        },
                    },
                },
            },
            {
                title = "Following",
                options = {
                    {
                        key = "shouldMapFollowPlayer",
                        label = "Turn the open map to the zone you walk into",
                        note = "Off: the map stays where you left it, as the game's own does.",
                        needs = false,
                    },
                    {
                        key = "shouldWaypointFocused",
                        label = "Waypoint on the focused quest",
                        note = "Moves with the quest's nearest place. TomTom's arrow when TomTom is installed, the game's own waypoint otherwise.",
                        needs = false,
                    },
                },
            },
        },
    },
    {
        title = "Quests to pick up",
        subtitle = "What the Available tab and the map offer.",
        icon = ICONS .. "INV_Misc_Note_01",
        needs = "available",
        groups = {
            {
                title = "Which quests",
                options = {
                    {
                        key = "shouldShowLowLevel",
                        label = "Include low-level quests",
                        note = "On the map, the minimap and in the Available list; the game's own on the minimap follow.",
                        handleToggle = setGameLowLevelTracking,
                    },
                    -- Left out, some are offered still for where their chain leads (Availability.getLeadInMode)
                    {
                        key = "shouldShowDungeonLeadIns",
                        label = "Still show those leading to a dungeon quest",
                        note = "A low quest whose chain leads to a dungeon's or a raid's quest in your range.",
                        isAvailable = function()
                            return ns.settings.shouldShowLowLevel ~= true
                        end,
                    },
                    {
                        key = "shouldShowAnyLeadIns",
                        label = "Still show those leading to any quest in range",
                        note = "Any chain that climbs into your range (takes in the one above).",
                        isAvailable = function()
                            return ns.settings.shouldShowLowLevel ~= true
                        end,
                    },
                    {
                        stepKey = "lowLevelGap",
                        label = "Low level means",
                        note = "Below you by more than this. Grey: as the game greys quests out.",
                        min = 0,
                        max = 15,
                        step = 1,
                        default = 0,
                        format = function(value)
                            return value == 0 and ns.L("Grey") or ns.Lp(value, "%d level", "%d levels")
                        end,
                        handleChange = function()
                            ns.Availability.invalidate()
                        end,
                        isAvailable = function()
                            return ns.settings.shouldShowLowLevel ~= true
                        end,
                    },
                    {
                        key = "shouldShowRepeatable",
                        label = "Include repeatable quests",
                        note = "Daily and repeatable hand-ins, and the cities' cloth donations.",
                    },
                    {
                        key = "shouldShowEvents",
                        label = "Include event quests",
                        note = "A holiday's or a world event's (the Darkmoon Faire, the Lunar Festival, Hallow's End...), only while it runs.",
                    },
                    {
                        key = "shouldShowRaid",
                        label = "Include raid quests",
                        note = "Quests for Molten Core, Onyxia's Lair, Zul'Gurub and the other raids.",
                    },
                    { key = "shouldShowPvp", label = "Include PvP quests", note = "Battleground quests." },
                    {
                        key = "shouldShowAQWarEffort",
                        label = "Include the Ahn'Qiraj War Effort quests",
                        note = "The realm-wide drive to open Ahn'Qiraj, over on every realm: its supply donations and the cities' Commendation Signets. Most are repeatable: they show with repeatable quests included.",
                    },
                },
            },
            {
                title = "Quest icons",
                -- Each kind's "!" and "?", on the maps and in the lists; a quest of two kinds takes the first that
                -- fits, in this order (MapMarks.ICON_KINDS)
                options = {
                    iconColourOption("Event", "Event quests", "A holiday's or a world event's."),
                    iconColourOption("Raid", "Raid quests", nil),
                    iconColourOption("Dungeon", "Dungeon quests", nil),
                    iconColourOption("PvP", "PvP quests", "A battleground's, or one the game marks PvP."),
                    iconColourOption(
                        "Repeatable",
                        "Repeatable quests",
                        "Dailies, cloth and other hand-ins done over and over."
                    ),
                    iconColourOption("LowLevel", "Low-level quests", 'Far below you: the "!" alone, as the game\'s.'),
                    iconColourOption("Normal", "Every other quest", nil),
                    {
                        label = "As the game has them",
                        note = 'Gold, a grey "!" far below your level, blue for repeatable quests.',
                        buttonText = "Put back",
                        handleClick = useGameIconColours,
                    },
                },
            },
            {
                title = "Hidden quests",
                options = {},
                -- The quests hidden with "Hide this quest", each with its button to bring it back (made as the page is
                -- drawn: they change as quests are hidden)
                getOptions = function()
                    local options = {}
                    for _, quest in ipairs(ns.QuestHiding.getHidden()) do
                        options[#options + 1] = {
                            label = quest.title,
                            note = quest.zoneName,
                            buttonText = "Show again",
                            handleClick = function()
                                ns.QuestHiding.unhide(quest.questId)
                            end,
                        }
                    end
                    return options
                end,
                footnote = 'Right-click a quest to pick up, in the Available list or its "!" on the map, and choose Hide this quest.',
            },
        },
    },
    {
        title = "Quest dialogs",
        subtitle = "Talking to quest givers, done for you.",
        icon = ICONS .. "INV_Letter_15",
        groups = {
            {
                title = "Done for you",
                options = {
                    {
                        key = "shouldAutoAccept",
                        label = "Accept quests as they are offered",
                        note = "Not grey (low-level) quests.",
                    },
                    {
                        key = "shouldAutoTurnIn",
                        label = "Hand quests in when they are ready",
                        note = "Not when there is a reward to choose, or the hand-in costs money.",
                    },
                },
                footnote = "Hold Shift as you talk to someone to answer yourself, that once.",
            },
        },
    },
    {
        title = "Group",
        subtitle = "Questing together.",
        icon = ICONS .. "INV_Misc_GroupNeedMore",
        groups = {
            {
                title = "Progress",
                options = {
                    {
                        key = "shouldShareProgress",
                        label = "Share quest progress with my group",
                        note = "Members with OneMoreQuest or Questie see your exact counts, in dungeons too. Theirs show either way.",
                    },
                },
            },
            {
                title = "Group chat",
                options = {
                    {
                        key = "shouldAnnounceReady",
                        label = "Say when a quest is ready",
                        note = 'In party or raid chat: "OneMoreQuest: [Quest] is ready to hand in".',
                    },
                    {
                        key = "shouldAnnounceObjectives",
                        label = "Say when an objective is done",
                        note = '"OneMoreQuest: Packaged Tonics 1/1 for [Quest]". Left to Questie while Questie announces objectives itself.',
                    },
                    {
                        key = "shouldAnnounceSolo",
                        label = "Show them to me when I play alone",
                        note = "Outside a group the same lines appear only in your own chat window.",
                        isAvailable = function()
                            return ns.settings.shouldAnnounceReady == true
                                or ns.settings.shouldAnnounceObjectives == true
                        end,
                    },
                },
            },
        },
    },
    {
        title = "Kills and profit",
        subtitle = "What creatures give your quests, and what a quest is worth.",
        icon = ICONS .. "INV_Misc_Coin_01",
        preview = "nameplate",
        groups = {
            {
                title = "Creatures",
                options = {
                    {
                        key = "shouldShowNameplateIcons",
                        label = "Quest icons on nameplates",
                        note = "A sword over a creature your quests still need killed, a sack over one that drops what they still need.",
                    },
                    {
                        choiceKey = "nameplateIconSide",
                        label = "Where on the nameplate",
                        isAvailable = isSettingOn("shouldShowNameplateIcons"),
                        choices = {
                            { value = "left", label = "Left", note = "Before the name and the bar." },
                            { value = "top", label = "Above", note = "Over the name." },
                            { value = "right", label = "Right", note = "After the bar." },
                        },
                    },
                    (function()
                        local option = sizeOption("nameplateIconScale", "Size on the nameplate", nil, 0.5, 2)
                        option.isAvailable = isSettingOn("shouldShowNameplateIcons")
                        return option
                    end)(),
                    {
                        key = "shouldShowUnitQuests",
                        label = "Quest drops on their tooltips",
                        note = "Hovering a creature, or your target's portrait, shows the quest items it drops with their chances, and the kills it counts for.",
                    },
                    {
                        key = "shouldCountKills",
                        label = "Count kills for drops",
                        note = "A bar under each drop objective: your kills against the kills an average player needs for the same drops.",
                    },
                },
            },
            {
                title = "Profit",
                options = {
                    {
                        key = "shouldShowProfit",
                        label = "Show what a quest is worth",
                        note = "An estimate (~): its money, best reward item, and loot from the kills left.",
                    },
                    {
                        key = "shouldUseAuctionPrices",
                        label = "Use auction prices",
                        note = "From the Auctionator addon; without it, vendor prices are used.",
                        isAvailable = isSettingOn("shouldShowProfit"),
                    },
                },
            },
        },
    },
    {
        title = "About",
        subtitle = "Version, data and credits.",
        icon = ICONS .. "INV_Misc_Book_07",
        kind = "about",
    },
}

---@return table[] options Every option of a section, group by group
function SettingsPage.getOptions(section)
    local options = {}
    for _, group in ipairs(section.groups or { { options = section.options or {} } }) do
        for _, option in ipairs(group.options) do
            options[#options + 1] = option
        end
    end
    return options
end

-- A section's need is each of its settings' need, unless the setting says its own
for _, section in ipairs(SettingsPage.SECTIONS) do
    for _, group in ipairs(section.groups or {}) do
        for _, option in ipairs(group.options) do
            if option.needs == nil then
                option.needs = section.needs or false
            end
        end
    end
end

---@return boolean isAvailable The option can be used now: what it needs is on (the part of the addon it belongs to,
---and the setting it stands under)
function SettingsPage.isAvailable(option)
    local need = option.needs and NEEDS[option.needs]
    if need and not need.isMet() then
        return false
    end
    return option.isAvailable == nil or option.isAvailable() == true
end

---@return table? part The part of the addon (one of REPLACEMENTS) a section's settings are for, while it is switched
---off: they do nothing until it is on
function SettingsPage.getSwitchedOffPart(section)
    local need = section.needs and NEEDS[section.needs]
    return need and not need.isMet() and need.part or nil
end

---@return boolean isOn The switch is on: its setting, or every one of its settings, is on
function SettingsPage.isOn(option)
    for _, key in ipairs(option.keys or { option.key }) do
        if ns.settings[key] ~= true then
            return false
        end
    end
    return true
end

---Flips a switch: its setting, or all its settings together, and carries the change out.
function SettingsPage.toggle(option)
    local isOn = not SettingsPage.isOn(option)
    for _, key in ipairs(option.keys or { option.key }) do
        ns.settings[key] = isOn
    end
    if option.handleToggle then
        option.handleToggle(isOn) -- (what else follows the switch, once, as it is flipped)
    end
    SettingsPage.apply()
end

---The game's own quest log, tracker and quest markers, in place of this addon's.
function SettingsPage.useGameOwn()
    for _, option in ipairs(REPLACEMENTS) do
        for _, key in ipairs(option.keys or { option.key }) do
            ns.settings[key] = false
        end
    end
    ns.settings.shouldWaypointFocused = false
    SettingsPage.apply()
    ns.print(
        ns.L(
            "everything is back to the game's own. To bring it back: Options, AddOns, %s, or /omq settings.",
            ns.ADDON_TITLE
        )
    )
end

---Carries a changed setting out everywhere it matters.
function SettingsPage.apply()
    -- A new language is told to everything that speaks or draws in it (fonts with Czech letters, translation addons,
    -- lists that hold words), however it was set; that comes back here once, with nothing new
    if ns.Locale.applyLanguage() then
        return
    end
    ns.Profit.reset() -- prices may count differently now
    ns.BlizzardTracker.apply()
    ns.Log.applyBinding()
    if not ns.settings.shouldReplaceQuestLog then
        ns.MapDock.restoreBuiltInPanel()
    end
    ns.MapPins.applyGameFilter(true) -- the game's own "Quest Objectives" map filter follows the Map marks switch
    ns.MapDock.apply() -- also draws the window border chosen
    ns.Tracker.refresh() -- the waypoint on the focused quest follows the switch at once
    ns.Nameplates.refresh()
    ns.queueRefresh()
end

local frame, category

---Builds the short page in the game's settings window.
function SettingsPage.create()
    if frame or not Settings or not Settings.RegisterCanvasLayoutCategory then
        return
    end
    frame = CreateFrame("Frame", "OneMoreQuestSettings", UIParent)
    frame:Hide()

    local title = ns.Widgets.createFontString(frame, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
    title:SetText(ns.ADDON_TITLE)
    local text = ns.Widgets.createFontString(frame, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    text:SetWidth(520)
    text:SetJustifyH("LEFT")

    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(200, 24)
    button:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
    button:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
            HideUIPanel(SettingsPanel) -- the panels open beside the map, which this window would cover
        end
        ns.Log.openSettings()
    end)

    -- With the panels off there is no cog to click: these switches are the way back
    local checks, labels = {}, {}
    local previous = button
    for index, option in ipairs(REPLACEMENTS) do
        local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", index == 1 and -4 or 0, index == 1 and -14 or -4)
        local label = ns.Widgets.createFontString(check, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        check:SetScript("OnClick", function()
            SettingsPage.toggle(option)
            frame.updateControls()
        end)
        checks[index], labels[index] = check, label
        previous = check
    end

    -- Words set on every showing, so a change of the addon's language shows here too
    local function updateControls()
        text:SetText(
            ns.L(
                "%s's settings are on its quest panels beside the map: the cog in their title opens them.",
                ns.ADDON_TITLE
            )
        )
        ns.Widgets.setButtonFonts(button) -- the game's button fonts lack Czech letters
        button:SetText(ns.L("Open %s settings", ns.ADDON_TITLE))
        for index, option in ipairs(REPLACEMENTS) do
            labels[index]:SetText(ns.L(option.label))
            checks[index]:SetChecked(SettingsPage.isOn(option))
        end
        button:SetEnabled(ns.settings.shouldReplaceQuestLog == true)
    end
    frame.updateControls = updateControls
    updateControls()
    frame:SetScript("OnShow", updateControls)
    frame.OnRefresh = updateControls -- the settings window asks pages to show their current values
    frame.OnDefault = function()
        ns.resetSettings()
        updateControls()
        SettingsPage.apply()
    end

    category = Settings.RegisterCanvasLayoutCategory(frame, ns.ADDON_TITLE)
    if category and Settings.RegisterAddOnCategory then
        Settings.RegisterAddOnCategory(category)
    end
end

---Opens OneMoreQuest's settings: on the quest panels, or, while the panels are off, the short page in the game's
---settings window, where they can be switched back on.
---@return boolean isOpened False when neither can be shown right now
function SettingsPage.open()
    if ns.Log.openSettings() then
        return true
    end
    if not category or not Settings.OpenToCategory or InCombatLockdown() then
        return false
    end
    Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
    return true
end

ns.on("LANGUAGE_CHANGED", SettingsPage.apply) -- the game's settings panel names its switches in the language
ns.registerModule({ name = "SettingsPage", create = SettingsPage.create })
