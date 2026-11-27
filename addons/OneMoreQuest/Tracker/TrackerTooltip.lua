local _, ns = ...

-- The tooltips of the tracker's rows: a quest's (its objectives and what drops their items, the kills for those drops,
-- its chain and the quests around it, the party's progress, what the clicks do), the line of its zones' and "Need a
-- hint?"'s. As much as the spoiler choices let tell, asked on the hover, never at a drawing.
local TrackerTooltip = {}
ns.TrackerTooltip = TrackerTooltip

local COLORS = ns.TrackerLook.COLORS
local TAN, GREY, GREEN = COLORS.tan, COLORS.grey, COLORS.green
local HEADING = { 1, 0.82, 0 } -- a section's heading in the tooltip
local DROP_NOTE_COLOR = { 0.7, 0.7, 0.7 } -- as the map's tooltip writes what drops an item
local MAX_DROP_SOURCES = 3

---A line of the row's tooltip in one of the tracker's colours.
---@param isWrapped boolean? Wrapped to the tooltip's width
local function addLine(text, color, isWrapped)
    GameTooltip:AddLine(text, color[1], color[2], color[3], isWrapped)
end

---@return string text "Turn in to Sergra Darkthorn", or, while who and where is held back, only that it is ready
function TrackerTooltip.composeTurnInText(entry, isTold)
    if not isTold then
        return ns.L("Ready to turn in")
    end
    return ns.L("Turn in to %s", entry.finisherName or ns.L("the quest giver"))
end

---@return string line A quest as the tooltip lists it: "[12] The quest's name"
local function formatQuestLine(questId)
    local name = ns.QuestText.getQuestName(questId) or ns.L("Quest %s", questId)
    return string.format("[%d] %s", ns.Database.getQuestField(questId, "questLevel") or 0, name)
end

---What drops an item objective's item, as much as the spoiler choice lets tell: with the chances (the map's tooltip's
---own lines), the creatures' names alone, only those that dropped it for the player, or nothing.
---@param choice string Spoilers' "drops" for the quest
local function addDropLines(questId, typeIndex, choice)
    if choice == "chances" then
        ns.MapHover.addDropLines(GameTooltip, questId, typeIndex)
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
            addLine(ns.Lp(#sources - MAX_DROP_SOURCES, "   + %d more", "   + %d more"), DROP_NOTE_COLOR)
            break
        end
        if choice == "names" or ns.Spoilers.hasSeenDrop(itemId, source.npcId or source.objectId) then
            addLine("   " .. source.name, DROP_NOTE_COLOR)
        end
    end
end

---The quest's objectives with their counts; under an item still to get, what drops it (or holds it) and how often, as
---the map's tooltip says.
local function addObjectiveLines(entry, drops)
    local itemIndex = 0 -- (the item objectives counted, as the database numbers them)
    for _, objective in ipairs(entry.objectives) do
        local status = objective.required > 1 and (objective.fulfilled .. "/" .. objective.required)
            or objective.isFinished and ns.L("done")
            or ""
        GameTooltip:AddDoubleLine((objective.shownLabel or objective.label), status, 1, 1, 1, 1, 1, 1)
        if objective.type == "item" then
            itemIndex = itemIndex + 1
            if not objective.isFinished then
                addDropLines(entry.questId, itemIndex, drops)
            end
        end
    end
end

---@return string text About how many kills the rest of an item takes: "About 6 more kills for the rest", with the
---party sharing the loot how many share it
local function composeRestText(progress)
    local remaining = math.floor(progress.remaining + 0.5)
    if (progress.sharerCount or 1) > 1 then
        return ns.Lp(
            remaining,
            "About %d more kill for the rest, the loot shared by %d",
            "About %d more kills for the rest, the loot shared by %d",
            progress.sharerCount
        )
    end
    return ns.Lp(remaining, "About %d more kill for the rest", "About %d more kills for the rest")
end

---One item's kills: its chance, the kills against the kills expected (green, or red when unlucky), what was collected
---before counting started, and about what the rest takes.
local function addKillLines(objective, progress)
    local red, green, blue = 1, 1, 1
    if progress.kills > 0 then
        local isUnlucky = progress.isUnlucky
        red, green, blue = isUnlucky and 1 or 0.5, isUnlucky and 0.48 or 0.88, isUnlucky and 0.35 or 0.5
    end
    GameTooltip:AddDoubleLine(
        (objective.shownLabel or objective.label) .. " (" .. ns.Drops.formatChance(progress.chance) .. ")",
        ns.KillCounter.formatKills(progress, ", "),
        1,
        1,
        1,
        red,
        green,
        blue
    )
    if (progress.earlierDrops or 0) > 0 then
        addLine(
            ns.Lp(progress.earlierDrops, "%d collected before counting started", "%d collected before counting started"),
            GREY
        )
    end
    addLine(composeRestText(progress), GREY)
end

---Kills for the items that drop, under their heading (none while the chances are held back: KillCounter.getProgress
---tells nothing then).
local function addKillSection(entry)
    if not ns.settings.shouldCountKills or entry.isTurnIn then
        return
    end
    local isHeadingShown = false
    for index, objective in ipairs(entry.objectives) do
        local progress = not objective.isFinished
            and objective.type == "item"
            and ns.KillCounter.getProgress(entry.questId, index, objective)
        if progress then
            if not isHeadingShown then
                GameTooltip:AddLine(" ")
                addLine(ns.L("Kills for drops"), HEADING)
                isHeadingShown = true
            end
            addKillLines(objective, progress)
        end
    end
end

---The quest chain, as much as the spoiler choice lets tell: every step, or the steps so far and how many are left
---(never "hidden": the chain is left out then).
local function addChainLines(entry, choice)
    GameTooltip:AddLine(" ")
    addLine(ns.L("Quest chain, step %d of %d", entry.chainIndex, entry.chainTotal), HEADING)
    for position, chainQuestId in ipairs(ns.Chain.getQuestIds(entry.questId)) do
        if position > entry.chainIndex and choice ~= "all" then
            addLine(ns.Lp(entry.chainTotal - entry.chainIndex, "%d more step", "%d more steps"), TAN)
            break
        end
        local line = formatQuestLine(chainQuestId)
        if position < entry.chainIndex then
            GameTooltip:AddDoubleLine(line, ns.L("done"), GREY[1], GREY[2], GREY[3], GREY[1], GREY[2], GREY[3])
        elseif position == entry.chainIndex then
            GameTooltip:AddDoubleLine(line, ns.L("this quest"), 1, 1, 1, TAN[1], TAN[2], TAN[3])
        else
            addLine(line, TAN)
        end
    end
end

---Each of the linked quests on a line of its own, done ones grey.
---@param noteText string? What the right column says of one not done yet
local function addLinkedQuestLines(questIds, noteText)
    for _, linkedQuestId in ipairs(questIds) do
        local isDone = ns.QuestState.isTurnedIn(linkedQuestId)
        local color = isDone and GREY or TAN
        GameTooltip:AddDoubleLine(
            formatQuestLine(linkedQuestId),
            isDone and ns.L("done") or noteText or "",
            color[1],
            color[2],
            color[3],
            GREY[1],
            GREY[2],
            GREY[3]
        )
    end
end

---The quests around this one that are not its chain: what it followed, and what it unlocks (by name only where the
---story may be told).
local function addLinkLines(entry, canName)
    local requiredIds, unlockIds = entry.requiredIds or {}, entry.unlockIds or {}
    if #requiredIds > 0 then
        GameTooltip:AddLine(" ")
        addLine(ns.Chain.composeFollowText(requiredIds), HEADING)
        if #requiredIds > 1 then
            addLinkedQuestLines(requiredIds)
        end
    end
    if #unlockIds > 0 then
        GameTooltip:AddLine(" ")
        addLine(ns.Chain.composeUnlockText(unlockIds, canName), HEADING)
        if #unlockIds > 1 and canName then
            addLinkedQuestLines(unlockIds)
        end
    end
end

---That the map cannot show where some objectives are (it matters only where the map would show them).
local function addUnlocatedLine(entry, places)
    local count = entry.unlocatedCount or 0
    if count == 0 or (places ~= "exact" and places ~= "rough") then
        return
    end
    local text = count == 1
            and ns.L("The database has no location for one objective, so the map cannot show where to go.")
        or ns.Lp(
            count,
            "The database has no location for %d objective, so the map cannot show where to go.",
            "The database has no location for %d objectives, so the map cannot show where to go."
        )
    addLine(text, TAN, true)
end

---The same clicks as on a quest in the quest list, on its page and on its mark on the map. With a controller's cursor
---on the row, none: the prompt bar says what its buttons do.
local function addClickHint(entry)
    if ns.GamepadTracker and ns.GamepadTracker.isFocused() then
        return
    end
    local clickHint = ns.Tracker.isFocused(entry.questId)
            and "Click to open it in the quest log, ctrl-click to stop focusing, shift-click to link it in chat, right-click for more"
        or "Click to open it in the quest log, ctrl-click to focus it, shift-click to link it in chat, right-click for more"
    addLine(ns.L(clickHint), GREY, true)
    ns.QuestTooltip.addHint(GameTooltip)
end

---"Need a hint?": what a click on it gives.
local function showHintTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(ns.L("Need a hint?"), 1, 1, 1)
    addLine(
        ns.L(
            "Click for one step at a time: the zone, roughly where, then exactly where. A hint stays for this quest only."
        ),
        TAN,
        true
    )
    GameTooltip:Show()
end

---The line of zones: every one of them, and a click for the next on the map.
local function showZonesTooltip(row)
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    ns.MapDock.addZonesToTooltip(GameTooltip, row.entry)
    GameTooltip:Show()
end

---The tooltip of a tracker's row hovered (a quest's lines, the line of its zones, "Need a hint?"); nothing on a zone's
---heading.
---@param row Button The row, with the quest it is of (row.entry)
function TrackerTooltip.show(row)
    local entry = row.entry
    if not entry then
        return
    elseif row.isHintLine then
        showHintTooltip(row)
        return
    elseif row.isZonesLine then
        showZonesTooltip(row)
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    ns.QuestTooltip.watch(GameTooltip, row, TrackerTooltip.show, row) -- Shift down or up: filled again
    ns.QuestTooltip.addTitle(GameTooltip, string.format("[%d] %s", entry.level, entry.title), entry.questId)
    -- As much as the spoiler choices let tell (asked here, on a hover, not at every drawing)
    local isHolding = ns.Spoilers.isActive()
    local drops = isHolding and ns.Spoilers.get("drops", entry.questId) or "chances"
    local places = isHolding and ns.Spoilers.get("objectives", entry.questId) or "exact"
    local chains = isHolding and ns.Spoilers.get("chains", entry.questId) or "all"
    addObjectiveLines(entry, drops)
    if entry.isTurnIn then
        local isTold = not isHolding or ns.Model.isTurnInShown(entry.questId)
        addLine(TrackerTooltip.composeTurnInText(entry, isTold), GREEN)
    end
    -- With Shift held: what it asks, the rewards, where it is handed in (its objectives are listed above already)
    ns.QuestTooltip.addDetails(GameTooltip, entry.questId, { hasObjectives = true, hasTurnIn = entry.isTurnIn })
    addKillSection(entry)
    if chains ~= "hidden" then
        if entry.chainIndex then
            addChainLines(entry, chains)
        end
        addLinkLines(entry, chains == "all" and not (isHolding and ns.Availability.isLaterHidden("quest")))
    end
    addUnlocatedLine(entry, places)
    ns.Party.addProgressToTooltip(GameTooltip, entry.questId, entry.objectives)
    addClickHint(entry)
    GameTooltip:Show()
end
