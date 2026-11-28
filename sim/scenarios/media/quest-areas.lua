--@addons QuestieDB, OneMoreQuest
-- The product page's picture of where quests are done: four Barrens quests whose places lie apart round the
-- Crossroads, each in a colour of its own (the harpies of the Dry Hills, the Kolkar camps, the prowlers, the pirates
-- on the coast), none in focus so each shows its own colour. The map made larger with the quest window's grip, the
-- quest panels put away, zoomed in, and the givers of quests to pick up hidden (the "!" button on the map), so the
-- areas and the spawn markers have the map to themselves. The fills at their strongest and every quest's markers at
-- full strength, as the settings allow.
local G = require("sim").G
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 16, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.31) -- The Barrens, by the Crossroads
-- Centaur Bracers, Harpy Raiders, Southsea Freebooters, Prowlers of the Barrens
for _, questId in ipairs({ 855, 867, 887, 903 }) do
    accept(questId)
    G.C_QuestLog.AddQuestWatch(questId)
end
addon.settings.areMapGiversHidden = true
addon.settings.areaFillStrength = 2
addon.settings.otherSpawnMarkers = "full"
addon.Focus.set(nil) -- (a quest in focus would leave the others grey)
wait(2)
key("M")
wait(1.5)
expect(G.WorldMapFrame:IsShown(), "the map opens with M")
-- Larger, with the quest window's grip
local MapDock = addon.MapDock
MapDock.startResize(false)
MapDock.resizeTo(440, 330)
MapDock.stopResize()
wait(0.5)
-- The quest panels put away, as the arrow on the map's edge does: the map alone
MapDock.foldUntilClosed()
wait(0.5)
expect(not G.OneMoreQuestLog:IsVisible(), "the quest panels are put away")
-- Then zoomed in round the Crossroads (folding the panels lays the map out again, at its whole zone)
local container = G.WorldMapFrame.ScrollContainer
container:InstantPanAndZoom(container:GetScaleForMaxZoom(), 0.48, 0.15)
wait(1.5)
expect(G.WorldMapFrame:GetCanvasZoomPercent() > 0.5, "the map is zoomed in")
saveScene("quest-areas", { only = { "WorldMapFrame" } })
