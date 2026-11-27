local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The chronicle's page: the whole window, as the settings are, opened by the book beside the cog. Chapters on the
-- list's side: At a glance (totals, quests a day, records), Journal (every quest handed in, day by day, each with
-- its story), Zones (how much of each is done, and what) and Kills and luck (drop quests against the average).
-- The Days chapter is in ChronicleDays.lua, the pictures (calendar, plaques, cards) in ChroniclePictures.lua; both
-- draw with the pieces this file shares on ChroniclePage (at its end).
local ChroniclePage = {}
ns.ChroniclePage = ChroniclePage

ChroniclePage.chapterIndex = 1
ChroniclePage.LIST_WIDTH = 210 -- the chapters' side: narrower than the quest list, so the page gets the room
local selectedEntryIndex -- the journal entry on the page; 0 is the quests done before the chronicle
local selectedZoneId
local pageTitle, pageNote -- what the page's header says, set while the page is drawn
local addDungeonQuests -- defined with the zones, used on a dungeon's page

local COLORS = ns.Widgets.COLORS
local DOT = ns.Widgets.MIDDLE_DOT
local PADDING = 18
local BETTER, WORSE = { 0.18, 0.48, 0.18 }, { 0.64, 0.2, 0.14 } -- on parchment: better or worse than usual
local ROW_HEIGHT = 32
local BAR_HIGHLIGHT = { 0.48, 0.31, 0 }
local UNLUCKY, LUCKY = { 0.54, 0.16, 0.1 }, { 0.18, 0.42, 0.18 }
local HEADER_BAR_LOW, HEADER_BAR_HIGH = { 0.23, 0.16, 0.09 }, { 0.31, 0.22, 0.13 }
local SELECTED_EDGE = { 0.79, 0.64, 0.15 }
local MAX_JOURNAL_ENTRIES = 300 -- drawn at a time: "Show older quests" under them draws as many more each time
local MAX_ZONE_QUESTS = 40

local CHAPTERS = {
    { key = "glance", title = "At a glance", icon = "Interface\\Icons\\Spell_Holy_BorrowedTime" }, -- as the settings' At a glance
    { key = "days", title = "Days", icon = "Interface\\Icons\\INV_Misc_PocketWatch_02" },
    { key = "journal", title = "Journal", icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { key = "zones", title = "Zones", icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "kills", title = "Kills and luck", icon = "Interface\\Icons\\Ability_Tracking" },
}

---@return string key The chosen chapter's: "glance", "days", "journal", "zones" or "kills"
local function getChapterKey()
    return (CHAPTERS[ChroniclePage.chapterIndex] or CHAPTERS[1]).key
end

---@return number index A chapter's place in the list
local function getChapterIndex(key)
    for index, chapter in ipairs(CHAPTERS) do
        if chapter.key == key then
            return index
        end
    end
    return 1
end
ChroniclePage.CHAPTERS = CHAPTERS

---------------------------------------------------------------------------------------------------------------
-- Words for numbers and times

---@return string text "41 s", "18 m", "1 h 12 m"
local function formatDuration(seconds)
    seconds = math.floor(seconds + 0.5)
    if seconds < 60 then
        return ns.L("%d s", seconds)
    elseif seconds < 3600 then
        return ns.L("%d m", math.floor(seconds / 60))
    end
    local minutes = math.floor(seconds / 60) % 60
    local hours = math.floor(seconds / 3600)
    return minutes > 0 and ns.L("%d h %d m", hours, minutes) or ns.L("%d h", hours)
end
ChroniclePage.formatDuration = formatDuration

---@return string text "today 14:02", "yesterday 21:05", "12 Nov 09:30"
local function formatWhen(stamp)
    local today = ns.Chronicle.getDay(ns.Chronicle.getNow())
    local day = ns.Chronicle.getDay(stamp)
    local clock = ns.Chronicle.formatDate("%H:%M", stamp)
    if day == today then
        return ns.L("today %s", clock)
    elseif day == ns.Chronicle.getDay(ns.Chronicle.getNow() - 86400) then
        return ns.L("yesterday %s", clock)
    end
    return ns.Chronicle.formatShownDate("%d %b ", stamp) .. clock
end

---@return string text "Today", "Yesterday", "Thursday 12 Nov"
local function formatDayHeading(stamp)
    local now = ns.Chronicle.getNow()
    local day = ns.Chronicle.getDay(stamp)
    if day == ns.Chronicle.getDay(now) then
        return ns.L("Today")
    elseif day == ns.Chronicle.getDay(now - 86400) then
        return ns.L("Yesterday")
    end
    return ns.Chronicle.formatShownDate("%A %d %b", stamp)
end

local function formatNumber(number)
    number = math.floor(number + 0.5)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(number) or tostring(number)
end

---@return string text, number[] color "-7%" in red for unlucky, "+12%" in green for lucky
local function formatLuck(luck)
    local percent = math.floor(math.abs(luck) * 100 + 0.5)
    if percent == 0 then
        return "0%", COLORS.ink
    end
    return (luck < 0 and "-" or "+") .. percent .. "%", luck < 0 and UNLUCKY or LUCKY
end

local function describeLuck(luck)
    if not luck then
        return ns.L("no kills counted yet")
    elseif luck <= -0.25 then
        return ns.L("unlucky")
    elseif luck < -0.03 then
        return ns.L("a little unlucky")
    elseif luck <= 0.03 then
        return ns.L("right on average")
    elseif luck < 0.25 then
        return ns.L("a little lucky")
    end
    return ns.L("lucky")
end

local function getNpcName(npcId)
    return ns.Database.getNpcField(npcId, "name") or ns.L("Creature %d", npcId)
end

---@return string title An entry's quest title as shown: translated when a translation addon has it
local function getShownTitle(entry)
    return ns.QuestText.getTitle(entry.questId, entry.title)
end

local function getEntryTitle(entry)
    local title = getShownTitle(entry)
    return entry.questLevel and entry.questLevel > 0 and string.format("[%d] %s", entry.questLevel, title) or title
end

---@return fun(data: any) handleClick Does what is asked, then draws the window again
local function composeClickHandler(handle)
    return function(data)
        handle(data)
        ns.Log.refresh()
    end
end

local pendingPageScroll -- where the page is to be scrolled once drawn: the top of a story, the list's place back
local journalListScroll = 0 -- where the journal's list was when a quest was opened from it

local selectChapter = composeClickHandler(function(index)
    ChroniclePage.chapterIndex = index
    selectedZoneId = nil -- the Zones chapter opens on its table
    selectedEntryIndex = nil -- and the Journal on its list
    pendingPageScroll = 0
end)
local selectEntry = composeClickHandler(function(index)
    journalListScroll = ns.LogState and ns.LogState.detail and ns.LogState.detail:getScroll() or 0
    selectedEntryIndex = index
    pendingPageScroll = 0
end)

---@return boolean isOpen A quest's story (or the quests before the chronicle) is on the page, with Back to the list
function ChroniclePage.isEntryOpen()
    return getChapterKey() == "journal" and selectedEntryIndex ~= nil
end

---@return number? index The journal's entry open on the page (its row's data in the list: 0 for the quests before)
function ChroniclePage.getOpenEntry()
    return ChroniclePage.isEntryOpen() and selectedEntryIndex or nil
end

---Back from a quest's story to the journal's list, where it was.
function ChroniclePage.closeEntry()
    selectedEntryIndex = nil
    pendingPageScroll = journalListScroll
    ns.Log.refresh()
end

