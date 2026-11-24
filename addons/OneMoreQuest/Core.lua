local addonName, ns = ...

-- The name players see; the addon's folder is named the same. Inside, the code keeps its first name
-- (TrailheadLog, TrailheadTracker), which players never see.
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
    areaStyle = "filled", -- the areas round each quest's spawns, in its colour: a light wash ("filled"), bold shapes with a bright edge ("blob"), or "none"
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

-- /omq timing: how long opening the map takes, for finding what makes it slow. Off, measure() only runs what it is given.
local Timing = { isOn = false }
ns.Timing = Timing
local TIMING_REPORT_SECONDS = 1.5 -- an opening's parts are added up this long, then printed
local TIMING_FRAMES = 30 -- frames remembered before the opening, for what a normal frame takes

local function getMilliseconds()
    return debugprofilestop and debugprofilestop() or 0
end

-- /omq trace: the same, and more, recorded by itself into the saved variables while the player plays as usual
-- (settings.performanceTrace): every frame OneMoreQuest took long in, with what of it took the time, every opening of
-- the map, and the game's own counts each minute. Read from the saved file after a /reload.
Timing.isRecording = false -- timing or tracing: the parts are measured
local TRACE_SLOW_MILLISECONDS = 16 -- a frame OneMoreQuest took this long in is written down
local TRACE_MAX_SLOW_FRAMES = 400
local TRACE_MAX_OPENINGS = 40
local TRACE_SNAPSHOT_SECONDS = 60
local TRACE_SAMPLE_SECONDS = 5 -- the game's recent averages written down this often, with what the player was doing
local TRACE_MAX_SAMPLES = 240
local TRACE_MAX_SECONDS = 20 * 60 -- it stops by itself after this long
Timing.frameParts, Timing.frameCauses = {}, {} -- what of ours ran since the watcher last looked, and what asked for it

local function updateRecording()
    Timing.isRecording = Timing.isOn or Timing.trace ~= nil
end

---Runs fn, and while timing or tracing adds its milliseconds to the part of that name: the opening's, and the frame's.
function Timing.measure(name, fn, ...)
    ns.noteActivity(name)
    if not Timing.isRecording then
        return fn(...)
    end
    local started = getMilliseconds()
    -- Up to four results kept without a table: a table each call would be garbage the measuring itself makes
    local first, second, third, fourth = fn(...)
    local milliseconds = getMilliseconds() - started
    if Timing.opening then
        local part = Timing.opening.parts[name] or { milliseconds = 0, count = 0 }
        Timing.opening.parts[name] = part
        part.milliseconds, part.count = part.milliseconds + milliseconds, part.count + 1
    end
    local trace = Timing.trace
    if trace then
        Timing.frameParts[name] = (Timing.frameParts[name] or 0) + milliseconds
        -- (and over the whole trace: what costs a little in every frame shows only added up)
        trace.partMilliseconds[name] = (trace.partMilliseconds[name] or 0) + milliseconds
        trace.partCounts[name] = (trace.partCounts[name] or 0) + 1
    end
    return first, second, third, fourth
end

---fn, measured under that name while timing or tracing, and otherwise called as it is: for the handlers that run
---every frame (an OnUpdate), whose cost is small each time and adds up
function Timing.timed(name, fn)
    return function(...)
        if not Timing.isRecording then
            return fn(...)
        end
        return Timing.measure(name, fn, ...)
    end
end

-- What each addon took in the last frame, as the game's own profiler measures it (C_AddOnProfiler, LastTime)
local ADDON_REPORT_COUNT = 10 -- addons named in the report, the dearest first

local function getLastTimeMetric()
    local names = Enum and Enum.AddOnProfilerMetric
    return names and names.LastTime or 3
end

local function canProfileAddOns()
    return C_AddOnProfiler ~= nil
        and C_AddOnProfiler.GetAddOnMetric ~= nil
        and not (C_AddOnProfiler.IsEnabled and not C_AddOnProfiler.IsEnabled())
end

