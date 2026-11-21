local _, ns = ...

-- Joins Trailhead's quest panels to the game's own world map, in place of the map's native quest panel. The
-- map stays the game's: zooming, dragging, continents and flight points are untouched. The map key and the
-- quest log key both open the pair.
local MapDock = {}
ns.MapDock = MapDock

local isCreated = false
local panelToggle -- the arrow at the map's lower right corner that folds the quest panels away or back
local isSettling = false -- MapDock.apply called once the map and other addons have laid out (MapDock.settle)
local placeGiverToggle -- defined with the button, below
local giverToggle -- the "!" beside it that hides the quest givers' marks on the map, or brings them back
local hasTakenOver = false -- Trailhead has changed the map window and owes it a restore when switched off

local function isReplacing()
    return ns.settings.shouldReplaceQuestLog == true
end

local EDGE_TOLERANCE = 2 -- how close a bar must sit to the map's edge to count as part of the map window

---@return boolean isShown The game's own border is drawn round the map, as it is unless a map addon took it off
local function isNativeBorderShown(map)
    local borderFrame = type(map.BorderFrame) == "table" and map.BorderFrame or nil
    local nineSlice = borderFrame and type(borderFrame.NineSlice) == "table" and borderFrame.NineSlice or nil
    if not nineSlice then
        return true
    end
    return nineSlice:IsShown() == true and (nineSlice:GetAlpha() or 1) > 0
end

---@return boolean isDrawn The frame or a frame inside it draws something: a texture or text that is shown. The
---game keeps invisible frames round the map that only hold space, such as the one above it for the title.
local function isDrawn(frame, depth)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsShown() and (region:GetAlpha() or 1) > 0 then
            return true
        end
    end
    if depth >= 2 then
        return false
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsShown() and (child:GetAlpha() or 1) > 0 and isDrawn(child, depth + 1) then
            return true
        end
    end
    return false
end

---@return number[]? color The colour of a map addon's title bar: its first plain-coloured picture, as Leatrix
---Maps draws its bar; nil when it has none or it is a picture with its own colours
local function getBarColor(bar)
    for _, region in ipairs({ bar:GetRegions() }) do
        if type(region.GetObjectType) == "function" and region:GetObjectType() == "Texture" and region:IsShown() then
            local red, green, blue = region:GetVertexColor()
            -- A white tint means the picture keeps its own colours, which cannot be read
            if red and not (red > 0.95 and green > 0.95 and blue > 0.95) then
                return { red, green, blue }
            end
        end
    end
    return nil
end

---Stands the panels beside what is seen of the map. With the game's border that is the map window itself. A
---map addon that takes the border off and draws its own round the map, as Leatrix Maps' simple map frame does,
---leaves the window larger than what is seen: then the panels go beside the map's picture, stretched over the
---bars that addon sets right on top of it and right under it (a title bar, a footer with coordinates).
local function placePanels(map)
    local container = type(map.ScrollContainer) == "table" and map.ScrollContainer or nil
    local top, bottom = container and container:GetTop(), container and container:GetBottom()
    if isNativeBorderShown(map) or not top or not bottom then
        ns.Log.setMapEdge(map, -2, 0, 0, { hasNativeBorder = true })
        return
    end
    local left, right, width = container:GetLeft(), container:GetRight(), container:GetWidth()
    local topExtra, bottomExtra, topBar = 0, 0, nil
    for _, child in ipairs({ map:GetChildren() }) do
        local childTop, childBottom = child:GetTop(), child:GetBottom()
        local childLeft, childRight = child:GetLeft(), child:GetRight()
        local isBar = child ~= container and child:IsShown() and (child:GetAlpha() or 1) > 0
            and childTop and childBottom and childLeft and childRight
            and childLeft < right and childRight > left and childRight - childLeft >= width / 2
            and isDrawn(child, 0)
        if isBar and math.abs(childBottom - top) <= EDGE_TOLERANCE and childTop - top > topExtra then
            topExtra, topBar = childTop - top, child
        elseif isBar and math.abs(childTop - bottom) <= EDGE_TOLERANCE then
            bottomExtra = math.max(bottomExtra, bottom - childBottom)
        end
    end
    -- What the map's own frame looks like, for the border that copies it
    local mapLook = { hasNativeBorder = false, barHeight = topBar and topExtra or nil, barColor = topBar and getBarColor(topBar) }
    ns.Log.setMapEdge(container, 2, topExtra, bottomExtra, mapLook)
