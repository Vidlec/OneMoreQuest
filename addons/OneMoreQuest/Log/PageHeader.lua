local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: the page's header, the bar pinned above the page (State.pageHeader): the quest's title in
-- the game's header art, its chain badge, the facts line with its zone to click, the narration's buttons, and a way
-- back.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local COLORS, LIST_WIDTH, MEDIA, PADDING, PAGE_CONTENT_WIDTH, PAGE_TOP =
    Style.COLORS, Style.LIST_WIDTH, Style.MEDIA, Style.PADDING, Style.PAGE_CONTENT_WIDTH, Style.PAGE_TOP

local HEADER_FILL, HEADER_EDGE = { 0.2, 0.07, 0.05 }, { 0.54, 0.48, 0.29 }
local HEADER_ART_RIM = 5 -- texels of darker rim on the left of the header's art
local HEADER_BADGE_TEXT = { 0.91, 0.86, 0.75 }

-- State.pageHeader: the bar pinned above the page; created with the window
local BADGE_HEIGHT = 18
local HEADER_FRINGE_SHARE = 9 / 52 -- the lower part of the header art that is a fringe over the page, as in the game's layout
local HEADER_FRINGE = 9 -- that fringe, texels and pixels: drawn at its own height however tall the header is
local PLAIN_PAGE_GAP = 6 -- between the header's shadow and a page that is not a quest's (settings, Chronicle)
local HEADER_CORNER = { 28, 23 } -- the gold flourishes in the header's lower corners (small: clear of the facts line)

