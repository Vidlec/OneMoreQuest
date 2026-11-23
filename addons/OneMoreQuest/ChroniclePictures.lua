local _, ns = ...

-- The chronicle's pictures: what it keeps, drawn rather than listed. The Days chapter's month (each day shaded by the
-- quests done), the records as framed plaques, the zones as cards on their own map art, and a journal entry as a
-- quest card on its zone's map art.
-- Drawn on the chronicle's page with its canvas; the chapters themselves are in ChroniclePage.lua.
local ChroniclePage = ns.ChroniclePage
local COLORS = ns.Widgets.COLORS
local DOT = ns.Widgets.MIDDLE_DOT
local WHITE = "Interface\\Buttons\\WHITE8X8"
local ICONS = "Interface\\Icons\\"

---------------------------------------------------------------------------------------------------------------
-- The Days chapter's month

local CALENDAR_SHADES = { { 0.86, 0.72, 0.45 }, { 0.72, 0.51, 0.24 }, { 0.54, 0.33, 0.13 }, { 0.36, 0.19, 0.06 } }
local CALENDAR_EMPTY = { 0.98, 0.93, 0.8 }
local CALENDAR_GOLD = { 1, 0.82, 0 }

local function getMonthKey(key)
    return key and key:sub(1, 7) or ns.Ledger.getDayKey():sub(1, 7)
end

local function shiftMonth(monthKey, delta)
    local year, month = monthKey:match("^(%d+)-(%d+)$")
    year, month = tonumber(year), tonumber(month) + delta
    while month < 1 do month, year = month + 12, year - 1 end
    while month > 12 do month, year = month - 12, year + 1 end
    return string.format("%04d-%02d", year, month)
end

local turnMonth = function(delta)
    ChroniclePage.calendarMonth = shiftMonth(ChroniclePage.calendarMonth or getMonthKey(ChroniclePage.selectedDayKey), delta)
    ns.Log.refresh()
end

