--@addons QuestieDB, ForeverDungeonJournal
--@login race=Orc,class=WARRIOR,level=20
wait(1)
local names = {}
for name in pairs(G) do
    if type(name) == "string" and name:match("^[%a_][%w_]*$") then
        names[#names + 1] = name
    end
end
table.sort(names)
local build = select(1, G.GetBuildInfo()) .. "." .. select(2, G.GetBuildInfo())
local out = assert(io.open(projectRoot .. "/.luacheck/forever-globals.lua", "wb"))
out:write(
    "-- Every global a WoW: Forever addon can read (client ",
    build,
    "): the client's API, the game's own Lua and its\n"
)
out:write(
    "-- named frames, and QuestieDB's and ForeverDungeonJournal's. Made by the simulator with the whole interface\n"
)
out:write("-- loaded, OneMoreQuest left out; made again after a client update: bun run luacheck:globals\n")
out:write("return {\n")
for _, name in ipairs(names) do
    out:write('    "', name, '",\n')
end
out:write("}\n")
out:close()
print("GLOBALS", #names, build)

-- The simulator's scenario steps (moveTo, wait, expect...), the globals every file of sim/ runs with: read from
-- AddonSim's declarations for the language server, and kept here so luacheck knows them where AddonSim is not
-- installed (CI)
local declarations = assert(io.open(projectRoot .. "/node_modules/addonsim/types/addonsim.lua", "rb"))
local steps, isListed = { "sim", "combat" }, { sim = true, combat = true, G = true } -- (G: writable, .luacheckrc)
for line in declarations:lines() do
    local name = line:match("^function ([%a_][%w_]*)%(") or line:match("^([%a_][%w_]*) = ")
    if name and not isListed[name] then
        isListed[name] = true
        steps[#steps + 1] = name
    end
end
declarations:close()
table.sort(steps)
local stepsOut = assert(io.open(projectRoot .. "/.luacheck/addonsim-steps.lua", "wb"))
stepsOut:write(
    "-- The simulator's scenario steps, the globals every file of sim/ runs with (G aside: a scenario may change\n"
)
stepsOut:write(
    "-- the game's globals through it). Read from AddonSim's types/addonsim.lua; made again after an AddonSim update:\n"
)
stepsOut:write("-- bun run luacheck:globals\n")
stepsOut:write("return {\n")
for _, name in ipairs(steps) do
    stepsOut:write('    "', name, '",\n')
end
stepsOut:write("}\n")
stepsOut:close()
print("STEPS", #steps)
