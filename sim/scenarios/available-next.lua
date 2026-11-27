--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=6
-- The Available tab by what to do next: the quests to pick up now with how far they are and what they give, then
-- the quests not yet to be had under what opens them (a quest in the log, a quest to pick up, a level), each of
-- those named once as a heading; and the chips that keep the list to now, soon or later.
setProfile({ level = 6, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68) -- Durotar, the Valley of Trials
local addon = require("addons").byName["onemorequest"].private
local CUTTING_TEETH, STING_OF_THE_SCORPID = 788, 789
accept(CUTTING_TEETH)
wait(2.5)
key("M")
wait(1)
click("Available")
wait(1)

-- The list's buttons are told apart by what a click on them is given: a chip its filter's name, a group's heading
-- its group
local function findButton(isWanted)
    local found
    local function search(frame)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsVisible() and child.handleClick and isWanted(child.data) then
                found = child
            end
            search(child)
        end
    end
    search(addon.Log.getListCanvas().content)
    return found
end
local function findChip(filter)
    return findButton(function(data)
        return data == filter
    end)
end
local function findGroup(key)
    return findButton(function(data)
        return type(data) == "table" and data.key == key and data.quests ~= nil
    end)
end

-- All of it at first: what to pick up now on top, with its facts
expectText("PICK UP NOW")
expectText("OPENS FROM YOUR LOG")
expect(findChip("soon") ~= nil, "the chips over the list")
expectText("XP") -- what a quest to pick up gives
expectText(" yd") -- and how far its giver is
expect(find("NOT YET AVAILABLE") == nil, "no one long list of locked quests")
saveScene("all")

-- Soon: the quests a quest away. Cutting Teeth, in the log, is named once, over the quests it opens
click(findChip("soon"))
wait(0.3)
expect(find("PICK UP NOW") == nil, "the chip keeps the list to what is soon")
expectText("Cutting Teeth")
expectText("Sting of the Scorpid")
expect(findGroup("log:" .. CUTTING_TEETH) ~= nil, "a heading for the quest in the log")
saveScene("soon")
-- Its heading folds the quests under it away, and brings them back
click(findGroup("log:" .. CUTTING_TEETH))
wait(0.3)
expect(find("Sting of the Scorpid") == nil, "a click on the heading folds its quests")
click(findGroup("log:" .. CUTTING_TEETH))
wait(0.3)
expectText("Sting of the Scorpid")
-- A quest under it opens its page, which says what it waits for
click("Sting of the Scorpid")
wait(0.5)
local selected = addon.LogState.selectedAvailableQuest
expect(selected and selected.questId == STING_OF_THE_SCORPID, "a locked quest's row opens its page")

-- Later: the levels still to reach, each a folded heading
click(findChip("later"))
wait(0.3)
expectText("NEEDS A LEVEL")
expectText("At level 7")
expectText("1 level to go")
saveScene("later")
click(findChip("all"))
wait(0.3)
expectText("PICK UP NOW")
