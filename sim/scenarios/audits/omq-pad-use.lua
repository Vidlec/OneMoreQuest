--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=14
-- Using OneMoreQuest's window with the gamepad, control by control: a tooltip as the cursor rests on a quest, the
-- quest page's buttons, the filter dropdown and its menu, a long list scrolling with the cursor, the settings' controls.
moveTo(1413, 0.52, 0.30)
for _, questId in ipairs({ 844, 870, 871, 819 }) do accept(questId) end
wait(1)
local blocked = 0
G.hooksecurefunc("DisplayInterfaceActionBlockedMessage", function() blocked = blocked + 1 end)
gamepadInterface(true)
key("M")
wait(1)
local window, manager, nav = G.TrailheadLog, G.GamepadMode.FrameControlsManager, G.SmartNavigation
local addon = require("addons").byName["onemorequest"].private
local scene, W, sim = require("scene"), require("widgets"), require("sim")
for _ = 1, 4 do if manager:GetActiveFrame() == window then break end pad("PADRTRIGGER") end
wait(0.3)
local function textOf(frame)
    if frame.GetText and frame:GetText() then return frame:GetText() end
    for _, region in ipairs({ frame:GetRegions() }) do if region.GetText and region:GetText() then return region:GetText() end end
end
local function goTo(test, label)
    local function visit(frame)
        if frame:IsVisible() and G.SmartNavigation_CanFocusFrame(frame) and test(frame) then return frame end
        for _, child in ipairs({ frame:GetChildren() }) do local found = visit(child); if found then return found end end
    end
    local found = visit(window)
    if found then sim.runSecurely(nav.SetTargetButtonForFrame, nav, window, found); wait(0.2) end
    print(label, found and "found" or "NOT FOUND", nav.currentButton == found)
    return found
end

-- A quest row: its tooltip, as the mouse resting on it
goTo(function(f) return f.data == 870 and f:GetWidth() > 100 end, "row of 870:")
print("tooltip on the row:", G.GameTooltip:IsShown(), G.GameTooltipTextLeft1:GetText())
print("cursor before A", nav.currentButton and nav.currentButton.data, "clickable", G.SmartNavigation_IsCurrentButtonClickable(), "active", nav.activeInfo ~= nil)
pad("PAD1") -- opens it on the page
wait(0.3)
print("cursor after A", nav.currentButton and nav.currentButton.data)
print("selected:", addon.Log.getSelectedQuestId())

-- The page's Untrack, then Track again
local untrack = goTo(function(f) return f:GetObjectType() == "Button" and textOf(f) == "Untrack" end, "Untrack:")
if untrack then
    pad("PAD1"); wait(0.3)
    print("after A on Untrack: tracked?", G.C_QuestLog.GetQuestWatchType(addon.Log.getSelectedQuestId() or 0) ~= nil, "button now", textOf(untrack), "cursor", nav.currentButton == untrack, nav.currentButton and textOf(nav.currentButton), nav.currentButton and nav.currentButton:IsVisible(), "clickable", G.SmartNavigation_IsCurrentButtonClickable())
    pad("PAD1"); wait(0.3)
    print("after A again: tracked?", G.C_QuestLog.GetQuestWatchType(addon.Log.getSelectedQuestId() or 0) ~= nil)
end

-- The filter dropdown ("All") and its menu
local dropdown = goTo(function(f) return f:GetObjectType() == "DropdownButton" end, "filter dropdown:")
if dropdown then
    pad("PAD1"); wait(0.3)
    local menu = G.Menu.GetManager():GetOpenMenu()
    print("menu open:", menu ~= nil and menu:IsShown(), "active frame is the menu:", manager:GetActiveFrame() ~= window, "cursor:", nav.currentButton and textOf(nav.currentButton))
    pad("PADDDOWN"); wait(0.2)
    print("cursor after down:", nav.currentButton and textOf(nav.currentButton))
    pad("PAD2"); wait(0.3)
    print("after B: menu open:", G.Menu.GetManager():GetOpenMenu() ~= nil, "focus back on the window:", manager:GetActiveFrame() == window)
end

-- A long list (Available) scrolls as the cursor walks down
pad("PADRSHOULDER"); wait(0.5)
local list = addon.Log.getListCanvas()
local before = list.frame:GetVerticalScroll()
local function inView()
    local b, f = nav.currentButton and W.computeRect(nav.currentButton), W.computeRect(list.frame)
    return b and f and b[2] >= f[2] - 1 and b[4] <= f[4] + 1, b and f and string.format("btn %d..%d view %d..%d", b[2], b[4], f[2], f[4])
end
for step = 1, 30 do pad("PADDDOWN"); local ok, where = inView(); if not ok then print("  step " .. step .. " cursor out of view: " .. tostring(where) .. " scroll " .. list.frame:GetVerticalScroll()) end end
print("Available list scroll", before, "->", list.frame:GetVerticalScroll(), "max", list.maxScroll, "cursor in view:", nav.currentButton and textOf(nav.currentButton))
pad("PADLSHOULDER"); wait(0.5)

-- Settings: a checkbox and a stepper
addon.Log.openSettings(1); wait(0.5)
local check = goTo(function(f) return f:GetObjectType() == "CheckButton" end, "a settings checkbox:")
if check then
    local was = check:GetChecked()
    pad("PAD1"); wait(0.2)
    print("checkbox", was, "->", check:GetChecked())
    pad("PAD1"); wait(0.2)
end
print("blocked actions:", blocked, "errors:", #sim.errors)
saveScene("pad-use")
