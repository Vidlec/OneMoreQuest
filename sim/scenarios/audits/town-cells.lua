-- What reads the NPCs of the database after login (53,000 reads in the first seconds), by who asks
local addon = require("addons").byName["onemorequest"].private
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local callers, fields, total = {}, {}, 0
for _, entity in ipairs({ "Npc", "Quest", "Object", "Item" }) do
    local get = G.LibQuestieDB[entity].Get
    G.LibQuestieDB[entity].Get = function(id, field)
        total = total + 1
        fields[entity .. "." .. tostring(field)] = (fields[entity .. "." .. tostring(field)] or 0) + 1
        if total % 7 == 0 then -- a sample of who asks
            local names = {}
            for level = 2, 12 do
                local info = debug.getinfo(level, "Sn")
                if not info then break end
                if info.source:sub(1, #PREFIX) == PREFIX then
                    names[#names + 1] = info.source:sub(#PREFIX + 1) .. ":" .. (info.name or "?")
                    if #names >= 4 then break end
                end
            end
            local key = table.concat(names, " < ")
            callers[key] = (callers[key] or 0) + 7
        end
        return get(id, field)
    end
end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190 }) do pcall(accept, questId) end
wait(3)
io.write("READS in the first 3 seconds: ", total, "\n")
local function dump(title, counts, limit)
    local rows = {}
    for key, count in pairs(counts) do rows[#rows + 1] = { key, count } end
    table.sort(rows, function(a, b) return a[2] > b[2] end)
    for index = 1, math.min(#rows, limit) do io.write(string.format("%s %6d  %s\n", title, rows[index][2], rows[index][1])) end
end
dump("FIELD", fields, 12)
dump("WHO", callers, 12)
