-- Tests: the group: members' progress, sharing, OneMoreQuest's channel and the Questie bridge.

test("party members show as two letters, and whether they have the quest", function()
    local ns, state = createAddon()
    expectEqual(ns.Party.getInitials("Mira Dawnfield"), "MD", "two names")
    expectEqual(ns.Party.getInitials("thrall"), "TH", "one name")
    expectEqual(#ns.Party.getMembers(201), 0, "solo")
    state.partyMembers.party1 = { name = "Mira Dawnfield", questIds = { [201] = true } }
    state.partyMembers.party2 = { name = "Olen Rusk", questIds = {} }
    local members = ns.Party.getMembers(201)
    expectEqual(members[1].isOnQuest, true, "first member on the quest")
    expectEqual(members[2].isOnQuest, false, "second member without it")
end)

test("each party member's counts are read from the game's party progress, by objective", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(1, 4) })
    state.partyMembers.party1 = { name = "Mira Dawnfield", questIds = { [301] = true } }
    state.partyMembers.party2 = { name = "Tor", questIds = {} }
    C_TooltipInfo = { GetQuestPartyProgress = function()
        return { lines = {
            { leftText = "Mira Dawnfield" },
            { leftText = " - 4/12 Roadside Bandit slain" },
            { leftText = " - Wolf Fang: 4/4" },
        } }
    end }
    local quest = ns.QuestState.getQuest(301)
    local members = ns.Party.getProgress(301, quest.objectives)
    expectEqual(#members, 2, "both members")
    local mira, tor = members[1], members[2]
    expectEqual(mira.counts[1] and mira.counts[1].fulfilled, 4, "Mira's bandits")
    expectEqual(mira.counts[2] and mira.counts[2].isDone, true, "Mira has all the fangs")
    expectEqual(tor.isOnQuest, false, "Tor does not have it")
    expectEqual(mira.classFile, "WARRIOR", "the member's class file, for the class colour, not only the class's name")
    expectEqual(ns.Party.formatCount(false):find("?", 1, true) ~= nil, true, "an unknown count is a question mark")
    expectEqual(ns.Party.formatCount({ fulfilled = 4, required = 7 }):find("4/7", 1, true) ~= nil, true, "a count as 4/7")
    expectEqual(ns.Party.formatCount({ fulfilled = 7, required = 7, isDone = true }):find("ReadyCheck-Ready", 1, true) ~= nil, true, "a tick once done")
    -- The tracker draws the table under the focused quest, and the tooltip lists the party
    ns.Tracker.create()
    ns.Focus.set(301)
    ns.Tracker.refresh()
    C_TooltipInfo = nil
end)

test("a quest's row offers to share it only when a party member could take it", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12) })
    local savedPushable = C_QuestLog.IsPushableQuest
    C_QuestLog.IsPushableQuest = function() return true end
    expectEqual(ns.Log.canShareWithParty(301), false, "solo: nobody to share with")
    installGroup(state)
    state.partyMembers.party1.questIds = { [301] = true }
    state.partyMembers.party2.questIds = { [301] = true }
    expectEqual(ns.Log.canShareWithParty(301), false, "everyone has it")
    state.partyMembers.party2.questIds = {}
    state.partyMembers.party2.level = 30
    expectEqual(ns.Log.canShareWithParty(301), true, "a member without it who could take it")
    state.partyMembers.party2.level = 1
    expectEqual(ns.Log.canShareWithParty(301), false, "a member too low for it: nothing to share")
    state.partyMembers.party2.level = 30
    C_QuestLog.IsPushableQuest = function() return false end
    expectEqual(ns.Log.canShareWithParty(301), false, "a quest the game will not share")
    C_QuestLog.IsPushableQuest = savedPushable
    removeGroup()
end)

