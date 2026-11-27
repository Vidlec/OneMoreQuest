-- Profiling the map's first opening after login against a later one: what is worked out only the first time.
-- Writes sim/scenarios/.profile-map-open.txt.
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
local getinfo = debug.getinfo
local phase, counts, totals = "", {}, {}
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
    totals[phase] = (totals[phase] or 0) + 1
    if first then
        totals[phase .. " (OMQ)"] = (totals[phase .. " (OMQ)"] or 0) + 1
        counts["inner  " .. phase .. "  " .. first] = (counts["inner  " .. phase .. "  " .. first] or 0) + 1
        counts["entry  " .. phase .. "  " .. last] = (counts["entry  " .. phase .. "  " .. last] or 0) + 1
    end
end
local clock = {}
local function run(name, body)
    phase = name
    debug.sethook(hook, "", 1000)
    local started = os.clock()
    body()
    clock[#clock + 1] = string.format("%-14s %.3f s cpu", name, os.clock() - started)
    debug.sethook()
end
-- The key press itself (OnShow and everything it does at once), then the frames after it (timers, jobs)
run("first open", function()
    key("M")
end)
run("first after", function()
    wait(2)
end)
key("M")
wait(1)
run("second open", function()
    key("M")
end)
run("second after", function()
    wait(2)
end)

local out = io.open(scenariosDir .. "/.profile-map-open.txt", "w")
for _, line in ipairs(clock) do
    out:write(line, "\n")
end
local rows = {}
for key, count in pairs(totals) do
    rows[#rows + 1] = { key, count }
end
for key, count in pairs(counts) do
    rows[#rows + 1] = { key, count }
end
table.sort(rows, function(a, b)
    return a[2] > b[2]
end)
for index = 1, math.min(#rows, 90) do
    out:write(string.format("%6d  %s\n", rows[index][2], rows[index][1]))
end
out:close()
