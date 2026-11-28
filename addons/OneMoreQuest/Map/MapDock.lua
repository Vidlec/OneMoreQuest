local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Joins OneMoreQuest's quest panels to the game's own world map, in place of the map's native quest panel. The
-- map stays the game's: zooming, dragging, continents and flight points are untouched. The map key and the
-- quest log key both open the pair.
local MapDock = {}
ns.MapDock = MapDock

local isCreated = false
local panelToggle -- the arrow at the map's lower right corner that folds the quest panels away or back
local isSettling = false -- MapDock.apply called once the map and other addons have laid out (MapDock.settle)
local placeGiverToggle -- defined with the button, below
local giverToggle -- the "!" beside it that hides the quest givers' marks on the map, or brings them back
local hasTakenOver = false -- OneMoreQuest has changed the map window and owes it a restore when switched off

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

---The game's own quest panel seen, or kept out of sight (the gamepad interface: open, under the window). Only its
---alpha: no script of the game's runs.
local function setNativePanelSeen(map, isSeen)
    local panel = type(map.QuestLog) == "table" and map.QuestLog or nil
    if panel and panel.SetAlpha and (panel:GetAlpha() > 0.5) ~= isSeen then
        panel:SetAlpha(isSeen and 1 or 0)
    end
end

---@return number width How much of the map window the game's quest panel takes now, from its left edge to the
---window's right, in the screen's units: open but out of sight with the gamepad interface, the window stands over it
---(no empty room where it is), and the room beside the map is that much less
local function getOpenPanelWidth(map)
    local panel = type(map.QuestLog) == "table" and map.QuestLog or nil
    if not panel or not panel:IsShown() or panel:GetAlpha() > 0.5 then
        return 0
    end
    local panelLeft, mapRight = panel:GetLeft(), map:GetRight()
    if not panelLeft or not mapRight then
        return 0
    end
    local screenScale = UIParent:GetEffectiveScale()
    return math.max(0, (mapRight * map:GetEffectiveScale() - panelLeft * panel:GetEffectiveScale()) / screenScale)
end

---@return boolean isBar A frame of the map is a bar of a map addon across the map's picture: shown, drawn, and at
---least half as wide as the picture, over it (left and right: the picture's edges, width: its width)
local function isBarAcross(child, left, right, width)
    if not child:IsShown() or (child:GetAlpha() or 1) <= 0 then
        return false
    end
    local childTop, childBottom = child:GetTop(), child:GetBottom()
    local childLeft, childRight = child:GetLeft(), child:GetRight()
    if not (childTop and childBottom and childLeft and childRight) then
        return false
    end
    return childLeft < right and childRight > left and childRight - childLeft >= width / 2 and isDrawn(child, 0)
end

---The bars a map addon sets right on top of the map's picture and right under it (a title bar, a footer with
---coordinates), told by where they stand against the picture's top and bottom.
---@return number topExtra, number bottomExtra, table? topBar How far they reach past the picture, and the bar on top
local function findMapBars(map, container, top, bottom)
    local left, right, width = container:GetLeft(), container:GetRight(), container:GetWidth()
    local topExtra, bottomExtra, topBar = 0, 0, nil
    for _, child in ipairs({ map:GetChildren() }) do
        if child ~= container and isBarAcross(child, left, right, width) then
            local childTop, childBottom = child:GetTop(), child:GetBottom()
            if math.abs(childBottom - top) <= EDGE_TOLERANCE and childTop - top > topExtra then
                topExtra, topBar = childTop - top, child
            elseif math.abs(childTop - bottom) <= EDGE_TOLERANCE then
                bottomExtra = math.max(bottomExtra, bottom - childBottom)
            end
        end
    end
    return topExtra, bottomExtra, topBar
end

