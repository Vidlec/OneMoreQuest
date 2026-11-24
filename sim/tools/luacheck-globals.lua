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
