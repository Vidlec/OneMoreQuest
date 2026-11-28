--@addons QuestieDB, OneMoreQuest
-- Every quest's Wowhead link: the game opens no web page for an addon, so "Wowhead" on the quest page's title line
-- and "Wowhead link" in the quests' menus open a small panel beside what was clicked, the link selected for Ctrl+C.
-- Ctrl+C is seen: the panel says the link was copied and closes. For a quest in the log and one to pick up alike.
screen(1920, 1080) -- (room to stretch the window)
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
    local url = "https://www.wowhead.com/forever/quest=" .. questId
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

-- A long line: "Wowhead" ends it while it fits the line's own width (a stretched window's is wider than the page's
-- least), and starts a line of its own under it when it does not. Letters are added until the line with "Wowhead"
-- passes that least but fits the stretched one.
do
    local MapDock = addon.MapDock
    MapDock.startResize(false)
    MapDock.resizeTo(300, 0) -- (sideways beyond the map's growing: the page widens)
    MapDock.stopResize()
    wait(0.3)
    local least = addon.LogStyle.PAGE_CONTENT_WIDTH - 2 * addon.LogStyle.PADDING
    local lineWidth = header.facts:GetWidth()
    local function measure(text)
        header.measure:SetText(text)
        return header.measure:GetStringWidth()
    end
    local longFacts = "Levels 36\226\128\14741+ \194\183 Riverglades \194\183 Group quest"
    while measure(longFacts .. " \194\183 Wowhead") <= least + 10 do
        longFacts = longFacts .. "i"
    end
    local width = measure(longFacts .. " \194\183 Wowhead")
    expect(width < lineWidth - 10, "the long line fits the stretched one (" .. width .. ", " .. lineWidth .. ")")
    addon.LogQuestPage.setPageHeader("Twilight No More!", longFacts, 1, 3, nil, 844)
    expect(
        header.facts:GetText() == longFacts .. " \194\183 Wowhead",
        "stretched: Wowhead ends the line (" .. header.facts:GetText() .. ")"
    )
    expect(header.wowheadButton:IsShown(), "a link over it")
    local oneLineHeight = header:GetHeight()

    -- The usual size again: Wowhead on a line of its own
    click(MapDock.getResizeGrip(), "RightButton")
    wait(0.3)
    addon.LogQuestPage.setPageHeader("Twilight No More!", longFacts, 1, 3, nil, 844)
    expect(
        header.facts:GetText() == longFacts .. "\nWowhead",
        "the usual width: Wowhead on a line of its own (" .. header.facts:GetText() .. ")"
    )
    expect(header.wowheadButton:IsShown(), "a link over it")
    local scale = header:GetEffectiveScale()
    local factsLeft, factsBottom = header.facts:GetLeft() * scale, header.facts:GetBottom() * scale
    local linkLeft, linkBottom = header.wowheadButton:GetLeft() * scale, header.wowheadButton:GetBottom() * scale
    expect(
        math.abs(linkLeft - (factsLeft - 2 * scale)) < 1 and math.abs(linkBottom - (factsBottom - 2 * scale)) < 1,
        "at the start of the facts' last line ("
            .. linkLeft
            .. ","
            .. linkBottom
            .. " / "
            .. factsLeft
            .. ","
            .. factsBottom
            .. ")"
    )
    expect(header:GetHeight() > oneLineHeight + 8, "the header grows by the line")

    -- A new width lays the shown header out again, without a new drawing (the page turns wide after it is drawn)
    local usualWidth = header:GetWidth()
    addon.LogQuestPage.setPageHeaderWidth(usualWidth + 100)
    expect(header.facts:GetText() == longFacts .. " \194\183 Wowhead", "wider: back on the line")
    addon.LogQuestPage.setPageHeaderWidth(usualWidth)
    expect(header.facts:GetText() == longFacts .. "\nWowhead", "narrower: on its own line again")
    addon.Log.selectQuest(869)
    wait(0.2)
    addon.Log.selectQuest(844)
    wait(0.2)
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
