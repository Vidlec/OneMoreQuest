-- luacheck (the Lua linter) for our addons and their simulator scenarios: bun run lint:lua. Formatting is StyLua's
-- (stylua.toml); this looks for mistakes: globals made or read by accident (an addon's most common bug: a missing
-- "local" leaks into every other addon), unused variables and values, redefinitions, unreachable code.
std = "lua51"
max_line_length = false -- StyLua's (stylua.toml): what it cannot wrap (a long string) stays as written
ignore = {
    "212", -- an unused argument: event handlers and methods keep the signature the game gives them
    "42.", -- shadowing a local, and
    "43.", -- an upvalue: closures reuse a name on purpose (self, frame)
    "542", -- an empty if branch: written for its comment, saying what is left alone
    "581", -- "not (x == y)": sometimes written so on purpose
}
exclude_files = { "node_modules/**", "sim/plugins/questie/**" } -- (Questie's own code, copied unchanged)

-- Every global the game offers on Forever (the client's API, the game's own Lua and frames, QuestieDB's): made by the
-- simulator (bun run luacheck:globals), so a name the client lacks is caught as well as a misspelled one
local function readList(path)
    local chunk = loadfile(path)
    return chunk and chunk() or {}
end
read_globals = readList(".luacheck/forever-globals.lua")
local function add(list, names)
    for _, name in ipairs(names) do
        list[#list + 1] = name
    end
end
-- Other addons ours work with when they are there (each use checks first)
add(read_globals, {
    "Questie",
    "QuestieLoader",
    "TomTom",
    "Auctionator",
    "TnnysMobLoot_Starter",
    "TnnysMobLoot_Forever",
    "ChatThrottleLib",
})
-- The game's frames from addons it loads on demand: there once loaded (each use checks first)
add(read_globals, { "BattlefieldMapFrame" })
-- Older clients' functions, Forever has none of them: each is only a fallback behind the C_ function first asked
-- (C_QuestLog.GetInfo before GetQuestLogTitle...). Not GetItemInfo and its kin: the ledger asked for those alone and
-- kept no loot on Forever: each such fallback is excused on its own line ("luacheck: ignore 113"), so a new use
-- of them stays a warning
add(read_globals, {
    "GetSpellInfo",
    "GetFactionInfoByID",
    "SendAddonMessage",
    "RegisterAddonMessagePrefix",
    "DisableAddOn",
    "GetNumAddOns",
    "GetAddOnInfo",
    "IsAddOnLoaded",
    "GetAddOnMetadata",
    "GetNumTradeSkills",
    "GetTradeSkillInfo",
    "GetTradeSkillItemLink",
    "GetTrackingTexture",
    "GetQuestsCompleted",
    "GetQuestTagInfo",
    "GetMouseFocus",
    "GetCoinTextureString",
    "GetQuestLogTitle",
    "GetNumQuestLogEntries",
})

-- What our addons make global on purpose: their saved variables, slash commands and popups
files["addons/OneMoreQuest/**"] = {
    globals = {
        "OneMoreQuestDB",
        "SlashCmdList",
        "StaticPopupDialogs",
        "SLASH_ONEMOREQUEST1",
        "SLASH_ONEMOREQUEST2",
    },
}
-- A function of the addon a reader can hold in their head (CLAUDE.md, Style): over this, split it into named steps.
-- (Not the tests and scenarios: they are long scripts on purpose.)
files["addons/OneMoreQuest/**"].max_cyclomatic_complexity = 25
-- The parts of the log and the map marks each start with the same header naming their sibling parts (local Compose,
-- Look, Layout... = MapMarks.Compose...) and the addon's name: kept whole in every part, used or not
for _, folder in ipairs({ "Log", "Map/Marks" }) do
    files["addons/OneMoreQuest/" .. folder .. "/**"] = { ignore = { "211/^%u%l", "211/addonName" } }
end
-- (MapUtils' own table of tabs, which OneMoreQuest adds its tab to)
files["addons/OneMoreQuest/Compatibility/MapUtils.lua"] = { globals = { "_G" } }

-- The unit tests run outside the game on a fake one (tests/FakeGame.lua), which sets the game's globals up itself;
-- a helper's several answers are read one at a time
files["addons/OneMoreQuest/tests/**"] = { ignore = { "11.", "12.", "311" }, max_cyclomatic_complexity = false }

-- Scenarios and the simulator's plugins run with its steps as globals (moveTo, wait, expect...): read from their
-- declarations for the language server (addonsim's types/addonsim.lua)
local steps = { "sim", "combat" }
local declarations = io.open("node_modules/addonsim/types/addonsim.lua")
if declarations then
    for line in declarations:lines() do
        local name = line:match("^function ([%a_][%w_]*)%(") or line:match("^([%a_][%w_]*) = ")
        if name then
            steps[#steps + 1] = name
        end
    end
    declarations:close()
end
-- (G: the game's globals, which a scenario may change: G.GetMinimapShape = ...; jit and _ENV, asked whether there)
for index = #steps, 1, -1 do
    if steps[index] == "G" then
        table.remove(steps, index) -- (writable, below)
    end
end
files["sim/**"] = { std = "luajit", read_globals = steps, globals = { "G", "_ENV" } }
-- The audit's trace settings, globals its hook reads
files["sim/scenarios/audits/api-budget.lua"] = { globals = { "traceMethod", "traceLeft", "traceEvery" } }
-- The recorder addon's saved variable, as a recording is saved; and a scenario standing in the game's hook
files["sim/scenarios/fixtures/sample-recording.lua"] = { globals = { "AddonSimRecording" } }
files["sim/scenarios/map-zoom.lua"] = { globals = { "hooksecurefunc" } }
-- The Questie plugin plays Questie's own library loader
files["sim/plugins/questie/LibStub.lua"] = { globals = { "_G" } }
-- The audits are measuring tools kept for when a question comes back: their spare helpers and counts are not checked
files["sim/scenarios/audits/**"] = { ignore = { "211", "213", "231", "241" } }
