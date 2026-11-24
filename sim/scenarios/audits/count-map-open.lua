-- Counts the draws one opening of the map runs (prints them)
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30)
for _, questId in ipairs({ 871, 867, 875, 899, 821, 903, 845, 850, 855, 1109, 1113 }) do
    pcall(accept, questId)
end
wait(3)
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
count("MapDock", addon.MapDock, "apply")
count("MapPins", addon.MapPins, "refresh")
count("MapMarks", addon.MapMarks, "draw")
count("MinimapPins", addon.MinimapPins, "refresh")
count("Tracker", addon.Tracker, "refresh")
count("Availability", addon.Availability, "getQuests")
local lastCalls = {}
local function report(title)
    lastCalls = calls
    local rows = {}
    for name, n in pairs(calls) do
        rows[#rows + 1] = name .. "=" .. n
    end
    table.sort(rows)
    print(title .. ": " .. table.concat(rows, "  "))
    calls = {}
end
key("M")
wait(1)
report("first open")
key("M")
wait(1)
report("close")
key("M")
wait(1)
report("second open")
key("M")
wait(1)
report("close again")
progress(871, 1, 1) -- a quest moves on while the map is closed
wait(1)
report("progress while closed")
key("M")
wait(1)
report("open after progress")
expect(
    (lastCalls["MapMarks.draw"] or 0) >= 1,
    "a quest that moved on while the map was closed: drawn again as it opens"
)
