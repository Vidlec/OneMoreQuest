local _, ns = ...

-- Who in the party shares a quest. The game says whether a member is on a quest and gives their progress as
-- ready-made tooltip lines; inside dungeons and raids those lines are withheld. Members running OneMoreQuest or
-- Questie send their exact counts (Comms), which win over the game's lines and are there in dungeons too.
local Party = {}
ns.Party = Party

local MAX_PARTY_MEMBERS = 4

---Two letters: first and second name, or the first two letters of a single name.
function Party.getInitials(name)
    local first, second = (name or ""):match("^(%S+)%s+(%S+)")
    if first then
        return (first:sub(1, 1) .. second:sub(1, 1)):upper()
    end
    return (name or "?"):sub(1, 2):upper()
end

---@return string[] units Everyone in the group but the player: party1-4, or the raid's members in a raid
function Party.getUnits()
    local units = {}
    if not UnitExists then
        return units
    end
    if IsInRaid and IsInRaid() then
        for index = 1, 40 do
            local unit = "raid" .. index
            if UnitExists(unit) and not (UnitIsUnit and UnitIsUnit(unit, "player")) then
                units[#units + 1] = unit
            end
        end
        return units
    end
    for index = 1, MAX_PARTY_MEMBERS do
        if UnitExists("party" .. index) then
            units[#units + 1] = "party" .. index
        end
    end
    return units
end

local UNKNOWN_REASON =
    "Not on this quest. Whether they did it already or could take it, only OneMoreQuest on their side can tell."

---What a member is to a quest: on it; or, when not, their own answer if their OneMoreQuest gave one (done it, can
---take it, can't and why), else what their race, class and level say; unknown when nothing rules them out, as
---they may have done it or still need an earlier quest.
---@return { state: string, reason: string, shortReason: string } status state is "has", "done", "can", "cannot" or "unknown"
function Party.getStatus(member, questId)
    if member.isOnQuest then
        return { state = "has", reason = ns.L("On this quest"), shortReason = "" }
    end
    local answer = ns.Comms and ns.Comms.getRemoteStatus(member.fullName, questId)
    if answer and answer.state == "done" then
        return { state = "done", reason = ns.L("Done it already"), shortReason = ns.L("done") }
    elseif answer and answer.state == "can" then
        return { state = "can", reason = ns.L("Can take it"), shortReason = ns.L("can take") }
    elseif answer then
        return {
            state = "cannot",
            reason = answer.reason or ns.L("Can't take it"),
            shortReason = answer.shortReason or ns.L("can't"),
        }
    end
    local reason, shortReason = ns.Availability.getUnmetRequirement(questId, ns.Availability.getPlayer(member.unit))
    if reason then
        return { state = "cannot", reason = reason, shortReason = shortReason }
    end
    return { state = "unknown", reason = ns.L(UNKNOWN_REASON), shortReason = "?" }
end

---@return { unit: string, name: string, fullName: string, initials: string, isOnQuest: boolean, sharedQuest: table?, status: table }[] members
---Empty when solo; sharedQuest holds the counts the member's addon sent (Comms.getRemoteQuest), status what they
---are to the quest (Party.getStatus)
function Party.getMembers(questId)
    local members = {}
    if not UnitExists or not C_QuestLog.IsUnitOnQuest then
        return members
    end
    for memberIndex = 1, MAX_PARTY_MEMBERS do
        local unit = "party" .. memberIndex
        if UnitExists(unit) then
            local name = UnitName(unit)
            if type(name) == "string" then
                -- Their addon's counts are keyed by name and, for another realm, the realm
                local fullName = GetUnitName and GetUnitName(unit, true) or name
                local sharedQuest = ns.Comms and ns.Comms.getRemoteQuest(fullName, questId)
                local member = {
                    unit = unit,
                    name = name,
                    fullName = fullName,
                    initials = Party.getInitials(name),
                    isOnQuest = C_QuestLog.IsUnitOnQuest(unit, questId) == true or sharedQuest ~= nil,
                    sharedQuest = sharedQuest,
                }
                member.status = Party.getStatus(member, questId)
                members[#members + 1] = member
            end
        end
    end
    return members
end

local function normalize(text)
    return (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
end

---Gives each member their class and a count per objective, unknown (false) until read.
---@return table byName [normalized name] = member, to find a member by a tooltip line
local function prepareMembers(members, objectives)
    local byName = {}
    for _, member in ipairs(members) do
        -- Not "UnitClass and UnitClass(...)": "and" would keep only the first value, the class's name
        local classFile = UnitClass and select(2, UnitClass(member.unit)) or nil
        member.classFile, member.counts = classFile, {}
        for index = 1, #objectives do
            member.counts[index] = false
        end
        byName[normalize(member.name)] = member
    end
    return byName
end

---@return table[] lines The game's party progress lines for a quest; none when it withholds them
local function readPartyProgressLines(questId)
    local getProgress = C_TooltipInfo and C_TooltipInfo.GetQuestPartyProgress
    local isSuccess, tooltip = false, nil
    if getProgress then
        isSuccess, tooltip = pcall(getProgress, questId, true, true)
    end
    return isSuccess and type(tooltip) == "table" and tooltip.lines or {}
end

---@return table count An objective's count read from a member's line: "4/10", or for a one-off objective without a
---count, done when the game greys it out
local function readLineCount(line, text)
    local fulfilled, required = text:match("(%d+)%s*/%s*(%d+)")
    fulfilled, required = tonumber(fulfilled), tonumber(required)
    if not required then
        local color = line.leftColor
        local isGrey = type(color) == "table"
            and math.abs((color.r or 1) - (color.g or 1)) < 0.05
            and (color.r or 1) < 0.8
        fulfilled, required = isGrey and 1 or 0, 1
    end
    return { fulfilled = fulfilled, required = required, isDone = fulfilled >= required }
end

---Reads the game's lines into the members' counts: a member's name, then their objectives, matched by words.
local function readGameCounts(questId, objectives, byName)
    local current
    for _, line in ipairs(readPartyProgressLines(questId)) do
        local text = normalize(line.leftText)
        local member = byName[text] or byName[(text:match("^(%S+)") or "")]
        if member then
            current = member
        elseif current and text ~= "" then
            for index, objective in ipairs(objectives) do
                if text:find(normalize(objective.label), 1, true) then
                    current.counts[index] = readLineCount(line, text)
                end
            end
        end
    end
end

---Exact counts sent by a member's addon win over the game's lines, which may be withheld or out of date.
---@return boolean isAnyUnknown A member is not on the quest, and nothing says why
local function applySharedCounts(members, objectives)
    local isAnyUnknown = false
    for _, member in ipairs(members) do
        isAnyUnknown = isAnyUnknown or member.status.state == "unknown"
        for index, count in ipairs(member.sharedQuest and member.sharedQuest.objectives or {}) do
            if index <= #objectives then
                member.counts[index] =
                    { fulfilled = count.fulfilled, required = count.required, isDone = count.isFinished }
            end
        end
    end
    return isAnyUnknown
end

---Each party member's progress on a quest's objectives, read from the lines the game gives its own quest
---tooltips: a member's name, then their objectives, each with its count. An objective is matched to the
---player's own by its words. The game withholds the lines inside dungeons and raids, and a member who does
---not have the quest has none; their counts are then unknown.
---@param objectives { label: string, required: number }[] The player's objectives, in their order
---@param hasEvent boolean? The quest's goal is an event (an escort, a place to explore), not nothing at all
---@return { name: string, unit: string, classFile: string?, isOnQuest: boolean, counts: ({ fulfilled: number, required: number, isDone: boolean }|false)[], share: number?, objectives: table[] }[] members
---share is how much of the quest they have done, 0 to 1, nil when it cannot be told
function Party.getProgress(questId, objectives, hasEvent)
    local members = Party.getMembers(questId)
    if #members == 0 then
        return members
    end
    readGameCounts(questId, objectives, prepareMembers(members, objectives))
    local isAnyUnknown = applySharedCounts(members, objectives)
    if isAnyUnknown and ns.Comms then
        ns.Comms.askStatus(questId) -- their OneMoreQuest can say whether they did it already, or could take it
    end
    for _, member in ipairs(members) do
        member.objectives = objectives
        member.share = member.isOnQuest and Party.getShare(member, hasEvent) or nil
    end
    return members
end

---@return number? share How much of the quest a member on it has done, 0 to 1: their counts together, each
---objective's up to what it asks; for a quest with nothing to count, 1 when ready and 0 when not yet. Nil when
---a count is unknown (inside a dungeon, without their addon).
function Party.getShare(member, hasEvent)
    if member.sharedQuest and member.sharedQuest.isComplete then
        return 1
    end
    local counts = member.counts or {}
    if #counts == 0 then
        local word = Party.getReadiness(member, hasEvent)
        return word == "ready" and 1 or word == "not yet" and 0 or nil
    end
    local done, total = 0, 0
    for _, count in ipairs(counts) do
        if not count then
            return nil
        end
        done, total = done + math.min(count.fulfilled, count.required), total + count.required
    end
    return total > 0 and done / total or nil
end

---Whether a member on the quest is ready to hand it in, for quests whose party row is a single one (nothing to
---count, or the player's own part done): from their addon's counts, else from the game's lines.
---@param hasEvent boolean The quest's goal is an event (an escort, a place to explore) rather than nothing at all
---@return string word "ready", "not yet" or "?"
function Party.getReadiness(member, hasEvent)
    if member.sharedQuest then
        return member.sharedQuest.isComplete and "ready" or "not yet"
    end
    local counts = member.counts or {}
    if #counts == 0 then
        return hasEvent and "?" or "ready" -- a talk-to quest has nothing to do before the turn-in
    end
    local isKnown = true
    for _, count in ipairs(counts) do
        if count and not count.isDone then
            return "not yet"
        end
        isKnown = isKnown and count ~= false
    end
    return isKnown and "ready" or "?"
end

---A member's count for one objective as short text: a tick when done, "4/10", or "?" when unknown.
---@param isOnPaper boolean? For the quest page's parchment: dark ink rather than white
---@return string text
function Party.formatCount(count, isOnPaper)
    if count and count.isDone then
        return "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
    end
    local faint, plain = isOnPaper and "8a7a5a" or "a0a0a0", isOnPaper and "2b1d0e" or "ffffff"
    if not count then
        return "|cff" .. faint .. "?|r"
    end
    local color = count.fulfilled == 0 and faint or plain
    return string.format("|cff%s%d/%d|r", color, count.fulfilled, count.required)
end

local RACE_PORTRAIT = "Interface\\CharacterFrame\\TemporaryPortrait-%s-%s"
local STATE_COLORS = {
    has = { 1, 1, 1 },
    done = { 0.49, 0.88, 0.49 },
    can = { 1, 0.82, 0 },
    cannot = { 1, 0.4, 0.3 },
    unknown = { 0.66, 0.66, 0.66 },
}
Party.STATE_COLORS = STATE_COLORS

---Puts a member's face on a texture as the game's party frames show it; while the game cannot draw it (they
---are out of sight), its portrait of their race and sex.
function Party.setPortrait(texture, unit)
    texture:SetTexCoord(0, 1, 0, 1)
    if SetPortraitTexture and (not UnitIsVisible or UnitIsVisible(unit)) then
        SetPortraitTexture(texture, unit)
        return
    end
    local _, raceFile = UnitRace(unit)
    local sex = UnitSex and UnitSex(unit)
    if raceFile then
        texture:SetTexture(string.format(RACE_PORTRAIT, sex == 3 and "Female" or "Male", raceFile))
    else
        texture:SetTexture("Interface\\CharacterFrame\\TemporaryPortrait")
    end
end

---@return number red, number green, number blue A class's colour, as the game's raid frames give it; white unknown
local function getClassColor(classFile)
    local classColor = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not classColor then
        return 1, 1, 1
    end
    return classColor.r or 1, classColor.g or 1, classColor.b or 1
end

---A member under the mouse: their name in their class's colour, then on the quest how far they are and every
---count; off it, why.
function Party.addMemberToTooltip(tooltip, member)
    local _, classFile = UnitClass(member.unit)
    tooltip:AddLine(member.name, getClassColor(classFile))
    if not member.isOnQuest then
        local color = STATE_COLORS[member.status.state]
        tooltip:AddLine(member.status.reason, color[1], color[2], color[3], true)
        return
    end
    if member.share == 1 then
        tooltip:AddLine(ns.L("Ready to turn in"), STATE_COLORS.done[1], STATE_COLORS.done[2], STATE_COLORS.done[3])
    elseif member.share == nil then
        tooltip:AddLine(
            ns.L("On the quest; how far is unknown here (inside a dungeon, without their addon)"),
            0.66,
            0.66,
            0.66,
            true
        )
    else
        tooltip:AddLine(ns.L("In progress, %d%%", math.floor(member.share * 100 + 0.5)), 1, 1, 1)
    end
    for index, objective in ipairs(member.objectives or {}) do
        local count = member.counts and member.counts[index]
        local shade = count and count.isDone and 0.6 or 1
        tooltip:AddDoubleLine(
            (objective.shownLabel or objective.label),
            Party.formatCount(count),
            shade,
            shade,
            shade,
            1,
            1,
            1
        )
    end
end

---Adds the party's progress to a tooltip as the game's own quest tooltips show it: each member's name, then
---their objectives under it, "- 4/7 Plainstrider Beak", greyed once done; a member not on the quest gets why
---beside their name.
---@param objectives { label: string, required: number }[]
function Party.addProgressToTooltip(tooltip, questId, objectives)
    local members = Party.getProgress(questId, objectives)
    if #members == 0 then
        return
    end
    tooltip:AddLine(" ")
    tooltip:AddLine(ns.L("Party"), 1, 0.82, 0)
    for _, member in ipairs(members) do
        local red, green, blue = getClassColor(member.classFile)
        if not member.isOnQuest then
            -- Why not, in a word or two, as the badge on their face says it: done it, can take it, the level
            local color = STATE_COLORS[member.status.state]
            local word = member.status.state == "unknown" and ns.L("not on it") or member.status.shortReason
            tooltip:AddDoubleLine(member.name, word, red, green, blue, color[1], color[2], color[3])
        else
            tooltip:AddLine(member.name, red, green, blue)
            for index, objective in ipairs(objectives) do
                local count = member.counts[index]
                local countText = count and (count.fulfilled .. "/" .. count.required .. " ")
                    or "?/" .. objective.required .. " "
                local shade = count and count.isDone and 0.6 or 1
                tooltip:AddLine("  - " .. countText .. (objective.shownLabel or objective.label), shade, shade, shade)
            end
        end
    end
end

-- GROUP_ROSTER_UPDATE comes often in a group without anyone joining or leaving: redraw only when who is in the
-- group, or who of them is online, changed
local lastRoster

ns.registerModule({
    name = "Party",
    changes = {
        GROUP_ROSTER_UPDATE = function()
            local parts = {}
            for _, unit in ipairs(Party.getUnits()) do
                parts[#parts + 1] = tostring(UnitGUID and UnitGUID(unit) or UnitName and UnitName(unit))
                    .. (UnitIsConnected and not UnitIsConnected(unit) and "-" or "+")
            end
            local roster = table.concat(parts, ",")
            local changed = roster ~= lastRoster
            lastRoster = roster
            return changed
        end,
    },
})
