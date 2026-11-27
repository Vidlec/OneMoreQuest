local _, ns = ...

-- The chronicle's Days chapter: a ledger of each day played (Ledger). On the chapters' side the days, the latest
-- first; on the page the month as a calendar (ChroniclePictures), then the chosen day's headlines, gold in and out
-- line by line, experience by source, chests and gathering, and the notable things it brought. Also Today's cards on
-- the first page (At a glance). Drawn with the pieces the chronicle's page shares (ChroniclePage.lua).
local ChroniclePage = ns.ChroniclePage
local COLORS = ns.Widgets.COLORS
local DOT = ns.Widgets.MIDDLE_DOT
local ICONS = ChroniclePage.ICONS
local PADDING = ChroniclePage.PADDING
local BETTER, WORSE = ChroniclePage.BETTER, ChroniclePage.WORSE
local SELECTED_EDGE = ChroniclePage.SELECTED_EDGE
local addHeading = ChroniclePage.addHeading
local addRewardStrip = ChroniclePage.addRewardStrip
local addEntryGrid = ChroniclePage.addEntryGrid
local addFact = ChroniclePage.addFact
local colorText = ChroniclePage.colorText
local composeClickHandler = ChroniclePage.composeClickHandler
local formatDuration = ChroniclePage.formatDuration
local formatNumber = ChroniclePage.formatNumber
local formatDayHeading = ChroniclePage.formatDayHeading
local getNpcName = ChroniclePage.getNpcName

---@return string text Money with its coins, a loss in red with a minus
local function formatSignedMoney(copper)
    if copper < 0 then
        return "|cffa33224-|r" .. ns.Widgets.formatMoney(-copper)
    end
    return ns.Widgets.formatMoney(copper)
end

---Money for a tile: a gold or more without its copper, to fit.
function ChroniclePage.formatTileMoney(copper)
    local amount = math.abs(copper) >= 10000 and (copper < 0 and -1 or 1) * (math.abs(copper) - math.abs(copper) % 100)
        or copper
    return formatSignedMoney(amount)
end

---@return number experience What the character still needs for the next level; 0 when not known
local function getExperienceToLevel()
    return UnitXPMax and UnitXP and (UnitXPMax("player") or 0) - (UnitXP("player") or 0) or 0
end

---@return string text, number[] color "2.2x average" (your average day), green when above it and red when below
local function compareWithAverage(value, averageValue)
    if not averageValue or averageValue <= 0 then
        return "", COLORS.softInk
    end
    local ratio = value / averageValue
    if ratio >= 1.1 then
        return ns.L("%.1fx average", ratio), BETTER
    elseif ratio <= 0.9 then
        return ns.L("%d%% of average", math.floor(ratio * 100 + 0.5)), WORSE
    end
    return ns.L("about average"), COLORS.softInk
end

---@return string text What a number is, then how it compares, in its colour
local function describeAgainstAverage(label, note, color)
    return note ~= "" and (label .. DOT .. colorText(note, color)) or label
end

---@return table cell One of today's cards: an icon, the number large, its label under it
local function composeTodayCell(icon, value, label)
    return {
        icon = icon,
        lines = {
            { text = value, font = "GameFontNormalLarge" },
            { text = label, font = "GameFontHighlightSmall", color = COLORS.softInk },
        },
    }
end

