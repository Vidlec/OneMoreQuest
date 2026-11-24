local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Reads the tracked quests and their progress from the game's quest log.
local QuestState = {}
ns.QuestState = QuestState

---The game writes "5/12 Roadside Bandit slain" or "Roadside Bandit slain: 5/12"; the tracker shows the count apart.
function QuestState.getObjectiveLabel(text)
    local label = (text or ""):gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:%s*%d+%s*/%s*%d+%s*$", "")
    return label
end

---@return boolean isLinkClick The click is meant to put a link in the chat: the game's chat-link modifier
---(Shift, unless the player bound it otherwise)
function QuestState.isLinkClick()
    if IsModifiedClick then
        return IsModifiedClick("CHATLINK") == true
    end
    return IsShiftKeyDown and IsShiftKeyDown() == true or false
end

---@return boolean isFocusClick The click is meant to put the quest in focus: Ctrl held
function QuestState.isFocusClick()
    return IsControlKeyDown and IsControlKeyDown() == true or false
end

---@return string? link A quest's chat link: the game's own, or one made the same way from the quest database
---for a quest not in the log (one to pick up)
function QuestState.getChatLink(questId)
    local link = GetQuestLink and GetQuestLink(questId)
    if type(link) == "string" and link ~= "" then
        return link
    end
    local title = ns.Database.getQuestField(questId, "name")
    if type(title) ~= "string" then
        return nil
    end
    local level = ns.Database.getQuestField(questId, "questLevel") or -1
    return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", questId, level, title)
end

---Puts a quest's link in the chat: into the message being typed, or a newly opened one.
---@return boolean isLinked
function QuestState.linkInChat(questId)
    local link = questId and QuestState.getChatLink(questId)
    if not link then
        return false
    end
    if ChatEdit_InsertLink and ChatEdit_InsertLink(link) then
        return true
    end
    if ChatFrame_OpenChat then
        ChatFrame_OpenChat(link)
        return true
    end
    return false
end

