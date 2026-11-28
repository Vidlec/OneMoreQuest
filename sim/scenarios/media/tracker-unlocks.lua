--@addons QuestieDB, OneMoreQuest
-- The product page's picture of what a quest unlocks (0.16.0): the tracker and a quest's tooltip with what it
-- unlocks. Cutting Teeth (Valley of Trials) opens three quests for an orc warrior.
local G = require("sim").G

screen(1920, 1080)
setProfile({ level = 4, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68) -- Durotar, the Valley of Trials
accept(788) -- Cutting Teeth
wait(2)

local function findTitleRow(questId, frame)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.entry and child.entry.questId == questId and child:IsVisible() and child.isTitle then
            return child
        end
        local found = findTitleRow(questId, child)
        if found then
            return found
        end
    end
end
local row = findTitleRow(788, G.UIParent)
expect(row ~= nil, "the quest has a row in the tracker")
hover(row)
wait(0.3)
expectText("Unlocks 3 quests", "the row's tooltip names what the quest opens")
saveScene("tracker-unlocks", { only = { "OneMoreQuestTracker", "GameTooltip", "MinimapCluster" } })
