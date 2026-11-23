-- Profiling the quest window's Available tab, open on the map: standing, walking, a kill. A user felt it stutter.
-- Writes sim/scenarios/.profile-available.txt.
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30) -- The Barrens, by the Crossroads
for _, questId in ipairs({ 871, 867, 875, 899, 821, 903, 845, 850, 855, 1109, 1113 }) do pcall(accept, questId) end
wait(3)
key("M")
wait(1)

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
count("MapPins", addon.MapPins, "refresh")
count("MinimapPins", addon.MinimapPins, "refresh")
count("Tracker", addon.Tracker, "refresh")
count("Availability", addon.Availability, "getQuests")
count("Availability", addon.Availability, "invalidate")

local prefix = "@Interface/AddOns/OneMoreQuest/"
local getinfo = debug.getinfo
local phase, counts, totals = "", {}, {}
local function hook()
    local first, last
    for level = 2, 60 do
        local info = getinfo(level, "S")
        if not info then break end
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
    body()
    debug.sethook()
    local rows = {}
    for callName, n in pairs(calls) do rows[#rows + 1] = callName .. "=" .. n end
    table.sort(rows)
    lines[#lines + 1] = string.format("%-26s OMQ samples %6d   %s", name, totals[name] or 0, table.concat(rows, " "))
end

run("my quests, idle 10s", function() wait(10) end)
click("Available")
wait(1)
run("available, idle 10s", function() wait(10) end)
run("available, walk 10s", function() hold("W", 10) end)
run("available, 5 kills", function() for _ = 1, 5 do pcall(kill, 3415) end end)
run("available, bag update", function() for _ = 1, 5 do fire("BAG_UPDATE_DELAYED"); wait(0.5) end end)

local out = io.open(scenariosDir .. "/.profile-available.txt", "w")
for _, line in ipairs(lines) do out:write(line, "\n") end
local rows = {}
for key, n in pairs(counts) do rows[#rows + 1] = { key, n } end
table.sort(rows, function(a, b) return a[2] > b[2] end)
for index = 1, math.min(#rows, 70) do out:write(string.format("%6d  %s\n", rows[index][2], rows[index][1])) end
out:close()