---@return string[] words The words the game puts on kill objectives in the client's language, from its own
---string ("%2$d/%3$d %1$s slain" in English, "%1$s getötet: %2$d/%3$d" in German), with the English ones too
function QuestState.getKillWords()
    local killWords = { "slain", "killed" }
    local pattern = type(QUEST_MONSTERS_KILLED) == "string" and QUEST_MONSTERS_KILLED or ""
    for word in pattern:gsub("%%%d*%$?%a", " "):gmatch("[^%s%p%d]+") do
        word = word:lower()
        if word ~= "slain" and word ~= "killed" then
            killWords[#killWords + 1] = word
        end
    end
    return killWords
end

---@return boolean isKill The objective is worded as a kill, in the client's language
function QuestState.isKillWording(label)
    local lower = (label or ""):lower()
    for _, word in ipairs(QuestState.getKillWords()) do
        if lower:find(word, 1, true) then
            return true
        end
    end
    return false
end

---@return string name An objective's label without the kill wording: "Roadside Bandit"
function QuestState.removeKillWording(label)
    local name = label or ""
    for _, word in ipairs(QuestState.getKillWords()) do
        name = name:gsub(word:gsub("%p", "%%%0"), ""):gsub(word:sub(1, 1):upper() .. word:sub(2):gsub("%p", "%%%0"), "")
    end
    return name
end

local GLYPH_BY_OBJECTIVE_TYPE = { monster = "kill", item = "loot" } -- anything else is "use"

---@return string glyph What an objective asks, as its icon shows it: "kill" for a creature to kill, "loot" for an
---item to collect, "use" for the rest. The game also reports "go there" and "trigger this" objectives as creatures;
---only the ones worded as kills, in the client's language, get the swords.
function QuestState.getObjectiveGlyph(objective)
    local glyph = GLYPH_BY_OBJECTIVE_TYPE[objective.type] or "use"
    if glyph == "kill" and not QuestState.isKillWording(objective.label) then
        glyph = "use"
    end
    return glyph
end

---@return number[] questIds Quests the player tracks, in the game's order
-- The tracked quests, read once a frame and shared (ns.frameNumber): every colour, number and mark asks for them, a
-- call into the game for each tracked quest at every asking. Forgotten at once when this addon changes what is
-- tracked (QuestState.forgetWatches), so nothing drawn in the same frame misses the change.
local watchedQuestIds, watchNumbers, watchedReadFrame = nil, nil, nil

local function readWatchedQuestIds()
    local frameNumber = ns.frameNumber
    if frameNumber > 0 and watchedReadFrame == frameNumber and watchedQuestIds then
        return watchedQuestIds
    end
    local questIds = {}
    for index = 1, C_QuestLog.GetNumQuestWatches() or 0 do
        local questId = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
        if questId and questId > 0 then
            questIds[#questIds + 1] = questId
        end
    end
    watchedQuestIds, watchNumbers, watchedReadFrame = questIds, nil, frameNumber
    return questIds
end

---What is tracked was just changed (by this addon): read again at the next asking.
function QuestState.forgetWatches()
    watchedQuestIds, watchNumbers, watchedReadFrame = nil, nil, nil
end

---The game said the log or what is tracked changed: what was read of them this frame is read again, so whoever
---hears the same event next (a quest just taken, handed in or dropped) sees the log as it now is.
function QuestState.forgetFrame()
    watchedQuestIds, watchNumbers, watchedReadFrame = nil, nil, nil
    QuestState.forgetLog()
end

---@return number[] questIds The tracked quests, in the order they were tracked (a list of the caller's own)
function QuestState.getWatchedQuestIds()
    local questIds = readWatchedQuestIds()
    local copy = {}
    for index = 1, #questIds do
        copy[index] = questIds[index]
    end
    return copy
end

---@return number[] questIds The quests whose marks the map and the minimap show: the tracked ones, then those ready to
---hand in that are not (their "?" shows whether tracked or not, as on the game's own map; one past the game's limit
---of tracked quests had none till selected)
function QuestState.getShownOnMapQuestIds()
    local questIds = QuestState.getWatchedQuestIds()
    local isListed = {}
    for _, questId in ipairs(questIds) do
        isListed[questId] = true
    end
    for _, questId in ipairs(QuestState.getLogQuestIds()) do
        if not isListed[questId] then
            local quest = QuestState.getQuest(questId)
            if quest and quest.isComplete then
                questIds[#questIds + 1] = questId
            end
        end
    end
    return questIds
end

---@return string key The tracked quests as one text, the same while the same quests are tracked in the same order
function QuestState.getWatchKey()
    local questIds = readWatchedQuestIds()
    if questIds.key == nil then
        questIds.key = table.concat(questIds, ",")
    end
    return questIds.key
end

---@class TrackedQuest
---@field questId number
---@field title string As shown: in the player's language when a translation addon has it
---@field englishTitle string As the game gives it
---@field level number
---@field isComplete boolean Every objective is done, the quest only has to be handed in
---@field objectives { label: string, text: string?, shownLabel: string, shownText: string?, type: string, isFinished: boolean, fulfilled: number, required: number }[]
---label and text as the game writes them, for matching; shownLabel and shownText as shown (translated when they can be)

-- What the game says of each quest in the log, kept until the log changes (every change to it comes with one of the
-- events forgetLog follows) or its words do (the language, a translation): a kill redraws the tracker, the quest
-- window and both maps, a frame apart, and each read every quest's objectives, title and level from the game anew,
-- a few tables each. Only once frames run (in the tests every asking is fresh).
local questReads = {}

local function readQuest(questId)
    local objectives = {}
    local gameObjectives = C_QuestLog.GetQuestObjectives(questId) or {}
    for _, objective in ipairs(gameObjectives) do
        -- The line in the player's language, from a translation addon; the English stays for matching
        local shownText = ns.QuestText.getObjective(
            questId,
            objective.text,
            objective.numFulfilled,
            objective.numRequired,
            objective.type,
            #gameObjectives
        )
        objectives[#objectives + 1] = {
            label = QuestState.getObjectiveLabel(objective.text),
            text = objective.text, -- as the game's own tooltips show it: "Kraul Guano: 3/12"
            shownLabel = QuestState.getObjectiveLabel(shownText),
            shownText = shownText,
            type = objective.type,
            isFinished = objective.finished == true,
            fulfilled = objective.numFulfilled or 0,
            required = objective.numRequired or 0,
        }
    end
    local level = C_QuestLog.GetQuestDifficultyLevel and C_QuestLog.GetQuestDifficultyLevel(questId)
    local englishTitle = C_QuestLog.GetTitleForQuestID(questId)
        or ns.Database.getQuestField(questId, "name")
        or ("Quest " .. questId)
    return {
        questId = questId,
        title = ns.QuestText.getTitle(questId, englishTitle, true), -- as shown: from a translation addon, when one has it
        englishTitle = englishTitle,
        level = level or ns.Database.getQuestField(questId, "questLevel") or 0,
        isComplete = C_QuestLog.IsComplete(questId) == true,
        objectives = objectives,
    }
end

---@return TrackedQuest quest The caller's own table (its fields may be added to: Model's entries are); the objectives
---in it are shared, to read
function QuestState.getQuest(questId)
    local read = questReads[questId]
    if not read then
        read = readQuest(questId)
        if ns.frameNumber > 0 then
            questReads[questId] = read
        end
    end
    return {
        questId = read.questId,
        title = read.title,
        englishTitle = read.englishTitle,
        level = read.level,
        isComplete = read.isComplete,
        objectives = read.objectives,
    }
end

---The words of quests changed (the language, a translation arrived): read again at the next asking.
function QuestState.forgetQuestReads()
    questReads = {}
end
if ns.on then
    ns.on("LANGUAGE_CHANGED", QuestState.forgetQuestReads)
    ns.on("QUEST_TEXT_CHANGED", QuestState.forgetQuestReads)
end

local GROUP_KINDS = { [1] = "Group quest", [62] = "Raid quest", [81] = "Dungeon quest", [85] = "Heroic dungeon quest" }
local DEFAULT_GROUP_SIZES = { [81] = 5, [85] = 5 } -- a dungeon takes a full party
local RAID_TAG = 62

---Whether the game labels a quest as one for a group: an elite, dungeon or raid quest, which the game's own
---quest log marks with a "+" after the level. The game may know nothing of a quest that is not in the log.
---@return { kindText: string, size: number?, isRaid: boolean }? group nil for an ordinary quest; size is the
---suggested number of players, when the game gives one
function QuestState.getGroupInfo(questId)
    local tagId = QuestState.getTagId(questId)
    local kindText = GROUP_KINDS[tagId] and ns.L(GROUP_KINDS[tagId])
    if not kindText then
        return nil
    end
    local size = C_QuestLog.GetSuggestedGroupSize and C_QuestLog.GetSuggestedGroupSize(questId)
    if type(size) ~= "number" or size <= 1 then
        size = DEFAULT_GROUP_SIZES[tagId]
    end
    return { kindText = kindText, size = size, isRaid = tagId == RAID_TAG }
end

-- The log's quests, read once a frame and shared: a drawing asks for them for every row (the log's size, a quest's
-- warnings), and each reading asks the game for every line of the log, a table each. Only once frames are seen to
-- run (in tests, where they do not, every call reads the log).
local logQuestIds, logReadFrame = nil, nil
-- { count, max } of the log, kept till the next redraw of everything (forgetMemos) or a change of the log (forgetLog),
-- once frames run
local logSizeMemo

local isInLogById = {} -- [questId] = true for every quest of the log, the hidden ones too, as last read

function QuestState.forgetLog()
    logQuestIds, logReadFrame = nil, nil
    questReads = {}
    logSizeMemo = nil -- (its count is the log's: a quest taken or dropped changes it before the next redraw)
end

-- Told first of every change to the log and to what is tracked (this file loads before the modules that listen for
-- the same events on frames of their own)
local LOG_EVENTS = {
    "QUEST_ACCEPTED",
    "QUEST_REMOVED",
    "QUEST_TURNED_IN",
    "QUEST_LOG_UPDATE",
    "QUEST_WATCH_LIST_CHANGED",
    "UNIT_QUEST_LOG_CHANGED",
}
if CreateFrame then
    local logWatcher = CreateFrame("Frame")
    if logWatcher and logWatcher.RegisterEvent and logWatcher.SetScript then
        for _, event in ipairs(LOG_EVENTS) do
            pcall(logWatcher.RegisterEvent, logWatcher, event)
        end
        logWatcher:SetScript("OnEvent", function()
            QuestState.forgetFrame()
        end)
    end
end

local function readLogQuestIds()
    local frameNumber = ns.frameNumber
    if frameNumber > 0 and logReadFrame == frameNumber and logQuestIds then
        return logQuestIds
    end
    local questIds, inLog = {}, {}
    for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(index)
        if info and not info.isHeader and info.questID and info.questID > 0 then
            inLog[info.questID] = true
            if not info.isHidden then
                questIds[#questIds + 1] = info.questID
            end
        end
    end
    logQuestIds, isInLogById, logReadFrame = questIds, inLog, frameNumber
    return questIds
end

-- What the lists ask the game about every quest they look at, thousands at a time, kept between askings (once
-- frames run; in the tests every asking is fresh):
--   a quest's tag (dungeon, raid, elite, PvP) never changes once the game has it, and is kept for good; that it has
--   none may only mean the game has not loaded the quest yet, so that is kept till the next redraw of everything;
--   whether a quest was handed in, kept till the next redraw of everything or a hand-in (QuestState.forgetMemos).
local tagIdByQuestId, hasNoTagById, isTurnedInById = {}, {}, {}

---Forgets what may have changed since the last redraw of everything.
function QuestState.forgetMemos()
    hasNoTagById, isTurnedInById = {}, {}
    logSizeMemo = nil
end

---@return number? tagId The game's tag for a quest; nil for a quest with none (or one the game has not loaded)
function QuestState.getTagId(questId)
    local isKeeping = ns.frameNumber > 0
    if isKeeping then
        local known = tagIdByQuestId[questId]
        if known then
            return known
        end
        if hasNoTagById[questId] then
            return nil
        end
    end
    local tagId
    local info = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questId)
    if type(info) == "table" then
        tagId = info.tagID
    elseif not info and GetQuestTagInfo then
        tagId = GetQuestTagInfo(questId)
    end
    if isKeeping then
        if tagId then
            tagIdByQuestId[questId] = tagId
        else
            hasNoTagById[questId] = true
        end
    end
    return tagId
end

---@return number[] questIds Every quest in the quest log, in the game's order (a list of the caller's own)
function QuestState.getLogQuestIds()
    local questIds = readLogQuestIds()
    local copy = {}
    for index = 1, #questIds do
        copy[index] = questIds[index]
    end
    return copy
end

---@return string? title The header the game's own quest log lists the quest under, such as "Cooking"
function QuestState.getLogHeader(questId)
    local header
    for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(index)
        if info and info.isHeader then
            header = info.title
        elseif info and info.questID == questId then
            return header
        end
    end
    return nil
end

function QuestState.isInLog(questId)
    if ns.frameNumber > 0 then
        readLogQuestIds() -- the log as read this frame (once): the lists ask this of thousands of quests
        return isInLogById[questId] == true
    end
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questId)
    return logIndex ~= nil and logIndex > 0
end

-- Quests handed in this session, by QUEST_TURNED_IN. The game marks a quest completed a moment after it is handed
-- in, but a giver offers the chain's next step at once (Blood in the Streets, then Heart of Disruption 4 seconds
-- later): until the mark comes, the next step would read as still waiting for it. Kept for the session only.
local turnedInThisSession = {}

