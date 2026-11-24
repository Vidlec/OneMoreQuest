-- Who asks for the quest window and the map marks to be drawn when the map is opened again with nothing changed
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({
    185,
    186,
    187,
    188,
    189,
    190,
    191,
    192,
    193,
    194,
    195,
    196,
    197,
    568,
    569,
    570,
    572,
    573,
    581,
    582,
}) do
    pcall(accept, questId)
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
key("M")
wait(1.5)
key("M")
wait(0.5)
local function watch(owner, name, label)
    local original = owner[name]
    owner[name] = function(...)
        io.write("CALL ", label, "\n", debug.traceback("", 2):gsub("\n[^\n]*play%.lua.*", ""), "\n")
        return original(...)
    end
end
watch(addon.Log, "refresh", "Log.refresh")
watch(addon.MapMarks, "draw", "MapMarks.draw")
io.write("=== reopening\n")
key("M")
wait(1.5)
io.write("=== done\n")
