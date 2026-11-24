-- What the OneMoreQuest gamepad scenarios share: a watch on everything OneMoreQuest must never do with the game's
-- gamepad interface (call into its navigation, its frame controls or its binding stack, or the map's own focus, from
-- OneMoreQuest's code: in the client that taints the game's state and it refuses its own work after; an action blocked;
-- a frame made inside an open window of the navigation's), and readers for OneMoreQuest's own cursor, bindings and menu.
local sim = require("sim")

local omqpad = {}
local G = sim.G

---@return boolean isOwn OneMoreQuest's code is running (somewhere up the stack)
local function isOneMoreQuestRunning()
    for level = 3, 40 do
        local info = debug.getinfo(level, "S")
        if not info then
            return false
        end
        if info.source and info.source:find("OneMoreQuest", 1, true) then
            return true
        end
    end
    return false
end

local READS = { "^Get", "^Is", "^Can", "^Has", "^Should", "^Find" }
-- (only reads, and calls on to what is watched when it would change something: RefreshButtonGroups)
local PASSED = { UpdateParent = true }
local function isRead(name)
    if PASSED[name] then
        return true
    end
    for _, pattern in ipairs(READS) do
        if name:find(pattern) then
            return true
        end
    end
    return false
end

---Every function of a table of the game's that changes something, wrapped: a call from OneMoreQuest's code is kept.
local function watchTable(target, label, calls, names)
    if type(target) ~= "table" then
        return
    end
    local wrapped = {}
    for name, value in pairs(target) do
        if type(name) == "string" and type(value) == "function" and not isRead(name) and (not names or names[name]) then
            wrapped[name] = value
        end
    end
    for name, original in pairs(wrapped) do
        target[name] = function(...)
            if isOneMoreQuestRunning() then
                local own = {}
                for level = 2, 60 do
                    local info = debug.getinfo(level, "Sln")
                    if not info then
                        break
                    end
                    if info.source and info.source:find("OneMoreQuest", 1, true) then
                        own[#own + 1] = info.short_src
                            .. ":"
                            .. tostring(info.currentline)
                            .. " "
                            .. tostring(info.name)
                    end
                end
                calls[#calls + 1] = label .. "." .. name .. "\n  from " .. table.concat(own, "\n  from ")
            end
            return original(...)
        end
    end
end

---Starts the watch.
---@return table pad { addon, window, blocked(), navCalls, madeInPanel, cursor(), isOwn(key), menu(), report() }
function omqpad.start()
    local addon = require("addons").byName["onemorequest"].private
    local pad = { addon = addon, window = G.TrailheadLog, navCalls = {}, madeInPanel = {} }
    local blocked = 0
    G.hooksecurefunc("DisplayInterfaceActionBlockedMessage", function()
        blocked = blocked + 1
    end)
    function pad.blocked()
        return blocked
    end
    watchTable(G.SmartNavigation, "SmartNavigation", pad.navCalls)
    watchTable(G.GamepadMode and G.GamepadMode.FrameControlsManager, "FrameControlsManager", pad.navCalls)
    watchTable(
        G.GamepadSharedUtility and G.GamepadSharedUtility.InputBindingManager,
        "InputBindingManager",
        pad.navCalls
    )
    watchTable(G.WorldMapFrame, "WorldMapFrame", pad.navCalls, {
        FocusMap = true,
        FocusQuests = true,
        FocusDetails = true,
        FocusQuestLog = true,
        FocusQuestLogFromMap = true,
        ClearBindings = true,
        UpdateStateChangeIndicators = true,
        SetMapID = true,
        FocusGamepad = true,
        UnfocusGamepad = true,
    })
    watchTable(G, "", pad.navCalls, {
        ShowUIPanel = true,
        HideUIPanel = true,
        SmartNavigation_MarkFrameIgnored = true,
        SmartNavigation_ClearIgnoreStatus = true,
        SmartNavigation_MarkFrameSubSection = true,
    })
    G.hooksecurefunc("CreateFrame", function(_, _, parent)
        if not parent or not isOneMoreQuestRunning() then
            return
        end
        local frame = parent
        while frame and frame ~= G.UIParent do
            for _, info in ipairs(G.SmartNavigation.activePanels or {}) do
                if info.frame == frame then
                    pad.madeInPanel[#pad.madeInPanel + 1] = debug.traceback()
                    return
                end
            end
            frame = frame:GetParent()
        end
    end)
    ---@return Frame? cursor OneMoreQuest's cursor in its window
    function pad.cursor()
        return addon.Gamepad.getCursor()
    end
    ---@return boolean isOwn The pad's button is bound to one of OneMoreQuest's (its window's, tracker's or menu's)
    function pad.isOwn(key)
        return tostring(G.GetBindingAction(key)):find("^CLICK OneMoreQuest") ~= nil
    end
    ---@return boolean isOpen OneMoreQuest's menu shows
    ---@return string texts Its entries' words, joined by "|"
    function pad.menu()
        local frame = G.OneMoreQuestGamepadMenu
        if not addon.GamepadMenu.isOpen() or not frame then
            return false, ""
        end
        local texts = {}
        local function collect(each)
            for _, region in ipairs({ each:GetRegions() }) do
                if region.GetText and region:IsVisible() and region:GetText() and region:GetText() ~= "" then
                    texts[#texts + 1] = region:GetText()
                end
            end
            for _, child in ipairs({ each:GetChildren() }) do
                collect(child)
            end
        end
        collect(frame)
        return true, table.concat(texts, "|")
    end
    ---@return Frame? row The menu's entry with these words in it (to press with the cursor on it)
    function pad.menuIndexOf(text)
        local frame = G.OneMoreQuestGamepadMenu
        for _, row in ipairs({ frame and frame:GetChildren() or nil }) do
            if row.text and row:IsVisible() and tostring(row.text:GetText()):find(text, 1, true) then
                return row
            end
        end
        return nil
    end
    ---@return string[] frames OneMoreQuest's frames the game's navigation walks as the map's focus goes to its quest log
    ---(every frame inside the map but its sections: the canvas, the quest panel); each taints the map's focus there
    function pad.framesInMapWalk()
        local found = {}
        local function isOwn(frame)
            if frame == G.TrailheadLog then
                return true
            end
            for _, script in ipairs({ "OnClick", "OnEnter", "OnShow", "OnUpdate", "OnMouseUp", "OnMouseDown", "OnLoad" }) do
                local handler = frame.HasScript and frame:HasScript(script) and frame:GetScript(script)
                local info = type(handler) == "function" and debug.getinfo(handler, "S")
                if info and info.source and info.source:find("OneMoreQuest", 1, true) then
                    return true
                end
            end
            return false
        end
        local function walk(frame)
            for _, child in ipairs({ frame:GetChildren() }) do
                if not G.SmartNavigation_IsFrameSubSection(child) then
                    if isOwn(child) then
                        found[#found + 1] = tostring(child:GetName() or child:GetObjectType())
                    else
                        walk(child)
                    end
                end
            end
        end
        walk(G.WorldMapFrame)
        return found
    end
    ---@return string? problem What OneMoreQuest did that it must not (nil: nothing)
    function pad.report()
        if blocked > 0 then
            return blocked .. " action(s) blocked"
        end
        if #pad.navCalls > 0 then
            local names, seen = {}, {}
            for _, call in ipairs(pad.navCalls) do
                local name = call:match("^[^\n]*")
                if not seen[name] then
                    seen[name] = true
                    names[#names + 1] = name
                end
            end
            return #pad.navCalls
                .. " call(s) from OneMoreQuest into the game's navigation ("
                .. table.concat(names, ", ")
                .. "), first: "
                .. pad.navCalls[1]
        end
        if #pad.madeInPanel > 0 then
            return #pad.madeInPanel .. " frame(s) made inside a window of the navigation's: " .. pad.madeInPanel[1]
        end
        return nil
    end
    return pad
end

return omqpad