---Notes a quest just handed in, so it counts as done before the game's own mark comes. Not one that can be done
---again (a repeatable hand-in, a daily, by the database's flags): the game never marks it done for good, and noted,
---it counted as done for the rest of the session, never offered again.
function QuestState.noteTurnedIn(questId)
    if questId then
        local isRepeatable = ns.Availability and ns.Availability.isRepeatable and ns.Availability.isRepeatable(questId)
        if not isRepeatable then
            turnedInThisSession[questId] = true
        end
        isTurnedInById = {}
    end
end

function QuestState.isTurnedIn(questId)
    if turnedInThisSession[questId] == true then
        return true
    end
    if ns.frameNumber == 0 then
        return C_QuestLog.IsQuestFlaggedCompleted(questId) == true
    end
    local known = isTurnedInById[questId]
    if known == nil then
        known = C_QuestLog.IsQuestFlaggedCompleted(questId) == true
        isTurnedInById[questId] = known
    end
    return known
end

function QuestState.isWatched(questId)
    return QuestState.getWatchNumbers()[questId] ~= nil
end

local STAY_ALIVE_FLAG = 1 -- the database's mark of a quest that fails when someone dies: an escort

---@return number? secondsLeft For a timed quest, the time left; nil for a quest without a time limit
function QuestState.getTimeLeft(questId)
    if not C_QuestLog.GetTimeAllowed then
        return nil
    end
    local total, elapsed = C_QuestLog.GetTimeAllowed(questId)
    if type(total) ~= "number" or total <= 0 or type(elapsed) ~= "number" then
        return nil
    end
    return math.max(total - elapsed, 0)
end

---@return boolean isFailed The quest has failed: its time ran out, or the one escorted died
function QuestState.isFailed(questId)
    return C_QuestLog.IsFailed ~= nil and C_QuestLog.IsFailed(questId) == true
end

---@return boolean isEscort Someone has to be kept alive for the quest
function QuestState.isEscort(questId)
    local flags = ns.Database.getQuestField(questId, "questFlags") or 0
    return math.floor(flags / STAY_ALIVE_FLAG) % 2 == 1
end

local DEFAULT_MAX_WATCHES = 25

local function showError(text)
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.1, 0.1, 1)
    else
        ns.print(text)
    end
