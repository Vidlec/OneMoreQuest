local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The chronicle: every quest the character hands in from the day it began, with when it was taken and handed in,
-- the level and the place, what it gave, the kills its drops took by creature, and deaths and company on the
-- way. Quests done before it began are known only from the game's own record of completed quests: named and
-- placed from the quest database, without dates or kills. Kept per character.
--
-- Times are of two kinds: when, on the calendar ("today 14:02"), and how long, in time logged in, so a quest
-- left in the log overnight does not count the night.
local Chronicle = {}
ns.Chronicle = Chronicle

local eventFrame
local sessionStart -- GetTime() when the played time was last added up
local pendingRewardLink -- the reward picked in the hand-in dialog (its link), until the hand-in is confirmed
local earlierCache -- quests done before the chronicle began, worked out once per session

local function getNow()
    if time then
        return time()
    end
    return os and os.time and os.time() or 0
end

Chronicle.getNow = getNow

local function formatDate(format, stamp)
    local formatter = date or (os and os.date)
    return formatter and formatter(format, stamp) or ""
end

-- An entry keeps only what the quest database cannot give back, so a long chronicle stays small in the saved
-- file: the title, the quest's level and its zone only when they differ from the database's, nothing for a value
-- that is its usual (no deaths, alone, nothing gained), the reward as its item number. Reading an entry fills the
-- rest in; what is filled in is never written to the file.
local ENTRY_DEFAULTS = { deaths = 0, experience = 0, money = 0, wasGrouped = false }
local NO_DROPS = setmetatable({}, {
    __newindex = function()
        error("an entry's drops are read only")
    end,
})
local startZoneIds = setmetatable({}, { __mode = "k" }) -- [entry] = its quest's start zone, worked out once a session

local entryMetatable = {
    __index = function(entry, key)
        local questId = rawget(entry, "questId")
        if key == "title" then
            return ns.Database.getQuestField(questId, "name") or ("Quest " .. tostring(questId))
        elseif key == "questLevel" then
            return ns.Database.getQuestField(questId, "questLevel")
        elseif key == "zoneId" then
            if startZoneIds[entry] == nil then
                startZoneIds[entry] = ns.Availability.getStartZoneId(questId) or false
            end
            return startZoneIds[entry] or nil
        elseif key == "acceptedLevel" then
            return rawget(entry, "playerLevel")
        elseif key == "drops" then
            return NO_DROPS
        elseif key == "rewardLink" then
            local itemId = rawget(entry, "rewardItemId")
            local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo -- luacheck: ignore 113 (an older client's fallback)
            local link = itemId and getItemInfo and select(2, getItemInfo(itemId))
            if itemId and not link then
                ns.Prices.requestItem(itemId) -- the link comes once the game has the item
            end
            return link
        end
        return ENTRY_DEFAULTS[key]
    end,
}

---Leaves out of an entry what reading it gives back (entryMetatable), and makes it read so.
local function compactEntry(entry)
    local questId = rawget(entry, "questId")
    local link = rawget(entry, "rewardLink")
    if type(link) == "string" then
        entry.rewardItemId, entry.rewardLink = tonumber(link:match("item:(%d+)")), nil
    end
    if rawget(entry, "title") == ns.Database.getQuestField(questId, "name") then
        entry.title = nil
    end
    if rawget(entry, "questLevel") == ns.Database.getQuestField(questId, "questLevel") then
        entry.questLevel = nil
    end
    if rawget(entry, "zoneId") ~= nil and rawget(entry, "zoneId") == ns.Availability.getStartZoneId(questId) then
        entry.zoneId = nil
    end
    if rawget(entry, "acceptedLevel") == rawget(entry, "playerLevel") then
        entry.acceptedLevel = nil
    end
    local duration = rawget(entry, "duration")
    if duration then
        entry.duration = math.floor(duration + 0.5) -- whole seconds: a long decimal in the file says no more
    end
    for key, default in pairs(ENTRY_DEFAULTS) do
        if rawget(entry, key) == default then
            entry[key] = nil
        end
    end
    local drops = rawget(entry, "drops")
    if drops and #drops == 0 then
        entry.drops = nil
    end
    for _, drop in ipairs(drops or {}) do
        if drop.expected then
            drop.expected = math.floor(drop.expected * 10 + 0.5) / 10
        end
    end
    return setmetatable(entry, entryMetatable)
end
Chronicle.compactEntry = compactEntry

local isBookCompacted = false

---@return table book The character's chronicle: entries (handed in, oldest first), open (quests in the log, what is
---known of them so far), played seconds, when it began, how many quests were abandoned
local function getBook()
    local book = ns.getCharacterRecords("chronicle")
    book.entries = book.entries or {}
    if not isBookCompacted then
        -- Once a session: entries read as a whole again, and older ones written in full are made small
        isBookCompacted = true
        for _, entry in ipairs(book.entries) do
            compactEntry(entry)
        end
    end
    book.open = book.open or {}
    book.levels = nil -- kept by a chapter since removed (Journey)
    book.playedSeconds = book.playedSeconds or 0
    book.abandonedCount = book.abandonedCount or 0
    book.startedAt = book.startedAt or getNow()
    return book
