local _, ns = ...

-- Holidays and world events, and whether each runs now: their quests are offered only then. The game's calendar says
-- so where the realm fills it in (its holidays this month); where it does not, the days each event runs on Classic Era
-- realms, as Questie keeps them, with the Lunar Festival's by year, Noblegarden on Easter Sunday and the Darkmoon Faire
-- in its first full week of each month. Which quest is whose: EventQuests.lua. Worked out at login, when the calendar
-- answers, and again each minute (a cheap date comparison); a change redraws the lists and maps once.
local Events = {}
ns.Events = Events

-- { start month, day, hour, minute, end month, day, hour, minute } in realm time; nil: not held on Classic Era realms
local DATES = {
    winterVeil = { 12, 15, 10, 0, 1, 2, 10, 0 },
    loveIsInTheAir = { 2, 11, 10, 0, 2, 15, 10, 0 },
    childrensWeek = { 4, 27, 10, 0, 5, 4, 10, 0 },
    midsummer = { 6, 21, 4, 0, 7, 5, 4, 0 },
    harvestFestival = { 9, 21, 0, 1, 9, 27, 23, 59 },
    hallowsEnd = { 10, 18, 4, 0, 11, 1, 23, 59 },
}
-- The Lunar Festival follows the moon: its days by year
local LUNAR_FESTIVAL = {
    [2019] = { 2, 5, 6, 0, 2, 19, 6, 0 }, [2020] = { 1, 23, 6, 0, 2, 10, 6, 0 }, [2021] = { 2, 5, 6, 0, 2, 19, 6, 0 },
    [2022] = { 1, 30, 6, 0, 2, 18, 6, 0 }, [2023] = { 1, 20, 6, 0, 2, 10, 6, 0 }, [2024] = { 2, 3, 6, 0, 2, 23, 6, 0 },
    [2025] = { 1, 28, 6, 0, 2, 17, 6, 0 }, [2026] = { 2, 16, 6, 0, 3, 9, 6, 0 }, [2027] = { 2, 5, 6, 0, 2, 19, 6, 0 },
    [2028] = { 1, 24, 6, 0, 2, 14, 6, 0 },
}
-- The Darkmoon Faire opens on the Monday after the first full weekend of the month (by the weekday of the 1st,
-- Sunday 1), at 4:00, for a week; in Elwynn Forest in odd months, in Mulgore in even ones
local FAIRE_START_DAY = { 9, 8, 7, 6, 5, 4, 10 }
local FAIRE_ZONES = { [true] = 12, [false] = 215 } -- odd month: Elwynn Forest; even: Mulgore

-- The calendar's holiday titles (the game's, in English) to the events' keys
local CALENDAR_TITLES = {
    { "winter veil", "winterVeil" }, { "love is in the air", "loveIsInTheAir" }, { "noblegarden", "noblegarden" },
    { "children", "childrensWeek" }, { "midsummer", "midsummer" }, { "harvest festival", "harvestFestival" },
    { "hallow", "hallowsEnd" }, { "lunar festival", "lunarFestival" }, { "brewfest", "brewfest" },
    { "day of the dead", "dayOfTheDead" }, { "pilgrim", "pilgrimsBounty" }, { "darkmoon", "darkmoonFaire" },
}

