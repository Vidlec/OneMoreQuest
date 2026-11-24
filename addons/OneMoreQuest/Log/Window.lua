local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: the window itself (its frame, tabs, header, buttons) and its public functions (ns.Log).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local focusQuest, toggleTracked = Actions.focusQuest, Actions.toggleTracked
local drawAvailableTab, pickZone, toggleLowLevel =
    AvailableTab.drawAvailableTab, AvailableTab.pickZone, AvailableTab.toggleLowLevel
local createPageHeader, createRewardsBlock, followPageScroll, setAtlasIfKnown, setPageHeader, setPageRewards =
    QuestPage.createPageHeader,
    QuestPage.createRewardsBlock,
    QuestPage.followPageScroll,
    QuestPage.setAtlasIfKnown,
    QuestPage.setPageHeader,
    QuestPage.setPageRewards
local FILTER_LABELS, drawLogTab, selectFilter = QuestsTab.FILTER_LABELS, QuestsTab.drawLogTab, QuestsTab.selectFilter
local detailScrollByTab, filterDropdown, hoveredQuestIds, listOpening, listScrollByTab, nativeTabs =
    State.detailScrollByTab,
    State.filterDropdown,
    State.hoveredQuestIds,
    State.listOpening,
    State.listScrollByTab,
    State.nativeTabs
