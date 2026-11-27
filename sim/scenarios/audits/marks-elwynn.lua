--@login race=Human,class=PALADIN,level=6
-- Marks audit: Elwynn Forest (see marks-common.lua)
setProfile({ level = 6 })
dofile(scenariosDir .. "/audits/marks-common.lua")(
    _ENV or getfenv(1),
    { name = "Elwynn Forest", uiMapId = 1429, areaId = 12, level = 6, x = 0.42, y = 0.65 }
)
