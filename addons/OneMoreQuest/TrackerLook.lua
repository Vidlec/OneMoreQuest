local addonName, ns = ...

-- How the tracker's text reads over the world behind it: the font, its outline and shadow, the sizes, and brighter
-- colours. The tracker's lines use font objects of their own, made from the game's (in their Czech look-alikes in
-- Czech, as Widgets.getFont gives them) and given what the player chose. Every line uses them, so a setting changed
-- sets these few again, never the rows: the game redraws each text with a font object when the object changes.
-- Nothing here runs while playing; TrackerLook.apply is a string compared at each drawing of the tracker.
local TrackerLook = {}
ns.TrackerLook = TrackerLook

local FONTS_FOLDER = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"

-- The fonts offered: the game's own (whatever font it has, another addon's too), its four, and the two shipped
-- with every Czech letter; then those other addons share (SharedMedia), as "lsm:<name>"
TrackerLook.FONTS = {
    { value = "game", label = "The game's", note = "The font the game's own tracker uses." },
    {
        value = "friz",
        label = "Friz Quadrata",
        isName = true,
        file = "Fonts\\FRIZQT__.TTF",
        note = "The game's usual font. In Czech: Marcellus, which has every Czech letter.",
    },
    {
        value = "arialn",
        label = "Arial Narrow",
        isName = true,
        file = "Fonts\\ARIALN.TTF",
        note = "Narrow and plain: long titles fit.",
    },
    {
        value = "morpheus",
        label = "Morpheus",
        isName = true,
        file = "Fonts\\MORPHEUS.TTF",
        note = "The quest book's lettering. In Czech: Metamorphous.",
    },
    { value = "skurri", label = "Skurri", isName = true, file = "Fonts\\SKURRI.TTF", note = "Heavy and square." },
    {
        value = "marcellus",
        label = "Marcellus",
        isName = true,
        file = FONTS_FOLDER .. "Marcellus-Regular.ttf",
        note = "Shipped with OneMoreQuest: every Czech letter.",
    },
    {
        value = "metamorphous",
        label = "Metamorphous",
        isName = true,
        file = FONTS_FOLDER .. "Metamorphous-Regular.ttf",
        note = "Shipped with OneMoreQuest: every Czech letter.",
    },
}

local OUTLINES = { ["none"] = "", ["thin"] = "OUTLINE", ["thick"] = "THICKOUTLINE" }
local SHADOWS = { ["off"] = { 0, 0, 0 }, ["soft"] = { 1, -1, 0.85 }, ["strong"] = { 2, -2, 1 } } -- offset x, y, darkness
-- Each kind of line: the game's font it was drawn in, and the size setting it follows
local ROLES = {
    title = { base = "GameFontNormal", sizeKey = "trackerTitleSize" },
    text = { base = "GameFontHighlightSmall", sizeKey = "trackerTextSize" },
    zone = { base = "GameFontNormalSmall", sizeKey = "trackerTextSize" },
    header = { base = "GameFontNormalMed2", fallback = "GameFontNormal" },
}

local fonts = {} -- [role] = the tracker's font object
local sizes = {} -- [role] = its size, after the settings
local appliedKey -- what the font objects were last set from

local function getSharedMedia()
    return LibStub and LibStub("LibSharedMedia-3.0", true) or nil
end

---@return string? file The font file of a choice; nil for the game's own
local function getFontFile(value)
    for _, font in ipairs(TrackerLook.FONTS) do
        if font.value == value then
            return font.file
        end
    end
    local media = getSharedMedia()
    if media and type(value) == "string" and value:find("^lsm:") then
        local isFetched, file = pcall(media.Fetch, media, "font", value:sub(5), true)
        return isFetched and type(file) == "string" and file or nil
    end
    return nil
end