end

---Tracks a quest, as the game's own quest log does: it refuses once as many quests are tracked as the game
---allows, and says so, in the same words and place as the game. A quest the game will not track is reported
---too, instead of the click seeming to do nothing.
---@return boolean isWatched The quest is tracked now
function QuestState.addWatch(questId)
    if QuestState.isWatched(questId) then
        return true
    end
    local maxWatches = Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES
        or DEFAULT_MAX_WATCHES
    if (C_QuestLog.GetNumQuestWatches() or 0) >= maxWatches then
        showError(OBJECTIVES_WATCH_TOO_MANY or ns.L("You can only track %d quests at a time.", maxWatches))
        return false
    end
    C_QuestLog.AddQuestWatch(questId)
    QuestState.forgetWatches()
    if not QuestState.isWatched(questId) then
        showError(ns.L("The game would not track this quest."))
        return false
    end
    return true
end

---Tracks every quest given, in order, until the game's limit: it says why once, and the rest stay untracked.
---@return number count Quests newly tracked
function QuestState.watchAll(questIds)
    local count = 0
    for _, questId in ipairs(questIds) do
        local wasWatched = QuestState.isWatched(questId)
        if not QuestState.addWatch(questId) then
            break -- the game said why; the rest would fail the same way
        end
        count = count + (wasWatched and 0 or 1)
    end
    return count
