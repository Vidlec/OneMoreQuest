-- For the mockups: a clean picture of the Stranglethorn map, and what OneMoreQuest draws on it for a few quests
-- (marks, spawn icons, areas) as data, in the map's own pixels.
local W, sim = require("widgets"), require("sim")
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
local out = io.open(os.getenv("MOCK_OUT") or (scenariosDir .. "/.mock-export.lua.json"), "w")
local accepted = {}
for _, questId in ipairs({ 185, 190, 194, 568, 581, 196 }) do
    if pcall(accept, questId) then accepted[#accepted + 1] = questId end
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
addon.settings.shouldUseAvailableQuests = false
addon.settings.areaStyle = "filled"
key("M"); wait(2)
addon.Focus.set(accepted[2]); wait(1.5)
local map = G.WorldMapFrame
local canvas = map:GetCanvas()
local rect = W.computeRect(map.ScrollContainer)
local left, top = rect[1], sim.screenHeight - rect[4]
local width, height = rect[3] - rect[1], rect[4] - rect[2]
local drawn = addon.MapMarks.getDrawn(map)
local function num(value) return string.format("%.2f", value) end
local parts = {}
parts[#parts + 1] = string.format('"map": {"left": %s, "top": %s, "width": %s, "height": %s, "scale": %s}', num(left), num(top), num(width), num(height), num(drawn.scale or 1))
-- the quests
local quests = {}
local numbers = addon.QuestState.getWatchNumbers()
for _, questId in ipairs(accepted) do
    local quest = addon.QuestState.getQuest(questId)
    local color = addon.MapMarks.getQuestColor(numbers[questId], questId)
    local glyph = addon.MapMarks.getQuestGlyph(questId, quest.objectives)
    quests[#quests + 1] = string.format('{"id": %d, "number": %s, "title": %q, "glyph": %q, "color": [%s, %s, %s], "focused": %s}', questId, tostring(numbers[questId]),
        quest.title, tostring(glyph), num(color[1]), num(color[2]), num(color[3]), tostring(questId == accepted[2]))
end
parts[#parts + 1] = '"quests": [' .. table.concat(quests, ", ") .. "]"
-- every spawn of each quest on this map, and each quest's areas as the addon shapes them (fractions of the map)
local mapId = map:GetMapID()
local player = addon.Model.getPlayer()
local spawns, areas = {}, {}
for _, questId in ipairs(accepted) do
    local entry = addon.Model.composeEntry(questId, player)
    local points = addon.MapMarks.composePoints(entry.allPlaces or entry.places or {}, mapId)
    for _, point in ipairs(points) do
        spawns[#spawns + 1] = string.format('{"x": %.4f, "y": %.4f, "quest": %d, "glyph": %q}', point.x, point.y, questId, tostring(point.place and point.place.glyph))
    end
    local shapes
    for _ = 1, 40 do
        shapes = addon.MapMarks.composeFittedShapes(questId, mapId, points, true)
        if shapes then break end
        wait(0.1)
    end
    for _, shape in ipairs(shapes or {}) do
        local edges = {}
        for _, edge in ipairs(shape.edges or {}) do
            edges[#edges + 1] = string.format("[%.4f,%.4f,%.4f,%.4f]", edge[1].x, edge[1].y, edge[2].x, edge[2].y)
        end
        areas[#areas + 1] = string.format('{"quest": %d, "count": %d, "edges": [%s]}', questId, #(shape.points or {}), table.concat(edges, ","))
    end
end
parts[#parts + 1] = '"spawns": [' .. table.concat(spawns, ", ") .. "]"
parts[#parts + 1] = '"areas": [' .. table.concat(areas, ", ") .. "]"
-- the marks
local marks = {}
local pools = addon.MapMarksState.pools
for index = 1, pools.marks.usedCount do
    local button = pools.marks[index]
    local mark = button.mark
    if mark and mark.place then
        marks[#marks + 1] = string.format('{"x": %s, "y": %s, "kind": %q, "quest": %s, "number": %s, "glyph": %q, "focused": %s}', num(mark.place.left), num(mark.place.top),
            tostring(mark.kind), tostring(mark.questId), tostring(mark.number), tostring(mark.glyph), tostring(mark.isFocused == true))
    end
end
parts[#parts + 1] = '"marks": [' .. table.concat(marks, ", ") .. "]"
out:write("{" .. table.concat(parts, ",\n") .. "}\n")
out:close()
saveScene("map-with-marks")
-- the clean map
addon.settings.shouldShowMapPins, addon.settings.shouldHideBuiltInMapPins = false, false
addon.MapPins.refresh(); addon.MinimapPins.refresh(); wait(1)
saveScene("map-clean")
io.write(string.format("MOCK map at %d,%d size %dx%d\n", left, top, width, height))
