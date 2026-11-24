--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=12
-- OneMoreQuest's other parts with a controller: the settings and the chronicle (sections down the side shown as the
-- cursor comes onto them, LB/RB the section before or after, A into one, B back a step, Y the settings' options),
-- the tracker (the game's quests shortcut gives it the pad) and the map's marks (the map's own cursor). All of it with
-- OneMoreQuest's own cursor, bindings and menus, nothing of the game's navigation called (lib/omqpad.lua).
if not require("addons").byName["onemorequest"].private.Gamepad then
    print("skipped: this OneMoreQuest has no controller support")
    return
end
moveTo(1413, 0.52, 0.30)
accept(844) -- Plainstrider Menace
accept(870) -- The Forgotten Pools
accept(871) -- Disrupt the Attacks
complete(844)
turnIn(844) -- (a quest's story in the chronicle's journal)
accept(845)
wait(1)
if not G.GamepadMainActionBarFrame then
    print("skipped: the game's own gamepad interface is not loaded (light mode)")
    return
end
local omq = require("omqpad").start()
local addon, window = omq.addon, omq.window
local Log = addon.Log
gamepadInterface(true)
addon.MapDock.open() -- (the window by itself)
wait(0.5)
expect(window:IsVisible() and omq.isOwn("PADDDOWN"), "the window has the pad")
local function isIn(frame, parent)
    while frame do
        if frame == parent then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end
local function inList(frame)
    return isIn(frame, Log.getListCanvas().frame)
end
local function cursor()
    return omq.cursor()
end

-- The settings
Log.openSettings(1)
wait(0.4)
expect(
    Log.getView() == "settings" and inList(cursor()) and cursor().data == 1,
    "the settings open with the cursor on their first section"
)
expectText("Sections", "LB/RB: the sections")
pad("PAD4")
wait(0.3)
local isOpen, texts = omq.menu()
expect(
    not isOpen or (texts:find("Reset to defaults", 1, true) and not texts:find("Abandon", 1, true)),
    "Y on a section: the settings' options, never a quest's menu: " .. texts
)
if isOpen then
    pad("PAD2")
    wait(0.3)
end
pad("PADDDOWN")
wait(0.5)
expect(cursor() and cursor().data == 2 and Log.isChosenSectionRow(2), "the cursor resting on a section shows it")
pad("PADRSHOULDER")
wait(0.3)
expect(Log.isChosenSectionRow(3) and cursor() and cursor().data == 3, "RB: the next section, the cursor on its row")
pad("PADLSHOULDER")
wait(0.3)
expect(Log.isChosenSectionRow(2), "LB: the one before")
pad("PAD1")
wait(0.3)
expect(Log.isInPage(cursor()), "A goes into the section, the cursor on its page")
pad("PADDLEFT")
expect(inList(cursor()), "d-pad left from the page: the sections")
pad("PADDRIGHT")
expect(Log.isInPage(cursor()), "and right: the page again")
saveScene("pad-settings")
-- A checkbox of the page: A turns it, as a click does
local checkbox
for _, stop in ipairs(addon.Gamepad.getStops()) do
    if stop:GetObjectType() == "CheckButton" and Log.isInPage(stop) then
        checkbox = stop
        break
    end
end
if checkbox then
    addon.Gamepad.setCursor(checkbox)
    local was = checkbox:GetChecked()
    pad("PAD1")
    wait(0.2)
    expect(checkbox:GetChecked() ~= was, "A turns a setting's checkbox")
    pad("PAD1")
    wait(0.2)
end
pad("PAD4")
wait(0.3)
local isMenu, joined = omq.menu()
expect(isMenu, "Y: the settings' options")
expect(
    joined:find("Reset to defaults", 1, true) ~= nil and not joined:find("Done", 1, true),
    "with Reset to defaults, not Done (B is that): " .. joined
)
pad("PAD2")
wait(0.3)
pad("PAD2")
wait(0.3)
expect(
    Log.getView() == "settings" and inList(cursor()) and cursor().data == 2,
    "B on the page: back to its section's row"
)
pad("PAD2")
wait(0.3)
expect(
    Log.getView() == "quests" and cursor() and cursor().isQuestRow,
    "B on the sections: out of the settings, on a quest's row"
)

-- The chronicle
Log.toggleChronicle()
wait(0.4)
expect(Log.getView() == "chronicle" and inList(cursor()), "the chronicle opens with the cursor on its chapters")
local journal
for _ = 1, 5 do
    pad("PADRSHOULDER")
    wait(0.2)
    if addon.ChroniclePage.isChosenRow(3) then
        journal = true
        break
    end
end
expect(journal, "RB through the chapters to the Journal")
pad("PAD1")
wait(0.3)
expect(Log.isInPage(cursor()), "A: into the journal")
local entryRow
local pool = Log.getPageCanvas().pools.buttons
for index = 1, pool.usedCount do
    if type(pool[index].data) == "number" and pool[index].data > 0 and pool[index]:IsVisible() then
        entryRow = pool[index]
        break
    end
end
expect(entryRow ~= nil, "the journal lists the quest handed in")
if entryRow then
    local entry = entryRow.data
    addon.Gamepad.setCursor(entryRow)
    pad("PAD1")
    wait(0.3)
    expect(addon.ChroniclePage.isEntryOpen(), "A opens its story")
    saveScene("pad-chronicle-story")
    pad("PAD2")
    wait(0.3)
    expect(
        not addon.ChroniclePage.isEntryOpen() and Log.getView() == "chronicle",
        "B: back to the journal's list, still in the chronicle"
    )
    expect(cursor() and cursor().data == entry and Log.isInPage(cursor()), "the cursor on that quest in the list")
end
pad("PAD2")
wait(0.3)
expect(Log.getView() == "chronicle" and inList(cursor()), "B: back to the chapters")
pad("PAD2")
wait(0.3)
expect(Log.getView() == "quests", "B: out of the chronicle")

-- The tracker: the game's quests shortcut (its modifier held, d-pad up) gives it the pad, the game's own tracker
-- being hidden for it
Log.closeWindow()
wait(0.5)
expect(not omq.isOwn("PADDDOWN"), "the window closed: the pad the game's")
local tracker = G.TrailheadTracker
expect(tracker:IsVisible() and not G.ObjectiveTrackerFrame:IsShown(), "OneMoreQuest's tracker stands in for the game's")
local shortcut = G.GamepadMainActionBarFrame.PageUnit.ShortcutsActionBar.dpadTopButton
shortcut:Click("LeftButton", true)
wait(0.3)
local Tracker = addon.GamepadTracker
expect(
    Tracker.isFocused() and tostring(G.GetBindingAction("PADDDOWN")):find("TrackerPad", 1, true),
    "the quests shortcut gives the tracker the pad"
)
expectText("Open in the quest log", "X: open it in the quest log, on its prompts")
saveScene("pad-tracker")
local rows, count = addon.Tracker.getRows()
local firstTitle
for index = 1, count do
    if rows[index]:IsVisible() and rows[index].isTitle then
        firstTitle = rows[index]
        break
    end
end
local questId = firstTitle and firstTitle.entry and firstTitle.entry.questId
if questId then
    local before = addon.Focus.get()
    pad("PAD1")
    wait(0.3)
    expect(addon.Focus.get() ~= before, "A focuses the quest, or lets go of it")
    expect(Tracker.isFocused(), "the tracker keeps the pad")
    pad("PAD4")
    wait(0.3)
    local isTrackerMenu, trackerTexts = omq.menu()
    expect(
        isTrackerMenu and trackerTexts:find("Untrack", 1, true) ~= nil,
        "Y: the quest's menu (OneMoreQuest's): " .. trackerTexts
    )
    pad("PAD2")
    wait(0.3)
    expect(not addon.GamepadMenu.isOpen() and Tracker.isFocused(), "B closes the menu, back in the tracker")
    pad("PADDDOWN")
    wait(0.2)
    pad("PADDUP")
    wait(0.2)
    pad("PAD3")
    wait(0.8)
    expect(window:IsShown() and Log.isAlone(), "X opens the quest in the quest log (the window by itself)")
    expect(
        not Tracker.isFocused()
            and omq.isOwn("PADDDOWN")
            and tostring(G.GetBindingAction("PADDDOWN")):find("OneMoreQuestPad", 1, true),
        "the window has the pad now, not the tracker"
    )
    Log.closeWindow()
    wait(0.5)
end
shortcut:Click("LeftButton", true)
wait(0.3)
pad("PAD2")
wait(0.3)
expect(not Tracker.isFocused() and not omq.isOwn("PADDDOWN"), "B: back to the game, the tracker's buttons let go")

-- The map's marks: the map's own cursor points at them as at the game's pins; A opens the quest in the window
key("M")
wait(1)
expect(window:IsShown() and not Log.isAlone(), "the map opens with the window in place of the game's quest panel")
pad("PADDLEFT") -- (the window has the pad: nothing to its left, the game's own "World map")
wait(0.3)
local soft = G.SoftCursor
expect(G.WorldMapFrame:IsMapFocused() and soft and soft:IsShown(), "d-pad left: the map, with its own cursor")
addon.MapMarks.getDrawn(G.WorldMapFrame)
local marks = addon.MapMarksState.pools.marks
local target
for index = 1, marks.usedCount do
    local button = marks[index]
    if button:IsVisible() and button.mark and button.mark.kind == "objective" and button.mark.questId == 871 then
        target = button
        break
    end
end
expect(target ~= nil, "Disrupt the Attacks has its mark on the map")
if target and soft then
    local x, y = target:GetCenter()
    local scale = target:GetEffectiveScale() / G.UIParent:GetEffectiveScale()
    soft:ClearAllPoints()
    soft:SetPoint("CENTER", G.UIParent, "BOTTOMLEFT", x * scale + 1, y * scale - 1)
    wait(0.3)
    expect(addon.GamepadMap.getMark() == target, "the map's cursor near the mark points at it")
    expect(G.GameTooltip:IsShown() and G.GameTooltip:GetOwner() == target, "its tooltip shows")
    expectText("Open in the quest log", "with what A does")
    saveScene("pad-map-mark")
    pad("PAD1")
    wait(0.5)
    expect(
        Log.getSelectedQuestId() == 871 and window:IsShown() and G.WorldMapFrame:IsShown(),
        "A opens its quest in the window"
    )
    do
        local cursor = addon.Gamepad.getCursor()
        local view = Log.getListCanvas().frame
        local middle = (view:GetTop() + view:GetBottom()) / 2
        expect(
            cursor and cursor.data == 871 and cursor.isQuestRow,
            "its row has the window's cursor, there when the window takes the pad again"
        )
        local isAtTop = Log.getListCanvas():getScroll() < 1
        expect(
            cursor and (isAtTop or math.abs((cursor:GetTop() + cursor:GetBottom()) / 2 - middle) < 30),
            "in the middle of the list (unless the list cannot scroll that far)"
        )
    end
    wait(0.2)
    expect(
        omq.isOwn("PADDDOWN") and addon.Gamepad.hasPad() and G.WorldMapFrame:IsMapFocused(),
        "and the window has the pad, on that quest (the map keeping its own focus)"
    )
    expect(G.SoftCursor:GetAlpha() == 0, "the map's cursor out of sight meanwhile")
    pad("PADDDOWN")
    pad("PADDLEFT")
    wait(0.2)
    expect(
        not addon.Gamepad.hasPad() and not omq.isOwn("PADDDOWN") and G.SoftCursor:GetAlpha() == 1,
        "d-pad left with nothing to the left: the pad back to the map, its cursor again"
    )
    -- Held A on the mark: its quest in focus (or let go of), nothing opened; the tooltip says both, as on the areas
    soft:ClearAllPoints()
    soft:SetPoint("CENTER", G.UIParent, "BOTTOMLEFT", x * scale + 1, y * scale - 1)
    wait(0.3)
    expectText("Hold: ", "the mark's tooltip says what held A does")
    local focusBefore = addon.Focus.get()
    pad("PAD1", 0.8)
    wait(0.2)
    expect(
        addon.Focus.get() ~= focusBefore and not addon.Gamepad.hasPad(),
        "held A on the mark: its quest's focus changes, the map keeps the pad"
    )
    soft:ClearAllPoints()
    soft:SetPoint("CENTER", G.UIParent, "BOTTOMLEFT", x * scale + 60, y * scale + 60)
    wait(0.3)
    expect(
        addon.GamepadMap.getMark() == nil and G.GameTooltip:GetOwner() ~= target,
        "moved away: the mark let go of, its tooltip gone"
    )
end
pad("PAD2")
wait(0.5)
expect(not G.WorldMapFrame:IsShown() and not window:IsShown(), "the map's own B closes it, the window with it")
local problem = omq.report()
expect(problem == nil, "nothing OneMoreQuest must not do: " .. tostring(problem))
