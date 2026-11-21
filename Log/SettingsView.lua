local _, ns = ...

-- The quest log window: the settings, drawn in the window in place of the quests.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window = ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local addBody = QuestPage.addBody
local setPageHeader, setPageRewards = QuestPage.setPageHeader, QuestPage.setPageRewards
local filterDropdown = State.filterDropdown
local BACKGROUND, COLORS, HEADER_BAR_HIGH, HEADER_BAR_LOW, MEDIA, PADDING = Style.BACKGROUND, Style.COLORS, Style.HEADER_BAR_HIGH, Style.HEADER_BAR_LOW, Style.MEDIA, Style.PADDING
local PAPER_FILL, SELECTED_EDGE, TITLE_HEIGHT = Style.PAPER_FILL, Style.SELECTED_EDGE, Style.TITLE_HEIGHT

---------------------------------------------------------------------------------------------------------------
-- Trailhead's settings, on the page beside the list: the cog opens them in place of the quest

local RADIO_IMAGE = "Interface\\Buttons\\UI-RadioButton"
local RADIO_OFF, RADIO_ON = { 0, 0.25, 0, 1 }, { 0.25, 0.5, 0, 1 } -- the parts of the game's radio button picture
local RADIO_SIZE = 16

---Carries a changed setting out everywhere, then draws the page again with it.
function SettingsView.applySetting()
    ns.SettingsPage.apply()
    Log.refresh()
end

local function toggleOption(option)
    ns.SettingsPage.toggle(option)
    Log.refresh()
end

---@param picked { key: string, value: any, choice: table?, option: table? } The tile clicked
local function chooseSetting(picked)
    if picked.choice and picked.choice.choose then
        picked.choice.choose() -- a tile that stands for another switch sets that one
    else
        ns.settings[picked.key] = picked.value
        if picked.option and picked.option.handleChoose then
            picked.option.handleChoose(picked.value)
        end
    end
    SettingsView.applySetting()
end

-- The settings are a panel of controls, so they stand on the game's dark marble, as its own windows' controls do
-- (parchment is for pages that are read): groups under the character window's carved title plate, each setting a
-- line ruled off from the next, the game's minimal checkbox, labels in white and notes in sand.
local LABEL, NOTE, DISABLED = COLORS.white, COLORS.tan, { 0.5, 0.5, 0.5 }
local TITLE_PLATE, RULE_LINE = { atlas = "UI-Character-Info-Title" }, { atlas = "UI-Character-Info-ScrollLine" }
local CHECK_BOX, CHECK_TICK, CHECK_TICK_DISABLED = { atlas = "checkbox-minimal" }, { atlas = "checkmark-minimal" }, { atlas = "checkmark-minimal-disabled" }
local CHECK_SIZE = 24
local LABEL_LEFT = PADDING + CHECK_SIZE + 8 -- a setting's words start after its checkbox
local DEPENDENT_INDENT = 22 -- a setting that needs another stands in under it

---A group's title on the carved plate, centred, as the character window heads its lists.
---@return number y Below the plate
local function addSettingsHeading(y, text)
    local width = State.detail.width - 2 * PADDING
    State.detail:addImage(PADDING, y, width, 32, TITLE_PLATE)
    State.detail:addText(text, PADDING, y + 9, { font = "GameFontHighlight", color = LABEL, width = width, justify = "CENTER", isSingleLine = true })
    return y + 40
end

---The rule under a setting, as between the character window's lines.
local function addRule(y, left)
    State.detail:addImage(left or PADDING, y, State.detail.width - PADDING - (left or PADDING), 7, RULE_LINE, nil, { 1, 1, 1 })
end

---A setting's label, and a short note under it.
---@param rightSpace number? Room kept free at the right, for a button
---@param isDisabled boolean? Greyed out: what it needs is off
---@return number y Below the note
local function addSettingText(y, left, label, note, rightSpace, isDisabled)
    local width = State.detail.width - PADDING - left - (rightSpace or 0)
    local height = State.detail:addText(ns.L(label), left, y, { font = "GameFontHighlight", color = isDisabled and DISABLED or LABEL, width = width })
    y = y + height + 2
    if note then
        local noteHeight = State.detail:addText(ns.L(note), left, y, { font = "GameFontHighlightSmall", color = isDisabled and DISABLED or NOTE, width = width })
        y = y + noteHeight + 1
    end
    return y
end

---A switch: the game's minimal checkbox in front of its label, the line ruled under it. The whole line takes the
---click; greyed out, with the grey tick, and no click while what it needs is off.
local function addSettingCheck(y, option)
    local top = y
    local isAvailable = ns.SettingsPage.isAvailable(option)
    local indent = option.isAvailable and DEPENDENT_INDENT or 0
    State.detail:addImage(PADDING + indent, y - 4, CHECK_SIZE, CHECK_SIZE, CHECK_BOX)
    if ns.SettingsPage.isOn(option) then
        State.detail:addImage(PADDING + indent, y - 4, CHECK_SIZE, CHECK_SIZE, isAvailable and CHECK_TICK or CHECK_TICK_DISABLED, nil, nil, 1)
    end
    y = addSettingText(y, LABEL_LEFT + indent, option.label, option.note, nil, not isAvailable)
    if isAvailable then
        State.detail:addButton(PADDING - 4 + indent, top - 5, State.detail.width - 2 * PADDING + 8 - indent, y - top + 8, toggleOption, option)
    end
    addRule(y + 2, PADDING + indent)
    return y + 12
end

-- Pictures of each choice, drawn small on the parchment
local TILE_EDGE, TILE_CHOSEN_EDGE, TILE_GROUND = { 0.54, 0.45, 0.31 }, { 0.79, 0.64, 0.15 }, { 0.1, 0.085, 0.063 }
local MAP_GROUND = { 0.45, 0.39, 0.22 }

