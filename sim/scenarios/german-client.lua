--@locale deDE
-- OneMoreQuest on a German client: the game's strings, map names and objective wording are German. Everything
-- opens without errors, and a kill objective worded in German ("getötet") is still a kill.
setProfile({ level = 30, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844) -- Plainstrider Menace: plainstriders to kill
wait(1)
expect(G.GetLocale() == "deDE", "the client is German")
key("M")
wait(0.5)
expectText("Karte & Questlog", "the map's title is the game's German one")
click("Available")
wait(0.3)
click("My quests")
wait(0.3)
local trailhead = require("addons").byName["onemorequest"].private
local objective = trailhead.QuestState.getQuest(844).objectives[1]
print("German objective:", objective.text, "label:", objective.label)
expect(objective.label and not objective.label:find("%d"), "the objective's label loses its count in German too")

-- A kill objective in German ("… getötet") is still a kill: its mark has the swords
accept(871) -- Disrupt the Attacks
wait(0.5)
trailhead.Focus.set(871)
local glyph
for _, mark in ipairs(trailhead.MapMarks.compose(1413)) do
    if mark.questId == 871 and mark.labels and mark.labels[1] then
        glyph = mark.labels[1].glyph
        break
    end
end
expect(glyph == "kill", "a German kill objective gets the kill symbol (got " .. tostring(glyph) .. ")")
