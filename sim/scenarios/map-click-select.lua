--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=20
-- (only the addons it plays with: ForeverDungeonJournal opens its first-run mode chooser over the screen three
-- seconds after login, in the way of what is clicked and hovered)
-- Ctrl-click puts a quest in focus, from the list or its mark on the map. A click on the map where there is
-- nothing lets go of the selected quest; dragging the map to pan it does not.
setProfile({ level = 20 })
moveTo(1413, 0.52, 0.30) -- The Barrens, by the Crossroads
local addon = require("addons").byName["onemorequest"].private
local GUNS_OF_NORTHWATCH, DISRUPTION_ENDS = 891, 872
accept(GUNS_OF_NORTHWATCH)
accept(DISRUPTION_ENDS)
wait(1.5)
addon.Focus.set(nil)
key("M")
wait(0.8)

-- Ctrl-click in the list: focused
click("The Guns of Northwatch", "LeftButton", { ctrl = true })
wait(0.3)
expect(addon.Focus.get() == GUNS_OF_NORTHWATCH, "ctrl-click in the list puts the quest in focus")
-- Ctrl-click again: let go of
click("The Guns of Northwatch", "LeftButton", { ctrl = true })
wait(0.3)
expect(addon.Focus.get() == nil, "ctrl-click on the focused quest lets go of it")

-- Ctrl-click a mark on the map
local function findMark(questId)
    for _, layer in ipairs({ G.WorldMapFrame:GetCanvas():GetChildren() }) do
        for _, child in ipairs({ layer:GetChildren() }) do
            if
                child.mark
                and child.mark.questId == questId
                and child.mark.kind == "objective"
                and child:IsVisible()
            then
                return child
            end
        end
    end
end
local mark = findMark(DISRUPTION_ENDS)
expect(mark ~= nil, "The Disruption Ends has a mark on the map")
if mark then
    click(mark, "LeftButton", { ctrl = true })
    wait(0.3)
    expect(addon.Focus.get() == DISRUPTION_ENDS, "ctrl-click on its mark puts the quest in focus")
end
addon.Focus.set(nil)
wait(0.3)

-- Select a quest, then click the map where there is nothing
addon.Log.selectQuest(GUNS_OF_NORTHWATCH)
wait(0.3)
expect(addon.Log.getSelectedQuestId() == GUNS_OF_NORTHWATCH, "selected")
local container = G.WorldMapFrame.ScrollContainer
local left, bottom, width, height = container:GetRect()
local scale = container:GetEffectiveScale()
-- An empty spot: the map's top left part, away from marks (checked: nothing there takes the mouse)
local empty = { x = (left + width * 0.08) * scale, y = require("sim").screenHeight - (bottom + height * 0.9) * scale }
hover(empty)
wait(0.1)
local focus = G.GetMouseFoci()[1]
expect(
    focus == container or focus == G.WorldMapFrame:GetCanvas() or (focus and focus:GetParent() == container),
    "nothing of ours under the empty spot"
)
drag(empty, { dx = 60, dy = 30 })
wait(0.3)
expect(addon.Log.getSelectedQuestId() == GUNS_OF_NORTHWATCH, "dragging the map to pan it keeps the selection")
click(empty)
wait(0.3)
expect(addon.Log.getSelectedQuestId() == nil, "a click on the map where there is nothing lets go of the selected quest")
saveScene("deselected")
