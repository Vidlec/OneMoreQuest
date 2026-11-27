local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: "Need a hint?", the page's button, and the hint ladder it opens (the tracker opens the
-- same one, Log.showHintLadder): the Spoilers hints for one quest, a step at a time, each telling a little more.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local COLORS, DOT, MEDIA, PADDING, READY_ICON = Style.COLORS, Style.DOT, Style.MEDIA, Style.PADDING, Style.READY_ICON
local Spoiled = QuestPage.Spoiled
local addPaperButton = QuestPage.addPaperButton

local HINT_GLOW_OUTER, HINT_GLOW_INNER = { 1, 0.82, 0.2, 0.22 }, { 1, 0.82, 0.2, 0.38 }

function Spoiled.openHintLadder(data)
    Log.showHintLadder(data.questId, data.button)
end

---The page's "Need a hint?" button, at the right: while a hint could show more of the quest. When it offers itself
---(Spoilers: hints "offered", stuck a while in the quest's zone) a soft gold glow round it.
---@return number y Below it
function Spoiled.addHintButton(y, questId)
    local text = ns.L("Need a hint?")
    local right = State.detail.width - PADDING
    if ns.Spoilers.isHintOffered(questId) then
        local width = #text * 6.5 + 18 -- (as addPaperButton measures it)
        State.detail:addRect(right - width - 5, y - 5, width + 10, 30, HINT_GLOW_OUTER, 2)
        State.detail:addRect(right - width - 2, y - 2, width + 4, 24, HINT_GLOW_INNER, 3)
    end
    local data = { questId = questId }
    local _, button = addPaperButton(State.detail, right, y, text, Spoiled.openHintLadder, data)
    data.button = button
    return y + 32
end

do
    local LADDER_WIDTH, STEP_HEIGHT, LADDER_TOP = 290, 42, 46
    local LADDER_EDGE, LADDER_BACK = { 0.42, 0.29, 0.13 }, { 0.03, 0.02, 0.01, 0.96 }
    local STEP_WORDS = {
        { title = "Which zone", note = "The zone its objectives are in" },
        { title = "Roughly where", note = "An area on the map, and where to hand it in" },
        { title = "Exactly where, and who drops it", note = "Every spawn, with chances" },
    }
    local DONE_COLOR, NEXT_COLOR, LATER_COLOR = { 0.85, 0.81, 0.66 }, { 1, 0.82, 0 }, { 0.5, 0.48, 0.44 }
    local ladder -- made the first time it opens

    local function setColor(text, color)
        text:SetTextColor(color[1], color[2], color[3])
    end

    ---@return string note What a step of the ladder says under its title: once the first is taken, its answer
    local function composeStepNote(index, words, isDone, questId)
        if index ~= 1 or not isDone then
            return ns.L(words.note)
        end
        -- The first step's answer: the zone of the quest's next step
        local entry = ns.QuestState.isInLog(questId) and ns.Model.composeEntry(questId, ns.Model.getPlayer())
        return entry and entry.zoneId and ns.Database.getZoneName(entry.zoneId) or ns.L("Unknown location")
    end

    ---A step's mark: a tick once taken, a gold arrow for the next, a grey dot for the later ones.
    local function setStepMark(mark, isDone, isNext)
        if isDone then
            mark:SetTexture(READY_ICON)
            mark:SetVertexColor(1, 1, 1)
            mark:SetSize(14, 14)
        elseif isNext then
            mark:SetTexture(MEDIA .. "ChevronRight")
            mark:SetVertexColor(NEXT_COLOR[1], NEXT_COLOR[2], NEXT_COLOR[3])
            mark:SetSize(12, 12)
        else
            mark:SetTexture("Interface\\Buttons\\WHITE8X8")
            mark:SetVertexColor(LATER_COLOR[1], LATER_COLOR[2], LATER_COLOR[3])
            mark:SetSize(4, 4)
        end
    end

    ---Fills the ladder for its quest: each step done (a tick), the next (an arrow, to click), the later ones greyed.
    local function fillLadder()
        if not ladder or not ladder:IsShown() then
            return
        end
        local questId = ladder.questId
        local step = ns.Spoilers.getHint(questId)
        ladder.title:SetText(ns.L("Need a hint?"))
        ladder.questName:SetText(
            ns.QuestText.getQuestName(questId)
                or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questId))
                or ("Quest " .. questId)
        )
        for index, words in ipairs(STEP_WORDS) do
            local row = ladder.rows[index]
            local isDone, isNext = index <= step, index == step + 1
            row.title:SetText(index .. DOT .. ns.L(words.title))
            row.note:SetText(composeStepNote(index, words, isDone, questId))
            setColor(row.title, isDone and DONE_COLOR or isNext and NEXT_COLOR or LATER_COLOR)
            setColor(row.note, isDone and DONE_COLOR or isNext and COLORS.white or LATER_COLOR)
            setStepMark(row.mark, isDone, isNext)
            row.isNext = isNext and ns.Spoilers.canHint(questId)
            row.hover:SetShown(row.isNext)
        end
        ladder.footnote:SetText(
            ns.L("A hint stays for this quest only. The Chronicle counts quests done with no hints.")
        )
        local footHeight = ladder.footnote:GetStringHeight()
        ladder:SetHeight(
            LADDER_TOP + #STEP_WORDS * STEP_HEIGHT + 8 + (type(footHeight) == "number" and footHeight or 24) + 12
        )
    end

    local function createLadder()
        ladder = CreateFrame("Frame", "OneMoreQuestHintLadder", UIParent, "BackdropTemplate")
        ladder:SetWidth(LADDER_WIDTH)
        ladder:SetFrameStrata("FULLSCREEN_DIALOG") -- over the map and the quest window beside it
        ladder:SetToplevel(true)
        ladder:SetClampedToScreen(true)
        ladder:EnableMouse(true)
        Style.setEdged(ladder, LADDER_EDGE, LADDER_BACK)
        ladder.title = ns.Widgets.createFontString(ladder, "OVERLAY", "GameFontNormal")
        ladder.title:SetPoint("TOPLEFT", ladder, "TOPLEFT", 12, -10)
        ladder.questName = ns.Widgets.createFontString(ladder, "OVERLAY", "GameFontHighlightSmall")
        ladder.questName:SetPoint("TOPLEFT", ladder.title, "BOTTOMLEFT", 0, -3)
        ladder.questName:SetPoint("RIGHT", ladder, "RIGHT", -28, 0)
        ladder.questName:SetJustifyH("LEFT")
        ladder.questName:SetWordWrap(false)
        setColor(ladder.questName, DONE_COLOR)
        Style.addCloseButton(ladder, 8)
        ladder.rows = {}
        for index = 1, #STEP_WORDS do
            local row = CreateFrame("Button", nil, ladder)
            row:SetPoint("TOPLEFT", ladder, "TOPLEFT", 1, -LADDER_TOP - (index - 1) * STEP_HEIGHT)
            row:SetPoint("RIGHT", ladder, "RIGHT", -1, 0)
            row:SetHeight(STEP_HEIGHT)
            row.hover = row:CreateTexture(nil, "HIGHLIGHT")
            row.hover:SetAllPoints(row)
            row.hover:SetColorTexture(1, 0.82, 0.2, 0.1)
            row.mark = row:CreateTexture(nil, "ARTWORK")
            row.mark:SetPoint("CENTER", row, "TOPLEFT", 19, -14)
            row.title = ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlight")
            row.title:SetPoint("TOPLEFT", row, "TOPLEFT", 32, -6)
            row.note = ns.Widgets.createFontString(row, "OVERLAY", "GameFontHighlightSmall")
            row.note:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3)
            for _, text in ipairs({ row.title, row.note }) do
                text:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                text:SetJustifyH("LEFT")
                text:SetWordWrap(false)
            end
            -- Only the next step takes a click: one step at a time
            row:SetScript("OnClick", function(self)
                if self.isNext then
                    ns.Spoilers.giveHint(ladder.questId)
                end
            end)
            ladder.rows[index] = row
        end
        ladder.footnote = ns.Widgets.createFontString(ladder, "OVERLAY", "GameFontHighlightSmall")
        ladder.footnote:SetPoint("TOPLEFT", ladder, "TOPLEFT", 12, -LADDER_TOP - #STEP_WORDS * STEP_HEIGHT - 8)
        ladder.footnote:SetPoint("RIGHT", ladder, "RIGHT", -12, 0)
        ladder.footnote:SetJustifyH("LEFT")
        ladder.footnote:SetWordWrap(true)
        setColor(ladder.footnote, LATER_COLOR)
        ladder:Hide()
        if type(UISpecialFrames) == "table" then
            table.insert(UISpecialFrames, "OneMoreQuestHintLadder") -- Escape closes it, as the game's own windows
        end
    end

    ---Opens "Need a hint?" for a quest, the ladder of three steps: the zone, roughly where, exactly where. The
    ---page's button and the tracker open it; under what opened it, else in the middle of the screen. Opened again
    ---for the same quest, it closes.
    ---@param anchorFrame table? What it opens under
    function Log.showHintLadder(questId, anchorFrame)
        if not questId or not CreateFrame or not UIParent then
            return
        end
        if not ladder then
            createLadder()
        end
        if ladder:IsShown() and ladder.questId == questId and ladder.anchorFrame == anchorFrame then
            ladder:Hide()
            return
        end
        ladder.questId, ladder.anchorFrame = questId, anchorFrame
        ladder:ClearAllPoints()
        -- Where it opens is fixed on the screen: the page's buttons are reused once it is drawn again
        local right, bottom =
            anchorFrame and anchorFrame.GetRight and anchorFrame:GetRight(),
            anchorFrame and anchorFrame.GetBottom and anchorFrame:GetBottom()
        local scale = type(right) == "number" and anchorFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
        if type(right) == "number" and type(bottom) == "number" and type(scale) == "number" then
            ladder:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right * scale, bottom * scale - 4)
        else
            ladder:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        ladder:Show()
        fillLadder()
    end

    ---@return table? ladder The ladder's frame, for the tests
    function Log.getHintLadder()
        return ladder
    end

    ns.on("SPOILERS_CHANGED", fillLadder) -- a step taken (here or in the tracker), a choice changed
end
