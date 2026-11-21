-- Tests: what quests are worth: rewards, prices, loot, kills counted against the drops expected.

test("experience from the database is lowered for a quest the character has outlevelled", function()
    local ns = createAddon()
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            if name == "QuestXP" then
                return { db = { [201] = { 13, 1000 } } }
            end
            return original(name)
        end
    end)(LibQuestieDB.Support.Get)
    expectEqual(ns.Database.getQuestExperience(201, 13), 1000, "full at the quest's level")
    expectEqual(ns.Database.getQuestExperience(201, 18), 1000, "and up to five levels above it")
    expectEqual(ns.Database.getQuestExperience(201, 19), 800, "a fifth less per level after that")
    expectEqual(ns.Database.getQuestExperience(201, 21), 400, "and less again")
    expectEqual(ns.Database.getQuestExperience(201, 40), 100, "down to a tenth")
    expectEqual(ns.Database.getQuestExperience(999, 40), nil, "nothing for a quest the database has no amount for")
end)

test("profit adds the reward to the expected loot of the kills still needed", function()
    local ns, state = createAddon()
    addProfitData()
    setQuest(state, 301, false, { killObjective(2, 12), itemObjective(1, 4) }) -- 10 bandits and 3 fangs to go
    GetQuestLogRewardMoney = function() return 700 end
    GetNumQuestLogChoices = function() return 2 end
    GetQuestLogChoiceInfo = function(index) return "Choice " .. index, nil, 1, nil, nil, index == 1 and 9201 or 9202 end
    local profit = ns.Profit.compose(301)
    expectEqual(profit.rewardMoney, 700, "the money the quest pays")
    expectEqual(profit.rewardValue, 700 + 4000, "plus only the most valuable of the items to choose from")
    expectEqual(#profit.mobs, 2, "two kinds of creature still to kill")
    local bandits, wolves
    for _, mob in ipairs(profit.mobs) do
        if mob.npcId == 5001 then bandits = mob else wolves = mob end
    end
    expectEqual(bandits.kills, 10, "the kills left on the kill objective")
    expectEqual(bandits.lootValue, 10 * 0.4 * 50, "their loot, the quest-only drop left out")
    expectEqual(wolves.kills, 3 / 0.25, "kills expected for the items left, by the database's drop rate")
    expectEqual(wolves.lootValue, 12 * 0.5 * 200, "and what those kills drop besides")
    expectEqual(profit.total, 4700 + 200 + 1200, "reward and loot together")
    expectEqual(profit.hasLootData, true, "a loot table is installed")
    expectEqual(ns.Profit.format(profit):find("Media\\Tilde", 1, true) ~= nil, true, "shown with the estimate sign")
    -- The list row, the rewards box and the breakdown all draw with these numbers
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.selectQuest(301)
    ns.Log.refresh()
    removeProfitData()
end)

test("profit without a loot table is the reward alone, and says so", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    GetQuestLogRewardMoney = function() return 300 end
    local profit = ns.Profit.compose(201)
    expectEqual(profit.total, 300, "only what the quest pays")
    expectEqual(profit.kills, 7, "the kills are still counted")
    expectEqual(profit.hasLootData, false, "and it is known that loot is missing")
    removeProfitData()
end)

test("auction prices count after the cut, never below the vendor, and never for bound items", function()
    local ns = createAddon()
    addProfitData()
    Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(_, itemId)
        return ({ [9101] = 1000, [9102] = 100, [9202] = 99999 })[itemId]
    end } } }
    expectEqual(ns.Prices.getItemValue(9101), 950, "the auction price less the house's 5%")
    expectEqual(ns.Prices.getItemValue(9102), 200, "the vendor price when the auction pays less")
    expectEqual(select(3, ns.Prices.getItemValue(9101)), true, "and it says which items went at an auction price")
    expectEqual(select(3, ns.Prices.getItemValue(9102)), false, "and which at the vendor's")
    expectEqual(ns.Prices.getItemValue(9202), 4000, "an item that binds on pickup goes to the vendor")
    ns.settings.shouldUseAuctionPrices = false
    expectEqual(ns.Prices.getItemValue(9101), 50, "and with auction prices off, vendor prices only")
    local _, isPending = ns.Prices.getItemValue(4242)
    expectEqual(isPending, true, "an item the game has not loaded yet is pending")
    removeProfitData()
