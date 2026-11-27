--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=14
-- Every control of OneMoreQuest's window, pressed with the gamepad: in each view the cursor is put on each control in
-- turn (as the d-pad would bring it there), the tooltip it shows is noted, A is pressed, and what changed is printed.
-- A control whose A changes nothing is flagged: on the pad it would be a dead button.
-- bun run test:sim sim/scenarios/audits/omq-pad-features.lua
moveTo(1413, 0.52, 0.30)
for _, questId in ipairs({ 844, 870, 871, 819 }) do
    accept(questId)
end
wait(1)
gamepadInterface(true)
key("M")
wait(1)
local window, manager, nav = G.OneMoreQuestLog, G.GamepadMode.FrameControlsManager, G.SmartNavigation
local addon = require("addons").byName["onemorequest"].private
local W, sim = require("widgets"), require("sim")
for _ = 1, 4 do
    if manager:GetActiveFrame() == window then
        break
    end
    pad("PADRTRIGGER")
end
wait(0.3)

local function rectOf(frame)
    return W.computeRect(frame)
end
-- What a control says: its own text, else the drawing's texts that lie on it
local function labelOf(button)
    local own = button.GetText and button:GetText()
    if own and own ~= "" then
        return own
    end
    for _, region in ipairs({ button:GetRegions() }) do
        if region.GetText and region:GetText() and region:GetText() ~= "" then
            return region:GetText()
        end
    end
    local r = rectOf(button)
    local words = {}
    for _, canvas in ipairs({ addon.Log.getListCanvas(), addon.Log.getPageCanvas() }) do
        local texts = canvas.pools and canvas.pools.texts
        for index = 1, texts and texts.usedCount or 0 do
            local text = texts[index]
            local t = text:IsVisible() and rectOf(text)
            if r and t and t[1] < r[3] and t[3] > r[1] and t[2] < r[4] and t[4] > r[2] and text:GetText() then
                words[#words + 1] = text:GetText()
            end
        end
    end
    local label = table.concat(words, " | ")
    if label == "" then
        label = (button:GetName() or button:GetObjectType())
    end
    return label
end
local function clean(text)
    return (tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("\n", " ")):sub(1, 60)
end

local function snapshot()
    local menu = G.Menu.GetManager():GetOpenMenu()
    return {
        view = addon.Log.getView(),
        spread = addon.Log.isPageSpread(),
        available = addon.Log.isShowingAvailable(),
        open = tostring(addon.Log.getOpenRowData()),
        map = G.WorldMapFrame:GetMapID(),
        menu = menu ~= nil,
        focus = tostring(addon.Focus.get()),
        list = addon.Log.getListCanvas().pools.buttons.usedCount,
        page = addon.Log.getPageCanvas().pools.buttons.usedCount,
        pageScroll = math.floor(addon.Log.getPageCanvas().frame:GetVerticalScroll()),
        listScroll = math.floor(addon.Log.getListCanvas().frame:GetVerticalScroll()),
        shown = window:IsShown(),
        keyboard = W.focus ~= nil,
        pageHeight = math.floor(addon.Log.getPageCanvas().content:GetHeight()),
        listHeight = math.floor(addon.Log.getListCanvas().content:GetHeight()),
    }
end
local chatLines = 0
G.hooksecurefunc("ChatEdit_InsertLink", function()
    chatLines = chatLines + 1
end)
local function diff(a, b)
    local parts = {}
    for key, value in pairs(b) do
        if a[key] ~= value then
            parts[#parts + 1] = key .. " " .. tostring(a[key]) .. "->" .. tostring(value)
        end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

local function controls()
    local found = {}
    local function visit(frame)
        if
            frame:IsVisible()
            and frame ~= window
            and G.SmartNavigation_CanFocusFrame(frame)
            and not G.SmartNavigation_IsFrameIgnored(frame)
        then
            local r = rectOf(frame)
            if r and r[3] - r[1] > 2 and r[4] - r[2] > 2 then
                found[#found + 1] = frame
            end
        end
        for _, child in ipairs({ frame:GetChildren() }) do
            visit(child)
        end
    end
    visit(window)
    return found
end

local deadCount = 0
local function pressAll(label, restore, keep, limit)
    print("== " .. label)
    local list = {}
    for _, control in ipairs(controls()) do
        if (not keep or keep(control)) and #list < (limit or 999) then
            list[#list + 1] = control
        end
    end
    for index, control in ipairs(list) do
        if control:IsVisible() then
            local name = clean(labelOf(control))
            local before = snapshot()
            before.checked = control.GetChecked and tostring(control:GetChecked()) or nil
            local chatBefore = chatLines
            G.GameTooltip:Hide()
            sim.runSecurely(nav.SetTargetButtonForFrame, nav, window, control)
            wait(0.05)
            local tip = G.GameTooltip:IsShown() and G.GameTooltipTextLeft1:GetText()
            pad("PAD1")
            wait(0.1)
            local after = snapshot()
            after.checked = control.GetChecked and tostring(control:GetChecked()) or nil
            local changed = diff(before, after)
            if chatLines ~= chatBefore then
                changed = changed .. " chat link"
            end
            local isDead = changed == "" and control:GetObjectType() ~= "EditBox"
            if isDead then
                deadCount = deadCount + 1
            end
            print(
                string.format(
                    "  %s %-40s tip=%-24s A: %s",
                    isDead and "DEAD" or "    ",
                    name,
                    clean(tip or "-"),
                    changed ~= "" and changed or "(nothing)"
                )
            )
            -- Undo what the press opened, so the next control is pressed in the same view
            if after.menu then
                pad("PAD2")
                wait(0.2)
            end
            if after.keyboard then
                local chat = G.ChatEdit_GetActiveWindow and G.ChatEdit_GetActiveWindow()
                if chat then
                    (G.ChatEdit_DeactivateChat or function(b)
                        b:Hide()
                    end)(chat)
                end
                W.setFocus(nil)
                wait(0.2)
            end
            for _ = 1, 4 do
                if manager:GetActiveFrame() == window then
                    break
                end
                pad("PADRTRIGGER")
            end
            if addon.Log.isPageSpread() then
                addon.Log.setPageSpread(false)
                wait(0.2)
            end
            if not window:IsShown() then
                key("M")
                wait(0.5)
                for _ = 1, 4 do
                    if manager:GetActiveFrame() == window then
                        break
                    end
                    pad("PADRTRIGGER")
                end
            end
            if restore then
                restore(before, after)
            end
        end
    end
end

local function backToQuests(before, after)
    if after.view ~= before.view then
        addon.Log.handleGamepadBack()
        wait(0.3)
    end
end
local only = os.getenv("PAD_AUDIT_ONLY") -- "settings": the settings and the chronicle alone (the lists change the map a lot)
if only ~= "settings" then
    pressAll("My quests", backToQuests, nil, 20)
    addon.Log.stepTab(1)
    wait(0.5)
    pressAll("Available", function(before, after)
        backToQuests(before, after)
        if not addon.Log.isShowingAvailable() then
            addon.Log.stepTab(1)
            wait(0.4)
        end
    end, nil, 12)
    addon.Log.stepTab(1)
    wait(0.5)
    pressAll("Dungeons", backToQuests, nil, 12)
end
for section = 1, 9 do
    addon.Log.openSettings(section)
    wait(0.5)
    pressAll("Settings section " .. section, function(before, after)
        if addon.Log.getView() ~= "settings" then
            addon.Log.openSettings(section)
            wait(0.4)
        end
    end, function(control)
        return addon.Log.isInPage(control)
    end)
end
addon.Log.handleGamepadBack()
wait(0.3)
addon.Log.toggleChronicle()
wait(0.5)
pressAll("Chronicle", function(before, after)
    if addon.Log.getView() ~= "chronicle" then
        addon.Log.toggleChronicle()
        wait(0.4)
    end
end)
print("dead controls: " .. deadCount)
