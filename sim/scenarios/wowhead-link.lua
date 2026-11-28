--@addons QuestieDB, OneMoreQuest
-- Every quest's Wowhead link: the game opens no web page for an addon, so "Wowhead" on the quest page's title line
-- and "Wowhead link" in the quests' menus open a small panel beside what was clicked, the link selected for Ctrl+C.
-- Ctrl+C is seen: the panel says the link was copied and closes. For a quest in the log and one to pick up alike.
setProfile({ level = 14, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844) -- Plainstrider Menace
accept(869) -- Raptor Thieves
wait(1.5)
local addon = require("addons").byName["onemorequest"].private

---The panel shows a quest's link, selected for copying, and closes again
local function expectLinkShown(questId, where)
    wait(0.2)
    local panel = addon.WowheadLink.getShownPanel()
    expect(panel ~= nil, where .. ": the Wowhead link panel opens")
    if not panel then
        return nil
    end
    local editBox = panel.editBox
    local url = "https://www.wowhead.com/classic/quest=" .. questId
    expect(editBox:GetText() == url, where .. ": it holds the quest's link (" .. tostring(editBox:GetText()) .. ")")
    expect(editBox:HasFocus(), where .. ": ready to copy (the text box has the keyboard)")
    expectText("on Wowhead", where .. ": it names the quest")
    expectText("Ctrl+C to copy", where .. ": and says how to copy it")
    -- Typing does not change it: the link is for copying
    editBox:SetText("something else")
    expect(editBox:GetText() == url, where .. ": typing puts the link back")
    return panel
end

local function expectClosed(where)
    wait(0.2)
    expect(addon.WowheadLink.getShownPanel() == nil, where .. ": and it closes")
end

-- The tracker's menu: the panel at the mouse; Escape closes it
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
click(trackerRow(869), "RightButton")
wait(0.2)
expectText("Wowhead link", "the tracker's menu offers the Wowhead link")
click("Wowhead link")
local panel = expectLinkShown(869, "tracker")
if panel then
    panel.editBox:GetScript("OnEscapePressed")(panel.editBox)
    expectClosed("tracker, Escape")
end

-- The quest list's menu
key("M")
wait(0.5)
local function listRow(isWanted)
    local canvas = addon.Log.getListCanvas and addon.Log.getListCanvas()
    for _, button in ipairs(canvas and canvas.pools and canvas.pools.buttons or {}) do
        if
            button:IsVisible()
            and type(button.data) == "number"
            and button.handleRightClick
            and isWanted(button.data)
        then
            return button
        end
    end
end
local row = listRow(function(questId)
    return questId == 844
end)
expect(row ~= nil, "the quest list shows Plainstrider Menace")
if row then
    click(row, "RightButton")
    wait(0.2)
    click("Wowhead link")
    panel = expectLinkShown(844, "quest list")
    if panel then
        panel:Hide()
    end
end

-- The quest page's title line ends in "Wowhead": the panel opens under it, and Ctrl+C closes it
addon.Log.selectQuest(844) -- (a click on a quest already chosen lets go of it: chosen here, whatever it was)
wait(0.3)
local header = addon.LogState.pageHeader
local facts = header.facts:GetText() or ""
expect(facts:find("Wowhead", 1, true) == #facts - #"Wowhead" + 1, "the title line ends in Wowhead (" .. facts .. ")")
expect(header.wowheadButton:IsVisible(), "a link lies over it")
expect(header.zoneButton:IsVisible(), "the zone stays a link of its own")
click(header.wowheadButton)
panel = expectLinkShown(844, "quest page")
if panel then
    -- (on the screen: the quest window is scaled with the map, the panel with the rest of the interface)
    local panelTop = panel:GetTop() * panel:GetEffectiveScale()
    local linkBottom = header.wowheadButton:GetBottom() * header.wowheadButton:GetEffectiveScale()
    expect(
        math.abs(panelTop - (linkBottom - 2 * panel:GetEffectiveScale())) < 1,
        "it opens right under the link (" .. tostring(panelTop) .. ", " .. tostring(linkBottom) .. ")"
    )
    -- Ctrl+C: the panel says the link was copied, and closes a moment later
    local isControlKeyDown = G.IsControlKeyDown
    G.IsControlKeyDown = function()
        return true
    end
    panel.editBox:GetScript("OnKeyDown")(panel.editBox, "C")
    G.IsControlKeyDown = isControlKeyDown
    expectText("Copied: paste it into your browser.", "Ctrl+C: it says the link is copied")
    wait(0.5)
    expect(addon.WowheadLink.getShownPanel() ~= nil, "and stays a moment to be read")
    wait(1.5)
    expectClosed("quest page, Ctrl+C")
end

-- Another page closes a panel opened from this one
click(header.wowheadButton)
wait(0.2)
addon.Log.selectQuest(869)
expectClosed("another quest's page")

-- A quest to pick up: its menu has the link too, and its page's title line
click("Available")
wait(0.5)
local available = listRow(function()
    return true
end)
expect(available ~= nil, "the Available tab lists a quest to pick up")
if available then
    click(available, "RightButton")
    wait(0.2)
    click("Wowhead link")
    panel = expectLinkShown(available.data, "a quest to pick up")
    if panel then
        panel:Hide()
    end
end
