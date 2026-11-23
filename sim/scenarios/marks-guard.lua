--@login race=Scourge,class=MAGE,level=18
-- A guard on the map marks (the audit in sim/scenarios/audits, one busy zone): party members and the player are
-- never covered on the world map, spawn squares never overlap one another, and none is hidden under a mark.
setProfile({ level = 18 })
local reports = dofile(scenariosDir .. "/audits/marks-common.lua")(_ENV or getfenv(1),
    { name = "The Barrens", uiMapId = 1413, areaId = 17, level = 18, x = 0.52, y = 0.31 })
-- Since 0.9.0 every mark and spawn icon stands on its own spot and none is moved apart (MapMarks.IS_LAYOUT_ON, off),
-- on the map and, since 0.10.1, on the minimap: two may overlap and an icon may lie under a mark, by design. That
-- none does holds only with the laying out on.
local isLaidOut = require("addons").byName["onemorequest"].private.MapMarks.IS_LAYOUT_ON == true
for _, report in ipairs(reports) do
    local view = report.view
    if isLaidOut then
        expect((report.overlaps["our spot / our spot"] or 0) == 0, view .. ": no two spawn squares overlap")
        expect((report.overlaps["our mark / our spot"] or 0) == 0, view .. ": no spawn square under a mark")
        expect((report.overlaps["our icon / our icon"] or 0) == 0, view .. ": no two icons overlap")
        expect((report.overlaps["our icon / our mark"] or 0) == 0, view .. ": no icon under a mark")
    end
    if view == "map" then
        for _, entry in ipairs(report.party) do
            expect(entry.covered == 0, string.format("map: the %s at %d, %d is not covered (%d%%)", entry.kind, entry.x, entry.y, entry.covered * 100))
        end
    end
end
