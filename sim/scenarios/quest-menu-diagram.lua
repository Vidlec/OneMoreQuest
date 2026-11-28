--@addons QuestieDB, OneMoreQuest
-- "Quest diagram" in a quest's right-click menu, in the quest list and the tracker: it opens the diagram of the quests
-- around it, as the quest page's button does. A quest with none around it has no such item.
setProfile({ level = 14, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844) -- Plainstrider Menace, the first of a chain
accept(869) -- Raptor Thieves, the first of another
wait(1.5)
local addon = require("addons").byName["onemorequest"].private
local Diagram = addon.LogDiagram

local function expectDiagramOn(questId, where)
    wait(0.3)
    local window = Diagram.getWindow()
    expect(window ~= nil and window:IsShown(), where .. ": the diagram opens")
    if window then
        expect(window.questId == questId, where .. ": on the quest (" .. tostring(window.questId) .. ")")
        window:Hide()
    end
end

-- The tracker's menu
local tracker = G.OneMoreQuestTracker
local function trackerRow(questId, frame)
    for _, child in ipairs({ (frame or tracker):GetChildren() }) do
        if child.entry and child.entry.questId == questId and child:IsVisible() then
            return child
        end
        local found = trackerRow(questId, child)
        if found then
            return found
        end
    end
end
expect(Diagram.canShow(869), "Raptor Thieves has quests around it")
click(trackerRow(869), "RightButton")
wait(0.2)
click("Quest diagram")
expectDiagramOn(869, "tracker")

-- The quest list's menu
key("M")
wait(0.5)
local canvas = addon.Log.getListCanvas()
local row
for _, button in ipairs(canvas.pools.buttons) do
    if button:IsVisible() and button.data == 844 and button.handleRightClick then
        row = button
    end
end
expect(row ~= nil, "the quest list shows Plainstrider Menace")
if row then
    click(row, "RightButton")
    wait(0.2)
    click("Quest diagram")
    expectDiagramOn(844, "quest list")
end

-- Spoilers that keep the chains back: no diagram in the menu
local preset = addon.Spoilers.getPreset()
addon.Spoilers.setChoice("chains", "count")
expect(not Diagram.canShow(844), "the chains kept back: no diagram")
if row then
    click(row, "RightButton")
    wait(0.2)
    expectNoText("Quest diagram", "and the menu has none")
    key("ESCAPE")
end
addon.Spoilers.setPreset(preset)
