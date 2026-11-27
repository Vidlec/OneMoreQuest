--@login race=Human,class=WARRIOR,level=22
--@addons QuestieDB, OneMoreQuest, OpenMap
-- OpenMap's joined-up world dragged from zone to zone: once the view has stayed put a moment, OpenMap loads the zone
-- now in view as the map underneath, and everything on the map is told the map changed. What that costs
-- OneMoreQuest each time (its marks drawn for the new map, its quest window following it): the time in all and its
-- share, its widget calls, the worst frame. A handful of quests tracked, as a player has.
-- SWITCH_QUESTS=<n> quests tracked (6); SWITCH_RENDERER=classic the drawing before the kept one; SWITCH_LOG=closed
-- the quest window shut; MAPCOST_TOP=<n> lists OneMoreQuest's top functions of each step.
if jit then
    jit.off()
    jit.flush()
end
local W, sim, scene = require("widgets"), require("sim"), require("scene")
local mapcost = require("mapcost")
local ELWYNN_MAP, ELWYNN_AREA, WESTFALL_AREA, DUSKWOOD_AREA = 1429, 12, 40, 10

setProfile({ level = 22, race = "Human", class = "WARRIOR" })
moveTo(ELWYNN_MAP, 0.42, 0.65)
local owner = require("addons").byName["onemorequest"]
local addon = owner and owner.private
local accepted = {}
do
    local Q = G.LibQuestieDB.Quest
    local wanted = tonumber(mapcost.option("SWITCH_QUESTS") or "6")
    local isWanted = { [ELWYNN_AREA] = true, [WESTFALL_AREA] = true, [DUSKWOOD_AREA] = true }
    for questId = 1, 99999 do
        local isRead, zoneOrSort = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and isWanted[zoneOrSort] and #accepted < wanted then
            local level = Q.Get(questId, "questLevel") or 0
            if level >= 10 and level <= 26 and pcall(accept, questId) then
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
print("SWITCH quests tracked: " .. #accepted .. (addon and "" or " (OneMoreQuest not loaded)"))
if addon and mapcost.option("SWITCH_RENDERER") then
    addon.settings.mapRenderer = mapcost.option("SWITCH_RENDERER")
end
wait(3)

mapcost.install()
if addon then
    mapcost.timeFunction(addon.MapPins, "refresh", "full redraw")
    mapcost.timeFunction(addon.MapMarks, "compose", "compose")
    mapcost.timeFunction(addon.MapMarks, "draw", "draw")
    mapcost.timeFunction(addon.MinimapPins, "refresh", "minimap")
    mapcost.timeFunction(addon.Log, "refresh", "quest window")
    mapcost.timeFunction(addon.Log, "handleMapChanged", "quest window told of the map")
    mapcost.timeFunction(addon.MapPins, "hideBuiltIn", "game's markers hidden")
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
if addon and mapcost.option("SWITCH_LOG") == "closed" and addon.Log.isOpen() then
    addon.Log.toggle()
    wait(1)
end
print("SWITCH quest window " .. (addon and addon.Log.isOpen() and "open" or "closed"))
local rect = W.computeRect(map.ScrollContainer)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2

local switches = 0
local function drag(name, dx, dy)
    local before = map:GetMapID()
    mapChanges = 0
    local movedX, movedY
    measure(name .. ", while it moves", function()
        movedX, movedY = mapcost.drag(map, dx, dy)
    end)
    measure(name .. ", the 2 s after", function()
        wait(2) -- (OpenMap loads the zone in view once the view has stayed put 0.6 s)
    end)
    local after = map:GetMapID()
    switches = switches + (after ~= before and 1 or 0)
    print(
        string.format(
            "   %s: the view went %.2f, %.2f of the map; map %s -> %s, told of a map change %d times",
            name,
            movedX,
            movedY,
            tostring(before),
            tostring(after),
            mapChanges
        )
    )
    mapcost.sayHanging(map, name)
end
scene.input({ type = "move", x = cx, y = cy })
wait(0.5)
mapcost.sayHanging(map, "opened")
-- Back and forth over the zones round Elwynn: each drag most of a zone's width
for index, move in ipairs({
    { 420, 0 },
    { 420, 0 },
    { -420, 0 },
    { -420, 0 },
    { 0, -330 },
    { 0, 330 },
    { -420, 0 },
    { 420, 0 },
}) do
    drag("drag " .. index, move[1], move[2])
end
print("SWITCH the map underneath changed after " .. switches .. " of 8 drags")
measure("2 s, nothing happening", function()
    wait(2)
end)
if addon then
    -- What a drag ends in when it showed ground the marks were not drawn for: the marks drawn again
    measure("the marks drawn again, nothing changed", function()
        addon.MapPins.refresh()
        wait(0.1)
    end)
end