local placeTabHints -- (the shoulder buttons beside the tabs: with the tabs' drawing, below)
local selectedQuestIds, shownDetailSubjectByTab, shownSubjectByTab =
    State.selectedQuestIds, State.shownDetailSubjectByTab, State.shownSubjectByTab
local BACKGROUND, BAR_BACKGROUND, BAR_HEIGHT, COLORS, FILTERS, HEADER_BAR_LOW =
    Style.BACKGROUND, Style.BAR_BACKGROUND, Style.BAR_HEIGHT, Style.COLORS, Style.FILTERS, Style.HEADER_BAR_LOW
local LIST_WIDTH, LOW_LEVEL_BAR_HEIGHT, PAGE_CONTENT_WIDTH, PAGE_TOP, PAGE_WIDTH, PANEL_WIDTH =
    Style.LIST_WIDTH,
    Style.LOW_LEVEL_BAR_HEIGHT,
    Style.PAGE_CONTENT_WIDTH,
    Style.PAGE_TOP,
    Style.PAGE_WIDTH,
    Style.PANEL_WIDTH
local RED_BUTTON_EDGE, RED_BUTTON_LIT, SCROLL_ARROW_HEIGHT, SEARCH_HEIGHT, TAB_AVAILABLE, TAB_LABELS =
    Style.RED_BUTTON_EDGE,
    Style.RED_BUTTON_LIT,
    Style.SCROLL_ARROW_HEIGHT,
    Style.SEARCH_HEIGHT,
    Style.TAB_AVAILABLE,
    Style.TAB_LABELS
local TAB_QUESTS, TITLE_HEIGHT, ZONE_MENU_HEIGHT = Style.TAB_QUESTS, Style.TITLE_HEIGHT, Style.ZONE_MENU_HEIGHT
local TAB_DUNGEONS = Style.TAB_DUNGEONS
local DungeonsTab = ns.LogDungeonsTab
local BACK_STRIP_HEIGHT = 24 -- over the page in the list's place: the way back to the list
-- (the spellbook's page-back arrow: in every client, the game's own look for "back")
local BACK_ARROW_MARKUP = "|TInterface\\Buttons\\UI-SpellbookIcon-PrevPage-Up:22:22:-4:0|t"
local NARROW_WIDTH = LIST_WIDTH + 4 -- the window with a controller: one pane, as wide as the list
local PAGE_BOTTOM_NARROW = 3 -- with a controller the page runs to the window's foot: no bar of buttons under it

---------------------------------------------------------------------------------------------------------------
-- The window

---The game's tab look: the open tab red with white text, the other in the frame's wood with gold text.
local function setTabLook(tab, isSelected)
    if nativeTabs[tab] then
        if isSelected then
            PanelTemplates_SelectTab(tab)
        else
            PanelTemplates_DeselectTab(tab)
        end
        return
    end
    local fill = isSelected and RED_BUTTON_LIT or HEADER_BAR_LOW
    tab.fill:SetColorTexture(fill[1], fill[2], fill[3], 1)
    tab.edge:SetColorTexture(RED_BUTTON_EDGE[1], RED_BUTTON_EDGE[2], RED_BUTTON_EDGE[3], 1)
    ns.Widgets.setColor(tab.label, isSelected and COLORS.white or COLORS.gold)
end

local function updateControls(selected, tabCount)
    local isQuestsTab = State.selectedTab == TAB_QUESTS
    local isAvailableTab, isDungeonsTab = State.selectedTab == TAB_AVAILABLE, State.selectedTab == TAB_DUNGEONS
    -- A dungeon's page (no quest of it opened): its way in on the map, and the DungeonJournal addon's page of it
    local shownDungeon = isDungeonsTab and State.shownDungeon or nil
    State.frame.entranceButton:SetShown(shownDungeon ~= nil and shownDungeon.entrance ~= nil)
    State.frame.journalButton:SetShown(
        shownDungeon ~= nil and ns.DungeonJournal ~= nil and ns.DungeonJournal.knows(shownDungeon.name)
    )
    local isZonePage = isQuestsTab and selected ~= nil and selected.entries ~= nil
    local questId = selected and selected.questId
    State.frame.shownZoneGroup = isZonePage and selected or nil
    State.frame.trackAllButton:SetShown(isZonePage)
    State.frame.zoneMapButton:SetShown(isZonePage)
    State.frame.trackButton:SetShown(isQuestsTab and questId ~= nil)
    State.frame.focusButton:SetShown(isQuestsTab and questId ~= nil)
    State.frame.shareButton:SetShown(isQuestsTab and questId ~= nil)
    State.frame.abandonButton:SetShown(isQuestsTab and questId ~= nil)

    -- On the Available tab the bar holds the two map buttons; the quest page has its own on the other tab
    local hasPlace = not isQuestsTab and State.shownPlace ~= nil and State.shownPlace.x >= 0
    local hasTurnInPlace = not isQuestsTab and State.shownTurnInPlace ~= nil and State.shownTurnInPlace.x >= 0
    State.frame.mapButton:SetShown(hasPlace)
    State.frame.turnInMapButton:SetShown(hasTurnInPlace)
    Log.setButtonText(
        State.frame.mapButton,
        ns.L(selected and selected.startType == "item" and "Show source" or "Show giver")
    )
    State.frame.turnInMapButton:ClearAllPoints()
    if hasPlace then
        State.frame.turnInMapButton:SetPoint("LEFT", State.frame.mapButton, "RIGHT", 6, 0)
    else
        State.frame.turnInMapButton:SetPoint("LEFT", State.frame.bar, "LEFT", 10, 0)
    end

    State.frame.search:SetShown(isQuestsTab)
    if type(State.frame.search.Instructions) == "table" and State.frame.search.Instructions.SetText then
        State.frame.search.Instructions:SetText(ns.L("Search")) -- the game's template writes its own, in the client's language
    end
    if filterDropdown.button then
        filterDropdown.button:SetShown(isQuestsTab)
    end
    State.frame.searchLabel:SetText(ns.L(isQuestsTab and "Search quests" or "Location"))
    State.frame.zoneButton:SetShown(isAvailableTab and not State.zoneDropdown)
    State.frame.availableSearch:SetShown(isAvailableTab and not State.isPickingZone)
    if
        type(State.frame.availableSearch.Instructions) == "table" and State.frame.availableSearch.Instructions.SetText
    then
        State.frame.availableSearch.Instructions:SetText(ns.L("Search"))
    end
    if State.zoneDropdown then
        State.zoneDropdown:SetShown(isAvailableTab)
    end
    -- The low-level switch stays put under the Available list, which ends above it
    State.lowLevelBar:SetShown(isAvailableTab)
    if isQuestsTab and questId then
        -- Each button says what it will do, as the game's own quest log does ("Untrack")
        local isWatched = ns.QuestState.isWatched(questId)
        Log.setButtonText(State.frame.trackButton, ns.L(isWatched and "Untrack" or "Track"))
        local isFocused = questId == ns.Focus.get()
        Log.setButtonText(State.frame.focusButton, ns.L(isFocused and "Unfocus" or "Focus"))
        local canShare = C_QuestLog.IsPushableQuest
            and C_QuestLog.IsPushableQuest(questId)
            and IsInGroup
            and IsInGroup()
        State.frame.shareButton:SetEnabled(canShare == true)
    end
    State.frame.resetSettingsButton:Hide()
    State.frame.doneButton:Hide()
    State.frame.journalBackButton:Hide()
    for _, control in ipairs({ State.frame.status, State.frame.tabRowFill, State.frame.tabRowRule }) do
        control:Show()
    end
    -- With this addon's quests to pick up switched off, or the Spoilers choice naming none, the game's own marks show
    -- them and the tab goes; the Dungeons tab goes where the choice keeps dungeons back. The tabs left close up.
    local isAvailableShown, isDungeonsShown = List.isAvailableTabShown(), List.isDungeonsTabShown()
    local shownTabsKey = (isAvailableShown and "a" or "") .. (isDungeonsShown and "d" or "")
    local isTabsMoved = State.frame.shownTabsKey ~= shownTabsKey
    State.frame.shownTabsKey = shownTabsKey
    local previousTab
    for tab, button in ipairs(State.frame.tabs) do
        local isShown = (tab ~= TAB_AVAILABLE or isAvailableShown) and (tab ~= TAB_DUNGEONS or isDungeonsShown)
        button:SetShown(isShown)
        if isShown then
            if previousTab and isTabsMoved then
                button:ClearAllPoints()
                button:SetPoint("LEFT", previousTab, "RIGHT", nativeTabs[button] and 3 or -1, 0)
            end
            previousTab = button
        end
    end
    if isTabsMoved and previousTab then
        State.frame.tabHintsKey = nil -- (the shoulder buttons and the quests' count after the last tab shown: placed again)
        placeTabHints(State.frame.isShowingTabHints == true)
    end
    for tab, button in ipairs(State.frame.tabs) do
        setTabLook(button, tab == State.selectedTab)
    end
    if tabCount then
        State.frame.tabCounts[State.selectedTab] = tabCount
    end
    -- Each tab with the count it last showed, named again in the language of the moment
    for tabIndex, tab in ipairs(State.frame.tabs) do
        local shownCount = State.frame.tabCounts[tabIndex]
        -- (the Dungeons tab with no count: how many dungeons there are tells nothing)
        local text = shownCount
                and tabIndex ~= TAB_DUNGEONS
                and string.format("%s (%d)", ns.L(TAB_LABELS[tabIndex]), shownCount)
            or ns.L(TAB_LABELS[tabIndex])
        if tabIndex == TAB_QUESTS then
            -- The quest log's size is on its tab: "My quests (31/40)", the count amber nearly full, red full (beside the
            -- tabs stand a controller's LB and RB)
            local count, max, isNearlyFull = ns.Warnings.getLogSize()
            local colour = count >= max and "ff9a7a" or isNearlyFull and "ffb84d" or nil
            local size = string.format("%d/%d", count, max)
            text = string.format(
                "%s (%s)",
                ns.L(TAB_LABELS[tabIndex]),
                colour and ("|cff" .. colour .. size .. "|r") or size
            )
        end
        if tabIndex == State.selectedTab and tabCount or State.frame.tabTexts[tabIndex] ~= text then
            State.frame.tabTexts[tabIndex] = text
            if nativeTabs[tab] then
                tab:SetText(text)
                PanelTemplates_TabResize(tab, 0)
            else
                tab.label:SetText(text)
            end
        end
    end
end

---A button of the bar with its words, widened when they need more room than it was made with (Czech runs long).
function Log.setButtonText(button, text)
    ns.Widgets.setButtonFonts(button) -- the game's button fonts lack Czech letters
    button:SetText(text)
    local textWidth = button.GetTextWidth and button:GetTextWidth()
    if type(textWidth) == "number" and button.baseWidth then
        button:SetWidth(math.max(button.baseWidth, math.ceil(textWidth) + 20))
    end
end

---Names the bar's buttons again, in the language of the moment; those that change with the quest are named as
---the quest is drawn.
function Log.applyButtonTexts()
    for _, button in ipairs(State.frame.textButtons or {}) do
        Log.setButtonText(button, ns.L(button.textKey))
    end
end

local drawWindow

---Draws the window again; then, with a controller, its marks for the game's navigation (Gamepad.lua).
function Log.refresh()
    drawWindow()
    if ns.Gamepad and ns.Gamepad.handleDrawn then
        ns.Gamepad.handleDrawn()
    end
end

---With a controller, the shoulder buttons beside the tabs as the game's own windows show them (its
---GamepadTabIndicatorsTemplate): its icon frame for each, 26 across with its shadow, LB against the first tab, RB
---against the last (they step from tab to tab); the tabs and the quests' count moved to make room.
local TAB_HINT_SIZE = 26
local function makeTabHint(frame, key)
    local isMade, hint = pcall(CreateFrame, "Frame", nil, frame, "InputIconTextureFrameTemplate")
    if isMade and type(hint) == "table" and hint.SetInputKey then
        hint:SetInputKey(key)
    else
        -- (no such template in this client: the icon alone)
        hint = CreateFrame("Frame", nil, frame)
        local icon = hint:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(hint)
        local iconUtility = type(InputIconTextureSetUtility) == "table"
            and InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture
        local atlas = iconUtility and iconUtility(key)
        if atlas then
            icon:SetAtlas(atlas)
        end
    end
    hint:SetSize(TAB_HINT_SIZE, TAB_HINT_SIZE)
    hint:SetFrameLevel((frame:GetFrameLevel() or 1) + 5)
    hint:EnableMouse(false)
    return hint
end

placeTabHints = function(isPad)
    local frame = State.frame
    local tabs = frame and frame.tabs
    if not tabs or not tabs[1] then
        return
    end
    local lastTab = tabs[1]
    for _, tab in ipairs(tabs) do
        if tab:IsShown() then
            lastTab = tab
        end
    end
    if not nativeTabs[tabs[1]] then
        frame.status:ClearAllPoints() -- (the drawn tabs of an older client: no shoulder buttons)
        frame.status:SetPoint("LEFT", lastTab, "RIGHT", 10, 0)
        return
    end
    if isPad and not frame.tabHints then
        frame.tabHints = { makeTabHint(frame, "PADLSHOULDER"), makeTabHint(frame, "PADRSHOULDER") }
    end
    local key = tostring(isPad) .. tostring(lastTab)
    if frame.tabHintsKey == key then
        return
    end
    frame.tabHintsKey, frame.isShowingTabHints = key, isPad
    tabs[1]:ClearAllPoints()
    tabs[1]:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", isPad and (2 + TAB_HINT_SIZE) or 8, -TITLE_HEIGHT - 1)
    frame.status:ClearAllPoints()
    if isPad then
        local left, right = frame.tabHints[1], frame.tabHints[2]
        left:ClearAllPoints()
        left:SetPoint("RIGHT", tabs[1], "LEFT", 0, -1)
        right:ClearAllPoints()
        right:SetPoint("LEFT", lastTab, "RIGHT", 0, -1)
        frame.status:SetPoint("LEFT", right, "RIGHT", 2, 1) -- (after RB, never under it)
        frame.status:SetWidth(40)
    else
        frame.status:SetPoint("LEFT", lastTab, "RIGHT", 10, 0)
        frame.status:SetWidth(70)
    end
    for _, hint in ipairs(frame.tabHints or {}) do
        hint:SetShown(isPad)
    end
end
drawWindow = function()
    if not State.frame or not State.isDocked or not State.frame:IsVisible() then
        State.isStale = true -- something changed while the window was closed: drawn again as it opens
        return
    end
    State.isStale = false
    State.drawnPosition = ns.Geometry.getPlayerPosition()
    State.drawnHeight = State.frame:GetHeight() -- (the height it is drawn for: a size change to it needs no drawing)
    Log.applyButtonTexts()
    -- The journal's search and dropdowns are frames of its own: shown again only if the journal is what is drawn
    if ns.ChroniclePage and ns.ChroniclePage.hideJournalControls then
        ns.ChroniclePage.hideJournalControls()
    end
    State.frame.journalBackButton:Hide() -- shown again only over a quest's story in the journal
    -- The Dungeons tab's buttons too: the settings and the chronicle have their own bar (updateControls puts them back)
    State.frame.entranceButton:Hide()
    State.frame.journalButton:Hide()
    State.frame.ironPage:Hide() -- the parchment again; the settings put their dark ground back as they are drawn
    if State.languageDropdown then
        State.languageDropdown:Hide() -- About shows it again as it is drawn
    end
    for _, dropdown in pairs(State.settingDropdowns or {}) do
        if dropdown then
            dropdown:Hide() -- the settings show theirs again as they are drawn
        end
    end
    -- With the quest details on a page of their own (the setting) the quests show in one pane, the list or a quest's
    -- page in its place; the settings and the chronicle need both columns, and have the whole width
    local isOnePane = ns.settings.questDetails == "own"
    if State.isNarrow ~= isOnePane then
        State.isNarrow, State.isPageSpread = isOnePane, false
    end
    -- (the page in the one pane is the open quest's or zone's: with nothing open, an abandoned quest, the list again)
    local hasOpenPage = selectedQuestIds[State.selectedTab] ~= nil
        or (State.selectedTab == TAB_QUESTS and State.selectedLogZoneId ~= nil)
    if State.view ~= "quests" or not hasOpenPage then
        State.isPageSpread = false
    end
    local isNarrow = State.isNarrow and State.view == "quests"
    local isSpread = isNarrow and State.isPageSpread
    if not (isNarrow and not isSpread) then
        Window.bringPageBack() -- (kept away while the list has the one pane: no showing and hiding it each drawing)
    end
    Window.setWidth(isNarrow and NARROW_WIDTH or PANEL_WIDTH)
    -- With a controller the page's buttons are X's, Y's and B's (Y has them all as a menu): no bar of them, the page
    -- runs to the window's foot (the settings and the chronicle too). With the mouse the bar stands under the page,
    -- in the one pane too (while the list has it, the bar is put away with the page).
    local isPad = ns.Gamepad ~= nil and ns.Gamepad.isGamepadUI()
    State.frame.bar:SetShown(not isPad)
    placeTabHints(isPad and not isSpread and State.view == "quests") -- (the settings and the chronicle hide the tabs)
    State.pageBottom = isPad and PAGE_BOTTOM_NARROW or BAR_HEIGHT
    State.list.frame:SetShown(not isSpread)
    State.frame.divider:SetShown(not isNarrow)
    State.frame.listArt:SetShown(not isSpread and State.frame.hasListArt)
    State.frame.backStrip:SetShown(isSpread)
    if State.view == "quests" then
        if isSpread then
            State.frame.placeSplit(0, BACK_STRIP_HEIGHT, -LIST_WIDTH, State.pageBottom) -- the page where the list was
        else
            State.frame.placeSplit(LIST_WIDTH, 0, 0, State.pageBottom)
        end
    end
    if State.view == "settings" then
        SettingsView.refreshSettings()
        return
    end
    if State.view == "chronicle" then
        Log.drawChronicle()
        return
    end
    local wasSettingsDrawn = State.isSettingsDrawn
    State.isSettingsDrawn = false
    if
        (State.selectedTab == TAB_AVAILABLE and not List.isAvailableTabShown())
        or (State.selectedTab == TAB_DUNGEONS and not List.isDungeonsTabShown())
    then
        State.selectedTab = TAB_QUESTS -- the tab was switched off (or the Spoilers choice took it away) while it was open
    end
    -- Placed before the list is drawn: its scroll range is measured against the height it has now
    -- The Dungeons tab has no search row: its list starts under the tabs
    State.list.frame:SetPoint(
        "TOPLEFT",
        State.frame,
        "TOPLEFT",
        6,
        -(TITLE_HEIGHT + (State.selectedTab == TAB_DUNGEONS and 4 or SEARCH_HEIGHT))
    )
    State.list.frame:SetPoint(
        "BOTTOMLEFT",
        State.frame,
        "BOTTOMLEFT",
        6,
        State.selectedTab == TAB_AVAILABLE and LOW_LEVEL_BAR_HEIGHT + 6 or 6
    )
    State.shownPlace, State.shownTurnInPlace, State.shownDungeon = nil, nil, nil
    State.selectedRowTop, State.selectedRowBottom = nil, nil
    setPageHeader(nil) -- a quest's page puts its own header and rewards back while it is drawn
    setPageRewards(nil)
    if State.shownTab and not wasSettingsDrawn then
        listScrollByTab[State.shownTab] = State.list:getScroll() -- each tab keeps its own place in its list
        detailScrollByTab[State.shownTab] = State.detail:getScroll() -- and in its page
    end
    State.list:clear()
    State.detail:clear()
    local selected, tabCount
    if State.selectedTab == TAB_QUESTS then
        selected, tabCount = drawLogTab()
    elseif State.selectedTab == TAB_DUNGEONS then
        selected, tabCount = DungeonsTab.drawDungeonsTab()
    else
        selected, tabCount = drawAvailableTab()
    end
    -- Each tab remembers how far its own list was scrolled. Within the Available tab, a list about another
    -- location, or the location picker, starts at its top.
    local listSubject = State.selectedTab == TAB_QUESTS and "quests"
        or State.selectedTab == TAB_DUNGEONS and "dungeons"
        or (State.isPickingZone and "picker" or ("zone" .. tostring(State.pickedZoneId or ns.Model.getPlayer().zoneId)))
    local previousSubject = shownSubjectByTab[State.selectedTab]
    shownSubjectByTab[State.selectedTab] = listSubject
    if previousSubject ~= nil and previousSubject ~= listSubject then
        State.list:scrollToTop()
    elseif State.selectedTab ~= State.shownTab or wasSettingsDrawn then
        State.list:setScroll(listScrollByTab[State.selectedTab] or 0)
    end
    -- The page beside the list works the same way: its own place per tab, and the top for another quest or zone
    local detailSubject = listSubject
        .. ":"
        .. (
            State.selectedTab == TAB_QUESTS and State.selectedLogZoneId and ("zone" .. State.selectedLogZoneId)
            or State.selectedTab == TAB_DUNGEONS and ("dungeon" .. tostring(State.selectedDungeonId) .. ":" .. tostring(
                selectedQuestIds[TAB_DUNGEONS]
            ))
            or ("quest" .. tostring(selectedQuestIds[State.selectedTab]))
        )
    local previousDetailSubject = shownDetailSubjectByTab[State.selectedTab]
    shownDetailSubjectByTab[State.selectedTab] = detailSubject
    if previousDetailSubject ~= nil and previousDetailSubject ~= detailSubject then
        State.detail:scrollToTop()
    elseif State.selectedTab ~= State.shownTab or wasSettingsDrawn then
        State.detail:setScroll(detailScrollByTab[State.selectedTab] or 0)
    end
    State.shownTab = State.selectedTab
    if
        State.scrollTargetQuestId
        and State.scrollTargetQuestId == selectedQuestIds[State.selectedTab]
        and State.selectedRowTop
    then
        State.list:scrollIntoView(State.selectedRowTop, State.selectedRowBottom)
    end
    State.scrollTargetQuestId = nil
    if listOpening.scrollTop then
        State.list:setScroll(math.max(listOpening.scrollTop - 2, 0)) -- the group's heading at the top of the list
        listOpening.scrollTop = nil
    end
    updateControls(selected, tabCount)
    if isSpread then
        Window.putListAway()
    elseif isNarrow then
        Window.putPageAway()
    end
end

---The window's width: the two panes, or one with a controller. The room the game keeps for it beside the map
---follows (MapDock), once the width has changed.
function Window.setWidth(width)
    if State.frame.shownWidth == width then
        return
    end
    State.frame.shownWidth = width
    State.frame:SetWidth(width)
    if ns.MapDock.reserveRoom and not (InCombatLockdown and InCombatLockdown()) then
        ns.MapDock.reserveRoom()
    end
end

---@return number width The window's width now, before the size chosen in the settings (two panes, or one)
function Log.getPanelWidth()
    return State.frame and State.frame.shownWidth or PANEL_WIDTH
end

-- The page's parts put away while the list has the one pane, those that were shown, to be shown again
local pageAway = {}

---The list in the one pane: the page's parts are put away (they are drawn, but not shown). The page's scroll bar is
---the window's child, not the page's: it goes too, and stays away while the page is (onPageScrollBarShown).
function Window.putPageAway()
    State.isPageAway = true
    local scrollBar = State.detail.frame.ScrollBar
    for _, part in ipairs({
        State.frame.parchment,
        State.frame.parchmentArt,
        State.detail.frame,
        State.pageHeader,
        State.rewardsBlock,
        State.frame.bar,
        type(scrollBar) == "table" and scrollBar or State.frame.bar,
    }) do
        if part:IsShown() then
            pageAway[part] = true
            part:Hide()
        end
    end
end

---The game's slim scroll bar shows itself again as its range changes (it hides only while there is nothing to
---scroll): while the page is put away, it is sent away again.
function Window.onPageScrollBarShown(scrollBar)
    if State.isPageAway then
        pageAway[scrollBar] = true
        scrollBar:Hide()
    end
