

local addonName, ns = ... -- the addon's folder, which its pictures are read from

-- The quest panels joined to the right side of the game's world map (see MapDock): a dark list, then the
-- selected quest on parchment, with actions under it. Two tabs: the quests in the log, grouped by where their
-- next step takes place, and the quests available in a zone.
local Log = {}
ns.Log = Log

-- The window is made of parts, each a file under Log\, loaded in this order:
--   Base          what every part shares: the look (ns.LogStyle), the window's state (ns.LogState), and actions on
--                 quests (ns.LogActions: select, focus, track, their menus)
--   List          the list on the left: headings and quest rows (ns.LogList)
--   QuestPage     the page on parchment: a quest's page, its header and rewards, a zone's page (ns.LogQuestPage)
--   QuestsTab     the My quests tab (ns.LogQuestsTab)
--   AvailableTab  the Available tab: quests to pick up, dungeon runs (ns.LogAvailableTab)
--   SettingsView  the settings, drawn in the window (ns.LogSettingsView)
--   Window        the window itself and its public functions, ns.Log (ns.LogWindow for its own parts)
-- A part reaches another only through these tables. What is set once is copied into a local at the top of the
-- part that uses it; what changes (the selected tab, the shown quest) lives in ns.LogState and is read there.
local Style, State, Actions = {}, {}, {}
ns.LogStyle, ns.LogState, ns.LogActions = Style, State, Actions
ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow = {}, {}, {}, {}, {}, {}
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
local BUTTON_FILL = { 0.23, 0.08, 0.06 }

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
State.isNarrow = false -- with a controller: one pane, the list or a quest's page in its place (Gamepad.lua)
State.isPageSpread = false -- in the one pane: the quest's page in the list's place (the controller's A on a quest)
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

---A click on a quest in the list. The selected quest is the highlighted one: its page is open and the map
---shows it in full (on the Available tab: where it starts and ends). Clicking it again deselects it, which
---leaves nothing highlighted.
local function selectQuest(questId)
    -- Shift-click (the game's chat-link click): the quest's link in the chat, nothing else changes
    if questId and ns.QuestState.isLinkClick() then
        ns.QuestState.linkInChat(questId)
        return
    end
    -- Ctrl-click a quest of the log: it is put in focus (or let go of, when it was), as its Focus button does
    if questId and State.selectedTab == TAB_QUESTS and ns.QuestState.isFocusClick() then
        Log.focusQuest(questId)
        return
    end
    -- With the settings open, a click opens the quest, even the one that was selected before
    local wasShowingSettings = State.view == "settings"
    State.view = "quests"
    local isSameQuest = not wasShowingSettings and selectedQuestIds[State.selectedTab] == questId and not (State.selectedTab == TAB_QUESTS and State.selectedLogZoneId)
    if isSameQuest then
        questId = nil
    end
    selectedQuestIds[State.selectedTab] = questId
    State.unfocusedSelection = nil -- (picked in the list: the map shows it again, Log.getSelectedQuestId)
    State.selectedLogZoneId, State.isChainExpanded = nil, false
    State.mapQuestId = questId
    -- An available quest picked up away from the map (a dungeon's quest given in The Barrens, a lead-in in a
    -- city): the map turns to where it starts, and the list stays where it is
    if questId and State.selectedTab == TAB_AVAILABLE then
        local places = ns.Location.getStarterPlaces(questId)
        if #places == 0 then
            local itemSource = ns.Location.getStartItemSource(questId)
            places = itemSource and itemSource.places or {}
        end
        local shownZoneId = ns.MapDock.getShownZoneId()
        local isOnMap = false
        for _, place in ipairs(places) do
            isOnMap = isOnMap or ns.Database.getParentZoneId(place.mapZoneId or 0) == shownZoneId or place.groupZoneId == shownZoneId
        end
        if not isOnMap and #places > 0 then
            local _, _, nearestPlace = ns.Geometry.getNearest(places, ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
            nearestPlace = nearestPlace or places[1]
            State.isMapFollowPaused = true
            ns.MapDock.showQuestPlace(nearestPlace.mapZoneId or nearestPlace.groupZoneId, nearestPlace.x >= 0 and nearestPlace or nil)
            State.isMapFollowPaused = false
        end
    end
    Log.refresh()
    ns.MapPins.queueRefresh()
end

local function selectZone(zoneId)
    State.view = "quests"
    State.selectedLogZoneId = zoneId
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

local function handleQuestLeave(_, questId)
    if hoveredQuestIds[State.selectedTab] == questId then
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
            root:CreateButton(ns.L(isFocused and "Unfocus" or "Focus"), function() focusQuest(questId) end)
            root:CreateButton(ns.L(ns.QuestState.isWatched(questId) and "Untrack" or "Track"), function() toggleTracked(questId) end)
        end
        root:CreateButton(ns.L("Share to chat"), function() ns.QuestState.linkInChat(questId) end)
        ns.QuestText.addVoiceMenuItems(root, questId) -- a translation addon's narration, when the quest has one
        if isInLog then
            local share = root:CreateButton(ns.L("Share with the party"), function() Log.shareQuest(questId) end)
            local canShare = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questId) and IsInGroup and IsInGroup()
            if not canShare and share.SetEnabled then
                share:SetEnabled(false)
            end
            root:CreateDivider()
            root:CreateButton("|cffff5040" .. ns.L("Abandon") .. "|r", function() Log.abandonQuest(questId) end)
        else
            -- One to pick up the player does not want offered (or the realm does not have): hidden till brought back
            root:CreateDivider()
            root:CreateButton(ns.L("Hide this quest"), function() ns.QuestHiding.hide(questId) end)
        end
    end)
end

-- Fields, not locals: this file is near Lua's limit of locals in one chunk
function Log.openLogQuestMenu(questId) Log.openQuestMenu(questId, true) end
function Log.openAvailableQuestMenu(questId) Log.openQuestMenu(questId, false) end

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
Actions.selectZone = selectZone
State.selectedQuestIds = selectedQuestIds
State.shownDetailSubjectByTab = shownDetailSubjectByTab
State.shownSubjectByTab = shownSubjectByTab
Actions.toggleTracked = toggleTracked
