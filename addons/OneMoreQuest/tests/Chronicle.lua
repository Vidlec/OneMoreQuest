-- Tests: the chronicle and the ledger: quests handed in, gold and experience by day, records.

test("a chronicle entry keeps only what the quest database cannot give back, and reads whole", function()
    local ns = createAddon()
    local questId = 301
    local name, level = ns.Database.getQuestField(questId, "name"), ns.Database.getQuestField(questId, "questLevel")
    local entry = ns.Chronicle.compactEntry({
        questId = questId,
        title = name,
        questLevel = level,
        playerLevel = 20,
        acceptedLevel = 20,
        deaths = 0,
        wasGrouped = false,
        experience = 850,
        money = 0,
        drops = {},
        turnedInAt = 1000,
        rewardLink = "|cff1eff00|Hitem:2034::::::::20:::::::|h[Scholarly Robes]|h|r",
    })
    for _, key in ipairs({
        "title",
        "questLevel",
        "acceptedLevel",
        "deaths",
        "wasGrouped",
        "money",
        "drops",
        "rewardLink",
    }) do
        expectEqual(rawget(entry, key), nil, key .. " is not written")
    end
    expectEqual(rawget(entry, "rewardItemId"), 2034, "the reward as its item number")
    expectEqual(rawget(entry, "experience"), 850, "what the database cannot give is kept")
    expectEqual(entry.title, name, "read: the title from the database")
    expectEqual(entry.questLevel, level, "the level")
    expectEqual(entry.acceptedLevel, 20, "taken at the level it was handed in at")
    expectEqual(
        entry.deaths .. " " .. tostring(entry.wasGrouped) .. " " .. entry.money .. " " .. #entry.drops,
        "0 false 0 0",
        "the usual values"
    )
    local unknown =
        ns.Chronicle.compactEntry({ questId = 999999, title = "A Quest Not In The Database", questLevel = 12 })
    expectEqual(rawget(unknown, "title"), "A Quest Not In The Database", "a title the database lacks is kept")
    expectEqual(rawget(unknown, "questLevel"), 12, "and its level")
    local dropped = ns.Chronicle.compactEntry({
        questId = questId,
        drops = { { itemId = 5, drops = 3, kills = 9, expected = 6.666666 } },
    })
    expectEqual(dropped.drops[1].expected, 6.7, "an average to a tenth")
end)

