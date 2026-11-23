-- Which of the game's functions OneMoreQuest calls while nothing happens (and while walking), by name and how
-- often: for what runs every frame. GAME_CALLS_WALK=1 walks instead of standing.
G.GetMinimapShape = function() return "SQUARE" end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
local accepted = {}
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 570, 572, 573, 581, 582, 583, 584, 585, 586 }) do
    if #accepted < 20 and pcall(accept, questId) then accepted[#accepted + 1] = questId end
end
wait(3)
local counts, isCounting = {}, false
local getinfo = debug.getinfo
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local function isFromAddon()
    for level = 3, 12 do
        local info = getinfo(level, "S")
        if not info then return false end
        if info.source:sub(1, #PREFIX) == PREFIX then return true end
    end
    return false
end
local function wrap(owner, name, label, fn)
    owner[name] = function(...)
        if isCounting and isFromAddon() then counts[label] = (counts[label] or 0) + 1 end
        return fn(...)
    end
end
local LUA_OWN = { pairs = true, ipairs = true, type = true, tostring = true, tonumber = true, select = true, unpack = true, next = true,
    rawget = true, rawset = true, setmetatable = true, getmetatable = true, pcall = true, xpcall = true, error = true, assert = true,
    print = true, loadstring = true, setfenv = true, getfenv = true, rawequal = true, collectgarbage = true, format = true,
    strsplit = true, strjoin = true, strtrim = true, tinsert = true, tremove = true, wipe = true, sort = true, floor = true, ceil = true,
    max = true, min = true, abs = true, date = true, time = true, debugprofilestop = true }
for key, value in pairs(G) do
    if type(value) == "table" and type(key) == "string" and key:match("^C_") then
        for name, fn in pairs(value) do
            if type(fn) == "function" then wrap(value, name, key .. "." .. name, fn) end
        end
    elseif type(value) == "function" and type(key) == "string" and not LUA_OWN[key] and not key:match("^str") and key:match("^[A-Z]") then
        wrap(G, key, key, value)
    end
end
local W = require("widgets")
for typeName, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if isCounting and isFromAddon() then counts[":" .. name] = (counts[":" .. name] or 0) + 1 end
                return method(...)
            end
        end
    end
end
isCounting = true
if os.getenv("GAME_CALLS_WALK") == "1" then hold("W", 2) else wait(2) end
isCounting = false
local rows = {}
for name, count in pairs(counts) do rows[#rows + 1] = { name, count } end
table.sort(rows, function(a, b) return a[2] > b[2] end)
local total = 0
for _, row in ipairs(rows) do total = total + row[2] end
io.write(string.format("CALLS == %d a second in all\n", total / 2))
for index = 1, math.min(#rows, 30) do
    io.write(string.format("CALLS   %6.1f a second  %s\n", rows[index][2] / 2, rows[index][1]))
end
