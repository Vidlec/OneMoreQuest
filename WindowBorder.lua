local addonName, ns = ... -- the addon's folder, which its pictures are read from

-- The frame round Trailhead's quest panels, in the look picked in the settings: the game's metal window frame,
-- a copy of the map's own frame, a thin gold line, or a flat black edge with no title strip. It owns the title
-- strip and the two buttons in it, settings and close.
local WindowBorder = {}
ns.WindowBorder = WindowBorder

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"
local GAME_STRIP_HEIGHT = 21 -- the title strip of the game's window frame
local DRAWN_STRIP_HEIGHT = 22 -- a title strip drawn by Trailhead: as tall as Leatrix Maps' title bar
local INSET = 3 -- the panels' content starts this far inside the window's edge
local MAP_BAR_COLOR = { 0.09, 0.09, 0.09 } -- a map addon's title bar, when its colour cannot be read
local GOLD = { 0.79, 0.64, 0.15, 0.9 }
local BLACK = { 0, 0, 0, 1 }
-- Lines round the content, innermost first: an edge, then a soft shadow fading out
local SHADOW = { { 0, 0, 0, 0.45 }, { 0, 0, 0, 0.3 }, { 0, 0, 0, 0.18 }, { 0, 0, 0, 0.08 } }
local EDGE_COUNT = 6

WindowBorder.STYLES = { "map", "game", "gold", "flat" }

local frame, options
local gameBorder -- the game's window frame, when this client has it
local edges = {} -- lines round the content, innermost first
local chrome -- holds what is drawn over the panels' edges: the title and the buttons
local stripFill, stripRule, title
local settingsButton, chronicleButton, gameCloseButton, flatCloseButton

local function createEdges()
    for index = 1, EDGE_COUNT do
        local edge = CreateFrame("Frame", nil, frame, "BackdropTemplate")
        edge:SetFrameLevel((frame:GetFrameLevel() or 1) + 40)
        if edge.SetBackdrop then
            edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        end
        edges[index] = edge
    end
end

---Draws lines round the content, one per colour, each a step further out.
local function setEdges(colors, stripHeight)
    for index, edge in ipairs(edges) do
        local color = colors[index]
        edge:SetShown(color ~= nil)
        if color then
            edge:ClearAllPoints()
            edge:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET - index, stripHeight - INSET + index)
            edge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INSET + index, INSET - index)
            if edge.SetBackdropBorderColor then
                edge:SetBackdropBorderColor(color[1], color[2], color[3], color[4] or 1)
            end
        end
    end
end

local function createIconButton(parent, size, texture, atlas)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    local hover = button:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints(button)
    local hasAtlas = atlas and icon.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
    for _, layer in ipairs({ icon, hover }) do
        if hasAtlas then
            layer:SetAtlas(atlas)
        else
            layer:SetTexture(texture)
        end
    end
    hover:SetBlendMode("ADD")
    hover:SetAlpha(0.5)
    button.icon = icon
    return button
end

local function showTooltip(button, text)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:AddLine(text, 1, 1, 1)
    GameTooltip:Show()
end

---Builds every part once; `apply` shows the ones the chosen look uses.
---@param window table The panels' frame
---@param layout { listWidth: number, tabRowHeight: number, stripColor: number[], handleSettingsClick: fun(), handleCloseClick: fun(), getSettingsTooltip: fun(): string, handleChronicleClick: fun()?, getChronicleTooltip: (fun(): string)? }
function WindowBorder.create(window, layout)
    frame, options = window, layout
    if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
        gameBorder = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
        gameBorder:SetFrameLevel((frame:GetFrameLevel() or 1) + 40) -- over the panels' edges, as a frame should be
        NineSliceUtil.ApplyLayoutByName(gameBorder, "ButtonFrameTemplateNoPortrait")
    end
    createEdges()
    stripFill = frame:CreateTexture(nil, "BACKGROUND")
    chrome = CreateFrame("Frame", nil, frame)
    chrome:SetAllPoints(frame)
    chrome:SetFrameLevel((frame:GetFrameLevel() or 1) + 42)
    stripRule = chrome:CreateTexture(nil, "ARTWORK")
    stripRule:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.55)
    title = ns.Widgets.createFontString(chrome, "OVERLAY", "GameFontNormal")
    title:SetText(ns.ADDON_TITLE)

    settingsButton = createIconButton(chrome, 17, "Interface\\Buttons\\UI-OptionsButton", "questlog-icon-setting")
    settingsButton:SetScript("OnClick", function() options.handleSettingsClick() end)
    settingsButton:SetScript("OnEnter", function(self) showTooltip(self, options.getSettingsTooltip()) end)
    settingsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The chronicle's book, always just left of the cog, wherever the look puts the cog
    if options.handleChronicleClick then
        chronicleButton = createIconButton(chrome, 18, "Interface\\Icons\\INV_Misc_Book_09")
        chronicleButton.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        chronicleButton:SetPoint("RIGHT", settingsButton, "LEFT", -6, 0)
        chronicleButton:SetScript("OnClick", function() options.handleChronicleClick() end)
        chronicleButton:SetScript("OnEnter", function(self) showTooltip(self, options.getChronicleTooltip and options.getChronicleTooltip() or ns.L("Chronicle")) end)
        chronicleButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- The game's own close button for its own frame; a flat cross for the drawn ones
    local isCreated, button = pcall(CreateFrame, "Button", nil, chrome, "UIPanelCloseButton")
    if isCreated and type(button) == "table" then
        gameCloseButton = button
        gameCloseButton:SetScript("OnClick", function() options.handleCloseClick() end)
    end
    flatCloseButton = createIconButton(chrome, 16, MEDIA .. "Close")
    flatCloseButton.icon:SetVertexColor(0.85, 0.85, 0.85)
    flatCloseButton:SetScript("OnClick", function() options.handleCloseClick() end)
    flatCloseButton:SetScript("OnEnter", function(self) showTooltip(self, ns.L("Close")) end)
    flatCloseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---The look actually drawn: "Like the map" copies the map's frame, and the game's frame needs the client to