end)

test("the profit estimate, the kill bar and the tracker hunt the same creature with the same chance", function()
    local ns, state = createAddon()
    LibQuestieDB.Item.Get = (function(original)
        return function(id, field)
            if id == 7001 and field == "npcDrops" then
                return { 5002, 5001 } -- wolves far off and far above, bandits here
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Item.Get)
    LibQuestieDB.Npc.Get = (function(original)
        return function(id, field)
            if id == 5002 and field == "minLevel" then
                return 30
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Npc.Get)
    ns.Drops.getChance = function(_, npcId) return ({ [5001] = 0.25, [5002] = 0.6 })[npcId] end
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    local hunted = ns.Drops.getHuntedSource(7001)
    expectEqual(hunted.npcId, 5001, "the creature here, not the likelier one twenty levels up")
    local progress = ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2])
    expectEqual(progress.remaining, 16, "the kill bar: 4 drops at 25%")
    expectEqual(ns.KillCounter.getDropChance(301, 2), 0.25, "the tracker's chance")
    local profit = ns.Profit.compose(301)
    expectEqual(#profit.mobs, 1, "one creature to kill")
    expectEqual(profit.mobs[1].npcId, 5001, "the same creature in the estimate")
    expectEqual(profit.kills, progress.remaining, "and the same kills still to go")
end)

test("kills of creatures that drop a quest's item are counted against the kills expected", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    local target = ns.Location.getObjectiveTarget(301, "item", 1)
    local npcId = (ns.Database.getItemField(target.itemId, "npcDrops") or {})[1]
    expectEqual(npcId ~= nil, true, "the fake item drops from a creature")
    ns.Drops.getChance = function(_, killedNpcId) return killedNpcId == npcId and 0.25 or nil end
    expectEqual(ns.Database.getNpcId("Creature-0-4372-0-1-" .. npcId .. "-0000A1B2C3"), npcId, "the creature read from its identifier")
    expectEqual(ns.Database.getNpcId("Player-4372-00ABCDEF"), nil, "players are not creatures")
    local before = ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2])
    expectEqual(before.kills, 0, "shown before the first kill")
    expectEqual(before.remaining, 16, "with what all 4 drops will take")
    expectEqual(before.earlierDrops, 0, "nothing collected before")
    for _ = 1, 8 do
        ns.KillCounter.handleKill(npcId)
    end
    ns.KillCounter.printCounts()
    ns.KillCounter.handleKill(424242) -- a creature that drops nothing for the quest
    state.questLog[301] = { isComplete = false, objectives = { killObjective(0, 12), itemObjective(1, 4) } }
    local objective = ns.QuestState.getQuest(301).objectives[2]
    local progress = ns.KillCounter.getProgress(301, 2, objective)
    expectEqual(progress.kills, 8, "only the kills that could drop the item")
    expectEqual(progress.expected, 4, "1 drop at a 25% chance is 4 kills on average")
    expectEqual(progress.remaining, 12, "3 drops to go is about 12 kills")
    expectEqual(ns.KillCounter.formatKills(progress, " · "), "8 kills for 1 drop · average 4", "the kills for the drops got, against the average")
    expectEqual(progress.isUnlucky, true, "8 kills for what an average player gets in 4")
    expectEqual(ns.KillCounter.formatKills({ kills = 3, drops = 0, expected = 0 }, " · "), "3 kills, no drop yet", "no drop yet: no average of 0")
    expectEqual(ns.KillCounter.formatKills({ kills = 0, drops = 0, expected = 0 }, " · "), "No kills counted yet", "nothing yet")
    -- Drops collected before counting started are an earlier part of the bar, at the kills they would take
    state.questLog[302] = nil
    ns.KillCounter.forget(301)
    state.questLog[301] = { isComplete = false, objectives = { killObjective(0, 12), itemObjective(3, 4) } }
    local earlier = ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2])
    expectEqual(earlier.earlierDrops, 3, "3 collected before")
    expectEqual(earlier.earlierKills, 12, "about 12 kills at 25%")
    state.questLog[301] = { isComplete = false, objectives = { killObjective(0, 12), itemObjective(1, 4) } }
    ns.Log.create()
    ns.MapDock.create()
    ns.Log.toggle()
    ns.Log.selectQuest(301) -- the quest page draws its bar
    ns.Tracker.create()
    ns.Tracker.refresh() -- and the tracker's tooltip has the kills (drawn by hovering a row)
    -- Ready to hand in: the page keeps what the drops took, under the turn-in
    local Canvas = getmetatable(ns.Widgets.createCanvas("OneMoreQuestTestCanvas", UIParent, 200, 100))
    local savedAddText, drawn = Canvas.addText, {}
    Canvas.addText = function(self, text, ...)
        drawn[#drawn + 1] = tostring(text)
        return savedAddText(self, text, ...)
    end
    for _ = 1, 8 do
        ns.KillCounter.handleKill(npcId)
    end
    state.questLog[301] = { isComplete = true, objectives = { killObjective(12, 12), itemObjective(4, 4) } }
    drawn = {}
    ns.Log.refresh()
    local summary
    for _, text in ipairs(drawn) do
        summary = summary or (text:find("8 kills for", 1, true) and text:find("average", 1, true) and text) or nil
    end
    expectEqual(summary ~= nil, true, "the kills and the kills expected, once the quest is ready")
    expectEqual(summary and summary:find("to go", 1, true), nil, "and nothing left to go")
    Canvas.addText = savedAddText
    ns.KillCounter.forget(301)
    expectEqual(ns.KillCounter.getProgress(301, 2, objective).kills, 0, "forgotten once the quest leaves the log")
end)

