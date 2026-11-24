--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=14
-- OneMoreQuest with a controller, the harder parts: the party on a quest's page as rows the cursor stops on; a full
-- quest log (the drop panel never taking the cursor from the quest it came back to, the banner on Available, abandoning
-- through Y, asked first in OneMoreQuest's own menu); the right stick scrolling the list; and the mouse's and the
-- controller's window swapped while it is open. Nothing of the game's navigation called (lib/omqpad.lua).
if not require("addons").byName["onemorequest"].private.Gamepad then
    print("skipped: this OneMoreQuest has no controller support")
    return
end
moveTo(1413, 0.52, 0.30)
accept(844)
joinParty({ name = "Garra", class = "HUNTER", level = 14 }) -- runs OneMoreQuest
joinParty({ name = "Brakka", class = "WARRIOR", level = 15, addon = "none" })
memberAccept("Garra", 844)
memberProgress("Garra", 844, 1, 3)
wait(1.5)
local omq = require("omqpad").start()
gamepadInterface(true)
local window = G.TrailheadLog
local addon = require("addons").byName["onemorequest"].private
addon.MapDock.open() -- (the gamepad interface: the window by itself, the map keeping the game's quest panel)
wait(0.5)
expect(omq.isOwn("PADDDOWN"), "the window has the pad")

-- The party on the quest's page: a row each, one stop each, the tooltip of the faces, A shares, Y their menu
local function pageButtons(test)
    local found, pool = {}, addon.Log.getPageCanvas().pools.buttons
    for index = 1, pool.usedCount do
        local button = pool[index]
        if button:IsVisible() and test(button) then
            found[#found + 1] = button
        end
    end
    return found
end
expect(omq.cursor() and omq.cursor().data == 844, "the cursor starts on Plainstrider Menace")
pad("PAD1")
wait(0.3)
expect(addon.Log.isInPage(omq.cursor()), "A takes the cursor into its page beside the list")
local members = pageButtons(function(button)
    return type(button.data) == "table" and button.data.unit ~= nil
end)
expect(#members == 2, "the party: a row a member (" .. #members .. ")")
local garra
for _, row in ipairs(members) do
    local isStop = false
    for _, stop in ipairs(addon.Gamepad.getStops()) do
        if stop == row then
            isStop = true
        end
    end
    expect(isStop, "a member's row is a cursor stop (" .. row.data.name .. ")")
    if row.data.name == "Garra" then
        garra = row
    end
end
expectText("3/", "Garra's row says her count")
if garra then
    addon.Gamepad.setCursor(garra)
    wait(0.2)
    expect(
        G.GameTooltip:IsShown() and G.GameTooltipTextLeft1:GetText() ~= nil,
        "the cursor on her row shows the faces' tooltip"
    )
    pad("PAD4")
    wait(0.3)
    expect(addon.GamepadMenu.isOpen(), "Y opens her menu")
    expectText("Whisper", "with Whisper in it")
    pad("PAD2")
    wait(0.3)
end
saveScene("pad-party")
pad("PAD2") -- back to the list
wait(0.3)
expect(omq.cursor() and omq.cursor().data == 844 and omq.cursor().isQuestRow, "B: back on the quest's own row")
leaveParty("Garra")
leaveParty("Brakka")
wait(0.5)

-- A full log: 20 quests
for _, questId in ipairs({
    870,
    871,
    819,
    869,
    1492,
    848,
    6365,
    867,
    5041,
    899,
    4921,
    855,
    850,
    1486,
    884,
    897,
    792,
    790,
    894,
}) do
    accept(questId)
end
wait(1)
local count, max = addon.QuestState.getLogSize()
expect(count >= max, "the log is full (" .. count .. "/" .. max .. ")")
-- A goes into any quest's details, B back to its row: every quest of the full log
do
    local failed = {}
    local rows = {}
    for _, stop in ipairs(addon.Gamepad.getStops()) do
        if stop.isQuestRow and type(stop.data) == "number" then
            rows[#rows + 1] = stop.data
        end
    end
    for _, questId in ipairs(rows) do
        local row
        for _, stop in ipairs(addon.Gamepad.getStops()) do
            if stop.isQuestRow and stop.data == questId then
                row = stop
            end
        end
        if row then
            addon.Gamepad.setCursor(row)
            pad("PAD1")
            local isIn = addon.Log.isInPage(omq.cursor())
            pad("PAD2")
            local isBack = omq.cursor() and omq.cursor().data == questId and omq.cursor().isQuestRow
            if not (isIn and isBack) then
                failed[#failed + 1] = questId .. (isIn and "" or " (A)") .. (isBack and "" or " (B)")
            end
        end
    end
    expect(
        #rows > 10 and #failed == 0,
        "A into each quest's details, B back to its row ("
            .. #rows
            .. " quests; failed: "
            .. table.concat(failed, ", ")
            .. ")"
    )
end
-- The right stick scrolls the pane the cursor is in: the list, or the quest's details beside it; the game's stick
-- hint stands on that pane's scroll bar
local list = addon.Log.getListCanvas()
expect((list.maxScroll or 0) > 0, "the full log's list scrolls")
list:setScroll(0)
addon.Gamepad.setCursor(addon.Gamepad.getStops()[1])
for _, stop in ipairs(addon.Gamepad.getStops()) do
    if stop.isQuestRow then
        addon.Gamepad.setCursor(stop)
        break
    end
end
padStick("Camera", 0, -1, 0.8)
wait(0.3)
expect(
    list:getScroll() > 0,
    "with the cursor in the list, the right stick scrolls the list (" .. list:getScroll() .. ")"
)
wait(0.3)
do
    local view = addon.Log.getListCanvas().frame
    local middle = (view:GetTop() + view:GetBottom()) / 2
    local cursor = omq.cursor()
    expect(
        cursor and cursor:GetTop() >= middle - 40 and cursor:GetBottom() <= middle + 40,
        "the cursor stays in the middle of the list as it scrolls, on the row there (a quest, or a zone's heading)"
    )
    expect(
        not cursor.isQuestRow or addon.Log.getSelectedQuestId() == cursor.data,
        "a quest there: its details show beside the list once the stick rests"
    )
end
local facing = G.GetPlayerFacing()
padStick("Camera", -1, -0.6, 0.6)
wait(0.2)
expect(
    math.abs(G.GetPlayerFacing() - facing) < 0.001,
    "the right stick is the window's meanwhile: the camera (the character) does not turn"
)
list:setScroll(0)
local page = addon.Log.getPageCanvas()
for _, stop in ipairs(addon.Gamepad.getStops()) do
    if stop.isQuestRow then
        addon.Gamepad.setCursor(stop)
        break
    end
end
pad("PAD1")
wait(0.3)
expect(addon.Log.isInPage(omq.cursor()), "(A: the cursor in the quest's details)")
page:setScroll(0)
padStick("Camera", 0, -1, 0.8)
wait(0.3)
if (page.maxScroll or 0) > 0 then
    expect(
        page:getScroll() > 0,
        "with the cursor in the details, the right stick scrolls them (" .. page:getScroll() .. ")"
    )
else
    print("(the open quest's details fit: nothing for the right stick to scroll)")
end
pad("PAD2")
wait(0.3)
for _ = 1, 16 do
    pad("PADDDOWN")
end
wait(0.3)
expect(list:getScroll() > 0, "walking down the list scrolls it (" .. list:getScroll() .. ")")
list:setScroll(0)
local function listButtons(test)
    local found, pool = {}, addon.Log.getListCanvas().pools.buttons
    for index = 1, pool.usedCount do
        local button = pool[index]
        if button:IsVisible() and test(button) then
            found[#found + 1] = button
        end
    end
    return found
end
-- The quests worth dropping, in their own window (over the list): the cursor on the first, each row
-- one stop (its Abandon left to the row's menu, Y), B closes the window and puts the cursor back in the list
addon.Log.showDropSuggestions()
wait(0.3)
local suggestions = addon.Log.getDropRows()
expect(#suggestions > 0, "the quests worth dropping open in their window (" .. #suggestions .. ")")
local firstSuggestion = suggestions[1]
local isAbandonStop = false
for _, stop in ipairs(addon.Gamepad.getStops()) do
    if firstSuggestion and stop == firstSuggestion.abandonButton then
        isAbandonStop = true
    end
end
expect(not isAbandonStop, "a suggestion is one stop, its Abandon under Y")
expect(omq.cursor() == firstSuggestion, "the cursor on the first quest worth dropping")
saveScene("pad-fulllog-mine")
pad("PAD2")
wait(0.3)
expect(#addon.Log.getDropRows() == 0, "B closes the window")
expect(omq.cursor() and omq.cursor().isQuestRow, "and the cursor is back in the list")
-- Back from a suggested quest's page lands on its own row in the list
local suggested = firstSuggestion and firstSuggestion.data
local ownRow = listButtons(function(button)
    return button.isQuestRow and button.data == suggested
end)[1]
expect(ownRow ~= nil, "the suggested quest has its own row in the list")
if ownRow then
    addon.Gamepad.setCursor(ownRow)
    pad("PAD1")
    wait(0.3)
    expect(
        addon.Log.isInPage(omq.cursor()) and addon.Log.getSelectedQuestId() == suggested,
        "A opens it, the cursor in its page"
    )
    pad("PAD2")
    wait(0.3)
    expect(omq.cursor() and omq.cursor().isQuestRow and omq.cursor().data == suggested, "B comes back to its own row")
end

-- Available: one banner; A on it goes to the quests worth dropping
pad("PADRSHOULDER")
wait(0.5)
local banner = listButtons(function(button)
    return button.isLogFullBanner
end)[1]
expect(banner ~= nil, "Available opens with the full-log banner")
expect(omq.cursor() and omq.cursor().isQuestRow, "the cursor still starts on a quest to pick up")
saveScene("pad-fulllog-available")
if banner then
    addon.Gamepad.setCursor(banner)
    wait(0.2)
    expectText("What to drop", "on the banner A says what it does")
    pad("PAD1")
    wait(0.5)
    expect(not addon.Log.isShowingAvailable(), "A on the banner goes to My quests")
    expect(omq.cursor() and omq.cursor().isDropSuggestion, "with the cursor on the first quest worth dropping")
end

-- Abandoning through Y, asked first in OneMoreQuest's own menu (the game's question would be taken over by its frame
-- controls in OneMoreQuest's run); the cursor stays in the window, on something shown
local dropped = omq.cursor() and omq.cursor().data
pad("PAD4")
wait(0.3)
local _, menuTexts = omq.menu()
expect(menuTexts:find("Abandon", 1, true) ~= nil, "Y on a suggestion has Abandon: " .. menuTexts)
local Menu = addon.GamepadMenu
for _ = 1, 12 do
    if tostring(Menu.getCursorText()):find("Abandon", 1, true) then
        break
    end
    pad("PADDDOWN")
end
expect(tostring(Menu.getCursorText()):find("Abandon", 1, true), "(the menu's cursor on Abandon)")
pad("PAD1")
wait(0.3)
local _, question = omq.menu()
expect(
    Menu.isOpen() and question:find("?", 1, true) and not (G.StaticPopup1 and G.StaticPopup1:IsShown()),
    "it asks first, in OneMoreQuest's menu: " .. question
)
saveScene("pad-abandon-question")
expect(tostring(Menu.getCursorText()):find("Abandon", 1, true), "the menu's cursor on Abandon")
pad("PAD1")
wait(0.8)
expect(not Menu.isOpen() and not addon.QuestState.isInLog(dropped), "A: the quest is abandoned")
do
    wait(0.2)
    local cursor = omq.cursor()
    local isInWindow = false
    local frame = cursor
    while frame do
        if frame == window then
            isInWindow = true
        end
        frame = frame:GetParent()
    end
    expect(cursor and cursor:IsVisible() and isInWindow, "the cursor is on something shown in the window, not lost")
end

-- The mouse's window and the controller's, swapped while it is open
gamepadInterface(false)
wait(0.5)
expect(
    window:IsShown() and window:GetWidth() > 600 and addon.Log.getPageCanvas().frame:IsShown(),
    "mouse and keyboard: the two panes again"
)
do
    local started = os.clock()
    for _ = 1, 10 do
        addon.Log.refresh()
    end
    print(
        string.format(
            "a drawing of the window, two panes, a full log: %.1f ms (in the simulator)",
            (os.clock() - started) * 100
        )
    )
end
gamepadInterface(true)
wait(0.5)
expect(
    window:IsShown() and window:GetWidth() > 600 and addon.Log.getPageCanvas().frame:IsShown(),
    "controller: still the two panes"
)

-- What a redraw costs with the controller, a full log
local started = os.clock()
for _ = 1, 10 do
    addon.Log.refresh()
end
local perDrawing = (os.clock() - started) * 1000 / 10
print(string.format("a drawing of the window with the controller, a full log: %.1f ms (in the simulator)", perDrawing))
do
    local started = os.clock()
    for _ = 1, 10 do
        addon.Gamepad.handleDrawn()
    end
    print(string.format("  of which the controller's part: %.2f ms", (os.clock() - started) * 100))
end
local problem = omq.report()
expect(problem == nil, "nothing OneMoreQuest must not do: " .. tostring(problem))
