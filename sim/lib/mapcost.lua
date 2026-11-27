-- Measuring what OneMoreQuest's map marks cost, for the audits: widget calls made from its code, its share of the Lua
-- time (sampled), the worst single frame, and its regions on the map. One harness for every map audit, so their
-- numbers compare.
local W, sim = require("widgets"), require("sim")
local getinfo = debug.getinfo
local OURS = "@Interface/AddOns/OneMoreQuest/"
local ADDON = "OneMoreQuest"

local mapcost = {}

---Measures another addon's calls and share in place of OneMoreQuest's (for comparing the two at the same play).
function mapcost.setAddon(name)
    ADDON, OURS = name, "@Interface/AddOns/" .. name .. "/"
end
local G = sim.G

local isCounting, widgetCalls, callTotal = false, {}, 0
local byAddon, ourFunctions, samples = {}, {}, 0
local timed = {}
-- Options: the process's environment, or (the daemon's game does not see a command's own) a file beside this one,
-- sim/lib/mapcost.options, of NAME=value lines; mapcost.option(name) reads one
local options = {}
do
    local here = (getinfo(1, "S").source:gsub("\\", "/"):match("^@(.*)/[^/]*$") or ".")
    local file = io.open(here .. "/mapcost.options", "r")
    if file then
        for line in file:lines() do
            local name, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
            if name then
                options[name] = value
            end
        end
        file:close()
    end
end

---@return string? value An option of the audit's: from sim/lib/mapcost.options, else the environment
function mapcost.option(name)
    return options[name] or os.getenv(name)
end
local top = tonumber(mapcost.option("MAPCOST_TOP") or "0")
local callKinds = tonumber(mapcost.option("MAPCOST_CALLS") or "6") -- how many kinds of widget call a step lists

