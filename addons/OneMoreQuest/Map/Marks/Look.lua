local addonName, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The map's marks: how each mark looks (the button, its tooltip and clicks, the looks of quests, givers and dungeons).
local MapMarks = ns.MapMarks
local Style, State = ns.MapMarksStyle, ns.MapMarksState
local Compose, Look, Layout, Shapes, Areas, Draw =
    ns.MapMarksCompose, ns.MapMarksLook, ns.MapMarksLayout, ns.MapMarksShapes, ns.MapMarksAreas, ns.MapMarksDraw
local CIRCLE_MASK, DARK, FOCUS_GOLD, GLYPHS, GOLD, MEDIA =
    Style.CIRCLE_MASK, Style.DARK, Style.FOCUS_GOLD, Style.GLYPHS, Style.GOLD, Style.MEDIA
local QUEST_SHADES, SOFT_DOT = Style.QUEST_SHADES, Style.SOFT_DOT
local FADED_ICON_ALPHA, FADED_ICON_GLOW_ALPHA, FOCUSED_ICON_GLOW_ALPHA =
    Style.FADED_ICON_ALPHA, Style.FADED_ICON_GLOW_ALPHA, Style.FOCUSED_ICON_GLOW_ALPHA

---------------------------------------------------------------------------------------------------------------
-- Drawing

--[[shared: State.areaLayer, State.markLayer]]
local function createPools()
    return {
        strips = { usedCount = 0 },
        dots = { usedCount = 0 },
        rings = { usedCount = 0 },
        marks = { usedCount = 0 },
        halos = { usedCount = 0 },
        glows = { usedCount = 0 },
        icons = { usedCount = 0 },
        triangles = { usedCount = 0 },
        lines = { usedCount = 0 },
        pills = { usedCount = 0 },
    }
end
State.pools = createPools()
-- What the last drawing laid out, for keeping the party clear between drawings: the map, its size and zoom, and
-- each square drawn with its place
State.drawn = { squares = {}, areas = {} }
local MEMBER_CLEAR = 9 -- no square nearer a party member's dot than this (the dot itself is 11 across)
local PLAYER_CLEAR = 13 -- nor nearer the player's arrow
local HALO_SIZE = 22 -- the soft dark patch under a party member's dot
local PARTY_SECONDS = 0.2 -- how often the party's patches follow them while the map is open

local BANG_SIZE = 17 -- height of a quest giver's "!", and of the game's "?" for a quest ready to hand in
local ITEM_BADGE_SIZE = 11 -- the "!" badge on the item a quest starts from
local ITEM_BADGE_INSET = 3 -- its middle, in from the item mark's upper right corner
local ENTRANCE_ICON_SIZE = 26 -- the game's dungeon or raid entrance icon, when no other addon draws one
local ORBIT_RADIUS = 22 -- how far a dungeon's quest marks circle its entrance icon
local ATTACHED_ORBIT_RADIUS = 25 -- round another addon's entrance icon, which is drawn larger (Leatrix Maps: 32)
local ORBIT_SCALE = 0.75 -- a quest's mark round a dungeon's entrance, against its size on the map
local MAX_ORBITING = 6 -- quest marks round one entrance; the entrance's tooltip lists them all
local ORBIT_STEP = math.pi / 3 -- one sixth of a turn between them, clockwise from the top
local ORBIT_SPOTS = 24 -- where they may go when another addon's pin covers some: every 15 degrees
local ORBIT_GAPS = { 4, 3 } -- in spots: a sixth of a turn apart where there is room, else 45 degrees, still clear
local ORBIT_WIDENINGS = { 0, 5, 10 } -- how much further out they circle when another addon's pin leaves too little room
local ITEM_MARK_SIZE = 22 -- the ring round the item a quest starts from
-- The item mark with its badge, which reaches past the ring at the upper right: laid out round its middle
local ITEM_MARK_REACH = (ITEM_MARK_SIZE + 2) / 2 + ITEM_BADGE_SIZE / 2 - ITEM_BADGE_INSET
local COIN_RIM, COIN_FACE, COIN_INK = { 0.23, 0.14, 0.01 }, { 0.87, 0.64, 0.13 }, { 0.2, 0.12, 0 }

local knownAtlases = {} -- [atlas] = whether the client has it: asked once (each asking makes a table in the game)

local function hasAtlas(atlas)
    local isKnown = knownAtlases[atlas]
    if isKnown == nil then
        isKnown = C_Texture ~= nil and C_Texture.GetAtlasInfo ~= nil and C_Texture.GetAtlasInfo(atlas) ~= nil
        if ns.frameNumber > 0 then -- (kept while the game runs; the tests swap clients)
            knownAtlases[atlas] = isKnown
        end
    end
    return isKnown
end

-- A spawn's marker is two textures, one under and one over, dressed in the kind the player chose (settings.spawnMarker):
--   "glyph":  what to do there (a sword, a sack, a hand, a speech bubble) over a soft glow in the quest's colour
--   "plate":  the same glyph on a small dark plate edged in the quest's colour
--   "game":   the game's own art, its skull for a kill, its chest for loot, its star for a thing to use, over the glow
--   "square": a small square in the quest's colour with a dark edge
-- The map and the minimap dress theirs by this one function, so a kind looks the same on both.
local GAME_SPAWN_ATLASES = { kill = "DungeonSkull", loot = "VignetteLoot", use = "VignetteEvent" } -- (talking has none: ours)
local PLATE = MEDIA .. "Plate"
local SQUARE_EDGE = { 0.04, 0.06, 0.1 }
local PLATE_SHARE, PLATE_GLYPH_SHARE = 1.35, 0.86 -- the plate against the glyph's size, and the glyph on it
local GAME_ART_SHARE, GAME_GLOW_SHARE = 1.2, 1.3 -- the game's art is fuller than a glyph: a little larger, on a wider glow, or it would hide the quest's colour
local SQUARE_SHARE = 0.45 -- a square against a glyph's size

