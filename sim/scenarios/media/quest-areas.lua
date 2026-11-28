--@addons QuestieDB, OneMoreQuest
-- The product page's picture of where quests' objectives are: a log of the Barrens' quests, Centaur Bracers in focus,
-- the map made larger with the quest window's grip and zoomed in on the middle Barrens, the quest panels put away. The
-- quest in focus is drawn in full (its areas as soft shadows, a marker on each spawn), the other quests' numbered marks
-- and spawns around it, and the givers of quests to pick up.
local G = require("sim").G
local addon = require("addons").byName["onemorequest"].private

screen(1920, 1080)
setProfile({ level = 20, race = "Orc", class = "WARRIOR" })
moveTo(1413, 0.52, 0.31) -- The Barrens, by the Crossroads
-- The Barrens' quests for the level (zone 17 in the quest database), each taken and tracked
local quests, taken = G.LibQuestieDB.Quest, 0
for questId = 1, 9999 do
    local isRead, zone = pcall(quests.Get, questId, "zoneOrSort")
    if isRead and zone == 17 and taken < 8 then
        local level = quests.Get(questId, "questLevel") or 0
        if level >= 14 and level <= 22 and pcall(accept, questId) then
            taken = taken + 1
            G.C_QuestLog.AddQuestWatch(questId)
        end
    end
end
expect(G.C_QuestLog.IsOnQuest(855), "Centaur Bracers is in the log")
wait(2)
addon.Focus.set(855) -- Centaur Bracers: the Kolkar camps round the Crossroads
key("M")
wait(1.5)
expect(G.WorldMapFrame:IsShown(), "the map opens with M")
-- Larger, with the quest window's grip, then zoomed in as far as the map goes on the middle Barrens
local MapDock = addon.MapDock
MapDock.startResize(false)
MapDock.resizeTo(560, 380)
MapDock.stopResize()
wait(0.5)
local container = G.WorldMapFrame.ScrollContainer
container:InstantPanAndZoom(container:GetScaleForMaxZoom(), 0.45, 0.4)
wait(1.5)
expect(G.WorldMapFrame:GetCanvasZoomPercent() > 0.5, "the map is zoomed in")
-- The quest panels put away, as the arrow on the map's edge does: the map alone
MapDock.foldUntilClosed()
wait(0.5)
expect(not G.OneMoreQuestLog:IsVisible(), "the quest panels are put away")
saveScene("quest-areas", { only = { "WorldMapFrame" } })
