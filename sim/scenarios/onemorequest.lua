-- OneMoreQuest, a short session: the map and its quest log, a quest page, the Available tab, a kill that loots
-- a quest item, a hand-in at the quest giver, the chronicle-adjacent report, and a dungeon the database lacks.
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.47, 0.6) -- The Barrens
accept(1109) -- Going, Going, Guano!
accept(1113) -- Hearts of Zeal
wait(1)

key("M")
wait(0.5)
expect(G.WorldMapFrame:IsShown(), "the map opens with M")
expectText("My quests")
click("Going, Going, Guano!")
expectText("To do", "the quest's page opens")
saveScene("quest-page") -- the map and the quest's page, as drawn: a picture to look at, not compared (it changes with every tweak)

click("Available")
wait(0.5)
expectText("Available", "the Available tab draws")
saveScene("available-tab")
click("My quests")

kill(4538) -- a Kraul Bat, which drops the guano
expect(G.C_QuestLog.IsComplete(1109), "the kill looted the guano and finished the quest")
talk(2055) -- Master Apothecary Faranell
turnIn(1109)
closeDialog()
expect(G.C_QuestLog.IsQuestFlaggedCompleted(1109), "handed in")

slash("/omq missing")
wait(0.5)

enterInstance(2998, "party", "Alcaz Prison") -- an instance QuestieDB does not know
kill(3974)
leaveInstance()

-- The report's copy box has the keyboard (Escape lets go of it), and zoning and the quest dialog closed the map, as
-- the game's own interface does: open it again
if require("widgets").focus then
    key("ESCAPE")
    wait(0.2)
end
if not (G.WorldMapFrame:IsShown() and G.OneMoreQuestLog and G.OneMoreQuestLog:IsShown()) then
    if G.WorldMapFrame:IsShown() then
        key("M")
        wait(0.5)
    end
    key("M")
    wait(0.5)
end
wheel("My quests", -1)
key("ESCAPE")
draw()
