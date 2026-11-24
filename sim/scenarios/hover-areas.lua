--@login race=Tauren,class=WARRIOR,level=14
-- Hovering a quest's area or a spawn mark shows the quest's tooltip as the game's own quest areas do: the title,
-- then the objectives still to do; a spawn mark of an item's creature also says which creature. On the world map
-- (OneMoreQuest's own check while the cursor is on the map) and on the minimap (added to the game's minimap
-- tooltip, which Minimap_OnUpdate rebuilds every frame). The minimap shows the quests' areas too.
setProfile({ level = 14 })
moveTo(1413, 0.52, 0.31) -- The Barrens, by the Crossroads
local addon = require("addons").byName["onemorequest"].private
local W, sim = require("widgets"), require("sim")
for _, questId in ipairs({ 844, 869, 855 }) do -- Plainstrider Menace, Raptor Thieves, Centaur Bracers
    accept(questId)
end
wait(1.5)
addon.settings.areaStyle, addon.settings.spawnMarker = "filled", "glyph"
addon.MinimapPins.refresh()

local function getTooltipLines()
    local lines = {}
    if not G.GameTooltip:IsShown() then
        return lines
    end
    for index = 1, G.GameTooltip:NumLines() do
        local line = G["GameTooltipTextLeft" .. index]
        lines[#lines + 1] = line and line:GetText() or ""
    end
    return lines
end

local function hasTitle(lines, questId)
    local title = addon.QuestState.getQuest(questId).title
    for _, line in ipairs(lines) do
        -- (written with its level, as quest tooltips write titles: "[12] Plainstrider Menace")
        if line == title or line:match("^%[%d+%+?%] (.+)$") == title then
            return true
        end
    end
    return false
end

---@return number x, number y Screen points (from the top left, as the hover step counts) of a place on a frame
---given in the frame's own units from its upper left corner (y down)
local function toScreen(frame, x, y)
    local rect = W.computeRect(frame)
    local ratio = (rect[3] - rect[1]) / frame:GetWidth()
    return rect[1] + x * ratio, sim.screenHeight - (rect[4] - y * ratio)
end

-- The minimap: its areas are drawn, and hovering one of its spawn marks, then a bare part of an area, shows the quest
local spots, areas = addon.MinimapPins.getDrawn()
expect(#areas > 0, "the minimap shows the quests' areas (" .. #areas .. ")")
expect(#spots > 0, "and spawn marks (" .. #spots .. ")")
local function minimapPoint(x, y) -- pixels from the minimap's middle, up positive
    local half = G.Minimap:GetWidth() / 2
    return toScreen(G.Minimap, half + x, half - y)
end
if spots[1] then
    local x, y = minimapPoint(spots[1].x, spots[1].y)
    hover({ x = x, y = y })
    wait(0.1)
    local lines = getTooltipLines()
    expect(
        hasTitle(lines, spots[1].questId),
        "minimap spawn mark: its quest's title (" .. table.concat(lines, " | ") .. ")"
    )
end
-- An area's box, and whether a point is in it: areas follow their spawns (spawns and a reach)
local function getBox(area)
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    for _, v in ipairs(area.points) do
        minX, maxX, minY, maxY =
            math.min(minX, v.x - area.reach),
            math.max(maxX, v.x + area.reach),
            math.min(minY, v.y - area.reach),
            math.max(maxY, v.y + area.reach)
    end
    return minX, maxX, minY, maxY
end
local function isInArea(area, x, y)
    return addon.MapMarks.isInsideArea(area, x, y)
end
-- A point inside an area, away from every spawn mark and quest mark
local function findBare(drawnAreas, drawnSpots, isClear)
    for _, area in ipairs(drawnAreas) do
        local minX, maxX, minY, maxY = getBox(area)
        for step = 1, 300 do
            local x = minX + (maxX - minX) * ((step * 0.618034) % 1)
            local y = minY + (maxY - minY) * ((step * 0.7548777) % 1)
            if isInArea(area, x, y) and isClear(x, y) then
                local isNearSpot = false
                for _, spot in ipairs(drawnSpots) do
                    if (spot.x - x) ^ 2 + (spot.y - y) ^ 2 < 144 then
                        isNearSpot = true
                    end
                end
                if not isNearSpot then
                    local isOnMark = false
                    for _, pin in ipairs({ G.Minimap:GetChildren() }) do
                        if pin.mark and pin:IsShown() then
                            local left, bottom, width, height = pin:GetRect()
                            local pinScale = pin:GetEffectiveScale() / G.Minimap:GetEffectiveScale()
                            local half = G.Minimap:GetWidth() / 2
                            local minimapLeft, minimapBottom = G.Minimap:GetRect()
                            local cx = (left + width / 2) * pinScale - minimapLeft - half
                            local cy = (bottom + height / 2) * pinScale - minimapBottom - half
                            if (cx - x) ^ 2 + (cy - y) ^ 2 < (math.max(width, height) * pinScale / 2 + 4) ^ 2 then
                                isOnMark = true
                            end
                        end
                    end
                    if not isOnMark then
                        return area, x, y
                    end
                end
            end
        end
    end
end
local area, areaX, areaY = findBare(areas, spots, function(x, y)
    return x * x + y * y < 85 * 85
end)
expect(area ~= nil, "a bare part of an area on the minimap to hover")
if area then
    hover({ x = select(1, minimapPoint(areaX, areaY)), y = select(2, minimapPoint(areaX, areaY)) })
    wait(0.1)
    local lines = getTooltipLines()
    expect(hasTitle(lines, area.questId), "minimap area: its quest's title (" .. table.concat(lines, " | ") .. ")")
    local hasObjective = false
    for _, line in ipairs(lines) do
        if line:sub(1, 2) == "- " then
            hasObjective = true
        end
    end
    expect(hasObjective, 'and what is still to do, as "- objective" lines')
end
saveScene("minimap-area-tooltip")
-- With the minimap's own hovering taken over (as another addon may: no Minimap_OnUpdate), the tooltip still shows
if area then
    hover({ x = 20, y = 20 })
    wait(0.1)
    G.Minimap:SetScript("OnEnter", nil)
    G.Minimap:SetScript("OnUpdate", nil)
    wait(0.4)
    hover({ x = select(1, minimapPoint(areaX, areaY)), y = select(2, minimapPoint(areaX, areaY)) })
    wait(0.2)
    local lines = getTooltipLines()
    expect(
        hasTitle(lines, area.questId),
        "minimap area, without the game's minimap tooltip: its quest's title (" .. table.concat(lines, " | ") .. ")"
    )
end
hover({ x = 20, y = 20 })
wait(0.1)
expect(not G.GameTooltip:IsShown(), "off the minimap, the tooltip goes")

-- The world map
key("M")
wait(0.8)
local drawn, markLayer = addon.MapMarks.getDrawn()
expect(#drawn.areas > 0, "the map shows the quests' areas")
-- Points on the map, from its 0 to 1 position, through the area layer (the canvas' size and units)
local function mapPoint(x, y)
    local canvas = drawn.map:GetCanvas()
    return toScreen(canvas, x * canvas:GetWidth(), y * canvas:GetHeight())
end
-- Inside an area, clear of spawn marks, and not on a quest mark (a pin shows its own tooltip): tried in turn
local isHovered = false
for _, area in ipairs(drawn.areas) do
    local minX, maxX, minY, maxY = getBox(area)
    for step = 1, 60 do
        local x = minX + (maxX - minX) * ((step * 0.618) % 1)
        local y = minY + (maxY - minY) * ((step * 0.382) % 1)
        local isClear = isInArea(area, x, y)
        for _, square in ipairs(drawn.squares) do
            -- (off its spawn mark: beyond the radius OneMoreQuest hit-tests a mark by, MapHover.findQuests, and a little)
            if (square.x - x * drawn.scale) ^ 2 + (square.y - y * drawn.scale) ^ 2 < ((square.radius or 4) + 3) ^ 2 then
                isClear = false
            end
        end
        if isClear then
            local screenX, screenY = mapPoint(x / drawn.width, y / drawn.height)
            hover({ x = screenX, y = screenY })
            wait(0.15)
            local focus = G.GetMouseFoci()[1]
            if not (focus and focus.mark) then
                local lines = getTooltipLines()
                local found = addon.MapHover.findQuests({}, drawn.areas, 0, 0, x, y)
                expect(
                    found[1] and hasTitle(lines, found[1].questId),
                    "map area: its quest's title (" .. table.concat(lines, " | ") .. ")"
                )
                saveScene("map-area-tooltip")
                -- Another addon's pin there that takes no mouse (as Leatrix Maps' zone arrows): ours steps aside
                local canvas = drawn.map:GetCanvas()
                local arrow = G.CreateFrame("Frame", nil, canvas)
                arrow.isLeaMapsPin = true
                arrow:SetFrameStrata("HIGH")
                arrow.Texture = arrow:CreateTexture(nil, "ARTWORK")
                arrow.Texture:SetAllPoints()
                arrow.Texture:SetAtlas("Garr_LevelUpgradeArrow")
                arrow:SetSize(48, 54)
                arrow:SetScale(0.7 / drawn.map:GetCanvasScale())
                arrow:SetPoint("CENTER", canvas, "TOPLEFT", x / arrow:GetScale(), -y / arrow:GetScale())
                arrow:Show()
                hover({ x = 20, y = 20 })
                wait(0.15)
                hover({ x = screenX, y = screenY })
                wait(0.2)
                expect(
                    not (G.GameTooltip:IsShown() and G.GameTooltip:GetOwner() == markLayer),
                    "on another addon's pin, no area tooltip of ours"
                )
                arrow:Hide()
                isHovered = true
                break
            end
        end
    end
    if isHovered then
        break
    end
end
expect(isHovered, "a bare part of an area on the map to hover")
local square = drawn.squares[1]
expect(square ~= nil and square.questId ~= nil, "the map's spawn marks know their quest")
if square then
    local x, y = mapPoint(square.x / (drawn.width * drawn.scale), square.y / (drawn.height * drawn.scale))
    hover({ x = x, y = y })
    wait(0.2)
    local lines = getTooltipLines()
    expect(hasTitle(lines, square.questId), "map spawn mark: its quest's title (" .. table.concat(lines, " | ") .. ")")
    saveScene("map-spawn-tooltip")
end
hover({ x = 20, y = 20 })
wait(0.2)
expect(not G.GameTooltip:IsShown(), "off the map, the tooltip goes")
