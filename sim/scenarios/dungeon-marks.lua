--@login race=Tauren,class=WARRIOR,level=33
-- A dungeon's mark: the entrance icon circled by its quests' own marks. With Leatrix Maps' icons on the map (made
-- here as Leatrix Maps makes them: frames on the canvas with their data rows, its real rows for the Barrens), the
-- quests circle Leatrix's entrance icon, OneMoreQuest draws no entrance of its own, and Leatrix's other pins
-- nearby (its zone arrows) never push the mark off the entrance.
setProfile({ level = 33 })
moveTo(1413, 0.47, 0.40) -- The Barrens, by Wailing Caverns
local addon = require("addons").byName["onemorequest"].private
-- Wailing Caverns: Leaders of the Fang, Serpentbloom, Deviate Hides, Smart Drinks;
-- Razorfen Kraul: Going, Going, Guano!, Blueleaf Tubers, A Vengeful Fate
for _, questId in ipairs({ 914, 962, 1486, 1491, 1109, 1221, 1102 }) do
    accept(questId)
end
wait(1.5)
key("M")
wait(0.8)

local map = G.WorldMapFrame
local canvas = map:GetCanvas()

---@return table[] buttons Our drawn dungeon marks, found among the canvas' frames
local function findDungeonButtons()
    local buttons = {}
    for _, layer in ipairs({ canvas:GetChildren() }) do
        for _, child in ipairs({ layer:GetChildren() }) do
            if child.mark and child.mark.kind == "dungeon" and child:IsShown() then
                buttons[child.mark.dungeonId] = child
            end
        end
    end
    return buttons
end

local function getCenter(frame)
    local left, bottom, width, height = frame:GetRect()
    local scale = frame:GetEffectiveScale()
    return (left + width / 2) * scale, (bottom + height / 2) * scale
end

local WAILING_CAVERNS, RAZORFEN_KRAUL = 718, 491
local buttons = findDungeonButtons()
for _, dungeonId in ipairs({ WAILING_CAVERNS, RAZORFEN_KRAUL }) do
    local button = buttons[dungeonId]
    expect(button ~= nil, dungeonId .. ": one mark for its quests")
    local shown = 0
    for _, orbiting in ipairs(button and button.orbiting or {}) do
        if orbiting:IsShown() then shown = shown + 1 end
    end
    expect(shown >= 2, dungeonId .. ": its quests circle the entrance (" .. shown .. ")")
    expect(button and button.entranceIcon:IsShown(), dungeonId .. ": with the entrance icon of its own")
end
saveScene("own-entrance")
-- Zoomed in on the entrance, to see the marks at their real size
local container = map.ScrollContainer
zoomMap(1)
map:PanTo(0.46, 0.364)
wait(0.5)
saveScene("own-entrance-zoomed")

-- Leatrix Maps' points of interest for the Barrens, as it makes them (Leatrix_Maps.lua, CreatePOIFrame,
-- PositionPOI and UpdatePOIScale), from its own rows (Leatrix_Maps_Icons.lua)
local ROWS = {
    { "Dungeon", 46.0, 36.4, "Wailing Caverns", atlas = "Dungeon", size = 46 },
    { "Dungeon", 42.9, 90.2, "Razorfen Kraul", atlas = "Dungeon", size = 46 },
    { "Dungeon", 49.0, 93.9, "Razorfen Downs", atlas = "Dungeon", size = 46 },
    { "Arrow", 41.2, 58.6, "Mulgore", atlas = "Garr_LevelUpgradeArrow", width = 48, height = 54 },
    { "Arrow", 49.8, 78.4, "Dustwallow Marsh", atlas = "Garr_LevelUpgradeArrow", width = 48, height = 54 },
    { "Arrow", 44.1, 91.5, "Thousand Needles", atlas = "Garr_LevelUpgradeArrow", width = 48, height = 54 },
}
local pins = {}
for _, row in ipairs(ROWS) do
    local pin = G.CreateFrame("Frame", nil, canvas)
    pin.isLeaMapsPin = true
    pin:SetFrameStrata("HIGH")
    pin:SetFrameLevel(100)
    pin.Texture = pin:CreateTexture(nil, "ARTWORK")
    pin.Texture:SetAllPoints()
    pin.Texture:SetAtlas(row.atlas)
    pin.data = { row[1], row[2], row[3], row[4] }
    pin:SetSize(row.width or row.size, row.height or row.size)
    pins[row[4]] = pin
