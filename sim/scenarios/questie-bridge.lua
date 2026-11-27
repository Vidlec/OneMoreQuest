--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=6
-- A party member who runs Questie never sees an error from OneMoreQuest's messages. The simulated member reads as
-- Questie 12.15 does (sim/plugins/questie-party.lua): a packet it has no reader for prints "Error reading QuestieComm
-- message" in its chat, as a player reported. Here the player's log, a quest's progress and a quest dropped all
-- reach it in packets it reads, and what it read is what the player has.
setProfile({ level = 6, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68)
local addon = require("addons").byName["onemorequest"].private
local CUTTING_TEETH, VILE_FAMILIARS = 788, 792
accept(CUTTING_TEETH)
accept(VILE_FAMILIARS)
wait(2)

-- Alone with a member who runs no addon: nothing is said on Questie's channel at all
local sentOnQuestie = 0
local sendAddonMessage = G.C_ChatInfo.SendAddonMessage
G.C_ChatInfo.SendAddonMessage = function(prefix, ...)
    sentOnQuestie = sentOnQuestie + (prefix == "questie" and 1 or 0)
    return sendAddonMessage(prefix, ...)
end
joinParty({ name = "Brakka", class = "WARRIOR", level = 7, addon = "none" })
wait(3)
progress(CUTTING_TEETH, 1, 2)
wait(3)
expect(sentOnQuestie == 0, "nobody heard on Questie's channel: nothing sent on it (" .. sentOnQuestie .. ")")

-- A member with Questie joins: it asks for logs and sends its own, and gets the player's log in its flat list
joinParty({ name = "Questa", class = "PRIEST", level = 6, addon = "Questie" })
memberAccept("Questa", CUTTING_TEETH)
wait(6)
local function errors()
    return table.concat(G.QuestieSimErrors or {}, "; ")
end
expect(G.QuestieSimErrors == nil, "no error in the Questie player's chat: " .. errors())
expect(sentOnQuestie > 0, "the bridge speaks once a Questie is heard")
local seen = G.QuestieSimQuests and G.QuestieSimQuests.Questa or {}
expect(seen[CUTTING_TEETH] ~= nil and seen[VILE_FAMILIARS] ~= nil, "Questie read both of the player's quests")
expect(seen[CUTTING_TEETH][1].fulfilled == 2, "with the count: " .. tostring(seen[CUTTING_TEETH][1].fulfilled))
expect(addon.Comms.getRemoteQuest("Questa", CUTTING_TEETH) ~= nil, "and the player has the member's quest")

-- Progress and a quest dropped reach it too, and still no error
progress(CUTTING_TEETH, 1, 3)
wait(4)
seen = G.QuestieSimQuests.Questa
expect(
    seen[CUTTING_TEETH][1].fulfilled == 5,
    "progress read by Questie: " .. tostring(seen[CUTTING_TEETH][1].fulfilled)
)
abandon(VILE_FAMILIARS)
wait(4)
expect(G.QuestieSimQuests.Questa[VILE_FAMILIARS] == nil, "a dropped quest is taken off Questie's list")
expect(G.QuestieSimErrors == nil, "and still no error: " .. errors())