local HEADER_BOTTOM_PADDING = 20 -- room under the last line (the facts, or the narration's buttons) to the header art's lower edge
local VOICE_ROW_HEIGHT = 26 -- the narration's buttons under the facts, with the gap above them

local setPageHeader
do
    ---For a quest in a chain, the tracker's badge with its step, wide enough for its words.
    local function setHeaderBadge(header, chainIndex, chainTotal)
        header.badge:SetShown(chainIndex ~= nil)
        if not chainIndex then
            return
        end
        header.badgeText:SetText(ns.L("%d of %d", chainIndex, chainTotal))
        local textWidth = header.badgeText:GetStringWidth()
        -- Edge, icon, gap, text, edge
        header.badge:SetWidth(12 + 4 + (type(textWidth) == "number" and textWidth or 36))
    end

    ---The title runs to the badge when there is one, else to the header's edge.
    local function placeHeaderTitle(header, title, chainIndex)
        header.title:ClearAllPoints()
        header.title:SetPoint("TOPLEFT", header, "TOPLEFT", PADDING, -10)
        header.title:SetPoint(
            "RIGHT",
            chainIndex and header.badge or header,
            chainIndex and "LEFT" or "RIGHT",
            chainIndex and -8 or -PADDING,
            0
        )
        header.title:SetText(title)
    end

    ---@return number width, number height A part of the facts line, measured in its font
    local function measureFacts(header, text)
        header.measure:SetText(text)
        local width, height = header.measure:GetStringWidth(), header.measure:GetStringHeight()
        return type(width) == "number" and width or #text * 6, type(height) == "number" and height or 12
    end

    ---A link in the facts (the zone, "Wowhead"), underlined over a button of its own size, as the page's place links
    ---are. A link the line would wrap onto a second line is left out, as the button is placed on the first.
    ---@return boolean isShown
    local function setFactsLink(header, button, link)
        local beforeWidth = link and measureFacts(header, link.before) or 0
        local linkWidth, lineHeight = 0, 0
        if link then
            linkWidth, lineHeight = measureFacts(header, link.text)
        end
        local isShown = link ~= nil and beforeWidth + linkWidth <= PAGE_CONTENT_WIDTH - 2 * PADDING
        button:SetShown(isShown)
        button.underline:SetShown(isShown)
        if not isShown then
            return false
        end
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", header.facts, "TOPLEFT", beforeWidth - 2, 2)
        button:SetSize(linkWidth + 4, lineHeight + 4)
        button.underline:ClearAllPoints()
        button.underline:SetPoint("TOPLEFT", header.facts, "TOPLEFT", beforeWidth, -lineHeight)
        button.underline:SetSize(linkWidth, 1)
        button.handleClick, button.data = link.handleClick, link.data
        return true
    end

    ---A quest's facts end in "Wowhead", the link to its page there (WowheadLink: a panel to copy it from).
    ---@return string factsText The facts with the link, when it fits on their first line
    local function setHeaderWowheadLink(header, factsText, questId)
        local link = questId
            and {
                before = factsText ~= "" and (factsText .. Style.DOT) or "",
                text = ns.L("Wowhead"),
                handleClick = ns.WowheadLink.show,
                data = questId,
            }
        if setFactsLink(header, header.wowheadButton, link) then
            return link.before .. link.text
        end
        return factsText
    end

    ---@return number height The title and the facts under it, with the room to the header art's lower edge
    local function measureHeaderText(header)
        local titleHeight, factsHeight = header.title:GetStringHeight(), header.facts:GetStringHeight()
        return 10
            + math.max(type(titleHeight) == "number" and titleHeight or 16, BADGE_HEIGHT)
            + 4
            + (type(factsHeight) == "number" and factsHeight or 12)
            + HEADER_BOTTOM_PADDING
    end

    ---@return string? text Where the narration is, while it plays or waits
    local function composeVoiceStateText(voiceState, voicePosition)
        if voiceState == "playing" then
            return ns.L("playing now")
        elseif voiceState == "paused" then
            return ns.L("paused")
        elseif voiceState == "queued" then
            return ns.L("number %d in the queue", voicePosition or 1)
        end
        return nil
    end

    ---A quest a translation addon has narrated: its buttons under the facts, and where the narration is.
    ---@return number height The room the buttons take, 0 without a narration
    local function setHeaderVoice(header, questId)
        local voice = header.voice
        local voiceState, voicePosition = ns.QuestText.getVoiceState(questId)
        voice:SetShown(voiceState ~= nil)
        voice.questId = questId
        if not voiceState then
            return 0
        end
        local _, provider = ns.QuestText.getVoice()
        Log.setButtonText(voice.playButton, ns.L(voiceState == "playing" and "Stop" or "Play"))
        Log.setButtonText(voice.queueButton, ns.L(voiceState == "queued" and "Unqueue" or "Queue"))
        voice.queueButton:SetShown(voiceState ~= "playing")
        voice.text:SetPoint("LEFT", voiceState == "playing" and voice.playButton or voice.queueButton, "RIGHT", 8, 0)
        -- Where it is, while it plays or waits; who narrates, while idle (the page is narrow for both)
        voice.text:SetText(
            composeVoiceStateText(voiceState, voicePosition)
                or ns.L("Narration by %s", provider and provider.label or "?")
        )
        return VOICE_ROW_HEIGHT
    end

    ---@return number overlap How far the page runs up under the header
    local function getPageOverlap(header, title, questId, height)
        -- The header's art ends in a soft fringe over the page, as the game's own does; the page starts under
        -- that fringe, so its text and the "more above" shade run right up to the header
        -- Only a quest's page runs up under the fringe: the settings and the Chronicle start below it, with room to
        -- breathe (their first line stood right against the header)
        if not title then
            return 0
        elseif questId == nil then
            return -PLAIN_PAGE_GAP
        elseif not header.hasArt then
            return 0
        end
        return header.hasFringeApart == true and HEADER_FRINGE or math.floor(height * HEADER_FRINGE_SHARE)
    end

    ---The page's header in the look of the game's window titles: a dark red bar with the quest's name in gold,
    ---a line of facts under it, and for a quest in a chain the tracker's badge with its step. It is pinned
    ---above the scrolling page and spans it edge to edge, scroll bar included.
    ---@param title string? nil takes the header away, and the page starts at the top again
    ---@param zoneLink { before: string, text: string, handleClick: function, data: any }? A zone in the facts line to
    ---click, to turn the map there: `before` is the facts' text ahead of it
    ---@param questId number? The quest the page is about: shift-clicking its title links it in chat
    function setPageHeader(title, factsText, chainIndex, chainTotal, zoneLink, questId)
        local header = State.pageHeader
        if not header then
            return
        end
        header.backButton:Hide() -- shown by Log.setPageHeaderBack, after the header is set
        if header.questId ~= questId then
            ns.WowheadLink.hide() -- (the panel opened under this quest's "Wowhead": another page now)
        end
        header.questId = questId
        header.titleButton:SetShown(questId ~= nil)
        -- The seal is a quest giver's: on a quest's page only, not on the settings, the Chronicle or a dungeon
        if type(header.seal) == "table" then
            header.seal:SetShown(questId ~= nil)
        end
        local height = 0
        if title then
            setHeaderBadge(header, chainIndex, chainTotal)
            placeHeaderTitle(header, title, chainIndex)
            header.facts:SetText(setHeaderWowheadLink(header, factsText or "", questId))
            setFactsLink(header, header.zoneButton, zoneLink)
            height = measureHeaderText(header) + setHeaderVoice(header, questId)
            header:SetHeight(height)
        end
        header:SetShown(title ~= nil)
        State.detail.frame:SetPoint(
            "TOPLEFT",
            State.frame,
            "TOPLEFT",
            State.frame.pageLeft or LIST_WIDTH + 2,
            -PAGE_TOP - height + getPageOverlap(header, title, questId, height)
        )
    end
end

---One piece of the game's art on the header, turned over (flipX, flipY) by its texture coordinates when asked.
---@return Texture? texture nil when this client has no such art
local function addOrnament(header, atlas, width, height, layer, flipX, flipY)
    local info = C_Texture.GetAtlasInfo(atlas)
    if not info then
        return nil
    end
    local texture = header:CreateTexture(nil, layer, nil, 2)
    texture:SetAtlas(atlas)
    texture:SetSize(width, height)
    if (flipX or flipY) and texture.SetTexCoord then
        local left, right, top, bottom = 0, 1, 0, 1 -- (the atlas's own coordinates)
        if flipX then
            left, right = right, left
        end
        if flipY then
            top, bottom = bottom, top
        end
        texture:SetTexCoord(left, right, top, bottom)
    end
    return texture
end

---The header's flair, all the game's own art, on its lower edge where it never covers the title, the facts, the
---narration's buttons or the chain's badge: a small gold filigree in the middle of the line between the wood and the
---parchment, gold flourishes in both lower corners (the game's parchment popups' corner, turned over), and the
---player's faction's wax seal pressed over the right corner, as on an order sealed by the quest giver. Drawn once.
local function addHeaderOrnaments(header)
    local filigree = addOrnament(header, "banner-smallfiligree", 61, 19, "ARTWORK")
    if filigree then
        filigree:SetPoint("BOTTOM", header, "BOTTOM", 0, 0)
    end
    local leftCorner =
        addOrnament(header, "parchmentpopup-filigree", HEADER_CORNER[1], HEADER_CORNER[2], "ARTWORK", false, true)
    if leftCorner then
        leftCorner:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 1, HEADER_FRINGE - 2)
    end
    local rightCorner =
        addOrnament(header, "parchmentpopup-filigree", HEADER_CORNER[1], HEADER_CORNER[2], "ARTWORK", true, true)
    if rightCorner then
        rightCorner:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -1, HEADER_FRINGE - 2)
    end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local seal = faction == "Horde" and "quest-horde-waxseal"
        or faction == "Alliance" and "quest-alliance-waxseal"
        or nil
    header.seal = seal and addOrnament(header, seal, 50, 47, "OVERLAY")
    if header.seal then
        header.seal:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -8, -22) -- (over the right flourish's end, half on the page)
    end
end

---A button over a link in the facts line, with its underline: setFactsLink places it and says what a click does
---(its handleClick, given its data and the button).
local function createFactsLinkButton(header)
    local button = CreateFrame("Button", nil, header)
    button:SetFrameLevel((header:GetFrameLevel() or 1) + 2)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(button)
    hover:SetColorTexture(1, 1, 1, 0.1)
    button:SetScript("OnClick", function(self)
        if self.handleClick then
            self.handleClick(self.data, self)
        end
    end)
    button.underline = header:CreateTexture(nil, "OVERLAY")
    button.underline:SetColorTexture(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3], 0.8)
    button:Hide()
    return button
