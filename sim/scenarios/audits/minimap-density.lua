-- How many spawns of the tracked quests stand how far from the player, thinned as the minimap thins them at its
-- zoom: for sizing the region the minimap lays out once (MinimapPins.compose).
G.GetMinimapShape = function()
    return "SQUARE"
end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
local accepted = {}
for _, questId in ipairs({
    185,
    186,
    187,
    188,
    189,
    190,
    191,
    192,
    193,
    194,
    195,
    196,
    197,
    568,
    569,
    570,
    572,
    573,
    581,
    582,
    583,
    584,
    585,
    586,
}) do
    if #accepted < 20 and pcall(accept, questId) then
        accepted[#accepted + 1] = questId
    end
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local player = addon.Model.getPlayer()
local position = addon.Geometry.getPlayerPosition()
for _, viewRadius in ipairs({ 233, 150, 100, 66 }) do
    local spacing = addon.MapMarks.chooseSpawnSpacing(70 / viewRadius, nil)
    local reach = viewRadius * 0.94 * math.sqrt(2)
    local counts, total = { 0, 0, 0, 0, 0, 0 }, 0
    local edges = { reach, reach + 50, reach + 100, reach + 200, reach + 400, math.huge }
    for _, questId in ipairs(addon.QuestState.getWatchedQuestIds()) do
        local entry = addon.Model.composeEntry(questId, player)
        local spawns = {}
        for _, place in ipairs(entry.allPlaces or {}) do
            if place.north == nil then
                local continentId, north, west =
                    addon.Geometry.getWorldPosition(addon.Database.getUiMapId(place.zoneId), place.x, place.y)
                place.continentId, place.north, place.west = continentId, north or false, west
            end
            if place.north and place.continentId == position.continentId then
                spawns[#spawns + 1] = { place = place }
            end
        end
        for _, point in ipairs(spacing > 0 and addon.MapMarks.thinPoints(spawns, spacing) or spawns) do
            local distance =
                addon.Geometry.getDistance(position.north, position.west, point.place.north, point.place.west)
            total = total + 1
            for index, edge in ipairs(edges) do
                if distance <= edge then
                    counts[index] = counts[index] + 1
                end
            end
        end
    end
    io.write(
        string.format(
            "DENSITY view %3d yards (spacing %s): in reach %d, +50 %d, +100 %d, +200 %d, +400 %d, all %d\n",
            viewRadius,
            tostring(spacing),
            counts[1],
            counts[2],
            counts[3],
            counts[4],
            counts[5],
            counts[6]
        )
    )
end
