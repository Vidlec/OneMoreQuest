-- Grom'gol: which givers the minimap hands to the game's own "!", and where the hover finds them
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29) -- Grom'gol Base Camp
wait(3)
local addon = require("addons").byName["onemorequest"].private
local MP = addon.MinimapPins
io.write(
    "settings: showMapPins=",
    tostring(addon.settings.shouldShowMapPins),
    " minimap=",
    tostring(addon.settings.shouldShowMinimapPins),
    " availableOnMap=",
    tostring(addon.settings.shouldShowAvailableOnMap),
    " availableShown=",
    tostring(addon.Availability.isShownOnMap()),
    "\n"
)
local seen = {}
local half = G.Minimap:GetWidth() / 2
for y = -half, half, 2 do
    for x = -half, half, 2 do
        for _, mark in ipairs(MP.findGameMarksAt(x, y, 1.5)) do
            local key = tostring(mark.kind) .. ":" .. table.concat(mark.lines or {}, " / ")
            if not seen[key] then
                seen[key] = true
                io.write(string.format("FOUND at %d,%d px: %s\n", x, y, key))
            end
        end
    end
end
local player = addon.Model.getPlayer()
for _, quest in
    ipairs(addon.Availability.getQuests(player.zoneId, { shouldShowLowLevel = true, shouldIncludeEntrances = true }))
do
    if
        quest.starterName
        and (
            quest.starterName:find("Nimboya")
            or quest.starterName:find("Kin'weelay")
            or quest.starterName:find("Gemmil")
        )
    then
        io.write(
            string.format(
                "QUEST %s [%d] %s low=%s at=%s handedInHere=%s\n",
                quest.starterName,
                quest.level,
                quest.title,
                tostring(quest.isLowLevel),
                tostring(quest.availableAtLevel),
                tostring(quest.isHandedInHere)
            )
        )
    end
end
local composed = MP.compose(G.C_Minimap and G.C_Minimap.GetViewRadius and G.C_Minimap.GetViewRadius() or 233)
local position = addon.Geometry.getPlayerPosition()
io.write(
    "player ",
    tostring(position and position.north),
    ",",
    tostring(position and position.west),
    " map ",
    tostring(position and position.uiMapId),
    "\n"
)
for _, shown in ipairs(composed) do
    local d = position
        and shown.place.north
        and addon.Geometry.getDistance(position.north, position.west, shown.place.north, shown.place.west)
    io.write(
        string.format(
            "COMPOSED %s gameLook=%s handover=%s dist=%s handed=%s %s\n",
            tostring(shown.data.kind),
            tostring(shown.isGameLook),
            tostring(shown.handoverYards),
            tostring(d and math.floor(d)),
            tostring(MP.isHandedOver(shown, position)),
            table.concat(shown.data.lines or {}, " / ")
        )
    )
end
local viewRadius = G.C_Minimap.GetViewRadius and G.C_Minimap.GetViewRadius() or 233
for _, shown in ipairs(composed) do
    local right, up = MP.getOffset(position, shown.place, viewRadius, nil, false)
    local x, y = right and right * half, up and up * half
    io.write(
        string.format(
            "AT %s: %s,%s px (half %s, view %s) -> found %d\n",
            shown.data.lines[1],
            tostring(x),
            tostring(y),
            tostring(half),
            tostring(viewRadius),
            x and #MP.findGameMarksAt(x, y, 3) or -1
        )
    )
end
