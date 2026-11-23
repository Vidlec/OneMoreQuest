-- A record of exactly what is drawn in the states the map goes through (focus, hover, zoom, the Available tab, a
-- kill, the minimap as the player walks, the map opened again), to compare before and after a change to how things
-- are drawn: the picture must stay the same. Writes sim/scenarios/.visual/<label>/<state>.txt, one line per drawn item
-- (sorted, without the objects' own numbers: which texture of a pool draws a thing does not matter).
--   set VISUAL_LABEL=before  (or after), then: bun run test:sim sim/scenarios/audits/visual-baseline.lua
--   python sim/scenarios/audits/visual-diff.py before after
local scene = require("scene")
local sim = require("sim")
local label = os.getenv("VISUAL_LABEL") or "run"
local folder = scenariosDir .. "/.visual/" .. label
sim.makeDirectory(scenariosDir .. "/.visual")
sim.makeDirectory(folder)

local function canonical(value, depth)
    local kind = type(value)
    if kind == "number" then
        return string.format("%.1f", value)
    elseif kind == "table" then
        if (depth or 0) > 4 then return "{...}" end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, key in ipairs(keys) do
            if key ~= "i" then -- the object's own number
                parts[#parts + 1] = tostring(key) .. "=" .. canonical(value[key], (depth or 0) + 1)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

local function record(state)
    local lines = {}
    for _, item in ipairs(scene.export()) do
        lines[#lines + 1] = canonical(item)
    end
    table.sort(lines)
    local out = io.open(folder .. "/" .. state .. ".txt", "w")
    out:write(table.concat(lines, "\n"), "\n")
    out:close()
    io.write("VISUAL ", state, ": ", #lines, " items\n")
end

setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29) -- Grom'gol Base Camp, Stranglethorn
local accepted = {}
for _, questId in ipairs({ 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 196, 197, 568, 569, 570, 572, 573, 581, 582 }) do
    accept(questId)
    accepted[#accepted + 1] = questId
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
-- KEEP_OFF=1: every redraw draws in full (no marks kept at a kill counted), to compare with the keeping
addon.MapPins.isKeepingOff = os.getenv("KEEP_OFF") == "1"
local function titleOf(questId) return addon.QuestState.getQuest(questId).title end

---Moves the mouse onto a quest's row in the quest window's list: the nth row showing there (titles repeat, in the
---tracker, on the quest's page and between the steps of a chain, so the row is taken by its place, not its words).
---@return number? questId The quest the list says is under the mouse
local function hoverListRow(rowNumber)
    local W = require("widgets")
    local list = W.computeRect(G.TrailheadLogList)
    local left, right = list[1], list[3]
    local top, bottom = sim.screenHeight - list[4], sim.screenHeight - list[2]
    local rows = {}
    for _, item in ipairs(scene.export()) do
        if item.k == "s" and item.x >= left and item.x <= right and item.y >= top + 4 and item.y + item.h <= bottom - 4 then
            for _, line in ipairs(item.lines) do
                if line:match("^%[%d+%] ") then -- a quest's row: "[31] Panther Mastery"
                    rows[#rows + 1] = item
                end
            end
        end
    end
    table.sort(rows, function(first, second) return first.y < second.y end)
    local row = rows[rowNumber]
    expect(row ~= nil, "the list shows a row number " .. rowNumber .. " (" .. #rows .. " rows)")
    if row then
        scene.input({ type = "move", x = row.x + 4, y = row.y + row.h / 2 })
    end
    wait(1)
    local hovered = addon.Log.getHoveredQuestId()
    expect(hovered ~= nil, "a quest of the list is under the mouse")
    expect(addon.MapMarks.getFocusedQuestId() == hovered, "and the map shows it in focus")
    return hovered
end

record("01-standing-map-closed")
key("M"); wait(2)
record("02-map-open")
addon.Focus.set(accepted[4]); wait(1)
record("03-followed-quest")
local firstHovered = hoverListRow(2)
record("04-hover-a-quest")
local secondHovered = hoverListRow(5)
expect(firstHovered ~= secondHovered, "the mouse moved on to another quest")
record("05-hover-another")
scene.input({ type = "move", x = 5, y = 5 }); wait(1) -- the mouse leaves the list
record("05b-hover-ended")
addon.Log.selectQuest(accepted[9]); wait(1)
record("06-quest-selected")
local W = require("widgets")
local rect = W.computeRect(G.WorldMapFrame.ScrollContainer)
local pointX, pointY = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
wheel({ pointX, pointY }, 1); wait(1)
record("07-zoomed-in")
wheel({ pointX, pointY }, -1); wheel({ pointX, pointY }, -1); wait(1)
record("08-zoomed-out-again")
progress(accepted[1], 1, 1); wait(1)
record("09-a-kill-counted-map-open")
click("Available"); wait(1.5)
record("10-available-tab")
click("My quests"); wait(1)
record("11-my-quests-again")
key("M"); wait(1)
record("12-map-closed")
hold("W", 3); wait(0.5)
record("13-after-walking")
key("M"); wait(2)
record("14-map-reopened-after-walking")
key("M"); wait(0.5)
key("M"); wait(2)
record("15-map-reopened-nothing-changed")
key("M"); wait(0.5)
progress(accepted[2], 1, 1); wait(1)
record("16-a-kill-counted-map-closed")
key("M"); wait(2)
record("17-map-opened-after-that-kill")
addon.Focus.set(nil); wait(1)
record("18-nothing-followed")
