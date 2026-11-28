local _, ns = ...

-- A quest's page on Wowhead (its WoW: Forever database, which has Forever's own quests too): a link to copy, as the
-- game opens no web page for an addon. "Wowhead" on the quest page's title line and "Wowhead link" in
-- the quests' menus (the quest list's and the tracker's) open a small panel in the tooltip's look beside what was
-- clicked: the quest's name, the link selected, and how to copy it. Ctrl+C is seen, so the panel says it worked and
-- closes. The link is in the game's language where Wowhead has a site in it, English otherwise.
local WowheadLink = {}
ns.WowheadLink = WowheadLink

local BASE_URL = "https://www.wowhead.com/forever/"
-- The game's languages and Wowhead's sites in them (each checked to answer: wowhead.com/forever/<site>/quest=844)
local SITES = {
    deDE = "de",
    esES = "es",
    esMX = "mx",
    frFR = "fr",
    itIT = "it",
    ptBR = "pt",
    ruRU = "ru",
    koKR = "ko",
    zhCN = "cn",
    zhTW = "tw",
}

local PANEL = {
    width = 380, -- the whole link in sight, with a language's site in it (".../forever/de/quest=12345")
    height = 76,
    padding = 12,
    copiedSeconds = 1.5, -- the "Copied" line stays this long, then the panel closes
    hintColor = { 0.6, 0.6, 0.6 },
}

local panel -- made at its first showing

---@return string url The quest's page on Wowhead, in the game's language where Wowhead has a site in it
function WowheadLink.getUrl(questId)
    local site = GetLocale and SITES[GetLocale()]
    return BASE_URL .. (site and (site .. "/") or "") .. "quest=" .. questId
end

---The link in the text box again, all of it selected, the box holding the keyboard: ready for Ctrl+C.
local function selectLink()
    local editBox = panel.editBox
    if editBox:GetText() ~= panel.url then
        editBox:SetText(panel.url)
    end
    editBox:SetFocus()
    editBox:HighlightText()
end

local function setHint(text, color)
    panel.hint:SetText(text)
    panel.hint:SetTextColor(color.r or color[1], color.g or color[2], color.b or color[3])
end

---Ctrl+C was pressed: the panel says so, then closes, unless another link was shown meanwhile.
local function showCopied()
    setHint(ns.L("Copied: paste it into your browser."), GREEN_FONT_COLOR or { 0.1, 1, 0.1 })
    local showing = panel.showing
    C_Timer.After(PANEL.copiedSeconds, function()
        if panel.showing == showing then
            panel:Hide()
        end
    end)
end

local function isCopyKey(key)
    return key == "C" and (IsControlKeyDown() or (IsMetaKeyDown ~= nil and IsMetaKeyDown()))
end

local function createEditBox(parent)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetHeight(20)
    editBox:SetAutoFocus(false)
    -- (the template's left edge is drawn a few pixels out of the box: moved in by as much)
    editBox:SetPoint("TOPLEFT", parent.title, "BOTTOMLEFT", 5, -6)
    editBox:SetPoint("RIGHT", parent, "RIGHT", -PANEL.padding, 0)
    -- The text is for copying: typing in it puts the link back, and a click selects it all again
    editBox:SetScript("OnTextChanged", selectLink)
    editBox:SetScript("OnMouseUp", selectLink)
    editBox:SetScript("OnKeyDown", function(_, key)
        if isCopyKey(key) then
            showCopied()
        end
    end)
    editBox:SetScript("OnEscapePressed", function()
        parent:Hide()
    end)
    editBox:SetScript("OnEnterPressed", function()
        parent:Hide()
    end)
    return editBox
end

---The panel: the game's tooltip border and ground, the quest's name in gold, the link, and a line saying how to copy it.
local function createPanel()
    local frame = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
    frame:SetSize(PANEL.width, PANEL.height)
    frame:SetFrameStrata("FULLSCREEN_DIALOG") -- over the map and the quest window it opens from
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame.title = ns.Widgets.createFontString(frame, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL.padding, -PANEL.padding)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -PANEL.padding, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.editBox = createEditBox(frame)
    frame.hint = ns.Widgets.createFontString(frame, "OVERLAY", "GameFontHighlightSmall")
    frame.hint:SetPoint("TOPLEFT", frame.editBox, "BOTTOMLEFT", -5, -6)
    frame.hint:SetPoint("RIGHT", frame, "RIGHT", -PANEL.padding, 0)
    frame.hint:SetJustifyH("LEFT")
    -- A click anywhere else closes it, as a menu closes
    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self.editBox:ClearFocus()
    end)
    frame:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() then
            self:Hide()
        end
    end)
    frame:Hide()
    return frame
end

---Beside what was clicked: under it, or at the mouse for a menu's item (the menu is gone by then).
local function placePanel(anchor)
    panel:ClearAllPoints()
    if anchor then
        panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        return
    end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 16, y / scale - 8)
end

---Shows a quest's Wowhead link, selected, ready to copy.
---@param questId number
---@param anchor table? The frame clicked: the panel opens under it (at the mouse without one)
function WowheadLink.show(questId, anchor)
    if not questId then
        return
    end
    panel = panel or createPanel()
    panel.url = WowheadLink.getUrl(questId)
    panel.showing = (panel.showing or 0) + 1
    panel.title:SetText(ns.L("%s on Wowhead", ns.QuestText.getQuestName(questId) or ns.L("Quest %d", questId)))
    setHint(ns.L("Ctrl+C to copy, Esc closes"), PANEL.hintColor)
    placePanel(anchor)
    panel:Show()
    panel:Raise()
    selectLink()
end

---Closes the panel (its anchor went away: the quest window closed, or another page is shown).
function WowheadLink.hide()
    if panel then
        panel:Hide()
    end
end

---@return table? panel The panel while it is open (for the scenarios)
function WowheadLink.getShownPanel()
    return panel and panel:IsShown() and panel or nil
end

---Adds "Wowhead link" to a quest's menu (the game's menu, as the quest list and the tracker open it).
function WowheadLink.addMenuItem(root, questId)
    root:CreateButton(ns.L("Wowhead link"), function()
        WowheadLink.show(questId)
    end)
end
