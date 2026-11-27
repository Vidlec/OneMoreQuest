--@login race=Tauren,class=WARRIOR,level=14
-- The tracker's right-click Open in the quest log, with the map closed: the map opens on the quest's zone (not the
-- player's), and the quest's page is open.
setProfile({ level = 14 })
moveTo(1413, 0.52, 0.31) -- The Barrens
local addon = require("addons").byName["onemorequest"].private
accept(870) -- The Forgotten Pools, in the Barrens
accept(1060) -- Letter to Jin'Zil: handed in at Stonetalon Mountains
wait(1.5)
expect(not G.WorldMapFrame:IsShown(), "the map is closed")
local entry
for _, group in ipairs(addon.Model.compose(nil).groups) do
    for _, candidate in ipairs(group.entries) do
        entry = candidate.questId == 1060 and candidate or entry
    end
end
print("QUEST ZONE", entry and entry.zoneId, "map zone for it", entry and addon.Database.getUiMapId(entry.zoneId))
-- Right-click the quest in the tracker, then the menu's Open in the quest log
addon.Tracker.openQuestMenu(entry, G.UIParent)
wait(0.3)
click("Open in the quest log")
wait(1)
print("MAP", G.WorldMapFrame:IsShown(), G.WorldMapFrame:GetMapID(), "SELECTED", addon.Log.getSelectedQuestId())
expect(G.WorldMapFrame:IsShown(), "the map opened")
expect(addon.Log.getSelectedQuestId() == 1060, "its page is open")
expect(
    G.WorldMapFrame:GetMapID() == addon.Database.getUiMapId(entry.zoneId),
    "the map shows the quest's zone, not the player's"
)