end
local function placePins()
    local scale = 0.7 / map:GetCanvasScale()
    for _, pin in pairs(pins) do
        pin:SetScale(scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", canvas:GetWidth() * pin.data[2] / 100 / scale, -(canvas:GetHeight() * pin.data[3] / 100) / scale)
        pin:Show()
    end
end

local function expectOnLeatrixIcons(zoomText)
    buttons = findDungeonButtons()
    for dungeonId, name in pairs({ [WAILING_CAVERNS] = "Wailing Caverns", [RAZORFEN_KRAUL] = "Razorfen Kraul" }) do
        local button = buttons[dungeonId]
        expect(button ~= nil, name .. ", " .. zoomText .. ": still one mark")
        if button then
            local buttonX, buttonY = getCenter(button)
            local pinX, pinY = getCenter(pins[name])
            expect(math.abs(buttonX - pinX) < 1.5 and math.abs(buttonY - pinY) < 1.5,
                string.format("%s, %s: the quests circle Leatrix's icon (ours at %.1f, %.1f; its at %.1f, %.1f)", name, zoomText, buttonX, buttonY, pinX, pinY))
            expect(not button.entranceIcon:IsShown(), name .. ", " .. zoomText .. ": no entrance icon of ours on top of Leatrix's")
            -- None of its quests under Leatrix's arrow (drawn over ours) by Razorfen Kraul
            local arrowLeft, arrowBottom, arrowWidth, arrowHeight = pins["Thousand Needles"]:GetRect()
            local arrowScale = pins["Thousand Needles"]:GetEffectiveScale()
            for _, orbiting in ipairs(button.orbiting) do
                if orbiting:IsShown() then
                    local x, y = getCenter(orbiting)
                    local isUnder = x > arrowLeft * arrowScale and x < (arrowLeft + arrowWidth) * arrowScale
                        and y > arrowBottom * arrowScale and y < (arrowBottom + arrowHeight) * arrowScale
                    expect(not isUnder, name .. ", " .. zoomText .. ": a quest mark of its is not under Leatrix's arrow")
                end
            end
        end
    end
end

placePins()
addon.MapPins.queueRefresh()
wait(0.5)
expectOnLeatrixIcons("zoomed in")
saveScene("leatrix-entrance")
zoomMap(-1)
placePins()
addon.MapPins.queueRefresh()
wait(0.5)
expectOnLeatrixIcons("zoomed out")
saveScene("leatrix-entrance-zoomed-out")

-- Leatrix's arrow by Razorfen Kraul, inside the ring of the dungeon's quests: pointing at it reaches the map (Leatrix
-- shows its own tooltip and takes the click), not the dungeon's mark
do
    zoomMap(1)
    map:PanTo(0.43, 0.9)
    placePins()
    addon.MapPins.refresh()
    wait(0.5)
    local arrow = pins["Thousand Needles"]
    local left, bottom, width, height = arrow:GetRect()
    local scale = arrow:GetEffectiveScale()
    local x, y = (left + width / 2) * scale, (bottom + height / 2) * scale
    hover({ x = x, y = require("sim").screenHeight - y })
    wait(0.2)
    local focus = G.GetMouseFoci()[1]
    expect(not (focus and focus.mark and focus.mark.kind == "dungeon"), "Leatrix's arrow by the entrance is not under the dungeon's mark")
end
