-- How long the quest window takes to draw, tab by tab (Grom'gol, a full Stranglethorn quest log)
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
    583,
    584,
    585,
    586,
    587,
    588,
    589,
    591,
    592,
    593,
    594,
    595,
    596,
    597,
    598,
    599,
    600,
}) do
    pcall(accept, questId)
end
wait(2)
key("M")
wait(2)
local addon = require("addons").byName["onemorequest"].private
local function timeRefresh(name)
    local started = os.clock()
    for _ = 1, 5 do
        addon.Log.refresh()
    end
    io.write(string.format("WINDOW %-28s %.1f ms a drawing (LuaJIT)\n", name, (os.clock() - started) * 200))
end
click("Available")
wait(1)
local started = os.clock()
for _ = 1, 5 do
    addon.Log.refresh()
end
io.write(string.format("WINDOW Available %.1f ms a drawing (LuaJIT)", (os.clock() - started) * 200), string.char(10))
local prefix = "@Interface/AddOns/OneMoreQuest/"
local getinfo = debug.getinfo
local counts, selfCounts = {}, {}
local function hook()
    local seen, first = {}, true
    for level = 2, 60 do
        local info = getinfo(level, "Sn")
        if not info then
            break
        end
        if info.source:sub(1, #prefix) == prefix then
            local name = info.source:sub(#prefix + 1) .. ":" .. info.linedefined .. " " .. tostring(info.name)
            if first then
                selfCounts[name] = (selfCounts[name] or 0) + 1
                first = false
            end
            if not seen[name] then
                seen[name] = true
                counts[name] = (counts[name] or 0) + 1
            end
        end
    end
end
debug.sethook(hook, "", 1000)
for _ = 1, 10 do
    addon.Log.refresh()
end
debug.sethook()
local function dump(title, t)
    local rows = {}
    for k, v in pairs(t) do
        rows[#rows + 1] = { k, v }
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    for i = 1, math.min(#rows, 22) do
        io.write(string.format("%s %5d %s" .. string.char(10), title, rows[i][2], rows[i][1]))
    end
end
dump("INCL", counts)
dump("SELF", selfCounts)
