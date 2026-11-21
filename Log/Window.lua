local _, ns = ...

-- The quest log window: the window itself (its frame, tabs, header, buttons) and its public functions (ns.Log).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window = ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local focusQuest, toggleTracked = Actions.focusQuest, Actions.toggleTracked
local drawAvailableTab, pickZone, toggleLowLevel = AvailableTab.drawAvailableTab, AvailableTab.pickZone, AvailableTab.toggleLowLevel
local createPageHeader, createRewardsBlock, followPageScroll, setAtlasIfKnown, setPageHeader, setPageRewards = QuestPage.createPageHeader, QuestPage.createRewardsBlock, QuestPage.followPageScroll, QuestPage.setAtlasIfKnown, QuestPage.setPageHeader, QuestPage.setPageRewards
local FILTER_LABELS, drawLogTab, selectFilter = QuestsTab.FILTER_LABELS, QuestsTab.drawLogTab, QuestsTab.selectFilter
local detailScrollByTab, filterDropdown, hoveredQuestIds, listOpening, listScrollByTab, nativeTabs = State.detailScrollByTab, State.filterDropdown, State.hoveredQuestIds, State.listOpening, State.listScrollByTab, State.nativeTabs
local selectedQuestIds, shownDetailSubjectByTab, shownSubjectByTab = State.selectedQuestIds, State.shownDetailSubjectByTab, State.shownSubjectByTab
local BACKGROUND, BAR_BACKGROUND, BAR_HEIGHT, COLORS, FILTERS, HEADER_BAR_LOW = Style.BACKGROUND, Style.BAR_BACKGROUND, Style.BAR_HEIGHT, Style.COLORS, Style.FILTERS, Style.HEADER_BAR_LOW
local LIST_WIDTH, LOW_LEVEL_BAR_HEIGHT, PAGE_CONTENT_WIDTH, PAGE_TOP, PAGE_WIDTH, PANEL_WIDTH = Style.LIST_WIDTH, Style.LOW_LEVEL_BAR_HEIGHT, Style.PAGE_CONTENT_WIDTH, Style.PAGE_TOP, Style.PAGE_WIDTH, Style.PANEL_WIDTH
local RED_BUTTON_EDGE, RED_BUTTON_LIT, SCROLL_ARROW_HEIGHT, SEARCH_HEIGHT, TAB_AVAILABLE, TAB_LABELS = Style.RED_BUTTON_EDGE, Style.RED_BUTTON_LIT, Style.SCROLL_ARROW_HEIGHT, Style.SEARCH_HEIGHT, Style.TAB_AVAILABLE, Style.TAB_LABELS
local TAB_QUESTS, TITLE_HEIGHT, ZONE_MENU_HEIGHT = Style.TAB_QUESTS, Style.TITLE_HEIGHT, Style.ZONE_MENU_HEIGHT
local TAB_DUNGEONS = Style.TAB_DUNGEONS
local DungeonsTab = ns.LogDungeonsTab

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
    State.frame.journalButton:SetShown(shownDungeon ~= nil and ns.DungeonJournal ~= nil and ns.DungeonJournal.knows(shownDungeon.name))
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
    Log.setButtonText(State.frame.mapButton, ns.L(selected and selected.startType == "item" and "Show source" or "Show giver"))
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
    if type(State.frame.availableSearch.Instructions) == "table" and State.frame.availableSearch.Instructions.SetText then
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
        local canShare = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questId) and IsInGroup and IsInGroup()
        State.frame.shareButton:SetEnabled(canShare == true)
    end
    State.frame.resetSettingsButton:Hide()
    State.frame.doneButton:Hide()
    State.frame.journalBackButton:Hide()
    for _, control in ipairs({ State.frame.status, State.frame.tabRowFill, State.frame.tabRowRule }) do
        control:Show()
    end
    for tab, button in ipairs(State.frame.tabs) do
        -- With this addon's quests to pick up switched off, the game's own marks show them and the tab goes
        button:SetShown(tab ~= TAB_AVAILABLE or ns.settings.shouldUseAvailableQuests)
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
        local text = shownCount and string.format("%s (%d)", ns.L(TAB_LABELS[tabIndex]), shownCount) or ns.L(TAB_LABELS[tabIndex])
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