---@return string[] names Every addon loaded now (the game's own Blizzard_ ones are measured with the game)
local function getLoadedAddOnNames()
    local names = {}
    local getCount = C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns
    local getInfo = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    for index = 1, getCount and getCount() or 0 do
        local name = getInfo(index)
        if name and ns.isAddOnLoaded(name) then
            names[#names + 1] = name
        end
    end
    return names
end

---In a frame after the map began opening: each addon's time in the frame before this one, the most it took
---in the opening's own frames and in those after kept apart.
local function noteAddOnFrame(opening, isOpeningFrame)
    if not opening.addOnNames then
        return
    end
    local metric = getLastTimeMetric()
    local field = isOpeningFrame and "opening" or "after"
    for _, name in ipairs(opening.addOnNames) do
        local isRead, milliseconds = pcall(C_AddOnProfiler.GetAddOnMetric, name, metric)
        if isRead and type(milliseconds) == "number" and milliseconds > 0 then
            local cost = opening.addOns[name] or { opening = 0, after = 0 }
            opening.addOns[name] = cost
            cost[field] = math.max(cost[field], milliseconds)
        end
    end
    local isRead, all = pcall(C_AddOnProfiler.GetOverallMetric, metric)
    if isRead and type(all) == "number" then
        opening.allAddOns[field] = math.max(opening.allAddOns[field] or 0, all)
    end
end

---The second line of an opening's report: which addons took the time, in the opening's frame and after it.
local function reportAddOns(opening)
    if not opening.addOnNames then
        ns.print(
            "this client does not measure each addon (no C_AddOnProfiler): only OneMoreQuest's own parts are timed."
        )
        return
    end
    local costs = {}
    for name, cost in pairs(opening.addOns) do
        costs[#costs + 1] = { name = name, opening = cost.opening, after = cost.after }
    end
    table.sort(costs, function(first, second)
        return math.max(first.opening, first.after) > math.max(second.opening, second.after)
    end)
    local texts = {}
    for index = 1, math.min(#costs, ADDON_REPORT_COUNT) do
        local cost = costs[index]
        texts[#texts + 1] = string.format("%s %.0f / %.0f", cost.name, cost.opening, cost.after)
    end
    local allOpening = opening.allAddOns.opening or 0
    print(
        string.format(
            "  by addon, ms in the opening frame / the slowest frame after: %s",
            #texts > 0 and table.concat(texts, ", ") or "none measured"
        )
    )
    print(
        string.format(
            "  all addons together %.0f ms of the %.0f ms opening frame: the game itself took the other %.0f ms",
            allOpening,
            opening.frame or 0,
            math.max((opening.frame or 0) - allOpening, 0)
        )
    )
end

local reportCauses -- what asked for each part (below)

local function reportOpening()
    local opening = Timing.opening
    Timing.opening = nil
    if not opening then
        return
    end
    local normal = 0
    for _, milliseconds in ipairs(opening.before) do
        normal = normal + milliseconds
    end
    normal = #opening.before > 0 and normal / #opening.before or 0
    local parts = {}
    for name, part in pairs(opening.parts) do
        parts[#parts + 1] = { name = name, milliseconds = part.milliseconds, count = part.count }
    end
    table.sort(parts, function(first, second)
        return first.milliseconds > second.milliseconds
    end)
    local texts = {}
    for _, part in ipairs(parts) do
        texts[#texts + 1] = string.format(
            "%s %.1f ms%s",
            part.name,
            part.milliseconds,
            part.count > 1 and (" (" .. part.count .. "x)") or ""
        )
    end
    if Timing.trace and #Timing.trace.openings < TRACE_MAX_OPENINGS then
        -- Written down for the trace, with which addons took the time and what asked for each part
        local addOns = {}
        for name, cost in pairs(opening.addOns) do
            if cost.opening >= 1 or cost.after >= 1 then
                addOns[name] = string.format("%.0f / %.0f", cost.opening, cost.after)
            end
        end
        local causes = {}
        for name, callers in pairs(opening.causes) do
            for caller, count in pairs(callers) do
                causes[#causes + 1] = string.format("%s <- %s x%d", name, caller, count)
            end
        end
        table.insert(Timing.trace.openings, {
            at = math.floor((GetTime and GetTime() or 0) - Timing.trace.startedAt),
            number = opening.number,
            frame = math.floor((opening.frame or 0) + 0.5),
            slowestAfter = math.floor((opening.slowestAfter or 0) + 0.5),
            ours = texts,
            addOns = addOns,
            causes = causes,
        })
    end
    if not Timing.isOn then
        return -- traced only: nothing said in the chat
    end
    ns.print(
        string.format(
            "map open #%d%s: frame %.0f ms (normal %.0f ms), next frames up to %.0f ms; ours: %s",
            opening.number,
            opening.number == 1 and " (first since login or /reload)" or "",
            opening.frame or 0,
            normal,
            opening.slowestAfter or 0,
            #texts > 0 and table.concat(texts, ", ") or "nothing"
        )
    )
    reportAddOns(opening)
    reportCauses(opening)
end

---Notes, while an opening is timed, what asked for a part to be done (the file and line that called), so the report
---says why a part ran more than once.
---@param cause string? What asked, when known (a game event); else the caller is read off the stack
function Timing.noteCause(name, cause)
    local opening = Timing.isRecording and Timing.opening
    if not (opening or Timing.trace) or (not cause and not debugstack) then
        return
    end
    local caller = cause or (debugstack(3, 1, 0) or ""):match("([%w_]+%.lua:%d+)") or "the game (a hook)"
    if opening then
        opening.causes[name] = opening.causes[name] or {}
        opening.causes[name][caller] = (opening.causes[name][caller] or 0) + 1
    end
    if Timing.trace then
        local key = name .. " <- " .. caller
        Timing.frameCauses[key] = (Timing.frameCauses[key] or 0) + 1
    end
end

reportCauses = function(opening)
    for name, callers in pairs(opening.causes) do
        local texts = {}
        for caller, count in pairs(callers) do
            texts[#texts + 1] = caller .. (count > 1 and (" " .. count .. "x") or "")
        end
        table.sort(texts)
        print(string.format("  %s asked for by: %s", name, table.concat(texts, ", ")))
    end
end

---The map began to open: its parts are measured from now, and the frame it opens in timed.
function Timing.startOpening()
    if not Timing.isRecording or Timing.opening then
        return
    end
    Timing.openCount = (Timing.openCount or 0) + 1
    local before = {}
    for index = 1, #Timing.frames do
        before[index] = Timing.frames[index]
    end
    Timing.opening = {
        number = Timing.openCount,
        parts = {},
        before = before,
        framesAfter = 0,
        addOnNames = canProfileAddOns() and getLoadedAddOnNames() or nil,
        addOns = {},
        allAddOns = {},
        causes = {},
    }
    C_Timer.After(TIMING_REPORT_SECONDS, reportOpening)
end

-- The game's own addon profiler (C_AddOnProfiler), always on: what each addon costs, measured by the game
local PROFILER_METRICS = { -- the game's names, and their numbers should a client lack the names
    { name = "RecentAverageTime", number = 1, label = "now %.2f ms/frame" },
    { name = "SessionAverageTime", number = 0, label = "session %.2f" },
    { name = "PeakTime", number = 4, label = "peak %.0f ms" },
    { name = "CountTimeOver5Ms", number = 6, label = ">5 ms %dx", isCount = true },
    { name = "CountTimeOver50Ms", number = 8, label = ">50 ms %dx", isCount = true },
}

local function getMetric(metric)
    local names = Enum and Enum.AddOnProfilerMetric
    return names and names[metric.name] or metric.number
end

-- The counts of slow frames at the last /omq cpu, per addon: the game counts from login, not from a /reload, so
-- what changed since is said beside them
local lastCounts = {}

local function describeCost(addOnName)
    local parts = {}
    local counts = {}
    for _, metric in ipairs(PROFILER_METRICS) do
        local isRead, value = pcall(C_AddOnProfiler.GetAddOnMetric, addOnName, getMetric(metric))
        if isRead and type(value) == "number" then
            local text = string.format(metric.label, value)
            if metric.isCount then
                counts[metric.name] = value
                local before = lastCounts[addOnName] and lastCounts[addOnName][metric.name]
                if before then
                    text = text .. string.format(" (+%d since last)", value - before)
                end
            end
            parts[#parts + 1] = text
        end
    end
    lastCounts[addOnName] = counts
    return table.concat(parts, ", ")
end

---@return number? ours OneMoreQuest's recent average (ms a frame), as the game measures it
---@return number? addOns every addon's together
---@return number? game the game's own scripts' and every addon's together (what the game menu's percents are of)
local function readRecentTimes()
    local metric = getMetric(PROFILER_METRICS[1])
    local function read(getter, ...)
        if not getter then
            return nil
        end
        local isRead, value = pcall(getter, ...)
        return isRead and type(value) == "number" and value or nil
    end
    return read(C_AddOnProfiler.GetAddOnMetric, addonName, metric),
        read(C_AddOnProfiler.GetOverallMetric, metric),
        read(C_AddOnProfiler.GetApplicationMetric, metric)
end

---Prints what OneMoreQuest, Questie and the busiest addons cost, as the game measures them.
function Timing.printCpu()
    if
        not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric)
        or (C_AddOnProfiler.IsEnabled and not C_AddOnProfiler.IsEnabled())
    then
        ns.print("this client does not measure addons (no C_AddOnProfiler).")
        return
    end
    -- The game menu's percents in milliseconds: an addon's share is of the game's own scripts' time and its own
    local ours, addOns, game = readRecentTimes()
    if ours and addOns and game and game > 0 then
        local relative = game - addOns + ours
        ns.print(
            string.format(
                "now, ms a frame: OneMoreQuest %.3f (the game menu's %.0f%%), every addon %.3f (%.0f%%), the game's "
                    .. "scripts and the addons %.3f",
                ours,
                relative > 0 and ours / relative * 100 or 0,
                addOns,
                addOns / game * 100,
                game
            )
        )
    end
    -- Every loaded addon the game has measured, the dearest over the session first
    local sessionMetric = getMetric(PROFILER_METRICS[2])
    local measured = {}
    for _, name in ipairs(getLoadedAddOnNames()) do
        local isRead, session = pcall(C_AddOnProfiler.GetAddOnMetric, name, sessionMetric)
        if isRead and type(session) == "number" and session > 0 then
            measured[#measured + 1] = { name = name, session = session }
        end
    end
    table.sort(measured, function(first, second)
        return first.session > second.session
    end)
    local names = {}
    for _, entry in ipairs(measured) do
        names[#names + 1] = entry.name
    end
    local overall = PROFILER_METRICS[1]
    local isOverallRead, allAddOns = pcall(C_AddOnProfiler.GetOverallMetric, getMetric(overall))
    ns.print(
        string.format(
            "CPU, as the game measures it%s:",
            isOverallRead
                    and type(allAddOns) == "number"
                    and string.format(" (all addons together now %.2f ms/frame)", allAddOns)
                or ""
        )
    )
    for _, name in ipairs(names) do
        print(string.format("  %s: %s", name, describeCost(name)))
    end
end

---@return table counts { [addon] = { session, peak, over5, over50 } }: what the game has counted of each loaded
---addon that has cost anything
local function readCpuCounts()
    local counts = {}
    if not canProfileAddOns() then
        return counts
    end
    for _, name in ipairs(getLoadedAddOnNames()) do
        local values = {}
        for _, metric in ipairs(PROFILER_METRICS) do
            local isRead, value = pcall(C_AddOnProfiler.GetAddOnMetric, name, getMetric(metric))
            values[metric.name] = isRead and type(value) == "number" and value or 0
        end
        if values.SessionAverageTime > 0 or values.CountTimeOver5Ms > 0 then
            counts[name] = {
                session = tonumber(string.format("%.3f", values.SessionAverageTime)),
                peak = math.floor(values.PeakTime + 0.5),
                over5 = values.CountTimeOver5Ms,
                over50 = values.CountTimeOver50Ms,
            }
        end
    end
    return counts
end

local function takeSnapshot()
    local trace = Timing.trace
    if not trace then
        return
    end
    table.insert(
        trace.snapshots,
        { at = math.floor((GetTime and GetTime() or 0) - trace.startedAt), addOns = readCpuCounts() }
    )
end

---@return table[] parts The parts of ours that took the most of a frame, dearest first, as text
local function describeFrameParts()
    local parts = {}
    for name, milliseconds in pairs(Timing.frameParts) do
        if milliseconds >= 0.5 or not debugprofilestop then -- the small ones leave the frame's cost unexplained anyway
            parts[#parts + 1] = { name = name, milliseconds = milliseconds }
        end
    end
    table.sort(parts, function(first, second)
        return first.milliseconds > second.milliseconds
    end)
    local texts = {}
    for index = 1, math.min(#parts, 8) do
        texts[index] = string.format("%s %.1f", parts[index].name, parts[index].milliseconds)
    end
    for cause, count in pairs(Timing.frameCauses) do
        texts[#texts + 1] = "asked: " .. cause .. (count > 1 and (" x" .. count) or "")
    end
    return texts
end

---Each frame while tracing: the frame before, if OneMoreQuest took long in it, written down with what of ours ran.
local function traceFrame(elapsed)
    local trace = Timing.trace
    local now = GetTime and GetTime() or 0
    local isRead, ours = pcall(C_AddOnProfiler.GetAddOnMetric, addonName, getLastTimeMetric())
    if
        isRead
        and type(ours) == "number"
        and ours >= TRACE_SLOW_MILLISECONDS
        and #trace.slowFrames < TRACE_MAX_SLOW_FRAMES
    then
        table.insert(trace.slowFrames, {
            at = math.floor((now - trace.startedAt) * 10) / 10,
            ours = math.floor(ours + 0.5),
            frame = math.floor(elapsed * 1000 + 0.5),
            mapOpen = WorldMapFrame and WorldMapFrame:IsShown() or nil,
            combat = InCombatLockdown and InCombatLockdown() or nil,
            moving = IsPlayerMoving and IsPlayerMoving() or nil,
            parts = describeFrameParts(),
        })
    end
    trace.frameCount = trace.frameCount + 1
    Timing.frameParts, Timing.frameCauses = {}, {}
    if now - trace.lastSampleAt >= TRACE_SAMPLE_SECONDS and #trace.samples < TRACE_MAX_SAMPLES then
        local frames = trace.frameCount - (trace.lastSampleFrames or 0)
        local ours, addOns, game = readRecentTimes()
        table.insert(trace.samples, {
            at = math.floor(now - trace.startedAt),
            fps = math.floor(frames / (now - trace.lastSampleAt) + 0.5),
            ours = ours and math.floor(ours * 1000 + 0.5) / 1000,
            addOns = addOns and math.floor(addOns * 1000 + 0.5) / 1000,
            game = game and math.floor(game * 1000 + 0.5) / 1000,
            memory = math.floor(collectgarbage("count")),
            mapOpen = WorldMapFrame and WorldMapFrame:IsShown() or nil,
            menuOpen = GameMenuFrame and GameMenuFrame:IsShown() or nil,
            combat = InCombatLockdown and InCombatLockdown() or nil,
            moving = IsPlayerMoving and IsPlayerMoving() or nil,
        })
        trace.lastSampleAt, trace.lastSampleFrames = now, trace.frameCount
    end
    if now - trace.lastSnapshotAt >= TRACE_SNAPSHOT_SECONDS then
        trace.lastSnapshotAt = now
        takeSnapshot()
    end
    if now - trace.startedAt >= TRACE_MAX_SECONDS then
        Timing.stopTrace()
    end
end

local function ensureWatcher()
    if Timing.watcher then
        return
    end
    -- Every frame's length, as the game gives it to OnUpdate: the frame the map opens in shows the whole wait,
    -- the game's own share (and loading its art) included
    Timing.frames = {}
    Timing.watcher = CreateFrame("Frame")
    Timing.watcher:SetScript("OnUpdate", function(_, elapsed)
        local milliseconds = elapsed * 1000
        local opening = Timing.opening
        if opening and opening.framesAfter < 2 then
            -- The opening's frame is the first or the second after it, as the game orders input and OnUpdate
            opening.framesAfter = opening.framesAfter + 1
            opening.frame = math.max(opening.frame or 0, milliseconds)
            noteAddOnFrame(opening, true)
        elseif opening then
            opening.slowestAfter = math.max(opening.slowestAfter or 0, milliseconds)
            noteAddOnFrame(opening, false)
        else
            table.insert(Timing.frames, milliseconds)
            if #Timing.frames > TIMING_FRAMES then
                table.remove(Timing.frames, 1)
            end
        end
        if Timing.trace then
            traceFrame(elapsed)
        end
    end)
    -- A /reload or logging out ends a trace, so what was recorded is saved
    Timing.watcher:RegisterEvent("PLAYER_LOGOUT")
    Timing.watcher:SetScript("OnEvent", function()
        if Timing.trace then
            Timing.stopTrace(true)
        end
    end)
end

local function updateWatcher()
    updateRecording()
    ensureWatcher()
    Timing.watcher:SetShown(Timing.isRecording)
end

function Timing.toggle()
    Timing.isOn = not Timing.isOn
    updateWatcher()
    ns.print(
        Timing.isOn and "timing on: open the map, each opening is reported here. /omq timing again to stop."
            or "timing off."
    )
end

-- While a trace records, what goes wrong is written down with it (trace.problems): OneMoreQuest's own Lua errors with
-- where they happened, and what the game refused it (an action blocked, as in a fight). So a fault that shows only
-- in the game can be read afterwards from the saved file, with nothing to copy out of the chat.
local MAX_PROBLEMS = 40
local previousErrorHandler, problemWatcher

---@param kind string "error", "blocked", "forbidden" or "refused"
---@param where string? The stack, for an error
function Timing.noteProblem(kind, text, where)
    local trace = Timing.trace
    if not trace then
        return
    end
    trace.problems = trace.problems or {}
    for _, problem in ipairs(trace.problems) do
        if problem.text == text then
            problem.count = problem.count + 1
            return
        end
    end
    if #trace.problems < MAX_PROBLEMS then
        trace.problems[#trace.problems + 1] = {
            kind = kind,
            text = text,
            where = where,
            count = 1,
            at = math.floor((GetTime and GetTime() or 0) - (trace.startedAt or 0)),
        }
    end
end

-- OneMoreQuest's own Lua errors are kept with the settings (errorLog), the last MAX_ERRORS of them, each once with how
-- often it came, where it happened and when: a fault seen in the game can be read afterwards from the saved file
-- (or with /omq errors), though the game's popup was closed. Nothing is done until an error happens.
local MAX_ERRORS = 20

---Keeps one error of OneMoreQuest's in the settings' errorLog.
function Timing.noteError(message, where)
    local log = type(ns.settings.errorLog) == "table" and ns.settings.errorLog or {}
    ns.settings.errorLog = log
    local now = date and date("%Y-%m-%d %H:%M:%S") or nil
    for _, entry in ipairs(log) do
        if entry.text == message then
            entry.count, entry.lastAt = entry.count + 1, now
            entry.where = where or entry.where -- (the latest: a fix since may have moved it)
            return
        end
    end
    local position = ns.Geometry and ns.Geometry.getPlayerPosition and ns.Geometry.getPlayerPosition()
    log[#log + 1] = {
        text = message,
        where = where,
        count = 1,
        firstAt = now,
        lastAt = now,
        version = ns.version,
        inCombat = InCombatLockdown and InCombatLockdown() or nil,
        inInstance = IsInInstance and (IsInInstance()) or nil,
        uiMapId = position and position.uiMapId or nil,
    }
    while #log > MAX_ERRORS do
        table.remove(log, 1)
    end
end

---The game's error handler, ours in front of it: an error from OneMoreQuest's code (its message, or the stack it
---came up through) is kept, and while a trace records noted with it; every error then goes on to the handler that
---was there, the game's popup or an error addon's. Set once, as the addon loads; another addon may set its own
---over it later, which is fine.
local function watchErrors()
    if previousErrorHandler or not geterrorhandler or not seterrorhandler then
        return
    end
    previousErrorHandler = geterrorhandler()
    local ownFiles = "AddOns/" .. addonName .. "/"
    seterrorhandler(function(message, ...)
        if type(message) == "string" then
            local where = debugstack and debugstack(2, 12, 0) or nil
            if message:find(addonName, 1, true) or (where and where:find(ownFiles, 1, true)) then
                pcall(Timing.noteError, message, where)
                if Timing.trace then
                    pcall(Timing.noteProblem, "error", message, where)
                end
            end
        end
        return previousErrorHandler(message, ...)
    end)
end
Timing.watchErrors = watchErrors

---Listens for problems from loading on: OneMoreQuest's Lua errors (watchErrors) and the actions the game refused it,
---both kept in the errorLog (the game's popup names no function; the event does), and noted in a running trace too.
local function watchProblems()
    watchErrors()
    if not problemWatcher and CreateFrame then
        problemWatcher = CreateFrame("Frame")
        pcall(problemWatcher.RegisterEvent, problemWatcher, "ADDON_ACTION_BLOCKED")
        pcall(problemWatcher.RegisterEvent, problemWatcher, "ADDON_ACTION_FORBIDDEN")
        problemWatcher:SetScript("OnEvent", function(_, event, name, action)
            if name == addonName then
                local kind = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden"
                -- (the whole stack: what set the game's code off is far below the refused call)
                local where = debugstack and debugstack(2, 60, 0) or nil
                pcall(Timing.noteError, "The game " .. kind .. " " .. tostring(action), where)
                if Timing.trace then
                    pcall(Timing.noteProblem, kind, tostring(action), where)
                end
            end
        end)
    end
end

---Starts recording, by itself, what OneMoreQuest costs as the player plays: the slow frames and what took the time
---in them, the map's openings, the game's counts each minute. Saved with the settings (performanceTrace).
function Timing.startTrace()
    if not canProfileAddOns() then
        ns.print("this client does not measure addons (no C_AddOnProfiler): nothing to trace.")
        return
    end
    local now = GetTime and GetTime() or 0
    Timing.trace = {
        startedAt = now,
        lastSnapshotAt = now,
        frameCount = 0,
        slowFrames = {},
        partMilliseconds = {}, -- [part] = its milliseconds over the whole trace, and how many times it ran
        partCounts = {},
        samples = {},
        lastSampleAt = now,
        openings = {},
        snapshots = {},
        startedOn = date and date("%Y-%m-%d %H:%M") or nil,
        version = ns.version or nil,
        settings = {
            areaStyle = ns.settings.areaStyle,
            spawnMarker = ns.settings.spawnMarker,
            shouldShowMinimapPins = ns.settings.shouldShowMinimapPins,
            shouldShowMapPins = ns.settings.shouldShowMapPins,
            shouldShowAvailableOnMap = ns.settings.shouldShowAvailableOnMap,
            shouldShowNameplateIcons = ns.settings.shouldShowNameplateIcons,
            arePanelsHidden = ns.settings.arePanelsHidden,
        },
    }
    ns.settings.performanceTrace = Timing.trace
    Timing.frameParts, Timing.frameCauses = {}, {}
    watchProblems()
    takeSnapshot()
    updateWatcher()
    ns.print(
        "tracing: play as you usually do, and open the map now and then. When you have played a while (it stops by "
            .. "itself after 20 minutes), type /reload: the trace is saved, and Claude can read it."
    )
end

---@param isLeaving boolean? The game is reloading or logging out: nothing said
function Timing.stopTrace(isLeaving)
    local trace = Timing.trace
    if not trace then
        return
    end
    takeSnapshot()
    trace.seconds = math.floor((GetTime and GetTime() or 0) - trace.startedAt)
    trace.startedAt, trace.lastSnapshotAt, trace.lastSampleAt = nil, nil, nil -- the game's clock means nothing after a reload
    -- Every part's whole time, rounded, the dearest first: { name, milliseconds, times }
    local parts = {}
    for name, milliseconds in pairs(trace.partMilliseconds) do
        parts[#parts + 1] = { name, math.floor(milliseconds * 10 + 0.5) / 10, trace.partCounts[name] or 0 }
    end
    table.sort(parts, function(first, second)
        return first[2] > second[2]
    end)
    trace.parts, trace.partMilliseconds, trace.partCounts = parts, nil, nil
    Timing.trace = nil
    updateWatcher()
    if not isLeaving then
        ns.print(
            string.format(
                "trace done: %d seconds, %d slow frames of OneMoreQuest's written down. Type /reload so it "
                    .. "is saved, then tell Claude.",
                trace.seconds,
                #trace.slowFrames
            )
        )
    end
end

function Timing.toggleTrace()
    if Timing.trace then
        Timing.stopTrace()
    else
        Timing.startTrace()
    end
end

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

---Puts every switch back to its default. Remembered things that are not switches (the highlighted quest of
---each character, zones folded by hand) are kept.
function ns.resetSettings()
    for key, value in pairs(DEFAULT_SETTINGS) do
        if type(value) ~= "table" then
            ns.settings[key] = value
        end
    end
    ns.settings.position = nil
end

-- The looks there were before the areas and the spawn markers became two choices: what each is now
local OLD_AREA_STYLES = {
    icons = { "filled", "glyph" }, -- "Icons and areas"
    spawns = { "none", "glyph" }, -- "Icons only"
    shapes = { "blob", "none" }, -- "Shapes": areas alone, as they were
    dots = { "none", "square" }, -- "Squares"
}

---Fills in the settings a saved table lacks. Table defaults start out empty. A damaged saved file (the whole of it not
---a table, or a setting of the wrong kind: words where a number goes) once stopped the addon loading: what is not
---of its default's kind is put back to the default, the rest kept.
function ns.loadSettings(savedSettings)
    local settings = type(savedSettings) == "table" and savedSettings or {}
    for key, value in pairs(DEFAULT_SETTINGS) do
        if settings[key] ~= nil and type(settings[key]) ~= type(value) then
            settings[key] = nil
        end
    end
    -- The dark ground was one switch: on, it is the whole box now
    if settings.trackerBackground == nil and settings.shouldShowTrackerBackground == true then
        settings.trackerBackground = "box"
    end
    -- PvP quests' colour, new: a player who had every quest's colour as the game has them (gold, a grey "!" far below,
    -- blue repeatable: "As the game has them") gets PvP gold as well, not the red it starts with
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
    local old = OLD_AREA_STYLES[settings.areaStyle]
    if old then
        settings.areaStyle = old[1]
        settings.spawnMarker = settings.spawnMarker or old[2]
    end
    for key, value in pairs(DEFAULT_SETTINGS) do
        if settings[key] == nil then
            settings[key] = type(value) == "table" and {} or value
        end
    end
    if settings.areaStyle == "game" then
        -- "Game's areas" used to be a look of this addon's marks; it is the game's own markers now, which is the
        -- map marks switched off
        settings.areaStyle = DEFAULT_SETTINGS.areaStyle
        settings.shouldShowMapPins, settings.shouldHideBuiltInMapPins = false, false
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

local function handleSlashCommand(input)
    local command = (input or ""):lower():match("^(%S*)")
    if command == "" then
        ns.settings.isShown = not ns.settings.isShown
        ns.queueRefresh()
    elseif command == "settings" or command == "options" or command == "config" then
        if not ns.SettingsPage.open() then
            ns.print(ns.L("the settings cannot be opened right now; try again out of combat."))
        end
    elseif command == "kills" then
        ns.KillCounter.printCounts()
    elseif command == "missing" then
        ns.MissedReport.printMissed()
    elseif command == "offers" then
        ns.GameOffers.printComparison() -- what the game's own map offers here, against what this addon lists
    elseif command == "distance" then
        ns.MinimapPins.printDistance()
    elseif command == "lock" then
        ns.settings.isLocked = not ns.settings.isLocked
        ns.print(
            ns.L(ns.settings.isLocked and "tracker locked in place." or "tracker unlocked, drag its title to move it.")
        )
    elseif command == "reset" then
        ns.settings.position = nil
        ns.settings.collapsedZones = {}
        ns.Tracker.resetPosition()
        ns.Tracker.queueRefresh()
        ns.MapDock.resetMapSpot() -- (the map, if it was moved by the quest window: back where the game puts it)
        ns.settings.aloneLogSpot = nil
    elseif command == "spoilers" then
        ns.Spoilers.handleCommand((input or ""):match("^%S+%s+(%S+)"))
    elseif command == "builtin" then
        ns.settings.shouldHideBuiltInTracker = not ns.settings.shouldHideBuiltInTracker
        ns.BlizzardTracker.apply()
        ns.print(ns.L(ns.settings.shouldHideBuiltInTracker and "built-in tracker hidden." or "built-in tracker shown."))
    elseif command == "log" then
        ns.Log.toggle()
    elseif command == "available" then
        ns.Log.showAvailable()
    elseif command == "key" then
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
    elseif command == "pins" then
        ns.settings.shouldShowMapPins = not ns.settings.shouldShowMapPins
        ns.MapPins.applyGameFilter(true)
        ns.queueRefresh()
        ns.print(ns.L(ns.settings.shouldShowMapPins and "map pins shown." or "map pins hidden."))
    elseif command == "timing" then
        Timing.toggle()
    elseif command == "cpu" then
        Timing.printCpu()
    elseif command == "trace" then
        Timing.toggleTrace()
    elseif command == "errors" then
        -- The errors of OneMoreQuest's that were kept (errorLog): to tell what broke, after the game's popup is gone
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
    elseif command == "plain" then
        -- For telling a fault in the drawing apart: every setting passed on to the game as it used to be (slower),
        -- nothing kept from one drawing to the next (Widgets.remember). Read as things are made, so after a reload.
        ns.settings.isPlainDrawing = not ns.settings.isPlainDrawing or nil
        ns.print(
            ns.settings.isPlainDrawing
                    and "plain drawing ON after /reload: everything is set anew at every drawing, as before (slower). /omq plain again turns it off."
                or "plain drawing OFF after /reload: what has not changed is left alone again."
        )
    elseif command == "hover" then
        ns.MapHover.toggleReport()
    elseif command == "mapbuiltin" then
        ns.settings.shouldHideBuiltInMapPins = not ns.settings.shouldHideBuiltInMapPins
        ns.queueRefresh()
        ns.print(
            ns.L(
                ns.settings.shouldHideBuiltInMapPins and "the game's quest markers are hidden on the map."
                    or "the game's quest markers return when the map next changes."
            )
        )
    elseif command == "givers" then
        ns.settings.shouldShowAvailableOnMap = not ns.settings.shouldShowAvailableOnMap
        ns.queueRefresh()
        ns.print(
            ns.L(
                ns.settings.shouldShowAvailableOnMap and "quest givers shown on the map."
                    or "quest givers hidden on the map."
            )
        )
    else
        ns.print(
            ns.L(
                "commands: /trailhead (show or hide the tracker), settings, log, available, key, pins, givers, mapbuiltin, lock, reset, builtin"
            )
        )
    end
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

    watchProblems() -- (OneMoreQuest's own Lua errors and refused actions kept from the start: errorLog)
    SLASH_TRAILHEAD1 = "/omq"
    SLASH_TRAILHEAD2 = "/onemorequest"
    SLASH_TRAILHEAD3 = "/trailhead" -- the addon's first name, kept for those used to it
    SlashCmdList.TRAILHEAD = handleSlashCommand
end

if CreateFrame then
    ns.start()
end