---LB/RB with a controller: the chapter before or after, as a click on it would open it (none past the first or last).
---@return boolean isStepped
function ChroniclePage.stepChapter(delta)
    local index = math.max(1, math.min(#CHAPTERS, (ChroniclePage.chapterIndex or 1) + delta))
    if index == ChroniclePage.chapterIndex then
        return false
    end
    selectChapter(index)
    return true
end

---@return boolean isChosen A row of the chronicle's list (a chapter, a day) is the one on the page
function ChroniclePage.isChosenRow(data)
    return data == ChroniclePage.chapterIndex or (type(data) == "string" and data == ChroniclePage.selectedDayKey)
end

---@return number? scroll Where the page is to be scrolled now it is drawn, once
function ChroniclePage.takePageScroll()
    local scroll = pendingPageScroll
    pendingPageScroll = nil
    return scroll
end
local selectZone = composeClickHandler(function(zoneId)
    selectedZoneId = zoneId or nil -- false: back to the table of zones
end)

---------------------------------------------------------------------------------------------------------------
-- The page's pieces

---@return number y Below the heading
local function addHeading(page, y, text, note)
    local height = page:addText(text, PADDING, y, { font = "QuestFont_Large", color = COLORS.ink, isSingleLine = true })
    if note then
        page:addText(note, PADDING, y + 4, {
            font = "GameFontHighlightSmall",
            color = COLORS.softInk,
            width = page.width - 2 * PADDING,
            justify = "RIGHT",
            isSingleLine = true,
        })
    end
    page:addRect(PADDING, y + height + 3, page.width - 2 * PADDING, 2, BAR_HIGHLIGHT)
    return y + height + 12
end

local ICONS = "Interface\\Icons\\"
local STRIP_EDGE, STRIP_RIM, STRIP_FILL, STRIP_SHINE =
    { 0, 0, 0 }, { 0.42, 0.29, 0.15 }, { 0.16, 0.1, 0.05 }, { 0.22, 0.15, 0.08 }
local STRIP_LABEL, STRIP_UNLUCKY, STRIP_LUCKY = { 0.85, 0.81, 0.66 }, { 1, 0.48, 0.35 }, { 0.54, 0.82, 0.54 }
local STRIP_ROW_HEIGHT = 44

local function showStripNote(button, cell)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(cell.label, 1, 1, 1)
    if cell.note then
        GameTooltip:AddLine(cell.note, 1, 0.82, 0, true)
    end
    GameTooltip:Show()
end

---Numbers on the dark wood the game puts behind a quest's rewards, three to a row, each beside its icon as a
---reward item is: the number large, its label under it, more about it when pointed at.
---@param cells { label: string, value: string, note: string?, icon: string, luck: number? }[] With a luck, the
---number is green when lucky and red when not
---@param columns number? Cells to a row: 3 when left out; fewer on a narrow page
---@return number y Below the strip
local function addRewardStrip(page, y, cells, columns)
    columns = columns or 3
    local width = page.width - 2 * PADDING
    local rowCount = math.ceil(#cells / columns)
    local height = rowCount * STRIP_ROW_HEIGHT + 12
    page:addRect(PADDING, y, width, height, STRIP_EDGE)
    page:addRect(PADDING + 1, y + 1, width - 2, height - 2, STRIP_RIM, 1)
    page:addRect(PADDING + 2, y + 2, width - 4, height - 4, STRIP_FILL, 2)
    page:addRect(PADDING + 2, y + 2, width - 4, math.floor((height - 4) / 2), STRIP_SHINE, 2)
    local cellWidth = (width - 16) / columns
    for index, cell in ipairs(cells) do
        local column, row = (index - 1) % columns, math.floor((index - 1) / columns)
        local x, top = PADDING + 8 + column * cellWidth, y + 8 + row * STRIP_ROW_HEIGHT
        page:addIcon(x, top + 2, 32, cell.icon, nil, 4, { 0.08, 0.92, 0.08, 0.92 })
        local color = COLORS.white
        if cell.luck then
            color = cell.luck < 0 and STRIP_UNLUCKY or STRIP_LUCKY
        end
        page:addText(
            cell.value,
            x + 38,
            top + 1,
            { font = "GameFontNormalLarge", color = color, width = cellWidth - 42, isSingleLine = true }
        )
        page:addText(
            cell.label,
            x + 38,
            top + 21,
            { font = "GameFontHighlightSmall", color = STRIP_LABEL, width = cellWidth - 42, isSingleLine = true }
        )
        page:addButton(x - 2, top - 2, cellWidth - 4, STRIP_ROW_HEIGHT - 4, nil, cell, showStripNote)
    end
    return y + height + 10
end

local ENTRY_ICON_SIZE, ENTRY_GAP = 32, 10
local LINE_HEIGHTS = { GameFontHighlightSmall = 12, QuestFont = 16, GameFontNormalLarge = 19 }

---@return string text Coloured for the page, as the game writes colours in text
local function colorText(text, color)
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(color[1] * 255 + 0.5),
        math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5),
        text
    )
end

---Entries two to a row, as the spellbook lists its spells: each an icon with its lines beside it, no box round it.
---@param cells { icon: string, lines: { text: string, font: string, color: number[]? }[], handleClick: function?, data: any }[]
---@return number y Below the entries
local function addEntryGrid(page, y, cells)
    local columnWidth = (page.width - 2 * PADDING - ENTRY_GAP * 2) / 2
    for rowStart = 1, #cells, 2 do
        local rowHeight = ENTRY_ICON_SIZE
        for column = 0, 1 do
            local cell = cells[rowStart + column]
            if cell then
                local x = PADDING + 2 + column * (columnWidth + ENTRY_GAP * 2)
                page:addFramedIcon(x, y, ENTRY_ICON_SIZE, cell.icon)
                local lineY = y - 1
                for _, line in ipairs(cell.lines) do
                    page:addText(line.text, x + ENTRY_ICON_SIZE + 8, lineY, {
                        font = line.font,
                        color = line.color or COLORS.ink,
                        width = columnWidth - ENTRY_ICON_SIZE - 10,
                        isSingleLine = true,
                    })
                    lineY = lineY + LINE_HEIGHTS[line.font]
                end
                if cell.handleClick then
                    page:addButton(x - 2, y - 2, columnWidth, lineY - y + 3, cell.handleClick, cell.data)
                end
                rowHeight = math.max(rowHeight, lineY - y)
            end
        end
        y = y + rowHeight + ENTRY_GAP
    end
    return y + 2
end

---A label on the left, its value on the right.
---@return number y Below the line
local function addFact(page, y, label, value, valueColor)
    page:addText(label, PADDING, y, { font = "QuestFont", color = COLORS.softInk, isSingleLine = true })
    local height = page:addText(value, PADDING + 110, y, {
        font = "QuestFont",
        color = valueColor or COLORS.ink,
        width = page.width - 2 * PADDING - 110,
        justify = "RIGHT",
    })
    return y + math.max(height, 14) + 5
end

---Kills against what an average player would have needed: the bar the kills fill, red when over, green when
---under, a gold line where the average player would be.
---@return number y Below the bar and its numbers
local function addLuckBar(page, y, kills, expected)
    local width = page.width - 2 * PADDING
    local total = math.max(kills, expected)
    local isUnlucky = kills > expected
    local innerLeft, innerTop, innerWidth, innerHeight = page:addStatBar(PADDING, y - 2, width, 14, {
        { share = kills / total, color = isUnlucky and { 0.75, 0.25, 0.16 } or { 0.25, 0.62, 0.25 } },
    })
    local mark = page:addImage(
        innerLeft + innerWidth * expected / total - 1,
        innerTop - 2,
        2,
        innerHeight + 4,
        "Interface\\Buttons\\WHITE8X8",
        nil,
        nil,
        3
    )
    mark:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
    page:addText(
        ns.L("%s kills", formatNumber(kills)),
        PADDING,
        y + 13,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, isSingleLine = true }
    )
    page:addText(ns.L("expected %s", formatNumber(expected)), PADDING, y + 13, {
        font = "GameFontHighlightSmall",
        color = BAR_HIGHLIGHT,
        width = width,
        justify = "RIGHT",
        isSingleLine = true,
    })
    return y + 30
end

---------------------------------------------------------------------------------------------------------------
-- At a glance