function Log.refresh()
    if not State.frame or not State.isDocked or not State.frame:IsVisible() then
        State.isStale = true -- something changed while the window was closed: drawn again as it opens
        return
    end
    State.isStale = false
    State.drawnPosition = ns.Geometry.getPlayerPosition()
    Log.applyButtonTexts()
    -- The journal's search and dropdowns are frames of its own: shown again only if the journal is what is drawn
    if ns.ChroniclePage and ns.ChroniclePage.hideJournalControls then
        ns.ChroniclePage.hideJournalControls()
    end
    State.frame.journalBackButton:Hide() -- shown again only over a quest's story in the journal
    State.frame.ironPage:Hide() -- the parchment again; the settings put their dark ground back as they are drawn
    if State.languageDropdown then
        State.languageDropdown:Hide() -- About shows it again as it is drawn
    end
    if State.view == "quests" then
        State.frame.placeSplit(LIST_WIDTH)
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
    if State.selectedTab == TAB_AVAILABLE and not ns.settings.shouldUseAvailableQuests then
        State.selectedTab = TAB_QUESTS -- the Available tab was switched off while it was open
    end
    -- Placed before the list is drawn: its scroll range is measured against the height it has now
    -- The Dungeons tab has no search row: its list starts under the tabs
    State.list.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 6, -(TITLE_HEIGHT + (State.selectedTab == TAB_DUNGEONS and 4 or SEARCH_HEIGHT)))
    State.list.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", 6, State.selectedTab == TAB_AVAILABLE and LOW_LEVEL_BAR_HEIGHT + 6 or 6)
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
    local listSubject = State.selectedTab == TAB_QUESTS and "quests" or State.selectedTab == TAB_DUNGEONS and "dungeons"
        or (State.isPickingZone and "picker" or ("zone" .. tostring(State.pickedZoneId or ns.Model.getPlayer().zoneId)))
    local previousSubject = shownSubjectByTab[State.selectedTab]
    shownSubjectByTab[State.selectedTab] = listSubject
    if previousSubject ~= nil and previousSubject ~= listSubject then
        State.list:scrollToTop()
    elseif State.selectedTab ~= State.shownTab or wasSettingsDrawn then
        State.list:setScroll(listScrollByTab[State.selectedTab] or 0)
    end
    -- The page beside the list works the same way: its own place per tab, and the top for another quest or zone
    local detailSubject = listSubject .. ":" .. (State.selectedTab == TAB_QUESTS and State.selectedLogZoneId and ("zone" .. State.selectedLogZoneId)
        or State.selectedTab == TAB_DUNGEONS and ("dungeon" .. tostring(State.selectedDungeonId) .. ":" .. tostring(selectedQuestIds[TAB_DUNGEONS]))
        or ("quest" .. tostring(selectedQuestIds[State.selectedTab])))
    local previousDetailSubject = shownDetailSubjectByTab[State.selectedTab]
    shownDetailSubjectByTab[State.selectedTab] = detailSubject
    if previousDetailSubject ~= nil and previousDetailSubject ~= detailSubject then
        State.detail:scrollToTop()
    elseif State.selectedTab ~= State.shownTab or wasSettingsDrawn then
        State.detail:setScroll(detailScrollByTab[State.selectedTab] or 0)
    end
    State.shownTab = State.selectedTab
    if State.scrollTargetQuestId and State.scrollTargetQuestId == selectedQuestIds[State.selectedTab] and State.selectedRowTop then
        State.list:scrollIntoView(State.selectedRowTop, State.selectedRowBottom)
    end
    State.scrollTargetQuestId = nil
    if listOpening.scrollTop then
        State.list:setScroll(math.max(listOpening.scrollTop - 2, 0)) -- the group's heading at the top of the list
        listOpening.scrollTop = nil
    end
    updateControls(selected, tabCount)
end

