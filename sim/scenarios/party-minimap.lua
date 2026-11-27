--@addons QuestieDB, OneMoreQuest
-- (only the addons it plays with: ForeverDungeonJournal's minimap button would stand in the minimap's snapshot)
-- The party and the minimap: two members join, one running OneMoreQuest and one without addons; both take
-- the player's quest and make progress, which the game's party lines and the addon's messages report. Then the
-- player walks and zooms, and the minimap follows.
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1113) -- Hearts of Zeal, which counts hearts
wait(0.5)

joinParty({ name = "Garra", class = "HUNTER", level = 32 }) -- runs OneMoreQuest
joinParty({ name = "Brakka Stone", class = "WARRIOR", level = 34, addon = "none" })
wait(1.5)
expect(G.IsInGroup() and G.GetNumGroupMembers() == 3, "two members and the player make a group of three")
expect(
    G.UnitName("party1") == "Garra" and select(2, G.UnitClass("party2")) == "WARRIOR",
    "the unit functions answer for members"
)

memberAccept("Garra", 1113)
memberAccept("Brakka Stone", 1113)
memberProgress("Garra", 1113, 1, 4)
memberProgress("Brakka Stone", 1113, 1, 2)
wait(2)
expect(G.C_QuestLog.IsUnitOnQuest("party1", 1113), "the game knows Garra has the quest")
local tooltip = G.C_TooltipInfo.GetQuestPartyProgress(1113)
expect(tooltip and tooltip.lines[1].leftText == "Garra", "the game's party lines start with a member's name")

-- The quest's page shows each member's count
key("M")
wait(0.5)
click("Hearts of Zeal")
wait(0.3)
expectText("Hover a face", "the quest page shows the party's faces, with the hint to hover them")
expectText("2 of 2 on it", "the Party part says how many have the quest")
click("Party")
wait(0.3)
expectNoText("Hover a face", "folded, the faces are gone")
saveScene("quest-page-party-folded")
click("Party")
wait(0.3)
expectText("Hover a face", "and back when opened")
saveScene("quest-page-with-party") -- a picture to look at, not compared

-- Inside a dungeon the game withholds its lines; Garra's addon still sends hers
enterInstance(2998, "party", "Alcaz Prison")
memberProgress("Garra", 1113, 1, 1)
wait(2)
expect(G.C_TooltipInfo.GetQuestPartyProgress(1113) == nil, "no party lines from the game inside")
-- OneMoreQuest heard Garra's addon (exact counts, there inside too), and nothing from Brakka, who has none
local omq = require("addons").byName["onemorequest"].private
local garra = omq.Comms.getRemoteQuest("Garra", 1113)
expect(garra and garra.objectives[1].fulfilled == 5, "OneMoreQuest has Garra's count of 5 from her addon")
expect(omq.Comms.getRemoteQuest("Brakka Stone", 1113) == nil, "nothing came from Brakka, who runs no addon")
leaveInstance()

-- Walking and the minimap
key("ESCAPE")
local _, northBefore = require("game").getPlayerWorldPosition()
face(0)
walk(40)
local _, northAfter = require("game").getPlayerWorldPosition()
expect(
    northAfter and math.abs(northAfter - northBefore - 40) < 0.5,
    "walking 40 yards facing north goes 40 yards north"
)
zoomMinimap(3)
expect(G.C_Minimap.GetViewRadius() < 200, "zooming in narrows the minimap's view")
memberMoveTo("Garra", 1413, 0.471, 0.598)
wait(0.2)
snapshot("minimap-zoomed", "Minimap")
leaveParty("Brakka Stone")
wait(0.5)
expect(G.GetNumGroupMembers() == 2, "Brakka left")

-- A member running Questie: its messages, made by Questie's own code, reach OneMoreQuest through its bridge
joinParty({ name = "Questa", class = "PRIEST", level = 33, addon = "Questie" })
-- (a moment for the hellos: OneMoreQuest asks a Questie it hears for its log, and the answer, made as it is asked
-- for, would otherwise cross with the progress below and land after it)
wait(1.5)
memberAccept("Questa", 1113)
memberProgress("Questa", 1113, 1, 7)
wait(3)
local questa = omq.Comms.getRemoteQuest("Questa", 1113)
expect(questa and questa.source == "Questie", "OneMoreQuest heard Questa through Questie's messages")
expect(questa and questa.objectives[1] and questa.objectives[1].fulfilled == 7, "with her count of 7 hearts")
memberAbandon("Questa", 1113)
wait(1)
expect(omq.Comms.getRemoteQuest("Questa", 1113) == nil, "and that she dropped it")
