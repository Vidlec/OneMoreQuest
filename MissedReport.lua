local _, ns = ...

-- The report of quests the game offered that OneMoreQuest's lists missed (GameOffers keeps them): a window with the
-- report selected, ready to copy into a bug report, and the /omq missing command that opens it.
local MissedReport = {}
ns.MissedReport = MissedReport

local reportFrame

---A window with the report, selected, ready to copy into a bug report.
function MissedReport.show()
    local report = ns.GameOffers.composeReport()
    if not CreateFrame or not UIParent then
        return
    end
    if not reportFrame then
        reportFrame = CreateFrame("Frame", "OneMoreQuestReport", UIParent, "BasicFrameTemplateWithInset")
        reportFrame:SetSize(620, 380)
        reportFrame:SetPoint("CENTER")
        reportFrame:SetFrameStrata("DIALOG")
        reportFrame:SetMovable(true)
        reportFrame:EnableMouse(true)
        reportFrame:RegisterForDrag("LeftButton")
        reportFrame:SetScript("OnDragStart", reportFrame.StartMoving)
        reportFrame:SetScript("OnDragStop", reportFrame.StopMovingOrSizing)
        if UISpecialFrames then
            table.insert(UISpecialFrames, "OneMoreQuestReport") -- Escape closes it
        end
        local title = ns.Widgets.createFontString(reportFrame, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", reportFrame, "TOP", 0, -5)
        reportFrame.title = title
        local hint = ns.Widgets.createFontString(reportFrame, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOPLEFT", reportFrame, "TOPLEFT", 14, -32)
        reportFrame.hint = hint
        local scroll = CreateFrame("ScrollFrame", nil, reportFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", reportFrame, "TOPLEFT", 12, -52)
        scroll:SetPoint("BOTTOMRIGHT", reportFrame, "BOTTOMRIGHT", -32, 44)
        local editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(ChatFontNormal)
        editBox:SetWidth(570)
        editBox:SetScript("OnEscapePressed", function() reportFrame:Hide() end)
        -- The text is for copying: typing in it puts the report back as it was
        editBox:SetScript("OnTextChanged", function(self, isUserInput)
            if isUserInput then
                self:SetText(reportFrame.report or "")
                self:HighlightText()
            end
        end)
        scroll:SetScrollChild(editBox)
        reportFrame.editBox = editBox
        local clearButton = CreateFrame("Button", nil, reportFrame, "UIPanelButtonTemplate")
        clearButton:SetSize(140, 24)
        clearButton:SetPoint("BOTTOMLEFT", reportFrame, "BOTTOMLEFT", 12, 12)
        reportFrame.clearButton = clearButton
        clearButton:SetScript("OnClick", function()
            ns.GameOffers.clearMissed()
            MissedReport.show()
        end)
        local closeButton = CreateFrame("Button", nil, reportFrame, "UIPanelButtonTemplate")
        closeButton:SetSize(100, 24)
        closeButton:SetPoint("BOTTOMRIGHT", reportFrame, "BOTTOMRIGHT", -12, 12)
        closeButton:SetScript("OnClick", function() reportFrame:Hide() end)
        reportFrame.closeButton = closeButton
    end
    -- The window's own words on every showing, in the addon's language; the report stays English, for the developers
    reportFrame.title:SetText(ns.L("%s: missed quests", ns.ADDON_TITLE))
    reportFrame.hint:SetText(ns.L("Press Ctrl+C to copy, then paste it into a bug report for OneMoreQuest."))
    ns.Widgets.setButtonFonts(reportFrame.clearButton) -- the game's button fonts lack Czech letters
    ns.Widgets.setButtonFonts(reportFrame.closeButton)
    reportFrame.clearButton:SetText(ns.L("Clear the list"))
    reportFrame.closeButton:SetText(ns.L("Close"))
    reportFrame.report = report
    reportFrame.editBox:SetText(report)
    reportFrame:Show()
    reportFrame.editBox:SetFocus()
    reportFrame.editBox:HighlightText()
end

---`/omq missing`: says how many quests were missed and opens the report to copy.
function MissedReport.printMissed()
    local _, count = ns.GameOffers.composeReport()
    local learnedCount = #ns.LearnedDungeons.getAreaIds()
    local differenceCount = #ns.DataCheck.composeReportLines()
    if count == 0 and learnedCount == 0 and differenceCount == 0 then
        ns.print(ns.L("no quests missed so far: everything the game offered was already listed."))
        return
    end
    if count == 0 and learnedCount == 0 then
        ns.print(ns.Lp(differenceCount, "%d place where the game's quests differ from the quest database; the report to copy is open.", "%d places where the game's quests differ from the quest database; the report to copy is open."))
        MissedReport.show()
        return
    end
    if count == 0 then
        ns.print(ns.Lp(learnedCount, "%d dungeon the quest database does not know, learned from your runs; the report to copy is open.", "%d dungeons the quest database does not know, learned from your runs; the report to copy is open."))
        MissedReport.show()
        return
    end
    ns.print(ns.Lp(count, "%d quest the game offered that the quest database or the addon's rules missed. It is listed anyway; the report to copy is open.", "%d quests the game offered that the quest database or the addon's rules missed. They are listed anyway; the report to copy is open."))
    MissedReport.show()
end
