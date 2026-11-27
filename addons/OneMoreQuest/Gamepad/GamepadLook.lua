local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The gamepad's look, in the game's own art drawn by OneMoreQuest: the cursor's pointing hand, the prompt strip under a
-- window (each pad button's icon and what it does), the focus glow round the window that has the pad, and the words of
-- the pad's usual actions. Used by the quest window (Gamepad.lua), its menus, the tracker and the map.
local Gamepad = ns.Gamepad

---------------------------------------------------------------------------------------------------------------
-- The words of the pad's usual actions: the game's own (its global strings), else OneMoreQuest's

local ACTION_LABELS = {
    select = function()
        return ACTION_LABEL_SELECT or ns.L("Select")
    end,
    back = function()
        return FRAME_ACTION_BACK or BACK or ns.L("Back")
    end,
    close = function()
        return FRAME_ACTION_CLOSE or CLOSE or ns.L("Close")
    end,
    options = function()
        return CONTEXT_ACTION_LABEL_OPTIONS or ns.L("Options")
    end,
}

---@param action string "select", "back", "close" or "options"
---@return string label What a prompt says for it, in the game's own words where it has them
function Gamepad.getActionLabel(action)
    return ACTION_LABELS[action]()
end

---------------------------------------------------------------------------------------------------------------
-- The cursor's hand

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

---------------------------------------------------------------------------------------------------------------
-- The prompt strip

local STRIP_PADDING, PROMPT_GAP, ICON_SIZE, DIVIDER_SIZE, ICON_GAP = 10, 15, 24, 16, 4 -- (the game's legend's)

---@return string? atlas The game's icon of a pad button (or a divider: "SLASH"), for the pad in use
local function getInputAtlas(key)
    local utility = type(InputIconTextureSetUtility) == "table"
        and InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture
    local atlas = utility and key and utility(key)
    return type(atlas) == "string" and atlas ~= "" and atlas or nil
end

---@return table item One prompt's parts: { icons = { texture, texture }, divider, text }, and a press-and-hold's marks
---as the game's own icons have them: the "hold" ring on the button, and while it is held the load bar running round it
---(InputIconTextureFrameTemplate)
local function makePromptItem(strip)
    local item = { icons = {} }
    for iconIndex = 1, 2 do
        local icon = strip:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ICON_SIZE, ICON_SIZE)
        item.icons[iconIndex] = icon
    end
    item.divider = strip:CreateTexture(nil, "ARTWORK")
    item.divider:SetSize(DIVIDER_SIZE, DIVIDER_SIZE)
    item.text = ns.Widgets.createFontString(strip, "OVERLAY", "GameFontNormal")
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
    return item
end

---@return table item The strip's prompt at an index, made as more are wanted
local function getPromptItem(strip, index)
    local item = strip.items[index]
    if not item then
        item = makePromptItem(strip)
        strip.items[index] = item
    end
    return item
end

---A hold's load bar stopped and put away (its ring shows again where the prompt is a hold: the caller says).
local function stopHoldLoad(item)
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

---A hold's load bar running round its button for the hold's length (the game's own ring; a cooldown's sweep where
---this client has no ring to run).
local function startHoldLoad(strip, item, seconds)
    item.isHolding = true
    item.holdBG:Hide()
    item.holdRing:Hide()
    item.loadBG:Show()
    item.loadBar:Show()
    if item.loadAnim then
        item.loadFill:SetDuration(seconds)
        item.loadAnim:Stop()
        item.loadAnim:Play()
        return
    end
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

---A prompt's button icons from x on: one, or two with a slash between.
---@return number x Where its text starts
---@return Region right What its text stands right of
local function placePromptIcons(strip, item, keys, x)
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
    return x, right
end

