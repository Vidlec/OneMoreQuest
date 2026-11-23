--@login race=Orc,class=WARRIOR,level=6
-- Marks audit: Durotar (see marks-common.lua)
setProfile({ level = 6 })
dofile(scenariosDir .. "/audits/marks-common.lua")(_ENV or getfenv(1), { name = "Durotar", uiMapId = 1411, areaId = 14, level = 6, x = 0.52, y = 0.68 })
