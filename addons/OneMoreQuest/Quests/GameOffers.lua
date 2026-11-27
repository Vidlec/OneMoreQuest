local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quests the game itself offers: on a map, the list its own "!" marks are drawn from, and in a quest giver's
-- dialog, what they offer when talked to. It catches what the quest database or this addon's rules miss. A
-- quest the game offers that this addon did not list is added to the quests to pick up on the fly, and noted
-- (`/omq missing` opens a report to copy), so the hole behind it can be fixed.
local GameOffers = {}
ns.GameOffers = GameOffers

local offersByMapId = {} -- [uiMapId] = the game's offers, read since it last said they changed
local signatureByMapId = {} -- [uiMapId] = which quests the game itself offered there when last read
local requestedMapIds = {} -- maps the game was asked about; it answers with QUESTLINE_UPDATE
local eventFrame

---@return boolean isOnMap A quest offered from a map shows on it, and on the map of the zone around it
local function isOfferedOnMap(startMapId, uiMapId)
    if not startMapId or startMapId == uiMapId then
        return true
    end
    return MapUtil ~= nil and MapUtil.IsChildMapCached ~= nil and MapUtil.IsChildMapCached(startMapId, uiMapId) == true
end

local function readOffers(uiMapId)
    if not C_QuestLine or not C_QuestLine.GetAvailableQuestLines then
        return {}
    end
    local isRead, questLines = pcall(C_QuestLine.GetAvailableQuestLines, uiMapId)
    if not isRead or type(questLines) ~= "table" then
        return {}
    end
    local offers = {}
    for _, info in ipairs(questLines) do
        if info.questID and not info.inProgress and isOfferedOnMap(info.startMapID, uiMapId) then
            offers[#offers + 1] = {
                questId = info.questID,
                title = info.questName,
                x = info.x,
                y = info.y,
                isTrivial = info.isHidden == true,
            }
        end
    end
    return offers
end

---The quests quest givers offered this character when talked to, kept per character: [questId] = the giver,
---where they stand and the quest's title.
local function getLearnedOffers()
    return ns.getCharacterRecords("learnedOffers")
end

---@return { questId: number, title: string?, x: number, y: number, isTrivial: boolean, npcId: number?, npcName: string?, isLearned: boolean?, wasClosed: boolean? }[] offers
---The quests the game offers on a zone's map, with their place on it (0 to 1): its own "!" marks, and the quests
---givers there offered when talked to (`isLearned`; `wasClosed` when the data called it closed for good even then).
---Empty until the game has answered.
function GameOffers.get(zoneId)
    local uiMapId = zoneId and ns.Database.getUiMapId(zoneId)
    -- Only a zone's own offers: on the world's or a continent's map the game names quests all over it, whose places
    -- the zone's list would then draw in the wrong place, and twice
    if not uiMapId or not ns.Database.isZoneMap(uiMapId) then
        return {}
    end
    if not offersByMapId[uiMapId] then
        if not requestedMapIds[uiMapId] and C_QuestLine and C_QuestLine.RequestQuestLinesForMap then
            requestedMapIds[uiMapId] = true
            pcall(C_QuestLine.RequestQuestLinesForMap, uiMapId)
        end
        local offers = readOffers(uiMapId)
        signatureByMapId[uiMapId] = GameOffers.getSignature(offers)
        local listed = {}
        for _, offer in ipairs(offers) do
            listed[offer.questId] = true
        end
        for questId, learned in pairs(getLearnedOffers()) do
            if not listed[questId] and learned.uiMapId and isOfferedOnMap(learned.uiMapId, uiMapId) then
                offers[#offers + 1] = {
                    questId = questId,
                    title = learned.title,
                    x = learned.x or 0.5,
                    y = learned.y or 0.5,
                    isTrivial = learned.isTrivial == true,
                    npcId = learned.npcId,
                    npcName = learned.npcName,
                    isLearned = true,
                    wasClosed = learned.wasClosed == true,
                }
            end
        end
        offersByMapId[uiMapId] = offers
    end
    return offersByMapId[uiMapId]
end