---Stands the panels beside what is seen of the map. With the game's border that is the map window itself. A
---map addon that takes the border off and draws its own round the map, as Leatrix Maps' simple map frame does,
---leaves the window larger than what is seen: then the panels go beside the map's picture, stretched over the
---bars that addon sets right on top of it and right under it (a title bar, a footer with coordinates).
local function placePanels(map)
    local container = type(map.ScrollContainer) == "table" and map.ScrollContainer or nil
    local top, bottom = container and container:GetTop(), container and container:GetBottom()
    if isNativeBorderShown(map) or not top or not bottom then
        -- (over the game's quest panel where it is open out of sight: the gamepad interface)
        local covered = getOpenPanelWidth(map)
        if covered > 0 then
            covered = covered * UIParent:GetEffectiveScale() / map:GetEffectiveScale()
        end
        ns.Log.setMapEdge(map, -2 - covered, 0, 0, { hasNativeBorder = true })
        return
    end
    local topExtra, bottomExtra, topBar = findMapBars(map, container, top, bottom)
    -- What the map's own frame looks like, for the border that copies it
    local mapLook =
        { hasNativeBorder = false, barHeight = topBar and topExtra or nil, barColor = topBar and getBarColor(topBar) }
    ns.Log.setMapEdge(container, 2, topExtra, bottomExtra, mapLook)
end

---Hides the native quest panel, shows OneMoreQuest's beside the windowed map, and tells the game how much wider
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
    UpdateUIPanelPositions(map) -- (where the player moved the map: the hook below, placeMovedMap)
    if #points > 0 then
        map:ClearAllPoints()
        for _, point in ipairs(points) do
            map:SetPoint(unpack(point))
        end
    end
end

-- The map moved by the quest window's title strip (out of a fight): the window is joined to it, so the two go
-- together. Where it was put is kept (settings.mapSpot, the screen's units) and given to the map again whenever the
-- game's window layout places it, unless a map addon places the map itself (Compatibility: placesMap).
local isMapDragged = false

-- A map addon's own handles on the map (OpenMap's title strip that moves the map, its grips that size it): such an
-- addon keeps the map's place and size itself and puts them back when anything else changes them, so a drag of
-- ours is handed to its handle (its own scripts run, and it remembers what the drag did). Known by what they are,
-- not by whose: a child of the map along its top that takes a drag, a small button in its lower right corner that
-- follows the mouse while held. Looked for once each time the map is shown.
local foreignMover, foreignResizer, areHandlesKnown = nil, nil, false

local HANDLE_MAX_HEIGHT = 48 -- a handle is a strip or a small button, never a panel
local MOVER_TOP_TOLERANCE, RESIZER_CORNER_TOLERANCE = 6, 16 -- how near the map's top, or its lower right corner

---@return boolean isMover A child of the map along its top that takes a drag (in the map's units, as top is)
local function isMoverHandle(child, top, childTop, height)
    return child:GetScript("OnDragStart") ~= nil
        and child:GetScript("OnDragStop") ~= nil
        and math.abs(childTop - top) <= MOVER_TOP_TOLERANCE
        and height <= HANDLE_MAX_HEIGHT
end

---@return boolean isResizer A small button in the map's lower right corner that follows the mouse while held
---@param awayRight number How far its right edge is from the map's (awayBottom: its bottom), in the map's units
local function isResizerHandle(child, awayRight, awayBottom, height)
    return child:GetScript("OnMouseDown") ~= nil
        and child:GetScript("OnMouseUp") ~= nil
        and child:GetScript("OnUpdate") ~= nil
        and math.abs(awayRight) <= RESIZER_CORNER_TOLERANCE
        and math.abs(awayBottom) <= RESIZER_CORNER_TOLERANCE
        and height <= HANDLE_MAX_HEIGHT
end

---Looks at one child of the map for a handle not found yet, in the map's units (its scale against the map's).
local function findHandleIn(child, mapScale, top, right, bottom)
    local share = (child:GetEffectiveScale() or mapScale) / mapScale
    local childTop, childRight, childBottom = child:GetTop(), child:GetRight(), child:GetBottom()
    local height = (child:GetHeight() or 0) * share
    if not (childTop and childRight and childBottom) then
        return
    end
    childTop, childRight, childBottom = childTop * share, childRight * share, childBottom * share
    if not foreignMover and isMoverHandle(child, top, childTop, height) then
        foreignMover = child
    elseif not foreignResizer and isResizerHandle(child, childRight - right, childBottom - bottom, height) then
        foreignResizer = child
    end
end

local function findMapHandles(map)
    if areHandlesKnown then
        return
    end
    areHandlesKnown = true
    foreignMover, foreignResizer = nil, nil
    local top, right, bottom = map:GetTop(), map:GetRight(), map:GetBottom()
    if not top or not right or not bottom or not map.GetChildren then
        return
    end
    local mapScale = map:GetEffectiveScale()
    for _, child in ipairs({ map:GetChildren() }) do
        local isOurs = child == (ns.Log.getWindow and ns.Log.getWindow())
        if not isOurs and child.GetScript and child.IsShown and child:IsShown() then
            findHandleIn(child, mapScale, top, right, bottom)
        end
    end
end

---@return table? mover A map addon's own handle that moves the map (and remembers where to)
local function getMapMover(map)
    findMapHandles(map)
    return foreignMover
end

---@return table? resizer A map addon's own grip that sizes the map (and remembers the size)
local function getMapResizer(map)
    findMapHandles(map)
    return foreignResizer
end

---Runs one of another addon's handle's own scripts, as the mouse on it would.
local function runHandleScript(handle, script)
    local handler = handle and handle:GetScript(script)
    if handler then
        pcall(handler, handle, "LeftButton")
    end
end
local draggedMover -- the map addon's handle a drag of ours was handed to

---@return boolean canMove The map can be moved now: open in its window, out of a fight
local function canMoveMap(map)
    return map:IsShown() == true and not map:IsMaximized() and not (InCombatLockdown and InCombatLockdown())
end

---Puts the map where the player moved it, if they did.
function MapDock.placeMovedMap()
    local map, spot = WorldMapFrame, ns.settings.mapSpot
    if not map or not spot or isMapDragged or not canMoveMap(map) or ns.Compatibility.isMapPlacedByAddOn() then
        return
    end
    if getMapMover(map) then
        return -- (a map addon with a mover of its own keeps the map's place itself)
    end
    local scale = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    map:ClearAllPoints()
    map:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", spot.left / scale, spot.top / scale)
end

---The quest window's title strip is dragged while it stands beside the map: the map moves, the window with it.
function MapDock.startMapDrag()
    local map = WorldMapFrame
    if not map or not canMoveMap(map) then
        return
    end
    isMapDragged = true
    -- A map addon that moves the map by a handle of its own: the drag is its handle's, so it remembers where the
    -- map went (moved from here, it put the map straight back where it had it)
    draggedMover = getMapMover(map)
    if draggedMover then
        runHandleScript(draggedMover, "OnDragStart")
        return
    end
    map:SetMovable(true)
    map:SetClampedToScreen(true)
    map:StartMoving()
end

---The title strip let go: the map stays where it was dragged, and that place is kept (settings.mapSpot), or the map
---addon whose handle had the drag keeps it.
function MapDock.stopMapDrag()
    local map = WorldMapFrame
    if not isMapDragged or not map then
        return
    end
    isMapDragged = false
    if draggedMover then
        runHandleScript(draggedMover, "OnDragStop") -- (it stops the move and keeps the place)
        draggedMover = nil
        MapDock.apply()
        return
    end
    map:StopMovingOrSizing()
    map:SetUserPlaced(false) -- (kept by OneMoreQuest, not in the game's layout file)
    local left, top = map:GetLeft(), map:GetTop()
    if left and top then
        local scale = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
        ns.settings.mapSpot = { left = left * scale, top = top * scale }
    end
    MapDock.apply() -- (the window fitted on the screen again, where it now stands)
end

---Forgets where the map was moved: the game's layout places it again.
function MapDock.resetMapSpot()
    ns.settings.mapSpot = nil
    local map = WorldMapFrame
    if map and map:IsShown() and not (InCombatLockdown and InCombatLockdown()) and UpdateUIPanelPositions then
        UpdateUIPanelPositions(map)
        MapDock.apply()
    end
end

local isFoldedTillClosed = false -- the panels were put away by their close button while the map could not be closed

-- The map and the quest log open as the game's own do. The arrow on the map is the lasting choice (the game's
-- "show the quest log": settings.arePanelsHidden): the map key opens the map with the panels or alone by it. The
-- quest log key, or anything that asks for a quest, brings the panels out for that opening only (isLogAskedFor),
-- whatever the arrow says, and leaves the lasting choice as it is; the map closed, it is forgotten.
local isLogAskedFor = false
-- The two keys each have their version of the map, as the game's own do: the map key's ("map": the map as the player
-- left it, full screen or windowed, its panels as the arrow says) and the quest log key's ("log": the windowed map with
-- the panels, as left). A key closes its own version, and on the other's brings out its own; a quest asked for opens
-- the quest log key's. Nil while the map is closed. shownAt: when the map last opened (a key's command, which the game
-- may turn several ways in one moment, is told from one pressed on a map already open).
local shownVersion
local shownAt
local wasHiddenChoice = false -- the arrow's choice when the dock was last looked at