end

---Hides the native quest panel, shows Trailhead's beside the windowed map, and tells the game how much wider
---the pair is so it stays centred on screen. Runs after every change of the map's display state.
---Lets the game's window layout take in the room set aside beside the map. When another addon keeps the map where the
---player moved it (Compatibility: placesMap), the map stays there instead of going to the layout's usual spot.
local function updatePanelPositions(map)
    if not UpdateUIPanelPositions then
        return
    end
    local points = {}
    if ns.Compatibility.isMapPlacedByAddOn() then
        for index = 1, map:GetNumPoints() do
            points[index] = { map:GetPoint(index) }
        end
    end
    UpdateUIPanelPositions(map)
    if #points > 0 then
        map:ClearAllPoints()
        for _, point in ipairs(points) do
            map:SetPoint(unpack(point))
        end
    end
end

local isFoldedTillClosed = false -- the panels were put away by their close button while the map could not be closed

---Puts the panels away until the map is next closed: for the close button, when the game will not close the map.
function MapDock.foldUntilClosed()
    isFoldedTillClosed = ns.settings.arePanelsHidden ~= true
    ns.settings.arePanelsHidden = true
    MapDock.apply()
end

function MapDock.apply()
    local map = WorldMapFrame
    if not map then
        return
    end
    if isFoldedTillClosed and not map:IsShown() then
        isFoldedTillClosed = false
        ns.settings.arePanelsHidden = false -- the map is closed now: opened again, the panels are beside it as before
    end
    local isWindowed = map:IsShown() == true and not map:IsMaximized()
    local isDocked = isReplacing() and isWindowed and not ns.settings.arePanelsHidden
    if panelToggle then
        panelToggle:SetShown(isReplacing() and isWindowed)
        MapDock.updatePanelToggle()
    end
    if giverToggle then
        -- Only while there are givers of ours to hide: the map marks and the quests to pick up both on
        local isGiverToggleShown = map:IsShown() == true and ns.settings.shouldShowMapPins == true and ns.Availability.isShownOnMap()
        giverToggle:SetShown(isGiverToggleShown)
        if isGiverToggleShown then
            placeGiverToggle(map, isSettling)
            MapDock.updateGiverToggle()
        end
    end
    if isReplacing() then
        -- The game remembers whether its own quest panel should be open. While it thinks so, the map key
        -- refuses to close the map and only "hides the panel", so the game is told the panel is closed.
        if GetCVar and SetCVar and GetCVar("questLogOpen") ~= "0" then
            SetCVar("questLogOpen", 0)
        end
        if type(map.QuestLog) == "table" and map.QuestLog:IsShown() and map.SetQuestLogPanelShown then
            map:SetQuestLogPanelShown(false)
            -- The map had already set aside room for its own panel; give that room back to the map
            if map.UpdateSpacerFrameAnchoring then
                map:UpdateSpacerFrameAnchoring()
            end
        end
        if type(map.SidePanelToggle) == "table" then
            map.SidePanelToggle:Hide() -- the arrow that reopens the native panel
        end
    end
    if isDocked then
        placePanels(map)
    end
    ns.Log.setDocked(isDocked)
    -- Other addons that have to make room for the window, or work around it (Compatibility\)
    ns.Compatibility.handleDockChanged(isDocked)
    if isReplacing() then
        hasTakenOver = true
        -- The room the game's layout keeps beside the map: the window's width at the size the player chose
        local extraWidth = isDocked and math.floor(ns.Log.PANEL_WIDTH * ns.Log.getWindowScale() + 0.5) or 0
        if SetUIPanelAttribute and map:GetAttribute("UIPanelLayout-extraWidth") ~= extraWidth then
            SetUIPanelAttribute(map, "extraWidth", extraWidth)
            updatePanelPositions(map)
        end
    elseif hasTakenOver then
        -- Switched off: everything Trailhead changed on the map is handed back, once. The width it reserved
        -- beside the map goes, the arrow that opens the game's quest panel returns, and on an open map the
        -- game's panel comes back straight away.
        hasTakenOver = false
        if SetUIPanelAttribute then
            SetUIPanelAttribute(map, "extraWidth", 0)
        end
        local isWindowed = map:IsShown() == true and not map:IsMaximized()
        if type(map.SidePanelToggle) == "table" and isWindowed then
            map.SidePanelToggle:Show()
            if map.SidePanelToggle.Refresh then
                map.SidePanelToggle:Refresh()
            end
        end
        if isWindowed and type(map.QuestLog) == "table" and map.SetQuestLogPanelShown then
            map:SetQuestLogPanelShown(true)
            if map.UpdateSpacerFrameAnchoring then
                map:UpdateSpacerFrameAnchoring()
            end
        else
            updatePanelPositions(map)
        end
    end
