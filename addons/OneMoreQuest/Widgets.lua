local addonName, ns = ... -- the addon's folder, which its pictures are read from
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- Shared pieces of the windows: colours, formatting, and a canvas that lays out pooled texts, shapes, icons and
-- click areas at exact positions.
local Widgets = {}
ns.Widgets = Widgets

Widgets.COLORS = {
    gold = { 1, 0.82, 0 },
    tan = { 0.85, 0.81, 0.66 },
    parchment = { 0.91, 0.86, 0.75 },
    white = { 1, 1, 1 },
    grey = { 0.6, 0.6, 0.6 },
    green = { 0.49, 0.88, 0.49 },
    amber = { 0.91, 0.69, 0.38 },
    rule = { 0.42, 0.38, 0.28 },
    -- On parchment
    ink = { 0.16, 0.12, 0.06 },
    softInk = { 0.35, 0.29, 0.19 },
    darkGreen = { 0.18, 0.42, 0.18 },
    brown = { 0.48, 0.31, 0 },
    sand = { 0.73, 0.67, 0.53 },
    warning = { 0.6, 0.27, 0.04 },
}

local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
-- A quest's mark on the map, as large as the game's own quest button (20); the tracker's and the lists' smaller marks are
-- scaled from it, and every part that draws or sizes marks reads it here
local MARK_NATIVE_SIZE = 20
Widgets.MARK_SIZE = MARK_NATIVE_SIZE
local SCROLL_BAR_WIDTH = 26
local DEFAULT_LINE_HEIGHT = 14
local DEFAULT_CHARACTER_WIDTH = 7

Widgets.SCROLL_BAR_WIDTH = SCROLL_BAR_WIDTH
Widgets.MIDDLE_DOT = " \194\183 "

function Widgets.setColor(fontString, color)
    fontString:SetTextColor(color[1], color[2], color[3])
end

---A font the client ships, or a common one when the name is unknown.
---Gives a checkbox made from the game's UICheckButtonTemplate Forever's own look: the minimal box and its tick.
function Widgets.setMinimalCheckLook(check)
    if not check.SetNormalAtlas then
        return
    end
    check:SetNormalAtlas("checkbox-minimal")
    check:SetPushedAtlas("checkbox-minimal")
    check:SetHighlightAtlas("checkbox-minimal", "ADD")
    local tick = check.GetCheckedTexture and check:GetCheckedTexture()
    if tick then
        tick:SetAtlas("checkmark-minimal")
    end
    local disabledTick = check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()
    if disabledTick then
        disabledTick:SetAtlas("checkmark-minimal-disabled")
    end
end

---Sets a texture to an atlas. A texture used before with its own part of a picture (an icon cropped of its
---border) keeps that part through SetAtlas in the game's client, which draws the atlas cropped, so the part is
---reset first, and the client asked to reset it as well.
function Widgets.setAtlas(texture, atlas)
    if texture.omqAtlas == atlas then
        return true -- a remembering texture (Widgets.remember) that shows this atlas already, its own part untouched
    end
    texture:SetTexCoord(0, 1, 0, 1)
    return texture:SetAtlas(atlas, false, nil, true)
end

-- Regions that remember what they were last given.
--
-- The windows are drawn by taking every text, icon and button of a pool again and setting each anew: its place, size,
-- colour, picture, text. Most drawings change almost nothing (a kill moves one count on), but every setting is a
-- call into the game, and a text set again is laid out and measured again, the dearest of all.
--
-- Widgets.remember(region) gives a region (a texture, a text, a line, a button) its own versions of the setters.
-- Each keeps what it was last given and passes on to the game only what differs. They are the region's own methods,
-- so whoever sets something on it, by whatever path, is remembered too. What is kept is let go wherever the game may
-- change it by another way (a new picture lets go of the part shown, the tint and the greying; a new font of the
-- colour and the alignment), so nothing kept can disagree with what the game has: the picture is the same as with
-- every call passed on, only the calls that change nothing are left out.
local Remembered = {}
local UNSET = {} -- "not known": equal to no value a caller can give
local ART_TEXTURE, ART_ATLAS, ART_COLOR = 1, 2, 3
local measureGeneration = 0 -- raised when every text's kept size is to be measured again (Widgets.forgetMeasures)

---Every kept text size is measured again when next asked for: the fonts changed (another language), or the size
---things are drawn at (the game's UI scale, a window's own).
function Widgets.forgetMeasures()
    measureGeneration = measureGeneration + 1
end

function Remembered.Show(self)
    self.omqHideWaits = nil -- (shown again while being dressed anew: never hidden, Widgets.hideLater)
    if self.omqShown ~= true then
        self.omqShown = true
        return self.omqRaw.Show(self)
    end
end

function Remembered.Hide(self)
    self.omqHideWaits = nil
    if self.omqShown ~= false then
        self.omqShown = false
        return self.omqRaw.Hide(self)
    end
end

function Remembered.SetShown(self, isShown)
    isShown = isShown and true or false
    self.omqHideWaits = nil
    if self.omqShown ~= isShown then
        self.omqShown = isShown
        return self.omqRaw.SetShown(self, isShown)
    end
end

-- (A part whose hiding waits reads as hidden already)
function Remembered.IsShown(self)
    if self.omqHideWaits then
        return false
    end
    return self.omqRaw.IsShown(self)
end

function Remembered.IsVisible(self)
    if self.omqHideWaits then
        return false
    end
    return self.omqRaw.IsVisible(self)
end

---Hides a part of something that is being dressed anew, where the dressing first hides every part and then shows
---those its look uses (a map mark: coin, gleam, "!"...). For a remembering part the hiding waits: shown again by
---the new look, it was never hidden, and Widgets.hideWaiting hides it if it was left out. Between the two it reads
---as hidden. Only for parts that are drawn and nothing more (textures and texts: they run no script when hidden).
function Widgets.hideLater(part)
    if type(part.omqRaw) == "table" then
        part.omqHideWaits = true
    else
        part:Hide()
    end
end

---Hides a part whose hiding still waits (Widgets.hideLater): the new look did not show it.
function Widgets.hideWaiting(part)
    if type(part.omqRaw) == "table" and part.omqHideWaits then
        part:Hide()
    end
end

-- Its place. Points set one by one are passed on as given, and what was kept is let go: a region held by several
-- points, or cleared of them, is not one Widgets.place knows the place of. (A text's size depends on its points
-- when two of them stretch it, so its kept size goes too.)
local function forgetPlace(self)
    self.omqPoint = UNSET
    self.omqStringWidth, self.omqStringHeight = nil, nil
    self.omqStartCount, self.omqEndCount = nil, nil
end

function Remembered.ClearAllPoints(self)
    forgetPlace(self)
    return self.omqRaw.ClearAllPoints(self)
end

function Remembered.SetPoint(self, ...)
    forgetPlace(self)
    return self.omqRaw.SetPoint(self, ...)
end

function Remembered.SetAllPoints(self, ...)
    forgetPlace(self)
    return self.omqRaw.SetAllPoints(self, ...)
end