---have it.
---@param mapLook table? What the map's own frame looks like, from MapDock
local function resolveStyle(style, mapLook)
    if style == "map" then
        if mapLook and mapLook.hasNativeBorder == false then
            return "drawn"
        end
        style = "game"
    end
    if style == "game" and not gameBorder then
        return "gold"
    end
    if style == "game" or style == "gold" or style == "flat" then
        return style
    end
    return gameBorder and "game" or "gold"
end

---A title strip drawn by Trailhead: filled, the title in its middle, settings and close at its right end.
local function placeDrawnStrip(stripHeight, color, hasRule)
    stripFill:Show()
    stripFill:SetColorTexture(color[1], color[2], color[3], 1)
    stripFill:ClearAllPoints()
    stripFill:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, stripHeight - INSET)
    stripFill:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -INSET, -INSET) -- down to where the content starts
    stripRule:SetShown(hasRule)
    stripRule:ClearAllPoints()
    stripRule:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, -INSET + 1)
    stripRule:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -INSET, -INSET)
    title:Show()
    title:ClearAllPoints()
    title:SetPoint("CENTER", frame, "TOP", 0, stripHeight / 2 - INSET)
    flatCloseButton:Show()
    flatCloseButton:ClearAllPoints()
    flatCloseButton:SetPoint("RIGHT", frame, "TOPRIGHT", -INSET - 5, stripHeight / 2 - INSET)
    settingsButton:ClearAllPoints()
    settingsButton:SetPoint("RIGHT", flatCloseButton, "LEFT", -6, 0)
end

---Shows the chosen look.
---@param style string "map", "game", "gold" or "flat"
---@param mapLook table? What the map's own frame looks like: { hasNativeBorder, barHeight, barColor }
---@return { stripHeight: number, outset: number, shiftX: number } layout How the window sits beside the map:
---the strip's height above the content, how far the window reaches past the map's top and bottom so its
---content lines up with the map's, and a sideways nudge
function WindowBorder.apply(style, mapLook)
    if not frame then
        return { stripHeight = 0, outset = 0, shiftX = 0 }
    end
    local drawnStyle = resolveStyle(style, mapLook)
    if gameBorder then
        gameBorder:SetShown(drawnStyle == "game")
    end
    if gameCloseButton then
        gameCloseButton:SetShown(drawnStyle == "game")
    end
    flatCloseButton:Hide()
    stripFill:Hide()
    stripRule:Hide()
    title:Hide()

    if drawnStyle == "game" then
        local stripHeight = GAME_STRIP_HEIGHT
        gameBorder:ClearAllPoints()
        gameBorder:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, stripHeight)
        gameBorder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        setEdges({}, stripHeight)
        local color = options.stripColor
        stripFill:Show()
        stripFill:SetColorTexture(color[1], color[2], color[3], 1)
        stripFill:ClearAllPoints()
        stripFill:SetPoint("TOPLEFT", frame, "TOPLEFT", INSET, stripHeight - INSET)
        stripFill:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -INSET, 0)
        title:Show()
        title:ClearAllPoints()
        title:SetPoint("TOP", gameBorder, "TOP", 0, -5)
        settingsButton:ClearAllPoints()
        if gameCloseButton then
            gameCloseButton:ClearAllPoints()
            gameCloseButton:SetPoint("TOPRIGHT", gameBorder, "TOPRIGHT", 1, 0)
            settingsButton:SetPoint("RIGHT", gameBorder, "TOPRIGHT", -30, -stripHeight / 2 - 1)
        else
            settingsButton:SetPoint("RIGHT", gameBorder, "TOPRIGHT", -9, -stripHeight / 2 - 1)
        end
        return { stripHeight = stripHeight, outset = 0, shiftX = 0 }
    end

    if drawnStyle == "drawn" then
        -- The map addon's own title bar continued: its height and colour, and the same black edge
        local stripHeight = mapLook.barHeight or DRAWN_STRIP_HEIGHT
        setEdges({ BLACK, SHADOW[1], SHADOW[2], SHADOW[3], SHADOW[4] }, stripHeight)
        placeDrawnStrip(stripHeight, mapLook.barColor or MAP_BAR_COLOR, false)
        -- Edge to edge with the map's frame, so the two read as one window
        return { stripHeight = stripHeight, outset = INSET, shiftX = -2 }
    end

    if drawnStyle == "gold" then
        local stripHeight = DRAWN_STRIP_HEIGHT
        setEdges({ GOLD, BLACK, SHADOW[1], SHADOW[2], SHADOW[3], SHADOW[4] }, stripHeight)
        placeDrawnStrip(stripHeight, options.stripColor, true)
        return { stripHeight = stripHeight, outset = INSET, shiftX = 0 }
    end

    -- Flat: no strip; the buttons stand at the end of the tab row, over the list
    setEdges({ BLACK, SHADOW[1], SHADOW[2], SHADOW[3], SHADOW[4] }, 0)
    flatCloseButton:Show()
    flatCloseButton:ClearAllPoints()
    flatCloseButton:SetPoint("RIGHT", frame, "TOPLEFT", options.listWidth - 6, -options.tabRowHeight / 2)
    settingsButton:ClearAllPoints()
    settingsButton:SetPoint("RIGHT", flatCloseButton, "LEFT", -4, 0)
    return { stripHeight = 0, outset = INSET, shiftX = 0 }
end