---One prompt drawn from x on: its icons, its hold's ring, its words.
---@return number x Where the next prompt starts
local function placePrompt(strip, item, prompt, x)
    local keys = prompt.keys or { prompt.key }
    local right
    x, right = placePromptIcons(strip, item, keys, x)
    if item.isHolding and item.key ~= keys[1] then
        stopHoldLoad(item) -- (the hold's ring was on another button: this slot is another prompt now)
    end
    item.key = keys[1]
    item.isHold = prompt.isHold == true
    item.holdBG:SetShown(item.isHold and not item.isHolding)
    item.holdRing:SetShown(item.isHold and not item.isHolding)
    item.text:SetText(prompt.label)
    item.text:ClearAllPoints()
    item.text:SetPoint("LEFT", right, "RIGHT", ICON_GAP, 0)
    item.text:Show()
    return x + ICON_GAP + (item.text:GetStringWidth() or 0) + PROMPT_GAP
end

---A slot no prompt uses now: all of it hidden.
local function hidePromptItem(item)
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

---@return string line The prompts in one string, to tell whether they changed since the last time
local function composePromptLine(prompts)
    local parts = {}
    for _, prompt in ipairs(prompts) do
        parts[#parts + 1] = table.concat(prompt.keys or { prompt.key }, "+") .. "=" .. tostring(prompt.label)
    end
    return table.concat(parts, "|")
end

---The strip's prompts, drawn again only when they changed.
local function setPrompts(strip, prompts)
    local line = composePromptLine(prompts)
    if line == strip.line then
        strip:SetShown(#prompts > 0)
        return
    end
    strip.line = line
    local x = STRIP_PADDING
    for index, prompt in ipairs(prompts) do
        x = placePrompt(strip, getPromptItem(strip, index), prompt, x)
    end
    for index = #prompts + 1, #strip.items do
        hidePromptItem(strip.items[index])
    end
    strip:SetWidth(math.max(10, x - PROMPT_GAP + STRIP_PADDING))
    strip:SetShown(#prompts > 0)
end

---@return Frame strip A line of prompts as the game's own prompt bar draws them under its windows (its slot and frame,
---each pad button's icon and what it does, two buttons with a slash between): strip.setPrompts, strip.beginHold,
---strip.endHold
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
    strip.items = {} -- the prompts' parts, made as more are wanted (getPromptItem)
    ---@param prompts table[] { key = "PAD1" (or keys = { "PADLSHOULDER", "PADRSHOULDER" }), label = "Select" }
    function strip.setPrompts(prompts)
        setPrompts(strip, prompts)
    end
    ---A press-and-hold begun on a prompt's button: its load bar runs round it for the hold's length
    function strip.beginHold(key, seconds)
        for _, item in ipairs(strip.items) do
            if item.key == key and item.isHold and item.text:IsShown() then
                startHoldLoad(strip, item, seconds)
            end
        end
    end
    ---The hold over (let go of, or held to its end): the button as before
    function strip.endHold(key)
        for _, item in ipairs(strip.items) do
            if item.key == key and item.isHolding then
                stopHoldLoad(item)
                item.holdBG:SetShown(item.isHold)
                item.holdRing:SetShown(item.isHold)
            end
        end
    end
    strip:Hide()
    return strip
end

---------------------------------------------------------------------------------------------------------------
-- The focus glow

local GLOW_ATLAS = "gamepad-uiframemetal-focus"

---@return Frame glow The game's focus glow round the window (its metal frame's, as round the game's windows that have
---the pad); Gamepad.updateGlow shows it
function Gamepad.makeGlow(window)
    local glow = CreateFrame("Frame", nil, window)
    glow:SetFrameLevel(math.max(0, (window:GetFrameLevel() or 1) + 39)) -- (under the frame, at +40)
    glow:SetPoint("TOPLEFT", window, "TOPLEFT", -10, 14 + 21)
    glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 14, -14)
    local texture = glow:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints(glow)
    texture:SetAtlas(GLOW_ATLAS)
    glow.texture = texture
    if texture.SetScale then
        pcall(texture.SetScale, texture, 0.5) -- (as the game's FrameGlowTemplate draws it)
    end
    glow:Hide()
    return glow
end

---@return string? mode How the glow goes round the window now: "pair" (round the map and the window docked on it,
---whenever the map has the pad), "alone" (round the window by itself, while it has the pad), or nil (none)
local function getGlowMode(window, map, mapGlow, hasPad)
    if not window:IsVisible() or not Gamepad.isGamepadUI() then
        return nil
    elseif ns.Log.isAlone() then
        return hasPad and "alone" or nil
    elseif
        mapGlow
        and map:IsShown()
        and not (map.IsMaximized and map:IsMaximized())
        and Gamepad.getGameFocus() == map
    then
        return "pair"
    end
    return nil
end

---The glow placed and coloured for its mode: the map's own glow's (its portrait's, its colour) round the pair, the
---game's usual one round the window alone.
local function placeGlow(glow, mode, window, mapGlow)
    glow:ClearAllPoints()
    if mode == "pair" then
        local mapTexture = mapGlow.GlowTexture
        local atlas = mapTexture and mapTexture.GetAtlas and mapTexture:GetAtlas()
        glow.texture:SetAtlas(type(atlas) == "string" and atlas ~= "" and atlas or GLOW_ATLAS)
        if mapTexture and mapTexture.GetVertexColor then
            glow.texture:SetVertexColor(mapTexture:GetVertexColor())
        end
        glow:SetPoint("TOPLEFT", mapGlow, "TOPLEFT", 0, 0)
        glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 14, -14)
    elseif mode == "alone" then
        glow.texture:SetAtlas(GLOW_ATLAS)
        glow.texture:SetVertexColor(1, 1, 1, 1)
        glow:SetPoint("TOPLEFT", window, "TOPLEFT", -10, 14 + 21) -- (the frame's title strip is 21 over the window)
        glow:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", 14, -14)
    end
end

---The focus glow as the game draws it round the window that has the pad. Docked, the map and the window are one window
---to see (the window over the map's quest panel): one glow round both whenever the map has the pad (its quest log,
---which is the window, or its map), the map's own glow out of sight meanwhile (it stops at the map's edge, under the
---window). Alone, round the window while it has the pad. Set again only when its mode changed.
---@param hasPad boolean The window has the pad now
function Gamepad.updateGlow(glow, window, hasPad)
    local map = WorldMapFrame
    local mapGlow = map and map.BorderFrame and map.BorderFrame.FrameGlow
    local mode = getGlowMode(window, map, mapGlow, hasPad)
    if mode == glow.mode then
        return
    end
    glow.mode = mode
    placeGlow(glow, mode, window, mapGlow)
    glow:SetShown(mode ~= nil)
    if mapGlow and mapGlow.SetAlpha then
        mapGlow:SetAlpha(mode == "pair" and 0 or 1)
    end
end