end
Chronicle.getBook = getBook

---@return number seconds Time logged in since the chronicle began
local function getPlayedSeconds()
    local book = getBook()
    local now = GetTime and GetTime() or 0
    sessionStart = sessionStart or now
    return book.playedSeconds + (now - sessionStart)
end

---Adds this session's time to the book, so it survives the end of the session.
local function savePlayedSeconds()
    local book = getBook()
    book.playedSeconds = getPlayedSeconds()
    sessionStart = GetTime and GetTime() or 0
end

local function getOpen(questId)
    local book = getBook()
    book.open[questId] = book.open[questId] or { deaths = 0 }
    return book.open[questId]
end

local function isInGroup()
    return IsInGroup ~= nil and IsInGroup() == true
end

---A quest was taken: when, at what level, alone or not.
function Chronicle.handleAccept(questId)
    local open = getOpen(questId)
    open.acceptedAt, open.acceptedPlayed = getNow(), getPlayedSeconds()
    open.level = UnitLevel and UnitLevel("player") or nil
    open.wasGrouped = isInGroup() or nil
end

---@return string? preset The spoilers in force at a hand-in ("hints", "explorer", "purist", "custom"); nil in Guide,
---with nothing held back
---@return boolean? isHinted A hint was taken for the quest (Spoilers forgets that once the quest is gone: the
---chronicle keeps it, for the journal's "found it yourself")
local function getSpoilersAtHandIn(questId)
    local Spoilers = ns.Spoilers
    if not (Spoilers and Spoilers.isActive()) then
        return nil, nil
    end
    return Spoilers.getPreset(), Spoilers.wasHinted(questId) or nil
end

---@return boolean isFound The quest was done with spoilers held back and no hint taken (a field read: the journal
---asks it of every row)
function Chronicle.isFoundYourself(entry)
    return entry.spoilers ~= nil and not entry.hinted
end

---A quest was handed in: it becomes an entry of the chronicle.
---@param experience number? What the game says it gave
---@param money number? Copper
function Chronicle.handleTurnIn(questId, experience, money)
    local book = getBook()
    local open = book.open[questId] or { deaths = 0 }
    local now, played = getNow(), getPlayedSeconds()
    local title = ns.Database.getQuestField(questId, "name")
        or (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId))
        or ("Quest " .. questId)
    local spoilers, isHinted = getSpoilersAtHandIn(questId)
    book.entries[#book.entries + 1] = compactEntry({
        questId = questId,
        title = title,
        questLevel = ns.Database.getQuestField(questId, "questLevel"),
        playerLevel = UnitLevel and UnitLevel("player") or nil,
        acceptedLevel = open.level,
        zoneId = ns.Availability.getStartZoneId(questId) or ns.Model.getPlayer().zoneId,
        acceptedAt = open.acceptedAt,
        turnedInAt = now,
        duration = open.acceptedPlayed and math.max(played - open.acceptedPlayed, 0) or nil,
        experience = experience or 0,
        money = money or 0,
        rewardLink = pendingRewardLink,
        -- What the level needed, so the journal can say how much of it the quest filled
        levelXp = UnitXPMax and UnitXPMax("player") or nil,
        deaths = open.deaths or 0,
        wasGrouped = open.wasGrouped or isInGroup(),
        drops = ns.KillCounter.composeTurnIn(questId),
        spoilers = spoilers,
        hinted = isHinted, -- (both nil in Guide: nothing kept)
    })
    if ns.Ledger then
        ns.Ledger.handleTurnIn(experience, money, pendingRewardLink)
    end
    book.open[questId], pendingRewardLink, earlierCache = nil, nil, nil
    ns.History.invalidate()
    savePlayedSeconds()
