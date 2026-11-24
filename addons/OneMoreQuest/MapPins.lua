local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Around the world map's marks (MapMarks): turning a place into a map position, hiding the game's own quest
-- markers, and redrawing when the map changes.
local MapPins = {}
ns.MapPins = MapPins

local REFRESH_DELAY_SECONDS = 0.05

local isRefreshQueued = false
local isCreated = false

-- While the world map's marks are worked out on a map another addon joins its neighbours onto (OpenMap): how it
-- places points, and the part of the map in view (MapPins.setView)
local currentView ---@type { view: MapView, bounds: { left: number, top: number, right: number, bottom: number } }?

---For the marks being worked out now: the other addon's view of the map and what of it is in view, or nil for
---the game's map alone.
---@param zones table<number, boolean>? The zones (uiMapIds) reaching into the view: their places are all taken, so a
---quest's marks (the middle of its spawns, its largest area) stay where they are as the view's edge moves over them
function MapPins.setView(view, bounds, zones)
    currentView = view and bounds and { view = view, bounds = bounds, zones = zones } or nil
end

---@return string? key The view the marks are being worked out for, as one text: the same text, the same view (its
---bounds and the zones in it), so what was worked out for it holds (MapMarks' kept points); nil for the game's map alone
function MapPins.getViewKey()
    if not currentView then
        return nil
    end
    if not currentView.key then
        local zoneIds = {}
        for zoneId in pairs(currentView.zones or {}) do
            zoneIds[#zoneIds + 1] = zoneId
        end
        table.sort(zoneIds)
        local bounds = currentView.bounds
        currentView.key = string.format("%.4f:%.4f:%.4f:%.4f:", bounds.left, bounds.top, bounds.right, bounds.bottom)
            .. table.concat(zoneIds, ",")
    end
    return currentView.key
end

---@return table<number, boolean> zones The zones (uiMapIds) reaching into the view, as a set
function MapPins.getViewZones(view, mapId, bounds)
    local zones = { [mapId] = true }
    local isFine, mapIds = pcall(view.getZoneMapIds, mapId, bounds)
    for _, zoneMapId in ipairs(isFine and type(mapIds) == "table" and mapIds or {}) do
        zones[zoneMapId] = true
    end
    return zones
end

---@return boolean isJoined The marks being worked out are for a map that shows its neighbouring zones as well
function MapPins.isViewJoined()
    return currentView ~= nil
end

---@return table? view, table? bounds, table? zones The view the marks are being worked out for (MapPins.setView)
function MapPins.getView()
    if not currentView then
        return nil, nil, nil
    end
    return currentView.view, currentView.bounds, currentView.zones
end

---Runs work for another map (the minimap) on the game's own placing, whatever view the world map has set, and puts
---that view back after: the world map's joined-on view (OpenMap) is no business of the minimap's.
function MapPins.withoutView(work, ...)
    local view, bounds, zones = MapPins.getView()
    currentView = nil
    local isFine, problem = pcall(work, ...)
    MapPins.setView(view, bounds, zones)
    if not isFine then
        error(problem, 0)
    end
end

---The part of a map's canvas in view: its scroll frame's edges as fractions of the canvas, widened by a margin
---on each side so that a little panning finds the marks already there.
---@param margin number? Of the view's own width and height on each side
---@return { left: number, top: number, right: number, bottom: number }? bounds
function MapPins.getVisibleBounds(map, margin)
    local container, canvas = map and map.ScrollContainer, map and map.GetCanvas and map:GetCanvas()
    if type(container) ~= "table" or not canvas or not container.GetLeft then
        return nil
    end
    local containerScale, canvasScale = container:GetEffectiveScale(), canvas:GetEffectiveScale()
    local containerLeft, containerTop = container:GetLeft(), container:GetTop()
    local containerRight, containerBottom = container:GetRight(), container:GetBottom()
    local canvasLeft, canvasTop = canvas:GetLeft(), canvas:GetTop()
    local canvasWidth, canvasHeight = canvas:GetWidth(), canvas:GetHeight()
    if
        not (containerLeft and containerTop and containerRight and containerBottom and canvasLeft and canvasTop)
        or not canvasWidth
        or canvasWidth <= 0
        or not canvasHeight
        or canvasHeight <= 0
    then
        return nil
    end
    local width, height = canvasWidth * canvasScale, canvasHeight * canvasScale
    local left = (containerLeft * containerScale - canvasLeft * canvasScale) / width
    local right = (containerRight * containerScale - canvasLeft * canvasScale) / width
    local top = (canvasTop * canvasScale - containerTop * containerScale) / height
    local bottom = (canvasTop * canvasScale - containerBottom * containerScale) / height
    local extraX, extraY = (right - left) * (margin or 0), (bottom - top) * (margin or 0)
    return { left = left - extraX, top = top - extraY, right = right + extraX, bottom = bottom + extraY }
end

---Where a place falls on a map, as fractions of its width and height.
---@param isGameMapOnly boolean? On the game's map alone, whatever another addon joins onto it (to pan the map there)
---@return number? x, number? y nil when the place is not on that map
function MapPins.getMapPosition(place, mapId, isGameMapOnly)
    if place.x < 0 then
        return nil
    end
    local placeMapId = ns.Database.getUiMapId(place.zoneId)
    if currentView and placeMapId and not isGameMapOnly then
        -- The neighbours are on this map too: placed as the other addon draws them, as far as the view reaches
        local isFine, x, y = pcall(currentView.view.project, placeMapId, place.x / 100, place.y / 100, mapId)
        if isFine and type(x) == "number" and type(y) == "number" then
            -- A zone in view gives all its places; only those of zones further off are cut at the view's edge
            local zones = currentView.zones
            if zones and zones[placeMapId] then
                return x, y
            end
            local bounds = currentView.bounds
            if x < bounds.left or x > bounds.right or y < bounds.top or y > bounds.bottom then
                return nil
            end
            return x, y
        end
    end
    if placeMapId == mapId then
        return place.x / 100, place.y / 100
    end
    local continentId, north, west = ns.Geometry.getWorldPosition(placeMapId, place.x, place.y)
    if not north or not C_Map.GetMapPosFromWorldPos then
        return nil
    end
    local _, position = C_Map.GetMapPosFromWorldPos(continentId, CreateVector2D(north, west), mapId)
    if not position then
        return nil
    end
    local x, y = position:GetXY()
    if x < 0 or x > 1 or y < 0 or y > 1 then
        return nil
    end
    return x, y
end

-- The game's own quest markers that this addon's pins replace: quest spots and areas, and quest givers
local BUILT_IN_QUEST_TEMPLATES = { "QuestPinTemplate", "QuestBlobPinTemplate" }
local BUILT_IN_GIVER_TEMPLATES = { "QuestOfferPinTemplate", "QuestHubPinTemplate" }
local isBuiltInTemplate = {}
for _, template in ipairs(BUILT_IN_QUEST_TEMPLATES) do
    isBuiltInTemplate[template] = true
end
for _, template in ipairs(BUILT_IN_GIVER_TEMPLATES) do
    isBuiltInTemplate[template] = true
end

-- The game's markers this addon has made invisible. The game reuses the same marker objects every time it
-- redraws the map, so one made transparent stays transparent when it is shown again; that is what stops the
-- game's markers flashing up for a moment whenever a quest is tracked, focused or progresses.
local silencedPins = setmetatable({}, { __mode = "k" })

local function silenceTemplates(templates)
    for _, template in ipairs(templates) do
        for pin in WorldMapFrame:EnumeratePinsByTemplate(template) do
            pin:SetAlpha(0)
            pin:Hide()
            silencedPins[pin] = true
        end
    end
end

local function shouldHideBuiltIn()
    return ns.settings.shouldShowMapPins and ns.settings.shouldHideBuiltInMapPins
end

---The game's own map filter "Quest Objectives" (its questPOI setting, in the map's filter menu) follows the Map marks
---switch. With this addon's marks off, the game's own quest markers are what the map is to show, and with that
---filter off the game shows none: it is switched on, at the switch and at login. With ours switched on, it is
---switched off (the game then draws none of its own to hide) when this addon's tracker stands in for the game's as
---well, whose own tracker takes its buttons from the same setting. Off only at the switch itself, so the player's
---own choice of the filter stands otherwise.
---@param isSwitching boolean? The Map marks switch may just have changed (the settings were carried out)
function MapPins.applyGameFilter(isSwitching)
    if not (GetCVar and SetCVar) then
        return
    end
    local isOurs = ns.settings.shouldShowMapPins == true
    local wasOurs = ns.settings.gameFilterSetFor
    ns.settings.gameFilterSetFor = isOurs
    if not isOurs then
        if GetCVar("questPOI") ~= "1" then
            SetCVar("questPOI", 1)
        end
    elseif
        isSwitching
        and wasOurs == false
        and ns.settings.shouldHideBuiltInMapPins
        and ns.settings.shouldHideBuiltInTracker
    then
        if GetCVar("questPOI") ~= "0" then
            SetCVar("questPOI", 0)
        end
    end
end

---Hides the game's markers for what this addon draws itself, or, with the setting off, gives back the ones
---hidden before; those reappear the next time the game redraws the map.
function MapPins.hideBuiltIn()
    if not WorldMapFrame then
        return
    end
    if not shouldHideBuiltIn() then
        local hadSilenced = next(silencedPins) ~= nil
        for pin in pairs(silencedPins) do
            pin:SetAlpha(1)
            silencedPins[pin] = nil
        end
        if hadSilenced then
            -- The ones the game has on the map right now were hidden as well as made see-through: shown again at
            -- once, not only when the game next redraws its map (switching the marks off left the map bare)
            pcall(function()
                for template in pairs(isBuiltInTemplate) do
                    for pin in WorldMapFrame:EnumeratePinsByTemplate(template) do
                        pin:Show()
                    end
                end
                if WorldMapFrame.RefreshAllDataProviders then
                    WorldMapFrame:RefreshAllDataProviders() -- and the game lays its own out afresh
                end
            end)
        end
        return
    end
    pcall(silenceTemplates, BUILT_IN_QUEST_TEMPLATES)
    if ns.Availability.isShownOnMap() and ns.Availability.isReady() then
        pcall(silenceTemplates, BUILT_IN_GIVER_TEMPLATES)
    else
        -- This addon is not drawing quest givers, so the game's own stay visible
        pcall(function()
            for _, template in ipairs(BUILT_IN_GIVER_TEMPLATES) do
                for pin in WorldMapFrame:EnumeratePinsByTemplate(template) do
                    if silencedPins[pin] then
                        pin:SetAlpha(1)
                        pin:Show()
                        silencedPins[pin] = nil
                    end
                end
            end
        end)
    end
end

---The game has just put one of its markers on the map. It is dealt with at once, in the same moment, so it
---is never drawn; waiting even a frame is what made the markers flicker.
local PIN_SETTLE_SECONDS = 0.2 -- other addons' pins come in bursts (Questie's by the hundred): looked at once they stop
local drawnEntranceKey -- the dungeon entrance icons of other addons the marks were last laid out on
local lastDrawnAt = 0 -- when the world map's marks were last drawn (GetTime)

