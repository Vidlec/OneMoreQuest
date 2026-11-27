local _, ns = ...

-- Which quests the player can pick up right now, and where. The rules follow Questie's: level, race, class,
-- earlier quests done, nothing exclusive taken, and so on, plus Questie's list of quests that are not really
-- in the game (HiddenQuests). In order below: the kinds of quests and the rules (who can pick up what), why a quest
-- cannot be picked up yet (its blocker), the lists of a zone and of a dungeon run, and the forgetting of what was
-- worked out (with the warm-up that works it out again in the background). The zone index the lists read is built
-- by AvailabilityIndex.lua.
local Availability = {}
ns.Availability = Availability

local REPEATABLE_FLAG = 1
local RECURRING_FLAGS = { 4096, 32768, 65536 } -- daily, weekly, monthly
local PVP_TAG_ID = 41
local RAID_TAG_ID = 62
local DUNGEON_TAG_IDS = { [81] = true, [85] = true } -- dungeon, heroic dungeon

-- Battleground quests: the general category and the three battlegrounds' own
local PVP_CATEGORIES = { [-25] = true, [2597] = true, [3277] = true, [3358] = true }

local UPCOMING_LEVELS = 3
local MAX_ITEM_LEVELS_ABOVE = 10 -- a quest from an item is offered up to this many levels above the player

local CACHE_SECONDS = 5

local index -- AvailabilityIndex's, once built (Availability.prepare)

---A reason as a phrase to say in any language: its English key and what goes into it, a quest as { questId }. Shared
---with the group (Comms), so each member reads it in their own language, quest titles included
local function phrase(key, ...)
    return { key = key, args = { ... } }
end
local mergeAlternatives, mergeInstantSteps -- defined with the zone states below
local cache = {} -- [zone and options] = { quests, hiddenCount, time }
-- Whether the character can pick each quest up, kept while nothing it follows changes: their level, the quests in
-- their log and done (Availability.invalidateForRedraw), their reputations, skills and spells (the game's own events,
-- below), the settings and what givers were found to hold back (Availability.invalidate). Working it out is most of
-- what a list of quests to pick up costs, and a kill or a loot counted changes none of it.
local eligibility = {} -- [questId] = true (can be picked up), false (cannot), or the level it comes at (a few levels on)
local changeCount = 0 -- raised whenever who can pick up what may have changed (Availability.getChangeKey)
local settleCharacterChanges, startWarmUp -- (written with the forgetting, below the lists)
local computeBlocker -- (written with Availability.getBlocker)
local blockers, blockersAt = {}, nil -- [questId] = { why it cannot be picked up yet (or false), isClosed }, and the changeCount they hold for
local isIndexing = false
local readyCallbacks = {}

---Masks can be wider than 32 bits, so the bit is tested with arithmetic.
local function hasBit(mask, bit)
    return bit ~= nil and bit > 0 and math.floor(mask / bit) % 2 == 1
end

---@param unit string? The character to describe, "player" when nil: a party member is judged the same way
---@return { level: number, raceMask: number?, classMask: number? } player
function Availability.getPlayer(unit)
    unit = unit or "player"
    local _, _, raceId = UnitRace(unit)
    local _, classKey = UnitClass(unit)
    return {
        level = UnitLevel(unit) or 1,
        unit = unit,
        raceMask = ns.Database.getRaceMask(raceId),
        classMask = ns.Database.getClassMask(classKey),
    }
end