end

---Makes a record from another history (an addon's) read as an entry does: its title, level and zone from the quest
---database, nothing gained or lost where it says nothing. It is not written to the chronicle.
---@return table record The same table
function Chronicle.readAsEntry(record)
    return setmetatable(record, entryMetatable)
end

-- OneMoreQuest's own chronicle, the most trusted history: its entries are the history's, others only fill in
ns.History.registerProvider({
    name = "OneMoreQuest",
    order = 10,
    getCompletions = function()
        return getBook().entries
    end,
})

---@return table[] entries Every quest handed in with a date, from every history (History): the chronicle's own, an
---addon's that kept one before it (Questie's journey), oldest first
function Chronicle.getEntries()
    return ns.History.getEntries()
end

---The character died: every quest in the log was on the way.
function Chronicle.handleDeath()
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        local open = getOpen(questId)
        open.deaths = (open.deaths or 0) + 1
    end
end

---Quests in the log done in a group count as such.
function Chronicle.handleGroupChange()
    if not isInGroup() then
        return
    end
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        getOpen(questId).wasGrouped = true
    end
end

---A quest left the log without being handed in: abandoned. Checked a moment later, as a hand-in removes it too.
function Chronicle.handleRemove(questId)
    local book = getBook()
    if not book.open[questId] or ns.QuestState.isTurnedIn(questId) then
        return
    end
    book.open[questId] = nil
    book.abandonedCount = book.abandonedCount + 1
end

---@return number[] questIds Quests the game says the character completed that no history dates (History.getUndated):
---done before the chronicle began, and before any other addon kept a history. Only those the quest database knows,
---so each has a name and a place, and only those meant for the character's race and class.
local earlierFrom -- the history's undated list earlierCache was worked out from

