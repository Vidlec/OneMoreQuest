-- A quest that hands out a usable item (Egg Hunt's Digging Claw): the tracker offers its button, hovering shows
-- the item, clicking uses it (the game's spell-cast event) and starts its cooldown.
setProfile({ level = 25, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(868)
wait(1.5)
local game = require("game")
local index = G.C_QuestLog.GetLogIndexForQuestID(868)
local link = G.GetQuestLogSpecialItemInfo(index)
expect(link and link:find("Digging Claw", 1, true), "the game offers the Digging Claw as the quest's item")
local button = G.TrailheadItemButton1
expect(button and button:IsVisible(), "OneMoreQuest's item button is shown beside the tracker")
if button then
    hover("TrailheadItemButton1")
    wait(0.2)
    expectText("Digging Claw", "hovering it shows the item")
    local casts = 0
    local listener = G.CreateFrame("Frame")
    listener:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    listener:SetScript("OnEvent", function() casts = casts + 1 end)
    click("TrailheadItemButton1")
    wait(0.2)
    expect(game.lastUsedItemId == 5059 and casts == 1, "clicking it uses the item")
end