-- The world map's marks stay on it while it is closed. Opened again with nothing changed meanwhile, the same map at
-- the same size and zoom, the player not far from where they were, they are not drawn again: drawing them is most
-- of what opening the map costs.
local isWorldMapStale = true -- something the marks show changed while the map was closed
local drawnWorldMap -- { mapId, view, position } when last drawn
local STALE_AFTER_YARDS = 50 -- the player walked this far since: the marks (nearest places, distances) drawn again
local drawnDataKey -- what the marks follow of the quests (getDataKey), as it was when they were last drawn
local drawnHoverKey -- the quests hovered in the list when the marks were last drawn

local function getHoverKey()
    local Log = ns.Log
    return tostring(Log.getHoveredQuestId and Log.getHoveredQuestId())
        .. ":"
        .. tostring(Log.getHighlightedAvailableQuestId and Log.getHighlightedAvailableQuestId())
end

---@return string view The map's size and zoom: the marks are laid out for them
local function getWorldMapViewKey()
    local map = WorldMapFrame
    local canvas = map.GetCanvas and map:GetCanvas()
    local scale = map.GetCanvasScale and map:GetCanvasScale() or 0
    return string.format("%.1f:%.1f:%.4f", canvas and canvas:GetWidth() or 0, canvas and canvas:GetHeight() or 0, scale)
