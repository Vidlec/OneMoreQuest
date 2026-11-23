-- Run after a scenario (ADDONSIM_AFTER=sim/scenarios/audits/after-verify-reads.lua): OneMoreQuest keeps what it reads of
-- the quest database and shares it between callers, so no caller may change a table it was given. Every kept value
-- is compared here with a fresh read of the database: one that differs was changed by somebody.
local addon = require("addons").byName["onemorequest"]
addon = addon and addon.private
if addon and addon.Database and addon.Database.verifyReads then
    local problems = addon.Database.verifyReads()
    io.write(string.format("READS verified: %d kept values no longer match the database\n", #problems))
    for index = 1, math.min(#problems, 20) do
        io.write("READS changed: ", problems[index], "\n")
    end
    expect(#problems == 0, "no caller changed a table it read from the quest database (" .. #problems .. " changed: "
        .. table.concat(problems, ", ", 1, math.min(#problems, 5)) .. ")")
end