end

local function createPageHeader(parent, pageLeft)
    local header = CreateFrame("Frame", nil, parent)
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", pageLeft, -PAGE_TOP)
    header:SetPoint("TOPRIGHT", parent, "TOPLEFT", pageLeft + PAGE_CONTENT_WIDTH, -PAGE_TOP)
    header:SetHeight(50)
    header:SetFrameLevel((parent:GetFrameLevel() or 1) + 35) -- over the page and its "more above" shade
    local fill = header:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(header)
    -- The dark wood the game puts behind the top of its own quest page, when this client has it
    if
        fill.SetAtlas
        and C_Texture
        and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo("questlog-reward-top-frame")
    then
        fill:SetAtlas("questlog-reward-top-frame") -- the art has an edge of its own, so no line is drawn under it
        header.hasArt = true
        -- Its left 5 texels are a darker rim, which the game's own frame covers; here it stood beside the divider as
        -- a second edge, the top's light line starting a little off it. Trimmed, the art meets the divider
        -- (Coordinates given after an atlas are the atlas's own, 0 to 1 across it, as the game's own tabs turn theirs
        -- over with 0, 1, 1, 0: not the whole file's)
        local info = C_Texture.GetAtlasInfo("questlog-reward-top-frame")
        if info.width and info.width > 0 and info.height and info.height > HEADER_FRINGE and fill.SetTexCoord then
            -- Its last texels are a soft shadow over the page: drawn apart, always its own height, so a tall header
            -- (a long title, the narration's row) stretches the wood alone, and the shadow does not grow over the
            -- page's first lines
            local left, fringeTop = HEADER_ART_RIM / info.width, 1 - HEADER_FRINGE / info.height
            fill:SetTexCoord(left, 1, 0, fringeTop)
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", header, "TOPLEFT", 0, 0)
            fill:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, HEADER_FRINGE)
            local fringe = header:CreateTexture(nil, "BACKGROUND")
            fringe:SetAtlas("questlog-reward-top-frame")
            fringe:SetTexCoord(left, 1, fringeTop, 1)
            fringe:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
            fringe:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
            fringe:SetHeight(HEADER_FRINGE)
            header.hasFringeApart = true
        end
        addHeaderOrnaments(header)
    else
        fill:SetColorTexture(HEADER_FILL[1], HEADER_FILL[2], HEADER_FILL[3], 1)
        local edge = header:CreateTexture(nil, "BORDER")
        edge:SetColorTexture(HEADER_EDGE[1], HEADER_EDGE[2], HEADER_EDGE[3], 1)
        edge:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
        edge:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
        edge:SetHeight(2)
    end
    header.title = ns.Widgets.createFontString(header, "OVERLAY", "GameFontNormalLarge")
    header.title:SetJustifyH("LEFT")
    header.title:SetJustifyV("TOP")
    header.title:SetWordWrap(true)
    header.facts = ns.Widgets.createFontString(header, "OVERLAY", "GameFontHighlightSmall")
    header.facts:SetJustifyH("LEFT")
    header.facts:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -4)
    header.facts:SetPoint("RIGHT", header, "RIGHT", -PADDING, 0)
    header.facts:SetTextColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
    header.measure = ns.Widgets.createFontString(header, "OVERLAY", "GameFontHighlightSmall") -- measures the facts' parts
    -- Back to a list from one of its pages (the journal's quest stories): the game's red button at the right
    header.backButton = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
    header.backButton:SetSize(110, 22)
    header.backButton:SetPoint("RIGHT", header, "RIGHT", -PADDING, 4)
    header.backButton:SetFrameLevel((header:GetFrameLevel() or 1) + 3)
    header.backButton:SetScript("OnClick", function(self)
        if self.handleClick then
            self.handleClick()
        end
    end)
    header.backButton:Hide()
    header.measure:Hide()
    -- Over the title: shift-click links the quest in chat
    header.titleButton = CreateFrame("Button", nil, header)
    header.titleButton:SetAllPoints(header.title)
    header.titleButton:SetFrameLevel((header:GetFrameLevel() or 1) + 2)
    header.titleButton:SetScript("OnClick", function()
        if header.questId and ns.QuestState.isLinkClick() then
            ns.QuestState.linkInChat(header.questId)
        elseif header.questId and ns.QuestState.isFocusClick() and ns.QuestState.getQuest(header.questId) then
            Log.focusQuest(header.questId) -- a quest of the log, put in focus or let go of
        end
    end)
    header.titleButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        local canFocus = header.questId and ns.QuestState.getQuest(header.questId)
        if ns.Gamepad and ns.Gamepad.isGamepadUI() and GameTooltip_AddLineWithInputIcon and GAMEPAD_FACE_BOTTOM then
            -- The gamepad's cursor on the title: its buttons, with their icons, as the game's own map pins say them
            GameTooltip_AddLineWithInputIcon(GameTooltip, ns.L("Share to chat"), GREEN_FONT_COLOR, GAMEPAD_FACE_BOTTOM)
            if canFocus then
                GameTooltip_AddLineWithInputIcon(
                    GameTooltip,
                    CONTEXT_ACTION_LABEL_FOCUS or ns.L("Focus"),
                    GREEN_FONT_COLOR,
                    GAMEPAD_FACE_LEFT
                )
            end
        else
            GameTooltip:AddLine(ns.L("Shift-click to link it in chat"), 0.6, 0.6, 0.6)
            if canFocus then
                GameTooltip:AddLine(ns.L("Ctrl-click to focus it"), 0.6, 0.6, 0.6)
            end
        end
        GameTooltip:Show()
    end)
    header.titleButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    header.titleButton:Hide()
    -- The narration's row, for a quest a translation addon has narrated: play now (or stop), queue (or take off
    -- the queue), then who narrates and where it is. Played by that addon, in its own player and queue.
    header.voice = CreateFrame("Frame", nil, header)
    header.voice:SetPoint("TOPLEFT", header.facts, "BOTTOMLEFT", 0, -6)
    header.voice:SetPoint("RIGHT", header, "RIGHT", -PADDING, 0)
    header.voice:SetHeight(20)
    header.voice:SetFrameLevel((header:GetFrameLevel() or 1) + 2)
    for _, part in ipairs({
        { "playButton", ns.QuestText.toggleVoice },
        { "queueButton", ns.QuestText.toggleVoiceQueue },
    }) do
        local button = CreateFrame("Button", nil, header.voice, "UIPanelButtonTemplate")
        button:SetSize(72, 20)
        button.baseWidth = 72
        button:SetScript("OnClick", function()
            part[2](header.voice.questId)
        end)
        header.voice[part[1]] = button
    end
    header.voice.playButton:SetPoint("LEFT", header.voice, "LEFT", 0, 0)
    header.voice.queueButton:SetPoint("LEFT", header.voice.playButton, "RIGHT", 4, 0)
    header.voice.text = ns.Widgets.createFontString(header.voice, "OVERLAY", "GameFontHighlightSmall")
    header.voice.text:SetPoint("LEFT", header.voice.queueButton, "RIGHT", 8, 0)
    header.voice.text:SetPoint("RIGHT", header.voice, "RIGHT", 0, 0)
    header.voice.text:SetJustifyH("LEFT")
    header.voice.text:SetWordWrap(false)
    header.voice.text:SetTextColor(COLORS.tan[1], COLORS.tan[2], COLORS.tan[3])
    header.voice:Hide()
    header.zoneButton = createFactsLinkButton(header)
    header.wowheadButton = createFactsLinkButton(header)
    header:HookScript("OnHide", ns.WowheadLink.hide) -- (the window closed: the panel opened from it goes too)
    -- The chain badge: the tracker's rounded outline around the chain icon and the step
    header.badge = CreateFrame("Frame", nil, header)
    header.badge:SetHeight(BADGE_HEIGHT)
    header.badge:SetPoint("TOPRIGHT", header, "TOPRIGHT", -PADDING, -10)
    header.badgeText = ns.Widgets.createFontString(header.badge, "OVERLAY", "GameFontHighlightSmall")
    header.badgeText:SetPoint("RIGHT", header.badge, "RIGHT", 0, 0) -- plain, as the game writes a step: no outline round it
    header.badgeText:SetTextColor(HEADER_BADGE_TEXT[1], HEADER_BADGE_TEXT[2], HEADER_BADGE_TEXT[3])
    local icon = header.badge:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "Chain")
    icon:SetSize(12, 12)
    icon:SetPoint("RIGHT", header.badgeText, "LEFT", -4, 0)
    icon:SetVertexColor(HEADER_BADGE_TEXT[1], HEADER_BADGE_TEXT[2], HEADER_BADGE_TEXT[3])
    header.badge:SetWidth(70) -- set to fit its text whenever the text changes; anchoring it to its own icon would be a loop
    header:Hide()
    return header
end

---Puts a back button in the page's header, as the journal's quest stories have: after setPageHeader, which takes
---it away again.
function QuestPage.setPageHeaderBack(text, handleClick)
    local button = State.pageHeader and State.pageHeader.backButton
    if not button then
        return
    end
    -- With a controller, B does it: its icon before the words, as the page's own way back says it
    button:SetText(ns.Gamepad.isGamepadUI() and (ns.Log.getPadIconMarkup(GAMEPAD_FACE_RIGHT, 16) .. text) or text)
    button.handleClick = handleClick
    button:Show()
end

-- Shared with the other parts of the window
QuestPage.createPageHeader = createPageHeader
QuestPage.setPageHeader = setPageHeader