end

---@return boolean isCurrent The marks on the world map are what it would draw now. That includes the quest they show
---in full: drawn with the quest panels open, they showed the quest selected there, and the panels open again on the
---quest in focus (Log.setDocked), which may be another
local function isWorldMapCurrent()
    local drawn = drawnWorldMap
    if
        isWorldMapStale
        or not drawn
        or drawn.mapId ~= WorldMapFrame:GetMapID()
        or drawn.view ~= getWorldMapViewKey()
    then
        return false
    end
    if MapPins.getDataKey() ~= drawnDataKey or getHoverKey() ~= drawnHoverKey then
        return false
    end
    local position = ns.Geometry.getPlayerPosition()
    if not position or not drawn.position then
        return position == drawn.position
    end
    return position.uiMapId == drawn.position.uiMapId
        and ns.Geometry.getDistance(position.north, position.west, drawn.position.north, drawn.position.west)
            < STALE_AFTER_YARDS
end

---The world map opened: its marks are drawn only when they are not what it would show now.
function MapPins.handleWorldMapShown()
    if not C_Timer then
        MapPins.queueRefresh()
        return
    end
    -- Looked at once the map has laid itself out (its size, another addon's view), as a drawing would wait
    C_Timer.After(REFRESH_DELAY_SECONDS, function()
        if not WorldMapFrame:IsShown() then
            return
        end
        if isWorldMapCurrent() then
            ns.Timing.noteCause("map marks", "kept from the last opening")
            return
        end
        MapPins.queueRefresh()
    end)
end

-- A quest hovered in the quest window's list stands out on the map. The mouse crosses many rows on its way: the map
-- is drawn for the one it rests on, not for each it passes (a drawing costs a frame tens of milliseconds)
local HOVER_SETTLE_SECONDS = 0.15
local lastHoverAt, isHoverQueued = 0, false

local function checkHover()
    local waited = (GetTime and GetTime() or 0) - lastHoverAt
    if waited < HOVER_SETTLE_SECONDS - 0.01 then
        C_Timer.After(HOVER_SETTLE_SECONDS - waited, checkHover)
        return
    end
    isHoverQueued = false
    if getHoverKey() ~= drawnHoverKey then
        MapPins.refresh()
    end
end

---The quest hovered in the list changed: the map follows once the mouse rests, unless it came back to what is drawn.
function MapPins.queueHoverRefresh()
    lastHoverAt = GetTime and GetTime() or 0
    if isHoverQueued or not C_Timer then
        return
    end
    isHoverQueued = true
    C_Timer.After(HOVER_SETTLE_SECONDS, checkHover)
end
local lastPinAt, isPinCheckQueued = 0, false

---@return string key Where other addons' (and the game's) dungeon entrance icons stand on the world map: all of
---theirs the marks take notice of, each dungeon's mark set on its entrance icon
local function getEntranceKey()
    local map = WorldMapFrame
    local parts = {}
    for _, entrance in ipairs(ns.MapMarks.getEntrancePins(map, map.GetCanvas and map:GetCanvas())) do
        parts[#parts + 1] = string.format("%.3f:%.3f", entrance.x, entrance.y)
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function checkPins()
    isPinCheckQueued = false
    local waited = (GetTime and GetTime() or 0) - lastPinAt
    if waited < PIN_SETTLE_SECONDS - 0.01 then
        isPinCheckQueued = true
        C_Timer.After(PIN_SETTLE_SECONDS - waited, checkPins)
        return
    end
    if WorldMapFrame and WorldMapFrame:IsShown() and getEntranceKey() ~= drawnEntranceKey then
        MapPins.queueRefresh()
    end
end

local isGiverTemplate = {}
for _, template in ipairs(BUILT_IN_GIVER_TEMPLATES) do
    isGiverTemplate[template] = true
end

---@return boolean shouldSilence The game's markers of this kind are hidden now (MapPins.hideBuiltIn's rules)
local function shouldSilenceTemplate(template)
    if isGiverTemplate[template] then
        return ns.Availability.isShownOnMap() and ns.Availability.isReady()
    end
    return true
