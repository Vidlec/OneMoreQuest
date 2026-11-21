local _, ns = ...

-- The ledger: a small summary of each day played, for the chronicle's Days chapter. Gold in and out by where it
-- came from or went, experience by source (the rested part of kills apart), quests, kills, deaths, levels, time
-- played, chests and gathering nodes opened, and the notable things looted (green and better).
--
-- Where money comes from is told by what is open when it arrives: a loot window, a vendor, the mailbox (an auction
-- sale is a mail with a seller's invoice), a trainer, a flight master, the auction house. Quest money and
-- experience come with the game's own word that a quest was handed in. Experience right after a creature the
-- group fought dies is a kill's, its rested part what the rested pool lost; right after entering an area, a
-- discovery's. What cannot be placed is "other": never guessed.
--
-- Kept per character in the chronicle's book, a day to a record; only what is not zero is written.
local Ledger = {}
ns.Ledger = Ledger

local KILL_SECONDS = 1.5 -- experience this soon after a kill, or after leaving combat, is the kill's
local DISCOVERY_SECONDS = 2 -- experience this soon after entering an area is its discovery's
local QUEST_DIALOG_SECONDS = 2 -- money and experience this soon after the hand-in dialog are the quest's
local FLIGHT_SECONDS = 3 -- money paid this soon after taking a flight is its fare
local MAX_NOTABLE_LOOT = 15 -- notable things kept a day
local MAX_GATHERED_KINDS = 20 -- kinds of herb and ore kept a day
local NOTABLE_QUALITY = 2 -- green and better
local TRADE_GOODS_CLASS = 7
local GATHERED_SUBCLASSES = { [7] = true, [9] = true } -- metal and stone, herbs
local TICK_SECONDS = 60

local eventFrame
local lastMoney, lastExperience, lastMaxExperience, lastLevel, lastRested
local lastTick
local openWindows = {} -- [kind] = true while a vendor, mailbox, trainer, flight map, auction house or loot window is open
local lastKillAt, lastAreaAt, questDialogUntil, flightAt, combatEndAt = -100, -100, -100, -100, -100
local repairCost, pendingMailKind -- what repairing everything costs now, read while it still can be
local lootSlots, lootSource = {}, nil -- the open loot window's items, and what it was opened on
local openedObjects = {} -- [GUID] = true: chests and nodes counted this session, opened twice or not

local function getNow()
    return GetTime and GetTime() or 0
end

---@return string key Today, as days are kept: "2026-11-17"
function Ledger.getDayKey(stamp)
    return ns.Chronicle.formatDate("%Y-%m-%d", stamp or ns.Chronicle.getNow())
end

---@return table days [day key] = the day's record
function Ledger.getDays()
    local book = ns.Chronicle.getBook()
    book.days = book.days or {}
    return book.days
end

---@return table day Today's record, begun at the level the character is at
local function getToday()
    local days = Ledger.getDays()
    local key = Ledger.getDayKey()
    if not days[key] then
        local level = UnitLevel and UnitLevel("player") or nil
        days[key] = { levelFrom = level }
    end
    return days[key]
end

---Adds to a number in a part of today's record ("gold", "xp"…), or to the record itself without a part.
local function add(part, key, amount)
    if not amount or amount == 0 then
        return
    end
    local day = getToday()
    local target = day
    if part then
        day[part] = day[part] or {}
        target = day[part]
    end
    target[key] = (target[key] or 0) + amount
end
Ledger.add = add

---Time played goes to the day it is played on.
local function addPlayed()
    local now = getNow()
    if lastTick then
        add(nil, "played", math.floor(now - lastTick + 0.5))
    end
    lastTick = now
end

---------------------------------------------------------------------------------------------------------------
-- Gold

---Money came or went: placed by what was open when it did.
---@param amount number Copper; below zero when spent
function Ledger.handleMoney(amount)
    local now = getNow()
    if amount == 0 or now <= questDialogUntil then
        return -- a quest's money comes with its hand-in (handleTurnIn)
    end
    if amount > 0 then
        local source = openWindows.loot and "looted" or openWindows.merchant and "vendor"
            or openWindows.mail and (pendingMailKind or "mail") or "other"
        add("gold", source, amount)
        return
    end
    local spent = -amount
    local purpose
    if openWindows.merchant then
        purpose = repairCost and repairCost > 0 and math.abs(repairCost - spent) <= 1 and "repairs" or "bought"
    elseif openWindows.trainer then
        purpose = "training"
    elseif openWindows.taxi or now - flightAt <= FLIGHT_SECONDS then
        purpose = "flights"
    elseif openWindows.auction then
        purpose = "auction"
    else
        purpose = "other"
    end
    add("spent", purpose, spent)
end

---------------------------------------------------------------------------------------------------------------
-- Experience

---Experience came: placed by what happened just before.
---@param amount number
---@param restedUsed number What the rested pool lost meanwhile: the rested bonus on kills
function Ledger.handleExperience(amount, restedUsed)
    local now = getNow()
    if amount <= 0 or now <= questDialogUntil then
        return -- a quest's experience comes with its hand-in
    end
    -- The game may give a kill's experience a moment before it says the creature died: in combat, or just out
    -- of it, experience is a kill's too
    local isFighting = UnitAffectingCombat and UnitAffectingCombat("player") == true
    if now - lastKillAt <= KILL_SECONDS or isFighting or now - combatEndAt <= KILL_SECONDS then
        local rested = math.min(math.max(restedUsed or 0, 0), amount)
        add("xp", "kills", amount - rested)
        add("xp", "rested", rested)
    elseif now - lastAreaAt <= DISCOVERY_SECONDS then
        add("xp", "discovery", amount)
    else
        add("xp", "other", amount)
    end
end

local function readExperience()
    local experience, maxExperience = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0
    local level = UnitLevel and UnitLevel("player") or 0
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    if lastExperience then
        local gained = level > lastLevel and (lastMaxExperience - lastExperience) + experience or experience - lastExperience
        Ledger.handleExperience(gained, (lastRested or 0) - rested)
    end
    if lastLevel and level > lastLevel then
        getToday().levelTo = level
    end
    lastExperience, lastMaxExperience, lastLevel, lastRested = experience, maxExperience, level, rested
end

---------------------------------------------------------------------------------------------------------------
-- What else happened

---A quest was handed in: its money and experience, as the game gives them, and a reward worth noting.
function Ledger.handleTurnIn(experience, money, rewardLink)
    add(nil, "quests", 1)
    add("gold", "quests", money or 0)
    add("xp", "quests", experience or 0)
    questDialogUntil = getNow() + QUEST_DIALOG_SECONDS
    if rewardLink then
        Ledger.noteLoot(rewardLink, "quest")
    end
end

---A creature the group fought died.
function Ledger.handleKill()
    lastKillAt = getNow()
    add(nil, "kills", 1)
end

function Ledger.handleDeath()
    add(nil, "deaths", 1)
end

---A thing looted, kept when it is green or better.
---@param from string|number "quest", "chest", or the creature's id
function Ledger.noteLoot(link, from)
    local itemId = type(link) == "string" and tonumber(link:match("item:(%d+)")) or link
    local quality = itemId and GetItemInfo and select(3, GetItemInfo(itemId))
    if not itemId or (quality or 0) < NOTABLE_QUALITY then
        return
    end
    local day = getToday()
    day.loot = day.loot or {}
    if #day.loot < MAX_NOTABLE_LOOT then
        day.loot[#day.loot + 1] = { itemId = itemId, from = from }
    end
end

---@return boolean isGathered An herb or ore, by the item's kind
local function isGathered(itemId)
    if not (itemId and GetItemInfoInstant) then
        return false
    end
    local classId, subclassId = select(6, GetItemInfoInstant(itemId))
    return classId == TRADE_GOODS_CLASS and GATHERED_SUBCLASSES[subclassId] == true
end

---A loot window opened: what it holds, and what it is on (a creature, a chest, a node).
local function readLoot()
    lootSlots, lootSource = {}, nil
    for slot = 1, GetNumLootItems and GetNumLootItems() or 0 do
        local link = GetLootSlotLink and GetLootSlotLink(slot)
        local _, _, quantity = GetLootSlotInfo(slot)
        lootSlots[slot] = { link = link, quantity = quantity or 1, itemId = link and tonumber(link:match("item:(%d+)")) }
        local guid = not lootSource and GetLootSourceInfo and GetLootSourceInfo(slot)
        if type(guid) == "string" then
            -- "Creature-0-4372-0-1-3110-0000A1B2C3": the kind first, the creature's or object's id sixth
            local parts = {}
            for part in guid:gmatch("[^-]+") do
                parts[#parts + 1] = part
            end
            lootSource = { kind = parts[1], id = tonumber(parts[6]), guid = guid }
        end
    end
    if lootSource and lootSource.kind == "GameObject" and not openedObjects[lootSource.guid] then
        openedObjects[lootSource.guid] = true
        local isNode = false
        for _, slot in pairs(lootSlots) do
            isNode = isNode or isGathered(slot.itemId)
        end
        lootSource.isNode = isNode
        add(nil, isNode and "nodes" or "chests", 1)
    end
end

---A thing taken from the open loot window.
local function takeLoot(slot)
    local taken = lootSlots[slot]
    if not (taken and taken.itemId) then
        return
    end
    local isObject = lootSource and lootSource.kind == "GameObject"
    if isObject and lootSource.isNode and isGathered(taken.itemId) then
        local day = getToday()
        day.gathered = day.gathered or {}
        local kinds = 0
        for _ in pairs(day.gathered) do
            kinds = kinds + 1
        end
        if day.gathered[taken.itemId] or kinds < MAX_GATHERED_KINDS then
            day.gathered[taken.itemId] = (day.gathered[taken.itemId] or 0) + taken.quantity
        end
        return
    end
    Ledger.noteLoot(taken.itemId, isObject and "chest" or (lootSource and lootSource.id))
end

---------------------------------------------------------------------------------------------------------------

local WINDOW_EVENTS = {
    MERCHANT_SHOW = { "merchant", true }, MERCHANT_CLOSED = { "merchant", false },
    MAIL_SHOW = { "mail", true }, MAIL_CLOSED = { "mail", false },
    TRAINER_SHOW = { "trainer", true }, TRAINER_CLOSED = { "trainer", false },
    TAXIMAP_OPENED = { "taxi", true }, TAXIMAP_CLOSED = { "taxi", false },
    AUCTION_HOUSE_SHOW = { "auction", true }, AUCTION_HOUSE_CLOSED = { "auction", false },
    LOOT_OPENED = { "loot", true }, LOOT_CLOSED = { "loot", false },
}

local function handleEvent(_, event, ...)
    local window = WINDOW_EVENTS[event]
    if window then
        -- A window closes a moment after the money it brought arrives: it is let go a little later
        if window[2] then
            openWindows[window[1]] = true
        elseif C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() openWindows[window[1]] = nil end)
        else
            openWindows[window[1]] = nil
        end
        if event == "LOOT_OPENED" then
            readLoot()
        elseif event == "MERCHANT_SHOW" then
            repairCost = GetRepairAllCost and (GetRepairAllCost()) or nil
        end
        return
    end
    if event == "PLAYER_MONEY" then
        local money = GetMoney()
        if lastMoney then
            Ledger.handleMoney(money - lastMoney)
        end
        lastMoney = money
    elseif event == "PLAYER_XP_UPDATE" or event == "PLAYER_LEVEL_UP" then
        readExperience()
    elseif event == "LOOT_SLOT_CLEARED" then
        takeLoot((...))
    elseif event == "QUEST_COMPLETE" or event == "QUEST_FINISHED" then
        questDialogUntil = getNow() + QUEST_DIALOG_SECONDS
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        lastAreaAt = getNow()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatEndAt = getNow()
    elseif event == "MERCHANT_UPDATE" or event == "UPDATE_INVENTORY_DURABILITY" then
        repairCost = GetRepairAllCost and (GetRepairAllCost()) or nil
    elseif event == "PLAYER_DEAD" then
        Ledger.handleDeath()
    elseif event == "PLAYER_LOGOUT" then
        addPlayed()
    end
end

Ledger.handleEvent = handleEvent

function Ledger.create()
    if eventFrame or not CreateFrame then
        return
    end
    lastMoney = GetMoney and GetMoney() or nil
    readExperience()
    lastTick = getNow()
    getToday()
    eventFrame = CreateFrame("Frame")
    local events = { "PLAYER_MONEY", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "LOOT_SLOT_CLEARED", "QUEST_COMPLETE", "QUEST_FINISHED",
        "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_DEAD", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED",
        "MERCHANT_UPDATE", "UPDATE_INVENTORY_DURABILITY" }
    for event in pairs(WINDOW_EVENTS) do
        events[#events + 1] = event
    end
    for _, event in ipairs(events) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    eventFrame:SetScript("OnEvent", handleEvent)
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(TICK_SECONDS, addPlayed)
    end
    -- Flights and auction sales are told from other money by what starts them
    if hooksecurefunc then
        if TakeTaxiNode then
            hooksecurefunc("TakeTaxiNode", function() flightAt = getNow() end)
        end
        -- An auction sale comes as a mail with a seller's invoice; taken one by one or all at once
        local function readMail(index)
            local invoiceType = GetInboxInvoiceInfo and GetInboxInvoiceInfo(index)
            pendingMailKind = invoiceType == "seller" and "auction" or "mail"
        end
        for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
            if _G[name] then
                hooksecurefunc(name, readMail)
            end
        end
    end
end

---What a day comes to: gold in, spent and net; experience; its time played.
---@return { income: number, spent: number, net: number, experience: number, played: number }
function Ledger.composeTotals(day)
    local income, spent, experience = 0, 0, 0
    for _, amount in pairs(day.gold or {}) do
        income = income + amount
    end
    for _, amount in pairs(day.spent or {}) do
        spent = spent + amount
    end
    for _, amount in pairs(day.xp or {}) do
        experience = experience + amount
    end
    return { income = income, spent = spent, net = income - spent, experience = experience, played = day.played or 0 }
end

---@return number stamp Noon of a day kept as "2026-11-17"
function Ledger.getDayStamp(key)
    local year, month, day = key:match("^(%d+)-(%d+)-(%d+)$")
    if not (year and time) then
        return ns.Chronicle.getNow()
    end
    return time({ year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 12 })
end

local AVERAGE_MIN_PLAYED = 600 -- a day counts towards the average day when played this long

---Everything kept, for the chronicle's first page: today and an average day to set it against, the totals of
---every day kept, and the days' records.
---@return { today: table?, todayTotals: table?, average: { net: number, experience: number, quests: number }?, totals: table,
---firstKey: string?, bestGold: table?, bestExperience: table?, mostQuests: table?, streak: number }
function Ledger.composeOverview()
    local days = Ledger.getDays()
    local todayKey = Ledger.getDayKey()
    local overview = { totals = { net = 0, experience = 0, kills = 0, quests = 0, played = 0 }, streak = 0 }
    local averageSum, averageCount = { net = 0, experience = 0, quests = 0 }, 0
    for key, day in pairs(days) do
        local totals = Ledger.composeTotals(day)
        local quests = day.quests or 0
        overview.totals.net = overview.totals.net + totals.net
        overview.totals.experience = overview.totals.experience + totals.experience
        overview.totals.kills = overview.totals.kills + (day.kills or 0)
        overview.totals.quests = overview.totals.quests + quests
        overview.totals.played = overview.totals.played + totals.played
        if not overview.firstKey or key < overview.firstKey then
            overview.firstKey = key
        end
        if key == todayKey then
            overview.today, overview.todayTotals = day, totals
        elseif totals.played >= AVERAGE_MIN_PLAYED then
            averageSum.net, averageSum.experience = averageSum.net + totals.net, averageSum.experience + totals.experience
            averageSum.quests, averageCount = averageSum.quests + quests, averageCount + 1
        end
        if totals.net > 0 and (not overview.bestGold or totals.net > overview.bestGold.value) then
            overview.bestGold = { key = key, value = totals.net }
        end
        if totals.experience > 0 and (not overview.bestExperience or totals.experience > overview.bestExperience.value) then
            overview.bestExperience = { key = key, value = totals.experience }
        end
        if quests > 0 and (not overview.mostQuests or quests > overview.mostQuests.value) then
            overview.mostQuests = { key = key, value = quests }
        end
    end
    if averageCount > 0 then
        overview.average = {
            net = averageSum.net / averageCount, experience = averageSum.experience / averageCount, quests = averageSum.quests / averageCount,
        }
    end
    -- Days in a row: back from today, or from yesterday while today is not played yet
    local stamp = Ledger.getDayStamp(todayKey)
    if not days[todayKey] then
        stamp = stamp - 86400
    end
    while days[Ledger.getDayKey(stamp)] do
        overview.streak = overview.streak + 1
        stamp = stamp - 86400
    end
    return overview
end

ns.registerModule({ name = "Ledger", create = Ledger.create })