local function addRecord(records, icon, label, value, when)
    records[#records + 1] = { icon = ICONS .. icon, label = label, value = value, when = when }
end

---@return string when A day's record's day, as a heading says it
local function getDayRecordWhen(record)
    return formatDayHeading(ns.Ledger.getDayStamp(record.key))
end

---@return string? when The day an entry was handed in
local function getEntryRecordWhen(entry)
    return entry.turnedInAt and ns.Chronicle.formatShownDate("%d %b", entry.turnedInAt) or nil
end

---The days' records: the best days for gold, experience and quests, and the days in a row.
local function addDayRecords(records, overview)
    if overview.bestGold then
        addRecord(
            records,
            "INV_Misc_Coin_01",
            ns.L("Best day for gold"),
            ns.Widgets.formatMoney(overview.bestGold.value),
            getDayRecordWhen(overview.bestGold)
        )
    end
    if overview.bestExperience then
        addRecord(
            records,
            "XP_Icon",
            ns.L("Best day for experience"),
            formatNumber(overview.bestExperience.value),
            getDayRecordWhen(overview.bestExperience)
        )
    end
    if overview.mostQuests then
        addRecord(
            records,
            "INV_Scroll_03",
            ns.L("Most quests in a day"),
            formatNumber(overview.mostQuests.value),
            getDayRecordWhen(overview.mostQuests)
        )
    end
    if overview.streak > 1 then
        addRecord(records, "INV_Misc_PocketWatch_02", ns.L("Days in a row"), formatNumber(overview.streak))
    end
end

---A quest's luck record: its title, its kills and what was expected.
local function addLuckRecord(records, icon, label, entry)
    local kills, expected = ns.Chronicle.getEntryKills(entry)
    addRecord(
        records,
        icon,
        label,
        ns.L(
            "%s: %s, %d expected",
            getShownTitle(entry),
            ns.Lp(kills, "%d kill", "%d kills"),
            math.floor(expected + 0.5)
        ),
        getEntryRecordWhen(entry)
    )
end

---The quests' records: the fastest and longest, the unluckiest and luckiest, the most killed, chains, abandoned.
local function addQuestRecords(records, summary)
    if summary.fastest then
        addRecord(
            records,
            "Spell_Holy_BorrowedTime",
            ns.L("Fastest"),
            getShownTitle(summary.fastest) .. DOT .. formatDuration(summary.fastest.duration),
            getEntryRecordWhen(summary.fastest)
        )
    end
    if summary.longest and summary.longest ~= summary.fastest then
        addRecord(
            records,
            "INV_Misc_PocketWatch_01",
            ns.L("Longest"),
            getShownTitle(summary.longest) .. DOT .. formatDuration(summary.longest.duration),
            getEntryRecordWhen(summary.longest)
        )
    end
    if summary.unluckiest then
        addLuckRecord(records, "Ability_Rogue_FeignDeath", ns.L("Unluckiest"), summary.unluckiest)
    end
    if summary.luckiest and summary.luckiest ~= summary.unluckiest then
        addLuckRecord(records, "INV_Misc_Ticket_Tarot_Madness", ns.L("Luckiest"), summary.luckiest)
    end
    if summary.mostKilled then
        addRecord(
            records,
            "Ability_Tracking",
            ns.L("Most killed"),
            getNpcName(summary.mostKilled.npcId) .. DOT .. formatNumber(summary.mostKilled.kills)
        )
    end
    addRecord(records, "INV_Misc_Book_09", ns.L("Chains finished"), formatNumber(summary.chainCount))
    if summary.abandonedCount > 0 then
        addRecord(records, "Ability_Rogue_Sprint", ns.L("Abandoned"), formatNumber(summary.abandonedCount))
    end
end

---@return table[] records Each record a framed plaque: the days' records first, then the quests'
local function composeGlanceRecords(summary, overview)
    local records = {}
    addDayRecords(records, overview)
    addQuestRecords(records, summary)
    return records
end

---Found yourself: only once spoilers were ever held back (a player always in Guide sees nothing of it).
---@return number y Below it
local function addFoundYourself(page, y, summary)
    local Spoilers = ns.Spoilers
    y = addHeading(
        page,
        y,
        ns.L("Found yourself"),
        ns.L("Spoilers: %s", ns.L(Spoilers.getPresetName(Spoilers.getPreset())))
    )
    return addRewardStrip(page, y, {
        {
            label = ns.L("Quests found yourself"),
            value = formatNumber(summary.foundCount),
            icon = ICONS .. "INV_Misc_Spyglass_02",
            note = ns.L(
                "Handed in with spoilers held back and no hint taken, of %s with spoilers held back",
                formatNumber(summary.spoilerCount)
            ),
        },
        {
            label = ns.L("Hints used"),
            value = formatNumber(summary.hintedCount + summary.peekCount),
            icon = ICONS .. "INV_Misc_Note_01",
            note = ns.Lp(summary.hintedCount, "%d quest done with a hint", "%d quests done with a hint")
                .. ", "
                .. ns.Lp(summary.peekCount, "%d peek at the whole map (Alt)", "%d peeks at the whole map (Alt)"),
        },
    }, 2)
end

---Altogether: from the days kept, once there are any; before them, quest rewards are all that was kept.
---@return number y Below it
local function addAltogether(page, y, summary, overview)
    local hasDays = overview.firstKey ~= nil
    local since = hasDays
            and ns.L(
                "Kept day by day since %s",
                ns.Chronicle.formatShownDate("%d %b", ns.Ledger.getDayStamp(overview.firstKey))
            )
        or ns.L("Quest rewards only, so far")
    local luckText = summary.luck and (formatLuck(summary.luck)) or "-"
    local money = hasDays and overview.totals.net or summary.money
    y = addHeading(
        page,
        y,
        ns.L("Altogether"),
        hasDays and ns.L("since %s", ns.Chronicle.formatShownDate("%d %b", ns.Ledger.getDayStamp(overview.firstKey)))
            or nil
    )
    return addRewardStrip(page, y, {
        {
            label = ns.L("Quests done"),
            value = formatNumber(summary.questCount),
            icon = ICONS .. "INV_Scroll_03",
            note = ns.L(
                "%s handed in since the chronicle began; the rest from the game's own record",
                formatNumber(summary.chronicledCount)
            ),
        },
        {
            label = ns.L("Gold earned, net"),
            value = money ~= 0 and ChroniclePage.formatTileMoney(money) or "-",
            icon = ICONS .. "INV_Misc_Coin_01",
            note = since,
        },
        {
            label = ns.L("Experience"),
            value = formatNumber(hasDays and overview.totals.experience or summary.experience),
            icon = ICONS .. "XP_Icon",
            note = since,
        },
        {
            label = ns.L("Time played"),
            value = formatDuration(math.max(summary.playedSeconds, overview.totals.played)),
            icon = ICONS .. "INV_Misc_PocketWatch_01",
            note = ns.L("Since the chronicle began"),
        },
        {
            label = ns.L("Kills"),
            value = formatNumber(hasDays and overview.totals.kills or summary.kills),
            icon = ICONS .. "Ability_Tracking",
            note = hasDays and since or ns.L("Kills for quest drops"),
        },
        {
            label = ns.L("Luck with drops"),
            value = luckText,
            icon = ICONS .. "INV_Misc_Ticket_Tarot_Madness",
            luck = summary.luck,
            note = summary.luck and ns.L("Kills against the average: %s", describeLuck(summary.luck))
                or ns.L("No kills counted yet"),
        },
    })
end

local function drawGlance(page)
    local summary = ns.Chronicle.composeSummary()
    local book = ns.Chronicle.getBook()
    pageTitle = ns.L("At a glance")
    pageNote = ns.L(
        "Level %d%skept since %s",
        UnitLevel and UnitLevel("player") or 1,
        DOT,
        ns.Chronicle.formatShownDate("%d %b %Y", book.startedAt)
    )
    local overview = ns.Ledger.composeOverview()
    local y = 10
    y = ChroniclePage.addToday(page, y, overview)
    y = addAltogether(page, y, summary, overview)
    if summary.hasSpoilers then
        y = addFoundYourself(page, y, summary)
    end
    y = addHeading(page, y, ns.L("Records"))
    local records = composeGlanceRecords(summary, overview)
    if summary.chronicledCount == 0 and overview.firstKey == nil then
        y = y
            + page:addText(
                ns.L("Records start with the first quest you hand in."),
                PADDING,
                y,
                { font = "QuestFont", color = COLORS.softInk, width = page.width - 2 * PADDING }
            )
            + 8
    end
    y = ChroniclePage.addTrophies(page, y, records)
    return y + PADDING
end

---------------------------------------------------------------------------------------------------------------
-- Journal

local JOURNAL_KIND_SIZE = 14 -- the quest's kind, as the map's icons show it, before its title

-- What the journal shows: a search over titles, zones and givers, a time (all, today, yesterday, this week, or one
-- day), and a zone, a kind of quest and a source (the chronicle's own, Questie's journey)
local journalFilter = { text = "", when = "all", zoneId = nil, kind = nil, source = nil }
local journalControls -- the search box and the two dropdowns over the journal's list, made once
local journalShownCount = MAX_JOURNAL_ENTRIES -- the newest this many of the quests kept are drawn; more on asking
local JOURNAL_CONTROLS_HEIGHT = 34 -- the row of the search and the dropdowns
local WEEK_SECONDS = 7 * 86400
local KIND_LABELS = { kill = "Kill", loot = "Collect", use = "Use", talk = "Talk" }

---@return string? giver Who gave the quest, for the search
local function getEntryGiver(entry)
    local startedBy = ns.Database.getQuestField(entry.questId, "startedBy")
    local npcId = type(startedBy) == "table" and startedBy[1] and startedBy[1][1]
    return npcId and ns.Database.getNpcField(npcId, "name") or nil
end

-- What the search looks through for each entry, worked out once (with the language it was in) rather than on every
-- key typed: the quest database is asked for its giver and objectives only the first time
local searchTexts = setmetatable({}, { __mode = "k" })

---@return string text An entry's title, zone, giver and what it asked for, lower case ("wolf" finds the quest for
---Prairie Wolf Paws)
local function getSearchText(entry)
    local language = ns.Locale and ns.Locale.getLanguage() or ""
    local known = searchTexts[entry]
    if known and known.language == language then
        return known.text
    end
    local objectives = ns.Database.getQuestField(entry.questId, "objectivesText")
    local text = table
        .concat({
            getEntryTitle(entry),
            ns.Database.getZoneName(entry.zoneId) or "",
            getEntryGiver(entry) or "",
            type(objectives) == "table" and table.concat(objectives, " ") or "",
        }, " ")
        :lower()
    searchTexts[entry] = { language = language, text = text }
    return text
end

---@return boolean isShown An entry the journal's search and filters keep
local function isJournalShown(entry)
    local filter = journalFilter
    if filter.when ~= "all" then
        local now = ns.Chronicle.getNow()
        local day = ns.Chronicle.getDay(entry.turnedInAt)
        if
            filter.when == "today" and day ~= ns.Chronicle.getDay(now)
            or filter.when == "yesterday" and day ~= ns.Chronicle.getDay(now - 86400)
            or filter.when == "week" and now - entry.turnedInAt > WEEK_SECONDS
            or filter.when:match("^%d") and day ~= filter.when
        then
            return false
        end
    end
    if filter.zoneId and entry.zoneId ~= filter.zoneId then
        return false
    end
    if filter.kind and ChroniclePage.getEntryKind(entry) ~= filter.kind then
        return false
    end
    if filter.source then
        local isFrom = false
        for _, source in ipairs(entry.sources or { "OneMoreQuest" }) do
            isFrom = isFrom or source == filter.source
        end
        if not isFrom then
            return false
        end
    end
    if filter.text ~= "" and not getSearchText(entry):find(filter.text, 1, true) then
        return false
    end
    return true
end

---@return boolean isFiltered The journal shows less than everything
local function isJournalFiltered()
    local filter = journalFilter
    return filter.text ~= ""
        or filter.when ~= "all"
        or filter.zoneId ~= nil
        or filter.kind ~= nil
        or filter.source ~= nil
end

local function setJournalFilter(key, value)
    journalFilter[key] = value
    ns.Log.refresh()
end

---"Show older quests" under the journal's list: as many more drawn again.
local showOlderEntries = function()
    journalShownCount = journalShownCount + MAX_JOURNAL_ENTRIES
    ns.Log.refresh()
end