end

---The game put down a marker of one of its kinds that this addon draws itself: that kind's new markers are hidden,
---and any it showed again. Only that kind, and nothing done twice: the game puts down dozens as the map opens, and
---going over all of them for each was most of what opening the map cost.
local function silenceNewPins(template)
    for pin in WorldMapFrame:EnumeratePinsByTemplate(template) do
        if not silencedPins[pin] then
            pin:SetAlpha(0)
            pin:Hide()
            silencedPins[pin] = true
        elseif pin:IsShown() then
            pin:Hide()
        end
    end
end

local function handleBuiltInPin(_, template)
    if isBuiltInTemplate[template] and shouldHideBuiltIn() and shouldSilenceTemplate(template) then
        ns.Timing.measure("game's markers hidden", pcall, silenceNewPins, template)
    end
    -- A pin put on the map (another addon's, or the game's): the marks are laid out again only when it is a dungeon
    -- entrance they stand on. Any other pin changes nothing of ours, and Questie puts down hundreds.
    lastPinAt = GetTime and GetTime() or 0
    if not isPinCheckQueued and C_Timer then
        isPinCheckQueued = true
        C_Timer.After(PIN_SETTLE_SECONDS, function()
            ns.Timing.measure("other addons' pins checked", checkPins)
        end)
    end
