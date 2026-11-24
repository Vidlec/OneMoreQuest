--@login race=NightElf,class=HUNTER,level=9
-- Highlighting a quest keeps its area: The Relics of Wakening with two relics to go, each in one chest. Out of
-- focus the quest is one mark with both chests, and an area round them; highlighted, each objective has its own
-- mark with one spawn, which must still make the same area ("icons and areas").
setProfile({ level = 9, race = "NightElf", class = "HUNTER" })
moveTo(1438, 0.35, 0.55) -- Teldrassil
local addon = require("addons").byName["onemorequest"].private
local RELICS_OF_WAKENING = 483
accept(RELICS_OF_WAKENING)
progress(RELICS_OF_WAKENING, 1, 1) -- Raven Claw Talisman
progress(RELICS_OF_WAKENING, 3, 1) -- Sapphire of Sky
wait(1.5)
addon.settings.areaStyle, addon.settings.spawnMarker = "filled", "glyph"
addon.Focus.set(nil)
key("M")
wait(1)
local function countAreas()
    local count = 0
    for _, area in ipairs(addon.MapMarks.getDrawn().areas or {}) do
        if area.questId == RELICS_OF_WAKENING then
            count = count + 1
        end
    end
    return count
end
expect(countAreas() == 1, "out of focus: one area round the two chests (" .. countAreas() .. ")")
addon.Log.selectQuest(RELICS_OF_WAKENING)
wait(1)
expect(countAreas() == 1, "highlighted: the same area (" .. countAreas() .. ")")
saveScene("highlighted")
