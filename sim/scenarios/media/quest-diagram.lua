--@addons QuestieDB, OneMoreQuest
-- The product page's picture of the quest diagram: a quest's chain as a tree, what comes before above and what
-- follows below, beside the quest's page. Cutting Teeth (Valley of Trials) opens three quests for an orc warrior.
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 4, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68) -- Durotar, the Valley of Trials
accept(788) -- Cutting Teeth
wait(2)

key("M")
wait(1)
click("Cutting Teeth")
wait(0.5)
addon.Log.getPageCanvas():setScroll(2000) -- (to the page's end, where the button is)
wait(0.3)
click("Quest diagram")
wait(0.5)
local window = addon.LogDiagram.getWindow()
expect(window ~= nil and window:IsVisible(), "the quest diagram opens")
saveScene("quest-diagram", { only = { window } })
