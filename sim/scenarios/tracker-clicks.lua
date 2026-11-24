-- A quest in the tracker answers clicks as it does everywhere else: a click opens it in the quest log (the map
-- opens with it), ctrl-click puts it in focus and takes the focus off again, shift-click links it in chat.
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.30)
accept(844)
accept(869)
wait(2)
local addon = require("addons").byName["onemorequest"].private
local function trackerRow(questId, frame)
    frame = frame or G.UIParent
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.entry and child.entry.questId == questId and child:IsVisible() and not child.zoneId then
            return child
        end
        local found = trackerRow(questId, child)
        if found then
            return found
        end
    end
end
expect(trackerRow(844) ~= nil, "the quest has a row in the tracker")
expect(not G.WorldMapFrame:IsShown(), "the map starts closed")
local focusedBefore = addon.Focus.get()
click(trackerRow(844))
wait(1.5)
expect(G.WorldMapFrame:IsShown() == true, "a click opens the map with the quest log")
expect(addon.Log.isOpen() == true, "the quest window is open beside it")
expect(addon.Focus.get() == focusedBefore, "a plain click changes no focus")
expectText("Plainstrider Menace")
key("M")
wait(1)
click(trackerRow(869), "LeftButton", { ctrl = true })
wait(1)
expect(addon.Focus.get() == 869, "ctrl-click puts the quest in focus")
expect(not G.WorldMapFrame:IsShown(), "and opens nothing")
click(trackerRow(869), "LeftButton", { ctrl = true })
wait(1)
expect(addon.Focus.get() == nil, "ctrl-click on the focused quest takes the focus off")
