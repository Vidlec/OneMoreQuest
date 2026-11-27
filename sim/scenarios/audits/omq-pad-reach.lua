--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=14
-- Which of OneMoreQuest's controls the gamepad's cursor reaches, in every part of its window: from each control the
-- cursor can stand on, each d-pad direction is pressed and where it lands is noted. Controls on screen that nothing
-- leads to are listed, with the parts' dead ends (a control no direction leaves).
-- bun run test:sim sim/scenarios/audits/omq-pad-reach.lua
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
local scene, W, sim = require("scene"), require("widgets"), require("sim")
for _ = 1, 4 do
    if manager:GetActiveFrame() == window then
        break
    end
    pad("PADRTRIGGER")
end
wait(0.2)

local function isInWindow(frame)
    while frame do
        if frame == window then
            return true
        end
        frame = frame:GetParent()
    end
    return false
end
local function describe(frame)
    if not frame then
        return "nothing"
    end
    local text
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetText and region:GetText() and region:GetText() ~= "" then
            text = region:GetText()
            break
        end
    end
    if not text and frame.GetText and frame:GetText() then
        text = frame:GetText()
    end
    local r = W.computeRect(frame)
    local where = r and string.format("@%d,%d", math.floor(r[1]), math.floor(sim.screenHeight - r[4])) or "@?"
    return (frame:GetName() or frame:GetObjectType())
        .. where
        .. (text and (" '" .. tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):sub(1, 24) .. "'") or "")
end
-- Every control the game's navigation could stand on in the window, on screen now
local function candidates()
    local found = {}
    local function visit(frame)
        if
            frame:IsVisible()
            and frame ~= window
            and G.SmartNavigation_CanFocusFrame(frame)
            and not G.SmartNavigation_IsFrameIgnored(frame)
        then
            local r = W.computeRect(frame)
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

local DIRECTIONS = { "PADDUP", "PADDDOWN", "PADDLEFT", "PADDRIGHT" }
local function explore(label)
    local reached, edges, queue = {}, {}, {}
    local start = nav.currentButton
    if not start then
        print("== " .. label .. ": no cursor")
        return
    end
    reached[start], queue[1] = true, start
    local deadEnds = {}
    local head = 1
    while queue[head] and head < 400 do
        local from = queue[head]
        head = head + 1
        local leaves = false
        for _, direction in ipairs(DIRECTIONS) do
            sim.runSecurely(nav.SetTargetButtonForFrame, nav, window, from)
            pad(direction)
            local to = nav.currentButton
            if to and to ~= from then
                leaves = true
                if isInWindow(to) and not reached[to] then
                    reached[to] = true
                    queue[#queue + 1] = to
                end
            end
        end
        if not leaves then
            deadEnds[#deadEnds + 1] = describe(from)
        end
    end
    local all, missed = candidates(), {}
    for _, frame in ipairs(all) do
        if not reached[frame] then
            missed[#missed + 1] = describe(frame)
        end
    end
    print(string.format("== %s: %d of %d controls reached", label, #all - #missed, #all))
    for _, text in ipairs(missed) do
        print("   never reached: " .. text)
    end
    for _, text in ipairs(deadEnds) do
        print("   dead end: " .. text)
    end
    sim.runSecurely(nav.SetTargetButtonForFrame, nav, window, start)
end

explore("My quests")
print(
    "   (the one missed, at 727,258:)",
    (function()
        for _, f in ipairs(candidates()) do
            local r = W.computeRect(f)
            if math.floor(r[1]) == 727 then
                return describe(f)
                    .. " size "
                    .. math.floor(r[3] - r[1])
                    .. "x"
                    .. math.floor(r[4] - r[2])
                    .. " script "
                    .. tostring(f:GetScript("OnClick"))
            end
        end
    end)()
)
pad("PADRSHOULDER")
wait(0.5)
explore("Available")
pad("PADRSHOULDER")
wait(0.5)
explore("Dungeons")
pad("PADRSHOULDER")
wait(0.5)
addon.Log.openSettings(1)
wait(0.5)
explore("Settings")
addon.Log.handleGamepadBack()
wait(0.3)
addon.Log.toggleChronicle()
wait(0.5)
explore("Chronicle")
addon.Log.toggleChronicle()
wait(0.3)
