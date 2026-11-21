local addonName, ns = ... -- the addon's folder, which its pictures are read from

-- The tracker window: zone headers, the active quest in full, the other quests in short.
local Tracker = {}
ns.Tracker = Tracker

local WIDTH = 260 -- as it starts; the player drags it wider or narrower (settings.trackerWidth)
local MIN_WIDTH, MAX_WIDTH = 200, 560
local MIN_SCALE, MAX_SCALE = 0.7, 1.6
local INDENT = 23 -- a quest's lines start under its title text, which begins after the ring
local REFRESH_DELAY_SECONDS = 0.1
local DEFAULT_POSITION = { "TOPRIGHT", "TOPRIGHT", -90, -260 }

local GOLD = { 1, 0.82, 0 }
local TAN = { 0.85, 0.81, 0.66 }
local WHITE = { 1, 1, 1 }
local GREY = { 0.66, 0.66, 0.66 }
local GREEN = { 0.49, 0.88, 0.49 }
local AMBER = { 1, 0.69, 0.25 }
local RED = { 1, 0.3, 0.25 }

local CHAIN_ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\Chain"
local READY_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local MARK_SIZE = ns.Widgets.MARK_SIZE -- a map mark's own size; the tracker's is that, scaled down
local RING_SIZE = 18 -- the quest's mark before its title
local BOX_SIZE = 12
local BADGE_TEXT = { 0.72, 0.68, 0.55 }

local HEADER_HEIGHT = 28
local HEADER_BAND_ALPHA = 0.65
local SIDE_MARGIN = 8 -- room at the sides of the scrolling area for the active quest's band
local BOTTOM_MARGIN = 110 -- kept clear at the bottom of the screen, where the action bars are
local MIN_HEIGHT = 160
local SCROLL_STEP = 40

local frame, scrollFrame, content
local scrollOffset = 0
local currentEntry -- the quest whose rows are being added; every one of them reacts to the mouse
local rows, usedRowCount = {}, 0
local cursor = 0
local activeQuestId -- the quest shown in full right now
local isRefreshQueued = false

local function setColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3])
end

local function getDifficultyColor(level)
    local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if color then
        return { color.r, color.g, color.b }
    end
    return GOLD
end

