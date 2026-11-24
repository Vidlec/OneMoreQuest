-- What each thing OneMoreQuest does asks of the game's UI: the widget calls its own code makes (SetPoint, SetText,
-- Show...), the objects it creates, and the game functions it calls. Counted, not timed: the numbers hold on any
-- machine, and in the real client each call crosses from Lua into the game, where most of the time goes.
-- Writes sim/scenarios/.api-budget.txt.
local W = require("widgets")
local sim = require("sim")
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local getinfo = debug.getinfo

local isCounting = false
local widgetCalls, creations, gameCalls = {}, {}, {}
local CREATORS = {
    CreateTexture = "textures",
    CreateFontString = "font strings",
    CreateMaskTexture = "mask textures",
    CreateLine = "lines",
}

local function isFromAddon()
    local info = getinfo(3, "S")
    return info and info.source:sub(1, #PREFIX) == PREFIX
end

-- Every widget method, of every widget type: counted when OneMoreQuest's own code is the caller
for _, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if isCounting and isFromAddon() then
                    widgetCalls[name] = (widgetCalls[name] or 0) + 1
                    if
                        traceMethod == name
                        and (traceLeft or 0) > 0
                        and (widgetCalls[name] % (traceEvery or 1)) == 1
                    then
                        traceLeft = traceLeft - 1
                        io.write(
                            "TRACE ",
                            name,
                            " ",
                            (debug.traceback("", 2):gsub("%s+", " ")):sub(1, 1100),
                            string.char(10)
                        )
                    end
                    if CREATORS[name] then
                        creations[CREATORS[name]] = (creations[CREATORS[name]] or 0) + 1
                    end
                end
                return method(...)
            end
        end
    end
end
-- The game's functions: CreateFrame, and everything in the C_ namespaces and the plain globals an addon calls
local LUA_OWN = {
    string = true,
    table = true,
    math = true,
    coroutine = true,
    bit = true,
    os = true,
    debug = true,
    io = true,
    package = true,
}
local function wrapGame(owner, key, label)
    local original = owner[key]
    owner[key] = function(...)
        if isCounting and isFromAddon() then
            gameCalls[label] = (gameCalls[label] or 0) + 1
            if label == "CreateFrame" then
                creations.frames = (creations.frames or 0) + 1
            end
        end
        return original(...)
    end
end
local LUA_GLOBALS = {
    pairs = true,
    ipairs = true,
    type = true,
    tostring = true,
    tonumber = true,
    select = true,
    unpack = true,
    next = true,
    rawget = true,
    rawset = true,
    setmetatable = true,
    getmetatable = true,
    pcall = true,
    xpcall = true,
    error = true,
    assert = true,
    print = true,
    require = true,
    loadstring = true,
    dofile = true,
    loadfile = true,
    setfenv = true,
    getfenv = true,
    rawequal = true,
    collectgarbage = true,
    gcinfo = true,
    date = true,
    time = true,
    format = true,
    strsplit = true,
    strjoin = true,
    strtrim = true,
    tinsert = true,
    tremove = true,
    wipe = true,
    sort = true,
    floor = true,
    ceil = true,
    max = true,
    min = true,
    abs = true,
}
for key, value in pairs(G) do
    if
        type(value) == "function"
        and type(key) == "string"
        and not LUA_GLOBALS[key]
        and not key:match("^str")
        and not key:match("^t[a-z]")
    then
        wrapGame(G, key, key)
    elseif type(value) == "table" and type(key) == "string" and key:match("^C_") then
        for name, fn in pairs(value) do
            if type(fn) == "function" then
                wrapGame(value, name, key .. "." .. name)
            end
        end
    end
end

setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29) -- Grom'gol Base Camp, Stranglethorn
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
local logSize = #addon.QuestState.getLogQuestIds()

local out = io.open(scenariosDir .. "/.api-budget.txt", "w")
out:write(string.format("Quests in the log: %d (Grom'gol, Stranglethorn Vale)\n\n", logSize))

local function top(counts, limit)
    local rows, total = {}, 0
    for name, count in pairs(counts) do
        rows[#rows + 1] = { name, count }
        total = total + count
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    local parts = {}
    for index = 1, math.min(#rows, limit) do
        parts[index] = rows[index][1] .. " " .. rows[index][2]
    end
    return total, table.concat(parts, ", ")
end

local summary = {}
local function measure(name, body)
    widgetCalls, creations, gameCalls = {}, {}, {}
    isCounting = true
    local ok, problem = pcall(body)
    isCounting = false
    local widgetTotal, widgetTop = top(widgetCalls, 14)
    local gameTotal, gameTop = top(gameCalls, 10)
    local made = {}
    for kind, count in pairs(creations) do
        made[#made + 1] = count .. " " .. kind
    end
    table.sort(made)
    out:write(
        string.format(
            "== %s%s\n   widget calls: %d\n      %s\n   objects created: %s\n   game functions called: %d\n      %s\n\n",
            name,
            ok and "" or (" (FAILED: " .. tostring(problem) .. ")"),
            widgetTotal,
            widgetTop,
            #made > 0 and table.concat(made, ", ") or "none",
            gameTotal,
            gameTop
        )
    )
    summary[#summary + 1] = string.format(
        "%-46s %7d widget calls  %6d game calls  created: %s",
        name,
        widgetTotal,
        gameTotal,
        #made > 0 and table.concat(made, ", ") or "-"
    )
end

measure("first map open after login (cold)", function()
    key("M")
    wait(1.5)
end)
key("M")
wait(0.5)
do
    local original = addon.Log.refresh
    addon.Log.refresh = function(...)
        io.write("REOPEN Log.refresh ", (debug.traceback("", 2):gsub("%s+", " ")):sub(1, 700), string.char(10))
        return original(...)
    end
    traceMethod, traceLeft, traceEvery = "SetText", 4, 70
    measure("map reopened, nothing changed", function()
        key("M")
        wait(1.5)
    end)
    traceMethod = nil
    addon.Log.refresh = original
end
measure("map marks drawn again in full (warm)", function()
    addon.MapPins.refresh()
end)
measure("quest window drawn: My quests (warm)", function()
    addon.Log.refresh()
end)
local title = addon.QuestState.getQuest(accepted[3]).title
measure("mouse rests on a quest in the list", function()
    hover(title)
    wait(0.6)
end)
measure("mouse moves on to another quest", function()
    hover(addon.QuestState.getQuest(accepted[5]).title)
    wait(0.6)
end)
measure("1 second, map open, nothing happening", function()
    wait(1)
end)
measure("a kill that counts, map open", function()
    progress(accepted[1], 1, 1)
    wait(0.6)
end)
measure("Available tab opened (first time)", function()
    click("Available")
    wait(1)
end)
measure("quest window drawn: Available (warm)", function()
    addon.Log.refresh()
end)
click("My quests")
wait(0.5)
key("M")
wait(0.5)
measure("tracker drawn", function()
    addon.Tracker.refresh()
end)
measure("minimap marks chosen and drawn", function()
    addon.MinimapPins.refresh()
end)
measure("minimap marks placed (as the player moves)", function()
    addon.MinimapPins.move()
end)
measure("1 second standing, map closed", function()
    wait(1)
end)
measure("1 second walking, map closed", function()
    hold("W", 1)
end)
measure("a kill that counts, map closed", function()
    progress(accepted[2], 1, 1)
    wait(0.6)
end)
measure("map opened after that kill", function()
    key("M")
    wait(1.5)
end)

out:write("== SUMMARY\n")
for _, line in ipairs(summary) do
    out:write(line, "\n")
end
out:close()
