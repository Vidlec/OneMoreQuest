local addonName, ns = ... -- the addon's folder, which its pictures are read from
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest panels joined to the right side of the game's world map (see MapDock): a dark list, then the
-- selected quest on parchment, with actions under it. Two tabs: the quests in the log, grouped by where their
-- next step takes place, and the quests available in a zone.
local Log = {}
ns.Log = Log

-- The window is made of parts, each a file under Log\, loaded in this order:
--   Base          what every part shares: the look (ns.LogStyle), the window's state (ns.LogState), and actions on
--                 quests (ns.LogActions: select, focus, track, their menus)
--   List          the list on the left: headings and quest rows (ns.LogList)
--   QuestPage     the page on parchment: what its parts share, a quest of the log's page, a zone's page
--                 (ns.LogQuestPage, which the page's parts below share through)
--   PageHeader, PageRewards, PageChain, PageToDo, PageParty, HintLadder, AvailablePage
--                 the page's parts: its header, what a quest gives, the quests around it, its To do list, the party
--                 on it, the hint ladder, and the page of a quest to pick up
--   QuestsTab     the My quests tab (ns.LogQuestsTab)
--   AvailableTab  the Available tab: quests to pick up, dungeon runs (ns.LogAvailableTab)
--   SettingsView  the settings, drawn in the window (ns.LogSettingsView)
--   Window        the window itself and its public functions, ns.Log (ns.LogWindow for its own parts)
-- A part reaches another only through these tables. What is set once is copied into a local at the top of the
-- part that uses it; what changes (the selected tab, the shown quest) lives in ns.LogState and is read there.
local Style, State, Actions = {}, {}, {}
ns.LogStyle, ns.LogState, ns.LogActions = Style, State, Actions
ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow =
    {}, {}, {}, {}, {}, {}
ns.LogDiagram = {} -- the quest diagram, a window of its own opened from a quest's page
ns.LogDungeonsTab = {} -- the Dungeons tab: every dungeon with quests for the player, and a dungeon's page

local LIST_WIDTH, PAGE_WIDTH = 330, 330
local PANEL_WIDTH = LIST_WIDTH + PAGE_WIDTH + 4
local PAGE_CONTENT_WIDTH = PAGE_WIDTH - ns.Widgets.SCROLL_BAR_WIDTH -- the page itself; the scroll bar stands beside it
local TITLE_HEIGHT, BAR_HEIGHT = 30, 40 -- the tab row over the list, the button bar under the page
local PAGE_TOP = 1 -- the quest page starts at the window's top: the tab row is only as wide as the list
local SEARCH_HEIGHT = 32
local LOW_LEVEL_BAR_HEIGHT = 30 -- the fixed line under the Available list
local ZONE_MENU_HEIGHT = 420 -- the location menu scrolls beyond this
local SCROLL_ARROW_HEIGHT = 18 -- the scroll bar's arrow buttons sit beyond its two ends
local PADDING = 14
local TAB_QUESTS, TAB_AVAILABLE, TAB_DUNGEONS = 1, 2, 3
local TAB_LABELS = { "My quests", "Available", "Dungeons" }
local READY_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local MAX_OPEN_CHAIN = 5 -- longer chains fold their finished and later steps
local FILTERS = { "all", "ready", "tracked" }
local PAPER_FILL = { 0.85, 0.79, 0.64 }
local CHAIN_ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Chain"
local GIVER_ICON = "Interface\\GossipFrame\\AvailableQuestIcon"
local OBJECT_ICON = "Interface\\Icons\\INV_Scroll_03"
local ITEM_ICON = "Interface\\Icons\\INV_Misc_Note_01"

local COLORS = ns.Widgets.COLORS
local DOT = ns.Widgets.MIDDLE_DOT
local BACKGROUND = { 0.1, 0.075, 0.05 } -- the list: dark, in the warm brown of the frame's wood
local HEADER_BAR_LOW, HEADER_BAR_HIGH = { 0.23, 0.16, 0.09 }, { 0.31, 0.22, 0.13 }
local DUNGEON_NAME = { 0.91, 0.83, 1 }
local SWITCH_EDGE, SWITCH_TRACK = { 0.42, 0.32, 0.22 }, { 0.07, 0.05, 0.03 }
local RED_BUTTON_EDGE, RED_BUTTON_LIT = { 0.1, 0.04, 0.02 }, { 0.66, 0.13, 0.09 } -- tabs, where the game's own are missing
local BAR_BACKGROUND = { 0.13, 0.11, 0.08 }
local SELECTED_FILL = { 0.29, 0.24, 0.09 }
local SELECTED_EDGE = { 0.79, 0.64, 0.15 }

-- State.frame, State.list, State.detail: shared with the other parts, set further on
-- State.toggleButton: shared with the other parts, set further on
State.selectedTab = TAB_QUESTS
local selectedQuestIds = {} -- [tab] = questId
-- State.shownPlace: where "Show on map" leads
-- State.shownTurnInPlace: where "Show turn-in on map" leads
-- State.pickedZoneId: the zone the Available tab shows; nil follows the player
State.isPickingZone = false
State.isUpcomingShown = false
State.logFilter = "all"
-- State.selectedLogZoneId: set while the zone page is shown in place of a quest
State.isChainExpanded = false
State.isNarrow = false -- quest details on a page of their own (the setting): one pane, the list or a quest's page in its place
State.isPageSpread = false -- in the one pane: the quest's page in the list's place (opened by a click, or the controller's A)

---With the quest details on a page of their own, and the mouse: what was just opened (a quest clicked in the list,
---on the map, in the tracker) takes the one pane, in the list's place. The controller opens it with A instead
---(Gamepad.lua): its d-pad selects the quests as it moves over them.
function Log.spreadOpenedPage()
    if State.isNarrow and not (ns.Gamepad and ns.Gamepad.isGamepadUI()) then
        State.isPageSpread = true
    end
end
State.isDocked = false
State.isMapFollowPaused = false -- set while a button turns the map, so the Available list does not follow it
-- State.selectedAvailableQuest: the quest on the Available tab's page, with its giver and turn-in places
State.view = "quests" -- what the window shows: "quests" (the two tabs), "settings" or "chronicle"
State.isSettingsDrawn = false -- the last drawing was the settings, so the quest list's places are kept aside
State.settingsSectionIndex = 1 -- the section of the settings on the page
local nativeTabs = {} -- the tabs that are the game's own
-- State.setLowLevelCount: defined with the Available tab
-- State.zoneDropdown: the Available tab's location, as the game's own dropdown, when the client has one
-- Which quests the list keeps (all, ready, tracked): the game's dropdown beside the search, and how many quests
-- each filter keeps, for its lines
local filterDropdown = { counts = {} }
-- State.lowLevelBar, State.lowLevelCheck, State.lowLevelLabel: the fixed line under the Available list
-- State.shownTab: the tab the list was last drawn for
-- State.scrollTargetQuestId: a quest chosen outside the list (on the map, in the tracker), to bring into view
-- State.selectedRowTop, State.selectedRowBottom: where the selected quest's row was drawn in the list
local listScrollByTab = {} -- how far each tab's list was scrolled when it was last shown
local listOpening = {} -- while the panels open: isOpening, and the scrollTop of the group to start the list at
local detailScrollByTab = {} -- the same for the page beside the list
local shownDetailSubjectByTab = {}
local shownSubjectByTab = {} -- what each tab's list was last about, to start at the top when that changes
-- State.mapQuestId: a quest just chosen by hand, whose zone the map should turn to

Log.PANEL_WIDTH = PANEL_WIDTH
Log.TITLE_HEIGHT = TITLE_HEIGHT -- the room the flat border's buttons take at the top of the list's side
State.searchText = ""

---A modified click that does something else than selecting: Shift (the game's chat-link click) puts the quest's
---link in the chat; Ctrl on a quest of the log puts it in focus (or lets go of it), as its Focus button does.
---@return boolean isHandled
local function handleModifiedClick(questId)
    if not questId then
        return false
    end
    if ns.QuestState.isLinkClick() then
        ns.QuestState.linkInChat(questId)
        return true
    end
    if State.selectedTab == TAB_QUESTS and ns.QuestState.isFocusClick() then
        Log.focusQuest(questId)
        return true
    end
    return false
end

---Turns the map to a zone, sliding to a spot in it when one is given, without the Available list following the
---map: the list keeps its location and its selected quest.
---@param place table? The spot; nil shows the zone
local function showPlaceOnMap(zoneId, place)
    State.isMapFollowPaused = true
    ns.MapDock.showQuestPlace(zoneId, place)
    State.isMapFollowPaused = false
end

---@return table[] places Where an available quest starts: its givers, or where the item that starts it is found
local function getStartPlaces(questId)
    local places = ns.Location.getStarterPlaces(questId)
    if #places > 0 then
        return places
    end
    local itemSource = ns.Location.getStartItemSource(questId)
    return itemSource and itemSource.places or {}
end

---An available quest picked up away from the map (a dungeon's quest given in The Barrens, a lead-in in a city):
---the map turns to where it starts, and the list stays where it is.
local function showAvailableQuestStart(questId)
    local places = getStartPlaces(questId)
    local shownZoneId = ns.MapDock.getShownZoneId()
    for _, place in ipairs(places) do
        if ns.Database.getParentZoneId(place.mapZoneId or 0) == shownZoneId or place.groupZoneId == shownZoneId then
            return -- on the map already
        end
    end
    if #places == 0 then
        return
    end
    local _, _, nearestPlace = ns.Geometry.getNearest(places, ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
    nearestPlace = nearestPlace or places[1]
    showPlaceOnMap(nearestPlace.mapZoneId or nearestPlace.groupZoneId, nearestPlace.x >= 0 and nearestPlace or nil)
end

---A quest chosen by hand on the Available or Dungeons tab: the map turns to where it starts and slides to it, as
---for a quest in the log. The list stays on its location meanwhile, though the map now shows another zone.
local function showChosenQuestStart(quest)
    local place = quest.nearestPlace or quest.places[1]
    if place and place.x >= 0 then
        showPlaceOnMap(place.mapZoneId or place.groupZoneId, place)
    end
end

---A click on a quest in the list. The selected quest is the highlighted one: its page is open and the map
---shows it in full (on the Available tab: where it starts and ends). Clicking it again deselects it, which
---leaves nothing highlighted.
local function selectQuest(questId)
    if handleModifiedClick(questId) then
        return
    end
    -- With the settings open, a click opens the quest, even the one that was selected before
    local wasShowingSettings = State.view == "settings"
    State.view = "quests"
    local isSameQuest = not wasShowingSettings
        and selectedQuestIds[State.selectedTab] == questId
        and not (State.selectedTab == TAB_QUESTS and State.selectedLogZoneId)
    -- (in the one pane the list shows the open quest highlighted: a click opens its page again, it never closes it)
    if isSameQuest and not State.isNarrow then
        questId = nil
    end
    if questId then
        Log.spreadOpenedPage()
    end
    selectedQuestIds[State.selectedTab] = questId
    State.unfocusedSelection = nil -- (picked in the list: the map shows it again, Log.getSelectedQuestId)
    State.selectedLogZoneId, State.isChainExpanded = nil, false
    State.mapQuestId = questId
    if questId and State.selectedTab == TAB_AVAILABLE then
        showAvailableQuestStart(questId)
    end
    Log.refresh()
    ns.MapPins.queueRefresh()
end

local function selectZone(zoneId)
    State.view = "quests"
    State.selectedLogZoneId = zoneId
    Log.spreadOpenedPage()
    ns.MapDock.showZoneMap(zoneId)
    Log.refresh()
end

---Puts a quest in focus: it becomes the tracker's active quest, tracked first if it was not, and the one
---the map draws in full. Done again on the same quest, it takes the focus off.
local function focusQuest(questId)
    if questId == ns.Focus.get() then
        ns.Focus.set(nil) -- focusing the focused quest again lets go of it
        return
    end
    -- Only a tracked quest can be followed; when the game will not track it, it says why
    if ns.QuestState.addWatch(questId) then
        ns.Focus.set(questId)
    end
end

Log.focusQuest = focusQuest

local hoveredQuestIds = {} -- [tab] = the quest under the mouse in that tab's list

---Hovering a quest in the list highlights it on the map until the mouse moves on, as the game's quest log does.
local function handleQuestEnter(_, questId)
    hoveredQuestIds[State.selectedTab] = questId
    ns.MapPins.queueHoverRefresh() -- once the mouse rests on it, not for every row it crosses
end

local function handleQuestLeave()
    -- (whichever quest: a pooled row redrawn under a resting pointer holds another quest by the time it is left)
    if hoveredQuestIds[State.selectedTab] ~= nil then
        hoveredQuestIds[State.selectedTab] = nil
        ns.MapPins.queueHoverRefresh()
    end
end

local function toggleTracked(questId)
    if ns.QuestState.isWatched(questId) then
        C_QuestLog.RemoveQuestWatch(questId)
        ns.QuestState.forgetWatches()
        ns.Focus.handleQuestGone(questId, true) -- lets go of it everywhere, this list included; still in the log
    else
        ns.QuestState.addWatch(questId)
    end
    Log.refresh()
    ns.Tracker.queueRefresh()
end

---A zone's "Track all" and "Untrack all" in a right-click menu, as the game's tracker has them on its zone
---headings: each only when it would change something.
---@param questIds number[] The zone's quests in the log
function Log.addTrackMenuItems(root, questIds)
    local watchedCount = ns.QuestState.countWatched(questIds or {})
    local function refresh()
        Log.refresh()
        ns.Tracker.queueRefresh()
    end
    if watchedCount < #(questIds or {}) then
        root:CreateButton(ns.L("Track all"), function()
            ns.QuestState.watchAll(questIds)
            refresh()
        end)
    end
    if watchedCount > 0 then
        root:CreateButton(ns.L("Untrack all"), function()
            ns.QuestState.unwatchAll(questIds)
            refresh()
        end)
    end
end

---Right-click on a quest in the list: the game's menu of what can be done with it. A quest in the log can be
---focused, tracked, shared to chat and with the party, or abandoned; one to pick up can be shared to chat.
function Log.openQuestMenu(questId, isInLog)
    if not MenuUtil or not questId then
        return
    end
    -- The game's menu belongs to a frame: the list it was opened from
    local canvas = Log.getListCanvas()
    ns.openMenu(canvas and canvas.content or UIParent, function(_, root)
        ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
        root:CreateTitle(ns.QuestText.getQuestName(questId) or ("Quest " .. questId))
        if isInLog then
            local isFocused = questId == ns.Focus.get()
            root:CreateButton(ns.L(isFocused and "Unfocus" or "Focus"), function()
                focusQuest(questId)
            end)
            root:CreateButton(ns.L(ns.QuestState.isWatched(questId) and "Untrack" or "Track"), function()
                toggleTracked(questId)
            end)
        end
        ns.LogDiagram.addMenuItem(root, questId)
        root:CreateButton(ns.L("Share to chat"), function()
            ns.QuestState.linkInChat(questId)
        end)
        ns.WowheadLink.addMenuItem(root, questId)
        ns.QuestText.addVoiceMenuItems(root, questId) -- a translation addon's narration, when the quest has one
        if isInLog then
            local share = root:CreateButton(ns.L("Share with the party"), function()
                Log.shareQuest(questId)
            end)
            local canShare = C_QuestLog.IsPushableQuest
                and C_QuestLog.IsPushableQuest(questId)
                and IsInGroup
                and IsInGroup()
            if not canShare and share.SetEnabled then
                share:SetEnabled(false)
            end
            root:CreateDivider()
            root:CreateButton("|cffff5040" .. ns.L("Abandon") .. "|r", function()
                Log.abandonQuest(questId)
            end)
        else
            -- One to pick up the player does not want offered (or the realm does not have): hidden till brought back
            root:CreateDivider()
            root:CreateButton(ns.L("Hide this quest"), function()
                ns.QuestHiding.hide(questId)
            end)
        end
    end)
end

-- Fields, not locals: this file is near Lua's limit of locals in one chunk
function Log.openLogQuestMenu(questId)
    Log.openQuestMenu(questId, true)
end
function Log.openAvailableQuestMenu(questId)
    Log.openQuestMenu(questId, false)
end

---Gives a small window of the quest window's own (the drop window, the hint ladder) its flat look: a fill and a
---1px edge.
---@param edge number[] The edge's colour
---@param back number[] The fill's colour, its alpha 1 unless given
function Style.setEdged(frame, edge, back)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(back[1], back[2], back[3], back[4] or 1)
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
end

---Puts the flat cross the quest window's drawn parts use (Media\Close), lit on hover, in a small window's top
---right corner: a click hides the window.
---@param inset number How far from the window's top and right edges
---@return Button close
function Style.addCloseButton(window, inset)
    local close = CreateFrame("Button", nil, window)
    close:SetSize(14, 14)
    close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -inset, -inset)
    local crossFile = MEDIA .. "Close"
    local cross = close:CreateTexture(nil, "ARTWORK")
    cross:SetAllPoints(close)
    cross:SetTexture(crossFile)
    cross:SetVertexColor(0.85, 0.85, 0.85)
    local lit = close:CreateTexture(nil, "HIGHLIGHT")
    lit:SetAllPoints(close)
    lit:SetTexture(crossFile)
    lit:SetBlendMode("ADD")
    lit:SetAlpha(0.5)
    close:SetScript("OnClick", function()
        window:Hide()
    end)
    return close
end

local function isMatch(...)
    if State.searchText == "" then
        return true
    end
    for index = 1, select("#", ...) do
        local text = select(index, ...)
        if text and text:lower():find(State.searchText, 1, true) then
            return true
        end
    end
    return false
end

-- Shared with the other parts of the window
Style.BACKGROUND = BACKGROUND
Style.BAR_BACKGROUND = BAR_BACKGROUND
Style.BAR_HEIGHT = BAR_HEIGHT
Style.CHAIN_ICON = CHAIN_ICON
Style.UNLOCK_ICON = MEDIA .. "Unlock" -- a quest that opens others, where the chain's mark would stand
Style.COLORS = COLORS
Style.DOT = DOT
Style.DUNGEON_NAME = DUNGEON_NAME
Style.FILTERS = FILTERS
Style.GIVER_ICON = GIVER_ICON
Style.LOCK_ICON = "Interface\\LFGFrame\\UI-LFG-ICON-LOCK" -- the game's padlock, for a quest that cannot be taken yet
Style.HEADER_BAR_HIGH = HEADER_BAR_HIGH
Style.HEADER_BAR_LOW = HEADER_BAR_LOW
Style.ITEM_ICON = ITEM_ICON
Style.LIST_WIDTH = LIST_WIDTH
Style.LOW_LEVEL_BAR_HEIGHT = LOW_LEVEL_BAR_HEIGHT
Style.MAX_OPEN_CHAIN = MAX_OPEN_CHAIN
Style.MEDIA = MEDIA
Style.OBJECT_ICON = OBJECT_ICON
Style.PADDING = PADDING
Style.PAGE_CONTENT_WIDTH = PAGE_CONTENT_WIDTH
Style.PAGE_TOP = PAGE_TOP
Style.PAGE_WIDTH = PAGE_WIDTH
Style.PANEL_WIDTH = PANEL_WIDTH
Style.PAPER_FILL = PAPER_FILL
Style.READY_ICON = READY_ICON
Style.RED_BUTTON_EDGE = RED_BUTTON_EDGE
Style.RED_BUTTON_LIT = RED_BUTTON_LIT
Style.SCROLL_ARROW_HEIGHT = SCROLL_ARROW_HEIGHT
Style.SEARCH_HEIGHT = SEARCH_HEIGHT
Style.SELECTED_EDGE = SELECTED_EDGE
Style.SELECTED_FILL = SELECTED_FILL
Style.SWITCH_EDGE = SWITCH_EDGE
Style.SWITCH_TRACK = SWITCH_TRACK
Style.TAB_AVAILABLE = TAB_AVAILABLE
Style.TAB_DUNGEONS = TAB_DUNGEONS
Style.TAB_LABELS = TAB_LABELS
Style.TAB_QUESTS = TAB_QUESTS
Style.TITLE_HEIGHT = TITLE_HEIGHT
Style.ZONE_MENU_HEIGHT = ZONE_MENU_HEIGHT
State.detailScrollByTab = detailScrollByTab
State.filterDropdown = filterDropdown
Actions.focusQuest = focusQuest
Actions.handleQuestEnter = handleQuestEnter
Actions.handleQuestLeave = handleQuestLeave
State.hoveredQuestIds = hoveredQuestIds
Actions.isMatch = isMatch
State.listOpening = listOpening
State.listScrollByTab = listScrollByTab
State.nativeTabs = nativeTabs
Actions.selectQuest = selectQuest
Actions.showChosenQuestStart = showChosenQuestStart
Actions.showPlaceOnMap = showPlaceOnMap
Actions.selectZone = selectZone
State.selectedQuestIds = selectedQuestIds
State.shownDetailSubjectByTab = shownDetailSubjectByTab
State.shownSubjectByTab = shownSubjectByTab
Actions.toggleTracked = toggleTracked