end

---@return string key What the maps' marks follow that the quest log's own news can change: which quests are tracked
---and where each stands (not how far along: Model.getStructureKey), the quest in focus, and the quests to pick up.
---The same key: a kill or a loot was counted and nothing drawn on a map changed, only words its tooltips read
---afresh (MapMarks.refreshMarkTexts). And what the player chose to see and has found (Spoilers.getKey: the same
---"guide" while nothing is held back), and whether Alt is held over the world map to see everything.
local function getDataKey()
    local focusedQuestId = ns.MapMarks.getFocusedQuestId()
    return ns.Model.getStructureKey(focusedQuestId)
        .. "|"
        .. tostring(focusedQuestId)
        .. "|"
        .. tostring(ns.Focus.get())
        .. "|"
        .. ns.Availability.getChangeKey()
        .. "|"
        .. ns.Spoilers.getKey()
        .. (ns.MapMarks.isPeeking() and "+" or "")
end
MapPins.getDataKey = getDataKey

---The redraw of everything. A quiet one (nothing asked for it but the quest log's news, Core's Module.refresh) with
---the quests standing where they did keeps the marks as they are, on the map and for its next opening: a kill
---counted is the most frequent redraw of all, and the marks were most of its cost.
function MapPins.refreshAfterChange(isQuiet)
    -- (MapPins.isKeepingOff: never kept, the minimap neither, for comparing the two ways in the simulator)
    if isQuiet and drawnDataKey ~= nil and not MapPins.isKeepingOff and getDataKey() == drawnDataKey then
        MapPins.keptCount = (MapPins.keptCount or 0) + 1 -- (how often: read by the simulator's audits)
        return
    end
    MapPins.refresh()
end

function MapPins.refresh()
    ns.Timing.noteCause("map marks") -- also drawn straight away, by the redraw of everything (Core)
    drawnDataKey = getDataKey()
    -- The zone map (Shift+M) gets the same marks, drawn on its own layers
    if BattlefieldMapFrame and BattlefieldMapFrame:IsShown() and BattlefieldMapFrame.GetCanvas then
        ns.MapMarks.draw(BattlefieldMapFrame)
    end
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        isWorldMapStale = true -- something changed while the map was closed: drawn again as it opens
        return
    end
    ns.Timing.measure("game's markers hidden (with a drawing)", MapPins.hideBuiltIn)
    ns.Timing.measure("map marks drawn", ns.MapMarks.draw, WorldMapFrame)
    drawnEntranceKey = getEntranceKey()
    lastDrawnAt = GetTime and GetTime() or 0
    isWorldMapStale = false
    drawnWorldMap =
        { mapId = WorldMapFrame:GetMapID(), view = getWorldMapViewKey(), position = ns.Geometry.getPlayerPosition() }
    drawnHoverKey = getHoverKey()
end

local isZoneMapHooked = false

---Follows the zone map (Shift+M, the game loads it the first time it is opened) as the world map is followed:
---opening it, a new zone or a zoom step redraws its marks.
local function hookZoneMap()
    if isZoneMapHooked or not BattlefieldMapFrame or not BattlefieldMapFrame.GetCanvas then
        return
    end
    isZoneMapHooked = true
    hooksecurefunc(BattlefieldMapFrame, "OnMapChanged", MapPins.queueRefresh)
    if BattlefieldMapFrame.OnCanvasScaleChanged then
        hooksecurefunc(BattlefieldMapFrame, "OnCanvasScaleChanged", MapPins.queueRefresh)
    end
    BattlefieldMapFrame:HookScript("OnShow", MapPins.queueRefresh)
    MapPins.queueRefresh()
end

function MapPins.queueRefresh()
    ns.Timing.noteCause("map marks")
    if isRefreshQueued then
        return
    end
    isRefreshQueued = true
    C_Timer.After(REFRESH_DELAY_SECONDS, function()
        isRefreshQueued = false
        MapPins.refresh()
    end)
end

local VIEW_MARGIN = 0.5 -- the marks reach this far past the view on each side (of its width and height), so panning finds them there

MapPins.VIEW_MARGIN = VIEW_MARGIN

---Another addon moved its view of the world map without the game's map changing (OpenMap's panning across its
---joined zones): redrawn once the view shows a part the marks were not worked out for.
function MapPins.handleViewMoved()
    local map = WorldMapFrame
    if not map or not map:IsShown() then
        return
    end
    local drawnBounds = ns.MapMarks.getDrawn(map).viewBounds
    local visible = MapPins.getVisibleBounds(map, 0)
    if
        not drawnBounds
        or not visible
        or visible.left < drawnBounds.left
        or visible.right > drawnBounds.right
        or visible.top < drawnBounds.top
        or visible.bottom > drawnBounds.bottom
    then
        MapPins.queueSettledRefresh() -- once the view stops moving, not at every step of a glide
    end
