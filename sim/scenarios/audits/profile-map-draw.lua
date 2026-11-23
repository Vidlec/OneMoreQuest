-- Where one drawing of the world map's marks spends its time (Grom'gol, a Stranglethorn quest log)
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 570, 572, 573, 581, 582, 583, 584, 585, 586, 587, 588, 589, 591, 592, 593, 594, 595, 596, 597, 598, 599, 600 }) do pcall(accept, questId) end
wait(2)
key("M"); wait(3)
local addon = require("addons").byName["onemorequest"].private
io.write("QUESTS in log: ", #addon.QuestState.getLogQuestIds(), "\n")
local prefix = "@Interface/AddOns/OneMoreQuest/"
local getinfo = debug.getinfo
local counts, selfCounts, total = {}, {}, 0
local function hook()
    local seen = {}
    local first = true
    for level = 2, 60 do
        local info = getinfo(level, "Sn")
        if not info then break end
        if info.source:sub(1, #prefix) == prefix then
            local name = info.source:sub(#prefix + 1) .. ":" .. info.linedefined .. " " .. tostring(info.name)
            if first then selfCounts[name] = (selfCounts[name] or 0) + 1; first = false end
            if not seen[name] then seen[name] = true; counts[name] = (counts[name] or 0) + 1 end
        end
    end
    total = total + 1
end
local started = os.clock()
debug.sethook(hook, "", 1000)
for _ = 1, 10 do addon.MapPins.refresh() end
debug.sethook()
io.write(string.format("DRAW %.1f ms each (LuaJIT), %d samples\n", (os.clock() - started) * 100, total))
local function dump(title, t)
    local rows = {}
    for k, v in pairs(t) do rows[#rows + 1] = { k, v } end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    for i = 1, math.min(#rows, 25) do io.write(string.format("%s %5d %s\n", title, rows[i][2], rows[i][1])) end
end
dump("INCL", counts)
dump("SELF", selfCounts)