---The search box and the two dropdowns over the journal's list, the game's own as on My quests: made once, on the
---list's scrolling side, so they scroll with it; placed and shown each time the journal is drawn.
local function getJournalControls(page)
    if journalControls or not CreateFrame then
        return journalControls
    end
    local parent = page.content
    local search = CreateFrame("EditBox", "OneMoreQuestJournalSearch", parent, "SearchBoxTemplate")
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function(self)
        local text = (self:GetText() or ""):lower()
        if text ~= journalFilter.text then
            setJournalFilter("text", text)
        end
    end)
    local function createDropdown()
        local isCreated, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        return isCreated and type(dropdown) == "table" and dropdown.SetupMenu and dropdown or nil
    end
    local when, filter = createDropdown(), createDropdown()
    local function isWhen(value)
        return journalFilter.when == value
    end
    if when then
        when:SetupMenu(function(_, root)
            for _, choice in ipairs({
                { "all", "All days" },
                { "today", "Today" },
                { "yesterday", "Yesterday" },
                { "week", "This week" },
            }) do
                root:CreateRadio(ns.L(choice[2]), isWhen, function(value)
                    setJournalFilter("when", value)
                end, choice[1])
            end
            -- Each recent day with quests, with how many
            local counts, days = {}, {}
            for _, entry in ipairs(ns.Chronicle.getEntries()) do
                local day = ns.Chronicle.getDay(entry.turnedInAt)
                if not counts[day] then
                    days[#days + 1] = { key = day, stamp = entry.turnedInAt }
                end
                counts[day] = (counts[day] or 0) + 1
            end
            table.sort(days, function(first, second)
                return first.stamp > second.stamp
            end)
            if #days > 0 then
                root:CreateTitle(ns.L("Days"))
            end
            for index = 1, math.min(#days, 14) do
                local day = days[index]
                root:CreateRadio(
                    string.format("%s (%d)", formatDayHeading(day.stamp), counts[day.key]),
                    isWhen,
                    function(value)
                        setJournalFilter("when", value)
                    end,
                    day.key
                )
            end
        end)
    end
    if filter then
        filter:SetupMenu(function(_, root)
            local entries = ns.Chronicle.getEntries()
            root:CreateTitle(ns.L("Zone"))
            root:CreateRadio(ns.L("Every zone"), function()
                return journalFilter.zoneId == nil
            end, function()
                setJournalFilter("zoneId", nil)
            end)
            local zoneCounts, zoneIds = {}, {}
            for _, entry in ipairs(entries) do
                local zoneId = entry.zoneId
                if zoneId then
                    if not zoneCounts[zoneId] then
                        zoneIds[#zoneIds + 1] = zoneId
                    end
                    zoneCounts[zoneId] = (zoneCounts[zoneId] or 0) + 1
                end
            end
            table.sort(zoneIds, function(first, second)
                return zoneCounts[first] > zoneCounts[second]
            end)
            for _, zoneId in ipairs(zoneIds) do
                root:CreateRadio(
                    string.format("%s (%d)", ns.Database.getZoneName(zoneId) or "?", zoneCounts[zoneId]),
                    function(value)
                        return journalFilter.zoneId == value
                    end,
                    function(value)
                        setJournalFilter("zoneId", value)
                    end,
                    zoneId
                )
            end
            root:CreateTitle(ns.L("Kind"))
            root:CreateRadio(ns.L("Every kind"), function()
                return journalFilter.kind == nil
            end, function()
                setJournalFilter("kind", nil)
            end)
            for _, kind in ipairs({ "kill", "loot", "use", "talk" }) do
                root:CreateRadio(ns.L(KIND_LABELS[kind]), function(value)
                    return journalFilter.kind == value
                end, function(value)
                    setJournalFilter("kind", value)
                end, kind)
            end
            -- Where each entry was written down, once another history fills the journal too
            local names = ns.History.getSourceNames()
            if #names > 2 then -- (the game's own record dates nothing: listed only with another)
                root:CreateTitle(ns.L("Kept by"))
                root:CreateRadio(ns.L("Every history"), function()
                    return journalFilter.source == nil
                end, function()
                    setJournalFilter("source", nil)
                end)
                for _, name in ipairs(names) do
                    if name ~= "Game" then
                        root:CreateRadio(name, function(value)
                            return journalFilter.source == value
                        end, function(value)
                            setJournalFilter("source", value)
                        end, name)
                    end
                end
            end
        end)
    end
    journalControls = { search = search, when = when, filter = filter }
    return journalControls
end

---Hides the journal's search and dropdowns: the window is drawn again, and only the journal shows them. Left as they
---are when the journal's list is what is drawn again (a key typed in its search): hidden and shown on every key, the
---box being typed in would flicker and could lose the keyboard.
function ChroniclePage.hideJournalControls()
    local logState = ns.LogState
    if logState and logState.view == "chronicle" and getChapterKey() == "journal" and selectedEntryIndex == nil then
        return -- (placeJournalControls places them again as the list is drawn)
    end
    for _, control in pairs(journalControls or {}) do
        control:Hide()
    end
end

---Places the journal's search and dropdowns in a row at the top of the page (or hides them).
---@return number y Below them
local function placeJournalControls(page, y, isShown)
    local controls = getJournalControls(page)
    if not controls then
        return y
    end
    for _, control in pairs(controls) do
        control:SetShown(isShown)
    end
    if not isShown then
        return y
    end
    local DROPDOWN_WIDTH = 140
    local width = page.width - 2 * PADDING
    controls.search:ClearAllPoints()
    controls.search:SetPoint("TOPLEFT", page.content, "TOPLEFT", PADDING + 6, -(y + 6))
    controls.search:SetHeight(20)
    local right = PADDING + width
    for _, key in ipairs({ "filter", "when" }) do
        local dropdown = controls[key]
        if dropdown then
            dropdown:ClearAllPoints()
            dropdown:SetPoint("TOPRIGHT", page.content, "TOPLEFT", right, -(y + 2))
            dropdown:SetWidth(DROPDOWN_WIDTH)
            right = right - DROPDOWN_WIDTH - 6
        end
    end
    -- The search fills what the dropdowns leave, however wide the game draws them
    local leftmost = controls.when or controls.filter
    if leftmost then
        controls.search:SetPoint("RIGHT", leftmost, "LEFT", -8, 0)
    else
        controls.search:SetWidth(width - 6)
    end
    if controls.filter and controls.filter.OverrideText then
        -- Says what it keeps: "Filter" alone, else how many filters are on
        local count = (journalFilter.zoneId and 1 or 0)
            + (journalFilter.kind and 1 or 0)
            + (journalFilter.source and 1 or 0)
        controls.filter:OverrideText(count > 0 and ns.L("Filter (%d)", count) or ns.L("Filter"))
    end
    return y + JOURNAL_CONTROLS_HEIGHT
end

local JOURNAL_ROW_HEIGHT = 24
-- A quest done with spoilers held back and no hint taken: a small gold star after its title (Chronicle.isFoundYourself)
local FOUND_MARK, FOUND_MARK_SIZE = { atlas = "PetJournal-FavoritesIcon" }, 13

---One quest of the journal's list, on one line: the time, its kind, its title, and how it went at the right.
---@return number y Below the row
local function addJournalRow(page, y, entry, index)
    local width = page.width - 2 * PADDING
    page:addText(
        ns.Chronicle.formatDate("%H:%M", entry.turnedInAt),
        PADDING + 4,
        y + 5,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, isSingleLine = true }
    )
    page:addImage(
        PADDING + 44,
        y + 5,
        JOURNAL_KIND_SIZE,
        JOURNAL_KIND_SIZE,
        ns.MapMarks.OBJECTIVE_ICONS[ChroniclePage.getEntryKind(entry)] or ns.MapMarks.OBJECTIVE_ICONS.use
    )
    local facts = {}
    local kills, expected = ns.Chronicle.getEntryKills(entry)
    if expected > 0 then
        -- Kills against what was expected: red over, green under, in the page's own inks
        local gap = math.floor(kills - expected + 0.5)
        facts[#facts + 1] = colorText(ns.L("%s%d kills", gap > 0 and "+" or "", gap), gap > 0 and WORSE or BETTER)
    end
    if entry.duration then
        facts[#facts + 1] = formatDuration(entry.duration)
    end
    if entry.deaths and entry.deaths > 0 then
        facts[#facts + 1] = entry.deaths == 1 and ns.L("died once") or ns.L("died %dx", entry.deaths)
    end
    if entry.wasGrouped then
        facts[#facts + 1] = ns.L("group")
    end
    facts[#facts + 1] = ns.Database.getZoneName(entry.zoneId)
    -- Kept by another addon's history: its name, as the story's page says too
    for _, name in ipairs(ChroniclePage.getOtherSources(entry)) do
        facts[#facts + 1] = name
    end
    local factsWidth = math.floor(width * 0.36)
    page:addText(table.concat(facts, DOT), PADDING + width - factsWidth, y + 5, {
        font = "GameFontHighlightSmall",
        color = COLORS.softInk,
        width = factsWidth - 4,
        justify = "RIGHT",
        isSingleLine = true,
    })
    local titleLeft = PADDING + 44 + JOURNAL_KIND_SIZE + 6
    local titleWidth = width - factsWidth - (titleLeft - PADDING) - 8
    local isFound = ns.Chronicle.isFoundYourself(entry)
    if isFound then
        titleWidth = titleWidth - FOUND_MARK_SIZE - 4 -- (room kept for the star, so a long title is cut before it)
    end
    local _, shownWidth = page:addText(
        getEntryTitle(entry),
        titleLeft,
        y + 3,
        { font = "QuestFont", color = COLORS.ink, width = titleWidth, isSingleLine = true }
    )
    if isFound then
        local markLeft = titleLeft + math.min(tonumber(shownWidth) or titleWidth, titleWidth) + 4
        page:addImage(markLeft, y + 5, FOUND_MARK_SIZE, FOUND_MARK_SIZE, FOUND_MARK, nil, nil, 3)
    end
    page:addRect(PADDING, y + JOURNAL_ROW_HEIGHT - 1, width, 1, { 0.55, 0.42, 0.25, 0.35 })
    page:addButton(PADDING, y, width, JOURNAL_ROW_HEIGHT, selectEntry, index)
    return y + JOURNAL_ROW_HEIGHT
end

---The journal on the page: the search and filters, then the quests day by day, newest first, then the quests done
---before the chronicle; only those the search and filters keep. A click opens a quest's story.
---@return number y
local function drawJournalPage(page)
    local y = placeJournalControls(page, 8, true)
    local allEntries = ns.Chronicle.getEntries()
    local isFiltered = isJournalFiltered()
    -- The entries shown, each with its place in the whole journal (what a click opens)
    local entries, indexes = {}, {}
    for index, entry in ipairs(allEntries) do
        if not isFiltered or isJournalShown(entry) then
            entries[#entries + 1] = entry
            indexes[#entries] = index
        end
    end
    local earlierCount = isFiltered and 0 or #ns.Chronicle.getEarlierQuestIds()
    pageTitle = ns.L("Journal")
    pageNote = isFiltered and ns.L("%s of %s quests", formatNumber(#entries), formatNumber(#allEntries))
        or ns.Lp(#allEntries, "%d quest", "%d quests")
    local shownDay
    local oldestShown = math.max(#entries - journalShownCount + 1, 1)
    for index = #entries, oldestShown, -1 do
        local entry = entries[index]
        local day = ns.Chronicle.getDay(entry.turnedInAt)
        if day ~= shownDay then
            shownDay = day
            -- The day's heading with how many quests it saw
            local count = 0
            for other = index, 1, -1 do
                if ns.Chronicle.getDay(entries[other].turnedInAt) ~= day then
                    break
                end
                count = count + 1
            end
            y = addHeading(page, y + 6, formatDayHeading(entry.turnedInAt), ns.Lp(count, "%d quest", "%d quests"))
        end
        y = addJournalRow(page, y, entry, indexes[index])
    end
    -- Older quests than those drawn: a link draws more, rather than the list ending as if there were no more
    local olderCount = oldestShown - 1
    if olderCount > 0 then
        local text = ns.Lp(olderCount, "Show older quests (%d more)", "Show older quests (%d more)")
        local _, linkWidth =
            page:addText(text, PADDING + 4, y + 10, { font = "QuestFont", color = COLORS.brown, isSingleLine = true })
        page:addRect(PADDING + 4, y + 25, linkWidth, 1, COLORS.brown, 1)
        page:addButton(PADDING, y + 7, linkWidth + 10, 22, showOlderEntries)
        y = y + 34
    end
    if earlierCount > 0 then
        y = addHeading(page, y + 10, ns.L("Before the chronicle"), formatNumber(earlierCount))
        local _, linkWidth = page:addText(
            ns.L("%s quests, no dates", formatNumber(earlierCount)),
            PADDING + 4,
            y,
            { font = "QuestFont", color = COLORS.brown, isSingleLine = true }
        )
        page:addRect(PADDING + 4, y + 15, linkWidth, 1, COLORS.brown, 1)
        page:addButton(PADDING, y - 3, linkWidth + 10, 22, selectEntry, 0)
        y = y + 24
    end
    if #entries == 0 and earlierCount == 0 then
        local emptyText = isFiltered and ns.L("No quest matches. Clear the search or a filter.")
            or ns.L("Quests you hand in are written down here.")
        page:addText(
            emptyText,
            PADDING + 4,
            y + 10,
            { font = "QuestFont", color = COLORS.softInk, width = page.width - 2 * PADDING }
        )
        y = y + 34
    end
    return y + PADDING
end

---The quests done before the chronicle began, by zone.
local function drawEarlier(page)
    pageTitle, pageNote = ns.L("Before the chronicle"), ns.L("Quests done before it began")
    local y = 10
    local earlierQuestIds = ns.Chronicle.getEarlierQuestIds()
    page:addText(
        ns.L(
            "%s quests the game says this character completed before the chronicle began. When and how they went is not known; their names and places come from the quest database.",
            formatNumber(#earlierQuestIds)
        ),
        PADDING,
        y,
        { font = "QuestFont", color = COLORS.softInk, width = page.width - 2 * PADDING }
    )
    y = y + 54
    local countByZone, zoneIds = {}, {}
    for _, questId in ipairs(earlierQuestIds) do
        local zoneId = ns.Availability.getStartZoneId(questId) or 0
        if not countByZone[zoneId] then
            zoneIds[#zoneIds + 1] = zoneId
        end
        countByZone[zoneId] = (countByZone[zoneId] or 0) + 1
    end
    table.sort(zoneIds, function(first, second)
        return countByZone[first] > countByZone[second]
    end)
    y = addHeading(page, y, ns.L("By zone"))
    for _, zoneId in ipairs(zoneIds) do
        y = addFact(
            page,
            y,
            zoneId ~= 0 and ns.Database.getZoneName(zoneId) or ns.L("Elsewhere"),
            formatNumber(countByZone[zoneId])
        )
    end
    return y + PADDING
end

---@return string[] names The other addons whose histories know this quest (not the chronicle's own, nor the
---game's undated list)
function ChroniclePage.getOtherSources(entry)
    local names = {}
    for _, source in ipairs(entry.sources or {}) do
        if source ~= "OneMoreQuest" and source ~= "Game" then
            names[#names + 1] = source
        end
    end
    return names
end

---Says where a quest's story came from when another addon's history wrote it, or filled it in: "From Questie's
---history" says why little is known (no experience, kills or money), "Filled in from" says what was added.
---@return number y Below the tag
function ChroniclePage.addSourceTag(page, y, entry)
    local others = ChroniclePage.getOtherSources(entry)
    if #others == 0 then
        return y
    end
    local isOwn = false
    for _, source in ipairs(entry.sources or {}) do
        isOwn = isOwn or source == "OneMoreQuest"
    end
    local names = table.concat(others, ", ")
    local text = isOwn and ns.L("Filled in from %s: when it was taken and at what level.", names)
        or ns.L("From %s's history: only when it was done and at what level are known.", names)
    page:addIcon(PADDING, y - 1, 16, ICONS .. "INV_Scroll_03", nil, 3, { 0.08, 0.92, 0.08, 0.92 })
    local height = page:addText(
        text,
        PADDING + 22,
        y,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, width = page.width - 2 * PADDING - 22 }
    )
    return y + math.max(tonumber(height) or 12, 16) + 10
end

---@return string header Where in the journal a story is: the day and the time, and when it was taken
local function composeEntryHeader(entry)
    local header = formatDayHeading(entry.turnedInAt) .. DOT .. ns.Chronicle.formatDate("%H:%M", entry.turnedInAt)
    if entry.acceptedAt then
        header = header .. DOT .. ns.L("taken %s", formatWhen(entry.acceptedAt))
    end
    return header
end

---@return string facts The line under a story's card: its level, zone, place in its chain, the player's level
local function composeEntryFacts(entry)
    local facts = {}
    if entry.questLevel and entry.questLevel > 0 then
        facts[#facts + 1] = ns.L("Level %d", entry.questLevel)
    end
    facts[#facts + 1] = ns.Database.getZoneName(entry.zoneId)
    local step, total = ns.Chain.getStep(entry.questId)
    if step then
        facts[#facts + 1] = ns.L("step %d of %d", step, total)
    end
    if entry.acceptedLevel and entry.playerLevel and entry.playerLevel ~= entry.acceptedLevel then
        facts[#facts + 1] = ns.L("level %d to %d", entry.acceptedLevel, entry.playerLevel)
    elseif entry.playerLevel then
        facts[#facts + 1] = ns.L("at level %d", entry.playerLevel)
    end
    return table.concat(facts, DOT)
end

---Done with spoilers held back: found yourself, or with a hint (in Guide nothing is said).
---@return table? tile
local function composeSpoilerTile(entry)
    if not entry.spoilers then
        return nil
    end
    local presetName = ns.L(ns.Spoilers.getPresetName(entry.spoilers))
    if entry.hinted then
        return {
            label = ns.L("Hints"),
            value = ns.L("used"),
            icon = ICONS .. "INV_Misc_Note_01",
            note = ns.L("A hint was taken for this quest. Spoilers: %s", presetName),
        }
    end
    return {
        label = ns.L("Found yourself"),
        value = ns.L("yes"),
        icon = ICONS .. "INV_Misc_Spyglass_02",
        note = ns.L("Done with no hints. Spoilers: %s", presetName),
    }
end

---@return table[] tiles A story's reward tiles: only what says something (no "0 kills" for a quest that needed none)
local function composeEntryTiles(entry)
    local kills = 0
    for _, drop in ipairs(entry.drops or {}) do
        kills = kills + (drop.kills or 0)
    end
    local tiles = {}
    if entry.duration then
        tiles[#tiles + 1] = {
            label = ns.L("Played"),
            value = formatDuration(entry.duration),
            icon = ICONS .. "INV_Misc_PocketWatch_01",
            note = entry.acceptedAt
                    and ns.Chronicle.getDay(entry.acceptedAt) ~= ns.Chronicle.getDay(entry.turnedInAt)
                    and ns.L("Over more than a day")
                or nil,
        }
    end
    if kills > 0 then
        tiles[#tiles + 1] = {
            label = ns.L("Kills"),
            value = formatNumber(kills),
            icon = ICONS .. "Ability_Tracking",
            note = ns.L("Kills for its drops"),
        }
    end
    if (entry.deaths or 0) > 0 then
        tiles[#tiles + 1] =
            { label = ns.L("Deaths"), value = formatNumber(entry.deaths), icon = ICONS .. "Ability_Rogue_FeignDeath" }
    end
    if entry.wasGrouped then
        tiles[#tiles + 1] =
            { label = ns.L("In a group"), value = ns.L("yes"), icon = ICONS .. "INV_Misc_GroupNeedMore" }
    end
    tiles[#tiles + 1] = composeSpoilerTile(entry)
    if (entry.experience or 0) > 0 then
        tiles[#tiles + 1] =
            { label = ns.L("Experience"), value = formatNumber(entry.experience), icon = ICONS .. "XP_Icon" }
    end
    if (entry.money or 0) > 0 then
        tiles[#tiles + 1] = {
            label = ns.L("Money"),
            value = ChroniclePage.formatTileMoney(entry.money),
            icon = ICONS .. "INV_Misc_Coin_01",
        }
    end
    return tiles
end

---A drop's kills against what an average player would have needed, and the sentence that says how it went.
---@return number y Below them
local function addDropLuck(page, y, drop)
    y = addLuckBar(page, y, drop.kills, drop.expected)
    local luck = ns.Chronicle.getLuck(drop.kills, drop.expected)
    local gap = math.floor(drop.kills - drop.expected + 0.5)
    if gap == 0 then
        return y
    end
    local text = gap > 0
            and ns.Lp(
                math.abs(gap),
                "%d kill more than expected: %s.",
                "%d kills more than expected: %s.",
                describeLuck(luck)
            )
        or ns.Lp(
            math.abs(gap),
            "%d kill fewer than expected: %s.",
            "%d kills fewer than expected: %s.",
            describeLuck(luck)
        )
    page:addText(text, PADDING, y, {
        font = "GameFontHighlightSmall",
        color = gap > 0 and UNLUCKY or LUCKY,
        width = page.width - 2 * PADDING,
    })
    return y + 18
end

---One drop of a story: its item, the kills it took (against the average when known), and each creature's share.
---@return number y Below it
local function addEntryDrop(page, y, drop)
    local itemName = drop.itemId and ns.Database.getItemField(drop.itemId, "name") or ns.L("Drops")
    y = addHeading(page, y, itemName, drop.drops > 0 and ns.L("%d collected while counted", drop.drops) or nil)
    if drop.expected then
        y = addDropLuck(page, y, drop)
    else
        y = addFact(page, y, ns.L("Kills"), tostring(drop.kills))
    end
    local npcIds = {}
    for npcId in pairs(drop.killsByNpcId or {}) do
        npcIds[#npcIds + 1] = npcId
    end
    table.sort(npcIds, function(first, second)
        return drop.killsByNpcId[first] > drop.killsByNpcId[second]
    end)
    for _, npcId in ipairs(npcIds) do
        local chance = drop.itemId and ns.Drops.getChance(drop.itemId, npcId)
        local kills = ns.Lp(drop.killsByNpcId[npcId], "%d kill", "%d kills")
        y = addFact(page, y, getNpcName(npcId), kills .. (chance and (DOT .. ns.Drops.formatChance(chance)) or ""))
    end
    return y + 6
end

---One quest's story: how it went, the kills its drops took, what it gave.
local function drawEntry(page, entry)
    local y = 10
    -- The header says where in the journal this is: the day and the time; the card is the quest
    pageTitle, pageNote = ns.L("Journal"), composeEntryHeader(entry)
    -- A quest card: the zone's map art as a banner with the quest's name and a line about it, the quest's own words,
    -- then on the game's dark reward tiles only what says something
    y = ChroniclePage.addQuestCard(page, y, entry, getShownTitle(entry), composeEntryFacts(entry))
    y = ChroniclePage.addSourceTag(page, y, entry)
    local tiles = composeEntryTiles(entry)
    if #tiles > 0 then
        y = addRewardStrip(page, y, tiles)
    end
    y = ChroniclePage.addChain(page, y, entry)
    y = ChroniclePage.addLevelShare(page, y, entry)
    for _, drop in ipairs(entry.drops or {}) do
        y = addEntryDrop(page, y, drop)
    end
    if entry.rewardLink then
        y = addFact(page, y, ns.L("Reward chosen"), entry.rewardLink)
    end
    return y + PADDING
end

---------------------------------------------------------------------------------------------------------------
-- Zones

local LOW_LEVEL_LEFT = { 0.33, 0.31, 0.28 } -- what is left and low-level: a muted grey after the done part

---The reputation panel's colours: red, orange, yellow, then green as a zone fills, as standing rises.
local function getProgressColor(share)
    if share >= 0.9 then
        return { 0.3, 0.68, 0.3 }
    elseif share >= 0.5 then
        return { 0.8, 0.66, 0.2 }
    elseif share >= 0.2 then
        return { 0.82, 0.48, 0.2 }
    end
    return { 0.72, 0.26, 0.2 }
end

---A zone's progress as the reputation panel draws standing: the done part coloured by how far along it is, the
---low-level part of what is left in a muted grey (not worth going back for), the count inside the bar.
local function addZoneBar(canvas, x, y, width, height, zone)
    local total = math.max(zone.totalCount, 1)
    local summary = zone.summary or {}
    local lowCount = (summary.lowAvailable or 0) + (summary.lowNotYet or 0)
    -- The game's progress bar: what is done in its colour, then what is left that is low-level, greyed
    canvas:addStatBar(x, y - 1, width, height + 2, {
        { share = zone.doneCount / total, color = getProgressColor(zone.doneCount / total) },
        { share = lowCount / total, color = LOW_LEVEL_LEFT },
    }, 2)
    if height >= 12 then
        canvas:addText(zone.doneCount .. " / " .. zone.totalCount, x, y + (height - 12) / 2, {
            font = "GameFontHighlightSmall",
            color = COLORS.white,
            width = width,
            justify = "CENTER",
            isSingleLine = true,
        })
    end
end

---A zone's levels and what is left there, for its row's tooltip.
local function showZoneNote(button, zone)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(zone.name, 1, 1, 1)
    if zone.minLevel then
        GameTooltip:AddLine(
            ns.L(
                "Levels %s",
                zone.minLevel == zone.maxLevel and zone.minLevel or (zone.minLevel .. "-" .. zone.maxLevel)
            ),
            1,
            0.82,
            0
        )
    end
    local summary = zone.summary or { inLog = 0, available = 0, notYet = 0, lowAvailable = 0, lowNotYet = 0 }
    GameTooltip:AddLine(
        ns.L(
            "%d done, %d in your log, %d to pick up, %d not yet",
            zone.doneCount,
            summary.inLog,
            summary.available,
            summary.notYet
        ),
        0.85,
        0.81,
        0.66,
        true
    )
    local lowCount = (summary.lowAvailable or 0) + (summary.lowNotYet or 0)
    if lowCount > 0 then
        GameTooltip:AddLine(ns.L("%d of what is left is low-level", lowCount), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local CONTINENT_ORDER =
    { ["Eastern Kingdoms"] = 1, Kalimdor = 2, Dungeons = 7, Raids = 8, Battlegrounds = 9, Elsewhere = 10 }
local OWN_CONTINENT_NAMES = { Dungeons = true, Raids = true, Battlegrounds = true, Elsewhere = true } -- the addon's, not the game's maps'

---Every zone with a quest done, on the page as a table, continent by continent: the name to open it, the levels
---its quests are for, a bar of how far it is done, and the count.
local function drawZoneTable(page, zones)
    local completeCount = 0
    for _, zone in ipairs(zones) do
        completeCount = completeCount + (zone.doneCount >= zone.totalCount and 1 or 0)
    end
    pageTitle = ns.L("Zones")
    pageNote = ns.L("%d places%s%d complete", #zones, DOT, completeCount)
    local y = 10
    if #zones == 0 then
        page:addText(
            ns.L("Zones show here once a quest is done in them."),
            PADDING,
            y,
            { font = "QuestFont", color = COLORS.softInk, width = page.width - 2 * PADDING }
        )
        return y + 40
    end
    local continents, zonesByContinent = {}, {}
    for _, zone in ipairs(zones) do
        local name = zone.continentName or "Elsewhere"
        if not zonesByContinent[name] then
            zonesByContinent[name] = {}
            continents[#continents + 1] = name
        end
        table.insert(zonesByContinent[name], zone)
    end
    table.sort(continents, function(first, second)
        local firstOrder, secondOrder = CONTINENT_ORDER[first] or 5, CONTINENT_ORDER[second] or 5
        if firstOrder ~= secondOrder then
            return firstOrder < secondOrder
        end
        return first < second
    end)
    local width = page.width - 2 * PADDING
    for _, continent in ipairs(continents) do
        y = addHeading(page, y, OWN_CONTINENT_NAMES[continent] and ns.L(continent) or continent)
        local continentZones = zonesByContinent[continent]
        -- Dungeons and raids by level, in the order they are run; zones the most done first, so the nearly
        -- finished lead
        local isByLevel = continent == "Dungeons" or continent == "Raids"
        table.sort(continentZones, function(first, second)
            if isByLevel and (first.minLevel or 999) ~= (second.minLevel or 999) then
                return (first.minLevel or 999) < (second.minLevel or 999) -- one without known levels goes last
            end
            local firstShare, secondShare =
                first.doneCount / math.max(first.totalCount, 1), second.doneCount / math.max(second.totalCount, 1)
            if not isByLevel and firstShare ~= secondShare then
                return firstShare > secondShare
            end
            return first.name < second.name
        end)
        -- Each zone a card on its own map art, with how far it is done; a click opens the zone
        y = ChroniclePage.addZoneCards(page, y, continentZones) + 6
    end
    page:addText(ns.L("Point at a zone for its levels and what is left; click it for its quests."), PADDING, y, {
        font = "GameFontHighlightSmall",
        color = COLORS.softInk,
        width = width,
    })
    return y + 24 + PADDING
end

---A dungeon's quests left, as one run can take them (Availability.getDungeonRun): in the log, to pick up before going
---(lead-ins named as such), found inside, behind a lead-in, not yet. Each says where it stands; a click opens it.
---@return number y
addDungeonQuests = function(page, y, zone)
    local run = ns.Availability.getDungeonRun(zone.zoneId)
    local width = page.width - 2 * PADDING
    local dungeon = ns.Database.getDungeon(zone.zoneId)
    if dungeon and dungeon.isLearned then
        local noteHeight = page:addText(
            ns.L(
                "Learned from your runs: the quest database does not know this dungeon yet, so only the quests you picked up, worked on or handed in inside are listed. More may be done here. The QuestieTrace addon helps the database learn it."
            ),
            PADDING,
            y,
            {
                font = "GameFontHighlightSmall",
                color = COLORS.softInk,
                width = width,
            }
        )
        y = y + 8 + math.max(tonumber(noteHeight) or 0, 28)
    end
    local function getTitle(quest)
        return quest.level and quest.level > 0 and string.format("[%d] %s", quest.level, quest.title) or quest.title
    end
    local function addQuestLine(quest, status)
        if quest.isLowLevel then
            status = status .. DOT .. ns.L("low-level")
        end
        page:addText(getTitle(quest), PADDING, y, {
            font = "GameFontNormal",
            color = quest.blocker and COLORS.softInk or COLORS.brown,
            width = width * 0.55,
            isSingleLine = true,
        })
        page:addText(status, PADDING + width * 0.55 + 6, y + 1, {
            font = "GameFontHighlightSmall",
            color = COLORS.softInk,
            width = width * 0.45 - 6,
            justify = "RIGHT",
            isSingleLine = true,
        })
        page:addButton(PADDING - 3, y - 3, width + 6, 20, function()
            ns.Log.showQuestAnywhere(quest.questId) -- the window leaves the chronicle for the quest
        end)
        y = y + 20
    end
    local function addSection(title, quests, getStatus)
        if #quests == 0 then
            return
        end
        page:addText(
            title .. DOT .. #quests,
            PADDING,
            y + 2,
            { font = "GameFontHighlightSmall", color = COLORS.softInk, isSingleLine = true }
        )
        y = y + 18
        for _, quest in ipairs(quests) do
            addQuestLine(quest, getStatus(quest))
        end
        y = y + 6
    end
    addSection(ns.L("In your log"), run.inLog, function()
        return ns.L("in your log")
    end)
    addSection(ns.L("Pick up before you go"), run.pickUp, function(quest)
        local startZoneId = ns.Availability.getStartZoneId(quest.questId)
        if quest.isLeadIn then
            return ns.L("lead-in for %s", quest.leadsToTitle)
        end
        return startZoneId and ns.L("pick up in %s", ns.Database.getZoneName(startZoneId)) or ns.L("pick up")
    end)
    addSection(ns.L("Found inside"), run.foundInside, function(quest)
        return quest.startType == "item" and ns.L("drops inside") or ns.L("given inside")
    end)
    addSection(ns.L("Behind a lead-in"), run.behindLeadIn, function(quest)
        local firstName = quest.leadInIds and quest.leadInIds[1] and ns.QuestText.getQuestName(quest.leadInIds[1])
        if not firstName then
            return ns.L("after a lead-in")
        end
        return #quest.leadInIds > 1 and ns.L("after %s and %d more", firstName, #quest.leadInIds - 1)
            or ns.L("after %s", firstName)
    end)
    addSection(ns.L("Not yet"), run.notYet, function(quest)
        return quest.blocker and quest.blocker.text or ns.L("not yet")
    end)
    return y + 4
end

---Each count of what is left says how many of it are low-level: far below the character, and so is all they lead to.
---@return string text "4", "4 · 2 low-level", "4, all low-level"
local function formatLeft(count, lowCount)
    if count > 0 and lowCount == count then
        return ns.Lp(count, "%d, low-level", "%d, all low-level")
    end
    return lowCount > 0 and ns.L("%d%s%d low-level", count, DOT, lowCount) or tostring(count)
end

local function openZoneInAvailable(zoneId)
    ns.Log.showZone(zoneId) -- the window leaves the chronicle for the zone
end

---A zone's page's top: back to all zones, the zone's bar across the page, and its time, experience and kills.
---@return number y Below them
local function addZoneOverview(page, y, zone)
    local _, backWidth = page:addText(
        ns.L("< All zones"),
        PADDING,
        y,
        { font = "GameFontNormal", color = COLORS.brown, isSingleLine = true }
    )
    page:addButton(PADDING - 3, y - 3, backWidth + 6, 20, selectZone, false)
    y = y + 24
    -- The same bar as in the table of zones, across the page
    local width = page.width - 2 * PADDING
    addZoneBar(page, PADDING, y + 2, width, 18, zone)
    y = y + 30
    local luck = ns.Chronicle.getLuck(zone.kills, zone.expected)
    return addRewardStrip(page, y, {
        {
            label = ns.L("Time here"),
            value = zone.playedSeconds > 0 and formatDuration(zone.playedSeconds) or "-",
            icon = ICONS .. "INV_Misc_PocketWatch_01",
            note = ns.L("The time its quests took, added up, since the chronicle began"),
        },
        {
            label = ns.L("Experience"),
            value = formatNumber(zone.experience),
            icon = ICONS .. "XP_Icon",
            note = ns.L("From %d quests handed in since the chronicle began", #zone.entries),
        },
        {
            label = ns.L("Kills for drops"),
            value = formatNumber(zone.kills),
            icon = ICONS .. "Ability_Tracking",
            luck = zone.expected > 0 and luck or nil,
            note = luck and ns.L("Against an average of %s: %s", formatNumber(zone.expected), describeLuck(luck))
                or ns.L("None counted yet"),
        },
    })
end

---Still to do here: what is in the log, to pick up and not yet, how much of it low-level; a dungeon's quests; the
---link to the zone in Available.
---@return number y Below it
local function addZoneLeft(page, y, zone)
    local summary = zone.summary or { inLog = 0, available = 0, notYet = 0 }
    local left = summary.inLog + summary.available + summary.notYet
    y = addHeading(page, y, ns.L("Still to do here"), tostring(left))
    if left == 0 then
        page:addText(
            zone.isDungeon and ns.L("Nothing left to do in here.") or ns.L("Nothing left that starts here."),
            PADDING,
            y,
            { font = "QuestFont", color = COLORS.softInk, isSingleLine = true }
        )
        return y + 22
    end
    local lowAvailable, lowNotYet = summary.lowAvailable or 0, summary.lowNotYet or 0
    y = addFact(page, y, ns.L("In your log"), tostring(summary.inLog))
    y = addFact(page, y, ns.L("To pick up now"), formatLeft(summary.available, lowAvailable))
    y = addFact(page, y, ns.L("Not yet"), formatLeft(summary.notYet, lowNotYet))
    if summary.inLog == 0 and lowAvailable + lowNotYet == left then
        page:addText(ns.L("Everything left here is low-level: little to gain at your level."), PADDING, y, {
            font = "QuestFont",
            color = COLORS.softInk,
            width = page.width - 2 * PADDING,
        })
        y = y + 22
    end
    y = y + 4
    if zone.isDungeon then
        y = addDungeonQuests(page, y, zone)
    end
    local _, linkWidth = page:addText(
        ns.L("Open in Available"),
        PADDING,
        y,
        { font = "QuestFont", color = COLORS.brown, isSingleLine = true }
    )
    page:addRect(PADDING, y + 15, linkWidth, 1, COLORS.brown, 1)
    page:addButton(PADDING - 3, y - 2, linkWidth + 6, 20, openZoneInAvailable, zone.zoneId)
    return y + 28
end

local function isQuestLevelLower(first, second)
    return (ns.Database.getQuestField(first, "questLevel") or 0)
        < (ns.Database.getQuestField(second, "questLevel") or 0)
end

---The quests done here before the chronicle, as names only, lowest level first, in two columns.
---@return number y Below them
local function addZoneEarlier(page, y, zone)
    page:addText(
        ns.L("Before the chronicle") .. DOT .. #zone.earlierQuestIds,
        PADDING,
        y + 2,
        { font = "GameFontHighlightSmall", color = COLORS.softInk, isSingleLine = true }
    )
    y = y + 20
    local columnWidth = (page.width - 2 * PADDING - 12) / 2
    local earlierQuestIds = {}
    for _, questId in ipairs(zone.earlierQuestIds) do
        earlierQuestIds[#earlierQuestIds + 1] = questId
    end
    table.sort(earlierQuestIds, isQuestLevelLower)
    for index, questId in ipairs(earlierQuestIds) do
        local level = ns.Database.getQuestField(questId, "questLevel") or 0
        local title = ns.QuestText.getQuestName(questId) or ns.L("Quest %d", questId)
        local column = (index - 1) % 2
        page:addText(
            level > 0 and string.format("[%d] %s", level, title) or title,
            PADDING + column * (columnWidth + 12),
            y,
            {
                font = "GameFontHighlightSmall",
                color = COLORS.ink,
                width = columnWidth,
                isSingleLine = true,
            }
        )
        if column == 1 or index == #earlierQuestIds then
            y = y + 16
        end
    end
    return y
end

---Done here: since the chronicle began, with when; before it, as names only.
---@return number y Below them
local function addZoneDone(page, y, zone)
    y = addHeading(page, y, ns.L("Done here"), tostring(#zone.entries + #zone.earlierQuestIds))
    for index, entry in ipairs(zone.entries) do
        if index > MAX_ZONE_QUESTS then
            break
        end
        local kills, expected = ns.Chronicle.getEntryKills(entry)
        y = addFact(
            page,
            y,
            getEntryTitle(entry),
            formatWhen(entry.turnedInAt) .. (expected > 0 and (DOT .. ns.Lp(kills, "%d kill", "%d kills")) or "")
        )
    end
    if #zone.earlierQuestIds > 0 then
        y = addZoneEarlier(page, y, zone)
    end
    return y
end

---One zone's page: its progress, what is left, what was done.
local function drawZone(page, zone)
    pageTitle = zone.name
    pageNote = zone.isDungeon and ns.L("%d of %d quests in this dungeon done", zone.doneCount, zone.totalCount)
        or ns.L("%d of %d quests that start here done", zone.doneCount, zone.totalCount)
    local y = addZoneOverview(page, 8, zone)
    y = addZoneLeft(page, y, zone)
    y = addZoneDone(page, y, zone)
    return y + PADDING
end

---------------------------------------------------------------------------------------------------------------
-- Kills and luck

---@return string texture An item's icon, the game's question mark when it is not known yet
local function getItemIcon(itemId)
    local icon = itemId
        and (
            C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId)
            or GetItemIcon and GetItemIcon(itemId) -- luacheck: ignore 113 (an older client's fallback)
        )
    return icon or (ICONS .. "INV_Misc_QuestionMark")
end

---@return string text An item's name for the page: in its quality's colour when better than common (as a link
---shows it), in ink otherwise, since white does not read on parchment
local function getItemName(itemId)
    local name, _, quality = nil, nil, nil
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo -- luacheck: ignore 113 (an older client's fallback)
    if getItemInfo then
        name, _, quality = getItemInfo(itemId)
    end
    if not name then
        ns.Prices.requestItem(itemId)
        return ns.Database.getItemField(itemId, "name") or ns.L("Item %d", itemId)
    end
    local color = quality and quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return color and colorText(name, { color.r, color.g, color.b }) or name
end

---Opens a quest's story in the Journal.
local openEntry = composeClickHandler(function(entry)
    for index, other in ipairs(ns.Chronicle.getEntries()) do
        if other == entry then
            ChroniclePage.chapterIndex, selectedEntryIndex = getChapterIndex("journal"), index
            journalListScroll, pendingPageScroll = 0, 0
        end
    end
end)

local function drawKills(page)
    local summary = ns.Chronicle.composeSummary()
    pageTitle, pageNote = ns.L("Kills and luck"), ns.L("Kills for quest drops against what an average player needs")
    local y = 10
    local luckText = summary.luck and (formatLuck(summary.luck)) or "-"
    y = addRewardStrip(page, y, {
        {
            label = ns.L("Kills for drops"),
            value = formatNumber(summary.kills),
            icon = ICONS .. "Ability_Tracking",
            note = ns.L("Counted since the chronicle began"),
        },
        {
            label = ns.L("Expected"),
            value = formatNumber(summary.expected),
            icon = ICONS .. "INV_Misc_Note_01",
            note = ns.L("What an average player needs for the same drops"),
        },
        {
            label = ns.L("Luck"),
            value = luckText,
            icon = ICONS .. "INV_Misc_Ticket_Tarot_Madness",
            luck = summary.luck,
            note = summary.luck and describeLuck(summary.luck) or ns.L("No kills counted yet"),
        },
    })

    -- Highlights: a record each, never a list that grows
    local cells = {}
    local function addQuestRecord(kind, entry)
        local kills, expected = ns.Chronicle.getEntryKills(entry)
        local drop = entry.drops[1]
        cells[#cells + 1] = {
            icon = getItemIcon(drop and drop.itemId),
            lines = {
                { text = kind, font = "GameFontHighlightSmall", color = COLORS.softInk },
                { text = getShownTitle(entry), font = "QuestFont" },
                {
                    text = ns.L("%s, %d expected", ns.Lp(kills, "%d kill", "%d kills"), math.floor(expected + 0.5)),
                    font = "GameFontHighlightSmall",
                    color = kills > expected and WORSE or BETTER,
                },
            },
            handleClick = openEntry,
            data = entry,
        }
    end
    if summary.luckiest then
        addQuestRecord(ns.L("Luckiest"), summary.luckiest)
    end
    if summary.unluckiest and summary.unluckiest ~= summary.luckiest then
        addQuestRecord(ns.L("Unluckiest"), summary.unluckiest)
    end
    if summary.rarest then
        local drop = summary.rarest.drop
        cells[#cells + 1] = {
            icon = getItemIcon(drop.itemId),
            lines = {
                { text = ns.L("Rarest drop"), font = "GameFontHighlightSmall", color = COLORS.softInk },
                { text = getItemName(drop.itemId), font = "QuestFont" },
                {
                    text = ns.L("a %s chance a kill", ns.Drops.formatChance(summary.rarest.chance)),
                    font = "GameFontHighlightSmall",
                    color = COLORS.softInk,
                },
            },
            handleClick = openEntry,
            data = summary.rarest.entry,
        }
    end
    if summary.longestHunt then
        local drop = summary.longestHunt.drop
        cells[#cells + 1] = {
            icon = getItemIcon(drop.itemId),
            lines = {
                { text = ns.L("Longest hunt"), font = "GameFontHighlightSmall", color = COLORS.softInk },
                { text = getShownTitle(summary.longestHunt.entry), font = "QuestFont" },
                {
                    text = ns.L("%d kills for %d", drop.kills, drop.drops),
                    font = "GameFontHighlightSmall",
                    color = COLORS.softInk,
                },
            },
            handleClick = openEntry,
            data = summary.longestHunt.entry,
        }
    end
    if summary.longestDry then
        local drop = summary.longestDry.drop
        cells[#cells + 1] = {
            icon = getItemIcon(drop.itemId),
            lines = {
                { text = ns.L("Longest dry spell"), font = "GameFontHighlightSmall", color = COLORS.softInk },
                { text = ns.L("%s kills", formatNumber(drop.longestDry)), font = "QuestFont" },
                { text = ns.L("before a drop came"), font = "GameFontHighlightSmall", color = COLORS.softInk },
            },
            handleClick = openEntry,
            data = summary.longestDry.entry,
        }
    end
    if summary.firstKillDrops > 0 then
        cells[#cells + 1] = {
            icon = ICONS .. "INV_Misc_Dice_01",
            lines = {
                { text = ns.L("Dropped on the first kill"), font = "GameFontHighlightSmall", color = COLORS.softInk },
                {
                    text = summary.firstKillDrops == 1 and ns.L("Once")
                        or ns.L("%s times", formatNumber(summary.firstKillDrops)),
                    font = "QuestFont",
                },
                { text = ns.L("no kill wasted"), font = "GameFontHighlightSmall", color = COLORS.softInk },
            },
        }
    end
    y = addHeading(page, y, ns.L("Highlights"))
    if #cells == 0 then
        y = y
            + page:addText(
                ns.L("Highlights start with the first quest handed in whose drops had their kills counted."),
                PADDING,
                y,
                {
                    font = "QuestFont",
                    color = COLORS.softInk,
                    width = page.width - 2 * PADDING,
                }
            )
            + 10
    else
        y = addEntryGrid(page, y, cells)
    end

    -- The creatures killed most for drops, a few at most
    if #summary.mostKilledList > 0 then
        y = addHeading(
            page,
            y + 2,
            ns.L("Killed most for drops"),
            #summary.mostKilledList > 1 and ns.L("top %d", #summary.mostKilledList) or nil
        )
        for _, killed in ipairs(summary.mostKilledList) do
            y = addFact(page, y, getNpcName(killed.npcId), formatNumber(killed.kills))
        end
    end
    return y + PADDING
end

---@return number height
local function drawList(list)
    local width = list.width
    -- Under the flat border's buttons when they stand at the top of this side, as the settings' sections are
    local y = ns.settings.windowBorder == "flat" and ns.Log.TITLE_HEIGHT or 4
    list:addText(
        ns.L("CHRONICLE"),
        8,
        y + 4,
        { font = "GameFontNormalSmall", color = COLORS.parchment, isSingleLine = true }
    )
    y = y + 22
    for index, chapter in ipairs(CHAPTERS) do
        local isChosen = index == ChroniclePage.chapterIndex
        if isChosen then
            list:addRect(0, y, width, ROW_HEIGHT, HEADER_BAR_LOW)
            list:addRect(0, y, width, ROW_HEIGHT / 2, HEADER_BAR_HIGH, 1)
            list:addRect(0, y, 3, ROW_HEIGHT, SELECTED_EDGE, 2)
        end
        list:addIcon(12, y + 4, ROW_HEIGHT - 8, chapter.icon, nil, 3, { 0.08, 0.92, 0.08, 0.92 })
        list:addText(ns.L(chapter.title), 18 + ROW_HEIGHT - 8, y + 9, {
            font = "GameFontNormal",
            color = isChosen and COLORS.gold or COLORS.parchment,
            isSingleLine = true,
            width = width - 50,
        })
        list:addButton(0, y, width, ROW_HEIGHT, selectChapter, index)
        y = y + ROW_HEIGHT + 2
    end
    y = y + 8
    if getChapterKey() == "days" then
        list:addRect(6, y, width - 12, 1, COLORS.rule)
        y = ChroniclePage.drawDayList(list, y + 4)
    end
    return y + 8
end

---Draws the chronicle into the window's list and page.
---@return number listHeight, number pageHeight
---@return string pageTitle, string pageNote For the page's header
function ChroniclePage.draw(list, page)
    local chapterKey = getChapterKey()
    local zones = chapterKey == "zones" and ns.Chronicle.getZones() or {}
    local listHeight = drawList(list)
    local pageHeight
    if chapterKey == "days" then
        pageHeight, pageTitle, pageNote = ChroniclePage.drawDay(page)
    elseif chapterKey == "journal" then
        -- The list of quests with its search, or one quest's story (the Back button returns to the list)
        local entry = selectedEntryIndex and ns.Chronicle.getEntries()[selectedEntryIndex]
        if entry then
            pageHeight = drawEntry(page, entry)
        elseif selectedEntryIndex == 0 then
            pageHeight = drawEarlier(page)
        else
            pageHeight = drawJournalPage(page)
        end
    elseif chapterKey == "zones" then
        local shownZone
        for _, zone in ipairs(zones) do
            if zone.zoneId == selectedZoneId then
                shownZone = zone
            end
        end
        pageHeight = shownZone and drawZone(page, shownZone) or drawZoneTable(page, zones)
    elseif chapterKey == "kills" then
        pageHeight = drawKills(page)
    else
        pageHeight = drawGlance(page)
    end
    return listHeight, pageHeight, pageTitle, pageNote
end

---Turns to a zone's page in the Zones chapter.
function ChroniclePage.openZone(zoneId)
    ChroniclePage.chapterIndex, selectedZoneId = getChapterIndex("zones"), zoneId
end

---@return table? entry The latest Journal entry of a quest handed in, and its place in the Journal; nil when the
---chronicle has none (done before it began, or never)
function ChroniclePage.findEntry(questId)
    local entries = ns.Chronicle.getEntries()
    for index = #entries, 1, -1 do
        if entries[index].questId == questId then
            return entries[index], index
        end
    end
    return nil
end

---Opens the chronicle on a quest done: its story in the Journal, or the quests done before the chronicle began.
function ChroniclePage.openQuest(questId)
    local _, index = ChroniclePage.findEntry(questId)
    ChroniclePage.chapterIndex, selectedEntryIndex, selectedZoneId = getChapterIndex("journal"), index or 0, nil
    journalListScroll, pendingPageScroll = 0, 0
    ns.LogState.view = "chronicle"
    ns.Log.refresh()
end

---Starts the chronicle again on its first chapter, nothing picked: as the window opens it (Log.toggleChronicle).
function ChroniclePage.openFirstChapter()
    ChroniclePage.chapterIndex, selectedEntryIndex, selectedZoneId = 1, nil, nil
    pendingPageScroll = 0
end

-- Shared with the chronicle's other files: its Days chapter (ChronicleDays.lua) and its pictures
-- (ChroniclePictures.lua)
ChroniclePage.PADDING = PADDING
ChroniclePage.ICONS = ICONS
ChroniclePage.BETTER, ChroniclePage.WORSE = BETTER, WORSE
ChroniclePage.SELECTED_EDGE = SELECTED_EDGE
ChroniclePage.addHeading = addHeading
ChroniclePage.addRewardStrip = addRewardStrip
ChroniclePage.addEntryGrid = addEntryGrid
ChroniclePage.addFact = addFact
ChroniclePage.colorText = colorText
ChroniclePage.composeClickHandler = composeClickHandler
ChroniclePage.formatNumber = formatNumber
ChroniclePage.formatDayHeading = formatDayHeading
ChroniclePage.getNpcName = getNpcName
ChroniclePage.getShownTitle = getShownTitle
ChroniclePage.selectZone = selectZone
ChroniclePage.showZoneNote = showZoneNote
ChroniclePage.getProgressColor = getProgressColor