test(
    "the chronicle writes down a quest handed in, with its time, kills by creature, deaths and what it gave",
    function()
        local ns, state = createAddon()
        local clock = 1000
        GetTime = function()
            return clock
        end
        ns.Availability.prepare()
        ns.Chronicle.create()
        ns.KillCounter.create()
        setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
        ns.Drops.getChance = function()
            return 0.25
        end
        local npcId = (ns.Database.getItemField(7001, "npcDrops") or {})[1]
        ns.Chronicle.handleAccept(301)
        clock = clock + 600 -- ten minutes played
        for _ = 1, 20 do
            ns.KillCounter.handleKill(npcId)
        end
        ns.Chronicle.handleDeath()
        state.questLog[301] = { isComplete = true, objectives = { killObjective(12, 12), itemObjective(4, 4) } }
        state.turnedInQuestIds[301] = true
        state.turnedInQuestIds[501] = true -- done before the chronicle began
        ns.Chronicle.handleTurnIn(301, 1450, 520)
        local entries = ns.Chronicle.getBook().entries
        expectEqual(#entries, 1, "one quest written down")
        local entry = entries[1]
        expectEqual(entry.questId, 301, "the quest")
        expectEqual(entry.duration, 600, "how long it took, in time played")
        expectEqual(entry.experience, 1450, "the experience it gave")
        expectEqual(entry.money, 520, "and the money")
        expectEqual(entry.deaths, 1, "a death on the way")
        expectEqual(entry.drops[1].kills, 20, "the kills its drops took")
        expectEqual(entry.drops[1].killsByNpcId[npcId], 20, "by creature")
        expectEqual(entry.drops[1].expected, 16, "against 4 drops at 25%")
        local kills, expected = ns.Chronicle.getEntryKills(entry)
        expectEqual(ns.Chronicle.getLuck(kills, expected) < 0, true, "more kills than expected is unlucky")
        local earlier = ns.Chronicle.getEarlierQuestIds()
        expectEqual(#earlier, 1, "a quest done before the chronicle, without its entry twice")
        expectEqual(earlier[1], 501, "known from the game's record")
        local summary = ns.Chronicle.composeSummary()
        expectEqual(summary.questCount, 2, "every quest done counts")
        expectEqual(summary.chronicledCount, 1, "one since the chronicle began")
        expectEqual(
            summary.fastest and summary.fastest.record,
            entry,
            "the fastest quest: the chronicle's entry, as the history reads it"
        )
        expectEqual(summary.mostKilled and summary.mostKilled.npcId, npcId, "the creature killed most")
        local zones = ns.Chronicle.getZones()
        expectEqual(#zones > 0, true, "the zones quests were done in")
        -- Abandoning a quest counts it as such; handing one in does not
        state.questLog[504] = { isComplete = false, objectives = {} }
        ns.Chronicle.handleAccept(504)
        state.questLog[504] = nil
        ns.Chronicle.handleRemove(504)
        expectEqual(ns.Chronicle.getBook().abandonedCount, 1, "an abandoned quest is counted")
        ns.Chronicle.handleRemove(301)
        expectEqual(ns.Chronicle.getBook().abandonedCount, 1, "a quest handed in is not abandoned")
        GetTime = nil
    end
)

test("the ledger keeps each day's gold by where it came from and went, and experience by source", function()
    local ns = createAddon()
    local clock = 1000
    local saved = {
        GetTime,
        GetRepairAllCost,
        UnitAffectingCombat,
        GetItemInfo,
        GetItemInfoInstant,
        GetNumLootItems,
        GetLootSlotLink,
        GetLootSlotInfo,
        GetLootSourceInfo,
    }
    GetTime = function()
        return clock
    end
    UnitAffectingCombat = function()
        return false
    end
    local Ledger = ns.Ledger
    local function event(name, ...)
        Ledger.handleEvent(nil, name, ...)
    end
    -- Gold, by what was open when it came or went
    event("MERCHANT_SHOW")
    Ledger.handleMoney(3172)
    GetRepairAllCost = function()
        return 312
    end
    event("UPDATE_INVENTORY_DURABILITY")
    Ledger.handleMoney(-312)
    Ledger.handleMoney(-240)
    event("MERCHANT_CLOSED")
    event("LOOT_OPENED")
    Ledger.handleMoney(75)
    event("LOOT_CLOSED")
    event("TRAINER_SHOW")
    Ledger.handleMoney(-900)
    event("TRAINER_CLOSED")
    Ledger.handleMoney(40)
    -- A quest's money and experience come with its hand-in, never twice
    Ledger.handleTurnIn(1450, 520, nil)
    Ledger.handleMoney(520)
    Ledger.handleExperience(1450, 0)
    clock = clock + 10
    -- Experience: a kill's, its rested part apart; a discovery's; and what cannot be placed
    Ledger.handleKill()
    Ledger.handleExperience(300, 100)
    clock = clock + 10
    event("ZONE_CHANGED")
    Ledger.handleExperience(80, 0)
    clock = clock + 10
    Ledger.handleExperience(50, 0)
    local day = Ledger.getDays()[Ledger.getDayKey()]
    expectEqual(day.gold.vendor, 3172, "sold to a vendor")
    expectEqual(day.spent.repairs, 312, "repairs, by the repair cost")
    expectEqual(day.spent.bought, 240, "the rest at a vendor was bought")
    expectEqual(day.gold.looted, 75, "coins looted")
    expectEqual(day.spent.training, 900, "training")
    expectEqual(day.gold.other, 40, "money nothing explains is other")
    expectEqual(day.gold.quests, 520, "quest money once")
    expectEqual(day.xp.quests, 1450, "quest experience once")
    expectEqual(day.quests, 1, "one quest")
    expectEqual(day.xp.kills .. " + " .. day.xp.rested, "200 + 100", "a kill's experience, its rested bonus apart")
    expectEqual(day.xp.discovery, 80, "a discovery")
    expectEqual(day.xp.other, 50, "experience nothing explains is other")
    local totals = Ledger.composeTotals(day)
    expectEqual(totals.net, 3172 + 75 + 40 + 520 - 312 - 240 - 900, "the day's net gold")
    expectEqual(totals.experience, 1450 + 300 + 80 + 50, "the day's experience")
    -- Notable loot: green and better only; a node's herbs and ore counted by kind
    GetItemInfo = function(itemId)
        return "Item", "|Hitem:" .. itemId .. "|h", itemId == 9001 and 3 or 1
    end
    Ledger.noteLoot("|cff0070dd|Hitem:9001::|h[Elder's Mantle]|h|r", 4280)
    Ledger.noteLoot("|cffffffff|Hitem:9002::|h[Broken Tooth]|h|r", 4280)
    expectEqual(#day.loot, 1, "only the green and better kept")
    expectEqual(day.loot[1].itemId .. " from " .. day.loot[1].from, "9001 from 4280", "with the creature it came from")
    GetItemInfoInstant = function(itemId)
        return itemId, "Trade Goods", "Metal & Stone", "", 0, 7, itemId == 2770 and 7 or 0
    end
    GetNumLootItems = function()
        return 1
    end
    GetLootSlotLink = function()
        return "|cffffffff|Hitem:2770::|h[Copper Ore]|h|r"
    end
    GetLootSlotInfo = function()
        return 0, "Copper Ore", 2
    end
    GetLootSourceInfo = function()
        return "GameObject-0-1-0-1-1731-0000ABCD"
    end
    event("LOOT_OPENED")
    event("LOOT_SLOT_CLEARED", 1)
    event("LOOT_CLOSED")
    event("LOOT_OPENED") -- the same node again counts once
    event("LOOT_CLOSED")
    expectEqual(day.nodes, 1, "a node opened")
    expectEqual(day.gathered[2770], 2, "and what it gave")
    expectEqual(day.chests, nil, "a node is not a chest")
    -- The Days chapter draws the day
    local Canvas = getmetatable(ns.Widgets.createCanvas("OneMoreQuestLedgerTestCanvas", UIParent, 200, 100))
    local savedAddText, drawn = Canvas.addText, {}
    Canvas.addText = function(self, text, ...)
        drawn[tostring(text)] = true
        return savedAddText(self, text, ...)
    end
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.toggleChronicle()
    for index, chapter in ipairs(ns.ChroniclePage.CHAPTERS) do
        if chapter.key == "days" then
            ns.ChroniclePage.chapterIndex = index
        end
    end
    ns.Log.refresh()
    Canvas.addText = savedAddText
    for _, label in ipairs({
        "Coins looted",
        "Sold to vendors",
        "Repairs",
        "Training",
        "Kills",
        "  Rested bonus",
        "Discovery",
        "Notable loot",
        "Chests and gathering",
    }) do
        expectEqual(drawn[label], true, "the page shows " .. label)
    end
    GetTime, GetRepairAllCost, UnitAffectingCombat, GetItemInfo, GetItemInfoInstant =
        saved[1], saved[2], saved[3], saved[4], saved[5]
    GetNumLootItems, GetLootSlotLink, GetLootSlotInfo, GetLootSourceInfo = saved[6], saved[7], saved[8], saved[9]
end)

test("on Forever an item's details come from C_Item: notable loot is kept with no global GetItemInfo", function()
    -- (the Forever client has C_Item.GetItemInfo and no global GetItemInfo; the ledger asked for the global alone
    -- and kept no loot in the game, while these tests, giving the global, passed: found by luacheck)
    local ns = createAddon()
    local savedItem, savedInfo, savedInstant, savedTime = C_Item, GetItemInfo, GetItemInfoInstant, GetTime
    GetItemInfo, GetItemInfoInstant = nil, nil
    C_Item = setmetatable({
        GetItemInfo = function(itemId)
            return "Item", "|Hitem:" .. itemId .. "|h", itemId == 9001 and 3 or 1
        end,
    }, { __index = savedItem })
    GetTime = function()
        return 1000
    end
    local Ledger = ns.Ledger
    Ledger.noteLoot("|cff0070dd|Hitem:9001::|h[Elder's Mantle]|h|r", 4280)
    Ledger.noteLoot("|cffffffff|Hitem:9002::|h[Broken Tooth]|h|r", 4280)
    local day = Ledger.getDays()[Ledger.getDayKey()]
    expectEqual(day.loot and #day.loot, 1, "the green item kept, the grey one not")
    C_Item, GetItemInfo, GetItemInfoInstant, GetTime = savedItem, savedInfo, savedInstant, savedTime
end)

test("at a glance: today against an average day, everything kept, and the days' records", function()
    local ns = createAddon()
    local Ledger = ns.Ledger
    local days = Ledger.getDays()
    local today = Ledger.getDayKey()
    local stamp = Ledger.getDayStamp(today)
    local yesterday, before, longAgo =
        Ledger.getDayKey(stamp - 86400), Ledger.getDayKey(stamp - 2 * 86400), Ledger.getDayKey(stamp - 5 * 86400)
    days[today] = { played = 3600, quests = 11, gold = { looted = 50000 }, xp = { kills = 40000 }, kills = 100 }
    days[yesterday] = { played = 7200, quests = 9, gold = { looted = 20000 }, xp = { kills = 30000 }, kills = 80 }
    days[before] = {
        played = 3600,
        quests = 19,
        gold = { looted = 30000 },
        spent = { repairs = 10000 },
        xp = { kills = 10000 },
        kills = 50,
    }
    days[longAgo] = { played = 120, quests = 1, gold = { looted = 900000 } } -- too short to count towards an average day
    local overview = Ledger.composeOverview()
    expectEqual(overview.average.net, 20000, "an average day: the days played long enough, today aside")
    expectEqual(overview.average.quests, 14, "and its quests")
    expectEqual(overview.totals.net, 50000 + 20000 + 20000 + 900000, "every day kept counts towards the totals")
    expectEqual(overview.totals.kills, 230, "kills of every day")
    expectEqual(overview.bestGold.key, longAgo, "the best day for gold")
    expectEqual(overview.mostQuests.value, 19, "most quests in a day")
    expectEqual(overview.streak, 3, "three days in a row up to today")
    expectEqual(overview.firstKey, longAgo, "kept since the first day")
    -- The page: today, altogether and records, no chart
    local Canvas = getmetatable(ns.Widgets.createCanvas("OneMoreQuestGlanceTestCanvas", UIParent, 200, 100))
    local savedAddText, drawn = Canvas.addText, {}
    Canvas.addText = function(self, text, ...)
        drawn[tostring(text)] = true
        return savedAddText(self, text, ...)
    end
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.toggleChronicle()
    ns.ChroniclePage.chapterIndex = 1
    ns.Log.refresh()
    Canvas.addText = savedAddText
    for _, label in ipairs({
        "Today",
        "Altogether",
        "Records",
        "Best day for gold",
        "Most quests in a day",
        "Days in a row",
    }) do
        expectEqual(drawn[label], true, "the page shows " .. label)
    end
    local comparison
    for text in pairs(drawn) do
        comparison = comparison or (text:find("2.5x average", 1, true) and text) or nil
    end
    expectEqual(comparison ~= nil, true, "today's gold says how it compares, under the number")
    expectEqual(drawn["Quests a day"], nil, "no chart of quests a day")
end)

test("a drop quest keeps its longest dry spell and the drops that came on the first kill", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    local target = ns.Location.getObjectiveTarget(301, "item", 1)
    local npcId = (ns.Database.getItemField(target.itemId, "npcDrops") or {})[1]
    ns.Drops.getChance = function(_, killedNpcId)
        return killedNpcId == npcId and 0.25 or nil
    end
    local function setFulfilled(count)
        state.questLog[301] =
            { isComplete = count >= 4, objectives = { killObjective(0, 12), itemObjective(count, 4) } }
    end
    for _ = 1, 3 do
        ns.KillCounter.handleKill(npcId)
    end -- three kills, nothing
    setFulfilled(1) -- the third gave one
    ns.KillCounter.handleKill(npcId)
    setFulfilled(2) -- the very next kill gave one too
    ns.KillCounter.handleKill(npcId)
    ns.KillCounter.handleKill(npcId)
    ns.KillCounter.handleKill(npcId)
    setFulfilled(4) -- the last of three kills gave the last two
    local drop = ns.KillCounter.composeTurnIn(301)[1]
    expectEqual(drop.kills, 7, "every kill counted")
    expectEqual(drop.longestDry, 2, "two kills gave nothing before a drop, twice")
    expectEqual(drop.firstKillDrops, 1, "one drop on the first kill after another")
end)

test("kills and luck: highlights and the five creatures killed most, whatever the number of quests", function()
    local ns = createAddon()
    local entries = ns.Chronicle.getBook().entries
    local function addEntry(questId, drops, kills, expected, killsByNpcId, extra)
        local drop = { itemId = 7001, drops = drops, kills = kills, expected = expected, killsByNpcId = killsByNpcId }
        for key, value in pairs(extra or {}) do
            drop[key] = value
        end
        entries[#entries + 1] = ns.Chronicle.compactEntry({
            questId = questId,
            title = "Quest " .. questId,
            turnedInAt = 100 + #entries,
            drops = { drop },
        })
    end
    addEntry(301, 4, 10, 16, { [9001] = 10 }, { firstKillDrops = 2 }) -- luckiest
    addEntry(302, 2, 30, 8, { [9002] = 30 }, { longestDry = 17 }) -- unluckiest, longest dry spell
    addEntry(303, 1, 12, 13, { [9003] = 12 }) -- rarest: 1 drop in an expected 13 kills
    addEntry(304, 10, 60, 50, { [9004] = 40, [9005] = 9, [9006] = 6, [9007] = 2 }, { firstKillDrops = 1 }) -- longest hunt
    local summary = ns.Chronicle.composeSummary()
    expectEqual(summary.luckiest.questId, 301, "the luckiest quest")
    expectEqual(summary.unluckiest.questId, 302, "the unluckiest")
    expectEqual(summary.rarest.entry.questId, 303, "the rarest drop: 1 in an expected 13 kills")
    expectEqual(summary.longestHunt.entry.questId, 304, "the most kills for one drop objective")
    expectEqual(summary.longestDry.drop.longestDry, 17, "the longest dry spell")
    expectEqual(summary.firstKillDrops, 3, "drops on the first kill, every quest's")
    expectEqual(#summary.mostKilledList, 5, "five creatures at most")
    expectEqual(summary.mostKilledList[1].npcId, 9004, "the most killed first")
    expectEqual(summary.mostKilled.npcId, 9004, "and the one At a glance names")
    -- The page: highlights and the top five, no list of every drop quest
    local Canvas = getmetatable(ns.Widgets.createCanvas("OneMoreQuestKillsTestCanvas", UIParent, 200, 100))
    local savedAddText, drawn = Canvas.addText, {}
    Canvas.addText = function(self, text, ...)
        drawn[tostring(text)] = true
        return savedAddText(self, text, ...)
    end
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.toggleChronicle()
    ns.ChroniclePage.chapterIndex = 5 -- Kills and luck
    ns.Log.refresh()
    Canvas.addText = savedAddText
    for _, label in ipairs({
        "Highlights",
        "Luckiest",
        "Unluckiest",
        "Rarest drop",
        "Longest hunt",
        "Longest dry spell",
        "Dropped on the first kill",
        "17 kills",
        "3 times",
        "Killed most for drops",
        "top 5",
    }) do
        expectEqual(drawn[label], true, "the page shows " .. label)
    end
    expectEqual(drawn["Drop quests"], nil, "no list of every drop quest")
    local sixth = ns.Database.getNpcField(9007, "name") or "Creature 9007"
    expectEqual(drawn[sixth], nil, "the sixth creature is left out")
end)

test("the chronicle's page draws every chapter, a quest's story and a zone, and closes again", function()
    local ns, state = createAddon()
    ns.Availability.prepare()
    state.turnedInQuestIds[501] = true
    ns.Chronicle.getBook().entries[1] = {
        questId = 301,
        title = "Two Fronts",
        questLevel = 14,
        zoneId = TIRISFAL,
        acceptedAt = 100,
        turnedInAt = 700,
        duration = 600,
        experience = 1450,
        money = 520,
        deaths = 1,
        wasGrouped = true,
        drops = { { itemId = 7001, drops = 4, kills = 20, expected = 16, killsByNpcId = { [5002] = 20 } } },
    }
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.toggleChronicle()
    expectEqual(ns.LogState.view, "chronicle", "the book opens the chronicle")
    for index = 1, #ns.ChroniclePage.CHAPTERS do
        ns.ChroniclePage.chapterIndex = index
        ns.Log.refresh()
    end
    ns.ChroniclePage.openZone(TIRISFAL) -- a zone's own page, from the table of zones
    ns.Log.refresh()
    expectEqual(ns.ChroniclePage.formatDuration(4320), "1 h 12 m", "a duration in words")
    ns.Log.selectQuest(201)
    expectEqual(ns.LogState.view, "quests", "opening a quest leaves the chronicle")
    -- The bar's Done button closes whichever is open: the chronicle, or the settings
    local doneButton = ns.LogState.frame.doneButton
    ns.Log.toggleChronicle()
    doneButton:GetScript("OnClick")(doneButton)
    expectEqual(ns.LogState.view, "quests", "Done closes the chronicle (and opens nothing else)")
    ns.Log.openSettings(1)
    doneButton:GetScript("OnClick")(doneButton)
    expectEqual(ns.LogState.view, "quests", "Done closes the settings")
    -- The cog and the book swap one for the other
    ns.Log.openSettings(1)
    ns.Log.toggleChronicle()
    expectEqual(ns.LogState.view, "chronicle", "the book over the settings: the chronicle")
end)

test("a dungeon counts only the quests done in it, and the chronicle's numbers add up", function()
    local ns, state = createAddon()
    addDungeon()
    ns.Availability.prepare()
    local KEEP = 209
    -- "Rumours of the Vault" is given in Tirisfal Glades and only leads in; "Into the Vault" is done inside
    state.turnedInQuestIds[520] = true
    state.turnedInQuestIds[521] = true
    local function getZoneSet(questId)
        local zoneIds = {}
        for _, zoneId in ipairs(ns.Availability.getQuestZoneIds(questId)) do
            zoneIds[zoneId] = true
        end
        return zoneIds
    end
    expectEqual(getZoneSet(520)[KEEP], nil, "a quest that only leads in is not counted for the dungeon")
    expectEqual(getZoneSet(520)[TIRISFAL], true, "but for where it is picked up")
    expectEqual(getZoneSet(521)[KEEP], true, "a quest done inside is the dungeon's")
    local dungeon
    for _, zone in ipairs(ns.Chronicle.getZones()) do
        if zone.zoneId == KEEP then
            dungeon = zone
        end
    end
    expectEqual(dungeon ~= nil, true, "the dungeon is in the chronicle's zones")
    expectEqual(dungeon.isDungeon, true, "as a dungeon")
    expectEqual(dungeon.doneCount >= 1, true, "with the quest done outside counted")
    local summary = dungeon.summary
    expectEqual(
        dungeon.totalCount,
        dungeon.doneCount + summary.inLog + summary.available + summary.notYet,
        "done and left add up"
    )
    ns.ChroniclePage.openZone(KEEP)
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.toggleChronicle()
    ns.ChroniclePage.openZone(KEEP)
    ns.Log.refresh()
end)

test("pointing at anything on any chronicle page shows its tooltip without errors", function()
    local ns, state = createAddon()
    addDungeon()
    ns.Availability.prepare()
    state.turnedInQuestIds[520] = true
    state.turnedInQuestIds[501] = true
    ns.Chronicle.getBook().entries[1] = {
        questId = 301,
        title = "Two Fronts",
        questLevel = 14,
        zoneId = TIRISFAL,
        acceptedAt = 100,
        turnedInAt = 700,
        duration = 600,
        experience = 1450,
        money = 520,
        deaths = 0,
        drops = { { itemId = 7001, drops = 4, kills = 20, expected = 16, killsByNpcId = { [5002] = 20 } } },
    }
    local list = ns.Widgets.createCanvas("TestChronicleList", UIParent, 210, 400)
    local page = ns.Widgets.createCanvas("TestChroniclePage", UIParent, 450, 400)
    local function pointAtEverything(canvas)
        for index = 1, canvas.pools.buttons.usedCount or 0 do
            local button = canvas.pools.buttons[index]
            if button.handleEnter then
                button.handleEnter(button, button.data)
            end
        end
    end
    for index = 1, #ns.ChroniclePage.CHAPTERS do
        ns.ChroniclePage.chapterIndex = index
        list:clear()
        page:clear()
        ns.ChroniclePage.draw(list, page)
        pointAtEverything(list)
        pointAtEverything(page)
    end
    ns.ChroniclePage.openZone(209)
    page:clear()
    ns.ChroniclePage.draw(list, page)
    pointAtEverything(page)
end)

test("the chronicle lists every dungeon with a quest for the character, started or not", function()
    local ns = createAddon()
    addDungeon()
    ns.Availability.prepare()
    local keep
    for _, zone in ipairs(ns.Chronicle.getZones()) do
        keep = zone.zoneId == 209 and zone or keep
    end
    expectEqual(keep ~= nil, true, "the keep, though nothing there is done")
    expectEqual(keep and keep.doneCount, 0, "with nothing done")
    expectEqual(keep and keep.totalCount > 0, true, "and its quests to do")
end)

test("a quest of another race that the game marks done is not the character's in the chronicle", function()
    local ns, state = createAddon()
    state.turnedInQuestIds[505] = true -- "Humans Only", marked done as the twin of one the character did
    state.turnedInQuestIds[501] = true
    local earlier = {}
    for _, questId in ipairs(ns.Chronicle.getEarlierQuestIds()) do
        earlier[questId] = true
    end
    expectEqual(earlier[501], true, "the character's own")
    expectEqual(earlier[505], nil, "not another race's")
end)

test("the chronicle's pictures: the zones as cards, a journal entry as a quest card", function()
    local ns, state = createAddon()
    local Chronicle = ns.Chronicle
    state.playerLevel = 10
    Chronicle.handleAccept(501)
    Chronicle.handleTurnIn(501, 400, 0)
    Chronicle.handleTurnIn(503, 600, 0)
    local Canvas = getmetatable(ns.Widgets.createCanvas("OneMoreQuestPicturesTestCanvas", UIParent, 200, 100))
    local savedAddText, drawn = Canvas.addText, {}
    Canvas.addText = function(self, text, ...)
        drawn[tostring(text)] = true
        return savedAddText(self, text, ...)
    end
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.toggleChronicle()
    for _, key in ipairs({ "zones", "journal", "days", "glance" }) do
        for index, chapter in ipairs(ns.ChroniclePage.CHAPTERS) do
            if chapter.key == key then
                ns.ChroniclePage.chapterIndex = index
            end
        end
        ns.Log.refresh()
    end
    Canvas.addText = savedAddText
    expectEqual(drawn[ns.Database.getZoneName(TIRISFAL)], true, "a zone' + chr(39) + 's card, by its name")
    expectEqual(Chronicle.getBook().levels, nil, "no levels kept since Journey went")
end)

test(
    "the history merges every provider: one entry for a quest known to several, the most trusted's, filled in by the others",
    function()
        local ns, state = createAddon()
        ns.Chronicle.create()
        -- The chronicle's own: 301 handed in at 5000 (no time it was accepted)
        ns.Chronicle.getBook().entries[1] =
            ns.Chronicle.compactEntry({ questId = 301, turnedInAt = 5000, experience = 900, playerLevel = 14 })
        -- Another addon's: 301 again (the same hand-in, a minute off, and when it was accepted), 201 (only it knows it),
        -- and 103 twice, a day apart (a quest done again)
        ns.History.registerProvider({
            name = "Other",
            order = 20,
            getCompletions = function()
                return {
                    ns.Chronicle.readAsEntry({ questId = 301, turnedInAt = 5060, acceptedAt = 4000, playerLevel = 14 }),
                    ns.Chronicle.readAsEntry({ questId = 201, turnedInAt = 3000, playerLevel = 12 }),
                    ns.Chronicle.readAsEntry({ questId = 103, turnedInAt = 1000 }),
                    ns.Chronicle.readAsEntry({ questId = 103, turnedInAt = 1000 + 86400 }),
                }
            end,
        })
        -- The game's: 301 and 201 done, and 501 (nobody dates it)
        state.turnedInQuestIds[301], state.turnedInQuestIds[201], state.turnedInQuestIds[501] = true, true, true
        ns.History.invalidate()
        local entries = ns.Chronicle.getEntries()
        local byQuest = {}
        for _, entry in ipairs(entries) do
            byQuest[entry.questId] = (byQuest[entry.questId] or 0) + 1
        end
        expectEqual(byQuest[301], 1, "301 once, though three providers know it")
        expectEqual(byQuest[201], 1, "201 from the other addon alone")
        expectEqual(byQuest[103], 2, "103 twice: two hand-ins a day apart")
        local own
        for _, entry in ipairs(entries) do
            own = entry.questId == 301 and entry or own
        end
        expectEqual(own.turnedInAt, 5000, "the chronicle's own time, the most trusted")
        expectEqual(own.experience, 900, "and what only it knows")
        expectEqual(own.acceptedAt, 4000, "when it was accepted, filled in from the other addon")
        expectEqual(table.concat(own.sources, ","), "OneMoreQuest,Other,Game", "every provider that knew it")
        expectEqual(entries[1].turnedInAt <= entries[#entries].turnedInAt, true, "oldest first")
        local earlier = ns.Chronicle.getEarlierQuestIds()
        expectEqual(#earlier == 1 and earlier[1] == 501, true, "only the quest nobody dates is earlier")
    end
)

test("Questie's journey is copied into the chronicle while Questie is on, and read as history after", function()
    local ns = createAddon()
    ns.Chronicle.create()
    UnitName, GetRealmName = function()
        return "Thrall"
    end, function()
        return "Forever"
    end
    QuestieConfig = {
        char = {
            ["Thrall - Forever"] = {
                journey = {
                    { Event = "Quest", SubType = "Accept", Quest = 201, Level = 11, Timestamp = 2000 },
                    { Event = "Level", NewLevel = 12, Timestamp = 2500 },
                    { Event = "Quest", SubType = "Complete", Quest = 201, Level = 12, Timestamp = 3000 },
                    { Event = "Quest", SubType = "Accept", Quest = 301, Level = 12, Timestamp = 3100 },
                    { Event = "Quest", SubType = "Abandon", Quest = 301, Level = 12, Timestamp = 3200 },
                },
            },
        },
    }
    ns.Compatibility.getProvider("Questie").importHistory()
    QuestieConfig = nil -- Questie turned off: its saved data no longer there
    ns.History.invalidate()
    local found
    for _, entry in ipairs(ns.Chronicle.getEntries()) do
        found = entry.questId == 201 and entry or found
    end
    expectEqual(found ~= nil, true, "the quest Questie saw done is in the history")
    expectEqual(found and found.turnedInAt, 3000, "when it was handed in")
    expectEqual(found and found.acceptedAt, 2000, "when it was accepted")
    expectEqual(found and found.acceptedLevel, 11, "and the levels")
    expectEqual(found and found.title, ns.Database.getQuestField(201, "name"), "named from the quest database")
    local ups = ns.History.getLevelUps()
    expectEqual(#ups == 1 and ups[1].level == 12 and ups[1].at == 2500, true, "the level reached, with when")
end)

test("Questie's journey is found under Forever's character key, the name and surname", function()
    local ns = createAddon()
    ns.Chronicle.create()
    UnitNameUnmodified, GetRealmName =
        function()
            return "Thrall", "Dunatný"
        end, function()
            return "Forever"
        end
    QuestieConfig = {
        char = {
            ["Thrall Dunatný"] = {
                journey = {
                    { Event = "Quest", SubType = "Complete", Quest = 201, Level = 12, Timestamp = 3000 },
                },
            },
        },
    }
    ns.Compatibility.getProvider("Questie").importHistory()
    QuestieConfig, UnitNameUnmodified = nil, nil
    local imported = ns.Chronicle.getBook().imported
    expectEqual(imported and imported.Questie and #imported.Questie.completions, 1, "the completion copied")
end)
test("one lucky quest is the luckiest on every page, never the unluckiest", function()
    local ns = createAddon()
    local entries = ns.Chronicle.getBook().entries
    local function addEntry(questId, kills, expected)
        local drop = { itemId = 7001, drops = 4, kills = kills, expected = expected, killsByNpcId = { [9001] = kills } }
        entries[#entries + 1] = ns.Chronicle.compactEntry({
            questId = questId,
            title = "Quest " .. questId,
            turnedInAt = 100 + #entries,
            drops = { drop },
        })
    end
    addEntry(301, 10, 16) -- fewer kills than expected
    local summary = ns.Chronicle.composeSummary()
    expectEqual(summary.luckiest and summary.luckiest.questId, 301, "the one quest is the luckiest")
    expectEqual(summary.unluckiest, nil, "and not the unluckiest as well")
    addEntry(302, 12, 14) -- lucky too, less so
    ns.History.invalidate()
    summary = ns.Chronicle.composeSummary()
    expectEqual(summary.luckiest and summary.luckiest.questId, 301, "the luckier of two lucky quests")
    expectEqual(summary.unluckiest, nil, "a lucky quest is never called the unluckiest")
    -- The pages: Kills and luck, and At a glance, name it the same
    for _, chapterIndex in ipairs({ 1, 5 }) do
        local Canvas =
            getmetatable(ns.Widgets.createCanvas("OneMoreQuestLuckTestCanvas" .. chapterIndex, UIParent, 200, 100))
        local savedAddText, drawn = Canvas.addText, {}
        Canvas.addText = function(self, text, ...)
            drawn[tostring(text)] = true
            return savedAddText(self, text, ...)
        end
        ns.Log.create()
        ns.MapDock.create()
        ns.Log.toggle()
        if not ns.LogState.view or ns.LogState.view ~= "chronicle" then
            ns.Log.toggleChronicle()
        end
        ns.ChroniclePage.chapterIndex = chapterIndex
        ns.Log.refresh()
        Canvas.addText = savedAddText
        expectEqual(drawn["Unluckiest"], nil, "no page calls it the unluckiest (chapter " .. chapterIndex .. ")")
    end
end)

test("Czech dates: the calendar's month on its own and the weekdays over its columns", function()
    local ns = createAddon()
    ns.settings.language = "cs"
    local stamp = os.time({ year = 2026, month = 11, day = 17, hour = 12 }) -- a Tuesday
    expectEqual(ns.Chronicle.formatShownDate("%B %Y", stamp), "Listopad 2026", "the month alone, as a heading")
    expectEqual(ns.Chronicle.formatShownDate("%a", stamp), "Út", "a weekday, short")
    expectEqual(
        ns.Chronicle.formatShownDate("%A %d %B", stamp),
        "Úterý 17. listopadu",
        "a day with its month, as before"
    )
    expectEqual(ns.Chronicle.formatShownDate("%d %b %Y", stamp), "17. 11. 2026", "and short")
    ns.settings.language = "en"
    expectEqual(ns.Chronicle.formatShownDate("%B %Y", stamp), "November 2026", "English as the game gives it")
end)

test("the journal draws its newest quests first and the older ones on asking, not stopping at 300", function()
    local ns = createAddon()
    local entries = ns.Chronicle.getBook().entries
    for index = 1, 305 do
        entries[index] =
            ns.Chronicle.compactEntry({ questId = 301, title = "Quest " .. index, turnedInAt = 1000 + index * 60 })
    end
    local Canvas = getmetatable(ns.Widgets.createCanvas("OneMoreQuestJournalTestCanvas", UIParent, 200, 100))
    local savedAddText, drawn = Canvas.addText, {}
    Canvas.addText = function(self, text, ...)
        drawn[tostring(text)] = true
        return savedAddText(self, text, ...)
    end
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.toggleChronicle()
    ns.ChroniclePage.chapterIndex = 3 -- Journal
    ns.Log.refresh()
    expectEqual(drawn["Show older quests (5 more)"], true, "a link says how many older quests are left out")
    local canvas = ns.LogState.detail
    local link
    for index = 1, canvas.pools.buttons.usedCount or 0 do
        local button = canvas.pools.buttons[index]
        if rawget(button, "data") == nil and type(rawget(button, "handleClick")) == "function" then -- (the rows carry their entry)
            link = button
        end
    end
    expectEqual(link ~= nil, true, "the link can be clicked")
    drawn = {}
    link.handleClick(link.data)
    Canvas.addText = savedAddText
    expectEqual(drawn["Show older quests (5 more)"], nil, "with them drawn, no link is left")
end)

test(
    "with spoilers held back, a hand-in keeps the preset and whether a hint was taken; the journal and At a glance count them",
    function()
        local ns, state = createAddon()
        ns.Availability.prepare()
        ns.Chronicle.create()
        ns.KillCounter.create()
        ns.Spoilers.create()
        -- In Guide nothing is kept, and At a glance says nothing of spoilers
        ns.Chronicle.handleTurnIn(301, 100, 0)
        local entries = ns.Chronicle.getBook().entries
        expectEqual(rawget(entries[1], "spoilers"), nil, "Guide: no preset kept")
        expectEqual(ns.Chronicle.isFoundYourself(entries[1]), false, "and no mark")
        expectEqual(ns.Chronicle.composeSummary().hasSpoilers, false, "a Guide player sees nothing of it")
        -- Explorer: one quest with a hint, one without
        ns.Spoilers.setPreset("explorer")
        setQuest(state, 302, false, { killObjective(0, 4) })
        setQuest(state, 303, false, { killObjective(0, 4) })
        ns.Spoilers.giveHint(302)
        ns.Chronicle.handleTurnIn(302, 100, 0)
        ns.Chronicle.handleTurnIn(303, 100, 0)
        local hinted, found = entries[2], entries[3]
        expectEqual(hinted.spoilers, "explorer", "the preset in force")
        expectEqual(hinted.hinted, true, "the hint copied at the hand-in")
        expectEqual(ns.Chronicle.isFoundYourself(hinted), false, "no mark with a hint")
        expectEqual(found.spoilers, "explorer", "the other's preset")
        expectEqual(rawget(found, "hinted"), nil, "no hint: nothing kept")
        expectEqual(ns.Chronicle.isFoundYourself(found), true, "found yourself")
        -- Spoilers forgets its hints once the quests leave the log; the chronicle keeps them
        ns.Spoilers.getMemory().hinted[302] = nil
        expectEqual(ns.Chronicle.isFoundYourself(hinted), false, "still hinted in the chronicle")
        ns.Spoilers.notePeek({})
        local summary = ns.Chronicle.composeSummary()
        expectEqual(summary.hasSpoilers, true, "At a glance counts them now")
        expectEqual(summary.spoilerCount, 2, "two with spoilers held back")
        expectEqual(summary.foundCount, 1, "one found yourself")
        expectEqual(summary.hintedCount, 1, "one with a hint")
        expectEqual(summary.peekCount, 1, "and a peek")
        -- The pages draw them: the journal's mark, the quest's tile, At a glance's totals
        ns.Log.create()
        ns.MapDock.create()
        ns.Log.toggle()
        ns.Log.toggleChronicle()
        for index = 1, #ns.ChroniclePage.CHAPTERS do
            ns.ChroniclePage.chapterIndex = index
            ns.Log.refresh()
        end
        ns.ChroniclePage.openQuest(303)
        ns.Log.refresh()
        ns.ChroniclePage.openQuest(302)
        ns.Log.refresh()
    end
)