local function showTooltip(row)
    local entry = row.entry
    if not entry then
        return
    end
    if row.isZonesLine then
        -- The line of zones: every one of them, and a click for the next on the map
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        ns.MapDock.addZonesToTooltip(GameTooltip, entry)
        GameTooltip:Show()
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    ns.QuestTooltip.watch(GameTooltip, row, showTooltip, row) -- Shift down or up: filled again
    ns.QuestTooltip.addTitle(GameTooltip, string.format("[%d] %s", entry.level, entry.title), entry.questId)
    for _, objective in ipairs(entry.objectives) do
        local status = objective.required > 1 and (objective.fulfilled .. "/" .. objective.required) or objective.isFinished and ns.L("done") or ""
        GameTooltip:AddDoubleLine((objective.shownLabel or objective.label), status, 1, 1, 1, 1, 1, 1)
    end
    if entry.isTurnIn then
        GameTooltip:AddLine(ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver")), GREEN[1], GREEN[2], GREEN[3])
    end
    -- With Shift held: what it asks, the rewards, where it is handed in (its objectives are listed above already)
    ns.QuestTooltip.addDetails(GameTooltip, entry.questId, { hasObjectives = true, hasTurnIn = entry.isTurnIn })
    -- Kills for the items that drop: the chance, kills against the kills expected, and about what the rest takes
    local isKillsHeadingShown = false
    for index, objective in ipairs(ns.settings.shouldCountKills and not entry.isTurnIn and entry.objectives or {}) do
        local progress = not objective.isFinished and objective.type == "item" and ns.KillCounter.getProgress(entry.questId, index, objective)
        if progress then
            if not isKillsHeadingShown then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ns.L("Kills for drops"), 1, 0.82, 0)
                isKillsHeadingShown = true
            end
            local chanceText = ns.Drops.formatChance(progress.chance)
            local isUnlucky = progress.isUnlucky
            local killsText = ns.KillCounter.formatKills(progress, ", ")
            local red, green, blue = 1, 1, 1
            if progress.kills > 0 then
                red, green, blue = isUnlucky and 1 or 0.5, isUnlucky and 0.48 or 0.88, isUnlucky and 0.35 or 0.5
            end
            GameTooltip:AddDoubleLine((objective.shownLabel or objective.label) .. " (" .. chanceText .. ")", killsText, 1, 1, 1, red, green, blue)
            if (progress.earlierDrops or 0) > 0 then
                GameTooltip:AddLine(ns.Lp(progress.earlierDrops, "%d collected before counting started", "%d collected before counting started"), GREY[1], GREY[2], GREY[3])
            end
            local remaining = math.floor(progress.remaining + 0.5)
            local restText = (progress.sharerCount or 1) > 1
                and ns.Lp(remaining, "About %d more kill for the rest, the loot shared by %d", "About %d more kills for the rest, the loot shared by %d", progress.sharerCount)
                or ns.Lp(remaining, "About %d more kill for the rest", "About %d more kills for the rest")
            GameTooltip:AddLine(restText, GREY[1], GREY[2], GREY[3])
        end
    end
    if entry.chainIndex then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ns.L("Quest chain, step %d of %d", entry.chainIndex, entry.chainTotal), 1, 0.82, 0)
        for position, chainQuestId in ipairs(ns.Chain.getQuestIds(entry.questId)) do
            local name = ns.QuestText.getQuestName(chainQuestId) or ns.L("Quest %s", chainQuestId)
            local line = string.format("[%d] %s", ns.Database.getQuestField(chainQuestId, "questLevel") or 0, name)
            if position < entry.chainIndex then
                GameTooltip:AddDoubleLine(line, ns.L("done"), GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
            elseif position == entry.chainIndex then
                GameTooltip:AddDoubleLine(line, ns.L("this quest"), 1, 1, 1, TAN[1], TAN[2], TAN[3])
            else
                GameTooltip:AddLine(line, TAN[1], TAN[2], TAN[3])
            end
        end
    end
    if (entry.unlocatedCount or 0) > 0 then
        local text = entry.unlocatedCount == 1 and ns.L("The database has no location for one objective, so the map cannot show where to go.")
            or ns.Lp(entry.unlocatedCount, "The database has no location for %d objective, so the map cannot show where to go.", "The database has no location for %d objectives, so the map cannot show where to go.")
        GameTooltip:AddLine(text, TAN[1], TAN[2], TAN[3], true)
    end
    ns.Party.addProgressToTooltip(GameTooltip, entry.questId, entry.objectives)
    -- The same clicks as on a quest in the quest list, on its page and on its mark on the map
    local clickHint = entry.questId == activeQuestId
        and "Click to open it in the quest log, ctrl-click to stop focusing, shift-click to link it in chat, right-click for more"
        or "Click to open it in the quest log, ctrl-click to focus it, shift-click to link it in chat, right-click for more"
    GameTooltip:AddLine(ns.L(clickHint), GREY[1], GREY[2], GREY[3], true)
    ns.QuestTooltip.addHint(GameTooltip)
    GameTooltip:Show()
end

---Opens a quest's page in the quest log, as a click on it in the quest list does, and turns the map to where it
---is. With the game's own quest log kept (the setting), that one opens on the quest.
---@param entry table The quest as the tracker shows it (Model's entry)
---@return boolean isOpened False when the game would not open the map (it opens none for an addon in a fight)
function Tracker.openInLog(entry)
    local questId = entry.questId
    if not ns.settings.shouldReplaceQuestLog and QuestMapFrame_OpenToQuestDetails then
        return pcall(QuestMapFrame_OpenToQuestDetails, questId) == true
    end
    ns.MapDock.open()
    ns.Log.selectQuest(questId)
    ns.MapDock.showQuest(entry)
    return WorldMapFrame ~= nil and WorldMapFrame:IsShown() == true
end

---Puts a quest in focus, or takes the focus off the one that has it.
local function toggleFocus(entry)
    local isFocusing = entry.questId ~= activeQuestId
    ns.Focus.set(isFocusing and entry.questId or nil)
    if isFocusing and WorldMapFrame and WorldMapFrame:IsShown() then
        ns.MapDock.showQuest(entry) -- an open map turns to the quest; a closed one stays closed
    end
end

---A quest's actions on a right click, in the game's own menu.
---@param entry table The quest as the tracker shows it (Model's entry)
---@param owner table The frame the menu opens at (the quest's row)
function Tracker.openQuestMenu(entry, owner)
    if not entry or not MenuUtil or not MenuUtil.CreateContextMenu then
        return
    end
    local questId = entry.questId
    MenuUtil.CreateContextMenu(owner, function(_, root)
        ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
        root:CreateTitle(entry.title)
        local isActive = questId == activeQuestId
        root:CreateButton(ns.L(isActive and "Unfocus" or "Focus"), function()
            ns.Focus.set(not isActive and questId or nil)
        end)
        if ns.Waypoints.getQuestPlace(entry) then
            root:CreateButton(ns.L(ns.Waypoints.hasTomTom() and "Set a TomTom waypoint" or "Set a waypoint"), function()
                ns.Waypoints.set(entry)
            end)
        end
        root:CreateButton(ns.L("Share to chat"), function() ns.QuestState.linkInChat(questId) end)
        root:CreateButton(ns.L("Open in the quest log"), function() Tracker.openInLog(entry) end)
        root:CreateButton(ns.L("Untrack"), function()
            C_QuestLog.RemoveQuestWatch(questId)
            ns.QuestState.forgetWatches()
            ns.Focus.handleQuestGone(questId) -- the windows let go of it, and the focus if it was it
            Tracker.refresh()
        end)
        local share = root:CreateButton(ns.L("Share with the party"), function() ns.Log.shareQuest(questId) end)
        local canShare = C_QuestLog.IsPushableQuest and C_QuestLog.IsPushableQuest(questId) and IsInGroup and IsInGroup()
        if not canShare and share.SetEnabled then
            share:SetEnabled(false)
        end
        ns.QuestText.addVoiceMenuItems(root, questId) -- a translation addon's narration, when the quest has one
        root:CreateDivider()
        root:CreateButton("|cffff5040" .. ns.L("Abandon") .. "|r", function() ns.Log.abandonQuest(questId) end)
    end)
end

---A zone heading's actions on a right click: untracking all its quests at once, as on the game's tracker.
local function openZoneMenu(row)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        return
    end
    MenuUtil.CreateContextMenu(row, function(_, root)
        ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
        root:CreateTitle(row.zoneName)
        ns.Log.addTrackMenuItems(root, row.zoneQuestIds)
    end)
end

local function handleRowClick(row, mouseButton)
    if mouseButton == "RightButton" then
        if row.zoneId then
            openZoneMenu(row)
            return
        end
        Tracker.openQuestMenu(row.entry, row)
        return
    end
    if row.isZonesLine then
        ns.MapDock.showNextQuestZone(row.entry)
        -- The tooltip follows: its arrow moves to the zone now on the map, now and after the tracker redraws
        local function refreshTooltip()
            if GameTooltip:IsShown() and GameTooltip:GetOwner() == row and row.isZonesLine then
                showTooltip(row)
            end
        end
        refreshTooltip()
        if C_Timer then
            C_Timer.After(0, refreshTooltip)
        end
        return
    end
    if row.zoneId then
        ns.settings.collapsedZones[row.zoneId] = not row.isCollapsed
    elseif row.entry and ns.QuestState.isLinkClick() then
        ns.QuestState.linkInChat(row.entry.questId) -- shift-click (untracking is in the right-click menu)
    elseif row.entry and ns.QuestState.isFocusClick() then
        toggleFocus(row.entry) -- ctrl-click; on the focused quest it takes the focus off
        return
    elseif row.entry then
        -- A plain click opens the quest in the quest log. Where the game opens no map for an addon (in a fight),
        -- the click still does what can be done from here: the quest comes into focus
        if not Tracker.openInLog(row.entry) and row.entry.questId ~= activeQuestId then
            toggleFocus(row.entry)
        end
        return
    end
    Tracker.refresh()
end

---@return number width The tracker's width, as the player dragged it, kept within reason
local function getWidth()
    local width = tonumber(ns.settings.trackerWidth) or WIDTH
    return math.max(MIN_WIDTH, math.min(MAX_WIDTH, width))
end
Tracker.getWidth = getWidth

---@return number scale The tracker's size, text included
local function getScale()
    local scale = tonumber(ns.settings.trackerScale) or 1
    return math.max(MIN_SCALE, math.min(MAX_SCALE, scale))
end

-- A row's parts remember what they were last given (Widgets.remember), and a row is put on them in one go once
-- whoever asked for it has said what it shows (flushRow): the tracker drawn again with nothing changed, as it is
-- every few yards walked, asks nothing of the game, and a kill counted changes the one count.
local remember = ns.Widgets.remember

local function createRow()
    local row = remember(CreateFrame("Button", nil, content))
    row.want = {} -- what the row is to show, gathered as it is filled (addRow), then put on its parts (flushRow)
    row:SetWidth(getWidth())
    row.leftText = remember(ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlightSmall"))
    row.leftText:SetJustifyH("LEFT")
    row.leftText:SetWordWrap(false)
    row.rightText = remember(ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlightSmall"))
    row.rightText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.portraits = {} -- the party's faces, under the focused quest's title
    row.chainIcon = remember(row:CreateTexture(nil, "ARTWORK"))
    row.chainIcon:SetTexture(CHAIN_ICON)
    row.chainIcon:SetVertexColor(TAN[1], TAN[2], TAN[3])
    row.chainIcon:SetSize(12, 12)
    row.chainIcon:SetPoint("RIGHT", row.rightText, "LEFT", -3, 0)
    -- The narration's speaker after the title, while a translation addon plays the quest's narration
    row.voiceIcon = remember(row:CreateTexture(nil, "ARTWORK"))
    row.voiceIcon:SetTexture(ns.QuestText.VOICE_ICON)
    row.voiceIcon:SetSize(12, 12)
    local playing = ns.QuestText.VOICE_COLORS.playing
    row.voiceIcon:SetVertexColor(playing[1], playing[2], playing[3])
    -- Checkbox of a one-off objective: Forever's minimal box, with the tracker's green tick once done
    row.box = remember(row:CreateTexture(nil, "BORDER"))
    row.box:SetSize(BOX_SIZE, BOX_SIZE)
    row.box:SetPoint("LEFT", row, "LEFT", INDENT, 0)
    row.box:SetAtlas("checkbox-minimal")
    row.tick = remember(row:CreateTexture(nil, "OVERLAY"))
    row.tick:SetTexture(READY_ICON)
    row.tick:SetSize(BOX_SIZE + 2, BOX_SIZE + 2)
    row.tick:SetPoint("CENTER", row.box, "CENTER", 1, 1)
    -- The quest's mark before the title, exactly as the map draws it in the look chosen in the settings. It
    -- takes no clicks; the row handles them.
    row.mark = ns.MapMarks.createMarkButton(row)
    row.mark:EnableMouse(false)
    row.mark:SetScale(RING_SIZE / MARK_SIZE)
    row.mark:SetPoint("CENTER", row, "LEFT", (RING_SIZE / 2) / (RING_SIZE / MARK_SIZE), 0)
    row.mark:Hide()
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", handleRowClick)
    row:SetScript("OnEnter", showTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local openRow -- the row being filled: put on its parts when the next one is asked for, or the drawing ends

---Puts the row being filled on its parts, each given only what differs from what it has.
local function flushRow()
    local row = openRow
    if not row then
        return
    end
    openRow = nil
    local want = row.want
    local place = ns.Widgets.place
    if row.isMouseOn ~= want.mouse then
        row.isMouseOn = want.mouse
        row:EnableMouse(want.mouse)
    end
    row:SetWidth(getWidth()) -- the width may have been dragged since the row was made
    row:SetHeight(want.height)
    place(row, "TOPLEFT", content, "TOPLEFT", SIDE_MARGIN, -want.top)
    -- The narration's speaker ends at the chain's icon, or at the right text
    local voiceTo = want.voice and (want.chain and row.chainIcon or row.rightText) or nil
    if voiceTo then
        place(row.voiceIcon, "RIGHT", voiceTo, "LEFT", want.chain and -4 or -2, 0)
    end
    row.voiceIcon:SetShown(voiceTo ~= nil)
    row.chainIcon:SetAlpha(want.chain and 0.7 or 1)
    row.chainIcon:SetShown(want.chain)
    -- The left text runs from its indent to whatever stands right of it: the speaker, the chain's icon, the right
    -- text. Its two points are set again only when either differs from what it has.
    local endsAt = voiceTo and row.voiceIcon or want.chain and row.chainIcon or row.rightText
    local endGap = voiceTo and -4 or -6
    if row.leftIndent ~= want.indent or row.leftEndsAt ~= endsAt or row.leftEndGap ~= endGap then
        row.leftIndent, row.leftEndsAt, row.leftEndGap = want.indent, endsAt, endGap
        row.leftText:ClearAllPoints()
        row.leftText:SetPoint("LEFT", row, "LEFT", want.indent, 0)
        row.leftText:SetPoint("RIGHT", endsAt, "LEFT", endGap, 0)
    end
    -- A text keeps the font and the colour it had unless the row says another (as it always did)
    if want.leftFont then
        ns.Widgets.setTextFont(row.leftText, want.leftFont)
    end
    row.leftText:SetText(want.leftText)
    if want.leftColor then
        setColor(row.leftText, want.leftColor)
    end
    if want.rightFont then
        ns.Widgets.setTextFont(row.rightText, want.rightFont)
    end
    row.rightText:SetText(want.rightText)
    if want.rightColor then
        setColor(row.rightText, want.rightColor)
    end
    row.mark:SetShown(want.mark)
    row.box:SetShown(want.box)
    row.tick:SetShown(want.tick)
    for index = want.faces + 1, #row.portraits do
        row.portraits[index]:Hide()
    end
    row:Show()
end

---Next row from the pool, placed below the previous one, showing nothing until whoever asked says what, in
---row.want: its texts (leftText, rightText), their fonts and colours (kept as they were when not said), and which
---of its parts show (mark, box, tick, chain, voice, and faces: how many of the party's).
local function addRow(height, indent)
    flushRow()
    usedRowCount = usedRowCount + 1
    local row = rows[usedRowCount]
    if not row then
        row = createRow()
        rows[usedRowCount] = row
    end
    row.entry, row.zoneId, row.isCollapsed, row.isZonesLine = currentEntry, nil, nil, false
    row.zoneName, row.zoneQuestIds = nil, nil
    local want = row.want
    want.height, want.top, want.indent = height, cursor, indent or 0
    want.leftText, want.rightText = "", ""
    want.leftFont, want.rightFont, want.leftColor, want.rightColor = nil, nil, nil, nil
    want.mark, want.box, want.tick, want.chain, want.voice = false, false, false, false, false
    want.faces = 0
    want.mouse = currentEntry ~= nil
    openRow = row
    cursor = cursor + height
    return row
end

local function addGap(height)
    cursor = cursor + height
end

local function addZoneRow(group)
    local row = addRow(16)
    local color = group.isCurrent and GOLD or TAN
    row.zoneId, row.isCollapsed = group.zoneId, group.isCollapsed
    row.zoneName, row.zoneQuestIds = group.zoneName, {}
    for _, entry in ipairs(group.entries) do
        row.zoneQuestIds[#row.zoneQuestIds + 1] = entry.questId
    end
    -- The zone's name plain, as the game's tracker writes its sections
    row.want.leftFont, row.want.leftColor = ns.Widgets.getFont("GameFontNormalSmall"), color
    row.want.leftText = (group.isCollapsed and "+ " or "") .. group.zoneName
    row.want.rightFont, row.want.rightColor = ns.Widgets.getFont("GameFontNormalSmall"), TAN
    row.want.rightText = #group.entries
    row.want.mouse = true
end

local FACE_SIZE = 18 -- a party member's face; its ring goes round it
local FACE_GAP = 6

---The party under the quest's title: each member's face in a ring that fills with their progress, a badge when
---not on it; hovering one gives their name and counts, or why not.
local function addPartyFaces(members)
    local size = ns.Widgets.getPortraitSize(FACE_SIZE)
    local row = addRow(size + 6, INDENT)
    row.want.faces = #members
    for index, member in ipairs(members) do
        local portrait = row.portraits[index]
        if not portrait then
            portrait = ns.Widgets.createPortrait(row)
            row.portraits[index] = portrait
        end
        ns.Widgets.setPortrait(portrait, member, FACE_SIZE)
        portrait:ClearAllPoints()
        portrait:SetPoint("LEFT", row, "LEFT", INDENT - 2 + (index - 1) * (size + FACE_GAP), 0)
    end
end

---One objective's line: its count leading, or a checkbox for a one-off, and how often an item still to drop does.
local function addObjectiveRow(entry, index, objective)
    local row = addRow(15, INDENT)
    row.want.leftFont, row.want.rightFont = ns.Widgets.getFont("GameFontHighlightSmall"), ns.Widgets.getFont("GameFontHighlightSmall")
    local text = (objective.shownLabel or objective.label)
    if objective.required > 1 then
        -- The count leads the line, as in the game's own tracker, so the right column stays empty
        local count = objective.fulfilled .. "/" .. objective.required
        text = (objective.isFinished and count or ("|cffffd100" .. count .. "|r")) .. " " .. (objective.shownLabel or objective.label)
    else
        -- A one-off objective is a checkbox, so the right column holds only real counts
        row.want.box, row.want.tick = true, objective.isFinished and true or false
        row.want.indent = INDENT + BOX_SIZE + 6
    end
    -- An item still to drop says how often it does, quietly after its name
    local chance = not objective.isFinished and objective.type == "item" and ns.KillCounter.getDropChance(entry.questId, index)
    if chance then
        text = text .. " |cff8a8a8a(" .. ns.Drops.formatChance(chance) .. ")|r"
    end
    row.want.leftText = text
    row.want.leftColor = objective.isFinished and GREY or WHITE
    row.want.rightColor = objective.isFinished and GREY or WHITE
end

local function addObjectiveRows(entry)
    for index, objective in ipairs(entry.objectives) do
        -- Done objectives can be left out, the player's choice: only what is still to do shows
        if not (objective.isFinished and ns.settings.shouldHideDoneObjectives) then
            addObjectiveRow(entry, index, objective)
        end
    end
end

local function addInfoRow(text, color)
    local row = addRow(15, INDENT)
    row.want.leftFont, row.want.leftText, row.want.leftColor = ns.Widgets.getFont("GameFontHighlightSmall"), text, color
    return row
end

local URGENT_SECONDS = 60
local TICK_YARDS = 8 -- how far the player walks before the tracker is drawn again for it (the nearest places)
local hasTimer = false -- a quest shown counts down its time left: drawn again every second
local refreshedAt -- { uiMapId, north, west }: where the player was when it was last drawn
local FLASH_SECONDS = 1.4

---"12:34", or "1:02:03" past the hour.
local function formatTime(seconds)
    seconds = math.floor(seconds)
    local hours, minutes = math.floor(seconds / 3600), math.floor(seconds / 60) % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, seconds % 60)
    end
    return string.format("%d:%02d", minutes, seconds % 60)
end

---@return number top, number bottom Vertical extent of the quest, for the active quest's band
local function addQuestRows(entry, isActive)
    local top = cursor
    currentEntry = entry
    local row = addRow(17)
    row.want.leftFont = ns.Widgets.getFont("GameFontNormal")
    row.want.leftText = ns.Widgets.formatQuestTitle(entry.level, entry.title, ns.QuestState.getGroupInfo(entry.questId))
    row.want.leftColor = isActive and WHITE or getDifficultyColor(entry.level)
    row.want.rightFont, row.want.rightColor = ns.Widgets.getFont("GameFontHighlightSmall"), TAN
    if entry.number then
        ns.MapMarks.applyMarkLook(row.mark, {
            kind = entry.isTurnIn and "turnIn" or "objective", questId = entry.questId, number = entry.number,
            glyph = ns.MapMarks.getQuestGlyph(entry.questId, entry.objectives),
            progress = entry.isTurnIn and 1 or ns.MapMarks.getProgress(entry), isFocused = false, lines = {},
        }, (row:GetFrameLevel() or 1) + 1)
        row.want.mark, row.want.indent = true, INDENT
    end
    -- The party is shown under the focused quest, its portraits heading a column each; on the others it is in
    -- the tooltip
    local members = isActive and ns.Party.getProgress(entry.questId, entry.objectives, entry.eventText ~= nil and not entry.isTurnIn) or {}
    -- Right of the title: the chain step, as the quest list writes it (the chain and "2 of 5", no outline)
    if entry.chainIndex then
        row.want.rightText = ns.L("%d of %d", entry.chainIndex, entry.chainTotal)
        row.want.rightColor = BADGE_TEXT
        row.want.chain = true
    end
    -- Its narration, only while it plays (the right-click menu plays, queues and stops it)
    if ns.QuestText.getVoiceState(entry.questId) == "playing" then
        row.want.voice = true
    end

    -- What can still go wrong comes first: a failed quest, the time left, someone to keep alive
    local timeLeft = ns.QuestState.getTimeLeft(entry.questId)
    if ns.QuestState.isFailed(entry.questId) then
        addInfoRow(ns.L("Failed - abandon it and take it again"), RED)
    elseif timeLeft then
        hasTimer = true
        addInfoRow(ns.L("Time left %s", formatTime(timeLeft)), timeLeft < URGENT_SECONDS and RED or AMBER)
    end
    if not entry.isTurnIn and not ns.QuestState.isFailed(entry.questId) and ns.QuestState.isEscort(entry.questId) then
        addInfoRow(ns.L("Escort: keep them alive"), AMBER)
    end
    -- The party first, under the title; then the player's own progress
    if #members > 0 then
        addPartyFaces(members)
    end
    -- A quest ready to hand in can be its title alone, the player's choice (its "?" says it is ready); the one in
    -- focus keeps its line
    local isFoldedReady = entry.isTurnIn and ns.settings.shouldCollapseReady and not isActive
    if isFoldedReady then
        -- nothing under the title
    elseif entry.isTurnIn then
        addInfoRow(ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver")), GREEN)
    elseif entry.eventText then
        addInfoRow(entry.eventText, WHITE)
    else
        addObjectiveRows(entry)
    end
    if entry.otherZonesText and not isFoldedReady then
        local row = addInfoRow(ns.Widgets.formatMoreZones(entry.otherZonesText, "ffd100"), GREY)
        row.isZonesLine = entry.zoneIds ~= nil
    end
    currentEntry = nil
    return top, cursor
end

---Pins the tracker by its top right corner where it is now, so it only ever grows downwards, and keeps that.
local function pinByTop()
    local right, top = frame:GetRight(), frame:GetTop()
    if type(right) ~= "number" or type(top) ~= "number" then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    ns.settings.position = { "TOPRIGHT", "BOTTOMLEFT", right, top }
end

local function applyPosition()
    local position = ns.settings.position or DEFAULT_POSITION
    frame:ClearAllPoints()
    if ns.settings.position then
        frame:SetPoint(position[1], UIParent, position[2], position[3], position[4])
    else
        -- The place it starts is meant on the screen: the same at any size the player chose (offsets are in the
        -- tracker's own units, which its size changes)
        local scale = frame:GetScale() or 1
        frame:SetPoint(position[1], UIParent, position[2], position[3] / scale, position[4] / scale)
    end
    -- A place saved by another point (the middle of an edge, as dragging used to keep it) is turned into the
    -- top right corner, so the tracker grows only downwards from there
    if ns.settings.position and not tostring(position[1]):find("^TOP") then
        pinByTop()
    end
end

function Tracker.resetPosition()
    if frame then
        applyPosition()
    end
end

local isInCombat = false -- between the game's "combat starts" and "combat ends"

---@return number opacity The whole tracker's (settings.trackerOpacity), 0.2 to 1: never so faint it is lost
function Tracker.getOpacity()
    return math.max(0.2, math.min(1, tonumber(ns.settings.trackerOpacity) or 1))
end

---@return number opacity Its dark background's (settings.trackerBackgroundOpacity), 0.1 to 1
function Tracker.getBackgroundOpacity()
    return math.max(0.1, math.min(1, tonumber(ns.settings.trackerBackgroundOpacity) or 0.5))
end

---@return string? situation "hide" or "fold" when the player chose that for now (in combat, in a dungeon or raid);
---nil to show the tracker as it is. Hiding wins over folding.
function Tracker.getSituation()
    local isInDungeon = false
    if IsInInstance then
        local isInside, kind = IsInInstance()
        isInDungeon = isInside == true and (kind == "party" or kind == "raid")
    end
    local inCombat = isInCombat and ns.settings.trackerInCombat or "show"
    local inDungeon = isInDungeon and ns.settings.trackerInDungeons or "show"
    if inCombat == "hide" or inDungeon == "hide" then
        return "hide"
    elseif inCombat == "fold" or inDungeon == "fold" then
        return "fold"
    end
    return nil
end

---Combat starting or ending: the tracker drawn again at once, for folding or hiding it. Combat's start is the last
---moment the quest item buttons can still be hidden, so it is not left to the usual short delay.
local function handleCombatEvent(_, event)
    isInCombat = event == "PLAYER_REGEN_DISABLED"
    if ns.settings.trackerInCombat ~= "show" then
        Tracker.refresh()
    end
end
Tracker.handleCombatEvent = handleCombatEvent

---Gives the tracker its width and size from the settings. A new size keeps its top right corner where it is on the
---screen: its place is kept in its own units, which a size changes, so it is worked out again in the new ones.
function Tracker.applySize()
    if not frame then
        return
    end
    local width = getWidth()
    frame:SetWidth(width)
    frame.header:SetWidth(width)
    scrollFrame:SetWidth(width + 2 * SIDE_MARGIN)
    content:SetWidth(width + 2 * SIDE_MARGIN)
    local oldScale, newScale = frame:GetScale(), getScale()
    if type(oldScale) ~= "number" or math.abs(oldScale - newScale) < 0.001 then
        return
    end
    local right, top = frame:GetRight(), frame:GetTop()
    frame:SetScale(newScale)
    if not ns.settings.position then
        applyPosition() -- where it starts, kept on the screen
    elseif type(right) == "number" and type(top) == "number" then
        frame:ClearAllPoints()
        frame:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * oldScale / newScale, top * oldScale / newScale)
        ns.settings.position = { "TOPRIGHT", "BOTTOMLEFT", right * oldScale / newScale, top * oldScale / newScale }
    end
end

local GRIP_WIDTH = 22
local GRIP_REACH = 30 -- how far left of the title the pointer still keeps the grip shown, so it is never lost on the way
local GRIP_CHECK_SECONDS = 0.1

---The grip at the left end of the title, for dragging the tracker wider or narrower: two gold arrows, pointing out,
---either side of a bar, as the game's own sizing handles look; the game's sizing cursor over it. Shown while the
---pointer is on the title or just left of it (checked a few times a second, so moving onto the grip never hides
---it), and while the tracker is not locked. The tracker keeps its right edge, so it grows to the left.
local function createWidthGrip()
    local grip = CreateFrame("Button", nil, frame.header)
    grip:SetSize(GRIP_WIDTH, HEADER_HEIGHT - 4)
    grip:SetPoint("RIGHT", frame.header, "LEFT", 0, 0)
    grip:SetFrameLevel((frame.header:GetFrameLevel() or 1) + 2)
    local ground = grip:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(grip)
    ground:SetColorTexture(0, 0, 0, 0.55)
    local bar = grip:CreateTexture(nil, "ARTWORK")
    bar:SetSize(2, HEADER_HEIGHT - 12)
    bar:SetPoint("CENTER", grip, "CENTER", 0, 0)
    bar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    -- The arrows: the chevron the tracker scrolls with, turned to point left and right
    local arrows = {}
    for index, side in ipairs({ { "RIGHT", -2, math.pi / 2 }, { "LEFT", 2, -math.pi / 2 } }) do
        local arrow = grip:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(MEDIA .. "ChevronDown")
        arrow:SetSize(9, 9)
        arrow:SetPoint(side[1], bar, index == 1 and "LEFT" or "RIGHT", side[2], 0)
        arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        if arrow.SetRotation then
            arrow:SetRotation(side[3])
        end
        arrows[index] = arrow
    end
    local function setBright(isBright)
        local alpha = isBright and 1 or 0.75
        bar:SetAlpha(alpha)
        for _, arrow in ipairs(arrows) do
            arrow:SetAlpha(alpha)
        end
    end
    local function isWanted()
        if ns.settings.isLocked or not frame:IsShown() then
            return false
        end
        -- The title, and a strip left of it as wide as the grip and a little more
        return grip.isDragging or grip:IsMouseOver() or frame.header:IsMouseOver(2, -2, -GRIP_REACH, 0)
    end
    -- A small watcher decides when it shows: not the title's own enter and leave, which fire as the pointer moves
    -- from the title onto the grip and hid it on the way
    local watcher = CreateFrame("Frame", nil, frame)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, seconds)
        elapsed = elapsed + seconds
        if elapsed < GRIP_CHECK_SECONDS then
            return
        end
        elapsed = 0
        local wanted = isWanted() == true
        if grip:IsShown() ~= wanted then
            grip:SetShown(wanted)
        end
    end)
    grip:SetScript("OnMouseDown", function(self)
        if ns.settings.isLocked then
            return
        end
        self.isDragging = true
        setBright(true)
        self.startX = GetCursorPosition() / frame:GetEffectiveScale()
        self.startWidth = getWidth()
        self:SetScript("OnUpdate", function()
            local x = GetCursorPosition() / frame:GetEffectiveScale()
            local width = math.floor(math.max(MIN_WIDTH, math.min(MAX_WIDTH, self.startWidth + self.startX - x)) + 0.5)
            if width ~= ns.settings.trackerWidth then
                ns.settings.trackerWidth = width
                Tracker.refresh()
            end
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
        setBright(self:IsMouseOver())
    end)
    grip:SetScript("OnEnter", function(self)
        setBright(true)
        if SetCursor then
            pcall(SetCursor, "UI_RESIZE_CURSOR") -- the game's sizing cursor, as over its own resizable windows
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L("Drag to make the tracker wider or narrower"), 1, 1, 1)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if ResetCursor then
            ResetCursor()
        end
        setBright(self.isDragging == true)
    end)
    setBright(false)
    grip:Hide()
    return grip
end

---@return number? questId The game's own focus (its super-tracked quest), when it is a quest in the log
function Tracker.create()
    frame = CreateFrame("Frame", "TrailheadTracker", UIParent)
    isInCombat = InCombatLockdown and InCombatLockdown() == true -- a reload in a fight starts in it
    frame:SetSize(WIDTH, 20)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    applyPosition()

    frame.header = CreateFrame("Button", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetSize(WIDTH, 22)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        if not ns.settings.isLocked then
            frame:StartMoving()
        end
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        -- The game keeps whichever point is nearest; the top is kept instead, so the tracker grows only downwards
        pinByTop()
        Tracker.refresh() -- the item buttons follow the tracker
    end)

    -- The game's own tracker header: "Quests" on a dark band that fades out at both ends, edged above and
    -- below in faint gold, with the gold "-" button at the right that folds the tracker away to its title
    local band = frame.header:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints(frame.header)
    band:SetColorTexture(1, 1, 1, 1)
    local function setFade(texture, alpha)
        if texture.SetGradient and CreateColor then
            -- Faded at the left end only; a second texture fades the right end
            texture:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, alpha))
        else
            texture:SetColorTexture(0, 0, 0, alpha / 2)
        end
    end
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", frame.header, "TOPLEFT", -SIDE_MARGIN, 0)
    band:SetPoint("BOTTOMRIGHT", frame.header, "BOTTOM", 0, 0)
    setFade(band, HEADER_BAND_ALPHA)
    local bandRight = frame.header:CreateTexture(nil, "BACKGROUND")
    bandRight:SetColorTexture(1, 1, 1, 1)
    bandRight:SetPoint("TOPLEFT", frame.header, "TOP", 0, 0)
    bandRight:SetPoint("BOTTOMRIGHT", frame.header, "BOTTOMRIGHT", SIDE_MARGIN, 0)
    if bandRight.SetGradient and CreateColor then
        bandRight:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, HEADER_BAND_ALPHA), CreateColor(0, 0, 0, 0))
    else
        bandRight:SetColorTexture(0, 0, 0, HEADER_BAND_ALPHA / 2)
    end
    for _, edge in ipairs({ "TOP", "BOTTOM" }) do
        local line = frame.header:CreateTexture(nil, "BORDER")
        line:SetColorTexture(1, 0.82, 0, 0.33)
        line:SetHeight(1)
        line:SetPoint(edge .. "LEFT", frame.header, edge .. "LEFT", 0, 0)
        line:SetPoint(edge .. "RIGHT", frame.header, edge .. "RIGHT", 0, 0)
    end
    frame.title = ns.Widgets.createFontString(frame.header, "OVERLAY", _G.GameFontNormalMed2 and "GameFontNormalMed2" or "GameFontNormal")
    frame.title:SetPoint("LEFT", frame.header, "LEFT", 6, 0)
    frame.title:SetText(ns.L("Quests"))
    frame.foldButton = CreateFrame("Button", nil, frame.header)
    frame.foldButton:SetSize(16, 16)
    frame.foldButton:SetPoint("RIGHT", frame.header, "RIGHT", -4, 0)
    frame.foldButton:SetScript("OnClick", function()
        ns.settings.isTrackerFolded = not ns.settings.isTrackerFolded
        Tracker.refresh()
    end)

    -- The quests scroll under the title when there are more than fit above the bottom of the screen. The
    -- scrolling area is a little wider than the rows, so the active quest's band is not cut off at the sides.
    scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -SIDE_MARGIN, -HEADER_HEIGHT)
    scrollFrame:SetSize(WIDTH + 2 * SIDE_MARGIN, 1)
    content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(WIDTH + 2 * SIDE_MARGIN, 1)
    scrollFrame:SetScrollChild(content)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        scrollOffset = scrollOffset - delta * SCROLL_STEP
        Tracker.refresh()
    end)
    -- Where more quests wait, a small gold arrow at that edge, as the quest panels have; the title row stays
    -- free, since other addons put things near it
    local function createScrollArrow(isTop)
        local arrow = frame:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(MEDIA .. "ChevronDown")
        arrow:SetSize(12, 12)
        arrow:SetVertexColor(1, 0.82, 0, 0.9)
        if isTop then
            arrow:SetTexCoord(0, 1, 1, 0) -- the same arrow, upside down
            arrow:SetPoint("BOTTOM", scrollFrame, "TOP", 0, 1)
        else
            arrow:SetPoint("TOP", scrollFrame, "BOTTOM", 0, -1)
        end
        arrow:Hide()
        return arrow
    end
    frame.moreAbove, frame.moreBelow = createScrollArrow(true), createScrollArrow(false)
    frame.widthGrip = createWidthGrip()
    -- A dark ground behind the tracker, the player's choice, for reading it over bright scenery
    frame.background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.background:SetPoint("TOPLEFT", frame, "TOPLEFT", -SIDE_MARGIN - 4, 4)
    frame.background:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", SIDE_MARGIN + 4, -6)
    frame.background:SetColorTexture(0, 0, 0, 0.5)
    frame.background:Hide()
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:SetScript("OnEvent", handleCombatEvent)

    frame.activeBand = content:CreateTexture(nil, "BACKGROUND")
    frame.activeBand:SetColorTexture(1, 1, 1, 0.07)
    -- The focused quest's gold bar down its right edge, as the quest list marks it
    frame.activeBar = content:CreateTexture(nil, "ARTWORK")
    frame.activeBar:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
    -- Both hidden until a quest is in focus (the drawing shows and places them when that changes)
    frame.activeBand:Hide()
    frame.activeBar:Hide()

    Tracker.refresh()
end

local lastProgress = {} -- [questId] = { done = objectives counted up, isReady = boolean } at the last refresh
local pendingFlashes = {} -- [questId] = colour of a flash still to play
local flashes = {} -- [questId] = the quest's flash texture, made when first needed
local fadeGroups = {} -- [questId] = the animation that fades the flash out

---Notes what moved since the last look: a count went up, or the quest became ready to hand in. The first look
---after logging in only takes note, so nothing flashes for progress made before.
local function noteProgress(entry)
    local done = 0
    for _, objective in ipairs(entry.objectives) do
        done = done + (objective.fulfilled or 0) + (objective.isFinished and 1 or 0)
    end
    local last = lastProgress[entry.questId]
    if last then
        local isFlashing = ns.settings.shouldFlashProgress
        if entry.isTurnIn and not last.isReady then
            pendingFlashes[entry.questId] = isFlashing and GREEN or nil
            if ns.settings.shouldPlayReadySound and PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
                PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
            end
        elseif done > last.done then
            pendingFlashes[entry.questId] = isFlashing and GOLD or nil
        end
    end
    lastProgress[entry.questId] = { done = done, isReady = entry.isTurnIn == true }
end

---A soft band over the quest's lines that lights up and fades, when the quest has just moved on.
local function placeFlash(questId, top, bottom)
    local flash = flashes[questId]
    if not flash then
        flash = content:CreateTexture(nil, "BACKGROUND", nil, 1)
        flash:SetAlpha(0)
        local group = flash.CreateAnimationGroup and flash:CreateAnimationGroup()
        if type(group) == "table" then
            local fade = group:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.55)
            fade:SetToAlpha(0)
            fade:SetDuration(FLASH_SECONDS)
            fade:SetSmoothing("OUT")
            group:SetScript("OnFinished", function() flash:SetAlpha(0) end)
            fadeGroups[questId] = group
        end
        flashes[questId] = flash
    end
    if flash.top ~= top or flash.bottom ~= bottom then -- (placed again only when its quest's lines moved)
        flash.top, flash.bottom = top, bottom
        flash:ClearAllPoints()
        flash:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(top - 2))
        flash:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -2, -(bottom + 2))
    end
    if not flash.isShownNow then
        flash.isShownNow = true
        flash:Show()
    end
    local color = pendingFlashes[questId]
    if color then
        pendingFlashes[questId] = nil
        flash:SetColorTexture(color[1], color[2], color[3], 1)
        local group = fadeGroups[questId]
        if group then
            group:Stop()
            group:Play()
        end
    end