end

---What putPageAway put away, shown again (the page has its place again).
function Window.bringPageBack()
    State.isPageAway = false
    for part in pairs(pageAway) do
        part:Show()
        pageAway[part] = nil
    end
end

---The page in the list's place: the list's controls put away, and over the page the way back to the list, the
---controller's B in the game's own icon and the tab's name.
function Window.putListAway()
    for _, control in ipairs({
        State.frame.search,
        State.frame.availableSearch,
        State.frame.searchLabel,
        State.frame.zoneButton,
        State.frame.status,
        State.frame.tabRowFill,
        State.frame.tabRowRule,
        State.lowLevelBar,
        filterDropdown.button or State.lowLevelBar,
        State.zoneDropdown or State.lowLevelBar,
    }) do
        control:Hide()
    end
    for _, tab in ipairs(State.frame.tabs) do
        tab:Hide()
    end
    local isPad = ns.Gamepad ~= nil and ns.Gamepad.isGamepadUI()
    State.frame.backStrip.text:SetText(
        (isPad and Log.getPadIconMarkup(GAMEPAD_FACE_RIGHT, 20) or BACK_ARROW_MARKUP)
            .. ns.L(TAB_LABELS[State.selectedTab])
    )
end

---@return string markup A controller button's icon (the game's own, for the pad in use) to put before a text, with a
---space after it; "" where the client has none
function Log.getPadIconMarkup(key, size)
    local iconUtility = type(InputIconTextureSetUtility) == "table"
        and InputIconTextureSetUtility.GetNormalActiveInputIconButtonTexture
    local atlas = iconUtility and key and iconUtility(key)
    if atlas and CreateAtlasMarkup then
        return CreateAtlasMarkup(atlas, size, size) .. " "
    end
    return ""
end

---In the one pane: the open quest's page in the list's place, or the list again.
function Log.setPageSpread(isSpread)
    isSpread = isSpread == true and State.isNarrow == true
    if State.isPageSpread == isSpread then
        return
    end
    State.isPageSpread = isSpread
    Log.refresh()
end

---My quests, with the quests worth dropping open in their window (the controller's way from a full log).
function Log.showDropSuggestions()
    State.isPageSpread = false
    local tab = State.frame and State.frame.tabs and State.frame.tabs[TAB_QUESTS]
    if tab and State.selectedTab ~= TAB_QUESTS then
        tab:Click()
    end
    QuestsTab.openDropWindow()
    State.wantsDropFocus = true -- (after the tab's own drawing: the drawing below puts the cursor in the window)
    Log.refresh()
end

Log.getDropRows = QuestsTab.getDropRows
Log.closeDropWindow = QuestsTab.closeDropWindow

---@return boolean isWanted The cursor is to go to the quests worth dropping (once: asking forgets it)
function Log.takeDropFocusWish()
    local isWanted = State.wantsDropFocus == true
    State.wantsDropFocus = false
    return isWanted
end

---@return boolean isNarrow The window is one pane (the quest details on a page of their own)
function Log.isNarrow()
    return State.isNarrow == true
end

---@return boolean isSpread The page has the one pane, in the list's place
function Log.isPageSpread()
    return State.isPageSpread == true
end

---A picked dungeon is shown on the map of the zone its entrance is in. That map is still the dungeon's, so
---the Available tab's location stays the dungeon while it shows.
---@param mapZoneId number The zone of the map being shown
local function isMapOfPickedDungeon(mapZoneId)
    return State.pickedZoneId ~= nil
        and ns.Database.getDungeon(State.pickedZoneId) ~= nil
        and ns.Database.getParentZoneId(ns.Database.getMapZoneId(State.pickedZoneId)) == mapZoneId
end

---Sets the Available tab's location to the zone the map is showing, when the map shows a zone at all. The
---player's own zone means "follow me"; any other is a picked location.
local function adoptMapZone()
    local uiMapId = WorldMapFrame and WorldMapFrame:IsShown() and WorldMapFrame:GetMapID()
    -- The world's or a continent's map is no location: the list stays where it was
    if uiMapId and not ns.Database.isZoneMap(uiMapId) then
        return
    end
    local areaId = uiMapId and ns.Database.getAreaId(uiMapId)
    local zoneId = areaId and ns.Database.getParentZoneId(areaId)
    if not zoneId then
        return
    end
    if isMapOfPickedDungeon(zoneId) then
        return
    end
    local newZoneId = zoneId ~= ns.Model.getPlayer().zoneId and zoneId or nil
    if newZoneId ~= State.pickedZoneId then
        State.pickedZoneId = newZoneId
        selectedQuestIds[TAB_AVAILABLE] = nil
    end
end

local function selectTab(tab)
    State.view = "quests"
    State.selectedTab = tab
    State.isPickingZone = false
    if tab == TAB_AVAILABLE then
        if
            State.selectedLogZoneId
            and ns.Database.getDungeon(State.selectedLogZoneId)
            and State.selectedLogZoneId ~= State.pickedZoneId
        then
            -- Coming from a dungeon's page: the map shows the zone its entrance is in, but the location meant
            -- is the dungeon. Should the map have moved on since, adopting its zone below overrides this.
            State.pickedZoneId = State.selectedLogZoneId ~= ns.Model.getPlayer().zoneId and State.selectedLogZoneId
                or nil
            selectedQuestIds[TAB_AVAILABLE] = nil
        end
        adoptMapZone() -- the list is about the zone on the map, not wherever it was last time
    end
    Log.refresh()
    ns.MapPins.queueRefresh()
end

local function handleTrackClick()
    local questId = selectedQuestIds[TAB_QUESTS]
    if questId then
        toggleTracked(questId)
    end
end

---Offers a quest to the party, as the game's own Share button does.
function Log.shareQuest(questId)
    if questId and QuestLogPushQuest then
        C_QuestLog.SetSelectedQuest(questId)
        QuestLogPushQuest()
    end
end

---Asks to abandon a quest, with the game's own confirmation.
function Log.abandonQuest(questId)
    if not questId then
        return
    end
    local title = C_QuestLog.GetTitleForQuestID(questId) or ns.L("this quest")
    if ns.Gamepad and ns.Gamepad.isGamepadUI() and ns.GamepadMenu then
        -- The gamepad interface: asked in OneMoreQuest's own menu (the game's question, shown from an addon's code, is
        -- taken over by the game's frame controls with the addon's taint: Gamepad.lua)
        ns.openMenu(nil, function(_, root)
            root:CreateTitle(ns.L("Abandon %s?", title))
            local red = RED_FONT_COLOR and RED_FONT_COLOR.WrapTextInColorCode
            root:CreateButton(
                red and RED_FONT_COLOR:WrapTextInColorCode(ABANDON_QUEST_ABBREV or ns.L("Abandon")) or ns.L("Abandon"),
                function()
                    C_QuestLog.SetSelectedQuest(questId)
                    C_QuestLog.SetAbandonQuest()
                    C_QuestLog.AbandonQuest()
                end
            )
            root:CreateButton(CANCEL or ns.L("Cancel"), function() end)
        end)
        return
    end
    C_QuestLog.SetSelectedQuest(questId)
    C_QuestLog.SetAbandonQuest()
    StaticPopup_Show("ABANDON_QUEST", title)
end

local function handleShareClick()
    Log.shareQuest(selectedQuestIds[TAB_QUESTS])
end

---Uses the game's own confirmation, which abandons the quest marked here.
local function handleAbandonClick()
    Log.abandonQuest(selectedQuestIds[TAB_QUESTS])
end

local function createFill(parent, layer, color)
    local fill = parent:CreateTexture(nil, layer)
    fill:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    return fill
end

---A button of the game's own kind: red, with gold text.
local function createButton(text, width, handleClick)
    local button = CreateFrame("Button", nil, State.frame.bar, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button.baseWidth, button.textKey = width, text -- its words are translated as it is drawn
    Log.setButtonText(button, ns.L(text))
    button:SetScript("OnClick", handleClick)
    return button
end

local function createTab(tab)
    -- The game's own top tabs, the open one joined to the panel below; an older client gets drawn ones
    local isCreated, button = pcall(CreateFrame, "Button", nil, State.frame, "PanelTopTabButtonTemplate")
    if isCreated and type(button) == "table" and PanelTemplates_SelectTab and PanelTemplates_TabResize then
        nativeTabs[button] = true
        State.frame.tabTexts[tab] = ns.L(TAB_LABELS[tab])
        button:SetText(State.frame.tabTexts[tab])
        PanelTemplates_TabResize(button, 0)
        if tab == 1 then
            button:SetPoint("BOTTOMLEFT", State.frame, "TOPLEFT", 8, -TITLE_HEIGHT - 1)
        else
            button:SetPoint("LEFT", State.frame.tabs[tab - 1], "RIGHT", 3, 0)
        end
    else
        button = CreateFrame("Button", nil, State.frame)
        button:SetSize(112, 24)
        button.edge = createFill(button, "BACKGROUND", COLORS.rule)
        button.edge:SetAllPoints(button)
        button.fill = createFill(button, "BORDER", BAR_BACKGROUND)
        button.fill:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
        button.fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
        button.label = ns.Widgets.createFontString(button, "OVERLAY", "GameFontNormalSmall")
        button.label:SetPoint("CENTER", button, "CENTER", 0, 0)
        State.frame.tabTexts[tab] = ns.L(TAB_LABELS[tab])
        button.label:SetText(State.frame.tabTexts[tab])
        if tab == 1 then
            button:SetPoint("LEFT", State.frame, "TOPLEFT", 10, -TITLE_HEIGHT / 2 - 1)
        else
            button:SetPoint("LEFT", State.frame.tabs[tab - 1], "RIGHT", -1, 0)
        end
    end
    button:SetScript("OnClick", function()
        selectTab(tab)
    end)
    return button
end

local function createSearch()
    local label = ns.Widgets.createFontString(State.frame, "OVERLAY", "GameFontHighlightSmall")
    -- No caption over the box: its own "Search" says what it is, and the line is better spent on quests
    label:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 12, -(TITLE_HEIGHT + 8))
    label:Hide()
    State.frame.searchLabel = label

    local search = CreateFrame("EditBox", "TrailheadLogSearch", State.frame, "SearchBoxTemplate")
    search:SetSize(LIST_WIDTH - 30, 20)
    search:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 18, -(TITLE_HEIGHT + 7))
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        if text ~= State.searchText then
            State.searchText = text
            Log.refresh()
        end
    end)
    return search
end

-- The Available tab's location picker shares its row with a search of its own: the picker on the left, narrower,
-- the search box filling the rest
local ZONE_PICKER_WIDTH = 176

---The Available tab's search: it filters the quests of the location shown, by title, giver or start item, and the
---list names other zones with matches. Kept apart from My quests' search, as the two lists are.
function Log.createAvailableSearch()
    local search = CreateFrame("EditBox", "TrailheadAvailableSearch", State.frame, "SearchBoxTemplate")
    search:SetSize(LIST_WIDTH - 12 - ZONE_PICKER_WIDTH - 6 - 14, 20)
    search:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 12 + ZONE_PICKER_WIDTH + 6 + 6, -(TITLE_HEIGHT + 7))
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        if text ~= State.availableSearchText then
            State.availableSearchText = text
            Log.refresh()
        end
    end)
    search:Hide()
    return search
end

