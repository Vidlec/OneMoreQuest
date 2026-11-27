local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- OneMoreQuest's tracker with the game's gamepad interface, worked as the game's own tracker is there. The shortcuts'
-- quests button (the shortcuts' modifier held, d-pad up) gives the game's tracker the cursor; while ours stands in
-- for it (the game's hidden), ours gets it instead. Each quest is one stop (its title), a zone's heading one more, and
-- OneMoreQuest's prompts show under the tracker:
--   A  focus the quest, or let go of it      X  open it in the quest log      Y  its menu      B  back to the game
-- On a zone's heading A folds or unfolds it and Y has its menu. A quest's item goes onto the gamepad's action bar
-- from its menu, as on the game's tracker. The cursor, the bindings and the prompts are OneMoreQuest's own, as the quest
-- window's are (Gamepad.lua says why none of the game's navigation is called).
local GamepadTracker = {}
ns.GamepadTracker = GamepadTracker

local state = {
    isActive = false, -- the tracker has the pad
    cursor = nil, -- the row under the cursor
    pointer = nil,
    prompts = nil,
    watcher = nil,
    gameFocus = nil, -- the game's own focus as the tracker took the pad: another of its windows taking it ends ours
    isShortcutHooked = false,
}

local KEYS = { "PADDUP", "PADDDOWN", "PAD1", "PAD2", "PAD3", "PAD4" }

---@return boolean isStop The row is a stop for the cursor: a quest's title, a zone's heading, the line of its zones
local function isStop(row)
    return row:IsVisible() and (row.isTitle or row.zoneId ~= nil or row.isZonesLine) == true
end

---@return Button[] stops The tracker's stops, top to bottom
local function getStops()
    local rows, count = ns.Tracker.getRows()
    local stops = {}
    for index = 1, count do
        if isStop(rows[index]) then
            stops[#stops + 1] = rows[index]
        end
    end
    return stops
end

---@return Button? row Where the cursor starts: the quest in focus, else the first quest, else the first stop
local function findStartRow()
    local firstTitle, firstStop
    for _, row in ipairs(getStops()) do
        if row.isTitle and row.entry and ns.Tracker.isFocused(row.entry.questId) then
            return row
        end
        firstTitle = firstTitle or (row.isTitle and row) or nil
        firstStop = firstStop or row
    end
    return firstTitle or firstStop
end

local function getPrompts()
    local row = state.cursor
    local prompts = {}
    if row then
        local label = ns.Gamepad.getActionLabel("select")
        if row.isTitle and row.entry then
            label = ns.L(ns.Tracker.isFocused(row.entry.questId) and "Unfocus" or "Focus")
        end
        prompts[#prompts + 1] = { key = "PAD1", label = label }
        if row.isTitle then
            prompts[#prompts + 1] = { key = "PAD3", label = ns.L("Open in the quest log") }
        end
        if row.isTitle or row.zoneId then
            prompts[#prompts + 1] = { key = "PAD4", label = ns.Gamepad.getActionLabel("options") }
        end
    end
    prompts[#prompts + 1] = { key = "PAD2", label = ns.Gamepad.getActionLabel("back") }
    return prompts
end

local function setCursor(row)
    if state.cursor and state.cursor ~= row then
        local onLeave = state.cursor:GetScript("OnLeave")
        if onLeave then
            pcall(onLeave, state.cursor)
        end
    end
    local isNew = state.cursor ~= row
    state.cursor = row
    if row then
        ns.Tracker.bringRowIntoView(row)
        local onEnter = isNew and row:GetScript("OnEnter")
        if onEnter then
            pcall(onEnter, row, false)
        end
    end
    if state.pointer then
        ns.Gamepad.placePointer(state.pointer, state.isActive and row or nil)
    end
    if state.prompts then
        if state.isActive then
            state.prompts.setPrompts(getPrompts())
        else
            state.prompts:Hide()
        end
    end
end

---Gives the tracker back to the game: the pad's buttons are the game's again.
function GamepadTracker.release()
    if not state.isActive then
        return
    end
    state.isActive = false
    if state.watcher then
        state.watcher:Hide()
    end
    if state.padButtons then
        state.padButtons.setKeys(nil)
    end
    setCursor(nil)
end

---A on a row: a quest comes into focus (or is let go of), as A on the game's tracker; a zone's heading folds or
---unfolds, the line of a quest's zones turns the map to the next, as a click does.
local function pressRow(row)
    if row.isTitle and row.entry then
        ns.Tracker.toggleFocus(row.entry)
        ns.Tracker.refresh()
    else
        row:Click("LeftButton")
    end
end

local function step(delta)
    local stops = getStops()
    local at
    for index, row in ipairs(stops) do
        if row == state.cursor then
            at = index
        end
    end
    local target = at and stops[at + delta] or (not at and findStartRow())
    if target then
        setCursor(target)
    end
end

local function handlePadDown(key, isRepeat)
    if not state.isActive or (ns.GamepadMenu and ns.GamepadMenu.isOpen()) then
        return
    end
    local row = state.cursor
    if key == "PADDUP" or key == "PADDDOWN" then
        step(key == "PADDUP" and -1 or 1)
        return
    elseif isRepeat then
        return
    elseif key == "PAD2" then
        GamepadTracker.release()
        return
    elseif not row or not isStop(row) then
        setCursor(findStartRow())
        return
    end
    if key == "PAD1" then
        pressRow(row)
    elseif key == "PAD3" and row.isTitle and row.entry then
        GamepadTracker.release()
        ns.Tracker.openInLog(row.entry) -- (the quest in the log: the map opens on it, the window beside it)
    elseif key == "PAD4" and (row.isTitle or row.zoneId) then
        row:Click("RightButton")
    end
    if state.isActive then
        setCursor(state.cursor)
    end
end

local function watch(frame)
    if not state.watcher then
        state.watcher = CreateFrame("Frame")
        state.watcher:SetScript(
            "OnUpdate",
            ns.Timing.timed("pad tracker watch (each frame)", function()
                if
                    not frame:IsVisible()
                    or not ns.Gamepad.isGamepadUI()
                    or ns.Gamepad.getGameFocus() ~= state.gameFocus
                then
                    GamepadTracker.release() -- (hidden, the interface changed, or one of the game's windows took the pad)
                    return
                end
                if state.pointer and state.cursor then
                    state.pointer:SetShown(
                        not (ns.GamepadMenu and ns.GamepadMenu.isOpen()) and state.cursor:IsVisible()
                    )
                end
            end)
        )
    end
    state.watcher:Show()
end

---The tracker takes the pad, the cursor on the quest in focus. Not in a fight (no bindings can be made then), nor
---when it has nothing to stop on (folded, no quests).
function GamepadTracker.handOver()
    local frame = ns.Tracker.getFrame()
    if
        not frame
        or not ns.Gamepad.isGamepadUI()
        or not frame:IsVisible()
        or (InCombatLockdown and InCombatLockdown())
        or ns.Gamepad.hasPad()
    then -- (the quest window has the pad: the shortcut leaves it be)
        return
    end
    local start = findStartRow()
    if not start then
        return
    end
    if not state.padButtons then
        state.padButtons = ns.Gamepad.makePadButtons("OneMoreQuestTrackerPad", KEYS, 2, handlePadDown)
        state.pointer = ns.Gamepad.makePointer(frame)
        state.prompts = ns.Gamepad.makePromptStrip(frame)
        state.prompts:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -4) -- (right-aligned: the tracker stands by the screen's right edge)
    end
    state.isActive = true
    state.gameFocus = ns.Gamepad.getGameFocus()
    state.padButtons.setKeys(KEYS)
    state.cursor = nil
    setCursor(start)
    watch(frame)
end

---@return boolean isFocused The tracker has the pad (its tooltips leave the mouse's hints out)
function GamepadTracker.isFocused()
    return state.isActive
end

---After each drawing of the tracker: the cursor kept on a stop (its rows are reused), the prompts.
function GamepadTracker.handleDrawn()
    if not state.isActive then
        return
    end
    local row = state.cursor
    if row and isStop(row) then
        setCursor(row)
        return
    end
    local start = findStartRow()
    if start then
        setCursor(start)
    else
        GamepadTracker.release() -- nothing left to stop on (the last quest handed in, folded away)
    end
end

---The shortcuts' quests button: the game's tracker gets the cursor when it shows; when ours stands in for it, ours
---(the next frame: once the game is done with the press).
local function handleQuestsShortcut(_, _, isDown)
    if isDown == false or state.isActive then
        return
    end
    if ObjectiveTrackerFrame and ObjectiveTrackerFrame:IsShown() then
        return -- the game's own tracker shows: the button is its
    end
    C_Timer.After(0, GamepadTracker.handOver)
end

---The game sets the quests button's click again now and then (the bar set up again): the hook goes on again with it.
local hookedButtons = setmetatable({}, { __mode = "k" }) -- the quests buttons hooked already (one hook each, ever)

local function hookShortcutButton(bar)
    local button = bar and bar.dpadTopButton
    if button and hookedButtons[button] then
        state.isShortcutHooked = true
        return
    end
    if not button or not button.HookScript or (InCombatLockdown and InCombatLockdown()) then
        state.isShortcutHooked = false -- (again once the fight is over)
        return
    end
    button:HookScript("OnClick", handleQuestsShortcut)
    hookedButtons[button] = true
    state.isShortcutHooked = true
end

local function hookShortcut()
    local main = GamepadMainActionBarFrame
    local bar = main and main.PageUnit and main.PageUnit.ShortcutsActionBar
    if not bar or type(bar.SetUpDpadTop) ~= "function" then
        return
    end
    if not state.isBarHooked then
        state.isBarHooked = true
        hooksecurefunc(bar, "SetUpDpadTop", hookShortcutButton)
    end
    if not state.isShortcutHooked then
        hookShortcutButton(bar)
    end
end

local function create()
    local frame = ns.Tracker.getFrame()
    if not frame then
        return
    end
    frame:HookScript("OnHide", GamepadTracker.release)
    hookShortcut()
end

local function handleInterfaceChange()
    if not ns.Gamepad.isGamepadUI() then
        GamepadTracker.release()
    end
    hookShortcut() -- (the game's gamepad bars may first be there now)
end

ns.registerModule({
    name = "GamepadTracker",
    create = create,
    afterCombat = hookShortcut,
    events = {
        INPUT_DEVICE_INTERFACE_TRANSITION = handleInterfaceChange,
        PLAYER_REGEN_DISABLED = GamepadTracker.release,
    },
})
