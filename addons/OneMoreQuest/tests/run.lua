-- Runs the addon's logic against the fake game. From the addon folder: luajit tests/run.lua
-- The tests are in one file per area of the addon (tests/<Area>.lua), run in the order below; this file holds the
-- fake game, the addon's files, and the helpers every test file can use.
local FakeGame = dofile("tests/FakeGame.lua")

local FILES = {
    "Core.lua",
    "Locale.lua",
    "Locales/Czech.lua",
    "Locales/CzechLog.lua",
    "Locales/CzechChronicle.lua",
    "Locales/CzechSettings.lua",
    "Locales/CzechMap.lua",
    "QuestText.lua",
    "Translators/AzerothCesky.lua",
    "Translators/WowfCZ.lua",
    "Translators/Spoken.lua",
    "Database.lua",
    "CraftedItems.lua",
    "Crafting.lua",
    "LearnedDungeons.lua",
    "Geometry.lua",
    "Location.lua",
    "Chain.lua",
    "QuestState.lua",
    "Focus.lua",
    "Model.lua",
    "Spoilers.lua",
    "HiddenQuests.lua",
    "EventQuests.lua",
    "Events.lua",
    "GameOffers.lua",
    "DataCheck.lua",
    "Availability.lua",
    "Prices.lua",
    "Loot.lua",
    "Drops.lua",
    "Profit.lua",
    "KillCounter.lua",
    "UnitTooltip.lua",
    "History.lua",
    "Chronicle.lua",
    "Ledger.lua",
    "Warnings.lua",
    "Comms.lua",
    "QuestieBridge.lua",
    "Party.lua",
    "Announce.lua",
    "AutoQuest.lua",
    "Nameplates.lua",
    "Widgets.lua",
    "QuestTooltip.lua",
    "MissedReport.lua",
    "BlizzardTracker.lua",
    "ItemButtons.lua",
    "TrackerLook.lua",
    "TrackerFrame.lua",
    "WindowBorder.lua",
    "Log/Base.lua",
    "Log/List.lua",
    "Log/QuestPage.lua",
    "Log/QuestsTab.lua",
    "Log/AvailableTab.lua",
    "Log/DungeonsTab.lua",
    "Log/SettingsView.lua",
    "Log/Window.lua",
    "MapDock.lua",
    "Gamepad.lua",
    "GamepadMenu.lua",
    "GamepadTracker.lua",
    "GamepadMap.lua",
    "MapPins.lua",
    "MapMarks/Compose.lua",
    "MapMarks/Look.lua",
    "MapMarks/Pills.lua",
    "MapMarks/Layout.lua",
    "MapMarks/Shapes.lua",
    "MapMarks/Areas.lua",
    "MapMarks/Draw.lua",
    "GatheringNodes.lua",
    "GatheringSpots.lua",
    "MinimapPins.lua",
    "MapHover.lua",
    "Waypoints.lua",
    "Compatibility.lua",
    "Compatibility/Questie.lua",
    "Compatibility/SpokenPlaces.lua",
    "Compatibility/QuestieDB.lua",
    "Compatibility/TomTom.lua",
    "Compatibility/Auctionator.lua",
    "Compatibility/TnnysMobLoot.lua",
    "Compatibility/LeatrixMaps.lua",
    "Compatibility/MapUtils.lua",
    "Compatibility/OpenMap.lua",
    "Compatibility/ForeverDungeonJournal.lua",
    "Settings.lua",
    "ChroniclePage.lua",
    "ChroniclePictures.lua",
}
local TIRISFAL, UNDERCITY, ORGRIMMAR, SILVERPINE = 85, 1497, 1637, 130

local passedCount, failedCount = 0, 0

---A fresh copy of the addon and of the game for every test.
local function createAddon()
    local state = FakeGame.install()
    FakeGame.installWidgets()
    local ns = {}
    for _, file in ipairs(FILES) do
        assert(loadfile(file))("OneMoreQuest", ns)
    end
    ns.loadSettings(nil)
    return ns, state
end