---Today on the first page: four cards, net gold, experience, quests and level, each set against an average day.
---@return number y Below the cards
function ChroniclePage.addToday(page, y, overview)
    local totals, average = overview.todayTotals, overview.average
    local day = overview.today
    local note = ns.Chronicle.formatShownDate("%A %d %B", ns.Chronicle.getNow())
    if totals then
        note = note .. DOT .. ns.L("%s so far", formatDuration(totals.played))
    end
    y = addHeading(page, y, ns.L("Today"), note)
    if not day then
        return y
            + page:addText(ns.L("Nothing yet today."), PADDING, y, { font = "QuestFont", color = COLORS.softInk })
            + 14
    end
    local level = UnitLevel and UnitLevel("player") or 0
    local levelText = day.levelFrom and day.levelFrom < level and ns.L("%d to %d", day.levelFrom, level)
        or tostring(level)
    local levelNote = ""
    local hours = totals.played / 3600
    local left = getExperienceToLevel()
    if hours >= 0.2 and totals.experience > 0 and left > 0 then
        levelNote = ns.L("next in %s", formatDuration(left / (totals.experience / hours) * 3600))
    end
    local goldNote, goldColor = compareWithAverage(totals.net, average and average.net)
    local experienceNote, experienceColor = compareWithAverage(totals.experience, average and average.experience)
    -- The level's icon is the game's for the ten it is in
    local levelIcon = ICONS .. "Achievement_Level_" .. math.min(math.max(math.floor(level / 10) * 10, 10), 60)
    return addEntryGrid(page, y + 2, {
        composeTodayCell(
            ICONS .. "INV_Misc_Coin_01",
            ChroniclePage.formatTileMoney(totals.net),
            describeAgainstAverage(ns.L("Gold, net"), goldNote, goldColor)
        ),
        composeTodayCell(
            ICONS .. "XP_Icon",
            formatNumber(totals.experience),
            describeAgainstAverage(ns.L("Experience"), experienceNote, experienceColor)
        ),
        composeTodayCell(
            ICONS .. "INV_Scroll_03",
            formatNumber(day.quests or 0),
            describeAgainstAverage(
                ns.L("Quests"),
                average and ns.L("average %s", formatNumber(average.quests)) or "",
                COLORS.softInk
            )
        ),
        composeTodayCell(levelIcon, levelText, describeAgainstAverage(ns.L("Level"), levelNote, COLORS.softInk)),
    }) + 2
end

local MAX_DAYS_LISTED = 60
local DAY_LINES = {
    gold = {
        { "looted", "Coins looted" },
        { "quests", "Quest rewards" },
        { "vendor", "Sold to vendors" },
        { "auction", "Auction house" },
        { "mail", "Mail" },
        { "other", "Other" },
    },
    spent = {
        { "repairs", "Repairs" },
        { "training", "Training" },
        { "flights", "Flights" },
        { "bought", "Bought" },
        { "auction", "Auction house" },
        { "other", "Other" },
    },
    xp = {
        { "quests", "Quests" },
        { "kills", "Kills" },
        { "rested", "  Rested bonus" },
        { "discovery", "Discovery" },
        { "other", "Other" },
    },
}
local SPENT_COLOR = { 0.64, 0.2, 0.14 }

---@return string[] keys The days kept, the latest first
function ChroniclePage.getDayKeys()
    local keys = {}
    for key in pairs(ns.Ledger.getDays()) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(first, second)
        return first > second
    end)
    return keys
end