---@return boolean isDown The quest log's key is held right now: it is what opened or closed the map (both keys run
---the game's own map command, since an addon may not open the map in a fight: Log.applyBinding)
local function isLogKeyDown()
    if not IsKeyDown or not GetBindingKey then
        return false
    end
    for _, key in ipairs({ GetBindingKey("TOGGLEQUESTLOG") }) do
        if type(key) == "string" and IsKeyDown(key:match("([^-]+)$") or key) then -- ("SHIFT-L": the key itself)
            return true
        end
    end
    return false
end

---@return boolean isDown The map's own key is held right now (not the quest log's, which runs the same command)
local function isMapKeyDown()
    if not IsKeyDown or not GetBindingKey or isLogKeyDown() then
        return false
    end
    for _, key in ipairs({ GetBindingKey("TOGGLEWORLDMAP") }) do
        if type(key) == "string" and IsKeyDown(key:match("([^-]+)$") or key) then
            return true
        end
    end
    return false
end

---Takes the full-screen map out of full screen for the quest log, as the game's own quest log key does: the windowed
---map, the player's lasting choice of size left as it was (the game's miniWorldMap, set only by the map's own minimize
---and maximize buttons). The map key then brings the full-screen map back, as the game's does
---(QuestLogOwnerMixin's HandleUserActionToggleSelf), and the map opens full screen again next time.
---@param map table WorldMapFrame
local function minimizeForLog(map)
    if not map:IsShown() or not map:IsMaximized() then
        return
    end
    if map.Minimize then
        map:Minimize()
        local sizeButton = map.BorderFrame and map.BorderFrame.MaximizeMinimizeFrame
        if sizeButton and sizeButton.SetMaximizedLook then
            sizeButton:SetMaximizedLook()
        end
    elseif map.HandleUserActionMinimizeSelf then
        map:HandleUserActionMinimizeSelf()
    end
end

---Puts the panels away until the map is next closed: for the close button, when the game will not close the map.
function MapDock.foldUntilClosed()
    isFoldedTillClosed = ns.settings.arePanelsHidden ~= true
    ns.settings.arePanelsHidden = true
    isLogAskedFor = false
    MapDock.apply()
end

local isResizing = false -- the quest window's grip is being dragged (below)

-- The map's size: the windowed map made larger or smaller (settings.mapSize, a share of the game's own size) by the
-- grip at the quest window's corner. Its size is set as the game sets it itself (the frame's width and height, its
-- picture fitted again: WorldMapMixin's Minimize), not by a scale, so nothing on it is drawn larger than it was but
-- the map's picture; the quest window stands as tall as the map. Not while a map addon places or sizes the map
-- itself, nor with the gamepad interface; the full-screen map is the game's own.
local MIN_MAP_SIZE, MAX_MAP_SIZE = 0.7, 2.2
local hasSizedMap = false -- the map has a size of ours

---@return number size The windowed map's size as the settings have it, a share of the game's own
function MapDock.getMapSize()
    return math.max(MIN_MAP_SIZE, math.min(MAX_MAP_SIZE, tonumber(ns.settings.mapSize) or 1))
end

---@return boolean canSize The windowed map's size is OneMoreQuest's to set
local function canSizeMap(map)
    return isReplacing()
        and type(map.minimizedWidth) == "number"
        and type(map.minimizedHeight) == "number"
        and not MapDock.isMapHandsOff()
        and not ns.Compatibility.isMapPlacedByAddOn()
        and not getMapResizer(map) -- (a map addon that sizes the map itself: by its own grip, below)
end

---@return number width, number height The windowed map's frame at a share of the game's own size: its picture that
---much larger, the strip over it (the title and the zone bar) as tall as ever
local function getMapFrameSize(map, size)
    local spacer = type(map.TitleCanvasSpacerFrame) == "table" and map.TitleCanvasSpacerFrame:GetHeight() or 0
    spacer = math.max(0, math.min(spacer or 0, map.minimizedHeight - 1))
    return math.floor(map.minimizedWidth * size + 0.5), math.floor(spacer + (map.minimizedHeight - spacer) * size + 0.5)
end

