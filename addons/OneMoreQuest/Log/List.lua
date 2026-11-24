local _, ns = ...

-- The quest log window: the list on the left (its headings and quest rows).
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local handleQuestEnter, handleQuestLeave, selectQuest, selectZone, toggleTracked =
    Actions.handleQuestEnter, Actions.handleQuestLeave, Actions.selectQuest, Actions.selectZone, Actions.toggleTracked
local selectedQuestIds = State.selectedQuestIds
local CHAIN_ICON, COLORS, DOT, DUNGEON_NAME, MEDIA, READY_ICON =
    Style.CHAIN_ICON, Style.COLORS, Style.DOT, Style.DUNGEON_NAME, Style.MEDIA, Style.READY_ICON
local SELECTED_EDGE, SELECTED_FILL, TAB_QUESTS = Style.SELECTED_EDGE, Style.SELECTED_FILL, Style.TAB_QUESTS

---------------------------------------------------------------------------------------------------------------
-- The list on the left

---A heading with a rule running to the count on the right.
---@return number y Below the heading
local function addListHeading(y, text, count, color, handleClick, data)
    local width = State.list.width
    local _, textWidth =
        State.list:addText(text:upper(), 6, y + 4, { font = "GameFontNormalSmall", color = color, isSingleLine = true })
    State.list:addText(
        count,
        width - 28,
        y + 4,
        { font = "GameFontHighlightSmall", color = COLORS.tan, width = 22, justify = "RIGHT", isSingleLine = true }
    )
    State.list:addRect(6 + textWidth + 8, y + 10, math.max(width - 30 - textWidth - 20, 0), 1, COLORS.rule)
    if handleClick then
        State.list:addButton(0, y, width, 20, handleClick, data)
    end
    return y + 22
end

local function toggleLogZone(zoneId)
    ns.settings.collapsedLogZones[zoneId] = ns.settings.collapsedLogZones[zoneId] ~= true
    Log.refresh()
end

-- The game's quest log art the list draws with (fields, not locals: the file keeps its local names few)
List.SELECTED_GLOW = { atlas = "questlog-quest-glow-yellow" }
List.READY_CHECK = { atlas = "questlog-icon-checkmark-yellow" }
List.HERE_GLOW = { atlas = "questlog-header-glow-yellow" }
local knownArt = {}

---@return boolean isKnown The client has the atlas (asked once)
function List.hasGameArt(atlas)
    if knownArt[atlas] == nil then
        knownArt[atlas] = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
    end
    return knownArt[atlas]
end

State.shownZoneIds = {} -- the zones of the list as last drawn, for "open all" and "shut all"
-- State.drawnMapZoneId: the zone the map showed when the list was last drawn
-- Declared here, defined in the block below: the list calls them
-- List.getShownMapZoneId, List.addZoneHeading: shared with the other parts, set further on

