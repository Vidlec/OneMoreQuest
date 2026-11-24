--@login race=Human,class=ROGUE,level=38
-- Marks audit: Stranglethorn Vale (see marks-common.lua)
setProfile({ level = 38 })
dofile(scenariosDir .. "/audits/marks-common.lua")(
    _ENV or getfenv(1),
    { name = "Stranglethorn Vale", uiMapId = 1434, areaId = 33, level = 38, x = 0.27, y = 0.77 }
)