test("a zone's quests a party member could take are shared all at once, a second apart", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(0, 12) })
    setQuest(state, 302, false, { killObjective(0, 5) })
    setQuest(state, 303, false, { killObjective(0, 5) })
    local savedPushable, savedPush, savedAfter, savedSelect = C_QuestLog.IsPushableQuest, QuestLogPushQuest, C_Timer.After, C_QuestLog.SetSelectedQuest
    local selected
    C_QuestLog.SetSelectedQuest = function(questId) selected = questId end
    C_QuestLog.IsPushableQuest = function() return true end
    local entries = { { questId = 301 }, { questId = 302 }, { questId = 303 } }
    expectEqual(#ns.Log.getShareableQuestIds(entries), 0, "solo: nothing to share")
    installGroup(state)
    state.partyMembers.party1.questIds = { [301] = true, [302] = true }
    state.partyMembers.party2.questIds = { [301] = true }
    state.partyMembers.party2.level = 30
    local shareable = ns.Log.getShareableQuestIds(entries)
    expectEqual(table.concat(shareable, ","), "302,303", "only what someone has not got")
    local shared, delays = {}, {}
    QuestLogPushQuest = function() shared[#shared + 1] = selected end
    C_Timer.After = function(seconds, callback) delays[#delays + 1] = seconds; callback() end
    ns.Log.shareQuests(shareable)
    expectEqual(table.concat(shared, ","), "302,303", "each offered, in order")
    expectEqual(delays[1], 1, "the second a second after the first")
    C_QuestLog.IsPushableQuest, QuestLogPushQuest, C_Timer.After, C_QuestLog.SetSelectedQuest = savedPushable, savedPush, savedAfter, savedSelect
    removeGroup()
end)

test("quest counts go to the group in a short text, and come back the same", function()
    local ns = createAddon()
    local quest = { objectives = { { fulfilled = 7, required = 12 }, { fulfilled = 4, required = 4 } }, isComplete = false }
    local entry = ns.Comms.composeEntry(301, quest)
    expectEqual(entry, "301:7/12,4/4:0", "the entry")
    local questId, parsed = ns.Comms.parseEntry(entry)
    expectEqual(questId, 301, "quest")
    expectEqual(parsed.objectives[1].fulfilled, 7, "first count")
    expectEqual(parsed.objectives[2].isFinished, true, "a finished objective")
    local entries = {}
    for index = 1, 40 do
        entries[index] = ns.Comms.composeEntry(10000 + index, quest)
    end
    local messages = ns.Comms.composeLogMessages(entries)
    local count = 0
    for _, message in ipairs(messages) do
        expectEqual(#message <= 250, true, "each message fits")
        count = count + #ns.Comms.parseMessage(message).entries
    end
    expectEqual(count, 40, "every quest of the log, over " .. #messages .. " messages")
    expectEqual(ns.Comms.parseMessage("2|U|301:1/2:0"), nil, "another version is left alone")
    expectEqual(ns.Comms.parseMessage("1|R|301").questId, 301, "a removal")
    expectEqual(ns.Comms.parseMessage(messages[2]).part, 2, "a log's parts are numbered")
end)

test("a member not on the quest: done or able by their addon's answer, unable by their level, else unknown", function()
    local ns, state = createAddon()
    local sent = installGroup(state)
    state.partyMembers.party1.level = 4
    state.partyMembers.party2.level = 20
    local QUEST = 9001
    local savedGet = ns.Database.getQuestField
    ns.Database.getQuestField = function(questId, field)
        if questId == QUEST then
            return ({ requiredLevel = 10, questLevel = 12, name = "Test Quest" })[field]
        end
        return savedGet(questId, field)
    end
    local function getMember(name)
        for _, member in ipairs(ns.Party.getProgress(QUEST, {})) do
            if member.name == name then return member end
        end
    end
    local mira = getMember("Mira Dawnfield")
    expectEqual(mira.status.state, "cannot", "level 4 cannot take a level 10 quest")
    expectEqual(mira.status.shortReason, "lvl 10", "and the column says the level")
    expectEqual(mira.status.reason:find("needs 10", 1, true) ~= nil, true, "the hover says why")
    expectEqual(getMember("Olen Rusk").status.state, "unknown", "nothing rules level 20 out: done or able, unknown")
    -- The group was asked, once
    local asked = 0
    for _, message in ipairs(sent) do
        if message.text == "1|Q|" .. QUEST then asked = asked + 1 end
    end
    expectEqual(asked, 1, "the group asked about the quest once")
    -- Olen's addon answers; and the player answers a member's question about a quest they did
    receive(ns, "OneMoreQuest", "1|S|" .. QUEST .. "|d||", "Olen Rusk")
    expectEqual(getMember("Olen Rusk").status.state, "done", "done it, by their addon's word")
    receive(ns, "OneMoreQuest", "1|S|" .. QUEST .. "|n|earlier|Take Test Prelude first", "Mira Dawnfield")
    local status = getMember("Mira Dawnfield").status
    expectEqual(status.shortReason .. " / " .. status.reason, "earlier / Take Test Prelude first", "their own reason wins")
    state.turnedInQuestIds[QUEST] = true
    receive(ns, "OneMoreQuest", "1|Q|" .. QUEST, "Mira Dawnfield")
    local answer = sent[#sent]
    expectEqual(answer.channel .. " " .. answer.target, "WHISPER Mira Dawnfield", "the answer goes to who asked")
    expectEqual(ns.Comms.parseMessage(answer.text).state, "done", "done it")
    ns.Database.getQuestField = savedGet
    removeGroup()
end)

test("a member on a quest with nothing to count is ready or not yet", function()
    local ns = createAddon()
    local function member(counts, sharedQuest) return { counts = counts, sharedQuest = sharedQuest } end
    expectEqual(ns.Party.getReadiness(member({}), false), "ready", "a talk-to quest: nothing before the turn-in")
    expectEqual(ns.Party.getReadiness(member({}), true), "?", "an escort, with nothing from their addon")
    expectEqual(ns.Party.getReadiness(member({}, { objectives = {}, isComplete = false }), true), "not yet", "their addon says not yet")
    expectEqual(ns.Party.getReadiness(member({ { fulfilled = 7, required = 7, isDone = true } }), false), "ready", "every count done")
    expectEqual(ns.Party.getReadiness(member({ { fulfilled = 2, required = 7, isDone = false } }), false), "not yet", "a count to go")
    expectEqual(ns.Party.getReadiness(member({ false }), false), "?", "a count unknown")
end)

test("a member's face ring fills with their share of the quest; hovering it gives every count", function()
    local ns = createAddon()
    local function count(fulfilled, required) return { fulfilled = fulfilled, required = required, isDone = fulfilled >= required } end
    local share = ns.Party.getShare({ counts = { count(4, 7), count(10, 10), count(1, 3) } }, false)
    expectEqual(math.floor(share * 100 + 0.5), 75, "15 of 20 things done, each objective up to what it asks")
    expectEqual(ns.Party.getShare({ counts = { count(9, 7) } }, false), 1, "more than asked is still all")
    expectEqual(ns.Party.getShare({ counts = { count(2, 7), false } }, false), nil, "a count unknown: unknown")
    expectEqual(ns.Party.getShare({ counts = {} }, false), 1, "a talk-to quest is ready")
    expectEqual(ns.Party.getShare({ counts = {} }, true), nil, "an escort, nothing from their addon: unknown")
    expectEqual(ns.Party.getShare({ counts = { count(1, 7) }, sharedQuest = { isComplete = true } }, false), 1, "their addon says complete")
    local lines = {}
    local tooltip = {
        AddLine = function(_, text) lines[#lines + 1] = text end,
        AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. " = " .. right end,
    }
    ns.Party.addMemberToTooltip(tooltip, {
        unit = "party1", name = "Garra Windmane", isOnQuest = true, share = 0.5, status = { state = "has" },
        objectives = { { label = "Plainstrider Beak" }, { label = "Zhevra Hoof" } }, counts = { count(4, 7), count(10, 10) },
    })
    expectEqual(lines[1], "Garra Windmane", "the full name")
    expectEqual(lines[2], "In progress, 50%", "how far")
    expectEqual(lines[3]:find("Plainstrider Beak = ", 1, true) ~= nil and lines[3]:find("4/7", 1, true) ~= nil, true, "each objective with its count")
    expectEqual(lines[4]:find("ReadyCheck-Ready", 1, true) ~= nil, true, "a tick for one done")
    lines = {}
    ns.Party.addMemberToTooltip(tooltip, { unit = "party2", name = "Olen Rusk", isOnQuest = false, status = { state = "cannot", reason = "Level 9, the quest needs 10" } })
    expectEqual(lines[2], "Level 9, the quest needs 10", "off the quest, why")
end)

test("in a group a quest item's drops go round between those who need it, so each kill is a share of a chance", function()
    local ns, state = createAddon()
    installGroup(state)
    setQuest(state, 301, false, { killObjective(0, 12), itemObjective(0, 4) })
    local target = ns.Location.getObjectiveTarget(301, "item", 1)
    local npcId = (ns.Database.getItemField(target.itemId, "npcDrops") or {})[1]
    ns.Drops.getChance = function(_, killedNpcId) return killedNpcId == npcId and 0.5 or nil end
    ns.Drops.getHuntedSource = function() return { npcId = npcId, chance = 0.5, name = "Test Creature" } end
    local isUnique = false
    ns.Drops.isForEveryone = function() return isUnique end -- a common creature, with many spawns
    local function getProgress()
        return ns.KillCounter.getProgress(301, 2, ns.QuestState.getQuest(301).objectives[2])
    end
    expectEqual(getProgress().remaining, 8, "alone: 4 drops at 50% is 8 kills")
    -- One of a kind (a named creature, a boss): its drops go to everyone on the quest, so nothing is shared
    state.partyMembers.party1.questIds[301] = true
    isUnique = true
    expectEqual(ns.KillCounter.getSharerCount(301, 2, npcId), 1, "a unique creature drops for everyone")
    expectEqual(getProgress().remaining, 8, "so a group needs no more kills of it")
    isUnique = false
    state.partyMembers.party1.questIds[301] = nil
    -- Mira takes the quest too: the drops go round between the two of them
    state.partyMembers.party1.questIds[301] = true
    expectEqual(ns.KillCounter.getSharerCount(301, 2), 2, "two need the item")
    expectEqual(getProgress().remaining, 16, "shared by two: 16 kills for the player's 4")
    for _ = 1, 4 do
        ns.KillCounter.handleKill(npcId)
    end
    state.questLog[301] = { isComplete = false, objectives = { killObjective(0, 12), itemObjective(1, 4) } }
    local progress = getProgress()
    expectEqual(progress.expected, 4, "1 drop at a quarter chance a kill is 4 kills on average")
    expectEqual(progress.isUnlucky, false, "4 kills for 1 drop is just average in a pair")
    expectEqual(progress.sharerCount, 2, "the loot is shared by 2")
    -- Mira has all hers now (her addon says so): the rest of the drops are the player's alone
    receive(ns, "OneMoreQuest", "1|U|301:12/12,4/4:1", "Mira Dawnfield")
    expectEqual(ns.KillCounter.getSharerCount(301, 2), 1, "a member with all of it takes no turn")
    expectEqual(getProgress().remaining, 6, "3 drops to go at 50%, alone again")
    removeGroup()
end)

test("a member's counts from their addon win over the game's, and show they have the quest", function()
    local ns, state = createAddon()
    installGroup(state)
    setQuest(state, 301, false, { killObjective(5, 12), itemObjective(1, 4) })
    receive(ns, "OneMoreQuest", "1|U|301:9/12,3/4:0", "Olen Rusk")
    local objectives = ns.QuestState.getQuest(301).objectives
    local olen
    for _, member in ipairs(ns.Party.getProgress(301, objectives)) do
        if member.name == "Olen Rusk" then
            olen = member
        end
    end
    expectEqual(olen.isOnQuest, true, "on the quest, by their addon's word")
    expectEqual(olen.counts[1].fulfilled, 9, "their kills")
    expectEqual(olen.counts[2].required, 4, "their items")
    -- A whole log in two parts: the second does not undo the first
    receive(ns, "OneMoreQuest", "1|L|1/2|301:9/12,3/4:0", "Olen Rusk")
    receive(ns, "OneMoreQuest", "1|L|2/2|302:1/1:1", "Olen Rusk")
    expectEqual(ns.Comms.getRemoteQuest("Olen Rusk", 301) ~= nil and ns.Comms.getRemoteQuest("Olen Rusk", 302) ~= nil, true, "both parts kept")
    receive(ns, "OneMoreQuest", "1|R|301", "Olen Rusk")
    expectEqual(ns.Comms.getRemoteQuest("Olen Rusk", 301), nil, "gone when they drop it")
    -- Nonsense never breaks anything
    receive(ns, "OneMoreQuest", "1|U|abc:||", "Olen Rusk")
    receive(ns, "OneMoreQuest", string.rep("\255", 300), "Olen Rusk")
    receive(ns, "OneMoreQuest", nil, "Olen Rusk")
    state.partyMembers.party2 = nil
    ns.Comms.handleGroupChange()
    receive(ns, "OneMoreQuest", "1|U|301:9/12,3/4:0", "Olen Rusk")
    ns.Comms.forgetPlayer("Olen Rusk")
    expectEqual(ns.Comms.getRemoteQuest("Olen Rusk", 301), nil, "forgotten once they leave")
    removeGroup()
end)

test("only what changed is sent, on this addon's channel and Questie's", function()
    local ns, state = createAddon()
    local sent = installGroup(state)
    setQuest(state, 301, false, { killObjective(5, 12), itemObjective(1, 4) })
    ns.Comms.sendChanges()
    local ours, questies = 0, 0
    for _, message in ipairs(sent) do
        if message.prefix == "OneMoreQuest" then
            ours = ours + 1
            expectEqual(message.text, "1|U|301:5/12,1/4:0", "the quest's counts")
        elseif message.prefix == "questie" then
            questies = questies + 1
            local packet = ns.QuestieBridge.deserialize(ns.QuestieBridge.joinMessage(message.text, "me"))
            expectEqual(packet.msgId, 1, "Questie's quest update")
            expectEqual(packet.msgVer, 5, "in the message version Questie reads")
            expectEqual(packet.quest.objectives[1].ful, 5, "with the counts")
            expectEqual(packet.quest.objectives[1].id, 5001, "and what to kill")
        end
    end
    expectEqual(ours, 1, "one message on our channel")
    expectEqual(questies, 1, "one on Questie's")
    local before = #sent
    ns.Comms.sendChanges()
    expectEqual(#sent, before, "nothing again while nothing moved")
    ns.settings.shouldShareProgress = false
    state.questLog[301].objectives[1] = killObjective(6, 12)
    ns.Comms.sendChanges()
    expectEqual(#sent, before, "nothing at all with sharing switched off")
    removeGroup()
end)

test("Questie's serializer reads back what it writes, long and repeated words included", function()
    local ns = createAddon()
    local value = {
        ver = "9.4.1", msgVer = 5, msgId = 10, big = 70000, negative = -300, edge = { 0, 237, 238, 255, 221, 222 },
        rawQuestList = {
            [301] = { id = 301, objectives = { { typ = "m", ful = 3, req = 12, fin = false }, { typ = "item", ful = 4, req = 4, fin = true } } },
            [302] = { id = 302, objectives = { { typ = "item", ful = 0, req = 1 } } },
        },
    }
    local data = ns.QuestieBridge.serialize(value)
    expectEqual(data:find("\0", 1, true), nil, "no zero byte in the message")
    local back = ns.QuestieBridge.deserialize(data)
    expectEqual(back.ver, "9.4.1", "a string")
    expectEqual(back.big, 70000, "a large number")
    expectEqual(back.negative, -300, "a negative one")
    expectEqual(table.concat(back.edge, ","), "0,237,238,255,221,222", "the escaped bytes")
    expectEqual(back.rawQuestList[301].objectives[2].typ, "item", "a word written as its hash the second time")
    expectEqual(back.rawQuestList[302].objectives[1].typ, "item", "and the third")
    expectEqual(back.rawQuestList[301].objectives[2].fin, true, "a flag")
    -- Questie's own hash, as Questie computes it with the game's bit library
    local questieHash = 5381
    for index = 1, #"objectives" do
        questieHash = bit.band(31 * questieHash + ("objectives"):byte(index), 4294967295)
    end
    expectEqual(ns.QuestieBridge.getHash("objectives"), questieHash % 4294967296, "the same hash as Questie's")
end)

test("a Questie player's progress is read, in one message or several, in either format", function()
    local ns, state = createAddon()
    local sent = installGroup(state)
    -- One quest update, as Questie sends it
    local update = ns.QuestieBridge.serialize({ ver = "9.4.1", msgVer = 5, msgId = 1,
        quest = { id = 301, objectives = { { id = 5001, typ = "m", ful = 3, req = 12 }, { id = 7001, typ = "i", ful = 4, req = 4, fin = true } } } })
    receive(ns, "questie", update, "Mira Dawnfield")
    local quest = ns.Comms.getRemoteQuest("Mira Dawnfield", 301)
    expectEqual(quest and quest.objectives[1].fulfilled, 3, "kills from Questie")
    expectEqual(quest.source, "Questie", "known to come from Questie")
    -- A whole log long enough to be split in parts
    local list = {}
    for questId = 400, 430 do
        list[questId] = { id = questId, objectives = { { typ = "m", ful = 1, req = 10 } } }
    end
    local parts = ns.QuestieBridge.splitMessage(ns.QuestieBridge.serialize({ ver = "9.4.1", msgVer = 5, msgId = 10, rawQuestList = list }))
    expectEqual(#parts > 1, true, "a long message goes in parts")
    for _, part in ipairs(parts) do
        receive(ns, "questie", part, "Olen Rusk")
    end
    expectEqual(ns.Comms.getRemoteQuest("Olen Rusk", 430) ~= nil, true, "put together again")
    -- The flat format: count, then quest, objective count, and id, type, have, need for each objective
    receive(ns, "questie", ns.QuestieBridge.serialize({ ver = "9.4.1", msgVer = 5, msgId = 12, [1] = { 1, 302, 1, 7001, 105, 2, 6 } }), "Mira Dawnfield")
    expectEqual(ns.Comms.getRemoteQuest("Mira Dawnfield", 302).objectives[1].fulfilled, 2, "from the flat format")
    -- A request for the log is answered with a whisper, in Questie's first format
    setQuest(state, 301, false, { killObjective(5, 12), itemObjective(1, 4) })
    receive(ns, "questie", ns.QuestieBridge.serialize({ ver = "9.4.1", msgVer = 5, msgId = 11 }), "Mira Dawnfield")
    local answer
    for _, message in ipairs(sent) do
        if message.prefix == "questie" and message.channel == "WHISPER" then
            answer = ns.QuestieBridge.deserialize(ns.QuestieBridge.joinMessage(message.text, "me"))
        end
    end
    expectEqual(answer and answer.msgId, 10, "the log, as Questie asks for it")
    expectEqual(answer.rawQuestList[301].objectives[1].ful, 5, "with the counts")
    -- A stranger's message is ignored
    receive(ns, "questie", update, "Somebody Else")
    expectEqual(ns.Comms.getRemoteQuest("Somebody Else", 301), nil, "only the group's")
    removeGroup()
end)

test("broken Questie messages switch the bridge off, and this addon's own channel carries on", function()
    local ns, state = createAddon()
    installGroup(state)
    receive(ns, "questie", "\033\010\255\255", "Mira Dawnfield")
    expectEqual(ns.QuestieBridge.isWorking(), true, "one bad message is let go")
    receive(ns, "questie", "\033\010", "Mira Dawnfield")
    receive(ns, "questie", "\033\010\005", "Mira Dawnfield")
    expectEqual(ns.QuestieBridge.isWorking(), false, "off once they keep failing")
    receive(ns, "OneMoreQuest", "1|U|301:9/12:0", "Mira Dawnfield")
    expectEqual(ns.Comms.getRemoteQuest("Mira Dawnfield", 301).objectives[1].fulfilled, 9, "our own messages still read")
    -- Questie itself running here talks for itself
    ns.QuestieBridge.reset()
    C_AddOns = { IsAddOnLoaded = function(name) return name == "Questie" end }
    expectEqual(ns.QuestieBridge.isWorking(), false, "the bridge stays out of Questie's way")
    removeGroup()
end)

test("a party member's reason is read in this player's own language, quest titles included", function()
    local ns = createAddon()
    ns.Locale.setLanguage("cs")
    local phrase = { key = "After %s", args = { { questId = 501 } } }
    local czech = ns.Comms.readPhrase(ns.Comms.writePhrase(phrase))
    ns.Locale.setLanguage("en")
    local message = ns.Comms.parseMessage(ns.Comms.composePhraseMessage(502, "cannot", phrase, { key = "lvl %d", args = { 12 } }))
    expectEqual(message ~= nil and message.kind, "T", "the phrase answer is read")
    expectEqual(message.reason, "After Fresh Start", "said in English here, whatever language the sender reads")
    expectEqual(message.shortReason, "lvl 12", "the short one too")
    expectEqual(czech ~= message.reason, true, "and in Czech for a Czech player")
    expectEqual(ns.Comms.parseMessage("1|S|502|n|lvl 12|After Fresh Start").reason, "After Fresh Start", "older versions' text answer still read")
end)