---A picked dungeon is shown on the map of the zone its entrance is in. That map is still the dungeon's, so
---the Available tab's location stays the dungeon while it shows.
---@param mapZoneId number The zone of the map being shown
local function isMapOfPickedDungeon(mapZoneId)
    return State.pickedZoneId ~= nil and ns.Database.getDungeon(State.pickedZoneId) ~= nil
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
        if State.selectedLogZoneId and ns.Database.getDungeon(State.selectedLogZoneId) and State.selectedLogZoneId ~= State.pickedZoneId then
            -- Coming from a dungeon's page: the map shows the zone its entrance is in, but the location meant
            -- is the dungeon. Should the map have moved on since, adopting its zone below overrides this.
            State.pickedZoneId = State.selectedLogZoneId ~= ns.Model.getPlayer().zoneId and State.selectedLogZoneId or nil
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
    C_QuestLog.SetSelectedQuest(questId)
    C_QuestLog.SetAbandonQuest()
    StaticPopup_Show("ABANDON_QUEST", C_QuestLog.GetTitleForQuestID(questId) or ns.L("this quest"))
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
    button:SetScript("OnClick", function() selectTab(tab) end)
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
        local playerName = player.zoneId and ns.Database.getZoneName(player.zoneId) or player.zoneName or ns.L("My location")
        root:CreateRadio(ns.L("%s (you are here)", playerName), isSelected, setSelected, false)
        local zones = ns.Availability.getZones({ shouldShowLowLevel = ns.settings.shouldShowLowLevel })
        -- A location the map turned to, with nothing to pick up there (only quests handed in, say), is not among
        -- the zones with quests: it gets a line of its own, so the dropdown still names it
        local isPickedListed = State.pickedZoneId == nil or State.pickedZoneId == player.zoneId
        for _, zone in ipairs(zones) do
            isPickedListed = isPickedListed or zone.zoneId == State.pickedZoneId
        end
        if not isPickedListed then
            root:CreateRadio(ns.L("%s (on the map)", ns.Database.getZoneName(State.pickedZoneId)), isSelected, setSelected, State.pickedZoneId)
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
                    root:CreateRadio(string.format("%s (%d)", zone.zoneName, zone.count), isSelected, setSelected, zone.zoneId)
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
            root:CreateRadio(ns.L(FILTER_LABELS[filter]) .. (count and string.format(" (%d)", count) or ""), isSelected, selectFilter, filter)
        end
    end)
    return dropdown
end

