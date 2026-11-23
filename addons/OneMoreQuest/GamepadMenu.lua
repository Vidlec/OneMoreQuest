local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- OneMoreQuest's menus with the game's gamepad interface: the same menus (a row's More actions, a dropdown's
-- choices), drawn and worked by OneMoreQuest itself. The game's own menus are taken over by its frame controls as they
-- open (Blizzard_GamepadSharedUtility's MenuProxy.OnShow), which an addon opening one does with the addon's taint: the
-- game's focus then refuses its own work after (Gamepad.lua says more). A menu is described as for the game's
-- (MenuUtil.CreateContextMenu's generator: root:CreateButton, CreateRadio, CreateCheckbox, CreateTitle, CreateDivider,
-- a button's own entries as its submenu), and shown in the game's menu art:
--   d-pad up/down  the entry before or after     A  choose it (a submenu: into it; d-pad right too)
--   B  back out of a submenu, else close (d-pad left out of a submenu too)
-- ns.openMenu opens the game's own menu without the gamepad interface (or in a fight, when no binding can be made).
local GamepadMenu = {}
ns.GamepadMenu = GamepadMenu

local ROW_HEIGHT, MAX_ROWS, MIN_WIDTH = 20, 16, 140

local state = {
    frame = nil,
    rows = {},
    levels = nil, -- the menu open, and the submenus gone into: { entries, index, offset, title }
    owner = nil,
    generator = nil,
    onDone = nil,
}

---------------------------------------------------------------------------------------------------------------
-- A menu's description, as the game's generators write it

local Description = {}

local function ignore(self)
    return setmetatable({ kind = "ignored", children = {}, isEnabled = true }, Description)
end

Description.__index = function(_, key)
    local method = rawget(Description, key)
    if method ~= nil then
        return method
    end
    -- Anything else the game's descriptions do (tooltips, initializers, scroll modes: their methods, named in capitals)
    -- is passed over; a field not set is nil, as ever
    if type(key) == "string" and key:find("^%u") then
        return ignore
    end
    return nil
end

local function newEntry(kind, text)
    return setmetatable({ kind = kind, text = text, children = {}, isEnabled = true }, Description)
end

local function add(parent, entry)
    parent.children[#parent.children + 1] = entry
    return entry
end

function Description:CreateButton(text, callback, data)
    local entry = newEntry("button", text)
    entry.callback, entry.data = callback, data
    return add(self, entry)
end

function Description:CreateRadio(text, isSelected, setSelected, data)
    local entry = newEntry("radio", text)
    entry.isSelected, entry.setSelected, entry.data = isSelected, setSelected, data
    return add(self, entry)
end

function Description:CreateCheckbox(text, isSelected, setSelected, data)
    local entry = newEntry("checkbox", text)
    entry.isSelected, entry.setSelected, entry.data = isSelected, setSelected, data
    return add(self, entry)
end

function Description:CreateTitle(text)
    return add(self, newEntry("title", text))
end

function Description:CreateDivider()
    return add(self, newEntry("divider"))
end

function Description:SetEnabled(isEnabled)
    self.isEnabled = isEnabled
end

---@return boolean isEnabled
local function isEntryEnabled(entry)
    local isEnabled = entry.isEnabled
    if type(isEnabled) == "function" then
        local isAsked, result = pcall(isEnabled, entry)
        return not isAsked or result ~= false
    end
    return isEnabled ~= false
end

---@return boolean isChoosable The cursor may stand on it: a button, a radio, a checkbox, enabled
local function isChoosable(entry)
    return (entry.kind == "button" or entry.kind == "radio" or entry.kind == "checkbox") and isEntryEnabled(entry)
end

local function isEntrySelected(entry)
    if type(entry.isSelected) ~= "function" then
        return false
    end
    local isAsked, result = pcall(entry.isSelected, entry.data)
    return isAsked and result == true
end

---@return table[]? entries The menu the generator describes now
local function describe(owner, generator)
    local root = newEntry("root")
    local isMade, problem = pcall(generator, owner, root)
    if not isMade then
        ns.Timing.noteProblem("gamepad", "a menu could not be made: " .. tostring(problem))
        return nil
    end
    return root.children
end

---------------------------------------------------------------------------------------------------------------
-- The menu on screen

local function getLevel()
    return state.levels and state.levels[#state.levels]
end

local function makeRow(frame, index)
    local row = CreateFrame("Button", nil, frame)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -6 - (index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
    row.highlight = row:CreateTexture(nil, "BACKGROUND")
    row.highlight:SetAllPoints(row)
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row.highlight:SetBlendMode("ADD")
    row.highlight:Hide()
    row.mark = row:CreateTexture(nil, "ARTWORK")
    row.mark:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.mark:SetSize(16, 16)
    row.text = ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row, "LEFT", 20, 0)
    row.text:SetJustifyH("LEFT")
    row.arrow = row:CreateTexture(nil, "ARTWORK")
    row.arrow:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.arrow:SetSize(16, 16)
    row.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    row.divider = row:CreateTexture(nil, "ARTWORK")
    row.divider:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.divider:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.divider:SetHeight(13)
    row.divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
    -- (a mouse works it too: its hover moves the cursor, its click chooses)
    row:SetScript("OnEnter", function()
        local level = getLevel()
        if level and row.entryIndex and isChoosable(level.entries[row.entryIndex]) then
            level.index = row.entryIndex
            GamepadMenu.draw()
        end
    end)
    row:SetScript("OnClick", function()
        local level = getLevel()
        if level and row.entryIndex then
            level.index = row.entryIndex
            GamepadMenu.choose()
        end
    end)
    return row
end

---The menu closed once what it was opened from is gone: another of the game's windows took the pad, the quest window
---or the tracker let it go, the menu's owner hid, the gamepad interface was left (its buttons would stay the menu's).
local function watchContext()
    if not state.levels then
        return
    end
    local owner = state.owner
    local isOwnerGone = type(owner) == "table" and owner.IsVisible ~= nil and not owner:IsVisible()
    if not ns.Gamepad.isGamepadUI() or ns.Gamepad.getGameFocus() ~= state.openedFocus or isOwnerGone
        or (state.openedWithPad and not ns.Gamepad.hasPad())
        or (state.openedWithTracker and not ns.GamepadTracker.isFocused()) then
        GamepadMenu.close()
    end
end

local function makeFrame()
    local frame = CreateFrame("Frame", "OneMoreQuestGamepadMenu", UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetScript("OnUpdate", watchContext)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas("common-dropdown-c-bg")
    background:SetPoint("TOPLEFT", frame, "TOPLEFT", -17, 12)
    background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 17, -22)
    frame.pointer = ns.Gamepad.makePointer(frame)
    frame.prompts = ns.Gamepad.makePromptStrip(frame)
    frame.prompts:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -16)
    frame:Hide()
    return frame
end

---@return string text The entry's words as the menu shows them: a title gold, a disabled entry grey
local function getEntryText(entry)
    local text = entry.text
    if type(text) == "function" then
        local isAsked, result = pcall(text, entry)
        text = isAsked and result or ""
    end
    text = tostring(text or "")
    if entry.kind == "title" and NORMAL_FONT_COLOR then
        return NORMAL_FONT_COLOR:WrapTextInColorCode(text)
    elseif not isEntryEnabled(entry) and GRAY_FONT_COLOR then
        return GRAY_FONT_COLOR:WrapTextInColorCode(text)
    end
    return text
end

local function getMarkAtlas(entry)
    if entry.kind == "radio" then
        return isEntrySelected(entry) and "common-dropdown-icon-radialtick-yellow-classic" or "common-dropdown-tickradial-classic"
    elseif entry.kind == "checkbox" and isEntrySelected(entry) then
        return "common-dropdown-icon-checkmark-yellow-classic-2"
    end
    return nil
end

---The open level drawn: its entries from the scroll offset, the cursor's entry highlighted, the hand beside it.
function GamepadMenu.draw()
    local frame, level = state.frame, getLevel()
    if not frame or not level then
        return
    end
    local entries = level.entries
    local count = math.min(#entries, MAX_ROWS)
    if level.index then
        level.offset = math.max(0, math.min(level.offset or 0, level.index - 1))
        if level.index > level.offset + MAX_ROWS then
            level.offset = level.index - MAX_ROWS
        end
    end
    local width, cursorRow = MIN_WIDTH, nil
    for index = 1, math.max(count, #state.rows) do
        local row = state.rows[index]
        if index <= count then
            row = row or makeRow(frame, index)
            state.rows[index] = row
            local entryIndex = (level.offset or 0) + index
            local entry = entries[entryIndex]
            row.entryIndex = entryIndex
            local isDivider = entry.kind == "divider"
            row.divider:SetShown(isDivider)
            row.text:SetText(isDivider and "" or getEntryText(entry))
            local atlas = getMarkAtlas(entry)
            row.mark:SetShown(atlas ~= nil)
            if atlas then
                row.mark:SetAtlas(atlas)
            end
            row.arrow:SetShown(entry.kind == "button" and #entry.children > 0)
            row.highlight:SetShown(entryIndex == level.index)
            if entryIndex == level.index then
                cursorRow = row
            end
            width = math.max(width, (row.text:GetStringWidth() or 0) + 20 + 28)
            row:Show()
        elseif row then
            row:Hide()
        end
    end
    frame:SetSize(width + 12, count * ROW_HEIGHT + 12)
    ns.Gamepad.placePointer(frame.pointer, cursorRow)
    local isSubmenu = #state.levels > 1
    frame.prompts.setPrompts({
        { key = "PAD1", label = ACTION_LABEL_SELECT or ns.L("Select") },
        { key = "PAD2", label = isSubmenu and (FRAME_ACTION_BACK or BACK or ns.L("Back")) or (FRAME_ACTION_CLOSE or CLOSE or ns.L("Close")) },
    })
end

---@return number? index The first entry the cursor may stand on from an index on, that way (1 or -1)
local function findChoosable(entries, from, step)
    local index = from
    while entries[index] do
        if isChoosable(entries[index]) then
            return index
        end
        index = index + step
    end
    return nil
end

local function pushLevel(entries, title)
    state.levels[#state.levels + 1] = { entries = entries, index = findChoosable(entries, 1, 1), offset = 0, title = title }
end

---@return string? text The words of the entry under the menu's cursor (for tests)
function GamepadMenu.getCursorText()
    local level = getLevel()
    local entry = level and level.entries[level.index or 0]
    return entry and getEntryText(entry) or nil
end

---@return boolean isOpen A menu of OneMoreQuest's shows
function GamepadMenu.isOpen()
    return state.frame ~= nil and state.frame:IsShown() and state.levels ~= nil
end

function GamepadMenu.close()
    if not state.levels then
        return
    end
    local onDone = state.onDone
    state.levels, state.owner, state.generator, state.onDone = nil, nil, nil, nil
    if state.frame then
        state.frame:Hide()
    end
    if state.padButtons then
        state.padButtons.setKeys(nil)
    end
    if onDone then
        pcall(onDone)
    end
    if ns.Gamepad.refreshPrompts then
        ns.Gamepad.refreshPrompts()
    end
end

---The menu described again (a checkbox changed what it says), the cursor where it was.
local function redescribe()
    local entries = describe(state.owner, state.generator)
    if not entries then
        GamepadMenu.close()
        return
    end
    local path = {}
    for depth, level in ipairs(state.levels) do
        path[depth] = level.index
    end
    state.levels = { { entries = entries, index = path[1], offset = 0 } }
    for depth = 2, #path do
        local parent = state.levels[depth - 1]
        local entry = parent.entries[parent.index or 0]
        if not entry or #entry.children == 0 then
            break
        end
        state.levels[depth] = { entries = entry.children, index = path[depth], offset = 0 }
    end
    for _, level in ipairs(state.levels) do
        if not level.index or not level.entries[level.index] or not isChoosable(level.entries[level.index]) then
            level.index = findChoosable(level.entries, 1, 1)
        end
    end
    GamepadMenu.draw()
end

local function isKeptOpen(response)
    return type(MenuResponse) == "table" and response ~= nil and (response == MenuResponse.Open or response == MenuResponse.Refresh)
end

---A: the entry under the cursor chosen, as a click on the game's menu chooses it.
function GamepadMenu.choose()
    local level = getLevel()
    local entry = level and level.entries[level.index or 0]
    if not entry or not isChoosable(entry) then
        return
    end
    if entry.kind == "button" and #entry.children > 0 then
        pushLevel(entry.children, entry.text)
        GamepadMenu.draw()
        return
    end
    local inputData = { buttonName = "LeftButton" }
    local levels = state.levels -- (an entry may open another menu in this one's place: that one stays)
    local isDone, response
    if entry.kind == "button" then
        isDone, response = pcall(entry.callback or function() end, entry.data, inputData)
    else
        isDone, response = pcall(entry.setSelected or function() end, entry.data, inputData)
    end
    if not isDone then
        ns.Timing.noteProblem("gamepad", "a menu's entry failed: " .. tostring(response))
    end
    if state.levels ~= levels then
        return
    elseif entry.kind == "checkbox" or isKeptOpen(response) then
        redescribe() -- (a checkbox's menu stays, as the game's does)
    else
        GamepadMenu.close()
    end
end

local function step(delta)
    local level = getLevel()
    if not level then
        return
    end
    local index = findChoosable(level.entries, (level.index or 0) + delta, delta)
    if index then
        level.index = index
        GamepadMenu.draw()
    end
end

local function back()
    if #state.levels > 1 then
        state.levels[#state.levels] = nil
        GamepadMenu.draw()
    else
        GamepadMenu.close()
    end
end

local function handlePadDown(key)
    if not GamepadMenu.isOpen() then
        return
    end
    if key == "PADDUP" then
        step(-1)
    elseif key == "PADDDOWN" then
        step(1)
    elseif key == "PAD1" then
        GamepadMenu.choose()
    elseif key == "PADDRIGHT" then
        local level = getLevel()
        local entry = level and level.entries[level.index or 0]
        if entry and entry.kind == "button" and #entry.children > 0 then
            GamepadMenu.choose()
        end
    elseif key == "PADDLEFT" then
        if #state.levels > 1 then
            back()
        end
    elseif key == "PAD2" or key == "PAD4" then
        back()
    end
end

local MENU_KEYS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT", "PAD1", "PAD2", "PAD3", "PAD4" }

---Opens a menu of OneMoreQuest's beside its owner (under a dropdown, beside a row).
---@param owner Frame? What the menu is of (the generator gets it, as the game's do)
---@param generator fun(owner: Frame?, root: table) The menu's description, as for MenuUtil.CreateContextMenu
---@param onDone fun()? Called once it closes
---@return Frame? menu The menu (IsShown, Close), nil when the menu had nothing to show
function GamepadMenu.open(owner, generator, onDone)
    GamepadMenu.close()
    local entries = describe(owner, generator)
    if not entries or #entries == 0 then
        return nil
    end
    state.frame = state.frame or makeFrame()
    state.frame.Close = GamepadMenu.close
    if not state.padButtons then
        state.padButtons = ns.Gamepad.makePadButtons("OneMoreQuestMenuPad", MENU_KEYS, 3, handlePadDown)
    end
    state.owner, state.generator, state.onDone, state.levels = owner, generator, onDone, {}
    -- What the menu was opened from, to close it once that is gone (watchContext)
    state.openedFocus = ns.Gamepad.getGameFocus()
    state.openedWithPad = ns.Gamepad.hasPad()
    state.openedWithTracker = ns.GamepadTracker ~= nil and ns.GamepadTracker.isFocused()
    pushLevel(entries)
    local frame = state.frame
    frame:ClearAllPoints()
    -- Where: under a dropdown; else at the pad's cursor (the window's, or the tracker's row it is of), under the control it
    -- stands on, as the game's menus open at its cursor; else at a small owner; else mid-screen. (A menu's owner can be
    -- a whole drawing, the list: never at its foot.)
    local cursor = ns.Gamepad.getCursor and ns.Gamepad.getCursor()
    local isOwnerShown = type(owner) == "table" and owner.IsVisible and owner:IsVisible()
    local anchor
    if isOwnerShown and owner.IsObjectType and owner:IsObjectType("DropdownButton") then
        frame:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -4)
    else
        if cursor and ns.Gamepad.isInView(cursor) and ns.Gamepad.hasPad() then
            anchor = cursor
        elseif isOwnerShown and (owner:GetHeight() or 0) < 120 then
            anchor = owner
        end
        if anchor then
            frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 24, -2)
        else
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
    frame:Show()
    frame:Raise()
    GamepadMenu.draw()
    state.padButtons.setKeys(MENU_KEYS)
    ns.Gamepad.refreshPrompts()
    return frame
end

---A dropdown's menu, OneMoreQuest's way: its choices (the generator it was set up with), and its text set again
---after a choice, as the game's dropdown does.
function GamepadMenu.openDropdown(dropdown)
    if type(dropdown.menuGenerator) ~= "function" then
        return nil
    end
    return GamepadMenu.open(dropdown, dropdown.menuGenerator, function()
        if dropdown.GenerateMenu then
            pcall(dropdown.GenerateMenu, dropdown)
        end
    end)
end

---A menu: OneMoreQuest's with the gamepad interface (in a fight too, worked by the mouse till the fight is over: no
---binding can be made then, and the game's menu opened from an addon's code taints its gamepad focus), else the game's
---(MenuUtil.CreateContextMenu).
---@return table? menu
function ns.openMenu(owner, generator)
    if ns.Gamepad.isGamepadUI() then
        return GamepadMenu.open(owner, generator)
    end
    if type(MenuUtil) == "table" and MenuUtil.CreateContextMenu then
        return MenuUtil.CreateContextMenu(owner, generator)
    end
    return nil
end

local function handleInterfaceChange()
    if not ns.Gamepad.isGamepadUI() then
        GamepadMenu.close()
    end
end

ns.registerModule({
    name = "GamepadMenu",
    events = { INPUT_DEVICE_INTERFACE_TRANSITION = handleInterfaceChange },
})
