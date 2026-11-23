-- What a move of the minimap's marks costs on a square minimap (Forever's), with the fills on their canvas and without
local W = require("widgets")
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local isCounting, calls = false, {}
for _, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if isCounting then
                    local info = debug.getinfo(2, "S")
                    if info and info.source:sub(1, #PREFIX) == PREFIX then calls[name] = (calls[name] or 0) + 1 end
                end
                return method(...)
            end
        end
    end
end
G.GetMinimapShape = function() return "SQUARE" end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 570, 572, 573, 581, 582 }) do accept(questId) end
local addon = require("addons").byName["onemorequest"].private
wait(3)
local function measure(name, body)
    calls = {}
    isCounting = true
    body()
    isCounting = false
    local rows, total = {}, 0
    for method, count in pairs(calls) do rows[#rows + 1] = { method, count }; total = total + count end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    local parts = {}
    for index = 1, math.min(#rows, 9) do parts[index] = rows[index][1] .. " " .. rows[index][2] end
    io.write(string.format("MOVE %-44s %6d widget calls  (%s)\n", name, total, table.concat(parts, ", ")))
end
for _, isOff in ipairs({ os.getenv("CANVAS_OFF") == "1" }) do
    addon.MinimapPins.isCanvasOff = isOff
    addon.MinimapPins.refresh(); wait(1)
    local label = isOff and "every triangle placed" or "fills on the canvas"
    face(45)
    measure(label .. ": 3 s walking", function() hold("W", 3) end)
    measure(label .. ": 3 s standing", function() wait(3) end)
    measure(label .. ": a kill that counts", function() progress(185, 1, 1); wait(0.6) end)
end
