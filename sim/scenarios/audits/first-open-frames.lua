-- The first opening of the map, frame by frame: how many widget calls OneMoreQuest's own code makes in each
local W = require("widgets")
local sim = require("sim")
local scene = require("scene")
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
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 570, 572, 573, 581, 582 }) do accept(questId) end
wait(3)
local function frames(name, start, ticks)
    isCounting = true
    count = 0
    start()
    local perFrame = { count }
    for _ = 1, ticks do
        count = 0
        sim.tick(0.05)
        perFrame[#perFrame + 1] = count
    end
    isCounting = false
    local total, peak = 0, 0
    for _, calls in ipairs(perFrame) do total = total + calls; peak = math.max(peak, calls) end
    io.write(string.format("FRAMES %-34s total %6d, worst frame %6d: %s\n", name, total, peak, table.concat(perFrame, " ")))
end
frames("first map open (cold)", function() scene.input({ type = "key", key = "M" }) end, 24)
scene.input({ type = "key", key = "M" }); wait(0.5)
frames("map reopened, nothing changed", function() scene.input({ type = "key", key = "M" }) end, 12)
local addon = require("addons").byName["onemorequest"].private
frames("a kill that counts, map open", function() game.progressQuest(185, 1, 1) end, 12)