---@param glyph string "kill", "loot", "use" or "talk"
---@param color number[] The quest's colour
---@param isStrong boolean At full strength (the quest in focus, or every quest when the player chose that)
---@param size number The glyph's size; the other kinds take theirs from it
---@param glowSize number The glow's size under a glyph
---@param dim number? How much of it shows, 0 to 1 (the minimap's are see-through)
---@param pixel number? How long a pixel is in the units the sizes are given in (1: they are pixels; the kept drawing
---gives them in a zone's own units, which grow with the map)
---@return boolean hasUnder The texture under is part of it (a glyph with its glow switched off has none): whoever
---shows the marker shows it, or keeps it hidden
function MapMarks.dressSpawnMarker(under, over, kind, glyph, color, isStrong, size, glowSize, dim, pixel)
    dim = dim or 1
    pixel = pixel or 1
    local overAlpha = (isStrong and 1 or FADED_ICON_ALPHA) * dim
    local glowAlpha = (isStrong and FOCUSED_ICON_GLOW_ALPHA or FADED_ICON_GLOW_ALPHA) * dim
    -- (the two are dressed in one kind after another as the player tries them: a picture given after the game's art
    -- would keep that art's part of its sheet, and a plain colour is tinted by what tint was left)
    under:SetTexCoord(0, 1, 0, 1)
    if kind == "square" then
        local side = math.max(size * SQUARE_SHARE, 3 * pixel)
        under:SetColorTexture(SQUARE_EDGE[1], SQUARE_EDGE[2], SQUARE_EDGE[3], 0.85 * overAlpha)
        under:SetVertexColor(1, 1, 1, 1)
        under:SetSize(side + 2 * pixel, side + 2 * pixel)
        over:SetTexCoord(0, 1, 0, 1)
        over:SetColorTexture(color[1], color[2], color[3], math.min(1, overAlpha + 0.2 * dim))
        over:SetVertexColor(1, 1, 1, 1)
        over:SetSize(side, side)
        return true
    end
    if kind == "plate" then
        over:SetTexCoord(0, 1, 0, 1)
        under:SetTexture(PLATE)
        under:SetVertexColor(color[1], color[2], color[3], math.min(1, overAlpha + 0.15 * dim))
        under:SetSize(size * PLATE_SHARE, size * PLATE_SHARE)
        MapMarks.setObjectiveIcon(over, glyph)
        over:SetVertexColor(1, 1, 1, overAlpha)
        over:SetSize(size * PLATE_GLYPH_SHARE, size * PLATE_GLYPH_SHARE)
        return true
    end
    -- A glow in the quest's colour (the player may switch it off), and over it the glyph or the game's own art
    local hasGlow = ns.settings.shouldGlowSpawnMarkers ~= false
    if hasGlow then
        under:SetTexture(SOFT_DOT)
        under:SetVertexColor(color[1], color[2], color[3], glowAlpha)
        under:SetSize(glowSize, glowSize)
    end
    local atlas = kind == "game" and GAME_SPAWN_ATLASES[glyph]
    if atlas and hasAtlas(atlas) then
        ns.Widgets.setAtlas(over, atlas)
        over:SetVertexColor(1, 1, 1, math.min(1, overAlpha + 0.15 * dim))
        over:SetSize(size * GAME_ART_SHARE, size * GAME_ART_SHARE)
        if hasGlow then
            local wide = math.max(glowSize * GAME_GLOW_SHARE, size * GAME_ART_SHARE * 1.6)
            under:SetSize(wide, wide)
        end
    else
        over:SetTexCoord(0, 1, 0, 1)
        MapMarks.setObjectiveIcon(over, glyph)
        over:SetVertexColor(1, 1, 1, overAlpha)
        over:SetSize(size, size)
    end
    return hasGlow
end

---@return number footprint How wide a marker of a kind stands, for a glyph of this size: what the laying out keeps
---apart (a plate is wider than its glyph, a square much smaller)
function MapMarks.getSpawnMarkerFootprint(kind, size)
    if kind == "square" then
        return math.max(size * SQUARE_SHARE, 3) + 2
    elseif kind == "plate" then
        return size * PLATE_SHARE
    end
    return size
end

---@return number room How much room a marker of the kind chosen needs against a glyph's, at the size the player set
---(scale: the map's or the minimap's): the spawns are thinned to it, so plates stand as clear of one another as
---glyphs do and squares may stand closer
function MapMarks.getSpawnMarkerRoom(scale)
    local room = MapMarks.getSpawnMarkerFootprint(MapMarks.getSpawnMarker(), 11) / 11
    return room * math.max(0.5, math.min(2, tonumber(scale) or 1))
end

---@return boolean isShown A quest's spawn markers are drawn at all: the quest in focus always; the others unless
---the player chose to hide theirs (settings.otherSpawnMarkers: "faded", "full" or "hidden")
---@return boolean isStrong At full strength: the quest in focus, and the others when the player chose that
function MapMarks.getSpawnMarkerStrength(isFocused)
    local others = ns.settings.otherSpawnMarkers
    if isFocused then
        return true, true
    end
    return others ~= "hidden", others == "full"
end

---Sets a texture to one of the game's own quest marks, or its older picture when the client lacks the mark.
---@param isGreyed boolean? Drawn grey (a quest not ready yet)
---@param isFileGreyed boolean? Grey when the older picture is shown (it has no grey variant of its own)
---@return boolean isAtlas The game's own art was found; otherwise the fallback file is shown
local function setGameMark(texture, atlas, fallbackFile, isGreyed, isFileGreyed)
    -- The picture first, then whether it is grey: once each, so a mark dressed the same again changes nothing
    if texture.SetAtlas and hasAtlas(atlas) then
        ns.Widgets.setAtlas(texture, atlas)
        texture:SetDesaturated(isGreyed and true or false)
        return true
    end
    texture:SetTexture(fallbackFile)
    texture:SetDesaturated((isGreyed or isFileGreyed) and true or false)
    return false
end

-- The "!" (to pick up) and "?" (to hand in) of each kind of quest, in the colour the player chose for it (settings
-- questIcon...): the game's own art where it has that colour, else its gold one greyed and tinted. Each a texture set
-- and one vertex colour, both remembered (Widgets.remember), so a mark dressed again the same asks nothing of the game.
-- Clients without the atlases get the older gold pictures, tinted.
local AVAILABLE_FILE, ACTIVE_FILE =
    "Interface\\GossipFrame\\AvailableQuestIcon", "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON_COLOURS = {
    gold = { bang = "QuestNormal", ask = "QuestTurnin" },
    blue = { bang = "QuestDaily", ask = "QuestTurnin", askTint = { 0.35, 0.72, 1 }, fileTint = { 0.35, 0.72, 1 } },
    green = { bang = "QuestNormal", ask = "QuestTurnin", tint = { 0.42, 1, 0.42 } },
    orange = { bang = "QuestLegendary", ask = "QuestLegendaryTurnin", fileTint = { 1, 0.58, 0.16 } },
    purple = { bang = "QuestNormal", ask = "QuestTurnin", tint = { 0.82, 0.55, 1 } },
    pink = { bang = "QuestNormal", ask = "QuestTurnin", tint = { 1, 0.5, 0.82 } },
    red = { bang = "QuestNormal", ask = "QuestTurnin", tint = { 1, 0.42, 0.34 } },
    grey = {
        bang = "TrivialQuests",
        ask = "QuestTurnin",
        askTint = { 0.66, 0.66, 0.66 },
        fileTint = { 0.66, 0.66, 0.66 },
    },
}
MapMarks.ICON_COLOUR_ORDER = { "gold", "blue", "green", "orange", "purple", "pink", "red", "grey" }
-- The kinds, the first that fits a quest deciding its colour; and the setting that holds each one's
MapMarks.ICON_KINDS = { "event", "pvp", "raid", "dungeon", "repeatable", "lowLevel", "normal" }
MapMarks.ICON_SETTINGS = {
    event = "questIconEvent",
    raid = "questIconRaid",
    dungeon = "questIconDungeon",
    pvp = "questIconPvP",
    repeatable = "questIconRepeatable",
    lowLevel = "questIconLowLevel",
    normal = "questIconNormal",
}
-- As the game colours them (it has no colour of its own for events, dungeons and raids), and as they start
MapMarks.GAME_ICON_COLOURS = {
    event = "gold",
    raid = "gold",
    dungeon = "gold",
    pvp = "gold",
    repeatable = "blue",
    lowLevel = "grey",
    normal = "gold",
}
MapMarks.DEFAULT_ICON_COLOURS = {
    event = "green",
    raid = "orange",
    dungeon = "gold",
    pvp = "red",
    repeatable = "blue",
    lowLevel = "grey",
    normal = "gold",
}

---@return string colour The colour chosen for a kind of quest's icons ("gold", "blue", ...)
function MapMarks.getIconColour(kind)
    local colour = ns.settings[MapMarks.ICON_SETTINGS[kind] or ""]
    return ICON_COLOURS[colour] and colour or MapMarks.DEFAULT_ICON_COLOURS[kind] or "gold"
end

---Dresses a texture as a quest's "!" or "?" in a colour.
---@param isTurnIn boolean? The "?" (to hand in); the "!" otherwise
---@param isGreyed boolean? Drawn grey whatever its colour (a quest not ready to hand in yet)
function MapMarks.dressQuestIcon(texture, colour, isTurnIn, isGreyed)
    local look = ICON_COLOURS[colour] or ICON_COLOURS.gold
    local atlas = isTurnIn and look.ask or look.bang
    local tint = look.tint or (isTurnIn and look.askTint) or nil
    if texture.SetAtlas and hasAtlas(atlas) then
        ns.Widgets.setAtlas(texture, atlas)
    else
        texture:SetTexture(isTurnIn and ACTIVE_FILE or AVAILABLE_FILE)
        texture.omqAtlas = nil -- (no atlas shown now: one set again later is set)
        tint = tint or look.fileTint
    end
    if isGreyed then
        tint = nil
    end
    texture:SetDesaturated((isGreyed or tint ~= nil) and true or false)
    texture:SetVertexColor(tint and tint[1] or 1, tint and tint[2] or 1, tint and tint[3] or 1)
end

-- What never changes of a quest's kind, kept once worked out: "event", "raid", "dungeon", "pvp", "repeatable", or false
local fixedKinds = {}

local function getFixedKind(questId)
    local kind = fixedKinds[questId]
    if kind == nil then
        local Availability = ns.Availability
        -- (PvP before the instances: the database files battlegrounds among them)
        kind = ns.Events.isEventQuest(questId) and "event"
            or Availability.isPvp(questId) and "pvp"
            or Availability.isRaid(questId) and "raid"
            or Availability.isDungeon(questId) and "dungeon"
            or Availability.isRepeatable(questId) and "repeatable"
            or false
        fixedKinds[questId] = kind
    end
    return kind
end

---@return string colour The colour of one quest's "!" (or "?", isTurnIn) in the lists: as on the map, with no mark made
function MapMarks.getQuestIconColour(questId, isLowLevel, isTurnIn)
    local kind = questId and getFixedKind(questId)
    if not kind then
        kind = (not isTurnIn and isLowLevel) and "lowLevel" or "normal"
    end
    return MapMarks.getIconColour(kind)
end

-- Each colour as text, for a "!" or "?" written in a tooltip's line
local ICON_TEXT_COLOURS = {
    gold = "ffd100",
    blue = "59b8ff",
    green = "6bff6b",
    orange = "ff9429",
    purple = "d18cff",
    pink = "ff85d1",
    red = "ff6b57",
    grey = "a8a8a8",
}

---@return string text A "!" or "?" in the colour of its quest's kind, for a tooltip's line
function MapMarks.formatQuestSign(questId, isTurnIn)
    return "|cff"
        .. ICON_TEXT_COLOURS[MapMarks.getQuestIconColour(questId, false, isTurnIn)]
        .. (isTurnIn and "?" or "!")
        .. "|r"
end

---Forgets the quests' kinds (the game told of quests' tags since, or the cities' donations were found).
function MapMarks.forgetIconKinds()
    fixedKinds = {}
end

---@return string kind The kind of quest a mark's icon is coloured for (MapMarks.ICON_KINDS): a giver of several
---quests is of a kind only when all of them are, else normal (low level when all of them are); a "?" is never low
---level, as the game's is not
---@param isTurnIn boolean? The mark's "?"
function MapMarks.getIconKind(mark, isTurnIn)
    local kind
    local questIds = mark.questIds
    if questIds and #questIds > 0 then
        for index = 1, #questIds do
            local each = getFixedKind(questIds[index])
            if index == 1 then
                kind = each
            elseif each ~= kind then
                kind = false
                break
            end
        end
    else
        kind = mark.questId and getFixedKind(mark.questId) or false
    end
    if kind then
        return kind
    end
    if mark.isRepeatable then
        return "repeatable" -- (as the mark was composed: a giver of only repeatable quests, the cities' donations too)
    end
    return (not isTurnIn and mark.isLowLevel) and "lowLevel" or "normal"
end

-- A quest in the log shows a coin. A quest of these kinds may show it otherwise (settings questMark...): "plain" as
-- every quest's, "colour" in the kind's colour (the colour of its "!" and "?", MapMarks.getIconColour), "icon" struck
-- with the kind's own icon in place of what to do, "both"
MapMarks.MARK_KINDS = { "dungeon", "raid", "pvp", "event", "repeatable" }
MapMarks.MARK_SETTINGS = {
    event = "questMarkEvent",
    raid = "questMarkRaid",
    dungeon = "questMarkDungeon",
    pvp = "questMarkPvP",
    repeatable = "questMarkRepeatable",
}
MapMarks.MARK_STYLES = { "plain", "colour", "icon", "both" }
-- The game's own icon for each kind, as its quest log puts it before a title (the event's: the horn of its map)
local MARK_KIND_ICONS = {
    dungeon = "questlog-questtypeicon-dungeon",
    raid = "questlog-questtypeicon-raid",
    pvp = "questlog-questtypeicon-pvp",
    event = "minimap-genericevent-hornicon-small",
    repeatable = "questlog-questtypeicon-recurring",
}
-- A coin in each colour of the quest icons: its face, its rim and the ink struck on it, darker shades of the face
local COIN_COLOURS = {
    gold = { face = COIN_FACE, rim = COIN_RIM, ink = COIN_INK },
    blue = { face = { 0.31, 0.61, 1 }, rim = { 0.05, 0.16, 0.33 }, ink = { 0.03, 0.1, 0.22 } },
    green = { face = { 0.37, 0.8, 0.32 }, rim = { 0.08, 0.25, 0.1 }, ink = { 0.04, 0.16, 0.05 } },
    orange = { face = { 1, 0.6, 0.18 }, rim = { 0.29, 0.14, 0 }, ink = { 0.22, 0.1, 0 } },
    purple = { face = { 0.69, 0.48, 1 }, rim = { 0.18, 0.09, 0.35 }, ink = { 0.12, 0.05, 0.24 } },
    pink = { face = { 1, 0.52, 0.8 }, rim = { 0.32, 0.07, 0.2 }, ink = { 0.24, 0.04, 0.15 } },
    red = { face = { 1, 0.35, 0.29 }, rim = { 0.29, 0.06, 0.04 }, ink = { 0.22, 0.03, 0.02 } },
    grey = { face = { 0.66, 0.66, 0.66 }, rim = { 0.17, 0.17, 0.17 }, ink = { 0.12, 0.12, 0.12 } },
}

---@return string? kind The kind a quest's coin is shown for (MapMarks.MARK_KINDS), nil for any other quest
---@return string style How (MapMarks.MARK_STYLES): the setting's, or the mark's own markStyle (the settings' pictures)
function MapMarks.getMarkStyle(mark)
    local kind = mark.markKind or (mark.questId and getFixedKind(mark.questId)) or nil
    local setting = kind and MapMarks.MARK_SETTINGS[kind]
    if not setting then
        return nil, "plain"
    end
    local style = mark.markStyle or ns.settings[setting]
    return kind, (style == "colour" or style == "icon" or style == "both") and style or "plain"
end

local MARK_GAP = -5 -- room kept between marks set side by side: below 0, their boxes may overlap that much (round marks leave the corners of their boxes empty), so each stands nearer its place
local MARK_SIZE = ns.Widgets.MARK_SIZE -- a quest's mark, as large as the game's own quest button; the one in focus too
local OVERVIEW_MAP_TYPE = 2 -- the game's map types up to "continent": cosmic 0, world 1, continent 2

local function acquire(pool, create)
    pool.usedCount = pool.usedCount + 1
    local item = pool[pool.usedCount]
    if not item then
        item = create()
        pool[pool.usedCount] = item
    end
    item.omqLoose = nil -- (let go of the map while unused: Draw; whoever takes it places it)
    item:Show()
    return item
end

-- A mark's parts remember what they were last given (Widgets.remember): a mark dressed again in the look it has
-- (the quest list, the tracker and both maps dress theirs at every drawing) asks nothing of the game.
local remember = ns.Widgets.remember

local function createCircle(parent, layer, level)
    local circle = parent:CreateTexture(nil, layer, nil, level)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(circle)
    circle:AddMaskTexture(mask)
    return remember(circle)
end

-- (a disc's colour: SetColorTexture's four numbers, given to the round picture as its tint)
local function setDiscColor(self, red, green, blue, alpha)
    return self:SetVertexColor(red, green, blue, alpha or 1)
end

---A round piece of one colour (a coin's rim, face and gleam, a ring): the round mask's own picture, a white disc,
---tinted. Painted as any colour is (SetColorTexture). A colour cut round by a mask looks the same and is the dearest
---thing there is for the game to draw (each masked picture is drawn apart from all others, every frame): a map of a
---hundred marks held two hundred of them, there for as long as the map stood open. Only a picture needs the mask (an
---item's icon: createCircle).
local function createDisc(parent, layer, level)
    local disc = parent:CreateTexture(nil, layer, nil, level)
    disc:SetTexture(CIRCLE_MASK)
    disc = remember(disc)
    disc.SetColorTexture = setDiscColor
    return disc
end

local WHITE = { 1, 1, 1 }

---The map's gamepad cursor on the mark: what A does on it, with A's icon, as the game's own pins say it (in place of
---the mouse's clicks).
---@return boolean isAdded
local function addPadLine(button)
    local GamepadMap = ns.GamepadMap
    if
        not GamepadMap
        or GamepadMap.getMark() ~= button
        or not GameTooltip_AddLineWithInputIcon
        or not GAMEPAD_FACE_BOTTOM
    then
        return false
    end
    GamepadMap.addPressLines(GameTooltip, button) -- (A, and held A, as the areas' tooltip says them)
    return true
end

local function showTooltip(button)
    local mark = button.mark
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    -- Shift going down or up while it is up shows or hides the quest's details: filled again from the start
    ns.QuestTooltip.watch(GameTooltip, button, showTooltip, button)
    if mark.kind == "dungeon" then
        -- Every quest at the entrance, the one in focus first: "!" to pick up, "?" ready to hand in; each with its
        -- level, group mark and experience (and with Shift held, what it asks)
        GameTooltip:AddLine(mark.lines[1], 1, 0.82, 0)
        for _, member in ipairs(mark.members) do
            local prefix = (member.kind == "giver" or member.kind == "turnIn")
                    and (MapMarks.formatQuestSign(member.questId, member.kind == "turnIn") .. " ")
                or ""
            if member.questIds then
                -- A shared "!" or "?": each of its quests (its first line names the NPC)
                for lineIndex = 2, #member.questIds + 1 do
                    ns.QuestTooltip.addTitle(
                        GameTooltip,
                        prefix .. member.lines[lineIndex],
                        member.questIds[lineIndex - 1],
                        WHITE,
                        true
                    )
                    ns.QuestTooltip.addDetails(GameTooltip, member.questIds[lineIndex - 1], { isBrief = true })
                end
            else
                local title = (member.lines and member.lines[1] or ""):gsub(" %- .*$", "")
                ns.QuestTooltip.addTitle(GameTooltip, prefix .. title, member.questId, WHITE, true)
                ns.QuestTooltip.addDetails(GameTooltip, member.questId, { isBrief = true })
            end
        end
        if not addPadLine(button) then
            GameTooltip:AddLine(ns.L("Click to plan the run"), 0.6, 0.6, 0.6)
            ns.QuestTooltip.addHint(GameTooltip)
        end
        GameTooltip:Show()
        return
    end
    local sharedIds = MapMarks.addMarkLines(GameTooltip, mark)
    if addPadLine(button) then
        GameTooltip:Show()
        return
    end
    local isFollowed = mark.questId == ns.Focus.get()
    local hint = not mark.isPreview
            and (isFollowed and ns.L(
                "Click to open this quest, shift-click to link it in chat, right-click to stop following it"
            ) or ns.L("Click to open this quest, shift-click to link it in chat, right-click to follow it"))
        or nil
    if mark.kind == "giver" then
        hint = mark.isFocused and ns.L("Click to stop highlighting") or ns.L("Click for details")
    end
    if hint then
        GameTooltip:AddLine(hint, 0.6, 0.6, 0.6)
    end
    if mark.questId or sharedIds then
        ns.QuestTooltip.addHint(GameTooltip)
    end
    GameTooltip:Show()
end

---@return number offset Where a mark's quests start in its lines: a shared "!" or "?" on the world map names the
---person first (1); the minimap's givers list their quests alone (0). Its quests are mark.questIds, in order.
function MapMarks.getQuestLineOffset(mark)
    local questIds = mark.questIds
    return questIds and #questIds > 0 and #mark.lines > #questIds and 1 or 0
end

---What a mark's tooltip says of its quests, the same for our marks and for the game-look "!" and "?" on the minimap:
---the title with its level, group mark and experience; a shared "!" or "?" names the person first, then each quest
---with its own (and, with Shift held, what each asks); what to do at it; how far along; the details with Shift.
---@return number[]? sharedIds The quests of a shared "!" or "?"
function MapMarks.addMarkLines(tooltip, mark)
    MapMarks.refreshMarkTexts(mark) -- its counts as they are now: the marks are not drawn again for a kill counted
    local sharedIds = mark.questIds and #mark.questIds > 0 and mark.questIds or nil
    local offset = MapMarks.getQuestLineOffset(mark)
    -- One quest and no name before it (a minimap giver with one quest): its title heads the tooltip
    local isOneQuest = sharedIds ~= nil and offset == 0 and #sharedIds == 1
    for lineIndex, line in ipairs(mark.lines) do
        local sharedId = sharedIds and sharedIds[lineIndex - offset]
        if not sharedIds and lineIndex == 1 then
            ns.QuestTooltip.addTitle(tooltip, line, mark.questId)
        elseif sharedId and isOneQuest then
            ns.QuestTooltip.addTitle(tooltip, line, sharedId)
            ns.QuestTooltip.addDetails(
                tooltip,
                sharedId,
                { isBrief = mark.kind == "giver", hasTurnIn = mark.kind == "turnIn" }
            )
        elseif sharedId then
            ns.QuestTooltip.addTitle(tooltip, line, sharedId, WHITE, true)
            ns.QuestTooltip.addDetails(tooltip, sharedId, { isBrief = true })
        elseif lineIndex == 1 then
            tooltip:AddLine(line, 1, 0.82, 0) -- the person
        else
            tooltip:AddLine(line, 1, 1, 1)
        end
    end
    -- What to do at this mark, when it is the quest in focus: a symbol in its objective's shade, then the line;
    -- a line the tooltip already has is not said twice
    local isShown = {}
    for _, line in ipairs(mark.lines) do
        isShown[line] = true
    end
    for _, label in ipairs(mark.labels or {}) do
        if not isShown[label.text] then
            local shade = QUEST_SHADES[label.shade] or GOLD
            local icon = string.format(
                "|T%s:12:12:0:0:64:64:0:64:0:64:%d:%d:%d|t ",
                GLYPHS[label.glyph] or GLYPHS.use,
                math.floor(shade[1] * 255),
                math.floor(shade[2] * 255),
                math.floor(shade[3] * 255)
            )
            tooltip:AddLine(icon .. label.text, 1, 1, 1)
        end
    end
    if mark.kind ~= "giver" and mark.progress then
        tooltip:AddLine(ns.L("%d%% done", math.floor(mark.progress * 100 + 0.5)), 0.85, 0.81, 0.66)
    end
    -- With Shift held, the quest's details: a giver's quest the short way, as several share a tooltip
    if not sharedIds and mark.questId then
        ns.QuestTooltip.addDetails(
            tooltip,
            mark.questId,
            { isBrief = mark.kind == "giver", hasTurnIn = mark.kind == "turnIn" }
        )
    end
    return sharedIds
end

---A right click on a quest giver's "!": a menu to hide its quests, each on its own (the giver's name over them).
local function openGiverMenu(button, mark)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        return
    end
    local questIds = mark.questIds and #mark.questIds > 0 and mark.questIds or { mark.questId }
    ns.openMenu(button, function(_, root)
        ns.Widgets.setMenuFonts(root)
        local offset = MapMarks.getQuestLineOffset(mark)
        root:CreateTitle(offset > 0 and mark.lines and mark.lines[1] or ns.L("Quests to pick up"))
        for _, questId in ipairs(questIds) do
            local name = ns.QuestText.getQuestName(questId) or ("Quest " .. questId)
            root:CreateButton(#questIds > 1 and ns.L("Hide %s", name) or ns.L("Hide this quest"), function()
                ns.QuestHiding.hide(questId)
            end)
        end
    end)
end

---A right click on the mark of a quest in the log puts it in focus, as a right click in the quest list does,
---or takes the focus off it again; on a quest giver's "!", a menu to hide its quests.
local function handleRightClick(button)
    local mark = button.mark
    if mark.kind == "giver" and (mark.questId or mark.questIds) and not mark.isPreview then
        openGiverMenu(button, mark)
        return
    end
    if mark.isPreview or (mark.kind ~= "objective" and mark.kind ~= "turnIn") then -- a dungeon's mark has no one quest
        return
    end
    if mark.questId == ns.Focus.get() then
        ns.Focus.set(nil)
    elseif ns.QuestState.addWatch(mark.questId) then
        ns.Focus.set(mark.questId)
    end
end

---Shift-click: the quest's link in the chat (a quest giver's first quest).
---@return boolean isHandled
local function handleLinkClick(mark)
    if not ns.QuestState.isLinkClick() or mark.kind == "dungeon" then
        return false
    end
    local questId = mark.questIds and mark.questIds[1] or mark.questId
    if not questId then
        return false
    end
    ns.QuestState.linkInChat(questId)
    return true
end

---Ctrl-click a quest of the log: it is put in focus, or let go of when it was.
---@return boolean isHandled
local function handleFocusClick(mark)
    if not (ns.QuestState.isFocusClick() and (mark.kind == "objective" or mark.kind == "turnIn") and mark.questId) then
        return false
    end
    if ns.Log.focusQuest then
        ns.Log.focusQuest(mark.questId)
    else
        ns.Focus.set(mark.questId ~= ns.Focus.get() and mark.questId or nil)
    end
    ns.MapPins.queueRefresh()
    return true
end

---The gamepad interface, the map open with the game's own quest panel: no window of OneMoreQuest's opens on it
---(MapDock.isMapHandsOff); a quest's mark puts it in focus or lets go, the rest is told by the tooltip.
---@return boolean isHandled
local function handleHandsOffClick(mark)
    if not (ns.MapDock.isMapHandsOff() and not ns.Log.isOpen() and WorldMapFrame and WorldMapFrame:IsShown()) then
        return false
    end
    if mark.questId and mark.kind ~= "giver" and mark.kind ~= "dungeon" then
        ns.Focus.set(mark.questId ~= ns.Focus.get() and mark.questId or nil)
        ns.MapPins.queueRefresh()
    end
    return true
end

---A plain click: a dungeon's mark opens its run plan, a giver's selects its quest on the Available tab (or lets go of
---it), a quest's opens it in the window.
local function handlePlainClick(mark)
    if mark.kind == "dungeon" then
        ns.Log.showZone(mark.dungeonId) -- the run plan: every quest in there, sorted by what to do
    elseif mark.kind == "giver" then
        if mark.isFocused then
            ns.Log.deselectAvailableQuest()
        else
            ns.Log.showAvailable(mark.questId)
        end
    elseif ns.Log.isOpen() then
        ns.Log.selectQuest(mark.questId) -- as a click in the quest list: opened and highlighted
    elseif ns.settings.shouldReplaceQuestLog and ns.MapDock.open then
        -- The window closed (the minimap, or the map without its panels): it opens on the quest, as the hint says.
        -- Following it alone changed nothing for the quest already followed, and the click seemed to do nothing.
        ns.MapDock.open()
        ns.Log.selectQuest(mark.questId)
    else
        ns.Focus.set(mark.questId)
    end
    ns.MapPins.queueRefresh()
end

local function handleClick(button, mouseButton)
    local mark = button.mark
    if mouseButton == "RightButton" then
        handleRightClick(button)
        return
    end
    if handleLinkClick(mark) then
        return
    end
    if mark.isPreview then
        return -- nothing to select: the quest is not in the log
    end
    if handleFocusClick(mark) or handleHandsOffClick(mark) then
        return
    end
    handlePlainClick(mark)
end

---A coin's parts, made the first time a mark is a coin: a rim, a face, and its gleam at the upper left.
local function ensureCoinParts(button)
    if type(button.edge) == "table" then -- (made already)
        return
    end
    button.omqParts = nil -- (more parts: the map lists them again, Draw's restHiddenParts)
    button.edge = createDisc(button, "BORDER", 0)
    button.edge:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.fill = createDisc(button, "ARTWORK", 0)
    button.fill:SetPoint("TOPLEFT", button.edge, "TOPLEFT", 1.5, -1.5)
    button.fill:SetPoint("BOTTOMRIGHT", button.edge, "BOTTOMRIGHT", -1.5, 1.5)
    button.shine = createDisc(button, "ARTWORK", 3)
    button.shine:SetColorTexture(1, 0.97, 0.75, 0.55)
    -- Hidden as every part is before a mark is dressed: whoever asked shows what it uses
    button.edge:Hide()
    button.fill:Hide()
    button.shine:Hide()
end

---An item mark's parts, made the first time a mark is one (a quest that starts from a dropped item): the item's own
---icon in a gold ring, so it is plain what to hunt, and its "!" badge at the upper right, drawn over everything of
---the mark, its focus glow included.
local function ensureItemParts(button)
    if type(button.itemEdge) == "table" then -- (made already)
        return
    end
    button.omqParts = nil -- (more parts: the map lists them again, Draw's restHiddenParts)
    button.itemEdge = createDisc(button, "ARTWORK", 3)
    button.itemEdge:SetColorTexture(0, 0, 0, 1)
    button.itemEdge:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.itemRing = createDisc(button, "ARTWORK", 4)
    button.itemRing:SetColorTexture(FOCUS_GOLD[1], FOCUS_GOLD[2], FOCUS_GOLD[3], 1)
    button.itemRing:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.itemIcon = createCircle(button, "ARTWORK", 5)
    button.itemIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.badgeEdge = createDisc(button, "OVERLAY", 5)
    button.badgeEdge:SetColorTexture(FOCUS_GOLD[1], FOCUS_GOLD[2], FOCUS_GOLD[3], 1)
    button.badgeFace = createDisc(button, "OVERLAY", 6)
    button.badgeFace:SetColorTexture(DARK[1], DARK[2], DARK[3], 1)
    button.badgeFace:SetPoint("CENTER", button.badgeEdge, "CENTER", 0, 0)
    button.badgeBang = remember(button:CreateTexture(nil, "OVERLAY", nil, 7))
    setGameMark(button.badgeBang, "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon")
    button.badgeBang:SetPoint("CENTER", button.badgeEdge, "CENTER", 0, 0)
end

-- The parts of a mark that a look may show, each hidden before the mark is dressed (those made so far)
local MARK_PARTS = {
    "edge",
    "fill",
    "shine",
    "bang",
    "dashedRing",
    "itemEdge",
    "itemRing",
    "itemIcon",
    "badgeEdge",
    "badgeFace",
    "badgeBang",
    "entranceIcon",
    "objectiveIcon",
}

---A mark button: a quest's coin, ring or pin, or a quest giver's "!". The minimap makes its marks with this too.
---@param parent table? The world map's mark layer when omitted
function MapMarks.createMarkButton(parent)
    local button = remember(CreateFrame("Button", nil, parent or State.markLayer))
    button.glow = remember(button:CreateTexture(nil, "BACKGROUND", nil, 0))
    button.glow:SetTexture(SOFT_DOT)
    button.glow:SetPoint("CENTER", button, "CENTER", 0, 0)
    -- The followed quest: a bright gold ring right round the mark, inside its glow
    button.focusRing = createDisc(button, "BACKGROUND", 2)
    -- (A coin's rim, face and gleam, and an item mark's ring and badge, are made when a mark first is one:
    -- ensureCoinParts and ensureItemParts. Each is a texture cut round by a mask, the dearest things to make, and a
    -- quest giver's "!" needs none of them; made with every button they were nine masks a mark.)
    button.text = remember(ns.Widgets.createFontString(button, "OVERLAY", "GameFontNormalSmall"))
    -- What the quest wants there (sword, sack, hand, speech bubble), struck in the coin's dark ink
    button.objectiveIcon = remember(button:CreateTexture(nil, "OVERLAY", nil, 2))
    -- The game's own "!" for a quest giver (gold, grey for one below your level, blue for a repeatable one), or
    -- its "?" for a quest ready to hand in
    button.bang = remember(button:CreateTexture(nil, "OVERLAY", nil, 1))
    setGameMark(button.bang, "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon")
    button.bang:SetPoint("CENTER", button, "CENTER", 0, 0)
    -- An NPC who takes quests in and gives new ones: the game's "!" beside the "?", one mark "?!"
    button.secondBang = remember(button:CreateTexture(nil, "OVERLAY", nil, 1))
    setGameMark(button.secondBang, "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon")
    -- How many quests the NPC has for you, all told, at the mark's lower right, as the game counts a stack of items
    button.count = remember(ns.Widgets.createFontString(button, "OVERLAY", "NumberFontNormalSmall"))
    -- A turn-in for a quest not taken yet: a dashed gold outline round the "?"
    button.dashedRing = remember(button:CreateTexture(nil, "ARTWORK", nil, 1))
    button.dashedRing:SetTexture(MEDIA .. "RingDashed")
    button.dashedRing:SetPoint("CENTER", button, "CENTER", 0, 0)
    -- A dungeon's mark: the game's entrance icon (or our sign on a dark coin, where the client has no such
    -- icon), circled by its quests' own marks, made when first needed
    button.entranceIcon = remember(button:CreateTexture(nil, "ARTWORK", nil, 3))
    button.entranceIcon:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.orbiting = {}
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnEnter", function(self)
        showTooltip(self)
        -- A quest giver who walks about: their path while pointed at
        if self.mark and self.mark.kind == "giver" and self.mark.questId then
            MapMarks.showHoverPatrols(self.mark.questId)
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
        MapMarks.hideHoverPatrols()
    end)
    button:SetScript("OnClick", handleClick)
    return button
end

---What a mark shows by its kind; returns its drawn size, how far its middle is raised, and the size of its glow.
local function dressMark(button, mark, size, isGiver, isReady)
    local place = ns.Widgets.place
    if mark.kind == "dungeon" then
        return MapMarks.applyDungeonLook(button, mark, size)
    end
    if isGiver and mark.itemIcon then
        -- Starts from a dropped item: the item in a gold ring with a small "!" badge, in place of the "!"
        ensureItemParts(button)
        local itemSize = ITEM_MARK_SIZE
        button:SetSize(itemSize + 2, itemSize + 2)
        button.itemEdge:SetSize(itemSize + 2, itemSize + 2)
        button.itemRing:SetSize(itemSize, itemSize)
        button.itemIcon:SetSize(itemSize - 4, itemSize - 4)
        button.itemIcon:SetTexture(mark.itemIcon)
        button.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        place(button.badgeEdge, "CENTER", button, "TOPRIGHT", -ITEM_BADGE_INSET, -ITEM_BADGE_INSET)
        button.badgeEdge:SetSize(ITEM_BADGE_SIZE, ITEM_BADGE_SIZE)
        button.badgeFace:SetSize(ITEM_BADGE_SIZE - 2, ITEM_BADGE_SIZE - 2)
        button.badgeBang:SetSize(ITEM_BADGE_SIZE, ITEM_BADGE_SIZE)
        button.itemEdge:Show()
        button.itemRing:Show()
        button.itemIcon:Show()
        button.badgeEdge:Show()
        button.badgeFace:Show()
        button.badgeBang:Show()
        local reach = ITEM_MARK_REACH * itemSize / ITEM_MARK_SIZE
        return reach * 2, reach * 2, 0, itemSize * 2, itemSize * 2
    end
    if isGiver or (isReady and not mark.isPreview) then
        -- The game's own "!" or "?", as over the NPC; grey where the client has no grey "!" of its own for a quest
        -- below your level, and for one not ready yet (the "?" over a quest giver whose quest is still to finish)
        local colour = MapMarks.getIconColour(MapMarks.getIconKind(mark, isReady))
        MapMarks.dressQuestIcon(button.bang, colour, isReady, mark.isPending)
        local bangSize = BANG_SIZE + 2
        button.bang:SetSize(bangSize, bangSize)
        button.bang:Show()
        if isReady and (mark.offerCount or 0) > 0 then
            -- The NPC gives new quests too: "?!", the game's two signs side by side, one mark
            local pairWidth = bangSize * 1.45
            button:SetSize(pairWidth, bangSize + 2)
            place(button.bang, "CENTER", button, "CENTER", -bangSize * 0.24, 0)
            -- (its "!" in the colour of a giver's: the quests it offers are not counted in the mark, so normal)
            MapMarks.dressQuestIcon(button.secondBang, MapMarks.getIconColour("normal"), false)
            button.secondBang:SetSize(bangSize, bangSize)
            place(button.secondBang, "CENTER", button, "CENTER", bangSize * 0.24, 0)
            button.secondBang:Show()
            place(button.count, "BOTTOMLEFT", button.secondBang, "BOTTOMRIGHT", -6, -1)
            return pairWidth, bangSize + 2, 0, pairWidth * 1.6, bangSize * 1.6
        end
        button:SetSize(bangSize, bangSize + 2)
        place(button.bang, "CENTER", button, "CENTER", 0, 0)
        place(button.count, "BOTTOMLEFT", button.bang, "BOTTOMRIGHT", -6, -1)
        return bangSize, bangSize + 2, 0, bangSize * 1.6, bangSize * 1.6 -- a halo round the game's "!" or "?", not a disc behind it
    end
    button:SetSize(size, size)
    if mark.isPreview then
        -- Where a quest not taken yet is handed in: a dashed gold outline round the game's "?", a place and not
        -- a quest of yours
        button.dashedRing:SetSize(size, size)
        button.dashedRing:SetVertexColor(FOCUS_GOLD[1], FOCUS_GOLD[2], FOCUS_GOLD[3], 1)
        button.dashedRing:Show()
        ensureCoinParts(button)
        button.fill:SetColorTexture(DARK[1], DARK[2], DARK[3], 0.35)
        button.fill:Show()
        MapMarks.dressQuestIcon(button.bang, MapMarks.getIconColour(MapMarks.getIconKind(mark, true)), true)
        button.bang:SetSize(size * 0.72, size * 0.72)
        button.bang:Show()
        return size, size, 0, size * 1.9, size * 1.9
    end
    -- A gold coin: dark rim, a gleam at its upper left, and what the quest wants there struck in dark ink. A quest of a
    -- kind may have it otherwise (settings questMark...): the coin in the kind's colour, the kind's own icon struck on it
    local kind, style = MapMarks.getMarkStyle(mark)
    local coinColour = (style == "colour" or style == "both") and COIN_COLOURS[MapMarks.getIconColour(kind)]
        or COIN_COLOURS.gold
    local kindAtlas = (style == "icon" or style == "both") and MARK_KIND_ICONS[kind]
    ensureCoinParts(button)
    button.edge:SetSize(size, size)
    local rim, face = coinColour.rim, coinColour.face
    button.edge:SetColorTexture(rim[1], rim[2], rim[3], 1)
    button.edge:Show()
    button.fill:SetColorTexture(face[1], face[2], face[3], 1)
    button.fill:Show()
    place(button.shine, "TOPLEFT", button.edge, "TOPLEFT", size * 0.2, -size * 0.16)
    button.shine:SetSize(size * 0.26, size * 0.2)
    button.shine:Show()
    place(button.objectiveIcon, "CENTER", button, "CENTER", 0, 0)
    if kindAtlas and hasAtlas(kindAtlas) then
        -- The game's own icon for the kind, in its own colours, a little larger than the ink it stands for
        ns.Widgets.setAtlas(button.objectiveIcon, kindAtlas)
        button.objectiveIcon:SetVertexColor(1, 1, 1, 1)
        button.objectiveIcon:SetSize(size * 0.74, size * 0.74)
    else
        local ink = coinColour.ink
        MapMarks.setObjectiveIcon(button.objectiveIcon, mark.glyph or "use")
        button.objectiveIcon:SetVertexColor(ink[1], ink[2], ink[3], 1)
        button.objectiveIcon:SetSize(size * 0.66, size * 0.66)
    end
    button.objectiveIcon:Show()
    return size, size, 0, size * 1.9, size * 1.9
end

local NO_PARTS = {}

---Calls action(part) for each of a mark's parts made so far (MARK_PARTS).
local function eachMadePart(button, action)
    for index = 1, #MARK_PARTS do
        local part = button[MARK_PARTS[index]]
        if type(part) == "table" then
            action(part)
        end
    end
end

---An NPC with several quests for you: how many in all, its "?" and its "!" counted together.
local function setQuestCount(button, mark, isGiver, isReady)
    local isCounted = (isGiver and not mark.itemIcon) or (isReady and not mark.isPreview)
    local questCount = 0
    if isCounted then
        questCount = (mark.questIds and #mark.questIds or 1) + (isReady and mark.offerCount or 0)
    end
    button.count:SetText(questCount > 1 and questCount or "")
    button.count:SetShown(questCount > 1)
end

---A mark's glow: in the colour whoever dresses the mark gave it (the world map: the colour of the quest's area),
---shown whether or not the quest is in focus; else gold, for the followed quest and a quest giver's selected quest,
---as a highlighted quest ready to hand in.
local function setMarkGlow(button, mark)
    ns.Widgets.place(button.glow, "CENTER", button, "CENTER", 0, 0)
    if type(button.glowRed) == "number" then
        button.glow:SetVertexColor(button.glowRed, button.glowGreen, button.glowBlue, button.glowAlpha)
        button.glow:Show()
    else
        button.glow:SetVertexColor(FOCUS_GOLD[1], FOCUS_GOLD[2], FOCUS_GOLD[3], 0.8)
        button.glow:SetShown(mark.isFocused == true)
    end
end

---Dresses a mark button. A quest in the log: a gold coin struck with what it wants there.
---Ready to hand in: the game's gold "?"; its turn-in before it is taken: the "?" in a dashed gold outline. A quest
---to pick up: the game's "!" (gold; grey below your level; blue when repeatable), or the item it starts from
---with a "!" badge. A dungeon: its entrance circled by its quests' marks. No numbers.
---Every part is set once, to what the look wants (its parts remember what they have: Widgets.remember), so a mark
---dressed again in the look it has costs nothing; a part the look leaves out is hidden at the end.
---Read from the button, set by whoever dresses it before this: glowScale (its glow's size against the mark's own,
---1 when nil) and glowRed, glowGreen, glowBlue, glowAlpha (its glow in that colour and always shown; gold and only
---for the quest in focus when nil).
---@param baseLevel number? Frame level the kinds of mark are layered from; the world map's when omitted
---@return number width, number height Of what is drawn
---@return number raise How far the middle of what is drawn sits above the spot; a pin stands on its tip
function MapMarks.applyMarkLook(button, mark, baseLevel)
    local isGiver = mark.kind == "giver"
    local isReady = mark.kind == "turnIn"
    local size = MARK_SIZE -- the one in focus stands out by its gold ring and glow, at the same size, as the game's does
    button.mark = mark
    if button.SetHitRectInsets then
        button:SetHitRectInsets(0, 0, 0, 0) -- the whole mark answers the mouse; a dungeon's only its middle
    end
    button:SetFrameLevel((baseLevel or State.frameLevel + 1) + (mark.isFocused and 3 or isGiver and 1 or 2))
    -- Every part hidden, to be shown by the look that uses it: for the parts made so far the hiding waits
    -- (Widgets.hideLater), so a part the look shows again was never hidden
    eachMadePart(button, ns.Widgets.hideLater)
    for _, orbiting in ipairs(button.orbiting or NO_PARTS) do
        orbiting:Hide()
    end
    button.text:SetText("")
    if button.count then
        setQuestCount(button, mark, isGiver, isReady)
    end
    if type(button.secondBang) == "table" then
        ns.Widgets.hideLater(button.secondBang)
    end
    ns.Widgets.setTextFont(button.text, ns.Widgets.getFont("GameFontNormalSmall"))
    setMarkGlow(button, mark)
    ns.Widgets.place(button.focusRing, "CENTER", button, "CENTER", 0, 0)
    button.focusRing:SetSize(size + 5, size + 5)
    button.focusRing:SetColorTexture(FOCUS_GOLD[1], FOCUS_GOLD[2], FOCUS_GOLD[3], 1)
    button.focusRing:SetShown(mark.isFocused == true and mark.kind == "objective")

    local width, height, raise, glowWidth, glowHeight = dressMark(button, mark, size, isGiver, isReady)
    -- The glow may lie on a layer scaled otherwise than its mark (both maps move it under their marks): whoever
    -- dresses the mark says by how much (button.glowScale), and the size is set once
    local glowScale = type(button.glowScale) == "number" and button.glowScale or 1
    button.glow:SetSize(glowWidth * glowScale, glowHeight * glowScale)
    eachMadePart(button, ns.Widgets.hideWaiting)
    if type(button.secondBang) == "table" then
        ns.Widgets.hideWaiting(button.secondBang)
    end
    return width, height, raise
end

---@return MapMark[] quests One mark per quest at a dungeon's entrance, the focused one first, at most six
local function getOrbitingMarks(mark)
    local unique, isShown = {}, {}
    for _, member in ipairs(mark.members or {}) do
        local key = (member.kind == "giver" and "giver" or "log") .. (member.questId or 0)
        if not isShown[key] then
            isShown[key] = true
            unique[#unique + 1] = member
        end
    end
    -- Always in the same order, whichever quest is selected, so selecting one never moves the marks round the
    -- entrance: quests in the log first, then quests to pick up, each by quest
    table.sort(unique, function(first, second)
        local firstGiver, secondGiver = first.kind == "giver", second.kind == "giver"
        if firstGiver ~= secondGiver then
            return secondGiver
        end
        return (first.questId or 0) < (second.questId or 0)
    end)
    local shown, focused = {}, nil
    for index, member in ipairs(unique) do
        if index <= MAX_ORBITING then
            shown[index] = member
        elseif member.isFocused then
            focused = member
        end
    end
    if focused then
        shown[MAX_ORBITING] = focused -- more than fit: the one selected still shows, in the last place
    end
    return shown
end

---@return number radius How far the quests' marks circle a dungeon's entrance
local function getOrbitRadius(mark)
    return mark.orbitRadius or (mark.entrancePin and ATTACHED_ORBIT_RADIUS or ORBIT_RADIUS)
end

---@return number reach From a dungeon's entrance to the outer edge of its quests' marks, a focused one's gold
---ring included
function MapMarks.getOrbitReach(mark)
    return getOrbitRadius(mark) + (MARK_SIZE + 2 + 5) * ORBIT_SCALE / 2
end

---Where round a dungeon's entrance its quests' marks go: a sixth of a turn apart clockwise from the top, as long
---as no other addon's pin covers the spot (Leatrix Maps draws its zone arrows near some entrances, over our
---marks). Covered spots are skipped; where the free side is short of room the marks move closer, 45 degrees
---apart, still clear of one another, then circle further out; only when there is no room left at all does one
---go under a pin. Sets mark.orbitRadius to the circle chosen.
---@param center { left: number, top: number } The entrance, in the mark layer's units
---@param pinRects table[] Other addons' and the game's pins, in the same units
---@return number[] angles One per quest mark, in radians clockwise from the top
function MapMarks.chooseOrbitAngles(mark, center, pinRects)
    mark.orbitRadius = nil
    local baseRadius, half = getOrbitRadius(mark), MARK_SIZE * ORBIT_SCALE / 2 + 1
    local radius = baseRadius
    local function isFree(spot)
        local angle = spot * 2 * math.pi / ORBIT_SPOTS
        local x, y = center.left + radius * math.sin(angle), center.top - radius * math.cos(angle)
        for _, rect in ipairs(pinRects) do
            if x + half > rect.left and x - half < rect.right and y + half > rect.top and y - half < rect.bottom then
                return false
            end
        end
        return true
    end
    local count = #getOrbitingMarks(mark)
    local taken = {}
    local markWidth = MARK_SIZE * ORBIT_SCALE + 1
    ---@return boolean isClear Marks this many spots apart on the circle do not touch
    local function isClearGap(gap)
        return 2 * radius * math.sin(gap * math.pi / ORBIT_SPOTS) >= markWidth
    end
    local function isApart(spot, gap)
        for _, other in ipairs(taken) do
            local distance = math.abs(spot - other) % ORBIT_SPOTS
            if math.min(distance, ORBIT_SPOTS - distance) < gap then
                return false
            end
        end
        return true
    end
    -- The whole set evenly spaced on free spots, starting as near the top as it can, as near the entrance as it can
    for _, widening in ipairs(ORBIT_WIDENINGS) do
        radius = baseRadius + widening
        for _, gap in ipairs(ORBIT_GAPS) do
            for distance = 0, isClearGap(gap) and ORBIT_SPOTS - 1 or -1 do
                local start = (distance % 2 == 0 and distance / 2 or ORBIT_SPOTS - (distance + 1) / 2) % ORBIT_SPOTS
                local spots, isAllFree = {}, count * gap <= ORBIT_SPOTS
                for index = 1, count do
                    spots[index] = (start + (index - 1) * gap) % ORBIT_SPOTS
                    isAllFree = isAllFree and isFree(spots[index])
                end
                if isAllFree then
                    table.sort(spots)
                    local angles = {}
                    for index, spot in ipairs(spots) do
                        angles[index] = spot * 2 * math.pi / ORBIT_SPOTS
                    end
                    mark.orbitRadius = widening > 0 and radius or nil
                    return angles
                end
            end
        end
    end
    radius = baseRadius
    -- No room for them all on free spots: as many as fit there, the rest wherever is left
    for _, isFreeOnly in ipairs({ true, false }) do
        for _, gap in ipairs(ORBIT_GAPS) do
            for spot = 0, ORBIT_SPOTS - 1 do
                if #taken < count and isApart(spot, gap) and (not isFreeOnly or isFree(spot)) then
                    taken[#taken + 1] = spot
                end
            end
        end
    end
    -- Crowded past even that (six quests on a short free side): the remaining marks on the free spots left
    for spot = 0, ORBIT_SPOTS - 1 do
        if #taken < count and isApart(spot, 1) then
            taken[#taken + 1] = spot
        end
    end
    table.sort(taken) -- clockwise from the top, as they are read
    local angles = {}
    for index, spot in ipairs(taken) do
        angles[index] = spot * 2 * math.pi / ORBIT_SPOTS
    end
    return angles
end

---A dungeon's mark: the game's dungeon or raid entrance icon, each of its quests' own small marks round it,
---clockwise from the top. When another addon (Leatrix Maps) or the game draws the entrance there, only the
---quests' marks are drawn, round that icon. Each small mark is the quest's own: its tooltip and click.
---@return number width, number height, number raise, number glowWidth, number glowHeight
function MapMarks.applyDungeonLook(button, mark, size)
    local radius = getOrbitRadius(mark)
    local reach = MapMarks.getOrbitReach(mark)
    button:SetSize(reach * 2, reach * 2)
    if not mark.entrancePin then
        if setGameMark(button.entranceIcon, mark.isRaid and "Raid" or "Dungeon", MEDIA .. "GlyphDungeon") then
            button.entranceIcon:SetVertexColor(1, 1, 1, 1)
            button.entranceIcon:SetSize(ENTRANCE_ICON_SIZE, ENTRANCE_ICON_SIZE)
        else
            -- No entrance icon in this client: our sign on a dark coin
            ensureCoinParts(button)
            button.edge:SetSize(size, size)
            button.edge:SetColorTexture(FOCUS_GOLD[1], FOCUS_GOLD[2], FOCUS_GOLD[3], 1)
            button.edge:Show()
            button.fill:SetColorTexture(DARK[1], DARK[2], DARK[3], 1)
            button.fill:Show()
            button.entranceIcon:SetVertexColor(0.91, 0.86, 0.75, 1)
            button.entranceIcon:SetSize(size * 0.62, size * 0.62)
        end
        button.entranceIcon:Show()
    end
    for index, member in ipairs(getOrbitingMarks(mark)) do
        local orbiting = button.orbiting[index]
        if not orbiting then
            orbiting = MapMarks.createMarkButton(button)
            button.orbiting[index] = orbiting
            button.omqParts = nil -- (more parts: the map lists them again, Draw's restHiddenParts)
        end
        -- The quest highlighted (selected, or hovered in the list) stands out from the dungeon's others: full size,
        -- with its gold ring and glow, over them; the rest small round the entrance
        local scale = member.isFocused and 1 or ORBIT_SCALE
        orbiting:SetScale(scale)
        MapMarks.applyMarkLook(orbiting, member, (button:GetFrameLevel() or 1) + (member.isFocused and 4 or 1))
        orbiting.glow:SetShown(member.isFocused == true)
        local angle = mark.orbitAngles and mark.orbitAngles[index] or (index - 1) * ORBIT_STEP
        ns.Widgets.place(
            orbiting,
            "CENTER",
            button,
            "CENTER",
            radius * math.sin(angle) / scale,
            radius * math.cos(angle) / scale
        )
        orbiting:Show()
    end
    -- Only the entrance in the middle answers the mouse: the quests round it have their own buttons, and what lies
    -- between them (another addon's zone arrow beside the entrance, the map itself) stays reachable
    if button.SetHitRectInsets then
        local iconRadius = mark.entrancePin and 11 or ENTRANCE_ICON_SIZE / 2 -- the drawn part of Leatrix's icon (32 across) or ours
        local inset = math.max(0, reach - iconRadius)
        button:SetHitRectInsets(inset, inset, inset, inset)
    end
    return reach * 2, reach * 2, 0, ENTRANCE_ICON_SIZE * 1.9, ENTRANCE_ICON_SIZE * 1.9 -- (and its glow's size)
end

-- Shared with the other parts of the window
Look.BANG_SIZE = BANG_SIZE
Look.HALO_SIZE = HALO_SIZE
Look.ITEM_MARK_REACH = ITEM_MARK_REACH
Look.MARK_GAP = MARK_GAP
Look.MARK_SIZE = MARK_SIZE
Look.MEMBER_CLEAR = MEMBER_CLEAR
Look.OVERVIEW_MAP_TYPE = OVERVIEW_MAP_TYPE
Look.PARTY_SECONDS = PARTY_SECONDS
Look.PLAYER_CLEAR = PLAYER_CLEAR
Look.acquire = acquire
Look.createPools = createPools