end

local ZOOM_SETTLE_SECONDS = 0.3 -- while the zoom keeps changing, the marks wait this long after the last step
-- On a map another addon joins its neighbours onto (OpenMap), the wait is longer: once the view has been still for
-- 0.6 seconds, OpenMap may put another map underneath it (the zone now in view, or the continent zoomed out to),
-- which draws the marks again anyway; drawn before that, every zoom or pan into another zone was drawn twice
local JOINED_SETTLE_SECONDS = 0.8
local lastZoomAt, settleSeconds = 0, ZOOM_SETTLE_SECONDS
local isSettledCheckPending = false -- a settled refresh will look at the view once it has stayed put

---@return boolean isComing The world map's marks are about to be drawn again: asked for, or looked at once the view
---settles (which, at another zoom than they were drawn at, draws them). Catching their lines and spawn marks up with
---the zoom meanwhile (MapMarks.followZoom) would be thousands of calls into the game the drawing then undoes.
function MapPins.isRedrawComing()
    return isRefreshQueued or isSettledCheckPending
end

---The map's zoom changed. Its marks are laid out again only once the zoom has settled: laid out at every step of a
---zoom (a wheel turned, OpenMap gliding) the spawn marks rearranged themselves all the while. Meanwhile they keep
---their places, scaling with the map.
---@return boolean isCovered The marks drawn last reach over all the map shows now, at the zoom it shows: drawing
---them again would change nothing
local function isViewCovered()
    local map = WorldMapFrame
    local drawn = map and ns.MapMarks.getDrawn(map)
    if not drawn or not drawn.mapId or map:GetMapID() ~= drawn.mapId then
        return false
    end
    local scale = map.GetCanvasScale and map:GetCanvasScale()
    if type(scale) ~= "number" or type(drawn.scale) ~= "number" or math.abs(scale - drawn.scale) > 0.0001 then
        return false
    end
    local drawnBounds = drawn.viewBounds
    if not drawnBounds then
        return true -- drawn for the whole map (no addon joins other zones on): whatever part shows is covered
    end
    local visible = MapPins.getVisibleBounds(map, 0)
    return visible ~= nil
        and visible.left >= drawnBounds.left
        and visible.right <= drawnBounds.right
        and visible.top >= drawnBounds.top
        and visible.bottom <= drawnBounds.bottom