end

---Stops tracking every quest given; they stay in the log, and a focused one among them is let go.
function QuestState.unwatchAll(questIds)
    for _, questId in ipairs(questIds) do
        if QuestState.isWatched(questId) then
            C_QuestLog.RemoveQuestWatch(questId)
            QuestState.forgetWatches()
            ns.Focus.handleQuestGone(questId, true)
        end
    end
end

---@return number count How many of the quests given are tracked
function QuestState.countWatched(questIds)
    local count = 0
    for _, questId in ipairs(questIds) do
        count = count + (QuestState.isWatched(questId) and 1 or 0)
    end
    return count
end

---@return number count Quests in the log
---@return number max Most quests the log can hold
function QuestState.getLogSize()
    if logSizeMemo and ns.frameNumber > 0 then
        return logSizeMemo[1], logSizeMemo[2]
    end
    local max = C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept() or 25
    local count = #readLogQuestIds()
    logSizeMemo = { count, max }
    return count, max
end

---The quest giver's text. The game only hands it out for the selected quest.
---@return string? description
function QuestState.getDescription(questId)
    if not GetQuestLogQuestText or not QuestState.isInLog(questId) then
        return nil
    end
    -- Selecting makes the game announce a quest log change, so it is done only when the selection differs
    if
        C_QuestLog.SetSelectedQuest and not (C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() == questId)
    then
        C_QuestLog.SetSelectedQuest(questId)
    end
    local description = GetQuestLogQuestText(C_QuestLog.GetLogIndexForQuestID(questId))
    -- In the player's language, when a translation addon has the quest's story
    return description ~= "" and ns.QuestText.getDescription(questId, description) or nil
