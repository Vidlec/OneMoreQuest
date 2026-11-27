local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: the party on a quest's page, under its own fold. Who of the group is on the quest and how
-- far: their faces in rings with the mouse; with a controller a row each, A sharing the quest with one who can take
-- it and Y opening their menu.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local COLORS, PADDING = Style.COLORS, Style.PADDING
local addFold = QuestPage.addFold

local PARTY_FACE = 24 -- a member's face on their row (controller)
local PARTY_ROW_HEIGHT = 34

---@return string text Where a member is with the quest, in a few words: their first count not done ("5/7 Plainstrider
---Beak"), done, or why they are not on it
---@return number[] color
---@return boolean canTake They can take it: sharing it with the party would give it to them
local function describeMember(member)
    local status = member.status or {}
    if status.state == "has" then
        if member.share == 1 then
            return ns.L("Done, ready to turn in"), COLORS.darkGreen, false
        end
        for index, count in ipairs(member.counts or {}) do
            local objective = member.objectives and member.objectives[index]
            if count and not count.isDone and objective then
                return string.format(
                    "%d/%d %s",
                    count.fulfilled,
                    count.required,
                    objective.shownLabel or objective.label
                ),
                    COLORS.ink,
                    false
            end
        end
        return ns.L("On this quest"), COLORS.ink, false
    elseif status.state == "can" then
        return ns.L("Not on it, can take it"), COLORS.brown, true
    elseif status.state == "done" then
        return ns.L("Done it already"), COLORS.softInk, false
    elseif status.state == "cannot" then
        return status.reason or ns.L("Not on it"), COLORS.softInk, false -- (why, in a few words: a level, a quest before)
    end
    return ns.L("Not on it"), COLORS.softInk, false -- (nothing known yet: the tooltip says what could be the reason)
end

---A member's menu (Y on their row): whisper them; share the quest when they can take it.
local function openMemberMenu(member)
    if type(MenuUtil) ~= "table" or not MenuUtil.CreateContextMenu then
        return
    end
    local _, _, canTake = describeMember(member)
    ns.openMenu(nil, function(_, root)
        root:CreateTitle(member.name)
        root:CreateButton(ns.L("Whisper"), function()
            if ChatFrame_SendTell then
                ChatFrame_SendTell(member.fullName or member.name)
            end
        end)
        if canTake and member.questId then
            root:CreateButton(ns.L("Share with the party"), function()
                ns.Log.shareQuest(member.questId)
            end)
        end
    end)
end

local function showMemberTooltip(button, member)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    ns.Party.addMemberToTooltip(GameTooltip, member)
    GameTooltip:Show()
end

local function pressMember(member)
    local _, _, canTake = describeMember(member)
    if canTake and member.questId then
        ns.Log.shareQuest(member.questId)
    end
end

---The party as rows (with a controller): each member's face in its ring, their name, and where they are with the
---quest; the row is one stop for the cursor, its tooltip the faces' own, A shares the quest with a member who can
---take it, Y opens their menu.
---@return number y Below the rows
function QuestPage.addPartyRows(y, entry, members)
    local width = State.detail.width - 2 * PADDING
    for _, member in ipairs(members) do
        member.questId = entry.questId
        local text, color, canTake = describeMember(member)
        local faceTop = y + (PARTY_ROW_HEIGHT - ns.Widgets.getPortraitSize(PARTY_FACE)) / 2
        State.detail:addPortrait(PADDING, faceTop, PARTY_FACE, member)
        local textLeft = PADDING + ns.Widgets.getPortraitSize(PARTY_FACE) + 8
        State.detail:addText(
            member.name,
            textLeft,
            y + 3,
            { font = "GameFontNormal", color = COLORS.ink, width = width - textLeft, isSingleLine = true }
        )
        State.detail:addText(
            text,
            textLeft,
            y + 18,
            { font = "GameFontHighlightSmall", color = color, width = width - textLeft + PADDING, isSingleLine = true }
        )
        local button = State.detail:addButton(
            PADDING - 4,
            y,
            width + 8,
            PARTY_ROW_HEIGHT,
            pressMember,
            member,
            showMemberTooltip,
            openMemberMenu
        )
        button.canShareWith = canTake
        y = y + PARTY_ROW_HEIGHT + 2
    end
    return y
end

---The party's faces across the row, large, each in a ring that fills with their progress; the rest on hover.
---@return number y Below them
local function addPartyFaces(y, members)
    local rowWidth = State.detail.width - 2 * PADDING
    local slotWidth = rowWidth / math.max(#members, 1)
    local faceSize = math.min(52, math.floor(math.min(slotWidth, rowWidth / 4) - 22))
    local size = ns.Widgets.getPortraitSize(faceSize)
    for index, member in ipairs(members) do
        State.detail:addPortrait(PADDING + (index - 0.5) * slotWidth - size / 2, y + 2, faceSize, member)
    end
    y = y + size + 8
    return y
        + State.detail:addText(ns.L("Hover a face for their name and progress, or why not"), PADDING, y, {
            font = "GameFontHighlightSmall",
            color = COLORS.softInk,
            width = rowWidth,
            justify = "CENTER",
            isSingleLine = true,
        })
        + 10
end

---The party, a part that folds as the ones below it do; its note says how many of them are on the quest.
---@return number y Below it, unchanged out of a party
local function addPartySection(y, entry)
    local partyMembers = ns.Party.getMembers(entry.questId)
    if #partyMembers == 0 then
        return y
    end
    local onQuestCount = 0
    for _, member in ipairs(partyMembers) do
        onQuestCount = onQuestCount + (member.isOnQuest and 1 or 0)
    end
    local isPartyOpen
    y, isPartyOpen =
        addFold(y, "party", entry.questId, ns.L("Party"), ns.L("%d of %d on it", onQuestCount, #partyMembers), true)
    if not isPartyOpen then
        return y
    end
    local members = ns.Party.getProgress(entry.questId, entry.objectives, entry.eventText ~= nil and not entry.isTurnIn)
    if ns.Gamepad.isGamepadUI() then
        -- With a controller: a row a member, its words saying where they are with the quest, for the cursor to
        -- stop on (the faces' hover is out of the pad's reach)
        return QuestPage.addPartyRows(y, entry, members) + 6
    end
    return addPartyFaces(y, members)
end

-- Shared with the other parts of the window
QuestPage.addPartySection = addPartySection
