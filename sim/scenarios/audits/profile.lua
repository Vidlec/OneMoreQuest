-- Profiling: where OneMoreQuest spends its time in an ordinary session (idle, walking, the map open, killing).
-- Samples every few thousand Lua instructions; each sample goes to the innermost OneMoreQuest function and to the
-- outermost one (the entry: an OnUpdate, an event, a timer). Writes sim/scenarios/.profile.txt.
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30) -- The Barrens, by the Crossroads
for _, questId in ipairs({
    871,
    867,
    875,
    899,
    821,
    903,
    845,
    850,
    855,
    1109,
    1113,
    5052,
    848,
    870,
    877,
    880,
    881,
    887,
    888,
    894,
}) do
    pcall(accept, questId)
end
wait(3)

local prefix = "@Interface/AddOns/OneMoreQuest/"
local inner, outer, phaseSamples = {}, {}, {}
local phase = "setup"
local getinfo = debug.getinfo
local function hook()
    local first, last
    for level = 2, 60 do
        local info = getinfo(level, "S")
        if not info then
            break
        end
        if info.source:sub(1, #prefix) == prefix then
            local name = info.source:sub(#prefix + 1) .. ":" .. info.linedefined
            first = first or name
            last = name
        end
    end
    phaseSamples[phase] = (phaseSamples[phase] or 0) + 1
    if first then
        local key = phase .. "  " .. first
        inner[key] = (inner[key] or 0) + 1
        local entry = phase .. "  " .. last
        outer[entry] = (outer[entry] or 0) + 1
        phaseSamples[phase .. " (OMQ)"] = (phaseSamples[phase .. " (OMQ)"] or 0) + 1
    end
end
local clock = {}
local function run(name, body)
    phase = name
    debug.sethook(hook, "", 1000)
    local started = os.clock()
    body()
    clock[name] = os.clock() - started
    debug.sethook()
end

run("idle 30s", function()
    wait(30)
end)
run("walk 30s", function()
    hold("W", 30)
end)
run("map open, idle 10s", function()
    key("M")
    wait(10)
end)
run("map open, walk 10s", function()
    hold("W", 10)
    key("ESCAPE")
end)
run("kills x20", function()
    for _ = 1, 20 do
        pcall(kill, 3415)
    end -- Savannah Prowler
end)

local out = io.open(scenariosDir .. "/.profile.txt", "w")
local function dump(title, counts)
    out:write("== ", title, "\n")
    local rows = {}
    for key, count in pairs(counts) do
        rows[#rows + 1] = { key, count }
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    for index = 1, math.min(#rows, 60) do
        out:write(string.format("%6d  %s\n", rows[index][2], rows[index][1]))
    end
end
for name, seconds in pairs(clock) do
    out:write(string.format("%-22s %.2f s cpu\n", name, seconds))
end
dump("samples per phase", phaseSamples)
dump("outermost OMQ function (entry)", outer)
dump("innermost OMQ function", inner)
out:close()