---A small window in a border's look: the list's dark side and the parchment page, framed as the border frames them.
local function drawBorderPicture(value, x, y, width, height)
    local left, top, right, bottom = x + 10, y + 8, x + width - 10, y + height - 8
    local edge = ({ map = { 0, 0, 0 }, game = { 0.43, 0.4, 0.34 }, gold = TILE_CHOSEN_EDGE, flat = { 0, 0, 0, 0 } })[value]
    local thickness = value == "game" and 3 or 1
    if value == "flat" then
        State.detail:addRect(left - 2, top - 2, right - left + 4, bottom - top + 4, { 0, 0, 0, 0.6 }, 1) -- a soft shadow
    else
        State.detail:addRect(left - thickness, top - thickness, right - left + 2 * thickness, bottom - top + 2 * thickness, edge, 1)
    end
    local stripHeight = value == "flat" and 0 or 6
    if stripHeight > 0 then
        State.detail:addRect(left, top, right - left, stripHeight, value == "game" and { 0.11, 0.09, 0.07 } or { 0.09, 0.09, 0.09 }, 2)
    end
    local split = left + math.floor((right - left) * 0.42)
    State.detail:addRect(left, top + stripHeight, split - left, bottom - top - stripHeight, BACKGROUND, 2)
    State.detail:addRect(split, top + stripHeight, right - split, bottom - top - stripHeight, PAPER_FILL, 2)
end

---Two quest marks in a look, as the map draws them.
---A quest's places as tiny squares, or as a shaded area with an edge.
-- A spawn's marker on a picture, in a kind (as MapMarks.dressSpawnMarker draws them on the maps)
local GAME_MARKER_ATLASES = { kill = "DungeonSkull", loot = "VignetteLoot", use = "VignetteEvent" }
local MARKER_EDGE = { 0.04, 0.06, 0.1 }
---@param scale number? Larger or smaller than on a tile's picture (a nameplate's is larger)
local function addMarkerPicture(kind, centerX, centerY, glyph, color, scale)
    scale = scale or 1
    local function addCentered(size, texture, tint, level)
        State.detail:addIcon(centerX - size * scale / 2, centerY - size * scale / 2, size * scale, texture, tint, level)
    end
    if kind == "square" then
        State.detail:addRect(centerX - 3.5 * scale, centerY - 3.5 * scale, 7 * scale, 7 * scale, MARKER_EDGE, 2)
        State.detail:addRect(centerX - 2.5 * scale, centerY - 2.5 * scale, 5 * scale, 5 * scale, color, 3)
    elseif kind == "plate" then
        addCentered(16, ns.MapMarksStyle.MEDIA .. "Plate", color, 3)
        addCentered(10, ns.MapMarks.OBJECTIVE_ICONS[glyph], { 1, 1, 1 }, 4)
    elseif kind == "game" or kind == "glyph" then
        local isGameArt = kind == "game" and GAME_MARKER_ATLASES[glyph] ~= nil
        if ns.settings.shouldGlowSpawnMarkers ~= false then
            addCentered(isGameArt and 22 or 17, ns.MapMarks.SOFT_DOT, color, 3)
        end
        if isGameArt then
            addCentered(13, { atlas = GAME_MARKER_ATLASES[glyph] }, { 1, 1, 1 }, 4)
        else
            addCentered(10, ns.MapMarks.OBJECTIVE_ICONS[glyph], { 1, 1, 1 }, 4)
        end
    end
end

-- An area on a picture, in a look: a light wash with a thin edge, or the bold shape (a bright edge over a dark rim);
-- its fill and its edge as the player set them (each on or off, and its strength)
local AREA_RIM = { 0.04, 0.06, 0.12, 0.7 }
local function addAreaPicture(style, x, y, size, color, level)
    if style ~= "blob" and style ~= "filled" then
        return
    end
    local settings = ns.settings
    local fill = settings.shouldFillAreas ~= false and math.min(2, tonumber(settings.areaFillStrength) or 1) or 0
    local edge = settings.shouldOutlineAreas ~= false and math.min(2, tonumber(settings.areaOutlineStrength) or 1) or 0
    local isBold = style == "blob"
    local inset = isBold and 2 or 1
    if edge > 0 then
        if isBold then
            State.detail:addDot(x - 1, y - 1, size + 2, { AREA_RIM[1], AREA_RIM[2], AREA_RIM[3], math.min(1, AREA_RIM[4] * edge) }, level)
        end
        State.detail:addDot(x, y, size, { color[1], color[2], color[3], math.min(1, (isBold and 1 or 0.75) * edge) }, level + 1)
        State.detail:addDot(x + inset, y + inset, size - 2 * inset, MAP_GROUND, level + 2)
    end
    if fill > 0 then
        State.detail:addDot(x + inset, y + inset, size - 2 * inset, { color[1], color[2], color[3], math.min(1, (isBold and 0.45 or 0.25) * fill) }, level + 3)
    end
end

-- Two quests' spawns on a tile's picture, as shares of it
local PICTURE_SPAWNS = { { 0.3, 0.4, "kill", 1 }, { 0.44, 0.66, "kill", 1 }, { 0.72, 0.42, "loot", 2 }, { 0.62, 0.74, "loot", 2 } }

---A choice of the areas' look: two quests' areas over one another in that look; with none, the markers alone.
local function drawAreaPicture(value, x, y, width, height)
    State.detail:addRect(x + 1, y + 1, width - 2, height - 2, MAP_GROUND, 1)
    if value == "game" then
        -- The game's own area, alone: nothing of ours on the spawns
        local size = height - 14
        State.detail:addIcon(x + (width - size) / 2, y + 7, size, "Interface\\WorldMap\\UI-QuestBlob-Inside", { 1, 1, 1 }, 2)
        State.detail:addIcon(x + (width - size) / 2, y + 7, size, "Interface\\WorldMap\\UI-QuestBlob-Outside", { 1, 1, 1 }, 3)
        return
    end
    local first, second = ns.MapMarks.getQuestColor(1), ns.MapMarks.getQuestColor(2)
    local size = height - 16
    addAreaPicture(value, x + width * 0.4 - size / 2, y + 8, size, first, -8)
    addAreaPicture(value, x + width * 0.64 - size / 2 + 2, y + 10, size - 4, second, -4)
    if value == "none" then
        -- (nothing round them: the markers alone, as chosen, or as they would be were none chosen)
        local kind = ns.MapMarks.getSpawnMarker()
        for _, spawn in ipairs(PICTURE_SPAWNS) do
            addMarkerPicture(kind == "none" and "glyph" or kind, x + spawn[1] * width, y + spawn[2] * height, spawn[3], spawn[4] == 1 and first or second)
        end
    end