local function createZoneButton()
    local button = CreateFrame("Button", nil, State.frame)
    button:SetSize(ZONE_PICKER_WIDTH, 24)
    button:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 12, -(TITLE_HEIGHT + 5))
    local edge = createFill(button, "BACKGROUND", COLORS.rule)
    edge:SetAllPoints(button)
    local fill = createFill(button, "BORDER", { 0.05, 0.04, 0.03 })
    fill:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
    local hover = createFill(button, "HIGHLIGHT", { 1, 1, 1, 0.08 })
    hover:SetAllPoints(fill)
    button.label = ns.Widgets.createFontString(button, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("LEFT", button, "LEFT", 10, 0)
    button.note = ns.Widgets.createFontString(button, "OVERLAY", "GameFontHighlightSmall")
    button.note:SetPoint("LEFT", button.label, "RIGHT", 8, 0)
    ns.Widgets.setColor(button.note, COLORS.tan)
    button.arrow = ns.Widgets.createFontString(button, "OVERLAY", "GameFontHighlightSmall")
    button.arrow:SetPoint("RIGHT", button, "RIGHT", -10, 0)
    button.arrow:SetText("change")
    ns.Widgets.setColor(button.arrow, COLORS.tan)
    button:SetScript("OnClick", function()
        State.isPickingZone = not State.isPickingZone
        Log.refresh()
    end)
    button:Hide()
    return button
end

---Turns the map to a place of the selected quest without the Available list following the map there: the
---list stays on its location and keeps its selection, so the quest's marks are still drawn.
local function showPlace(place)
    State.isMapFollowPaused = true
    ns.MapDock.showPlaceZone(place)
    State.isMapFollowPaused = false
end

local function createLowLevelBar()
    local bar = CreateFrame("Frame", nil, State.frame)
    bar:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", 3, 3)
    bar:SetPoint("TOPRIGHT", State.frame, "BOTTOMLEFT", LIST_WIDTH, LOW_LEVEL_BAR_HEIGHT + 3)
    local fill = createFill(bar, "BORDER", BAR_BACKGROUND)
    fill:SetAllPoints(bar)
    local rule = createFill(bar, "ARTWORK", COLORS.rule)
    rule:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, -1)
    local check = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    ns.Widgets.setMinimalCheckLook(check)
    check:SetPoint("LEFT", bar, "LEFT", 8, 0)
    check:SetScript("OnClick", toggleLowLevel)
    local label = ns.Widgets.createFontString(bar, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    ns.Widgets.setColor(label, COLORS.tan)
    State.lowLevelCheck, State.lowLevelLabel = check, label
    bar:Hide()
    return bar
end

---The location of the Available tab, as the game's own dropdown: the player's zone first, then the zones and
---the dungeons with quests for the character, each with how many. A long list scrolls inside the menu.
local function createZoneDropdown()
    if not (MenuUtil or Menu) then
        return nil
    end
    local isCreated, dropdown = pcall(CreateFrame, "DropdownButton", nil, State.frame, "WowStyle1DropdownTemplate")
    if not isCreated or type(dropdown) ~= "table" or not dropdown.SetupMenu then
        return nil
    end
    dropdown:SetWidth(ZONE_PICKER_WIDTH)
    dropdown:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 12, -(TITLE_HEIGHT + 5))
    -- Hidden until the Available tab shows it: a dropdown builds its menu whenever it comes into view (to say what is
    -- selected), and this menu lists every zone with quests, which looks at every quest of the database. Left
    -- shown, that was done as the window first appeared, on any tab.
    dropdown:Hide()
    -- The location shown is always the selected line: "you are here" when it is the player's zone, however it
    -- was chosen (by the map turning back to it, too)
    local function isSelected(zoneId)
        local playerZoneId = ns.Model.getPlayer().zoneId
        local shownZoneId = State.pickedZoneId or playerZoneId
        if zoneId == false then
            return shownZoneId == playerZoneId
        end
        return shownZoneId == zoneId
    end
    local function setSelected(zoneId)
        pickZone(zoneId or nil)
    end
    dropdown:SetupMenu(function(_, root)
        root:SetScrollMode(ZONE_MENU_HEIGHT)
        local player = ns.Model.getPlayer()
        local playerName = player.zoneId and ns.Database.getZoneName(player.zoneId)
            or player.zoneName
            or ns.L("My location")
        root:CreateRadio(ns.L("%s (you are here)", playerName), isSelected, setSelected, false)
        local zones = ns.Availability.getZones({ shouldShowLowLevel = ns.settings.shouldShowLowLevel })
        -- With quests to pick up kept back to givers met (Spoilers), a zone's count would tell what is not met yet
        local isCounted = List.getPickupChoice() == "all"
        -- A location the map turned to, with nothing to pick up there (only quests handed in, say), is not among
        -- the zones with quests: it gets a line of its own, so the dropdown still names it
        local isPickedListed = State.pickedZoneId == nil or State.pickedZoneId == player.zoneId
        for _, zone in ipairs(zones) do
            isPickedListed = isPickedListed or zone.zoneId == State.pickedZoneId
        end
        if not isPickedListed then
            root:CreateRadio(
                ns.L("%s (on the map)", ns.Database.getZoneName(State.pickedZoneId)),
                isSelected,
                setSelected,
                State.pickedZoneId
            )
        end
        -- Zones only: the dungeons have a tab of their own
        for _, section in ipairs({ { title = "Zones with quests for you", isDungeon = false } }) do
            local hasTitle = false
            for _, zone in ipairs(zones) do
                if zone.isDungeon == section.isDungeon and zone.zoneId ~= player.zoneId then
                    if not hasTitle then
                        root:CreateTitle(ns.L(section.title))
                        hasTitle = true
                    end
                    root:CreateRadio(
                        isCounted and string.format("%s (%d)", zone.zoneName, zone.count) or zone.zoneName,
                        isSelected,
                        setSelected,
                        zone.zoneId
                    )
                end
            end
        end
    end)
    return dropdown
end

---Which quests the list keeps, as the game's own dropdown beside the search, as its windows filter a list.
function filterDropdown.create(search)
    local FILTER_DROPDOWN_WIDTH = 104
    if not (MenuUtil or Menu) then
        return nil
    end
    local isCreated, dropdown = pcall(CreateFrame, "DropdownButton", nil, State.frame, "WowStyle1DropdownTemplate")
    if not isCreated or type(dropdown) ~= "table" or not dropdown.SetupMenu then
        return nil
    end
    search:SetWidth(LIST_WIDTH - 30 - FILTER_DROPDOWN_WIDTH - 6)
    dropdown:SetWidth(FILTER_DROPDOWN_WIDTH)
    dropdown:SetPoint("LEFT", search, "RIGHT", 6, 0)
    local function isSelected(filter)
        return filter == State.logFilter
    end
    dropdown:SetupMenu(function(_, root)
        for _, filter in ipairs(FILTERS) do
            -- Its name and how many quests it keeps, "Ready (4)"
            local count = filterDropdown.counts[filter]
            root:CreateRadio(
                ns.L(FILTER_LABELS[filter]) .. (count and string.format(" (%d)", count) or ""),
                isSelected,
                selectFilter,
                filter
            )
        end
    end)
    return dropdown
end