end

function MapPins.queueSettledRefresh()
    local now = GetTime and GetTime() or 0
    lastZoomAt = now
    settleSeconds = ns.MapMarks.getDrawn(WorldMapFrame).view and JOINED_SETTLE_SECONDS or ZOOM_SETTLE_SECONDS
    isSettledCheckPending = true
    C_Timer.After(settleSeconds, function()
        if (GetTime and GetTime() or 0) - lastZoomAt >= settleSeconds - 0.01 then
            isSettledCheckPending = false
            -- Drawn since the view last moved (the map opening draws as it settles), for what it shows now: no need
            -- (the marks catch up with the zoom instead, MapMarks' OnUpdate, if they have not)
            if lastDrawnAt >= lastZoomAt and isViewCovered() then
                return
            end
            MapPins.queueRefresh()
        end
    end)
end

---Follows the world map: a new zone, a zoom step, or the map opening redraws the pins.
function MapPins.create()
    if isCreated or not WorldMapFrame or not hooksecurefunc then
        return
    end
    isCreated = true
    hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
        ns.Timing.measure("map changed", function()
            ns.Log.handleMapChanged(WorldMapFrame:GetMapID())
            ns.MapMarks.hideUntilDrawn(WorldMapFrame) -- laid out for the last map: hidden till drawn for this one
            MapPins.queueRefresh()
        end)
    end)
    hooksecurefunc(WorldMapFrame, "OnCanvasScaleChanged", function()
        -- At every step the quest marks only follow the zoom, nothing drawn again: they stay on their spots and take
        -- the zoom's size; the rest catches up once the zoom stays put. Drawn again only when the settled zoom crossed
        -- a step of the spawns' thinning (MapMarks' OnUpdate), or a pan shows ground they were not drawn for
        -- (handleViewMoved)
        if WorldMapFrame:IsShown() then
            ns.Timing.measure("marks follow the zoom", ns.MapMarks.followZoom, WorldMapFrame, true)
        end
    end)
    hooksecurefunc(WorldMapFrame, "AcquirePin", handleBuiltInPin)
    WorldMapFrame:HookScript("OnShow", MapPins.handleWorldMapShown)
    MapPins.applyGameFilter()
    ns.Availability.prepare(MapPins.queueRefresh)
    hookZoneMap()
    local loadWatcher = CreateFrame("Frame")
    loadWatcher:RegisterEvent("ADDON_LOADED")
    loadWatcher:SetScript("OnEvent", function(_, _, name)
        if name == "Blizzard_BattlefieldMap" then
            hookZoneMap()
        end
    end)
end

ns.on("FOCUS_CHANGED", function()
    MapPins.queueRefresh()
end) -- the quest in focus stands out on the map
ns.registerModule({
    name = "MapPins",
    create = MapPins.create,
    needsWorldMap = true,
    refresh = MapPins.refreshAfterChange,
})