---Accepts and tracks quests of a zone for an audit: the first so many of its area (Riverglades') that a character
---of the audits' level can take, in the database's order, so every audit has the same ones.
---@param accept fun(questId: number) The scenario's own step (a scenario's steps are its globals, not a module's)
---@param count number How many
---@param areaId number? The zone's area (Riverglades, 16591)
---@return number[] questIds
function mapcost.trackZoneQuests(accept, count, areaId)
    local quests, accepted = G.LibQuestieDB.Quest, {}
    for questId = 1, 99999 do
        local isRead, zone = pcall(quests.Get, questId, "zoneOrSort")
        if isRead and zone == (areaId or 16591) and #accepted < count then
            local level = quests.Get(questId, "questLevel") or 0
            if level >= 34 and level <= 44 and pcall(accept, questId) then
                accepted[#accepted + 1] = questId
            end
        end
    end
    for _, questId in ipairs(accepted) do
        if not G.C_QuestLog.GetQuestWatchType(questId) then
            G.C_QuestLog.AddQuestWatch(questId)
        end
    end
    return accepted
end

---Wraps every widget method once: calls made from OneMoreQuest's code are counted while a measurement runs.
function mapcost.install()
    if mapcost.isInstalled then
        return
    end
    mapcost.isInstalled = true
    for _, definition in pairs(W.types) do
        for name, method in pairs(definition.methods) do
            if type(method) == "function" then
                definition.methods[name] = function(...)
                    if isCounting then
                        local info = getinfo(2, "S")
                        if info and info.source:sub(1, #OURS) == OURS then
                            widgetCalls[name] = (widgetCalls[name] or 0) + 1
                            callTotal = callTotal + 1
                        end
                    end
                    return method(...)
                end
            end
        end
    end
end

-- Samples: every 1000 instructions, the innermost addon on the stack (or "game" when none), and every function of
-- ours on it
local function sample()
    samples = samples + 1
    local owner, seen = nil, {}
    for level = 2, 80 do
        local info = getinfo(level, "Sn")
        if not info then
            break
        end
        local name = info.source:match("^@Interface/AddOns/([^/]+)/")
        if name and not owner then
            owner = name
        end
        if name == ADDON then
            local key = info.source:sub(#OURS + 1):gsub("%.lua$", "")
                .. ":"
                .. tostring(info.name or "?")
                .. "@"
                .. info.linedefined
            if not seen[key] then
                seen[key] = true
                ourFunctions[key] = (ourFunctions[key] or 0) + 1
            end
        end
    end
    owner = owner or "game"
    byAddon[owner] = (byAddon[owner] or 0) + 1
end

---Counts and times a function of the addon's (with the widget calls made under it) while a measurement runs.
function mapcost.timeFunction(owner, key, label)
    local original = owner and owner[key]
    if type(original) ~= "function" then
        return
    end
    owner[key] = function(...)
        if not isCounting then
            return original(...)
        end
        local started, callsBefore = os.clock(), callTotal
        local a, b, c, d = original(...)
        local entry = timed[label] or { count = 0, ms = 0, calls = 0 }
        entry.count, entry.ms = entry.count + 1, entry.ms + (os.clock() - started) * 1000
        entry.calls = entry.calls + (callTotal - callsBefore)
        timed[label] = entry
        return a, b, c, d
    end
end

local function sorted(counts)
    local rows, total = {}, 0
    for key, count in pairs(counts) do
        rows[#rows + 1] = { key, count }
        total = total + count
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    return rows, total
end

mapcost.results = {} -- [name] = { ms, ours, calls, worstMs, worstCalls }, for an audit's own summary

---Runs a piece of play and prints what it cost: the time in all and OneMoreQuest's share, the widget calls from its
---code, and the worst single frame (its time and its calls): a hitch is one frame's cost, not the sum.
function mapcost.measure(name, body)
    widgetCalls, byAddon, ourFunctions, samples, timed = {}, {}, {}, 0, {}
    mapcost.frameSeen = {}
    callTotal = 0
    collectgarbage("collect")
    local memory = collectgarbage("count")
    -- Each frame by itself: the worst is what the player feels
    local worstMs, worstCalls, frames = 0, 0, 0
    local tick = sim.tick
    sim.tick = function(elapsed)
        local started, callsBefore = os.clock(), callTotal
        local a, b = tick(elapsed)
        local spent = (os.clock() - started) * 1000
        frames = frames + 1
        worstMs, worstCalls = math.max(worstMs, spent), math.max(worstCalls, callTotal - callsBefore)
        if mapcost.frameLog then
            -- (each frame by itself, for an audit that wants the course of a zoom: its time, its calls, what ran)
            local ran = {}
            for label, entry in pairs(timed) do
                local before = mapcost.frameSeen[label] or 0
                if entry.count > before then
                    ran[#ran + 1] = label
                end
                mapcost.frameSeen[label] = entry.count
            end
            table.sort(ran)
            mapcost.frameLog[#mapcost.frameLog + 1] =
                { ms = spent, calls = callTotal - callsBefore, ran = table.concat(ran, ", ") }
        end
        return a, b
    end
    isCounting = true
    local started = os.clock()
    debug.sethook(sample, "", 1000)
    local isFine, problem = pcall(body)
    debug.sethook()
    local spent = (os.clock() - started) * 1000
    isCounting = false
    sim.tick = tick
    if not isFine then
        error(problem, 0)
    end
    local calls, total = sorted(widgetCalls)
    local kinds = {}
    for index = 1, math.min(callKinds, #calls) do
        kinds[index] = calls[index][1] .. " " .. calls[index][2]
    end
    local ours = (byAddon[ADDON] or 0) / math.max(samples, 1)
    print(
        string.format(
            "== %-30s %6.0f ms, OMQ ~%5.0f ms, calls %6d | worst frame %5.0f ms, %5d calls | [%s]",
            name,
            spent,
            spent * ours,
            total,
            worstMs,
            worstCalls,
            table.concat(kinds, ", ")
        )
    )
    mapcost.results[name] =
        { ms = spent, ours = spent * ours, calls = total, worstMs = worstMs, worstCalls = worstCalls, frames = frames }
    local parts = {}
    for label, entry in pairs(timed) do
        parts[#parts + 1] = string.format("%s x%d %.0f ms %d calls", label, entry.count, entry.ms, entry.calls)
    end
    table.sort(parts)
    if #parts > 0 then
        print(string.format("   %s   (+%.0f KB)", table.concat(parts, "; "), collectgarbage("count") - memory))
    end
    local functions = sorted(ourFunctions)
    for index = 1, math.min(top, #functions) do
        print(
            string.format(
                "     %3d%%  %s",
                math.floor(functions[index][2] / math.max(samples, 1) * 100 + 0.5),
                functions[index][1]
            )
        )
    end
end

---OneMoreQuest's regions under the world map's canvas: how many there are, how many are shown, and how many of
---those lie in the view (the rest drawn for nothing).
function mapcost.countRegions(label)
    local map = G.WorldMapFrame
    local view = W.computeRect(map.ScrollContainer)
    local all, shown, inView, frames = 0, 0, 0, 0
    local function walk(frame, isShown)
        isShown = isShown and frame:IsShown()
        frames = frames + 1
        local state = W.state[frame]
        for _, region in ipairs(state.regions or {}) do
            all = all + 1
            if isShown and region:IsShown() then
                shown = shown + 1
                local rect = W.computeRect(region)
                if rect and rect[3] >= view[1] and rect[1] <= view[3] and rect[4] >= view[2] and rect[2] <= view[4] then
                    inView = inView + 1
                end
            end
        end
        for _, child in ipairs(state.children or {}) do
            walk(child, isShown)
        end
    end
    local addon = require("addons").byName["onemorequest"].private
    for _, layer in ipairs(mapcost.getLayers(addon, map)) do
        walk(layer, true)
    end
    print(
        string.format(
            "   regions %-22s %5d made, %5d shown, %5d in view (%3d%%), %4d frames",
            label,
            all,
            shown,
            inView,
            shown > 0 and math.floor(inView / shown * 100 + 0.5) or 0,
            frames
        )
    )
    mapcost.sayHanging(map, label)
    local counts = addon.MapMarksWorld and addon.MapMarksWorld.getCounts(map) or {}
    if counts.spaces then
        print(
            string.format(
                "   kept: %d sets shown (%d a continent's) %d fills %d edges, %d walk lines, %d tiles %d spawn marks (level %s), %d spaces; kept in all %d pieces %d marks; %d to do",
                counts.setsShown,
                counts.wide,
                counts.fillsShown,
                counts.edgesShown,
                counts.walksShown,
                counts.tilesShown,
                counts.iconsShown,
                tostring(counts.level),
                counts.spacesShown,
                counts.kept,
                counts.keptIcons,
                counts.todo
            )
        )
    end
    return shown, inView, all
end

---What the game lays out again on every frame of a drag or a zoom: every frame and region hanging from the map's
---canvas by its anchors, shown or hidden (a hidden texture costs as much as one on screen; one with no anchors, or
---hung from something that is itself let go, costs nothing). Counted for OneMoreQuest's own (everything under its
---layers on the canvas) and for everything else on the canvas.
---@return { ours: number, oursShown: number, oursHidden: number, others: number, byKind: table<string, number> }
function mapcost.countHanging(map)
    local addon = require("addons").byName["onemorequest"]
    addon = addon and addon.private
    local canvas = map.ScrollContainer.Child
    local isOurLayer = {}
    for _, layer in ipairs(addon and mapcost.getLayers(addon, map) or {}) do
        isOurLayer[layer] = true
    end
    local hangs = { [canvas] = true } -- [object] = hangs from the canvas (false: looked at, does not)
    local function isHanging(object, depth)
        local known = hangs[object]
        if known ~= nil then
            return known
        end
        hangs[object] = false -- (a ring of anchors: not hanging)
        local state = W.state[object]
        local result = false
        if state and (depth or 0) < 40 then
            for _, anchor in ipairs(state.points or {}) do
                if anchor.relative and isHanging(anchor.relative, (depth or 0) + 1) then
                    result = true
                    break
                end
            end
            for _, name in ipairs({ "startPoint", "endPoint" }) do
                local anchor = state[name]
                if not result and anchor and anchor.relative and isHanging(anchor.relative, (depth or 0) + 1) then
                    result = true
                end
            end
        end
        hangs[object] = result
        return result
    end
    local counts = { ours = 0, oursShown = 0, oursHidden = 0, others = 0, byKind = {} }
    local function count(object, isOurs, isShown, kind)
        if isHanging(object) then
            if isOurs then
                counts.ours = counts.ours + 1
                if isShown then
                    counts.oursShown = counts.oursShown + 1
                else
                    counts.oursHidden = counts.oursHidden + 1
                end
                counts.byKind[kind] = (counts.byKind[kind] or 0) + 1
            else
                counts.others = counts.others + 1
            end
        end
    end
    local function walk(frame, isOurs, isShown, kind)
        local state = W.state[frame]
        isShown = isShown and frame:IsShown()
        count(frame, isOurs, isShown, kind .. " frames")
        for _, region in ipairs(state.regions or {}) do
            count(region, isOurs, isShown and region:IsShown(), kind)
        end
        for _, child in ipairs(state.children or {}) do
            walk(child, isOurs, isShown, kind)
        end
    end
    local names = {}
    if addon then
        local drawn, markLayer, areaLayer = addon.MapMarks.getDrawn(map)
        names[markLayer or false], names[areaLayer or false] = "old marks' layer", "old areas' layer"
        names[drawn.pinLayer or false], names[drawn.glowLayer or false] = "marks", "marks' glows"
        local roots = addon.MapMarksWorld and addon.MapMarksWorld.getLayers(map) or {}
        for index, root in ipairs(roots) do
            names[root] = index == 1 and "kept drawing" or "kept " .. index
        end
    end
    for _, child in ipairs(W.state[canvas].children or {}) do
        local isOurs = isOurLayer[child] == true or names[child] ~= nil
        walk(child, isOurs, true, names[child] or "other")
    end
    return counts
end

---Prints a map's hanging frames and regions (mapcost.countHanging), OneMoreQuest's by the layer they are on.
function mapcost.sayHanging(map, label)
    local counts = mapcost.countHanging(map)
    local kinds = {}
    for kind, count in pairs(counts.byKind) do
        kinds[#kinds + 1] = kind .. " " .. count
    end
    table.sort(kinds)
    print(
        string.format(
            "   hanging from the map %-18s OneMoreQuest %5d (%d shown, %d hidden), others %5d | %s",
            label or "",
            counts.ours,
            counts.oursShown,
            counts.oursHidden,
            counts.others,
            table.concat(kinds, ", ")
        )
    )
    return counts
end

---Where to press on a map to drag it: the point nearest its middle where a press reaches the map itself. (A mark
---under the cursor is a button and takes the press: nothing is dragged then, and a drag measured there measures
---nothing.)
---@return number x, number y On screen, as scene.input takes them
function mapcost.findGrip(map)
    local scene = require("scene")
    local rect = W.computeRect(map.ScrollContainer)
    local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
    for ring = 0, 14 do
        local steps = math.max(1, ring * 8)
        for step = 0, steps - 1 do
            local angle = step / steps * 2 * math.pi
            local x, y = cx + math.cos(angle) * ring * 12, cy + math.sin(angle) * ring * 12
            scene.input({ type = "move", x = x, y = y })
            local foci = G.GetMouseFoci and G.GetMouseFoci() or { G.GetMouseFocus and G.GetMouseFocus() }
            if foci[1] == map.ScrollContainer then
                return x, y
            end
        end
    end
    return cx, cy
end

---Drags a map by so many pixels, over 0.6 s, from a point of it that takes the drag (mapcost.findGrip).
---@return number movedX, number movedY How far its view went, in shares of the map underneath (0, 0: not dragged)
function mapcost.drag(map, dx, dy)
    local scene = require("scene")
    local container = map.ScrollContainer
    local x, y = mapcost.findGrip(map)
    local fromX, fromY = container:GetNormalizedHorizontalScroll(), container:GetNormalizedVerticalScroll()
    scene.input({ type = "down", x = x, y = y, button = "LeftButton" })
    for step = 1, 12 do
        scene.input({ type = "move", x = x + dx * step / 12, y = y + dy * step / 12 })
        sim.tick(0.05) -- (a frame of the game, as the scenarios' wait runs them)
    end
    scene.input({ type = "up", x = x + dx, y = y + dy, button = "LeftButton" })
    scene.input({ type = "move", x = x, y = y })
    return container:GetNormalizedHorizontalScroll() - fromX, container:GetNormalizedVerticalScroll() - fromY
end

---@return table[] layers OneMoreQuest's own frames on a map's canvas
function mapcost.getLayers(addon, map)
    local layers = {}
    local canvas = map.ScrollContainer.Child
    local state = W.state[canvas]
    local ours = {}
    local _, markLayer, areaLayer = addon.MapMarks.getDrawn(map)
    ours[markLayer or false], ours[areaLayer or false] = true, true
    for _, layer in ipairs(addon.MapMarksWorld and addon.MapMarksWorld.getLayers(map) or {}) do
        ours[layer] = true
    end
    local drawnNow = addon.MapMarks.getDrawn(map)
    ours[drawnNow.pinLayer or false], ours[drawnNow.glowLayer or false] = true, true
    for _, child in ipairs(state.children or {}) do
        if ours[child] then
            layers[#layers + 1] = child
        end
    end
    return layers
end

return mapcost
