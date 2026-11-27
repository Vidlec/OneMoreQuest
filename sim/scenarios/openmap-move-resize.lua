--@login race=Orc,class=WARRIOR,level=6
--@addons QuestieDB, OneMoreQuest, OpenMap
-- With OpenMap the map's place and size are OpenMap's: it keeps them itself and puts them back when anything else
-- changes them. So the quest window's own drag and its resize grip hand over to OpenMap's handles: the map moved by
-- the quest window's title strip stays where it was dropped (it used to snap back), and the grip sizes the map
-- through OpenMap's own grip. With Ctrl the grip sizes the quest window alone.
screen(1920, 1080)
setProfile({ level = 6, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68)
local addon = require("addons").byName["onemorequest"].private
accept(788)
wait(2.5)
key("M")
wait(1.5)
local map, window, MapDock = G.WorldMapFrame, addon.Log.getWindow(), addon.MapDock
expect(map:IsShown() and window:IsShown(), "the map and the quest window are open, with OpenMap")
expect(G.OpenMapAPI ~= nil, "OpenMap is loaded")

-- Moved by the quest window's title strip: where it is dropped, it stays
local function getSpot()
    return math.floor(map:GetLeft() + 0.5), math.floor(map:GetTop() + 0.5)
end
local left, top = getSpot()
MapDock.startMapDrag()
-- (the mouse carries the map while it is held: here it is put down 120 to the right and 60 lower)
map:ClearAllPoints()
map:SetPoint("TOPLEFT", G.UIParent, "BOTTOMLEFT", left + 120, top - 60)
MapDock.stopMapDrag()
wait(1)
local movedLeft, movedTop = getSpot()
expect(
    math.abs(movedLeft - left - 120) <= 2 and math.abs(movedTop - top + 60) <= 2,
    "the map stays where the drag left it: " .. movedLeft .. ", " .. movedTop .. " from " .. left .. ", " .. top
)
key("M")
wait(0.5)
key("M")
wait(1.5)
local againLeft, againTop = getSpot()
expect(
    math.abs(againLeft - movedLeft) <= 2 and math.abs(againTop - movedTop) <= 2,
    "and there again at the next opening"
)

-- The grip does not fight OpenMap over the map's size: a plain drag is OpenMap's own grip's
addon.settings.mapSize = 1.4 -- (a size of ours kept from before OpenMap was installed)
local width = map:GetWidth()
MapDock.apply()
wait(0.3)
expect(math.abs(map:GetWidth() - width) < 1, "OneMoreQuest leaves the map's size to OpenMap")
addon.settings.mapSize = 1

-- With Ctrl, the quest window alone: taller than the map, its page wider
local function getHeight()
    return window:GetTop() - window:GetBottom()
end
local usualHeight, usualWidth = getHeight(), window:GetWidth()
MapDock.startResize(false, true)
MapDock.resizeTo(150, 100)
MapDock.stopResize()
wait(0.5)
expect(math.abs(map:GetWidth() - width) < 1, "Ctrl: the map as it was")
expect(math.abs(getHeight() - usualHeight - 100) < 3, "the window 100 taller: " .. (getHeight() - usualHeight))
expect(math.abs(window:GetWidth() - usualWidth - 150) < 2, "and 150 wider: " .. (window:GetWidth() - usualWidth))

-- A right click on the grip puts the usual size back: the window's, and the map's that OpenMap keeps (sized by its
-- own grip), where the map stands
local openMap = G.OpenMapDB
local kept
for _, saved in pairs(openMap or {}) do
    if type(saved) == "table" and saved.windowSize ~= nil then
        kept = saved
    end
end
expect(kept ~= nil, "OpenMap's kept settings found")
local usualMapWidth, usualMapHeight = map:GetWidth(), map:GetHeight()
kept.windowSize = { math.floor(usualMapWidth * 1.2), math.floor(usualMapHeight * 1.2) }
key("M")
wait(0.5)
key("M")
wait(1.5)
expect(map:GetWidth() > usualMapWidth + 20, "the map larger, as OpenMap keeps it: " .. map:GetWidth())
local leftBefore, topBefore = getSpot()
click(MapDock.getResizeGrip(), "RightButton")
wait(1.5)
expect(map:IsShown() and window:IsShown(), "after the right click the map and the quest window are still open")
expect(math.abs(map:GetWidth() - usualMapWidth) < 2, "the map its usual width again: " .. map:GetWidth())
expect(math.abs(getHeight() - usualHeight) < 3, "the window as tall as usual: " .. getHeight())
expect(math.abs(window:GetWidth() - usualWidth) < 2, "and as wide: " .. window:GetWidth())
local leftAfter, topAfter = getSpot()
expect(
    math.abs(leftAfter - leftBefore) <= 2 and math.abs(topAfter - topBefore) <= 2,
    "the map where it stood: " .. leftAfter .. ", " .. topAfter .. " (was " .. leftBefore .. ", " .. topBefore .. ")"
)