---Gives the windowed map its size, or the game's own again (the setting back at 1, or switched off).
local function applyMapSize(map, isWindowed)
    if not isWindowed or (InCombatLockdown and InCombatLockdown()) then
        return -- (full screen and closed, its size is the game's; in a fight it is not an addon's to change)
    end
    local size = canSizeMap(map) and MapDock.getMapSize() or 1
    if size == 1 and not hasSizedMap then
        return
    end
    if type(map.minimizedWidth) ~= "number" or type(map.minimizedHeight) ~= "number" then
        return
    end
    local width, height = getMapFrameSize(map, size)
    hasSizedMap = size ~= 1
    if math.abs((map:GetWidth() or 0) - width) < 0.5 and math.abs((map:GetHeight() or 0) - height) < 0.5 then
        return
    end
    map:SetSize(width, height)
    if map.OnFrameSizeChanged then
        map:OnFrameSizeChanged() -- (its picture fitted to the new size, as the game does after sizing it)
    end
end

---The room the game's layout keeps beside the map: the window's width now (one pane or two), at the size the player
---chose; none while it is not docked.
local function reserveRoom(map, isDocked)
    local windowWidth = ns.Log.getPanelWidth() * ns.Log.getWindowScale()
    local extraWidth = isDocked and math.max(0, math.floor(windowWidth - getOpenPanelWidth(map) + 0.5)) or 0
    if isResizing then
        return -- (the map stays where it is while the grip is dragged: laid out again once let go)
    end
    if SetUIPanelAttribute and map:GetAttribute("UIPanelLayout-extraWidth") ~= extraWidth then
        SetUIPanelAttribute(map, "extraWidth", extraWidth)
        updatePanelPositions(map)
    end
end

---Forgets what lasts only as long as one opening of the map: the panels put away by their close button
---(foldUntilClosed), and the panels asked for (gone with the opening, and with the panels put away since).
local function forgetOpeningChoices(map)
    if isFoldedTillClosed and not map:IsShown() then
        isFoldedTillClosed = false
        ns.settings.arePanelsHidden = false -- the map is closed now: opened again, the panels are beside it as before
    end
    local isHiddenNow = ns.settings.arePanelsHidden == true
    if not map:IsShown() or (isHiddenNow and not wasHiddenChoice) then
        isLogAskedFor = false
    end
    wasHiddenChoice = isHiddenNow
end

---The "!" that hides the quest givers' marks: only while there are givers of ours to hide (the map marks and the
---quests to pick up both on, and not while the spoiler choice shows no quests to pick up at all).
local function applyGiverToggle(map)
    if not giverToggle then
        return
    end
    local isGiverToggleShown = map:IsShown() == true
        and ns.settings.shouldShowMapPins == true
        and ns.Availability.isShownOnMap()
        and ns.Spoilers.getChoice("pickup") ~= "none"
    giverToggle:SetShown(isGiverToggleShown)
    if isGiverToggleShown then
        placeGiverToggle(map, isSettling)
        MapDock.updateGiverToggle()
    end
end