---@return { value: string, label: string, note: string? }[] choices The fonts offered now: ours, then other addons'
function TrackerLook.getFontChoices()
    local choices = {}
    local known = {}
    for _, font in ipairs(TrackerLook.FONTS) do
        choices[#choices + 1] = font
        known[font.label:lower()] = true
    end
    local media = getSharedMedia()
    local isListed, names = false, nil
    if media then
        isListed, names = pcall(media.List, media, "font")
    end
    if isListed and type(names) == "table" then
        for _, name in ipairs(names) do
            if type(name) == "string" and not known[name:lower()] then
                choices[#choices + 1] = {
                    value = "lsm:" .. name,
                    label = name,
                    isName = true,
                    note = "Shared by another addon (SharedMedia).",
                }
            end
        end
    end
    return choices
end

local function getKey()
    local settings = ns.settings
    return table.concat({
        tostring(settings.trackerFont),
        tostring(settings.trackerOutline),
        tostring(settings.trackerShadow),
        tostring(settings.trackerTitleSize),
        tostring(settings.trackerTextSize),
        ns.Locale and ns.Locale.getLanguage() or "",
    }, ":")
end

---Sets the tracker's font objects from the settings, when they changed since the last time.
function TrackerLook.apply()
    local key = getKey()
    if key == appliedKey or not CreateFont then
        return
    end
    appliedKey = key
    local settings = ns.settings
    local chosenFile = getFontFile(settings.trackerFont)
    -- In Czech a font without the Czech letters is drawn in its look-alike, as everywhere else in the addon
    if chosenFile and ns.Widgets.getLookAlike then
        chosenFile = ns.Widgets.getLookAlike(chosenFile) or chosenFile
    end
    local flags = OUTLINES[settings.trackerOutline] or OUTLINES.thin
    local shadow = SHADOWS[settings.trackerShadow] or SHADOWS.soft
    for role, info in pairs(ROLES) do
        local baseName = _G[info.base] and info.base or info.fallback or info.base
        local base = ns.Widgets.getFont(baseName)
        local font = fonts[role]
        if not font then
            font = CreateFont("OneMoreQuestTracker_" .. role)
            fonts[role] = font
        end
        font:CopyFontObject(base) -- its colour, as the game's
        local file, size = base:GetFont()
        local scale = info.sizeKey and tonumber(settings[info.sizeKey]) or 1
        size = (size or 12) * math.max(0.7, math.min(1.6, scale))
        font:SetFont(chosenFile or file, size, flags)
        font:SetShadowOffset(shadow[1], shadow[2])
        font:SetShadowColor(0, 0, 0, shadow[3])
        sizes[role] = size
    end
end

---@return table fontObject The tracker's font for a kind of line: "title", "text", "zone" or "header"
function TrackerLook.getFont(role)
    return fonts[role] or ns.Widgets.getFont(ROLES[role].base)
end

---@return number size The size a kind of line is drawn at
function TrackerLook.getSize(role)
    return sizes[role] or 12
end

---@return number height A line's height for a kind of line, so a larger font never runs into the next line
function TrackerLook.getRowHeight(role, least)
    return math.max(least, math.ceil(TrackerLook.getSize(role) + (role == "title" and 5 or 3)))
end

-- High-contrast text: every colour a third of the way to white (objectives white, titles brighter)
local toned = setmetatable({}, { __mode = "k" })

---@return number[] color The colour to draw, brightened when the player chose high-contrast text
function TrackerLook.tone(color)
    if not ns.settings.isTrackerHighContrast or type(color) ~= "table" then
        return color
    end
    local brighter = toned[color]
    if not brighter then
        brighter =
            { color[1] + (1 - color[1]) * 0.35, color[2] + (1 - color[2]) * 0.35, color[3] + (1 - color[3]) * 0.35 }
        toned[color] = brighter
    end
    return brighter
end

---Forgets what the font objects were set from, so the next drawing sets them again (the game's fonts changed).
function TrackerLook.reset()
    appliedKey = nil
end