-- Quest categories of seasonal and world events (the database's zoneOrSort): a quest filed under one is an event's
-- even when the list does not name it, and offered never, as no one can tell when it runs
local EVENT_CATEGORIES = {
    [-21] = true, [-22] = true, [-41] = true, [-284] = true, [-364] = true, [-365] = true, [-366] = true,
    [-368] = true, [-369] = true, [-370] = true, [-374] = true, [-375] = true, [-376] = true, [-378] = true,
    [-404] = true, [-1001] = true, [-1002] = true, [-1003] = true, [-1005] = true, [-1006] = true,
}

local active = {} -- [event key] = true while it runs
local calendarActive -- [event key] = true, from the calendar, when it has holidays this month; nil: the dates decide
local version = 0 -- raised whenever what runs changes (Events.getChangeKey)
local checkedAt -- when last worked out (GetTime)
local CHECK_SECONDS = 60

---@return table now { year, month, monthDay, hour, minute } in realm time
local function getNow()
    local now = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if type(now) == "table" and now.year then
        return now
    end
    local today = date("*t")
    return { year = today.year, month = today.month, monthDay = today.day, hour = today.hour, minute = today.min }
end

---@return boolean isWithin Now lies in the days (a span over the new year wraps round)
local function isWithin(now, days)
    local current = now.month * 1000000 + now.monthDay * 10000 + now.hour * 100 + now.minute
    local start = days[1] * 1000000 + days[2] * 10000 + days[3] * 100 + days[4]
    local finish = days[5] * 1000000 + days[6] * 10000 + days[7] * 100 + days[8]
    if start <= finish then
        return current >= start and current <= finish
    end
    return current >= start or current <= finish
end

---@return number month, number day Easter Sunday of a year (the Gregorian reckoning)
function Events.getEaster(year)
    local a, b, c = year % 19, math.floor(year / 100), year % 100
    local d, e = math.floor(b / 4), b % 4
    local f = math.floor((b + 8) / 25)
    local g = math.floor((b - f + 1) / 3)
    local h = (19 * a + b - d - g + 15) % 30
    local i, k = math.floor(c / 4), c % 4
    local l = (32 + 2 * e + 2 * i - h - k) % 7
    local m = math.floor((a + 11 * h + 22 * l) / 451)
    local month = math.floor((h + l - 7 * m + 114) / 31)
    local day = (h + l - 7 * m + 114) % 31 + 1
    return month, day
end

---@return number? day The Darkmoon Faire's first day this month, by the weekday of the 1st
function Events.getFaireStartDay(year, month)
    local first = date("*t", time({ year = year, month = month, day = 1, hour = 12 }))
    return first and FAIRE_START_DAY[first.wday]
end

---@return boolean isOpen The Darkmoon Faire is open: Monday 4:00 to the next Monday 4:00
local function isFaireOpen(now)
    local startDay = Events.getFaireStartDay(now.year, now.month)
    if not startDay then
        return false
    end
    local clock = now.hour * 100 + now.minute
    if now.monthDay == startDay then
        return clock >= 400
    elseif now.monthDay == startDay + 7 then
        return clock < 400
    end
    return now.monthDay > startDay and now.monthDay < startDay + 7
end

---@return number? zoneId Where the Darkmoon Faire stands this month (Elwynn Forest or Mulgore), nil while it is shut
function Events.getFaireZone()
    if not active.darkmoonFaire then
        return nil
    end
    return FAIRE_ZONES[getNow().month % 2 == 1]
end

---@return table running [event key] = true for each event running at `now`, by the dates
function Events.composeByDates(now)
    local running = {}
    for key, days in pairs(DATES) do
        running[key] = isWithin(now, days) or nil
    end
    local lunar = LUNAR_FESTIVAL[now.year]
    running.lunarFestival = lunar and isWithin(now, lunar) or nil
    local easterMonth, easterDay = Events.getEaster(now.year)
    running.noblegarden = (now.month == easterMonth and now.monthDay == easterDay) or nil
    running.darkmoonFaire = isFaireOpen(now) or nil
    return running
end

---Reads the calendar's holidays this month, when it has any: those running today decide (the Darkmoon Faire, which the
---calendar shows only when the player asks it to, still by its own week).
local function readCalendar()
    local calendar = C_Calendar
    if not (calendar and calendar.GetMonthInfo and calendar.GetNumDayEvents and calendar.GetDayEvent) then
        return
    end
    local now = getNow()
    local info = calendar.GetMonthInfo(0)
    if type(info) ~= "table" or info.month ~= now.month or info.year ~= now.year then
        return -- (the calendar shows another month: left alone, the dates decide)
    end
    local found, hasAny = {}, false
    for day = 1, info.numDays or 0 do
        for index = 1, calendar.GetNumDayEvents(0, day) or 0 do
            local event = calendar.GetDayEvent(0, day, index)
            if type(event) == "table" and event.calendarType == "HOLIDAY" and type(event.title) == "string" then
                local title = event.title:lower()
                for _, pair in ipairs(CALENDAR_TITLES) do
                    if title:find(pair[1], 1, true) and pair[2] ~= "darkmoonFaire" then
                        hasAny = true
                        if day == now.monthDay then
                            found[pair[2]] = true
                        end
                    end
                end
            end
        end
    end
    calendarActive = hasAny and found or nil
end

---Works out what runs now; a change forgets who can pick up what and redraws once.
function Events.update()
    checkedAt = GetTime and GetTime() or 0
    local now = getNow()
    local running = Events.composeByDates(now)
    if calendarActive then
        local faire = running.darkmoonFaire
        running = {}
        for key in pairs(calendarActive) do
            running[key] = true
        end
        running.darkmoonFaire = faire
    end
    local isChanged = false
    for key in pairs(running) do
        isChanged = isChanged or not active[key]
    end
    for key in pairs(active) do
        isChanged = isChanged or not running[key]
    end
    if not isChanged then
        return
    end
    active = running
    version = version + 1
    if ns.Availability and ns.Availability.invalidate then
        ns.Availability.invalidate()
    end
    if ns.queueRefresh then
        ns.queueRefresh()
    end
end

---@return boolean isRunning The event runs now
function Events.isActive(key)
    return active[key] == true
end

---@return string? key The event a quest belongs to, when the list names it
function Events.getEventKey(questId)
    return ns.EventQuests.quests[questId]
end

---@return boolean isEvent A holiday's or a world event's quest: named in the list, or filed under an event's category
function Events.isEventQuest(questId)
    if ns.EventQuests.quests[questId] then
        return true
    end
    return EVENT_CATEGORIES[ns.Database.getQuestField(questId, "zoneOrSort") or 0] == true
end

---@return boolean isOffered The quest's event runs now, and its own days, when it has them, too; an event quest the list
---does not name never is (no one can tell when it runs)
function Events.isQuestOffered(questId)
    local key = ns.EventQuests.quests[questId]
    if not key or not active[key] then
        return false
    end
    local days = ns.EventQuests.windows[questId]
    return not days or isWithin(getNow(), days)
end

---@return number key Changes whenever an event starts or ends (what the lists and maps of quests to pick up follow)
function Events.getChangeKey()
    return version
end

---The calendar's answer, once asked at login.
local function handleCalendarUpdate()
    readCalendar()
    Events.update()
end

ns.registerModule({
    name = "Events",
    create = function()
        if C_Calendar and C_Calendar.OpenCalendar then
            pcall(C_Calendar.OpenCalendar) -- asks the realm for this month's holidays: CALENDAR_UPDATE_EVENT_LIST
        end
        Events.update()
    end,
    -- Once a minute: an event that starts or ends while playing
    tick = function()
        if not checkedAt or (GetTime and GetTime() or 0) - checkedAt >= CHECK_SECONDS then
            Events.update()
        end
    end,
    events = { CALENDAR_UPDATE_EVENT_LIST = handleCalendarUpdate },
})
