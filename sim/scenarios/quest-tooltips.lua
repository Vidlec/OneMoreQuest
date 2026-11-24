-- Quest tooltips: the experience at the right of each quest's title, and while Shift is held the quest's details
-- (what it asks, its rewards, where it is handed in), filled again the moment Shift goes down or up.
setProfile({ level = 33, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29) -- Grom'gol Base Camp, Stranglethorn
for _, questId in ipairs({ 190, 185, 568 }) do
    pcall(accept, questId)
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local sim = require("sim")
addon.Focus.set(190)

local function tooltipText()
    local lines = {}
    if not G.GameTooltip:IsShown() then
        return ""
    end
    for index = 1, G.GameTooltip:NumLines() do
        local left, right = G["GameTooltipTextLeft" .. index], G["GameTooltipTextRight" .. index]
        local text = left and left:GetText() or ""
        local rightText = right and right:IsShown() and right:GetText()
        lines[#lines + 1] = text .. (rightText and rightText ~= "" and ("  >> " .. rightText) or "")
    end
    return table.concat(lines, "\n")
end
local function setShift(isDown)
    sim.modifiers.shift = isDown
    fire("MODIFIER_STATE_CHANGED", "LSHIFT", isDown and 1 or 0)
    wait(0.1)
end

key("M")
wait(2)
-- The followed quest's mark on the map
local button
for index = 1, addon.MapMarksState.pools.marks.usedCount do
    local candidate = addon.MapMarksState.pools.marks[index]
    if candidate.mark and candidate.mark.questId == 190 and candidate:IsVisible() then
        button = candidate
    end
end
expect(button ~= nil, "the followed quest's mark is on the map")
hover(button)
wait(0.3)
local text = tooltipText()
io.write("TOOLTIP mark:\n", text, "\n")
expect(
    text:find("[31] Panther Mastery  >> ", 1, true) ~= nil and text:find(" XP", 1, true) ~= nil,
    "the experience at the right of the title"
)
expect(text:find("Hold Shift for details", 1, true) ~= nil, "the hint")
saveScene("mark")
setShift(true)
text = tooltipText()
io.write("TOOLTIP mark, Shift:\n", text, "\n")
expect(text:find("wants you to kill 10 Young Panthers", 1, true) ~= nil, "Shift: what it asks")
expect(text:find("Rewards: ", 1, true) ~= nil, "Shift: the rewards")
expect(text:find("Hold Shift", 1, true) == nil, "Shift: no hint")
saveScene("mark-shift")
setShift(false)
expect(tooltipText():find("wants you to kill", 1, true) == nil, "Shift let go: the details go")
hover({ x = 5, y = 5 })
wait(0.2)

-- A quest giver's "!" on the map
local giver
for index = 1, addon.MapMarksState.pools.marks.usedCount do
    local candidate = addon.MapMarksState.pools.marks[index]
    if candidate.mark and candidate.mark.kind == "giver" and candidate:IsVisible() and not giver then
        giver = candidate
    end
end
if giver then
    hover(giver)
    wait(0.3)
    io.write("TOOLTIP giver:\n", tooltipText(), "\n")
    setShift(true)
    io.write("TOOLTIP giver, Shift:\n", tooltipText(), "\n")
    expect(tooltipText():find("From level", 1, true) ~= nil, "a quest to pick up: the level it needs")
    saveScene("giver-shift")
    setShift(false)
    hover({ x = 5, y = 5 })
    wait(0.2)
end
key("M")
wait(1)

-- The tracker's row
hover("Panther Mastery")
wait(0.3)
io.write("TOOLTIP tracker:\n", tooltipText(), "\n")
expect(tooltipText():find(" XP", 1, true) ~= nil, "the tracker's tooltip has the experience")
setShift(true)
io.write("TOOLTIP tracker, Shift:\n", tooltipText(), "\n")
expect(tooltipText():find("Rewards: ", 1, true) ~= nil, "and its details with Shift")
saveScene("tracker-shift")
setShift(false)

-- A "?" drawn in the game's look on the minimap: the same lines as any mark (level, experience, Shift details)
hover({ x = 5, y = 5 })
wait(0.2)
local pin = addon.MinimapPins.acquireGamePin(
    99,
    { kind = "turnIn", questId = 190, lines = { "[31] Panther Mastery", "Turn in to Sir S. J. Erlgadin" } }
)
pin:ClearAllPoints()
pin:SetPoint("CENTER", G.Minimap, "CENTER", 30, 30)
pin:Show()
hover(pin)
wait(0.3)
io.write("TOOLTIP game ?:\n", tooltipText(), "\n")
expect(tooltipText():find("[31] Panther Mastery  >> ", 1, true) ~= nil, 'the game-look "?": level and experience')
setShift(true)
io.write("TOOLTIP game ?, Shift:\n", tooltipText(), "\n")
expect(tooltipText():find("Rewards: ", 1, true) ~= nil, "and the details with Shift")
setShift(false)
pin:Hide()

-- The game's own "!" near the player (Grom'gol): what our lines under the game's minimap tooltip say of each
local handed = addon.MinimapPins.findGameMarksAt(0, 0, 1000)
local gameLines = addon.MapHover.composeGameMarkLines(handed)
io.write(string.format("TOOLTIP game's own marks: %d handed over, %d lines\n", #handed, #gameLines))
for index = 1, math.min(#gameLines, 4) do
    io.write("  ", gameLines[index], "\n")
end
expect(#handed == 0 or #gameLines >= #handed, 'every "!" and "?" handed to the game has its quests listed')