do -- a block of its own, so its helpers do not count against the file's limit of local names
    local ZONE_BAR_HEIGHT = 34
    local BAND_WOOD_MIDDLE, BAND_WOOD_BOTTOM = 0.4, 0.74 -- the band's wood, against its height (its art: rows 2 to 39 of 52)
    local HERE_EDGE = { 1, 0.82, 0 } -- the zone the player is in
    local HERE_EDGE_LEFT = 3 -- the window's border covers the list's first pixels
    local PLAIN_TEXTURE = "Interface\\Buttons\\WHITE8X8"
    local ZONE_BAND = { atlas = "questlog-reward-top-frame" } -- the quest page's dark title band
    local FOLD_OPEN, FOLD_SHUT = { atlas = "campaign_headericon_open" }, { atlas = "campaign_headericon_closed" }
    local MUTED_ZONE_NAME, MUTED_DUNGEON_NAME = { 0.6, 0.56, 0.45 }, { 0.56, 0.5, 0.66 } -- no tracked quest inside
    local DUNGEON_ICON_SIZE = 16
    local dungeonIcon, dungeonIconColor -- the game's own mark of a dungeon's entrance, or our gate when it is missing

    ---The mark the world map puts at a dungeon's entrance, so a dungeon's bar is known by more than its colour.
    local function getDungeonIcon()
        if not dungeonIcon then
            local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("Dungeon") ~= nil
            dungeonIcon = hasAtlas and { atlas = "Dungeon" } or MEDIA .. "GlyphDungeon"
            dungeonIconColor = not hasAtlas and DUNGEON_NAME or nil
        end
        return dungeonIcon, dungeonIconColor
    end

    ---@return number? zoneId The zone the world map shows now
    function List.getShownMapZoneId()
        return ns.MapDock.getShownZoneId()
    end

    ---Under the mouse, a zone bar lights its name, as the game's quest log lights its own; a name cut short for
    ---room shows whole in a tooltip, and the zone the player is in says so there.
    local function showZoneBarHover(button, bar)
        bar.name:SetTextColor(1, 1, 1)
        local isCut = bar.name.IsTruncated and bar.name:IsTruncated()
        if isCut or bar.isHere then
            GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
            GameTooltip:SetText(bar.zoneName, 1, 1, 1)
            if bar.isHere then
                GameTooltip:AddLine(ns.L("You are here"), 1, 0.82, 0)
            end
            GameTooltip:Show()
        end
    end

    local function hideZoneBarHover(_, bar)
        ns.Widgets.setColor(bar.name, bar.nameColor)
    end

    local function handleZoneBarClick(bar)
        toggleLogZone(bar.zoneId)
    end

    local SHARE_BUTTON_WIDTH, SHARE_BUTTON_HEIGHT = 16, 16
    local SHARE_ICON = { atlas = "friends-icon-friendsingroup" }

    ---The zone's shareable quests under the mouse: each with who would get it.
    local function showShareHover(button, share)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(ns.L("Share %d with your party", #share.questIds), 1, 0.82, 0)
        for _, questId in ipairs(share.questIds) do
            local names = {}
            for _, member in ipairs(ns.Party.getMembers(questId)) do
                if not member.isOnQuest and (member.status.state == "can" or member.status.state == "unknown") then
                    names[#names + 1] = member.name
                end
            end
            GameTooltip:AddDoubleLine(
                C_QuestLog.GetTitleForQuestID(questId) or ("Quest " .. questId),
                table.concat(names, ", "),
                1,
                1,
                1,
                0.6,
                0.8,
                1
            )
        end
        GameTooltip:AddLine(ns.L("Offered one after another, a second apart"), 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end

    local function hideShareHover()
        GameTooltip:Hide()
    end

    local function handleShareClick(share)
        Log.shareQuests(share.questIds)
    end

    local function setAllZonesCollapsed(isCollapsed)
        for _, zoneId in ipairs(State.shownZoneIds) do
            ns.settings.collapsedLogZones[zoneId] = isCollapsed
        end
        Log.refresh()
    end

    ---Right-click on a zone bar: the game's menu, with the way to the zone on the map and its page, and folding
    ---every zone at once. A category such as cooking is no place, so it has only the folding.
    local function openZoneMenu(bar)
        if not MenuUtil or not MenuUtil.CreateContextMenu then
            return
        end
        ns.openMenu(State.frame, function(_, root)
            ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
            root:CreateTitle(bar.zoneName)
            Log.addTrackMenuItems(root, bar.questIds)
            if not bar.isCategory then
                root:CreateButton(ns.L("Show on the map"), function()
                    ns.MapDock.showZoneMap(bar.zoneId)
                end)
                root:CreateButton(ns.L("Open the zone's page"), function()
                    selectZone(bar.zoneId)
                end)
                if bar.shareable and #bar.shareable > 0 then
                    root:CreateButton(ns.L("Share %d with your party", #bar.shareable), function()
                        Log.shareQuests(bar.shareable)
                    end)
                end
                root:CreateDivider()
            end
            root:CreateButton(ns.L("Open all zones"), function()
                setAllZonesCollapsed(false)
            end)
            root:CreateButton(ns.L("Shut all zones"), function()
                setAllZonesCollapsed(true)
            end)
        end)
    end

    ---A zone's heading, on the quest page's dark title band across the list: the game's + or - to fold it in
    ---front, then the zone's name: white when a tracked quest is inside, muted when none is. After the name a
    ---dungeon has the map's gate mark (and a lilac name, so it is told apart by more than colour), a category such
    ---as cooking its own picture, as it is not a place; the zone the player is in has a gold edge down its left
    ---("You are here" when pointed at). At the
    ---right, in words, how many of its quests are ready to hand in and how many there are, "2 ready · 4 quests".
    ---The heading itself is never highlighted: the quest inside that is selected or followed is.
    function List.addZoneHeading(y, group, isCollapsed, hasTracked)
        -- The zone the player is in has a gold edge at its left. A category (cooking) is no place, though it opens
        -- when a quest's next step is where the player is.
        local isHere = group.isCurrent and not group.isCategory
        local barLeft, barWidth = 0, State.list.width
        local barHeight = ZONE_BAR_HEIGHT
        -- The band's wood fills its upper three quarters, a dark lip the rest: what it holds is centred on the wood
        local middle = y + math.floor(barHeight * BAND_WOOD_MIDDLE + 0.5)
        local isDungeon = ns.Database.getDungeon(group.zoneId) ~= nil
        -- Bright when a tracked quest is inside, muted when none is; a dungeon in lilac either way
        local nameColor
        if isDungeon then
            nameColor = hasTracked and DUNGEON_NAME or MUTED_DUNGEON_NAME
        else
            nameColor = hasTracked and COLORS.white or MUTED_ZONE_NAME
        end
        State.list:addImage(barLeft, y, barWidth, barHeight, ZONE_BAND, nil, nil, 0)

        -- At the right, in words: the ready ones in green, then how many quests
        local readyCount = 0
        for _, entry in ipairs(group.shownEntries) do
            readyCount = readyCount + (entry.isTurnIn and 1 or 0)
        end
        local questCount = #group.shownEntries
        local countText = ns.Lp(questCount, "%d quest", "%d quests")
        if readyCount > 0 then
            countText = "|cff7ce07c" .. ns.Lp(readyCount, "%d ready", "%d ready") .. "|r" .. DOT .. countText -- in green, as ready elsewhere
        end
        local textTop = middle - 6
        local countRight = barLeft + barWidth - 10
        if isHere then
            -- A gold edge down the left of the band's wood, as the settings and the chronicle mark the chosen section
            local woodTop, woodHeight = y + 3, math.floor(barHeight * BAND_WOOD_BOTTOM) - 3
            -- Drawn as pictures, over the band's own
            -- Inside the band, clear of the window's border, which covers the list's first pixels
            State.list:addImage(barLeft + HERE_EDGE_LEFT, woodTop, 3, woodHeight, PLAIN_TEXTURE, nil, HERE_EDGE, 2)
            State.list
                :addImage(barLeft + HERE_EDGE_LEFT + 3, woodTop, 2, woodHeight, PLAIN_TEXTURE, nil, HERE_EDGE, 2)
                :SetAlpha(0.3)
            -- And the game's gold glow along its lower edge, as the game's quest log lights the heading it means
            if List.hasGameArt("questlog-header-glow-yellow") then
                State.list:addImage(
                    barLeft,
                    y + math.floor(barHeight * BAND_WOOD_BOTTOM) - 10,
                    barWidth,
                    14,
                    List.HERE_GLOW,
                    nil,
                    nil,
                    1
                )
            end
        end
        -- In a group, the quests here someone could still take, offered all at once from a button at the right
        local shareable = Log.getShareableQuestIds(group.shownEntries)
        local shareWidth = 0
        if #shareable > 0 then
            shareWidth = SHARE_BUTTON_WIDTH + 6
            local shareLeft = countRight - SHARE_BUTTON_WIDTH
            local shareTop = middle - SHARE_BUTTON_HEIGHT / 2
            -- Only the game's group icon, as on a quest's row: the count and who gets what are in its tooltip
            State.list:addImage(shareLeft, shareTop, SHARE_BUTTON_WIDTH, SHARE_BUTTON_HEIGHT, SHARE_ICON, nil, nil, 6)
        end
        local _, countWidth = State.list:addText(countText, countRight - shareWidth - 120, textTop, {
            font = "GameFontHighlightSmall",
            color = COLORS.tan,
            width = 120,
            justify = "RIGHT",
            isSingleLine = true,
        })
        local rightEdge = countRight - shareWidth - math.min(countWidth, 120)

        -- In front: the game's + or -, as its campaign headings fold
        local foldSize = 18
        State.list:addImage(
            barLeft + 9,
            middle - foldSize / 2,
            foldSize,
            foldSize,
            isCollapsed and FOLD_SHUT or FOLD_OPEN,
            nil,
            nil,
            5
        )
        local nameLeft = barLeft + 9 + foldSize + 4
        -- After the name, so names always start in one place: what the heading is when it is not a plain zone
        -- (the map's gate for a dungeon, the category's own picture for cooking or a class), and "you are here"
        local icon, iconColor, texCoords
        if isDungeon then
            icon, iconColor = getDungeonIcon()
        elseif group.isCategory then
            icon, texCoords = ns.Database.getCategoryIcon(group.zoneId)
        end
        local maxNameWidth = rightEdge - nameLeft - 6 - (icon and DUNGEON_ICON_SIZE + 6 or 0)
        local nameTop = middle - 7
        local questIds = {}
        for _, entry in ipairs(group.shownEntries or {}) do
            questIds[#questIds + 1] = entry.questId
        end
        local bar = {
            zoneId = group.zoneId,
            zoneName = group.zoneName,
            isCategory = group.isCategory,
            nameColor = nameColor,
            isHere = isHere,
            shareable = shareable,
            questIds = questIds,
        }
        local _, nameWidth, name = State.list:addText(
            group.zoneName,
            nameLeft,
            nameTop,
            { font = "GameFontNormalMed2", color = nameColor, isSingleLine = true, width = maxNameWidth }
        )
        local afterLeft = nameLeft
            + math.min(type(nameWidth) == "number" and nameWidth or maxNameWidth, maxNameWidth)
            + 6
        if icon then
            State.list:addIcon(afterLeft, nameTop - 1, DUNGEON_ICON_SIZE, icon, iconColor, 6, texCoords)
        end
        bar.name = name
        State.list:addButton(
            barLeft,
            y,
            barWidth,
            barHeight,
            handleZoneBarClick,
            bar,
            showZoneBarHover,
            openZoneMenu,
            hideZoneBarHover
        )
        if #shareable > 0 then
            -- Over the bar's own button, so a click here shares rather than folds
            local share = { questIds = shareable, zoneName = group.zoneName }
            State.list:addButton(
                countRight - SHARE_BUTTON_WIDTH,
                middle - SHARE_BUTTON_HEIGHT / 2,
                SHARE_BUTTON_WIDTH,
                SHARE_BUTTON_HEIGHT,
                handleShareClick,
                share,
                showShareHover,
                nil,
                hideShareHover
            ).padSkip =
                true -- (a controller shares from the heading's menu, Y)
        end
        return y + barHeight + (isCollapsed and 0 or 4)
    end

    ---A dungeon on the Dungeons tab, drawn as the log draws a dungeon's heading, not as a quest: the dark band with
    ---the map's gate mark and the lilac name, its levels at the right in the colour of their difficulty, and under
    ---the band where its way in is and what it holds for the player. The open one has the gold edge down its left; a
    ---dungeon whose quests are all done is muted, and says so.
    ---@param row { name: string, levelText: string?, levelColor: number[]?, subText: string, isSelected: boolean, isDone: boolean, handleClick: function, data: any }
    ---@return number y Below the row
    function List.addDungeonRow(y, row)
        local width, barHeight = State.list.width, ZONE_BAR_HEIGHT
        local middle = y + math.floor(barHeight * BAND_WOOD_MIDDLE + 0.5)
        State.list:addImage(0, y, width, barHeight, ZONE_BAND, nil, nil, 0)
        if row.isSelected then
            local woodTop, woodHeight = y + 3, math.floor(barHeight * BAND_WOOD_BOTTOM) - 3
            State.list:addImage(HERE_EDGE_LEFT, woodTop, 3, woodHeight, PLAIN_TEXTURE, nil, HERE_EDGE, 2)
            State.list
                :addImage(HERE_EDGE_LEFT + 3, woodTop, 2, woodHeight, PLAIN_TEXTURE, nil, HERE_EDGE, 2)
                :SetAlpha(0.3)
        end
        local icon, iconColor = getDungeonIcon()
        State.list:addIcon(
            10,
            middle - DUNGEON_ICON_SIZE / 2,
            DUNGEON_ICON_SIZE,
            icon,
            row.isDone and MUTED_DUNGEON_NAME or iconColor,
            6
        )
        local rightEdge = width - 10
        if row.levelText then
            local _, levelWidth = State.list:addText(row.levelText, rightEdge - 90, middle - 6, {
                font = "GameFontHighlightSmall",
                color = row.isDone and MUTED_ZONE_NAME or row.levelColor or COLORS.tan,
                width = 90,
                justify = "RIGHT",
                isSingleLine = true,
            })
            rightEdge = rightEdge - math.min(type(levelWidth) == "number" and levelWidth or 90, 90) - 8
        end
        -- Its name and the line under the band where its quests' text starts, its mark over their icons
        local nameLeft = 10 + DUNGEON_ICON_SIZE + 6
        local nameColor = row.isDone and MUTED_DUNGEON_NAME or (row.isSelected and COLORS.white or DUNGEON_NAME)
        State.list:addText(
            row.name,
            nameLeft,
            middle - 7,
            { font = "GameFontNormalMed2", color = nameColor, isSingleLine = true, width = rightEdge - nameLeft }
        )
        local subTop = y + barHeight + 1
        local subText = row.isDone
                and ("|cff7ce07c" .. ns.L("All done") .. "|r" .. (row.subText ~= "" and (DOT .. row.subText) or ""))
            or row.subText
        State.list:addText(
            subText,
            nameLeft,
            subTop,
            { font = "GameFontHighlightSmall", color = COLORS.tan, isSingleLine = true, width = width - nameLeft - 10 }
        )
        local height = barHeight + 17
        State.list:addButton(0, y, width, height, row.handleClick, row.data)
        if row.isSelected then
            State.selectedRowTop, State.selectedRowBottom = y, y + height
        end
        return y + height + 4
    end
end

-- The game's group icon on a quest's row, only when sharing the quest would help: someone in the party could
-- take it but has not got it, and the game lets it be shared. A click offers it to the party.
local partyShare = { icon = { atlas = "friends-icon-friendsingroup" } }

---@return boolean canShare Sharing the quest would help: a party member who has not got it could take it (or
---nothing says they could not), and the game lets it be shared
function Log.canShareWithParty(questId)
    if not (IsInGroup and IsInGroup()) or not (C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questId)) then
        return false
    end
    for _, member in ipairs(ns.Party.getMembers(questId)) do
        if not member.isOnQuest and (member.status.state == "can" or member.status.state == "unknown") then
            return true
        end
    end
    return false
end

---@param entries { questId: number }[] A zone's quests in the log
---@return number[] questIds Those worth sharing (Log.canShareWithParty), in the list's order
function Log.getShareableQuestIds(entries)
    local questIds = {}
    if not (IsInGroup and IsInGroup()) then
        return questIds
    end
    for _, entry in ipairs(entries) do
        if Log.canShareWithParty(entry.questId) then
            questIds[#questIds + 1] = entry.questId
        end
    end
    return questIds
end

local SHARE_GAP_SECONDS = 1 -- the game offers one quest at a time; another sent at once replaces the first

---Offers several quests to the party, one after another, as the game's Share button would each.
function Log.shareQuests(questIds)
    for position, questId in ipairs(questIds) do
        if position == 1 or not (C_Timer and C_Timer.After) then
            Log.shareQuest(questId)
        else
            C_Timer.After((position - 1) * SHARE_GAP_SECONDS, function()
                if ns.QuestState.isInLog(questId) then
                    Log.shareQuest(questId)
                end
            end)
        end
    end
end

function partyShare.show(button, questId)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.L("Share with your party"), 1, 0.82, 0)
    for _, member in ipairs(ns.Party.getMembers(questId)) do
        if not member.isOnQuest then
            ns.Party.addMemberToTooltip(GameTooltip, member)
        end
    end
    GameTooltip:AddLine(ns.L("Click to share"), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

function partyShare.hide()
    GameTooltip:Hide()
end

function partyShare.share(questId)
    Log.shareQuest(questId)
end

---One quest in the list.
---@param line { handleClick: fun(questId: number)?, indent: number?, title: string, level: number, subText: string?, color: number[]?, isReady: boolean?, icon: string?, itemTexture: any, canShareWithParty: boolean?, chainText: string?, warnings: string[]?, number: number?, progress: number?, isFocused: boolean?, canFocus: boolean? }
---@return number y Below the row
local function addListQuest(y, questId, line)
    local width = State.list.width
    local warnings = line.warnings or {}
    local hasSecondLine = line.subText ~= nil or line.profitText ~= nil
    local height = 24 + (hasSecondLine and 15 or 0) + #warnings * 15
    local isSelected = selectedQuestIds[State.selectedTab] == questId
        and not (State.selectedTab == TAB_QUESTS and State.selectedLogZoneId)
    if isSelected then
        State.selectedRowTop, State.selectedRowBottom = y, y + height
    end
    if isSelected then
        -- The game's own glow round the chosen quest, as its quest log shows it; a gold box where the client lacks it
        if List.hasGameArt("questlog-quest-glow-yellow") then
            State.list:addImage(2, y, width - 4, height, List.SELECTED_GLOW):SetDrawLayer("BORDER", 2) -- under the row's text
        else
            State.list:addRect(2, y, width - 4, height, SELECTED_EDGE)
            State.list:addRect(3, y + 1, width - 6, height - 2, SELECTED_FILL, 1)
        end
    end
    if line.isFocused then
        State.list:addRect(width - 5, y, 3, height, COLORS.gold, 2) -- the tracker's active quest: a gold bar down the row's right edge
    end
    local indent = line.indent or 0
    local left, buttonLeft = 10 + indent, 2
    if line.isIconSpaceKept and not line.icon then
        left = 30 + indent -- no icon, but its text lines up with the rows that have one
    elseif line.icon then
        local icon = State.list:addIcon(8 + indent, y + 4, 16, line.icon)
        if line.iconColour then
            -- A quest's "!" or "?" in its kind's colour, as on the map (line.isTurnInIcon: the "?")
            ns.MapMarks.dressQuestIcon(icon, line.iconColour, line.isTurnInIcon)
        end
        left = 30 + indent
    elseif line.isTracked ~= nil then
        -- The quest's mark, as on the map, is also how it is tracked: a tracked quest shows its coin with what
        -- it wants, an untracked one an empty dashed ring. Clicking it tracks or untracks.
        local ringLeft, ringTop, ringSize = 6, y + 2, 20
        if line.isTracked then
            -- The quest's mark exactly as on the map
            State.list:addMark(ringLeft, ringTop, ringSize, {
                kind = line.isReady and "turnIn" or "objective",
                questId = questId,
                number = line.number,
                glyph = ns.MapMarks.getQuestGlyph(questId),
                progress = line.isReady and 1 or line.progress or 0,
                isFocused = false,
                lines = {},
            })
        else
            State.list:addIcon(ringLeft, ringTop, ringSize, MEDIA .. "RingDashed", { 0.42, 0.38, 0.28 })
        end
        -- Its click area is a square just round the mark, the same whether tracked or not; the rest of the row
        -- below it selects the quest, as the row does
        local trackButton =
            State.list:addButton(ringLeft - 3, ringTop - 3, ringSize + 6, ringSize + 6, toggleTracked, questId)
        trackButton:SetFrameLevel((trackButton:GetFrameLevel() or 1) + 2) -- over the row's own button
        trackButton.padSkip = true -- with a controller, X tracks the quest (Gamepad.lua)
        left = 32
    end
    local right = width - 10
    if line.itemTexture then
        right = right - 16
        State.list:addIcon(right, y + 4, 16, line.itemTexture)
        right = right - 4
    end
    if line.chainText then
        local _, textWidth = State.list:addText(
            line.chainText,
            right - 30,
            y + 7,
            { font = "GameFontHighlightSmall", color = COLORS.tan, width = 30, justify = "RIGHT", isSingleLine = true }
        )
        right = right - math.min(textWidth, 30) - 16
        State.list:addIcon(right, y + 6, 12, CHAIN_ICON, COLORS.tan)
        right = right - 4
    end
    -- Before the chain step: the offer to share it with the party, when that would help
    if line.canShareWithParty then
        right = right - 16
        State.list:addImage(right, y + 4, 16, 16, partyShare.icon, nil, nil, 1)
        local shareButton = State.list:addButton(
            right - 2,
            y + 2,
            20,
            20,
            partyShare.share,
            questId,
            partyShare.show,
            nil,
            partyShare.hide
        )
        shareButton:SetFrameLevel((shareButton:GetFrameLevel() or 1) + 2) -- over the row's own button, which takes the rest
        shareButton.padSkip = true -- the gamepad shares from the row's menu (Y)
        right = right - 4
    end
    -- The narration, only while it plays, waits paused or waits in the queue (with its place): click plays or
    -- stops it, right click takes it off the queue
    local voiceState, voicePosition = ns.QuestText.getVoiceState(questId)
    if voiceState and voiceState ~= "idle" then
        if voiceState == "queued" then
            local _, numberWidth = State.list:addText(tostring(voicePosition or ""), right - 14, y + 7, {
                font = "GameFontHighlightSmall",
                color = ns.QuestText.VOICE_COLORS.queued,
                width = 14,
                justify = "RIGHT",
                isSingleLine = true,
            })
            right = right - math.min(numberWidth, 14) - 1
        end
        right = right - 14
        State.list:addIcon(right, y + 5, 14, ns.QuestText.VOICE_ICON, ns.QuestText.VOICE_COLORS[voiceState])
        local voiceButton = State.list:addButton(
            right - 3,
            y + 2,
            20,
            20,
            ns.QuestText.toggleVoice,
            questId,
            function(button)
                ns.QuestText.showVoiceTooltip(button, questId)
            end,
            ns.QuestText.toggleVoiceQueue,
            function()
                GameTooltip:Hide()
            end
        )
        voiceButton:SetFrameLevel((voiceButton:GetFrameLevel() or 1) + 2) -- over the row's own button
        right = right - 4
    end
    State.list:addText(
        ns.Widgets.formatQuestTitle(line.level, line.title, ns.QuestState.getGroupInfo(questId)),
        left,
        y + 5,
        {
            font = "GameFontNormal",
            width = right - left - 4,
            isSingleLine = true,
            color = line.color or ns.Widgets.getDifficultyColor(line.level), -- the glow alone marks the chosen quest
        }
    )
    local textY = y + 21
    local subRight = width - 10
    if line.profitText then
        -- What the quest is worth, quietly at the right of the second line
        local _, profitWidth = State.list:addText(line.profitText, width - 10 - 110, textY, {
            font = "GameFontHighlightSmall",
            color = COLORS.tan,
            width = 110,
            justify = "RIGHT",
            isSingleLine = true,
        })
        subRight = width - 10 - math.min(profitWidth, 110) - 8
    end
    if line.subText then
        local subLeft = left
        if line.isReady then
            -- The tick starts the green line it belongs to: the game's yellow check, as its quest log ticks a quest
            if List.hasGameArt("questlog-icon-checkmark-yellow") then
                State.list:addImage(left, textY, 13, 11, List.READY_CHECK)
            else
                State.list:addIcon(left, textY, 11, READY_ICON)
            end
            subLeft = left + 16
        end
        State.list:addText(line.subText, subLeft, textY, {
            font = "GameFontHighlightSmall",
            color = line.isReady and COLORS.green or COLORS.tan,
            width = subRight - subLeft,
            isSingleLine = true,
        })
    end
    if hasSecondLine then
        textY = textY + 15
    end
    for _, warning in ipairs(warnings) do
        State.list:addText(
            warning,
            left,
            textY,
            { font = "GameFontHighlightSmall", color = COLORS.amber, width = width - left - 10, isSingleLine = true }
        )
        textY = textY + 15
    end
    -- A click opens the quest on the page and highlights it on the map, which turns to it; shift-click links it
    -- in chat; a right click opens its menu (focus, track, share to chat or the party, abandon)
    local rowButton = State.list:addButton(
        buttonLeft,
        y,
        width - 2 - buttonLeft,
        height,
        line.handleClick or selectQuest,
        questId,
        handleQuestEnter,
        line.canFocus and Log.openLogQuestMenu
            or (questId and not line.handleClick and Log.openAvailableQuestMenu)
            or nil,
        handleQuestLeave
    )
    rowButton.isQuestRow = questId ~= nil
    return y + height + 2
end

---------------------------------------------------------------------------------------------------------------
-- What the Spoilers choices let the window name (ns.Spoilers). Fields, not locals: the file keeps its local names
-- few. In Guide each answers at once with "everything", and the tabs ask once a drawing, not once a row.

---@return string choice Which quests to pick up the window names: "all", "met" (givers the player met) or "none"
function List.getPickupChoice()
    return ns.Spoilers.isActive() and ns.Spoilers.getChoice("pickup") or "all"
end

---@return boolean isShown The Available tab is there: the player uses this addon's quests to pick up, and their
---Spoilers choice names some
function List.isAvailableTabShown()
    return ns.settings.shouldUseAvailableQuests == true and List.getPickupChoice() ~= "none"
end

---@return boolean isShown The Dungeons tab is there: the Spoilers choice tells of dungeons
function List.isDungeonsTabShown()
    return not ns.Spoilers.isActive() or ns.Spoilers.getChoice("dungeons") ~= "hidden"
end

---@param hasOwnQuests boolean? The player has quests of it in the log, or has done some there: a dungeon their own
---quests lead into is one they know of
---@return boolean isShown A dungeon may be named: dungeons shown; or "entered" and the player was inside, or has quests of it
function List.isDungeonShown(dungeonId, hasOwnQuests)
    if not ns.Spoilers.isActive() then
        return true
    end
    local choice = ns.Spoilers.getChoice("dungeons")
    if choice == "entered" then
        return hasOwnQuests == true or ns.Spoilers.hasEntered(dungeonId)
    end
    return choice == "shown"
end

---@return boolean isKnown A dungeon may be named where only its id is at hand (List.isDungeonShown): with the choice
---"entered", one not entered counts as known when the player has quests of it in the log, or done
function List.isDungeonKnown(dungeonId)
    if
        not ns.Spoilers.isActive()
        or ns.Spoilers.getChoice("dungeons") ~= "entered"
        or ns.Spoilers.hasEntered(dungeonId)
    then
        return List.isDungeonShown(dungeonId)
    end
    local run = ns.Availability.getDungeonRun(dungeonId)
    return #run.inLog > 0 or (run.doneCount or 0) > 0
end

---@return boolean isFound A quest to pick up the player has come across, for the pickup choice "met": its giver
---met; one from an item once the item is had or seen dropping; one from an object once its spot on the map is
---explored (an object cannot be met); one only the game knows stays, as the game's own "!" shows it
function List.isPickupFound(quest)
    if quest.startType == "item" then
        return quest.isItemInBags == true
            or (
                quest.itemId ~= nil
                and (ns.QuestState.getItemCount(quest.itemId) > 0 or ns.Spoilers.hasSeenDrop(quest.itemId))
            )
    elseif quest.startType == "object" then
        local place = quest.nearestPlace or (quest.places or {})[1]
        return place ~= nil
            and place.x >= 0
            and ns.Spoilers.isExplored(place.mapZoneId or place.groupZoneId or place.zoneId, place.x, place.y)
    end
    local npcIds = ns.Location.getStarterNpcIds(quest.questId)
    if #npcIds == 0 then
        return quest.isFromGame == true
    end
    for _, npcId in ipairs(npcIds) do
        if ns.Spoilers.hasMet(npcId) then
            return true
        end
    end
    return false
end

---@param choice string List.getPickupChoice(), asked once by the drawing
---@return table[] quests Those of the quests to pick up the choice lets be named; the same list when it names all
function List.keepToPickUp(quests, choice)
    if choice == "all" then
        return quests
    end
    local kept = {}
    for _, quest in ipairs(choice == "met" and quests or {}) do
        if List.isPickupFound(quest) then
            kept[#kept + 1] = quest
        end
    end
    return kept
end

---@return table run A dungeon's run with only the quests to pick up the choice lets be named (those in the log and
---those done stay); the same run when it names all
function List.keepRunToPickUp(run, choice)
    if choice == "all" then
        return run
    end
    local kept = {}
    for key, value in pairs(run) do
        kept[key] = value
    end
    for _, key in ipairs({ "pickUp", "foundInside", "behindLeadIn", "notYet" }) do
        kept[key] = List.keepToPickUp(run[key] or {}, choice)
    end
    return kept
end

-- Shared with the other parts of the window
List.addListHeading = addListHeading
List.addListQuest = addListQuest
