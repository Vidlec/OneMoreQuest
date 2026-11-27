local addonName, ns = ...

-- What OneMoreQuest costs, measured for finding what makes it slow, and what goes wrong, kept for reading afterwards:
--   /omq timing  how long each opening of the map takes, said in the chat;
--   /omq trace   the same and more, recorded by itself into the saved variables while the player plays;
--   /omq cpu     what the game's own profiler measured of each addon;
--   the errorLog OneMoreQuest's own Lua errors and the actions the game refused it, kept from loading on.
-- Loaded before Core.lua, which measures its modules' moments with it: what it calls of the rest of the addon
-- (ns.print, ns.CreateFrame, ns.noteActivity, ns.settings) is called later, while the game runs.

-- /omq timing: how long opening the map takes, for finding what makes it slow. Off, measure() only runs what it is given.
local Timing = { isOn = false }
ns.Timing = Timing
local TIMING_REPORT_SECONDS = 1.5 -- an opening's parts are added up this long, then printed
local TIMING_FRAMES = 30 -- frames remembered before the opening, for what a normal frame takes

local function getMilliseconds()
    return debugprofilestop and debugprofilestop() or 0
end

---@return number seconds The game's clock (0 where there is none)
local function getTime()
    return GetTime and GetTime() or 0
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
-- The settings written down with a trace: the ones that change most what the addon draws
local TRACED_SETTINGS = {
    "areaStyle",
    "spawnMarker",
    "shouldShowMinimapPins",
    "shouldShowMapPins",
    "shouldShowAvailableOnMap",
    "shouldShowNameplateIcons",
    "arePanelsHidden",
}
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

---------------------------------------------------------------------------------------------------------------
-- The game's own addon profiler (C_AddOnProfiler)

-- What each addon took in the last frame, as the game's own profiler measures it (C_AddOnProfiler, LastTime)
local ADDON_REPORT_COUNT = 10 -- addons named in the report, the dearest first

-- The game's metrics read, by their names, and their numbers should a client lack the names
local PROFILER_METRICS = {
    { name = "RecentAverageTime", number = 1, label = "now %.2f ms/frame" },
    { name = "SessionAverageTime", number = 0, label = "session %.2f" },
    { name = "PeakTime", number = 4, label = "peak %.0f ms" },
    { name = "CountTimeOver5Ms", number = 6, label = ">5 ms %dx", isCount = true },
    { name = "CountTimeOver50Ms", number = 8, label = ">50 ms %dx", isCount = true },
}

local function getLastTimeMetric()
    local names = Enum and Enum.AddOnProfilerMetric
    return names and names.LastTime or 3
end

local function getMetric(metric)
    local names = Enum and Enum.AddOnProfilerMetric
    return names and names[metric.name] or metric.number
end

local function canProfileAddOns()
    return C_AddOnProfiler ~= nil
        and C_AddOnProfiler.GetAddOnMetric ~= nil
        and not (C_AddOnProfiler.IsEnabled and not C_AddOnProfiler.IsEnabled())
end

---@param getter function? One of C_AddOnProfiler's getters (a client may lack it)
---@return number? value What it gives, when it gives a number
local function readMetric(getter, ...)
    if not getter then
        return nil
    end
    local isRead, value = pcall(getter, ...)
    return isRead and type(value) == "number" and value or nil
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

---@return number? ours OneMoreQuest's recent average (ms a frame), as the game measures it
---@return number? addOns every addon's together
---@return number? game the game's own scripts' and every addon's together (what the game menu's percents are of)
local function readRecentTimes()
    local metric = getMetric(PROFILER_METRICS[1])
    return readMetric(C_AddOnProfiler.GetAddOnMetric, addonName, metric),
        readMetric(C_AddOnProfiler.GetOverallMetric, metric),
        readMetric(C_AddOnProfiler.GetApplicationMetric, metric)
end

---------------------------------------------------------------------------------------------------------------
-- An opening of the map, timed

---In a frame after the map began opening: each addon's time in the frame before this one, the most it took
---in the opening's own frames and in those after kept apart.
local function noteAddOnFrame(opening, isOpeningFrame)
    if not opening.addOnNames then
        return
    end
    local metric = getLastTimeMetric()
    local field = isOpeningFrame and "opening" or "after"
    for _, name in ipairs(opening.addOnNames) do
        local milliseconds = readMetric(C_AddOnProfiler.GetAddOnMetric, name, metric)
        if milliseconds and milliseconds > 0 then
            local cost = opening.addOns[name] or { opening = 0, after = 0 }
            opening.addOns[name] = cost
            cost[field] = math.max(cost[field], milliseconds)
        end
    end
    local all = readMetric(C_AddOnProfiler.GetOverallMetric, metric)
    if all then
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

