--@login race=Human,class=WARRIOR,level=36
-- A quest to pick up that starts from an item creatures drop (Strahnbrad Mystery, from a Singed Note): selected on
-- the Available tab, the map shows where those creatures are, each in its own shade as on the quest page, in
-- every look of the places (icons and areas included).
setProfile({ level = 36 })
moveTo(1416, 0.58, 0.67) -- Alterac Mountains
wait(1)
local addon = require("addons").byName["onemorequest"].private
local W, S = require("widgets"), require("widgets").state
local questId
local zoneId = addon.Database.getParentZoneId(addon.Database.getAreaId(1416))
for _, quest in ipairs(addon.Availability.getQuests(zoneId, { shouldShowLowLevel = true })) do
    if quest.title == "Strahnbrad Mystery" then questId = quest.questId end
end
expect(questId ~= nil, "Strahnbrad Mystery is offered in Alterac Mountains")
key("M")
wait(0.5)
click("Available")
wait(0.5)
addon.Log.showAvailable(questId)
wait(0.5)
expect(addon.Log.getSelectedAvailableQuestId and addon.Log.getSelectedAvailableQuestId() == questId, "it is selected")

local function countIcons(look)
    addon.settings.areaStyle = look
    addon.MapPins.refresh()
    local icons, colours = 0, {}
    for _, frame in ipairs({ G.WorldMapFrame.ScrollContainer.Child:GetChildren() }) do
        for _, region in ipairs({ frame:GetRegions() }) do
            local texture = S[region].texture
            if region:IsVisible() and type(texture) == "string" and texture:find("IconLoot", 1, true) then icons = icons + 1 end
            if region:IsVisible() and type(texture) == "string" and texture:find("SoftDot", 1, true) then
                local r, g, b = region:GetVertexColor()
                colours[string.format("%.2f,%.2f,%.2f", r, g, b)] = true
            end
        end
    end
    local colourCount = 0
    for _ in pairs(colours) do colourCount = colourCount + 1 end
    return icons, colourCount
end
local icons, colours = countIcons("filled")
expect(icons > 3, "icons and areas: a bag where the creatures that drop the note are (" .. icons .. ")")
expect(colours >= 2, "each creature in its own shade (" .. colours .. " shades)")
addon.settings.areaStyle, addon.settings.spawnMarker = "filled", "glyph"
addon.MapPins.refresh()
wait(0.3)
saveScene("strahnbrad-mystery")

-- Selected, it shows where it starts, not where it is handed in; "Show turn-in" marks that
local function hasTurnInMark(mapId)
    for _, mapMark in ipairs(addon.MapMarks.compose(mapId)) do
        if mapMark.isPreview and mapMark.questId == questId then return true end
    end
    return false
end
expect(not hasTurnInMark(1424), "selecting the quest does not mark its turn-in (in Hillsbrad)")
click("Show turn-in")
wait(0.5)
expect(hasTurnInMark(1424), "Show turn-in marks it")
