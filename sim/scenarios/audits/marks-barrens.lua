--@login race=Scourge,class=MAGE,level=18
-- Marks audit: The Barrens (see marks-common.lua)
setProfile({ level = 18 })
dofile(scenariosDir .. "/audits/marks-common.lua")(_ENV or getfenv(1), { name = "The Barrens", uiMapId = 1413, areaId = 17, level = 18, x = 0.52, y = 0.31 })
