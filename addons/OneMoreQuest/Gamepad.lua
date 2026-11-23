local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- OneMoreQuest with the game's gamepad interface (WoW Forever's Gamepad UI). The window stands in for the game's quest
-- log beside the map, and works with the pad the way that log does, with OneMoreQuest's own means only: its own
-- cursor (the game's hand, drawn by OneMoreQuest), its own bindings for the pad's buttons (override bindings of its
-- own, the way any addon binds keys) and its own prompts under the window.
--   d-pad  move the cursor (left, with nothing to the left in the window: the game's own "World map")
--   A  press (a quest: its page in the list's place)     X  track or untrack the quest; held, focus it (or let go)
--   Y  the row's menu (More actions); on the page, the page's buttons (Options)     View  the search box
--   LB/RB  the tab before or after     B  back one step (search, page, settings, chronicle); with nothing to go back
--   to, the game's own B (it closes the map)     right stick  scroll
-- None of it calls the game's navigation (SmartNavigation, its frame controls): an addon's call there carries the
-- addon's taint into the game's own state (its binding stack, its cursor), and the game then refuses its own work
-- (the d-pad dead, "Interface action failed because of an AddOn"). The window works while the map's focus is on its
-- quest log (the game's, which the window keeps hidden: the map's own d-pad right, RT, and the map opening put it
-- there), or while the window is open alone (the map closed). Menus are OneMoreQuest's own too (GamepadMenu.lua):
-- the game's menus are taken over by its frame controls as they open. The tracker and the map's marks have their own
-- (GamepadTracker.lua, GamepadMap.lua). Everything the game has for it is asked for and left alone when this client
-- has none of it: the window then works as it always has.
local Gamepad = {}
ns.Gamepad = Gamepad

local state = {
    isActive = false, -- the window has the pad: its bindings on, its cursor shown
    cursor = nil, -- the control the cursor is on
    pointer = nil, -- the cursor's hand
    prompts = nil, -- the prompt strip under the window
    watcher = nil, -- follows the map's focus and the right stick while the window shows in the Gamepad UI
    isHooked = false,
    hasPlacedCursor = false, -- the cursor was put on the open quest's row since the window opened
    placeAfterDrawing = false, -- the next drawing puts the cursor on the open quest's row (another tab)
    drawnView = nil, -- the view of the last drawing: the cursor moves with the window to the settings and back
}

---@return boolean isOn The game's gamepad interface is on (Forever's Gamepad UI)
function Gamepad.isGamepadUI()
    return type(InputUtil) == "table" and type(InputUtil.IsGamepadUIEnabled) == "function" and InputUtil.IsGamepadUIEnabled() == true
end

---@return table? manager The game's frame controls (GamepadMode.FrameControlsManager), only ever read
local function getManager()
    local manager = type(GamepadMode) == "table" and GamepadMode.FrameControlsManager
    return type(manager) == "table" and manager or nil
end
Gamepad.getManager = getManager

---@return Frame? frame The frame the game's frame controls have the pad on (the map, the bags...), nil for none
function Gamepad.getGameFocus()
    local manager = getManager()
    return manager and type(manager.GetActiveFrame) == "function" and manager:GetActiveFrame() or nil
end

---------------------------------------------------------------------------------------------------------------
-- The pad's buttons: OneMoreQuest's own override bindings
--
-- A set of hidden buttons, one for each of some of the pad's buttons, which override bindings of OneMoreQuest's own
-- click on the press and on the release. Priority bindings: they come before the game's own gamepad bindings (also
-- priority override bindings, on UIParent), the latest set first; the game sets its own again as its windows change,
-- so OneMoreQuest's are set again after each of the game's on the same buttons (hooked: the game's own call is left
-- as it is). Sets have a rank: a menu's buttons come before the window's. Not in a fight (the game refuses bindings
-- then): done once it is over (rebind).

local padSets = {} -- every set, lowest rank first
local ownOwners = {} -- the sets' owners: their own bindings are not the game's
local REPEAT_DELAY, REPEAT_EVERY = 0.35, 0.08 -- a d-pad button held: the move again after a while, and again
local REPEATED = { PADDUP = true, PADDDOWN = true, PADDLEFT = true, PADDRIGHT = true }

local function canBind()
    return not (InCombatLockdown and InCombatLockdown())
end

local function bindKey(set, key)
    SetOverrideBinding(set.owner, true, key, nil)
    SetOverrideBindingClick(set.owner, true, key, set.buttons[key]:GetName(), "LeftButton")
end

---Every set that has the key bound, set again from the lowest rank up: the highest set last comes first.
local function applyKey(key)
    for _, set in ipairs(padSets) do
        if set.boundKeys[key] then
            bindKey(set, key)
        end
    end
end

---The game set a binding of its own: OneMoreQuest's on the same button set again after it.
local function handleForeignBinding(owner, _, key)
    if ownOwners[owner] or type(key) ~= "string" or not canBind() then
        return
    end
    key = key:upper()
    for _, set in ipairs(padSets) do
        if set.boundKeys[key] then
            applyKey(key)
            return
        end
    end
end

local function hookBindings()
    if state.isBindingHooked or type(hooksecurefunc) ~= "function" then
        return
    end
    state.isBindingHooked = true
    for _, name in ipairs({ "SetOverrideBinding", "SetOverrideBindingClick" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, handleForeignBinding)
        end
    end
end

---@param name string The buttons' name, before each key (a click binding needs a global name)
---@param keys string[] The pad's buttons (PADDUP, PAD1...)
---@param rank number Which set comes first on a button both have bound (the higher)
---@param handleDown fun(key: string, isRepeat: boolean)
---@param handleUp fun(key: string)?
function Gamepad.makePadButtons(name, keys, rank, handleDown, handleUp)
    hookBindings()
    local set = { owner = CreateFrame("Frame"), buttons = {}, boundKeys = {}, wantedKeys = {}, rank = rank }
    ownOwners[set.owner] = true
    for _, key in ipairs(keys) do
        local button = CreateFrame("Button", name .. key, UIParent)
        button:Hide()
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetScript("OnClick", function(_, _, isDown)
            ns.noteActivity("pad " .. key .. (isDown and " down" or " up"))
            if isDown then
                if REPEATED[key] then
                    set.held, set.heldFor, set.nextRepeat = key, 0, REPEAT_DELAY
                    set.owner:Show()
                end
                handleDown(key, false)
            else
                if set.held == key then
                    set.held = nil
                    set.owner:Hide()
                end
                if handleUp then
                    handleUp(key)
                end
            end
        end)
        set.buttons[key] = button
    end
    set.owner:Hide()
    set.owner:SetScript("OnUpdate", function(owner, elapsed)
        local key = set.held
        -- (the button another set's now, a menu's say: its release goes there, the repeat stops here)
        local isOurs = key and GetBindingAction and GetBindingAction(key, true) == "CLICK " .. set.buttons[key]:GetName() .. ":LeftButton"
        if not key or not set.boundKeys[key] or not isOurs then
            set.held = nil
            owner:Hide()
            return
        end
        set.heldFor = set.heldFor + elapsed
        if set.heldFor >= set.nextRepeat then
            set.nextRepeat = set.heldFor + REPEAT_EVERY
            handleDown(key, true)
        end
    end)
    ---The buttons bound now: these (nil: none), the others let go of.
    function set.setKeys(wanted)
        set.wantedKeys = {}
        for _, key in ipairs(wanted or {}) do
            if set.buttons[key] then
                set.wantedKeys[key] = true
            end
        end
        if not canBind() then
            return -- (once the fight is over: rebind)
        end
        local hasLetGo = false
        for key in pairs(set.boundKeys) do
            if not set.wantedKeys[key] then
                set.boundKeys[key] = nil
                hasLetGo = true
            end
        end
        if hasLetGo then
            ClearOverrideBindings(set.owner)
            for key in pairs(set.boundKeys) do
                applyKey(key)
            end
        end
        for key in pairs(set.wantedKeys) do
            if not set.boundKeys[key] then
                set.boundKeys[key] = true
                applyKey(key)
            end
        end
    end
    function set.isBound(key)
        return set.boundKeys[key] == true
    end
    function set.rebind()
        local wanted = {}
        for key in pairs(set.wantedKeys) do
            wanted[#wanted + 1] = key
        end
        set.setKeys(wanted)
    end
    local index = #padSets + 1
    for at, other in ipairs(padSets) do
        if other.rank > rank then
            index = at
            break
        end
    end
    table.insert(padSets, index, set)
    return set
end

---------------------------------------------------------------------------------------------------------------
-- The cursor's look and the prompts: the game's own art, drawn by OneMoreQuest

---@return Frame pointer The game's pointing hand, bobbing beside the control it is put on (Gamepad.placePointer)
function Gamepad.makePointer(parent)
    local pointer = CreateFrame("Frame", nil, parent)
    pointer:SetSize(32, 32)
    pointer:SetFrameStrata("FULLSCREEN_DIALOG")
    if pointer.SetFixedFrameStrata then
        pointer:SetFixedFrameStrata(true) -- (kept over the window and the map when the window's strata changes)
    end
    pointer:EnableMouse(false)
    local hand = pointer:CreateTexture(nil, "ARTWORK")
    hand:SetAtlas("gamepad-largecursor-white", true)
    hand:SetPoint("LEFT", pointer, "LEFT", 0, 0)
    if hand.SetScale then
        pcall(hand.SetScale, hand, 0.8)
    end
    local color = GAMEPAD_SMARTNAV_CURSOR_COLOR
    if type(color) == "table" and color.GetRGBA then
        hand:SetVertexColor(color:GetRGBA())
    end
    pointer.hand = hand
    pcall(function()
        local bob = pointer:CreateAnimationGroup()
        bob:SetLooping("REPEAT")
        for order, offset in ipairs({ 4, -4 }) do
            local move = bob:CreateAnimation("Translation")
            move:SetOffset(offset, 0)
            move:SetDuration(1)
            move:SetOrder(order)
            if move.SetSmoothing then
                move:SetSmoothing("IN_OUT")
            end
        end
        bob:Play()
    end)
    pointer:Hide()
    return pointer
end

---The hand beside a control, pointing at it (where the game's own cursor stands), or put away.
function Gamepad.placePointer(pointer, button)
    if not button then
        pointer:Hide()
        return
    end
    pointer:ClearAllPoints()
    pointer:SetPoint("RIGHT", button, "LEFT", 10, 0)
    pointer:Show()
end

local STRIP_PADDING, PROMPT_GAP, ICON_SIZE, DIVIDER_SIZE, ICON_GAP = 10, 15, 24, 16, 4 -- (the game's legend's)

---@return string? atlas The game's icon of a pad button (or a divider: "SLASH"), for the pad in use
local function getInputAtlas(key)
    local utility = type(InputIconTextureSetUtility) == "table" and InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture
    local atlas = utility and key and utility(key)
    return type(atlas) == "string" and atlas ~= "" and atlas or nil
end

---@return Frame strip A line of prompts as the game's own prompt bar draws them under its windows (its slot and frame,
---each pad button's icon and what it does, two buttons with a slash between): strip.setPrompts
function Gamepad.makePromptStrip(parent)
    local strip = CreateFrame("Frame", nil, parent)
    strip:SetSize(10, ICON_SIZE + 2 * STRIP_PADDING)
    strip:EnableMouse(false)
    strip:SetClampedToScreen(true) -- (never cut off at the screen's edge, under a window or the tracker standing there)
    local slot = strip:CreateTexture(nil, "BACKGROUND")
    slot:SetAllPoints(strip)
    slot:SetAtlas("gamepad-footer-slot-bg")
    local border = strip:CreateTexture(nil, "BORDER")
    border:SetAllPoints(strip)
    border:SetAtlas("gamepad-footer-slot-frameneutral")
    local items = {} -- the prompts' parts, made as more are wanted: { icons = { texture, texture }, divider, text }
    local function getItem(index)
        local item = items[index]
        if not item then
            item = { icons = {} }
            for iconIndex = 1, 2 do
                local icon = strip:CreateTexture(nil, "ARTWORK")
                icon:SetSize(ICON_SIZE, ICON_SIZE)
                item.icons[iconIndex] = icon
            end
            item.divider = strip:CreateTexture(nil, "ARTWORK")
            item.divider:SetSize(DIVIDER_SIZE, DIVIDER_SIZE)
            item.text = ns.Widgets.createFontString(strip, "OVERLAY", "GameFontNormal")
            -- A press-and-hold's marks, as the game's own icons have them: the "hold" ring on the button, and while it
            -- is held the load bar running round it (InputIconTextureFrameTemplate)
            local function addHoldTexture(atlas, layer)
                local texture = strip:CreateTexture(nil, layer)
                texture:SetAtlas(atlas)
                texture:SetAllPoints(item.icons[1])
                texture:Hide()
                return texture
            end
            item.holdBG = addHoldTexture("gamepad-press&hold-indicator-BG", "BACKGROUND")
            item.holdRing = addHoldTexture("gamepad-press&hold-indicator", "OVERLAY")
            item.loadBG = addHoldTexture("gamepad-press&hold-loadBar-BG", "BACKGROUND")
            item.loadBar = addHoldTexture("gamepad-press&hold-loadBar", "OVERLAY")
            if item.loadBar.SetRotation then
                item.loadBar:SetRotation(math.pi)
            end
            pcall(function()
                local group = item.loadBar:CreateAnimationGroup()
                local fill = group:CreateAnimation("RadialProgress")
                fill:SetFromPercent(0)
                fill:SetToPercent(1)
                item.loadAnim, item.loadFill = group, fill
            end)
            item.text:SetJustifyH("LEFT")
            items[index] = item
        end
        return item
    end
    ---@param prompts table[] { key = "PAD1" (or keys = { "PADLSHOULDER", "PADRSHOULDER" }), label = "Select" }
    function strip.setPrompts(prompts)
        local parts = {}
        for _, prompt in ipairs(prompts) do
            parts[#parts + 1] = table.concat(prompt.keys or { prompt.key }, "+") .. "=" .. tostring(prompt.label)
        end
        local line = table.concat(parts, "|")
        if line == strip.line then
            strip:SetShown(#prompts > 0)
            return
        end
        strip.line = line
        local x = STRIP_PADDING
        for index, prompt in ipairs(prompts) do
            local item = getItem(index)
            local keys = prompt.keys or { prompt.key }
            for iconIndex, icon in ipairs(item.icons) do
                local atlas = keys[iconIndex] and getInputAtlas(keys[iconIndex])
                icon:SetShown(atlas ~= nil)
                if atlas then
                    icon:SetAtlas(atlas)
                end
            end
            local first, second = item.icons[1], item.icons[2]
            first:ClearAllPoints()
            first:SetPoint("LEFT", strip, "LEFT", x, 0)
            local right = first
            x = x + (first:IsShown() and ICON_SIZE or 0)
            local dividerAtlas = second:IsShown() and getInputAtlas(GAMEPAD_PROMPT_DIVIDER_SLASH or "SLASH")
            item.divider:SetShown(dividerAtlas ~= nil and dividerAtlas ~= false)
            if dividerAtlas then
                item.divider:SetAtlas(dividerAtlas)
                item.divider:ClearAllPoints()
                item.divider:SetPoint("LEFT", first, "RIGHT", ICON_GAP, 0)
                x = x + ICON_GAP + DIVIDER_SIZE
                right = item.divider
            end
            if second:IsShown() then
                second:ClearAllPoints()
                second:SetPoint("LEFT", right, "RIGHT", ICON_GAP, 0)
                x = x + ICON_GAP + ICON_SIZE
                right = second
            end
            if item.isHolding and item.key ~= keys[1] then
                -- (the hold's ring was on another button: this slot is another prompt now)
                item.isHolding = false
                if item.loadAnim then
                    item.loadAnim:Stop()
                end
                if item.sweep then
                    item.sweep:Hide()
                end
                item.loadBG:Hide()
                item.loadBar:Hide()
            end
            item.key = keys[1]
            item.isHold = prompt.isHold == true
            item.holdBG:SetShown(item.isHold and not item.isHolding)
            item.holdRing:SetShown(item.isHold and not item.isHolding)
            item.text:SetText(prompt.label)
            item.text:ClearAllPoints()
            item.text:SetPoint("LEFT", right, "RIGHT", ICON_GAP, 0)
            item.text:Show()
            x = x + ICON_GAP + (item.text:GetStringWidth() or 0) + PROMPT_GAP
        end
        for index = #prompts + 1, #items do
            local item = items[index]
            item.icons[1]:Hide()
            item.icons[2]:Hide()
            item.divider:Hide()
            item.text:Hide()
            item.holdBG:Hide()
            item.holdRing:Hide()
            item.loadBG:Hide()
            item.loadBar:Hide()
            item.key, item.isHold = nil, false
        end
        strip:SetWidth(math.max(10, x - PROMPT_GAP + STRIP_PADDING))
        strip:SetShown(#prompts > 0)
    end
    ---A press-and-hold begun on a prompt's button: its load bar runs round it for the hold's length (the game's own
    ---ring; a cooldown's sweep where this client has no ring to run)
    function strip.beginHold(key, seconds)
        for _, item in ipairs(items) do
            if item.key == key and item.isHold and item.text:IsShown() then
                item.isHolding = true
                item.holdBG:Hide()
                item.holdRing:Hide()
                item.loadBG:Show()
                item.loadBar:Show()
                if item.loadAnim then
                    item.loadFill:SetDuration(seconds)
                    item.loadAnim:Stop()
                    item.loadAnim:Play()
                else
                    if not item.sweep then
                        item.sweep = CreateFrame("Cooldown", nil, strip, "CooldownFrameTemplate")
                        item.sweep:SetAllPoints(item.icons[1])
                        if item.sweep.SetReverse then
                            item.sweep:SetReverse(true)
                        end
                    end
                    item.loadBar:Hide()
                    item.sweep:SetCooldown(GetTime(), seconds)
                    item.sweep:Show()
                end
            end
        end
    end
    ---The hold over (let go of, or held to its end): the button as before
    function strip.endHold(key)
        for _, item in ipairs(items) do
            if item.key == key and item.isHolding then
                item.isHolding = false
                if item.loadAnim then
                    item.loadAnim:Stop()
                end
                if item.sweep then
                    item.sweep:Hide()
                end
                item.loadBG:Hide()
                item.loadBar:Hide()
                item.holdBG:SetShown(item.isHold)
                item.holdRing:SetShown(item.isHold)
            end
        end
    end
    strip:Hide()
    return strip
end

---------------------------------------------------------------------------------------------------------------
-- Where things are

---@return number? left
---@return number? right
---@return number? top
---@return number? bottom In the screen's units
local function getRect(frame)
    if frame.isRect then
        return frame.left, frame.right, frame.top, frame.bottom
    end
    local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    if not (left and right and top and bottom) then
        return nil
    end
    local scale = frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    return left * scale, right * scale, top * scale, bottom * scale
end
Gamepad.getRect = getRect

---@return boolean isInside The frame is the other one, or inside it
local function isInside(frame, other)
    while frame do
        if frame == other then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end

---@return table? canvas The scrolled drawing the control is in: the list's or the page's
local function getCanvasOf(button)
    for _, canvas in ipairs({ ns.Log.getListCanvas(), ns.Log.getPageCanvas() }) do
        if canvas and canvas.content and isInside(button, canvas.content) then
            return canvas
        end
    end
    return nil
end

---@return boolean isInView The control shows: in its drawing's view, if it is in one
local function isInView(button)
    if not button or not button:IsVisible() then
        return false
    end
    local canvas = getCanvasOf(button)
    if not canvas then
        return true
    end
    local _, _, top, bottom = getRect(button)
    local _, _, viewTop, viewBottom = getRect(canvas.frame)
    if not (top and viewTop) then
        return false
    end
    local middle = (top + bottom) / 2
    return middle <= viewTop and middle >= viewBottom
end
Gamepad.isInView = isInView

---Scrolls the control's drawing so it is in view (with a margin round it), as walking down a list scrolls it.
local function bringIntoView(button)
    local canvas = button and getCanvasOf(button)
    local contentTop, buttonTop = canvas and canvas.content:GetTop(), button and button:GetTop()
    if contentTop and buttonTop and canvas.scrollIntoView then
        local top = contentTop - buttonTop
        canvas:scrollIntoView(top, top + (button:GetHeight() or 0))
    end
end

---@return Frame? stop The nearest of the stops in a direction from a control ("up", "down", "left", "right"): ahead
---of it, the nearer the better, and on its line (its column) before any off it
function Gamepad.findInDirection(from, direction, stops)
    local fromLeft, fromRight, fromTop, fromBottom = getRect(from)
    if not fromLeft then
        return nil
    end
    local fromX, fromY = (fromLeft + fromRight) / 2, (fromTop + fromBottom) / 2
    local isVertical = direction == "up" or direction == "down"
    local best, bestScore
    for _, stop in ipairs(stops) do
        local left, right, top, bottom = getRect(stop)
        if stop ~= from and left then
            local x, y = (left + right) / 2, (top + bottom) / 2
            local ahead, gap, offset
            -- (ahead: its middle past the control's edge that way; a button inside a row is not beside the row)
            if direction == "down" then
                ahead = y <= fromBottom and fromY - y
            elseif direction == "up" then
                ahead = y >= fromTop and y - fromY
            elseif direction == "right" then
                ahead = x >= fromRight and x - fromX
            else
                ahead = x <= fromLeft and fromX - x
            end
            if ahead then
                if isVertical then
                    gap, offset = math.max(0, left - fromRight, fromLeft - right), math.abs(x - fromX)
                else
                    gap, offset = math.max(0, bottom - fromTop, fromBottom - top), math.abs(y - fromY)
                end
                local score = ahead + gap * (isVertical and 2 or 4) + offset * 0.1
                if not bestScore or score < bestScore then
                    best, bestScore = stop, score
                end
            end
        end
    end
    return best
end

---------------------------------------------------------------------------------------------------------------
-- The window's stops: what the cursor may stand on

---@return boolean isStop The frame takes the pad's A: a button, a box to type in, a slider
local function isStopFrame(frame)
    if frame.padSkip or not (frame:IsObjectType("Button") or frame:IsObjectType("EditBox") or frame:IsObjectType("Slider")) then
        return false
    end
    if frame.IsMouseEnabled and not frame:IsMouseEnabled() then
        return false
    end
    return (frame:GetWidth() or 0) > 1 and (frame:GetHeight() or 0) > 1
end

---@return table excluded The window's frames the cursor passes over: the tabs (LB/RB), the page's buttons (Y), the
---close and back buttons (B), the scroll bars (the right stick), the drawings' marks and faces, the rewards with
---nothing more to tell than their amount, the quests worth dropping's Abandon (the row's menu)
local function getPassedOver(window)
    local excluded = {}
    for _, tab in ipairs(window.tabs or {}) do
        excluded[tab] = true
    end
    local others = { window.bar, ns.Log.getPageHeaderBackButton(), state.prompts, state.pointer }
    for index = 1, 4 do
        if others[index] then
            excluded[others[index]] = true
        end
    end
    for _, button in ipairs(ns.WindowBorder.getCloseButtons and ns.WindowBorder.getCloseButtons() or {}) do
        excluded[button] = true
    end
    for _, icon in ipairs(ns.Log.getRewardIcons()) do
        if icon.item == nil then
            excluded[icon] = true
        end
    end
    for _, row in ipairs(ns.Log.getDropRows()) do
        if row.abandonButton then
            excluded[row.abandonButton] = true
        end
    end
    for _, canvas in ipairs({ ns.Log.getListCanvas(), ns.Log.getPageCanvas() }) do
        if canvas and canvas.frame and canvas.frame.ScrollBar then
            excluded[canvas.frame.ScrollBar] = true
        end
        for name, pool in pairs(canvas and canvas.pools or {}) do
            local first = pool[1]
            if name ~= "buttons" and type(first) == "table" and first.IsObjectType and first:IsObjectType("Frame") then
                for _, piece in ipairs(pool) do
                    excluded[piece] = true
                end
            end
        end
    end
    return excluded
end

local function collectStops(frame, excluded, stops)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsShown() and not excluded[child] then
            if isStopFrame(child) then
                stops[#stops + 1] = child
            end
            collectStops(child, excluded, stops)
        end
    end
end

---@return Frame[] stops Every control of the window the cursor may stand on now
local function getStops()
    local window = ns.Log.getWindow()
    local stops = {}
    if window and window:IsVisible() then
        collectStops(window, getPassedOver(window), stops)
    end
    return stops
end
Gamepad.getStops = getStops

---@return boolean isInWindow The frame is a control of the window, shown
local function isShownInWindow(frame)
    local window = ns.Log.getWindow()
    return frame ~= nil and frame:IsVisible() == true and isInside(frame, window)
end

---@return boolean isInList The frame is in the quest list
local function isInList(frame)
    local canvas = ns.Log.getListCanvas()
    return frame ~= nil and canvas ~= nil and isInside(frame, canvas.frame)
end

---@return number width The width from which a list's button is a whole row (narrower ones are its icons)
local function getRowWidth()
    local canvas = ns.Log.getListCanvas()
    return (canvas and canvas.width or 300) / 2
end

---------------------------------------------------------------------------------------------------------------
-- The quest under the cursor, and X on it

---@return number? questId The quest of the row under the cursor (its title or any button in it)
---@return boolean isInLog It is one of the player's quests
local function getCursorQuest()
    local button = state.cursor
    if not button or ns.Log.getView() ~= "quests" then
        return nil, false -- (the settings' and the chronicle's rows are sections, chapters and days)
    end
    -- A quest's own row (or one worth dropping) only: other rows carry numbers too (a dungeon's, negative; a zone's)
    local questId = (button.isQuestRow or button.isDropSuggestion) and type(button.data) == "number" and button.data or nil
    if button == ns.Log.getPageTitleButton() then
        questId = button:GetParent() and button:GetParent().questId -- the page's title: its quest
    end
    local open = ns.Log.getOpenRowData()
    if not questId and ns.Log.isInPage(button) and type(open) == "number" and open > 0 then
        questId = open -- anywhere on the page: the quest it is about
    end
    if not questId or questId <= 0 then
        return nil, false
    end
    local isInLog = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questId) ~= nil
    return questId, isInLog == true
end

---@return number? questId The quest under the cursor, when it is one of the player's (only those can be focused)
local function getCursorQuestId()
    local questId, isInLog = getCursorQuest()
    return isInLog and questId or nil
end

local HOLD_SECONDS = 0.5 -- how long X is held to focus rather than track (the game's own holds are about as long)

local function focusCursorQuest()
    local questId = getCursorQuestId()
    if questId and ns.Log.focusQuest then
        ns.Log.focusQuest(questId)
    end
end

local function trackCursorQuest()
    local questId = getCursorQuestId()
    if questId and ns.LogActions and ns.LogActions.toggleTracked then
        ns.LogActions.toggleTracked(questId)
    end
end

---@return string? kind What X does on the row under the cursor on the other tabs: "giver" (a quest to pick up, on
---Available) or "entrance" (a dungeon); nil elsewhere
---@return Button? row
local function getPlaceRow()
    local button = state.cursor
    if not button or not isInList(button) or type(button.data) ~= "number" or (button:GetWidth() or 0) < getRowWidth() then
        return nil, nil
    end
    if ns.Log.isShowingAvailable() and button.isQuestRow and not ns.QuestState.isInLog(button.data) then
        return "giver", button
    elseif ns.Log.isShowingDungeons() and button.data < 0 then
        return "entrance", button
    end
    return nil, nil
end

---X on Available or Dungeons: the row's quest giver, or its dungeon's entrance, on the map, as the page's own button
---shows it (the row opened first, the list staying where it is).
local function showRowPlace()
    local kind, row = getPlaceRow()
    local window = ns.Log.getWindow()
    if not kind or not window then
        return
    end
    if row.data ~= ns.Log.getOpenRowData() then
        row:Click("LeftButton")
    end
    local button = kind == "giver" and window.mapButton or window.entranceButton
    if button and button.Click then
        button:Click()
    end
end

---@return string label What X does on the quest under the cursor: "Track · hold: Focus", in the words that fit it now
local function getQuestActionLabel()
    local questId = getCursorQuestId()
    if not questId then
        return ns.L("Track")
    end
    local track = ns.L(ns.QuestState.isWatched(questId) and "Untrack" or "Track")
    local focus = ns.L(questId == ns.Focus.get() and "Unfocus" or "Focus")
    return ns.L("%s · hold: %s", track, focus)
end

local holdTimer
local function startHold()
    if holdTimer then
        holdTimer:Cancel()
    end
    state.isXDown = true
    if state.prompts then
        state.prompts.beginHold("PAD3", HOLD_SECONDS) -- (X's load bar runs round it, as the game's holds show)
    end
    holdTimer = C_Timer.NewTimer(HOLD_SECONDS, function()
        holdTimer = nil
        if state.prompts then
            state.prompts.endHold("PAD3")
        end
        focusCursorQuest()
        Gamepad.refreshPrompts()
    end)
end

---X's hold dropped with no doing (the window let go of the pad meanwhile): neither tracked nor focused.
local function cancelHold()
    state.isXDown = false
    if holdTimer then
        holdTimer:Cancel()
        holdTimer = nil
    end
    if state.prompts then
        state.prompts.endHold("PAD3")
    end
end

local function endHold()
    if not state.isXDown then
        return false
    end
    state.isXDown = false
    if state.prompts then
        state.prompts.endHold("PAD3")
    end
    if holdTimer then
        holdTimer:Cancel()
        holdTimer = nil
        trackCursorQuest()
    end
    return true
end

---------------------------------------------------------------------------------------------------------------
-- Y: the row's menu, or the page's buttons

---@return Button[] buttons The buttons at the page's foot that are shown now, Abandon last (they change with the
---quest, the tab and the view: Track, Focus, Share, Show giver, Track all here, Show entrance...)
local function getPageActions()
    local window = ns.Log.getWindow()
    local bar = window and window.bar
    local actions, abandon = {}, nil
    for _, child in ipairs(bar and { bar:GetChildren() } or {}) do
        local text = child:IsShown() and child.GetText and child:GetText()
        -- (Done and the journal's Back are B's)
        local isBack = child == window.doneButton or child == window.journalBackButton
        if type(text) == "string" and text ~= "" and child.Click and not isBack then
            if child == window.abandonButton then
                abandon = child
            else
                actions[#actions + 1] = child
            end
        end
    end
    actions[#actions + 1] = abandon
    return actions
end

---@return boolean hasOwnMenu The control under the cursor has a menu of its own: its right click, or the quest of
---a row in the list
local function hasOwnMenu(button)
    -- (a quest worth dropping, in its own window, has the quest's menu too: Abandon is there)
    return button ~= nil and (button.handleRightClick ~= nil or ((isInList(button) or button.isDropSuggestion) and getCursorQuest() ~= nil))
end

---@return boolean isSections The window shows the settings or the chronicle: sections (chapters) down the list's side,
---the one chosen on the page
local function isSectionView()
    local view = ns.Log.getView()
    return view == "settings" or view == "chronicle"
end

---@return boolean isOptions Y opens the page's buttons as a menu (the cursor on the page, or anywhere in the settings,
---on nothing with a menu)
local function isOptionsMenu()
    local button = state.cursor
    return button ~= nil and (ns.Log.isInPage(button) or isSectionView()) and not hasOwnMenu(button) and #getPageActions() > 0
end

---The page's buttons as a menu at the cursor, Abandon in red, each as the button itself would be clicked.
local function openPageOptions()
    local actions = getPageActions()
    local window = ns.Log.getWindow()
    if #actions == 0 or not window then
        return
    end
    ns.openMenu(state.cursor or window, function(_, root)
        for _, button in ipairs(actions) do
            local text = button:GetText()
            if button == window.abandonButton and RED_FONT_COLOR and RED_FONT_COLOR.WrapTextInColorCode then
                text = RED_FONT_COLOR:WrapTextInColorCode(text)
            end
            local entry = root:CreateButton(text, function() button:Click() end)
            if button.IsEnabled and not button:IsEnabled() and entry and entry.SetEnabled then
                entry:SetEnabled(false)
            end
        end
    end)
end

---Y: the menu of the control under the cursor (a row's right-click: focus, track, share, abandon...), or on the page
---the page's buttons.
local function openCursorMenu()
    if isOptionsMenu() then
        openPageOptions()
        return
    end
    local button = state.cursor
    if button and button.handleRightClick and button.Click then
        button:Click("RightButton")
        return
    end
    local questId, isInLog = getCursorQuest()
    local Log = ns.Log
    if questId and isInLog and Log.openLogQuestMenu then
        Log.openLogQuestMenu(questId)
    elseif questId and Log.openAvailableQuestMenu then
        Log.openAvailableQuestMenu(questId)
    end
end

---@return boolean hasMenu Y has a menu to open
local function hasCursorMenu()
    return hasOwnMenu(state.cursor) or isOptionsMenu()
end

---------------------------------------------------------------------------------------------------------------
-- The cursor

---The control the cursor leaves: its hover undone (its highlight, its tooltip).
local function leave(button)
    if button.UnlockHighlight then
        pcall(button.UnlockHighlight, button)
    end
    local onLeave = button:GetScript("OnLeave")
    if onLeave then
        pcall(onLeave, button)
    end
end

---The control the cursor comes onto: hovered, as the mouse would (its highlight, its tooltip).
local function enter(button)
    if button.LockHighlight then
        pcall(button.LockHighlight, button)
    end
    local onEnter = button:GetScript("OnEnter")
    if onEnter then
        pcall(onEnter, button, false)
    end
end

local REST_SECONDS = 0.15 -- with a d-pad button held (the cursor running down the list), how long it rests on a row
-- before the row shows: a press shows it at once

---@return boolean isShown The list's row is what the page beside it shows now: the quest open, the section chosen
local function isRowOnPage(button)
    if isSectionView() then
        return ns.Log.isChosenSectionRow(button.data)
    end
    return button.data == ns.Log.getOpenRowData()
end

---@return Button? row The list's shown row with this data (a quest, a section), whichever of its buttons draws it now
local function findListButton(data, isQuest)
    local canvas = ns.Log.getListCanvas()
    local pool = canvas and canvas.pools and canvas.pools.buttons
    for index = 1, pool and pool.usedCount or 0 do
        local button = pool[index]
        if button.data == data and button:IsVisible() and (not isQuest or button.isQuestRow) then
            return button
        end
    end
    return nil
end

local setCursor

---The row shown on the page, as a click shows it; the list drawn anew may draw it with another of its buttons: the
---cursor stays with the row.
local function showRow(button)
    local data, isQuest = button.data, button.isQuestRow == true
    button:Click("LeftButton")
    if state.cursor == button and button.data ~= data then
        setCursor(findListButton(data, isQuest) or button)
    end
end

---The cursor coming onto a row of the list (a quest; in the settings or the chronicle a section): it shows on the page
---beside it (as a click shows it), so walking down the list shows each without pressing A, as the mouse's window shows
---the quest clicked; with the d-pad held, once the cursor rests on it. Zones' headings and other rows are left to A.
local function showSectionOnRest(button)
    local isQuest = not isSectionView() and button.isQuestRow == true and type(button.data) == "number"
    if not (isSectionView() or isQuest) or not isInList(button) or isRowOnPage(button) then
        return
    end
    state.restToken = (state.restToken or 0) + 1
    if not state.isRepeatMove then
        showRow(button) -- (one press: at once)
        return
    end
    local token, data = state.restToken, button.data
    C_Timer.After(REST_SECONDS, function()
        if token == state.restToken and state.cursor == button and button.data == data and button:IsVisible()
            and not isRowOnPage(button) then
            showRow(button)
        end
    end)
end

local updateKeys

---Puts the cursor on a control of the window, in view, hovered; nil takes it away.
setCursor = function(button)
    if state.cursor and state.cursor ~= button then
        leave(state.cursor)
    end
    local isNew = state.cursor ~= button
    state.cursor = button
    if button then
        if not state.isStickMove then
            bringIntoView(button) -- (the right stick scrolls the list itself: left as it is)
        end
        if isNew then
            enter(button)
            if isInList(button) and button.isQuestRow then
                state.lastRowData = button.data -- the row B brings the cursor back to from the page
            end
            showSectionOnRest(button)
        end
    end
    local cursor = state.cursor -- (the row shown may have moved it onto another of the list's buttons: showRow)
    if state.pointer then
        Gamepad.placePointer(state.pointer, state.isActive and cursor and isInView(cursor) and cursor or nil)
    end
    if state.isActive then
        updateKeys()
        Gamepad.refreshPrompts()
    end
end
Gamepad.setCursor = setCursor

---@return Button? button The cursor's control (for tests and the map's marks)
function Gamepad.getCursor()
    return state.cursor
end

---@return boolean hasPad The window has the pad now (its cursor shows)
function Gamepad.hasPad()
    return state.isActive == true
end

---------------------------------------------------------------------------------------------------------------
-- Where the cursor goes: the list's open quest, the page's first control

---@return Button? button The list's row of the quest open on the page, else of its first quest: where the cursor
---starts, and where B brings it back from the page
---@param wanted any The row's data (a quest); nil for the quest open on the page
---@param isExact boolean? Only that row: no first row in its place
local function findListRow(wanted, isExact)
    local canvas = ns.Log.getListCanvas()
    local pool = canvas and canvas.pools and canvas.pools.buttons
    if not pool then
        return nil
    end
    if wanted == nil then
        wanted = ns.Log.getOpenRowData()
    end
    local rowWidth = getRowWidth()
    local firstRow
    for index = 1, pool.usedCount or 0 do
        local button = pool[index]
        -- A quest's own row (not a suggestion of the drop panel above the list, which has the same quest), or a
        -- row of another kind (a dungeon, a place to pick)
        local isRow = button.isQuestRow or (button.data ~= nil and type(button.data) ~= "number") or (type(button.data) == "number" and button.data < 0)
        if isRow and button:IsVisible() and (button:GetWidth() or 0) >= rowWidth then
            if button.data == wanted then
                return button
            end
            firstRow = firstRow or (button.isQuestRow and button)
        end
    end
    return not isExact and firstRow or nil
end

---@return Button? row The list's row to come back to from the page: the quest open on the page, else the quest row
---the cursor last stood on in the list. A quest of the log whose row is not drawn (its zone folded, filtered out) is
---opened again from the list, which unfolds it and brings it into view.
local function findReturnRow()
    local open = ns.Log.getOpenRowData()
    local row = findListRow(open, true) or (state.lastRowData ~= nil and findListRow(state.lastRowData, true))
    if row then
        return row
    end
    for _, questId in ipairs({ open, state.lastRowData }) do
        if type(questId) == "number" and ns.Log.isShowingQuests() and ns.QuestState.isInLog(questId) then
            ns.Log.selectQuest(questId)
            row = findListRow(questId, true)
            if row then
                return row
            end
        end
    end
    return findListRow()
end

---Scrolls the list so a row stands in the middle of it.
local function centerRow(row)
    local canvas = getCanvasOf(row)
    local contentTop, rowTop = canvas and canvas.content:GetTop(), row:GetTop()
    local viewHeight = canvas and canvas.frame:GetHeight()
    if contentTop and rowTop and viewHeight and canvas.setScroll then
        canvas:setScroll((contentTop - rowTop) - (viewHeight - (row:GetHeight() or 0)) / 2)
    end
end

---A quest opened from the map (the map's cursor, A): its row in the middle of the list and highlighted, the window's
---cursor on it, there when the window takes the pad again (the map's own d-pad right). Its zone folded, opened.
function Gamepad.showRowInList(data, isRetry)
    if not Gamepad.isGamepadUI() then
        return
    end
    local row = findListRow(data, true)
    if not row and type(data) == "number" and ns.Log.isShowingQuests() and ns.QuestState.isInLog(data) then
        ns.Log.selectQuest(data) -- (unfolds its zone)
        row = findListRow(data, true)
    end
    if not row then
        if not isRetry and C_Timer then
            C_Timer.After(0, function() Gamepad.showRowInList(data, true) end) -- (the list drawn the next frame)
        end
        return
    end
    centerRow(row)
    state.hasPlacedCursor = true
    state.lastRowData = data
    if state.isActive then
        state.isStickMove = true -- (centred already: not scrolled again to its edge)
        setCursor(row)
        state.isStickMove = false
    else
        if state.cursor and state.cursor ~= row and state.cursor.UnlockHighlight then
            pcall(state.cursor.UnlockHighlight, state.cursor)
        end
        state.cursor = row -- (entered as the window takes the pad: its tooltip then, not over the map now)
        if row.LockHighlight then
            pcall(row.LockHighlight, row)
        end
    end
end

---@return Button? button The first control of a canvas in view, from the top left
local function findFirstControl(canvas)
    local pool = canvas and canvas.pools and canvas.pools.buttons
    local view = canvas and canvas.frame
    local viewTop, viewBottom = view and view:GetTop(), view and view:GetBottom()
    if not pool or not viewTop or not viewBottom then
        return nil
    end
    local best, bestTop
    for index = 1, pool.usedCount or 0 do
        local button = pool[index]
        local top, bottom = button:GetTop(), button:GetBottom()
        if button:IsVisible() and not button.padSkip and top and bottom and top <= viewTop + 1 and bottom >= viewBottom - 1
            and (not bestTop or top > bestTop + 1 or (math.abs(top - bestTop) <= 1 and (button:GetLeft() or 0) < (best:GetLeft() or 0))) then
            best, bestTop = button, top
        end
    end
    return best
end

---@return Frame? stop Where A on the open quest takes the cursor: the page's first control in view; else the details'
---top one anywhere (their header's title or buttons, the page, the rewards), so A always goes into the details
local function findPageStart()
    local first = findFirstControl(ns.Log.getPageCanvas())
    if first then
        return first
    end
    local best, bestTop
    for _, stop in ipairs(getStops()) do
        local _, _, top = getRect(stop)
        if top and ns.Log.isInPage(stop) and (not bestTop or top > bestTop + 1) then
            best, bestTop = stop, top
        end
    end
    return best
end

---@return Button? button A canvas's shown button with this data (its first, from the top)
local function findCanvasButton(canvas, data)
    local pool = canvas and canvas.pools and canvas.pools.buttons
    for index = 1, pool and pool.usedCount or 0 do
        if pool[index].data == data and pool[index]:IsVisible() then
            return pool[index]
        end
    end
    return nil
end

---@return Button? row In the settings or the chronicle, the list's row of the section (chapter) on the page
local function findChosenSectionRow()
    local canvas = ns.Log.getListCanvas()
    local pool = canvas and canvas.pools and canvas.pools.buttons
    for index = 1, pool and pool.usedCount or 0 do
        local button = pool[index]
        if button:IsVisible() and ns.Log.isChosenSectionRow(button.data) then
            return button
        end
    end
    return nil
end

---@return Button? button The first of the quests worth dropping (the panel over My quests as the log fills)
local function findDropSuggestion()
    return ns.Log.getDropRows()[1] -- (in their own window, open)
end

---@return Frame? button Where the cursor starts: the open quest's row, or with its page spread the page's first
---control; else the first control the window has
local function findStart()
    local start
    if ns.Log.isPageSpread() then
        start = findPageStart() or ns.Log.getPageTitleButton()
    elseif isSectionView() then
        start = findChosenSectionRow() or findFirstControl(ns.Log.getListCanvas()) or findPageStart()
    else
        start = findListRow()
    end
    if start and start:IsVisible() then
        return start
    end
    return getStops()[1]
end

---A on a quest's row: the quest opens with its page spread over the whole window in place of the list, the cursor on
---the page's first control (B folds it back: handleBack). The quest open already is not closed, as a second click
---does with the mouse. Any other row (a zone, a dungeon, a place to pick) is pressed as the mouse presses it.
local function handleRowPress(button)
    if isSectionView() then
        -- A section (a chapter, a day) of the settings or the chronicle: shown already as the cursor came onto it; A
        -- goes into it, the cursor on the page's first control
        if not ns.Log.isChosenSectionRow(button.data) then
            button:Click("LeftButton")
        end
        setCursor(findPageStart() or button)
        return
    end
    if not button.isQuestRow then
        button:Click("LeftButton")
        return
    end
    local questId = button.data
    if questId ~= ns.Log.getOpenRowData() then
        button:Click("LeftButton")
    end
    if questId == ns.Log.getOpenRowData() then
        state.lastRowData = questId
        state.isPlacing = true -- (the cursor is put here, not by the drawing)
        ns.Log.setPageSpread(true)
        state.isPlacing = false
        setCursor(findPageStart() or ns.Log.getPageTitleButton())
    end
end

---After a drawing: another tab puts the cursor on its open quest's row (or its first); the settings or the chronicle
---opening put it on their first control, and closing them back on the open quest's row.
local function placeCursorAfterDrawing()
    local view = ns.Log.getView()
    local hasViewChanged = state.drawnView ~= nil and state.drawnView ~= view
    state.drawnView = view
    local wantsDrop = ns.Log.takeDropFocusWish()
    if not state.isActive or state.isPlacing then
        state.placeAfterDrawing = false
        return
    end
    local cursor = state.cursor
    if wantsDrop then
        setCursor(findDropSuggestion() or findListRow())
    elseif not isShownInWindow(cursor) and not hasViewChanged and isSectionView() then
        -- In the settings or the chronicle, what the cursor was on went with the page drawn anew: its section's row
        setCursor(findChosenSectionRow() or findPageStart())
    elseif not isShownInWindow(cursor) and not hasViewChanged and not state.placeAfterDrawing then
        -- What the cursor was on is gone (a quest abandoned, a zone folded under it): the next quest worth dropping,
        -- else the open quest's row, never nothing
        setCursor(findDropSuggestion() or findStart())
    elseif hasViewChanged and view ~= "quests" then
        setCursor(findFirstControl(ns.Log.getListCanvas()) or findFirstControl(ns.Log.getPageCanvas()) or findStart())
    elseif hasViewChanged or state.placeAfterDrawing then
        setCursor(findListRow() or findStart())
    else
        setCursor(cursor) -- (in view again, the prompts for what it is now)
    end
    state.placeAfterDrawing = false
end

---LB/RB: the tab before or after, the cursor on its open quest.
local function stepTab(delta)
    if isSectionView() then
        -- The settings and the chronicle: their section (chapter) before or after, the cursor on its row
        if ns.Log.stepSection(delta) then
            setCursor(findChosenSectionRow() or state.cursor)
        end
        return
    end
    state.placeAfterDrawing = true
    ns.Log.setPageSpread(false)
    if not ns.Log.stepTab(delta) then
        state.placeAfterDrawing = false -- (at the first or the last tab: nothing drawn for it)
    end
end

---A on the page's title: the quest's link in chat (with the mouse, a shift-click; the pad has no shift).
local function pressTitle(button)
    local questId = button:GetParent() and button:GetParent().questId
    if questId then
        ns.QuestState.linkInChat(questId)
    end
end

---A: the control under the cursor pressed, as the mouse presses it (a dropdown opens its menu, a box takes the
---keyboard, a list's row opens as handleRowPress says).
local function pressCursor()
    local button = state.cursor
    if not isShownInWindow(button) then
        setCursor(findStart())
        return
    end
    if button:IsObjectType("EditBox") then
        button:SetFocus()
    elseif button:IsObjectType("Slider") then
        return -- (left and right move it)
    elseif type(button.menuGenerator) == "function" then
        ns.GamepadMenu.openDropdown(button)
    elseif button == ns.Log.getPageTitleButton() then
        pressTitle(button)
    elseif isInList(button) and button:GetParent() == ns.Log.getListCanvas().content then
        handleRowPress(button)
    elseif button.Click then
        button:Click("LeftButton")
    end
end

---d-pad left or right on a slider: its value a step that way.
local function stepSlider(slider, delta)
    local low, high = slider:GetMinMaxValues()
    local step = slider.GetValueStep and slider:GetValueStep() or 0
    if not step or step <= 0 then
        step = ((high or 1) - (low or 0)) / 20
    end
    slider:SetValue(math.max(low or 0, math.min(high or 1, (slider:GetValue() or 0) + delta * step)))
end

local DIRECTIONS = { PADDUP = "up", PADDDOWN = "down", PADDLEFT = "left", PADDRIGHT = "right" }

---@return table? from Where a move starts: the cursor, or with it scrolled out of view the edge of its drawing's view
---the move goes in from (the right stick scrolled the list on: down goes to the first row in view)
local function getMoveStart(direction)
    local cursor = state.cursor
    if not isShownInWindow(cursor) then
        return nil
    end
    if isInView(cursor) then
        return cursor
    end
    local canvas = getCanvasOf(cursor)
    local left, right, top, bottom = getRect(canvas.frame)
    if not left or (direction ~= "up" and direction ~= "down") then
        return cursor
    end
    local edge = direction == "down" and top + 2 or bottom - 2
    return { isRect = true, left = left, right = right, top = edge, bottom = edge }
end

local handleBack

local function moveCursor(direction)
    local from = getMoveStart(direction)
    if not from then
        setCursor(findStart())
        return
    end
    if not from.isRect and from:IsObjectType("Slider") and (direction == "left" or direction == "right") then
        stepSlider(from, direction == "left" and -1 or 1)
        return
    end
    -- d-pad right on a quest's row (a section's) is A: into its details; d-pad left in the details, with nothing more to
    -- the left in them, is B: back to its row
    if direction == "right" and not from.isRect and isInList(from) and (from.isQuestRow or isSectionView()) then
        pressCursor()
        return
    end
    local stops = getStops()
    if direction == "up" or direction == "down" then
        -- Up and down stay in the pane the cursor is in: the list (and its search and filter over it), or the details
        -- (their header, the page, the rewards); from one to the other only sideways, A and B
        local inPage = not from.isRect and ns.Log.isInPage(from)
        if from.isRect then
            inPage = getCanvasOf(state.cursor) == ns.Log.getPageCanvas()
        end
        local samePane = {}
        for _, stop in ipairs(stops) do
            if ns.Log.isInPage(stop) == inPage then
                samePane[#samePane + 1] = stop
            end
        end
        stops = samePane
    end
    local target = Gamepad.findInDirection(from, direction, stops)
    if direction == "left" and not from.isRect and ns.Log.isInPage(from) and not (target and ns.Log.isInPage(target)) then
        handleBack()
        return
    end
    if direction == "left" and not target and state.isTakenFromMap then
        state.isTakenFromMap = false -- (taken from the map, nothing to the left: the pad back to it, the next frame)
        return
    end
    if target then
        setCursor(target)
    end
end

---------------------------------------------------------------------------------------------------------------
-- B: one step back, as the game's quest log goes back (search, details, list) before it closes

---@return boolean isSearching The search box has the keyboard
local function isSearching()
    local box = ns.Log.getShownSearchBox()
    return box ~= nil and box:HasFocus() == true
end

---@return boolean canGoBack B goes back a step rather than closing the window
local function canGoBack()
    if isSearching() or ns.Log.getView() ~= "quests" or ns.Log.isPageSpread() or #ns.Log.getDropRows() > 0 then
        return true
    end
    local button = state.cursor
    return button ~= nil and ns.Log.isInPage(button) and findListRow() ~= nil
end

handleBack = function()
    ns.noteActivity("pad B (window)")
    local box = ns.Log.getShownSearchBox()
    if box and box:HasFocus() then
        box:ClearFocus()
        return
    end
    if ns.Log.closeDropWindow() then
        setCursor(findListRow() or findStart()) -- the quests worth dropping closed: back to the list
        return
    end
    if ns.Log.getView() == "chronicle" and ns.ChroniclePage.isEntryOpen() then
        -- A quest's story in the journal: back to the journal's list, the cursor on that quest
        local entry = ns.ChroniclePage.getOpenEntry()
        state.isPlacing = true
        ns.ChroniclePage.closeEntry()
        state.isPlacing = false
        setCursor(findCanvasButton(ns.Log.getPageCanvas(), entry) or findPageStart() or findChosenSectionRow())
        return
    end
    if isSectionView() and ns.Log.isInPage(state.cursor) then
        -- On a section's page: back to its row among the sections; from there B leaves the settings (the chronicle)
        local row = findChosenSectionRow()
        if row then
            setCursor(row)
            return
        end
    end
    if ns.Log.getView() == "quests" and state.cursor and (ns.Log.isInPage(state.cursor) or ns.Log.isPageSpread()) then
        -- Back to the quest in the list: the page folds back beside it, the cursor on its row, in view
        state.isPlacing = true
        ns.Log.setPageSpread(false)
        state.isPlacing = false
        local row = findReturnRow()
        if row then
            setCursor(row)
            return
        end
    end
    if ns.Log.getView() ~= "quests" or ns.Log.isAlone() then
        ns.Log.handleGamepadBack() -- the settings, the chronicle given way to the quests; alone, the window closed
    elseif state.isTakenFromMap then
        state.isTakenFromMap = false -- (taken from the map: the pad back to it, the next frame)
    end
end

---View: the search box of the open tab, to type in (with the keyboard, or the system's on-screen one).
local function focusSearch()
    local box = ns.Log.getShownSearchBox()
    if box then
        setCursor(box)
        box:SetFocus()
    end
end

---------------------------------------------------------------------------------------------------------------
-- The window's buttons and prompts

local WINDOW_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PAD1", "PAD2", "PAD3", "PAD4", "PADBACK", "PADLSHOULDER", "PADRSHOULDER" }

---@return boolean isTaken d-pad left is the window's: something to the left in it (or a slider to move, or the window
---alone); else it is the game's, which goes to the map from its quest log
local function ownsLeft()
    if ns.Log.isAlone() or state.isTakenFromMap then
        return true
    end
    local from = getMoveStart("left")
    if not from then
        return false
    end
    if not from.isRect and (from:IsObjectType("Slider") or ns.Log.isInPage(from)) then
        return true -- (a slider moves; in the details, left is B)
    end
    return Gamepad.findInDirection(from, "left", getStops()) ~= nil
end

---@return boolean isTaken B is the window's: a step to go back, or the window alone (B closes it); else the game's,
---which closes the map
local function ownsBack()
    return ns.Log.isAlone() or state.isTakenFromMap == true or canGoBack()
end

updateKeys = function()
    if not state.padButtons then
        return
    end
    if not state.isActive then
        state.padButtons.setKeys(nil)
        return
    end
    local keys = { "PADDUP", "PADDDOWN", "PADDRIGHT", "PAD1", "PAD3", "PAD4", "PADLSHOULDER", "PADRSHOULDER" }
    -- View: the search box. Docked always the window's (the game's own View would put the keyboard in its quest panel's
    -- search box, out of sight under the window); alone only while there is a search box
    if not ns.Log.isAlone() or ns.Log.getShownSearchBox() then
        keys[#keys + 1] = "PADBACK"
    end
    if ownsLeft() then
        keys[#keys + 1] = "PADDLEFT"
    end
    if ownsBack() then
        keys[#keys + 1] = "PAD2"
    end
    state.padButtons.setKeys(keys)
end

---@return table[] prompts What the pad's buttons do on the control under the cursor (the map's own prompts say the
---rest beside the docked window: World map, its B)
local function getPrompts()
    local prompts = {}
    local button = state.cursor
    if isShownInWindow(button) then
        local label = ACTION_LABEL_SELECT or ns.L("Select")
        if button.canShareWith then
            label = ns.L("Share with the party")
        elseif button.isLogFullBanner then
            label = ns.L("What to drop")
        elseif isInList(button) and button.isQuestRow then
            label = OBJECTIVES_VIEW_IN_QUESTLOG or ns.L("Details") -- (A: into its details, as the game's log says)
        end
        prompts[#prompts + 1] = { key = "PAD1", label = label }
    end
    if getCursorQuestId() then
        prompts[#prompts + 1] = { key = "PAD3", label = getQuestActionLabel(), isHold = true }
    elseif getPlaceRow() then
        prompts[#prompts + 1] = { key = "PAD3", label = ns.L(getPlaceRow() == "entrance" and "Show entrance" or "Show giver") }
    end
    if hasCursorMenu() then
        local label = isOptionsMenu() and (CONTEXT_ACTION_LABEL_OPTIONS or ns.L("Options")) or (CONTEXT_ACTION_LABEL_MORE_ACTIONS or ns.L("More actions"))
        prompts[#prompts + 1] = { key = "PAD4", label = label }
    end
    if ns.Log.getShownSearchBox() and not isSearching() then
        prompts[#prompts + 1] = { key = "PADBACK", label = SEARCH or ns.L("Search") }
    end
    if isSectionView() then
        prompts[#prompts + 1] = { keys = { "PADLSHOULDER", "PADRSHOULDER" }, label = ns.L("Sections") } -- (the tabs show their own beside them)
    end
    if not ns.Log.isAlone() and (state.isTakenFromMap or not ownsLeft()) then
        prompts[#prompts + 1] = { key = "PADDLEFT", label = WORLD_MAP or ns.L("World map") } -- (the game's own, to the map)
    end
    -- (beside the map with nothing to go back to: the game's own B, which closes the map)
    prompts[#prompts + 1] = { key = "PAD2", label = canGoBack() and (FRAME_ACTION_BACK or BACK or ns.L("Back")) or (FRAME_ACTION_CLOSE or CLOSE or ns.L("Close")) }
    return prompts
end

function Gamepad.refreshPrompts()
    if state.prompts then
        -- (a menu open says its own: Select, Back or Close)
        if state.isActive and not (ns.GamepadMenu and ns.GamepadMenu.isOpen()) then
            state.prompts.setPrompts(getPrompts())
        else
            state.prompts:Hide()
        end
    end
end

local function handlePadDown(key, isRepeat)
    if ns.GamepadMenu and ns.GamepadMenu.isOpen() then
        return -- (the menu's own buttons come first; a press that reached the window anyway is the menu's)
    end
    if DIRECTIONS[key] then
        state.isRepeatMove = isRepeat
        moveCursor(DIRECTIONS[key])
        state.isRepeatMove = false
    elseif isRepeat then
        return
    elseif key == "PAD1" then
        pressCursor()
    elseif key == "PAD2" then
        handleBack()
    elseif key == "PAD3" then
        if getCursorQuestId() then
            startHold()
        elseif getPlaceRow() then
            showRowPlace()
        end
    elseif key == "PAD4" then
        if hasCursorMenu() then
            openCursorMenu()
        end
    elseif key == "PADBACK" then
        if ns.Log.getShownSearchBox() and not isSearching() then
            focusSearch()
        end
    elseif key == "PADLSHOULDER" or key == "PADRSHOULDER" then
        stepTab(key == "PADLSHOULDER" and -1 or 1)
    end
    if state.isActive then
        updateKeys()
        Gamepad.refreshPrompts()
    end
end

local function handlePadUp(key)
    if key == "PAD3" and endHold() then
        Gamepad.refreshPrompts()
    end
end

---------------------------------------------------------------------------------------------------------------
-- When the window has the pad

---@return boolean isWanted The window has the pad now: shown in the Gamepad UI, and either alone with no window of
---the game's holding the pad, or beside the map with the map's focus on its quest log (which the window stands in for)
local function isWanted()
    local window = ns.Log.getWindow()
    if not window or not window:IsVisible() or not Gamepad.isGamepadUI() then
        return false
    end
    local focus = Gamepad.getGameFocus()
    if ns.Log.isAlone() then
        return focus == nil
    end
    local map = WorldMapFrame
    if not map or not map:IsShown() or focus ~= map or (map.IsMaximized and map:IsMaximized()) then
        state.isTakenFromMap = false
        return false
    end
    if map.currentFocus == "Quest" or map.currentFocus == "Details" then
        state.isTakenFromMap = false -- (the map's own focus is on its quest log now: the window's anyway)
        return true
    end
    return state.isTakenFromMap == true
end

---A quest opened from the map (its mark, its area: A): the window takes the pad from the map, its cursor on that quest,
---as the map's own Quests does. The map's focus stays on the map (an addon moving it taints the game: Gamepad.lua
---says why), its cursor out of sight meanwhile; d-pad left (with nothing to the left) or B (with nothing to go back
---to) give the pad back to it.
function Gamepad.takePadFromMap()
    local map = WorldMapFrame
    if Gamepad.isGamepadUI() and not ns.Log.isAlone() and map and map:IsShown() and Gamepad.getGameFocus() == map then
        state.isTakenFromMap = true
    end
end

---The game's own hand, prompts and scroll hint are left with its quest log, out of sight under the window: not shown
---over it meanwhile (the window's prompts say what the map's buttons do too). Only their alpha: nothing of the
---game's runs.
local function hideGameCursor(isHidden)
    local map = WorldMapFrame
    local parts = { type(SmartNavigation) == "table" and SmartNavigation.Pointer, _G.GamepadScrollBarHint,
        map and map.questLogFooter and map.questLogFooter.inputLegend, map and map.questDetailsFooter and map.questDetailsFooter.inputLegend }
    for index = 1, 4 do
        local part = parts[index]
        if type(part) == "table" and part.SetAlpha then
            part:SetAlpha(isHidden and 0 or 1)
        end
    end
end

---The right stick taken from the camera while the window has the pad (it scrolls the window then): a hidden frame of
---OneMoreQuest's that takes the gamepad's sticks and says the right one is handled, as the game's own stick bindings do
---(Blizzard_GamepadSharedUtility's InputAxisBinding); the left one is left to the game (the character walks). Never in
---a fight (let go of as it begins: beforeCombat).
local function takeRightStick(isTaken)
    if isTaken and (InCombatLockdown and InCombatLockdown()) then
        isTaken = false
    end
    local frame = state.stickTaker
    if not frame and isTaken then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetScript("OnGamePadStick", function(_, stick)
            return not (stick == "Camera" or stick == "Right") -- (true: unhandled, the game's)
        end)
        state.stickTaker = frame
    end
    if frame and frame.EnableGamePadStick and frame.isTaken ~= isTaken then
        frame.isTaken = isTaken
        pcall(frame.EnableGamePadStick, frame, isTaken)
    end
end

---The map's own cursor out of sight while the window has the pad taken from the map (it points at nothing then).
---Only its alpha.
local function updateSoftCursor()
    local cursor = _G.SoftCursor
    local isHidden = state.isActive and state.isTakenFromMap == true
    if type(cursor) == "table" and cursor.SetAlpha and state.isSoftCursorHidden ~= isHidden then
        state.isSoftCursorHidden = isHidden
        cursor:SetAlpha(isHidden and 0 or 1)
    end
end

local function setActive(isActive)
    if isActive == state.isActive then
        return
    end
    state.isActive = isActive
    ns.noteActivity(isActive and "gamepad: window has the pad" or "gamepad: window lets the pad go")
    takeRightStick(isActive)
    hideGameCursor(isActive and not ns.Log.isAlone())
    if isActive then
        local cursor = state.cursor
        if not state.hasPlacedCursor or not isShownInWindow(cursor) then
            -- The first time since the window opened, or what the cursor was on went meanwhile (a quest opened from
            -- the map, its page in the list's place): the open quest's row, or with its page spread the page's first
            -- control
            state.hasPlacedCursor = true
            cursor = findStart()
        end
        state.cursor = nil
        setCursor(cursor)
    else
        cancelHold()
        state.isTakenFromMap = false -- (taken from the map: over with the pad gone, whatever took it)
        if state.cursor then
            leave(state.cursor)
        end
        if state.pointer then
            state.pointer:Hide()
        end
        if state.stickHint then
            state.stickHint:Hide()
        end
        updateKeys()
        Gamepad.refreshPrompts()
    end
end

local STICK_DEAD_ZONE, STICK_SPEED = 0.25, 900 -- the right stick: pixels a second, pushed all the way

---@return number y The right stick's push up (1) or down (-1), read from the pad's state (nothing bound to it)
local function readRightStick()
    local pad = C_GamePad
    if type(pad) ~= "table" or type(pad.GetDeviceMappedState) ~= "function" then
        return 0
    end
    local mapped = pad.GetDeviceMappedState(pad.GetActiveDeviceID and pad.GetActiveDeviceID() or nil)
    if type(mapped) ~= "table" or type(mapped.sticks) ~= "table" then
        return 0
    end
    for index = 1, mapped.stickCount or #mapped.sticks do
        if pad.StickIndexToConfigName and pad.StickIndexToConfigName(index - 1) == "Camera" then
            local stick = mapped.sticks[index]
            return stick and stick.y or 0
        end
    end
    return 0
end

---@return table? canvas What the right stick scrolls: the pane the cursor is in (the list, or the quest's details
---beside it); else the details
local function getStickCanvas()
    local canvas = state.cursor and isShownInWindow(state.cursor) and getCanvasOf(state.cursor)
    if canvas then
        return canvas
    end
    local page = ns.Log.getPageCanvas()
    if page and page.frame and page.frame:IsVisible() then
        return page
    end
    return ns.Log.getListCanvas()
end

---The game's right-stick hint on the scroll bar of the pane the right stick scrolls (as the game's quest log shows it
---on its own), none where that pane does not scroll.
local function placeStickHint()
    local hint = state.stickHint
    if not hint then
        return
    end
    local canvas = state.isActive and getStickCanvas()
    local bar = canvas and canvas.frame and canvas.frame.ScrollBar
    local thumb = bar and ((bar.Track and bar.Track.Thumb) or (bar.GetThumbTexture and bar:GetThumbTexture())) or nil
    local anchor = (thumb and thumb.IsVisible and thumb:IsVisible() and thumb) or nil
    if not anchor or (canvas.maxScroll or 0) <= 0 then
        hint:Hide()
        return
    end
    if hint.anchor ~= anchor then
        hint.anchor = anchor
        hint:ClearAllPoints()
        hint:SetPoint("CENTER", anchor, "CENTER", 0, 0)
    end
    hint:Show()
end

local function makeStickHint(window)
    local hint = CreateFrame("Frame", nil, window)
    hint:SetSize(32, 32)
    hint:SetFrameLevel((window:GetFrameLevel() or 1) + 60)
    local texture = hint:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", hint, "TOPLEFT", -8, 8)
    texture:SetPoint("BOTTOMRIGHT", hint, "BOTTOMRIGHT", 8, -8)
    texture:SetAtlas("gamepad-xbox1-stick-updown-flat-normal")
    hint:Hide()
    return hint
end

---The game's focus glow round the window (its metal frame's, as round the game's windows that have the pad).
local function makeGlow(window)
    local glow = CreateFrame("Frame", nil, window)
    glow:SetFrameLevel(math.max(0, (window:GetFrameLevel() or 1) + 39)) -- (under the frame, at +40)
    glow:SetPoint("TOPLEFT", window, "TOPLEFT", -10, 14 + 21)
    glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 14, -14)
    local texture = glow:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(glow)
    texture:SetAtlas("gamepad-uiframemetal-focus")
    glow.texture = texture
    if texture.SetScale then
        pcall(texture.SetScale, texture, 0.5) -- (as the game's FrameGlowTemplate draws it)
    end
    glow:Hide()
    return glow
end

---The focus glow as the game draws it round the window that has the pad. Docked, the map and the window are one window
---to see (the window over the map's quest panel): one glow round both whenever the map has the pad (its quest log,
---which is the window, or its map), in the map's own glow (its portrait's, its colour), the map's own glow out of
---sight meanwhile (it stops at the map's edge, under the window). Alone, round the window while it has the pad.
local function updateGlow()
    local glow, window, map = state.glow, ns.Log.getWindow(), WorldMapFrame
    if not glow or not window then
        return
    end
    local mapGlow = map and map.BorderFrame and map.BorderFrame.FrameGlow
    local mode
    if window:IsVisible() and Gamepad.isGamepadUI() then
        if ns.Log.isAlone() then
            mode = state.isActive and "alone" or nil
        elseif mapGlow and map:IsShown() and not (map.IsMaximized and map:IsMaximized()) and Gamepad.getGameFocus() == map then
            mode = "pair"
        end
    end
    if mode == state.glowMode then
        return
    end
    state.glowMode = mode
    glow:ClearAllPoints()
    if mode == "pair" then
        local mapTexture = mapGlow.GlowTexture
        local atlas = mapTexture and mapTexture.GetAtlas and mapTexture:GetAtlas()
        glow.texture:SetAtlas(type(atlas) == "string" and atlas ~= "" and atlas or "gamepad-uiframemetal-focus")
        if mapTexture and mapTexture.GetVertexColor then
            glow.texture:SetVertexColor(mapTexture:GetVertexColor())
        end
        glow:SetPoint("TOPLEFT", mapGlow, "TOPLEFT", 0, 0)
        glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 14, -14)
    elseif mode == "alone" then
        glow.texture:SetAtlas("gamepad-uiframemetal-focus")
        glow.texture:SetVertexColor(1, 1, 1, 1)
        glow:SetPoint("TOPLEFT", window, "TOPLEFT", -10, 14 + 21) -- (the frame's title strip is 21 over the window)
        glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 14, -14)
    end
    glow:SetShown(mode ~= nil)
    if mapGlow and mapGlow.SetAlpha then
        mapGlow:SetAlpha(mode == "pair" and 0 or 1)
    end
end

---@return Button? row The list's row nearest the middle of its view (a quest, a zone's heading, folded or not: none
---passed over); in the details, their control nearest the middle
local function findMiddleRow(canvas)
    local isList = canvas == ns.Log.getListCanvas()
    local pool = canvas.pools and canvas.pools.buttons
    local _, _, viewTop, viewBottom = getRect(canvas.frame)
    if not viewTop then
        return nil
    end
    local middle = (viewTop + viewBottom) / 2
    local rowWidth = isList and getRowWidth() or 0
    local best, bestDistance
    for index = 1, pool and pool.usedCount or 0 do
        local button = pool[index]
        local _, _, top, bottom = getRect(button)
        if top and button:IsVisible() and not button.padSkip and (button:GetWidth() or 0) >= rowWidth and isInView(button) then
            local distance = math.abs((top + bottom) / 2 - middle)
            if not bestDistance or distance < bestDistance then
                best, bestDistance = button, distance
            end
        end
    end
    return best
end

local function scrollByStick(elapsed)
    local push = readRightStick()
    if math.abs(push) < STICK_DEAD_ZONE then
        return
    end
    local canvas = getStickCanvas()
    if canvas and canvas.setScroll then
        canvas:setScroll(canvas:getScroll() - push * STICK_SPEED * elapsed)
    end
    -- The pane scrolled under the cursor: the cursor stays in the middle of the view, on what is there (in the list a
    -- quest, shown beside the list once the stick rests; in the details their control there), as the game's quest log
    -- keeps its cursor on what it shows
    local cursor = state.cursor
    if canvas and cursor and getCanvasOf(cursor) == canvas then
        local row = findMiddleRow(canvas)
        if row and row ~= cursor then
            state.isRepeatMove, state.isStickMove = true, true
            setCursor(row)
            state.isRepeatMove, state.isStickMove = false, false
        end
    end
end

local function watch()
    if not state.watcher then
        state.watcher = CreateFrame("Frame")
        state.watcher:SetScript("OnUpdate", function(watcher, elapsed)
            local window = ns.Log.getWindow()
            if not window or not window:IsVisible() or not Gamepad.isGamepadUI() then
                setActive(false)
                updateGlow()
                updateSoftCursor()
                watcher:Hide()
                return
            end
            setActive(isWanted())
            updateGlow()
            updateSoftCursor()
            if state.isActive then
                scrollByStick(elapsed)
                placeStickHint()
                local isMenuOpen = ns.GamepadMenu and ns.GamepadMenu.isOpen()
                state.pointer:SetShown(not isMenuOpen and state.cursor ~= nil and isInView(state.cursor))
            end
        end)
    end
    state.watcher:Show()
end

---The window shown or hidden, the interface changed: one pane with the pad, two without; the watch started.
function Gamepad.sync()
    ns.noteActivity("gamepad sync")
    local window = ns.Log and ns.Log.getWindow and ns.Log.getWindow()
    if not window then
        return
    end
    local isPad = Gamepad.isGamepadUI() and window:IsVisible()
    ns.Log.setNarrow(false) -- (the list and the quest's page side by side, as with the mouse)
    if isPad then
        watch()
    else
        state.hasPlacedCursor = false
        setActive(false)
        state.cursor = nil
    end
end

---After each drawing of the window (Log.refresh): the cursor kept on something shown, the prompts for what is under it.
function Gamepad.handleDrawn()
    placeCursorAfterDrawing()
end

---A fight begins: every button of OneMoreQuest's let go of now, while bindings can still change (left bound, a
---window closed in the fight would keep the d-pad from the game till it is over); bound again after it.
function Gamepad.beforeCombat()
    takeRightStick(false)
    for _, set in ipairs(padSets) do
        if next(set.boundKeys) then
            ClearOverrideBindings(set.owner)
            set.boundKeys = {}
        end
    end
    if ns.GamepadMenu then
        ns.GamepadMenu.close()
    end
end

---A fight is over: the buttons the fight held back bound.
function Gamepad.afterCombat()
    Gamepad.sync()
    takeRightStick(state.isActive)
    for _, set in ipairs(padSets) do
        set.rebind()
    end
end

---------------------------------------------------------------------------------------------------------------
-- Diagnostics: the game's gamepad state must stay untainted (an addon's taint in it makes the game refuse its own
-- calls later). The first value found tainted is kept in the errorLog with what OneMoreQuest did just before
-- (ns.getActivityText), which names the culprit where the stack of a later refusal cannot.

---@return boolean isSecure The table's value at the key is untainted (keys the game cannot ask of: taken as untainted;
---asked safely, the watch must never break the game)
---@return string? taintedBy The addon that tainted it
local function isSecureAt(container, key)
    local keyType = type(key)
    if type(issecurevariable) ~= "function" or (keyType ~= "string" and keyType ~= "number") then
        return true
    end
    local isAsked, isSecure, taintedBy = pcall(issecurevariable, container, key)
    if not isAsked then
        return true
    end
    return isSecure, taintedBy
end

local SCAN_SECONDS, SCAN_MAX_VALUES = 0.25, 4000
local function scanTable(root, path, depth, seen, budget)
    if type(root) ~= "table" or seen[root] or budget.left <= 0 then
        return nil
    end
    seen[root] = true
    for key, value in pairs(root) do
        budget.left = budget.left - 1
        if budget.left <= 0 then
            return nil
        end
        local isSecure, taintedBy = isSecureAt(root, key)
        if not isSecure then
            return path .. "." .. tostring(key), taintedBy
        end
        -- (into the game's tables, not into frames: OneMoreQuest's own frames are its own to taint)
        if depth > 0 and type(value) == "table" and type(rawget(value, 0)) ~= "userdata" then
            local found, by = scanTable(value, path .. "." .. tostring(key), depth - 1, seen, budget)
            if found then
                return found, by
            end
        end
    end
    return nil
end

local function findGameTaint()
    local seen, budget = {}, { left = SCAN_MAX_VALUES }
    local roots = {
        { GamepadSharedUtility and GamepadSharedUtility.InputBindingManager, "InputBindingManager", 4 },
        { _G.SmartNavigation, "SmartNavigation", 2 },
        { GamepadMode and GamepadMode.FrameControlsManager, "FrameControlsManager", 2 },
        { _G.GamepadRadial, "GamepadRadial", 1 },
    }
    local map = _G.WorldMapFrame
    if map then
        for _, key in ipairs({ "currentFocus", "questLogTooltipBindings", "worldMapCursorBindings", "questDetailCursorBindings",
            "navBarBindings", "worldMapFooter", "questLogFooter", "questDetailsFooter" }) do
            local isSecure, taintedBy = isSecureAt(map, key)
            if not isSecure then
                return "WorldMapFrame." .. key, taintedBy
            end
            roots[#roots + 1] = { map[key], "WorldMapFrame." .. key, 2 }
        end
    end
    for _, root in ipairs(roots) do
        local found, by = scanTable(root[1], root[2], root[3], seen, budget)
        if found then
            return found, by
        end
    end
    return nil
end

local function watchGameTaint()
    if state.taintScanner or type(issecurevariable) ~= "function" then
        return
    end
    state.taintScanner = CreateFrame("Frame")
    local elapsedSince = 0
    state.taintScanner:SetScript("OnUpdate", function(scanner, elapsed)
        elapsedSince = elapsedSince + elapsed
        if elapsedSince < SCAN_SECONDS then
            return
        end
        elapsedSince = 0
        if not Gamepad.isGamepadUI() then
            return
        end
        local found, taintedBy = findGameTaint()
        if found then
            ns.Timing.noteError("The game's gamepad state was tainted by " .. tostring(taintedBy) .. ": " .. found,
                "OneMoreQuest's last doings:\n" .. ns.getActivityText())
            scanner:Hide()
        end
    end)
end

---------------------------------------------------------------------------------------------------------------

local function hookWindow()
    local window = ns.Log and ns.Log.getWindow and ns.Log.getWindow()
    if state.isHooked or not window then
        return
    end
    state.isHooked = true
    window:HookScript("OnShow", Gamepad.sync)
    window:HookScript("OnHide", Gamepad.sync)
    state.pointer = Gamepad.makePointer(window)
    state.prompts = Gamepad.makePromptStrip(window)
    state.prompts:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, -4) -- (as the game's bar stands under its window)
    state.glow = makeGlow(window)
    state.stickHint = makeStickHint(window)
    state.padButtons = Gamepad.makePadButtons("OneMoreQuestPad", WINDOW_KEYS, 1, handlePadDown, handlePadUp)
    -- The game's navigation selects a button of its own quest panel (open out of sight under the window) as the map's
    -- focus goes there, and that button shows its tooltip over the window: while the window has the pad, the tooltip
    -- of the window's cursor instead
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnShow", function(tooltip)
            local panel = WorldMapFrame and WorldMapFrame.QuestLog
            local owner = tooltip.GetOwner and tooltip:GetOwner()
            if not state.isActive or not panel or (panel:GetAlpha() or 1) > 0.5 or not owner or not isInside(owner, panel) then
                return
            end
            tooltip:Hide()
            local cursor = state.cursor
            local onEnter = cursor and cursor:IsVisible() and cursor:GetScript("OnEnter")
            if onEnter then
                pcall(onEnter, cursor, false)
            end
        end)
    end
end

function Gamepad.create()
    watchGameTaint()
    hookWindow()
    Gamepad.sync()
end

ns.registerModule({
    name = "Gamepad",
    create = Gamepad.create,
    needsWorldMap = true, -- the window is the map's
    afterCombat = Gamepad.afterCombat,
    events = {
        INPUT_DEVICE_INTERFACE_TRANSITION = function()
            Gamepad.sync()
            ns.MapDock.apply() -- (OneMoreQuest's frames on the map out of it, or back in it: MapDock.placeOnMap)
            ns.Log.refresh() -- (the page's bar of buttons: none with the pad, Y has them)
        end,
        PLAYER_REGEN_DISABLED = Gamepad.beforeCombat,
    },
})