---@return number levels How far below a character a quest is low-level ("trivial"): the game's own range for
---them (UnitQuestTrivialLevelRange, what greys a quest in the game's lists), so a quest is low-level here exactly
---when the game shows it grey. Without the game's answer, the classic rule for their level.
local function getTrivialGap(level, unit)
    local range = UnitQuestTrivialLevelRange and UnitQuestTrivialLevelRange(unit or "player")
    if type(range) == "number" and range > 0 then
        return range
    end
    -- The classic grey levels: 5 below up to level 5, then a tenth of the level and 5, from 40 a fifth and 1
    if level <= 5 then
        return 5
    elseif level < 40 then
        return math.floor(level / 10) + 5
    end
    return math.floor(level / 5) + 1
end
Availability.getTrivialGap = getTrivialGap

---@return boolean isBelow The quest itself is so far below the player that the game greys it: low-level
local function isBelowPlayer(questId, player)
    local questLevel = ns.Database.getQuestField(questId, "questLevel") or 0
    -- The player's own gap when set ("more than 5 levels below me"), else the game's grey
    local gap = tonumber(ns.settings.lowLevelGap) or 0
    return questLevel > 0 and player.level - questLevel > (gap > 0 and gap or getTrivialGap(player.level, player.unit))
end

local function isDone(questId)
    return ns.QuestState.isTurnedIn(questId)
end

local function isTaken(questId)
    return ns.QuestState.isTurnedIn(questId) or ns.QuestState.isInLog(questId)
end

---Whether a quest asked for first counts as done: it is, or another side of its choice is (its exclusiveTo, as
---Questie reads it): a character who took the other of two breadcrumbs, or the other of two quests to choose
---between, has what the later quest asks for, and never will the one they passed by.
local function isDoneOrChosenOther(questId)
    if isDone(questId) then
        return true
    end
    for _, otherQuestId in ipairs(ns.Database.getQuestField(questId, "exclusiveTo") or {}) do
        if isDone(otherQuestId) then
            return true
        end
    end
    return false
end

local function isAnyDone(questIds)
    for _, questId in ipairs(questIds) do
        if isDoneOrChosenOther(math.abs(questId)) then
            return true
        end
    end
    return false
end

local function isEveryDone(questIds)
    for _, questId in ipairs(questIds) do
        if not isDoneOrChosenOther(math.abs(questId)) then
            return false
        end
    end
    return true
end

local function hasReputation(requirement, isMinimum)
    if not requirement then
        return true
    end
    local faction = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(requirement[1])
    if not faction then
        return not isMinimum
    end
    if isMinimum then
        return faction.currentStanding >= requirement[2]
    end
    return faction.currentStanding < requirement[2]
end

---@return number rank The character's rank in a skill line, such as a profession; 0 when it is not learnt
function Availability.getSkillRank(skillId)
    -- The skill lines of the character sheet, as this client's own Skills panel reads them
    if C_SkillInfo and C_SkillInfo.GetSkillLineInfoByID then
        local isRead, info = pcall(C_SkillInfo.GetSkillLineInfoByID, skillId)
        if isRead and type(info) == "table" and (info.rank or 0) > 0 then
            return info.rank
        end
    end
    if C_SkillInfo and C_SkillInfo.GetNumSkillLines and C_SkillInfo.GetSkillLineInfo then
        for index = 1, C_SkillInfo.GetNumSkillLines() or 0 do
            local info = C_SkillInfo.GetSkillLineInfo(index)
            if type(info) == "table" and info.skillID == skillId and not info.isHeader then
                return info.rank or 0
            end
        end
    end
    -- Newer clients know professions by their own lookup
    local getProfession = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
    local profession = getProfession and getProfession(skillId)
    return type(profession) == "table" and profession.skillLevel or 0
end

local function hasSkill(requirement)
    if not requirement then
        return true
    end
    local rank = Availability.getSkillRank(requirement[1])
    return rank > 0 and rank >= (requirement[2] or 0)
end

---@return boolean isForRun A quest a dungeon run can be for: not one done over and over, nor an event's
function Availability.isForRun(questId)
    return not Availability.isRepeatable(questId) and not ns.Events.isEventQuest(questId)
end

---Whether a quest can be done over and over, or is a city donation (AvailabilityIndex): each is done once,
---so the database does not call them repeatable, but they are the same kind of hand-in for reputation, on the
---same quartermasters as the repeatable "Additional Runecloth".
function Availability.isRepeatable(questId)
    local get = ns.Database.getQuestField
    if (index and index.isCityDonation[questId]) or hasBit(get(questId, "specialFlags") or 0, REPEATABLE_FLAG) then
        return true
    end
    local questFlags = get(questId, "questFlags") or 0
    for _, flag in ipairs(RECURRING_FLAGS) do
        if hasBit(questFlags, flag) then
            return true
        end
    end
    return false
end

---@return boolean isRaid A quest for a raid: the game labels it so, or the database files it under a raid
function Availability.isRaid(questId)
    if ns.QuestState.getTagId(questId) == RAID_TAG_ID then
        return true
    end
    local dungeon = ns.Database.getDungeon(ns.Database.getQuestField(questId, "zoneOrSort") or 0)
    return dungeon ~= nil and dungeon.isRaid == true
end

---@return boolean isDungeon A quest for a dungeon (not a raid): the game labels it so, or the database files it under one
function Availability.isDungeon(questId)
    if DUNGEON_TAG_IDS[ns.QuestState.getTagId(questId)] then
        return true
    end
    local dungeon = ns.Database.getDungeon(ns.Database.getQuestField(questId, "zoneOrSort") or 0)
    return dungeon ~= nil and not dungeon.isRaid
end

---Whether a quest belongs to player-versus-player play: a battleground's quest, or one the game labels so.
function Availability.isPvp(questId)
    if PVP_CATEGORIES[ns.Database.getQuestField(questId, "zoneOrSort") or 0] then
        return true
    end
    return ns.QuestState.getTagId(questId) == PVP_TAG_ID
end

---@return boolean isAllowed The quest's races include the character's (or it names none, or theirs is unknown)
local function isRaceAllowed(questId, player)
    local requiredRaces = ns.Database.getQuestField(questId, "requiredRaces") or 0
    return requiredRaces == 0 or not player.raceMask or hasBit(requiredRaces, player.raceMask)
end

---@return boolean isAllowed The quest's classes include the character's (or it names none, or theirs is unknown)
local function isClassAllowed(questId, player)
    local requiredClasses = ns.Database.getQuestField(questId, "requiredClasses") or 0
    return requiredClasses == 0 or not player.classMask or hasBit(requiredClasses, player.classMask)
end

---@return boolean isMeant A quest's race and class allow this character: the other faction's twin of a quest,
---or another class's, is not theirs even when the game marks it done
function Availability.isForRaceAndClass(questId)
    local player = Availability.getPlayer()
    return isRaceAllowed(questId, player) and isClassAllowed(questId, player)
end

---@return boolean isAboveRange The character is past the highest level the quest is for
local function isAboveMaxLevel(questId, player)
    local requiredMaxLevel = ns.Database.getQuestField(questId, "requiredMaxLevel") or 0
    return requiredMaxLevel ~= 0 and player.level > requiredMaxLevel
end

---Whether the player's own choices leave a quest out: one they hid, or of a kind the settings leave out (repeatable,
---player versus player, events, raids, the Ahn'Qiraj War Effort). The game offering a quest overrules the quest
---database and this addon's rules, never these.
local function isLeftOutBySettings(questId)
    -- The Ahn'Qiraj War Effort's, over on every realm, unless asked for (as Questie); one the player hid
    if
        (ns.AQWarEffortQuests[questId] and ns.settings.shouldShowAQWarEffort ~= true)
        or ns.QuestHiding.isHidden(questId)
    then
        return true
    end
    if not ns.settings.shouldShowRepeatable and Availability.isRepeatable(questId) then
        return true
    end
    if not ns.settings.shouldShowPvp and Availability.isPvp(questId) then
        return true
    end
    if ns.settings.shouldShowEvents == false and ns.Events.isEventQuest(questId) then
        return true
    end
    return ns.settings.shouldShowRaid == false and Availability.isRaid(questId)
end
Availability.isLeftOutBySettings = isLeftOutBySettings

---@return boolean isUnreachable The quest is given only by creatures the character cannot deal with: of the other
---faction, or out of reach in its capitals (no object or item starts it either)
local function isGivenOnlyByUnfriendly(questId)
    local startedBy = ns.Database.getQuestField(questId, "startedBy") or {}
    local starterNpcIds = startedBy[1] or {}
    if #starterNpcIds == 0 or #(startedBy[2] or {}) > 0 or #(startedBy[3] or {}) > 0 then
        return false
    end
    for _, npcId in ipairs(starterNpcIds) do
        if ns.Database.isNpcFriendly(npcId) then
            return false
        end
    end
    return true
end

---Whether a quest is meant for this character at all: its race and class, an event's only while it runs, and not of
---a kind the settings leave out (isLeftOutBySettings).
local function isForCharacter(questId, player)
    -- (Questie's list hides every event quest all year, as Questie shows each only while its event runs: one whose
    -- event runs now is offered, Events says)
    if
        (ns.HiddenQuests[questId] and not ns.Events.isQuestOffered(questId)) or ns.QuestState.isMissingFromGame(questId)
    then
        return false -- not really in the game (the game itself said so, for the second)
    end
    if isLeftOutBySettings(questId) then
        return false
    end
    if ns.Events.isEventQuest(questId) and not ns.Events.isQuestOffered(questId) then
        return false -- (an event's quest, offered only while it runs)
    end
    if isGivenOnlyByUnfriendly(questId) then
        return false
    end
    return isRaceAllowed(questId, player) and isClassAllowed(questId, player)
end

local MAX_LEAD_STEPS = 15
local chainLeads = {} -- [questId:level:kind] = the lead found, or false; cleared with the lists

---@return string mode Which low-level quests stay offered for where their chain leads (the settings'
---shouldShowAnyLeadIns, shouldShowDungeonLeadIns): "any" those leading to any quest in the player's range, "dungeon"
---those leading to a dungeon's quest in range, "none" not one
function Availability.getLeadInMode()
    local settings = ns.settings
    if settings.shouldShowAnyLeadIns == true then
        return "any"
    end
    return settings.shouldShowDungeonLeadIns == false and "none" or "dungeon"
end

---@return boolean isInstance A quest for a dungeon or a raid: so filed or so labelled, or its work is inside one
---(not index.forDungeon, which holds whole chains: the steps before and after a dungeon's quest too)
local instanceQuests = {} -- [questId] = isInstanceQuest's answer: the database's, it stands (the spawns are dear to read)
local function isInstanceQuest(questId)
    local known = instanceQuests[questId]
    if known == nil then
        known = Availability.isDungeon(questId)
            or Availability.isRaid(questId)
            or (
                Availability.isForRun(questId)
                and (ns.Location.getQuestDungeonId(questId) or ns.Location.getObjectivesDungeonId(questId)) ~= nil
            )
        instanceQuests[questId] = known
    end
    return known
end

---Where a quest far below the player leads: the first quest further on in its chain that is not, following
---every follow-up, forks too. A low start of a chain that climbs into the player's range is worth doing.
---@param kind string? "dungeon": only a dungeon's (or a raid's) quest counts, the steps before it passed through,
---low or not; "any" (when left out: as the settings have it, and "any" with none kept): any quest in range
---@return { questId: number, title: string, level: number, stepCount: number }? lead Nil when every step ahead is low too
function Availability.getChainLead(questId, player, kind)
    kind = kind or (Availability.getLeadInMode() == "dungeon" and "dungeon" or "any")
    local cacheKey = questId .. ":" .. player.level .. ":" .. kind
    if chainLeads[cacheKey] ~= nil then
        return chainLeads[cacheKey] or nil
    end
    local isDungeonOnly = kind == "dungeon"
    local lead
    local seen, queue, position = { [questId] = true }, { { questId = questId, depth = 0 } }, 1
    while queue[position] and not lead and position <= MAX_LEAD_STEPS * 4 do
        local current = queue[position]
        position = position + 1
        local nextQuestIds = {}
        local nextInChain = ns.Database.getQuestField(current.questId, "nextQuestInChain") or 0
        if nextInChain ~= 0 then
            nextQuestIds[1] = nextInChain
        end
        for _, followUpQuestId in ipairs(index and index.followUps[current.questId] or {}) do
            nextQuestIds[#nextQuestIds + 1] = followUpQuestId
        end
        for _, nextQuestId in ipairs(nextQuestIds) do
            if not seen[nextQuestId] and current.depth < MAX_LEAD_STEPS then
                seen[nextQuestId] = true
                if
                    isForCharacter(nextQuestId, player)
                    and not isTaken(nextQuestId)
                    and not isBelowPlayer(nextQuestId, player)
                    and (not isDungeonOnly or isInstanceQuest(nextQuestId))
                then
                    lead = {
                        questId = nextQuestId,
                        title = ns.QuestText.getTitle(
                            nextQuestId,
                            ns.Database.getQuestField(nextQuestId, "name") or ("Quest " .. nextQuestId)
                        ),
                        level = ns.Database.getQuestField(nextQuestId, "questLevel") or 0,
                        stepCount = current.depth + 1,
                    }
                    break
                end
                queue[#queue + 1] = { questId = nextQuestId, depth = current.depth + 1 }
            end
        end
    end
    chainLeads[cacheKey] = lead or false
    return lead
end

---Whether a quest is left out as low-level: far below the player, and its chain leads to nothing kept for
---(Availability.getLeadInMode: a dungeon's quest in the player's range, any quest in range, or nothing at all).
function Availability.isLowLevel(questId, player)
    if not isBelowPlayer(questId, player) then
        return false
    end
    return Availability.getLeadInMode() == "none" or Availability.getChainLead(questId, player) == nil
end

---@return table? lead Where a low quest's chain leads, for its row to say: what keeps it offered, or with none kept
---(all low-level quests shown), the first step in range
local function getShownLead(questId, player)
    if not isBelowPlayer(questId, player) then
        return nil
    end
    local mode = Availability.getLeadInMode()
    return Availability.getChainLead(questId, player, mode == "dungeon" and "dungeon" or "any")
        or (mode == "dungeon" and Availability.getChainLead(questId, player, "any"))
        or nil
end

---Everything except the level, which decides between "now" and "soon".
-- Each profession's specializations, as the spells the game teaches for them (game constants, like the skill
-- names): a quest asking for the profession itself as its "specialization" is for those who have not chosen yet
local SPECIALIZATION_SPELLS = {
    [164] = { 9787, 9788 }, -- Blacksmithing: Weaponsmith, Armorsmith
    [165] = { 10656, 10658, 10660 }, -- Leatherworking: Dragonscale, Elemental, Tribal
    [202] = { 20219, 20222 }, -- Engineering: Gnomish, Goblin
}

local function isSpellKnown(spellId)
    return (IsPlayerSpell and IsPlayerSpell(spellId)) or (IsSpellKnown and IsSpellKnown(spellId)) or false
end

local function getSpellName(spellId)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellId)
    return name or (GetSpellInfo and GetSpellInfo(spellId)) or ns.L("a spell")
end

---What a quest's spell and specialization requirements say for the character, read as Questie reads them.
---@return string? state "closed" (it will never be theirs: they know a spell it is not for, or chose their
---specialization), "missing" (a spell or specialization still to learn), nil when met
---@return string? text For "missing": what to learn
local function checkSpellRequirements(questId)
    local get = ns.Database.getQuestField
    local requiredSpell = get(questId, "requiredSpell") or 0
    if requiredSpell < 0 and isSpellKnown(-requiredSpell) then
        return "closed" -- for those who do not know it yet (Camping 101 teaches a profession)
    elseif requiredSpell > 0 and not isSpellKnown(requiredSpell) then
        return "missing", ns.L("Needs %s", getSpellName(requiredSpell))
    end
    local specialization = get(questId, "requiredSpecialization") or 0
    if specialization ~= 0 then
        local choices = SPECIALIZATION_SPELLS[specialization]
        if choices then
            for _, spellId in ipairs(choices) do
                if isSpellKnown(spellId) then
                    return "closed" -- the specialization is chosen: the quests for choosing are done with
                end
            end
        elseif not isSpellKnown(specialization) then
            return "missing", ns.L("Needs %s", getSpellName(specialization))
        end
    end
    return nil
end

-- The rules on other quests (isClosedByOtherQuest, haveEarlierQuestsOpened) read the fields AvailabilityIndex's
-- DEPENDENCY_FIELDS names, so that a quest taken or handed in forgets the answers it bears on: a field read here
-- must be listed there.

---@return boolean isClosed Another quest has closed this one for good: the next step of its chain, or the quest it
---is a breadcrumb for, taken; the other side of its choice taken; or a quest that ends it done (one that disables it,
---or the one it is available only until)
local function isClosedByOtherQuest(questId)
    local get = ns.Database.getQuestField
    local nextQuestId, leadsToQuestId = get(questId, "nextQuestInChain") or 0, get(questId, "breadcrumbForQuestId") or 0
    if (nextQuestId ~= 0 and isTaken(nextQuestId)) or (leadsToQuestId ~= 0 and isTaken(leadsToQuestId)) then
        return true
    end
    for _, exclusiveQuestId in ipairs(get(questId, "exclusiveTo") or {}) do
        if isTaken(exclusiveQuestId) then
            return true
        end
    end
    local disablingQuestId = get(questId, "disabledByQuest") or 0
    if disablingQuestId ~= 0 and isDone(disablingQuestId) then
        return true
    end
    local untilQuestId = get(questId, "availableUntilCompleted") or 0
    return untilQuestId ~= 0 and isDone(untilQuestId)
end

---@return boolean isOpened The quests asked for first are done (any one of preQuestSingle, every one of
---preQuestGroup), the quest it is part of is in the log, and the quest it is available from on is taken or done
local function haveEarlierQuestsOpened(questId)
    local get = ns.Database.getQuestField
    local preQuestSingle, preQuestGroup = get(questId, "preQuestSingle"), get(questId, "preQuestGroup")
    if preQuestSingle and not isAnyDone(preQuestSingle) then
        return false
    end
    if not preQuestSingle and preQuestGroup and not isEveryDone(preQuestGroup) then
        return false
    end
    local parentQuestId = get(questId, "parentQuest") or 0
    if parentQuestId ~= 0 and not ns.QuestState.isInLog(parentQuestId) then
        return false
    end
    local startingQuestId = get(questId, "availableStartingWith") or 0
    return startingQuestId == 0 or isTaken(startingQuestId)
end

---@return boolean isMet The character has the reputation, the skill and the spells the quest asks for
local function meetsCharacterRequirements(questId)
    local get = ns.Database.getQuestField
    if
        not hasReputation(get(questId, "requiredMinRep"), true)
        or not hasReputation(get(questId, "requiredMaxRep"), false)
    then
        return false
    end
    if not hasSkill(get(questId, "requiredSkill")) or checkSpellRequirements(questId) then
        return false
    end
    return not get(questId, "requiredRanks") -- a rare requirement the addon cannot check yet (one quest)
end

local function isEligibleApartFromLevel(questId, player)
    if isTaken(questId) or not isForCharacter(questId, player) then
        return false
    end
    return not isClosedByOtherQuest(questId)
        and haveEarlierQuestsOpened(questId)
        and meetsCharacterRequirements(questId)
end

---@return number level The level a quest asks for. With none in the database (a gap in the data, not "anyone
---may take it") the quest's own level stands in, as Questie does; otherwise level 40 quests would be offered to a
---level 9 character.
local function getRequiredLevel(questId)
    local requiredLevel = ns.Database.getQuestField(questId, "requiredLevel") or 0
    if requiredLevel == 0 then
        requiredLevel = math.max(ns.Database.getQuestField(questId, "questLevel") or 0, 0)
    end
    return requiredLevel
end

---@return number level The level a blocker names: the one the quest asks for, or its own where the database gives
---none (or less than none)
local function getLevelToReach(questId)
    local requiredLevel = ns.Database.getQuestField(questId, "requiredLevel") or 0
    if requiredLevel <= 0 then
        requiredLevel = math.max(ns.Database.getQuestField(questId, "questLevel") or 0, 0)
    end
    return requiredLevel
end

---@return boolean isEligible The player can pick the quest up now
---@return number? availableAtLevel Set instead when only a few levels are missing
local function computeEligible(questId, player)
    if not isEligibleApartFromLevel(questId, player) or isAboveMaxLevel(questId, player) then
        return false
    end
    local requiredLevel = getRequiredLevel(questId)
    if requiredLevel > player.level then
        return false, requiredLevel - player.level <= UPCOMING_LEVELS and requiredLevel or nil
    end
    -- Its giver left it out of what they offered when talked to: the game knows of a condition the data lacks
    if ns.GameOffers.getRefusal(questId) then
        return false
    end
    return true
end

---@return boolean isEligible The player can pick the quest up now
---@return number? availableAtLevel Set instead when only a few levels are missing
function Availability.isEligible(questId, player)
    -- Kept for the character themselves, while the game runs (the tests change the world between two askings)
    if ns.frameNumber == 0 or player.unit ~= "player" then
        return computeEligible(questId, player)
    end
    local known = eligibility[questId]
    if known == nil then
        local isEligible, availableAtLevel = computeEligible(questId, player)
        known = isEligible == true or availableAtLevel or false
        eligibility[questId] = known
    end
    if known == true then
        return true, nil
    end
    return false, known or nil
end

local STANDINGS = { -- the lowest reputation of each standing, highest first
    { 42000, "Exalted" },
    { 21000, "Revered" },
    { 9000, "Honored" },
    { 3000, "Friendly" },
    { 0, "Neutral" },
    { -3000, "Unfriendly" },
    { -6000, "Hostile" },
    { -42000, "Hated" },
}

local function getStandingName(value)
    for _, standing in ipairs(STANDINGS) do
        if value >= standing[1] then
            return standing[2]
        end
    end
    return "Hated"
end

local function getFactionName(factionId)
    local faction = C_Reputation and C_Reputation.GetFactionDataByID and C_Reputation.GetFactionDataByID(factionId)
    if type(faction) == "table" and faction.name then
        return faction.name
    end
    return GetFactionInfoByID and GetFactionInfoByID(factionId) or ns.L("a faction")
end
Availability.getFactionName = getFactionName

---The earlier quest to name as the one still to do: the one in the log first. When any one of them is enough,
---only the character's own count (not the other faction's version, nor another class's), the one they can pick
---up now before the others.
---@return number? questId
---@return number otherCount When any one is enough: how many others would do as well
local function getMissingQuestId(questIds, isAnyEnough)
    local missingQuestId, eligibleQuestId, candidateCount = nil, nil, 0
    local player = isAnyEnough and Availability.getPlayer()
    for _, signedQuestId in ipairs(questIds) do
        local questId = math.abs(signedQuestId)
        if
            not isDoneOrChosenOther(questId)
            and ns.Database.getQuestField(questId, "name")
            and (not player or isForCharacter(questId, player))
        then
            if ns.QuestState.isInLog(questId) then
                return questId, 0
            end
            candidateCount = candidateCount + 1
            missingQuestId = missingQuestId or questId
            if player and not eligibleQuestId and Availability.isEligible(questId, player) then
                eligibleQuestId = questId
            end
        end
    end
    return eligibleQuestId or missingQuestId, math.max(candidateCount - 1, 0)
end

---@return table blocker The quest a blocker names, as "Take ... first", "After ..." or "Finish ... first", without
---the level still to reach
local function composeQuestBlockerFor(questId, isAfter, blockedQuestId)
    local name = ns.Database.getQuestField(questId, "name") or ("quest " .. questId)
    local shownName = ns.QuestText.getTitle(questId, name)
    if name == ns.Database.getQuestField(blockedQuestId, "name") then
        -- "Finish Elixir of Agony first" on Elixir of Agony reads as itself: the step's place in the chain tells
        -- (or, outside a known chain, that it is the step before: the Sparklematic 5200!'s two steps)
        local stepIndex, total = ns.Chain.getStep(questId)
        local title = ns.QuestText.getTitle(questId, name)
        shownName = stepIndex and string.format("%s %d/%d", title, stepIndex, total)
            or ns.L("%s (the step before)", title)
    end
    local key = ns.QuestState.isInLog(questId) and "Finish %s first" or isAfter and "After %s" or "Take %s first"
    return {
        kind = "quest",
        questId = questId,
        name = shownName,
        text = ns.L(key, shownName),
        phrase = phrase(key, { questId = questId }),
    }
end

---@param blockedQuestId number The quest waiting for it: when both have one name, the step says which it is
local function composeQuestBlocker(questId, isAfter, blockedQuestId)
    local blocker = composeQuestBlockerFor(questId, isAfter, blockedQuestId)
    -- A level still to reach as well says so: a level 60 quest after a chain step is far off, not one step away
    local player = Availability.getPlayer()
    local requiredLevel = getLevelToReach(blockedQuestId)
    if player.level and requiredLevel > player.level then
        blocker.level = requiredLevel
        blocker.text = ns.L("%s · needs level %d", blocker.text, requiredLevel)
    end
    return blocker
end

---Why a quest the character could do one day cannot be picked up yet: a level to reach, a quest to do first,
---a reputation or a profession to raise.
---@return { kind: string, text: string, questId: number?, name: string?, level: number? }? blocker Nil when the quest can
---be picked up now, or will never be
---@return boolean isClosed It will never be: another quest of its choice was taken, the player is past it, or
---it is not meant for them
function Availability.getBlocker(questId, player)
    -- Kept for the character themselves while who can pick up what stands as it was (changeCount): a zone's list
    -- of quests not yet to be had asks this of every quest of the zone, and of each one's chain back to its
    -- start, at every drawing. (The table is shared: to read, not to change.)
    if ns.frameNumber == 0 or player.unit ~= "player" then
        return computeBlocker(questId, player)
    end
    if blockersAt ~= changeCount then
        blockers, blockersAt = {}, changeCount
    end
    local known = blockers[questId]
    if not known then
        local blocker, isClosed = computeBlocker(questId, player)
        known = { blocker or false, isClosed }
        blockers[questId] = known
    end
    return known[1] or nil, known[2]
end

---The earlier quest a quest waits for: one asked for first (any one of preQuestSingle, or every one of
---preQuestGroup), or the quest it is part of, not in the log.
---@return table? blocker
---@return boolean? isClosed None of the quests of which any one is enough is for this character: neither is this one
local function getEarlierQuestBlocker(questId)
    local get = ns.Database.getQuestField
    local preQuestSingle, preQuestGroup = get(questId, "preQuestSingle"), get(questId, "preQuestGroup")
    if preQuestSingle and not isAnyDone(preQuestSingle) then
        local missingQuestId, otherCount = getMissingQuestId(preQuestSingle, true)
        if not missingQuestId then
            return nil, true
        end
        local blocker = composeQuestBlocker(missingQuestId, true, questId)
        if otherCount > 0 then
            -- Any one is enough: say so, or the player does them all
            blocker.text = blocker.text .. ns.Lp(otherCount, " (or %d other)", " (or any of %d others)")
        end
        return blocker
    end
    if not preQuestSingle and preQuestGroup and not isEveryDone(preQuestGroup) then
        local missingQuestId = getMissingQuestId(preQuestGroup, false)
        if missingQuestId then
            return composeQuestBlocker(missingQuestId, true, questId)
        end
    end
    local parentQuestId = get(questId, "parentQuest") or 0
    if parentQuestId ~= 0 and not ns.QuestState.isInLog(parentQuestId) then
        return composeQuestBlocker(parentQuestId, false, questId)
    end
    return nil
end

---What else a quest waits for, besides its earlier quests and the level: a reputation, a profession, the quest
---it is available from on, a spell, a requirement the addon cannot check, or its giver's refusal.
---@param spellState string? checkSpellRequirements' answer, and its text
---@return table? blocker
local function getRequirementBlocker(questId, spellState, spellText)
    local get = ns.Database.getQuestField
    local minReputation = get(questId, "requiredMinRep")
    if not hasReputation(minReputation, true) then
        return {
            kind = "reputation",
            text = ns.L("Needs %s with %s", getStandingName(minReputation[2]), getFactionName(minReputation[1])),
        }
    end
    local skill = get(questId, "requiredSkill")
    if not hasSkill(skill) then
        local skillName = ns.Crafting.getProfessionName(skill[1]) or ns.L("a profession")
        return {
            kind = "skill",
            text = (skill[2] or 0) > 0 and ns.L("Needs %s %s", skillName, skill[2]) or ns.L("Needs %s", skillName),
        }
    end
    local startingQuestId = get(questId, "availableStartingWith") or 0
    if startingQuestId ~= 0 and not isTaken(startingQuestId) then
        return composeQuestBlocker(startingQuestId, false, questId)
    end
    if spellState == "missing" then
        return { kind = "spell", text = spellText }
    end
    if get(questId, "requiredRanks") then
        return { kind = "other", text = ns.L("Has a requirement the addon cannot check") }
    end
    local refusal = ns.GameOffers.getRefusal(questId)
    if refusal then
        local npcName = refusal.npcName or ns.L("the quest giver")
        return {
            kind = "refused",
            text = ns.L("Not offered by %s when you asked", npcName),
            phrase = phrase("Not offered by %s when you asked", npcName),
        }
    end
    return nil
end

---With nothing else in the way: the level still to reach, or nothing when the quest can be picked up now.
---@return table? blocker
---@return boolean? isClosed false when it can be picked up
local function getLevelBlocker(questId, player)
    local isEligible, availableAtLevel = Availability.isEligible(questId, player)
    if isEligible then
        return nil, false
    end
    local requiredLevel = availableAtLevel or getLevelToReach(questId)
    return {
        kind = "level",
        level = requiredLevel,
        text = ns.L("Needs level %d", requiredLevel),
        phrase = phrase("Needs level %d", requiredLevel),
    }
end

computeBlocker = function(questId, player)
    if isTaken(questId) or not isForCharacter(questId, player) or isClosedByOtherQuest(questId) then
        return nil, true
    end
    local spellState, spellText = checkSpellRequirements(questId)
    if
        spellState == "closed"
        or not hasReputation(ns.Database.getQuestField(questId, "requiredMaxRep"), false)
        or isAboveMaxLevel(questId, player)
    then
        return nil, true
    end
    local blocker, isClosed = getEarlierQuestBlocker(questId)
    if blocker or isClosed then
        return blocker, isClosed
    end
    blocker = getRequirementBlocker(questId, spellState, spellText)
    if blocker then
        return blocker
    end
    return getLevelBlocker(questId, player)
end

---Why a character cannot take a quest, judged by what anyone can see of them: race, class and level. Whether
---they did it already or still need an earlier quest only their own game knows.
---@param player { level: number, raceMask: number?, classMask: number? } From Availability.getPlayer
---@return string? reason Nil when nothing seen rules them out
---@return string? shortReason The same in a word or two, for a narrow column
function Availability.getUnmetRequirement(questId, player)
    if not isRaceAllowed(questId, player) then
        return ns.L("Not for this race"), ns.L("race"), phrase("Not for this race"), phrase("race")
    end
    if not isClassAllowed(questId, player) then
        return ns.L("Not for this class"), ns.L("class"), phrase("Not for this class"), phrase("class")
    end
    if isAboveMaxLevel(questId, player) then
        local requiredMaxLevel = ns.Database.getQuestField(questId, "requiredMaxLevel")
        return ns.L("Level %d, the quest is for level %d and below", player.level, requiredMaxLevel),
            ns.L("too high"),
            phrase("Level %d, the quest is for level %d and below", player.level, requiredMaxLevel),
            phrase("too high")
    end
    local requiredLevel = getRequiredLevel(questId)
    if requiredLevel > player.level then
        return ns.L("Level %d, the quest needs %d", player.level, requiredLevel),
            ns.L("lvl %d", requiredLevel),
            phrase("Level %d, the quest needs %d", player.level, requiredLevel),
            phrase("lvl %d", requiredLevel)
    end
    return nil
end

local BLOCKER_SHORT_REASONS =
    { quest = "earlier", level = "level", reputation = "rep", skill = "skill", spell = "spell" }

---What the player is to a quest, as a party member asking about it is told: on it, done it, can take it, or
---cannot and why.
---@return string state "has", "done", "can" or "cannot"
---@return string? reason, string? shortReason Why not, when they cannot
function Availability.getOwnStatus(questId)
    if ns.QuestState.isInLog(questId) then
        return "has"
    end
    if isDone(questId) then
        return "done"
    end
    local player = Availability.getPlayer()
    local reason, shortReason, reasonPhrase, shortPhrase = Availability.getUnmetRequirement(questId, player)
    if reason then
        return "cannot", reason, shortReason, reasonPhrase, shortPhrase
    end
    local blocker, isClosed = Availability.getBlocker(questId, player)
    if blocker then
        local shortKey = BLOCKER_SHORT_REASONS[blocker.kind] or "not yet"
        if blocker.kind == "level" then
            return "cannot",
                blocker.text,
                ns.L("lvl %d", blocker.level),
                blocker.phrase,
                phrase("lvl %d", blocker.level)
        end
        return "cannot", blocker.text, ns.L(shortKey), blocker.phrase, phrase(shortKey)
    end
    if isClosed then
        return "cannot",
            ns.L("Can't take it any more"),
            ns.L("closed"),
            phrase("Can't take it any more"),
            phrase("closed")
    end
    return "can"
end

---Follows a quest's earlier quests back to the one to start with: the first of its chain the character can
---pick up now, or a few levels from now.
---@return number? questId Nil when the quest itself is that one, or the chain cannot be followed
function Availability.getChainStart(questId, player)
    local startQuestId, blocker = nil, Availability.getBlocker(questId, player)
    for _ = 1, 15 do
        if not blocker or blocker.kind ~= "quest" or ns.QuestState.isInLog(blocker.questId) then
            break
        end
        startQuestId = blocker.questId
        blocker = Availability.getBlocker(startQuestId, player)
    end
    return startQuestId
end

---@return boolean isAtEntrance The zone holds the quest only because the dungeon it is picked up in opens there
local function isAtEntranceOnly(zoneId, questId)
    local questIds = index and index.atEntrance and index.atEntrance[zoneId]
    return questIds ~= nil and questIds[questId] ~= nil
end

---The index is made (AvailabilityIndex.build): it is the one read from now on, and whoever waited for it is told.
local function handleIndexBuilt(newIndex)
    index, isIndexing = newIndex, false
    -- Who can pick up what, as far as it was asked before the index was there, is asked again: from here on the
    -- index says what each answer follows, and where the character stands now is noted
    eligibility, chainLeads = {}, {}
    changeCount = changeCount + 1
    settleCharacterChanges(true)
    startWarmUp()
    local callbacks = readyCallbacks
    readyCallbacks = {}
    for _, callback in ipairs(callbacks) do
        callback()
    end
    -- What each quest in the log unlocks is read off the index (Chain.getUnlockedQuestIds): entries composed
    -- before it was there are composed again, and the tracker and the log drawn with them
    ns.Model.forgetEntries()
    ns.queueRefresh()
end

---Builds the zone index a few hundred quests at a time, so the game never stalls (AvailabilityIndex).
---@param handleReady fun()? Called once the index exists
function Availability.prepare(handleReady)
    if index then
        if handleReady then
            handleReady()
        end
        return
    end
    -- (each caller once: a window drawn again and again while the index is made asks every time)
    for _, queued in ipairs(readyCallbacks) do
        if queued == handleReady then
            handleReady = nil
        end
    end
    readyCallbacks[#readyCallbacks + 1] = handleReady
    if isIndexing then
        return
    end
    isIndexing = true
    ns.AvailabilityIndex.build(handleIndexBuilt)
end

---@return boolean isShown This addon marks quests to pick up on the map and minimap. When it does not, the game's own
---marks for them stay visible.
function Availability.isShownOnMap()
    return ns.settings.shouldUseAvailableQuests == true and ns.settings.shouldShowAvailableOnMap == true
end

function Availability.isReady()
    return index ~= nil
end

---@class AvailableQuest
---@field questId number
---@field title string
---@field level number
---@field availableAtLevel number? Set when the player is a few levels short
---@field blocker table? Set for a quest listed though it cannot be picked up yet: why (Availability.getBlocker)
---@field isLowLevel boolean
---@field leadsTo table? For a quest far below the player that is listed all the same: the step of its chain worth it (Availability.getChainLead)
---@field startType string "npc", "object" or "item"
---@field starterName string?
---@field itemName string? The item that starts the quest
---@field isHandedInHere boolean The quest starts from an item found elsewhere and is handed in in this zone
---@field finisherName string?
---@field places table[] Where to go in this zone: the giver, the item's source, or the hand-in
---@field sourceZoneName string? For item quests, where the item is found
---@field sourceZoneId number? That zone
---@field dungeonStepTitle string? In a dungeon's list: the quest further along this one's chain that goes in
---@field leadsToDungeonName string? In a zone's list: the dungeon the quest is for, or whose chain it begins
---@field distance number?
---@field direction string?

---@return boolean isListed The quest goes on a list: it can be picked up (or the game offers it), it is a few
---levels off, or it is listed with what holds it back
---@return number? availableAtLevel The level it comes at, when only a few levels are missing
local function getListing(questId, player, isOfferedByGame, blocker)
    local isEligible, availableAtLevel = Availability.isEligible(questId, player)
    if isOfferedByGame then
        isEligible, availableAtLevel = true, nil
    end
    if blocker then
        return true, nil
    end
    return isEligible or availableAtLevel ~= nil, availableAtLevel
end

---@return boolean isOutOfReach A quest started by an item is not to be listed: the item drops anywhere and is not in
---the bags (there is nowhere to send the player until it is, and then the quest shows where it is handed in), or
---the quest is far above the player (the database often asks no level for these, a level 60 Craftsman's Writ "from
---level 1", but the item comes from places and work far beyond them)
local function isItemStartOutOfReach(questId, itemSource, player, isOfferedByGame)
    local hasItem = ns.QuestState.getItemCount(itemSource.itemId) ~= 0
    if itemSource.isWorldDrop and not hasItem then
        return true
    end
    local questLevel = ns.Database.getQuestField(questId, "questLevel") or 0
    return not isOfferedByGame and questLevel > player.level + MAX_ITEM_LEVELS_ABOVE and not hasItem
end

---@return table? place The first place the quest is handed in at that is on a map
local function getFirstFinisherPlace(finisherPlaces)
    for _, place in ipairs(finisherPlaces) do
        if place.x >= 0 then
            return place
        end
    end
    return nil
end

---@return number count The quest's versions the character could take, itself among them: the others of its
---choice of the same name (one at each machine). Only the character's own: the other faction's trainer, or another
---class's, is no choice of theirs.
local function countVersions(questId, englishTitle, player)
    local count = 1
    for _, otherQuestId in ipairs(ns.Database.getQuestField(questId, "exclusiveTo") or {}) do
        if ns.Database.getQuestField(otherQuestId, "name") == englishTitle and isForCharacter(otherQuestId, player) then
            count = count + 1
        end
    end
    return count
end

---@return string? text Said on its row: "2 steps, back to back", "any of 3 places" (one machine of three, one
---trainer of four)
local function composeStepsText(quest)
    local stepsParts = {}
    if #quest.instantStepIds > 0 then
        stepsParts[#stepsParts + 1] =
            ns.Lp(#quest.instantStepIds + 1, "%d step, back to back", "%d steps, back to back")
    end
    if quest.versionCount > 1 then
        stepsParts[#stepsParts + 1] = quest.startType == "npc" and ns.L("any of %d givers", quest.versionCount)
            or ns.L("any of %d places", quest.versionCount)
    end
    return #stepsParts > 0 and table.concat(stepsParts, " · ") or nil
end

---The fields of a quest started by an item: the item, the creature named as its source, the zone it is found in.
local function addItemSource(quest, itemSource)
    quest.startType = "item"
    -- Named by the creature worth hunting for it (Drops), else the database's first source
    quest.starterName = (ns.Drops.getHuntedSource(itemSource.itemId) or {}).name
        or itemSource.sourceName
        or quest.starterName
    quest.itemName, quest.itemId = itemSource.itemName, itemSource.itemId
    quest.isItemInBags = itemSource.isWorldDrop -- a world drop is listed only once looted
    if itemSource.places[1] then
        quest.sourceZoneId = itemSource.places[1].groupZoneId
        quest.sourceZoneName = ns.Database.getZoneName(quest.sourceZoneId)
    end
end

---@param isOfferedByGame boolean? The game itself offers the quest, so it is available whatever the rules say
---@param blocker table? Why the quest cannot be picked up yet (Availability.getBlocker), to list it all the same
local function composeQuest(questId, zoneId, isHandedInHere, player, position, isOfferedByGame, blocker)
    local isListed, availableAtLevel = getListing(questId, player, isOfferedByGame, blocker)
    if not isListed then
        return nil
    end
    local starterPlaces, starterName, startType = ns.Location.getStarterPlaces(questId)
    local itemSource = #starterPlaces == 0 and ns.Location.getStartItemSource(questId) or nil
    if itemSource and isItemStartOutOfReach(questId, itemSource, player, isOfferedByGame) then
        return nil
    end
    local finisherPlaces, finisherName = ns.Location.getFinisherPlaces(questId)
    local allPlaces = isHandedInHere and finisherPlaces or itemSource and itemSource.places or starterPlaces
    local englishTitle = ns.Database.getQuestField(questId, "name") or ("Quest " .. questId)
    local quest = {
        questId = questId,
        title = ns.QuestText.getTitle(questId, englishTitle), -- as shown: translated, when a translation addon has it
        englishTitle = englishTitle,
        level = ns.Database.getQuestField(questId, "questLevel") or 0,
        availableAtLevel = availableAtLevel,
        blocker = blocker,
        isLowLevel = Availability.isLowLevel(questId, player),
        leadsTo = getShownLead(questId, player),
        startType = startType or "npc",
        starterName = starterName,
        isHandedInHere = isHandedInHere,
        finisherName = finisherName,
        places = ns.Location.getPlacesInZone(allPlaces, zoneId),
        isItemInBags = false,
    }
    if itemSource then
        addItemSource(quest, itemSource)
    end
    if #quest.places == 0 and not isHandedInHere and ns.Database.getDungeon(zoneId) then
        -- Listed under its dungeon though it starts outside: the giver is the place to go, wherever that is
        quest.places = allPlaces
    end
    quest.finisherPlace = getFirstFinisherPlace(finisherPlaces)
    quest.chainIndex, quest.chainTotal = ns.Chain.getStep(questId)
    quest.unlockIds, quest.requiredIds = ns.Chain.getUnlockedQuestIds(questId), ns.Chain.getRequiredQuestIds(questId)
    quest.instantStepIds = Availability.getInstantSteps(questId)
    quest.versionCount = countVersions(questId, englishTitle, player)
    quest.stepsText = composeStepsText(quest)
    if quest.level <= 0 then
        quest.level = player.level
    end
    quest.distance, quest.direction, quest.nearestPlace =
        ns.Geometry.getNearest(quest.places, position, ns.Database.getUiMapId)
    return quest
end

---A quest the game offers that the lists missed: as the database knows it, where it does, and otherwise from
---what the game says, its name and the place of its "!".
---@param wasConsidered boolean The lists had the quest but their rules left it out
---@return AvailableQuest? quest Nil for a quest the player's own choices leave out (isLeftOutBySettings): one they
---hid, or of a kind they turned off. The game's word overrules the data, not the player.
---@return string reason Why the lists missed it, for the player's report
local function composeGameOffer(offer, zoneId, player, position, wasConsidered)
    local questId = offer.questId
    local isKnown = ns.Database.getQuestField(questId, "name") ~= nil
    if isLeftOutBySettings(questId) then
        return nil, ""
    end
    local quest = isKnown and composeQuest(questId, zoneId, false, player, position, true) or nil
    if not quest then
        local englishTitle = offer.title
            or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId))
            or ("Quest " .. questId)
        quest = {
            questId = questId,
            title = ns.QuestText.getTitle(questId, englishTitle),
            englishTitle = englishTitle,
            level = player.level,
            startType = "npc",
            isHandedInHere = false,
            places = {},
        }
    end
    if #quest.places == 0 then
        quest.places = { { zoneId = zoneId, groupZoneId = zoneId, x = offer.x * 100, y = offer.y * 100 } }
    end
    quest.isLowLevel = quest.isLowLevel or offer.isTrivial
    quest.isFromGame = true
    quest.distance, quest.direction, quest.nearestPlace =
        ns.Geometry.getNearest(quest.places, position, ns.Database.getUiMapId)
    local reason = not isKnown and "not in the quest database"
        or wasConsidered and "the addon's rules said it was not available"
        or "the quest database starts it in another place"
    if offer.npcName then
        reason = reason .. "; offered by " .. offer.npcName .. " when talked to"
    end
    return quest, reason
end

local function isBefore(first, second)
    if (first.availableAtLevel ~= nil) ~= (second.availableAtLevel ~= nil) then
        return first.availableAtLevel == nil
    end
    if first.distance and second.distance and first.distance ~= second.distance then
        return first.distance < second.distance
    end
    if (first.distance ~= nil) ~= (second.distance ~= nil) then
        return first.distance ~= nil
    end
    if first.level ~= second.level then
        return first.level < second.level
    end
    return first.title < second.title
end

---@return table? cached The list kept under that key, when worked out less than CACHE_SECONDS ago
local function getCachedList(cacheKey, now)
    local cached = cache[cacheKey]
    if cached and now - cached.time < CACHE_SECONDS then
        return cached
    end
    return nil
end

---@return table list A zone's list being made (Availability.getQuests, getBlockedQuests): the quests shown, how many
---low-level ones were left out, and what was looked at already
local function createList(zoneId, shouldShowLowLevel)
    return {
        zoneId = zoneId,
        shouldShowLowLevel = shouldShowLowLevel,
        player = Availability.getPlayer(),
        position = ns.Geometry.getPlayerPosition(),
        quests = {},
        hiddenCount = 0,
        seen = {}, -- [questId] = true: looked at, from any of the zone's lists
        listed = {}, -- [questId] = true: put forward, shown or hidden as low-level
    }
end

---Puts a quest composed for a list on it, or counts it among the low-level ones left out.
local function addToList(list, quest)
    if quest.isLowLevel and not list.shouldShowLowLevel then
        list.hiddenCount = list.hiddenCount + 1
    else
        list.quests[#list.quests + 1] = quest
    end
end

---Adds the quests of one of the index's lists of the zone that can be picked up (or come in a few levels).
local function addIndexedQuests(list, questIds, isHandedInHere)
    for _, questId in ipairs(questIds or {}) do
        if not list.seen[questId] and (list.shouldIncludeEntrances or not isAtEntranceOnly(list.zoneId, questId)) then
            list.seen[questId] = true
            local quest = composeQuest(questId, list.zoneId, isHandedInHere, list.player, list.position)
            list.listed[questId] = quest ~= nil or nil
            if quest then
                ns.QuestState.checkExists(questId) -- the game asked, once, whether it has it at all
                addToList(list, quest)
            end
        end
    end
end

---@return boolean isGone A giver's offer learnt by talking to them that something has closed since: another quest of
---its choice taken, the player past its level. It was theirs then and is not any more. (Closed already when
---offered, the data has a hole there, and the giver's word stands.)
local function isLearnedOfferClosedSince(offer, player)
    return offer.isLearned
        and not offer.wasClosed
        and not isLeftOutBySettings(offer.questId)
        and select(2, Availability.getBlocker(offer.questId, player)) == true
end

---What the game itself offers here and the lists missed is added on its word, and noted, so the hole can be fixed:
---a quest the database does not have, or one its rules wrongly held back.
local function addGameOffers(list)
    for _, offer in ipairs(ns.GameOffers.get(list.zoneId)) do
        local questId = offer.questId
        if not list.listed[questId] and not isTaken(questId) and not isDone(questId) then
            list.listed[questId] = true
            local quest, reason
            if isLearnedOfferClosedSince(offer, list.player) then
                ns.GameOffers.forgetLearned(questId) -- neither listed nor noted as missed
            else
                quest, reason =
                    composeGameOffer(offer, list.zoneId, list.player, list.position, list.seen[questId] == true)
            end
            if quest then
                ns.GameOffers.noteMissed(questId, quest.englishTitle or quest.title, list.zoneId, reason, offer)
                addToList(list, quest)
            end
        end
    end
end

---In a zone's list, a quest for a dungeon (picked up here, or a lead-in to its chain) says which; in a dungeon's
---list, a quest that only leads there names the quest of its chain that goes in.
local function nameDungeons(quests, zoneId)
    if not ns.Database.getDungeon(zoneId) then
        for _, quest in ipairs(quests) do
            local dungeon =
                ns.Database.getDungeon(index.dungeonByQuestId and index.dungeonByQuestId[quest.questId] or 0)
            quest.leadsToDungeonName = dungeon and dungeon.name or nil
        end
    end
    local steps = index.dungeonSteps and index.dungeonSteps[zoneId]
    for _, quest in ipairs(steps and quests or {}) do
        local stepQuestId = steps[quest.questId]
        if stepQuestId and stepQuestId ~= quest.questId then
            quest.dungeonStepTitle = ns.QuestText.getTitle(stepQuestId, ns.Database.getQuestField(stepQuestId, "name"))
        end
    end
end

---Versions of one quest (one at each machine) are one row: the first, the nearest. Either one naming the other is
---enough (the database does not always name them both ways), and a quest is one row however it came in.
---@param quests AvailableQuest[] Sorted
---@return AvailableQuest[] rows
local function mergeVersions(quests)
    local isVersionListed, rows, rowQuestIds = {}, {}, {}
    for _, quest in ipairs(quests) do
        local name = quest.englishTitle or quest.title
        local exclusiveTo = ns.Database.getQuestField(quest.questId, "exclusiveTo") or {}
        local isListedAlready = isVersionListed[quest.questId] == true
        for _, otherQuestId in ipairs(exclusiveTo) do
            isListedAlready = isListedAlready
                or (rowQuestIds[otherQuestId] == true and ns.Database.getQuestField(otherQuestId, "name") == name)
        end
        if not isListedAlready then
            rows[#rows + 1] = quest
            rowQuestIds[quest.questId] = true
            isVersionListed[quest.questId] = true
            for _, otherQuestId in ipairs(exclusiveTo) do
                if ns.Database.getQuestField(otherQuestId, "name") == name then
                    isVersionListed[otherQuestId] = true
                end
            end
        end
    end
    return rows
end

---Quests to pick up in a zone, nearest first, then the ones a few levels away.
---@param options { shouldShowLowLevel: boolean?, shouldIncludeEntrances: boolean? }?
---@return AvailableQuest[] quests Empty until the index is ready
---@return number hiddenCount Low-level quests left out
function Availability.getQuests(zoneId, options)
    if not index or not zoneId then
        return {}, 0
    end
    local shouldShowLowLevel = options and options.shouldShowLowLevel
    local shouldIncludeEntrances = options and options.shouldIncludeEntrances
    local cacheKey = zoneId .. (shouldShowLowLevel and ":all" or "") .. (shouldIncludeEntrances and ":entrances" or "")
    local now = GetTime and GetTime() or 0
    local cached = getCachedList(cacheKey, now)
    if cached then
        return cached.quests, cached.hiddenCount
    end
    local list = createList(zoneId, shouldShowLowLevel)
    list.shouldIncludeEntrances = shouldIncludeEntrances
    addIndexedQuests(list, index.startedInZone[zoneId], false)
    addIndexedQuests(list, index.forDungeon[zoneId], false)
    addIndexedQuests(list, index.handedInZone[zoneId], true)
    addGameOffers(list)
    nameDungeons(list.quests, zoneId)
    table.sort(list.quests, isBefore)
    local quests = mergeVersions(list.quests)
    cache[cacheKey] = { quests = quests, hiddenCount = list.hiddenCount, time = now }
    return quests, list.hiddenCount
end

---Quests that start in a zone but cannot be picked up yet, each with why: a level still to reach (more than a
---few levels away; nearer ones are among the quests to pick up), an earlier quest, a reputation, a profession.
local UNLOCK_RANK_LEVEL, UNLOCK_RANK_OTHER = 100, 200

---What stands between the character and a quest they cannot take yet, said as what to do: "Needs Harpy Raiders
---first: you can take it now", "2 quests first, from Harpy Raiders: in your log", or the blocker's own words (a
---level, a reputation, a profession).
---@return string text
---@return number rank How near it is to unlocking, smaller is nearer: the quests to do first (half a step more
---when the first of them cannot be taken yet either), then levels to go, then anything else
function Availability.describeUnlock(questId, blocker, player)
    if blocker.kind == "quest" then
        local leadInIds = Availability.getLeadIns(questId, player)
        local firstQuestId = leadInIds[1] or blocker.questId
        local firstName = ns.QuestText.getQuestName(firstQuestId)
            or ns.Database.getQuestField(firstQuestId, "name")
            or ("Quest " .. firstQuestId)
        local state, extra = nil, 0.5
        if ns.QuestState.isInLog(firstQuestId) then
            state, extra = ns.L("in your log"), 0
        elseif not Availability.getBlocker(firstQuestId, player) then
            state, extra = ns.L("you can take it now"), 0
        end
        local text = #leadInIds > 1 and ns.L("%d quests first, from %s", #leadInIds, firstName)
            or ns.L("Needs %s first", firstName)
        return state and (text .. ": " .. state) or text, math.max(#leadInIds, 1) + extra
    elseif blocker.kind == "level" then
        return blocker.text .. " \194\183 " .. ns.L("you are %d", player.level),
            UNLOCK_RANK_LEVEL + math.max((blocker.level or 0) - player.level, 0)
    end
    return blocker.text, UNLOCK_RANK_OTHER
end

---What a quest that cannot be taken yet waits for, as the thing to do about it: the quest at the start of what
---leads to it when that one is in the log ("log") or can be picked up now ("take"), a level to reach ("level"),
---or anything else ("other": a reputation, a profession, a quest that is itself out of reach). The Available list
---groups the quests not yet to be had by it.
---@return { kind: "log"|"take"|"level"|"other", questId: number?, level: number?, text: string?, stepCount: number } root
function Availability.getUnlockRoot(questId, blocker, player)
    if blocker.kind == "level" then
        return { kind = "level", level = blocker.level, stepCount = 0 }
    elseif blocker.kind ~= "quest" then
        return { kind = "other", text = blocker.text, stepCount = 0 }
    end
    local leadInIds = Availability.getLeadIns(questId, player)
    local firstQuestId = leadInIds[1] or blocker.questId
    local stepCount = math.max(#leadInIds, 1)
    if ns.QuestState.isInLog(firstQuestId) then
        return { kind = "log", questId = firstQuestId, stepCount = stepCount }
    end
    local firstBlocker = Availability.getBlocker(firstQuestId, player)
    if not firstBlocker then
        return { kind = "take", questId = firstQuestId, stepCount = stepCount }
    elseif firstBlocker.kind == "level" then
        return { kind = "level", level = firstBlocker.level, stepCount = stepCount }
    end
    return { kind = "other", text = firstBlocker.text, stepCount = stepCount }
end

---@param kind "quest"|"dungeon" What the words would name: a quest of the story, or a dungeon
---@return boolean isHidden The Spoilers choice keeps that back (chains not shown whole, or dungeons not shown): a reason
---or a lead that names one says only "Later in the story". Always false in Guide.
function Availability.isLaterHidden(kind)
    if not ns.Spoilers.isActive() then
        return false
    end
    if kind == "dungeon" then
        return ns.Spoilers.getChoice("dungeons") ~= "shown"
    end
    return ns.Spoilers.getChoice("chains") ~= "all"
end

---Why a quest cannot be taken yet, as it may be told: its blocker's words (or the text given, describeUnlock's), or,
---where they name an earlier quest the Spoilers choice keeps back, "Later in the story" (with the level still to
---reach, when there is one).
---@param text string? The words to show when nothing is held back; the blocker's own by default
---@return string text
function Availability.getShownReason(blocker, text)
    text = text or blocker.text
    if blocker.kind ~= "quest" or not Availability.isLaterHidden("quest") then
        return text
    end
    if blocker.level then
        return ns.L("%s · needs level %d", ns.L("Later in the story"), blocker.level)
    end
    return ns.L("Later in the story")
end

---@return boolean isShownElsewhere A quest held back that is listed with another: a level only a few away (it is
---among the quests to pick up), or a step done straight after the one before (part of that one's row)
local function isBlockedShownElsewhere(questId, blocker, player)
    if blocker.kind == "level" then
        return blocker.level - player.level <= UPCOMING_LEVELS
    end
    return blocker.kind == "quest"
        and Availability.isInstantStep(questId)
        and ns.Database.getQuestField(blocker.questId, "name") == ns.Database.getQuestField(questId, "name")
end

---Adds a quest of the zone that cannot be picked up yet, with how near it is to unlocking.
local function addBlockedQuest(list, questId)
    local player = list.player
    local blocker = Availability.getBlocker(questId, player)
    if not blocker or isBlockedShownElsewhere(questId, blocker, player) then
        return
    end
    local quest = composeQuest(questId, list.zoneId, false, player, list.position, false, blocker)
    if quest then
        quest.unlockText, quest.unlockRank = Availability.describeUnlock(questId, blocker, player)
        quest.unlockRoot = Availability.getUnlockRoot(questId, blocker, player)
        addToList(list, quest)
    end
end

---Nearest to unlocking first: one quest away and takeable now, then further down chains, then levels, the rest.
local function isNearerUnlock(first, second)
    if first.unlockRank ~= second.unlockRank then
        return first.unlockRank < second.unlockRank
    end
    if first.level ~= second.level then
        return first.level < second.level
    end
    return first.title < second.title
end

---Quests the character will never get are left out.
---Quests far below the player are left out as on the quests to pick up, unless asked for, and counted.
---@param options { shouldShowLowLevel: boolean? }?
---@return AvailableQuest[] quests Lowest level first; empty until the index is ready
---@return number hiddenCount Low-level ones left out
function Availability.getBlockedQuests(zoneId, options)
    if not index or not zoneId then
        return {}, 0
    end
    local shouldShowLowLevel = options and options.shouldShowLowLevel
    local cacheKey = "blocked" .. zoneId .. (shouldShowLowLevel and ":all" or "")
    local now = GetTime and GetTime() or 0
    local cached = getCachedList(cacheKey, now)
    if cached then
        return cached.quests, cached.hiddenCount
    end
    local list = createList(zoneId, shouldShowLowLevel)
    for _, questId in ipairs(Availability.getZoneQuestIds(zoneId)) do
        if not list.seen[questId] then
            list.seen[questId] = true
            addBlockedQuest(list, questId)
        end
    end
    table.sort(list.quests, isNearerUnlock)
    cache[cacheKey] = { quests = list.quests, hiddenCount = list.hiddenCount, time = now }
    return list.quests, list.hiddenCount
end

---@return number[]? questIds The quests that need this one first; nil while the index is not built
function Availability.getFollowUps(questId)
    return index and (index.followUps[questId] or {}) or nil
end

local startZoneByQuestId -- built from the index on first use

---@return number? zoneId Where a quest is picked up: its giver's zone, or where its item drops
function Availability.getStartZoneId(questId)
    if not index then
        return nil
    end
    if not startZoneByQuestId then
        startZoneByQuestId = {}
        for zoneId, questIds in pairs(index.startedInZone) do
            for _, listedQuestId in ipairs(questIds) do
                -- A giver inside a dungeon is listed under the dungeon and the zone of its entrance; either leads there
                startZoneByQuestId[listedQuestId] = startZoneByQuestId[listedQuestId] or zoneId
            end
        end
    end
    return startZoneByQuestId[questId]
end

local zoneQuestIds = {} -- [zoneId] = the zone's quests, worked out from the index once
local zoneIdsByQuestId -- the other way round, built on first use

---The quests that belong to a zone, as they are counted: for a zone, those picked up there; for a dungeon,
---those done in it, filed under it or with their work inside, wherever they are given. A giver who merely
---stands in a dungeon, or a chain that only leads to it, does not make a quest the dungeon's: the Available
---tab lists those under the dungeon too, as the way in, but they are not counted for it. The zone summary,
---the "not yet" list and the chronicle all count these.
---@return number[] questIds
function Availability.getZoneQuestIds(zoneId)
    if not index or not zoneId then
        return {}
    end
    if not zoneQuestIds[zoneId] then
        local questIds, seen = {}, {}
        local lists = { index.startedInZone[zoneId] or {} }
        if ns.Database.getDungeon(zoneId) then
            lists = { index.inDungeon[zoneId] or {} }
        end
        for _, list in ipairs(lists) do
            for _, questId in ipairs(list) do
                if not seen[questId] and not isAtEntranceOnly(zoneId, questId) then
                    seen[questId] = true
                    questIds[#questIds + 1] = questId
                end
            end
        end
        zoneQuestIds[zoneId] = questIds
    end
    return zoneQuestIds[zoneId]
end

---A quest the player was seen doing inside a dungeon the database does not know (ns.LearnedDungeons), added
---while playing; the index takes it at once.
function Availability.addLearnedQuest(dungeonId, questId)
    if not index then
        return
    end
    ns.AvailabilityIndex.addToDungeon(index, dungeonId, questId)
    cache, zoneQuestIds, zoneIdsByQuestId = {}, {}, nil
end

---@return number[] questIds The steps done straight after a quest, at the same place, asking nothing; empty for most
function Availability.getInstantSteps(questId)
    local questIds, current = {}, questId
    while index and index.instantStepAfter[current] and #questIds < 10 do
        current = index.instantStepAfter[current]
        questIds[#questIds + 1] = current
    end
    return questIds
end

---@return number? questId The step a back-to-back step goes with (Availability.getInstantSteps), nil for others
function Availability.getInstantStepBefore(questId)
    return index and index.isInstantStep[questId] or nil
end

---@return boolean isInstantStep The quest is such a step (Availability.getInstantSteps): it goes with the one before
function Availability.isInstantStep(questId)
    return index ~= nil and index.isInstantStep[questId] ~= nil
end

---@return { dungeonId: number, name: string, count: number }[] dungeons The dungeons whose entrance is in the zone, with
---how many quests the character can pick up inside each: the zone's list points to them instead of listing those
function Availability.getEntranceDungeons(zoneId)
    local countByDungeonId, player = {}, Availability.getPlayer()
    for questId, dungeonId in pairs(index and index.atEntrance and index.atEntrance[zoneId] or {}) do
        countByDungeonId[dungeonId] = (countByDungeonId[dungeonId] or 0)
            + ((not isTaken(questId) and Availability.isEligible(questId, player)) and 1 or 0)
    end
    local dungeons = {}
    for dungeonId, count in pairs(countByDungeonId) do
        dungeons[#dungeons + 1] = { dungeonId = dungeonId, name = ns.Database.getZoneName(dungeonId), count = count }
    end
    table.sort(dungeons, function(first, second)
        return first.name < second.name
    end)
    return dungeons
end

---@return number[] dungeonIds Every dungeon (raids and battlegrounds among them) with a quest done inside it
function Availability.getDungeonIds()
    local dungeonIds = {}
    for dungeonId in pairs(index and index.inDungeon or {}) do
        dungeonIds[#dungeonIds + 1] = dungeonId
    end
    table.sort(dungeonIds)
    return dungeonIds
end

---@return number[] zoneIds Every zone a quest belongs to (Availability.getZoneQuestIds): where it is picked up,
---and the dungeon it leads to
function Availability.getQuestZoneIds(questId)
    if not index then
        return {}
    end
    if not zoneIdsByQuestId then
        zoneIdsByQuestId = {}
        local zoneIds = {}
        for zoneId in pairs(index.startedInZone) do
            zoneIds[zoneId] = true
        end
        for zoneId in pairs(index.forDungeon) do
            zoneIds[zoneId] = true
        end
        for zoneId in pairs(index.inDungeon) do
            zoneIds[zoneId] = true -- a dungeon whose quests are all given outside has no giver of its own
        end
        for zoneId in pairs(zoneIds) do
            for _, listedQuestId in ipairs(Availability.getZoneQuestIds(zoneId)) do
                zoneIdsByQuestId[listedQuestId] = zoneIdsByQuestId[listedQuestId] or {}
                table.insert(zoneIdsByQuestId[listedQuestId], zoneId)
            end
        end
    end
    return zoneIdsByQuestId[questId] or {}
end

---@class ZoneQuestState
---@field questId number
---@field state string "done", "inLog", "available" or "notYet"
---@field blocker table? For "notYet": why (Availability.getBlocker)
---@field isLowLevel boolean

local STATE_RANKS = { done = 4, inLog = 3, available = 2, notYet = 1 }
local ACTION_RANKS = { inLog = 4, available = 3, notYet = 2, done = 1 } -- the step to do now leads

---Steps done back to back (Availability.getInstantSteps) count once, as one thing to do: the step to do now
---stands for them, and they are done when the last is.
---@param states ZoneQuestState[]
---@return ZoneQuestState[] merged
mergeInstantSteps = function(states)
    -- Each quest's group: the first step it follows straight on from, through the steps' own links, as one of
    -- its versions (the lowest ID of them), so the second step at one machine meets the first at another
    local function getGroupKey(questId)
        local first, hops = questId, 0
        while index.isInstantStep[first] and hops < 10 do
            first, hops = index.isInstantStep[first], hops + 1
        end
        local key, name = first, ns.Database.getQuestField(first, "name")
        for _, otherQuestId in ipairs(ns.Database.getQuestField(first, "exclusiveTo") or {}) do
            if otherQuestId < key and ns.Database.getQuestField(otherQuestId, "name") == name then
                key = otherQuestId
            end
        end
        return key, hops > 0 or index.instantStepAfter[first] ~= nil
    end
    local slotByKey, merged = {}, {}
    for _, entry in ipairs(states) do
        local key, isGrouped = getGroupKey(entry.questId)
        local slot = isGrouped and slotByKey[key]
        if slot then
            if ACTION_RANKS[entry.state] > ACTION_RANKS[merged[slot].state] then
                merged[slot] = entry
            end
        else
            merged[#merged + 1] = entry
            if isGrouped then
                slotByKey[key] = #merged
            end
        end
    end
    return merged
end

---Alternatives of one quest count once: quests of the same name that close each other (the Sparklematic 5200!,
---one at each of three machines). The one furthest along stands for them.
---@param states ZoneQuestState[]
---@return ZoneQuestState[] merged
mergeAlternatives = function(states)
    local merged, slotByQuestId = {}, {}
    for _, entry in ipairs(states) do
        local name = ns.Database.getQuestField(entry.questId, "name")
        local slot
        for _, otherQuestId in ipairs(ns.Database.getQuestField(entry.questId, "exclusiveTo") or {}) do
            if not slot and slotByQuestId[otherQuestId] and ns.Database.getQuestField(otherQuestId, "name") == name then
                slot = slotByQuestId[otherQuestId]
            end
        end
        if slot then
            if STATE_RANKS[entry.state] > STATE_RANKS[merged[slot].state] then
                merged[slot] = entry
            end
        else
            merged[#merged + 1] = entry
            slot = #merged
        end
        slotByQuestId[entry.questId] = slot
    end
    return merged
end

---Each of a zone's quests the character can have, with where they stand on it; quests never to be had (the other
---half of a choice, not their race or class) are left out.
---@return ZoneQuestState[] states
function Availability.getZoneQuestStates(zoneId)
    local cacheKey = "states" .. tostring(zoneId)
    if cache[cacheKey] then
        return cache[cacheKey]
    end
    local player, states = Availability.getPlayer(), {}
    for _, questId in ipairs(Availability.getZoneQuestIds(zoneId)) do
        if isForCharacter(questId, player) then
            local state, blocker
            if ns.QuestState.isTurnedIn(questId) then
                state = "done"
            elseif ns.QuestState.isInLog(questId) then
                state = "inLog"
            elseif Availability.isEligible(questId, player) then
                state = "available"
            else
                blocker = Availability.getBlocker(questId, player)
                state = blocker and "notYet" or nil
            end
            if state then
                states[#states + 1] = {
                    questId = questId,
                    state = state,
                    blocker = blocker,
                    isLowLevel = (state == "available" or state == "notYet")
                        and Availability.isLowLevel(questId, player),
                }
            end
        end
    end
    states = mergeInstantSteps(mergeAlternatives(states))
    cache[cacheKey] = states
    return states
end

---The quests that stand before one, earliest first: each quest its chain needs done before it, back to the first
---the character can pick up now (or has in the log).
---@return number[] questIds Empty when nothing holds the quest back but its own requirements
function Availability.getLeadIns(questId, player)
    local leadInIds, seen = {}, { [questId] = true }
    local blocker = Availability.getBlocker(questId, player)
    while blocker and blocker.kind == "quest" and not seen[blocker.questId] and #leadInIds < 15 do
        seen[blocker.questId] = true
        table.insert(leadInIds, 1, blocker.questId)
        if ns.QuestState.isInLog(blocker.questId) then
            break
        end
        blocker = Availability.getBlocker(blocker.questId, player)
    end
    return leadInIds
end

---@class DungeonRun
---@field inLog table[] Quests in the log: questId, title, level
---@field pickUp AvailableQuest[] To pick up before going in, outside; with lead-ins that can be picked up now
---(isLeadIn, leadsToTitle)
---@field foundInside AvailableQuest[] Picked up on the run itself: a giver inside, or an item that drops inside
---@field behindLeadIn AvailableQuest[] Waiting for a quest of their chain; leadInIds, earliest first
---@field notYet AvailableQuest[] Held back by a level, a reputation or a profession; blocker says which
---@field done table[] Handed in already: questId, title, level, isDone
---@field doneCount number
---@field totalCount number

---@return table row A row of a dungeon run for a quest not composed as one to pick up (done, or in the log): its
---title and level
local function composeRunRow(questId)
    return {
        questId = questId,
        title = ns.QuestText.getTitle(
            questId,
            ns.Database.getQuestField(questId, "name") or ("Quest " .. questId),
            true
        ),
        level = ns.Database.getQuestField(questId, "questLevel") or 0,
    }
end

---A quest of the run that a lead-in opens: the first quest it opens is the one its row names.
local function noteOpens(context, leadInId, title)
    context.opensTitleByQuestId[leadInId] = context.opensTitleByQuestId[leadInId] or title
end

---A quest of the dungeon waiting for a quest of its chain: listed behind its lead-ins, and the first of them listed
---too, to pick up now (or as in the log already), saying what it opens.
local function addBehindLeadIn(run, context, questId, quest)
    local player = context.player
    quest.leadInIds = Availability.getLeadIns(questId, player)
    run.behindLeadIn[#run.behindLeadIn + 1] = quest
    local firstLeadInId = quest.leadInIds[1]
    local lastLeadInId = quest.leadInIds[#quest.leadInIds]
    if lastLeadInId and context.isDungeonQuest[lastLeadInId] then
        quest.isLeadInOnRun = true -- both can be done on one run
        noteOpens(context, lastLeadInId, quest.title)
    end
    if not firstLeadInId then
        return
    end
    -- A lead-in that is itself one of the dungeon's quests is listed once, as that, saying what it opens
    if context.isDungeonQuest[firstLeadInId] then
        noteOpens(context, firstLeadInId, quest.title)
    elseif context.listedLeadIns[firstLeadInId] then
        return
    elseif not isTaken(firstLeadInId) and Availability.isEligible(firstLeadInId, player) then
        -- The lead-in to pick up now, among the quests to pick up before going, saying what it opens
        context.listedLeadIns[firstLeadInId] = true
        local leadIn = composeQuest(firstLeadInId, context.dungeonId, false, player, context.position)
        if leadIn then
            leadIn.isLeadIn, leadIn.leadsToTitle, leadIn.leadsToQuestId = true, quest.title, questId
            run.pickUp[#run.pickUp + 1] = leadIn
        end
    elseif ns.QuestState.isInLog(firstLeadInId) then
        -- The lead-in is in the log already (picked up in another zone): listed with the dungeon too, under the
        -- quest it opens
        context.listedLeadIns[firstLeadInId] = true
        local row = composeRunRow(firstLeadInId)
        row.isLowLevel, row.isLeadIn, row.leadsToTitle, row.leadsToQuestId = false, true, quest.title, questId
        run.inLog[#run.inLog + 1] = row
    end
end

---Puts one of the dungeon's quests in the run's list for where the character stands on it.
---@param zoneQuest ZoneQuestState
local function addRunQuest(run, context, zoneQuest)
    local questId, state = zoneQuest.questId, zoneQuest.state
    if state == "done" then
        local row = composeRunRow(questId)
        row.isDone = true
        run.doneCount = run.doneCount + 1
        run.done[#run.done + 1] = row
    elseif state == "inLog" then
        local row = composeRunRow(questId)
        row.isLowLevel = false
        run.inLog[#run.inLog + 1] = row
    elseif state == "available" then
        local quest = composeQuest(questId, context.dungeonId, false, context.player, context.position)
        if quest then
            local isFoundInside = ns.Location.getPickupDungeonId(questId) == context.dungeonId
                or ns.LearnedDungeons.isPickedUpInside(context.dungeonId, questId)
            local list = isFoundInside and run.foundInside or run.pickUp
            list[#list + 1] = quest
        end
    else
        local blocker = zoneQuest.blocker
        local quest = composeQuest(questId, context.dungeonId, false, context.player, context.position, false, blocker)
        if quest and blocker and blocker.kind == "quest" then
            addBehindLeadIn(run, context, questId, quest)
        elseif quest then
            run.notYet[#run.notYet + 1] = quest
        end
    end
end

local function isLowerLevel(first, second)
    if first.level ~= second.level then
        return first.level < second.level
    end
    return first.title < second.title
end

---Everything one dungeon run can hold for the character: every quest done inside the dungeon (Availability.getZoneQuestIds),
---sorted by what to do about it, and the lead-ins that open the ones behind them. Lead-ins are named as such and
---not counted as the dungeon's quests.
---@return DungeonRun run
function Availability.getDungeonRun(dungeonId)
    local cacheKey = "run" .. tostring(dungeonId)
    if cache[cacheKey] then
        return cache[cacheKey]
    end
    local run = {
        inLog = {},
        pickUp = {},
        foundInside = {},
        behindLeadIn = {},
        notYet = {},
        done = {},
        doneCount = 0,
        totalCount = 0,
    }
    local context = {
        dungeonId = dungeonId,
        player = Availability.getPlayer(),
        position = ns.Geometry.getPlayerPosition(),
        isDungeonQuest = {},
        opensTitleByQuestId = {}, -- [lead-in] = the title of the first quest of the run it opens
        listedLeadIns = {},
    }
    for _, questId in ipairs(Availability.getZoneQuestIds(dungeonId)) do
        context.isDungeonQuest[questId] = true
    end
    for _, zoneQuest in ipairs(Availability.getZoneQuestStates(dungeonId)) do
        run.totalCount = run.totalCount + 1
        addRunQuest(run, context, zoneQuest)
    end
    for _, list in ipairs({ run.inLog, run.pickUp, run.foundInside, run.behindLeadIn, run.notYet, run.done }) do
        table.sort(list, isLowerLevel)
        for _, quest in ipairs(list) do
            quest.opensTitle = context.opensTitleByQuestId[quest.questId]
        end
    end
    cache[cacheKey] = run
    return run
end

---How far the character is through a zone's quests (Availability.getZoneQuestStates, counted).
---Of the quests left, how many are low-level: far below the player, and so is every step they lead to.
---@return { done: number, inLog: number, available: number, notYet: number, lowAvailable: number, lowNotYet: number } summary Zeroes until the index is ready
function Availability.getZoneSummary(zoneId)
    local summary = { done = 0, inLog = 0, available = 0, notYet = 0, lowAvailable = 0, lowNotYet = 0 }
    if not index or not zoneId then
        return summary
    end
    for _, zoneQuest in ipairs(Availability.getZoneQuestStates(zoneId)) do
        summary[zoneQuest.state] = summary[zoneQuest.state] + 1
        if zoneQuest.isLowLevel then
            local lowKey = zoneQuest.state == "available" and "lowAvailable" or "lowNotYet"
            summary[lowKey] = summary[lowKey] + 1
        end
    end
    return summary
end

---@return number? minLevel, number? maxLevel The levels a zone is for: the game's own, as its map shows them
---when the zone is pointed at; for a dungeon, or a zone the map gives none, the levels most of its quests are for, leaving out the odd quarter far
---below or above (class and city quests); nil for a zone without either
function Availability.getZoneLevels(zoneId)
    if not index or not zoneId then
        return nil, nil
    end
    local cacheKey = "levels" .. zoneId
    if cache[cacheKey] then
        return cache[cacheKey][1], cache[cacheKey][2]
    end
    -- A dungeon's levels are its quests': the game's maps give few dungeons a range, and some a wrong one
    local isDungeon = ns.Database.getDungeon(zoneId) ~= nil
    local uiMapId = not isDungeon and ns.Database.getUiMapId(zoneId)
    if uiMapId and C_Map and C_Map.GetMapLevels then
        local isRead, minLevel, maxLevel = pcall(C_Map.GetMapLevels, uiMapId)
        if isRead and type(minLevel) == "number" and minLevel > 0 then
            cache[cacheKey] = { minLevel, math.max(maxLevel or minLevel, minLevel) }
            return cache[cacheKey][1], cache[cacheKey][2]
        end
    end
    local player, levels = Availability.getPlayer(), {}
    for _, questId in ipairs(Availability.getZoneQuestIds(zoneId)) do
        local level = ns.Database.getQuestField(questId, "questLevel") or 0
        if level > 0 and isForCharacter(questId, player) then
            levels[#levels + 1] = level
        end
    end
    if #levels == 0 then
        return nil, nil
    end
    table.sort(levels)
    local minLevel = levels[math.floor(#levels * 0.25) + 1]
    local maxLevel = levels[math.max(math.ceil(#levels * 0.75), 1)]
    cache[cacheKey] = { minLevel, maxLevel }
    return minLevel, maxLevel
end

---Every zone that has something to pick up now, by name.
---@param options { shouldShowLowLevel: boolean? }?
---@return { zoneId: number, zoneName: string, count: number }[] zones Empty until the index is ready
function Availability.getZones(options)
    local zones = {}
    if not index then
        return zones
    end
    local shouldShowLowLevel = options and options.shouldShowLowLevel
    local cacheKey = "zones" .. (shouldShowLowLevel and ":all" or "")
    if cache[cacheKey] then
        return cache[cacheKey]
    end
    local player = Availability.getPlayer()
    local isAvailable = {} -- [questId] = true or false, since a quest can start in several zones
    local questIdsByZoneId = {} -- [zoneId] = { [questId] = true }: a dungeon's quests come from two lists
    for _, questIdsOfZones in ipairs({ index.startedInZone, index.forDungeon }) do
        for zoneId, questIds in pairs(questIdsOfZones) do
            questIdsByZoneId[zoneId] = questIdsByZoneId[zoneId] or {}
            for _, questId in ipairs(questIds) do
                if not isAtEntranceOnly(zoneId, questId) then
                    questIdsByZoneId[zoneId][questId] = true
                end
            end
        end
    end
    for zoneId, questIds in pairs(questIdsByZoneId) do
        local count = 0
        for questId in pairs(questIds) do
            if isAvailable[questId] == nil then
                isAvailable[questId] = Availability.isEligible(questId, player) == true
                    and (shouldShowLowLevel or not Availability.isLowLevel(questId, player))
            end
            if isAvailable[questId] then
                count = count + 1
            end
        end
        if count > 0 and zoneId > 0 then
            zones[#zones + 1] = {
                zoneId = zoneId,
                zoneName = ns.Database.getZoneName(zoneId),
                count = count,
                isDungeon = ns.Database.getDungeon(zoneId) ~= nil,
            }
        end
    end
    table.sort(zones, function(first, second)
        if first.zoneName ~= second.zoneName then
            return first.zoneName < second.zoneName
        end
        return first.zoneId < second.zoneId
    end)
    cache[cacheKey] = zones
    return zones
end

---@return boolean isMatch The quest's title holds the searched text (lower case), in the player's language or in
---English, or its giver's or start item's name does
function Availability.isSearchMatch(quest, searchText)
    if not searchText or searchText == "" then
        return true
    end
    for _, text in ipairs({ quest.title, quest.englishTitle, quest.starterName, quest.itemName }) do
        if type(text) == "string" and text:lower():find(searchText, 1, true) then
            return true
        end
    end
    return false
end

---The quests to pick up in other zones whose titles hold the searched text: for the Available tab's search, which
---lists the shown zone's matches and points to these. Dungeons are left out (they have a tab of their own).
---@param searchText string Lower case
---@param exceptZoneId number? The zone the list shows
---@return { zoneId: number, zoneName: string, titles: string[] }[] zones Most matches first
function Availability.findInOtherZones(searchText, exceptZoneId, options)
    local found = {}
    if not index or not searchText or searchText == "" then
        return found
    end
    for _, zone in ipairs(Availability.getZones(options)) do
        if zone.zoneId ~= exceptZoneId and not zone.isDungeon then
            -- Only a zone whose quest names could match is worked out in full
            local isCandidate = false
            for _, questId in ipairs(index.startedInZone[zone.zoneId] or {}) do
                local englishTitle = ns.Database.getQuestField(questId, "name")
                local title = ns.QuestText.getTitle(questId, englishTitle)
                if
                    (type(title) == "string" and title:lower():find(searchText, 1, true))
                    or (type(englishTitle) == "string" and englishTitle:lower():find(searchText, 1, true))
                then
                    isCandidate = true
                    break
                end
            end
            if isCandidate then
                local titles = {}
                for _, quest in ipairs((Availability.getQuests(zone.zoneId, options))) do
                    if
                        not quest.availableAtLevel
                        and Availability.isSearchMatch(
                            { title = quest.title, englishTitle = quest.englishTitle },
                            searchText
                        )
                    then
                        titles[#titles + 1] = quest.title
                    end
                end
                if #titles > 0 then
                    found[#found + 1] = { zoneId = zone.zoneId, zoneName = zone.zoneName, titles = titles }
                end
            end
        end
    end
    table.sort(found, function(first, second)
        if #first.titles ~= #second.titles then
            return #first.titles > #second.titles
        end
        return first.zoneName < second.zoneName
    end)
    return found
end

---Drops the remembered lists, and who can pick up what, outright: for what bears on any quest (the level, the kinds
---of quests wanted, a giver's refusal, a quest found missing from the game, another zone). Filled again in the
---background (startWarmUp).
function Availability.invalidate()
    cache, chainLeads, eligibility = {}, {}, {}
    changeCount = changeCount + 1
    startWarmUp()
end

---Quests came into the log, left it or were handed in: whether they, and the quests whose availability reads theirs
---(index.dependents, from AvailabilityIndex's DEPENDENCY_FIELDS), can be picked up is worked out again when next asked. Every other
---quest's answer stands.
local function forgetQuests(questIds)
    local dependents = index and index.dependents
    if not dependents then
        eligibility = {} -- (no index yet to say whom a quest bears on)
    end
    for _, questId in ipairs(questIds) do
        eligibility[questId] = nil
        for _, dependentId in ipairs(dependents and dependents[questId] or {}) do
            eligibility[dependentId] = nil
        end
    end
    cache, chainLeads = {}, {} -- (where a chain leads follows every quest along it: all of them again)
    changeCount = changeCount + 1
end

-- The character's reputations, skills and spells change all the time (a kill's few points of reputation, a fight's
-- point of weapon skill) and almost never for a quest: a quest asks for a standing or a rank reached, or a spell
-- known. Each event only says so (below); at the next redraw, or the next list asked for, the few standings, ranks
-- and spells that quests ask for are read, and only where one has crossed what a quest asks is that quest's answer
-- forgotten.
local isReputationStale, isSkillStale, isSpellStale = false, false, false

---@return number band How many of the thresholds a value has reached
local function getBand(thresholds, value)
    local band = 0
    for index = 1, #thresholds do
        if value >= thresholds[index] then
            band = band + 1
        end
    end
    return band
end

---@param isFirst boolean? The index has just been built: where the character stands is only noted
settleCharacterChanges = function(isFirst)
    if not index then
        if isReputationStale or isSkillStale or isSpellStale then
            isReputationStale, isSkillStale, isSpellStale = false, false, false
            eligibility = {} -- (no index yet to say which quests ask for what)
            changeCount = changeCount + 1
        end
        return
    end
    local hasChanged = false
    local function forget(questIds)
        for _, questId in ipairs(questIds) do
            eligibility[questId] = nil
        end
        hasChanged = true
    end
    if isReputationStale or isFirst then
        isReputationStale = false
        for factionId, requirement in pairs(index.reputation) do
            local faction = C_Reputation
                and C_Reputation.GetFactionDataByID
                and C_Reputation.GetFactionDataByID(factionId)
            local band = faction and getBand(requirement.thresholds, faction.currentStanding or 0) or -1
            if requirement.band ~= band then
                requirement.band = band
                forget(requirement.questIds)
            end
        end
    end
    if isSkillStale or isFirst then
        isSkillStale = false
        for skillId, requirement in pairs(index.skill) do
            local band = getBand(requirement.thresholds, Availability.getSkillRank(skillId))
            if requirement.band ~= band then
                requirement.band = band
                forget(requirement.questIds)
            end
        end
    end
    if isSpellStale or isFirst then
        isSpellStale = false
        for questId, known in pairs(index.spellStates) do
            local state = checkSpellRequirements(questId) or "met"
            if state ~= known then
                index.spellStates[questId] = state
                eligibility[questId] = nil
                hasChanged = true
            end
        end
    end
    if hasChanged and not isFirst then
        cache = {}
        changeCount = changeCount + 1
    end
end

-- Who can pick up what is worked out for every quest of the lists in the background, a millisecond a frame, so
-- that the lists of every zone (the Available tab) open at once instead of working it all out as they are opened:
-- after login, and whenever all of it was forgotten. Left alone in a fight.
local WARM_SLICE_MILLISECONDS = 1
local WARM_DELAY_SECONDS = 4 -- (after login, once the game's own loading has settled)
local warmRun = 0 -- raised to stop the run under way

startWarmUp = function()
    warmRun = warmRun + 1
    if
        not index
        or not C_Timer
        or not debugprofilestop
        or ns.frameNumber == 0
        or ns.settings.shouldUseAvailableQuests ~= true
    then
        return
    end
    local run = warmRun
    local questIds = index.listedQuestIds
    if not questIds then
        -- Every quest a zone's or a dungeon's list may hold, once each
        local isListed = {}
        questIds = {}
        for _, questIdsByZone in ipairs({ index.startedInZone, index.forDungeon }) do
            for _, zoneQuestIds in pairs(questIdsByZone) do
                for _, questId in ipairs(zoneQuestIds) do
                    if not isListed[questId] then
                        isListed[questId] = true
                        questIds[#questIds + 1] = questId
                    end
                end
            end
        end
        index.listedQuestIds = questIds
    end
    local position = 0
    local zoneQuestIds, zonePosition -- then what holds back each quest of the player's zone (the tab opens on it)
    local step
    local function work()
        local player = Availability.getPlayer()
        local started = debugprofilestop()
        while position < #questIds do
            position = position + 1
            local questId = questIds[position]
            if eligibility[questId] == nil and Availability.isEligible(questId, player) then
                Availability.isLowLevel(questId, player) -- (where its chain leads, kept too)
            end
            if debugprofilestop() - started >= WARM_SLICE_MILLISECONDS then
                C_Timer.After(0, step)
                return
            end
        end
        -- The Available tab's list of quests not to be had yet asks this of every quest of the zone, and was most of
        -- what opening the tab cost (kept while who can pick up what stands: getBlocker)
        if not zoneQuestIds then
            local zoneId = ns.Model.getPlayer().zoneId
            zoneQuestIds, zonePosition = zoneId and Availability.getZoneQuestIds(zoneId) or {}, 0
        end
        while zonePosition < #zoneQuestIds do
            zonePosition = zonePosition + 1
            Availability.getBlocker(zoneQuestIds[zonePosition], player)
            if debugprofilestop() - started >= WARM_SLICE_MILLISECONDS then
                C_Timer.After(0, step)
                return
            end
        end
    end
    step = function()
        if run ~= warmRun or not index then
            return
        end
        if InCombatLockdown and InCombatLockdown() then
            C_Timer.After(1, step)
            return
        end
        -- (what it reads of the database is not kept: a pass over all of it would push out what is read all the time)
        ns.Timing.measure("who can pick up what (in the background)", ns.Database.passThrough, work)
    end
    C_Timer.After(WARM_DELAY_SECONDS, step)
end

local knownLevel, knownKinds, knownLogIds -- the level, the kinds of quests wanted and the quests in the log, at the last redraw

---Each redraw: the lists are worked out again (how far each quest is, and in what order, follows the player), but
---not who can pick up what, nor the zones with quests (every quest of the database looked at, the dearest of them).
---Those stand while the level and the kinds of quests wanted do; a quest come into the log or gone from it forgets
---only what it bears on (forgetQuests). A kill or a loot redraws, and changes none of that.
---@param isQuiet boolean? Nothing asked for the redraw but the quest log's own news (Core's Module.invalidate): then
---the quests not yet to be had, which follow nothing of where the player stands, are kept too. A zone's list of
---them is the dearest of the Available tab, and with its heading folded only their number shows.
function Availability.invalidateForRedraw(isQuiet)
    settleCharacterChanges()
    local settings = ns.settings
    local level = UnitLevel and UnitLevel("player")
    local kinds = tostring(settings.shouldShowRepeatable)
        .. tostring(settings.shouldShowPvp)
        .. tostring(settings.lowLevelGap)
        .. tostring(settings.shouldShowDungeonLeadIns)
        .. tostring(settings.shouldShowAnyLeadIns)
        .. tostring(settings.shouldShowEvents)
        .. tostring(settings.shouldShowRaid)
        .. tostring(settings.shouldShowAQWarEffort)
        .. ns.Events.getChangeKey()
    local logIds = {}
    for _, questId in ipairs(ns.QuestState.getLogQuestIds()) do
        logIds[questId] = true
    end
    if level ~= knownLevel or kinds ~= knownKinds or not knownLogIds then
        Availability.invalidate()
    else
        local changed
        for questId in pairs(logIds) do
            if not knownLogIds[questId] then
                changed = changed or {}
                changed[#changed + 1] = questId
            end
        end
        for questId in pairs(knownLogIds) do
            if not logIds[questId] then
                changed = changed or {}
                changed[#changed + 1] = questId
            end
        end
        if changed then
            forgetQuests(changed)
        else
            local kept = { zones = cache.zones, ["zones:all"] = cache["zones:all"] }
            for key, value in pairs(isQuiet == true and cache or {}) do
                if type(key) == "string" and key:sub(1, 7) == "blocked" then
                    value.time = math.huge -- (held till the lists are next forgotten, not for a few seconds)
                    kept[key] = value
                end
            end
            cache = kept
        end
    end
    knownLevel, knownKinds, knownLogIds = level, kinds, logIds
end

---@return string key Another value whenever the quests to pick up may have changed by the character's own doing: the
---level, the quests in the log or done, a reputation, a skill, a spell, the kinds of quests wanted, a giver's
---refusal. Whoever draws them (the maps' "!") can tell by it, at a redraw the quest log's news alone asked for,
---that theirs still stand. (What else they follow, an item in the bags that starts a quest, a setting, the zone,
---asks for a full redraw itself: Core's Module.refresh.)
function Availability.getChangeKey()
    return tostring(changeCount) .. ":" .. tostring(index ~= nil)
end
---Forgets the index, for tests.
---Forgets the lists worked out, for when what is offered changed (a quest found missing from the game).
---What the game offers on its maps, or what givers hold back, changed (GameOffers): the lists are worked out again,
---and whether the quests named can be picked up; every other quest's answer stands.
---@param questIds number[]? The quests whose giver's refusal came or went
function Availability.forgetOffers(questIds)
    forgetQuests(questIds or {})
end

---Whether the quests of the zone the player is in can be picked up is asked again (with the lists).
function Availability.forgetPlayerZone()
    local zoneId = index and ns.Model and ns.Model.getPlayer().zoneId
    if not zoneId then
        return
    end
    forgetQuests(Availability.getZoneQuestIds(zoneId))
end

---@param questId number? The quest handed in; nil for one found missing from the game
function Availability.forgetLists(questId)
    if questId then
        forgetQuests({ questId }) -- a quest handed in opens others: its own answer, and theirs
    else
        Availability.invalidate() -- one not in the game: whatever that bears on
    end
end

function Availability.reset()
    index, isIndexing, readyCallbacks, cache = nil, false, {}, {}
    startZoneByQuestId, chainLeads, zoneQuestIds, zoneIdsByQuestId = nil, {}, {}, nil
    instanceQuests = {} -- (the dungeons may be others now: a provider's, learned ones)
    eligibility, knownLevel, knownKinds, knownLogIds = {}, nil, nil, nil
    isReputationStale, isSkillStale, isSpellStale = false, false, false
    warmRun = warmRun + 1
end

-- The lists hold their reasons in words, and what is known of quests: worked out again when either changes
ns.on("QUEST_FACTS_CHANGED", Availability.forgetLists)
ns.on("LANGUAGE_CHANGED", Availability.invalidate)
ns.on("QUEST_TEXT_CHANGED", Availability.invalidate)
ns.registerModule({
    name = "Availability",
    invalidate = Availability.invalidateForRedraw,
    events = {
        -- What a quest may ask of the character besides their level and other quests: looked at when next needed
        UPDATE_FACTION = function()
            isReputationStale = true
        end,
        SKILL_LINES_CHANGED = function()
            isSkillStale = true
        end,
        SPELLS_CHANGED = function()
            isSpellStale = true
        end,
        -- Another zone, or back in the world: the quests of the zone the player is in now are asked again (the game
        -- may have marked a quest done meanwhile with no word of it). Only those: they are what the map and the
        -- list show first, and asking all of them again was a second's work in the background at every zone.
        ZONE_CHANGED_NEW_AREA = function()
            Availability.forgetPlayerZone()
        end,
        PLAYER_ENTERING_WORLD = function()
            Availability.forgetPlayerZone()
        end,
    },
})