local function setQuest(state, questId, isComplete, objectives)
    state.watchedQuestIds[#state.watchedQuestIds + 1] = questId
    state.questLog[questId] = { isComplete = isComplete, objectives = objectives or {} }
end

local function killObjective(fulfilled, required)
    return {
        text = fulfilled .. "/" .. required .. " Roadside Bandit slain",
        type = "monster",
        finished = fulfilled >= required,
        numFulfilled = fulfilled,
        numRequired = required,
    }
end

local function itemObjective(fulfilled, required)
    return {
        text = "Wolf Fang: " .. fulfilled .. "/" .. required,
        type = "item",
        finished = fulfilled >= required,
        numFulfilled = fulfilled,
        numRequired = required,
    }
end

local function getGroup(model, zoneId)
    for _, group in ipairs(model.groups) do
        if group.zoneId == zoneId then
            return group
        end
    end
    return nil
end

local function expectEqual(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function test(name, body)
    local isSuccess, message = pcall(body)
    if isSuccess then
        passedCount = passedCount + 1
    else
        failedCount = failedCount + 1
        print("FAIL  " .. name .. "\n      " .. tostring(message))
    end
end

-- Helpers shared by the areas' tests
local function getQuest(quests, questId)
    for _, quest in ipairs(quests) do
        if quest.questId == questId then
            return quest
        end
    end
    return nil
end

local function getAvailableQuests(ns, zoneId, options)
    ns.Availability.invalidate()
    ns.Availability.prepare()
    return ns.Availability.getQuests(zoneId, options)
end

local function getMarks(marks, kind)
    local found = {}
    for _, mark in ipairs(marks) do
        if mark.kind == kind then
            found[#found + 1] = mark
        end
    end
    return found
end

---Item prices, a loot table and quest item drop rates for the profit tests.
---Bandits (5001) drop linen (9101, 40% of kills, 50c) and a quest-only token; wolves (5002) drop fangs
---(7001, the quest item, 25%) and a pelt (9102, 50%, 2s).
local function addProfitData()
    local vendorPrices = { [9101] = 50, [9102] = 200, [9201] = 1500, [9202] = 4000, [7001] = 0 }
    GetItemInfo = function(itemId)
        if not vendorPrices[itemId] then
            return nil
        end
        return "Item " .. itemId,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            vendorPrices[itemId],
            nil,
            nil,
            itemId == 9202 and 1 or 2
    end
    TnnysMobLoot_Starter = {
        npc = {
            [5001] = { "9101:40,9999:100:q", nil, nil, "Roadside Bandit" },
            [5002] = { "9102:50,7001:10", nil, nil, "Silverpine Wolf" },
        },
    }
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            if name == "QuestieClassicItemDrops" then
                return { wowheadData = "return { [7001] = { [5002] = 25 } }" }
            end
            return original(name)
        end
    end)(LibQuestieDB.Support.Get)
end

local function removeProfitData()
    GetItemInfo, TnnysMobLoot_Starter, Auctionator = nil, nil, nil
    GetQuestLogRewardMoney, GetNumQuestLogChoices, GetQuestLogChoiceInfo = nil, nil, nil
end

---Makes Shadowfang Keep a known dungeon: area 209, also known as 236, entered from Silverpine Forest.
local function addDungeon()
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            local module = original(name)
            if name == "ZoneDB" then
                module.private.dungeons = { [209] = { "Shadowfang Keep", { 236 }, 130, { { 130, 45, 68 } } } }
                module.private.subZoneToParentZoneOverride = "return { [2090] = 209 }" -- an area inside the keep
            end
            return module
        end
    end)(LibQuestieDB.Support.Get)
end

---@return string text A file's whole text, the file closed again (Windows allows few open files at once)
local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

---A party of two around the player, with addon messages caught instead of sent.
local function installGroup(state)
    state.partyMembers.party1 = { name = "Mira Dawnfield", questIds = {} }
    state.partyMembers.party2 = { name = "Olen Rusk", questIds = {} }
    local sent = {}
    IsInGroup = function()
        return true
    end
    C_ChatInfo = {
        RegisterAddonMessagePrefix = function()
            return true
        end,
        SendAddonMessage = function(prefix, text, channel, target)
            sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
        end,
    }
    return sent
end

local function removeGroup()
    IsInGroup, C_ChatInfo, C_AddOns = nil, nil, nil
end

local function receive(ns, prefix, text, sender, channel)
    ns.Comms.handleEvent(nil, "CHAT_MSG_ADDON", prefix, text, channel or "PARTY", sender)
end

---A stand-in for Azeroth česky's public interface: it knows quest 301 and its kill objective.
local function installAzerothCesky(state)
    local fake = { isOn = true, listeners = {}, asked = 0 }
    local function answer(text)
        fake.asked = fake.asked + 1
        if not fake.isOn then
            return { kind = "unavailable", reason = "disabled" }
        end
        return text and { kind = "translated", text = text } or { kind = "missing", reason = "translation-missing" }
    end
    local interface = {
        GetState = function()
            return { ready = true, canTranslateTracker = fake.isOn }
        end,
        Subscribe = function(callback)
            fake.listeners[#fake.listeners + 1] = callback
            return function() end
        end,
        ResolveQuestTitle = function(questId)
            return answer(questId == 301 and "Dvě fronty" or nil)
        end,
        ResolveQuestMapField = function(questId, field, source)
            return answer(questId == 301 and field == "title" and source == "Two Fronts" and "Dvě fronty" or nil)
        end,
        ResolveTrackerObjective = function(questId, text)
            return answer(
                questId == 301
                        and text:find("Roadside Bandit slain", 1, true)
                        and text:gsub("Roadside Bandit slain", "zabitých banditů")
                    or nil
            )
        end,
    }
    fake.change = function(isOn)
        fake.isOn = isOn
        for _, listener in ipairs(fake.listeners) do
            listener({ state = interface.GetState() })
        end
    end
    _G.AzerothCeskyAPI = {
        GetInterface = function(version)
            return version == 1 and interface or nil
        end,
    }
    _G.C_AddOns = _G.C_AddOns or {}
    _G.C_AddOns.IsAddOnLoaded = function(name)
        return name == "AzerothCesky"
    end
    return fake
end

local function removeAzerothCesky()
    _G.AzerothCeskyAPI = nil
    if _G.C_AddOns then
        _G.C_AddOns.IsAddOnLoaded = nil
    end
end

-- Each test file sees the helpers above; whatever else it reads or sets is the real global (a stub of a game function
-- set by a test must reach the addon, which reads the real globals)
local HELPERS = {
    FakeGame = FakeGame,
    FILES = FILES,
    TIRISFAL = TIRISFAL,
    UNDERCITY = UNDERCITY,
    ORGRIMMAR = ORGRIMMAR,
    SILVERPINE = SILVERPINE,
    createAddon = createAddon,
    setQuest = setQuest,
    killObjective = killObjective,
    itemObjective = itemObjective,
    getGroup = getGroup,
    expectEqual = expectEqual,
    test = test,
    getQuest = getQuest,
    getAvailableQuests = getAvailableQuests,
    getMarks = getMarks,
    addProfitData = addProfitData,
    removeProfitData = removeProfitData,
    addDungeon = addDungeon,
    readFile = readFile,
    installGroup = installGroup,
    removeGroup = removeGroup,
    receive = receive,
    installAzerothCesky = installAzerothCesky,
    removeAzerothCesky = removeAzerothCesky,
}
local AREAS = {
    "Tracker",
    "Available",
    "Map",
    "Log",
    "Dungeons",
    "Profit",
    "Party",
    "Chronicle",
    "Language",
    "Integrations",
    "Spoilers",
    "SpoilersSettings",
    "SpoilersTracker",
    "SpoilersLog",
    "SpoilersMap",
    "Core",
}
for _, area in ipairs(AREAS) do
    local chunk = assert(loadfile("tests/" .. area .. ".lua"))
    setfenv(
        chunk,
        setmetatable({}, {
            __index = function(_, name)
                if HELPERS[name] ~= nil then
                    return HELPERS[name]
                end
                return _G[name]
            end,
            __newindex = function(_, name, value)
                _G[name] = value
            end,
        })
    )
    chunk()
end

print(string.format("%d passed, %d failed", passedCount, failedCount))
os.exit(failedCount == 0 and 0 or 1)
