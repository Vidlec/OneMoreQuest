--@login race=Orc,class=WARRIOR,level=43
--@addons QuestieDB, OneMoreQuest, OpenMap
-- A full quest log (quests of eight zones of two continents, the three of thousands of spawns among them) and
-- OpenMap's joined-up map zoomed out over several zones, left alone: what OneMoreQuest keeps on the map, and what it
-- still does at every frame with nothing changing. A map that only stands there should cost nothing of ours.
-- STATIC_OUT=<n> wheel steps out (4), STATIC_QUESTS=<n> a zone (5).
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene, game = require("widgets"), require("sim"), require("scene"), require("game")
local mapcost = require("mapcost")
setProfile({ level = 43, race = "Orc", class = "WARRIOR" })
moveTo(1434, 0.314, 0.296) -- Grom'gol, Stranglethorn Vale
local ZONES = { 33, 3, 8, 47, 16591, 357, 405, 45 } -- Stranglethorn, Badlands, Swamp, Hinterlands, Riverglades, Feralas, Desolace, Arathi
local accepted, perZone = {}, {}
local each = tonumber(mapcost.option("STATIC_QUESTS") or "5")
do
    local Q = G.LibQuestieDB.Quest
    local isWanted = {}
    for _, zone in ipairs(ZONES) do
        isWanted[zone] = true
    end
    for questId = 1, 99999 do
        local isRead, zone = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and isWanted[zone] and (perZone[zone] or 0) < each and #accepted < 37 then
            local level = Q.Get(questId, "questLevel") or 0
            if level >= 34 and level <= 46 and pcall(accept, questId) then
                accepted[#accepted + 1] = questId
                perZone[zone] = (perZone[zone] or 0) + 1
            end
        end
    end
    for _, questId in ipairs({ 95261, 92109, 1073 }) do
        if game.acceptQuest(questId) ~= false then
            accepted[#accepted + 1] = questId
        end
    end
end
for _, questId in ipairs(accepted) do
    if not G.C_QuestLog.GetQuestWatchType(questId) then
        G.C_QuestLog.AddQuestWatch(questId)
    end
end
print("STATIC quests tracked: " .. #accepted)
local addon = require("addons").byName["onemorequest"].private
wait(3)
local map = G.WorldMapFrame
key("M")
wait(3)
expect(G.OpenMapAPI and G.OpenMapAPI.IsStitched(), "OpenMap's joined-up map shows")
local rect = W.computeRect(map.ScrollContainer)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
scene.input({ type = "move", x = cx, y = cy - 150 })
for _ = 1, tonumber(mapcost.option("STATIC_OUT") or "4") do
    scene.input({ type = "wheel", x = cx, y = cy - 150, delta = -1 })
    wait(1.5)
end
scene.input({ type = "move", x = 5, y = 5 })

mapcost.install()
mapcost.timeFunction(addon.MapPins, "refresh", "MAP REDRAW")
mapcost.timeFunction(addon.MapMarksWorld, "update", "world.update")
mapcost.timeFunction(addon.MapMarks, "followZoom", "followZoom")
mapcost.timeFunction(addon.MapPins, "handleViewMoved", "viewMoved")
mapcost.timeFunction(addon.MinimapPins, "move", "minimap.move")
local function say(label)
    local c = addon.MapMarksWorld.getCounts(map)
    print(
        string.format(
            "   %-10s shown: %d sets (%d a continent's), %d fills, %d edges, %d walk lines, %d tiles, %d spawn marks (level %s); to do %d; kept in all %d pieces, %d marks (map %s, zoom %.2f)",
            label,
            c.setsShown or 0,
            c.wide or 0,
            c.fillsShown or 0,
            c.edgesShown or 0,
            c.walksShown or 0,
            c.tilesShown or 0,
            c.iconsShown or 0,
            tostring(c.level),
            c.todo or 0,
            c.kept or 0,
            c.keptIcons or 0,
            tostring(map:GetMapID()),
            map:GetCanvasScale()
        )
    )
end
for second = 1, 8 do
    mapcost.frameLog = {}
    mapcost.measure("left alone, second " .. second, function()
        for _ = 1, 60 do
            sim.tick(0.016)
        end
    end)
    local busy, calls, worst = 0, 0, 0
    for _, frame in ipairs(mapcost.frameLog) do
        calls = calls + frame.calls
        worst = math.max(worst, frame.calls)
        if frame.calls > 30 then
            busy = busy + 1
        end
    end
    mapcost.frameLog = nil
    print(string.format("   60 frames: %d with more than 30 calls, %d calls in all, worst %d", busy, calls, worst))
    say("second " .. second)
end
mapcost.sayHanging(map, "left alone")
do
    -- What stands there, by kind: a masked picture is the dearest thing to draw, then a picture, then a line
    local counts = {}
    local function walk(frame)
        if not frame:IsShown() then
            return
        end
        for _, region in ipairs(W.state[frame].regions or {}) do
            if region:IsShown() then
                local kind = region:IsObjectType("MaskTexture") and "MaskTexture"
                    or region:IsObjectType("FontString") and "FontString"
                    or region:IsObjectType("Line") and "Line"
                    or "Texture"
                counts[kind] = (counts[kind] or 0) + 1
            end
        end
        for _, child in ipairs(W.state[frame].children or {}) do
            walk(child)
        end
    end
    for _, layer in ipairs(mapcost.getLayers(addon, map)) do
        walk(layer)
    end
    local parts = {}
    for kind, count in pairs(counts) do
        parts[#parts + 1] = kind .. " " .. count
    end
    table.sort(parts)
    print("   shown regions by kind: " .. table.concat(parts, ", "))
end