end

---@param rewardType string "reward" or "choice", as the game's tooltip names the two kinds
local function getRewardItems(getCount, getInfo, questId, rewardType)
    local items = {}
    for index = 1, getCount and getCount(questId) or 0 do
        local name, texture, count, quality, _, itemId = getInfo(index, questId)
        if name then
            -- The kind, position and quest are what the game's tooltip needs to show the item
            items[#items + 1] = {
                name = name,
                texture = texture,
                count = count or 1,
                rewardType = rewardType,
                index = index,
                questId = questId,
                itemId = itemId,
                quality = type(quality) == "number" and quality or nil,
            }
        end
    end
    return items
end

local requestedRewardQuestIds = {} -- [questId] = true while its rewards are asked of the game, "answered" after
local isAnswerOurs = false -- the last QUEST_DATA_LOAD_RESULT answered something this addon asked (read by its change check)
local askedExistence = {} -- [questId] = "asked" while the game is asked whether it has the quest, true once known

---@return string build The game's build, under which quests it does not have are remembered
---@return string build The game's build number, as the "not in the game" answers are kept by
local knownBuild -- the game's build, asked once (it was asked for every quest of every list)

local function getBuild()
    if knownBuild then
        return knownBuild
    end
    local build
    if GetBuildInfo then
        _, build = GetBuildInfo() -- not "GetBuildInfo and GetBuildInfo()": "and" keeps only the first value
    end
    if build and ns.frameNumber > 0 then -- kept once frames run (in the tests a build may change under the addon)
        knownBuild = tostring(build)
    end
    return tostring(build or "unknown")
end
QuestState.getBuild = getBuild

