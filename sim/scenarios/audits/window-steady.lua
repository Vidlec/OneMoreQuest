-- The quest window drawn again and again with nothing changed: how many widget calls each drawing makes
local W = require("widgets")
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local isCounting, count = false, 0
for _, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if isCounting then
                    local info = debug.getinfo(2, "S")
                    if info and info.source:sub(1, #PREFIX) == PREFIX then count = count + 1 end
                end
                return method(...)
            end
        end
    end
end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
local accepted = {}
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 570, 572, 573, 581, 582, 583, 584, 585, 586 }) do
    if #accepted < 20 and pcall(accept, questId) then accepted[#accepted + 1] = questId end
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
key("M"); wait(1.5)
local draws = {}
for index = 1, 5 do
    count, isCounting = 0, true
    addon.Log.refresh()
    isCounting = false
    draws[index] = count
    wait(0.2)
end
io.write("STEADY quest window drawn again, calls each time: ", table.concat(draws, " "), "\n")
draws = {}
for index = 1, 4 do
    count, isCounting = 0, true
    addon.Tracker.refresh()
    isCounting = false
    draws[index] = count
    wait(0.2)
end
io.write("STEADY tracker drawn again, calls each time: ", table.concat(draws, " "), "\n")
