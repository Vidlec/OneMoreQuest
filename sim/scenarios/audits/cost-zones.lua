-- How long the Available lists take to work out from nothing (after a refresh forgets them)
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30)
for _, questId in ipairs({ 871, 867, 875, 899, 821, 903 }) do pcall(accept, questId) end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local A = addon.Availability
local function time(name, fn)
    local started = os.clock()
    for _ = 1, 5 do A.invalidate(); fn() end
    io.write(string.format("COST %-34s %.1f ms each (LuaJIT)\n", name, (os.clock() - started) * 1000 / 5))
end
time("getZones", function() A.getZones({}) end)
time("getQuests(Barrens)", function() A.getQuests(17, {}) end)
time("getQuests(Durotar)", function() A.getQuests(14, {}) end)
time("getZoneSummary(Barrens)", function() A.getZoneSummary(17) end)
jit.off()
time("getZones, interpreter only", function() A.getZones({}) end)
time("getQuests(Barrens), interpreter", function() A.getQuests(17, {}) end)