---Builds the panels as a child of the world map, joined to its right edge and as tall as it is.
function Log.create()
    if State.frame or not WorldMapFrame then
        return
    end
    State.frame = CreateFrame("Frame", "TrailheadLog", WorldMapFrame, "BackdropTemplate")
    State.frame:SetWidth(PANEL_WIDTH)
    State.frame:EnableMouse(true) -- clicks must not fall through to the world behind
    -- Nor the wheel: over the window's header, bar and edges it would otherwise zoom the camera
    State.frame:EnableMouseWheel(true)
    State.frame:SetScript("OnMouseWheel", function() end)
    State.frame:SetScript("OnShow", function() Log.handleShown() end)
    State.frame:Hide()
    -- The frame round the panels, in the look picked in the settings, with the settings and close buttons
    ns.WindowBorder.create(State.frame, {
        listWidth = LIST_WIDTH,
        tabRowHeight = TITLE_HEIGHT,
        stripColor = BAR_BACKGROUND,
        handleSettingsClick = SettingsView.toggleSettings,
        handleCloseClick = function()
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
                ns.Timing.noteProblem("refused", "the close button could not close the map: the panels were folded away instead")
                ns.MapDock.foldUntilClosed()
            elseif State.frame:IsShown() then
                ns.MapDock.apply() -- (the map was gone already: the panels go after it)
            end
        end,
        getSettingsTooltip = function()
            return State.view == "settings" and ns.L("Close the settings") or ns.L("%s settings", ns.ADDON_TITLE)
        end,
        handleChronicleClick = function() Log.toggleChronicle() end,
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
    if not setAtlasIfKnown(listArt, "QuestLog-main-background") then
        listArt:Hide()
    end
    State.frame.listArt = listArt
    State.list = ns.Widgets.createCanvas("TrailheadLogList", State.frame, LIST_WIDTH - 6, 400)
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
        scrollBar:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", barLeft, BAR_HEIGHT + inset)
    end

    State.frame.bar = CreateFrame("Frame", nil, State.frame)
    State.frame.bar:SetPoint("TOPLEFT", State.frame, "BOTTOMLEFT", pageLeft, BAR_HEIGHT)
    State.frame.bar:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMRIGHT", -3, 3)
    State.frame.pageLeft = pageLeft

    ---Moves the line between the list and the page: a narrower list gives the page its room. The page's right
    ---edge, its scroll bar and the window stay where they are.
    function State.frame.placeSplit(listWidth)
        local newPageLeft = listWidth + 2
        if State.frame.pageLeft == newPageLeft then
            return
        end
        State.frame.pageLeft = newPageLeft
        State.list:setWidth(listWidth - 6)
        State.detail:setWidth(PAGE_WIDTH - 2 + LIST_WIDTH - listWidth)
        divider:SetPoint("TOPLEFT", State.frame, "TOPLEFT", listWidth + 1, 0)
        divider:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", listWidth + 2, 3)
        listArt:SetPoint("BOTTOMRIGHT", State.frame, "BOTTOMLEFT", listWidth + 1, 3)
        parchment:SetPoint("TOPLEFT", State.frame, "TOPLEFT", newPageLeft, -PAGE_TOP)
        State.detail.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", newPageLeft, -PAGE_TOP - 2)
        State.detail.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", newPageLeft, BAR_HEIGHT + 2)
        State.pageHeader:SetPoint("TOPLEFT", State.frame, "TOPLEFT", newPageLeft, -PAGE_TOP)
        State.rewardsBlock:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", newPageLeft, BAR_HEIGHT)
        State.frame.bar:SetPoint("TOPLEFT", State.frame, "BOTTOMLEFT", newPageLeft, BAR_HEIGHT)
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
    State.frame.textButtons = { State.frame.shareButton, State.frame.abandonButton, State.frame.turnInMapButton, State.frame.trackAllButton,
        State.frame.zoneMapButton, State.frame.resetSettingsButton, State.frame.doneButton, State.frame.entranceButton, State.frame.journalButton, State.frame.journalBackButton }

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

---Shows the panels beside the map or takes them away; MapDock decides which.
function Log.setDocked(shouldDock)
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
        if State.view ~= "quests" or selectedQuestIds[TAB_QUESTS] ~= focusedQuestId or State.selectedLogZoneId ~= nil
            or not Log.isNearDrawnPosition() then
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
    local scale = Log.getWindowScale()
    State.frame:SetScale(scale)
    -- The map's edges were measured in its units; the window reads its offsets in its own, which its size changes
    x, topExtra, bottomExtra = x / scale, topExtra / scale, bottomExtra / scale
    State.frame:ClearAllPoints()
    State.frame:SetPoint("TOPLEFT", region, "TOPRIGHT", x + layout.shiftX, topExtra - layout.stripHeight + layout.outset)
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

---@return table? quest The quest shown on the page of the Available tab, while the panels are open
function Log.getSelectedAvailableQuest()
    if not Log.isOpen() or State.selectedTab ~= TAB_AVAILABLE or State.isPickingZone then
        return nil
    end
    return State.selectedAvailableQuest
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
    if not Log.isOpen() or State.selectedTab ~= TAB_AVAILABLE then
        return nil
    end
    return hoveredQuestIds[TAB_AVAILABLE] or selectedQuestIds[TAB_AVAILABLE]
end

---@return number? questId The quest shown on the page of the Available tab, while the panels are open
function Log.getSelectedAvailableQuestId()
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
    State.selectedLogZoneId, State.isChainExpanded = nil, false
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---The tracker's active quest changed: the My quests tab selects and highlights it, or, when the focus was
---taken off, highlights nothing.
function Log.handleActiveQuestChanged(questId)
    -- With a quest: it is opened. Without one, the focus was only taken off: whatever is open stays open.
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

---@return Button? button The quest page's title, which links the quest in chat on shift-click
function Log.getPageTitleButton()
    return State.pageHeader and State.pageHeader.titleButton
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
    local dungeon = ns.Database.getDungeon(dungeonId)
    State.view, State.isPickingZone = "quests", false
    State.selectedTab = TAB_DUNGEONS
    State.selectedDungeonId = dungeon and dungeon.areaId or nil
    selectedQuestIds[TAB_DUNGEONS] = questId or (State.selectedDungeonId and -State.selectedDungeonId) or nil
    State.scrollTargetQuestId = selectedQuestIds[TAB_DUNGEONS]
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
    if not zoneId or not ns.settings.shouldUseAvailableQuests then
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
    Log.refresh()
    ns.MapPins.queueRefresh()
end

---Opens the panels on the Available tab.
---@param questId number? The quest to select there
function Log.showAvailable(questId)
    State.view = "quests"
    if not ns.settings.shouldUseAvailableQuests then
        ns.MapDock.open() -- switched off: the panels open on the quests in the log
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
            for _, quests in ipairs({ (ns.Availability.getQuests(zoneId, { shouldShowLowLevel = true })), (ns.Availability.getBlockedQuests(zoneId, { shouldShowLowLevel = true })) }) do
                for _, quest in ipairs(quests) do
                    isListed = isListed or quest.questId == questId
                end
            end
        end
        local homeZoneId = not isListed and (ns.Location.getPickupDungeonId(questId) or ns.Availability.getStartZoneId(questId))
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
    end,
    needsWorldMap = true,
    refresh = Log.refresh,
    afterCombat = Log.applyBinding, -- key bindings cannot change in combat
    events = { UPDATE_BINDINGS = Log.applyBinding },
})
