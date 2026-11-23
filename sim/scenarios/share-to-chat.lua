--@addons QuestieDB, OneMoreQuest
-- (only the addons it plays with: ForeverDungeonJournal opens its first-run mode chooser over the screen three
-- seconds after login, in the way of what is clicked and hovered)
-- Sharing quests to chat, as the game's quest log does: shift-click a quest (tracker, quest list, quest page,
-- map mark) puts its link in the message being typed, or opens the chat with it; the right-click menus of the
-- tracker and the quest log have "Share to chat"; untracking is in the menu, not on shift-click.
setProfile({ level = 14, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844) -- Plainstrider Menace
accept(869) -- Raptor Thieves
wait(1.5)
local addon = require("addons").byName["onemorequest"].private
local W = require("widgets")
local box = G.ChatFrame1EditBox
local function message() return box:IsShown() and (box:GetText() or "") or "" end
local function hasLink(questId) return message():find("|Hquest:" .. questId .. ":", 1, true) ~= nil end
local function closeChat() if box:IsShown() then box:SetText(""); box:Hide(); box:ClearFocus() end end

-- The tracker: shift-click opens the chat with the link; the quest stays tracked
local tracker = G.TrailheadTracker
local function trackerRow(questId, frame)
    for _, child in ipairs({ (frame or tracker):GetChildren() }) do
        if child.entry and child.entry.questId == questId and child:IsVisible() then return child end
        local found = trackerRow(questId, child)
        if found then return found end
    end
end
local row = trackerRow(844)
expect(row ~= nil, "the tracker shows Plainstrider Menace")
click(row, "LeftButton", { shift = true })
expect(hasLink(844), "shift-click in the tracker opens the chat with the quest's link")
expect(addon.QuestState.isWatched(844), "and leaves the quest tracked")
click(trackerRow(869), "LeftButton", { shift = true })
expect(hasLink(844) and hasLink(869), "a second shift-click adds its link to the message being typed")
closeChat()

-- The tracker's menu: Share to chat
click(trackerRow(869), "RightButton")
wait(0.2)
expectText("Share to chat", "the tracker's menu offers Share to chat")
expectText("Untrack", "and Untrack")
click("Share to chat")
wait(0.2)
expect(hasLink(869), "Share to chat in the tracker's menu puts the link in the chat")
closeChat()

-- The quest log: right-click menu, and shift-click on a row and on the page's title
key("M")
wait(0.5)
local function logRow(questId)
    local canvas = addon.Log.getListCanvas and addon.Log.getListCanvas()
    -- The row itself (its small track button carries the quest too, without a menu)
    for _, button in ipairs(canvas and canvas.pools and canvas.pools.buttons or {}) do
        if button:IsVisible() and button.data == questId and button.handleRightClick then return button end
    end
end
local entry = logRow(869)
expect(entry ~= nil, "the quest log lists Raptor Thieves")
if entry then
    click(entry, "RightButton")
    wait(0.2)
    expectText("Share with the party", "the log's menu offers sharing with the party")
    click("Share to chat")
    wait(0.2)
    expect(hasLink(869), "Share to chat in the log's menu puts the link in the chat")
    closeChat()
    click(entry, "LeftButton", { shift = true })
    expect(hasLink(869), "shift-click on a quest in the log links it")
    closeChat()
    click(entry) -- opens its page
    wait(0.3)
    local title = G.TrailheadLog and addon.Log.getPageTitleButton and addon.Log.getPageTitleButton()
    if title then
        click(title, "LeftButton", { shift = true })
        expect(hasLink(869), "shift-click on the quest page's title links it")
        closeChat()
    end
end

-- A map mark
local canvas = G.WorldMapFrame.ScrollContainer.Child
local markButton
-- (one the player can click: the open quest's own marks may lie over some of them)
local scene = require("scene")
local function isOnTop(button)
    local rect = W.computeRect(button)
    return rect and scene.findFrameAt((rect[1] + rect[3]) / 2, (rect[2] + rect[4]) / 2, "click") == button
end
for _, layer in ipairs({ canvas:GetChildren() }) do
    for _, child in ipairs({ layer:GetChildren() }) do
        if child.mark and child.mark.questId == 844 and child:IsVisible() and (not markButton or isOnTop(child)) then markButton = child end
    end
end
expect(markButton ~= nil, "the map marks Plainstrider Menace")
if markButton then
    click(markButton, "LeftButton", { shift = true })
    expect(hasLink(844), "shift-click on its map mark links it")
    closeChat()
end

-- A quest to pick up: its menu shares it to chat too, with a link made like the game's
click("Available")
wait(0.5)
local available
local canvasList = addon.Log.getListCanvas()
for _, button in ipairs(canvasList.pools.buttons or {}) do
    if button:IsVisible() and type(button.data) == "number" and button.handleRightClick then available = button; break end
end
expect(available ~= nil, "the Available tab lists a quest to pick up")
if available then
    click(available, "RightButton")
    wait(0.2)
    click("Share to chat")
    wait(0.2)
    expect(hasLink(available.data), "Share to chat works for a quest to pick up")
end

-- Sending it: said aloud, with the link
local said
local listener = G.CreateFrame("Frame")
listener:RegisterEvent("CHAT_MSG_SAY")
listener:SetScript("OnEvent", function(_, _, text) said = text end)
key("ENTER")
wait(0.1)
expect(said and said:find("|Hquest:", 1, true), "Enter says the message with its link")
