local addonName, ns = ...

-- The addon's core: its frames' CreateFrame, the settings (their defaults and their loading from the saved file),
-- the modules every other file registers and the moments Core runs them at (login, the game's events, the redraw of
-- everything shared out over frames, every second), the messages between modules, and the /omq command.

-- The name players see; the addon's folder and its frames (OneMoreQuestLog, OneMoreQuestTracker) are named the same.
ns.ADDON_TITLE = "OneMoreQuest"
ns.ADDON_FOLDER = addonName -- for asking the game about this addon (its version), whatever the folder is called

---@return boolean isInPanel The frame is inside a window the game's gamepad navigation has open (SmartNavigation's
---active panels, up to UIParent)
local function isInNavigationPanel(frame)
    local navigation = _G.SmartNavigation
    local panels = type(navigation) == "table" and rawget(navigation, "activePanels")
    if type(panels) ~= "table" or #panels == 0 then
        return false
    end
    local root = _G.UIParent
    while frame and frame ~= root do
        for _, info in ipairs(panels) do
            if info.frame == frame then
                return true
            end
        end
        frame = frame.GetParent and frame:GetParent()
    end
    return false
end

---CreateFrame for all of OneMoreQuest's frames (each file takes it as its CreateFrame). In the game's gamepad interface
---the gamepad navigation hooks CreateFrame: a frame made with a parent inside an open window has that window's buttons
---looked over again within the caller's own run, an addon's, which taints the window's navigation; the game then
---refuses its own calls (closing the map: SetPreferredGamepadInteractTarget, "blocked from an action"). Such a frame is
---made without a parent and given it after, which the hook does not watch (as SpokenQuests found, its PR #87).
function ns.CreateFrame(frameType, name, parent, template, id)
    local create = _G.CreateFrame
    if parent and isInNavigationPanel(parent) then
        local frame = create(frameType, name, nil, template, id)
        frame:SetParent(parent)
        return frame
    end
    return create(frameType, name, parent, template, id)
end
local CreateFrame = ns.CreateFrame

local DEFAULT_SETTINGS = {
    isShown = true,
    shouldShowUnitQuests = true, -- a creature's tooltip lists the quest items it drops (with chances) and kills it counts for
    isLocked = false,
    trackerScale = 1, -- the tracker's size, text included: larger on a big or ultrawide screen at a small UI scale
    trackerWidth = 260, -- how wide the tracker is, set by dragging the grip at its title's left end
    trackerHeightShare = 0, -- the most of the screen's height the tracker takes (the grip under it); 0: as much as fits
    windowScale = 1, -- the quest window's size, text included, beside the map
    diagramTreeWidth = 0, -- the quest diagram's window as the player sized it (its tree's width, its height);
    diagramHeight = 0, -- 0: its usual size (numbers, as saved: a setting of another kind is put back at login)
    mapSize = 1, -- the windowed map's size, a share of the game's own (the grip at the quest window's corner)
    pageStretch = 0, -- how much wider than usual the quest window's page is, set by the grip at its corner
    windowExtraHeight = 0, -- how much taller than the map beside it the quest window is (the same grip)
    trackerOrder = "number", -- quests in a tracker zone: as tracked ("number"), "distance", "level" or "progress"
    shouldCollapseReady = false, -- a quest ready to hand in is its title alone in the tracker
    shouldHideDoneObjectives = false, -- the tracker lists only objectives still to do
    shouldShowTrackerBackground = false, -- the dark ground's old switch: read once into trackerBackground
    trackerBackground = "off", -- a dark ground behind the tracker: "off", "box", "bands" (behind each quest) or "hover"
    trackerBackgroundOpacity = 0.5, -- how dark that ground is (0.1 to 1)
    trackerFont = "game", -- the tracker's font (TrackerLook.FONTS, or "lsm:<name>" from SharedMedia)
    trackerOutline = "thin", -- a black edge round its letters: "none", "thin" or "thick"
    trackerShadow = "soft", -- its letters' shadow: "off", "soft" or "strong"
    isTrackerHighContrast = false, -- brighter colours: white objectives, brighter titles
    trackerTitleSize = 1, -- the quests' titles, times the game's size
    trackerTextSize = 1, -- objectives, zones and the lines under a title, times the game's size
    trackerFilter = "all", -- what the tracker lists: "all", "here" (the zone the player is in), "ready" or "focus"
    trackerOpacity = 1, -- the whole tracker, text and item buttons too (0.2 to 1): lower lets the world show through
    trackerInCombat = "show", -- the tracker in combat: "show", "fold" (to its title) or "hide"
    trackerInDungeons = "show", -- the same in a dungeon or raid
    mapMarkScale = 1, -- the world map's marks, times their size
    minimapMarkScale = 1, -- the minimap's marks, times their size
    shouldShowFocusedAreasOnly = false, -- areas drawn only for the quest in focus
    shouldFadeMarksNearPlayer = false, -- minimap marks over the player's arrow faded
    shouldHideMarksOnContinents = false, -- continent and world maps without marks
    shouldShowNameplateIcons = true, -- an icon on the nameplate of a creature your quests still need
    nameplateIconSide = "left", -- where on the nameplate: "left", "top" or "right"
    nameplateIconScale = 1, -- its size
    shouldAutoAccept = false, -- quests offered are accepted (Shift held: the player answers)
    shouldAutoTurnIn = false, -- ready quests are handed in when there is no reward to choose
    shouldKeepUntracked = false, -- a quest moving on is not tracked by it (the game's way, kept when off): QuestState
    lowLevelGap = 0, -- levels below the player past which a quest is low-level; 0: as the game greys them out
    shouldShowDungeonLeadIns = true, -- low-level quests still offered when their chain leads to a dungeon's (or a raid's) quest in range
    shouldShowAnyLeadIns = false, -- ... or to any quest in range (takes in the one above)
    shouldHideBuiltInTracker = true,
    collapsedZones = {}, -- [zoneId] = true or false; zones the player opened or closed by hand
    isTrackerFolded = false, -- the tracker folded away to its title, by its "-" button
    collapsedLogZones = {}, -- the same for the quest log window
    cycledQuestZones = {}, -- [questId] = the zone last shown by clicking a quest's "Also in" line; the map returns to it
    focusedQuestIds = {}, -- [character] = the quest that character put in focus
    shouldReplaceQuestLog = true, -- the map and quest log keys open the map with this addon's quest panels
    arePanelsHidden = false, -- the quest panels folded away by the arrow on the map, leaving the map alone
    shouldShowLowLevel = false,
    shouldShowRepeatable = false,
    areaGeometry = "soft", -- how an area is drawn on the maps: soft shadows alone ("soft"), an oval with a ring round each group of spawns ("ovals"), both a couple of pictures an area; or traced round the spawns, many pieces ("traced")
    areaStyle = "filled", -- the areas round each quest's spawns, in its colour ("filled"), or "none"
    shouldFillAreas = true, -- the areas filled in the quest's colour (off: their outlines alone)
    shouldOutlineAreas = true, -- a line round each area in the quest's colour (off: the fill alone)
    areaFillStrength = 1, -- how strongly they are filled and outlined, against the look as it comes (0.1 to 2)
    areaOutlineStrength = 1,
    spawnMarker = "glyph", -- what stands on each spawn: what to do there on a glow ("glyph") or on a dark plate ("plate"), the game's own art ("game"), a small square ("square"), or "none"
    spawnMarkerScale = 1, -- the spawn markers' size on the world map, against their usual one
    minimapSpawnMarkerScale = 1, -- and on the minimap
    shouldGlowSpawnMarkers = true, -- a glow in the quest's colour under a glyph or the game's art
    otherSpawnMarkers = "faded", -- the markers of quests not in focus: fainter ("faded"), as strong as the focused quest's ("full"), or "hidden"
    windowBorder = "map", -- the frame round the quest panels: "map" (like the map's), "game", "gold" or "flat"
    questDetails = "beside", -- the open quest's page "beside" the list, or on a page of its "own" in the list's place (the window one pane wide)
    logGrouping = "step", -- quests in the log and the tracker grouped by where their next step is ("step"), or where picked up ("pickup")
    shouldShowPvp = false,
    shouldShowEvents = true, -- a holiday's or a world event's quests, while it runs (Events)
    shouldShowRaid = true, -- quests for a raid
    shouldShowAQWarEffort = false, -- the Ahn'Qiraj War Effort's quests (over on every realm), as Questie: only when asked for
    -- Each kind of quest's "!" and "?" (MapMarks.ICON_KINDS): "gold", "blue", "green", "orange", "purple", "pink", "red", "grey"
    questIconEvent = "green",
    questIconRaid = "orange",
    questIconDungeon = "gold",
    questIconPvP = "red",
    questIconRepeatable = "blue",
    questIconLowLevel = "grey",
    questIconNormal = "gold",
    -- A quest in the log, of a kind: its coin as it is ("plain"), in the kind's colour ("colour"), struck with the kind's
    -- own icon in place of what to do ("icon"), or both ("both") (MapMarks.MARK_KINDS)
    questMarkEvent = "plain",
    questMarkRaid = "plain",
    questMarkDungeon = "plain",
    questMarkPvP = "plain",
    questMarkRepeatable = "plain",
    shouldShowProfit = true,
    shouldSuggestDrops = true, -- the box over the quest list, as the log fills up, naming the quests worth abandoning
    shouldUseAuctionPrices = true, -- only has an effect with the Auctionator addon installed
    shouldShowMapPins = true,
    shouldUseAvailableQuests = true, -- the Available tab and this addon's marks for quests to pick up
    shouldShowAvailableOnMap = true,
    areMapGiversHidden = false, -- the "!" button on the map: quest givers' marks hidden there (not on the minimap)
    shouldHideBuiltInMapPins = true, -- the game's quest markers that this addon's pins replace
    shouldShowMinimapPins = true, -- the quest marks on the minimap, besides those on the world map
    shouldMapFollowPlayer = true, -- an open world map turns to the zone the player walks into
    shouldFlashProgress = true, -- the tracker lights a quest up when it moves on
    shouldPlayReadySound = true, -- the game's sound when a quest is ready to hand in
    shouldFocusAccepted = true, -- a quest just accepted goes into focus, as the game puts it (Focus)
    shouldWaypointFocused = false, -- keep a waypoint (TomTom's, or the game's) on the focused quest's nearest place
    shouldCountKills = true, -- a bar under each drop objective: kills so far against the kills expected
    shouldShareProgress = true, -- send quest counts to the group (OneMoreQuest's channel and Questie's)
    shouldAnnounceReady = false, -- say in group chat when a quest is ready to hand in (the player's choice: off at first)
    shouldAnnounceObjectives = false, -- say in group chat when an objective is done
    shouldAnnounceSolo = false, -- show those lines in the player's own chat when not in a group
    killCounts = {}, -- [character] = { [questId] = { [objective] = { kills, knownKills, chanceSum, startFulfilled } } }
    missedQuests = {}, -- [questId] = { title, zoneId, reason }: quests the game offered that the lists missed
    questsNotInGame = {}, -- [game build] = { [questId] = true }: quests the database knows that the game said it has not
    hasAnsweredQuestie = false, -- the player answered whether to turn Questie off, so it is not asked again
    hasAnsweredMapUtils = false, -- the same for MapUtils' own quest givers and turn-ins
    language = "en", -- the addon's own words: "en" or "cs" (the game has no Czech client; names from the game stay)
}

local REFRESH_EVENTS = {
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "ZONE_CHANGED",
    "ZONE_CHANGED_NEW_AREA",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LEVEL_UP",
    "GROUP_ROSTER_UPDATE",
    "BAG_UPDATE_DELAYED",
    "GET_ITEM_INFO_RECEIVED", -- an item's details arrived, so a price that was waiting can be worked out
    "QUEST_DATA_LOAD_RESULT", -- the game answered a request for a quest's details, such as its rewards
}

-- Data the game sends in bursts (hundreds of items' details after login or a loot): drawn once they settle, and not
-- at all when a redraw for something else came after the last of them
local SLOW_REFRESH_EVENTS = { GET_ITEM_INFO_RECEIVED = true, QUEST_DATA_LOAD_RESULT = true }
-- The quest log saying it changed, which most often is a kill or a loot counted: a redraw asked for by nothing
-- else is a quiet one (Module.refresh), and what follows only which quests there are and where they stand, the
-- maps' marks, may stay as drawn. (A change of the bags redraws only for an item that matters: never quiet.)
local QUIET_REFRESH_EVENTS = { QUEST_LOG_UPDATE = true }
local SLOW_REFRESH_DELAY_SECONDS = 0.5

local REFRESH_DELAY_SECONDS = 0.1

local POSITION_REFRESH_SECONDS = 1

ns.addonName = addonName
ns.settings = {}

-- The frames drawn so far. What the game is asked many times within one frame (where the player stands, the quests
-- of the log, the quests tracked) is read once and shared while this number stays the same. It stays 0 where no
-- frames run (the tests), which turns that sharing off: every call reads afresh there.
ns.frameNumber = 0
if CreateFrame then
    local frameCounter = CreateFrame("Frame")
    if frameCounter and frameCounter.SetScript then
        frameCounter:SetScript("OnUpdate", function()
            ns.frameNumber = ns.frameNumber + 1
        end)
    end
end

-- What OneMoreQuest costs, and its errors kept: Core/Timing.lua (loaded first)
local Timing = ns.Timing

---@return boolean isLoaded The addon of that folder name is loaded and running
function ns.isAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name) == true
    end
    return IsAddOnLoaded ~= nil and IsAddOnLoaded(name) == true
end

function ns.print(message)
    print("|cffffd100" .. ns.ADDON_TITLE .. "|r: " .. message)
end

-- Answers the player gave once, kept by a reset (or the questions would be asked again at the next login)
local KEPT_BY_RESET = { hasAnsweredQuestie = true, hasAnsweredMapUtils = true }

---Puts every switch back to its default. Remembered things that are not switches (the highlighted quest of
---each character, zones folded by hand, the answers to the questions asked once) are kept.
function ns.resetSettings()
    for key, value in pairs(DEFAULT_SETTINGS) do
        if type(value) ~= "table" and not KEPT_BY_RESET[key] then
            ns.settings[key] = value
        end
    end
    ns.settings.position = nil
end

-- The looks there were before the areas and the spawn markers became two choices: what each is now
local OLD_AREA_STYLES = {
    icons = { "filled", "glyph" }, -- "Icons and areas"
    spawns = { "none", "glyph" }, -- "Icons only"
    shapes = { "filled", "none" }, -- "Shapes": areas alone (the bold look there was: its strengths, below)
    dots = { "none", "square" }, -- "Squares"
}

-- The steps a saved table goes through as it loads (SETTINGS_LOAD_STEPS, in order): each takes the settings and
-- changes them in place.

---A setting of the wrong kind (words where a number goes) is dropped, so the default takes its place.
local function dropMistypedSettings(settings)
    for key, value in pairs(DEFAULT_SETTINGS) do
        if settings[key] ~= nil and type(settings[key]) ~= type(value) then
            settings[key] = nil
        end
    end
end

---The dark ground was one switch: on, it is the whole box now.
local function migrateTrackerBackground(settings)
    if settings.trackerBackground == nil and settings.shouldShowTrackerBackground == true then
        settings.trackerBackground = "box"
    end
end

---PvP quests' colour, new: a player who had every quest's colour as the game has them (gold, a grey "!" far below,
---blue repeatable: "As the game has them") gets PvP gold as well, not the red it starts with.
local function migratePvpIconColour(settings)
    if
        settings.questIconPvP == nil
        and settings.questIconNormal ~= nil
        and settings.questIconEvent == "gold"
        and settings.questIconRaid == "gold"
        and settings.questIconDungeon == "gold"
        and settings.questIconNormal == "gold"
    then
        settings.questIconPvP = "gold"
    end
end

---The looks of before the areas and the spawn markers became two choices, made those two choices.
local function migrateOldAreaStyles(settings)
    local old = OLD_AREA_STYLES[settings.areaStyle]
    local wasBold = settings.areaStyle == "blob" or settings.areaStyle == "shapes"
    if old then
        settings.areaStyle = old[1]
        settings.spawnMarker = settings.spawnMarker or old[2]
    end
    if wasBold then
        -- "Shapes", the bold look, is the one look of areas now, as strong as it was: its fill and its outline were
        -- so many times the light look's, and the two strengths say that (up to the most they go to)
        settings.areaStyle = "filled"
        settings.areaFillStrength = math.min(2, (tonumber(settings.areaFillStrength) or 1) * 2)
        settings.areaOutlineStrength = math.min(2, (tonumber(settings.areaOutlineStrength) or 1) * 1.6)
    end
end

---Every setting the saved table lacks takes its default; a table default starts out empty.
local function fillDefaults(settings)
    for key, value in pairs(DEFAULT_SETTINGS) do
        if settings[key] == nil then
            settings[key] = type(value) == "table" and {} or value
        end
    end
end

---"Game's areas" used to be a look of this addon's marks; it is the game's own markers now, which is the map marks
---switched off.
local function migrateGameAreaStyle(settings)
    if settings.areaStyle == "game" then
        settings.areaStyle = DEFAULT_SETTINGS.areaStyle
        settings.shouldShowMapPins, settings.shouldHideBuiltInMapPins = false, false
    end
end

local SETTINGS_LOAD_STEPS = {
    dropMistypedSettings,
    migrateTrackerBackground,
    migratePvpIconColour,
    migrateOldAreaStyles,
    fillDefaults,
    migrateGameAreaStyle,
}

---Fills in the settings a saved table lacks. Table defaults start out empty. A damaged saved file (the whole of it not
---a table, or a setting of the wrong kind: words where a number goes) once stopped the addon loading: what is not
---of its default's kind is put back to the default, the rest kept. Older versions' settings are moved to what they
---are now (SETTINGS_LOAD_STEPS).
function ns.loadSettings(savedSettings)
    local settings = type(savedSettings) == "table" and savedSettings or {}
    for _, step in ipairs(SETTINGS_LOAD_STEPS) do
        step(settings)
    end
    ns.settings = settings
    if ns.Locale and ns.Locale.noteLoaded then
        ns.Locale.noteLoaded() -- the language the addon starts in: nothing to tell of it
    end
    return settings
end

local isRefreshQueued = false
local isLoggedIn = false

---------------------------------------------------------------------------------------------------------------
-- Modules: each takes part in the addon's life by registering, at the end of its own file, what it does at each
-- moment. Core runs them in the order they register, which is the TOC's.

---@class Module
---@field name string
---@field create fun()? At login, once every addon has loaded
---@field needsWorldMap boolean? Its create needs the world map: run again when the map loads after login
---@field invalidate fun(isQuiet: boolean?)? Before a redraw: forget what was worked out (lists, prices). isQuiet as
---for refresh, of the redraw as a whole
---@field refresh fun(isQuiet: boolean?)? The redraw after a change of quests, zone or settings. isQuiet: nothing
---asked for it since the module last drew but the quest log saying it changed (a kill or a loot counted, most
---often): a module whose drawing follows only what the quests are, not how far along, may keep what it has
---@field isLoudPending boolean? Set here: something other than the quest log's own news asked for the next redraw
---@field tick fun()? Every second, as the player moves
---@field afterCombat fun()? Once a fight is over (frames the game protects in combat can move again)
---@field events table<string, fun(...)>? Game events and their handlers; a quest event redraws everything after
---@field changes table<string, fun(...): boolean>? For a frequent event that redraws: whether it changed what the
---module reads (the quest log, the zone, the group). When every module that checks an event says no, it does not redraw
---@field prune fun(isInLog: table<number, boolean>?)? Keeps the saved file small: drops what was kept for quests
---done with. isInLog is nil while the quest log may not have been read yet.
local modules = {}

---@param module Module
function ns.registerModule(module)
    modules[#modules + 1] = module
end

---@return Module[] modules Every registered module, in order (to read, for tests and diagnostics)
function ns.getModules()
    return modules
end

---Hands an error in a module's part to the game's error handler (its popup, an error addon, the error log kept
---above), from inside the failed call, so the handler still sees where it happened.
local function reportModuleError(message)
    local handler = geterrorhandler and geterrorhandler()
    if handler then
        handler(message)
    end
    return message
end

---Runs one part of a module so that its failing does not stop what comes after it: one broken module once stopped
---every module after it (their create at login, their redraw, their events). The error is reported as any other is.
---Where the game has no error handler (the tests), the error goes on up as it is.
---@return boolean isFine
---@return any result The part's first result, when it ran through
local function callSafely(fn, ...)
    if not geterrorhandler then
        return true, fn(...)
    end
    return xpcall(fn, reportModuleError, ...)
end
ns.callSafely = callSafely

-- What OneMoreQuest did last (its events, its modules' moments, its messages, measured parts, the gamepad's presses):
-- a ring of names with their time, read when something goes wrong to tell what ran just before it (the gamepad's
-- taint watch, Gamepad.lua). A name and a number put in place each time: no garbage.
local ACTIVITY_KEPT = 60
local activityNames, activityTimes, activityNext = {}, {}, 1

function ns.noteActivity(name)
    activityNames[activityNext], activityTimes[activityNext] = name, GetTime and GetTime() or 0
    activityNext = activityNext % ACTIVITY_KEPT + 1
end

---@return string text The activity kept, oldest first, each line its time and name
function ns.getActivityText()
    local lines = {}
    for step = 0, ACTIVITY_KEPT - 1 do
        local index = (activityNext - 1 + step) % ACTIVITY_KEPT + 1
        if activityNames[index] then
            lines[#lines + 1] = string.format("%.2f %s", activityTimes[index], tostring(activityNames[index]))
        end
    end
    return table.concat(lines, "\n")
end

---Runs one moment's handler of every module that has one, in order.
local function runModules(moment, ...)
    for _, module in ipairs(modules) do
        if module[moment] then
            if moment ~= "tick" then
                ns.noteActivity(moment) -- (the module's name only matters with the moment: kept cheap)
            end
            if Timing.isRecording then
                Timing.measure(moment .. " " .. module.name, callSafely, module[moment], ...)
            else
                callSafely(module[moment], ...)
            end
        end
    end
end

-- Messages: a module announces a change it made, and those it concerns act on it, without the announcer knowing
-- them. ns.on("LANGUAGE_CHANGED", handler); ns.emit("LANGUAGE_CHANGED").
--   LANGUAGE_CHANGED    the addon's language changed
--   QUEST_FACTS_CHANGED what is known of quests changed (one handed in, one the game says it has not)
--   QUEST_TEXT_CHANGED  a translation addon's quest texts changed (switched on or off, another language)
local listeners = {}

function ns.on(message, handler)
    listeners[message] = listeners[message] or {}
    table.insert(listeners[message], handler)
end

function ns.emit(message, ...)
    ns.noteActivity(message)
    for _, handler in ipairs(listeners[message] or {}) do
        if Timing.isRecording then
            Timing.measure("message " .. message, callSafely, handler, ...)
        else
            callSafely(handler, ...) -- (one listener failing leaves the others told)
        end
    end
end

---Events arrive in bursts, so they share one redraw of everything.
local queueRefresh
local refreshCount, countAtLastArrival, isSlowRefreshQueued = 0, 0, false -- redraws so far; the slow lane's state
---@return table records The part of a saved setting that belongs to this character, created on first use: for
---what differs between characters (kills counted, quests givers offered)
function ns.getCharacterRecords(settingKey)
    local key = (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
    -- (a damaged saved file may hold something else there: started afresh)
    if type(ns.settings[settingKey]) ~= "table" then
        ns.settings[settingKey] = {}
    end
    local records = ns.settings[settingKey]
    if type(records[key]) ~= "table" then
        records[key] = {}
    end
    return records[key]
end

local RETIRED_SETTINGS = { "markStyle", "minimapIcon", "shouldShowMinimapButton", "respawns", "respawnLog" } -- settings of looks since removed
local TIDY_DELAY_SECONDS = 15 -- after login, once the quest log is surely read

---Keeps the saved file small: what earlier versions saved and nothing reads any more goes, and what was kept for
---a quest goes once the quest is done with. Only with the quest log read, so nothing is dropped for a quest that
---merely was not loaded yet.
function ns.tidySavedData()
    local settings = ns.settings
    for _, key in ipairs(RETIRED_SETTINGS) do
        settings[key] = nil
    end
    -- Each module prunes its own: an empty log may be one not read yet, and then nothing kept for quests in the
    -- log is dropped
    local logQuestIds = ns.QuestState.getLogQuestIds()
    local isInLog
    if #logQuestIds > 0 then
        isInLog = {}
        for _, questId in ipairs(logQuestIds) do
            isInLog[questId] = true
        end
    end
    runModules("prune", isInLog)
end

---Something other than the quest log's own news asks for the redraw: every module draws in full, also the ones
---that keep what they have at a mere count going up (Module.refresh's isQuiet).
local function markLoud()
    for _, module in ipairs(modules) do
        module.isLoudPending = true
    end
end

function ns.queueRefresh()
    Timing.noteCause("everything redrawn")
    markLoud()
    queueRefresh()
end

local REFRESH_SHARE_MILLISECONDS = 3 -- a frame's share of a redraw of everything: past it, the rest waits a frame

---The redraw of everything, shared out over frames. The tracker, the quest window, the map's marks and the minimap
---are each thousands of calls into the game: all in one frame they were a hitch at every kill that counted. Each
---module is drawn in turn; once a frame has spent its share, the modules left are drawn in the next. A newer redraw
---takes over from one still under way (it draws everything anyway). Where the game gives no clock (the tests), all
---at once.
local function runRefreshes()
    local generation = refreshCount
    local index = 0
    local function step()
        if generation ~= refreshCount then
            return
        end
        local started = debugprofilestop and debugprofilestop() or nil
        while index < #modules do
            index = index + 1
            local module = modules[index]
            if module.refresh then
                -- (loud until it has drawn once since: a redraw taken over by a newer one leaves its modules loud)
                local isQuiet = not module.isLoudPending
                module.isLoudPending = nil
                if Timing.isRecording then
                    Timing.measure("refresh " .. module.name, callSafely, module.refresh, isQuiet)
                else
                    callSafely(module.refresh, isQuiet)
                end
                if started and index < #modules and debugprofilestop() - started >= REFRESH_SHARE_MILLISECONDS then
                    C_Timer.After(0, step)
                    return
                end
            end
        end
    end
    step()
end

function queueRefresh()
    if isRefreshQueued then
        return
    end
    isRefreshQueued = true
    C_Timer.After(REFRESH_DELAY_SECONDS, function()
        isRefreshQueued = false
        refreshCount = refreshCount + 1
        -- (quiet: nothing but the quest log's own news has asked for a redraw since every module last drew)
        local isQuiet = true
        for _, module in ipairs(modules) do
            isQuiet = isQuiet and not module.isLoudPending
        end
        runModules("invalidate", isQuiet)
        runRefreshes()
    end)
end

---A redraw once a burst of data has settled; none when another redraw ran after its last arrival.
local function queueSlowRefresh()
    countAtLastArrival = refreshCount
    if isSlowRefreshQueued then
        return
    end
    isSlowRefreshQueued = true
    C_Timer.After(SLOW_REFRESH_DELAY_SECONDS, function()
        isSlowRefreshQueued = false
        if refreshCount == countAtLastArrival then
            queueRefresh()
        end
    end)
end

---@return boolean changed Whether a redrawing event changed anything drawn: yes unless every module that checks it
---says no. Every check runs, so each keeps what it last saw.
local function hasChanged(event, ...)
    local isChecked, changed = false, false
    for _, module in ipairs(modules) do
        local check = module.changes and module.changes[event]
        if check then
            isChecked = true
            local isFine, hasChangedHere = callSafely(check, ...)
            changed = not isFine or hasChangedHere or changed -- (a check that failed cannot say no)
        end
    end
    return changed or not isChecked
end

---The player moves, so distances and the minimap are redrawn every second.
local function handleTick()
    runModules("tick")
end

local function handlePlayerLogin()
    isLoggedIn = true
    if not ns.Database.isAvailable() then
        ns.print(ns.L("QuestieDB is not loaded, so quests cannot be grouped by location."))
    end
    -- Earlier versions put the game's own map pin on a place to show it. That pin outlives its use, so the
    -- one left behind is removed, once.
    if not ns.settings.hasRemovedOldMapPin then
        ns.settings.hasRemovedOldMapPin = true
        if C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.ClearUserWaypoint then
            C_Map.ClearUserWaypoint()
        end
    end
    -- Every module, in order (every addon has loaded by now: translation addons, map addons)
    runModules("create")
    C_Timer.After(TIDY_DELAY_SECONDS, function()
        pcall(ns.tidySavedData)
    end)
    C_Timer.NewTicker(POSITION_REFRESH_SECONDS, handleTick)
end

local isRefreshEvent = {}
for _, event in ipairs(REFRESH_EVENTS) do
    isRefreshEvent[event] = true
end

local eventFrame

---Listens to every game event a module handles, besides those that redraw. Once all the addon's files have run,
---so every module has registered. An event this client does not have (one renamed in another version of the game)
---is left out: registering it would stop the addon loading.
local function registerModuleEvents()
    local isEventValid = C_EventUtils and C_EventUtils.IsEventValid
    for _, module in ipairs(modules) do
        for event in pairs(module.events or {}) do
            if not isEventValid or isEventValid(event) then
                pcall(eventFrame.RegisterEvent, eventFrame, event)
            end
        end
    end
end

-- The events that say the quest log, or what is tracked, changed: what was read of them this frame is forgotten
-- before anybody acts on the event (this frame hears them before QuestState's own does)
local LOG_CHANGE_EVENTS = {
    QUEST_ACCEPTED = true,
    QUEST_REMOVED = true,
    QUEST_TURNED_IN = true,
    QUEST_LOG_UPDATE = true,
    QUEST_WATCH_LIST_CHANGED = true,
}

local function handleEvent(_, event, ...)
    ns.noteActivity(event)
    if LOG_CHANGE_EVENTS[event] and ns.QuestState and ns.QuestState.forgetFrame then
        ns.QuestState.forgetFrame()
    end
    if event == "ADDON_LOADED" then
        if ... == addonName then
            -- A saved file that still cannot be read leaves the addon running on the defaults this session (the file
            -- itself left as it is), rather than not loading at all
            if
                not callSafely(function()
                    OneMoreQuestDB = ns.loadSettings(OneMoreQuestDB)
                end)
            then
                ns.loadSettings(nil)
            end
            registerModuleEvents()
        elseif ... == "Blizzard_WorldMap" and isLoggedIn then
            -- The world map loaded after login: what is built on it is built now
            Timing.startOpening() -- the game loads it as it first opens
            for _, module in ipairs(modules) do
                if module.needsWorldMap and module.create then
                    Timing.measure("building " .. module.name, callSafely, module.create)
                end
            end
        end
        return
    elseif event == "PLAYER_LOGIN" then
        handlePlayerLogin()
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        runModules("afterCombat")
    end
    for _, module in ipairs(modules) do
        local handler = module.events and module.events[event]
        if handler then
            if Timing.isRecording then
                Timing.measure(event .. " " .. module.name, callSafely, handler, ...)
            else
                callSafely(handler, ...)
            end
        end
    end
    if
        isRefreshEvent[event]
        and (
            Timing.isRecording and Timing.measure("change check " .. event, hasChanged, event, ...)
            or not Timing.isRecording and hasChanged(event, ...)
        )
    then
        Timing.noteCause("everything redrawn", event)
        if not QUIET_REFRESH_EVENTS[event] then
            markLoud()
        end
        if SLOW_REFRESH_EVENTS[event] then
            queueSlowRefresh()
        else
            queueRefresh()
        end
    end
end

---------------------------------------------------------------------------------------------------------------
-- /omq and its commands: each a handler in SLASH_COMMANDS, given what was typed after /omq. The modules' own
-- functions are looked up as a command comes, so each handler stays one line where it only hands over.

local function toggleShown()
    ns.settings.isShown = not ns.settings.isShown
    ns.queueRefresh()
end

local function openSettings()
    if not ns.SettingsPage.open() then
        ns.print(ns.L("the settings cannot be opened right now; try again out of combat."))
    end
end

local function toggleLock()
    ns.settings.isLocked = not ns.settings.isLocked
    ns.print(
        ns.L(ns.settings.isLocked and "tracker locked in place." or "tracker unlocked, drag its title to move it.")
    )
end

local function resetPositions()
    ns.settings.position = nil
    ns.settings.collapsedZones = {}
    ns.Tracker.resetPosition()
    ns.Tracker.queueRefresh()
    ns.MapDock.resetMapSpot() -- (the map, if it was moved by the quest window: back where the game puts it)
    ns.settings.aloneLogSpot = nil
end

local function toggleBuiltInTracker()
    ns.settings.shouldHideBuiltInTracker = not ns.settings.shouldHideBuiltInTracker
    ns.BlizzardTracker.apply()
    ns.print(ns.L(ns.settings.shouldHideBuiltInTracker and "built-in tracker hidden." or "built-in tracker shown."))
end

local function toggleQuestLogKey()
    ns.settings.shouldReplaceQuestLog = not ns.settings.shouldReplaceQuestLog
    ns.Log.applyBinding()
    if not ns.settings.shouldReplaceQuestLog then
        ns.MapDock.restoreBuiltInPanel()
    end
    ns.MapDock.apply()
    ns.print(
        ns.L(
            ns.settings.shouldReplaceQuestLog and "the map shows the quest panels beside it."
                or "the map shows the game's own quest panel again; reopen the map."
        )
    )
end

local function toggleMapPins()
    ns.settings.shouldShowMapPins = not ns.settings.shouldShowMapPins
    ns.MapPins.applyGameFilter(true)
    ns.queueRefresh()
    ns.print(ns.L(ns.settings.shouldShowMapPins and "map pins shown." or "map pins hidden."))
end

-- /omq ovals: the settings' "Drawn as", from the chat, for comparing them at one spot of the map
local NEXT_AREA_GEOMETRY = { ovals = "soft", soft = "traced", traced = "ovals" }
local AREA_GEOMETRY_SAID = {
    ovals = "areas drawn as ovals. /omq ovals again for soft shadows.",
    soft = "areas drawn as soft shadows alone. /omq ovals again for traced shapes.",
    traced = "areas traced round their spawns (the heaviest). /omq ovals again for ovals.",
}

local function cycleAreaGeometry()
    ns.settings.areaGeometry = NEXT_AREA_GEOMETRY[ns.settings.areaGeometry] or "soft"
    ns.queueRefresh()
    if ns.MapPins and ns.MapPins.queueRefresh then
        ns.MapPins.queueRefresh()
    end
    ns.print(AREA_GEOMETRY_SAID[ns.settings.areaGeometry])
end

---The errors of OneMoreQuest's that were kept (errorLog): to tell what broke, after the game's popup is gone.
local function printErrors(input)
    local log = type(ns.settings.errorLog) == "table" and ns.settings.errorLog or {}
    if (input or ""):lower():match("^%S+%s+clear") then
        ns.settings.errorLog = nil
        ns.print("the errors kept are cleared.")
    elseif #log == 0 then
        ns.print("no errors kept.")
    else
        for index, entry in ipairs(log) do
            ns.print(string.format("%d. %s (%dx, last %s)", index, entry.text, entry.count, entry.lastAt or "?"))
        end
        ns.print("they are in the saved file too (OneMoreQuestDB.errorLog); /omq errors clear empties the list.")
    end
end

---For telling a fault in the drawing apart: every setting passed on to the game as it used to be (slower), nothing
---kept from one drawing to the next (Widgets.remember). Read as things are made, so after a reload.
local function togglePlainDrawing()
    ns.settings.isPlainDrawing = not ns.settings.isPlainDrawing or nil
    ns.print(
        ns.settings.isPlainDrawing
                and "plain drawing ON after /reload: everything is set anew at every drawing, as before (slower). /omq plain again turns it off."
            or "plain drawing OFF after /reload: what has not changed is left alone again."
    )
end

---The map's areas and spawn marks: kept on the map and only moved by it (MapMarks\World), or drawn again for every
---view as before, for telling a fault of the kept drawing apart. /omq drawing kept|classic, or the other one.
local function chooseMapDrawing(input)
    local rest = (input or ""):lower():match("^%S+%s+(%S+)")
    local isClassic = ns.settings.mapRenderer ~= "classic"
    if rest == "kept" then
        isClassic = false
    elseif rest == "classic" then
        isClassic = true
    end
    ns.settings.mapRenderer = isClassic and "classic" or nil
    ns.MapMarks.forgetKeptPoints()
    ns.queueRefresh()
    ns.print(
        isClassic
                and "map drawing: CLASSIC (every area and spawn mark laid out again for each view; slower). /omq drawing again for the kept one."
            or "map drawing: KEPT (areas and spawn marks laid out once in the world and moved with the map)."
    )
end

local function toggleBuiltInMapPins()
    ns.settings.shouldHideBuiltInMapPins = not ns.settings.shouldHideBuiltInMapPins
    ns.queueRefresh()
    ns.print(
        ns.L(
            ns.settings.shouldHideBuiltInMapPins and "the game's quest markers are hidden on the map."
                or "the game's quest markers return when the map next changes."
        )
    )
end

local function toggleMapGivers()
    ns.settings.shouldShowAvailableOnMap = not ns.settings.shouldShowAvailableOnMap
    ns.queueRefresh()
    ns.print(
        ns.L(
            ns.settings.shouldShowAvailableOnMap and "quest givers shown on the map."
                or "quest givers hidden on the map."
        )
    )
end

local function printCommands()
    ns.print(
        ns.L(
            "commands: /omq (show or hide the tracker), settings, log, available, key, pins, givers, mapbuiltin, lock, reset, builtin"
        )
    )
end

local SLASH_COMMANDS = {
    [""] = toggleShown,
    settings = openSettings,
    options = openSettings,
    config = openSettings,
    kills = function()
        ns.KillCounter.printCounts()
    end,
    missing = function()
        ns.MissedReport.printMissed()
    end,
    offers = function()
        ns.GameOffers.printComparison() -- what the game's own map offers here, against what this addon lists
    end,
    distance = function()
        ns.MinimapPins.printDistance()
    end,
    lock = toggleLock,
    reset = resetPositions,
    spoilers = function(input)
        ns.Spoilers.handleCommand((input or ""):match("^%S+%s+(%S+)"))
    end,
    builtin = toggleBuiltInTracker,
    log = function()
        ns.Log.toggle()
    end,
    available = function()
        ns.Log.showAvailable()
    end,
    key = toggleQuestLogKey,
    pins = toggleMapPins,
    ovals = cycleAreaGeometry,
    timing = function()
        Timing.toggle()
    end,
    cpu = function()
        Timing.printCpu()
    end,
    trace = function()
        Timing.toggleTrace()
    end,
    errors = printErrors,
    plain = togglePlainDrawing,
    drawing = chooseMapDrawing,
    hover = function()
        ns.MapHover.toggleReport()
    end,
    mapbuiltin = toggleBuiltInMapPins,
    givers = toggleMapGivers,
}

local function handleSlashCommand(input)
    local command = (input or ""):lower():match("^(%S*)")
    local handler = SLASH_COMMANDS[command] or printCommands
    handler(input)
end

function ns.start()
    eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("ADDON_LOADED")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    for _, event in ipairs(REFRESH_EVENTS) do
        eventFrame:RegisterEvent(event)
    end
    eventFrame:SetScript("OnEvent", handleEvent)
    ns.handleEvent = handleEvent -- the same, for tests and the simulator to send events through

    Timing.watchProblems() -- (OneMoreQuest's own Lua errors and refused actions kept from the start: errorLog)
    SLASH_ONEMOREQUEST1 = "/omq"
    SLASH_ONEMOREQUEST2 = "/onemorequest"
    SlashCmdList.ONEMOREQUEST = handleSlashCommand
end

if CreateFrame then
    ns.start()
end