---Closes the window, and the map it stands beside, as its close button does (the gamepad's B too).
function Log.closeWindow()
    if State.isAlone then
        State.frame:Hide() -- (alone, in a fight: only the window; OnHide joins it to the map again)
        return
    end
    if ns.MapDock.isMapHandsOff() then
        return -- (the gamepad's: the map closes by its own B; an addon's closing of it taints, MapDock.isMapHandsOff)
    end
    local map = WorldMapFrame
    if HideUIPanel then
        HideUIPanel(map)
    else
        map:Hide()
    end
    if map:IsShown() then
        pcall(map.Hide, map) -- the game's window keeping would not close it for an addon: the map's own way
    end
    if map:IsShown() then
        -- Still there (the game lets an addon close no window of its own in a fight): the panels alone
        -- are put away, till the map is next closed; the close button always closes what it stands on
        ns.Timing.noteProblem(
            "refused",
            "the close button could not close the map: the panels were folded away instead"
        )
        ns.MapDock.foldUntilClosed()
    elseif State.frame:IsShown() then
        ns.MapDock.apply() -- (the map was gone already: the panels go after it)
    end
end

---Builds the panels as a child of the world map, joined to its right edge and as tall as it is.
function Log.create()
    if State.frame or not WorldMapFrame then
        return
    end
    State.frame = CreateFrame("Frame", "TrailheadLog", WorldMapFrame, "BackdropTemplate")
    State.frame:SetWidth(PANEL_WIDTH)
    State.frame.shownWidth = PANEL_WIDTH
    State.frame:EnableMouse(true) -- clicks must not fall through to the world behind
    -- Nor the wheel: over the window's header, bar and edges it would otherwise zoom the camera
    State.frame:EnableMouseWheel(true)
    State.frame:SetScript("OnMouseWheel", function() end)
    State.frame:SetScript("OnShow", function()
        Log.handleShown()
    end)
    State.frame:SetScript("OnHide", function()
        if State.isAlone then
            Log.endAlone()
        end
    end)
    -- Made taller or shorter with the map it stands beside: drawn again a moment later (once for a whole drag), so
    -- the page's scrolling, its scroll bar and whether it needs one follow the new height
    local SIZE_REDRAW_SECONDS = 0.1
    -- (not when the drawing since was already for the height it has now: docking beside the map sizes the window and
    -- draws it at that size, and drawing it again cost the map's opening a second full page)
    local isSizeRedrawQueued = false
    local function isDrawnForHeight(height)
        return type(height) == "number" and State.drawnHeight ~= nil and math.abs(height - State.drawnHeight) < 0.5
    end
    State.frame:SetScript("OnSizeChanged", function(_, _, height)
        if type(height) ~= "number" or isDrawnForHeight(height) or isSizeRedrawQueued then
            return
        end
        if not (C_Timer and C_Timer.After) then
            return
        end
        isSizeRedrawQueued = true
        C_Timer.After(SIZE_REDRAW_SECONDS, function()
            isSizeRedrawQueued = false
            if not isDrawnForHeight(State.frame:GetHeight()) then
                Log.refresh()
            end
        end)
    end)
    -- Moved by its title strip or edges, where nothing of its own takes the press: on its own (in a fight) the
    -- window alone; beside the map, out of a fight, the map, which the window goes along with (MapDock)
    State.frame:SetMovable(true)
    State.frame:RegisterForDrag("LeftButton")
    State.frame:SetScript("OnDragStart", function(frame)
        if State.isAlone then
            frame:StartMoving()
        elseif State.isDocked then
            ns.MapDock.startMapDrag()
        end
    end)
    State.frame:SetScript("OnDragStop", function(frame)
        frame:StopMovingOrSizing()
        ns.MapDock.stopMapDrag()
        if State.isAlone then
            Log.rememberAloneSpot()
        end
    end)
    State.frame:Hide()
    -- The frame round the panels, in the look picked in the settings, with the settings and close buttons
    ns.WindowBorder.create(State.frame, {
        listWidth = LIST_WIDTH,
        tabRowHeight = TITLE_HEIGHT,
        stripColor = BAR_BACKGROUND,
        handleSettingsClick = SettingsView.toggleSettings,
        handleCloseClick = function()
            Log.closeWindow()
        end,
        -- What dragging the title strip does now, for its tooltip
        getMoveHint = function()
            if State.isAlone then
                return ns.L("Drag to move this window")
            elseif InCombatLockdown and InCombatLockdown() then
                return ns.L("Out of combat, drag to move the map and this window")
            elseif WorldMapFrame and WorldMapFrame:IsShown() and not WorldMapFrame:IsMaximized() then
                return ns.L("Drag to move the map and this window")
            end
        end,
        getSettingsTooltip = function()
            return State.view == "settings" and ns.L("Close the settings") or ns.L("%s settings", ns.ADDON_TITLE)
        end,
        handleChronicleClick = function()
            Log.toggleChronicle()
        end,
        getChronicleTooltip = function()
            return ns.L(State.view == "chronicle" and "Close the chronicle" or "Chronicle: the quests you have done")
        end,
    })
    Log.setMapEdge(WorldMapFrame, -2, 0, 0)

    local background = createFill(State.frame, "BACKGROUND", BACKGROUND)
    background:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 3, -3)
    background:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMRIGHT", -3, 3)

    -- Top strip: tabs and a status line
    local titleBar = createFill(State.frame, "BORDER", BAR_BACKGROUND)
    State.frame.tabRowFill = titleBar
    titleBar:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 3, -3)
    titleBar:SetPoint("BOTTOMRIGHT", State.frame, "TOPLEFT", LIST_WIDTH + 1, -TITLE_HEIGHT)
    local titleRule = createFill(State.frame, "ARTWORK", COLORS.rule)
    State.frame.tabRowRule = titleRule
    titleRule:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 3, -TITLE_HEIGHT)
    titleRule:SetPoint("BOTTOMRIGHT", State.frame, "TOPLEFT", LIST_WIDTH + 1, -TITLE_HEIGHT - 1)
    State.frame.tabs = {}
    State.frame.tabCounts, State.frame.tabTexts = {}, {} -- [tab] = the count it last showed, and its text now
    State.frame.tabs[1] = createTab(1)
    State.frame.tabs[2] = createTab(2)
    State.frame.tabs[3] = createTab(3)
    State.frame.status = ns.Widgets.createFontString(State.frame, "OVERLAY", "GameFontHighlightSmall")
    -- On the tabs' own line, and never into the page beside it
    State.frame.status:SetPoint("LEFT", State.frame.tabs[3], "RIGHT", 10, 0)
    State.frame.status:SetWidth(70)
    State.frame.status:SetJustifyH("LEFT")
    State.frame.status:SetWordWrap(false)

    -- Left: search or the location picker, then the list, down to the bottom edge
    State.frame.search = createSearch()
    State.frame.zoneButton = createZoneButton()
    State.frame.availableSearch = Log.createAvailableSearch()
    State.zoneDropdown = createZoneDropdown()
    filterDropdown.button = filterDropdown.create(State.frame.search)
    State.lowLevelBar = createLowLevelBar()
    local listTop = TITLE_HEIGHT + SEARCH_HEIGHT
    -- Behind the list, under the tabs: the dark book the game's own quest log lies on, when this client has it
    local listArt = State.frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    listArt:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 3, -TITLE_HEIGHT - 1)
    listArt:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", LIST_WIDTH + 1, 3)
    State.frame.hasListArt = setAtlasIfKnown(listArt, "QuestLog-main-background") and true or false
    listArt:SetShown(State.frame.hasListArt)
    State.frame.listArt = listArt
    State.list = ns.Widgets.createCanvas("TrailheadLogList", State.frame, LIST_WIDTH - 6, 400)
    -- The list's scroll bar goes where the list goes: with a controller the list is hidden under a quest's page in
    -- the one pane, and its bar (made beside it, a child of the window) stood on as a second bar on the page
    local listBar = State.list.frame.ScrollBar
    if type(listBar) == "table" and listBar.SetParent then
        local level = listBar:GetFrameLevel()
        listBar:SetParent(State.list.frame)
        listBar:SetFrameLevel(level)
    end
    State.list.frame:ClearAllPoints()
    State.list.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 6, -listTop)
    State.list.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", 6, 6)
    local divider = createFill(State.frame, "ARTWORK", COLORS.rule)
    divider:SetPoint("TOPLEFT", State.frame, "TOPLEFT", LIST_WIDTH + 1, 0)
    divider:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", LIST_WIDTH + 2, 3)
    State.frame.divider = divider

    -- Right: the quest on parchment, with the actions under it
    local pageLeft = LIST_WIDTH + 2
    local parchment = createFill(State.frame, "BORDER", COLORS.parchment)
    parchment:SetPoint("TOPLEFT", State.frame, "TOPLEFT", pageLeft, -PAGE_TOP)
    -- The parchment ends where the scroll bar's strip begins, so the bar stands beside the page, not on it
    parchment:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", pageLeft + PAGE_CONTENT_WIDTH, BAR_HEIGHT)
    -- Over the plain colour, the textured parchment of the game's own quest page, when this client has it
    local parchmentArt = State.frame:CreateTexture(nil, "BORDER", nil, 1)
    parchmentArt:SetAllPoints(parchment)
    State.frame.parchment, State.frame.parchmentArt = parchment, parchmentArt
    if not setAtlasIfKnown(parchmentArt, "QuestDetailsBackgrounds") then
        parchmentArt:Hide()
    end
    -- The settings' ground instead of the parchment: the game's dark marble of a panel of controls (parchment is
    -- for pages that are read)
    local ironPage = State.frame:CreateTexture(nil, "BORDER", nil, 2)
    ironPage:SetAllPoints(parchment)
    ironPage:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
    if ironPage.SetHorizTile then
        ironPage:SetHorizTile(true)
        ironPage:SetVertTile(true)
    end
    ironPage:Hide()
    State.frame.ironPage = ironPage
    State.detail = ns.Widgets.createCanvas("TrailheadLogDetail", State.frame, PAGE_WIDTH - 2, 400, 2)
    State.detail.frame:ClearAllPoints()
    State.detail.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", pageLeft, -PAGE_TOP - 2)
    State.detail.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", pageLeft, BAR_HEIGHT + 2)

    State.pageHeader = createPageHeader(State.frame, pageLeft)
    State.rewardsBlock = createRewardsBlock(State.frame, pageLeft)
    State.detail.handleScroll = followPageScroll
    -- The scroll bar runs the full height of the page beside it, from under the tabs down to the buttons,
    -- whatever the header and the rewards take from the scrolling part
    local scrollBar = State.detail.frame.ScrollBar
    if type(scrollBar) == "table" and scrollBar.ClearAllPoints then
        -- The game's slim bar has its arrows inside its ends and is centred in the strip; the older bar's
        -- arrows stand beyond its ends, so it is set in from them
        local isMinimal = State.detail.frame.isMinimalBar == true
        local inset = isMinimal and 6 or SCROLL_ARROW_HEIGHT
        local barLeft = pageLeft + PAGE_CONTENT_WIDTH + (isMinimal and (ns.Widgets.SCROLL_BAR_WIDTH - 8) / 2 or 5)
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPLEFT", State.frame, "TOPLEFT", barLeft, -PAGE_TOP - inset)
        State.frame.placeScrollBar = function(topInset, shift, bottom)
            scrollBar:SetPoint("TOPLEFT", State.frame, "TOPLEFT", barLeft + shift, -PAGE_TOP - topInset - inset)
            scrollBar:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", barLeft + shift, bottom + inset)
        end
        scrollBar:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", barLeft, BAR_HEIGHT + inset)
        if scrollBar.HookScript then
            scrollBar:HookScript("OnShow", Window.onPageScrollBarShown) -- (kept away with the page: putPageAway)
        end
    end

    State.frame.bar = CreateFrame("Frame", nil, State.frame)
    State.frame.bar:SetPoint("TOPLEFT", State.frame, "BOTTOMLEFT", pageLeft, BAR_HEIGHT)
    State.frame.bar:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMRIGHT", -3, 3)
    State.frame.pageLeft = pageLeft
    State.frame.pageTopInset, State.frame.pageShift, State.frame.pageBottom = 0, 0, BAR_HEIGHT
    -- A page with nothing to scroll has no scroll bar, and takes its strip too: the parchment, the header and the
    -- rewards reach the window's edge. pageExtra is how much wider than with the bar it is now.
    State.frame.pageExtra = 0
    local pageRight = pageLeft + PAGE_CONTENT_WIDTH
    -- Over the page in the list's place (a quest clicked, or the controller's A on one): the way back to the list, the
    -- tab's name after the game's back arrow (with a controller its B), in the tab row's colours. A click goes back.
    local backStrip = CreateFrame("Button", nil, State.frame)
    backStrip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    backStrip:SetScript("OnClick", function()
        Log.setPageSpread(false)
    end)
    createFill(backStrip, "HIGHLIGHT", { 1, 1, 1, 0.08 }):SetAllPoints(backStrip)
    backStrip:SetPoint("TOPLEFT", State.frame, "TOPLEFT", pageLeft, -PAGE_TOP)
    backStrip:SetPoint("RIGHT", State.frame, "RIGHT", -3, 0)
    backStrip:SetHeight(BACK_STRIP_HEIGHT)
    createFill(backStrip, "BORDER", BAR_BACKGROUND):SetAllPoints(backStrip)
    local backRule = createFill(backStrip, "ARTWORK", COLORS.rule)
    backRule:SetPoint("BOTTOMLEFT", backStrip, "BOTTOMLEFT", 0, 0)
    backRule:SetPoint("TOPRIGHT", backStrip, "BOTTOMRIGHT", 0, 1)
    backStrip.text = ns.Widgets.createFontString(backStrip, "OVERLAY", "GameFontNormal")
    backStrip.text:SetPoint("LEFT", backStrip, "LEFT", 8, 0)
    backStrip:Hide()
    State.frame.backStrip = backStrip

    ---The page's right edge and foot, where the split, the shift, the scroll bar's strip and the bar put them.
    local function placePageRight()
        local right, bottom = pageRight + State.frame.pageShift + State.frame.pageExtra, State.frame.pageBottom
        parchment:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", right, bottom)
        State.pageHeader:SetPoint("TOPRIGHT", State.frame, "TOPLEFT", right, -PAGE_TOP - State.frame.pageTopInset)
        State.rewardsBlock:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", right, bottom)
        State.detail:setWidth(
            PAGE_WIDTH - 2 + pageLeft - State.frame.pageLeft + State.frame.pageShift + State.frame.pageExtra
        )
    end

    ---Moves the line between the list and the page: a narrower list gives the page its room. The page's right edge,
    ---its scroll bar and the window stay where they are, unless shifted: the controller's one pane has the page
    ---where the list was (no list, shifted left by the list's width).
    ---@param topInset number? Room kept over the page (the controller's way back to the list), 0 when left out
    ---@param shift number? How far the page's right edge moves (left: negative), 0 when left out
    ---@param bottom number? Where the page ends above the window's foot: over the bar of buttons (BAR_HEIGHT, when
    ---left out), or at the foot with a controller, which has no bar
    function State.frame.placeSplit(listWidth, topInset, shift, bottom)
        topInset, shift, bottom = topInset or 0, shift or 0, bottom or BAR_HEIGHT
        local newPageLeft = listWidth + 2
        if
            State.frame.pageLeft == newPageLeft
            and State.frame.pageTopInset == topInset
            and State.frame.pageShift == shift
            and State.frame.pageBottom == bottom
        then
            return
        end
        State.frame.pageLeft, State.frame.pageTopInset, State.frame.pageShift, State.frame.pageBottom =
            newPageLeft, topInset, shift, bottom
        if listWidth > 0 then
            State.list:setWidth(listWidth - 6) -- (the page in the list's place hides the list: it keeps its width)
        end
        if State.frame.placeScrollBar then
            State.frame.placeScrollBar(topInset, shift, bottom)
        end
        placePageRight()
        divider:SetPoint("TOPLEFT", State.frame, "TOPLEFT", listWidth + 1, 0)
        divider:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", listWidth + 2, 3)
        listArt:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", listWidth + 1, 3)
        parchment:SetPoint("TOPLEFT", State.frame, "TOPLEFT", newPageLeft, -PAGE_TOP - topInset)
        State.detail.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", newPageLeft, -PAGE_TOP - topInset - 2)
        State.detail.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", newPageLeft, bottom + 2)
        State.pageHeader:SetPoint("TOPLEFT", State.frame, "TOPLEFT", newPageLeft, -PAGE_TOP - topInset)
        backStrip:SetPoint("TOPLEFT", State.frame, "TOPLEFT", newPageLeft, -PAGE_TOP)
        State.rewardsBlock:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", newPageLeft, bottom)
        State.frame.bar:SetPoint("TOPLEFT", State.frame, "BOTTOMLEFT", newPageLeft, BAR_HEIGHT)
    end

    ---Makes the page as wide as the window allows (isWide), or leaves the scroll bar its strip.
    function State.frame.setPageWide(isWide)
        local extra = isWide and ns.Widgets.SCROLL_BAR_WIDTH or 0
        if State.frame.pageExtra == extra then
            return
        end
        State.frame.pageExtra = extra
        placePageRight()
    end

    ---Draws the page (draw puts it on State.detail and gives its height) as wide as it can be: at the width it had
    ---last, then once more at the other only when that was wrong (wide, it needs scrolling; narrow, it does not).
    ---A wider page is never taller, so the second drawing is the right one.
    function State.frame.finishPage(draw)
        local wasWide = State.frame.pageExtra > 0
        State.detail:finish(draw())
        local isScrolling = (State.detail.maxScroll or 0) > 0
        if isScrolling == wasWide then
            State.frame.setPageWide(not isScrolling)
            setPageHeader(nil)
            setPageRewards(nil)
            State.detail:clear()
            State.detail:finish(draw())
        end
    end

    local barFill = createFill(State.frame.bar, "BORDER", BAR_BACKGROUND)
    barFill:SetAllPoints(State.frame.bar)
    local barRule = createFill(State.frame.bar, "ARTWORK", COLORS.rule)
    barRule:SetPoint("TOPLEFT", State.frame.bar, "TOPLEFT", 0, 0)
    barRule:SetPoint("BOTTOMRIGHT", State.frame.bar, "TOPRIGHT", 0, -1)

    State.frame.trackButton = createButton("Track", 74, handleTrackClick)
    State.frame.trackButton:SetPoint("LEFT", State.frame.bar, "LEFT", 10, 0)
    State.frame.focusButton = createButton("Focus", 72, function()
        if selectedQuestIds[TAB_QUESTS] then
            focusQuest(selectedQuestIds[TAB_QUESTS])
        end
    end)
    State.frame.focusButton:SetPoint("LEFT", State.frame.trackButton, "RIGHT", 4, 0)
    State.frame.shareButton = createButton("Share", 58, handleShareClick)
    State.frame.shareButton:SetPoint("LEFT", State.frame.focusButton, "RIGHT", 4, 0)
    State.frame.abandonButton = createButton("Abandon", 72, handleAbandonClick)
    State.frame.abandonButton:SetPoint("RIGHT", State.frame.bar, "RIGHT", -10, 0)
    State.frame.mapButton = createButton("Show giver", 100, function()
        if State.shownPlace then
            showPlace(State.shownPlace)
        end
    end)
    State.frame.mapButton:SetPoint("LEFT", State.frame.bar, "LEFT", 10, 0)
    State.frame.turnInMapButton = createButton("Show turn-in", 106, function()
        if State.shownTurnInPlace then
            -- Only now is the turn-in marked on the map, for this quest (selecting a quest shows where it starts)
            Log.turnInShownQuestId = Log.getSelectedAvailableQuestId()
            showPlace(State.shownTurnInPlace)
            ns.MapPins.queueRefresh()
        end
    end)
    State.frame.trackAllButton = createButton("Track all here", 110, function()
        local questIds = {}
        for _, entry in ipairs(State.frame.shownZoneGroup and State.frame.shownZoneGroup.entries or {}) do
            questIds[#questIds + 1] = entry.questId
        end
        ns.QuestState.watchAll(questIds)
        Log.refresh()
        ns.Tracker.queueRefresh()
    end)
    State.frame.trackAllButton:SetPoint("LEFT", State.frame.bar, "LEFT", 10, 0)
    State.frame.zoneMapButton = createButton("Show zone", 90, function()
        if State.frame.shownZoneGroup then
            ns.MapDock.showZoneMap(State.frame.shownZoneGroup.zoneId)
        end
    end)
    State.frame.zoneMapButton:SetPoint("LEFT", State.frame.trackAllButton, "RIGHT", 6, 0)
    -- The Dungeons tab: a dungeon's way in on the map, and its page in the DungeonJournal addon when that is there
    State.frame.entranceButton = createButton("Show entrance", 110, function()
        local dungeon = State.shownDungeon
        if dungeon and dungeon.entrance then
            State.isMapFollowPaused = true
            ns.MapDock.showQuestPlace(dungeon.entrance.mapZoneId or dungeon.entrance.groupZoneId, dungeon.entrance)
            State.isMapFollowPaused = false
        end
    end)
    State.frame.entranceButton:SetPoint("LEFT", State.frame.bar, "LEFT", 10, 0)
    State.frame.journalButton = createButton("Dungeon Journal", 120, function()
        if State.shownDungeon and ns.DungeonJournal then
            ns.DungeonJournal.open(State.shownDungeon.name)
        end
    end)
    State.frame.journalButton:SetPoint("RIGHT", State.frame.bar, "RIGHT", -10, 0)
    State.frame.resetSettingsButton = createButton("Reset to defaults", 130, function()
        ns.resetSettings()
        ns.Tracker.resetPosition()
        SettingsView.applySetting()
    end)
    State.frame.resetSettingsButton:SetPoint("LEFT", State.frame.bar, "LEFT", 10, 0)
    State.frame.doneButton = createButton("Done", 80, function()
        if State.view == "chronicle" then
            Log.toggleChronicle()
        else
            SettingsView.toggleSettings()
        end
    end)
    State.frame.doneButton:SetPoint("RIGHT", State.frame.bar, "RIGHT", -10, 0)
    -- The journal: from a quest's story back to the list of quests
    State.frame.journalBackButton = createButton("Back", 80, function()
        ns.ChroniclePage.closeEntry()
    end)
    State.frame.journalBackButton:SetPoint("LEFT", State.frame.bar, "LEFT", 10, 0)
    State.frame.journalBackButton:Hide()
    -- The buttons whose words stay the same whatever is shown; the others are named as the page is drawn
    State.frame.textButtons = {
        State.frame.shareButton,
        State.frame.abandonButton,
        State.frame.turnInMapButton,
        State.frame.trackAllButton,
        State.frame.zoneMapButton,
        State.frame.resetSettingsButton,
        State.frame.doneButton,
        State.frame.entranceButton,
        State.frame.journalButton,
        State.frame.journalBackButton,
    }

    State.toggleButton = CreateFrame("Frame", nil, UIParent) -- owns the quest log key's binding
    Log.hookMapClicks()
end

---A click on the map where there is nothing to click lets go of the selected quest. Only a click: a press
---and release with the mouse moved between is the map being dragged, and leaves the selection as it was.
function Log.hookMapClicks()
    local DRAG_DISTANCE = 4 -- in the map's own units, past which the press was a drag
    local container = WorldMapFrame and WorldMapFrame.ScrollContainer
    if type(container) ~= "table" or not container.HookScript or not GetCursorPosition then
        return
    end
    local pressX, pressY
    container:HookScript("OnMouseDown", function(_, mouseButton)
        pressX, pressY = nil, nil
        if mouseButton == "LeftButton" then
            local scale = container:GetEffectiveScale()
            local x, y = GetCursorPosition()
            pressX, pressY = x / scale, y / scale
        end
    end)
    container:HookScript("OnMouseUp", function(_, mouseButton)
        if mouseButton ~= "LeftButton" or not pressX then
            return
        end
        local scale = container:GetEffectiveScale()
        local x, y = GetCursorPosition()
        local distance = math.sqrt((x / scale - pressX) ^ 2 + (y / scale - pressY) ^ 2)
        pressX, pressY = nil, nil
        if distance <= DRAG_DISTANCE then
            Log.deselectQuest()
        end
    end)
end

---Lets go of the quest selected on the open tab, so nothing is highlighted on the map or opened on the page.
function Log.deselectQuest()
    if not Log.isOpen() or State.view ~= "quests" or not selectedQuestIds[State.selectedTab] then
        return
    end
    selectedQuestIds[State.selectedTab] = nil
    State.mapQuestId = nil
    Log.refresh()
    ns.MapPins.queueRefresh()
end

-- When the window is drawn. What it shows stays on it while it is hidden, so it is drawn only when that is out of
-- date (State.isStale): something asked for a drawing while it could not be seen (Log.refresh notes it), it was
-- never drawn, or opening it changes what it shows. Coming into view by itself draws nothing: drawing the window is
-- thousands of calls into the game, and it used to happen twice at every opening of the map.

---Draws the window if what it shows is out of date.
function Log.refreshIfStale()
    if State.isStale ~= false then
        ns.Timing.measure("quest window drawn", Log.refresh)
    else
        ns.Timing.noteCause("quest window", "kept as it was")
    end
end

---The window came into view other than by being docked (the map shown again with it still beside it).
function Log.handleShown()
    if State.isDocked and not State.isDocking then
        Log.refreshIfStale()
    end
end

-- On its own: in a fight the game opens no map for an addon, so a quest clicked in the tracker opens the window
-- by itself, where it stood beside the map, on that quest. Escape or its close button closes it; the map opened
-- (its key in the fight, or by itself once the fight is over while the window is still open) takes it back.
State.isAlone = false
local aloneQuestId
local dockedSpot -- where the window stood beside the map, in the screen's units, its size in its own

local function rememberDockedSpot()
    local frame = State.frame
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top and UIParent then
        local toScreen = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        dockedSpot =
            { left = left * toScreen, top = top * toScreen, width = frame:GetWidth(), height = frame:GetHeight() }
    end
end

---Where the player moved the lone window, kept with the settings (aloneLogSpot, the screen's units): it opens
---there again, in the next fight and after a reload, instead of beside where the map stood.
function Log.rememberAloneSpot()
    local frame = State.frame
    frame:SetUserPlaced(false) -- (the game keeps no place of its own for it: the window is the map's again after)
    local left, top = frame:GetLeft(), frame:GetTop()
    if left and top and UIParent then
        local toScreen = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        ns.settings.aloneLogSpot = { left = left * toScreen, top = top * toScreen }
    end
end

local function setSpecialFrame(isSpecial)
    if type(UISpecialFrames) ~= "table" then
        return
    end
    for index = #UISpecialFrames, 1, -1 do
        if UISpecialFrames[index] == "TrailheadLog" then
            table.remove(UISpecialFrames, index)
        end
    end
    if isSpecial then
        table.insert(UISpecialFrames, "TrailheadLog") -- Escape closes it, as the game's own windows
    end
end

---@return boolean isAlone The window stands by itself, without the map
function Log.isAlone()
    return State.isAlone == true
end

---Opens the window by itself on a quest (in a fight, with the map closed; with a controller, whenever the map is).
---@return boolean isOpened
function Log.openAlone(questId)
    local frame = State.frame
    if not frame or not UIParent then
        return false
    end
    aloneQuestId = questId
    if not State.isAlone then
        State.isAlone = true
        local scale = Log.getWindowScale()
        local spot = dockedSpot
            or {
                -- Never beside the map yet: right of the screen's middle, as it stands beside a centred map
                left = UIParent:GetWidth() / 2,
                top = UIParent:GetHeight() * 0.85,
                width = Log.PANEL_WIDTH,
                height = UIParent:GetHeight() * 0.7 / scale,
            }
        frame:SetParent(UIParent)
        frame:SetFrameStrata("HIGH")
        frame:SetScale(scale)
        frame:ClearAllPoints()
        local moved = ns.settings.aloneLogSpot
        local left, top = moved and moved.left or spot.left, moved and moved.top or spot.top
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale) -- (the screen's units, in its own)
        -- (the width the window has now: two panes, or one with a controller, Window.setWidth)
        frame:SetSize(Log.getPanelWidth(), spot.height)
        frame:SetClampedToScreen(true)
        setSpecialFrame(true)
        ns.WindowBorder.setLeftEdgeShown(true) -- (by itself: its whole frame)
        Log.setDocked(true) -- (drawn as when docked: the list, the page)
    end
    if questId then
        Log.selectQuest(questId)
    end
    return true
end

---The window's place among the frames: docked, the map's child (with the gamepad interface the screen's, laid over
---the map: MapDock.placeOnMap says why); alone, the screen's anyway.
function Log.placeOnMap()
    local frame = State.frame
    if not frame or State.isAlone or State.isWarming or not WorldMapFrame then
        return
    end
    if ns.MapDock.isMapHandsOff() then
        ns.MapDock.placeOnMap(frame, 600)
    elseif frame:GetParent() ~= WorldMapFrame then
        frame:SetParent(WorldMapFrame)
        frame:SetFrameStrata(WorldMapFrame:GetFrameStrata())
        frame:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 0) + 1) -- (as made: just over the map, not where the pad's had it)
    end
end

---The lone window goes back to the map (closed, or the map opened): what it is a part of again.
function Log.endAlone()
    if not State.isAlone then
        return
    end
    State.isAlone = false
    setSpecialFrame(false)
    local frame = State.frame
    frame:StopMovingOrSizing() -- (taken back by the map mid-drag)
    frame:SetClampedToScreen(false)
    Log.placeOnMap()
    if not WorldMapFrame:IsShown() then
        State.isDocked = false
        frame:Hide()
    end
end

-- Warming up: a few seconds after login, out of a fight and with the map closed, the window is opened once where it
-- cannot be seen (off the screen, see-through) and closed again. Its frames are made and its pictures read from the
-- disk then, at a quiet moment, instead of at the first opening of the map, which waited on both. Done once.
local WARM_UP_SECONDS, WARM_UP_RETRY_SECONDS, WARM_UP_TRIES = 6, 10, 6
local isWarmedUp = false

---Opens the window unseen and closes it again.
---@return boolean isDone It was done (or needs doing no more); false: not now (a fight, the map open), to try later
function Log.warmUp()
    local frame = State.frame
    if isWarmedUp or not frame or not UIParent then
        return true
    end
    if
        State.isDocked
        or State.isAlone
        or (WorldMapFrame and WorldMapFrame:IsShown())
        or (InCombatLockdown and InCombatLockdown())
    then
        return false
    end
    isWarmedUp = true
    local scale = Log.getWindowScale()
    State.isWarming = true
    frame:SetParent(UIParent)
    frame:SetAlpha(0)
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "TOPLEFT", -100, 0) -- off the screen
    frame:SetSize(Log.PANEL_WIDTH, UIParent:GetHeight() * 0.7 / scale)
    ns.Timing.measure("quest window warmed up", function()
        Log.setDocked(true) -- drawn: every frame of the list and the page made, their pictures asked for
        Log.setDocked(false)
    end)
    frame:SetAlpha(1)
    State.dockedSize = nil -- the first real opening fits it to the map, with everything already made
    State.isWarming = nil
    frame:SetParent(WorldMapFrame) -- (back where it waits for the map)
    frame:SetFrameStrata(WorldMapFrame:GetFrameStrata())
    Log.placeOnMap()
    return true
end

local function scheduleWarmUp(triesLeft, seconds)
    if not C_Timer then
        return
    end
    C_Timer.After(seconds, function()
        if not Log.warmUp() and triesLeft > 1 then
            scheduleWarmUp(triesLeft - 1, WARM_UP_RETRY_SECONDS)
        end
    end)
end
Log.scheduleWarmUp = scheduleWarmUp

---A fight is over: a lone window still open is joined to the map, opened on the same quest.
function Log.openMapAfterCombat()
    if not State.isAlone then
        return
    end
    if not State.frame:IsShown() then
        Log.endAlone()
        return
    end
    local questId = aloneQuestId
    ns.MapDock.open() -- (the map's showing docks the window: setDocked)
    if questId and Log.isOpen() then
        Log.selectQuest(questId)
    end
end

---Shows the panels beside the map or takes them away; MapDock decides which.
function Log.setDocked(shouldDock)
    -- Alone, the closed map does not take the window away; the map shown takes it back
    if State.isAlone then
        if not shouldDock then
            return
        end
        if WorldMapFrame and WorldMapFrame:IsShown() then
            Log.endAlone()
        end
    end
    local wasDocked = State.isDocked
    State.isDocked = shouldDock == true
    if not State.frame then
        return
    end
    if State.isDocked and not wasDocked then
        -- Opening: the list starts on the tracker's active quest, highlighted, so list and map agree. When that is
        -- how it was left (the same quest followed, the list as it was), and the player is near where they were, the
        -- opening changes nothing it shows.
        local focusedQuestId = ns.Focus.get()
        if
            State.view ~= "quests"
            or selectedQuestIds[TAB_QUESTS] ~= focusedQuestId
            or State.selectedLogZoneId ~= nil
            or not Log.isNearDrawnPosition()
        then
            State.isStale = true
        end
        State.view = "quests"
        selectedQuestIds[TAB_QUESTS] = focusedQuestId
        State.selectedLogZoneId = nil
        listOpening.isOpening = true -- the list scrolls to the focused quest's group, or the first open one with a tracked quest
    end
    if State.isDocked then
        State.isDocking = true -- its OnShow waits: the one look below decides, once its size is known
        State.frame:Show()
        State.isDocking = false
        -- Another size (the map laid out anew, the size chosen in the settings): its lists are fitted again
        local size = string.format("%.1f:%.1f", State.frame:GetWidth() or 0, State.frame:GetHeight() or 0)
        if size ~= State.dockedSize then
            State.isStale = true
        end
        State.dockedSize = size
        Log.refreshIfStale()
        listOpening.isOpening = nil
        if not State.isAlone and not State.isWarming then
            rememberDockedSpot() -- (where the window stands, for a fight with the map closed)
        end
    else
        State.frame:Hide()
    end
end

local STALE_AFTER_YARDS = 50 -- distances on the quest pages: drawn again once the player walked this far

---@return boolean isNear The player is within STALE_AFTER_YARDS of where they were when the window was last drawn
function Log.isNearDrawnPosition()
    local drawn, position = State.drawnPosition, ns.Geometry.getPlayerPosition()
    if not drawn or not position then
        return drawn == position
    end
    return drawn.uiMapId == position.uiMapId
        and ns.Geometry.getDistance(drawn.north, drawn.west, position.north, position.west) < STALE_AFTER_YARDS
end

---Joins the panels to the right edge of what is seen of the map, as tall as it is: the window's frame top
---level with the map's top and its bottom with the map's bottom.
---@param region table The part of the map to stand beside
---@param x number Gap from its right edge
---@param topExtra number How far the visible map reaches above the region's top, such as a title bar
---@param bottomExtra number How far it reaches below the region's bottom, such as a footer
---@param mapLook table? What the map's own frame looks like, for the "Like the map" border
function Log.setMapEdge(region, x, topExtra, bottomExtra, mapLook)
    if not State.frame then
        return
    end
    local layout = ns.WindowBorder.apply(ns.settings.windowBorder, mapLook)
    -- (with the gamepad interface the window lies against the map: no left side of its own frame there)
    ns.WindowBorder.setLeftEdgeShown(not ns.MapDock.isMapHandsOff())
    local scale = Log.getWindowScale()
    State.frame:SetScale(scale)
    -- The map's edges were measured in its units; the window reads its offsets in its own, which its size changes
    x, topExtra, bottomExtra = x / scale, topExtra / scale, bottomExtra / scale
    State.frame:ClearAllPoints()
    State.frame:SetPoint(
        "TOPLEFT",
        region,
        "TOPRIGHT",
        x + layout.shiftX,
        topExtra - layout.stripHeight + layout.outset
    )
    State.frame:SetPoint("BOTTOMLEFT", region, "BOTTOMRIGHT", x + layout.shiftX, -bottomExtra - layout.outset)
    Log.fitOnScreen()
end

---@return number scale The quest window's size, text included, as the settings have it
function Log.getWindowScale()
    local scale = tonumber(ns.settings.windowScale) or 1
    return math.max(0.7, math.min(1.6, scale))
end

---Beside the map on a narrow screen (a 16:9 screen at UI scale 1 is 1365 wide) map and window are wider than the
---screen: the window is drawn just small enough to end at the screen's edge, its layout unchanged. Its left
---edge stays against the map and its top and bottom level with the map's.
function Log.fitOnScreen()
    -- Smaller than this the text gets hard to read; past it the window may reach off screen. A size the player
    -- chose smaller than that is kept.
    local minScale = math.min(0.75, Log.getWindowScale())
    -- Twice: drawn smaller, its offset from the map is smaller too, which moves its left edge a little
    for _ = 1, 2 do
        local left, right = State.frame:GetLeft(), State.frame:GetRight()
        local screenRight = UIParent:GetRight()
        if not left or not right or not screenRight then
            return
        end
        -- In the window's own units, as its edges are
        screenRight = screenRight * UIParent:GetEffectiveScale() / State.frame:GetEffectiveScale()
        if right <= screenRight + 0.25 then
            return
        end
        local scale = State.frame:GetScale() * (screenRight - left) / (right - left)
        State.frame:SetScale(math.max(minScale, scale))
    end
end

---Opens the panels with the settings on the page beside the list.
---@return boolean isOpened False when Trailhead's panels are switched off, so there is nowhere to show them
---@param sectionIndex number? The section to open on; where it was left when nil
function Log.openSettings(sectionIndex)
    if not State.frame or not ns.settings.shouldReplaceQuestLog then
        return false
    end
    ns.MapDock.open()
    State.view = "settings"
    State.settingsSectionIndex = sectionIndex or State.settingsSectionIndex
    Log.refresh()
    return true
end

---@return boolean isShowing The settings are on the page beside the list
function Log.isShowingSettings()
    return State.view == "settings"
end

---@return boolean isOpen The panels are on screen
function Log.isOpen()
    return State.frame ~= nil and State.isDocked and State.frame:IsVisible() == true
end

---@return number? questId The quest selected, and so highlighted, on the My quests tab while the panels are
---open; nil when the player has none selected
function Log.getSelectedQuestId()
    if not Log.isOpen() or State.selectedTab ~= TAB_QUESTS or State.selectedLogZoneId then
        return nil
    end
    return selectedQuestIds[TAB_QUESTS]
end

---@return boolean isUnfocused The quest open in the window had its focus taken off while open: it stays open, but the
---map no longer shows it as the one in focus, till it is picked again
function Log.isUnfocusedSelection(questId)
    return questId ~= nil and questId == State.unfocusedSelection
end

---@return number? dungeonId The dungeon open on the Dungeons tab, when that tab is shown
function Log.getShownDungeonId()
    return Log.isOpen() and State.selectedTab == TAB_DUNGEONS and State.selectedDungeonId or nil
end

---@return number? questId The quest open on the Dungeons tab's page
function Log.getSelectedDungeonQuestId()
    local selectedId = Log.isOpen() and State.selectedTab == TAB_DUNGEONS and selectedQuestIds[TAB_DUNGEONS]
    return selectedId and selectedId > 0 and selectedId or nil
end

---@return boolean isShowingAvailable The panels are open on the Available tab
function Log.isShowingAvailable()
    return Log.isOpen() and State.selectedTab == TAB_AVAILABLE
end

---A quest to pick up opened on the Dungeons tab's page is one the map shows as the Available tab's is: its giver
---highlighted, its turn-in once "Show turn-in" is pressed. (A quest of the log opens on My quests instead.)
---@return number? questId The quest to pick up opened on the Dungeons tab, while the panels show that tab
local function getDungeonPageQuestId()
    local selectedId = Log.isOpen() and State.selectedTab == TAB_DUNGEONS and selectedQuestIds[TAB_DUNGEONS]
    if not selectedId or selectedId <= 0 or ns.QuestState.isInLog(selectedId) then
        return nil
    end
    return selectedId
end

---@return table? quest The quest to pick up shown on the page of the Available tab (or of the Dungeons tab), while
---the panels are open
function Log.getSelectedAvailableQuest()
    local quest = State.selectedAvailableQuest
    if getDungeonPageQuestId() then
        return quest and quest.questId == getDungeonPageQuestId() and quest or nil
    end
    if not Log.isOpen() or State.selectedTab ~= TAB_AVAILABLE or State.isPickingZone then
        return nil
    end
    return quest
end

---@return number? questId The quest of the My quests tab under the mouse, which the map shows in full meanwhile
function Log.getHoveredQuestId()
    if not Log.isOpen() or State.selectedTab ~= TAB_QUESTS then
        return nil
    end
    return hoveredQuestIds[TAB_QUESTS]
end

---@return number? questId The available quest the map highlights: the one under the mouse, else the selected one
function Log.getHighlightedAvailableQuestId()
    if Log.isOpen() and State.selectedTab == TAB_DUNGEONS then
        -- (a dungeon's own row is under the mouse as its negative id: no quest of it is highlighted for that)
        local hoveredId = hoveredQuestIds[TAB_DUNGEONS]
        return hoveredId and hoveredId > 0 and not ns.QuestState.isInLog(hoveredId) and hoveredId
            or getDungeonPageQuestId()
    end
    if not Log.isOpen() or State.selectedTab ~= TAB_AVAILABLE then
        return nil
    end
    return hoveredQuestIds[TAB_AVAILABLE] or selectedQuestIds[TAB_AVAILABLE]
end

---@return number? questId The quest to pick up shown on the page of the Available tab (or of the Dungeons tab), while
---the panels are open
function Log.getSelectedAvailableQuestId()
    local dungeonQuestId = getDungeonPageQuestId()
    if dungeonQuestId then
        return dungeonQuestId
    end
    if not Log.isOpen() or State.selectedTab ~= TAB_AVAILABLE then
        return nil
    end
    return selectedQuestIds[TAB_AVAILABLE]
end

---@return number? questId The quest last selected on the Available tab, kept with the window closed: the minimap goes
---on showing where it starts while the player walks there. Let go of once it is deselected, another is chosen, or it is
---picked up (then its own objectives show)
function Log.getChosenAvailableQuestId()
    local questId = selectedQuestIds[TAB_AVAILABLE]
    if not questId or ns.QuestState.isInLog(questId) or ns.QuestState.isTurnedIn(questId) then
        return nil
    end
    return questId
end

---Lets go of the quest selected on the Available tab, as a second click on its giver's mark does.
function Log.deselectAvailableQuest()
    selectedQuestIds[TAB_AVAILABLE] = nil
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---Selects a quest of the log, as a click on its map pin does.
function Log.selectQuest(questId)
    State.view = "quests"
    State.scrollTargetQuestId = questId -- chosen outside the list, so the list brings it into view
    State.selectedTab = TAB_QUESTS
    selectedQuestIds[TAB_QUESTS] = questId
    State.unfocusedSelection = nil
    State.selectedLogZoneId, State.isChainExpanded = nil, false
    Log.spreadOpenedPage()
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---The tracker's active quest changed: the My quests tab selects and highlights it, or, when the focus was
---taken off, highlights nothing.
function Log.handleActiveQuestChanged(questId)
    -- With a quest: it is opened. Without one, the focus was only taken off: whatever is open stays open, no longer
    -- shown on the map as the one in focus
    State.unfocusedSelection = not questId and selectedQuestIds[TAB_QUESTS] or nil
    if questId and (selectedQuestIds[TAB_QUESTS] ~= questId or State.selectedLogZoneId) then
        State.scrollTargetQuestId = questId -- highlighted from the tracker or the map: brought into view
        selectedQuestIds[TAB_QUESTS] = questId
        State.selectedLogZoneId, State.isChainExpanded = nil, false
    end
    Log.refresh()
end

---A quest stopped being tracked or left the log. One that left the log is let go of if it was the open one.
function Log.handleQuestDropped(questId)
    -- Untracked, the quest is still in the log and stays open; only a quest that left the log is let go
    if not ns.QuestState.isInLog(questId) then
        ns.settings.cycledQuestZones[questId] = nil -- gone from the log: nothing to return to
    end
    if selectedQuestIds[TAB_QUESTS] == questId and not ns.QuestState.isInLog(questId) then
        selectedQuestIds[TAB_QUESTS] = nil
        Log.refresh()
        ns.MapPins.queueRefresh()
    end
end

---The map turned to another zone: the Available tab follows it.
function Log.handleMapChanged(uiMapId)
    -- On the My quests tab the zone the map shows is highlighted in the list
    if Log.isOpen() and State.selectedTab == TAB_QUESTS and State.view == "quests" then
        if List.getShownMapZoneId() ~= State.drawnMapZoneId then
            ns.Timing.measure("quest window drawn (map changed)", Log.refresh)
        end
        return
    end
    if not Log.isOpen() or State.selectedTab ~= TAB_AVAILABLE or State.isPickingZone or State.isMapFollowPaused then
        return
    end
    local areaId = uiMapId and ns.Database.isZoneMap(uiMapId) and ns.Database.getAreaId(uiMapId)
    local zoneId = areaId and ns.Database.getParentZoneId(areaId)
    local shownZoneId = State.pickedZoneId or ns.Model.getPlayer().zoneId
    if zoneId and zoneId ~= shownZoneId and not isMapOfPickedDungeon(zoneId) and ns.Availability.isReady() then
        State.pickedZoneId = zoneId
        selectedQuestIds[TAB_AVAILABLE] = nil
        ns.Timing.measure("quest window drawn (map changed)", Log.refresh)
    end
end

function Log.toggle()
    ns.MapDock.toggle()
end

---Shows a zone's own page on the My quests tab.
function Log.showZonePage(zoneId)
    State.view = "quests"
    State.selectedTab = TAB_QUESTS
    State.selectedLogZoneId = zoneId
    ns.MapDock.open()
    Log.refresh()
end

---@return number? zoneId The location the Available tab is about: the picked one, or the player's
---@return table canvas The list's canvas, for tests that press its rows
function Log.getListCanvas()
    return State.list
end

---@return table canvas The page's canvas, for tests that read what it drew
function Log.getPageCanvas()
    return State.detail
end

---@return Button? button The quest page's title, which links the quest in chat on shift-click
function Log.getPageTitleButton()
    return State.pageHeader and State.pageHeader.titleButton
end

---@return Frame? window The window (TrailheadLog), once made
function Log.getWindow()
    return State.frame
end

---Opens the tab beside the open one (1: the next, -1: the one before), as the tab itself would be clicked: the
---gamepad's shoulder buttons. It stops at the first and the last, and passes over a tab that is not shown, as the
---game's own tab indicators do.
function Log.stepTab(delta)
    local tabs = State.frame and State.frame.tabs
    if not tabs or #tabs == 0 then
        return
    end
    local index = State.view == "quests" and State.selectedTab or 0
    repeat
        index = index + delta
        local target = tabs[index]
        if target and target:IsShown() and (not target.IsEnabled or target:IsEnabled()) then
            target:Click()
            return true
        end
    until not target
    return false
end

---@return string view What the window shows: "quests", "settings" or "chronicle"
function Log.getView()
    return State.view
end

---@return boolean isShowingDungeons The window shows the Dungeons tab
function Log.isShowingDungeons()
    return State.view == "quests" and State.selectedTab == TAB_DUNGEONS
end

---@return boolean isShowingQuests The window shows the My quests tab
function Log.isShowingQuests()
    return State.view == "quests" and State.selectedTab == TAB_QUESTS
end

---@return any data What the open tab has open on its page: a quest, or the Dungeons tab's row (as its row's data)
function Log.getOpenRowData()
    return State.view == "quests" and selectedQuestIds[State.selectedTab] or nil
end

---@return boolean isInPage The frame is part of the page beside the list: its header, its drawing, the rewards
---under it or the buttons at its foot
function Log.isInPage(frame)
    local parts =
        { State.detail and State.detail.frame, State.pageHeader, State.rewardsBlock, State.frame and State.frame.bar }
    while frame do
        for _, part in ipairs(parts) do
            if frame == part then
                return true
            end
        end
        frame = frame:GetParent()
    end
    return false
end

---@return EditBox? search The search box the open tab shows (the quests' search, or the Available tab's location)
function Log.getShownSearchBox()
    local frame = State.frame
    for _, box in ipairs(frame and { frame.search, frame.availableSearch } or {}) do
        if box and box:IsVisible() then
            return box
        end
    end
    return nil
end

---The gamepad's B: the settings or the chronicle give way to the quests, as their own buttons would; on the quests
---the window closes.
---@return boolean isHandled
function Log.handleGamepadBack()
    if State.view == "settings" then
        SettingsView.toggleSettings()
    elseif State.view == "chronicle" and ns.ChroniclePage.isEntryOpen() then
        ns.ChroniclePage.closeEntry() -- a quest's story: back to the journal's list first, as the page's Back does
    elseif State.view == "chronicle" then
        Log.toggleChronicle()
    else
        Log.closeWindow()
    end
    return true
end

---@return Button? button The page header's Back (over a quest's story in the chronicle's journal: B with a controller)
function Log.getPageHeaderBackButton()
    return State.pageHeader and State.pageHeader.backButton
end

---@return Button[] icons The Rewards strip's icons (each with its .item, or none: experience, money)
function Log.getRewardIcons()
    return State.rewardsBlock and State.rewardsBlock.icons or {}
end

function Log.getAvailableZoneId()
    return State.pickedZoneId or ns.Model.getPlayer().zoneId
end

---Opens the Available tab on a chosen zone.
function Log.showZone(zoneId)
    -- A dungeon is on the Dungeons tab (its gate on the map, a dungeon row of a zone's list)
    if ns.Database.getDungeon(zoneId) then
        Log.showDungeon(zoneId)
        return
    end
    ns.MapDock.showZoneMap(zoneId) -- the Available tab then takes its location from the map
    selectedQuestIds[TAB_AVAILABLE] = nil
    Log.showAvailable()
    if State.pickedZoneId ~= zoneId and zoneId ~= ns.Model.getPlayer().zoneId then
        State.pickedZoneId = zoneId -- the map could not be turned (closed, or no map for the zone)
        Log.refresh()
    end
end

---Opens the Dungeons tab on a dungeon: its page, or one of its quests (a quest clicked on the map).
function Log.showDungeon(dungeonId, questId)
    if not List.isDungeonsTabShown() then
        -- (the Spoilers choice keeps dungeons back: no tab to open; a quest of the log opens there all the same)
        if questId and ns.QuestState.isInLog(questId) then
            Log.selectQuest(questId)
        end
        return
    end
    local dungeon = ns.Database.getDungeon(dungeonId)
    State.view, State.isPickingZone = "quests", false
    State.selectedTab = TAB_DUNGEONS
    State.selectedDungeonId = dungeon and dungeon.areaId or nil
    selectedQuestIds[TAB_DUNGEONS] = questId or (State.selectedDungeonId and -State.selectedDungeonId) or nil
    State.scrollTargetQuestId = selectedQuestIds[TAB_DUNGEONS]
    if questId then
        Log.spreadOpenedPage() -- (a dungeon by itself unfolds its quests in the list: they are what is wanted)
    end
    ns.MapDock.open()
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---Shows a quest wherever it is: its page in the log when it is there, else on the Available tab of the zone it
---starts in, opening the "not yet" part of the list when it waits there.
function Log.showQuestAnywhere(questId)
    if ns.QuestState.isInLog(questId) then
        Log.selectQuest(questId)
        return
    end
    local zoneId = ns.Availability.getStartZoneId(questId)
    if not zoneId or not List.isAvailableTabShown() then
        return
    end
    State.view, State.isPickingZone = "quests", false
    State.selectedTab = TAB_AVAILABLE
    State.isUpcomingShown = true
    ns.MapDock.open()
    State.isMapFollowPaused = true -- the list moves to the zone itself, without letting go of the quest
    ns.MapDock.showZoneMap(zoneId)
    State.isMapFollowPaused = false
    State.pickedZoneId = zoneId ~= ns.Model.getPlayer().zoneId and zoneId or nil
    selectedQuestIds[TAB_AVAILABLE] = questId
    State.scrollTargetQuestId = questId
    Log.spreadOpenedPage()
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---Opens the panels on the Available tab.
---@param questId number? The quest to select there
function Log.showAvailable(questId)
    State.view = "quests"
    if not List.isAvailableTabShown() then
        ns.MapDock.open() -- switched off (or kept back by the Spoilers choice): the panels open on the quests in the log
        return
    end
    State.selectedTab = TAB_AVAILABLE
    State.isPickingZone = false
    ns.MapDock.open()
    -- A quest clicked on the map belongs to the zone the map shows, which may not be where the player is
    adoptMapZone()
    -- ... unless the list there does not hold it: a dungeon's list and its entrance zone's share one map (a
    -- Barrens quest clicked while Razorfen Kraul is listed, or the other way round). The list then moves to
    -- where the quest is listed: the dungeon it is picked up in, else the zone it starts in.
    if questId then
        local playerZoneId = ns.Model.getPlayer().zoneId
        local zoneId = State.pickedZoneId or playerZoneId
        local isListed = false
        if ns.Database.getDungeon(zoneId) then
            local run = ns.Availability.getDungeonRun(zoneId)
            for _, section in ipairs({ run.inLog, run.pickUp, run.foundInside, run.behindLeadIn, run.notYet }) do
                for _, quest in ipairs(section) do
                    isListed = isListed or quest.questId == questId
                end
            end
        else
            for _, quests in ipairs({
                (ns.Availability.getQuests(zoneId, { shouldShowLowLevel = true })),
                (ns.Availability.getBlockedQuests(zoneId, { shouldShowLowLevel = true })),
            }) do
                for _, quest in ipairs(quests) do
                    isListed = isListed or quest.questId == questId
                end
            end
        end
        local homeZoneId = not isListed
            and (ns.Location.getPickupDungeonId(questId) or ns.Availability.getStartZoneId(questId))
        if homeZoneId and homeZoneId ~= zoneId and ns.Database.getDungeon(homeZoneId) then
            Log.showDungeon(homeZoneId, questId) -- a dungeon's quest is on the Dungeons tab, under its dungeon
            return
        end
        if homeZoneId and homeZoneId ~= zoneId then
            State.pickedZoneId = homeZoneId ~= playerZoneId and homeZoneId or nil
        end
    end
    selectedQuestIds[TAB_AVAILABLE] = questId or selectedQuestIds[TAB_AVAILABLE]
    State.scrollTargetQuestId = questId
    if questId then
        Log.spreadOpenedPage()
    end
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---Makes the quest log key do exactly what the map key does, or gives it back. The key is pointed at the
---game's own map command, not at addon code, because the game refuses to let an addon open the map during
---combat. Key bindings cannot change in combat either, so Core calls this again when combat ends.
function Log.applyBinding()
    if not State.toggleButton or InCombatLockdown() then
        return
    end
    ClearOverrideBindings(State.toggleButton)
    if not ns.settings.shouldReplaceQuestLog then
        return
    end
    for _, key in ipairs({ GetBindingKey("TOGGLEQUESTLOG") }) do
        SetOverrideBinding(State.toggleButton, false, key, "TOGGLEWORLDMAP")
    end
end

-- Shared with the other parts of the window
Window.showPlace = showPlace

-- The quest in focus is opened in the list; a quest untracked or gone from the log is let go of
ns.on("FOCUS_CHANGED", Log.handleActiveQuestChanged)
ns.on("QUEST_GONE", Log.handleQuestDropped)

ns.registerModule({
    name = "Log",
    create = function()
        Log.create()
        Log.applyBinding()
        Log.scheduleWarmUp(WARM_UP_TRIES, WARM_UP_SECONDS) -- (made and drawn unseen before the first opening)
    end,
    needsWorldMap = true,
    refresh = Log.refresh,
    afterCombat = function()
        Log.applyBinding() -- key bindings cannot change in combat
        Log.openMapAfterCombat() -- a window opened alone in the fight joins the map now
    end,
    events = { UPDATE_BINDINGS = Log.applyBinding },
})
