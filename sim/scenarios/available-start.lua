--@login race=Human,class=WARRIOR,level=36
-- A quest to pick up that starts from an item creatures drop (Strahnbrad Mystery, from a Singed Note): selected on
-- the Available tab, the map shows where those creatures are, drawn as a tracked quest's places are (the kept
-- drawing: the same areas and spawn marks, by the player's settings for them), each creature named in its marks.
setProfile({ level = 36 })
moveTo(1416, 0.58, 0.67) -- Alterac Mountains
wait(1)
local addon = require("addons").byName["onemorequest"].private
local questId
local zoneId = addon.Database.getParentZoneId(addon.Database.getAreaId(1416))
for _, quest in ipairs(addon.Availability.getQuests(zoneId, { shouldShowLowLevel = true })) do
    if quest.title == "Strahnbrad Mystery" then
        questId = quest.questId
    end
end
expect(questId ~= nil, "Strahnbrad Mystery is offered in Alterac Mountains")
key("M")
wait(0.5)
click("Available")
wait(0.5)
addon.Log.showAvailable(questId)
wait(0.5)
expect(addon.Log.getSelectedAvailableQuestId and addon.Log.getSelectedAvailableQuestId() == questId, "it is selected")

-- The kept drawing shows them, as it shows a tracked quest's places (the same areas and spawn marks, the player's
-- own look for them): each creature's spawns, named with its chance in their notes
local function countSpots()
    addon.settings.areaStyle = "filled"
    addon.MapPins.refresh()
    wait(1.5) -- (the kept drawing lays its pieces out a little each frame)
    local _, spots = addon.MapMarks.World.list(G.WorldMapFrame, 1)
    local count, notes, noteCount = 0, {}, 0
    for _, spot in ipairs(spots) do
        if spot.questId == questId then
            count = count + 1
            if spot.note and not notes[spot.note] then
                notes[spot.note], noteCount = true, noteCount + 1
            end
        end
    end
    return count, noteCount
end
local spotCount, creatureCount = countSpots()
expect(spotCount > 3, "icons and areas: a spawn mark where the creatures that drop the note are (" .. spotCount .. ")")
expect(creatureCount >= 2, "each creature named in its own marks (" .. creatureCount .. " creatures)")
local keptAreas = addon.MapMarks.World.list(G.WorldMapFrame, 1)
local areaCount = 0
for _, area in ipairs(keptAreas) do
    areaCount = areaCount + (area.questId == questId and 1 or 0)
end
expect(areaCount > 0, "with an area round them, drawn as a tracked quest's (" .. areaCount .. ")")
addon.settings.areaStyle, addon.settings.spawnMarker = "filled", "glyph"
addon.MapPins.refresh()
wait(0.3)
saveScene("strahnbrad-mystery")

-- Selected, it shows where it starts, not where it is handed in; "Show turn-in" marks that
local function hasTurnInMark(mapId)
    for _, mapMark in ipairs(addon.MapMarks.compose(mapId)) do
        if mapMark.isPreview and mapMark.questId == questId then
            return true
        end
    end
    return false
end
expect(not hasTurnInMark(1424), "selecting the quest does not mark its turn-in (in Hillsbrad)")
click("Show turn-in")
wait(0.5)
expect(hasTurnInMark(1424), "Show turn-in marks it")
