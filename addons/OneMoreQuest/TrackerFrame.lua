local addonName, ns = ... -- the addon's folder, which its pictures are read from
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

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

local Look = ns.TrackerLook
local rowHeights = { title = 17, text = 15, zone = 16 } -- each kind of line's height, from its font's size (refresh)
local LOG_FILLING = { 1, 0.6, 0.48 } -- the log's count once two places or fewer are left
local COUNT_COLOR = { 0.9, 0.9, 0.9 }

-- What the spoiler choices let the tracker tell (Spoilers): whether anything is held back, asked once a drawing; then
-- the choices for the quest whose lines are being added, asked once a quest (addQuestRows). In Guide nothing is asked
-- and these stay as they are: everything told.
local isSpoiling = false
local questDrops, questPlaces, questChains, isQuestTurnInTold = "chances", "exact", "all", true
local DROP_NOTE_COLOR = { 0.7, 0.7, 0.7 } -- as the map's tooltip writes what drops an item
local MAX_DROP_SOURCES = 3

local function setColor(fontString, color)
    color = Look.tone(color)
    fontString:SetTextColor(color[1], color[2], color[3])
end

local function getDifficultyColor(level)
    local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if color then
        return { color.r, color.g, color.b }
    end
    return GOLD
end

---What drops an item objective's item, as much as the spoiler choice lets tell: with the chances (the map's tooltip's
---own lines), the creatures' names alone, only those that dropped it for the player, or nothing.
---@param choice string Spoilers' "drops" for the quest
local function addDropLines(tooltip, questId, typeIndex, choice)
    if choice == "chances" then
        ns.MapHover.addDropLines(tooltip, questId, typeIndex)
        return
    elseif choice ~= "names" and choice ~= "found" then
        return
    end
    local target = ns.Location.getObjectiveTarget(questId, "item", typeIndex)
    local itemId = target and target.itemId
    local zone = itemId and ns.Drops.getZones(itemId)[1]
    local sources = zone and zone.sources or {}
    for index, source in ipairs(sources) do
        if choice == "names" and index > MAX_DROP_SOURCES then
            tooltip:AddLine(ns.Lp(#sources - MAX_DROP_SOURCES, "   + %d more", "   + %d more"), DROP_NOTE_COLOR[1], DROP_NOTE_COLOR[2], DROP_NOTE_COLOR[3])
            break
        end
        if choice == "names" or ns.Spoilers.hasSeenDrop(itemId, source.npcId or source.objectId) then
            tooltip:AddLine("   " .. source.name, DROP_NOTE_COLOR[1], DROP_NOTE_COLOR[2], DROP_NOTE_COLOR[3])
        end
    end
end

---@return boolean isTold Where the quest's next step is may be pointed at exactly (a waypoint): its spawns shown, or,
---ready to hand in, its turn-in. Asked only while something is held back.
local function isPlaceTold(entry)
    if entry.isTurnIn then
        return ns.Model.isTurnInShown(entry.questId)
    end
    return ns.Spoilers.get("objectives", entry.questId) == "exact"
end

---@return string text "Turn in to Sergra Darkthorn", or, while who and where is held back, only that it is ready
local function composeTurnInText(entry, isTold)
    if not isTold then
        return ns.L("Ready to turn in")
    end
    return ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver"))
end

---"Need a hint?": the quest page's ladder, one step at a time, by the row; where the quest log has none yet, the next
---step at once.
local function openHint(questId, anchor)
    if ns.Log and ns.Log.showHintLadder then
        ns.Log.showHintLadder(questId, anchor)
    else
        ns.Spoilers.giveHint(questId)
    end
end

---The quest chain in the row's tooltip, as much as the spoiler choice lets tell: every step, or the steps so far and
---how many are left (never "hidden": the drawing leaves the chain out then).
local function addChainLines(entry, choice)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(ns.L("Quest chain, step %d of %d", entry.chainIndex, entry.chainTotal), 1, 0.82, 0)
    for position, chainQuestId in ipairs(ns.Chain.getQuestIds(entry.questId)) do
        if position > entry.chainIndex and choice ~= "all" then
            GameTooltip:AddLine(ns.Lp(entry.chainTotal - entry.chainIndex, "%d more step", "%d more steps"), TAN[1], TAN[2], TAN[3])
            break
        end
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

local function showTooltip(row)
    local entry = row.entry
    if not entry then
        return
    end
    if row.isHintLine then
        GameTooltip:SetOwner(row, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L("Need a hint?"), 1, 1, 1)
        GameTooltip:AddLine(ns.L("Click for one step at a time: the zone, roughly where, then exactly where. A hint stays for this quest only."),
            TAN[1], TAN[2], TAN[3], true)
        GameTooltip:Show()
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
    -- As much as the spoiler choices let tell (asked here, on a hover, not at every drawing)
    local isHolding = ns.Spoilers.isActive()
    local drops = isHolding and ns.Spoilers.get("drops", entry.questId) or "chances"
    local places = isHolding and ns.Spoilers.get("objectives", entry.questId) or "exact"
    local chains = isHolding and ns.Spoilers.get("chains", entry.questId) or "all"
    local typeIndexes = {}
    for _, objective in ipairs(entry.objectives) do
        local status = objective.required > 1 and (objective.fulfilled .. "/" .. objective.required) or objective.isFinished and ns.L("done") or ""
        GameTooltip:AddDoubleLine((objective.shownLabel or objective.label), status, 1, 1, 1, 1, 1, 1)
        -- An item still to get: what drops it (or holds it) and how often, as the map's tooltip says
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        if objective.type == "item" and not objective.isFinished then
            addDropLines(GameTooltip, entry.questId, typeIndexes.item, drops)
        end
    end
    if entry.isTurnIn then
        GameTooltip:AddLine(composeTurnInText(entry, not isHolding or ns.Model.isTurnInShown(entry.questId)), GREEN[1], GREEN[2], GREEN[3])
    end
    -- With Shift held: what it asks, the rewards, where it is handed in (its objectives are listed above already)
    ns.QuestTooltip.addDetails(GameTooltip, entry.questId, { hasObjectives = true, hasTurnIn = entry.isTurnIn })
    -- Kills for the items that drop: the chance, kills against the kills expected, and about what the rest takes
    -- (none while the chances are held back: KillCounter.getProgress tells nothing then)
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
    if entry.chainIndex and chains ~= "hidden" then
        addChainLines(entry, chains)
    end
    -- (what the map cannot show matters only where the map would show it)
    if (entry.unlocatedCount or 0) > 0 and (places == "exact" or places == "rough") then
        local text = entry.unlocatedCount == 1 and ns.L("The database has no location for one objective, so the map cannot show where to go.")
            or ns.Lp(entry.unlocatedCount, "The database has no location for %d objective, so the map cannot show where to go.", "The database has no location for %d objectives, so the map cannot show where to go.")
        GameTooltip:AddLine(text, TAN[1], TAN[2], TAN[3], true)
    end
    ns.Party.addProgressToTooltip(GameTooltip, entry.questId, entry.objectives)
    -- The same clicks as on a quest in the quest list, on its page and on its mark on the map (with a controller's
    -- cursor on it, the prompt bar says what its buttons do)
    if not (ns.GamepadTracker and ns.GamepadTracker.isFocused()) then
        local clickHint = entry.questId == activeQuestId
            and "Click to open it in the quest log, ctrl-click to stop focusing, shift-click to link it in chat, right-click for more"
            or "Click to open it in the quest log, ctrl-click to focus it, shift-click to link it in chat, right-click for more"
        GameTooltip:AddLine(ns.L(clickHint), GREY[1], GREY[2], GREY[3], true)
        ns.QuestTooltip.addHint(GameTooltip)
    end
    GameTooltip:Show()
end
Tracker.showTooltip = showTooltip -- (for the tests: a row hovered)

---Opens a quest's page in the quest log, as a click on it in the quest list does, and turns the map to where it
---is. With the game's own quest log kept (the setting), that one opens on the quest.
---@param entry table The quest as the tracker shows it (Model's entry)
---@return boolean isOpened False when the game would not open the map (it opens none for an addon in a fight)
function Tracker.openInLog(entry)
    local questId = entry.questId
    if not ns.settings.shouldReplaceQuestLog and QuestMapFrame_OpenToQuestDetails then
        if ns.MapDock.isMapHandsOff() then
            return false -- (the gamepad interface: the game's map opened by an addon taints it, MapDock.isMapHandsOff)
        end
        return pcall(QuestMapFrame_OpenToQuestDetails, questId) == true
    end
    -- In a fight the game opens no map for an addon: the quest log opens on its own, without it (the map follows
    -- once the fight is over, if the window is still open)
    if InCombatLockdown and InCombatLockdown() and not (WorldMapFrame and WorldMapFrame:IsShown()) then
        return ns.Log.openAlone(questId)
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
    ns.openMenu(owner, function(_, root)
        ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
        root:CreateTitle(entry.title)
        local isActive = questId == activeQuestId
        root:CreateButton(ns.L(isActive and "Unfocus" or "Focus"), function()
            ns.Focus.set(not isActive and questId or nil)
        end)
        -- Something of it held back that a hint could show (never in Guide)
        if ns.Spoilers.canHint(questId) then
            root:CreateButton(ns.L("Need a hint?"), function() openHint(questId, owner) end)
        end
        if ns.Waypoints.getQuestPlace(entry) and (not ns.Spoilers.isActive() or isPlaceTold(entry)) then
            root:CreateButton(ns.L(ns.Waypoints.hasTomTom() and "Set a TomTom waypoint" or "Set a waypoint"), function()
                ns.Waypoints.set(entry)
            end)
        end
        root:CreateButton(ns.L("Share to chat"), function() ns.QuestState.linkInChat(questId) end)
        root:CreateButton(ns.L("Open in the quest log"), function()
            if ns.GamepadTracker then
                ns.GamepadTracker.release() -- (the quest window has the pad then, not the tracker)
            end
            Tracker.openInLog(entry)
        end)
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
        -- With a controller, its item onto the gamepad's action bar, as the game's own tracker offers it
        local editFrame = entry.item and entry.item.itemId and ns.Gamepad and ns.Gamepad.isGamepadUI() and _G.GamepadActionBarEditFrame
        if editFrame and editFrame.BindItem then
            root:CreateButton(_G.CONTEXT_ACTION_LABEL_BIND_TO_GAMEPAD_ACTION_BAR or ns.L("Put its item on the action bar"), function()
                if ns.GamepadTracker then
                    ns.GamepadTracker.release()
                end
                editFrame:BindItem(entry.item.itemId)
            end)
        end
        root:CreateDivider()
        root:CreateButton("|cffff5040" .. ns.L("Abandon") .. "|r", function() ns.Log.abandonQuest(questId) end)
    end)
end

---A zone heading's actions on a right click: untracking all its quests at once, as on the game's tracker.
local function openZoneMenu(row)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        return
    end
    ns.openMenu(row, function(_, root)
        ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
        root:CreateTitle(row.zoneName)
        ns.Log.addTrackMenuItems(root, row.zoneQuestIds)
    end)
end

local function handleRowClick(row, mouseButton)
    if row.isHintLine and mouseButton ~= "RightButton" then
        openHint(row.entry.questId, row)
        return
    end
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
    -- The quest's mark before the title, exactly as the map draws it in the look chosen in the settings. A click on
    -- it puts the quest in focus (its waypoint, its marks lit), or takes the focus off; the rest of the row opens it
    row.mark = ns.MapMarks.createMarkButton(row)
    row.mark:EnableMouse(true)
    if row.mark.RegisterForClicks then
        row.mark:RegisterForClicks("LeftButtonUp")
    end
    row.mark:SetScript("OnClick", function()
        if row.entry then
            toggleFocus(row.entry)
        end
    end)
    row.mark:SetScript("OnEnter", function(self)
        if not row.entry then
            return
        end
        local isFocused = row.entry.questId == activeQuestId
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L(isFocused and "Click to stop focusing" or "Click to focus it"), 1, 1, 1)
        if not isFocused then
            GameTooltip:AddLine(ns.L("Its waypoint, and its marks lit on the map and the minimap."), TAN[1], TAN[2], TAN[3], true)
        end
        GameTooltip:Show()
    end)
    row.mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
    row.entry, row.zoneId, row.isCollapsed, row.isZonesLine, row.isHintLine = currentEntry, nil, nil, false, false
    row.zoneName, row.zoneQuestIds, row.isTitle = nil, nil, nil
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
    local row = addRow(rowHeights.zone)
    local color = group.isCurrent and GOLD or TAN
    row.zoneId, row.isCollapsed = group.zoneId, group.isCollapsed
    row.zoneName, row.zoneQuestIds = group.zoneName, {}
    for _, entry in ipairs(group.entries) do
        row.zoneQuestIds[#row.zoneQuestIds + 1] = entry.questId
    end
    -- The zone's name plain, as the game's tracker writes its sections
    row.want.leftFont, row.want.leftColor = Look.getFont("zone"), color
    row.want.leftText = (group.isCollapsed and "+ " or "") .. group.zoneName
    row.want.rightFont, row.want.rightColor = Look.getFont("zone"), TAN
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
    local row = addRow(rowHeights.text, INDENT)
    row.want.leftFont, row.want.rightFont = Look.getFont("text"), Look.getFont("text")
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
    -- An item still to drop says how often it does, quietly after its name (what drops it: the row's tooltip); not
    -- while the chances are held back
    local chance = not objective.isFinished and objective.type == "item" and questDrops == "chances"
        and ns.KillCounter.getDropChance(entry.questId, index)
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
    local row = addRow(rowHeights.text, INDENT)
    row.want.leftFont, row.want.leftText, row.want.leftColor = Look.getFont("text"), text, color
    return row
end

-- "Need a hint?" offering itself (Spoilers' hints "offered"): the quests drawn and whether each showed the offer, so
-- the tick can tell, now and then, that one has begun offering it. Reused from drawing to drawing.
local OFFER_CHECK_SECONDS = 15
local isOfferWatched = false
local offerCheckAt = 0
local drawnOfferQuestIds, drawnOffers, drawnOfferCount = {}, {}, 0

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
    -- What the spoiler choices let tell of this quest, asked once for all its lines
    local isHintOffered = false
    if isSpoiling then
        questDrops = ns.Spoilers.get("drops", entry.questId)
        questPlaces = ns.Spoilers.get("objectives", entry.questId)
        questChains = ns.Spoilers.get("chains", entry.questId)
        isQuestTurnInTold = not entry.isTurnIn or ns.Model.isTurnInShown(entry.questId)
        if isOfferWatched then
            isHintOffered = ns.Spoilers.isHintOffered(entry.questId)
            drawnOfferCount = drawnOfferCount + 1
            drawnOfferQuestIds[drawnOfferCount], drawnOffers[drawnOfferCount] = entry.questId, isHintOffered
        end
    end
    local row = addRow(rowHeights.title)
    row.isTitle = true -- (the quest's one stop for a controller's cursor)
    row.want.leftFont = Look.getFont("title")
    row.want.leftText = ns.Widgets.formatQuestTitle(entry.level, entry.title, ns.QuestState.getGroupInfo(entry.questId))
    row.want.leftColor = isActive and WHITE or getDifficultyColor(entry.level)
    row.want.rightFont, row.want.rightColor = Look.getFont("text"), TAN
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
    -- Right of the title: the chain step, as the quest list writes it (the chain and "2 of 5", no outline); none while
    -- the chain is held back
    if entry.chainIndex and questChains ~= "hidden" then
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
        addInfoRow(composeTurnInText(entry, isQuestTurnInTold), GREEN)
    elseif entry.eventText then
        addInfoRow(entry.eventText, WHITE)
    else
        addObjectiveRows(entry)
    end
    -- The other zones it can be done in, where its places may be told at least roughly
    if entry.otherZonesText and not isFoldedReady and (questPlaces == "exact" or questPlaces == "rough") then
        local row = addInfoRow(ns.Widgets.formatMoreZones(entry.otherZonesText, "ffd100"), GREY)
        row.isZonesLine = entry.zoneIds ~= nil
    end
    -- Stuck a while: "Need a hint?" offers itself, quietly, a click away
    if isHintOffered and not isFoldedReady then
        local row = addInfoRow(ns.L("Need a hint?"), GREY)
        row.isHintLine = true
    end
    currentEntry = nil
    if isSpoiling then
        questDrops, questPlaces, questChains, isQuestTurnInTold = "chances", "exact", "all", true -- (for the next one)
    end
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

---The game is told not to keep the tracker's place in its own layout file (see Tracker.create)
local function forgetGamePlacement()
    if frame.SetDontSavePosition then
        frame:SetDontSavePosition(true)
    end
    if frame.SetUserPlaced and frame.IsUserPlaced and frame:IsUserPlaced() then
        frame:SetUserPlaced(false)
    end
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
-- The player unfolded a tracker folded for the moment (a fight, a dungeon): shown until that moment is over
local isMomentFoldUndone = false

---@return number opacity The whole tracker's (settings.trackerOpacity), 0.2 to 1: never so faint it is lost
function Tracker.getOpacity()
    return math.max(0.2, math.min(1, tonumber(ns.settings.trackerOpacity) or 1))
end

---@return number opacity Its dark background's (settings.trackerBackgroundOpacity), 0.1 to 1
function Tracker.getBackgroundOpacity()
    return math.max(0.1, math.min(1, tonumber(ns.settings.trackerBackgroundOpacity) or 0.5))
end

---@return string mode The dark ground behind it (settings.trackerBackground): "off", "box" (all of it), "bands" (a
---soft band behind each quest and zone only) or "hover" (all of it while the pointer is on it)
function Tracker.getBackgroundMode()
    local mode = ns.settings.trackerBackground
    if mode == "box" or mode == "bands" or mode == "hover" then
        return mode
    end
    return "off"
end

-- The filters on the title band: one choice, as the quest log's switch (settings.trackerFilter). Their buttons come
-- in while the pointer is on the band (Tracker.watchHover, the width grip's watcher); at rest only the chosen one's
-- icon stays, beside what is ready.
local FILTERS = {
    { value = "all", label = "All quests", note = "Every quest you track.", atlas = "questlog-tab-icon-quest" },
    { value = "here", label = "Here", note = "Only the quests of the zone you are in; it follows you from zone to zone.", atlas = "Waypoint-MapPin-Untracked" },
    { value = "ready", label = "Ready", note = "Only the quests ready to hand in.", atlas = "QuestTurnin" },
    { value = "focus", label = "Focus", note = "Only the quest in focus.", atlas = "navigation-tracked-icon", iconSize = 15 }, -- (the game's own mark for the quest it guides you to)
}
local FILTERS_BY_VALUE = {}
for _, filter in ipairs(FILTERS) do
    FILTERS_BY_VALUE[filter.value] = filter
end
-- The order in a zone, as the settings' "Order in a zone" (settings.trackerOrder), from the sort button's menu
local SORT_CHOICES = {
    { value = "number", label = "As tracked" }, { value = "distance", label = "Nearest" },
    { value = "level", label = "By level" }, { value = "progress", label = "Most done" },
}
local FILTER_BUTTON_SIZE, FILTER_BUTTON_GAP = 18, 2

---@return string filter The filter chosen: "all", "here", "ready" or "focus"
function Tracker.getFilter()
    local filter = ns.settings.trackerFilter
    return FILTERS_BY_VALUE[filter] and filter or "all"
end

---Chooses a filter; the chosen one clicked again goes back to all quests.
local function chooseFilter(value)
    ns.settings.trackerFilter = (Tracker.getFilter() == value and value ~= "all") and "all" or value
    scrollOffset = 0
    Tracker.refresh()
end

---@return table[] groups The zones and quests the filter keeps (a zone kept is a light copy of the model's, with
---only its kept quests; for Ready and Focus it is open whatever was chosen for it)
---@return number hiddenCount The quests the filter leaves out
---@return table counts How many each filter keeps: all, here, ready, focus
local function filterGroups(model)
    local filter = Tracker.getFilter()
    local counts = { all = 0, here = 0, ready = 0, focus = model.activeQuestId and 1 or 0 }
    for _, group in ipairs(model.groups) do
        for _, entry in ipairs(group.entries) do
            counts.all = counts.all + 1
            counts.here = counts.here + (group.isCurrent and 1 or 0)
            counts.ready = counts.ready + (entry.isTurnIn and 1 or 0)
        end
    end
    if filter == "all" then
        return model.groups, 0, counts
    end
    local kept, hiddenCount = {}, 0
    for _, group in ipairs(model.groups) do
        local entries = {}
        for _, entry in ipairs(group.entries) do
            local isKept = (filter == "here" and group.isCurrent) or (filter == "ready" and entry.isTurnIn)
                or (filter == "focus" and entry.questId == model.activeQuestId)
            if isKept then
                entries[#entries + 1] = entry
            else
                hiddenCount = hiddenCount + 1
            end
        end
        if #entries > 0 then
            kept[#kept + 1] = setmetatable({ entries = entries, isCollapsed = filter == "here" and group.isCollapsed or false }, { __index = group })
        end
    end
    return kept, hiddenCount, counts
end
Tracker.filterGroups = filterGroups

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

---@return boolean isFolded The tracker is folded to its title: by its "-", or for the moment (in combat, in a
---dungeon, as the player chose) unless the player unfolded it for that moment
function Tracker.isFolded()
    return ns.settings.isTrackerFolded == true or (Tracker.getSituation() == "fold" and not isMomentFoldUndone)
end

---The fold button, or a click on the band: folds the tracker, or unfolds it. Folded for a fight or a dungeon, it
---unfolds for the rest of that moment, and the player's own fold is left as it was, so it folds again next time.
function Tracker.toggleFold()
    local isMomentFolded = Tracker.getSituation() == "fold"
    if Tracker.isFolded() then
        ns.settings.isTrackerFolded = false
        isMomentFoldUndone = isMomentFolded
    elseif isMomentFolded then
        isMomentFoldUndone = false -- folded again for the rest of the moment
    else
        ns.settings.isTrackerFolded = true
    end
    Tracker.refresh()
end

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

local GRIP_CHECK_SECONDS = 0.1

---The grip at the left end of the title, for dragging the tracker wider or narrower: two gold arrows, pointing out,
---either side of a bar, as the game's own sizing handles look; the game's sizing cursor over it. Shown while the
---pointer is on the title or just left of it (checked a few times a second, so moving onto the grip never hides
---it), and while the tracker is not locked. The tracker keeps its right edge, so it grows to the left.
-- The soft bands: dark only behind each zone and quest, fading out at both ends (settings.trackerBackground
-- "bands"). Three textures a band, from a pool; placed at each drawing, set again only when their place changed.
local BAND_FADE_LEFT, BAND_FADE_RIGHT = 10, 28
local bands, usedBandCount = {}, 0
local isResizing -- the resize mode's outline shows (declared here for the band's button; set with the outline)
local filterFade -- the filters' buttons coming in
local filterCounts = {} -- how many quests each filter keeps, for the buttons' tooltips

local function createBand()
    local band = { parts = {} }
    for index = 1, 3 do
        local part = content:CreateTexture(nil, "BACKGROUND", nil, -2)
        part:SetColorTexture(1, 1, 1, 1)
        band.parts[index] = part
    end
    return band
end

local function setBandAlpha(band, alpha)
    if band.alpha == alpha then
        return
    end
    band.alpha = alpha
    local left, middle, right = band.parts[1], band.parts[2], band.parts[3]
    middle:SetColorTexture(0, 0, 0, alpha)
    if left.SetGradient and CreateColor then
        left:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, alpha))
        right:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, alpha), CreateColor(0, 0, 0, 0))
    else
        left:SetColorTexture(0, 0, 0, alpha / 2)
        right:SetColorTexture(0, 0, 0, alpha / 2)
    end
end

---Puts the next band behind the lines from top to bottom (in the content's units).
local function placeBand(top, bottom)
    usedBandCount = usedBandCount + 1
    local band = bands[usedBandCount]
    if not band then
        band = createBand()
        bands[usedBandCount] = band
    end
    setBandAlpha(band, Tracker.getBackgroundOpacity())
    local width = getWidth() + 2 * SIDE_MARGIN - 4
    if band.top ~= top or band.bottom ~= bottom or band.width ~= width then
        band.top, band.bottom, band.width = top, bottom, width
        local height = math.max(bottom - top + 2, 1)
        local left, middle, right = band.parts[1], band.parts[2], band.parts[3]
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(top - 1))
        left:SetSize(BAND_FADE_LEFT, height)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", content, "TOPLEFT", 2 + width, -(top - 1))
        right:SetSize(BAND_FADE_RIGHT, height)
        middle:ClearAllPoints()
        middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
        middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", 0, 0)
    end
    if not band.isShownNow then
        band.isShownNow = true
        for _, part in ipairs(band.parts) do
            part:Show()
        end
    end
end

local function showFilterTooltip(button)
    local filter = button.filter
    local counts = filterCounts
    GameTooltip:SetOwner(button, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(ns.L(filter.label) .. (counts[filter.value] and string.format(" |cff9a9a9a(%d)|r", counts[filter.value]) or ""), 1, 1, 1)
    GameTooltip:AddLine(ns.L(filter.note), TAN[1], TAN[2], TAN[3], true)
    if filter.value ~= "all" and Tracker.getFilter() == filter.value then
        GameTooltip:AddLine(ns.L("Click again for all quests."), GREY[1], GREY[2], GREY[3], true)
    end
    GameTooltip:Show()
end

local sortMenu -- the sort button's menu while open: the band's buttons stay while it does (closing the button closes it)

local function openSortMenu(owner)
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        return
    end
    local function isChosen(value)
        return (ns.settings.trackerOrder or "number") == value
    end
    local function choose(value)
        ns.settings.trackerOrder = value
        Tracker.refresh()
    end
    local function isPreset(preset)
        return ns.Spoilers.getPreset() == preset
    end
    sortMenu = ns.openMenu(owner, function(_, root)
        ns.Widgets.setMenuFonts(root) -- Czech letters in the game's menu
        root:CreateTitle(ns.L("Order in a zone"))
        for _, choice in ipairs(SORT_CHOICES) do
            root:CreateRadio(ns.L(choice.label), isChosen, choose, choice.value)
        end
        -- A quick switch of how much is told (Spoilers): the four presets in a submenu, the one on checked (none
        -- while it is changed by hand); a menu without submenus lists them under it
        root:CreateDivider()
        local submenu = root:CreateButton(ns.L("Spoilers: %s", ns.L(ns.Spoilers.getPresetName(ns.Spoilers.getPreset()))))
        local parent = type(submenu) == "table" and type(submenu.CreateRadio) == "function" and submenu or root
        for _, preset in ipairs(ns.Spoilers.PRESET_ORDER) do
            parent:CreateRadio(ns.L(ns.Spoilers.getPresetName(preset)), isPreset, ns.Spoilers.setPreset, preset)
        end
    end)
end

---A small square button of the band: dark with a bronze rim, gold-rimmed while chosen, the game's art in it.
local function createBandButton(parent, atlas, file)
    local button = CreateFrame("Button", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    button:SetSize(FILTER_BUTTON_SIZE, FILTER_BUTTON_SIZE)
    if button.SetBackdrop then
        button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    end
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(13, 13)
    button.icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    if file then
        button.icon:SetTexture(file)
    elseif button.icon.SetAtlas then
        button.icon:SetAtlas(atlas)
    end
    local glow = button:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(button)
    glow:SetColorTexture(1, 0.82, 0, 0.15)
    button.isChosen = nil
    return button
end

local function setBandButtonChosen(button, isChosen)
    if button.isChosen == isChosen then
        return
    end
    button.isChosen = isChosen
    if button.SetBackdropColor then
        if isChosen then
            button:SetBackdropColor(0.42, 0.29, 0.11, 0.95)
            button:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
        else
            button:SetBackdropColor(0.04, 0.03, 0.02, 0.85)
            button:SetBackdropBorderColor(0.42, 0.3, 0.16, 1)
        end
    end
    button.icon:SetDesaturated(not isChosen)
    button.icon:SetAlpha(isChosen and 1 or 0.85)
end

---The filters and the sort button, at the band's right end; hidden until the pointer is on the band.
function Tracker.createFilterBar()
    local bar = CreateFrame("Frame", nil, frame.header)
    bar:SetHeight(FILTER_BUTTON_SIZE)
    bar:SetWidth((#FILTERS + 2) * (FILTER_BUTTON_SIZE + FILTER_BUTTON_GAP) + 6)
    bar:SetPoint("RIGHT", frame.header, "RIGHT", -3, 0)
    bar:SetFrameLevel((frame.header:GetFrameLevel() or 1) + 3)
    bar.buttons = {}
    for index, filter in ipairs(FILTERS) do
        local button = createBandButton(bar, filter.atlas)
        if filter.iconSize then
            button.icon:SetSize(filter.iconSize, filter.iconSize)
        end
        button.filter = filter
        button:SetPoint("LEFT", bar, "LEFT", (index - 1) * (FILTER_BUTTON_SIZE + FILTER_BUTTON_GAP), 0)
        button:SetScript("OnClick", function() chooseFilter(filter.value) end)
        button:SetScript("OnEnter", showFilterTooltip)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.buttons[filter.value] = button
    end
    local rule = bar:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(0.42, 0.3, 0.16, 1)
    rule:SetSize(1, FILTER_BUTTON_SIZE - 4)
    rule:SetPoint("LEFT", bar, "LEFT", #FILTERS * (FILTER_BUTTON_SIZE + FILTER_BUTTON_GAP) + 1, 0)
    local sort = createBandButton(bar, "auctionhouse-ui-sortarrow")
    sort:SetPoint("LEFT", rule, "RIGHT", 4, 0)
    setBandButtonChosen(sort, false)
    sort:SetScript("OnClick", openSortMenu)
    sort:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L("Order in a zone"), 1, 1, 1)
        for _, choice in ipairs(SORT_CHOICES) do
            if (ns.settings.trackerOrder or "number") == choice.value then
                GameTooltip:AddLine(ns.L(choice.label), TAN[1], TAN[2], TAN[3])
            end
        end
        if ns.Spoilers.isActive() then
            GameTooltip:AddLine(ns.L("Spoilers: %s", ns.L(ns.Spoilers.getPresetName(ns.Spoilers.getPreset()))), TAN[1], TAN[2], TAN[3])
        end
        GameTooltip:Show()
    end)
    sort:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local resize = createBandButton(bar, nil, "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetPoint("LEFT", sort, "RIGHT", FILTER_BUTTON_GAP, 0)
    setBandButtonChosen(resize, false)
    resize:SetScript("OnClick", function() Tracker.toggleResizing() end)
    resize:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(ns.L("Resize"), 1, 1, 1)
        GameTooltip:AddLine(ns.L("Shows its outline: drag the arrows to make it wider, narrower, taller or shorter."), TAN[1], TAN[2], TAN[3], true)
        GameTooltip:Show()
    end)
    resize:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.resize = resize
    -- Comes in softly, as the game's own controls do on hover
    local group = bar.CreateAnimationGroup and bar:CreateAnimationGroup()
    local alpha = type(group) == "table" and type(group.CreateAnimation) == "function" and group:CreateAnimation("Alpha")
    if type(alpha) == "table" and alpha.SetFromAlpha then
        alpha:SetFromAlpha(0)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.15)
        filterFade = group
    end
    bar:Hide()
    return bar
end

---The band's own parts, as at rest: the filters' buttons while the pointer is on it, else what is ready and the
---chosen filter's icon.
local function showBandParts()
    local isHovered = frame.filterBar:IsShown()
    local filter = Tracker.getFilter()
    frame.filterIcon:SetShown(filter ~= "all" and not isHovered)
    frame.readyText:SetShown(not isHovered)
    -- What is ready stands left of the filter's icon while one is on, else at the band's end
    local readyTo = filter ~= "all" and frame.filterIcon or nil
    if frame.readyTo ~= readyTo then
        frame.readyTo = readyTo
        frame.readyText:ClearAllPoints()
        if readyTo then
            frame.readyText:SetPoint("RIGHT", readyTo, "LEFT", -4, 0)
        else
            frame.readyText:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
        end
    end
end

---The resize button lit while the outline shows.
function Tracker.showResizeButton()
    if frame and frame.filterBar and frame.filterBar.resize then
        setBandButtonChosen(frame.filterBar.resize, isResizing == true)
    end
end

---Shows or hides the filters' buttons on the band.
function Tracker.setFiltersShown(isShown)
    local bar = frame.filterBar
    if bar:IsShown() == isShown then
        return
    end
    bar:SetShown(isShown)
    if isShown and filterFade then
        filterFade:Play()
    end
    showBandParts()
end

---Draws the title band: the fold arrow, the log's count, what is ready, the filters.
function Tracker.drawBand(isFolded, counts)
    frame.title:SetText(ns.L("Quests")) -- on every drawing, so a change of language shows
    ns.Widgets.setTextFont(frame.title, Look.getFont("header"))
    ns.Widgets.setTextFont(frame.countText, Look.getFont("text"))
    ns.Widgets.setTextFont(frame.readyText, Look.getFont("text"))
    if frame.isFoldedLook ~= isFolded then
        frame.isFoldedLook = isFolded
        for _, chevron in ipairs({ frame.foldIcon, frame.foldGlow }) do
            if chevron.SetRotation then
                chevron:SetRotation(isFolded and math.pi / 2 or 0) -- (the chevron points down; turned, to the right)
            end
        end
    end
    local count, max = ns.QuestState.getLogSize()
    local hasMax = type(max) == "number" and max > 0
    frame.countText:SetText(hasMax and string.format("%d/%d", count, max) or "")
    setColor(frame.countText, hasMax and max - count <= 2 and LOG_FILLING or COUNT_COLOR)
    frame.readyText:SetText(counts.ready > 0 and ns.Lp(counts.ready, "%d ready", "%d ready") or "")
    setColor(frame.readyText, GREEN)
    filterCounts = counts
    local filter = Tracker.getFilter()
    for value, button in pairs(frame.filterBar.buttons) do
        setBandButtonChosen(button, value == filter)
    end
    if filter ~= "all" and frame.filterIcon.SetAtlas and frame.filterAtlas ~= filter then
        frame.filterAtlas = filter
        frame.filterIcon:SetAtlas(FILTERS_BY_VALUE[filter].atlas)
    end
    showBandParts()
end

---Ten times a second, with the width grip (its watcher): the filters come in while the pointer is on the band, and
---the dark ground "on hover" while it is on the tracker. Only what changed is set.
function Tracker.watchHover()
    -- (kept while its sort menu is open, which closes with the button it came from, and while resizing)
    local isMenuOpen = type(sortMenu) == "table" and sortMenu.IsShown and sortMenu:IsShown() == true
    local isOnBand = frame.header:IsMouseOver() or (frame.filterBar:IsShown() and frame.filterBar:IsMouseOver())
        or isMenuOpen or isResizing == true
    if isOnBand ~= frame.filterBar:IsShown() then
        Tracker.setFiltersShown(isOnBand)
    end
    if Tracker.getBackgroundMode() == "hover" then
        local isOn = frame:IsMouseOver(4, -6, -SIDE_MARGIN - 4, SIDE_MARGIN + 4) == true
        if isOn ~= frame.isHovered then
            frame.isHovered = isOn
            frame.background:SetShown(isOn)
        end
    end
end

-- Its height: as tall as its quests, up to what fits between its top and the bottom of the screen, or less, as the
-- player chose (settings.trackerHeightShare: the most of the screen it takes, 0 for no more than fits); beyond that
-- it scrolls with the mouse wheel. Set by the grip under it, or in the settings.
local MIN_CHOSEN_HEIGHT = 60
local getMaxVisibleHeight -- (below, with the resize mode)
local drawnContentHeight = 0 -- the quests' whole height at the last drawing, for fitting again without drawing

---@return number? height The most the quests may take, in the tracker's units, as the player chose; nil: no limit
local function getChosenHeight()
    local share = tonumber(ns.settings.trackerHeightShare) or 0
    if share <= 0 or not UIParent then
        return nil
    end
    local screen = UIParent:GetHeight() * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    return math.max(MIN_CHOSEN_HEIGHT, screen * share - HEADER_HEIGHT)
end

---Fits the tracker's height to its quests (their whole height, contentHeight) and scrolls what does not fit.
---@return number visibleHeight What shows of the quests
function Tracker.fitHeight(contentHeight)
    drawnContentHeight = contentHeight
    local maxHeight = getMaxVisibleHeight()
    local visibleHeight = math.min(contentHeight, maxHeight)
    local isScrollable = contentHeight > maxHeight
    scrollOffset = math.max(0, math.min(scrollOffset, contentHeight - visibleHeight))
    content:SetHeight(math.max(contentHeight, 1))
    scrollFrame:SetHeight(math.max(visibleHeight, 1))
    scrollFrame:SetVerticalScroll(scrollOffset)
    scrollFrame:EnableMouseWheel(isScrollable) -- only then, so the wheel still zooms the camera otherwise
    frame:SetHeight(HEADER_HEIGHT + visibleHeight)
    local hasAbove, hasBelow = scrollOffset > 0, scrollOffset < contentHeight - visibleHeight
    frame.moreAbove:SetShown(hasAbove)
    frame.moreBelow:SetShown(hasBelow)
    return visibleHeight
end

---@return number height The most of the quests that may show, in the tracker's units: what fits above the action bars,
---or less as the player chose
getMaxVisibleHeight = function()
    local top = frame:GetTop()
    local maxHeight = math.max((type(top) == "number" and top or 700) - HEADER_HEIGHT - BOTTOM_MARGIN, MIN_HEIGHT)
    local chosen = getChosenHeight()
    return chosen and math.min(maxHeight, chosen) or maxHeight, maxHeight
end

-- Resizing: the band's resize button shows the tracker's outline at the most it may take, with arrows to drag: the
-- left edge for the width, the bottom edge for the height, the bottom-left corner for both. The tracker keeps its top
-- right corner where it is. Done, the button again, or Escape ends it. While an arrow is dragged, a new height only
-- fits the tracker again; a new width draws it again (its lines wrap to it), as the width grip did.
local RESIZE_HANDLE = 18
local resizeFrame
isResizing = false

local function getScreenHeight()
    return UIParent:GetHeight() * UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
end

---Places the outline at the tracker's width and the most it may take, with the size written in it.
function Tracker.placeOutline()
    if not resizeFrame or not resizeFrame:IsShown() then
        return
    end
    local width = getWidth()
    local height = HEADER_HEIGHT + getMaxVisibleHeight()
    resizeFrame:SetSize(width + 2 * SIDE_MARGIN + 4, height + 4)
    resizeFrame.size:SetText(string.format("%d × %d", math.floor(width + 0.5), math.floor(height + 0.5)))
end

local function createResizeHandle(kind)
    local handle = CreateFrame("Button", nil, resizeFrame)
    handle.kind = kind
    local ground = handle:CreateTexture(nil, "BACKGROUND")
    ground:SetAllPoints(handle)
    ground:SetColorTexture(0, 0, 0, 0.75)
    local glow = handle:CreateTexture(nil, "HIGHLIGHT")
    glow:SetAllPoints(handle)
    glow:SetColorTexture(1, 0.82, 0, 0.2)
    local function addArrow(point, x, y, rotation)
        local arrow = handle:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(MEDIA .. "ChevronDown")
        arrow:SetSize(10, 10)
        arrow:SetPoint(point, handle, point, x, y)
        arrow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
        if arrow.SetRotation then
            arrow:SetRotation(rotation)
        end
    end
    if kind == "width" then
        handle:SetSize(RESIZE_HANDLE, 44)
        handle:SetPoint("CENTER", resizeFrame, "LEFT", 0, 0)
        addArrow("TOP", 0, -4, -math.pi / 2)
        addArrow("BOTTOM", 0, 4, math.pi / 2)
    elseif kind == "height" then
        handle:SetSize(44, RESIZE_HANDLE)
        handle:SetPoint("CENTER", resizeFrame, "BOTTOM", 0, 0)
        addArrow("LEFT", 4, 0, math.pi)
        addArrow("RIGHT", -4, 0, 0)
    else
        handle:SetSize(RESIZE_HANDLE + 4, RESIZE_HANDLE + 4)
        handle:SetPoint("CENTER", resizeFrame, "BOTTOMLEFT", 0, 0)
        local grabber = handle:CreateTexture(nil, "ARTWORK")
        grabber:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
        grabber:SetTexCoord(1, 0, 0, 1) -- the game's corner grabber, turned to the bottom-left corner
        grabber:SetPoint("CENTER", handle, "CENTER", 0, 0)
        grabber:SetSize(16, 16)
        grabber:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    end
    handle:SetScript("OnMouseDown", function(self)
        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        self.startX, self.startY = x / scale, y / scale
        self.startWidth, self.startHeight = getWidth(), getMaxVisibleHeight()
        self:SetScript("OnUpdate", function()
            local cursorX, cursorY = GetCursorPosition()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            if self.kind ~= "height" then
                local width = math.floor(math.max(MIN_WIDTH, math.min(MAX_WIDTH, self.startWidth + self.startX - cursorX)) + 0.5)
                if width ~= getWidth() then
                    ns.settings.trackerWidth = width
                    Tracker.refresh()
                end
            end
            if self.kind ~= "width" then
                local _, room = getMaxVisibleHeight()
                local wanted = math.max(MIN_CHOSEN_HEIGHT, math.min(room, self.startHeight + self.startY - cursorY))
                local share = math.floor((wanted + HEADER_HEIGHT) / getScreenHeight() * 1000 + 0.5) / 1000
                if share ~= ns.settings.trackerHeightShare then
                    ns.settings.trackerHeightShare = share
                    Tracker.fitHeight(drawnContentHeight)
                end
            end
            Tracker.placeOutline()
        end)
    end)
    handle:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        Tracker.refresh() -- the item buttons follow what shows now
    end)
    handle:SetScript("OnEnter", function(self)
        if SetCursor then
            pcall(SetCursor, "UI_RESIZE_CURSOR")
        end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L(self.kind == "width" and "Drag: wider or narrower" or self.kind == "height" and "Drag: taller or shorter"
            or "Drag: wider, narrower, taller or shorter"), 1, 1, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if ResetCursor then
            ResetCursor()
        end
    end)
    return handle
end

local function createResizeFrame()
    resizeFrame = CreateFrame("Frame", "OneMoreQuestTrackerResize", frame)
    resizeFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", SIDE_MARGIN + 2, 2)
    resizeFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 30)
    local fill = resizeFrame:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(resizeFrame)
    fill:SetColorTexture(1, 0.82, 0, 0.06)
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local edge = resizeFrame:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.9)
        edge:SetPoint(side[1], resizeFrame, side[1], 0, 0)
        edge:SetPoint(side[2], resizeFrame, side[2], 0, 0)
        if side[1] == "TOPLEFT" and side[2] == "BOTTOMLEFT" or side[1] == "TOPRIGHT" then
            edge:SetWidth(2)
        else
            edge:SetHeight(2)
        end
    end
    resizeFrame.size = ns.Widgets.createFontString(resizeFrame, "OVERLAY", "GameFontHighlight")
    resizeFrame.size:SetPoint("BOTTOM", resizeFrame, "BOTTOM", 0, 50)
    local done = CreateFrame("Button", nil, resizeFrame, "UIPanelButtonTemplate")
    done:SetSize(84, 22)
    done:SetPoint("BOTTOMRIGHT", resizeFrame, "BOTTOM", -4, 18)
    done:SetText(ns.L("Done"))
    done:SetScript("OnClick", function() resizeFrame:Hide() end)
    local reset = CreateFrame("Button", nil, resizeFrame, "UIPanelButtonTemplate")
    reset:SetSize(84, 22)
    reset:SetPoint("BOTTOMLEFT", resizeFrame, "BOTTOM", 4, 18)
    reset:SetText(ns.L("Put back"))
    reset:SetScript("OnClick", function()
        ns.settings.trackerWidth, ns.settings.trackerHeightShare = nil, 0 -- as wide as it started, as tall as fits
        Tracker.refresh()
        Tracker.placeOutline()
    end)
    resizeFrame.done, resizeFrame.reset = done, reset
    for _, kind in ipairs({ "width", "height", "both" }) do
        createResizeHandle(kind)
    end
    resizeFrame:SetScript("OnHide", function()
        isResizing = false
        Tracker.showResizeButton()
    end)
    resizeFrame:Hide()
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "OneMoreQuestTrackerResize") -- Escape ends it, as the game's own windows close
    end
end

---Turns the resize mode on or off (the band's resize button).
function Tracker.toggleResizing()
    if not resizeFrame then
        createResizeFrame()
    end
    isResizing = not isResizing
    resizeFrame:SetShown(isResizing)
    if isResizing then
        Tracker.placeOutline()
    end
    Tracker.showResizeButton()
end

---@return boolean isResizing The outline is shown
function Tracker.isResizing()
    return isResizing
end

---The hover watcher: ten times a second, while the tracker shows, the band's buttons and the dark ground on hover
---follow the pointer (Tracker.watchHover). One small frame, no script per row.
local function createWatcher()
    local watcher = CreateFrame("Frame", nil, frame)
    local elapsed = 0
    watcher:SetScript("OnUpdate", function(_, seconds)
        elapsed = elapsed + seconds
        if elapsed < GRIP_CHECK_SECONDS then
            return
        end
        elapsed = 0
        Tracker.watchHover()
    end)
    return watcher
end

---@return number? questId The game's own focus (its super-tracked quest), when it is a quest in the log
function Tracker.create()
    frame = CreateFrame("Frame", "TrailheadTracker", UIParent)
    -- Under every window, as the game's own quest tracker: in one layer a frame's parts sort by level, and the
    -- tracker's rows would draw over the quest window's page when the map is moved over it
    frame:SetFrameStrata("LOW")
    isInCombat = InCombatLockdown and InCombatLockdown() == true -- a reload in a fight starts in it
    frame:SetSize(WIDTH, 20)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    -- Its place is this addon's to keep (settings.position), never the game's: a named frame dragged by StartMoving
    -- is marked as placed by the player, and the game then writes it to its own layout file and puts it back from
    -- there at the next login, over the place kept here (the tracker seemed to forget where it was put)
    forgetGamePlacement()
    -- Its size first: the place saved is in the tracker's own units at that size, so put on at any other size it
    -- would be somewhere else, and kept there (Tracker.applySize), moving it a little further at every login
    frame:SetScale(getScale())
    applyPosition()

    frame.header = CreateFrame("Button", nil, frame)
    frame.header:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.header:SetSize(WIDTH, 22)
    frame.header:RegisterForDrag("LeftButton")
    frame.header:SetScript("OnDragStart", function()
        frame.header.wasDragged = true -- (the press ends a drag, not a click)
        if not ns.settings.isLocked then
            frame:StartMoving()
        end
    end)
    -- A click on the band folds the tracker to it, or unfolds it, as its arrow does
    frame.header:RegisterForClicks("LeftButtonUp")
    frame.header:SetScript("OnMouseDown", function(self) self.wasDragged = false end)
    frame.header:SetScript("OnClick", function(self)
        if self.wasDragged then
            return
        end
        Tracker.toggleFold()
    end)
    frame.header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        forgetGamePlacement()
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
    -- The game's own tracker arrow at the left folds the tracker to its band, and back
    frame.foldButton = CreateFrame("Button", nil, frame.header)
    frame.foldButton:SetSize(16, 16)
    frame.foldButton:SetPoint("LEFT", frame.header, "LEFT", 2, 0)
    -- A plain gold chevron, as the tracker's scroll arrows: down while open, to the right while folded; lit on hover
    frame.foldIcon = frame.foldButton:CreateTexture(nil, "ARTWORK")
    frame.foldIcon:SetTexture(MEDIA .. "ChevronDown")
    frame.foldIcon:SetSize(12, 12)
    frame.foldIcon:SetPoint("CENTER", frame.foldButton, "CENTER", 0, 0)
    frame.foldIcon:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1)
    frame.foldGlow = frame.foldButton:CreateTexture(nil, "HIGHLIGHT")
    frame.foldGlow:SetTexture(MEDIA .. "ChevronDown")
    frame.foldGlow:SetAllPoints(frame.foldIcon)
    frame.foldGlow:SetBlendMode("ADD")
    frame.foldGlow:SetAlpha(0.6)
    frame.foldButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(ns.L(Tracker.isFolded() and "Unfold the tracker" or "Fold the tracker"), 1, 1, 1)
        GameTooltip:Show()
    end)
    frame.foldButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.foldButton:SetScript("OnClick", Tracker.toggleFold)
    frame.title = ns.Widgets.createFontString(frame.header, "OVERLAY", _G.GameFontNormalMed2 and "GameFontNormalMed2" or "GameFontNormal")
    frame.title:SetPoint("LEFT", frame.foldButton, "RIGHT", 3, 0)
    frame.title:SetText(ns.L("Quests"))
    -- The log's places: its count, orange as the last places go
    frame.countText = remember(ns.Widgets.createFontString(frame.header, "OVERLAY", "GameFontHighlightSmall"))
    frame.countText:SetPoint("LEFT", frame.title, "RIGHT", 6, 0)
    -- At the right: what is ready to hand in, and the chosen filter's icon while one is on
    frame.filterIcon = remember(frame.header:CreateTexture(nil, "OVERLAY"))
    frame.filterIcon:SetSize(13, 13)
    frame.filterIcon:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
    frame.filterIcon:Hide()
    frame.readyText = remember(ns.Widgets.createFontString(frame.header, "OVERLAY", "GameFontHighlightSmall"))
    frame.readyText:SetPoint("RIGHT", frame.header, "RIGHT", -6, 0)
    frame.filterBar = Tracker.createFilterBar()

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
    createWatcher()
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

local lastProgress = {} -- [questId] = { done = objectives counted up, isReady = boolean, look = noteCount } at the last refresh
local noteCount = 0 -- refreshes so far: which quests were looked at in this one
local pendingFlashes = {} -- [questId] = colour of a flash still to play
local flashes = {} -- [questId] = the quest's flash texture, made when first needed
local fadeGroups = {} -- [questId] = the animation that fades the flash out

---Notes what moved since the last look: a count went up, or the quest became ready to hand in. The first look
---after logging in only takes note, so nothing flashes for progress made before. A quest not drawn (the tracker
---or its zone folded, a filter) is looked at too: it still rings when ready, but has no lines to flash.
---@param isDrawn boolean Its lines are on the tracker this time
local function noteProgress(entry, isDrawn)
    local done = 0
    for _, objective in ipairs(entry.objectives) do
        done = done + (objective.fulfilled or 0) + (objective.isFinished and 1 or 0)
    end
    local last = lastProgress[entry.questId]
    if last then
        local isFlashing = isDrawn and ns.settings.shouldFlashProgress
        if entry.isTurnIn and not last.isReady then
            pendingFlashes[entry.questId] = isFlashing and GREEN or nil
            if ns.settings.shouldPlayReadySound and PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
                PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
            end
        elseif done > last.done then
            pendingFlashes[entry.questId] = isFlashing and GOLD or nil
        end
        last.done, last.isReady, last.look = done, entry.isTurnIn == true, noteCount
    else
        lastProgress[entry.questId] = { done = done, isReady = entry.isTurnIn == true, look = noteCount }
    end
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

---The waypoint follows the quest in focus, where its place may be told (in Guide always); else this addon's goes.
local function followFocused(activeEntry)
    if isSpoiling and activeEntry and not isPlaceTold(activeEntry) then
        activeEntry = nil
    end
    ns.Waypoints.followFocusedQuest(activeEntry)
end

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
        return
    elseif isMoved then
        local key, activeEntry = getOrderKey(ns.Model.compose(ns.Focus.getPicked()))
        if not refreshedAt or key ~= drawnOrderKey or (position and position.uiMapId) ~= refreshedAt.uiMapId then
            Tracker.refresh()
            return
        end
        followFocused(activeEntry)
        refreshedAt.north, refreshedAt.west = position and position.north, position and position.west
    end
    -- Now and then, while "Need a hint?" may offer itself: drawn again once a quest's offer came (or went)
    if isOfferWatched then
        local now = GetTime and GetTime() or 0
        if now >= offerCheckAt then
            offerCheckAt = now + OFFER_CHECK_SECONDS
            for index = 1, drawnOfferCount do
                if ns.Spoilers.isHintOffered(drawnOfferQuestIds[index]) ~= drawnOffers[index] then
                    Tracker.refresh()
                    return
                end
            end
        end
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
    -- Whether anything is held back, asked once for the whole drawing (Spoilers)
    isSpoiling = ns.Spoilers.isActive()
    isOfferWatched = isSpoiling and ns.Spoilers.getChoice("hints") == "offered"
    drawnOfferCount = 0
    local activeEntry
    drawnOrderKey, activeEntry = getOrderKey(model)
    followFocused(activeEntry)

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
    if situation ~= "fold" then
        isMomentFoldUndone = false -- the moment is over: the next one folds it again
    end
    local isFolded = Tracker.isFolded()
    -- The text's font, outline, shadow and sizes (set again only when a setting changed), and the lines' heights
    Look.apply()
    rowHeights.title = Look.getRowHeight("title", 17)
    rowHeights.text = Look.getRowHeight("text", 15)
    rowHeights.zone = Look.getRowHeight("zone", 16)
    local shownGroups, hiddenCount, counts = filterGroups(model)
    noteCount = noteCount + 1
    Tracker.drawBand(isFolded, counts)
    local isBanded = Tracker.getBackgroundMode() == "bands"
    usedBandCount = 0
    for _, group in ipairs(isFolded and {} or shownGroups) do
        local zoneTop = cursor
        addZoneRow(group)
        if isBanded then
            placeBand(zoneTop, cursor)
        end
        if not group.isCollapsed then
            for _, entry in ipairs(group.entries) do
                addGap(4)
                local isActive = entry.questId == activeQuestId
                noteProgress(entry, true)
                local top, bottom = addQuestRows(entry, isActive)
                if isBanded then
                    placeBand(top, bottom)
                end
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
    -- The quests not drawn this time, looked at all the same: one made ready meanwhile still rings
    for _, group in ipairs(model.groups) do
        for _, entry in ipairs(group.entries) do
            local last = lastProgress[entry.questId]
            if not last or last.look ~= noteCount then
                noteProgress(entry, false)
            end
        end
    end
    -- What the filter leaves out, said under what it keeps
    if not isFolded and hiddenCount > 0 then
        -- The filter kept nothing: said plainly first
        local filter = Tracker.getFilter()
        if #shownGroups == 0 then
            addInfoRow(ns.L(filter == "focus" and "No quest in focus" or filter == "ready" and "No quest ready to hand in"
                or "No quest in this zone"), GREY)
        end
        addInfoRow(ns.Lp(hiddenCount, "%d more hidden by the filter", "%d more hidden by the filter"), GREY)
    end
    flushRow()
    for index = usedRowCount + 1, #rows do
        rows[index]:Hide()
    end
    for index = usedBandCount + 1, #bands do
        local band = bands[index]
        if band.isShownNow then
            band.isShownNow = false
            for _, part in ipairs(band.parts) do
                part:Hide()
            end
        end
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

    local visibleHeight = Tracker.fitHeight(cursor)
    if isResizing then
        Tracker.placeOutline()
    end

    local isShown = ns.settings.isShown and model.questCount > 0 and situation ~= "hide"
    local backgroundMode = Tracker.getBackgroundMode()
    frame.background:SetShown(backgroundMode == "box" or (backgroundMode == "hover" and frame.isHovered == true))
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
    if ns.GamepadTracker then
        ns.GamepadTracker.handleDrawn() -- a controller's cursor on it: its stops and prompts again
    end
end

---@return Frame? frame The tracker
function Tracker.getFrame()
    return frame
end

---@return Button[] rows The tracker's rows (pooled: the first count of them are drawn)
---@return number count
function Tracker.getRows()
    return rows, usedRowCount
end

---@return boolean isFocused The quest is the one in focus
function Tracker.isFocused(questId)
    return questId ~= nil and questId == activeQuestId
end

Tracker.toggleFocus = toggleFocus

---Scrolls the tracker so one of its rows is in full view (a controller's cursor walked onto it), when it scrolls.
function Tracker.bringRowIntoView(row)
    local top, height = row.want and row.want.top, row.want and row.want.height
    local visible = scrollFrame and scrollFrame:GetHeight()
    if not top or not height or not visible then
        return
    end
    local wanted = scrollOffset
    if top < scrollOffset then
        wanted = math.max(0, top - 16) -- (with its zone's heading or the quest before it, when there is room)
    elseif top + height > scrollOffset + visible then
        wanted = top + height - visible + 4
    end
    if wanted ~= scrollOffset then
        scrollOffset = wanted
        Tracker.refresh()
    end
end

---@return { left: string, right: string, isHint: boolean }[] lines What the last drawing's lines say, top to bottom
---(for the tests)
function Tracker.getDrawnLines()
    local lines = {}
    for index = 1, usedRowCount do
        local row = rows[index]
        lines[index] = { left = tostring(row.want.leftText), right = tostring(row.want.rightText), isHint = row.isHintLine, row = row }
    end
    return lines
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
    events = {
        -- Put back where it was kept once the world is entered, in case the game placed it from its own layout
        -- file after it was made (a place it kept from before this addon told it not to)
        PLAYER_ENTERING_WORLD = function()
            if frame and ns.settings.position then
                applyPosition()
            end
        end,
    },
    refresh = Tracker.refresh,
    tick = Tracker.tick, -- distances change as the player moves, and time left counts down
    afterCombat = Tracker.refresh, -- quest item buttons could not move during the fight
})