end

---A choice of the spawn markers: two quests' spawns in that kind.
local function drawMarkerPicture(value, x, y, width, height)
    State.detail:addRect(x + 1, y + 1, width - 2, height - 2, MAP_GROUND, 1)
    local first, second = ns.MapMarks.getQuestColor(1), ns.MapMarks.getQuestColor(2)
    for _, spawn in ipairs(PICTURE_SPAWNS) do
        addMarkerPicture(value, x + spawn[1] * width, y + spawn[2] * height, spawn[3], spawn[4] == 1 and first or second)
    end
end

---A colour for a kind of quest's icons: its "!" and its "?" side by side.
local function drawIconColourPicture(value, x, y, width, height)
    local size = math.min(height - 10, (width - 8) / 2)
    local top = y + (height - size) / 2
    local left = x + width / 2 - size
    local dress = ns.MapMarks.dressQuestIcon
    dress(State.detail:addIcon(left, top, size, { atlas = "QuestNormal" }, nil, 2), value, false)
    dress(State.detail:addIcon(left + size, top, size, { atlas = "QuestTurnin" }, nil, 2), value, true)
end

local PICTURES = { logGrouping = drawGroupingPicture, windowBorder = drawBorderPicture, areaStyle = drawAreaPicture, spawnMarker = drawMarkerPicture,
    questIconEvent = drawIconColourPicture, questIconRaid = drawIconColourPicture, questIconDungeon = drawIconColourPicture,
    questIconRepeatable = drawIconColourPicture, questIconLowLevel = drawIconColourPicture, questIconNormal = drawIconColourPicture }

---A setting with several values, as pictures to pick from: the chosen one in a gold frame with a soft glow
---and a tick, its name under each, and under them all what the chosen one does.
local function addSettingChoice(y, option)
    -- Its name and note as any setting's, then the choices under them; greyed out, and not to be picked, while what
    -- it needs is off
    local isAvailable = ns.SettingsPage.isAvailable(option)
    y = addSettingText(y, PADDING, option.label, option.note, nil, not isAvailable) + 6
    local count = #option.choices
    local gap = 10
    local width = math.floor((State.detail.width - 2 * PADDING - gap * (count - 1)) / count)
    local drawPicture = PICTURES[option.choiceKey]
    -- Without a picture, a low tile with its name inside
    local height = not drawPicture and 26 or count >= 4 and 46 or 52
    -- Each language is named in itself, as a player looking for theirs reads it: never translated
    local translate = option.choiceKey == "language" and function(text) return text end or ns.L
    local chosenNote
    -- A tile that stands for another switch (the game's own markers: Map marks off) is the chosen one while that
    -- says so, and then no other is
    local standIn
    for _, choice in ipairs(option.choices) do
        standIn = standIn or (choice.isChosen and choice.isChosen() and choice) or nil
    end
    for index, choice in ipairs(option.choices) do
        local x = PADDING + (index - 1) * (width + gap)
        local isChosen = choice == standIn or (not standIn and ns.settings[option.choiceKey] == choice.value)
        local chosenEdge = isAvailable and TILE_CHOSEN_EDGE or DISABLED
        if isChosen then
            chosenNote = choice.note and translate(choice.note)
            State.detail:addRect(x - 2, y - 2, width + 4, height + 4, chosenEdge, 0) -- a gold rim, no glow
        end
        State.detail:addRect(x, y, width, height, isChosen and chosenEdge or TILE_EDGE, 0)
        State.detail:addRect(x + 1, y + 1, width - 2, height - 2, TILE_GROUND, 0)
        if drawPicture then
            drawPicture(choice.value, x, y, width, height)
        end
        if isChosen and drawPicture then -- a small tile's gold rim says it alone
            State.detail:addImage(x + width - 19, y + 1, 18, 18, CHECK_TICK, nil, nil, 7)
        end
        if drawPicture then
            State.detail:addText(translate(choice.label), x - 4, y + height + 4, {
                font = "GameFontHighlightSmall", color = isChosen and COLORS.gold or NOTE, width = width + 8, justify = "CENTER",
            })
        else
            State.detail:addText(translate(choice.label), x + 2, y + 7, {
                font = "GameFontHighlightSmall", color = not isAvailable and DISABLED or isChosen and COLORS.gold or COLORS.sand, width = width - 4, justify = "CENTER", isSingleLine = true,
            })
        end
        if isAvailable then
            State.detail:addButton(x - 2, y - 2, width + 4, height + (drawPicture and 22 or 4), chooseSetting,
                { key = option.choiceKey, value = choice.value, choice = choice, option = option })
        end
    end
    y = y + height + (drawPicture and 22 or 8)
    if chosenNote then
        local noteHeight = State.detail:addText(chosenNote, PADDING, y, { font = "GameFontHighlightSmall", color = NOTE, width = State.detail.width - 2 * PADDING })
        y = y + noteHeight
    end
    addRule(y + 4)
    return y + 14
end

-- A number in steps, as a size (70% to 160% in tenths) or a count of levels: each option says its range and how
-- its value reads
local function stepSetting(change)
    local option = change.option
    local value = tonumber(ns.settings[option.stepKey]) or option.default or option.min
    value = math.floor((value + change.step) / option.step + 0.5) * option.step
    value = math.floor(value * 100 + 0.5) / 100 -- tenths added up drift (1.6000000000000003): kept to hundredths
    ns.settings[option.stepKey] = math.max(option.min, math.min(option.max, value))
    if option.handleChange then
        option.handleChange()
    end
    SettingsView.applySetting()
end

-- The small buttons of a number: the dark face and bronze rim of the game's dropdown button, a gold sign
local STEP_RIM, STEP_FACE, STEP_SHINE = { 0.42, 0.29, 0.15 }, { 0.07, 0.05, 0.035 }, { 0.16, 0.11, 0.07 }
local STEP_SIZE = 22

local function addStepButton(x, y, text, data, isEnabled)
    State.detail:addRect(x, y, STEP_SIZE, STEP_SIZE, { 0, 0, 0 }, 2)
    State.detail:addRect(x + 1, y + 1, STEP_SIZE - 2, STEP_SIZE - 2, STEP_RIM, 3)
    State.detail:addRect(x + 2, y + 2, STEP_SIZE - 4, STEP_SIZE - 4, STEP_FACE, 4)
    State.detail:addRect(x + 2, y + 2, STEP_SIZE - 4, (STEP_SIZE - 4) / 2, STEP_SHINE, 4)
    State.detail:addText(text, x, y + 4, { font = "GameFontNormal", color = isEnabled and COLORS.gold or DISABLED, width = STEP_SIZE, justify = "CENTER", isSingleLine = true })
    if isEnabled then
        State.detail:addButton(x, y, STEP_SIZE, STEP_SIZE, stepSetting, data)
    end
end

---A number: its label and note, and at the right "-", its value in white, "+"; each sign only while it can go
---further. Greyed out while what it needs is off.
local function addSettingStepper(y, option)
    local top = y
    local isAvailable = ns.SettingsPage.isAvailable(option)
    local indent = option.isAvailable and DEPENDENT_INDENT or 0
    local value = tonumber(ns.settings[option.stepKey]) or option.default or option.min
    local right = State.detail.width - PADDING
    local valueWidth = 70
    addStepButton(right - STEP_SIZE, top - 2, "+", { option = option, step = option.step }, isAvailable and value < option.max)
    State.detail:addText(option.format(value), right - STEP_SIZE - valueWidth, top + 2, {
        font = "GameFontHighlight", color = isAvailable and LABEL or DISABLED, width = valueWidth, justify = "CENTER", isSingleLine = true,
    })
    addStepButton(right - 2 * STEP_SIZE - valueWidth, top - 2, "-", { option = option, step = -option.step }, isAvailable and value > option.min)
    y = addSettingText(y, LABEL_LEFT + indent, option.label, option.note, 2 * STEP_SIZE + valueWidth + 8, not isAvailable)
    y = math.max(y, top + STEP_SIZE)
    addRule(y + 2, PADDING + indent)
    return y + 12
end

-- The game's red button, from its own art in three slices (UIPanelButtonTemplate's in this client)
local RED_LEFT, RED_MIDDLE, RED_RIGHT = { atlas = "128-RedButton-Left" }, { atlas = "_128-RedButton-Center" }, { atlas = "128-RedButton-Right" }
local RED_HEIGHT, RED_END = 24, 14