---@return number? npcId, string? npcName The creature the player is talking to; nil for an item or an object
local function getTalkedToNpc()
    local guid = UnitGUID and UnitGUID("npc")
    local npcId = guid and ns.Database.getNpcId(guid)
    return npcId, npcId and UnitName and UnitName("npc") or nil
end

---@return number? uiMapId, number? x, number? y Where the player stands: the map, and the place on it
local function getPlayerMapSpot()
    local uiMapId = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local position = uiMapId and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(uiMapId, "player")
    if position and position.GetXY then
        local x, y = position:GetXY()
        return uiMapId, x, y
    end
    return uiMapId, nil, nil
end

---Keeps what the giver offers in the learned offers, with where they stand.
---@param giver { npcId: number, npcName: string?, uiMapId: number?, x: number?, y: number? }
---@return table<number, boolean> offered The quests offered
local function rememberOffers(learned, quests, giver)
    local offered = {}
    local player = ns.Availability.getPlayer()
    for _, quest in ipairs(quests) do
        if quest.questId and quest.questId > 0 then
            offered[quest.questId] = true
            -- Whether the quest database already called it closed for good while the giver offered it: a hole in
            -- the data, the giver's word stands. Otherwise the offer holds only until the data closes it (another
            -- quest of its choice taken, the player past its level): what was offered then is not offered now
            -- (a quest the player hid or turned off reads as closed too, but is not: that is theirs to change)
            local _, isClosed = ns.Availability.getBlocker(quest.questId, player)
            learned[quest.questId] = {
                title = quest.title,
                isTrivial = quest.isTrivial,
                npcId = giver.npcId,
                npcName = giver.npcName,
                uiMapId = giver.uiMapId,
                x = giver.x,
                y = giver.y,
                wasClosed = (isClosed == true and not ns.Availability.isLeftOutBySettings(quest.questId)) or nil,
            }
        end
    end
    return offered
end