---@return boolean isMissing The game said it has no such quest: one the database knows from another version of the
---game (Season of Discovery's supply crates in the Barrens, for one), never to be offered here
function QuestState.isMissingFromGame(questId)
    local missing = ns.settings.questsNotInGame and ns.settings.questsNotInGame[getBuild()]
    return missing ~= nil and missing[questId] == true
end

---Asks the game, once, whether it has a quest the lists are about to offer: the database also holds quests from
---other versions of the game. A quest it already describes is taken as there.
function QuestState.checkExists(questId)
    if askedExistence[questId] or not C_QuestLog.RequestLoadQuestByID or QuestState.isInLog(questId) then
        return
    end
    if HaveQuestData and HaveQuestData(questId) then
        askedExistence[questId] = true
        return
    end
    askedExistence[questId] = "asked"
    C_QuestLog.RequestLoadQuestByID(questId)
end

---The game answered whether it could load a quest's details.
---@return boolean isNewlyMissing It has no such quest: the lists are to be worked out again without it
function QuestState.handleQuestDataLoaded(questId, isLoaded)
    if askedExistence[questId] ~= "asked" then
        return false
    end
    askedExistence[questId] = true
    if isLoaded ~= false then
        return false
    end
    local build = getBuild()
    ns.settings.questsNotInGame = ns.settings.questsNotInGame or {}
    ns.settings.questsNotInGame[build] = ns.settings.questsNotInGame[build] or {}
    ns.settings.questsNotInGame[build][questId] = true
    return true
end

---@return { money: number, experience: number, items: table[], choices: table[], isLoading: boolean } rewards
---Money in copper. For a quest not in the log the game has to be asked first; until it answers, isLoading
---is set and the experience comes from the database.
function QuestState.getRewards(questId)
    local isLoading = false
    if not QuestState.isInLog(questId) and HaveQuestRewardData and not HaveQuestRewardData(questId) then
        -- Asked once per quest: a quest the game will not describe must not be asked about on every redraw
        if not requestedRewardQuestIds[questId] and C_QuestLog.RequestLoadQuestByID then
            requestedRewardQuestIds[questId] = true
            isLoading = true
            C_QuestLog.RequestLoadQuestByID(questId)
        end
    end
    local experience = GetQuestLogRewardXP and GetQuestLogRewardXP(questId) or 0
    if experience == 0 then
        -- The game gave no amount (the quest is not in the log): the database's, lowered as the game would
        -- for a quest the character has outlevelled
        experience = ns.Database.getQuestExperience(questId, UnitLevel and UnitLevel("player") or nil) or 0
    end
    return {
        money = GetQuestLogRewardMoney and GetQuestLogRewardMoney(questId) or 0,
        experience = experience,
        items = getRewardItems(GetNumQuestLogRewards, GetQuestLogRewardInfo, questId, "reward"),
        choices = getRewardItems(GetNumQuestLogChoices, GetQuestLogChoiceInfo, questId, "choice"),
        isLoading = isLoading,
    }
end

---The usable item that goes with a quest: the one the game marks for it, else the item the quest giver hands
---over when it is one that can be used and is in the bags.
---@return { link: string, texture: any, count: number?, itemId: number?, name: string?, shouldShowWhenComplete: boolean }? item
function QuestState.getItem(questId)
    local logIndex = C_QuestLog.GetLogIndexForQuestID(questId)
    if logIndex and logIndex > 0 and GetQuestLogSpecialItemInfo then
        local link, texture, charges, shouldShowWhenComplete = GetQuestLogSpecialItemInfo(logIndex)
        if link then
            return {
                link = link,
                texture = texture,
                count = charges and charges > 0 and charges or nil,
                itemId = tonumber(link:match("item:(%d+)")),
                name = link:match("%[(.-)%]"),
                shouldShowWhenComplete = shouldShowWhenComplete == true,
            }
        end
    end
    local itemId = ns.Database.getQuestField(questId, "sourceItemId") or 0
    if itemId == 0 or not C_Item or not C_Item.GetItemSpell then
        return nil
    end
    local count = QuestState.getItemCount(itemId)
    if count == 0 or not C_Item.GetItemSpell(itemId) then
        return nil
    end
    return {
        link = "item:" .. itemId,
        texture = C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemId) or nil,
        count = count,
        itemId = itemId,
        name = ns.Database.getItemField(itemId, "name"),
        shouldShowWhenComplete = false,
    }
end

---The number each tracked quest goes by on the map, in the tracker and in the quest list: its place in the
---game's list of tracked quests, which only changes when tracking does.
---@return table<number, number> numbers By quest ID
function QuestState.getWatchNumbers()
    local questIds = readWatchedQuestIds()
    if watchNumbers and ns.frameNumber > 0 then
        return watchNumbers -- shared for the frame: to read, not to change
    end
    local numbers = {}
    for index, questId in ipairs(questIds) do
        numbers[questId] = index
    end
    watchNumbers = numbers
    return numbers
end

