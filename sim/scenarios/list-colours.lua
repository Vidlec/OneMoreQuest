-- The Available list's "!" in each quest's kind's colour: the cities' commendation signets and cloth donations
-- (repeatable) blue, as on the map.
setProfile({ level = 60, race = "Orc", class = "WARRIOR" })
moveTo(1454, 0.42, 0.38) -- Orgrimmar, by its commendation officer
wait(3)
local addon = require("addons").byName["onemorequest"].private
local scene = require("scene")
addon.settings.shouldShowRepeatable = true
addon.SettingsPage.apply()
wait(1)
addon.Log.showAvailable()
wait(2)
local counts = {}
for _, item in ipairs(scene.export()) do
    local atlas = tostring(item.atlas or ""):lower()
    if atlas == "questnormal" or atlas == "questdaily" then
        counts[atlas] = (counts[atlas] or 0) + 1
    end
end
io.write(string.format("LIST gold %d, blue %d\n", counts.questnormal or 0, counts.questdaily or 0))
expect((counts.questdaily or 0) > 0, 'repeatable quests\' "!" blue in the list')
saveScene("available-colours")