end

---Looks again once the map and other addons have laid out their frames for the opening: the panels are placed
---again, and the quest window drawn again only if that changed its size (Log.setDocked).
function MapDock.settle()
    isSettling = true -- (the "!" button looks for other addons' buttons now: they have their places)
    MapDock.apply()
    isSettling = false
end

---Shows the arrow's state: pointing left to fold the panels away while they are out, right to bring them back.
function MapDock.updatePanelToggle()
    if not panelToggle then
        return
    end
    local isHidden = ns.settings.arePanelsHidden == true
    local normal, pushed = isHidden and "QuestCollapse-Show-Up" or "QuestCollapse-Hide-Up", isHidden and "QuestCollapse-Show-Down" or "QuestCollapse-Hide-Down"
    if panelToggle.SetNormalAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(normal) then
        panelToggle:SetNormalAtlas(normal)
        panelToggle:SetPushedAtlas(pushed)
    else
        panelToggle:SetNormalTexture(isHidden and "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up" or "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    end
end

---The game's own arrow at the map's lower right, where it sits for the game's quest panel: it folds the quest
---panels away, leaving the map alone to travel with, and brings them back.
local function createPanelToggle(map)
    local container = map.GetCanvasContainer and map:GetCanvasContainer() or map
    local button = CreateFrame("Button", nil, map)
    button:SetSize(32, 32)
    button:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -2, 1)
    button:SetFrameLevel((map:GetFrameLevel() or 1) + 500)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function()
        ns.settings.arePanelsHidden = not ns.settings.arePanelsHidden
        MapDock.apply()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L(ns.settings.arePanelsHidden and "Show the quest panels" or "Hide the quest panels"), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

-- The "!" button: a dark square with a bronze rim, as the game's map buttons, the "!" in the colour of a normal
-- quest's; greyed while the givers are hidden. Its place: left of the arrow (or in the corner without it), moved
-- further left past any other addon's button there, looked at when the map opens (never while it is open).
local TOGGLE_SIZE, TOGGLE_GAP = 30, 4
local TOGGLE_RIM, TOGGLE_FACE = { 0.42, 0.29, 0.15 }, { 0.06, 0.05, 0.035 }
local MAX_BUTTON_SIZE = 80 -- frames larger than this are panels and layers, not buttons in the way

---Shows the "!" as the givers are: bright while shown, greyed and faint while hidden.
function MapDock.updateGiverToggle()
    if not giverToggle then
        return
    end
    local isHidden = ns.settings.areMapGiversHidden == true
    ns.MapMarks.dressQuestIcon(giverToggle.icon, ns.MapMarks.getIconColour("normal"), false, isHidden)
    giverToggle.icon:SetAlpha(isHidden and 0.45 or 1)
end

---@return boolean isInTheWay Another visible frame, button-sized, covers any of the rectangle (in screen pixels:
---each frame's own units times its scale, as addons' buttons may be scaled otherwise than ours)
local function isCovered(frames, left, bottom, right, top)
    for _, frame in ipairs(frames) do
        if frame ~= giverToggle and frame ~= panelToggle and frame.IsVisible and frame:IsVisible() then
            local frameLeft, frameBottom, width, height = frame:GetRect()
            local scale = frame:GetEffectiveScale() or 1
            if frameLeft and width and width > 0 and width <= MAX_BUTTON_SIZE and height <= MAX_BUTTON_SIZE then
                frameLeft, frameBottom, width, height = frameLeft * scale, frameBottom * scale, width * scale, height * scale
                if frameLeft < right and frameLeft + width > left and frameBottom < top and frameBottom + height > bottom then
                    return true
                end
            end
        end
    end
    return false
end

---Puts the "!" left of the arrow, then further left while another addon's button covers its place.
function placeGiverToggle(map, isAfterLayout)
    local container = map.GetCanvasContainer and map:GetCanvasContainer() or map
    local offset = -2 - ((panelToggle and panelToggle:IsShown()) and (32 + TOGGLE_GAP) or 0)
    giverToggle:ClearAllPoints()
    giverToggle:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", offset, 2)
    if not isAfterLayout then
        return -- (the other addons' buttons are looked at once they have their places: MapDock.settle)
    end
    local frames = { map:GetChildren() }
    for _, child in ipairs({ container:GetChildren() }) do
        frames[#frames + 1] = child
    end
    local scale = giverToggle:GetEffectiveScale() or 1
    for _ = 1, 8 do
        local left, bottom, width, height = giverToggle:GetRect()
        if not left or not isCovered(frames, left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale) then
            return
        end
        offset = offset - (TOGGLE_SIZE + TOGGLE_GAP)
        giverToggle:ClearAllPoints()
        giverToggle:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", offset, 2)
    end
end

local function createGiverToggle(map)
    local button = CreateFrame("Button", nil, map)
    button:SetSize(TOGGLE_SIZE, TOGGLE_SIZE)
    button:SetFrameLevel((map:GetFrameLevel() or 1) + 500)
    local rim = button:CreateTexture(nil, "BACKGROUND")
    rim:SetAllPoints(button)
    rim:SetColorTexture(TOGGLE_RIM[1], TOGGLE_RIM[2], TOGGLE_RIM[3], 1)
    local face = button:CreateTexture(nil, "BORDER")
    face:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
    face:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
    face:SetColorTexture(TOGGLE_FACE[1], TOGGLE_FACE[2], TOGGLE_FACE[3], 0.92)
    button.icon = ns.Widgets.remember(button:CreateTexture(nil, "ARTWORK"))
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.icon:SetSize(TOGGLE_SIZE - 6, TOGGLE_SIZE - 6)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    button:SetScript("OnClick", function(self)
        ns.settings.areMapGiversHidden = not ns.settings.areMapGiversHidden
        MapDock.updateGiverToggle()
        ns.MapPins.refresh()
        if GameTooltip:IsOwned(self) then
            self:GetScript("OnEnter")(self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L(ns.settings.areMapGiversHidden and "Show quests to pick up" or "Hide quests to pick up"), 1, 1, 1)
        GameTooltip:AddLine(ns.L("The \"!\" of quest givers on this map; the minimap keeps them."), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()
    return button
end

---Opens the map in its windowed form, which is the one with room for the panels. Asking for the panels
---brings them back if the arrow had folded them away.
function MapDock.open()
    local map = WorldMapFrame
    if not map then
        return
    end
    ns.settings.arePanelsHidden = false
    if not map:IsShown() then
        ShowUIPanel(map)
    end
    if map:IsShown() and map:IsMaximized() and map.HandleUserActionMinimizeSelf then
        map:HandleUserActionMinimizeSelf()
    end
    MapDock.apply()
end

---The quest log key: closes the pair when it is open, opens it otherwise.
function MapDock.toggle()
    local map = WorldMapFrame
    if not map then
        return
    end
    if map:IsShown() and not map:IsMaximized() then
        HideUIPanel(map)
    else
        MapDock.open()
    end
end

---Turns the map to another map. An open map is told directly; a closed one is opened on it, which the game
---does not allow addons to do during combat.
function MapDock.showMap(uiMapId)
    local map = WorldMapFrame
    if not uiMapId or not map then
        return
    end
    -- A map the game has no picture for breaks the map window when it is asked to show it
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(uiMapId)
    if C_Map.GetMapArtLayers and (not layers or #layers == 0) then
        return
    end
    if map:IsShown() then
        if map:GetMapID() ~= uiMapId then
            map:SetMapID(uiMapId)
        end
    elseif C_Map.OpenWorldMap and not InCombatLockdown() then
        C_Map.OpenWorldMap(uiMapId)
    end
end

---Turns the map to a zone, if it is not already showing it.
---Turns the map to the zone of a place. It leaves no pin of the game's behind: OneMoreQuest's own marks show the
---place, and a game pin would stay after it was wanted and sit under those marks.
---@return boolean isShown False for places without map coordinates, such as inside a dungeon
function MapDock.showPlaceZone(place)
    local uiMapId = place and ns.Database.getUiMapId(place.zoneId)
    if not uiMapId or place.x < 0 then
        return false
    end
    MapDock.showMap(uiMapId)
    return true
end

function MapDock.showZoneMap(zoneId)
    MapDock.showMap(zoneId and ns.Database.getUiMapId(ns.Database.getMapZoneId(zoneId)))
end

---Turns the map to a quest's zone and, when the map is zoomed in, slides it so the place is in the middle.
---A map zoomed all the way out shows the whole zone already and stays put.
---@param place table? Where the quest's step is; nil only turns the map
function MapDock.showQuestPlace(zoneId, place)
    MapDock.showZoneMap(zoneId)
    local map = WorldMapFrame
    if not place or not map or not map:IsShown() or not map.PanTo then
        return
    end
    local zoom = map.GetCanvasZoomPercent and map:GetCanvasZoomPercent()
    if type(zoom) == "number" and zoom <= 0 then
        return
    end
    local x, y = ns.MapPins.getMapPosition(place, map:GetMapID(), true)
    if x then
        map:PanTo(x, y)
    end
end

---@return number? zoneId The zone the world map shows now
function MapDock.getShownZoneId()
    if not WorldMapFrame or type(WorldMapFrame.GetMapID) ~= "function" then
        return nil
    end
    local uiMapId = WorldMapFrame:GetMapID()
    local areaId = uiMapId and ns.Database.getAreaId(uiMapId)
    return areaId and ns.Database.getParentZoneId(areaId) or nil
end

---A quest that can be done in several zones: turns the map to the next of them after the one it shows, the
---first again after the last, and slides it to the quest's place there.
---@return number index Which of the quest's zones the map shows, 0 for none of them
local function getShownZoneIndex(entry)
    local shownZoneId, shownIndex = MapDock.getShownZoneId(), 0
    for index, zoneId in ipairs(entry.zoneIds or {}) do
        if shownIndex == 0 and (zoneId == shownZoneId or ns.Database.getMapZoneId(zoneId) == shownZoneId) then
            shownIndex = index
        end
    end
    return shownIndex
end

---@return table? place The quest's first known place in a zone
local function getPlaceInZone(entry, zoneId)
    for _, place in ipairs(entry.allPlaces or {}) do
        if place.x >= 0 and (place.groupZoneId == zoneId or place.mapZoneId == zoneId) then
            return place
        end
    end
    return nil
end

---Turns the map to the next of a quest's zones, and remembers it: the map returns there whenever the quest is
---chosen later.
function MapDock.showNextQuestZone(entry)
    local zoneIds = entry.zoneIds
    if not zoneIds or #zoneIds == 0 then
        return
    end
    local zoneId = zoneIds[getShownZoneIndex(entry) % #zoneIds + 1]
    ns.settings.cycledQuestZones[entry.questId] = zoneId
    MapDock.showQuestPlace(zoneId, getPlaceInZone(entry, zoneId))
end

---Turns the map to a quest chosen in the list or the tracker: to the zone last picked from its "Also in" line,
---when it is still one of the quest's zones, otherwise to where its next step is.
function MapDock.showQuest(entry)
    local cycledZoneId = ns.settings.cycledQuestZones[entry.questId]
    for _, zoneId in ipairs(entry.zoneIds or {}) do
        if zoneId == cycledZoneId then
            MapDock.showQuestPlace(zoneId, getPlaceInZone(entry, zoneId))
            return
        end
    end
    MapDock.showQuestPlace(entry.zoneId, entry.nearestPlace or entry.places[1])
end

local SHOWN_ZONE_ARROW = "|TInterface\\ChatFrame\\ChatFrameExpandArrow:12:12|t " -- before the zone on the map
local ZONE_INDENT = "      " -- about the arrow's room before the others, so the names line up

---Every zone a quest can be done in, for its tooltip: where the cycle stands ("2 of 9"), and an arrow at the
---zone the map shows, which moves with each click.
function MapDock.addZonesToTooltip(tooltip, entry)
    local zoneIds = entry.zoneIds or {}
    local shownIndex = getShownZoneIndex(entry)
    local heading = ns.L(entry.categoryId and "Done in" or "Can be done in")
    local where = shownIndex > 0 and ns.L("%d of %d", shownIndex, #zoneIds) or ns.Lp(#zoneIds, "%d zones", "%d zones")
    tooltip:AddDoubleLine(heading, where, 1, 0.82, 0, 0.8, 0.78, 0.72)
    for index, zoneId in ipairs(zoneIds) do
        if index == shownIndex then
            tooltip:AddDoubleLine(SHOWN_ZONE_ARROW .. ns.Database.getZoneName(zoneId), ns.L("on the map"), 1, 1, 1, 1, 0.82, 0)
        else
            tooltip:AddLine(ZONE_INDENT .. ns.Database.getZoneName(zoneId), 0.8, 0.78, 0.72)
        end
    end
    tooltip:AddLine(ns.L("Click to show the next one on the map"), 0.5, 0.8, 0.5)
end

local playerMapId -- the map the player was last seen on

---Keeps an open map on the player: when the player walks onto another map while the open map still shows
---the one just left, the map turns to the new one. A map the player browsed away to is left alone.
function MapDock.followPlayer()
    local newMapId = C_Map.GetBestMapForUnit("player")
    if not newMapId or newMapId == playerMapId then
        return
    end
    local map = WorldMapFrame
    local isFollowing = ns.settings.shouldMapFollowPlayer
    if isFollowing and playerMapId and map and map:IsShown() and map:GetMapID() == playerMapId then
        map:SetMapID(newMapId)
    end
    playerMapId = newMapId
end

function MapDock.create()
    if isCreated or not WorldMapFrame or not hooksecurefunc then
        return
    end
    isCreated = true
    panelToggle = createPanelToggle(WorldMapFrame)
    giverToggle = createGiverToggle(WorldMapFrame)
    hooksecurefunc(WorldMapFrame, "SetDisplayState", function() ns.Timing.measure("map layout (display state)", MapDock.apply) end)
    WorldMapFrame:HookScript("OnShow", function()
        ns.Timing.startOpening()
        ns.Timing.measure("opening (quest window included)", MapDock.apply)
        -- Map addons lay out their own frame as the map opens too; look again once everything has its place
        if C_Timer then
            C_Timer.After(0, function() ns.Timing.measure("second look", MapDock.settle) end)
        end
    end)
    WorldMapFrame:HookScript("OnHide", MapDock.apply) -- closing with Escape does not go through the map's own toggle
    -- A new screen size or UI scale with the map open: the panels are fitted beside it again
    local screenWatcher = CreateFrame("Frame")
    screenWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
    screenWatcher:RegisterEvent("UI_SCALE_CHANGED")
    screenWatcher:SetScript("OnEvent", function()
        if C_Timer then
            C_Timer.After(0, MapDock.apply) -- once the game has laid its own windows out for the new size
        else
            MapDock.apply()
        end
    end)
    MapDock.apply()
end

---Hands the quest panel back to the game, for when Trailhead's panels are switched off.
function MapDock.restoreBuiltInPanel()
    if SetCVar then
        SetCVar("questLogOpen", 1)
    end
end

ns.registerModule({
    name = "MapDock",
    create = MapDock.create,
    needsWorldMap = true,
    tick = MapDock.followPlayer,
    -- The zone the map cycles to for a quest is kept until the quest is done
    prune = function()
        local cycled = ns.settings.cycledQuestZones or {}
        for questId in pairs(cycled) do
            if ns.QuestState.isTurnedIn(questId) then
                cycled[questId] = nil
            end
        end
    end,
})