---@return string signature Everything about the quest log that the windows draw: its quests and headers in order, each
---quest's title, done or failed, objective texts (with their counts) and its usable item. The same text means the
---log looks the same, so a QUEST_LOG_UPDATE that changed nothing (it comes with many a kill and loot) need not redraw.
function QuestState.getLogSignature()
    local parts = {}
    for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(index)
        local questId = info and not info.isHeader and info.questID
        if questId and questId > 0 then
            parts[#parts + 1] = string.format(
                "%d:%s:%s:%s",
                questId,
                tostring(C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId)),
                tostring(C_QuestLog.IsComplete and C_QuestLog.IsComplete(questId)),
                tostring(C_QuestLog.IsFailed and C_QuestLog.IsFailed(questId))
            )
            for _, objective in ipairs(C_QuestLog.GetQuestObjectives(questId) or {}) do
                parts[#parts + 1] = tostring(objective.text) .. (objective.finished and "+" or "-")
            end
            if GetQuestLogSpecialItemInfo then
                local link, _, charges = GetQuestLogSpecialItemInfo(index)
                parts[#parts + 1] = tostring(link) .. "x" .. tostring(charges)
            end
        elseif info then
            parts[#parts + 1] = "#" .. tostring(info.title)
        end
    end
    return table.concat(parts, "|")
end

-- The items whose number in the bags something drawn depends on (a quest's usable item, a world drop that starts a
-- quest), with the number last read: a BAG_UPDATE_DELAYED redraws only when one of them changed.
local countedItems = {}

local function readItemCount(itemId)
    local getCount = (C_Item and C_Item.GetItemCount) or GetItemCount -- luacheck: ignore 113 (an older client's fallback)
    return getCount and getCount(itemId) or 0
end

---@return number count How many of an item the player carries; remembered, so a change of it redraws
function QuestState.getItemCount(itemId)
    local count = readItemCount(itemId)
    countedItems[itemId] = count
    return count
end

local lastLogSignature

ns.registerModule({
    name = "QuestState",
    invalidate = QuestState.forgetMemos, -- every redraw of everything: what was asked of the game is asked afresh
    -- Whether a frequent event changed what is drawn: the log's look, or the number of an item that matters
    changes = {
        QUEST_LOG_UPDATE = function()
            local signature = QuestState.getLogSignature()
            local changed = signature ~= lastLogSignature
            lastLogSignature = signature
            return changed
        end,
        BAG_UPDATE_DELAYED = function()
            local changed = false
            for itemId, count in pairs(countedItems) do
                local now = readItemCount(itemId)
                if now ~= count then
                    countedItems[itemId], changed = now, true
                end
            end
            return changed
        end,
        -- The game answers every addon's asking (Questie's, the game's own): only an answer to ours redraws
        QUEST_DATA_LOAD_RESULT = function()
            return isAnswerOurs
        end,
    },
    events = {
        -- The game says whether it has a quest; one it has not is left out from then on
        QUEST_DATA_LOAD_RESULT = function(questId, isLoaded)
            -- Ours: rewards asked for the lists, or whether the game has the quest (read before that is noted)
            isAnswerOurs = askedExistence[questId] == "asked" or requestedRewardQuestIds[questId] == true
            if requestedRewardQuestIds[questId] == true then
                requestedRewardQuestIds[questId] = "answered"
            end
            if QuestState.handleQuestDataLoaded(questId, isLoaded) then
                ns.emit("QUEST_FACTS_CHANGED")
            end
        end,
        -- Done at once: the giver may offer the next step before the game marks this one completed
        QUEST_TURNED_IN = function(questId)
            QuestState.noteTurnedIn(questId)
            ns.emit("QUEST_FACTS_CHANGED", questId)
        end,
    },
    -- The game's "no such quest" answers hold for its own build only
    prune = function()
        local build = QuestState.getBuild()
        for savedBuild in pairs(ns.settings.questsNotInGame or {}) do
            if savedBuild ~= build then
                ns.settings.questsNotInGame[savedBuild] = nil
            end
        end
    end,
})
