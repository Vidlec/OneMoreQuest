-- What each recurring thing OneMoreQuest does costs in Lua itself: time in the interpreter (JIT off, so the numbers
-- are of the kind the game's own Lua gives, within a small factor), garbage made, calls into the game's functions and
-- the quest database, and which of its own functions the time goes to. The widget calls are api-budget.lua's.
-- LUA_COST_ONLY=<part of a name> measures one; LUA_COST_STYLE=game|icons picks the areas' look (icons).
local PREFIX = "@Interface/AddOns/OneMoreQuest/"
local getinfo = debug.getinfo
if jit then
    jit.off()
    jit.flush()
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
addon.settings.areaStyle = os.getenv("LUA_COST_STYLE") or "filled"

-- Calls into the game, and reads of the quest database, counted; and the memory the game's functions and widgets
-- use while they run, which is the simulator's own (in the game they are not Lua): taken off the addon's garbage
local gameCalls, dbReads, isCounting = 0, 0, false
local insideGame, depth = 0, 0
local count = collectgarbage
local function wrapGame(owner, name, fn)
    owner[name] = function(...)
        if not isCounting then
            return fn(...)
        end
        gameCalls = gameCalls + 1
        if depth > 0 then
            return fn(...)
        end
        depth = 1
        local before = count("count")
        local a, b, c, d, e, f, g, h, i, j = fn(...)
        insideGame = insideGame + (count("count") - before)
        depth = 0
        return a, b, c, d, e, f, g, h, i, j
    end
end
local LUA_OWN = {
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
    loadstring = true,
    setfenv = true,
    getfenv = true,
    rawequal = true,
    collectgarbage = true,
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
    date = true,
    time = true,
    debugprofilestop = true,
    GetTime = true,
}
for key, value in pairs(G) do
    if type(value) == "table" and type(key) == "string" and key:match("^C_") then
        for name, fn in pairs(value) do
            if type(fn) == "function" then
                wrapGame(value, name, fn)
            end
        end
    elseif
        type(value) == "function"
        and type(key) == "string"
        and not LUA_OWN[key]
        and not key:match("^str")
        and key:match("^[A-Z]")
    then
        wrapGame(G, key, value)
    end
end
local W = require("widgets")
for _, definition in pairs(W.types) do
    for name, method in pairs(definition.methods) do
        if type(method) == "function" then
            definition.methods[name] = function(...)
                if not isCounting or depth > 0 then
                    return method(...)
                end
                depth = 1
                local before = count("count")
                local a, b, c, d, e, f, g, h = method(...)
                insideGame = insideGame + (count("count") - before)
                depth = 0
                return a, b, c, d, e, f, g, h
            end
        end
    end
end
for _, entity in ipairs({ "Quest", "Npc", "Object", "Item" }) do
    local library = G.LibQuestieDB and G.LibQuestieDB[entity]
    if library and library.Get then
        local original = library.Get
        library.Get = function(...)
            if isCounting then
                dbReads = dbReads + 1
            end
            return original(...)
        end
    end
end

local wanted = os.getenv("LUA_COST_ONLY")
local TOP = tonumber(os.getenv("LUA_COST_TOP") or "8")
local function measure(name, body, times, prepare)
    if wanted and not name:find(wanted, 1, true) then
        return
    end
    times = times or 5
    local counts, total = {}, 0
    local function hook()
        local seen = {}
        for level = 2, 60 do
            local info = getinfo(level, "Sn")
            if not info then
                break
            end
            if info.source:sub(1, #PREFIX) == PREFIX then
                local key = info.source:sub(#PREFIX + 1):gsub("%.lua$", "")
                    .. ":"
                    .. tostring(info.name or "?")
                    .. "@"
                    .. info.linedefined
                if not seen[key] then
                    seen[key] = true
                    counts[key] = (counts[key] or 0) + 1
                end
            end
        end
        total = total + 1
    end
    -- Time and garbage without the sampler; then again with it, for the shares
    local spent, garbage = 0, 0
    gameCalls, dbReads, insideGame = 0, 0, 0
    for _ = 1, times do
        if prepare then
            prepare()
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        isCounting = true
        -- (LUA_COST_SAMPLE_FIRST=1: the shares taken in this very run, for what only happens once; its time then
        -- includes the looking)
        if os.getenv("LUA_COST_SAMPLE_FIRST") == "1" then
            debug.sethook(hook, "", 200)
        end
        local started = os.clock()
        body()
        spent = spent + (os.clock() - started)
        debug.sethook()
        isCounting = false
        garbage = garbage + (collectgarbage("count") - before)
        collectgarbage("restart")
    end
    for _ = 1, os.getenv("LUA_COST_SAMPLE_FIRST") == "1" and 0 or times do
        if prepare then
            prepare()
        end
        debug.sethook(hook, "", 200)
        body()
        debug.sethook()
    end
    io.write(
        string.format(
            "COST == %-44s %7.2f ms   %6.0f KB the addon's own garbage (+%5.0f KB inside the game's functions)   %5d game calls   %5d database reads\n",
            name,
            spent / times * 1000,
            (garbage - insideGame) / times,
            insideGame / times,
            gameCalls / times,
            dbReads / times
        )
    )
    local rows = {}
    for key, count in pairs(counts) do
        rows[#rows + 1] = { key, count }
    end
    table.sort(rows, function(a, b)
        return a[2] > b[2]
    end)
    for index = 1, math.min(#rows, TOP) do
        io.write(
            string.format(
                "COST      %3d%%  %s\n",
                math.floor(rows[index][2] / math.max(total, 1) * 100 + 0.5),
                rows[index][1]
            )
        )
    end
    -- Who makes the garbage: memory in use sampled as the code runs (the collector stopped), each rise put down to
    -- the function running (itself) and to everything that called it (with what it calls)
    if os.getenv("LUA_COST_GARBAGE") == "1" then
        local made, madeSelf, madeTotal, last = {}, {}, 0, 0
        local function memoryHook()
            local delta = collectgarbage("count") - last
            if delta <= 0 then
                last = collectgarbage("count")
                return
            end
            madeTotal = madeTotal + delta
            local seen, isFirst = {}, true
            for level = 2, 60 do
                local info = getinfo(level, "Sn")
                if not info then
                    break
                end
                if info.source:sub(1, #PREFIX) == PREFIX then
                    local key = info.source:sub(#PREFIX + 1):gsub("%.lua$", "")
                        .. ":"
                        .. tostring(info.name or "?")
                        .. "@"
                        .. info.linedefined
                    if isFirst then
                        madeSelf[key] = (madeSelf[key] or 0) + delta
                        isFirst = false
                    end
                    if not seen[key] then
                        seen[key] = true
                        made[key] = (made[key] or 0) + delta
                    end
                end
            end
            last = collectgarbage("count") -- (what this looking itself made is not the addon's)
        end
        if prepare then
            prepare()
        end
        collectgarbage("collect")
        collectgarbage("stop")
        last = collectgarbage("count")
        debug.sethook(memoryHook, "", 20)
        body()
        debug.sethook()
        collectgarbage("restart")
        for _, kind in ipairs({ { "garbage, with what it calls", made }, { "garbage, the function itself", madeSelf } }) do
            local list = {}
            for key, amount in pairs(kind[2]) do
                list[#list + 1] = { key, amount }
            end
            table.sort(list, function(a, b)
                return a[2] > b[2]
            end)
            io.write("COST   ", kind[1], " (", math.floor(madeTotal), " KB in all)\n")
            for index = 1, math.min(#list, TOP + 6) do
                io.write(string.format("COST      %6.0f KB  %s\n", list[index][2], list[index][1]))
            end
        end
    end
end

key("M")
wait(2)
local function invalidate()
    -- As a quest's progress does before everything is drawn again: what was worked out is let go
    addon.QuestState.forgetFrame()
    addon.QuestState.forgetMemos()
    addon.Model.forgetEntries()
    addon.Availability.invalidateForRedraw(true) -- (a quiet redraw: the quest log's news alone)
end
measure("map marks drawn (nothing changed)", function()
    addon.MapPins.refresh()
end)
measure("map marks drawn (after a quest changed)", function()
    addon.MapPins.refresh()
end, 5, invalidate)
measure("quest window drawn (after a quest changed)", function()
    addon.Log.refresh()
end, 5, invalidate)
measure("tracker drawn (after a quest changed)", function()
    addon.Tracker.refresh()
end, 5, invalidate)
measure("minimap marks chosen (after a quest changed)", function()
    addon.MinimapPins.refresh()
end, 5, invalidate)
measure("minimap marks chosen (walked on)", function()
    addon.MinimapPins.refresh()
end)
measure("a kill counted, all of it, map open", function()
    progress(accepted[1], 1, 1)
    wait(0.7)
end, 3)
measure("Available tab opened (first time)", function()
    click("Available")
    wait(0.5)
end, 1)
measure("Available tab drawn again (nothing changed)", function()
    addon.Log.refresh()
end)
measure("Available tab drawn (after a quest changed)", function()
    addon.Log.refresh()
end, 3, invalidate)
click("My quests")
wait(0.3)
key("M")
wait(0.5)
measure("a kill counted, all of it, map closed", function()
    progress(accepted[2], 1, 1)
    wait(0.7)
end, 3)
measure("1 second standing, map closed", function()
    wait(1)
end, 3)
measure("1 second walking, map closed", function()
    hold("W", 1)
end, 3)
measure("1 second standing, later", function()
    wait(1)
end, 3)
measure("1 second walking, later", function()
    hold("W", 1)
end, 3)