---The month the chosen day is in, as a calendar on the Days page: each day played shaded by the quests done that
---day (the count in its corner), the chosen day ringed in gold. A click opens a day; the arrows turn the month.
---@return number y Below the calendar
function ChroniclePage.addCalendar(page, y, selectedKey)
    local padding = ChroniclePage.PADDING
    local monthKey = ChroniclePage.calendarMonth or getMonthKey(selectedKey)
    local days = ns.Ledger.getDays()
    local firstStamp = ns.Ledger.getDayStamp(monthKey .. "-01")
    y = ChroniclePage.addHeading(page, y, ns.Chronicle.formatShownDate("%B %Y", firstStamp))
    -- The arrows to the months before and after, at the heading's right
    local arrowTop = y - 30
    page:addText("<", page.width - padding - 44, arrowTop, { font = "GameFontNormal", color = COLORS.brown, width = 16, justify = "CENTER", isSingleLine = true })
    page:addButton(page.width - padding - 48, arrowTop - 4, 24, 22, turnMonth, -1)
    page:addText(">", page.width - padding - 18, arrowTop, { font = "GameFontNormal", color = COLORS.brown, width = 16, justify = "CENTER", isSingleLine = true })
    page:addButton(page.width - padding - 22, arrowTop - 4, 24, 22, turnMonth, 1)

    local gap = 4
    local cellWidth = math.floor((page.width - 2 * padding - 6 * gap) / 7)
    local cellHeight = math.floor(cellWidth * 0.7)
    -- The days of the week, Monday first, in the player's language (from a week known to start on a Monday)
    for weekday = 0, 6 do
        local name = ns.Chronicle.formatShownDate("%a", ns.Ledger.getDayStamp(string.format("2024-01-%02d", 1 + weekday)))
        page:addText(name, padding + weekday * (cellWidth + gap), y, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = cellWidth, justify = "CENTER", isSingleLine = true })
    end
    y = y + 16
    -- The busiest day of the month sets the shades
    local most = 1
    for dayNumber = 1, 31 do
        local day = days[string.format("%s-%02d", monthKey, dayNumber)]
        most = math.max(most, day and day.quests or 0)
    end
    local firstWeekday = (tonumber(ns.Chronicle.formatDate("%w", firstStamp)) + 6) % 7 -- Monday 0
    local todayKey = ns.Ledger.getDayKey()
    local rows = 0
    for dayNumber = 1, 31 do
        local key = string.format("%s-%02d", monthKey, dayNumber)
        if ns.Chronicle.formatDate("%Y-%m-%d", ns.Ledger.getDayStamp(key)) ~= key then
            break -- past the month's last day
        end
        local index = firstWeekday + dayNumber - 1
        local row, column = math.floor(index / 7), index % 7
        rows = math.max(rows, row + 1)
        local x, top = padding + column * (cellWidth + gap), y + row * (cellHeight + gap)
        local day = days[key]
        local quests = day and day.quests or 0
        if key == selectedKey then
            page:addRect(x - 2, top - 2, cellWidth + 4, cellHeight + 4, CALENDAR_GOLD, 0)
        end
        page:addRect(x, top, cellWidth, cellHeight, { 0.42, 0.29, 0.14 }, 1)
        local fill = CALENDAR_EMPTY
        if day and quests > 0 then
            fill = CALENDAR_SHADES[math.min(4, 1 + math.floor(3 * quests / most))]
        end
        page:addRect(x + 1, top + 1, cellWidth - 2, cellHeight - 2, { fill[1], fill[2], fill[3], day and 1 or (key > todayKey and 0.25 or 0.5) }, 2)
        local isDark = day and quests > 0 and fill ~= CALENDAR_SHADES[1]
        page:addText(tostring(dayNumber), x + 3, top + 2, { font = "GameFontHighlightSmall", color = isDark and { 0.95, 0.88, 0.7 } or COLORS.softInk, isSingleLine = true })
        if quests > 0 then
            page:addText(tostring(quests), x, top + cellHeight - 16, {
                font = "GameFontNormal", color = isDark and COLORS.white or COLORS.ink, width = cellWidth - 4, justify = "RIGHT", isSingleLine = true,
            })
        end
        if day then
            page:addButton(x, top, cellWidth, cellHeight, ChroniclePage.selectDay, key)
        end
    end
    y = y + rows * (cellHeight + gap) + 4
    -- Fewer to more, and the streak of days in a row
    page:addText(ns.L("Fewer"), padding, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, isSingleLine = true })
    for index, shade in ipairs(CALENDAR_SHADES) do
        page:addRect(padding + 36 + (index - 1) * 16, y, 12, 12, shade, 1)
    end
    page:addText(ns.L("More quests"), padding + 36 + #CALENDAR_SHADES * 16 + 4, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, isSingleLine = true })
    local streak = ns.Ledger.composeOverview().streak or 0
    if streak > 1 then
        page:addText(ns.L("%d days in a row", streak), padding, y, {
            font = "GameFontHighlightSmall", color = { 0.18, 0.42, 0.18 }, width = page.width - 2 * padding, justify = "RIGHT", isSingleLine = true,
        })
    end
    return y + 26
end

---------------------------------------------------------------------------------------------------------------
-- Records as plaques

local PLAQUE_HEIGHT = 48
local PLAQUE_RIM, PLAQUE_EDGE, PLAQUE_LOW, PLAQUE_HIGH = { 0.69, 0.54, 0.23 }, { 0.1, 0.06, 0.02 }, { 0.15, 0.1, 0.05 }, { 0.23, 0.16, 0.09 }

---@param records { icon: string, label: string, value: string, when: string? }[]
---@return number y Below the plaques
function ChroniclePage.addTrophies(page, y, records)
    local padding = ChroniclePage.PADDING
    local gap = 8
    local width = math.floor((page.width - 2 * padding - gap) / 2)
    for index, record in ipairs(records) do
        local column = (index - 1) % 2
        local top = y + math.floor((index - 1) / 2) * (PLAQUE_HEIGHT + gap)
        local x = padding + column * (width + gap)
        -- A gold-rimmed dark plaque, lit from above
        page:addRect(x, top, width, PLAQUE_HEIGHT, PLAQUE_EDGE, 0)
        page:addRect(x + 1, top + 1, width - 2, PLAQUE_HEIGHT - 2, PLAQUE_RIM, 1)
        page:addRect(x + 3, top + 3, width - 6, PLAQUE_HEIGHT - 6, PLAQUE_LOW, 2)
        page:addRect(x + 3, top + 3, width - 6, (PLAQUE_HEIGHT - 6) / 2, PLAQUE_HIGH, 3)
        page:addFramedIcon(x + 9, top + 9, 30, record.icon, 1)
        local textLeft, textWidth = x + 46, width - 52
        page:addText(record.label, textLeft, top + 6, { font = "GameFontHighlightSmall", color = COLORS.tan, width = textWidth, isSingleLine = true })
        page:addText(record.value, textLeft, top + 19, { font = "GameFontNormal", color = COLORS.gold, width = textWidth, isSingleLine = true })
        if record.when then
            page:addText(record.when, textLeft, top + 33, { font = "GameFontHighlightSmall", color = { 0.66, 0.6, 0.49 }, width = textWidth, isSingleLine = true })
        end
    end
    return y + math.ceil(#records / 2) * (PLAQUE_HEIGHT + gap) + 4
end

---------------------------------------------------------------------------------------------------------------
-- Zones as cards on their map art

local CARD_HEIGHT = 72

---@return number|string? texture A middle tile of the zone's map art, or nil when the game has none for it
local function getZoneArt(zoneId)
    local uiMapId = ns.Database.getUiMapId(zoneId)
    if not uiMapId or not C_Map or not C_Map.GetMapArtLayerTextures then
        return nil
    end
    local isRead, textures = pcall(C_Map.GetMapArtLayerTextures, uiMapId, 1)
    if not isRead or type(textures) ~= "table" or #textures == 0 then
        return nil
    end
    -- The art is cut in tiles, four across and three down for a zone: one from the middle shows its land
    return textures[math.min(#textures, math.max(1, math.ceil(#textures / 2)))]
end

---@return number y Below the cards
function ChroniclePage.addZoneCards(page, y, zones)
    local padding = ChroniclePage.PADDING
    local gap = 8
    local width = math.floor((page.width - 2 * padding - gap) / 2)
    for index, zone in ipairs(zones) do
        local column = (index - 1) % 2
        local top = y + math.floor((index - 1) / 2) * (CARD_HEIGHT + gap)
        local x = padding + column * (width + gap)
        local share = zone.doneCount / math.max(zone.totalCount, 1)
        page:addRect(x - 1, top - 1, width + 2, CARD_HEIGHT + 2, PLAQUE_EDGE, 0)
        local art = getZoneArt(zone.zoneId)
        if art then
            -- The tile is square; the card shows a band across its middle
            local band = (CARD_HEIGHT / width) / 2
            page:addImage(x, top, width, CARD_HEIGHT, art, { 0, 1, 0.5 - band, 0.5 + band }):SetDrawLayer("BORDER", 2)
        else
            page:addRect(x, top, width, CARD_HEIGHT, { 0.2, 0.14, 0.08 }, 2)
        end
        -- Dark at the bottom, where the name is
        local shadow = page:addImage(x, top + CARD_HEIGHT * 0.4, width, CARD_HEIGHT * 0.6, WHITE, nil, { 0, 0, 0 })
        shadow:SetDrawLayer("BORDER", 3)
        shadow:SetAlpha(0.6)
        -- How far it is done: a bar along the bottom, and the share in a badge at the top right
        local color = ChroniclePage.getProgressColor(share)
        page:addRect(x, top + CARD_HEIGHT - 3, width, 3, { 0.08, 0.05, 0.02 }, 4)
        page:addRect(x, top + CARD_HEIGHT - 3, width * share, 3, color, 5)
        page:addDot(x + width - 33, top + 5, 28, color, 1)
        page:addDot(x + width - 30, top + 8, 22, { 0.08, 0.05, 0.02, 0.85 }, 2)
        page:addText(math.floor(share * 100) .. "%", x + width - 33, top + 13, { font = "GameFontHighlightSmall", color = COLORS.white, width = 28, justify = "CENTER", isSingleLine = true })
        page:addText(zone.name, x + 8, top + CARD_HEIGHT - 36, { font = "GameFontNormal", color = COLORS.white, width = width - 16, isSingleLine = true })
        local levels = zone.minLevel and (zone.minLevel == zone.maxLevel and tostring(zone.minLevel) or (zone.minLevel .. "-" .. zone.maxLevel))
        page:addText(ns.L("%d of %d", zone.doneCount, zone.totalCount) .. (levels and (DOT .. ns.L("levels %s", levels)) or ""), x + 8, top + CARD_HEIGHT - 19, {
            font = "GameFontHighlightSmall", color = { 0.92, 0.85, 0.69 }, width = width - 16, isSingleLine = true,
        })
        page:addButton(x, top, width, CARD_HEIGHT, ChroniclePage.selectZone, zone.zoneId, function(button)
            ChroniclePage.showZoneNote(button, zone)
        end)
    end
    return y + math.ceil(#zones / 2) * (CARD_HEIGHT + gap) + 4
end

---------------------------------------------------------------------------------------------------------------
-- A journal entry as a quest card

local BANNER_HEIGHT = 58

---The top of a journal entry: the zone's map art as a banner with the quest's title and a line about it (level,
---place, step), then what the quest asked in its own words, set off as a quote.
---@return number y Below it
function ChroniclePage.addQuestCard(page, y, entry, title, when)
    local padding = ChroniclePage.PADDING
    local width = page.width - 2 * padding
    -- The banner: the zone's land, darkened towards the left where the words are
    page:addRect(padding - 1, y - 1, width + 2, BANNER_HEIGHT + 2, PLAQUE_EDGE, 0)
    local art = getZoneArt(entry.zoneId)
    if art then
        local band = (BANNER_HEIGHT / width) / 2
        page:addImage(padding, y, width, BANNER_HEIGHT, art, { 0, 1, 0.5 - band, 0.5 + band }):SetDrawLayer("BORDER", 2)
    else
        page:addRect(padding, y, width, BANNER_HEIGHT, { 0.2, 0.14, 0.08 }, 2)
    end
    -- One smooth fade, dark where the words are, the land showing through towards the right
    -- (thin slices, each a little lighter: the same in every client, where a texture's gradient is not)
    local slices = 24
    local sliceWidth = width / slices
    for index = 1, slices do
        local shade = page:addImage(padding + (index - 1) * sliceWidth, y, sliceWidth, BANNER_HEIGHT, WHITE, nil, { 0.04, 0.02, 0 })
        shade:SetDrawLayer("BORDER", 3)
        shade:SetAlpha(0.85 - 0.75 * (index - 1) / (slices - 1))
    end
    -- A gold rim along the top and the bottom, the quest log's filigree on the lower one
    page:addRect(padding, y, width, 2, PLAQUE_RIM, 4)
    page:addRect(padding, y + BANNER_HEIGHT - 2, width, 2, PLAQUE_RIM, 4)
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("questlog-frame-filigree") then
        page:addImage(padding + width / 2 - 24, y + BANNER_HEIGHT - 10, 48, 19, { atlas = "questlog-frame-filigree" }, nil, nil, 5)
    end
    -- The quest's name, and under it its level, place and step (the page's header says the day and time)
    page:addText(title, padding + 12, y + 10, { font = "GameFontNormalLarge", color = COLORS.gold, width = width - 24, isSingleLine = true })
    page:addText(when, padding + 12, y + 33, { font = "GameFontHighlightSmall", color = { 0.92, 0.85, 0.69 }, width = width - 24, isSingleLine = true })
    y = y + BANNER_HEIGHT + 12
    -- What the quest asked, in its own words (the player's language when a translation addon has them)
    local english = ns.Database.getQuestField(entry.questId, "objectivesText")
    english = type(english) == "table" and table.concat(english, " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or nil
    local words = english and english ~= "" and ns.QuestText.getObjectives(entry.questId, english) or nil
    if words then
        local textHeight = page:addText(words, padding + 12, y + 6, { font = "QuestFontNormalSmall", color = COLORS.ink, width = width - 20 })
        local height = (tonumber(textHeight) or 14) + 12
        page:addRect(padding, y, 3, height, { 0.63, 0.48, 0.25 }, 1)
        page:addRect(padding + 3, y, width - 3, height, { 1, 0.94, 0.78, 0.4 }, 0)
        y = y + height + 10
    end
    return y
end

---------------------------------------------------------------------------------------------------------------
-- A journal entry's chain, its kind and its share of the level

local CREATURES, ITEMS = 1, 3 -- the database's objectives: creatures to kill, items to collect
local STONE_SIZE, STONE_GAP_MIN = 20, 6
local STONE_DONE, STONE_THIS, STONE_LATER = { 0.24, 0.5, 0.22 }, { 0.95, 0.72, 0.16 }, { 0.76, 0.63, 0.42 }
local STONE_EDGE, STONE_LINE = { 0.17, 0.09, 0.02 }, { 0.6, 0.45, 0.22 }
local MAX_STONES = 12 -- longer chains are told in words only
local LEVEL_PURPLE = { 0.58, 0.4, 0.92 }

---@return string kind What the quest asked, as the map's icons show it: "loot" when its drops were counted or it
---asks for items, "kill" when it asks for creatures, "talk" when it asks for nothing (go and speak), "use" else
function ChroniclePage.getEntryKind(entry)
    if entry.drops and #entry.drops > 0 then
        return "loot"
    end
    local objectives = ns.Database.getQuestField(entry.questId, "objectives") or {}
    if next(objectives[ITEMS] or {}) then
        return "loot"
    elseif next(objectives[CREATURES] or {}) then
        return "kill"
    elseif next(objectives) == nil then
        return "talk"
    end
    return "use"
end

---@return number seconds Played on the chain's steps handed in up to and with this entry, as the journal kept them
local function getChainSeconds(entry, questIds)
    local isInChain = {}
    for _, questId in ipairs(questIds) do
        isInChain[questId] = true
    end
    for _, instantQuestId in ipairs(ns.Availability.getInstantSteps(entry.questId) or {}) do
        isInChain[instantQuestId] = true
    end
    local seconds = 0
    for _, other in ipairs(ns.Chronicle.getEntries()) do
        if isInChain[other.questId] and other.turnedInAt and entry.turnedInAt and other.turnedInAt <= entry.turnedInAt then
            seconds = seconds + (other.duration or 0)
        end
    end
    return seconds
end

---The chain the quest is a step of: its steps as numbered stones (done ones green, this one gold, the rest pale),
---the next step by name and the time the chain has taken so far. Nothing for a quest outside a chain.
---@return number y Below it
function ChroniclePage.addChain(page, y, entry)
    local step, total = ns.Chain.getStep(entry.questId)
    if not step then
        return y
    end
    local padding = ChroniclePage.PADDING
    local questIds = ns.Chain.getQuestIds(entry.questId)
    local firstName = ns.Database.getQuestField(questIds[1], "name")
    y = ChroniclePage.addHeading(page, y, ns.L("The chain"), ns.L("step %d of %d", step, total))
    local width = page.width - 2 * padding
    if total <= MAX_STONES then
        local spacing = math.max(STONE_SIZE + STONE_GAP_MIN, math.min((width - STONE_SIZE) / math.max(total - 1, 1), 46))
        local left = padding + 2
        if total > 1 then
            page:addRect(left + STONE_SIZE / 2, y + STONE_SIZE / 2 - 1, spacing * (total - 1), 2, STONE_LINE, 1)
        end
        for index = 1, total do
            local x = left + (index - 1) * spacing
            local color = index < step and STONE_DONE or index == step and STONE_THIS or STONE_LATER
            page:addDot(x - 1, y - 1, STONE_SIZE + 2, STONE_EDGE, 2)
            page:addDot(x, y, STONE_SIZE, color, 3)
            page:addText(tostring(index), x, y + 4, {
                font = "GameFontHighlightSmall", color = index > step and STONE_EDGE or COLORS.white, width = STONE_SIZE, justify = "CENTER", isSingleLine = true,
            })
        end
        y = y + STONE_SIZE + 6
    end
    local parts = {}
    local nextQuestId = questIds[step + 1]
    if nextQuestId then
        local nextName = ns.Database.getQuestField(nextQuestId, "name") or "?"
        parts[#parts + 1] = ns.L("Next: %s (step %d)", nextName, step + 1)
    end
    local seconds = getChainSeconds(entry, questIds)
    if seconds > 0 then
        parts[#parts + 1] = nextQuestId and ns.L("the chain took %s so far", ChroniclePage.formatDuration(seconds))
            or ns.L("the chain took %s in all", ChroniclePage.formatDuration(seconds))
    elseif not nextQuestId then
        parts[#parts + 1] = ns.L("the last step")
    end
    if firstName and step > 1 then
        parts[#parts + 1] = ns.L("began with %s", firstName)
    end
    local height = page:addText(table.concat(parts, DOT), padding, y, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width })
    return y + (tonumber(height) or 12) + 12
end

---How much of the level the quest's experience filled: a purple bar, as the game's experience bar, and its share.
---Nothing when the quest gave none, or for entries kept before the level's size was written down with them.
---@return number y Below it
function ChroniclePage.addLevelShare(page, y, entry)
    local experience, levelXp = entry.experience or 0, entry.levelXp
    if experience <= 0 or not levelXp or levelXp <= 0 then
        return y
    end
    local padding = ChroniclePage.PADDING
    local width = page.width - 2 * padding
    local share = math.min(experience / levelXp, 1)
    y = ChroniclePage.addHeading(page, y, ns.L("Level progress")) -- the experience itself is on its tile above
    page:addStatBar(padding, y - 2, width, 14, { { share = share, color = LEVEL_PURPLE } })
    local level = entry.playerLevel
    local text = level and ns.L("%d%% of level %d", math.floor(share * 100 + 0.5), level) or ns.L("%d%% of a level", math.floor(share * 100 + 0.5))
    page:addText(text, padding, y + 15, { font = "GameFontHighlightSmall", color = COLORS.softInk, width = width, isSingleLine = true })
    return y + 34
end