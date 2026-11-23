local _, ns = ...

-- OneMoreQuest's map marks with the game's gamepad interface. There the world map has a cursor of its own (the left
-- stick moves it): the game's pins near it are pointed at, and A clicks them. Our marks are no pins of the game's,
-- so they are pointed at here the same way: the mark nearest the cursor, within the game's own reach, lights up and
-- shows its tooltip (with A's icon and what it does), and A opens it as a click does: its quest's page in
-- OneMoreQuest's window. Away from the marks, the quest areas and spawns under the cursor give their tooltip, as
-- under the mouse (MapHover asks where the cursor is: getPointer).
local GamepadMap = {}
ns.GamepadMap = GamepadMap

local REACH = 14 -- how near the cursor's middle a mark's is to be pointed at (the game reaches its pins at 12)

local state = {
    mark = nil, -- the mark pointed at
    isHooked = false,
}

---@return number? x, number? y The map cursor's middle in the screen's points (UIParent's), while the gamepad's
---interface is on and the map has its cursor; nil otherwise (the mouse is what points)
function GamepadMap.getPointer(map)
    local cursor = _G.SoftCursor
    if not map or not ns.Gamepad.isGamepadUI() or type(cursor) ~= "table" or not cursor.IsShown or not cursor:IsShown() or not map:IsVisible() then
        return nil, nil
    end
    if ns.Gamepad.hasPad() then
        return nil, nil -- (the quest window has the pad, taken from the map: the map's cursor points at nothing meanwhile)
    end
    local left, bottom, width, height = cursor:GetRect()
    if not left then
        return nil, nil
    end
    local scale = cursor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return (left + width / 2) * scale, (bottom + height / 2) * scale
end

---@return boolean isOver A point (the screen's points) is over a frame
function GamepadMap.isOver(frame, x, y)
    local left, bottom, width, height = frame:GetRect()
    if not left then
        return false
    end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return x >= left * scale and x <= (left + width) * scale and y >= bottom * scale and y <= (bottom + height) * scale
end

---@return Button? mark The mark the map's cursor points at
function GamepadMap.getMark()
    return state.mark
end

local function leaveMark()
    local mark = state.mark
    if not mark then
        return
    end
    state.mark = nil
    if mark.UnlockHighlight then
        mark:UnlockHighlight()
    end
    local leave = mark:GetScript("OnLeave")
    if leave then
        leave(mark)
    end
end

---Points at the mark nearest the map's cursor (its tooltip, its highlight), or at none.
---@param x number? The cursor, in the screen's points; nil: none pointed at (the map's cursor gone)
function GamepadMap.pointAt(map, x, y)
    local mark = x and ns.MapMarks.findMarkAt(map, x, y, REACH) or nil
    if mark == state.mark then
        return
    end
    leaveMark()
    if not mark then
        return
    end
    state.mark = mark
    if mark.LockHighlight then
        mark:LockHighlight()
    end
    local enter = mark:GetScript("OnEnter")
    if enter then
        enter(mark)
    end
end

---@return string? label What A does on a mark's button (for its tooltip, with A's icon), nil where it does nothing
function GamepadMap.getPressLabel(button)
    local mark = button and button.mark
    if not mark or mark.isPreview then
        return nil
    end
    if ns.MapDock.isMapHandsOff() and not ns.Log.isOpen() then
        -- (the gamepad interface: the map has the game's own quest panel; A focuses a quest, Look.handleMarkClick)
        if mark.questId and mark.kind ~= "giver" and mark.kind ~= "dungeon" then
            return ns.L(mark.questId == ns.Focus.get() and "Unfocus" or "Focus")
        end
        return nil
    end
    if button.coin then
        return ns.L("Show the zone") -- a zone's pill on a continent's map
    elseif mark.kind == "dungeon" then
        return ns.L("Plan the run")
    elseif mark.kind == "giver" then
        return ns.L(mark.isFocused and "Stop highlighting" or "Details")
    end
    return ns.L("Open in the quest log")
end

---What A opened in the quest window, shown there: its row in the middle of the list with the window's cursor on it,
---and the window takes the pad from the map (d-pad left or B give it back: Gamepad.takePadFromMap).
local function showOpened()
    local Log = ns.Log
    if Log.isOpen() and Log.getView() == "quests" and Log.getOpenRowData() ~= nil then
        ns.Gamepad.showRowInList(Log.getOpenRowData())
        ns.Gamepad.takePadFromMap()
    end
end

local function openInLog(questId)
    ns.Log.selectQuest(questId) -- (as a click in the quest list: opened and highlighted)
    showOpened()
end

local function toggleFocus(questId)
    if ns.Log.focusQuest then
        ns.Log.focusQuest(questId)
    else
        ns.Focus.set(questId ~= ns.Focus.get() and questId or nil)
    end
    ns.MapPins.queueRefresh()
end

---@return number[] questIds The quests of the log whose areas are under the map's cursor (as last looked: MapHover)
local function getAreaQuests()
    local questIds = {}
    for _, quest in ipairs(ns.MapHover.getMapQuests()) do
        if ns.QuestState.isInLog(quest.questId) then
            questIds[#questIds + 1] = quest.questId
        end
    end
    return questIds
end

---@return number[] questIds The quests of the log whose areas are under the map's cursor, looked at now
function GamepadMap.getQuestsUnderCursor()
    ns.MapHover.updateMap() -- (what is under the cursor now, not a moment ago)
    return getAreaQuests()
end

---@return number? questId The quest of the log a mark is of (its objectives, its turn-in): what holding A focuses
local function getMarkQuest(mark)
    local data = mark and mark.mark
    if data and not data.isPreview and data.questId and (data.kind == "objective" or data.kind == "turnIn")
        and ns.QuestState.isInLog(data.questId) then
        return data.questId
    end
    return nil
end

---@return boolean isLowest The map shown is a zone's (or a dungeon's, a small place's): one A does nothing of the map's
---own on. On a continent's or the world's map A is the map's own (it goes into the zone under the cursor): OneMoreQuest
---takes no A there, its tooltips do not offer it.
function GamepadMap.isLowestMap()
    local map = WorldMapFrame
    local mapId = map and map.GetMapID and map:GetMapID()
    local info = mapId and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapId)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    return info ~= nil and (info.mapType or 0) >= zoneType
end

---The lines a tooltip of the map's cursor ends with, as the game's own pins say what the pad does: A and what it does,
---held A and what that does, each with A's icon, in the same green. For a mark (button) or the quests' areas under the
---cursor (questIds).
function GamepadMap.addPressLines(tooltip, button, questIds)
    if not GameTooltip_AddLineWithInputIcon or not GAMEPAD_FACE_BOTTOM or not GamepadMap.isLowestMap() then
        return
    end
    local tap, hold
    if button then
        tap = GamepadMap.getPressLabel(button)
        local questId = getMarkQuest(button)
        if questId and ns.Log.isOpen() then
            hold = ns.L(questId == ns.Focus.get() and "Unfocus" or "Focus")
        end
    elseif questIds and #questIds > 0 and ns.Log.isOpen() then
        -- (the quest window open: with the game's own quest panel A stays the game's, isPressWanted)
        tap = ns.L(#questIds == 1 and "Open in the quest log" or "Choose which to open")
        if #questIds == 1 then
            hold = ns.L(questIds[1] == ns.Focus.get() and "Unfocus" or "Focus")
        else
            hold = ns.L("Choose which to focus")
        end
    end
    if tap then
        GameTooltip_AddLineWithInputIcon(tooltip, tap, GREEN_FONT_COLOR, GAMEPAD_FACE_BOTTOM)
    end
    if hold then
        GameTooltip_AddLineWithInputIcon(tooltip, ns.L("Hold: %s", hold), GREEN_FONT_COLOR, GAMEPAD_FACE_BOTTOM)
    end
end

---A tapped on the map's cursor: the mark pointed at clicked (its quest opened in the quest window), or with no mark
---there the quest whose area is under it (several: a menu to choose). The window then has the pad, on that quest.
local function tapAt(mark)
    if mark and mark:IsVisible() then
        mark:Click("LeftButton")
        showOpened()
        return
    end
    if not ns.Log.isOpen() then
        return
    end
    local questIds = GamepadMap.getQuestsUnderCursor()
    if #questIds == 1 then
        openInLog(questIds[1])
    elseif #questIds > 1 then
        ns.openMenu(WorldMapFrame, function(_, root)
            ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
            root:CreateTitle(ns.L("Open in the quest log"))
            for _, questId in ipairs(questIds) do
                local quest = ns.QuestState.getQuest(questId)
                root:CreateButton(quest and quest.title or tostring(questId), function() openInLog(questId) end)
            end
        end)
    end
end

---A held on the map's cursor: the mark's quest put in focus (or let go of); with no mark there, the quest whose area is
---under it, as Alt-click does with the mouse (several: a menu to choose).
local function holdAt(mark)
    if mark and mark:IsVisible() then
        local questId = getMarkQuest(mark)
        if questId then
            toggleFocus(questId)
            local enter = mark:GetScript("OnEnter")
            if enter then
                pcall(enter, mark) -- (its tooltip says Unfocus now, or Focus)
            end
        end
        return
    end
    if WorldMapFrame then
        ns.MapHover.focusUnderCursor(WorldMapFrame)
        ns.MapHover.forgetShownMapQuests() -- (the areas' tooltip filled again: Unfocus now, or Focus)
    end
end

-- A on the map's cursor while it is over a mark of OneMoreQuest's or a quest's area: OneMoreQuest's own (a binding of
-- its own, Gamepad.makePadButtons, so it tells a tap from a hold); elsewhere the game's own A (Change map).
local HOLD_SECONDS = 0.5
local function handlePadDown()
    state.pressedMark = state.mark
    if state.holdTimer then
        state.holdTimer:Cancel()
    end
    state.holdTimer = C_Timer.NewTimer(HOLD_SECONDS, function()
        state.holdTimer = nil
        holdAt(state.pressedMark)
        state.pressedMark = nil
    end)
end

local function handlePadUp()
    if state.holdTimer then
        state.holdTimer:Cancel()
        state.holdTimer = nil
        tapAt(state.pressedMark)
    end
    state.pressedMark = nil
end

---@return boolean isWanted A is OneMoreQuest's now: the map has the pad (its own map focus), its cursor over a mark of
---OneMoreQuest's or a quest's area, and the quest window does not have the pad
local function isPressWanted()
    local map = WorldMapFrame
    if not map or not map:IsVisible() or not ns.Gamepad.isGamepadUI() or ns.Gamepad.hasPad() or map.currentFocus ~= "Map"
        or ns.Gamepad.getGameFocus() ~= map or (ns.GamepadMenu and ns.GamepadMenu.isOpen()) or not GamepadMap.isLowestMap() then
        return false
    end
    if map.GetHoveredPin and map:GetHoveredPin() then
        return false -- (a pin of the game's, or of another addon, under the cursor: A is the game's, to click it)
    end
    if state.mark and state.mark:IsVisible() then
        return GamepadMap.getPressLabel(state.mark) ~= nil or getMarkQuest(state.mark) ~= nil -- (only a mark A does something on)
    end
    return ns.Log.isOpen() and #getAreaQuests() > 0
end

local function watchPress()
    if state.pressWatcher then
        return
    end
    state.padButtons = ns.Gamepad.makePadButtons("OneMoreQuestMapPad", { "PAD1" }, 2, handlePadDown, handlePadUp)
    state.pressWatcher = CreateFrame("Frame")
    state.pressWatcher:SetScript("OnUpdate", function()
        local isWanted = isPressWanted() or state.holdTimer ~= nil -- (kept while held: the release is A's too)
        if isWanted ~= state.isPressBound then
            state.isPressBound = isWanted
            state.padButtons.setKeys(isWanted and { "PAD1" } or nil)
        end
    end)
end

---A on the map through the game's own binding (OneMoreQuest's not bound: in a fight): a tap, as before.
local function handleMapClick()
    local isOurs = state.padButtons ~= nil and state.padButtons.isBound("PAD1") -- (bound in fact: not in a fight)
    if not isOurs and GamepadMap.isLowestMap() then
        tapAt(state.mark)
    end
end

-- (The map opens with the gamepad's focus on its quest panel, gone for our window: d-pad left, the game's own "Map"
-- prompt, brings its cursor up, and RT goes on to our window. Addons cannot move that focus themselves: the game's
-- navigation refuses them, as an action blocked.)

local function create()
    if state.isHooked or not WorldMapFrame or type(WorldMapFrame.ClickHoveredPins) ~= "function" then
        return
    end
    state.isHooked = true
    hooksecurefunc(WorldMapFrame, "ClickHoveredPins", handleMapClick)
    WorldMapFrame:HookScript("OnHide", leaveMark)
    watchPress()
end

ns.registerModule({
    name = "GamepadMap",
    create = create,
    needsWorldMap = true,
    events = {
        INPUT_DEVICE_INTERFACE_TRANSITION = leaveMark,
        -- A fight: the map's A let go of (Gamepad.beforeCombat), a hold begun on it dropped (its release goes to the game)
        PLAYER_REGEN_DISABLED = function()
            if state.holdTimer then
                state.holdTimer:Cancel()
                state.holdTimer = nil
            end
            state.pressedMark = nil
            state.isPressBound = nil -- (bound again after the fight, as the watch asks)
        end,
    },
})
