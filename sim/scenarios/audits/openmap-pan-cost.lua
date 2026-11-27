--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- Panning OpenMap's joined-up world with hardly any quest marks: what OneMoreQuest costs there, where the map shows
-- many zones stitched together and next to nothing of ours. The cursor resting on the map, moving over it, a row of
-- drags across zones at a zone's zoom, then the same zoomed out. For each: the time in all and OneMoreQuest's share,
-- its widget calls, the worst frame, how often the map underneath changed, and how many frames lie on the canvas.
-- PAN_QUESTS=<n> quests tracked (2); MAPCOST_TOP=<n> lists OneMoreQuest's top functions of each step.
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene, game = require("widgets"), require("sim"), require("scene"), require("game")
local mapcost = require("mapcost")
local RIVER_MAP, RIVER_AREA = 2548, 16591

setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local owner = require("addons").byName["onemorequest"]
local addon = owner and owner.private
local accepted = {}
do
    local Q = G.LibQuestieDB.Quest
    local wanted = tonumber(mapcost.option("PAN_QUESTS") or "2")
    for questId = 1, 99999 do
        local isRead, zoneOrSort = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and zoneOrSort == RIVER_AREA and #accepted < wanted then
            local level = Q.Get(questId, "questLevel") or 0
            if level >= 34 and level <= 44 and pcall(accept, questId) then
                accepted[#accepted + 1] = questId
            end
        end
    end
end
for _, questId in ipairs(accepted) do
    if not G.C_QuestLog.GetQuestWatchType(questId) then
        G.C_QuestLog.AddQuestWatch(questId)
    end
end
print("PAN quests tracked: " .. #accepted .. (addon and "" or " (OneMoreQuest not loaded)"))
if addon and mapcost.option("PAN_RENDERER") then
    addon.settings.mapRenderer = mapcost.option("PAN_RENDERER")
end
if addon and mapcost.option("PAN_GIVERS") == "off" then
    addon.settings.shouldShowAvailableOnMap = false
end
wait(3)

mapcost.install()
if addon then
    mapcost.timeFunction(addon.MapPins, "refresh", "full redraw")
    mapcost.timeFunction(addon.MapMarks, "compose", "compose")
    mapcost.timeFunction(addon.MapMarks, "draw", "draw")
    mapcost.timeFunction(addon.MapMarks, "followZoom", "followZoom")
    mapcost.timeFunction(addon.MapMarks, "getForeignPins", "other addons' pins read")
    mapcost.timeFunction(addon.MapMarks, "getEntrancePins", "entrance pins read")
    mapcost.timeFunction(addon.MapHover, "updateMap", "map hover")
    mapcost.timeFunction(addon.MapPins, "handleViewMoved", "view moved")
    mapcost.timeFunction(addon.MapPins, "hideBuiltIn", "game's markers hidden")
    mapcost.timeFunction(addon.MinimapPins, "refresh", "minimap")
    mapcost.timeFunction(addon.Log, "refresh", "quest window")
    mapcost.timeFunction(addon.Log, "handleMapChanged", "quest window told of the map")
    mapcost.timeFunction(addon.MapMarksWorld, "update", "kept drawing looked at")
end
local measure = mapcost.measure
local map = G.WorldMapFrame
local mapChanges = 0
G.hooksecurefunc(map, "OnMapChanged", function()
    mapChanges = mapChanges + 1
end)

key("M")
wait(1)
do -- (OpenMap asks once which map to use: its own)
    local frame = G.EnumerateFrames()
    while frame do
        if frame:IsObjectType("Button") and frame:IsVisible() and frame.GetText and frame:GetText() == "OpenMap" then
            frame:Click()
            break
        end
        frame = G.EnumerateFrames(frame)
    end
end
wait(3)
expect(G.OpenMapAPI and G.OpenMapAPI.IsStitched(), "OpenMap's joined-up map shows")
local rect = W.computeRect(map.ScrollContainer)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2

local function sayCanvas(label)
    local canvas = map:GetCanvas()
    local children = { canvas:GetChildren() }
    local shown = 0
    for _, child in ipairs(children) do
        shown = shown + (child:IsShown() and 1 or 0)
    end
    print(
        string.format(
            "   canvas %-18s map %s scale %.2f: %d frames on it, %d shown; the map underneath changed %d times",
            label,
            tostring(map:GetMapID()),
            map:GetCanvasScale(),
            #children,
            shown,
            mapChanges
        )
    )
    mapChanges = 0
    -- (what the game lays out again on every frame of a drag: the number that counts in the real client)
    mapcost.sayHanging(map, label)
end
local function drag(name, dx, dy)
    local movedX, movedY
    measure(name, function()
        movedX, movedY = mapcost.drag(map, dx, dy)
        wait(1.5)
    end)
    print(string.format("   %s: the view went %.2f, %.2f of the map", name, movedX, movedY))
    sayCanvas(name)
end
scene.input({ type = "move", x = cx, y = cy })
wait(0.5)
sayCanvas("opened")
measure("cursor resting on the map, 2 s", function()
    wait(2)
end)
measure("cursor moving over the map, 2 s", function()
    for step = 1, 40 do
        scene.input({ type = "move", x = cx + math.sin(step / 6) * 150, y = cy + math.cos(step / 5) * 100 })
        wait(0.05)
    end
end)
measure("cursor off the map, 2 s", function()
    scene.input({ type = "move", x = 5, y = 5 })
    wait(2)
end)
scene.input({ type = "move", x = cx, y = cy })
for index, move in ipairs({ { -350, 0 }, { -350, 0 }, { 0, -250 }, { 350, 0 }, { 350, 250 }, { -350, -100 } }) do
    drag("zone zoom, drag " .. index, move[1], move[2])
end
for _ = 1, 3 do
    scene.input({ type = "wheel", x = cx, y = cy, delta = -1 })
    wait(1.5)
end
sayCanvas("zoomed out 3")
for index, move in ipairs({ { -350, 0 }, { 0, -250 }, { 350, 0 }, { 350, 250 }, { -350, -100 } }) do
    drag("out 3, drag " .. index, move[1], move[2])
end
for _ = 1, 3 do
    scene.input({ type = "wheel", x = cx, y = cy, delta = -1 })
    wait(1.5)
end
sayCanvas("zoomed out 6")
for index, move in ipairs({ { -350, 0 }, { 0, -250 }, { 350, 0 }, { 350, 250 } }) do
    drag("out 6, drag " .. index, move[1], move[2])
end
measure("out 6, cursor moving, 2 s", function()
    for step = 1, 40 do
        scene.input({ type = "move", x = cx + math.sin(step / 6) * 150, y = cy + math.cos(step / 5) * 100 })
        wait(0.05)
    end
end)

local totalMs, totalOurs, totalCalls, worstMs, worstName = 0, 0, 0, 0, ""
for name, result in pairs(mapcost.results) do
    totalMs, totalOurs, totalCalls = totalMs + result.ms, totalOurs + result.ours, totalCalls + result.calls
    if result.worstMs > worstMs then
        worstMs, worstName = result.worstMs, name
    end
end
print(
    string.format(
        "PAN in all: %.0f ms, OneMoreQuest ~%.0f ms, %d widget calls; worst frame %.0f ms (%s)",
        totalMs,
        totalOurs,
        totalCalls,
        worstMs,
        worstName
    )
)