test("a creature the group fought counts as a kill when it dies; one tapped by others or never fought does not", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    local target = ns.Location.getObjectiveTarget(301, "item", 1)
    local npcId = (ns.Database.getItemField(target.itemId, "npcDrops") or {})[1]
    ns.Drops.getChance = function(_, killedNpcId) return killedNpcId == npcId and 0.25 or nil end
    local ours, theirs, unseen = "Creature-0-1-0-1-" .. npcId .. "-00000001", "Creature-0-1-0-1-" .. npcId .. "-00000002",
        "Creature-0-1-0-1-" .. npcId .. "-00000003"
    -- The units as the game shows them: the target (ours, in combat), a nameplate (in combat, tapped by others)
    local units = {
        target = { guid = ours, isFighting = true, isTappedByOthers = false },
        nameplate1 = { guid = theirs, isFighting = true, isTappedByOthers = true },
    }
    local saved = { UnitExists, UnitIsPlayer, UnitCanAttack, UnitAffectingCombat, UnitIsTapDenied, UnitGUID }
    UnitExists = function(unit) return units[unit] ~= nil end
    UnitIsPlayer = function() return false end
    UnitCanAttack = function(_, unit) return units[unit] ~= nil end
    UnitAffectingCombat = function(unit) return units[unit] and units[unit].isFighting end
    UnitIsTapDenied = function(unit) return units[unit] and units[unit].isTappedByOthers end
    UnitGUID = function(unit) return units[unit] and units[unit].guid end
    ns.KillCounter.handleEvent(nil, "PLAYER_TARGET_CHANGED")
    ns.KillCounter.handleEvent(nil, "NAME_PLATE_UNIT_ADDED", "nameplate1")
    for _, guid in ipairs({ ours, theirs, unseen, ours }) do
        ns.KillCounter.handleEvent(nil, "UNIT_DIED", guid)
    end
    local progress = ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2])
    expectEqual(progress.kills, 1, "only the creature we fought, and only once")
    -- Its corpse still sends its flags while in combat, and the game says once more that it died: still one kill
    ns.KillCounter.handleEvent(nil, "UNIT_FLAGS", "target")
    ns.KillCounter.handleEvent(nil, "UNIT_DIED", ours)
    expectEqual(ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2]).kills, 1, "a death said twice counts once")
    -- A value the game keeps secret is left alone
    issecretvalue = function(value) return value == ours end
    units.target.guid = ours
    ns.KillCounter.handleEvent(nil, "PLAYER_TARGET_CHANGED")
    ns.KillCounter.handleEvent(nil, "UNIT_DIED", ours)
    expectEqual(ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2]).kills, 1, "a secret identifier counts nothing")
    issecretvalue = nil
    UnitExists, UnitIsPlayer, UnitCanAttack, UnitAffectingCombat, UnitIsTapDenied, UnitGUID = unpack(saved)
    ns.KillCounter.forget(301)