function Chronicle.getEarlierQuestIds()
    local undated = ns.History.getUndated()
    if earlierCache and earlierFrom == undated then
        return earlierCache
    end
    local questIds = {}
    for _, entry in ipairs(undated) do
        local questId = entry.questId
        -- Only the character's own: the game also marks the other faction's twin of a quest done (Crest of Lordaeron)
        if
            ns.Database.getQuestField(questId, "name")
            and not (ns.HiddenQuests[questId] and not ns.Events.getEventKey(questId))
            and ns.Availability.isForRaceAndClass(questId)
        then
            questIds[#questIds + 1] = questId
        end
    end
    table.sort(questIds)
    earlierCache, earlierFrom = questIds, undated
    return questIds
end

---------------------------------------------------------------------------------------------------------------
-- What the chronicle adds up to

---@return number kills, number expected Over every drop objective of an entry that had its kills counted
local function getEntryKills(entry)
    local kills, expected = 0, 0
    for _, drop in ipairs(entry.drops or {}) do
        if drop.expected then
            kills, expected = kills + drop.kills, expected + drop.expected
        end
    end
    return kills, expected
end
Chronicle.getEntryKills = getEntryKills

---@return number? luck How much luckier than average the kills went: 0.1 is a tenth fewer kills than expected,
---and -0.1 a tenth more; nil without counted kills
function Chronicle.getLuck(kills, expected)
    if not expected or expected <= 0 then
        return nil
    end
    return (expected - kills) / expected
end

---@return string day The calendar day of a time, "2026-11-16"
function Chronicle.getDay(stamp)
    return formatDate("%Y-%m-%d", stamp)
end

function Chronicle.formatDate(format, stamp)
    return formatDate(format, stamp)
end

-- Day and month names in Czech, which the game's date does not give: weekdays from Sunday, as "%w" counts them
-- (capitalised, as a date starts with them here), months in the genitive, as a date says them ("17. listopadu")
local CZECH_WEEKDAYS = { "Neděle", "Pondělí", "Úterý", "Středa", "Čtvrtek", "Pátek", "Sobota" }
local CZECH_MONTHS = {
    "ledna",
    "února",
    "března",
    "dubna",
    "května",
    "června",
    "července",
    "srpna",
    "září",
    "října",
    "listopadu",
    "prosince",
}
-- A month on its own ("%B", as the calendar's heading "Listopad 2026"), in the nominative and capitalised, as it starts
-- the heading; and the weekdays short ("%a", over the calendar's columns), from Sunday as well
local CZECH_MONTHS_ALONE = {
    "Leden",
    "Únor",
    "Březen",
    "Duben",
    "Květen",
    "Červen",
    "Červenec",
    "Srpen",
    "Září",
    "Říjen",
    "Listopad",
    "Prosinec",
}
local CZECH_SHORT_WEEKDAYS = { "Ne", "Po", "Út", "St", "Čt", "Pá", "So" }

---A date to show, in the addon's language: as Chronicle.formatDate in English; in Czech "%A %d %B" is
---"Úterý 17. listopadu", "%d %b" "17. 11.", "%B %Y" "Listopad 2026" and "%a" "Út". Not for keys: those stay as the
---game's date gives them.
---@return string text
function Chronicle.formatShownDate(format, stamp)
    if not (ns.Locale and ns.Locale.getLanguage() == "cs") then
        return formatDate(format, stamp)
    end
    local day = tonumber(formatDate("%d", stamp)) or 1
    local month = tonumber(formatDate("%m", stamp)) or 1
    local weekday = (tonumber(formatDate("%w", stamp)) or 0) + 1
    -- (a day with its month first, so a month left on its own after is the nominative one)
    format = format
        :gsub("%%d %%B", day .. ". " .. CZECH_MONTHS[month])
        :gsub("%%d %%b", day .. ". " .. month .. ".")
        :gsub("%%B", CZECH_MONTHS_ALONE[month])
        :gsub("%%A", CZECH_WEEKDAYS[weekday])
        :gsub("%%a", CZECH_SHORT_WEEKDAYS[weekday])
    return formatDate(format, stamp)
end

---@class ChronicleSummary
---@field questCount number Every quest done, the earlier ones included
---@field chronicledCount number Handed in since the chronicle began
---@field experience number From quests handed in since
---@field money number Copper, likewise
---@field playedSeconds number Time logged in since
---@field kills number Kills for drops, counted
---@field expected number What an average player would have needed for the same drops
---@field luck number?
---@field abandonedCount number
---@field days { day: string, count: number }[] The last seven days, oldest first
---@field fastest table? The entry handed in quickest after it was taken
---@field longest table?
---@field unluckiest table? With the most kills over what was expected (none when every quest took fewer)
---@field luckiest table? With the most kills saved against what was expected (none when every quest took more)
---@field mostKilled { npcId: number, kills: number }?
---@field mostKilledList { npcId: number, kills: number }[] The creatures killed most for drops, most first, at most five
---@field rarest { entry: table, drop: table, chance: number }? The drop with the smallest chance that came
---@field longestHunt { entry: table, drop: table }? The drop that took the most kills
---@field longestDry { entry: table, drop: table }? The longest run of kills before a drop came
---@field firstKillDrops number Drops that came on the first kill
---@field chainCount number Chains finished, the earlier ones included
---@field spoilerCount number Quests handed in with spoilers held back (Spoilers: not in Guide)
---@field foundCount number Of those, done with no hint taken
---@field hintedCount number Of those, done with a hint
---@field peekCount number Times Alt was held over the map to see everything for a moment
---@field hasSpoilers boolean Anything of the above: a player always in Guide has none, and sees nothing of it

local MOST_KILLED_COUNT = 5

---Adds an entry's experience, money and spoiler choice to the summary, and keeps it when it was the fastest or the
---longest.
local function addEntryTotals(summary, entry)
    summary.experience = summary.experience + (entry.experience or 0)
    summary.money = summary.money + (entry.money or 0)
    if entry.spoilers then
        summary.spoilerCount = summary.spoilerCount + 1
        if entry.hinted then
            summary.hintedCount = summary.hintedCount + 1
        else
            summary.foundCount = summary.foundCount + 1
        end
    end
    if entry.duration and entry.duration > 0 then
        if not summary.fastest or entry.duration < summary.fastest.duration then
            summary.fastest = entry
        end
        if not summary.longest or entry.duration > summary.longest.duration then
            summary.longest = entry
        end
    end
end

---Adds an entry's kills for drops, and keeps it when it was the unluckiest or the luckiest so far.
---@param gaps { unluckiest: number?, luckiest: number? } The kills over (or under) expected of those kept so far
local function addEntryLuck(summary, entry, gaps)
    local kills, expected = getEntryKills(entry)
    if expected <= 0 then
        return
    end
    summary.kills, summary.expected = summary.kills + kills, summary.expected + expected
    -- Unluckiest only among quests that took more kills than expected, luckiest among those that took fewer:
    -- one quest can never be both, so no page calls it one and another page the other
    local gap = kills - expected
    if gap > 0 and (not gaps.unluckiest or gap > gaps.unluckiest) then
        summary.unluckiest, gaps.unluckiest = entry, gap
    end
    if gap < 0 and (not gaps.luckiest or gap < gaps.luckiest) then
        summary.luckiest, gaps.luckiest = entry, gap
    end
end

---Adds an entry's drops: the kills of each creature, and the rarest drop, the longest hunt and the longest dry run.
local function addEntryDrops(summary, entry, killsByNpcId)
    for _, drop in ipairs(entry.drops or {}) do
        for npcId, npcKills in pairs(drop.killsByNpcId or {}) do
            killsByNpcId[npcId] = (killsByNpcId[npcId] or 0) + npcKills
        end
        -- The chance an average player has a kill, from what such a player needs: drops ÷ expected kills
        local chance = drop.expected and drop.expected > 0 and drop.drops > 0 and drop.drops / drop.expected
        if chance and (not summary.rarest or chance < summary.rarest.chance) then
            summary.rarest = { entry = entry, drop = drop, chance = chance }
        end
        if drop.drops > 0 and (not summary.longestHunt or drop.kills > summary.longestHunt.drop.kills) then
            summary.longestHunt = { entry = entry, drop = drop }
        end
        if drop.longestDry and (not summary.longestDry or drop.longestDry > summary.longestDry.drop.longestDry) then
            summary.longestDry = { entry = entry, drop = drop }
        end
        summary.firstKillDrops = summary.firstKillDrops + (drop.firstKillDrops or 0)
    end
end

local function isKilledMore(first, second)
    if first.kills ~= second.kills then
        return first.kills > second.kills
    end
    return first.npcId < second.npcId
end

---@return { npcId: number, kills: number }[] list The creatures killed most for drops, most first, at most five
local function composeMostKilled(killsByNpcId)
    local list = {}
    for npcId, kills in pairs(killsByNpcId) do
        list[#list + 1] = { npcId = npcId, kills = kills }
    end
    table.sort(list, isKilledMore)
    for index = #list, MOST_KILLED_COUNT + 1, -1 do
        list[index] = nil
    end
    return list
end

---@return boolean isFinished A quest is the last of its chain: done, it finishes the chain
local function isChainEnd(questId)
    local index, total = ns.Chain.getStep(questId)
    return index ~= nil and index == total
end

---@return number count The chains finished: those whose last quest is done, the earlier quests included
local function countFinishedChains(earlierQuestIds)
    local count = 0
    for _, entry in ipairs(Chronicle.getEntries()) do
        count = count + (isChainEnd(entry.questId) and 1 or 0)
    end
    for _, questId in ipairs(earlierQuestIds) do
        count = count + (isChainEnd(questId) and 1 or 0)
    end
    return count
end

---@return ChronicleSummary summary
function Chronicle.composeSummary()
    local book = getBook()
    local entries = Chronicle.getEntries() -- every history's, the chronicle's own and those it fills in from
    local earlierQuestIds = Chronicle.getEarlierQuestIds()
    local summary = {
        questCount = #entries + #earlierQuestIds,
        chronicledCount = #entries,
        experience = 0,
        money = 0,
        playedSeconds = getPlayedSeconds(),
        kills = 0,
        expected = 0,
        abandonedCount = book.abandonedCount,
        chainCount = 0,
        firstKillDrops = 0,
        mostKilledList = {},
        spoilerCount = 0,
        foundCount = 0,
        hintedCount = 0,
        peekCount = 0,
    }
    local killsByNpcId, gaps = {}, {}
    for _, entry in ipairs(entries) do
        addEntryTotals(summary, entry)
        addEntryLuck(summary, entry, gaps)
        addEntryDrops(summary, entry, killsByNpcId)
    end
    summary.luck = Chronicle.getLuck(summary.kills, summary.expected)
    local memory = ns.Spoilers and ns.Spoilers.getMemory()
    summary.peekCount = memory and tonumber(memory.peeks) or 0
    summary.hasSpoilers = summary.spoilerCount > 0 or summary.peekCount > 0
    summary.mostKilledList = composeMostKilled(killsByNpcId)
    summary.mostKilled = summary.mostKilledList[1]
    summary.chainCount = countFinishedChains(earlierQuestIds)
    return summary
end

---@class ChronicleZone
---@field zoneId number
---@field name string
---@field doneCount number Quests that start here done, the earlier ones included
---@field totalCount number Quests that start here for this character: done, in the log, available and not yet
---@field entries table[] Chronicle entries of the zone, newest first
---@field earlierQuestIds number[] Done here before the chronicle began
---@field lastAt number? When a quest of the zone was last handed in
---@field experience number
---@field playedSeconds number Time the zone's quests took, added up
---@field kills number
---@field expected number

local CONTINENT_MAP_TYPE = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2

-- The quest database lists raids and battlegrounds among its dungeons; they are told apart here
local RAID_AREA_IDS = {
    [2717] = true,
    [2159] = true,
    [2677] = true,
    [1977] = true,
    [3429] = true,
    [3428] = true,
    [3456] = true,
} -- Molten Core, Onyxia's Lair, Blackwing Lair, Zul'Gurub, Ruins and Temple of Ahn'Qiraj, Naxxramas
local BATTLEGROUND_AREA_IDS = { [2597] = true, [3277] = true, [3358] = true } -- Alterac Valley, Warsong Gulch, Arathi Basin

---@return string name The continent a zone is on, from the game's maps; "Dungeons", "Raids" or "Battlegrounds"
---for an instance
local function getContinentName(zoneId)
    local dungeon = ns.Database.getDungeon(zoneId)
    if dungeon then
        return (RAID_AREA_IDS[dungeon.areaId] or dungeon.isRaid) and "Raids"
            or BATTLEGROUND_AREA_IDS[dungeon.areaId] and "Battlegrounds"
            or "Dungeons"
    end
    local uiMapId = ns.Database.getUiMapId(zoneId)
    local info = uiMapId and C_Map and C_Map.GetMapInfo and ns.Database.getMapInfo(uiMapId)
    for _ = 1, 6 do
        if not info or not info.mapType or info.mapType <= CONTINENT_MAP_TYPE then
            break
        end
        info = info.parentMapID and ns.Database.getMapInfo(info.parentMapID) or nil
    end
    return info and info.mapType == CONTINENT_MAP_TYPE and info.name or "Elsewhere"
end

---@return ChronicleZone[] zones Every zone with a quest done, the last one played first, then by quests done
function Chronicle.getZones()
    local zonesById, zones = {}, {}
    local function getZone(zoneId)
        if not zoneId then
            return nil
        end
        local zone = zonesById[zoneId]
        if not zone then
            zone = {
                zoneId = zoneId,
                name = ns.Database.getZoneName(zoneId),
                doneCount = 0,
                totalCount = 0,
                entries = {},
                earlierQuestIds = {},
                experience = 0,
                playedSeconds = 0,
                kills = 0,
                expected = 0,
            }
            zonesById[zoneId] = zone
            zones[#zones + 1] = zone
        end
        return zone
    end
    -- A quest belongs to every zone the Available tab lists it under: where it is picked up, and the dungeon
    -- it leads to (Availability.getZoneQuestIds); one the index does not know stays where it was handed in
    local function getQuestZones(questId, fallbackZoneId)
        local zoneIds = ns.Availability.getQuestZoneIds(questId)
        if #zoneIds == 0 then
            zoneIds = { fallbackZoneId }
        end
        local questZones = {}
        for _, zoneId in ipairs(zoneIds) do
            questZones[#questZones + 1] = getZone(zoneId)
        end
        return questZones
    end
    local doneByZone = {} -- [zone] = { [questId] = true }, each quest done counted once however often handed in
    local function addDone(zone, questId)
        doneByZone[zone] = doneByZone[zone] or {}
        doneByZone[zone][questId] = true
    end
    local entries = Chronicle.getEntries()
    for index = #entries, 1, -1 do
        local entry = entries[index]
        for _, zone in ipairs(getQuestZones(entry.questId, entry.zoneId)) do
            zone.entries[#zone.entries + 1] = entry
            zone.lastAt = zone.lastAt or entry.turnedInAt
            zone.experience = zone.experience + (entry.experience or 0)
            zone.playedSeconds = zone.playedSeconds + (entry.duration or 0)
            local kills, expected = getEntryKills(entry)
            zone.kills, zone.expected = zone.kills + kills, zone.expected + expected
            addDone(zone, entry.questId)
        end
    end
    for _, questId in ipairs(Chronicle.getEarlierQuestIds()) do
        for _, zone in ipairs(getQuestZones(questId, nil)) do
            zone.earlierQuestIds[#zone.earlierQuestIds + 1] = questId
            addDone(zone, questId)
        end
    end
    -- Zones and dungeons with a quest in the log count too, before anything there is done
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        getQuestZones(questId, nil)
    end
    -- And every dungeon with a quest for the character, done or not: the ones not started are the ones to plan
    for _, dungeonId in ipairs(ns.Availability.getDungeonIds()) do
        if #ns.Availability.getZoneQuestStates(dungeonId) > 0 then
            getZone(dungeonId)
        end
    end
    for _, zone in ipairs(zones) do
        -- What is done is what the lists show; what is left, the zone's quests not done yet: the two add up
        local zoneSummary = ns.Availability.getZoneSummary(zone.zoneId)
        local doneCount = 0
        for _ in pairs(doneByZone[zone] or {}) do
            doneCount = doneCount + 1
        end
        zone.doneCount = doneCount
        zone.totalCount = doneCount + zoneSummary.inLog + zoneSummary.available + zoneSummary.notYet
        zone.summary = zoneSummary
        zone.isDungeon = ns.Database.getDungeon(zone.zoneId) ~= nil
        zone.continentName = getContinentName(zone.zoneId)
        zone.minLevel, zone.maxLevel = ns.Availability.getZoneLevels(zone.zoneId)
    end
    table.sort(zones, function(first, second)
        if (first.lastAt ~= nil) ~= (second.lastAt ~= nil) then
            return first.lastAt ~= nil
        end
        if first.lastAt and first.lastAt ~= second.lastAt then
            return first.lastAt > second.lastAt
        end
        if first.doneCount ~= second.doneCount then
            return first.doneCount > second.doneCount
        end
        return first.name < second.name
    end)
    return zones
end

---------------------------------------------------------------------------------------------------------------

local function handleEvent(_, event, ...)
    if event == "QUEST_ACCEPTED" then
        local first, second = ...
        -- Some clients send the log index first and the quest's number second
        Chronicle.handleAccept(second or first)
    elseif event == "QUEST_TURNED_IN" then
        Chronicle.handleTurnIn(...)
    elseif event == "QUEST_REMOVED" then
        local questId = ...
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                -- (taken again meanwhile, a repeatable accepted at once: its new record stays, nothing abandoned)
                if not ns.QuestState.isInLog(questId) then
                    Chronicle.handleRemove(questId)
                end
            end)
        else
            Chronicle.handleRemove(questId)
        end
    elseif event == "PLAYER_DEAD" then
        Chronicle.handleDeath()
    elseif event == "GROUP_ROSTER_UPDATE" then
        Chronicle.handleGroupChange()
    elseif event == "PLAYER_LOGOUT" then
        savePlayedSeconds()
    end
end

function Chronicle.create()
    if eventFrame or not CreateFrame then
        return
    end
    sessionStart = GetTime and GetTime() or 0
    eventFrame = CreateFrame("Frame")
    for _, event in ipairs({
        "QUEST_ACCEPTED",
        "QUEST_TURNED_IN",
        "QUEST_REMOVED",
        "PLAYER_DEAD",
        "GROUP_ROSTER_UPDATE",
        "PLAYER_LOGOUT",
    }) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    eventFrame:SetScript("OnEvent", handleEvent)
    -- The reward picked in the hand-in dialog
    if hooksecurefunc and GetQuestReward then
        hooksecurefunc("GetQuestReward", function(choice)
            pendingRewardLink = choice and choice > 0 and GetQuestItemLink and GetQuestItemLink("choice", choice) or nil
        end)
    end
    -- Quests already in the log when the chronicle starts: known from now on, when they were taken is not
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        getOpen(questId)
    end
end

---Forgets what was worked out, for tests and when the game's record of completed quests changes.
function Chronicle.reset()
    earlierCache = nil
end

ns.registerModule({
    name = "Chronicle",
    create = Chronicle.create,
    -- What the chronicle knows of a quest so far is kept while it is in the log (one that left the log with the
    -- addon off left it behind)
    prune = function(isInLog)
        if not isInLog then
            return
        end
        local open = Chronicle.getBook().open
        for questId in pairs(open) do
            if not isInLog[questId] then
                open[questId] = nil
            end
        end
    end,
})