end

local drawnOrderKey -- the quests and their order as the tracker last drew them (getOrderKey)

---@return string key What of the tracker follows where the player stands: its zones and quests in their order (by
---distance, where the player chose that), which zones are open, and the quest in focus
---@return TrackerEntry? activeEntry The quest in focus
local function getOrderKey(model)
    local parts, activeEntry = { tostring(model.activeQuestId) }, nil
    for _, group in ipairs(model.groups) do
        parts[#parts + 1] = "#" .. tostring(group.zoneId) .. (group.isCollapsed and "-" or "+") .. (group.isCurrent and "c" or "")
        for _, entry in ipairs(group.entries) do
            parts[#parts + 1] = entry.questId
            activeEntry = entry.questId == model.activeQuestId and entry or activeEntry
        end
    end
    return table.concat(parts, ","), activeEntry
end

---Every second: drawn again only for a time left counting down, or when the player has walked far enough that the
---order of the quests changed (listed by distance). Walking on otherwise, only the waypoint followed moves to the
---nearest place: nothing on the tracker says how far anything is. Standing still, nothing is done at all.
function Tracker.tick()
    if not frame then
        return
    end
    local position = ns.Geometry.getPlayerPosition()
    local isMoved = not refreshedAt or (position and position.uiMapId) ~= refreshedAt.uiMapId
        or (position and ns.Geometry.getDistance(position.north, position.west, refreshedAt.north, refreshedAt.west) >= TICK_YARDS)
    if hasTimer then
        Tracker.refresh()
    elseif isMoved then
        local key, activeEntry = getOrderKey(ns.Model.compose(ns.Focus.getPicked()))
        if not refreshedAt or key ~= drawnOrderKey or (position and position.uiMapId) ~= refreshedAt.uiMapId then
            Tracker.refresh()
            return
        end
        ns.Waypoints.followFocusedQuest(activeEntry)
        refreshedAt.north, refreshedAt.west = position and position.north, position and position.west
    end
end

function Tracker.refresh()
    if not frame then
        return
    end
    -- The player's pick is kept even while it cannot be shown (right after logging in the game has not
    -- listed the tracked quests yet), so it comes back as soon as the quest is there
    local model = ns.Model.compose(ns.Focus.getPicked())
    activeQuestId = model.activeQuestId
    local activeEntry
    drawnOrderKey, activeEntry = getOrderKey(model)
    ns.Waypoints.followFocusedQuest(activeEntry)

    Tracker.applySize()
    hasTimer = false
    local position = ns.Geometry.getPlayerPosition()
    refreshedAt = { uiMapId = position and position.uiMapId, north = position and position.north, west = position and position.west }
    usedRowCount, cursor = 0, 0
    local itemPlacements = {}
    local activeTop, activeBottom -- the quest in focus: where its lines are, for its band and bar
    -- The "-" folds the tracker to its title; "+" brings the quests back
    -- Folded by its "-", or for the moment: in combat or in a dungeon, as the player chose
    local situation = Tracker.getSituation()
    local isFolded = ns.settings.isTrackerFolded == true or situation == "fold"
    frame.title:SetText(ns.L("Quests")) -- on every drawing, so a change of language shows
    frame.foldButton:SetNormalTexture(isFolded and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    frame.foldButton:SetPushedTexture(isFolded and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
    for _, group in ipairs(isFolded and {} or model.groups) do
        addZoneRow(group)
        if not group.isCollapsed then
            for _, entry in ipairs(group.entries) do
                addGap(4)
                local isActive = entry.questId == activeQuestId
                noteProgress(entry)
                local top, bottom = addQuestRows(entry, isActive)
                placeFlash(entry.questId, top, bottom)
                if entry.item then
                    itemPlacements[#itemPlacements + 1] = { item = entry.item, offset = top, size = isActive and 32 or 26 }
                end
                if isActive then
                    activeTop, activeBottom = top, bottom
                end
            end
        end
        addGap(10)
    end
    flushRow()
    for index = usedRowCount + 1, #rows do
        rows[index]:Hide()
    end
    -- The focused quest's band and bar, placed again only when its lines moved
    if activeTop ~= frame.activeTop or activeBottom ~= frame.activeBottom then
        frame.activeTop, frame.activeBottom = activeTop, activeBottom
        frame.activeBand:SetShown(activeTop ~= nil)
        frame.activeBar:SetShown(activeTop ~= nil)
        if activeTop then
            frame.activeBand:ClearAllPoints()
            frame.activeBand:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(activeTop - 2))
            frame.activeBand:SetPoint("BOTTOMRIGHT", content, "TOPRIGHT", -2, -(activeBottom + 2))
            frame.activeBar:ClearAllPoints()
            frame.activeBar:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -(activeTop - 2))
            frame.activeBar:SetPoint("BOTTOMLEFT", content, "TOPRIGHT", -5, -(activeBottom + 2))
        end
    end

    -- As tall as its quests, up to what fits between its top and the bottom of the screen; beyond that it
    -- scrolls with the mouse wheel
    local top = frame:GetTop()
    local maxHeight = math.max((type(top) == "number" and top or 700) - HEADER_HEIGHT - BOTTOM_MARGIN, MIN_HEIGHT)
    local visibleHeight = math.min(cursor, maxHeight)
    local isScrollable = cursor > maxHeight
    scrollOffset = math.max(0, math.min(scrollOffset, cursor - visibleHeight))
    content:SetHeight(math.max(cursor, 1))
    scrollFrame:SetHeight(math.max(visibleHeight, 1))
    scrollFrame:SetVerticalScroll(scrollOffset)
    scrollFrame:EnableMouseWheel(isScrollable) -- only then, so the wheel still zooms the camera otherwise
    frame:SetHeight(HEADER_HEIGHT + visibleHeight)
    local hasAbove, hasBelow = scrollOffset > 0, scrollOffset < cursor - visibleHeight
    frame.moreAbove:SetShown(hasAbove)
    frame.moreBelow:SetShown(hasBelow)

    local isShown = ns.settings.isShown and model.questCount > 0 and situation ~= "hide"
    frame.background:SetShown(ns.settings.shouldShowTrackerBackground == true)
    local backgroundOpacity = Tracker.getBackgroundOpacity()
    if frame.backgroundOpacity ~= backgroundOpacity then
        frame.backgroundOpacity = backgroundOpacity
        frame.background:SetColorTexture(0, 0, 0, backgroundOpacity)
    end
    local opacity = Tracker.getOpacity()
    if frame.opacity ~= opacity then
        frame.opacity = opacity
        frame:SetAlpha(opacity)
    end
    if isShown then
        frame:Show()
    else
        frame:Hide()
    end
    -- Item buttons sit beside their quests, so they scroll with them and go when their quest is out of view
    local visiblePlacements = {}
    for _, placement in ipairs(itemPlacements) do
        local offset = placement.offset - scrollOffset
        if offset >= 0 and offset + placement.size <= visibleHeight then
            placement.offset = HEADER_HEIGHT + offset
            visiblePlacements[#visiblePlacements + 1] = placement
        end
    end
    ns.ItemButtons.apply(isShown and frame or nil, isShown and visiblePlacements or {})
end

---Characters have their own quests, so each remembers its own quest in focus.

---Events arrive in bursts, so they share one refresh.
function Tracker.queueRefresh()
    if isRefreshQueued then
        return
    end
    isRefreshQueued = true
    C_Timer.After(REFRESH_DELAY_SECONDS, function()
        isRefreshQueued = false
        ns.Timing.measure("tracker drawn (queued)", Tracker.refresh)
    end)
end

ns.on("FOCUS_CHANGED", function() Tracker.refresh() end) -- the quest in focus is the one shown in full

ns.registerModule({
    name = "Tracker",
    create = Tracker.create,
    refresh = Tracker.refresh,
    tick = Tracker.tick, -- distances change as the player moves, and time left counts down
    afterCombat = Tracker.refresh, -- quest item buttons could not move during the fight
})