---Something to do rather than switch: its label and note, and the game's red button at the right.
local function addSettingAction(y, option)
    local top = y
    local text = ns.L(option.buttonText)
    local buttonWidth = math.max(90, #text * 7 + 28)
    local x = State.detail.width - PADDING - buttonWidth
    State.detail:addImage(x, top - 3, RED_END, RED_HEIGHT, RED_LEFT, nil, nil, 2)
    State.detail:addImage(x + RED_END, top - 3, buttonWidth - 2 * RED_END, RED_HEIGHT, RED_MIDDLE, nil, nil, 2)
    State.detail:addImage(x + buttonWidth - RED_END, top - 3, RED_END, RED_HEIGHT, RED_RIGHT, nil, nil, 2)
    State.detail:addText(text, x, top + 2, { font = "GameFontNormal", color = COLORS.gold, width = buttonWidth, justify = "CENTER", isSingleLine = true })
    State.detail:addButton(x, top - 3, buttonWidth, RED_HEIGHT, function()
        option.handleClick()
        Log.refresh()
    end)
    y = addSettingText(y, LABEL_LEFT, option.label, option.note, buttonWidth + 8)
    y = math.max(y, top + RED_HEIGHT - 2)
    addRule(y + 2)
    return y + 12
end
-- A small picture of the tracker or the map over a section's switches, drawn from the settings as they are
local PREVIEW_GROUND = { 0.06, 0.05, 0.04 }

local function addPreviewFrame(y, height)
    local width = State.detail.width - 2 * PADDING
    State.detail:addRect(PADDING, y, width, height, { 0, 0, 0 }, 0)
    State.detail:addRect(PADDING + 1, y + 1, width - 2, height - 2, PREVIEW_GROUND, 0)
    State.detail:addText(ns.L("PREVIEW"), PADDING, y + 5, { font = "GameFontDisableSmall", color = COLORS.sand, width = width, justify = "CENTER", isSingleLine = true })
    return PADDING + 1, width - 2
end

local GREEN_TEXT, GREY_TEXT = { 0.49, 0.88, 0.49 }, { 0.66, 0.66, 0.66 }

---The tracker in small, as the settings draw it now: a quest under way (the light on progress, an objective done
---that can be left out) and a quest ready to hand in (on one line, or with whom to), on its dark ground or not.
local function addTrackerPreview(y)
    local lines = {
        { kind = "zone", text = "Thousand Needles" },
        { kind = "title", text = "[30] Hardened Shells", mark = { kind = "objective", glyph = "kill", progress = 0.45 }, isFlashing = true },
        { kind = "objective", text = "4/9 Hardened Tortoise Shell", color = COLORS.white },
    }
    if not ns.settings.shouldHideDoneObjectives then
        lines[#lines + 1] = { kind = "objective", text = "Speak with Pao'ka Swiftmountain", color = GREY_TEXT }
    end
    lines[#lines + 1] = { kind = "title", text = "[29] Load Lightening", mark = { kind = "turnIn", progress = 1 } }
    if not ns.settings.shouldCollapseReady then
        lines[#lines + 1] = { kind = "objective", text = ns.L("Turn in to %s", "Wizlo Bearingshiner"), color = GREEN_TEXT }
    end
    local LINE_HEIGHTS = { zone = 16, title = 16, objective = 12 }
    local contentHeight = 22
    for _, line in ipairs(lines) do
        contentHeight = contentHeight + LINE_HEIGHTS[line.kind] + (line.kind == "title" and 4 or 0)
    end
    local height = contentHeight + 30
    local left, width = addPreviewFrame(y, height)
    local x = left + 30
    if ns.settings.shouldShowTrackerBackground then
        State.detail:addRect(x - 10, y + 16, width - 40, contentHeight + 6, { 0.18, 0.15, 0.11, math.min(1, ns.Tracker.getBackgroundOpacity() * 2) }, 1) -- the dark ground, seen on the frame's darker one (as dark as set)
    end
    State.detail:addText(ns.L("Quests"), x, y + 20, { font = "GameFontNormal", color = COLORS.gold, isSingleLine = true })
    State.detail:addRect(x, y + 36, width - 60, 1, { 1, 0.82, 0, 0.4 }, 2)
    local lineY = y + 40
    for _, line in ipairs(lines) do
        if line.kind == "zone" then
            State.detail:addText(line.text, x, lineY, { font = "GameFontHighlightSmall", color = COLORS.tan, isSingleLine = true })
        elseif line.kind == "title" then
            lineY = lineY + 4
            if line.isFlashing and ns.settings.shouldFlashProgress then
                State.detail:addRect(x - 4, lineY - 2, width - 52, 30, { 1, 0.82, 0, 0.22 }, 2) -- the flash on progress
            end
            State.detail:addMark(x, lineY - 1, 16, line.mark)
            State.detail:addText(line.text, x + 22, lineY, { font = "GameFontNormalSmall", color = COLORS.gold, isSingleLine = true })
        else
            State.detail:addText(line.text, x + 22, lineY, { font = "GameFontHighlightSmall", color = line.color, isSingleLine = true })
        end
        lineY = lineY + LINE_HEIGHTS[line.kind]
    end
    return y + height + 12
end

local function addMapPreview(y)
    local height = 104
    local left, width = addPreviewFrame(y, height)
    State.detail:addRect(left + 8, y + 20, width - 16, height - 28, MAP_GROUND, 1)
    -- The focused quest's places, in the chosen look
    if ns.settings.shouldShowMapPins then
        local areaX, areaY = left + 30, y + 34
        local color = ns.MapMarks.getQuestColor(1)
        addAreaPicture(ns.MapMarks.getAreaStyle(), areaX, areaY, 54, color, 0)
        for _, spot in ipairs({ { 12, 16 }, { 30, 34 }, { 40, 14 } }) do
            addMarkerPicture(ns.MapMarks.getSpawnMarker(), areaX + spot[1], areaY + spot[2], "kill", color)
        end
        State.detail:addMark(left + 120, y + 40, 22, { kind = "objective", glyph = "kill", progress = 0.5, isFocused = true })
        State.detail:addMark(left + 160, y + 58, 22, { kind = "turnIn", progress = 1 })
    else
        -- Map marks switched off: the game's own quest area, as the game draws it
        State.detail:addIcon(left + 30, y + 34, 54, "Interface\\WorldMap\\UI-QuestBlob-Inside", { 1, 1, 1 }, 2)
        State.detail:addIcon(left + 30, y + 34, 54, "Interface\\WorldMap\\UI-QuestBlob-Outside", { 1, 1, 1 }, 3)
    end
    if ns.settings.shouldShowMapPins and ns.Availability.isShownOnMap() then
        State.detail:addMark(left + 210, y + 36, 22, { kind = "giver" })
    end
    -- The minimap, with marks when they show there
    local minimapSize = 46
    local minimapX, minimapY = left + width - minimapSize - 14, y + 26
    State.detail:addDot(minimapX - 2, minimapY - 2, minimapSize + 4, { 0.6, 0.6, 0.6 }, 4)
    State.detail:addDot(minimapX, minimapY, minimapSize, { 0.24, 0.3, 0.2 }, 5)
    if ns.settings.shouldShowMapPins and ns.settings.shouldShowMinimapPins then
        State.detail:addMark(minimapX + 10, minimapY + 12, 14, { kind = "objective", glyph = "kill", progress = 0.5 })
    end
    return y + height + 12
end

---A creature's nameplate as the game draws one, its name over its red bar, with the quest icon where and how large
---the settings put it (or none, while the icons are off).
local function addNameplatePreview(y)
    local height = 104
    local left, width = addPreviewFrame(y, height)
    local barWidth, barHeight = 140, 10
    local barLeft, barTop = left + (width - barWidth) / 2, y + 62
    State.detail:addText("Daggerspine Raider", barLeft - 30, barTop - 17, { font = "GameFontNormalSmall", color = { 1, 0.13, 0.13 }, width = barWidth + 60, justify = "CENTER", isSingleLine = true })
    State.detail:addRect(barLeft - 1, barTop - 1, barWidth + 2, barHeight + 2, { 0, 0, 0 }, 2)
    State.detail:addRect(barLeft, barTop, barWidth, barHeight, { 0.75, 0.08, 0.06 }, 3)
    State.detail:addRect(barLeft, barTop, barWidth, barHeight / 2, { 0.86, 0.2, 0.15 }, 3)
    if ns.settings.shouldShowNameplateIcons then
        -- The plate the game gives runs over the name and the bar: the icon sits off its side, or above it
        local scale = math.max(0.5, math.min(2, tonumber(ns.settings.nameplateIconScale) or 1))
        local glow, icon = ns.Nameplates.GLOW_SIZE * scale, ns.Nameplates.ICON_SIZE * scale
        local plateLeft, plateRight, plateTop, plateMiddle = barLeft, barLeft + barWidth, barTop - 18, barTop - 4
        local x, iconY
        if ns.settings.nameplateIconSide == "right" then
            x, iconY = plateRight - 6 * scale, plateMiddle - glow / 2
        elseif ns.settings.nameplateIconSide == "top" then
            x, iconY = left + width / 2 - glow / 2, plateTop - glow + 4 * scale
        else
            x, iconY = plateLeft - glow + 6 * scale, plateMiddle - glow / 2
        end
        -- In a quest's own colour and the kind chosen for the spawn markers, as on the map and the minimap
        local marker = ns.MapMarks.getSpawnMarker()
        addMarkerPicture(marker == "none" and "glyph" or marker, x + glow / 2, iconY + glow / 2, "kill", ns.MapMarks.getQuestColor(1),
            icon / 10 * (marker == "square" and 1.6 or 1))
    end
    return y + height + 12
end

local PREVIEWS = { tracker = addTrackerPreview, map = addMapPreview, nameplate = addNameplatePreview }

local function applyQuickSetup(setup)
    setup.apply()
    Log.refresh()
end

---The first page: the parts this addon replaces, each beside its icon with its checkbox at the right, as
---the game lists things on a page (no boxes on parchment), and setups in one click.
local function addOverview(y)
    y = addSettingsHeading(y, ns.L("What %s replaces", ns.ADDON_TITLE))
    local width = State.detail.width - 2 * PADDING
    local textLeft = PADDING + 44
    local textWidth = width - 44 - 34 -- room for the icon at the left and the checkbox at the right
    for _, option in ipairs(ns.SettingsPage.REPLACEMENTS) do
        local isOn = ns.SettingsPage.isOn(option)
        local top = y
        State.detail:addText(ns.L(option.name), textLeft, top, { font = "GameFontNormal", color = isOn and COLORS.gold or DISABLED, width = textWidth, isSingleLine = true })
        local noteHeight = State.detail:addText(ns.L(isOn and option.ours or option.game), textLeft, top + 17, {
            font = "GameFontHighlightSmall", color = NOTE, width = textWidth,
        })
        local height = math.max(34, 17 + noteHeight)
        State.detail:addFramedIcon(PADDING + 2, top + (height - 32) / 2, 32, option.icon)
        State.detail:addImage(PADDING + width - CHECK_SIZE, top + (height - CHECK_SIZE) / 2, CHECK_SIZE, CHECK_SIZE, CHECK_BOX, nil, nil, 3)
        if isOn then
            State.detail:addImage(PADDING + width - CHECK_SIZE, top + (height - CHECK_SIZE) / 2, CHECK_SIZE, CHECK_SIZE, CHECK_TICK, nil, nil, 4)
        end
        addRule(top + height + 4)
        State.detail:addButton(PADDING - 4, top - 4, width + 8, height + 8, toggleOption, option)
        y = top + height + 14
    end
    y = addSettingsHeading(y, ns.L("Quick setups"))
    local currentIndex = ns.SettingsPage.getQuickSetupIndex()
    for index, setup in ipairs(ns.SettingsPage.QUICK_SETUPS) do
        -- The setup in use: its name darker, with the gold tick at the right
        local isCurrent = index == currentIndex
        local top = y
        State.detail:addText(ns.L(setup.title), PADDING, top, { font = "GameFontHighlight", color = isCurrent and COLORS.gold or LABEL, width = width - 34, isSingleLine = true })
        local noteHeight = State.detail:addText(ns.L(setup.note), PADDING, top + 17, { font = "GameFontHighlightSmall", color = NOTE, width = width - 34 })
        local height = 17 + noteHeight
        if isCurrent then
            State.detail:addImage(PADDING + width - CHECK_SIZE, top + (height - CHECK_SIZE) / 2, CHECK_SIZE, CHECK_SIZE, CHECK_TICK, nil, nil, 3)
        end
        addRule(top + height + 4)
        State.detail:addButton(PADDING - 4, top - 4, width + 8, height + 8, applyQuickSetup, setup)
        y = top + height + 12
    end
    return y + 4
end

local function countMissed()
    local count = 0
    for _ in pairs(ns.settings.missedQuests) do
        count = count + 1
    end
    return count
end

-- The addon's language: the game's dropdown, each language with its flag and named in itself (never translated, so
-- a player looking for theirs reads it), in a font with every Czech letter whatever the language now
local FLAGS = "Interface\\AddOns\\" .. ns.ADDON_FOLDER .. "\\Media\\Flags\\"
local DROPDOWN_WIDTH = 190

---@return string text A language's flag and its own name, for the dropdown
local function formatLanguage(language)
    return string.format("|T%s%s:12:24|t  %s", FLAGS, language.value, language.label)
end

---The language dropdown, made once on the page's scrolling side; placed and shown as About is drawn, hidden by
---Log.refresh otherwise.
local function getLanguageDropdown()
    if State.languageDropdown ~= nil or not CreateFrame then
        return State.languageDropdown or nil
    end
    local isCreated, dropdown = pcall(CreateFrame, "DropdownButton", nil, State.detail.content, "WowStyle1DropdownTemplate")
    if not isCreated or type(dropdown) ~= "table" or not dropdown.SetupMenu then
        State.languageDropdown = false
        return nil
    end
    dropdown:SetWidth(DROPDOWN_WIDTH)
    local function isSelected(value)
        return ns.settings.language == value
    end
    local function select(value)
        chooseSetting({ key = "language", value = value })
    end
    dropdown:SetupMenu(function(_, root)
        for _, language in ipairs(ns.Locale.LANGUAGES) do
            ns.Widgets.setMenuEntryAlwaysLookAlike(root:CreateRadio(formatLanguage(language), isSelected, select, language.value))
        end
    end)
    State.languageDropdown = dropdown
    return dropdown
end

---The language: what it is for, the dropdown at the right, and the chosen one's note under.
---@return number y Below it
local function addLanguageDropdown(y)
    local top = y
    local dropdown = getLanguageDropdown()
    local rightSpace = dropdown and DROPDOWN_WIDTH + 12 or 0
    y = addSettingText(y, PADDING, "OneMoreQuest's own words", "Quests, places, people and items keep the names the game gives them.", rightSpace)
    local chosen = ns.Locale.LANGUAGES[1]
    for _, language in ipairs(ns.Locale.LANGUAGES) do
        if language.value == ns.settings.language then
            chosen = language
        end
    end
    if dropdown then
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPRIGHT", State.detail.content, "TOPLEFT", State.detail.width - PADDING, -(top - 2))
        if type(dropdown.Text) == "table" and dropdown.Text.SetFontObject then
            dropdown.Text:SetFontObject(ns.Widgets.getAlwaysLookAlikeFont("GameFontHighlightSmall"))
        end
        if dropdown.OverrideText then
            dropdown:OverrideText(formatLanguage(chosen))
        end
        dropdown:Show()
    else
        -- No dropdown in this client: the languages as tiles, as before
        return addSettingChoice(top, { choiceKey = "language", label = "Language", choices = ns.Locale.LANGUAGES })
    end
    y = math.max(y, top + 26)
    local noteHeight = State.detail:addText(chosen.note, PADDING, y + 2, { font = "GameFontHighlightSmall", color = NOTE, width = State.detail.width - 2 * PADDING })
    addRule(y + noteHeight + 6)
    return y + noteHeight + 16
end

local function addAbout(y)
    local getMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMetadata and getMetadata(ns.ADDON_FOLDER or "OneMoreQuest", "Version") or "?"
    y = addSettingsHeading(y, ns.ADDON_TITLE .. " " .. tostring(version))
    y = addBody(y, ns.L("Quests grouped by where you have to go next, in the game's own look. Made for WoW: Forever."), LABEL) + 6
    -- The addon's own language: the game has no Czech client, so it is chosen here (names from the game stay)
    y = addSettingsHeading(y + 4, ns.L("Language"))
    y = addLanguageDropdown(y)
    y = addSettingsHeading(y, ns.L("Quests the game showed"))
    local missedCount = countMissed()
    y = addBody(y, missedCount == 0 and ns.L("Every quest the game offered was already listed.")
        or ns.Lp(missedCount, "%d quest the game offered that the quest database or the addon's rules missed. Type /omq missing to see it, and send it so the hole can be fixed.",
            "%d quests the game offered that the quest database or the addon's rules missed. Type /omq missing to list them, and send the list so the holes can be fixed."), NOTE) + 6
    local differenceCount = #ns.DataCheck.composeReportLines()
    if differenceCount > 0 then
        y = addBody(y, ns.Lp(differenceCount, "%d place where the game's quests differ from the quest database (a giver, a turn-in, the items asked for). They are in /omq missing too.",
            "%d places where the game's quests differ from the quest database (givers, turn-ins, the items asked for). They are in /omq missing too."), NOTE) + 6
    end
    -- Every other addon OneMoreQuest works with now: those it reads from, translates or narrates with, and
    -- makes room for (Compatibility\, Translators\), each with what it brings
    y = addSettingsHeading(y, ns.L("Works with"))
    local integrations = {}
    for _, source in ipairs({ ns.Compatibility.getIntegrations(), ns.QuestText.getIntegrations() }) do
        for _, integration in ipairs(source) do
            integrations[#integrations + 1] = integration
        end
    end
    table.sort(integrations, function(first, second) return first.label < second.label end)
    if #integrations == 0 then
        y = addBody(y, ns.L("No other addon OneMoreQuest works with is on."), NOTE) + 6
    end
    local integrationWidth = State.detail.width - 2 * PADDING
    for _, integration in ipairs(integrations) do
        State.detail:addText(integration.label, PADDING, y, { font = "GameFontNormal", color = COLORS.gold, width = integrationWidth, isSingleLine = true })
        local noteHeight = State.detail:addText(integration.text, PADDING, y + 17, {
            font = "GameFontHighlightSmall", color = NOTE, width = integrationWidth,
        })
        y = y + 17 + noteHeight + 10
    end
    y = y + 4
    y = addSettingsHeading(y, ns.L("Credits"))
    y = addBody(y, ns.L("Quest data from QuestieDB (GPL-3.0). The list of quests that are not in the game comes from Questie (GPL-3.0). Drop rates from Tnny's Mob Loot when it is installed. Free software under the GNU GPL v3."), NOTE)
    y = addBody(y, ns.L("Logo: the sealed scroll is painted by MELLE (Fantasy parchment set, OpenGameArt, CC0)."), NOTE)
    return y
end

---The chosen section on its dark ground: its preview, then its groups of switches and choices.
---@return number height
local function drawSettingsPage()
    setPageRewards(nil)
    local section = ns.SettingsPage.SECTIONS[State.settingsSectionIndex]
    setPageHeader(ns.L(section.title), ns.L(section.subtitle or "Every change takes effect at once."))
    local y = 10
    if section.kind == "overview" then
        return addOverview(y) + PADDING
    elseif section.kind == "about" then
        return addAbout(y) + PADDING
    end
    if PREVIEWS[section.preview] then
        y = PREVIEWS[section.preview](y)
    end
    -- The part of the addon these settings are for is switched off: said first, with the switch at hand; what
    -- needs it is greyed out below
    local offPart = ns.SettingsPage.getSwitchedOffPart(section)
    if offPart then
        y = addSettingAction(y, {
            label = ns.L("%s: switched off", ns.L(offPart.name)),
            note = "What is greyed out below does nothing until it is on.",
            buttonText = "Switch on",
            handleClick = function() ns.SettingsPage.toggle(offPart) end,
        })
    end
    for _, group in ipairs(section.groups or { { options = section.options or {} } }) do
        if group.title then
            y = addSettingsHeading(y + 4, ns.L(group.title))
        end
        -- (a group may make its options as it is drawn: the hidden quests, each with its button)
        for _, option in ipairs(group.getOptions and group.getOptions() or group.options) do
            if option.choices then
                y = addSettingChoice(y, option)
            elseif option.stepKey then
                y = addSettingStepper(y, option)
            elseif option.key or option.keys then
                y = addSettingCheck(y, option)
            else
                y = addSettingAction(y, option)
            end
        end
        if group.footnote then
            local height = State.detail:addText(ns.L(group.footnote), PADDING, y, { font = "GameFontHighlightSmall", color = NOTE, width = State.detail.width - 2 * PADDING })
            y = y + height + 10
        end
    end
    return y + PADDING
end

local SECTION_ROW_HEIGHT = 32

local function selectSettingsSection(index)
    State.settingsSectionIndex = index
    State.detail:scrollToTop()
    Log.refresh()
end

---The sections down the list's side, in the list's own dark look: the chosen one on a header bar with a gold
---edge, the others in plain text.
---@return number height
local function drawSettingsSections()
    -- The flat border keeps its settings and close buttons at the top of this side: the sections start under them
    local y = ns.settings.windowBorder == "flat" and TITLE_HEIGHT or 4
    -- Titled as the chronicle's chapters are
    State.list:addText(ns.L("SETTINGS"), 8, y + 4, { font = "GameFontNormalSmall", color = COLORS.parchment, isSingleLine = true })
    y = y + 22
    for index, section in ipairs(ns.SettingsPage.SECTIONS) do
        local isChosen = index == State.settingsSectionIndex
        if isChosen then
            State.list:addRect(0, y, State.list.width, SECTION_ROW_HEIGHT, HEADER_BAR_LOW)
            State.list:addRect(0, y, State.list.width, SECTION_ROW_HEIGHT / 2, HEADER_BAR_HIGH, 1)
            State.list:addRect(0, y, 3, SECTION_ROW_HEIGHT, SELECTED_EDGE, 2)
        end
        State.list:addIcon(12, y + 4, SECTION_ROW_HEIGHT - 8, section.icon, nil, 3, { 0.08, 0.92, 0.08, 0.92 })
        State.list:addText(ns.L(section.title), 18 + SECTION_ROW_HEIGHT - 8, y + 9, { font = "GameFontNormal", color = isChosen and COLORS.gold or COLORS.parchment, isSingleLine = true, width = State.list.width - 50 })
        State.list:addButton(0, y, State.list.width, SECTION_ROW_HEIGHT, selectSettingsSection, index)
        y = y + SECTION_ROW_HEIGHT + 2
    end
    return y + 6
end

---The whole window as the settings: the sections on the list's side, the chosen one on the page, and the
---settings' own buttons under it. The tabs, the search and the quest buttons stand aside meanwhile.
function SettingsView.refreshSettings()
    -- The sections need little room, as the chronicle's chapters: the page gets the rest
    State.frame.placeSplit(ns.ChroniclePage.LIST_WIDTH)
    local pageScroll = State.detail:getScroll()
    State.shownPlace, State.shownTurnInPlace = nil, nil
    State.list.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 6, -6)
    State.list.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", 6, 6)
    -- The sections reach right up to the page; the scroll bar's strip is kept only when they need it
    local listWidth = ns.ChroniclePage.LIST_WIDTH - 6
    for _, width in ipairs({ listWidth + ns.Widgets.SCROLL_BAR_WIDTH - 1, listWidth }) do
        State.list:setWidth(width)
        State.list:clear()
        State.detail:clear()
        State.list:finish(drawSettingsSections())
        State.detail:finish(drawSettingsPage())
        if (State.list.maxScroll or 0) <= 0 then
            break
        end
    end
    State.detail:setScroll(pageScroll) -- a switch flipped leaves the page where it was
    State.isSettingsDrawn = true
    for _, control in ipairs({ State.frame.search, State.frame.availableSearch, State.frame.searchLabel, State.frame.zoneButton, State.frame.status, State.frame.tabRowFill, State.frame.tabRowRule,
        State.frame.trackAllButton, State.frame.zoneMapButton, State.frame.trackButton, State.frame.focusButton, State.frame.shareButton,
        State.frame.abandonButton, State.frame.mapButton, State.frame.turnInMapButton, State.lowLevelBar, filterDropdown.button or State.lowLevelBar, State.zoneDropdown }) do
        control:Hide()
    end
    for _, tab in ipairs(State.frame.tabs) do
        tab:Hide()
    end
    State.frame.ironPage:Show() -- the settings' dark ground in place of the parchment
    State.frame.resetSettingsButton:Show()
    State.frame.doneButton:Show()
end

---The cog: opens the settings on the page beside the list, or closes them again.
function SettingsView.toggleSettings()
    State.view = State.view == "settings" and "quests" or "settings"
    if State.view == "settings" then
        State.settingsSectionIndex = 1
        State.detail:scrollToTop()
    end
    Log.refresh()
end

---The whole window as the chronicle: its chapters on the list's side, the chosen one on the page, as the
---settings are shown.
function Log.drawChronicle()
    State.frame.placeSplit(ns.ChroniclePage.LIST_WIDTH) -- its chapters need little room; the page gets the rest
    State.shownPlace, State.shownTurnInPlace = nil, nil
    setPageRewards(nil)
    State.list.frame:SetPoint("TOPLEFT", State.frame, "TOPLEFT", 6, -6)
    State.list.frame:SetPoint("BOTTOMLEFT", State.frame, "BOTTOMLEFT", 6, 6)
    -- The chapters reach right up to the page; the scroll bar's strip is kept only when the list is long
    -- enough to scroll, as a long journal is
    local listWidth = ns.ChroniclePage.LIST_WIDTH - 6
    for _, width in ipairs({ listWidth + ns.Widgets.SCROLL_BAR_WIDTH - 1, listWidth }) do
        State.list:setWidth(width)
        State.list:clear()
        State.detail:clear()
        local listHeight, pageHeight, pageTitle, pageNote = ns.ChroniclePage.draw(State.list, State.detail)
        setPageHeader(pageTitle, pageNote)
        if ns.ChroniclePage.isEntryOpen() then
            QuestPage.setPageHeaderBack(ns.L("Back to list"), ns.ChroniclePage.closeEntry) -- as the bar's Back does
        end
        State.list:finish(listHeight)
        State.detail:finish(pageHeight)
        local pageScroll = ns.ChroniclePage.takePageScroll()
        if pageScroll then
            State.detail:setScroll(pageScroll) -- the top of a quest's story, or the journal's list where it was
        end
        if (State.list.maxScroll or 0) <= 0 then
            break
        end
    end
    State.isSettingsDrawn = true -- the quest list's places are kept aside meanwhile, as for the settings
    for _, control in ipairs({ State.frame.search, State.frame.availableSearch, State.frame.searchLabel, State.frame.zoneButton, State.frame.status, State.frame.tabRowFill, State.frame.tabRowRule,
        State.frame.trackAllButton, State.frame.zoneMapButton, State.frame.trackButton, State.frame.focusButton, State.frame.shareButton,
        State.frame.abandonButton, State.frame.mapButton, State.frame.turnInMapButton, State.lowLevelBar, filterDropdown.button or State.lowLevelBar, State.frame.resetSettingsButton, State.zoneDropdown }) do
        control:Hide()
    end
    for _, tab in ipairs(State.frame.tabs) do
        tab:Hide()
    end
    State.frame.doneButton:Show()
    State.frame.journalBackButton:SetShown(ns.ChroniclePage.isEntryOpen())
end

---The book: opens the chronicle over the window, or closes it again.
function Log.toggleChronicle()
    State.view = State.view == "chronicle" and "quests" or "chronicle"
    if State.view == "chronicle" then
        ns.ChroniclePage.openFirstChapter()
        State.detail:scrollToTop()
        State.list:scrollToTop()
    end
    Log.refresh()
end