end)

test("kills told in an awkward order still count right: a one-blow kill, a creature someone else took, items lost", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    local target = ns.Location.getObjectiveTarget(301, "item", 1)
    local npcId = (ns.Database.getItemField(target.itemId, "npcDrops") or {})[1]
    ns.Drops.getChance = function(_, killedNpcId) return killedNpcId == npcId and 0.25 or nil end
    local oneBlow, takenOver = "Creature-0-1-0-1-" .. npcId .. "-00000004", "Creature-0-1-0-1-" .. npcId .. "-00000005"
    local units = { target = { guid = oneBlow, isFighting = true, isTappedByOthers = false } }
    local saved = { UnitExists, UnitIsPlayer, UnitCanAttack, UnitAffectingCombat, UnitIsTapDenied, UnitGUID }
    UnitExists = function(unit) return units[unit] ~= nil end
    UnitIsPlayer = function() return false end
    UnitCanAttack = function(_, unit) return units[unit] ~= nil end
    UnitAffectingCombat = function(unit) return units[unit] and units[unit].isFighting end
    UnitIsTapDenied = function(unit) return units[unit] and units[unit].isTappedByOthers end
    UnitGUID = function(unit) return units[unit] and units[unit].guid end
    local function kills()
        return ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2]).kills
    end
    -- Killed in one blow: the game tells the death before the creature's first update in combat
    ns.KillCounter.handleEvent(nil, "UNIT_DIED", oneBlow)
    ns.KillCounter.handleEvent(nil, "UNIT_HEALTH", "target")
    expectEqual(kills(), 1, "a death told just before the creature was seen fighting still counts")
    ns.KillCounter.handleEvent(nil, "UNIT_HEALTH", "target")
    ns.KillCounter.handleEvent(nil, "UNIT_DIED", oneBlow)
    expectEqual(kills(), 1, "and only once, whatever comes after")
    -- Fought for a moment, then seen tagged by someone else: their kill
    units.target = { guid = takenOver, isFighting = true, isTappedByOthers = false }
    ns.KillCounter.handleEvent(nil, "PLAYER_TARGET_CHANGED")
    units.target.isTappedByOthers = true
    ns.KillCounter.handleEvent(nil, "UNIT_FLAGS", "target")
    ns.KillCounter.handleEvent(nil, "UNIT_DIED", takenOver)
    expectEqual(kills(), 1, "a creature someone else took is not ours")
    UnitExists, UnitIsPlayer, UnitCanAttack, UnitAffectingCombat, UnitIsTapDenied, UnitGUID = unpack(saved)
    ns.KillCounter.forget(301)
    -- An item lost (destroyed, traded) and a new one dropped: the drop is still seen
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(2, 4) })
    ns.KillCounter.handleKill(npcId)
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(1, 4) })
    ns.KillCounter.handleKill(npcId)
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(2, 4) })
    ns.KillCounter.handleKill(npcId)
    expectEqual(ns.KillCounter.composeTurnIn(301)[1].longestDry, 1, "the drop after the loss ends a run of two kills")
    ns.KillCounter.forget(301)
end)
