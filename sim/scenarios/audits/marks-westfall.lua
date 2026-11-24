--@login race=Human,class=PRIEST,level=14
-- Marks audit: Westfall (see marks-common.lua)
setProfile({ level = 14 })
dofile(scenariosDir .. "/audits/marks-common.lua")(
    _ENV or getfenv(1),
    { name = "Westfall", uiMapId = 1436, areaId = 40, level = 14, x = 0.56, y = 0.47 }
)