---Puts a region at one point and no other: region:ClearAllPoints() and region:SetPoint(...) in one, which a
---remembering region already there needs neither of. Always with all five: the point, what it is set against,
---that one's point, and the offsets.
function Widgets.place(region, point, relativeTo, relativePoint, x, y)
    local raw = region.omqRaw
    if type(raw) ~= "table" then -- not a remembering region: as given
        region:ClearAllPoints()
        region:SetPoint(point, relativeTo, relativePoint, x, y)
        return
    end
    if
        region.omqPoint == point
        and region.omqRelativeTo == relativeTo
        and region.omqRelativePoint == relativePoint
        and region.omqX == x
        and region.omqY == y
    then
        return
    end
    -- (the same point against the same thing, only moved: set again, it takes the old one's place; nothing to clear)
    if region.omqPoint ~= point or region.omqRelativeTo ~= relativeTo or region.omqRelativePoint ~= relativePoint then
        raw.ClearAllPoints(region)
    end
    raw.SetPoint(region, point, relativeTo, relativePoint, x, y)
    region.omqPoint, region.omqRelativeTo, region.omqRelativePoint, region.omqX, region.omqY =
        point, relativeTo, relativePoint, x, y
end

-- A triangle's corners (MapMarks.setTriangle): each of the four offsets kept. On a round minimap the areas are placed
-- piece by piece at every move, and walking (not turning) moves only where each piece stands, never its shape
function Remembered.SetVertexOffset(self, index, x, y)
    local kept = self.omqVertex
    if not kept then
        kept = {}
        self.omqVertex = kept
    end
    local slot = index * 2
    if kept[slot - 1] ~= x or kept[slot] ~= y then
        kept[slot - 1], kept[slot] = x, y
        return self.omqRaw.SetVertexOffset(self, index, x, y)
    end
end

function Remembered.SetSize(self, width, height)
    if self.omqWidth ~= width or self.omqHeight ~= height then
        self.omqWidth, self.omqHeight = width, height
        self.omqStringWidth, self.omqStringHeight = nil, nil
        return self.omqRaw.SetSize(self, width, height)
    end
end

function Remembered.SetWidth(self, width)
    if self.omqWidth ~= width then
        self.omqWidth = width
        self.omqStringWidth, self.omqStringHeight = nil, nil
        return self.omqRaw.SetWidth(self, width)
    end
end

function Remembered.SetHeight(self, height)
    if self.omqHeight ~= height then
        self.omqHeight = height
        self.omqStringWidth, self.omqStringHeight = nil, nil
        return self.omqRaw.SetHeight(self, height)
    end
end

function Remembered.SetAlpha(self, alpha)
    if self.omqAlpha ~= alpha then
        self.omqAlpha = alpha
        return self.omqRaw.SetAlpha(self, alpha)
    end
end

function Remembered.SetScale(self, scale)
    if self.omqScale ~= scale then
        self.omqScale = scale
        return self.omqRaw.SetScale(self, scale)
    end
end

-- (A frame's level also moves when its parent's does, with nothing set on it: looked up, which is cheap, not kept)
function Remembered.SetFrameLevel(self, level)
    local raw = self.omqRaw
    if raw.GetFrameLevel(self) ~= level then
        return raw.SetFrameLevel(self, level)
    end
end

function Remembered.SetDrawLayer(self, layer, sublevel)
    if self.omqLayer ~= layer or self.omqSublevel ~= sublevel then
        self.omqLayer, self.omqSublevel = layer, sublevel
        return self.omqRaw.SetDrawLayer(self, layer, sublevel)
    end
end

function Remembered.SetHitRectInsets(self, left, right, top, bottom)
    if
        self.omqInsetLeft ~= left
        or self.omqInsetRight ~= right
        or self.omqInsetTop ~= top
        or self.omqInsetBottom ~= bottom
    then
        self.omqInsetLeft, self.omqInsetRight, self.omqInsetTop, self.omqInsetBottom = left, right, top, bottom
        return self.omqRaw.SetHitRectInsets(self, left, right, top, bottom)
    end
end

-- A texture's picture: a file, an atlas or a plain colour, each taking the place of the others. A new picture lets
-- go of what is kept of the part of it shown, of its tint and of its greying, whether or not the game keeps those
-- through the change: each is then passed on once more. omqAtlas is the atlas while it shows, its own part of the
-- picture untouched (Widgets.setAtlas asks).
local function forgetPictureLook(self)
    self.omqAtlas = nil
    self.omqCoordCount, self.omqTintCount, self.omqDesaturated = nil, nil, nil
end

function Remembered.SetTexture(self, ...)
    local count = select("#", ...)
    local first, second, third, fourth = ...
    if
        self.omqArt == ART_TEXTURE
        and self.omqArtCount == count
        and self.omqArt1 == first
        and self.omqArt2 == second
        and self.omqArt3 == third
        and self.omqArt4 == fourth
    then
        return
    end
    self.omqArt, self.omqArtCount, self.omqArt1, self.omqArt2, self.omqArt3, self.omqArt4 =
        ART_TEXTURE, count, first, second, third, fourth
    forgetPictureLook(self)
    return self.omqRaw.SetTexture(self, ...)
end

function Remembered.SetColorTexture(self, ...)
    local count = select("#", ...)
    local red, green, blue, alpha = ...
    if
        self.omqArt == ART_COLOR
        and self.omqArtCount == count
        and self.omqArt1 == red
        and self.omqArt2 == green
        and self.omqArt3 == blue
        and self.omqArt4 == alpha
    then
        return
    end
    self.omqArt, self.omqArtCount, self.omqArt1, self.omqArt2, self.omqArt3, self.omqArt4 =
        ART_COLOR, count, red, green, blue, alpha
    forgetPictureLook(self)
    return self.omqRaw.SetColorTexture(self, ...)
end

function Remembered.SetAtlas(self, ...)
    local count = select("#", ...)
    local atlas, useAtlasSize, third, fourth = ...
    if
        self.omqArt == ART_ATLAS
        and self.omqAtlas == atlas
        and self.omqArtCount == count
        and self.omqArt2 == useAtlasSize
        and self.omqArt3 == third
        and self.omqArt4 == fourth
    then
        return
    end
    self.omqArt, self.omqArtCount, self.omqArt1, self.omqArt2, self.omqArt3, self.omqArt4 =
        ART_ATLAS, count, atlas, useAtlasSize, third, fourth
    forgetPictureLook(self)
    self.omqAtlas = atlas
    if useAtlasSize then
        self.omqWidth, self.omqHeight = nil, nil -- asked to, the atlas brings its own size
    end
    return self.omqRaw.SetAtlas(self, ...)
end

function Remembered.SetTexCoord(self, ...)
    local count = select("#", ...)
    local a, b, c, d, e, f, g, h = ...
    local kept = self.omqCoords
    if
        kept
        and self.omqCoordCount == count
        and kept[1] == a
        and kept[2] == b
        and kept[3] == c
        and kept[4] == d
        and kept[5] == e
        and kept[6] == f
        and kept[7] == g
        and kept[8] == h
    then
        return
    end
    if not kept then
        kept = {}
        self.omqCoords = kept
    end
    self.omqCoordCount = count
    kept[1], kept[2], kept[3], kept[4], kept[5], kept[6], kept[7], kept[8] = a, b, c, d, e, f, g, h
    self.omqAtlas = nil -- an atlas's own part no longer shows: the same atlas asked for again is set again
    return self.omqRaw.SetTexCoord(self, ...)
end

-- (A text's colour can be set as a tint too, so each lets go of the other)
function Remembered.SetVertexColor(self, ...)
    local count = select("#", ...)
    local red, green, blue, alpha = ...
    if
        self.omqTintCount == count
        and self.omqTint1 == red
        and self.omqTint2 == green
        and self.omqTint3 == blue
        and self.omqTint4 == alpha
    then
        return
    end
    self.omqTintCount, self.omqTint1, self.omqTint2, self.omqTint3, self.omqTint4 = count, red, green, blue, alpha
    self.omqColorCount = nil
    return self.omqRaw.SetVertexColor(self, ...)
end

function Remembered.SetGradient(self, ...)
    self.omqTintCount = nil -- a gradient is the tint, corner by corner
    return self.omqRaw.SetGradient(self, ...)
end

function Remembered.SetDesaturated(self, isDesaturated)
    isDesaturated = isDesaturated and true or false
    if self.omqDesaturated ~= isDesaturated then
        self.omqDesaturated = isDesaturated
        return self.omqRaw.SetDesaturated(self, isDesaturated)
    end
end

-- A line: its ends and how thick it is
function Remembered.SetStartPoint(self, ...)
    local count = select("#", ...)
    local point, relativeTo, x, y = ...
    if
        self.omqStartCount == count
        and self.omqStartPoint == point
        and self.omqStartTo == relativeTo
        and self.omqStartX == x
        and self.omqStartY == y
    then
        return
    end
    self.omqStartCount, self.omqStartPoint, self.omqStartTo, self.omqStartX, self.omqStartY =
        count, point, relativeTo, x, y
    return self.omqRaw.SetStartPoint(self, ...)
end

function Remembered.SetEndPoint(self, ...)
    local count = select("#", ...)
    local point, relativeTo, x, y = ...
    if
        self.omqEndCount == count
        and self.omqEndPoint == point
        and self.omqEndTo == relativeTo
        and self.omqEndX == x
        and self.omqEndY == y
    then
        return
    end
    self.omqEndCount, self.omqEndPoint, self.omqEndTo, self.omqEndX, self.omqEndY = count, point, relativeTo, x, y
    return self.omqRaw.SetEndPoint(self, ...)
end

function Remembered.SetThickness(self, thickness)
    if self.omqThickness ~= thickness then
        self.omqThickness = thickness
        return self.omqRaw.SetThickness(self, thickness)
    end
end

-- A text: its words, colour and layout. Whatever changes how it is laid out lets go of its kept size; a font given
-- lets go of everything a font brings with it (its colour and alignment), and of the font Widgets.setTextFont keeps.
local function forgetFontLook(self)
    self.omqLookFont = nil
    self.omqColorCount, self.omqTintCount, self.omqJustifyH, self.omqJustifyV = nil, nil, nil, nil
    self.omqStringWidth, self.omqStringHeight = nil, nil
end

function Remembered.SetFontObject(self, ...)
    forgetFontLook(self)
    return self.omqRaw.SetFontObject(self, ...)
end

function Remembered.SetFont(self, ...)
    forgetFontLook(self)
    return self.omqRaw.SetFont(self, ...)
end

function Remembered.SetText(self, text)
    if self.omqText ~= text then
        self.omqText = text
        self.omqStringWidth, self.omqStringHeight = nil, nil
        return self.omqRaw.SetText(self, text)
    end
end

function Remembered.SetFormattedText(self, ...)
    self.omqText = UNSET
    self.omqStringWidth, self.omqStringHeight = nil, nil
    return self.omqRaw.SetFormattedText(self, ...)
end

function Remembered.SetTextColor(self, ...)
    local count = select("#", ...)
    local red, green, blue, alpha = ...
    if
        self.omqColorCount == count
        and self.omqColor1 == red
        and self.omqColor2 == green
        and self.omqColor3 == blue
        and self.omqColor4 == alpha
    then
        return
    end
    self.omqColorCount, self.omqColor1, self.omqColor2, self.omqColor3, self.omqColor4 = count, red, green, blue, alpha
    self.omqTintCount = nil
    return self.omqRaw.SetTextColor(self, ...)
end

function Remembered.SetWordWrap(self, isWrapped)
    isWrapped = isWrapped and true or false
    if self.omqWrap ~= isWrapped then
        self.omqWrap = isWrapped
        self.omqStringWidth, self.omqStringHeight = nil, nil
        return self.omqRaw.SetWordWrap(self, isWrapped)
    end
end

function Remembered.SetJustifyH(self, justify)
    if self.omqJustifyH ~= justify then
        self.omqJustifyH = justify
        return self.omqRaw.SetJustifyH(self, justify)
    end
end

function Remembered.SetJustifyV(self, justify)
    if self.omqJustifyV ~= justify then
        self.omqJustifyV = justify
        return self.omqRaw.SetJustifyV(self, justify)
    end
end

-- Settings that change how a text is laid out, passed on as given
for _, name in ipairs({
    "SetSpacing",
    "SetMaxLines",
    "SetIndentedWordWrap",
    "SetNonSpaceWrap",
    "SetTextScale",
    "SetTextHeight",
}) do
    Remembered[name] = function(self, ...)
        self.omqStringWidth, self.omqStringHeight = nil, nil
        return self.omqRaw[name](self, ...)
    end
end

-- A text's size as the game lays it out, kept while nothing it comes from changes: its words, font, width and
-- wrapping (each lets go of it above), the fonts themselves and the scale it is drawn at (Widgets.forgetMeasures).
-- Only for a text put at one point by Widgets.place: held by more, other regions' places decide its width.
-- A size is trusted once the game has given the same in two different frames: the first answer may come before
-- the text's font is ready or its layout settled, and a wrong one must not stick (a text drawn anew every time
-- was simply measured right the next time). So a text is measured twice in its life, not at every drawing.
function Remembered.GetStringWidth(self)
    if self.omqPoint == UNSET then
        return self.omqRaw.GetStringWidth(self)
    end
    if self.omqMeasured ~= measureGeneration then
        self.omqStringWidth, self.omqStringHeight, self.omqMeasured = nil, nil, measureGeneration
    end
    local kept = self.omqStringWidth
    if kept ~= nil and self.omqWidthSure then
        return kept
    end
    local now = GetTime and GetTime() or 0 -- (the same all through a frame)
    if kept ~= nil and self.omqWidthAt == now then
        return kept
    end
    local width = self.omqRaw.GetStringWidth(self)
    self.omqWidthSure = kept ~= nil and kept == width
    self.omqStringWidth, self.omqWidthAt = width, now
    return width
end

function Remembered.GetStringHeight(self)
    if self.omqPoint == UNSET then
        return self.omqRaw.GetStringHeight(self)
    end
    if self.omqMeasured ~= measureGeneration then
        self.omqStringWidth, self.omqStringHeight, self.omqMeasured = nil, nil, measureGeneration
    end
    local kept = self.omqStringHeight
    if kept ~= nil and self.omqHeightSure then
        return kept
    end
    local now = GetTime and GetTime() or 0
    if kept ~= nil and self.omqHeightAt == now then
        return kept
    end
    local height = self.omqRaw.GetStringHeight(self)
    self.omqHeightSure = kept ~= nil and kept == height
    self.omqStringHeight, self.omqHeightAt = height, now
    return height
end

---Gives a text a font, and of that font's file the size asked for (texts are reused from one drawing to the next,
---and one last set to a special size keeps it when given the font it already had, so the size is always set
---outright). A text that has just this already is left as it is: each font set makes the game lay the text out anew.
---@param path string? The font's file, size and flags, as fontObject:GetFont() gives them; none: the font alone
---@param size number? The size to draw at: the font's own, or another for text that has to fit a tight spot
function Widgets.setTextFont(fontString, fontObject, path, size, flags)
    if
        fontString.omqLookFont == fontObject
        and fontString.omqLookPath == path
        and fontString.omqLookSize == size
        and fontString.omqLookFlags == flags
    then
        return
    end
    fontString:SetFontObject(fontObject)
    if type(path) == "string" and type(size) == "number" then
        fontString:SetFont(path, size, flags)
    end
    -- (after the two above: a remembering text lets go of this at every font it is given)
    fontString.omqLookFont, fontString.omqLookPath, fontString.omqLookSize, fontString.omqLookFlags =
        fontObject, path, size, flags
