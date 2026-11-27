--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=12
-- OneMoreQuest in the game's gamepad interface (needs the whole interface): its window stands in for the game's quest
-- panel beside the map and works with the pad by itself: its own cursor, its own bindings while the map's focus is on
-- its quest log (or while the window is open alone), its own prompts and menus. The d-pad walks its rows, X tracks or
-- focuses the quest under the cursor, Y opens the row's menu, LB/RB change tabs, B goes back, the right stick scrolls.
-- With nothing to the left, d-pad left is the game's own "World map", and with nothing to go back to B is the game's
-- (it closes the map). OneMoreQuest never calls the game's navigation, nor opens, turns or closes the map itself
-- (each taints the game's gamepad state: lib/omqpad.lua watches for it).
if not require("addons").byName["onemorequest"].private.Gamepad then
    print("skipped: this OneMoreQuest has no controller support")
    return
end
moveTo(1413, 0.52, 0.30)
accept(844) -- Plainstrider Menace
accept(870) -- The Forgotten Pools
wait(1)
if not G.GamepadMainActionBarFrame then
    print("skipped: the game's own gamepad interface is not loaded (light mode)")
    return
end
local omq = require("omqpad").start()
local addon, window = omq.addon, omq.window
local Log = addon.Log
gamepadInterface(true)
local map = G.WorldMapFrame
local function isIn(frame, parent)
    while frame do
        if frame == parent then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end
local function isQuestRow(button)
    return button ~= nil and button.isQuestRow == true and type(button.data) == "number"
end

-- The map: OneMoreQuest's window in place of the game's quest panel; the map's focus on its quest log, so the window
-- has the pad
key("M")
wait(1)
expect(
    window:IsVisible() and not Log.isAlone() and (not G.QuestMapFrame:IsShown() or G.QuestMapFrame:GetAlpha() == 0),
    "OneMoreQuest's window stands in for the game's quest panel (kept open by the game, out of sight)"
)
expect(
    map.currentFocus == "Quest",
    "the map opens with its focus on its quest log (" .. tostring(map.currentFocus) .. ")"
)
local inWalk = omq.framesInMapWalk()
expect(
    #inWalk == 0,
    "no frame of OneMoreQuest's inside the map where the game's navigation walks it as its focus goes to its quest log ("
        .. table.concat(inWalk, ", ")
        .. ")"
)
local STRATA =
    { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
expect(
    window:GetParent() == G.UIParent and STRATA[window:GetFrameStrata()] > STRATA[map:GetFrameStrata()],
    "the window laid over the map instead, the screen's child a strata above it (nothing of the map's draws over it)"
)
expect(isQuestRow(omq.cursor()), "the window's cursor on a quest")
expect(omq.isOwn("PADDDOWN") and omq.isOwn("PAD1") and omq.isOwn("PAD3"), "the d-pad, A and X are the window's")
expect(
    not omq.isOwn("PADDLEFT") and not omq.isOwn("PAD2"),
    "d-pad left and B are the game's (nothing to the left, nothing to go back to)"
)
local first = omq.cursor()
pad("PADDDOWN")
expect(
    omq.cursor() ~= first and isIn(omq.cursor(), window),
    "d-pad down moves the cursor (" .. tostring(omq.cursor() and omq.cursor().data) .. ")"
)
pad("PADDUP")
expect(omq.cursor() == first, "and up back")
saveScene("omq-gamepad-docked")
-- d-pad left: the game's own "World map"; its d-pad right ("Quests") comes back to the window
pad("PADDLEFT")
wait(0.3)
expect(map:IsMapFocused() and not omq.isOwn("PADDDOWN"), "d-pad left: the map has the pad, the window's buttons let go")
pad("PADDRIGHT")
wait(0.3)
expect(
    map.currentFocus == "Quest" and omq.isOwn("PADDDOWN") and omq.cursor() == first,
    "the map's Quests (d-pad right) gives the window the pad again, its cursor where it was"
)
-- B with nothing to go back to: the game's own, which closes the map (OneMoreQuest closes no map)
pad("PAD2")
wait(0.5)
expect(not map:IsShown() and not window:IsShown(), "B closes the map, the window with it")
expect(not omq.isOwn("PADDDOWN") and not omq.isOwn("PAD1"), "the window's buttons let go")

-- OneMoreQuest's window by itself (as its tracker's X opens it): the list and the page side by side as with the mouse, the
-- pad its own, the cursor on a quest
addon.MapDock.open()
wait(0.5)
expect(window:IsVisible() and Log.isAlone(), "OneMoreQuest's window opens by itself")
expect(
    window:GetWidth() > 600 and Log.getPageCanvas().frame:IsVisible() and Log.getListCanvas().frame:IsVisible(),
    "the list and the quest's details side by side, as with the mouse"
)
expect(isQuestRow(omq.cursor()) and omq.isOwn("PAD2"), "its cursor on a quest; B is the window's (it closes it)")
expect(
    window.tabHints and window.tabHints[1]:IsShown() and window.tabHints[2]:IsShown(),
    "LB and RB beside the tabs, as the game's windows show them"
)
saveScene("omq-gamepad")

-- Walking the list: the details beside it follow the cursor once it rests on a quest
do
    local from = omq.cursor()
    for _ = 1, 8 do
        pad("PADDDOWN")
        if isQuestRow(omq.cursor()) and omq.cursor() ~= from then
            break
        end
    end
    wait(0.4)
    expect(
        isQuestRow(omq.cursor()) and Log.getSelectedQuestId() == omq.cursor().data,
        "the cursor resting on a quest shows its details beside the list"
    )
    expect(isIn(omq.cursor(), Log.getListCanvas().frame), "the cursor stays in the list")
    for _ = 1, 20 do
        pad("PADDDOWN")
    end
    expect(
        isIn(omq.cursor(), Log.getListCanvas().frame),
        "down past the list's last quest: the cursor stays in the list (the details are reached sideways, with A and B)"
    )
    for _ = 1, 20 do
        pad("PADDUP")
    end
    expect(not Log.isInPage(omq.cursor()), "and up past its top: not into the details either")
end

-- On a quest of the player's: X held focuses it, X tapped tracks it
for _ = 1, 12 do
    if isQuestRow(omq.cursor()) then
        break
    end
    pad("PADDDOWN")
end
local questId = omq.cursor() and omq.cursor().data
expect(isQuestRow(omq.cursor()), "the cursor reached a quest")
if questId then
    local before = addon.Focus.get()
    pad("PAD3", 0.8)
    expect(
        addon.Focus.get() == (before ~= questId and questId or nil),
        "X held focuses the quest under the cursor, or lets go of it"
    )
    pad("PAD3", 0.8)
    expect(
        addon.Focus.get() == (before == questId and questId or nil),
        "and held again lets go of it (or focuses it again)"
    )
    local wasTracked = G.C_QuestLog.GetQuestWatchType(questId) ~= nil
    expectText(wasTracked and "Untrack" or "Track", "the prompts say what X does")
    pad("PAD3")
    wait(0.2)
    expect((G.C_QuestLog.GetQuestWatchType(questId) ~= nil) ~= wasTracked, "X tapped tracks or untracks it")
    pad("PAD3")
    wait(0.2)
    expect((G.C_QuestLog.GetQuestWatchType(questId) ~= nil) == wasTracked, "and tapped again undoes it")
end

-- Y: the row's menu, OneMoreQuest's own, worked by the pad; B closes it
pad("PAD4")
wait(0.3)
local isOpen, texts = omq.menu()
expect(
    isOpen and G.Menu.GetManager():GetOpenMenu() == nil,
    "Y opens the row's menu (OneMoreQuest's, not the game's): " .. texts
)
expect(
    omq.isOwn("PADDDOWN") and tostring(G.GetBindingAction("PADDDOWN")):find("MenuPad", 1, true),
    "the menu has the d-pad while it shows"
)
pad("PADDDOWN")
pad("PAD2")
wait(0.2)
expect(
    not addon.GamepadMenu.isOpen() and tostring(G.GetBindingAction("PADDDOWN")):find("OneMoreQuestPad", 1, true),
    "B closes it, the d-pad the window's again"
)

-- A on a quest's row: the cursor into its page beside the list
local function findStop(test)
    for _, stop in ipairs(addon.Gamepad.getStops()) do
        if test(stop) then
            return stop
        end
    end
end
local row = findStop(function(f)
    return f.data == 870 and isQuestRow(f)
end)
expect(row ~= nil, "the list has The Forgotten Pools' row")
local stopsOfRow = 0
for _, stop in ipairs(addon.Gamepad.getStops()) do
    if stop.data == 870 and isIn(stop, Log.getListCanvas().frame) then
        stopsOfRow = stopsOfRow + 1
    end
end
expect(stopsOfRow == 1, "a quest's row is one stop (X tracks it, Y has the rest) (" .. stopsOfRow .. ")")
for _, tab in ipairs(window.tabs) do
    expect(not findStop(function(f)
        return f == tab
    end), "the tabs are not stops (LB/RB)")
end
if row then
    addon.Gamepad.setCursor(row)
    pad("PAD1")
    wait(0.3)
    expect(Log.getSelectedQuestId() == 870, "A on a row opens its quest")
    expect(Log.getListCanvas().frame:IsVisible() and Log.getPageCanvas().frame:IsVisible(), "its page beside the list")
    expect(Log.isInPage(omq.cursor()), "with the cursor on the page")
    local focusedBefore = addon.Focus.get()
    pad("PAD3", 0.7)
    wait(0.2)
    expect(addon.Focus.get() ~= focusedBefore, "X held focuses the quest from anywhere on its page")
    pad("PAD3", 0.7)
    wait(0.2)
    expect(addon.Focus.get() == focusedBefore, "and held again puts it back")
    local plainRewards = 0
    for _, icon in ipairs(Log.getRewardIcons()) do
        if icon:IsVisible() and not icon.item and findStop(function(f)
            return f == icon
        end) then
            plainRewards = plainRewards + 1
        end
    end
    expect(plainRewards == 0, "the rewards' experience and money are not stops (" .. plainRewards .. ")")
    -- Down through the page: the cursor walks its controls, the page scrolling with it
    local seen, steps = {}, 0
    for _ = 1, 30 do
        local before = omq.cursor()
        pad("PADDDOWN")
        if omq.cursor() == before then
            break
        end
        steps = steps + 1
        seen[#seen + 1] = omq.cursor()
    end
    expect(steps > 0, "d-pad down walks the page (" .. steps .. " stops)")
    expect(omq.cursor() and addon.Gamepad.isInView(omq.cursor()), "the page scrolled to keep the cursor in view")
    saveScene("omq-gamepad-page")
    -- Y on the page: the page's buttons as a menu
    pad("PAD4")
    wait(0.3)
    local isMenu, menuTexts = omq.menu()
    expect(
        isMenu and menuTexts:find("Abandon", 1, true),
        "Y on the page: its buttons as a menu, Abandon among them: " .. menuTexts
    )
    pad("PAD2")
    wait(0.2)
    pad("PAD2")
    wait(0.3)
    expect(isIn(omq.cursor(), Log.getListCanvas().frame), "B goes back to the list")
    expect(omq.cursor() and omq.cursor().data == 870 and isQuestRow(omq.cursor()), "with the cursor on the quest's row")
    -- d-pad right on the row is A (into its details), d-pad left in the details is B (back to its row)
    pad("PADDRIGHT")
    wait(0.2)
    expect(
        Log.isInPage(omq.cursor()) and Log.getSelectedQuestId() == 870,
        "d-pad right on a quest goes into its details, as A"
    )
    for _ = 1, 3 do
        pad("PADDDOWN")
    end
    pad("PADDLEFT")
    wait(0.2)
    expect(
        omq.cursor() and omq.cursor().data == 870 and isQuestRow(omq.cursor()),
        "d-pad left in the details goes back to its row, as B"
    )
end

-- Back from the page to its quest even when its zone was folded meanwhile: the zone opens again, the row in view
row = findStop(function(f)
    return f.data == 870 and isQuestRow(f)
end)
addon.Gamepad.setCursor(row)
pad("PAD1")
wait(0.2)
expect(Log.isInPage(omq.cursor()), "A takes the cursor into the quest's page")
local heading
local pool = Log.getListCanvas().pools.buttons
for index = 1, pool.usedCount do
    if type(pool[index].data) == "table" and pool[index]:GetWidth() > 100 then
        heading = pool[index]
        break
    end
end
expect(heading ~= nil, "(a zone's heading)")
heading:Click("LeftButton") -- the zone folded (as the mouse would)
wait(0.3)
addon.Gamepad.setCursor(findStop(function(f)
    return Log.isInPage(f)
end))
pad("PAD2")
wait(0.3)
expect(
    omq.cursor() and omq.cursor().data == 870 and omq.cursor():IsVisible(),
    "B comes back to the quest's row, its zone open again"
)
-- A folded zone's heading is a stop as any other: the d-pad walks onto it (A unfolds it)
do
    local folded
    local pool = Log.getListCanvas().pools.buttons
    for index = 1, pool.usedCount do
        if type(pool[index].data) == "table" and pool[index]:GetWidth() > 100 and pool[index]:IsVisible() then
            folded = pool[index]
            break
        end
    end
    folded:Click("LeftButton")
    wait(0.3)
    local headings = 0
    for _, stop in ipairs(addon.Gamepad.getStops()) do
        if type(stop.data) == "table" and isIn(stop, Log.getListCanvas().frame) then
            headings = headings + 1
        end
    end
    expect(headings > 0, "the folded zone's heading is still a stop of the list (" .. headings .. ")")
    for index = 1, pool.usedCount do
        if type(pool[index].data) == "table" and pool[index]:GetWidth() > 100 and pool[index]:IsVisible() then
            pool[index]:Click("LeftButton")
            break
        end
    end
    wait(0.3)
end

-- The filter dropdown: A opens its choices in OneMoreQuest's menu; a choice sets it
local dropdown = findStop(function(f)
    return f:GetObjectType() == "DropdownButton"
end)
expect(dropdown ~= nil, "the filter dropdown is a stop")
if dropdown then
    addon.Gamepad.setCursor(dropdown)
    pad("PAD1")
    wait(0.3)
    local isMenu, choices = omq.menu()
    expect(isMenu and G.Menu.GetManager():GetOpenMenu() == nil, "A on the filter opens its choices: " .. choices)
    pad("PAD2")
    wait(0.2)
    expect(not addon.GamepadMenu.isOpen() and omq.cursor() == dropdown, "B closes them, the cursor on the dropdown")
end

-- View: the search box
pad("PADBACK")
wait(0.2)
expect(Log.getShownSearchBox():HasFocus(), "View goes to the search box")
pad("PAD2")
wait(0.2)
expect(not Log.getShownSearchBox():HasFocus() and window:IsShown(), "B leaves the search box, the window stays")

-- LB/RB change tabs, the cursor going to the tab's list
pad("PADRSHOULDER")
wait(0.3)
expect(
    Log.isShowingAvailable() and isIn(omq.cursor(), Log.getListCanvas().frame),
    "RB: the next tab (Available), the cursor in its list"
)
saveScene("omq-gamepad-available")
pad("PADLSHOULDER")
wait(0.3)
expect(not Log.isShowingAvailable() and isQuestRow(omq.cursor()), "LB: back to My quests")

-- The settings: the cursor goes into them, and B brings it back to the open quest
Log.openSettings(1)
wait(0.3)
expect(
    Log.getView() == "settings" and omq.cursor() ~= nil and isIn(omq.cursor(), window),
    "the settings open with the cursor in them"
)
pad("PAD2")
wait(0.3)
expect(
    Log.getView() == "quests" and isQuestRow(omq.cursor()) and omq.cursor().data == Log.getSelectedQuestId(),
    "B leaves the settings, the cursor back on the open quest"
)

-- B closes the window, the pad the game's again
pad("PAD2")
wait(0.5)
expect(not window:IsShown(), "B closes the window")
expect(not omq.isOwn("PADDDOWN") and not omq.isOwn("PAD2"), "its buttons let go")
local problem = omq.report()
expect(problem == nil, "nothing OneMoreQuest must not do: " .. tostring(problem))

-- Mouse and keyboard again: OneMoreQuest's window stands beside the map once more, in place of the game's panel
gamepadInterface(false)
wait(0.3)
key("M")
wait(1)
expect(
    window:IsVisible() and not Log.isAlone() and not G.QuestMapFrame:IsShown(),
    "mouse and keyboard: the window beside the map again"
)
-- (and the walk below does find frames of OneMoreQuest's inside the map, where they are harmless without the gamepad)
expect(#omq.framesInMapWalk() > 0, "mouse and keyboard: the window is the map's own child again")
key("M")
wait(0.5)
