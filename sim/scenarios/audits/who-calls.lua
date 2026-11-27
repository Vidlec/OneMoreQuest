-- Who, in OneMoreQuest, calls a game function so often as the map first opens (the chain of its own functions)
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local target = os.getenv("WHO_CALLS") or "IsQuestFlaggedCompleted"
local chains, total, isCounting = {}, 0, false
local original = G.C_QuestLog[target]
G.C_QuestLog[target] = function(...)
    if isCounting then
        total = total + 1
        local names = {}
        for level = 2, 30 do
            local info = debug.getinfo(level, "Sn")
            if not info then
                break
            end
            if info.source:sub(1, #PREFIX) == PREFIX then
                names[#names + 1] = info.source:sub(#PREFIX + 1):gsub("%.lua$", "") .. ":" .. (info.name or "?")
                if #names >= 7 then
                    break
                end
            end
        end
        local key = table.concat(names, " < ")
        chains[key] = (chains[key] or 0) + 1
    end
    return original(...)
end
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
}) do
    pcall(accept, questId)
end
wait(3)
isCounting = true
key("M")
wait(1.5)
isCounting = false
io.write("WHO ", target, ": ", total, " calls as the map first opens\n")
local rows = {}
for key, count in pairs(chains) do
    rows[#rows + 1] = { key, count }
end
table.sort(rows, function(a, b)
    return a[2] > b[2]
end)
for index = 1, math.min(#rows, 8) do
    io.write(string.format("WHO %6d  %s\n", rows[index][2], rows[index][1]))
end
