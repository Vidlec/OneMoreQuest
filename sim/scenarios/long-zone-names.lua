--@addons QuestieDB, OneMoreQuest
--@login race=Scourge,class=MAGE,level=30
-- (only the addons it plays with: ForeverDungeonJournal opens its first-run mode chooser over the screen three
-- seconds after login, in the way of what is clicked and hovered)
-- Zone headings with the longest names there are, at their busiest: the zone the player is in (its gold edge at
-- the left), a dungeon's gate after its name, "2 ready · 4 quests" at the right. A name that does not fit ends in
-- "..." and shows whole in a tooltip, with "You are here" for the player's zone; nothing else moves.
setProfile({ level = 30 })
moveTo(1413, 0.52, 0.30) -- The Barrens
local addon = require("addons").byName["onemorequest"].private
for _, questId in ipairs({ 869, 865, 872, 891, 914, 962, 1486, 1102, 862 }) do accept(questId) end
complete(869); complete(865)
wait(1.5)
local LONGEST_ZONE, LONGEST_DUNGEON = "Venture Co. Operations Center", "Ahn'kahet: The Old Kingdom"
local compose = addon.Model.compose
addon.Model.compose = function(...)
    local model = compose(...)
    for _, group in ipairs(model.groups or {}) do
        if group.isCurrent and not group.isCategory then
            group.zoneName = LONGEST_ZONE
        elseif addon.Database.getDungeon(group.zoneId) then
            group.zoneName = LONGEST_DUNGEON
        end
    end
    return model
end
key("M")
wait(1)
expectText("Venture Co. Operations", "the longest zone name, as much as fits")
expectText("2 ready", "the counts still there")
saveScene("long-names")
-- The list's own heading (the tracker shows the full name too, behind the window)
local heading
for _, region in ipairs({ addon.Log.getListCanvas().content:GetRegions() }) do
    if region:IsShown() and region.GetText and region:GetText() == LONGEST_ZONE then heading = region end
end
expect(heading ~= nil and heading:IsTruncated(), "the longest name is cut short in the list")
if heading then hover(heading) end
wait(0.3)
expect(G.GameTooltip:IsShown() and G.GameTooltipTextLeft1 and G.GameTooltipTextLeft1:GetText() == LONGEST_ZONE, "hovering the cut name shows it whole")
expect(G.GameTooltipTextLeft2 and G.GameTooltipTextLeft2:GetText() == "You are here", "and says it is where the player is")
saveScene("long-names-hover")