---The last lines of an opening's report: what asked for each part.
local function reportCauses(opening)
    for name, callers in pairs(opening.causes) do
        local texts = {}
        for caller, count in pairs(callers) do
            texts[#texts + 1] = caller .. (count > 1 and (" " .. count .. "x") or "")
        end
        table.sort(texts)
        print(string.format("  %s asked for by: %s", name, table.concat(texts, ", ")))
    end
end

---@return number milliseconds What a frame took on average before the opening
local function getNormalFrame(opening)
    local total = 0
    for _, milliseconds in ipairs(opening.before) do
        total = total + milliseconds
    end
    return #opening.before > 0 and total / #opening.before or 0
end

---@return string[] texts Our parts of the opening, the dearest first ("name 1.2 ms (3x)")
local function describeOpeningParts(opening)
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
    return texts
end

---Writes an opening down in a running trace, with which addons took the time and what asked for each part.
---@param partTexts string[] Our parts of it (describeOpeningParts)
local function traceOpening(opening, partTexts)
    local trace = Timing.trace
    if not trace or #trace.openings >= TRACE_MAX_OPENINGS then
        return
    end
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
    table.insert(trace.openings, {
        at = math.floor(getTime() - trace.startedAt),
        number = opening.number,
        frame = math.floor((opening.frame or 0) + 0.5),
        slowestAfter = math.floor((opening.slowestAfter or 0) + 0.5),
        ours = partTexts,
        addOns = addOns,
        causes = causes,
    })
end

---Once an opening's parts have been added up: written down in a running trace, and said in the chat while timing.
local function reportOpening()
    local opening = Timing.opening
    Timing.opening = nil
    if not opening then
        return
    end
    local texts = describeOpeningParts(opening)
    traceOpening(opening, texts)
    if not Timing.isOn then
        return -- traced only: nothing said in the chat
    end
    ns.print(
        string.format(
            "map open #%d%s: frame %.0f ms (normal %.0f ms), next frames up to %.0f ms; ours: %s",
            opening.number,
            opening.number == 1 and " (first since login or /reload)" or "",
            opening.frame or 0,
            getNormalFrame(opening),
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

---------------------------------------------------------------------------------------------------------------
-- /omq cpu

-- The counts of slow frames at the last /omq cpu, per addon: the game counts from login, not from a /reload, so
-- what changed since is said beside them
local lastCounts = {}

local function describeCost(addOnName)
    local parts = {}
    local counts = {}
    for _, metric in ipairs(PROFILER_METRICS) do
        local value = readMetric(C_AddOnProfiler.GetAddOnMetric, addOnName, getMetric(metric))
        if value then
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

---@return string[] names Every loaded addon the game has measured, the dearest over the session first
local function getMeasuredAddOnNames()
    local sessionMetric = getMetric(PROFILER_METRICS[2])
    local measured = {}
    for _, name in ipairs(getLoadedAddOnNames()) do
        local session = readMetric(C_AddOnProfiler.GetAddOnMetric, name, sessionMetric)
        if session and session > 0 then
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
    return names
end

---Prints what OneMoreQuest, Questie and the busiest addons cost, as the game measures them.
function Timing.printCpu()
    if not canProfileAddOns() then
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
    local names = getMeasuredAddOnNames()
    local allAddOns = readMetric(C_AddOnProfiler.GetOverallMetric, getMetric(PROFILER_METRICS[1]))
    ns.print(
        string.format(
            "CPU, as the game measures it%s:",
            allAddOns and string.format(" (all addons together now %.2f ms/frame)", allAddOns) or ""
        )
    )
    for _, name in ipairs(names) do
        print(string.format("  %s: %s", name, describeCost(name)))
    end
end

---------------------------------------------------------------------------------------------------------------
-- /omq trace

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
            values[metric.name] = readMetric(C_AddOnProfiler.GetAddOnMetric, name, getMetric(metric)) or 0
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
    table.insert(trace.snapshots, { at = math.floor(getTime() - trace.startedAt), addOns = readCpuCounts() })
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

-- What the player was doing, for a trace's records: true, or nil so the saved file leaves it out

local function isFrameShown(frame)
    return frame and frame:IsShown() or nil
end

local function isInCombat()
    return InCombatLockdown and InCombatLockdown() or nil
end

local function isMoving()
    return IsPlayerMoving and IsPlayerMoving() or nil
end

---@return number? rounded The value to three decimals (nil stays nil)
local function roundToThousandths(value)
    return value and math.floor(value * 1000 + 0.5) / 1000
end

---The frame before, written down if OneMoreQuest took long in it, with what of ours ran in it.
local function noteSlowFrame(trace, now, elapsed)
    local ours = readMetric(C_AddOnProfiler.GetAddOnMetric, addonName, getLastTimeMetric())
    if not ours or ours < TRACE_SLOW_MILLISECONDS or #trace.slowFrames >= TRACE_MAX_SLOW_FRAMES then
        return
    end
    table.insert(trace.slowFrames, {
        at = math.floor((now - trace.startedAt) * 10) / 10,
        ours = math.floor(ours + 0.5),
        frame = math.floor(elapsed * 1000 + 0.5),
        mapOpen = isFrameShown(WorldMapFrame),
        combat = isInCombat(),
        moving = isMoving(),
        parts = describeFrameParts(),
    })
end

---Every TRACE_SAMPLE_SECONDS: the game's recent averages written down, with what the player was doing.
local function takeSample(trace, now)
    if now - trace.lastSampleAt < TRACE_SAMPLE_SECONDS or #trace.samples >= TRACE_MAX_SAMPLES then
        return
    end
    local frames = trace.frameCount - (trace.lastSampleFrames or 0)
    local ours, addOns, game = readRecentTimes()
    table.insert(trace.samples, {
        at = math.floor(now - trace.startedAt),
        fps = math.floor(frames / (now - trace.lastSampleAt) + 0.5),
        ours = roundToThousandths(ours),
        addOns = roundToThousandths(addOns),
        game = roundToThousandths(game),
        memory = math.floor(collectgarbage("count")),
        mapOpen = isFrameShown(WorldMapFrame),
        menuOpen = isFrameShown(GameMenuFrame),
        combat = isInCombat(),
        moving = isMoving(),
    })
    trace.lastSampleAt, trace.lastSampleFrames = now, trace.frameCount
end

---Each frame while tracing: the frame before written down if slow, a sample and a snapshot when theirs is due.
local function traceFrame(elapsed)
    local trace = Timing.trace
    local now = getTime()
    noteSlowFrame(trace, now, elapsed)
    trace.frameCount = trace.frameCount + 1
    Timing.frameParts, Timing.frameCauses = {}, {}
    takeSample(trace, now)
    if now - trace.lastSnapshotAt >= TRACE_SNAPSHOT_SECONDS then
        trace.lastSnapshotAt = now
        takeSnapshot()
    end
    if now - trace.startedAt >= TRACE_MAX_SECONDS then
        Timing.stopTrace()
    end
end

---Each frame while recording: the frames around an opening of the map timed, the others remembered, and the trace's.
local function watchFrame(_, elapsed)
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
end

local function ensureWatcher()
    if Timing.watcher then
        return
    end
    -- Every frame's length, as the game gives it to OnUpdate: the frame the map opens in shows the whole wait,
    -- the game's own share (and loading its art) included
    Timing.frames = {}
    Timing.watcher = ns.CreateFrame("Frame")
    Timing.watcher:SetScript("OnUpdate", watchFrame)
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

---/omq timing: each opening of the map reported in the chat, or no longer.
function Timing.toggle()
    Timing.isOn = not Timing.isOn
    updateWatcher()
    ns.print(
        Timing.isOn and "timing on: open the map, each opening is reported here. /omq timing again to stop."
            or "timing off."
    )
end

---Starts recording, by itself, what OneMoreQuest costs as the player plays: the slow frames and what took the time
---in them, the map's openings, the game's counts each minute. Saved with the settings (performanceTrace).
function Timing.startTrace()
    if not canProfileAddOns() then
        ns.print("this client does not measure addons (no C_AddOnProfiler): nothing to trace.")
        return
    end
    local now = getTime()
    local settings = {}
    for _, key in ipairs(TRACED_SETTINGS) do
        settings[key] = ns.settings[key]
    end
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
        settings = settings,
    }
    ns.settings.performanceTrace = Timing.trace
    Timing.frameParts, Timing.frameCauses = {}, {}
    Timing.watchProblems()
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
    trace.seconds = math.floor(getTime() - trace.startedAt)
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

---/omq trace: a trace started, or the running one stopped.
function Timing.toggleTrace()
    if Timing.trace then
        Timing.stopTrace()
    else
        Timing.startTrace()
    end
end

---------------------------------------------------------------------------------------------------------------
-- Problems: errors and refused actions

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
            at = math.floor(getTime() - (trace.startedAt or 0)),
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

---Keeps a problem in the errorLog, and while a trace records notes it there too. Neither may fail the caller (the
---game's error handler, an event).
---@param logText string What the errorLog says
---@param traceText string What the trace says, beside the kind
local function keepProblem(kind, logText, traceText, where)
    pcall(Timing.noteError, logText, where)
    if Timing.trace then
        pcall(Timing.noteProblem, kind, traceText, where)
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
                keepProblem("error", message, message, where)
            end
        end
        return previousErrorHandler(message, ...)
    end)
end
Timing.watchErrors = watchErrors

---Listens for problems from loading on: OneMoreQuest's Lua errors (watchErrors) and the actions the game refused it,
---both kept in the errorLog (the game's popup names no function; the event does), and noted in a running trace too.
function Timing.watchProblems()
    watchErrors()
    if problemWatcher then
        return
    end
    problemWatcher = ns.CreateFrame("Frame")
    pcall(problemWatcher.RegisterEvent, problemWatcher, "ADDON_ACTION_BLOCKED")
    pcall(problemWatcher.RegisterEvent, problemWatcher, "ADDON_ACTION_FORBIDDEN")
    problemWatcher:SetScript("OnEvent", function(_, event, name, action)
        if name == addonName then
            local kind = event == "ADDON_ACTION_BLOCKED" and "blocked" or "forbidden"
            -- (the whole stack: what set the game's code off is far below the refused call)
            local where = debugstack and debugstack(2, 60, 0) or nil
            keepProblem(kind, "The game " .. kind .. " " .. tostring(action), tostring(action), where)
        end
    end)
end