---@return string text An item as its link (its name in its quality's colour), asked of the game when not known yet
local function getItemText(itemId)
    local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo -- luacheck: ignore 113 (an older client's fallback)
    local link = getItemInfo and select(2, getItemInfo(itemId))
    if link then
        return link
    end
    ns.Prices.requestItem(itemId)
    return ns.L("item %d", itemId)
end

local selectDay = composeClickHandler(function(key)
    ChroniclePage.selectedDayKey = key
end)

---The days on the list's side, the latest first: each with its gold and its levels.
---@return number y Below the list
function ChroniclePage.drawDayList(list, y)
    local keys = ChroniclePage.getDayKeys()
    ChroniclePage.selectedDayKey = ChroniclePage.selectedDayKey or keys[1]
    local width = list.width
    for index = 1, math.min(#keys, MAX_DAYS_LISTED) do
        local key = keys[index]
        local day = ns.Ledger.getDays()[key]
        local totals = ns.Ledger.composeTotals(day)
        local isSelected = key == ChroniclePage.selectedDayKey
        if isSelected then
            list:addRect(2, y, width - 4, 36, SELECTED_EDGE)
            list:addRect(3, y + 1, width - 6, 34, { 0.29, 0.24, 0.09 }, 1)
        end
        list:addText(formatDayHeading(ns.Ledger.getDayStamp(key)), 8, y + 3, {
            font = "GameFontNormal",
            color = isSelected and COLORS.white or COLORS.parchment,
            width = width - 14,
            isSingleLine = true,
        })
        local facts = { formatSignedMoney(totals.net) }
        local levels = (day.levelTo or day.levelFrom or 0) - (day.levelFrom or 0)
        if levels > 0 then
            facts[#facts + 1] = ns.Lp(levels, "+%d level", "+%d levels")
        end
        list:addText(
            table.concat(facts, DOT),
            8,
            y + 19,
            { font = "GameFontHighlightSmall", color = COLORS.tan, width = width - 14, isSingleLine = true }
        )
        list:addButton(0, y, width, 36, selectDay, key)
        y = y + 38
    end
    return y
end

---@return string note A day's page's note: the levels it saw and the time played
local function composeDayNote(day, totals)
    local noteParts = {}
    if day.levelFrom then
        noteParts[#noteParts + 1] = day.levelTo and ns.L("Level %d to %d", day.levelFrom, day.levelTo)
            or ns.L("Level %d", day.levelFrom)
    end
    noteParts[#noteParts + 1] = ns.L("%s played", formatDuration(totals.played))
    return table.concat(noteParts, DOT)
end

---A day's headlines on the reward tiles: gold, experience, quests, kills, deaths and time played.
---@return number y Below them
local function addDayTiles(page, y, day, totals)
    local hours = totals.played / 3600
    return addRewardStrip(page, y, {
        -- In a tile, a gold or more without its copper, to fit
        {
            label = ns.L("Gold, net"),
            value = ChroniclePage.formatTileMoney(totals.net),
            icon = ICONS .. "INV_Misc_Coin_01",
            note = ns.L("What came in, less what was spent: %s", formatSignedMoney(totals.net)),
        },
        {
            label = ns.L("Experience"),
            value = formatNumber(totals.experience),
            icon = ICONS .. "XP_Icon",
            note = hours >= 0.2 and ns.L("%s an hour", formatNumber(totals.experience / hours)) or nil,
        },
        {
            label = ns.L("Quests"),
            value = formatNumber(day.quests or 0),
            icon = ICONS .. "INV_Scroll_03",
            note = ns.L("Handed in"),
        },
        {
            label = ns.L("Kills"),
            value = formatNumber(day.kills or 0),
            icon = ICONS .. "Ability_Tracking",
            note = ns.L("Creatures you or your group fought"),
        },
        { label = ns.L("Deaths"), value = formatNumber(day.deaths or 0), icon = ICONS .. "Ability_Rogue_FeignDeath" },
        {
            label = ns.L("Time played"),
            value = formatDuration(totals.played),
            icon = ICONS .. "INV_Misc_PocketWatch_01",
        },
    })
end

local function formatMoney(copper)
    return ns.Widgets.formatMoney(copper)
end

local function formatSpent(copper)
    return "-" .. ns.Widgets.formatMoney(copper)
end

-- How each part of a day's record is listed: its lines in order, each amount's words, and their colour
local DAY_PARTS = {
    gold = { lines = DAY_LINES.gold, format = formatMoney },
    spent = { lines = DAY_LINES.spent, format = formatSpent, color = SPENT_COLOR },
    xp = { lines = DAY_LINES.xp, format = formatNumber },
}

---A part of a day's record line by line, each source or purpose that has an amount.
---@param partName string "gold", "spent" or "xp"
---@return number y Below the lines
local function addDayPartLines(page, y, day, partName)
    local part = DAY_PARTS[partName]
    local amounts = day[partName] or {}
    for _, line in ipairs(part.lines) do
        local amount = amounts[line[1]]
        if amount then
            y = addFact(page, y, ns.L(line[2]), part.format(amount), part.color)
        end
    end
    return y
end

---Gold: where it came from, then where it went, and how much an hour.
---@return number y Below it
local function addDayGold(page, y, day, totals)
    if totals.income <= 0 and totals.spent <= 0 then
        return y
    end
    y = addHeading(page, y, ns.L("Gold")) -- the net is on the tiles above
    y = addDayPartLines(page, y, day, "gold")
    y = addDayPartLines(page, y, day, "spent")
    local hours = totals.played / 3600
    if hours >= 0.2 then
        y = addFact(page, y, ns.L("An hour"), formatSignedMoney(math.floor(totals.net / hours)))
    end
    return y + 6
end

---Experience by source, and how much an hour (today, also when the next level comes at this pace).
---@return number y Below it
local function addDayExperience(page, y, day, totals, key)
    if totals.experience <= 0 then
        return y
    end
    y = addHeading(page, y, ns.L("Experience")) -- the total is on the tiles above
    y = addDayPartLines(page, y, day, "xp")
    local hours = totals.played / 3600
    if hours >= 0.2 then
        local perHour = totals.experience / hours
        local value = formatNumber(perHour)
        local left = getExperienceToLevel()
        if key == ns.Ledger.getDayKey() and left > 0 and perHour > 0 then
            value = value .. DOT .. ns.L("next level in %s", formatDuration(left / perHour * 3600))
        end
        y = addFact(page, y, ns.L("An hour"), value)
    end
    return y + 6
end

---Chests opened and herbs and ore gathered, and what the gathering gave.
---@return number y Below them
local function addDayGathering(page, y, day)
    if (day.chests or 0) + (day.nodes or 0) <= 0 then
        return y
    end
    y = addHeading(page, y, ns.L("Chests and gathering"), formatNumber((day.chests or 0) + (day.nodes or 0)))
    if day.chests then
        y = addFact(page, y, ns.L("Chests opened"), formatNumber(day.chests))
    end
    if day.nodes then
        y = addFact(page, y, ns.L("Herbs and ore"), formatNumber(day.nodes))
    end
    for itemId, count in pairs(day.gathered or {}) do
        y = addFact(page, y, "", getItemText(itemId) .. " x" .. count)
    end
    return y + 6
end

---@return string from Where a notable thing came from: a quest's reward, a chest, fishing, or the creature
local function describeLootSource(from)
    return from == "quest" and ns.L("quest reward")
        or from == "chest" and ns.L("from a chest")
        or from == "fishing" and ns.L("fished")
        or type(from) == "number" and getNpcName(from)
        or ""
end

---What the day brought worth noting.
---@return number y Below it
local function addDayLoot(page, y, day)
    if not (day.loot and #day.loot > 0) then
        return y
    end
    y = addHeading(page, y, ns.L("Notable loot"), formatNumber(#day.loot))
    for _, loot in ipairs(day.loot) do
        y = addFact(page, y, describeLootSource(loot.from), getItemText(loot.itemId))
    end
    return y
end

---A day's page: its headlines, then gold in and out line by line, experience by source, chests and nodes,
---and the notable things it brought.
---@return number height, string title, string note
function ChroniclePage.drawDay(page)
    local key = ChroniclePage.selectedDayKey or ChroniclePage.getDayKeys()[1]
    local day = key and ns.Ledger.getDays()[key]
    if not day then
        page:addText(ns.L("Nothing kept yet: from now on, each day you play gets a page here."), PADDING, 14, {
            font = "QuestFont",
            color = COLORS.softInk,
            width = page.width - 2 * PADDING,
        })
        return 60, ns.L("Days"), ""
    end
    local totals = ns.Ledger.composeTotals(day)
    local title = ns.Chronicle.formatShownDate("%A %d %B", ns.Ledger.getDayStamp(key))
    local note = composeDayNote(day, totals)
    -- The month first, each day shaded by its quests; the chosen day's ledger under it
    local y = ChroniclePage.addCalendar(page, 10, key)
    y = addHeading(page, y, title)
    y = addDayTiles(page, y, day, totals)
    y = addDayGold(page, y, day, totals)
    y = addDayExperience(page, y, day, totals, key)
    y = addDayGathering(page, y, day)
    y = addDayLoot(page, y, day)
    return y + PADDING, title, note
end

ChroniclePage.selectDay = selectDay
