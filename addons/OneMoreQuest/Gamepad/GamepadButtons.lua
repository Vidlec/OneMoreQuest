local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The pad's buttons: OneMoreQuest's own override bindings, for the quest window, its menus, the tracker and the map.
--
-- A set of hidden buttons, one for each of some of the pad's buttons, which override bindings of OneMoreQuest's own
-- click on the press and on the release. Priority bindings: they come before the game's own gamepad bindings (also
-- priority override bindings, on UIParent), the latest set first; the game sets its own again as its windows change,
-- so OneMoreQuest's are set again after each of the game's on the same buttons (hooked: the game's own call is left
-- as it is). Sets have a rank: a menu's buttons come before the window's. Not in a fight (the game refuses bindings
-- then): done once it is over (rebind).
local Gamepad = ns.Gamepad

local padSets = {} -- every set, lowest rank first
local ownOwners = {} -- the sets' owners: their own bindings are not the game's
local isBindingHooked = false
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
    if isBindingHooked or type(hooksecurefunc) ~= "function" then
        return
    end
    isBindingHooked = true
    for _, name in ipairs({ "SetOverrideBinding", "SetOverrideBindingClick" }) do
        if type(_G[name]) == "function" then
            hooksecurefunc(name, handleForeignBinding)
        end
    end
end

---The buttons bound now: these (nil: none), the others let go of.
local function setKeys(set, wanted)
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

---The buttons wanted bound again (after a fight, which held them back).
local function rebind(set)
    local wanted = {}
    for key in pairs(set.wantedKeys) do
        wanted[#wanted + 1] = key
    end
    setKeys(set, wanted)
end

---A d-pad button held, each frame: its move again after a while, and again, while the button is still the set's.
local function repeatHeld(set, elapsed)
    local key = set.held
    -- (the button another set's now, a menu's say: its release goes there, the repeat stops here)
    local isOurs = key
        and GetBindingAction
        and GetBindingAction(key, true) == "CLICK " .. set.buttons[key]:GetName() .. ":LeftButton"
    if not key or not set.boundKeys[key] or not isOurs then
        set.held = nil
        set.owner:Hide()
        return
    end
    set.heldFor = set.heldFor + elapsed
    if set.heldFor >= set.nextRepeat then
        set.nextRepeat = set.heldFor + REPEAT_EVERY
        set.handleDown(key, true)
    end
end

---A press or a release of one of the set's buttons; a d-pad button's press starts its repeat.
local function handleClick(set, key, isDown)
    ns.noteActivity("pad " .. key .. (isDown and " down" or " up"))
    if isDown then
        if REPEATED[key] then
            set.held, set.heldFor, set.nextRepeat = key, 0, REPEAT_DELAY
            set.owner:Show()
        end
        set.handleDown(key, false)
        return
    end
    if set.held == key then
        set.held = nil
        set.owner:Hide()
    end
    if set.handleUp then
        set.handleUp(key)
    end
end

---The set among the others by its rank, the lowest first.
local function insertByRank(set)
    local index = #padSets + 1
    for at, other in ipairs(padSets) do
        if other.rank > set.rank then
            index = at
            break
        end
    end
    table.insert(padSets, index, set)
end

---@param name string The buttons' name, before each key (a click binding needs a global name)
---@param keys string[] The pad's buttons (PADDUP, PAD1...)
---@param rank number Which set comes first on a button both have bound (the higher)
---@param handleDown fun(key: string, isRepeat: boolean)
---@param handleUp fun(key: string)?
---@return table set Its buttons: set.setKeys(keys), set.isBound(key), set.rebind()
function Gamepad.makePadButtons(name, keys, rank, handleDown, handleUp)
    hookBindings()
    local set = {
        owner = CreateFrame("Frame"),
        buttons = {},
        boundKeys = {},
        wantedKeys = {},
        rank = rank,
        handleDown = handleDown,
        handleUp = handleUp,
    }
    ownOwners[set.owner] = true
    for _, key in ipairs(keys) do
        local button = CreateFrame("Button", name .. key, UIParent)
        button:Hide()
        button:RegisterForClicks("AnyDown", "AnyUp")
        button:SetScript("OnClick", function(_, _, isDown)
            handleClick(set, key, isDown)
        end)
        set.buttons[key] = button
    end
    set.owner:Hide()
    set.owner:SetScript("OnUpdate", function(_, elapsed)
        repeatHeld(set, elapsed)
    end)
    function set.setKeys(wanted)
        setKeys(set, wanted)
    end
    function set.isBound(key)
        return set.boundKeys[key] == true
    end
    function set.rebind()
        rebind(set)
    end
    insertByRank(set)
    return set
end

---A fight begins: every set's buttons let go of now, while bindings can still change; bound again after it.
function Gamepad.releasePadButtons()
    for _, set in ipairs(padSets) do
        if next(set.boundKeys) then
            ClearOverrideBindings(set.owner)
            set.boundKeys = {}
        end
    end
end

---A fight is over: the buttons each set wants bound again.
function Gamepad.rebindPadButtons()
    for _, set in ipairs(padSets) do
        set.rebind()
    end
end
