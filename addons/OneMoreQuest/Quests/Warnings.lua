local _, ns = ...

-- The classic questing mistakes worth a warning before accepting a quest: skipping a lead-in quest, picking
-- one of several either/or quests without knowing, and running out of room in the quest log.
local Warnings = {}
ns.Warnings = Warnings

local LOG_SPARE_SLOTS = 2
local MAX_NAMES = 3

local function getQuestName(questId)
    return ns.QuestText.getQuestName(questId) or ("quest " .. questId)
end

local function composeNameList(questIds)
    local names = {}
    for nameIndex = 1, math.min(#questIds, MAX_NAMES) do
        names[nameIndex] = '"' .. getQuestName(questIds[nameIndex]) .. '"'
    end
    local text = table.concat(names, ", ")
    if #questIds > MAX_NAMES then
        text = text .. ns.Lp(#questIds - MAX_NAMES, " and %d more", " and %d more")
    end
    return text
end

---@param shouldSkipLog boolean? Leaves out the full-log warning, for lists where it would repeat on every row
---@return string[] warnings About accepting a quest that is not in the log yet
---@return table<number, { format: string, questId: number }> links For a warning naming one quest, by its index: the
---warning's text format (its "%s" the quest's name) and the quest, so a page can make the name a link to it
function Warnings.getQuestWarnings(questId, shouldSkipLog)
    local warnings, links = {}, {}
    local player = ns.Availability.getPlayer()
    -- What the Spoilers choice lets these name: the quest a lead-in leads to is later in the story; the lead-ins and
    -- the other quests of a choice are quests to pick up. Held back, the warning still warns, naming none of them.
    local isStoryHidden = ns.Availability.isLaterHidden("quest")
    local isPickupHidden = ns.Spoilers.isActive() and ns.Spoilers.getChoice("pickup") ~= "all"

    local leadsToQuestId = ns.Database.getQuestField(questId, "breadcrumbForQuestId") or 0
    if leadsToQuestId ~= 0 and isStoryHidden then
        warnings[#warnings + 1] = ns.L("A lead-in: lost once you take the quest it leads to")
    elseif leadsToQuestId ~= 0 then
        warnings[#warnings + 1] = ns.L('Lead-in to "%s": lost once you take that quest', getQuestName(leadsToQuestId))
        links[#warnings] = { format = ns.L('Lead-in to "%s": lost once you take that quest'), questId = leadsToQuestId }
    end

    local openLeadIns = {}
    for _, leadInQuestId in ipairs(ns.Database.getQuestField(questId, "breadcrumbs") or {}) do
        if ns.Availability.isEligible(leadInQuestId, player) then
            openLeadIns[#openLeadIns + 1] = leadInQuestId
        end
    end
    if #openLeadIns > 0 and (isStoryHidden or isPickupHidden) then
        warnings[#warnings + 1] = ns.Lp(
            #openLeadIns,
            "A lead-in to this is still open: it is lost once you take this",
            "%d lead-ins to this are still open: they are lost once you take this"
        )
    elseif #openLeadIns > 0 then
        warnings[#warnings + 1] = ns.L("Do %s first, or it is lost once you take this", composeNameList(openLeadIns))
        if #openLeadIns == 1 then
            links[#warnings] =
                { format = ns.L("Do %s first, or it is lost once you take this"), questId = openLeadIns[1] }
        end
    end

    local exclusiveQuestIds = ns.Database.getQuestField(questId, "exclusiveTo")
    if exclusiveQuestIds and #exclusiveQuestIds > 0 then
        -- Versions of this same quest (one at each of the Sparklematic's machines) are told apart from other quests
        local name, otherQuestIds = ns.Database.getQuestField(questId, "name"), {}
        for _, exclusiveQuestId in ipairs(exclusiveQuestIds) do
            -- Not one the game does not offer (Questie's duplicates, HiddenQuests): nothing to lock out
            if
                ns.Database.getQuestField(exclusiveQuestId, "name") ~= name and not ns.HiddenQuests[exclusiveQuestId]
            then
                otherQuestIds[#otherQuestIds + 1] = exclusiveQuestId
            end
        end
        -- Versions of this same quest are said on its row ("any of 3 places") and its page, not warned of
        if #otherQuestIds > 0 and isPickupHidden then
            warnings[#warnings + 1] = ns.Lp(
                #otherQuestIds,
                "Choose one: it locks out %d other quest",
                "Choose one: it locks out %d other quests"
            )
        elseif #otherQuestIds > 0 then
            warnings[#warnings + 1] = ns.L("Choose one: locks out %s", composeNameList(otherQuestIds))
        end
    end

    local count, max = ns.QuestState.getLogSize()
    if not shouldSkipLog and count >= max then
        warnings[#warnings + 1] = ns.L("Your quest log is full.")
    end
    return warnings, links
end

local DROP_SUGGESTION_FROM = 5 -- the suggestions show once the log has this few places left, or fewer
local MAX_DROP_SUGGESTIONS = 3
local STALE_DAYS = 3
local CONTINENT_MAP_TYPE = 2 -- Enum.UIMapType.Continent

---@return number? uiMapId The continent a zone is on, by the map's own parents
local function getContinentMapId(zoneId)
    local uiMapId = zoneId and ns.Database.getUiMapId(zoneId)
    for _ = 1, 6 do
        local info = uiMapId and C_Map and C_Map.GetMapInfo and ns.Database.getMapInfo(uiMapId)
        if not info then
            return nil
        elseif info.mapType == CONTINENT_MAP_TYPE then
            return uiMapId
        end
        uiMapId = info.parentMapID
    end
    return nil
end

---@class DropSuggestion
---@field questId number
---@field level number
---@field reason string Why it is worth dropping, in a few words

---@return number? zoneId Where the quest leads now (its step's zone; a dungeon as the zone of its entrance), not where
---it was picked up: a quest taken here may well be done on another continent, and one taken there, here
local function getLeadsToZoneId(questId, modelPlayer)
    local stepZoneId = ns.Model.composeEntry(questId, modelPlayer).zoneId
    return stepZoneId and stepZoneId ~= 0 and ns.Database.getMapZoneId(stepZoneId)
        or ns.Availability.getStartZoneId(questId)
end

---@param context table What every quest is judged against: player, modelPlayer, playerContinent, book, now
---@return number score How worth dropping it is: 3 grey, 2 on another continent, 1 taken days ago, 0 not at all
---@return string? reason Why, in a few words
---@return number days How many days ago it was taken
local function judgeDrop(questId, level, context)
    local zoneId = getLeadsToZoneId(questId, context.modelPlayer)
    local open = context.book and context.book.open and context.book.open[questId]
    local days = open and open.acceptedAt and math.floor((context.now - open.acceptedAt) / 86400) or 0
    local player = context.player
    if level > 0 and player.level - level > ns.Availability.getTrivialGap(player.level) then
        return 3, ns.L("Grey: no experience left in it"), days
    end
    local continent = context.playerContinent and zoneId and getContinentMapId(zoneId)
    if continent and continent ~= context.playerContinent then
        return 2, ns.L("Far: %s, on another continent", ns.Database.getZoneName(zoneId)), days
    end
    if days >= STALE_DAYS then
        return 1, ns.Lp(days, "Taken %d day ago", "Taken %d days ago"), days
    end
    return 0, nil, days
end

---Best first: grey, then far, then old; the longest taken, then the lowest.
local function isBetterDrop(first, second)
    if first.score ~= second.score then
        return first.score > second.score
    end
    if first.days ~= second.days then
        return first.days > second.days
    end
    return first.level < second.level
end

---Quests worth giving up as the log fills: grey ones (no experience left in them), ones on another continent, ones
---taken days ago. Never one ready to hand in, nor the followed one. Best first: grey, then far, then old.
---@return DropSuggestion[] suggestions Empty while the log has room
function Warnings.getDropSuggestions()
    local count, max = ns.QuestState.getLogSize()
    if max - count > DROP_SUGGESTION_FROM then
        return {}
    end
    local modelPlayer = ns.Model.getPlayer()
    local context = {
        player = ns.Availability.getPlayer(),
        modelPlayer = modelPlayer,
        playerContinent = getContinentMapId(modelPlayer.zoneId),
        book = ns.Chronicle and ns.Chronicle.getBook(),
        now = ns.Chronicle and ns.Chronicle.getNow() or 0,
    }
    local candidates = {}
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        local quest = ns.QuestState.getQuest(questId)
        if quest and not quest.isComplete and questId ~= ns.Focus.get() then
            local level = quest.level or ns.Database.getQuestField(questId, "questLevel") or 0
            local score, reason, days = judgeDrop(questId, level, context)
            if score > 0 then
                candidates[#candidates + 1] =
                    { questId = questId, level = level, reason = reason, score = score, days = days }
            end
        end
    end
    table.sort(candidates, isBetterDrop)
    for index = #candidates, MAX_DROP_SUGGESTIONS + 1, -1 do
        candidates[index] = nil
    end
    return candidates
end

---@return number count, number max, boolean isNearlyFull
function Warnings.getLogSize()
    local count, max = ns.QuestState.getLogSize()
    return count, max, count >= max - LOG_SPARE_SLOTS
end
