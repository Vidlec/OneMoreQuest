-- Profiling a change of zone on the Available tab (a user felt it lag): the first visit of a zone, then again.
-- Writes sim/scenarios/.profile-zone-pick.txt.
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30) -- The Barrens
for _, questId in ipairs({ 871, 867, 875, 899, 821, 903, 845, 850, 855 }) do
    pcall(accept, questId)
end
wait(3)
key("M")
wait(1)
click("Available")
wait(2)

local addon = require("addons").byName["onemorequest"].private
local calls = {}
local function count(tableName, object, name)
    local original = object[name]
    object[name] = function(...)
        calls[tableName .. "." .. name] = (calls[tableName .. "." .. name] or 0) + 1
        return original(...)
    end
end
count("Log", addon.Log, "refresh")
count("MapMarks", addon.MapMarks, "draw")
count("Availability", addon.Availability, "getQuests")
count("Availability", addon.Availability, "getZones")
count("Availability", addon.Availability, "getZoneSummary")
count("Availability", addon.Availability, "invalidate")
count("Availability", addon.Availability, "forgetLists")

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
    if first then
        totals[phase] = (totals[phase] or 0) + 1
        counts["inner  " .. phase .. "  " .. first] = (counts["inner  " .. phase .. "  " .. first] or 0) + 1
        counts["entry  " .. phase .. "  " .. last] = (counts["entry  " .. phase .. "  " .. last] or 0) + 1
    end
end
local lines = {}
local function run(name, body)
    phase = name
    calls = {}
    debug.sethook(hook, "", 1000)
    local started = os.clock()
    body()
    local seconds = os.clock() - started
    debug.sethook()
    local rows = {}
    for callName, n in pairs(calls) do
        rows[#rows + 1] = callName .. "=" .. n
    end
    table.sort(rows)
    lines[#lines + 1] =
        string.format("%-22s %.3f s  OMQ samples %6d   %s", name, seconds, totals[name] or 0, table.concat(rows, " "))
end

run("map to Durotar", function()
    G.WorldMapFrame:SetMapID(1411)
    wait(1)
end)
run("map to The Barrens", function()
    G.WorldMapFrame:SetMapID(1413)
    wait(1)
end)
run("map to Durotar again", function()
    G.WorldMapFrame:SetMapID(1411)
    wait(1)
end)
run("map to Mulgore", function()
    G.WorldMapFrame:SetMapID(1412)
    wait(1)
end)
run("kill, Available open", function()
    pcall(kill, 3415)
    wait(1)
end)

local out = io.open(scenariosDir .. "/.profile-zone-pick.txt", "w")
for _, line in ipairs(lines) do
    out:write(line, "\n")
end
local rows = {}
for key, n in pairs(counts) do
    rows[#rows + 1] = { key, n }
end
table.sort(rows, function(a, b)
    return a[2] > b[2]
end)
for index = 1, math.min(#rows, 60) do
    out:write(string.format("%6d  %s\n", rows[index][2], rows[index][1]))
end
out:close()
