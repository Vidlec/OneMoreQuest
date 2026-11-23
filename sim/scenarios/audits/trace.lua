-- /omq trace records by itself: slow frames with what of ours ran, the map's openings, the game's counts.
-- The simulator has no addon profiler: a stand-in says OneMoreQuest took 20 ms every frame.
G.C_AddOnProfiler = {
    IsEnabled = function() return true end,
    GetAddOnMetric = function(name, metric) return name == "OneMoreQuest" and 20 or 0 end,
    GetOverallMetric = function() return 25 end,
}
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30)
for _, questId in ipairs({ 871, 867, 875, 899 }) do pcall(accept, questId) end
wait(2)
slash("/omq trace")
hold("W", 3)
key("M"); wait(2); key("M"); wait(0.5)
pcall(kill, 3415)
wait(1)
slash("/omq trace")
local addon = require("addons").byName["onemorequest"].private
local trace = addon.settings.performanceTrace
expect(trace ~= nil, "the trace is in the saved settings")
expect(#trace.slowFrames > 0, "slow frames written down")
expect(#trace.openings >= 1, "the map's opening written down")
expect(#trace.snapshots >= 2, "the game's counts at the start and the end")
local withParts = 0
for _, frame in ipairs(trace.slowFrames) do if #frame.parts > 0 then withParts = withParts + 1 end end
expect(withParts > 0, "with what of ours ran in them")
io.write("TRACE ", #trace.slowFrames, " slow frames, ", #trace.openings, " openings, ", #trace.snapshots, " snapshots\n")
for index = 1, #trace.slowFrames do
    local frame = trace.slowFrames[index]
    if #frame.parts > 0 then io.write("FRAME ", frame.at, "s: ", table.concat(frame.parts, "; "), "\n") end
    if index > 400 then break end
end
for _, opening in ipairs(trace.openings) do io.write("OPEN ", table.concat(opening.ours, ", "), " | ", table.concat(opening.causes, ", "), "\n") end
