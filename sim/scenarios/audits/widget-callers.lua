-- Which of OneMoreQuest's own functions make the widget calls of each operation: where the redrawing still asks
-- the game for things that have not changed. Square minimap (Forever's own).
local W = require("widgets")
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local getinfo = debug.getinfo
local isCounting, callers = false, {}
for _, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if isCounting then
                    local info = getinfo(2, "Sl")
                    if info and info.source:sub(1, #PREFIX) == PREFIX then
                        local file = info.source:sub(#PREFIX + 1):gsub("%.lua$", "")
                        -- The addon's own function the call is in, and the one that called it
                        local own = getinfo(2, "n")
                        local parent = getinfo(3, "Sn")
                        local key = file .. ":" .. (own and own.name or "?") .. "@" .. info.currentline
                        if os.getenv("CALLERS_BY") == "function" then
                            local outer = parent and parent.source:sub(1, #PREFIX) == PREFIX and (parent.name or "?")
                                or "-"
                            key = file .. ":" .. (info.linedefined or 0) .. " < " .. outer
                        end
                        local row = callers[key]
                        if not row then
                            row = { total = 0, methods = {} }
                            callers[key] = row
                        end
                        row.total = row.total + 1
                        row.methods[name] = (row.methods[name] or 0) + 1
                    end
                end
                return method(...)
            end
        end
    end
end
G.GetMinimapShape = function()
    return "SQUARE"
end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
local accepted = {}
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
}) do
    if #accepted < 20 and pcall(accept, questId) then
        accepted[#accepted + 1] = questId
    end
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local LIMIT = tonumber(os.getenv("CALLERS_TOP") or "14")
local wanted = os.getenv("CALLERS_ONLY")
local function measure(name, body)
    if wanted and not name:find(wanted, 1, true) then
        body()
        return
    end
    callers = {}
    isCounting = true
    body()
    isCounting = false
    local rows, total = {}, 0
    for key, row in pairs(callers) do
        rows[#rows + 1] = { key, row }
        total = total + row.total
    end
    table.sort(rows, function(a, b)
        return a[2].total > b[2].total
    end)
    io.write(string.format("CALLERS == %s: %d widget calls\n", name, total))
    for index = 1, math.min(#rows, LIMIT) do
        local methods = {}
        for method, count in pairs(rows[index][2].methods) do
            methods[#methods + 1] = { method, count }
        end
        table.sort(methods, function(a, b)
            return a[2] > b[2]
        end)
        local parts = {}
        for position = 1, math.min(#methods, 5) do
            parts[position] = methods[position][1] .. " " .. methods[position][2]
        end
        io.write(
            string.format("CALLERS %6d  %-44s %s\n", rows[index][2].total, rows[index][1], table.concat(parts, ", "))
        )
    end
end
key("M")
wait(1.5)
measure("map marks drawn again in full (warm)", function()
    addon.MapPins.refresh()
end)
measure("quest window drawn (warm)", function()
    addon.Log.refresh()
end)
measure("a kill that counts, map open", function()
    progress(accepted[1], 1, 1)
    wait(0.6)
end)
key("M")
wait(0.5)
measure("tracker drawn", function()
    addon.Tracker.refresh()
end)
measure("minimap marks chosen and drawn", function()
    addon.MinimapPins.refresh()
end)
face(45)
measure("3 s walking, map closed", function()
    hold("W", 3)
end)
measure("3 s standing, map closed", function()
    wait(3)
end)
