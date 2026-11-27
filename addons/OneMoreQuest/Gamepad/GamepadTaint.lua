local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Diagnostics: the game's gamepad state must stay untainted (an addon's taint in it makes the game refuse its own
-- calls later). A few times a second with the gamepad interface on, the game's gamepad tables are looked through; the
-- first value found tainted is kept in the errorLog with what OneMoreQuest did just before (ns.getActivityText), which
-- names the culprit where the stack of a later refusal cannot. Only ever read: nothing of the game's is changed.
local Gamepad = ns.Gamepad

local SCAN_SECONDS, SCAN_MAX_VALUES = 0.25, 4000
-- The map's own gamepad fields: each looked at itself, then into
local MAP_KEYS = {
    "currentFocus",
    "questLogTooltipBindings",
    "worldMapCursorBindings",
    "questDetailCursorBindings",
    "navBarBindings",
    "worldMapFooter",
    "questLogFooter",
    "questDetailsFooter",
}

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

---@return string? path The first tainted value in a table, to a depth, within the scan's budget of values
---@return string? taintedBy
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

---@return string? path The first tainted value of the game's gamepad state
---@return string? taintedBy
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
        for _, key in ipairs(MAP_KEYS) do
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

local taintScanner

---Starts the watch (once; never where the game cannot tell what is tainted). It stops at the first taint found.
function Gamepad.watchGameTaint()
    if taintScanner or type(issecurevariable) ~= "function" then
        return
    end
    taintScanner = CreateFrame("Frame")
    local elapsedSince = 0
    taintScanner:SetScript("OnUpdate", function(scanner, elapsed)
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
            ns.Timing.noteError(
                "The game's gamepad state was tainted by " .. tostring(taintedBy) .. ": " .. found,
                "OneMoreQuest's last doings:\n" .. ns.getActivityText()
            )
            scanner:Hide()
        end
    end)
end
