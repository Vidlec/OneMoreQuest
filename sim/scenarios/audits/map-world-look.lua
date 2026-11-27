--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- The map as it looks with many quests tracked on OpenMap's joined-up world, left open for a picture
-- (bun addonsim shot): to compare the kept drawing with the classic one. Options (sim/lib/mapcost.options):
-- LOOK_RENDERER=classic the drawing before the kept one; LOOK_OUT=<n> wheel steps out (0), LOOK_IN=<n> steps in (0);
-- LOOK_QUESTS=<n> Riverglades quests (20); LOOK_FOCUS=<n> which of them is in focus (1)
local W, sim, scene, game = require("widgets"), require("sim"), require("scene"), require("game")
local mapcost = require("mapcost")
local RIVER_MAP, RIVER_AREA = 2548, 16591
setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = {}
do
    local Q = G.LibQuestieDB.Quest
    local wanted = tonumber(mapcost.option("LOOK_QUESTS") or "20")
    for questId = 1, 99999 do
        local isRead, zoneOrSort = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and zoneOrSort == RIVER_AREA and #accepted < wanted then
            local level = Q.Get(questId, "questLevel") or 0
            if level >= 34 and level <= 44 and pcall(accept, questId) then
                accepted[#accepted + 1] = questId
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
local addon = require("addons").byName["onemorequest"].private
if mapcost.option("LOOK_RENDERER") then
    addon.settings.mapRenderer = mapcost.option("LOOK_RENDERER")
end
if mapcost.option("LOOK_AREAS") then
    addon.settings.areaGeometry = mapcost.option("LOOK_AREAS") -- "ovals", "soft" or "traced" (the settings' "Drawn as")
end
addon.Focus.set(accepted[tonumber(mapcost.option("LOOK_FOCUS") or "1")])
wait(1)
local map = G.WorldMapFrame
key("M")
wait(1)
-- (OpenMap asks once which map to use: its own)
for _, frame in ipairs({ G.EnumerateFrames and nil }) do
    local _ = frame
end
do
    local welcome
    local frame = G.EnumerateFrames()
    while frame do
        if frame:IsObjectType("Button") and frame:IsVisible() and frame.GetText and frame:GetText() == "OpenMap" then
            welcome = frame
        end
        frame = G.EnumerateFrames(frame)
    end
    if welcome then
        welcome:Click()
    end
end
wait(1.5)
local rect = W.computeRect(map.ScrollContainer)
local cx, cy = (rect[1] + rect[3]) / 2, sim.screenHeight - (rect[2] + rect[4]) / 2
scene.input({ type = "move", x = cx, y = cy })
for _ = 1, tonumber(mapcost.option("LOOK_OUT") or "0") do
    scene.input({ type = "wheel", x = cx, y = cy, delta = -1 })
    wait(1.5)
end
for _ = 1, tonumber(mapcost.option("LOOK_IN") or "0") do
    scene.input({ type = "wheel", x = cx, y = cy, delta = 1 })
    wait(1.5)
end
if mapcost.option("LOOK_MAP") then
    map:SetMapID(tonumber(mapcost.option("LOOK_MAP"))) -- (another map: a continent's, the world's)
    wait(1.5)
end
scene.input({ type = "move", x = 5, y = 5 }) -- (the pointer off the map: no tooltip in the picture)
wait(3)
if addon.MapMarksWorld.isOn() then
    addon.MapMarksWorld.finish(map)
    wait(0.5)
    local c = addon.MapMarksWorld.getCounts(map)
    print(
        string.format(
            "LOOK kept: sets %d fills %d edges %d walks %d icons %d (level %s) todo %d",
            c.setsShown,
            c.fillsShown,
            c.edgesShown,
            c.walksShown,
            c.iconsShown,
            tostring(c.level),
            c.todo
        )
    )
end
print("LOOK map " .. tostring(map:GetMapID()) .. " scale " .. tostring(map:GetCanvasScale()))