end

---A texture's picture was changed by a way of the game's that is no method of the texture's (SetPortraitTexture
---draws a face into it): what was kept of its picture is let go.
function Widgets.forgetPicture(texture)
    if type(texture.omqRaw) == "table" then
        texture.omqArt = nil
        forgetPictureLook(texture)
    end
end

local overridesFor = {} -- [a kind of region's own methods] = { name, setter, name, setter... }: those the kind has

---Gives a region its remembering setters (those of them its kind of region has). The region's own, so every caller
---goes through them; safe to ask twice. Where the game's objects are not tables of methods (the tests' stand-ins),
---nothing is done and every setting is passed on as before.
---@return table region The same region
function Widgets.remember(region)
    if type(region) ~= "table" or type(rawget(region, "omqRaw")) == "table" then
        return region
    end
    if ns.settings and ns.settings.isPlainDrawing then
        return region -- (/omq plain: everything passed on as given, to tell a fault in the drawing apart)
    end
    local meta = getmetatable(region)
    local methods = meta and meta.__index
    if type(methods) ~= "table" then
        return region
    end
    region.omqRaw = methods
    region.omqText, region.omqPoint = UNSET, UNSET
    -- Which setters its kind of region has is worked out once for the kind (thousands of regions are made)
    local list = overridesFor[methods]
    if not list then
        list = {}
        for name, remembering in pairs(Remembered) do
            if type(methods[name]) == "function" then
                list[#list + 1] = name
                list[#list + 1] = remembering
            end
        end
        overridesFor[methods] = list
    end
    for index = 1, #list, 2 do
        region[list[index]] = list[index + 1]
    end
    return region
end

-- The game's Friz Quadrata and Morpheus have only the letters of Western Europe: Czech's ě č ř ů ň ť ď show as
-- boxes. In Czech, the addon's text takes free look-alikes that have them all (SIL Open Font License, in
-- Media\Fonts): Marcellus for Friz Quadrata, Metamorphous for Morpheus. A font another addon put in the game's
-- place (a Czech translation addon's, say) is left alone, as is Arial Narrow, which has every letter.
local FONT_FOLDER = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"
local LOOK_ALIKES =
    { frizqt__ = FONT_FOLDER .. "Marcellus-Regular.ttf", morpheus = FONT_FOLDER .. "Metamorphous-Regular.ttf" }
local fontCopies = {} -- [font object's name] = its copy in a font with every Czech letter
local trackedFontStrings = {} -- texts made from a font template, set again when the language changes
local TOOLTIP_FONTS = { "GameTooltipHeaderText", "GameTooltipText", "GameTooltipTextSmall" }
local tooltipFontPaths = {} -- [font object] = the game's own font file, while a look-alike stands in

---@return string? path The look-alike for a font file of the game's that lacks Czech letters; nil when it has them
---@param isAlways boolean? Whatever the language: for words that are Czech in any language ("Čeština")
local function getLookAlike(path, isAlways)
    -- Czech letters are needed in Czech (a translation addon's Czech quest texts are used only then too)
    if not (isAlways or (ns.Locale and ns.Locale.getLanguage() == "cs")) or type(path) ~= "string" then
        return nil
    end
    local file = path:lower():match("([^\\/]+)%.ttf$")
    return file and LOOK_ALIKES[file] or nil
end
Widgets.getLookAlike = getLookAlike

-- The game's menus (MenuUtil) draw their entries in the game's fonts, which lack Czech letters ("Otev?ít").
local MENU_METHODS = { "CreateButton", "CreateTitle", "CreateCheckbox", "CreateRadio" }

local menuFonts = {} -- [the game's font object, or its file and size] = its copy in the look-alike, for menu entries
local menuFontCount = 0

---A copy of a menu entry's font in the look-alike: the game's menus forbid SetFont on their texts ("Use of
---function 'SetFont' is disallowed"), but take a font object. One copy per font of the game's, so a gold title and
---white entries keep their own colours (a font object's change shows on every text that uses it).
local function getMenuFont(fontObject, lookAlike, size, flags)
    local key = fontObject or (lookAlike .. ":" .. tostring(size) .. ":" .. tostring(flags))
    local font = menuFonts[key]
    if not font and CreateFont then
        menuFontCount = menuFontCount + 1
        font = CreateFont("OneMoreQuestMenuFont" .. menuFontCount)
        if fontObject then
            font:CopyFontObject(fontObject) -- its colour and shadow, as the game's menu draws them
        end
        font:SetFont(lookAlike, size or 12, flags or "")
        menuFonts[key] = font
    end
    return font
end

---Sets one menu entry's text in the look-alike while it shows, and gives the button back its own font after: the
---game reuses its menu buttons for every other menu.
local function addMenuEntryFont(description, isAlways)
    if not (type(description) == "table" and description.AddInitializer) then
        return
    end
    description:AddInitializer(function(button)
        local text = button.fontString or (button.GetFontString and button:GetFontString())
        if not (text and text.GetFont and text.SetFontObject) then
            return
        end
        local path, size, flags = text:GetFont()
        local lookAlike = getLookAlike(path, isAlways)
        local fontObject = text.GetFontObject and text:GetFontObject()
        local font = lookAlike and getMenuFont(fontObject, lookAlike, size, flags)
        if font then
            button.oneMoreQuestFont = button.oneMoreQuestFont or fontObject
            pcall(text.SetFontObject, text, font) -- a menu that refuses it keeps the game's font
        end
    end)
    if description.AddResetter then
        description:AddResetter(function(button)
            local text = button.fontString or (button.GetFontString and button:GetFontString())
            if text and button.oneMoreQuestFont then
                pcall(text.SetFontObject, text, button.oneMoreQuestFont)
            end
            button.oneMoreQuestFont = nil
        end)
    end
end

---In Czech, makes every entry added to a menu (and to its submenus) draw in a font with Czech letters. Called first
---in a menu's generator: Widgets.setMenuFonts(root).
function Widgets.setMenuFonts(root)
    if not (ns.Locale and ns.Locale.getLanguage() == "cs") or type(root) ~= "table" then
        return
    end
    for _, method in ipairs(MENU_METHODS) do
        local create = root[method]
        if type(create) == "function" then
            root[method] = function(self, ...)
                local description = create(self, ...)
                addMenuEntryFont(description)
                Widgets.setMenuFonts(description) -- its submenu's entries too
                return description
            end
        end
    end
end

---@return table fontObject A font object of the game's by name; in Czech, a copy of it in a font with every
---Czech letter when the game's own lacks them
function Widgets.getFont(name)
    local font = _G[name] or GameFontNormal
    local path, size, flags
    if type(font) == "table" and font.GetFont then
        path, size, flags = font:GetFont()
    end
    local lookAlike = getLookAlike(path)
    if not lookAlike or not CreateFont then
        return font
    end
    local copy = fontCopies[name]
    if not copy then
        copy = CreateFont("OneMoreQuestFont_" .. tostring(name))
        fontCopies[name] = copy
    end
    copy:CopyFontObject(font) -- its colour and shadow, kept up with the game's
    copy:SetFont(lookAlike, size, flags)
    return copy
end

---Draws one menu entry in the look-alike whatever the language: a language's own name, which has its letters.
function Widgets.setMenuEntryAlwaysLookAlike(description)
    addMenuEntryFont(description, true)
end

local alwaysCopies = {} -- [font object's name] = its copy in the look-alike, used whatever the language

---@return table fontObject A font object of the game's by name, in the look-alike whatever the language
function Widgets.getAlwaysLookAlikeFont(name)
    local font = _G[name] or GameFontNormal
    local path, size, flags = font:GetFont()
    local lookAlike = getLookAlike(path, true)
    if not lookAlike or not CreateFont then
        return font
    end
    if not alwaysCopies[name] then
        alwaysCopies[name] = CreateFont("OneMoreQuestAlwaysFont_" .. tostring(name))
        alwaysCopies[name]:CopyFontObject(font)
        alwaysCopies[name]:SetFont(lookAlike, size, flags)
    end
    return alwaysCopies[name]
end

---Gives a button of the game's own kind (UIPanelButtonTemplate) fonts for the language: the game's lack Czech
---letters ("P?ehrát"). Called as its words are set, so a change of language reaches it.
function Widgets.setButtonFonts(button)
    if button and button.SetNormalFontObject then
        button:SetNormalFontObject(Widgets.getFont("GameFontNormal"))
        button:SetHighlightFontObject(Widgets.getFont("GameFontHighlight"))
        button:SetDisabledFontObject(Widgets.getFont("GameFontDisable"))
    end
end

---@return table fontString A text made from one of the game's font templates, its font following the language
function Widgets.createFontString(parent, layer, fontName)
    local fontString = parent:CreateFontString(nil, layer, fontName)
    fontString.fontName = fontName
    trackedFontStrings[#trackedFontStrings + 1] = fontString
    fontString:SetFontObject(Widgets.getFont(fontName))
    return fontString
end

---Sets every font again for the language: the texts made from templates, and the game's tooltips, whose fonts
---are the whole game's (in Czech, while the game's own tooltip font lacks Czech letters, every tooltip takes the
---look-alike; back in English, the game's own font returns).
function Widgets.applyFonts()
    Widgets.forgetMeasures() -- every text's kept size was measured in the fonts as they were
    for _, fontString in ipairs(trackedFontStrings) do
        fontString:SetFontObject(Widgets.getFont(fontString.fontName))
    end
    for _, name in ipairs(TOOLTIP_FONTS) do
        local font = _G[name]
        if type(font) == "table" and font.GetFont then
            local path, size, flags = font:GetFont()
            local gamePath = tooltipFontPaths[font] or path -- the game's own, also while ours stands in
            local lookAlike = getLookAlike(gamePath)
            if lookAlike then
                if path ~= lookAlike then
                    tooltipFontPaths[font] = gamePath
                    font:SetFont(lookAlike, size, flags)
                end
            elseif tooltipFontPaths[font] then
                font:SetFont(tooltipFontPaths[font], size, flags)
                tooltipFontPaths[font] = nil
            end
        end
    end
end

---Money with the game's coin icons.
function Widgets.formatMoney(copper)
    if GetMoneyString then
        return GetMoneyString(copper)
    end
    return string.format("%dg %ds %dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-- A players icon in orange, for use inside any text
local PLAYERS_ICON = "|TInterface\\AddOns\\"
    .. addonName
    .. "\\Media\\GlyphPlayers:12:12:0:0:32:32:0:32:0:32:255:176:96|t"

---The players icon and the suggested group size, when known, as text.
---@param group { size: number? }
function Widgets.formatGroup(group)
    return PLAYERS_ICON .. (group.size and ("|cffffb060" .. group.size .. "|r") or "")
end

---A quest's level and name as lists show them. A group quest gets the game's "+" after the level and the
---players icon after the name.
---@param group { size: number? }? From QuestState.getGroupInfo
-- The "and 7 more" at the end of a line of zones (Model.composeOtherZonesText), in English and in Czech
local MORE_ZONES_PATTERNS = { "( and )(%d+ more)$", "( a )(%d+ dalš%S+)$" }

---Colours the "7 more" at the end of a line of zones, as the part to point at for the rest of them.
---@param colorHex string Six hex digits
function Widgets.formatMoreZones(text, colorHex)
    for _, pattern in ipairs(MORE_ZONES_PATTERNS) do
        local colored, count = text:gsub(pattern, "%1|cff" .. colorHex .. "%2|r")
        if count > 0 then
            return colored
        end
    end
    return text
end

function Widgets.formatQuestTitle(level, title, group)
    if not group then
        return string.format("[%d] %s", level, title)
    end
    return string.format("[%d+] %s  %s", level, title, Widgets.formatGroup(group))
end

---@return number[] color A quest level's colour as the game gives it (GetQuestDifficultyColor): grey exactly when
---the game counts the quest low-level, the same rule that leaves low-level quests out of the Available list
function Widgets.getDifficultyColor(level)
    local color = GetQuestDifficultyColor and GetQuestDifficultyColor(level)
    if color then
        return { color.r, color.g, color.b }
    end
    return Widgets.COLORS.gold
end

function Widgets.formatDistance(distance)
    if not distance then
        return ""
    end
    return string.format("%d yd", math.floor(distance + 0.5))
end

---@return table texture A texture cut to a circle
local function createRound(parent, layer, subLevel)
    local texture = parent:CreateTexture(nil, layer, nil, subLevel)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return texture
end

local PORTRAIT_DIM = { 0.42, 0.39, 0.31 }
local RING_GOLD = { 1, 0.82, 0 }
local RING_TRACK = { 0.23, 0.2, 0.13 }
local RING_WIDTH = 3
local RING_SEGMENTS = 24
local READY_CHECK = "Interface\\RaidFrame\\ReadyCheck-"
-- The badge on a member's face: the game's own ready-check pictures, and its "!" for a quest to take
local BADGES = {
    ready = { texture = READY_CHECK .. "Ready" },
    done = { texture = READY_CHECK .. "Ready", isGrey = true }, -- done it before: grey, not a turn-in waiting
    can = { atlas = "QuestNormal" },
    cannot = { texture = READY_CHECK .. "NotReady" },
    unknown = { texture = READY_CHECK .. "Waiting" },
}

---@return number size A member's face with its ring, across
function Widgets.getPortraitSize(faceSize)
    return faceSize + 2 * RING_WIDTH + 2
end

---A party member's face, as the game's unit frames show it, in a ring that fills with their progress on the
---quest, clockwise from the top, with a green tick once they are ready to hand it in. Greyed, in a dim ring with
---a badge, when they are not on it: done it already, can take it, can't, or unknown. Under the mouse it gives
---their name and every count, or why not.
function Widgets.createPortrait(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame.edge = createRound(frame, "BORDER", 0)
    frame.track = createRound(frame, "BORDER", 1)
    frame.segments = {}
    for index = 1, RING_SEGMENTS do
        frame.segments[index] = frame:CreateTexture(nil, "BORDER", nil, 2)
    end
    frame.face = createRound(frame, "ARTWORK", 0)
    frame.badgeEdge = createRound(frame, "OVERLAY", 0)
    frame.badgeFill = createRound(frame, "OVERLAY", 1)
    frame.badgeIcon = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        ns.Party.addMemberToTooltip(GameTooltip, self.member)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return frame
end

---@param member table From Party.getProgress: status, and share (0 to 1, nil when unknown) when on the quest
---@param faceSize number The face's size; the ring goes round it (Widgets.getPortraitSize)
function Widgets.setPortrait(frame, member, faceSize)
    frame.member = member
    local size = Widgets.getPortraitSize(faceSize)
    frame:SetSize(size, size)
    local isOnQuest = member.status.state == "has"
    local share = isOnQuest and member.share or nil
    local function place(texture, textureSize, x, y)
        texture:ClearAllPoints()
        texture:SetPoint("CENTER", frame, "CENTER", x or 0, y or 0)
        texture:SetSize(textureSize, textureSize)
    end
    place(frame.edge, size)
    frame.edge:SetColorTexture(0, 0, 0, 1)
    place(frame.track, size - 2)
    local track = isOnQuest and RING_TRACK or PORTRAIT_DIM
    frame.track:SetColorTexture(track[1], track[2], track[3], 1)
    -- The progress: short gold pieces laid round the face, as many as the share done
    local litCount = share and math.floor(share * RING_SEGMENTS + 0.5) or 0
    local radius = faceSize / 2 + RING_WIDTH / 2
    local length = 2 * math.pi * radius / RING_SEGMENTS + 1
    for index, segment in ipairs(frame.segments) do
        segment:SetShown(index <= litCount)
        if index <= litCount then
            local angle = (index - 0.5) / RING_SEGMENTS * 2 * math.pi
            segment:ClearAllPoints()
            segment:SetPoint("CENTER", frame, "CENTER", radius * math.sin(angle), radius * math.cos(angle))
            segment:SetSize(length, RING_WIDTH)
            segment:SetColorTexture(RING_GOLD[1], RING_GOLD[2], RING_GOLD[3], 1)
            segment:SetRotation(-angle)
        end
    end
    place(frame.face, faceSize)
    ns.Party.setPortrait(frame.face, member.unit)
    frame.face:SetDesaturated(not isOnQuest)
    frame.face:SetAlpha(isOnQuest and 1 or 0.75)
    local badgeName = member.status.state
    if isOnQuest then
        badgeName = share == 1 and "ready" or share == nil and "unknown" or nil
    end
    local badge = BADGES[badgeName or ""]
    for _, part in ipairs({ frame.badgeEdge, frame.badgeFill, frame.badgeIcon }) do
        part:SetShown(badge ~= nil)
    end
    if badge then
        local badgeSize = math.max(10, math.floor(faceSize * 0.55))
        local x, y = faceSize * 0.42, -faceSize * 0.36
        place(frame.badgeEdge, badgeSize + 2, x, y)
        frame.badgeEdge:SetColorTexture(0, 0, 0, 1)
        place(frame.badgeFill, badgeSize, x, y)
        frame.badgeFill:SetColorTexture(0.1, 0.08, 0.04, 1)
        place(frame.badgeIcon, badgeSize - 2, x, y)
        if badge.atlas then
            Widgets.setAtlas(frame.badgeIcon, badge.atlas)
        else
            frame.badgeIcon:SetTexture(badge.texture)
            frame.badgeIcon:SetTexCoord(0, 1, 0, 1)
        end
        frame.badgeIcon:SetDesaturated(badge.isGrey == true)
        local shade = badge.isGrey and 0.75 or 1
        frame.badgeIcon:SetVertexColor(shade, shade, shade)
    end
    frame:Show()
end

local Canvas = {}
Canvas.__index = Canvas
local NO_OPTIONS = {} -- for a text given none (never changed)

---@param create fun(canvas: table): table Makes one more of the pool's things, on the canvas given
local function acquire(pool, create, canvas)
    pool.usedCount = pool.usedCount + 1
    local item = pool[pool.usedCount]
    if not item then
        item = create(canvas)
        pool[pool.usedCount] = item
    end
    item:Show()
    return item
end

-- What a pool's things are made as: each remembers what it was last given (Widgets.remember), so a drawing that
-- sets it the same again asks nothing of the game
local function createText(canvas)
    local created = Widgets.remember(canvas.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    created:SetDrawLayer("OVERLAY", 7) -- text over any icon it sits on
    return created
end

local function createRect(canvas)
    return Widgets.remember(canvas.content:CreateTexture(nil, "BORDER"))
end

local function createIcon(canvas)
    return Widgets.remember(canvas.content:CreateTexture(nil, "OVERLAY"))
end

local function createDot(canvas)
    local texture = canvas.content:CreateTexture(nil, "ARTWORK")
    local mask = canvas.content:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(texture)
    texture:AddMaskTexture(mask)
    return Widgets.remember(texture)
end

-- (The frame itself remembers whether it is shown, its size and its place; its parts are the mark's look's own)
local function createMark(canvas)
    local created = Widgets.remember(ns.MapMarks.createMarkButton(canvas.content))
    created:EnableMouse(false)
    return created
end

local function createPortraitItem(canvas)
    return Widgets.remember(Widgets.createPortrait(canvas.content))
end

local function handleButtonClick(self, mouseButton)
    if mouseButton == "RightButton" then
        if self.handleRightClick then
            self.handleRightClick(self.data)
        end
    elseif self.handleClick then
        self.handleClick(self.data)
    end
end

local function handleButtonEnter(self)
    if self.handleEnter then
        self.handleEnter(self, self.data)
    end
end

local function handleButtonLeave(self)
    GameTooltip:Hide()
    if self.handleLeave then
        self.handleLeave(self, self.data)
    end
end

local function createButton(canvas)
    local created = Widgets.remember(CreateFrame("Button", nil, canvas.content))
    created.hover = created:CreateTexture(nil, "HIGHLIGHT")
    created.hover:SetAllPoints(created)
    created.hover:SetColorTexture(1, 1, 1, 0.07)
    created:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    created:SetScript("OnClick", handleButtonClick)
    created:SetScript("OnEnter", handleButtonEnter)
    created:SetScript("OnLeave", handleButtonLeave)
    return created
end

-- Each font's file, size and flags, asked of the game once a drawing (every text of a drawing asked again)
local fontDetails = {}

---Starts a new drawing; everything from the previous one is reused.
function Canvas:clear()
    for _, pool in pairs(self.pools) do
        pool.usedCount = 0
    end
    fontDetails = {}
    -- Texts' sizes are kept from one drawing to the next (Widgets.remember), for the scale they were measured at
    local scale = self.content.GetEffectiveScale and self.content:GetEffectiveScale()
    if type(scale) == "number" and scale ~= self.measuredScale then
        self.measuredScale = scale
        Widgets.forgetMeasures()
    end
end

---@param options { width: number?, font: string?, fontSize: number?, color: number[]?, justify: string?, isSingleLine: boolean? }?
---@return number height, number width Of the text as drawn
function Canvas:addText(text, x, y, options)
    options = options or NO_OPTIONS
    local fontString = acquire(self.pools.texts, createText, self)
    local fontObject = Widgets.getFont(options.font or "GameFontHighlightSmall")
    local details = fontDetails[fontObject]
    if not details then
        details = {}
        if type(fontObject) == "table" and fontObject.GetFont then
            details[1], details[2], details[3] = fontObject:GetFont()
        end
        fontDetails[fontObject] = details
    end
    -- The size always set outright: the asked-for one, for text that has to fit a tight spot, or the font's own
    Widgets.setTextFont(fontString, fontObject, details[1], options.fontSize or details[2], details[3])
    -- Each of these reaches the game only when it differs from what the text has (Widgets.remember): a text that
    -- says the same as in the last drawing, at the same place, is not laid out or measured again
    fontString:SetJustifyH(options.justify or "LEFT")
    fontString:SetJustifyV("TOP")
    fontString:SetWordWrap(not options.isSingleLine)
    fontString:SetWidth(options.width or 0)
    fontString:SetText(text)
    Widgets.setColor(fontString, options.color or Widgets.COLORS.white)
    Widgets.place(fontString, "TOPLEFT", self.content, "TOPLEFT", x, -y)
    local height = fontString:GetStringHeight() or DEFAULT_LINE_HEIGHT
    local width = fontString:GetStringWidth() or (#tostring(text) * DEFAULT_CHARACTER_WIDTH)
    return height, width, fontString -- the text itself, to change while it is shown, until the next drawing
end

---@param color number[] Red, green, blue and optionally alpha
---@param level number? 0 to 7; a rectangle on a higher level draws over lower ones, as a fill over its edge
function Canvas:addRect(x, y, width, height, color, level)
    local rect = acquire(self.pools.rects, createRect, self)
    rect:SetDrawLayer("BORDER", level or 0)
    Widgets.place(rect, "TOPLEFT", self.content, "TOPLEFT", x, -y)
    rect:SetSize(math.max(width, 0.01), height)
    rect:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

---A filled circle. A ring is two dots, the inner one on a higher level.
---@param level number? 0 to 7; higher levels draw over lower ones
function Canvas:addDot(x, y, size, color, level)
    local dot = acquire(self.pools.dots, createDot, self)
    dot:SetDrawLayer("ARTWORK", level or 0)
    Widgets.place(dot, "TOPLEFT", self.content, "TOPLEFT", x, -y)
    dot:SetSize(size, size)
    dot:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
end

---A picture of any size: a texture (with its part, texCoords) or an atlas ({ atlas = name }).
---@param tintAlpha number? How much of the tinted picture shows; all of it when nil
---@return table texture To change while it is shown, until the next drawing
function Canvas:addImage(x, y, width, height, texture, texCoords, color, level, tintAlpha)
    local icon = acquire(self.pools.icons, createIcon, self)
    icon:SetDrawLayer("OVERLAY", level or 0)
    if tintAlpha then
        icon:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1, tintAlpha)
    else
        icon:SetVertexColor(color and color[1] or 1, color and color[2] or 1, color and color[3] or 1)
    end
    Widgets.place(icon, "TOPLEFT", self.content, "TOPLEFT", x, -y)
    icon:SetSize(width, height)
    icon:SetAlpha(1) -- icons are reused from one drawing to the next, and one may have been faded
    icon:SetDesaturated(false) -- and one greyed (a quest icon tinted: MapMarks.dressQuestIcon); remembered, so free
    if type(texture) == "table" then
        if icon.omqAtlas ~= texture.atlas then -- (not when it shows this atlas already)
            -- Cleared first: the texture is reused, and an atlas the client does not know would leave the last picture
            icon:SetTexture(nil)
            Widgets.setAtlas(icon, texture.atlas) -- the atlas brings its own part of the picture
        end
        return icon
    end
    icon:SetTexture(texture)
    if texCoords then
        icon:SetTexCoord(texCoords[1], texCoords[2], texCoords[3], texCoords[4])
    else
        icon:SetTexCoord(0, 1, 0, 1)
    end
    return icon
end

---@param color number[]? Tint; white textures take the colour
---@param level number? 0 to 7; an icon on a higher level draws over lower ones
---@param texture string|{ atlas: string } A picture's path, or the name of one of the game's own (an atlas)
---@param texCoords number[]? The part of the picture to show: left, right, top, bottom; all of it when nil
---@return table texture To change while it is shown, until the next drawing
function Canvas:addIcon(x, y, size, texture, color, level, texCoords)
    return self:addImage(x, y, size, size, texture, texCoords, color, level)
end

local ICON_RIM, ICON_EDGE = { 0.42, 0.29, 0.15 }, { 0, 0, 0 }

---An icon in a thin dark rim, as the game frames an icon on a page, cropped of its own border.
function Canvas:addFramedIcon(x, y, size, texture, level)
    level = level or 0
    self:addRect(x - 2, y - 2, size + 4, size + 4, ICON_RIM, level)
    self:addRect(x - 1, y - 1, size + 2, size + 2, ICON_EDGE, level + 1)
    return self:addIcon(
        x,
        y,
        size,
        texture or "Interface\\Icons\\INV_Misc_QuestionMark",
        nil,
        level + 4,
        { 0.08, 0.92, 0.08, 0.92 }
    )
end

-- Atlases are named as the game's own code names them, without Forever's "-c60": the client puts Forever's
-- variant in their place, and does not know the "-c60" names when asked for them.
-- The game's coloured progress bar (ColoredProgressBarTemplate's art): a dark rounded track, a fill tinted to a
-- colour inside its rim. The track is cut in three so its rounded ends keep their shape at any width.
local BAR_TRACK, BAR_FILL = "common-stat-bar-BG", "common-stat-bar-white"
local TRACK_WIDTH, TRACK_HEIGHT, TRACK_END = 67, 29, 12 -- the track's art, in its own pixels
local TRACK_RIM_TOP, TRACK_RIM_BOTTOM, TRACK_RIM_SIDE = 5, 7, 5
local FALLBACK_RIM, FALLBACK_GROUND = { 0.35, 0.29, 0.19 }, { 0.08, 0.06, 0.04 }

---A progress bar as the game draws its skills: the track, then each part of the fill from the left, in its colour.
---@param parts { share: number, color: number[] }[] Each a share of the bar, 0 to 1, drawn one after the other
---@return number left, number top, number innerWidth, number innerHeight Inside the rim, to mark a place on the bar
function Canvas:addStatBar(x, y, width, height, parts, level)
    level = level or 0
    local scale = height / TRACK_HEIGHT
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BAR_TRACK)
    local rimTop, rimBottom, rimSide = TRACK_RIM_TOP * scale, TRACK_RIM_BOTTOM * scale, TRACK_RIM_SIDE * scale
    if info and info.file then
        local left, right, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
        local endShare = (right - left) * TRACK_END / TRACK_WIDTH
        local endWidth = math.min(TRACK_END * scale, width / 2)
        self:addImage(x, y, endWidth, height, info.file, { left, left + endShare, top, bottom }, nil, level)
        self:addImage(
            x + endWidth,
            y,
            width - 2 * endWidth,
            height,
            info.file,
            { left + endShare, right - endShare, top, bottom },
            nil,
            level
        )
        self:addImage(
            x + width - endWidth,
            y,
            endWidth,
            height,
            info.file,
            { right - endShare, right, top, bottom },
            nil,
            level
        )
    else
        rimTop, rimBottom, rimSide = 1, 1, 1
        self:addRect(x, y, width, height, FALLBACK_RIM, level)
        self:addRect(x + 1, y + 1, width - 2, height - 2, FALLBACK_GROUND, level)
    end
    local innerLeft, innerTop = x + rimSide, y + rimTop
    local innerWidth, innerHeight = width - 2 * rimSide, height - rimTop - rimBottom
    local fillLeft = innerLeft
    for _, part in ipairs(parts) do
        local partWidth = innerWidth * math.max(0, math.min(part.share, 1))
        if partWidth >= 0.5 then
            local color = part.color
            self:addImage(
                fillLeft,
                innerTop,
                partWidth,
                innerHeight,
                { atlas = BAR_FILL },
                nil,
                color,
                level + 1,
                color[4] or 1
            )
            fillLeft = fillLeft + partWidth
        end
    end
    return innerLeft, innerTop, innerWidth, innerHeight
end

---A quest's mark exactly as the map draws it, in the look chosen in the settings, set in a square of the
---given size. It takes no clicks; whatever lies under it handles them.
---@param mark table As MapMarks.applyMarkLook takes it: kind, number, progress, isFocused
---@param isMuted boolean? Drawn faint, for something not there yet
function Canvas:addMark(x, y, size, mark, isMuted)
    local button = acquire(self.pools.marks, createMark, self)
    local scale = size / MARK_NATIVE_SIZE
    button:SetScale(scale)
    ns.MapMarks.applyMarkLook(button, mark, (self.content:GetFrameLevel() or 1) + 2)
    button:SetAlpha(isMuted and 0.45 or 1)
    -- The mark is drawn at its own size and scaled down, so its place is given in its own units
    Widgets.place(button, "CENTER", self.content, "TOPLEFT", (x + size / 2) / scale, -(y + size / 2) / scale)
end

---A party member's face in its progress ring (Widgets.setPortrait), its top left corner at x, y.
function Canvas:addPortrait(x, y, faceSize, member)
    local portrait = acquire(self.pools.portraits, createPortraitItem, self)
    portrait:SetFrameLevel((self.content:GetFrameLevel() or 1) + 3)
    Widgets.setPortrait(portrait, member, faceSize)
    Widgets.place(portrait, "TOPLEFT", self.content, "TOPLEFT", x, -y)
end

---An area that reacts to the mouse, lit up while hovered.
---@param handleClick fun(data: any)
---@param handleEnter fun(button: table, data: any)? Fills the tooltip
---@param handleRightClick fun(data: any)?
---@param handleLeave fun(button: table, data: any)? Called when the mouse leaves
function Canvas:addButton(x, y, width, height, handleClick, data, handleEnter, handleRightClick, handleLeave)
    local button = acquire(self.pools.buttons, createButton, self)
    button.handleClick, button.handleEnter, button.handleLeave, button.data =
        handleClick, handleEnter, handleLeave, data
    button.handleRightClick = handleRightClick
    button.padSkip = nil -- (set by a drawing for a shortcut the gamepad reaches another way: Gamepad.lua)
    button.isQuestRow, button.canShareWith, button.isDropSuggestion, button.isLogFullBanner = nil, nil, nil, nil -- (Gamepad.lua)
    Widgets.place(button, "TOPLEFT", self.content, "TOPLEFT", x, -y)
    button:SetSize(width, height)
    -- Reused from one drawing to the next: back to the level of any button, unless raised over another again
    button:SetFrameLevel((self.content:GetFrameLevel() or 0) + 1)
    return button
end

---Hides what this drawing did not use and sets the scrolling height.
---Gives the canvas another width, its scroll bar included, for a window that moves the line between its parts.
function Canvas:setWidth(width)
    self.width = width - SCROLL_BAR_WIDTH
    self.frame:SetWidth(self.width)
    self.content:SetWidth(self.width)
end

function Canvas:finish(height)
    for _, pool in pairs(self.pools) do
        for index = pool.usedCount + 1, #pool do
            pool[index]:Hide()
        end
    end
    self.content:SetHeight(math.max(height, 1))
    if self.frame.UpdateScrollChildRect then
        self.frame:UpdateScrollChildRect() -- the scroll range follows the new height now, not a frame later
    end
    local frameHeight = self.frame:GetHeight()
    frameHeight = type(frameHeight) == "number" and frameHeight > 0 and frameHeight or self.height
    local maxScroll = math.max(height - frameHeight, 0)
    self.maxScroll = maxScroll
    -- The scroll bar only shows when there is something to scroll. The wheel is always taken, even then: the
    -- window covers the map, and a wheel turn over it must not zoom the camera behind it
    local scrollBar = self.frame.ScrollBar
    if type(scrollBar) == "table" and scrollBar.SetShown then
        scrollBar:SetShown(maxScroll > 0)
    end
    if self.frame.EnableMouseWheel then
        self.frame:EnableMouseWheel(true)
    end
    -- A drawing shorter than the last one must not stay scrolled past its end
    local scroll = self.frame.GetVerticalScroll and self.frame:GetVerticalScroll()
    if type(scroll) == "number" and scroll > maxScroll then
        self.frame:SetVerticalScroll(maxScroll)
    end
    self:updateScrollHints()
end

---Puts the game's slim scroll bar where the drawing is. The bar measures by the scroll frame's own range, which can
---still hold a longer drawing's (the thumb then stood high up with the page scrolled to its end); the drawing's own
---end is told to it instead, and how much of it is in view.
function Canvas:syncScrollBar()
    local scrollBar = self.frame.isMinimalBar and self.frame.ScrollBar
    if type(scrollBar) ~= "table" or not scrollBar.SetScrollPercentage or not scrollBar.SetVisibleExtentPercentage then
        return
    end
    local maxScroll = self.maxScroll or 0
    local frameHeight = self.frame:GetHeight()
    frameHeight = type(frameHeight) == "number" and frameHeight > 0 and frameHeight or self.height
    scrollBar:SetVisibleExtentPercentage(maxScroll > 0 and frameHeight / (maxScroll + frameHeight) or 1)
    local percentage = maxScroll > 0 and math.max(0, math.min(1, self:getScroll() / maxScroll)) or 0
    -- (setting it may make the bar say it scrolled, which must not come back here as the player's scrolling)
    self.isSyncingBar = true
    scrollBar:SetScrollPercentage(percentage, ScrollBoxConstants and ScrollBoxConstants.NoScrollInterpolation)
    self.isSyncingBar = false
end

---Shows a shaded edge with an arrow where more of the drawing lies beyond the top or the bottom.
function Canvas:updateScrollHints()
    self:syncScrollBar()
    if not self.hints then
        return
    end
    local scroll, maxScroll = self:getScroll(), self.maxScroll or 0
    self.hints.top:SetShown(scroll > 1)
    self.hints.bottom:SetShown(scroll < maxScroll - 1)
    if self.handleScroll then
        self.handleScroll(scroll, maxScroll) -- whoever owns the drawing may follow its scrolling
    end
end

---@return number scroll How far down the drawing is scrolled
function Canvas:getScroll()
    local scroll = self.frame.GetVerticalScroll and self.frame:GetVerticalScroll()
    return type(scroll) == "number" and scroll or 0
end

---Scrolls the finished drawing, no further than its end.
function Canvas:setScroll(scroll)
    if self.frame.SetVerticalScroll then
        self.frame:SetVerticalScroll(math.max(math.min(scroll or 0, self.maxScroll or 0), 0))
    end
    self:updateScrollHints()
end

---Scrolls just enough for a part of the drawing to be in view, with a little room around it. A part already
---in view leaves the scroll as it is.
function Canvas:scrollIntoView(top, bottom)
    local frameHeight = self.frame:GetHeight()
    frameHeight = type(frameHeight) == "number" and frameHeight > 0 and frameHeight or self.height
    local scroll, margin = self:getScroll(), 24
    if top - margin < scroll then
        self:setScroll(top - margin)
    elseif bottom + margin > scroll + frameHeight then
        self:setScroll(bottom + margin - frameHeight)
    end
end

---Back to the top, for when the drawing shows something else than before.
function Canvas:scrollToTop()
    self:setScroll(0)
end

local MINIMAL_BAR_WIDTH = 8 -- the game's slim scroll bar
local WHEEL_STEP = 24 -- pixels per step of the mouse wheel
local HINT_HEIGHT = 16
local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\Media\\"

---The cues that a scrolling area has more beyond an edge: a shade fading into the content, and an arrow.
---They sit over the area and let clicks through.
---@return { top: table, bottom: table } hints
---@param overhang number How far past the area's right edge the shade runs
local function createScrollHints(scrollFrame, overhang)
    local hints = {}
    for _, edge in ipairs({ "top", "bottom" }) do
        local isTop = edge == "top"
        local hint = CreateFrame("Frame", nil, scrollFrame)
        hint:SetFrameLevel((scrollFrame:GetFrameLevel() or 1) + 20)
        hint:SetHeight(HINT_HEIGHT)
        hint:SetPoint(isTop and "TOPLEFT" or "BOTTOMLEFT", scrollFrame, isTop and "TOPLEFT" or "BOTTOMLEFT", 0, 0)
        -- Across the whole area, the scroll bar's strip included, so the shade ends at the panel's edge
        hint:SetPoint(
            isTop and "TOPRIGHT" or "BOTTOMRIGHT",
            scrollFrame,
            isTop and "TOPRIGHT" or "BOTTOMRIGHT",
            overhang,
            0
        )
        local shade = hint:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints(hint)
        shade:SetColorTexture(1, 1, 1, 1)
        if shade.SetGradient and CreateColor then
            -- Dark at the edge, clear towards the content
            local dark, clear = CreateColor(0, 0, 0, 0.28), CreateColor(0, 0, 0, 0)
            shade:SetGradient("VERTICAL", isTop and clear or dark, isTop and dark or clear)
        else
            shade:SetColorTexture(0, 0, 0, 0.15)
        end
        local disc = hint:CreateTexture(nil, "ARTWORK")
        disc:SetSize(13, 13)
        disc:SetPoint(isTop and "TOP" or "BOTTOM", hint, isTop and "TOP" or "BOTTOM", -overhang / 2, isTop and -2 or 2)
        disc:SetColorTexture(0, 0, 0, 0.45)
        local mask = hint:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK)
        mask:SetAllPoints(disc)
        disc:AddMaskTexture(mask)
        local arrow = hint:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(8, 8)
        arrow:SetPoint("CENTER", disc, "CENTER", 0, isTop and 0.5 or -0.5)
        arrow:SetTexture(MEDIA .. "ChevronDown")
        arrow:SetVertexColor(1, 0.82, 0)
        arrow:SetAlpha(0.85)
        if isTop then
            arrow:SetTexCoord(0, 1, 1, 0) -- the same arrow, upside down
        end
        hint:Hide()
        hints[edge] = hint
    end
    return hints
end

---A scroll area with the game's own slim scroll bar, the one its quest page and other modern windows use,
---standing in the strip to the area's right. A client without that bar gets the older one with its arrow
---buttons.
local function createScrollFrame(name, parent)
    local canCreateBar = ScrollUtil and ScrollUtil.InitScrollFrameWithScrollBar
    if canCreateBar then
        local scrollFrame = CreateFrame("ScrollFrame", name, parent)
        local isCreated, scrollBar = pcall(CreateFrame, "EventFrame", nil, parent, "MinimalScrollBar")
        if isCreated and type(scrollBar) == "table" then
            scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", (SCROLL_BAR_WIDTH - MINIMAL_BAR_WIDTH) / 2, -4)
            scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", (SCROLL_BAR_WIDTH - MINIMAL_BAR_WIDTH) / 2, 4)
            ScrollUtil.InitScrollFrameWithScrollBar(scrollFrame, scrollBar)
            scrollFrame.ScrollBar = scrollBar
            scrollFrame.isMinimalBar = true -- its arrows sit inside its own ends
            return scrollFrame
        end
        scrollFrame:Hide()
    end
    return CreateFrame("ScrollFrame", name .. "Legacy", parent, "UIPanelScrollFrameTemplate")
end

---A scrolling drawing area.
---@param name string Global name for the scroll frame, which its template needs
---@param width number Outer width including the scroll bar
---@return table canvas With frame (the scroll frame), content and width (the drawable width)
---@param hintOverhang number? How far the "more this way" shade runs past the drawable area: by default
---across the scroll bar's strip, to the panel's edge
function Widgets.createCanvas(name, parent, width, height, hintOverhang)
    local canvas = setmetatable({ width = width - SCROLL_BAR_WIDTH, height = height, pools = {} }, Canvas)
    for _, poolName in ipairs({ "texts", "rects", "dots", "icons", "buttons", "marks", "portraits" }) do
        canvas.pools[poolName] = { usedCount = 0 }
    end
    canvas.frame = createScrollFrame(name, parent)
    canvas.frame:SetSize(canvas.width, height)
    local scrollBar = canvas.frame.ScrollBar
    if type(scrollBar) == "table" and scrollBar.SetHideIfUnscrollable then
        scrollBar:SetHideIfUnscrollable(true)
    end
    canvas.content = CreateFrame("Frame", nil, canvas.frame)
    canvas.content:SetSize(canvas.width, 1)
    canvas.frame:SetScrollChild(canvas.content)
    -- The template scrolls half a page for every step of the wheel, which on a trackpad, where a small swipe
    -- is many steps, throws the page to its middle and then its end. A short fixed step per wheel step reads
    -- smoothly on both.
    canvas.frame:SetScript("OnMouseWheel", function(_, delta)
        canvas:setScroll(canvas:getScroll() - delta * WHEEL_STEP)
    end)
    canvas.hints = createScrollHints(canvas.frame, hintOverhang or SCROLL_BAR_WIDTH)
    local function handleVerticalScroll(scrollFrame, offset)
        -- The scroll frame's range can still be a longer drawing's; the drawing's own end is the limit
        if type(offset) == "number" and offset > (canvas.maxScroll or 0) + 0.5 then
            scrollFrame:SetVerticalScroll(canvas.maxScroll or 0)
            return
        end
        canvas:updateScrollHints()
    end
    local slimBar = canvas.frame.isMinimalBar and canvas.frame.ScrollBar
    if type(slimBar) == "table" and slimBar.RegisterCallback and BaseScrollBoxEvents then
        -- The game's slim bar is driven from here, by the drawing's own end rather than the scroll frame's range (the
        -- thumb stood high up with the page scrolled to its end): the game's handlers, which set it by that range,
        -- are replaced, not followed
        canvas.frame:SetScript("OnVerticalScroll", handleVerticalScroll)
        canvas.frame:SetScript("OnScrollRangeChanged", function()
            canvas:syncScrollBar()
        end)
        -- The bar dragged or clicked: a share of the drawing's own end (the same owner as the game's own handler,
        -- which this takes the place of)
        slimBar:RegisterCallback(BaseScrollBoxEvents.OnScroll, function(_, percentage)
            if type(percentage) == "number" and not canvas.isSyncingBar then
                canvas:setScroll(percentage * (canvas.maxScroll or 0))
            end
        end, canvas.frame)
    elseif canvas.frame.HookScript then
        canvas.frame:HookScript("OnVerticalScroll", handleVerticalScroll)
    end
    return canvas
end

ns.on("LANGUAGE_CHANGED", Widgets.applyFonts)
-- The fonts for the language, once every addon has loaded (a Czech addon may have put fonts of its own in the game's)
ns.registerModule({
    name = "Widgets",
    create = function()
        C_Timer.After(0, Widgets.applyFonts)
    end,
})
