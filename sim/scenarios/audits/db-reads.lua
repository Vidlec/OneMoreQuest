-- Which QuestieDB reads each drawing makes, and how many of them repeat (the same entity and field read again)
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 570, 572, 573, 581, 582 }) do pcall(accept, questId) end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local reads, isCounting = {}, false
for _, entity in ipairs({ "Quest", "Npc", "Object", "Item" }) do
    local api = G.LibQuestieDB[entity]
    if api and api.Get then
        local original = api.Get
        api.Get = function(id, field)
            if isCounting then
                local key = entity .. "." .. tostring(field)
                reads[key] = reads[key] or { count = 0, seen = {}, distinct = 0, isTable = false }
                local entry = reads[key]
                entry.count = entry.count + 1
                if not entry.seen[id] then entry.seen[id] = true; entry.distinct = entry.distinct + 1 end
                local value = original(id, field)
                if type(value) == "table" then entry.isTable = true end
                return value
            end
            return original(id, field)
        end
    end
end
local function measure(name, body)
    reads = {}
    isCounting = true
    body()
    isCounting = false
    local rows, total, tableReads, tableDistinct = {}, 0, 0, 0
    for key, entry in pairs(reads) do
        rows[#rows + 1] = { key, entry }
        total = total + entry.count
        if entry.isTable then tableReads = tableReads + entry.count; tableDistinct = tableDistinct + entry.distinct end
    end
    table.sort(rows, function(a, b) return a[2].count > b[2].count end)
    io.write(string.format("DB %s: %d reads, %d of them of table fields (a fresh decode each), which were only %d different entity-fields\n", name, total, tableReads, tableDistinct))
    for index = 1, math.min(#rows, 14) do
        local key, entry = rows[index][1], rows[index][2]
        io.write(string.format("DB    %-26s %5d reads of %4d different%s\n", key, entry.count, entry.distinct, entry.isTable and "  (table)" or ""))
    end
end
key("M"); wait(2)
measure("map marks drawn in full", function() addon.MapPins.refresh() end)
measure("map marks drawn in full, again at once", function() addon.MapPins.refresh() end)
measure("quest window: My quests", function() addon.Log.refresh() end)
measure("minimap marks chosen", function() addon.MinimapPins.refresh() end)
measure("tracker drawn", function() addon.Tracker.refresh() end)
measure("a kill that counts, map open", function() progress(185, 1, 1); wait(0.6) end)
measure("Available tab opened", function() click("Available"); wait(1) end)
