-- A small stand-in for the game and for QuestieDB, enough to run the addon's logic outside the client.
-- Zones: 85 Tirisfal Glades (map 1420), 1497 Undercity (map 1458), 1637 Orgrimmar (map 1454),
-- 130 Silverpine Forest (map 1421), 159 Brill, a subzone of Tirisfal Glades.
local FakeGame = {}

local ZONE_NAMES = {
    [85] = "Tirisfal Glades",
    [1497] = "Undercity",
    [1637] = "Orgrimmar",
    [130] = "Silverpine Forest",
    [159] = "Brill",
    [209] = "Shadowfang Keep",
}

-- Each map is a 1000 yard square; its top-left corner in world yards (north, west) and its continent.
local MAPS = {
    [1420] = { continentId = 0, north = 3000, west = 2000 },
    [1458] = { continentId = 0, north = 2000, west = 2000 },
    [1421] = { continentId = 0, north = 2000, west = 3000 },
    [1454] = { continentId = 1, north = 5000, west = 5000 },
}
local MAP_SIZE = 1000

local function createVector(x, y)
    return {
        x = x,
        y = y,
        GetXY = function(self)
            return self.x, self.y
        end,
    }
end

local QUESTS = {
    -- Delivery: no objectives, handed in to an NPC in Orgrimmar
    [101] = {
        name = "Urgent Dispatch",
        questLevel = 12,
        finishedBy = { { 9001 } },
        objectives = {},
        zoneOrSort = 1497,
        nextQuestInChain = 102,
    },
    [102] = {
        name = "The Warchief's Reply",
        questLevel = 12,
        finishedBy = { { 9002 } },
        objectives = {},
        preQuestSingle = { 101 },
        nextQuestInChain = 103,
    },
    [103] = {
        name = "Back to Work",
        questLevel = 13,
        finishedBy = { { 9002 } },
        objectives = {},
        preQuestSingle = { 102 },
    },
    -- Kill quest in Tirisfal Glades, handed in in Undercity
    [201] = {
        name = "Bandit Trouble",
        questLevel = 13,
        finishedBy = { { 9002 } },
        objectives = { { { 5001 } } },
        zoneOrSort = 85,
    },
    -- Kill in Tirisfal Glades and collect in Silverpine Forest
    [301] = {
        name = "Two Fronts",
        questLevel = 14,
        finishedBy = { { 9002 } },
        objectives = { { { 5001 } }, nil, { { 7001 } } },
        zoneOrSort = 85,
    },
    -- Objective with no known place
    [401] = {
        name = "A Mystery",
        questLevel = 10,
        finishedBy = { {} },
        objectives = { { { 5999 } } },
        zoneOrSort = 130,
    },
    -- Dungeon quests: filed under an area of Shadowfang Keep; one with a creature inside, one with nothing known
    [601] = {
        name = "The Archivist's Notes",
        questLevel = 22,
        finishedBy = { { 9002 } },
        objectives = { { { 5003 } } },
        zoneOrSort = 236,
    },
    [604] = {
        name = "The Inner Vault",
        questLevel = 22,
        finishedBy = { { 9002 } },
        objectives = { { { 5004 } } },
        zoneOrSort = 85,
    },
    [602] = {
        name = "Whispers in the Keep",
        questLevel = 22,
        finishedBy = { { 9002 } },
        objectives = { { { 5999 } } },
        zoneOrSort = 236,
    },
    -- Filed under Tirisfal Glades, with one creature there and one inside the dungeon
    -- A cooking quest: filed under the category, not a zone, its meat dropped in two zones
    [606] = {
        name = "Turtle Soup",
        questLevel = 20,
        finishedBy = { { 9002 } },
        objectives = { nil, nil, { { 7001 } } },
        zoneOrSort = -304,
    },
    -- Belongs to the dungeon, but nothing to do there: wait at the NPC outside until something happens
    [605] = {
        name = "Wait for It",
        questLevel = 22,
        finishedBy = { { 9002 } },
        objectives = {},
        zoneOrSort = 236,
        objectivesText = { "Wait for the envoy to finish." },
    },
    [603] = {
        name = "In and Out",
        questLevel = 22,
        finishedBy = { { 9002 } },
        objectives = { { { 5001 }, { 5003 } } },
        zoneOrSort = 85,
    },
    -- Quests to pick up. The player is a level 10 undead warrior unless a test says otherwise.
    [501] = {
        name = "Fresh Start",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    [502] = {
        name = "After Fresh Start",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        preQuestSingle = { 501 },
        disabledByQuest = 504,
    },
    [503] = {
        name = "High Road",
        questLevel = 13,
        requiredLevel = 12,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    [504] = {
        name = "Too High",
        questLevel = 32,
        requiredLevel = 30,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    [505] = {
        name = "Humans Only",
        questLevel = 10,
        requiredLevel = 1,
        requiredRaces = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    -- Starts from an item dropped in a dungeon, handed in in Tirisfal Glades
    [506] = {
        name = "The Dropped Letter",
        questLevel = 11,
        requiredLevel = 1,
        startedBy = { nil, nil, { 7002 } },
        finishedBy = { { 9003 } },
    },
    [507] = {
        name = "Either",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        exclusiveTo = { 508 },
    },
    [508] = {
        name = "Or",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        exclusiveTo = { 507 },
    },
    [509] = {
        name = "Main Quest",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9002 } },
        finishedBy = { { 9002 } },
        breadcrumbs = { 510 },
    },
    [510] = {
        name = "Lead-in",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9002 } },
        finishedBy = { { 9002 } },
        breadcrumbForQuestId = 509,
    },
    -- Open to every race on paper, but given by an Alliance officer
    [512] = {
        name = "For the Alliance",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9005 } },
        finishedBy = { { 9005 } },
    },
    -- A mage's class quest
    [513] = {
        name = "Arcane Studies",
        questLevel = 10,
        requiredLevel = 1,
        requiredClasses = 128,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    -- Kinds the settings leave out: repeatable, daily, a cloth donation, a battleground's quest
    [514] = {
        name = "More Supplies",
        questLevel = 10,
        requiredLevel = 1,
        specialFlags = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    [515] = {
        name = "Daily Patrol",
        questLevel = 10,
        requiredLevel = 1,
        questFlags = 4096,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    -- A city donation, one in each of three capitals: told by the data, not by its ID
    [7813] = {
        name = "A Donation of Wool",
        questLevel = 10,
        requiredLevel = 1,
        zoneOrSort = 1497,
        objectives = { nil, nil, { { 2592 } } },
        reputationReward = { { 68, 150 } },
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    [7791] = {
        name = "A Donation of Wool",
        questLevel = 10,
        requiredLevel = 1,
        zoneOrSort = 1519,
        objectives = { nil, nil, { { 2592 } } },
        reputationReward = { { 72, 150 } },
    },
    [7802] = {
        name = "A Donation of Wool",
        questLevel = 10,
        requiredLevel = 1,
        zoneOrSort = 1537,
        objectives = { nil, nil, { { 2592 } } },
        reputationReward = { { 47, 150 } },
    },
    [516] = {
        name = "Battle of the Gulch",
        questLevel = 10,
        requiredLevel = 1,
        zoneOrSort = 3277,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    -- Starts from an item that drops all over the world, handed in in Tirisfal Glades
    [517] = {
        name = "Crystal in the Hills",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { nil, nil, { 7003 } },
        finishedBy = { { 9003 } },
    },
    -- For the dungeon, but given outside it in Tirisfal Glades
    [518] = {
        name = "Into the Keep",
        questLevel = 10,
        requiredLevel = 1,
        zoneOrSort = 236,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    -- Starts from an item the bandits drop, at each of their camps
    [519] = {
        name = "Orders from the Road",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { nil, nil, { 7004 } },
        finishedBy = { { 9003 } },
    },
    -- A chain that starts in Tirisfal Glades and goes into the dungeon at its second step
    [520] = {
        name = "Rumours of the Vault",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        nextQuestInChain = 521,
    },
    [521] = {
        name = "Into the Vault",
        questLevel = 11,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        preQuestSingle = { 520 },
        objectives = { { { 5004 } } },
    },
    -- A chain that forks before the dungeon, as Dalaran's does: two lead-ins, both needed for the next step
    [524] = {
        name = "The Sewer Key",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        nextQuestInChain = 526,
    },
    [525] = {
        name = "Break-In",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
    },
    [526] = {
        name = "Patrols",
        questLevel = 10,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        preQuestGroup = { 524, 525 },
        nextQuestInChain = 527,
    },
    [527] = {
        name = "Down Below",
        questLevel = 11,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        preQuestSingle = { 526 },
        objectives = { { { 5004 } } },
        nextQuestInChain = 528,
    },
    [528] = {
        name = "Afterwards",
        questLevel = 11,
        requiredLevel = 1,
        startedBy = { { 9003 } },
        finishedBy = { { 9003 } },
        preQuestSingle = { 527 },
    },
    [511] = {
        name = "Childhood Chore",
        questLevel = 2,
        requiredLevel = 1,
        startedBy = { { 9002 } },
        finishedBy = { { 9002 } },
    },
}

local NPCS = {
    [9001] = { name = "Aide Rokka", spawns = { [1637] = { { 50, 50 } } } },
    [9002] = { name = "Envoy Maldrek", spawns = { [1497] = { { 55, 90 } } } },
    [5001] = { name = "Roadside Bandit", spawns = { [85] = { { 60, 50 }, { 80, 50 } }, [159] = { { 61, 52 } } } },
    [5002] = { name = "Silverpine Wolf", spawns = { [130] = { { 40, 40 } } } },
    [5003] = { name = "Keep Archivist", spawns = { [209] = { { -1, -1 } } } },
    -- Recorded by an area inside the dungeon, with coordinates on the dungeon's own map
    [5004] = { name = "Vault Warden", spawns = { [2090] = { { 40, 50 } } } },
    [9003] = { name = "Deathguard Morris", spawns = { [85] = { { 30, 30 } } }, friendlyToFaction = "H" },
    [9005] = { name = "Captain Vance", spawns = { [85] = { { 70, 70 } } }, friendlyToFaction = "A" },
}

local ITEMS = {
    [7001] = { name = "Wolf Fang", npcDrops = { 5002 } },
    [7002] = { name = "Sealed Letter", npcDrops = { 5003 } },
    [7004] = { name = "Bandit Orders", npcDrops = { 5001 } },
    -- Drops from creatures all over the world
    [7003] = {
        name = "Strange Pendant",
        npcDrops = { 5001, 5002, 5003, 5001, 5002, 5003, 5001, 5002, 5003, 5001, 5002, 5003, 5001, 5002, 5003, 5001 },
    },
}

local NUMBER_FIELDS = {
    questLevel = true,
    zoneOrSort = true,
    nextQuestInChain = true,
    requiredLevel = true,
    requiredMaxLevel = true,
    requiredRaces = true,
    requiredClasses = true,
    specialFlags = true,
    questFlags = true,
    parentQuest = true,
    breadcrumbForQuestId = true,
    requiredSpell = true,
    requiredSpecialization = true,
    disabledByQuest = true,
}

local function createEntity(rows)
    return {
        Get = function(id, field)
            local row = rows[id]
            if not row then
                return nil
            end
            local value = row[field]
            if value == nil and NUMBER_FIELDS[field] then
                return 0
            end
            return value
        end,
        GetAllIds = function()
            local ids = {}
            for id in pairs(rows) do
                ids[#ids + 1] = id
            end
            table.sort(ids)
            return ids
        end,
    }
end

---Installs the fake globals. State is the mutable game state the tests change.
function FakeGame.install()
    local state = {
        watchedQuestIds = {},
        questLog = {}, -- [questId] = { isComplete, objectives = { { text, type, finished, numFulfilled, numRequired } } }
        playerMapId = 1420,
        playerX = 0.5,
        playerY = 0.5,
        isInInstance = false,
        turnedInQuestIds = {}, -- [questId] = true
        playerLevel = 10,
        playerRaceId = 5,
        playerFaction = "Horde",
        partyMembers = {}, -- [unit] = { name, questIds = { [questId] = true } }
        maxQuestCount = 25,
    }

    local function getLogQuestIds()
        local questIds = {}
        for questId in pairs(state.questLog) do
            questIds[#questIds + 1] = questId
        end
        table.sort(questIds)
        return questIds
    end

    LibQuestieDB = {
        Quest = createEntity(QUESTS),
        Npc = createEntity(NPCS),
        Object = createEntity({}),
        Item = createEntity(ITEMS),
        Enum = {
            raceMaskById = { [1] = 1, [2] = 2, [5] = 16 },
            classKeys = { WARRIOR = 1, MAGE = 128 },
        },
        Support = {
            Get = function(name)
                if name ~= "ZoneDB" then
                    return nil
                end
                return {
                    private = {
                        areaIdToUiMapId = "return { [85] = 1420, [1497] = 1458, [1637] = 1454, [130] = 1421, [10074] = 1415 }",
                        areaIdToUiMapIdOverride = "return { [159] = 1420 }",
                        uiMapIdToAreaId = "return { [1420] = 85, [1458] = 1497, [1454] = 1637, [1421] = 130 }",
                        uiMapIdToAreaIdOverride = "return {}",
                        subZoneToParentZone = "return { [159] = 85 }",
                        subZoneToParentZoneOverride = "return {}",
                    },
                }
            end,
        },
    }

    CreateVector2D = createVector

    C_Map = {
        GetAreaInfo = function(areaId)
            return ZONE_NAMES[areaId]
        end,
        GetBestMapForUnit = function()
            return state.playerMapId
        end,
        -- Only the continent is typed: an area drawn on it is no place of its own
        GetMapInfo = function(mapId)
            return mapId == 1415 and { mapId = 1415, name = "Eastern Kingdoms", mapType = 2 } or nil
        end,
        GetPlayerMapPosition = function(mapId)
            if state.isInInstance then
                return nil
            end
            return createVector(state.playerX, state.playerY)
        end,
        GetWorldPosFromMapPos = function(mapId, vector)
            local map = MAPS[mapId]
            if not map then
                return nil
            end
            return map.continentId, createVector(map.north - MAP_SIZE * vector.y, map.west - MAP_SIZE * vector.x)
        end,
        GetMapPosFromWorldPos = function(continentId, vector, mapId)
            local map = MAPS[mapId]
            if not map or map.continentId ~= continentId then
                return nil
            end
            return mapId, createVector((map.west - vector.y) / MAP_SIZE, (map.north - vector.x) / MAP_SIZE)
        end,
    }

    C_QuestLog = {
        GetNumQuestWatches = function()
            return #state.watchedQuestIds
        end,
        GetQuestIDForQuestWatchIndex = function(index)
            return state.watchedQuestIds[index]
        end,
        GetQuestObjectives = function(questId)
            return state.questLog[questId] and state.questLog[questId].objectives
        end,
        GetTitleForQuestID = function(questId)
            return QUESTS[questId] and QUESTS[questId].name
        end,
        GetQuestDifficultyLevel = function(questId)
            return QUESTS[questId] and QUESTS[questId].questLevel
        end,
        IsComplete = function(questId)
            return state.questLog[questId] and state.questLog[questId].isComplete or false
        end,
        GetNumQuestLogEntries = function()
            return #getLogQuestIds()
        end,
        GetInfo = function(index)
            local questId = getLogQuestIds()[index]
            return questId and { questID = questId, isHeader = false, title = QUESTS[questId] and QUESTS[questId].name }
        end,
        GetLogIndexForQuestID = function(questId)
            for index, logQuestId in ipairs(getLogQuestIds()) do
                if logQuestId == questId then
                    return index
                end
            end
            return nil
        end,
        IsQuestFlaggedCompleted = function(questId)
            return state.turnedInQuestIds[questId] == true
        end,
        GetAllCompletedQuestIDs = function()
            local questIds = {}
            for questId in pairs(state.turnedInQuestIds) do
                questIds[#questIds + 1] = questId
            end
            return questIds
        end,
        GetMaxNumQuestsCanAccept = function()
            return state.maxQuestCount
        end,
        IsUnitOnQuest = function(unit, questId)
            local member = state.partyMembers[unit]
            return member ~= nil and member.questIds[questId] == true
        end,
        AddQuestWatch = function(questId)
            state.watchedQuestIds[#state.watchedQuestIds + 1] = questId
        end,
        RemoveQuestWatch = function(questId)
            for index, watchedQuestId in ipairs(state.watchedQuestIds) do
                if watchedQuestId == questId then
                    table.remove(state.watchedQuestIds, index)
                    return
                end
            end
        end,
    }

    GetRealZoneText = function()
        local areaId = ({ [1420] = 85, [1458] = 1497, [1454] = 1637, [1421] = 130 })[state.playerMapId]
        return ZONE_NAMES[areaId]
    end

    -- Quest 201 comes with an item to use
    GetQuestLogSpecialItemInfo = function(logIndex)
        if getLogQuestIds()[logIndex] == 201 then
            return "|cffffffff|Hitem:7003::::::::|h[Sampling Vial]|h|r", 134800, 3, false
        end
        return nil
    end

    UnitFactionGroup = function()
        return state.playerFaction, state.playerFaction
    end
    UnitRace = function()
        return "Undead", "Scourge", state.playerRaceId
    end
    UnitClass = function()
        return "Warrior", "WARRIOR", 1
    end
    UnitLevel = function(unit)
        local member = state.partyMembers[unit]
        return member and member.level or state.playerLevel
    end
    UnitExists = function(unit)
        return state.partyMembers[unit] ~= nil
    end
    UnitName = function(unit)
        return state.partyMembers[unit] and state.partyMembers[unit].name
    end

    return state
end

---A widget whose every method exists and does nothing, so the window code can run without the client.
local function createWidget()
    local widget = {}
    return setmetatable(widget, {
        __index = function(_, key)
            if
                key == "CreateFontString"
                or key == "CreateTexture"
                or key == "CreateMaskTexture"
                or key == "CreateLine"
            then
                return createWidget
            end
            -- Anchors are kept once set, so a test can see where a frame was put; one never placed reads as before
            if key == "SetPoint" then
                return function(self, ...)
                    rawset(self, "points", rawget(self, "points") or {})
                    table.insert(rawget(self, "points"), { ... })
                end
            end
            if key == "ClearAllPoints" then
                return function(self)
                    rawset(self, "points", {})
                end
            end
            if key == "GetNumPoints" then
                return function(self)
                    local points = rawget(self, "points")
                    return points and #points or 1
                end
            end
            if key == "GetPoint" then
                return function(self, index)
                    local points = rawget(self, "points")
                    local point = points and points[index or 1]
                    if point then
                        return unpack(point)
                    end
                    return "TOPRIGHT", nil, "TOPRIGHT", -90, -260
                end
            end
            if key == "IsShown" or key == "IsVisible" then
                return function()
                    return true
                end
            end
            if key == "GetCanvas" then
                return createWidget
            end
            if key == "GetMapID" then
                return function(self)
                    return rawget(self, "mapId") or 1420
                end
            end
            if key == "SetMapID" then
                return function(self, mapId)
                    rawset(self, "mapId", mapId)
                end -- the map remembers where it was turned
            end
            -- Scripts are kept, so a test can click a button
            if key == "SetScript" then
                return function(self, name, handler)
                    rawset(self, "scripts", rawget(self, "scripts") or {})
                    rawget(self, "scripts")[name] = handler
                end
            end
            if key == "GetScript" then
                return function(self, name)
                    return (rawget(self, "scripts") or {})[name]
                end
            end
            return function() end
        end,
    })
end

---Installs the frame-related globals the window code touches.
function FakeGame.installWidgets()
    UIParent = createWidget()
    GameTooltip = createWidget()
    CreateFrame = function()
        return createWidget()
    end
    GameFontNormal, GameFontNormalSmall, GameFontNormalLarge, GameFontHighlightSmall = {}, {}, {}, {}
    IsShiftKeyDown = function()
        return false
    end
    InCombatLockdown = function()
        return false
    end
    SlashCmdList = {}
    Minimap, WorldMapFrame = createWidget(), createWidget()
    hooksecurefunc = function() end
    ShowUIPanel, HideUIPanel = function() end, function() end
    SetUIPanelAttribute, UpdateUIPanelPositions = function() end, function() end
    ClearOverrideBindings = function() end
    SetOverrideBinding = function() end
    GetBindingKey = function()
        return "L"
    end
    C_Timer = {
        After = function(_, callback)
            callback()
        end,
        NewTicker = function() end,
    }
end

return FakeGame