---@return number[] zoneIds The zones the giver stands in, each once (a subzone as its zone)
local function getGiverZoneIds(npcId)
    local zoneIds, isSeen = {}, {}
    for zoneId in pairs(ns.Database.getNpcField(npcId, "spawns") or {}) do
        local parentZoneId = ns.Database.getParentZoneId(zoneId) or zoneId
        if not isSeen[parentZoneId] then
            isSeen[parentZoneId] = true
            zoneIds[#zoneIds + 1] = parentZoneId
        end
    end
    return zoneIds
end

---@return boolean isStarter The database names the creature among the quest's givers
local function isStartedBy(questId, npcId)
    local startedBy = ns.Database.getQuestField(questId, "startedBy") or {}
    for _, starterId in ipairs(startedBy[1] or {}) do
        if starterId == npcId then
            return true
        end
    end
    return false
end

---What this giver should offer by the quest database and this addon's rules, and did not: the game knows of a
---condition the database does not (Drum Fel's Call to Arms). Until the giver offers it, or the player has gone up a
---level, it is not listed to pick up. Low-level quests are left be: a giver may leave them out.
---@param changedQuestIds number[] Added to: the quests refused now
local function noteRefusals(refusals, giver, offered, changedQuestIds)
    if not ns.Availability.isReady() then
        return
    end
    -- The quests listed in the zones where the giver stands
    for _, zoneId in ipairs(getGiverZoneIds(giver.npcId)) do
        for _, quest in ipairs(ns.Availability.getQuests(zoneId, { shouldShowLowLevel = false })) do
            if
                isStartedBy(quest.questId, giver.npcId)
                and not offered[quest.questId]
                and not quest.availableAtLevel
                and not quest.isLowLevel
            then
                refusals[quest.questId] =
                    { npcId = giver.npcId, npcName = giver.npcName, level = UnitLevel and UnitLevel("player") or 0 }
                changedQuestIds[#changedQuestIds + 1] = quest.questId
            end
        end
    end
end

---Remembers what a giver offers now. A full list (`isComplete`) also forgets what the same giver offered before
---and no longer does: taken by now, or never really this character's.
---@param quests { questId: number, title: string?, isTrivial: boolean? }[]
function GameOffers.learnOffers(quests, isComplete)
    local npcId, npcName = getTalkedToNpc()
    if not npcId then
        return
    end
    local uiMapId, x, y = getPlayerMapSpot()
    local giver = { npcId = npcId, npcName = npcName, uiMapId = uiMapId, x = x, y = y }
    local learned = getLearnedOffers()
    local offered = rememberOffers(learned, quests, giver)
    local refusals = ns.getCharacterRecords("learnedRefusals")
    local changedQuestIds = {} -- the quests whose refusal came or went: whether they can be picked up is asked again
    for questId in pairs(offered) do
        if refusals[questId] then
            changedQuestIds[#changedQuestIds + 1] = questId
        end
        refusals[questId] = nil
    end
    if isComplete then
        for questId, entry in pairs(learned) do
            if entry.npcId == npcId and not offered[questId] then
                learned[questId] = nil
            end
        end
        noteRefusals(refusals, giver, offered, changedQuestIds)
    end
    offersByMapId = {}
    ns.Availability.forgetOffers(changedQuestIds)
    ns.queueRefresh()
end

---Forgets what a giver was found to offer, for a quest closed since (Availability.getQuests): it is no longer theirs to
---give, so it is neither listed on their word nor noted as missed.
function GameOffers.forgetLearned(questId)
    local learned = getLearnedOffers()
    if learned[questId] then
        learned[questId] = nil
        offersByMapId = {}
    end
end

---@return { npcId: number, npcName: string? }? refusal Who left the quest out of what they offered, at the player's
---level now; nil once they have offered it, or the player has gone up a level since (worth asking again)
function GameOffers.getRefusal(questId)
    local refusal = ns.getCharacterRecords("learnedRefusals")[questId]
    local level = UnitLevel and UnitLevel("player") or 0
    return refusal and refusal.level == level and refusal or nil
end

---What the open dialog offers: a gossip window's list, a greeting's list, or the one quest being shown.
local function readDialogOffers(event)
    local quests = {}
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetAvailableQuests then
        for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            quests[#quests + 1] = { questId = info.questID, title = info.title, isTrivial = info.isTrivial }
        end
        return quests, true
    elseif event == "QUEST_GREETING" and GetNumAvailableQuests then
        for index = 1, GetNumAvailableQuests() do
            -- Called on its own: "f and f()" would keep only the first of its values, and the quest is the fifth
            local isTrivial, questId
            if GetAvailableQuestInfo then
                local _
                isTrivial, _, _, _, questId = GetAvailableQuestInfo(index)
            end
            quests[#quests + 1] =
                { questId = questId, title = GetAvailableTitle and GetAvailableTitle(index), isTrivial = isTrivial }
        end
        return quests, true
    elseif event == "QUEST_DETAIL" and GetQuestID then
        quests[1] = { questId = GetQuestID(), title = GetTitleText and GetTitleText() }
        return quests, false
    end
    return quests, false
end

GameOffers.readDialogOffers = readDialogOffers -- for tests

---Notes a quest the game offered that this addon had missed, once, with why and where.
---@param reason string What made this addon miss it
---@param offer table? The game's offer: its place on the map, and the giver when one was talked to
function GameOffers.noteMissed(questId, title, zoneId, reason, offer)
    local missed = ns.settings.missedQuests
    if not missed[questId] then
        missed[questId] = {
            title = title,
            zoneId = zoneId,
            reason = reason,
            npcId = offer and offer.npcId,
            npcName = offer and offer.npcName,
            x = offer and offer.x,
            y = offer and offer.y,
        }
    end
end

local function getAddOnVersion(name)
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return getMetadata and getMetadata(name, "Version") or "?"
end

---@return string[] lines The report's opening: the client and the character
local function composeReportHeader()
    local version, build
    if GetBuildInfo then
        version, build = GetBuildInfo() -- both values: "GetBuildInfo and GetBuildInfo()" would keep only the first
    end
    local race, class = UnitRace and UnitRace("player"), UnitClass and UnitClass("player")
    return {
        "OneMoreQuest: quests the game offered that the addon missed",
        string.format(
            "OneMoreQuest %s, QuestieDB %s, client %s (%s), %s",
            getAddOnVersion(ns.ADDON_FOLDER or "OneMoreQuest"),
            getAddOnVersion("QuestieDB"),
            tostring(version or "?"),
            tostring(build or "?"),
            GetLocale and GetLocale() or "?"
        ),
        string.format(
            "Character: level %s %s %s %s",
            tostring(UnitLevel and UnitLevel("player") or "?"),
            tostring(UnitFactionGroup and UnitFactionGroup("player") or "?"),
            tostring(race or "?"),
            tostring(class or "?")
        ),
        "",
        "quest | title | zone | why it was missed | giver | place",
    }
end

---@return string line One missed quest: its zone, the giver and their place, and why the addon missed it
local function composeMissedLine(questId, missed)
    local giver = missed.npcId and string.format("%s (%d)", missed.npcName or "?", missed.npcId) or "-"
    local place = missed.x and string.format("%.1f, %.1f", missed.x * 100, missed.y * 100) or "-"
    return string.format(
        "%d | %s | %s | %s | %s | %s",
        questId,
        missed.title or "?",
        missed.zoneId and ns.Database.getZoneName(missed.zoneId) or "?",
        missed.reason or "?",
        giver,
        place
    )
end

---Adds a section to the report when it has lines: a blank line, its headings, then its lines.
local function appendSection(lines, headings, sectionLines)
    if #sectionLines == 0 then
        return
    end
    lines[#lines + 1] = ""
    for _, heading in ipairs(headings) do
        lines[#lines + 1] = heading
    end
    for _, line in ipairs(sectionLines) do
        lines[#lines + 1] = line
    end
end

---@return string report The quests noted as missed, with what a fix needs: the client, the character, and for each
---quest its zone, the giver and their place, and why the addon missed it
---@return number count
function GameOffers.composeReport()
    local questIds = {}
    for questId in pairs(ns.settings.missedQuests) do
        questIds[#questIds + 1] = questId
    end
    table.sort(questIds)
    local lines = composeReportHeader()
    for _, questId in ipairs(questIds) do
        lines[#lines + 1] = composeMissedLine(questId, ns.settings.missedQuests[questId])
    end
    -- Where the game's quests differ from the database's: a quest it lacks, a giver, turn-in or items it has otherwise
    appendSection(lines, {
        "Where the game differs from QuestieDB",
        "quest | title | what | the game | QuestieDB",
    }, ns.DataCheck.composeReportLines())
    -- Dungeons the database lacks, learned by playing: what to pass on to the quest database's makers
    appendSection(lines, {
        "Dungeons QuestieDB does not know (quests marked * are picked up inside)",
        "instance | name | entrance | quests done inside",
        "(QuestieTrace, on CurseForge, records runs like these for the Questie team.)",
    }, ns.LearnedDungeons.composeReportLines())
    return table.concat(lines, "\n"), #questIds
end

---Empties the list of missed quests (the report's Clear button).
function GameOffers.clearMissed()
    ns.settings.missedQuests = {}
    ns.DataCheck.clear()
end

function GameOffers.create()
    if eventFrame or not CreateFrame then
        return
    end
    eventFrame = CreateFrame("Frame")
    -- The game says its offers changed (an answer to a request, a quest taken or handed in): read them again.
    -- A quest giver's dialog says what they offer this character: learnt.
    for _, event in ipairs({ "QUESTLINE_UPDATE", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_TURNED_IN" }) do
        pcall(eventFrame.RegisterEvent, eventFrame, event)
    end
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "QUEST_TURNED_IN" then
            -- A quest handed in may be the condition a giver's refusal stood on (The Hammer May Fall, before Drum
            -- Fel's Call to Arms): every refusal is asked again
            local refusals = ns.getCharacterRecords("learnedRefusals")
            local askedAgain = {}
            for questId in pairs(refusals) do
                askedAgain[#askedAgain + 1] = questId
                refusals[questId] = nil
            end
            if #askedAgain > 0 then
                ns.Availability.forgetOffers(askedAgain)
            end
            return
        end
        if event == "QUESTLINE_UPDATE" then
            -- The game says so for every asking, its own world map's too (each time it opens): the lists and the
            -- maps are worked out again only when what it offers on a map read before is not what was read
            if GameOffers.haveOffersChanged() then
                offersByMapId, signatureByMapId = {}, {}
                ns.Availability.forgetOffers() -- (what the game offers is in the lists, not in who can pick up what)
                ns.queueRefresh()
            end
            return
        end
        local isRead, quests, isComplete = pcall(readDialogOffers, event)
        if isRead and (#quests > 0 or isComplete) then
            GameOffers.learnOffers(quests, isComplete)
        end
    end)
end

---@return string signature Which quests a map's offers are, and whether each is low level: what is drawn of them
function GameOffers.getSignature(offers)
    local parts = {}
    for _, offer in ipairs(offers) do
        parts[#parts + 1] = tostring(offer.questId) .. (offer.isTrivial and "t" or "")
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

---@return boolean changed The game offers, on a map read before, other quests than it did then
function GameOffers.haveOffersChanged()
    for uiMapId, signature in pairs(signatureByMapId) do
        if GameOffers.getSignature(readOffers(uiMapId)) ~= signature then
            return true
        end
    end
    return false
end

---Forgets what was read, so the next look asks the game again.
---/omq offers: in the player's zone, how many quests the game's own map offers, and which quests this addon lists to
---pick up that the game's map does not, each with what kind it is. Tells whether the game's list is whole enough to
---leave out what it does not offer (a giver the realm does not have, as the Commendation Officers on Forever).
function GameOffers.printComparison()
    local zoneId = ns.Model.getPlayer().zoneId
    local uiMapId = zoneId and ns.Database.getUiMapId(zoneId)
    if not uiMapId or not ns.Availability.isReady() then
        ns.print("offers: not ready yet (the quest lists are still being worked out); try again in a moment.")
        return
    end
    GameOffers.get(zoneId) -- (asks the game for the map's list, when it was not asked yet)
    local gameIds, gameCount = {}, 0
    for _, offer in ipairs(readOffers(uiMapId)) do
        gameIds[offer.questId] = true
        gameCount = gameCount + 1
    end
    local listed, notInGame = 0, {}
    for _, quest in ipairs(ns.Availability.getQuests(zoneId, { shouldShowLowLevel = true })) do
        if not quest.availableAtLevel and not quest.isHandedInHere and not quest.blocker then
            listed = listed + 1
            if not gameIds[quest.questId] then
                local kinds = {}
                if quest.isLowLevel then
                    kinds[#kinds + 1] = "low level"
                end
                if ns.Availability.isRepeatable(quest.questId) then
                    kinds[#kinds + 1] = "repeatable"
                end
                if ns.Events.isEventQuest(quest.questId) then
                    kinds[#kinds + 1] = "event"
                end
                kinds[#kinds + 1] = quest.startType or "npc"
                notInGame[#notInGame + 1] = string.format(
                    "  %d [%d] %s - %s (%s)",
                    quest.questId,
                    quest.level or 0,
                    quest.title or "?",
                    quest.starterName or "?",
                    table.concat(kinds, ", ")
                )
            end
        end
    end
    ns.print(
        string.format(
            "offers in %s: the game's map offers %d, OneMoreQuest lists %d, of which %d the game's map does not:",
            ns.Database.getZoneName(zoneId),
            gameCount,
            listed,
            #notInGame
        )
    )
    if gameCount == 0 then
        ns.print("  (the game has not answered for this map yet: open the map once, then try again)")
    end
    for _, line in ipairs(notInGame) do
        print(line)
    end
end

function GameOffers.reset()
    offersByMapId, requestedMapIds = {}, {}
end

ns.registerModule({
    name = "GameOffers",
    create = GameOffers.create,
    -- What givers offered is kept until the quest is done (one abandoned is offered again)
    prune = function()
        local learnedOffers = ns.getCharacterRecords("learnedOffers")
        for questId in pairs(learnedOffers) do
            if ns.QuestState.isTurnedIn(questId) then
                learnedOffers[questId] = nil
            end
        end
        -- A giver's refusal holds at the level it was made; the player has gone up since, it is asked again
        local refusals, level = ns.getCharacterRecords("learnedRefusals"), UnitLevel and UnitLevel("player") or 0
        for questId, refusal in pairs(refusals) do
            if refusal.level ~= level or ns.QuestState.isTurnedIn(questId) then
                refusals[questId] = nil
            end
        end
    end,
})