---The game's own quest panel kept closed while OneMoreQuest's stand in for it.
local function closeNativePanel(map)
    -- The game remembers whether its own quest panel should be open. While it thinks so, the map key
    -- refuses to close the map and only "hides the panel", so the game is told the panel is closed.
    if GetCVar and SetCVar and GetCVar("questLogOpen") ~= "0" then
        SetCVar("questLogOpen", 0)
    end
    local isHandsOff = MapDock.isMapHandsOff()
    setNativePanelSeen(map, not isHandsOff)
    if isHandsOff then
        -- The gamepad interface: the game's panel is left open (its focus opens it again each time: the map's
        -- FocusQuests), only out of sight under the window. Closing it from here runs its OnHide in OneMoreQuest's
        -- code, which closes the quest's details and has the map focus its quest log again, all with the addon's
        -- taint (the game's right-stick binding, its quest buttons' navigation marks)
        return
    end
    if type(map.QuestLog) == "table" and map.QuestLog:IsShown() and map.SetQuestLogPanelShown then
        map:SetQuestLogPanelShown(false)
        -- The map had already set aside room for its own panel; give that room back to the map
        if map.UpdateSpacerFrameAnchoring then
            map:UpdateSpacerFrameAnchoring()
        end
    end
    if type(map.SidePanelToggle) == "table" then
        map.SidePanelToggle:Hide() -- the arrow that reopens the native panel (the gamepad's: the game hides it)
    end
end

---Switched off: everything OneMoreQuest changed on the map is handed back, once. The width it reserved beside the
---map goes, the arrow that opens the game's quest panel returns, and on an open map the game's panel comes back
---straight away.
local function handBackMap(map)
    hasTakenOver = false
    setNativePanelSeen(map, true)
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

---Lays the map and the quest panels out for how they stand now: docked beside the windowed map or not, the
---toggles, the grip, the map's size and the room the game's layout keeps for the panels.
function MapDock.apply()
    local map = WorldMapFrame
    if not map then
        return
    end
    MapDock.placeOnMap(panelToggle, 500) -- (with the gamepad interface: the screen's, over the map)
    MapDock.placeOnMap(giverToggle, 500)
    ns.Log.placeOnMap()
    forgetOpeningChoices(map)
    local isWindowed = map:IsShown() == true and not map:IsMaximized()
    applyMapSize(map, isWindowed)
    local isDocked = isReplacing() and isWindowed and (isLogAskedFor or not ns.settings.arePanelsHidden)
    if panelToggle then
        panelToggle:SetShown(isReplacing() and isWindowed)
        MapDock.updatePanelToggle()
    end
    applyGiverToggle(map)
    if isReplacing() then
        closeNativePanel(map)
    end
    if isDocked then
        placePanels(map)
    end
    ns.Log.setDocked(isDocked)
    MapDock.placeResizeGrip(isDocked)
    -- Other addons that have to make room for the window, or work around it (Compatibility\)
    ns.Compatibility.handleDockChanged(isDocked)
    if isReplacing() then
        hasTakenOver = true
        reserveRoom(map, isDocked)
    elseif hasTakenOver then
        handBackMap(map)
    end
end

-- Resizing: the grip at the quest window's lower right corner. Dragged down or up, the map is made larger or
-- smaller and the quest window stands as tall beside it, at its own text size: more rows. Dragged right or left,
-- what the grip goes beyond the map's own growing widens the window's page. Where the map's size is not ours to set
-- (a map addon places it: OpenMap, Leatrix Maps), down and up make the window itself taller or shorter than the
-- map. With Shift held as the drag starts, the window is scaled as well, its text too. A right click puts the
-- usual size back. The size is kept with the settings.
local resizeGrip
local resize -- the drag under way: what the sizes were when it started

---Starts a resize from the sizes as they are.
---@param isScaling boolean? The window is scaled with the map, its text too (Shift); else it stretches
---@param isWindowOnly boolean? Only the quest window is sized, taller and wider, the map as it is (Ctrl)
function MapDock.startResize(isScaling, isWindowOnly)
    local map, window = WorldMapFrame, ns.Log.getWindow and ns.Log.getWindow()
    if not map or not window or not window:IsShown() or MapDock.isMapHandsOff() then
        return
    end
    -- A map addon that sizes the map by a grip of its own (OpenMap): a plain drag is its grip's, which follows the
    -- mouse itself and remembers the size; the quest window stands as tall as the map meanwhile
    local resizer = not isScaling and not isWindowOnly and getMapResizer(map) or nil
    if resizer then
        runHandleScript(resizer, "OnMouseDown")
        resize, isResizing = { delegate = resizer }, true
        return
    end
    local shownScale = window:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local mapScale = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    resize = {
        isScaling = isScaling == true,
        canSizeMap = not isWindowOnly and canSizeMap(map) and not (InCombatLockdown and InCombatLockdown()),
        mapSize = MapDock.getMapSize(),
        mapScale = mapScale,
        windowScale = ns.Log.getWindowScale(),
        stretch = ns.Log.getPageStretch(),
        extraHeight = ns.Log.getExtraHeight(),
        -- (in the screen's units) how tall the window is, and how much room there is under it and to its right
        height = (window:GetHeight() or 1) * shownScale,
        roomBelow = math.max(0, (window:GetBottom() or 0) * shownScale - 8),
        roomRight = math.max(0, (UIParent:GetWidth() or 0) - 8 - (window:GetRight() or 0) * shownScale),
    }
    if resize.canSizeMap then
        -- The map's picture (its frame without the strip over it) at the game's own size, in the screen's units
        local width, height = getMapFrameSize(map, 1)
        local _, sizedHeight = getMapFrameSize(map, 2)
        resize.unitWidth, resize.unitHeight = width * mapScale, (sizedHeight - height) * mapScale
    end
    isResizing = true
end

---The grip moved so far from where the drag started (the screen's units; down and right are larger).
function MapDock.resizeTo(across, down)
    local start = resize
    if not start then
        return
    end
    if start.delegate then
        MapDock.apply() -- (the map addon's grip sizes the map: the window is fitted beside it as it goes)
        return
    end
    down, across = math.min(down, start.roomBelow), math.min(across, start.roomRight)
    local mapGrowth = 0
    if start.canSizeMap and start.unitHeight > 0 then
        -- Down and up are the map's: its picture that much taller, and as much wider as its shape asks
        local size = start.mapSize + down / start.unitHeight
        -- (no wider than the room to the right, which the window beside it needs too)
        size = math.min(size, start.mapSize + start.roomRight / start.unitWidth)
        size = math.max(MIN_MAP_SIZE, math.min(MAX_MAP_SIZE, math.floor(size * 100 + 0.5) / 100))
        ns.settings.mapSize = size
        mapGrowth = (size - start.mapSize) * start.unitWidth
        if start.isScaling then
            -- (the quest window by the same share, text and all: the settings' window size)
            local scale = start.windowScale * size / start.mapSize
            ns.settings.windowScale = math.max(0.7, math.min(1.6, math.floor(scale * 100 + 0.5) / 100))
        end
    elseif start.isScaling then
        local share = start.height > 0 and (start.height + down) / start.height or 1
        ns.settings.windowScale = math.max(0.7, math.min(1.6, math.floor(start.windowScale * share * 100 + 0.5) / 100))
    else
        -- The map is not ours to size: the window itself taller or shorter than it
        ns.settings.windowExtraHeight = math.floor(start.extraHeight + down / start.windowScale + 0.5)
    end
    if not start.isScaling then
        -- What the grip went sideways beyond the map's own growing is the page's
        local stretch = start.stretch + (across - mapGrowth) / start.windowScale
        local room = start.stretch + (start.roomRight - mapGrowth) / start.windowScale
        ns.settings.pageStretch = math.floor(math.max(0, math.min(stretch, math.max(room, 0))) + 0.5)
    end
    ns.Log.refresh()
    MapDock.apply()
end

---The drag is over: the game's layout takes in the pair's new size.
function MapDock.stopResize()
    if not resize then
        return
    end
    if resize.delegate then
        runHandleScript(resize.delegate, "OnMouseUp") -- (it keeps the size the drag left)
    end
    resize, isResizing = nil, false
    MapDock.apply()
    MapDock.reserveRoom()
end

---The usual size for a map another addon sizes (OpenMap, by its own grip): the size is that addon's to keep, so its
---own command puts it back. That command puts the map's place back as well: the map is set where it stood again, and
---the addon's own handle told to keep that place.
local function resetForeignSize(map)
    local command = SlashCmdList and SlashCmdList.OPENMAP
    if not command or not getMapResizer(map) or (InCombatLockdown and InCombatLockdown()) then
        return
    end
    local scale = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local left, top = map:GetLeft(), map:GetTop()
    left, top = left and left * scale, top and top * scale
    local wasLogAskedFor = isLogAskedFor
    pcall(command, "reset")
    isLogAskedFor = wasLogAskedFor -- (the command closes and opens the map: the quest window stays as it was)
    areHandlesKnown = false
    -- (the game's own size, said here as well: the addon keeps none any more, so it stays)
    local isMaximized = map.IsMaximized and map:IsMaximized()
    if not isMaximized and type(map.minimizedWidth) == "number" and type(map.minimizedHeight) == "number" then
        local width, height = getMapFrameSize(map, 1)
        if math.abs((map:GetWidth() or 0) - width) >= 0.5 or math.abs((map:GetHeight() or 0) - height) >= 0.5 then
            map:SetSize(width, height)
            if map.OnFrameSizeChanged then
                map:OnFrameSizeChanged()
            end
        end
    end
    local nowScale = map:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local nowLeft, nowTop = map:GetLeft(), map:GetTop()
    if
        left
        and top
        and nowLeft
        and nowTop
        and (math.abs(nowLeft * nowScale - left) > 1 or math.abs(nowTop * nowScale - top) > 1)
    then
        local mover = getMapMover(map)
        if mover then
            map:ClearAllPoints()
            map:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / nowScale, top / nowScale)
            runHandleScript(mover, "OnDragStop") -- (it keeps the place)
        end
    end
end

---The usual size again: the map the game's own size, the window as tall as it, the page as wide as usual, the
---window and its text at their own size.
function MapDock.resetSize()
    local settings = ns.settings
    settings.mapSize, settings.pageStretch, settings.windowExtraHeight, settings.windowScale = 1, 0, 0, 1
    resize, isResizing = nil, false
    if WorldMapFrame and WorldMapFrame:IsShown() then
        resetForeignSize(WorldMapFrame)
    end
    ns.Log.refresh()
    MapDock.apply()
    MapDock.reserveRoom()
end

local function createResizeGrip(window)
    local grip = CreateFrame("Button", nil, window)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel((window:GetFrameLevel() or 1) + 60)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then
            return
        end
        MapDock.startResize(IsShiftKeyDown and IsShiftKeyDown(), IsControlKeyDown and IsControlKeyDown())
        if not resize then
            return
        end
        local uiScale = UIParent:GetEffectiveScale()
        local startX, startY = GetCursorPosition()
        local sinceDrawn = 1
        self:SetScript("OnUpdate", function(_, elapsed)
            sinceDrawn = sinceDrawn + (elapsed or 0)
            if sinceDrawn < 0.03 then
                return -- (the window is drawn again at each size: not more often than this)
            end
            sinceDrawn = 0
            local x, y = GetCursorPosition()
            MapDock.resizeTo((x - startX) / uiScale, (startY - y) / uiScale)
        end)
    end)
    -- (the right button's release itself, not a click: a click is the left button's alone on some frames)
    grip:SetScript("OnMouseUp", function(self, button)
        self:SetScript("OnUpdate", nil)
        MapDock.stopResize()
        if button == "RightButton" then
            MapDock.resetSize()
        end
    end)
    grip:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        MapDock.stopResize()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(ns.L("Drag to resize"), 1, 1, 1)
        GameTooltip:AddLine(
            ns.L(
                "Down makes the map larger and the quest window as tall beside it, with more rows; right makes its page wider. The text stays as it is. Hold Ctrl to size the quest window alone, Shift to scale it, text and all. Right-click for the usual size."
            ),
            0.85,
            0.81,
            0.66,
            true
        )
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return grip
end

---The grip shown at the window's corner while the window stands beside the map (not the gamepad's one pane).
function MapDock.placeResizeGrip(isDocked)
    local window = ns.Log.getWindow and ns.Log.getWindow()
    if not window then
        return
    end
    if not resizeGrip then
        resizeGrip = createResizeGrip(window)
    end
    resizeGrip:SetShown(isDocked == true and not MapDock.isMapHandsOff() and not ns.Log.isNarrow())
end

---@return table? grip The resize grip, for the tests and the simulator
function MapDock.getResizeGrip()
    return resizeGrip
end

---The window's width now (one pane with a controller, two without) kept again beside the open map.
function MapDock.reserveRoom()
    local map = WorldMapFrame
    if map and isReplacing() and hasTakenOver then
        reserveRoom(map, ns.Log.isOpen and ns.Log.isOpen())
    end
end

---Looks again once the map and other addons have laid out their frames for the opening: the panels are placed
---again, and the quest window drawn again only if that changed its size (Log.setDocked).
function MapDock.settle()
    MapDock.placeMovedMap()
    isSettling = true -- (the "!" button looks for other addons' buttons now: they have their places)
    MapDock.apply()
    isSettling = false
end

---Shows the arrow's state: pointing left to fold the panels away while they are out, right to bring them back.
function MapDock.updatePanelToggle()
    if not panelToggle then
        return
    end
    local isHidden = ns.settings.arePanelsHidden == true and not isLogAskedFor
    local normal, pushed =
        isHidden and "QuestCollapse-Show-Up" or "QuestCollapse-Hide-Up",
        isHidden and "QuestCollapse-Show-Down" or "QuestCollapse-Hide-Down"
    if panelToggle.SetNormalAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(normal) then
        panelToggle:SetNormalAtlas(normal)
        panelToggle:SetPushedAtlas(pushed)
    else
        panelToggle:SetNormalTexture(
            isHidden and "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
                or "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up"
        )
    end
end

local STRATA_ABOVE = { BACKGROUND = "LOW", LOW = "MEDIUM", MEDIUM = "HIGH", HIGH = "DIALOG", DIALOG = "FULLSCREEN" }

---Puts one of OneMoreQuest's frames on the map. With the gamepad interface it is the screen's child, laid over the map
---(a strata above it): as the map's focus goes to its quest log, the game's navigation walks every frame inside the
---map but its canvas and its quest panel, in the map's own run (SmartNavigation:RefreshButtonGroups in FocusQuests),
---and what it reads of an addon's frames there taints the map's focus written right after (WorldMapFrame.currentFocus,
---then the game's gamepad bindings). Without it, the map's own child, as always.
---@param levelAbove number How far above the map's frame level it stands
function MapDock.placeOnMap(frame, levelAbove)
    local map = WorldMapFrame
    if not frame or not map then
        return
    end
    local isOut = MapDock.isMapHandsOff()
    local parent = isOut and UIParent or map
    if frame:GetParent() ~= parent then
        frame:SetParent(parent)
    end
    -- Out of the map: a strata above the map's, which the map's own parts (its frame's ground where its quest panel
    -- would be) never draw over, whatever their levels
    local strata = map:GetFrameStrata()
    frame:SetFrameStrata(isOut and (STRATA_ABOVE[strata] or strata) or strata)
    frame:SetFrameLevel((isOut and 10 or (map:GetFrameLevel() or 1)) + levelAbove)
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
        -- The lasting choice, as the game's own arrow is: the panels put away (also when only asked for this once),
        -- or kept out from now on
        local areOut = isLogAskedFor or not ns.settings.arePanelsHidden
        ns.settings.arePanelsHidden, isLogAskedFor = areOut, false
        MapDock.apply()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local areOut = isLogAskedFor or not ns.settings.arePanelsHidden
        GameTooltip:AddLine(ns.L(areOut and "Hide the quest panels" or "Show the quest panels"), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
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
                frameLeft, frameBottom, width, height =
                    frameLeft * scale, frameBottom * scale, width * scale, height * scale
                if
                    frameLeft < right
                    and frameLeft + width > left
                    and frameBottom < top
                    and frameBottom + height > bottom
                then
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
        if
            not left
            or not isCovered(frames, left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale)
        then
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
        GameTooltip:AddLine(
            ns.L(ns.settings.areMapGiversHidden and "Show quests to pick up" or "Hide quests to pick up"),
            1,
            1,
            1
        )
        GameTooltip:AddLine(ns.L('The "!" of quest givers on this map; the minimap keeps them.'), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:Hide()
    return button
end

---In the game's gamepad interface the map is the game's alone to open, turn and close: each of them, done from an
---addon's code, has the map rebuild its prompt bar, whose bindings then go on the game's shared stack of gamepad
---bindings with the addon's taint, and the game refuses its own calls after (the gamepad action bar's
---SetPreferredGamepadInteractTarget, the radial menu's actions; the stack's d-pad no longer works). OneMoreQuest leaves
---the map be then: its window opens by itself instead, the map stays on what it shows, B hands the gamepad to the map.
---@return boolean isHandsOff
function MapDock.isMapHandsOff()
    return ns.Gamepad ~= nil and ns.Gamepad.isGamepadUI ~= nil and ns.Gamepad.isGamepadUI()
end

---Opens the map in its windowed form, which is the one with room for the panels. Asking for the panels
---brings them out for this opening if the arrow had folded them away; the arrow's choice stays.
function MapDock.open()
    local map = WorldMapFrame
    if not map then
        return
    end
    if MapDock.isMapHandsOff() then
        -- (the gamepad interface: the map is opened by the game's own keys; with it closed, the window by itself)
        if not map:IsShown() then
            ns.Log.openAlone(ns.Log.getSelectedQuestId())
        end
        return
    end
    isLogAskedFor = true
    if not map:IsShown() then
        ShowUIPanel(map)
        isLogAskedFor = true -- (the map's showing looked at the dock already: asked for still)
    end
    shownVersion = "log"
    minimizeForLog(map)
    MapDock.apply()
end

---The quest log key: closes its version of the map when that is open, brings it out otherwise.
function MapDock.toggle()
    local map = WorldMapFrame
    if not map then
        return
    end
    if map:IsShown() and shownVersion == "log" then
        if MapDock.isMapHandsOff() then
            return -- (the gamepad's: the map closes by the game's own keys)
        end
        HideUIPanel(map)
    else
        MapDock.open()
    end
end

---Turns the map to another map. An open map is told directly; a closed one is opened on it, which the game
---does not allow addons to do during combat.
function MapDock.showMap(uiMapId)
    local map = WorldMapFrame
    if not uiMapId or not map or MapDock.isMapHandsOff() then
        return -- (the gamepad's: the map stays on what it shows, MapDock.isMapHandsOff)
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

---Turns the map to a zone, if it is not already showing it.
function MapDock.showZoneMap(zoneId)
    MapDock.showMap(zoneId and ns.Database.getUiMapId(ns.Database.getMapZoneId(zoneId)))
end

---Turns the map to a quest's zone and, when the map is zoomed in, slides it so the place is in the middle.
---A map zoomed all the way out shows the whole zone already and stays put.
---@param place table? Where the quest's step is; nil only turns the map
function MapDock.showQuestPlace(zoneId, place)
    MapDock.showZoneMap(zoneId)
    local map = WorldMapFrame
    if not place or not map or not map:IsShown() or not map.PanTo or MapDock.isMapHandsOff() then
        return -- (the gamepad's: the map stays as the player turns it, MapDock.isMapHandsOff)
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
---@return number index Which of the quest's zones the map shows, 0 for none of them. A dungeon is shown on the map
---of the zone its entrance stands in, which may be in the list too: the zone last cycled to is the one shown when
---the map shows its map, then the zone itself, then a dungeon whose entrance is there. (Taking the first zone the
---map fits, a dungeon after its entrance's zone was never got past.)
local function getShownZoneIndex(entry)
    local shownZoneId = MapDock.getShownZoneId()
    local zoneIds = entry.zoneIds or {}
    local cycledZoneId = entry.questId and ns.settings.cycledQuestZones and ns.settings.cycledQuestZones[entry.questId]
    local ownIndex, entranceIndex
    for index, zoneId in ipairs(zoneIds) do
        local isShown = zoneId == shownZoneId or ns.Database.getMapZoneId(zoneId) == shownZoneId
        if isShown and zoneId == cycledZoneId then
            return index
        end
        if zoneId == shownZoneId then
            ownIndex = ownIndex or index
        elseif isShown then
            entranceIndex = entranceIndex or index
        end
    end
    return ownIndex or entranceIndex or 0
end

---@return boolean canShow The map can be turned to a zone: it has a map, with a picture (MapDock.showMap's rule).
---A dungeon without either would leave the map where it was, and the cycle on it.
local function canShowZone(zoneId)
    local uiMapId = ns.Database.getUiMapId(ns.Database.getMapZoneId(zoneId))
    if not uiMapId then
        return false
    end
    if C_Map.GetMapArtLayers then
        local layers = C_Map.GetMapArtLayers(uiMapId)
        return layers ~= nil and #layers > 0
    end
    return true
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
    -- The next zone the map can show: one it cannot is passed over
    local shownIndex, zoneId = getShownZoneIndex(entry), nil
    for step = 1, #zoneIds do
        local candidate = zoneIds[(shownIndex + step - 1) % #zoneIds + 1]
        if canShowZone(candidate) then
            zoneId = candidate
            break
        end
    end
    zoneId = zoneId or zoneIds[shownIndex % #zoneIds + 1]
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
            tooltip:AddDoubleLine(
                SHOWN_ZONE_ARROW .. ns.Database.getZoneName(zoneId),
                ns.L("on the map"),
                1,
                1,
                1,
                1,
                0.82,
                0
            )
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
    if
        isFollowing
        and playerMapId
        and map
        and map:IsShown()
        and map:GetMapID() == playerMapId
        and not MapDock.isMapHandsOff()
    then
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
    hooksecurefunc(WorldMapFrame, "SetDisplayState", function()
        -- The game's map command made the map full screen (the player's lasting size), or the map's own maximize
        -- button did. That is the map key's version of the map: the panels asked for put away. By the quest log key (which runs the same command:
        -- Log.applyBinding) it never is, as the game's own quest log key never makes the map full screen: on its own
        -- version it closes the map, otherwise it brings that version out, windowed, with the log
        -- (QuestLogOwnerMixin's HandleUserActionToggleQuestLog)
        local map = WorldMapFrame
        local canAct = isReplacing()
            and not MapDock.isMapHandsOff()
            and not (InCombatLockdown and InCombatLockdown())
            and map:IsShown()
            and map:IsMaximized()
        local isOpenedNow = shownAt == (GetTime and GetTime())
        if canAct and isLogKeyDown() and shownVersion == "log" and not isOpenedNow then
            HideUIPanel(map) -- (its OnHide lays out the rest)
            return
        elseif canAct and isLogKeyDown() then
            isLogAskedFor, shownVersion = true, "log"
            minimizeForLog(map)
        elseif canAct then
            -- (by the map key, or the map's own maximize button: a full-screen map is the map key's version)
            isLogAskedFor, shownVersion = false, "map"
        end
        ns.Timing.measure("map layout (display state)", MapDock.apply)
    end)
    -- The game's window layout places the map at each opening and when other windows open beside it: where the
    -- player moved it, it goes back there
    if UpdateUIPanelPositions then
        hooksecurefunc("UpdateUIPanelPositions", function()
            MapDock.placeMovedMap()
        end)
    end
    WorldMapFrame:HookScript("OnShow", function()
        areHandlesKnown = false -- (a map addon's own handles: looked for again, once it has made them)
        shownAt = GetTime and GetTime()
        -- Opened by the quest log's key: its version, with the panels, in the windowed map, as the game's own quest
        -- log key; by anything asking for the log (MapDock.open) the same; otherwise the map key's version
        if isLogKeyDown() and isReplacing() and not MapDock.isMapHandsOff() then
            isLogAskedFor = true
            minimizeForLog(WorldMapFrame)
        end
        shownVersion = isLogAskedFor and "log" or "map"
        ns.Timing.startOpening()
        ns.Timing.measure("opening (quest window included)", MapDock.apply)
        -- Map addons lay out their own frame as the map opens too; look again once everything has its place
        if C_Timer then
            C_Timer.After(0, function()
                ns.Timing.measure("second look", MapDock.settle)
            end)
        end
    end)
    WorldMapFrame:HookScript("OnHide", function()
        -- Both keys run the game's map command, which closes the map open in either version. A key on its own version
        -- means that (the map stays closed); on the other's it asks for its own, so the map is opened again in it
        -- once the game is done closing it. Not in a fight, where an addon may not open the map: there a key closes
        -- it, and pressed again opens its version.
        local wasVersion = shownVersion
        shownVersion = nil
        local canAct = isReplacing() and not MapDock.isMapHandsOff() and not (InCombatLockdown and InCombatLockdown())
        local isLogWanted = canAct and wasVersion ~= "log" and isLogKeyDown()
        local isMapWanted = canAct and wasVersion == "log" and isMapKeyDown()
        MapDock.apply() -- (closing with Escape does not go through the map's own toggle)
        if isLogWanted and C_Timer then
            C_Timer.After(0, MapDock.open)
        elseif isMapWanted and C_Timer then
            C_Timer.After(0, function()
                isLogAskedFor = false -- (the map key's version: its panels as the arrow says)
                ShowUIPanel(WorldMapFrame)
                MapDock.apply()
            end)
        end
    end)
    -- The gamepad interface: the map opens its quest panel itself as its focus goes to it (out of sight there, the
    -- window over it): the window placed again once the game is done with it (the next frame)
    local panel = WorldMapFrame.QuestLog
    if type(panel) == "table" and panel.HookScript and C_Timer then
        local function handlePanelShown()
            if MapDock.isMapHandsOff() then
                C_Timer.After(0, MapDock.apply)
            end
        end
        panel:HookScript("OnShow", handlePanelShown)
        panel:HookScript("OnHide", handlePanelShown)
    end
    -- (with the gamepad interface on already: OneMoreQuest's frames out of the map before it first opens)
    MapDock.placeOnMap(panelToggle, 500)
    MapDock.placeOnMap(giverToggle, 500)
    ns.Log.placeOnMap()
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

---Hands the quest panel back to the game, for when OneMoreQuest's panels are switched off.
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
