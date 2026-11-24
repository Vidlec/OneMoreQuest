-- Tests: the world map's and the minimap's marks, spawn squares and icons, and quest areas.

test(
    "a spawn's marker is dressed in the kind chosen: a glyph on a glow or a plate, the game's art, a square",
    function()
        local ns = createAddon()
        local function fakeTexture()
            local texture = { calls = {} }
            return setmetatable(texture, {
                __index = function(self, name)
                    return function(_, ...)
                        self.calls[name] = { ... }
                    end
                end,
            })
        end
        local savedTexture = C_Texture
        C_Texture = {
            GetAtlasInfo = function(atlas)
                return { width = 32, height = 32 }
            end,
        }
        local color = { 0.2, 0.8, 0.4 }
        local function dress(kind, glyph, isStrong)
            local under, over = fakeTexture(), fakeTexture()
            local hasUnder = ns.MapMarks.dressSpawnMarker(under, over, kind, glyph, color, isStrong, 11, 17)
            return under.calls, over.calls, hasUnder
        end
        -- What to do there, on a glow in the quest's colour
        local under, over, hasUnder = dress("glyph", "kill", true)
        expectEqual(hasUnder, true, "a glyph has its glow under it")
        expectEqual(
            under.SetVertexColor[1] == 0.2 and under.SetVertexColor[2] == 0.8 and under.SetVertexColor[4] == 1,
            true,
            "the glow in the quest's colour, at full strength in focus"
        )
        expectEqual(
            tostring(over.SetTexture[1]):find("IconKill", 1, true) ~= nil and over.SetSize[1] == 11,
            true,
            "the sword over it, at its size"
        )
        expectEqual(under.SetSize[1], 17, "the glow at its own size")
        -- A quest not in focus: fainter
        local fadedUnder, fadedOver = dress("glyph", "kill", false)
        expectEqual(
            fadedOver.SetVertexColor[4] < 1 and fadedUnder.SetVertexColor[4] < 1,
            true,
            "out of focus, glyph and glow are fainter"
        )
        -- On a plate edged in the quest's colour: the plate wider than the glyph, the glyph a little smaller
        under, over, hasUnder = dress("plate", "loot", true)
        expectEqual(
            tostring(under.SetTexture[1]):find("Plate", 1, true) ~= nil and under.SetVertexColor[2] == 0.8,
            true,
            "the plate takes the quest's colour"
        )
        expectEqual(
            under.SetSize[1] > 11
                and over.SetSize[1] < 11
                and tostring(over.SetTexture[1]):find("IconLoot", 1, true) ~= nil,
            true,
            "the sack on it, smaller than the plate"
        )
        -- The game's own art: its skull for a kill, its chest for loot; a talk has none and keeps the addon's glyph
        under, over, hasUnder = dress("game", "kill", true)
        expectEqual(over.SetAtlas and over.SetAtlas[1], "DungeonSkull", "a kill is the game's skull")
        expectEqual(hasUnder, true, "on the glow")
        under, over = dress("game", "loot", true)
        expectEqual(over.SetAtlas and over.SetAtlas[1], "VignetteLoot", "loot is the game's chest")
        under, over = dress("game", "talk", true)
        expectEqual(
            over.SetAtlas == nil and tostring(over.SetTexture[1]):find("IconTalk", 1, true) ~= nil,
            true,
            "a talk keeps the speech bubble"
        )
        -- A client without that art: the glyph instead
        C_Texture = {
            GetAtlasInfo = function()
                return nil
            end,
        }
        under, over = dress("game", "kill", true)
        expectEqual(
            over.SetAtlas == nil and tostring(over.SetTexture[1]):find("IconKill", 1, true) ~= nil,
            true,
            "no such art in the client: the sword"
        )
        -- A small square in the quest's colour with a dark edge, clear of whatever tint the textures had
        under, over, hasUnder = dress("square", "kill", true)
        expectEqual(
            over.SetColorTexture[1] == 0.2 and over.SetColorTexture[2] == 0.8 and over.SetSize[1] < 11,
            true,
            "a small square in the quest's colour"
        )
        expectEqual(
            under.SetColorTexture[1] < 0.2 and under.SetSize[1] == over.SetSize[1] + 2,
            true,
            "on a dark edge a pixel wider each side"
        )
        expectEqual(
            over.SetVertexColor[1] == 1 and under.SetVertexColor[1] == 1,
            true,
            "a tint left from another kind is cleared"
        )
        -- The glow switched off: the glyph alone
        ns.settings.shouldGlowSpawnMarkers = false
        under, over, hasUnder = dress("glyph", "kill", true)
        expectEqual(hasUnder, false, "the glow off: nothing under the glyph")
        ns.settings.shouldGlowSpawnMarkers = true
        -- The other quests' markers: fainter, as strong, or not there, as chosen; the quest in focus always in full
        ns.settings.otherSpawnMarkers = "faded"
        local isShown, isStrong = ns.MapMarks.getSpawnMarkerStrength(false)
        expectEqual(isShown == true and isStrong == false, true, "fainter by default")
        ns.settings.otherSpawnMarkers = "full"
        isShown, isStrong = ns.MapMarks.getSpawnMarkerStrength(false)
        expectEqual(isShown == true and isStrong == true, true, "as strong as the focused quest's")
        ns.settings.otherSpawnMarkers = "hidden"
        isShown = ns.MapMarks.getSpawnMarkerStrength(false)
        expectEqual(isShown, false, "hidden")
        isShown, isStrong = ns.MapMarks.getSpawnMarkerStrength(true)
        expectEqual(isShown == true and isStrong == true, true, "the quest in focus is never hidden")
        -- How wide each kind stands, for keeping them apart: a plate wider than its glyph, a square much smaller
        expectEqual(
            ns.MapMarks.getSpawnMarkerFootprint("plate", 11) > 11
                and ns.MapMarks.getSpawnMarkerFootprint("square", 11) < 8
                and ns.MapMarks.getSpawnMarkerFootprint("glyph", 11) == 11,
            true,
            "each kind's footprint"
        )
        C_Texture = savedTexture
    end
)

test("the areas' two looks: a light wash, and bold shapes with a thicker edge in focus", function()
    local ns = createAddon()
    ns.settings.areaStyle = "filled"
    local light = ns.MapMarks.getAreaLook()
    local lightFill, lightEdge = light.focusedFillAlpha, light.focusedEdgePixels
    expectEqual(
        light.style == "filled" and light.focusedEdgePixels == light.edgePixels,
        true,
        "the light look: one edge width"
    )
    ns.settings.areaStyle = "blob"
    local bold = ns.MapMarks.getAreaLook()
    expectEqual(bold.style, "blob", "the shapes")
    expectEqual(bold.focusedFillAlpha > lightFill and bold.fillAlpha > 0.1, true, "filled more plainly")
    expectEqual(
        bold.focusedEdgePixels > lightEdge and bold.focusedEdgePixels > bold.edgePixels,
        true,
        "the quest in focus edged thicker"
    )
    ns.settings.areaStyle = "something saved by another version"
    expectEqual(ns.MapMarks.getAreaStyle(), "filled", "an unknown look reads as the light one")
    ns.settings.spawnMarker = nil
    expectEqual(ns.MapMarks.getSpawnMarker(), "glyph", "and no marker saved as the glyph")
    ns.settings.areaStyle, ns.settings.spawnMarker = "none", "none"
    expectEqual(ns.MapMarks.hasQuestColours(), false, "neither areas nor markers: nothing in the quests' colours")
    ns.settings.spawnMarker = "square"
    expectEqual(ns.MapMarks.hasQuestColours(), true, "markers alone carry them")
end)

test(
    "the areas' fill and outline: each switched on or off and set in strength, the quest in focus still the strongest",
    function()
        local ns = createAddon()
        ns.settings.areaStyle = "blob"
        local look = ns.MapMarks.getAreaLook()
        local fill, focusedFill, edge, rim, version =
            look.fillAlpha, look.focusedFillAlpha, look.edgeAlpha, look.rimAlpha, look.version
        expectEqual(
            ns.MapMarks.getAreaLook() == look and look.version == version,
            true,
            "asked again with nothing changed: the same table, as it was"
        )
        ns.settings.areaFillStrength = 0.5
        look = ns.MapMarks.getAreaLook()
        expectEqual(
            look.version ~= version and math.abs(look.fillAlpha - fill / 2) < 1e-9 and look.edgeAlpha == edge,
            true,
            "half the fill, the outline as it was"
        )
        ns.settings.areaFillStrength = 2
        look = ns.MapMarks.getAreaLook()
        expectEqual(
            look.focusedFillAlpha <= 1
                and look.focusedFillAlpha > look.fillAlpha
                and look.focusedFillAlpha > focusedFill,
            true,
            "stronger, never past solid, focus above the rest"
        )
        ns.settings.areaFillStrength = 40
        expectEqual(
            ns.MapMarks.getAreaLook().fillAlpha,
            math.min(1, fill * 2),
            "a strength saved out of range reads as the nearest end"
        )
        ns.settings.areaFillStrength, ns.settings.areaOutlineStrength = 1, 0.5
        look = ns.MapMarks.getAreaLook()
        expectEqual(
            math.abs(look.rimAlpha - rim / 2) < 1e-9 and look.trailAlpha == edge,
            true,
            "the outline and its dark rim together; walks keep the look's own"
        )
        ns.settings.shouldFillAreas = false
        look = ns.MapMarks.getAreaLook()
        expectEqual(
            look.hasFill == false and look.hasEdges and look.fillAlpha == 0 and ns.MapMarks.hasAreas(),
            true,
            "fill off: the outlines alone"
        )
        ns.settings.shouldFillAreas, ns.settings.shouldOutlineAreas = true, false
        look = ns.MapMarks.getAreaLook()
        expectEqual(
            look.hasFill and look.hasEdges == false and look.edgeAlpha == 0 and ns.MapMarks.hasAreas(),
            true,
            "outline off: the fill alone"
        )
        ns.settings.shouldFillAreas = false
        expectEqual(ns.MapMarks.hasAreas(), false, "both off: no areas")
        ns.settings.spawnMarker = "none"
        expectEqual(ns.MapMarks.hasQuestColours(), false, "nor anything else in the quests' colours")
    end
)

test(
    "events run on their days: fixed ones, the Lunar Festival by year, Noblegarden on Easter, the Darkmoon Faire's week",
    function()
        local ns = createAddon()
        local savedDate, savedTime, savedCalendar = date, time, C_DateAndTime
        date, time = os.date, os.time
        local now = { year = 2026, month = 12, monthDay = 20, hour = 12, minute = 0 }
        C_DateAndTime = {
            GetCurrentCalendarTime = function()
                return now
            end,
        }
        local running = ns.Events.composeByDates(now)
        expectEqual(
            running.winterVeil == true and not running.hallowsEnd,
            true,
            "Winter Veil in December, nothing else of the year's"
        )
        running = ns.Events.composeByDates({ year = 2027, month = 1, monthDay = 1, hour = 12, minute = 0 })
        expectEqual(running.winterVeil, true, "across the new year")
        expectEqual(
            ns.Events.composeByDates({ year = 2026, month = 2, monthDay = 20, hour = 12, minute = 0 }).lunarFestival,
            true,
            "the Lunar Festival of 2026, late that year"
        )
        local month, day = ns.Events.getEaster(2027)
        expectEqual(month .. "/" .. day, "3/28", "Easter Sunday 2027")
        expectEqual(
            ns.Events.composeByDates({ year = 2027, month = 3, monthDay = 28, hour = 9, minute = 0 }).noblegarden,
            true,
            "Noblegarden on it"
        )
        -- November 2026 starts on a Sunday: the faire opens on Monday the 9th at 4:00, for a week, in Elwynn Forest
        expectEqual(ns.Events.getFaireStartDay(2026, 11), 9, "the faire's first day")
        expectEqual(
            ns.Events.composeByDates({ year = 2026, month = 11, monthDay = 9, hour = 3, minute = 0 }).darkmoonFaire,
            nil,
            "not before 4:00"
        )
        expectEqual(
            ns.Events.composeByDates({ year = 2026, month = 11, monthDay = 12, hour = 3, minute = 0 }).darkmoonFaire,
            true,
            "open in its week"
        )
        expectEqual(
            ns.Events.composeByDates({ year = 2026, month = 11, monthDay = 20, hour = 3, minute = 0 }).darkmoonFaire,
            nil,
            "shut after it"
        )
        -- A quest is offered while its event runs, and one with days of its own only on those
        ns.Events.update()
        expectEqual(
            ns.Events.isActive("winterVeil") and ns.Events.isEventQuest(6961) and ns.Events.isQuestOffered(6961),
            true,
            "a Winter Veil quest in December"
        )
        expectEqual(ns.Events.isQuestOffered(8744), false, "one from Christmas on: not yet on the 20th")
        now = { year = 2026, month = 12, monthDay = 26, hour = 12, minute = 0 }
        expectEqual(ns.Events.isQuestOffered(8744), true, "on the 26th")
        local key = ns.Events.getChangeKey()
        now = { year = 2026, month = 7, monthDay = 1, hour = 12, minute = 0 }
        ns.Events.update()
        expectEqual(
            ns.Events.getChangeKey() ~= key and not ns.Events.isQuestOffered(6961) and ns.Events.isActive("midsummer"),
            true,
            "summer: Midsummer runs, Winter Veil's quests are gone"
        )
        date, time, C_DateAndTime = savedDate, savedTime, savedCalendar
    end
)

test(
    "a quest in the log of a kind shows its coin as set: as now, in the kind's colour, with the kind's icon, or both",
    function()
        local ns = createAddon()
        C_Texture = {
            GetAtlasInfo = function(name)
                return { name = name }
            end,
        }
        local button = ns.MapMarks.createMarkButton(UIParent)
        local mark =
            { kind = "objective", markKind = "dungeon", glyph = "kill", progress = 0, isFocused = false, lines = {} }
        ns.MapMarks.applyMarkLook(button, mark, 1) -- (the coin's parts are made the first time)
        local icon, fill = button.objectiveIcon, button.fill
        rawset(icon, "SetAtlas", function(self, name)
            rawset(self, "shown", "atlas " .. name)
        end)
        rawset(icon, "SetTexture", function(self, file)
            rawset(self, "shown", "file " .. tostring(file):match("[^\\]+$"))
        end)
        rawset(fill, "SetColorTexture", function(self, red, green, blue)
            rawset(self, "colour", string.format("%.2f %.2f %.2f", red, green, blue))
        end)
        local function dress(style)
            ns.settings.questMarkDungeon = style
            ns.MapMarks.applyMarkLook(button, mark, 1)
            return rawget(icon, "shown") .. " / " .. rawget(fill, "colour")
        end
        ns.settings.questIconDungeon = "purple"
        expectEqual(ns.settings.questMarkRaid, "plain", "as it starts: every kind's coin as now")
        expectEqual(dress("plain"), "file IconKill / 0.87 0.64 0.13", "as now: what to do, on the gold coin")
        expectEqual(dress("colour"), "file IconKill / 0.69 0.48 1.00", "its colour: the coin in the dungeons' purple")
        expectEqual(
            dress("icon"),
            "atlas questlog-questtypeicon-dungeon / 0.87 0.64 0.13",
            "its icon: the game's dungeon icon on the gold coin"
        )
        expectEqual(dress("both"), "atlas questlog-questtypeicon-dungeon / 0.69 0.48 1.00", "both")
        expectEqual(dress("plain"), "file IconKill / 0.87 0.64 0.13", "and back")
        local kind, style = ns.MapMarks.getMarkStyle({ kind = "objective", questId = 201 })
        expectEqual(tostring(kind) .. " " .. style, "nil plain", "a quest of no such kind keeps the plain coin")
    end
)

test(
    "each kind of quest's icon takes its colour: the game's art where it has one, its gold one tinted otherwise",
    function()
        local ns = createAddon()
        C_Texture = {
            GetAtlasInfo = function(name)
                return { name = name }
            end,
        }
        local function createTexture()
            local texture = {}
            function texture:SetAtlas(name)
                self.atlas = name
            end
            function texture:SetTexCoord() end
            function texture:SetTexture(file)
                self.file = file
            end
            function texture:SetDesaturated(isGrey)
                self.isGrey = isGrey
            end
            function texture:SetVertexColor(red, green, blue)
                self.tint = string.format("%.2f %.2f %.2f", red, green, blue)
            end
            return texture
        end
        local texture = createTexture()
        ns.MapMarks.dressQuestIcon(texture, "blue", false)
        expectEqual(
            texture.atlas .. " " .. tostring(texture.isGrey) .. " " .. texture.tint,
            "QuestDaily false 1.00 1.00 1.00",
            'blue: the game\'s own daily "!"'
        )
        ns.MapMarks.dressQuestIcon(texture, "green", true)
        expectEqual(
            texture.atlas .. " " .. tostring(texture.isGrey) .. " " .. texture.tint,
            "QuestTurnin true 0.42 1.00 0.42",
            'green: the gold "?" greyed and tinted'
        )
        ns.MapMarks.dressQuestIcon(texture, "green", true, true)
        expectEqual(
            tostring(texture.isGrey) .. " " .. texture.tint,
            "true 1.00 1.00 1.00",
            "a quest not ready yet: grey whatever its colour"
        )
        -- The kinds: the first that fits, a giver of several only when all are of it
        expectEqual(
            ns.MapMarks.getIconKind({ kind = "giver", questId = 6961, isLowLevel = true }),
            "event",
            "an event's quest, low level too: the event's"
        )
        expectEqual(
            ns.MapMarks.getIconKind({ kind = "giver", questIds = { 6961, 6962 } }),
            "event",
            "a giver of two event quests"
        )
        expectEqual(
            ns.MapMarks.getIconKind({ kind = "giver", questIds = { 6961, 201 } }),
            "normal",
            "a giver of an event quest and another"
        )
        expectEqual(
            ns.MapMarks.getIconKind({ kind = "giver", questId = 201, isLowLevel = true }),
            "lowLevel",
            "low level"
        )
        expectEqual(
            ns.MapMarks.getIconKind({ kind = "turnIn", questId = 201, isLowLevel = true }, true),
            "normal",
            'a "?" is never low level'
        )
        expectEqual(
            ns.MapMarks.getIconColour("event") .. " " .. ns.MapMarks.getIconColour("raid"),
            "green orange",
            "as they start: event green, raid orange"
        )
        ns.settings.questIconEvent = "purple"
        expectEqual(ns.MapMarks.getIconColour("event"), "purple", "as chosen")
        ns.settings.questIconEvent = "something else"
        expectEqual(ns.MapMarks.getIconColour("event"), "green", "an unknown colour reads as the first one")
        -- The lists ask by quest, with no mark made: an event's "!" green, an ordinary low-level one grey, its "?" gold
        ns.settings.questIconEvent = "green"
        expectEqual(
            ns.MapMarks.getQuestIconColour(6961)
                .. " "
                .. ns.MapMarks.getQuestIconColour(201, true)
                .. " "
                .. ns.MapMarks.getQuestIconColour(201, true, true),
            "green grey gold",
            "the lists' icons by quest"
        )
        expectEqual(ns.MapMarks.formatQuestSign(6961), "|cff6bff6b!|r", "a tooltip's \"!\" in the event's green")
        -- Each kind's colour, as the game has them
        for kind, setting in pairs(ns.MapMarks.ICON_SETTINGS) do
            ns.settings[setting] = ns.MapMarks.GAME_ICON_COLOURS[kind]
        end
        expectEqual(
            ns.MapMarks.getIconColour("event")
                .. ns.MapMarks.getIconColour("repeatable")
                .. ns.MapMarks.getIconColour("lowLevel"),
            "goldbluegrey",
            "the game's: gold, blue, grey"
        )
        C_Texture = nil
    end
)

test("quest tooltips show the experience on the title line, and the details while Shift is held", function()
    local ns, state = createAddon()
    LibQuestieDB.Support.Get = (function(original)
        return function(name)
            if name == "QuestXP" then
                return { db = { [201] = { 13, 2850 } } }
            end
            return original(name)
        end
    end)(LibQuestieDB.Support.Get)
    state.playerLevel = 13
    -- A tooltip that keeps its lines
    local function createTooltip()
        local tooltip = { lines = {}, isShown = false }
        function tooltip:AddLine(text)
            self.lines[#self.lines + 1] = { text = text }
        end
        function tooltip:AddDoubleLine(left, right)
            self.lines[#self.lines + 1] = { text = left, right = right }
        end
        function tooltip:SetOwner(owner)
            self.owner, self.lines = owner, {}
        end
        function tooltip:GetOwner()
            return self.owner
        end
        function tooltip:Show()
            self.isShown = true
        end
        function tooltip:IsShown()
            return self.isShown
        end
        return tooltip
    end
    local function hasText(tooltip, wanted)
        for _, line in ipairs(tooltip.lines) do
            if tostring(line.text):find(wanted, 1, true) or tostring(line.right or ""):find(wanted, 1, true) then
                return true
            end
        end
        return false
    end
    -- The title with its experience at the right end
    local tooltip = createTooltip()
    ns.QuestTooltip.addTitle(tooltip, "[13] Bandit Trouble", 201)
    expectEqual(
        tooltip.lines[1].text .. " | " .. tostring(tooltip.lines[1].right),
        "[13] Bandit Trouble | 2,850 XP",
        "the experience on the title line"
    )
    -- Outlevelled: lowered as the game lowers it; at the top level: none
    state.playerLevel = 21
    tooltip = createTooltip()
    ns.QuestTooltip.addTitle(tooltip, "[13] Bandit Trouble", 201)
    expectEqual(tooltip.lines[1].right, "1,150 XP", "lowered for a character above the quest")
    local savedMax = GetMaxPlayerLevel
    GetMaxPlayerLevel = function()
        return 21
    end
    tooltip = createTooltip()
    ns.QuestTooltip.addTitle(tooltip, "[13] Bandit Trouble", 201)
    expectEqual(tooltip.lines[1].right, nil, "at the top level no experience is shown")
    GetMaxPlayerLevel = savedMax
    state.playerLevel = 13
    -- Without Shift: no details, a grey line saying Shift shows them
    tooltip = createTooltip()
    expectEqual(ns.QuestTooltip.addDetails(tooltip, 201), false, "no details without Shift")
    ns.QuestTooltip.addHint(tooltip)
    expectEqual(hasText(tooltip, "Hold Shift for details"), true, "the hint says Shift shows more")
    -- With Shift: what it asks, the rewards, where it is handed in; for a quest not taken, the level it needs
    local savedShift = IsShiftKeyDown
    IsShiftKeyDown = function()
        return true
    end
    tooltip = createTooltip()
    expectEqual(ns.QuestTooltip.addDetails(tooltip, 201), true, "details with Shift")
    expectEqual(hasText(tooltip, "Rewards: 2,850 XP"), true, "the rewards")
    expectEqual(hasText(tooltip, "Turn in to Envoy Maldrek"), true, "where it is handed in")
    ns.QuestTooltip.addHint(tooltip)
    expectEqual(hasText(tooltip, "Hold Shift"), false, "no hint while Shift is held")
    -- Shift going down or up fills the tooltip shown again, once its owner still has it
    local owner, fills = {}, 0
    tooltip = createTooltip()
    local function fill(argument)
        expectEqual(argument, "the row", "filled again with what it was given")
        fills = fills + 1
        tooltip:SetOwner(owner)
        tooltip:Show()
    end
    fill("the row")
    ns.QuestTooltip.watch(tooltip, owner, fill, "the row")
    ns.QuestTooltip.handleModifierChange("LSHIFT", 1)
    expectEqual(fills, 2, "Shift down: filled again")
    ns.QuestTooltip.handleModifierChange("LCTRL", 1)
    expectEqual(fills, 2, "another key: left as it is")
    tooltip:SetOwner({})
    ns.QuestTooltip.handleModifierChange("LSHIFT", 0)
    expectEqual(fills, 2, "someone else's tooltip now: left alone")
    IsShiftKeyDown = savedShift
end)

test("a quest with nothing to do but wait points at its NPC, not at its dungeon", function()
    local ns, state = createAddon()
    setQuest(state, 605, false, {})
    local entry = ns.Model.compose().groups[1].entries[1]
    expectEqual(entry.zoneId, UNDERCITY, "zone of the NPC")
    expectEqual(entry.eventText, "Wait for the envoy to finish.", "what to do")
    expectEqual(#entry.places > 0, true, "the NPC is marked")
    local marks = getMarks(ns.MapMarks.compose(1458), "objective")
    expectEqual(#marks, 1, "one mark at the NPC")
    expectEqual(marks[1].lines[2], "Wait for the envoy to finish.", "the mark says what to do")
    ns.Tracker.create()
    ns.Tracker.refresh()
    ns.Log.create()
    ns.Log.toggle()
    ns.Log.selectQuest(605)
    ns.Log.refresh()
end)

test(
    "a tracked quest out of focus brings its spawn points, to draw fainter; the focused quest's are its own",
    function()
        local ns, state = createAddon()
        setQuest(state, 201, false, { killObjective(5, 12) })
        ns.Tracker.create()
        ns.Focus.set(nil)
        local marks = getMarks(ns.MapMarks.compose(1420), "objective")
        expectEqual(#marks, 1, "one mark while out of focus")
        expectEqual(marks[1].fadedPoints ~= nil and #marks[1].fadedPoints, 3, "with every spawn point, to draw faded")
        ns.Focus.set(201)
        for _, mark in ipairs(getMarks(ns.MapMarks.compose(1420), "objective")) do
            expectEqual(mark.fadedPoints, nil, "in focus its points are drawn at full strength instead")
        end
        ns.MapPins.create()
        ns.MapPins.refresh() -- draws both kinds of squares
    end
)

test("the quest in focus gets one mark per area, with shading and a label", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    local marks = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#marks, 2, "areas: two spawns close together, one far off")
    expectEqual(marks[1].isFocused, true, "in focus")
    expectEqual(marks[1].labels[1].glyph, "kill", "says what to do")
    expectEqual(marks[1].labels[1].text, "Roadside Bandit slain 5/12", "label on the largest area")
    expectEqual(math.floor(marks[1].progress * 100), 41, "progress of the quest")
    expectEqual(marks[1].number, 1, "its number")
    expectEqual(#marks[2].labels, 0, "no second label")
    expectEqual(#marks[1].areas, 1, "shaded area")
    expectEqual(#marks[1].points, 2, "spawn points of the largest area")
    local elsewhere = ns.MapMarks.compose(1458)
    expectEqual(
        #elsewhere == 1 and elsewhere[1].isPending,
        true,
        "on another zone's map only where it will be handed in, in grey"
    )
end)

test("a quest out of focus is a single numbered mark", function()
    local ns, state = createAddon()
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(301)
    local marks = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#marks, 1, "one mark for the quest out of focus")
    expectEqual(marks[1].questId, 201, "quest")
    expectEqual(marks[1].isFocused, false, "out of focus")
    expectEqual(marks[1].number, 2, "its number among the tracked quests")
    expectEqual(marks[1].areas, nil, "no shading")
end)

test("two objectives of the quest in focus in one spot share a mark", function()
    local ns, state = createAddon()
    -- Both objectives of this quest are the bandits, so their areas coincide
    state.questLog[201] = { isComplete = false, objectives = { killObjective(5, 12), killObjective(0, 3) } }
    state.watchedQuestIds[1] = 201
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 201 and field == "objectives" then
                return { { { 5001 }, { 5001 } } }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Tracker.create()
    ns.Focus.set(201)
    local marks = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#marks, 2, "still two areas, not four marks")
    expectEqual(#marks[1].labels, 2, "both labels on the shared mark")
end)

test("turn-ins and quest givers are their own kinds of mark", function()
    local ns, state = createAddon()
    setQuest(state, 201, true, { killObjective(12, 12) })
    local marks = ns.MapMarks.compose(1458)
    expectEqual(#marks, 1, "marks in Undercity")
    expectEqual(marks[1].kind, "turnIn", "kind")
    expectEqual(marks[1].number, 1, "the turn-in carries the quest's number")
    expectEqual(marks[1].progress, 1, "a turn-in is a full ring")
    ns.Availability.prepare()
    local givers, itemCount = {}, 0
    for _, mark in ipairs(getMarks(ns.MapMarks.compose(1420), "giver")) do
        if mark.itemIcon then
            itemCount = itemCount + 1 -- a quest from a dropped item keeps its own mark, the item's picture
        else
            givers[#givers + 1] = mark
        end
    end
    expectEqual(itemCount > 0, true, "the dropped item's quest is marked on its own")
    expectEqual(#givers, 1, "one giver: one mark for all the quests they offer")
    local questCount = givers[1] and givers[1].questIds and #givers[1].questIds or 0
    expectEqual(questCount > 1, true, "it counts them")
    expectEqual(
        givers[1] and givers[1].lines[1],
        "Deathguard Morris",
        "its tooltip names the giver, then lists each quest"
    )
    expectEqual(givers[1] and #givers[1].lines, questCount + 1, "a line for each quest")
    ns.settings.shouldShowAvailableOnMap = false
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "giver"), 0, "givers switched off")
end)

test('quests handed in to one NPC share a "?", the ready ones apart from those not ready yet', function()
    local ns = createAddon()
    local function turnIn(questId, isPending, isFocused)
        return {
            kind = "turnIn",
            questId = questId,
            x = 0.5,
            y = 0.5,
            isPending = isPending,
            isFocused = isFocused,
            lines = { "[10] Quest " .. questId, "Turn in to Deathguard Morris" },
        }
    end
    -- 102, 201, 103 and 301 are handed in to one NPC (9002); 101 to another (9001) standing on the same spot
    local marks = ns.MapMarks.mergeTurnIns({
        turnIn(101),
        turnIn(102, false, true),
        turnIn(201),
        turnIn(103, true),
        turnIn(301, true),
        { kind = "objective", questId = 601, x = 0.5, y = 0.5, lines = {} },
    })
    expectEqual(#marks, 4, 'the other NPC\'s "?", one ready "?", one grey "?", and the objective as it was')
    expectEqual(
        marks[1].questId == 101 and marks[1].questIds == nil,
        true,
        'another NPC on the same spot keeps its own "?"'
    )
    local ready = marks[2]
    expectEqual(#ready.questIds, 2, "the two ready quests of one NPC share it")
    expectEqual(ready.questId, 102, "the followed one goes first: a click opens it")
    expectEqual(ready.isFocused, true, "and the shared mark stands out as the followed quest's")
    expectEqual(ready.lines[1], "Turn in to Deathguard Morris", "its tooltip says who takes them, then lists them")
    expectEqual(marks[3].isPending and #marks[3].questIds, 2, "the two not ready yet share the grey one")
    expectEqual(marks[4].kind, "objective", "other marks are left alone")
end)

test('an NPC who takes quests in and gives new ones has one mark: the "?" when one is ready, else the "!"', function()
    local ns = createAddon()
    local function giver()
        return {
            kind = "giver",
            questId = 501,
            questIds = { 501, 502 },
            x = 0.5,
            y = 0.5,
            lines = { "Deathguard Morris", "[10] Fresh Start", "[10] After Fresh Start" },
        }
    end
    -- The giver (9003) takes 503 and 504 in too
    local ready = {
        kind = "turnIn",
        questId = 503,
        x = 0.5,
        y = 0.5,
        lines = { "[13] High Road", "Turn in to Deathguard Morris" },
    }
    local elsewhere = {
        kind = "turnIn",
        questId = 101,
        x = 0.5,
        y = 0.5,
        lines = { "[12] Urgent Dispatch", "Turn in to someone else" },
    }
    expectEqual(
        #ns.MapMarks.joinGiversAndTurnIns({ giver(), elsewhere }),
        2,
        'another NPC\'s "?" on the same spot: two marks'
    )
    local marks = ns.MapMarks.joinGiversAndTurnIns({ giver(), ready })
    expectEqual(#marks, 1, "one mark")
    expectEqual(marks[1].kind, "turnIn", 'the "?": a quest is ready there')
    expectEqual(marks[1].offerCount, 2, 'with the "!" badge for the two offered')
    expectEqual(marks[1].lines[#marks[1].lines], "[10] After Fresh Start", "its tooltip lists the offers too")
    local pending = {
        kind = "turnIn",
        isPending = true,
        questId = 504,
        x = 0.5,
        y = 0.5,
        lines = { "[12] The Warchief's Reply", "Turn in to Deathguard Morris" },
    }
    marks = ns.MapMarks.joinGiversAndTurnIns({ giver(), pending })
    expectEqual(#marks, 1, "one mark")
    expectEqual(marks[1].kind, "giver", 'the "!": nothing is ready there')
    expectEqual(
        marks[1].lines[#marks[1].lines],
        "[12] The Warchief's Reply",
        "its tooltip says what will be handed in later"
    )
    local selected = giver()
    selected.isFocused = true
    expectEqual(
        #ns.MapMarks.joinGiversAndTurnIns({ selected, ready }),
        2,
        'the quest selected to pick up keeps its own "!"'
    )
end)

test("with laying out off, every mark and spawn stays on its own spot, overlapping or not", function()
    local ns = createAddon()
    expectEqual(ns.MapMarks.IS_LAYOUT_ON, false, "off for now")
    local items = {
        { mark = { kind = "objective" }, width = 24, height = 24, spotLeft = 100, spotTop = 100 },
        { mark = { kind = "objective" }, width = 24, height = 24, spotLeft = 102, spotTop = 101 },
    }
    ns.MapMarks.arrangeMarks(items, {}, { left = 0, top = 0, right = 1000, bottom = 1000 })
    expectEqual(
        items[2].left == 102 and items[2].top == 101,
        true,
        "the second mark keeps its spot, on top of the first"
    )
    local icons = ns.MapMarks.placeIcons(
        { { color = { 1, 1, 1 }, points = { { x = 10.3, y = 20.7 }, { x = 10.4, y = 20.8 } } } },
        { { left = 0, right = 50, top = 0, bottom = 50 } }
    )
    expectEqual(
        #icons == 2 and icons[1].x == 10.3 and icons[2].y == 20.8,
        true,
        "an icon on every spawn, on its spot, under a mark or not"
    )
end)

test(
    "a quest's mark sits on one of its real spawns, the one nearest its area's middle, the same on every map",
    function()
        local ns, state = createAddon()
        setQuest(state, 201, false, { killObjective(5, 12) }) -- bandits at 60,50 and 80,50 in Tirisfal, and 61,52 in Brill
        ns.Tracker.create()
        local marks = getMarks(ns.MapMarks.compose(1420), "objective")
        expectEqual(#marks, 1, "one mark: the quest out of focus")
        local isOnSpawn = false
        for _, spawn in ipairs({ { 0.60, 0.50 }, { 0.80, 0.50 }, { 0.61, 0.52 } }) do
            isOnSpawn = isOnSpawn or (math.abs(marks[1].x - spawn[1]) < 1e-6 and math.abs(marks[1].y - spawn[2]) < 1e-6)
        end
        expectEqual(isOnSpawn, true, "on a spawn, not an empty middle between them")
        local again = getMarks(ns.MapMarks.compose(1420), "objective")
        expectEqual(again[1].x == marks[1].x and again[1].y == marks[1].y, true, "drawn again, on the very same spot")
    end
)

test("spawns are thinned in the world in nested steps: zooming out only takes some away, none moves", function()
    local ns = createAddon()
    -- A row of spawns 10 yards apart in Tirisfal (its map is 1000 yards across): 0 to 300 yards
    local points = {}
    for index = 0, 30 do
        points[#points + 1] = { x = 0.2 + index * 0.01, y = 0.5, place = { zoneId = 85, x = 20 + index, y = 50 } }
    end
    local all = ns.MapMarks.thinPoints(points, 0)
    expectEqual(#all, #points, "the finest step: every spawn")
    local previous = all
    for _, spacing in ipairs({ 25, 50, 100, 200, 400 }) do
        local kept = ns.MapMarks.thinPoints(points, spacing)
        local wasKept = {}
        for _, point in ipairs(previous) do
            wasKept[point] = true
        end
        local isNested = true
        for _, point in ipairs(kept) do
            isNested = isNested and wasKept[point] == true
        end
        expectEqual(isNested, true, spacing .. " yards: only spawns the finer step showed too, on their own spots")
        expectEqual(#kept <= #previous, true, spacing .. " yards: fewer, or as many")
        previous = kept
    end
    expectEqual(#ns.MapMarks.thinPoints(points, 400) >= 1, true, "the coarsest step still shows the area")
    -- The same spawns kept whatever list they come in (the map's, the minimap's, another view's): in reverse order,
    -- and with spawns far off added, the same ones of these
    local function keptSet(list, spacing)
        local set = {}
        for _, point in ipairs(ns.MapMarks.thinPoints(list, spacing)) do
            set[point.place] = true
        end
        return set
    end
    local reversed, withOthers = {}, {}
    for index = #points, 1, -1 do
        reversed[#reversed + 1] = points[index]
    end
    for _, point in ipairs(points) do
        withOthers[#withOthers + 1] = point
    end
    for index = 0, 9 do
        withOthers[#withOthers + 1] =
            { x = 0.9, y = 0.1 + index * 0.05, place = { zoneId = 85, x = 90, y = 10 + index * 5 } }
    end
    local isSame = true
    local inOrder, inReverse, amongOthers = keptSet(points, 50), keptSet(reversed, 50), keptSet(withOthers, 50)
    for _, point in ipairs(points) do
        isSame = isSame
            and inOrder[point.place] == inReverse[point.place]
            and inOrder[point.place] == amongOthers[point.place]
    end
    expectEqual(isSame, true, "the same spawns kept in any order, and with others far off in the list")
    -- The step for a zoom: finer as the map grows, and held at a step's edge
    local far, near = ns.MapMarks.chooseSpawnSpacing(0.02), ns.MapMarks.chooseSpawnSpacing(1)
    expectEqual(far > near, true, "zoomed far out, a coarser step than zoomed in")
    local edge = ns.MapMarks.chooseSpawnSpacing(12 / 50 * 1.01, 100)
    expectEqual(edge, 100, "just past a step's edge: the step shown stays, no flicker")
    expectEqual(ns.MapMarks.chooseSpawnSpacing(12 / 50 * 1.3, 100), 50, "well past it: the finer step")
    expectEqual(
        ns.MapMarks.chooseSpawnSpacing(0.1, nil, 0.5) < ns.MapMarks.chooseSpawnSpacing(0.1, nil, 1),
        true,
        "marks drawn smaller need less room: a finer step at the same zoom"
    )
end)

test("a walk is drawn as dashes along it, carried on round its bends, with gaps between", function()
    local ns = createAddon()
    -- An L: 20 across, then 20 down; dashes of 7 with gaps of 6
    local dashes = ns.MapMarks.composeDashes({ { x = 0, y = 0 }, { x = 20, y = 0 }, { x = 20, y = 20 } }, 7, 6)
    local drawn = 0
    for _, dash in ipairs(dashes) do
        drawn = drawn + math.sqrt((dash.to.x - dash.from.x) ^ 2 + (dash.to.y - dash.from.y) ^ 2)
    end
    expectEqual(math.abs(drawn - 22) < 1e-6, true, "40 long: 7 + 7 + 7 + 1 drawn, the gaps left out")
    expectEqual(dashes[1].from.x == 0 and dashes[1].to.x == 7, true, "it starts with a dash")
    local corner = dashes[3]
    expectEqual(
        corner and corner.from.x == 20 and corner.from.y == 6 and corner.to.y == 13,
        true,
        "the dash after the bend carries on the pattern: gap to 6 down, then 7 long"
    )
end)

test(
    "a quest's areas are worked out once on their zone's map and fitted onto any map: the same shape, moved",
    function()
        local ns = createAddon()
        -- Three spawns some 50 yards apart in Tirisfal (85, its map 1420, 1000 yards across here): one area
        local points = {}
        for index, spot in ipairs({ { 50, 50 }, { 55, 52 }, { 52, 56 } }) do
            points[index] = { x = spot[1] / 100, y = spot[2] / 100, place = { zoneId = 85, x = spot[1], y = spot[2] } }
        end
        local own = ns.MapMarks.composeFittedShapes(201, 1420, points, true)
        expectEqual(#own, 1, "one area on the zone's own map")
        local corner = own[1].triangles[1] and own[1].triangles[1][1]
        expectEqual(corner ~= nil, true, "drawn as triangles")
        -- On a continent map Tirisfal fills a box from (0.2, 0.1) to (0.4, 0.3): the same shape, fitted into it
        local savedRect = C_Map.GetMapRectOnMap
        C_Map.GetMapRectOnMap = function()
            return 0.2, 0.4, 0.1, 0.3
        end
        local isFine, problem = pcall(function()
            local continent = ns.MapMarks.composeFittedShapes(201, 1415, points, true)
            local fitted = continent[1] and continent[1].triangles[1] and continent[1].triangles[1][1]
            expectEqual(
                fitted
                    and math.abs(fitted.x - (0.2 + corner.x * 0.2)) < 1e-9
                    and math.abs(fitted.y - (0.1 + corner.y * 0.2)) < 1e-9,
                true,
                "each corner moved into the zone's box on the continent map, nothing worked out again"
            )
        end)
        C_Map.GetMapRectOnMap = savedRect
        if not isFine then
            error(problem, 0)
        end
    end
)

test(
    "MapUtils: its quest pins are noticed and switched off on request, its entrances carry our dungeon marks",
    function()
        local ns = createAddon()
        local provider = ns.Compatibility.getProvider("MapUtils")
        local savedSettings = MAUTTAB
        MAUTTAB = nil
        expectEqual(provider.areQuestPinsShown(), true, "not saved yet: its defaults show quest givers")
        MAUTTAB = { QUESTGIVERWORLDMAPPINS_ENABLED = false, QUESTTURNINWORLDMAPPINS_ENABLED = false }
        expectEqual(provider.areQuestPinsShown(), false, "both kinds switched off in its settings")
        MAUTTAB = { QUESTGIVERWORLDMAPPINS_ENABLED = false }
        expectEqual(provider.areQuestPinsShown(), true, "its turn-ins still on")
        -- Asked once: turning them off writes its own switches
        local shownPopup
        local savedDialogs, savedShow = StaticPopupDialogs, StaticPopup_Show
        StaticPopupDialogs, StaticPopup_Show = {}, function(name)
            shownPopup = name
        end
        provider.ask()
        expectEqual(shownPopup ~= nil, true, "the question is asked")
        StaticPopupDialogs[shownPopup].OnAccept()
        expectEqual(
            MAUTTAB.QUESTGIVERWORLDMAPPINS_ENABLED == false and MAUTTAB.QUESTTURNINWORLDMAPPINS_ENABLED == false,
            true,
            "both switched off"
        )
        shownPopup = nil
        provider.ask()
        expectEqual(shownPopup, nil, "not asked again")
        -- Its one map: a neighbouring zone's point placed where the game puts it in the world, past the map's edges too
        MAUTTAB = {}
        local view = provider.getMapView(WorldMapFrame)
        expectEqual(view ~= nil, true, "its one map is on as it starts: the neighbours' marks too")
        local x, y = view.project(1420, 0.5, 0.5, 1458)
        local expectedX, expectedY
        do
            local continentId, position = C_Map.GetWorldPosFromMapPos(1420, CreateVector2D(0.5, 0.5))
            local _, onMap = C_Map.GetMapPosFromWorldPos(continentId, position, 1458)
            expectedX, expectedY = onMap:GetXY()
        end
        expectEqual(
            x == expectedX and y == expectedY,
            true,
            "Tirisfal's middle on the Undercity's map, as the game reckons it"
        )
        MAUTTAB = { ONEMAP = false }
        expectEqual(provider.getMapView(WorldMapFrame), nil, "its one map switched off: the game's map alone")
        StaticPopupDialogs, StaticPopup_Show, MAUTTAB = savedDialogs, savedShow, savedSettings
    end
)

test("a zone's map shows only the places that belong to that zone", function()
    local ns, state = createAddon()
    -- The bandits are in Tirisfal Glades; pretend the Undercity map also covers the ground they stand on
    C_Map.GetMapPosFromWorldPos = function(_, _, mapId)
        return mapId, {
            GetXY = function()
                return 0.5, 0.5
            end,
        }
    end
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    expectEqual(#ns.MapMarks.compose(1458), 0, "nothing from the neighbouring zone on the Undercity map")
    expectEqual(#ns.MapMarks.compose(1420) > 0, true, "still marked on its own zone's map")
    expectEqual(#ns.MapMarks.compose(9999) > 0, true, "and on a map that belongs to no zone, such as a continent")
    -- The database gives a continent an area of its own; the game says it is a continent
    C_Map.GetMapInfo = function(mapId)
        return { mapType = mapId == 1458 and 2 or 3 }
    end
    expectEqual(
        #ns.MapMarks.compose(1458) > 0,
        true,
        "a continent's map shows everything, even with an area of its own"
    )
    C_Map.GetMapInfo = nil
end)

test("on OpenMap's joined-up map the zones in view are marked too, where OpenMap draws them", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) }) -- its bandits are in Tirisfal Glades (1420)
    ns.Tracker.create()
    -- OpenMap's world: Tirisfal fills its first square; the Undercity map (1458), a tenth of its size, lies off to its east
    local function toWorld(mapId, x, y)
        if mapId == 1420 then
            return x, y
        end
        if mapId == 1458 then
            return 1.2 + x * 0.1, y * 0.1
        end
    end
    local savedApi = OpenMapAPI
    OpenMapAPI = {
        major = 1,
        IsStitched = function()
            return true
        end,
        WorldFromMap = toWorld,
        MapFromWorld = function(mapId, u, v)
            if mapId == 1420 then
                return u, v
            end
            if mapId == 1458 then
                return (u - 1.2) / 0.1, v / 0.1
            end
        end,
        MapAt = function(u)
            return u >= 1.2 and 1458 or 1420
        end,
    }
    local isFine, problem = pcall(function()
        local view = ns.Compatibility.getMapView(WorldMapFrame)
        expectEqual(view ~= nil, true, "OpenMap's view of the world map is used")
        expectEqual(#ns.MapMarks.compose(1458), 0, "without it, the Undercity map shows nothing of Tirisfal's")
        -- In view: the whole of Tirisfal, in the Undercity map's fractions
        local wide = { left = -13, top = -1, right = 1, bottom = 11 }
        ns.MapPins.setView(view, wide)
        local marks = getMarks(ns.MapMarks.compose(1458), "objective")
        expectEqual(#marks > 0, true, "the bandits in Tirisfal are marked, on the Undercity map underneath")
        local x, y = marks[1] and marks[1].x or 0, marks[1] and marks[1].y or 0
        local u, v = toWorld(1458, x, y)
        expectEqual(x < 0, true, "west of the Undercity map's own rectangle")
        expectEqual(u >= 0 and u <= 1 and v >= 0 and v <= 1, true, "where OpenMap draws Tirisfal")
        -- Out of view: not worked out at all
        ns.MapPins.setView(view, { left = 0, top = 0, right = 1, bottom = 1 })
        expectEqual(#getMarks(ns.MapMarks.compose(1458), "objective"), 0, "nothing past what is in view")
        -- A zone reaching into the view gives all its places, wherever the view's edge cuts it: its marks stay put
        ns.MapPins.setView(view, { left = 0, top = 0, right = 1, bottom = 1 }, { [1420] = true })
        local whole = getMarks(ns.MapMarks.compose(1458), "objective")
        expectEqual(
            #whole > 0 and whole[1].x == x and whole[1].y == y,
            true,
            "the same mark in the same place as with the whole zone in view"
        )
        expectEqual(#view.getZoneMapIds(1458, wide), 2, "the zones in view: Tirisfal and the Undercity")
        -- Where the game lists the world's zones, every zone reaching into the view is found, however small the
        -- zones are against the view (zoomed far out a few points across it would miss most of them)
        local savedChildren, savedInfo = C_Map.GetMapChildrenInfo, C_Map.GetMapInfo
        C_Map.GetMapChildrenInfo = function()
            return { { mapID = 1420 }, { mapID = 1458 }, { mapID = 1421 } }
        end
        C_Map.GetMapInfo = function(mapId)
            if mapId == 947 then
                return { mapType = 1, parentMapID = 0 }
            end
            if mapId == 1415 then
                return { mapType = 2, parentMapID = 947 }
            end
            return { mapType = 3, parentMapID = 1415 }
        end
        OpenMapAPI.WorldFromMap = function(mapId, x, y)
            if mapId == 1421 then
                return 5 + x, y
            end -- far off to the east
            return toWorld(mapId, x, y)
        end
        local isListed, problem = pcall(function()
            local inView = view.getZoneMapIds(1458, wide)
            expectEqual(#inView, 2, "Tirisfal and the Undercity, not the zone far off")
            expectEqual(
                #view.getZoneMapIds(1458, { left = 0, top = 0, right = 1, bottom = 1 }),
                1,
                "the Undercity alone in a view of it"
            )
        end)
        C_Map.GetMapChildrenInfo, C_Map.GetMapInfo = savedChildren, savedInfo
        if not isListed then
            error(problem, 0)
        end
    end)
    ns.MapPins.setView(nil)
    OpenMapAPI = savedApi
    if not isFine then
        error(problem, 0)
    end
end)

test("on OpenMap's joined-up map a walk the database lists in two zones' maps is drawn once", function()
    local ns = createAddon()
    -- OpenMap's world: Tirisfal (1420) fills it; the Undercity's map (1458) is a tenth of it, lying in it
    local function toWorld(mapId, x, y)
        if mapId == 1420 then
            return x, y
        end
        if mapId == 1458 then
            return 0.6 + x * 0.1, 0.5 + y * 0.1
        end
    end
    local savedApi = OpenMapAPI
    OpenMapAPI = {
        major = 1,
        IsStitched = function()
            return true
        end,
        WorldFromMap = toWorld,
        MapFromWorld = function(mapId, u, v)
            if mapId == 1420 then
                return u, v
            end
            if mapId == 1458 then
                return (u - 0.6) / 0.1, (v - 0.5) / 0.1
            end
        end,
        MapAt = function(u, v)
            return (u >= 0.6 and u <= 0.7 and v >= 0.5 and v <= 0.6) and 1458 or 1420
        end,
    }
    local isFine, problem = pcall(function()
        local tirisfal, undercity = ns.Database.getAreaId(1420), ns.Database.getAreaId(1458)
        -- One walk in the Undercity's land, listed under Tirisfal's map and again under the Undercity's own
        local inTirisfal = { zoneId = tirisfal, points = { { 62, 52 }, { 65, 55 }, { 68, 58 } } }
        local inUndercity = { zoneId = undercity, points = { { 20, 20 }, { 50, 50 }, { 80, 80 } } }
        ns.MapPins.setView(ns.Compatibility.getMapView(WorldMapFrame), { left = 0, top = 0, right = 1, bottom = 1 })
        expectEqual(#ns.MapMarks.getPatrolLines({ inTirisfal, inUndercity }, 1420), 1, "drawn once, not twice")
        expectEqual(
            #ns.MapMarks.getPatrolLines({ inTirisfal }, 1420),
            1,
            "listed in one zone only: kept, wherever it walks"
        )
        -- A walk of Tirisfal's own, beside a copy elsewhere: both kept
        local outside = { zoneId = tirisfal, points = { { 10, 10 }, { 20, 20 } } }
        expectEqual(
            #ns.MapMarks.getPatrolLines({ outside, inUndercity }, 1420),
            2,
            "each in its own zone's land: both drawn"
        )
    end)
    ns.MapPins.setView(nil)
    OpenMapAPI = savedApi
    if not isFine then
        error(problem, 0)
    end
end)

test("zoomed far out, a zone too small on screen gathers its marks into one pill with its name and counts", function()
    local ns = createAddon()
    local zone = ns.Database.getAreaId(1420)
    local marks = {
        { kind = "objective", questId = 201, zoneId = zone, isFocused = true, glyph = "kill", x = 0.5, y = 0.5 },
        { kind = "objective", questId = 201, zoneId = zone, isFocused = true, glyph = "kill", x = 0.6, y = 0.5 }, -- the same quest's other area
        { kind = "objective", questId = 301, zoneId = zone, glyph = "loot", x = 0.4, y = 0.4 },
        { kind = "turnIn", questId = 101, zoneId = zone, x = 0.3, y = 0.3 },
        { kind = "turnIn", questId = 102, zoneId = zone, isPending = true, x = 0.3, y = 0.3 }, -- not ready: no work there
        { kind = "giver", questId = 501, zoneId = zone, x = 0.2, y = 0.2 },
        { kind = "giver", questId = 502, zoneId = zone, x = 0.25, y = 0.2 },
    }
    local savedRect, savedOn = C_Map.GetMapRectOnMap, ns.MapMarks.ARE_PILLS_ON
    C_Map.GetMapRectOnMap = function()
        return 0.4, 0.5, 0.4, 0.5
    end -- a tenth of the map across
    expectEqual(#ns.MapMarks.gatherZonePills(marks, 1414, 1000), #marks, "pills switched off: the marks themselves")
    ns.MapMarks.ARE_PILLS_ON = true
    local isFine, problem = pcall(function()
        local small = ns.MapMarks.gatherZonePills(marks, 1414, 1000) -- 100 pixels across: a pill
        expectEqual(#small, 1, "one pill for the zone, its marks gone")
        local pill = small[1]
        expectEqual(pill.kind, "zonePill", "a pill")
        expectEqual(pill.questCount, 2, "two of your quests with work there, the one with two areas once")
        expectEqual(pill.readyCount, 1, "one ready to hand in; the grey one not counted")
        expectEqual(pill.giverCount, 2, "two to pick up")
        expectEqual(pill.isFocused, true, "the followed quest is there: its pill is edged in gold")
        expectEqual(pill.x, 0.45, "at the zone's middle")
        expectEqual(#ns.MapMarks.gatherZonePills(marks, 1414, 4000), #marks, "400 pixels across: the marks themselves")
        local few = ns.MapMarks.gatherZonePills({ marks[1], marks[6] }, 1414, 1000)
        expectEqual(#few, 2, "two marks in a small zone stay marks: no pill for so few")
        expectEqual(few[1].kind ~= "zonePill" and few[2].kind ~= "zonePill", true, "neither is a pill")
    end)
    C_Map.GetMapRectOnMap, ns.MapMarks.ARE_PILLS_ON = savedRect, savedOn
    if not isFine then
        error(problem, 0)
    end
end)

test("a quest that starts from a dropped item gets one mark per area, not one per creature", function()
    local ns = createAddon()
    ns.Availability.prepare()
    local marks = {}
    for _, mark in ipairs(getMarks(ns.MapMarks.compose(1420), "giver")) do
        if mark.questId == 519 then
            marks[#marks + 1] = mark
        end
    end
    expectEqual(#marks, 2, "one for each bandit camp in Tirisfal, three spawns between them")
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.showAvailable(519)
    local spots, labels, shade = 0, {}, nil
    for _, mark in ipairs(getMarks(ns.MapMarks.compose(1420), "giver")) do
        if mark.questId == 519 and mark.isFocused then
            spots = spots + #(mark.points or {})
            shade = shade or (mark.points and mark.points[1] and mark.points[1].shade)
            for _, label in ipairs(mark.labels or {}) do
                labels[#labels + 1] = label.text
            end
        end
    end
    expectEqual(spots, 3, "selected, every spawn point of the creature that drops it, in both camps")
    expectEqual(shade, 1, "in the creature's own colour, as on the quest page")
    expectEqual(
        labels[1] and labels[1]:find("Roadside Bandit", 1, true) ~= nil,
        true,
        "the mark's tooltip names the creature"
    )
end)

test("one item left that several creatures drop: each creature gets its own colour, else each objective", function()
    local ns = createAddon()
    LibQuestieDB.Item.Get = (function(original)
        return function(id, field)
            if id == 7001 and field == "npcDrops" then
                return { 5002, 5001 }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Item.Get)
    -- "Two Fronts": bandits to kill, then Wolf Fangs
    local entry = {
        questId = 301,
        objectives = {
            { type = "monster", isFinished = true },
            { type = "item", isFinished = false },
        },
    }
    local shades, sources, sourceObjectiveIndex = ns.MapMarks.getObjectiveShades(entry)
    expectEqual(sourceObjectiveIndex, 2, "the fangs are coloured by creature")
    expectEqual(#sources, 2, "wolves in Silverpine, bandits in Tirisfal")
    expectEqual(shades[2], nil, "no shade of its own")
    entry.objectives[1].isFinished = false
    shades, sources = ns.MapMarks.getObjectiveShades(entry)
    expectEqual(sources, nil, "with two objectives left, colours go by objective")
    expectEqual(shades[1] ~= shades[2], true, "one colour each")
end)

test("where an item drops goes zone by zone: yours first, likeliest creatures first, high levels last", function()
    local ns, state = createAddon()
    LibQuestieDB.Item.Get = (function(original)
        return function(id, field)
            if id == 7004 and field == "npcDrops" then
                return { 5002, 5001, 5003 }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Item.Get)
    LibQuestieDB.Npc.Get = (function(original)
        return function(id, field)
            if id == 5002 and field == "minLevel" then
                return 30 -- wolves far above a level 10 character
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Npc.Get)
    ns.Drops.getChance = function(_, npcId)
        return ({ [5001] = 0.25, [5002] = 0.6, [5003] = 0.05 })[npcId]
    end
    local zones = ns.Drops.getZones(7004)
    expectEqual(zones[1].zoneId, TIRISFAL, "the player's own zone first")
    expectEqual(zones[1].isPlayerZone, true, "marked as where the player is")
    expectEqual(zones[1].sources[1].name, "Roadside Bandit", "its likeliest creature first")
    expectEqual(zones[1].sources[1].shade, 1, "in the first colour")
    expectEqual(zones[#zones].zoneId, SILVERPINE, "the zone of much higher creatures last")
    expectEqual(zones[#zones].isTooHigh, true, "and marked as for higher levels")
    state.playerLevel = 30
    expectEqual(ns.Drops.getZones(7004)[#zones].isTooHigh, false, "no longer once the player is near their level")
end)

test("marks keep clear of other addons' pins, and quests come before givers", function()
    local ns = createAddon()
    local items = {
        { mark = { kind = "giver", questId = 9 }, index = 1, width = 19, height = 21, spotLeft = 200, spotTop = 200 },
        {
            mark = { kind = "objective", number = 1, questId = 1 },
            index = 2,
            width = 24,
            height = 24,
            spotLeft = 202,
            spotTop = 200,
        },
    }
    local pin = { left = 230, top = 190, right = 246, bottom = 206 }
    ns.MapMarks.arrangeMarks(items, { pin })
    expectEqual(
        items[2].left == 202 and items[2].top == 200,
        true,
        "the quest in the log keeps its spot; the giver moves"
    )
    for _, item in ipairs(items) do
        local isClear = item.left + item.width / 2 <= pin.left
            or item.left - item.width / 2 >= pin.right
            or item.top + item.height / 2 <= pin.top
            or item.top - item.height / 2 >= pin.bottom
        expectEqual(isClear, true, "mark " .. item.index .. " is clear of the other addon's pin")
    end
end)

test(
    "however many marks crowd one place, none ends up hidden under another (packed close: boxes may share 5 pixels, round marks almost touching)",
    function()
        local ns = createAddon()
        ns.MapMarks.IS_LAYOUT_ON = true -- what this checks is the laying out, switched off for now
        math.randomseed(7)
        for trial = 1, 300 do
            local items = {}
            local count = math.random(2, 30)
            for index = 1, count do
                local isGiver = math.random() < 0.4
                items[index] = {
                    mark = {
                        kind = isGiver and "giver" or "objective",
                        number = not isGiver and index or nil,
                        questId = index,
                    },
                    index = index,
                    width = isGiver and 19 or 24,
                    height = isGiver and 21 or 24,
                    spotLeft = 300 + math.random() * 120,
                    spotTop = 300 + math.random() * 120,
                }
            end
            ns.MapMarks.arrangeMarks(items)
            for first = 1, count do
                for second = first + 1, count do
                    local a, b = items[first], items[second]
                    local isCovered = (a.width + b.width) / 2 - math.abs(a.left - b.left) > 5.5
                        and (a.height + b.height) / 2 - math.abs(a.top - b.top) > 5.5
                    if isCovered then
                        expectEqual(
                            false,
                            true,
                            "trial " .. trial .. ": marks " .. first .. " and " .. second .. " overlap"
                        )
                        return
                    end
                end
            end
        end
    end
)

test("marks that would overlap are nudged only as far as they must, whatever is selected", function()
    local ns = createAddon()
    ns.MapMarks.IS_LAYOUT_ON = true -- what this checks is the laying out, switched off for now
    local function arrange(focusedNumber)
        local items = {}
        for number = 1, 5 do
            -- Five quests on nearly the same spot, and one far away
            items[number] = {
                mark = { kind = "objective", number = number, isFocused = number == focusedNumber },
                index = number,
                width = 24,
                height = 24,
                spotLeft = 100 + number,
                spotTop = 100,
            }
        end
        items[6] = {
            mark = { kind = "objective", number = 6 },
            index = 6,
            width = 24,
            height = 24,
            spotLeft = 400,
            spotTop = 100,
        }
        ns.MapMarks.arrangeMarks(items)
        return items
    end
    local items = arrange(nil)
    expectEqual(items[6].left == 400 and items[6].top == 100, true, "a mark with room keeps its exact spot")
    for first = 1, 5 do
        for second = first + 1, 5 do
            local a, b = items[first], items[second]
            local isApart = math.abs(a.left - b.left) >= 19 or math.abs(a.top - b.top) >= 19 -- packed close: 5 pixels shared at most
            expectEqual(isApart, true, "quests " .. first .. " and " .. second .. " do not overlap")
        end
    end
    for number = 1, 5 do
        local distance = math.sqrt(
            (items[number].left - items[number].spotLeft) ^ 2 + (items[number].top - items[number].spotTop) ^ 2
        )
        expectEqual(
            distance <= 2 * 24 + 6,
            true,
            "quest " .. number .. " stays near its spot (" .. math.floor(distance) .. ")"
        )
    end
    expectEqual(
        items[1].left == items[1].spotLeft and items[1].top == items[1].spotTop,
        true,
        "the first quest by number keeps its exact spot"
    )
    local selected = arrange(3)
    for number = 1, 6 do
        expectEqual(
            selected[number].left == items[number].left and selected[number].top == items[number].top,
            true,
            "quest " .. number .. " stays put when another is selected"
        )
    end
end)

test("the tracker, the quest list and the quest page draw their marks in every look", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, true, { killObjective(12, 12), itemObjective(4, 4) })
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Tracker.refresh()
    ns.Log.selectQuest(201)
    ns.Log.refresh()
    ns.Log.selectQuest(301)
    ns.Log.refresh()
end)

test("an item that drops in several zones draws zone by zone on the quest page and the map", function()
    local ns, state = createAddon()
    LibQuestieDB.Item.Get = (function(original)
        return function(id, field)
            if id == 7001 and field == "npcDrops" then
                return { 5002, 5001, 5003, 5004 }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Item.Get)
    LibQuestieDB.Npc.Get = (function(original)
        return function(id, field)
            if id == 5002 and field == "minLevel" then
                return 30
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Npc.Get)
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(4, 10) })
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.selectQuest(301)
    ns.Log.refresh()
    local _, zones = ns.MapMarks.getObjectiveShades({
        questId = 301,
        objectives = {
            { type = "monster", isFinished = true },
            { type = "item", isFinished = false },
        },
    })
    expectEqual(zones ~= nil and #zones >= 2, true, "coloured by creature, over several zones")
    local spots = 0
    for _, mark in ipairs(ns.MapMarks.compose(1420)) do
        spots = spots + #(mark.points or {})
    end
    expectEqual(spots > 0, true, "the creatures' spawn points on the map of the zone shown")
end)

test("the followed quest's places draw in every look of the areas and every kind of spawn marker", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    ns.MapPins.create()
    for _, look in ipairs({
        { "none", "square" },
        { "blob", "none" },
        { "filled", "glyph" },
        { "blob", "plate" },
        { "none", "game" },
        { "filled", "square" },
        { "none", "none" },
        { "filled", "glyph" },
    }) do
        ns.settings.areaStyle, ns.settings.spawnMarker = look[1], look[2]
        ns.MapMarks.draw(WorldMapFrame) -- draws without error in every look, and switches back cleanly
        ns.MapMarks.followZoom(WorldMapFrame) -- and follows a zoom step without laying anything out
    end
    -- A zoom step: each mark keeps its spot on the map and its size on screen, drawn smaller by as much as the map grew
    local drawn = ns.MapMarks.getDrawn(WorldMapFrame)
    local savedScale = WorldMapFrame.GetCanvasScale
    WorldMapFrame.GetCanvasScale = function()
        return (drawn.scale or 1) * 2
    end
    ns.MapMarks.followZoom(WorldMapFrame)
    WorldMapFrame.GetCanvasScale = savedScale
    local pool = ns.MapMarksState.pools.marks
    local button = pool.usedCount > 0 and pool[1]
    local expected = ns.MapMarks.getMarkScale(WorldMapFrame:GetMapID(), (drawn.width or 1) * (drawn.scale or 1) * 2) / 2
    expectEqual(
        button and button.zoomScale and math.abs(button.zoomScale - expected) < 1e-6,
        true,
        "the map twice as large: the mark at the new zoom's size, against the layer that grew with the map"
    )
end)

test("icons and areas: one icon to a cell, the quest in focus first, each showing what to do there", function()
    local ns = createAddon()
    ns.MapMarks.IS_LAYOUT_ON = true -- what this checks is the laying out, switched off for now
    local killPoints, lootPoints = {}, {}
    for index = 1, 60 do
        killPoints[index] = { x = 100 + (index * 37 % 50), y = 100 + (index * 53 % 40), glyph = "kill" }
        lootPoints[index] = { x = 110 + (index * 41 % 50), y = 105 + (index * 29 % 40), glyph = "loot" }
    end
    local icons = ns.MapMarks.placeIcons({
        { points = killPoints, color = ns.MapMarks.getQuestColor(3), isFocused = true },
        { points = lootPoints, color = ns.MapMarks.getQuestColor(1), isFocused = false },
    }, {})
    for first = 1, #icons do
        for second = first + 1, #icons do
            local isApart = math.abs(icons[first].x - icons[second].x) >= 12 - 0.001
                or math.abs(icons[first].y - icons[second].y) >= 12 - 0.001
            if not isApart then
                error("icons " .. first .. " and " .. second .. " share a cell")
            end
        end
    end
    expectEqual(
        icons[1].isFocused and icons[1].glyph,
        "kill",
        "the quest in focus claims its cells first, with its swords"
    )
    local hasLoot = false
    for _, icon in ipairs(icons) do
        hasLoot = hasLoot or (icon.glyph == "loot" and not icon.isFocused)
    end
    expectEqual(hasLoot, true, "the other quest's bags fill the cells left")
    expectEqual(
        ns.MapMarks.getQuestColor(13),
        ns.MapMarks.getQuestColor(1),
        "colours go round by the quest's number, twelve of them"
    )
    expectEqual(ns.MapMarks.getQuestColor(2) ~= ns.MapMarks.getQuestColor(1), true, "neighbouring numbers differ")
end)

test("every look of the marks dresses every kind of mark", function()
    local ns = createAddon()
    local marks = {
        { kind = "objective", questId = 201, number = 1, progress = 0.5, isFocused = false, lines = { "a" } },
        { kind = "objective", questId = 201, number = 12, progress = 0, isFocused = true, lines = { "a" } },
        { kind = "turnIn", questId = 301, number = 2, isFocused = false, lines = { "b" } },
        { kind = "giver", questId = 501, isFocused = false, lines = { "c" } },
        { kind = "giver", questId = 507, isFocused = true, lines = { "d" } },
        { kind = "turnIn", questId = 301, number = 2, isFocused = true, isPreview = true, lines = { "b" } },
    }
    for _, mark in ipairs(marks) do
        local button = ns.MapMarks.createMarkButton(UIParent)
        local width, height = ns.MapMarks.applyMarkLook(button, mark)
        expectEqual(type(width) == "number" and type(height) == "number", true, mark.kind .. " has a size")
    end
end)

test("clicking a mark picks its quest; clicking a selected quest giver lets it go", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Log.create()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Availability.prepare()
    local function click(mark)
        local button = ns.MapMarks.createMarkButton(UIParent)
        ns.MapMarks.applyMarkLook(button, mark)
        button:GetScript("OnClick")(button)
    end
    local quest = getMarks(ns.MapMarks.compose(1420), "objective")[1]
    click(quest)
    expectEqual(ns.MapMarks.getFocusedQuestId(), 201, "a quest's mark selects it")
    local giver = getMarks(ns.MapMarks.compose(1420), "giver")[1]
    click(giver)
    expectEqual(ns.Log.getSelectedAvailableQuestId(), giver.questId, "a giver's mark selects its quest")
    local selected
    for _, mark in ipairs(getMarks(ns.MapMarks.compose(1420), "giver")) do
        if mark.isFocused then
            selected = mark
        end
    end
    expectEqual(selected ~= nil and selected.questId, giver.questId, "and it is drawn as selected")
    click(selected)
    expectEqual(ns.Log.getSelectedAvailableQuestId(), nil, "a second click lets it go")
end)

test("quest givers share a mark when close on screen and split when zoomed in", function()
    local ns = createAddon()
    ns.Availability.prepare()
    -- A second giver a little way from the first, offering its own quest
    local points = {
        { x = 0.300, y = 0.300, questId = 501, line = "one" },
        { x = 0.300, y = 0.300, questId = 507, line = "two" },
        { x = 0.312, y = 0.300, questId = 508, line = "three" },
    }
    expectEqual(#ns.MapMarks.composeAreas(points, 0.05), 1, "one group when zoomed out")
    local areas = ns.MapMarks.composeAreas(points, 0.004)
    expectEqual(#areas, 2, "two groups when zoomed in")
    expectEqual(#areas[1].points, 2, "the giver with two quests stays one group")
end)

test("places are grouped into areas by nearness", function()
    local ns = createAddon()
    local areas = ns.MapMarks.composeAreas({ { x = 0.10, y = 0.10 }, { x = 0.12, y = 0.11 }, { x = 0.80, y = 0.80 } })
    expectEqual(#areas, 2, "areas")
    expectEqual(#areas[1].points, 2, "the larger area comes first")
    expectEqual(areas[1].radiusX >= 0.02, true, "an area is never a pinpoint")
end)

test("minimap pins follow distance, facing and the rim", function()
    local ns = createAddon()
    local player = { north = 0, west = 0 }
    local right, up = ns.MinimapPins.getOffset(player, { north = 0, west = -100 }, 200)
    expectEqual(right, 0.5, "100 yards east is half-way to the right")
    expectEqual(up, 0, "and level")
    right, up = ns.MinimapPins.getOffset(player, { north = 0, west = -100 }, 200, math.pi / 2)
    expectEqual(math.floor(up * 100 + 0.5), -50, "facing west, the east is behind")
    expectEqual(math.floor(right * 100 + 0.5), 0, "and centred")
    expectEqual(ns.MinimapPins.getOffset(player, { north = 500, west = 0 }, 200), nil, "out of range is hidden")
    local _, rimUp, isOnRim = ns.MinimapPins.getOffset(player, { north = 500, west = 0 }, 200, nil, true)
    expectEqual(isOnRim, true, "the active quest stays on the rim")
    expectEqual(rimUp > 0.9 and rimUp < 1, true, "at the top")
end)

test(
    "on a minimap that does not turn, the spawn icons stand on a canvas slid under it, and are not placed again as the player walks",
    function()
        local ns, state = createAddon()
        state.playerX, state.playerY = 0.6, 0.5 -- on the first bandit spawn
        setQuest(state, 201, false, { killObjective(5, 12) })
        ns.Tracker.create()
        ns.Focus.set(201)
        -- A minimap with a size and a zoom (the stand-in has neither, which leaves the icons placed move by move)
        Minimap.GetWidth = function()
            return 140
        end
        C_Minimap = {
            GetViewRadius = function()
                return 100
            end,
        }
        ns.MinimapPins.create()
        ns.MinimapPins.refresh()
        local spots = ns.MinimapPins.getDrawn()
        expectEqual(#spots, 2, "both spawns in view answer the pointer")
        -- Every icon of a spawn hangs on the canvas, not on the minimap; the canvas hangs on the minimap's middle
        local first = ns.MinimapPins.getSpot(1)
        expectEqual(first ~= nil and first.isLaid, true, "the first spot has its place")
        -- As on the world map (its laying out is off): the icon stands on its own spawn, not on a cell of a grid
        expectEqual(ns.MapMarks.IS_LAYOUT_ON, false, "marks and icons are not moved apart")
        local _, composedSpots = ns.MinimapPins.compose(100)
        local isOnOwnSpawn = false
        for _, composed in ipairs(composedSpots) do
            isOnOwnSpawn = isOnOwnSpawn or (composed.place.north == first.north and composed.place.west == first.west)
        end
        expectEqual(isOnOwnSpawn, true, "each icon on its own spawn, as on the map")
        local texture = first.textures[1]
        local point = rawget(texture, "points")[1]
        local canvas = point[2]
        expectEqual(point[1], "CENTER", "an icon is held by its middle")
        expectEqual(canvas ~= Minimap, true, "on the canvas, not on the minimap itself")
        local canvasPoint = rawget(canvas, "points")
        canvasPoint = canvasPoint[#canvasPoint]
        expectEqual(canvasPoint[2], Minimap, "the canvas is slid under the minimap")
        -- From the canvas's corner (the player's place when it was laid): right is less west, down is less north
        local origin = ns.Geometry.getPlayerPosition()
        expectEqual(
            math.abs(point[4] - (origin.west - first.west)) < 0.001,
            true,
            "its place across, in yards from the corner"
        )
        expectEqual(math.abs(-point[5] - (origin.north - first.north)) < 0.001, true, "and down")
        -- A few yards on: the canvas slides, the icon is not placed again
        local placedBefore = #rawget(texture, "points")
        local slidBefore = canvasPoint[4]
        state.playerX = 0.601
        ns.MinimapPins.move()
        local slid = rawget(canvas, "points")
        expectEqual(slid[#slid][4] ~= slidBefore, true, "the canvas moved with the land")
        expectEqual(#rawget(texture, "points"), placedBefore, "and the icon was not placed again")
        expectEqual(rawget(texture, "points")[1], point, "it stands where it was put")
        local after = ns.MinimapPins.getDrawn()
        expectEqual(#after, 2, "both still answer the pointer")
        expectEqual(after[1].x ~= spots[1].x, true, "at their new places on the minimap")
        C_Minimap = nil
    end
)

test("the minimap keeps the active quest's far place and shows near ones", function()
    local ns, state = createAddon()
    state.playerX, state.playerY = 0.6, 0.5 -- on the first bandit spawn
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    -- What is chosen is the land round the player, past what the minimap sees; what shows of it is told as they move
    local function getShown(composed)
        local position = ns.Geometry.getPlayerPosition()
        local marks = {}
        for _, shown in ipairs(composed) do
            local right, _, isOnRim = ns.MinimapPins.getMarkOffset(shown, position, 100)
            if right then
                marks[#marks + 1] = { shown = shown, isOnRim = isOnRim }
            end
        end
        return marks
    end
    local composed, spots, _, validYards = ns.MinimapPins.compose(100)
    local shown = getShown(composed)
    expectEqual(#shown, 1, "the nearest of the two spawns within 100 yards has the quest's mark")
    expectEqual(shown[1].isOnRim, false, "at its place: no pointer on the rim while a place of the quest is in view")
    local inView = 0
    for _, spot in ipairs(spots) do
        if ns.MinimapPins.getOffset(ns.Geometry.getPlayerPosition(), spot.place, 100) then
            inView = inView + 1
        end
    end
    expectEqual(inView, 2, "both spawns keep their icons: the mark steps beside the nearest, not over it")
    -- The mark is where the world map has it, not at the spawn nearest the player: walking on, it stays put
    expectEqual(shown[1].shown.place.zoneId, nil, "the mark's place is the world map's, not one of the quest's spawns")
    local markNorth, markWest = shown[1].shown.place.north, shown[1].shown.place.west
    state.playerX, state.playerY = 0.58, 0.52
    local shownAfter = getShown((ns.MinimapPins.compose(100)))
    expectEqual(
        #shownAfter >= 1 and shownAfter[1].shown.place.north == markNorth and shownAfter[1].shown.place.west == markWest,
        true,
        "the quest's mark does not move as the player walks"
    )
    expectEqual(spots[1].isFocused, true, "at full strength: its quest is in focus")
    expectEqual(
        validYards,
        math.huge,
        "all of the quest's places were chosen: the minimap stands till the quests change"
    )
    state.playerX, state.playerY = 0.1, 0.1
    shown = getShown((ns.MinimapPins.compose(100)))
    expectEqual(#shown, 1, "only the rim pin from far away")
    expectEqual(shown[1].shown.isKeptOnRim and shown[1].isOnRim, true, "kept on the rim")
end)

test("the minimap is laid out once: walking slides it, and a kill counted leaves it as it is", function()
    local ns, state = createAddon()
    state.playerX, state.playerY = 0.6, 0.5 -- on the first bandit spawn
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    Minimap.GetWidth = function()
        return 140
    end
    C_Minimap = {
        GetViewRadius = function()
            return 100
        end,
    }
    ns.MinimapPins.create()
    ns.MinimapPins.refresh()
    local composeCount = 0
    local compose = ns.MinimapPins.compose
    ns.MinimapPins.compose = function(...)
        composeCount = composeCount + 1
        return compose(...)
    end
    -- Walking: nothing is chosen again while all that could show was laid out
    for step = 1, 20 do
        state.playerX = 0.6 + step * 0.002
        ns.MinimapPins.tick()
        ns.MinimapPins.move()
    end
    expectEqual(composeCount, 0, "walked on: the minimap's marks were not chosen again")
    -- A kill counted: the quest log's news alone asked for the redraw, and the quest stands where it did
    state.questLog[201] = { isComplete = false, objectives = { killObjective(6, 12) } }
    ns.QuestState.forgetFrame()
    ns.Model.forgetEntries()
    ns.MinimapPins.refreshAfterChange(true)
    expectEqual(composeCount, 0, "a kill counted: kept as laid out")
    local key = ns.MapPins.getDataKey()
    ns.MapPins.refresh()
    ns.MapPins.refreshAfterChange(true)
    expectEqual(ns.MapPins.keptCount or 0, 1, "the world map's marks too")
    -- The objective done: the quest moved on, and both are drawn again
    state.questLog[201] = { isComplete = false, objectives = { killObjective(12, 12) } }
    ns.QuestState.forgetFrame()
    ns.Model.forgetEntries()
    expectEqual(ns.MapPins.getDataKey() ~= key, true, "an objective done: the quests no longer stand where they did")
    ns.MinimapPins.refreshAfterChange(true)
    expectEqual(composeCount, 1, "chosen again")
    -- Anything else asking for the redraw (a setting, the zone): drawn again whatever the quests say
    ns.MinimapPins.refreshAfterChange(false)
    expectEqual(composeCount, 2, "a redraw asked for by something else is never kept")
    ns.MinimapPins.compose = compose
    C_Minimap = nil
end)

test("the minimap keeps a turn-in's mark until the game's own \"?\" has surely come", function()
    local ns, state = createAddon()
    -- Urgent Dispatch, handed in to Aide Rokka in the middle of Orgrimmar (a map 1000 yards across)
    setQuest(state, 101, true)
    ns.Tracker.create()
    state.playerMapId, state.playerX = 1454, 0.5
    local function turnInMarks()
        local count = 0
        for _, shown in ipairs((ns.MinimapPins.compose(200))) do
            local position = ns.Geometry.getPlayerPosition()
            local isShown = shown.data.kind == "turnIn"
                and not shown.isKeptOnRim
                and not ns.MinimapPins.isHandedOver(shown, position)
                and ns.MinimapPins.getOffset(position, shown.place, 200) ~= nil -- in view, as the move step asks
            count = count + (isShown and 1 or 0)
        end
        return count
    end
    state.playerY = 0.365 -- 135 yards off: in the minimap's view (200), beyond the game's visibility range
    expectEqual(turnInMarks(), 1, "ours stands at her place")
    local inView
    for _, shown in ipairs((ns.MinimapPins.compose(200))) do
        inView = shown.data.kind == "turnIn" and not shown.isKeptOnRim and shown or inView
    end
    expectEqual(inView and inView.isGameLook, true, 'drawn as the game\'s own "?", no ring or glow')
    ns.MinimapPins.create()
    ns.MinimapPins.refresh()
    expectEqual(ns.MinimapPins.getHandoverKey(), "0", "checked every frame: ours for now")
    state.playerY = 0.42 -- 80 yards: the game has sent her, its own \"?\" is there
    expectEqual(turnInMarks(), 0, "handed over to the game's")
    expectEqual(ns.MinimapPins.getHandoverKey(), "1", "and the frame check sees it at once")
    state.playerY = 0.2 -- 300 yards: out of view, and not the followed quest
    expectEqual(turnInMarks(), 0, "out of view: none")
end)

test("the quest log window, the map and the minimap draw every state without errors", function()
    local ns, state = createAddon()
    setQuest(state, 101, true)
    setQuest(state, 201, false, { killObjective(5, 12) })
    state.questLog[301] = { isComplete = false, objectives = { killObjective(12, 12), itemObjective(0, 4) } }
    state.partyMembers.party1 = { name = "Mira Dawnfield", questIds = { [201] = true } }
    ns.Tracker.create()
    ns.Tracker.refresh()
    ns.Log.create()
    ns.Log.applyBinding()
    ns.MapDock.create()
    ns.MapDock.apply()
    ns.Log.toggle()
    ns.Log.refresh()
    ns.Log.selectQuest(201)
    ns.settings.collapsedLogZones[TIRISFAL] = true -- a folded group draws its heading only
    ns.Log.refresh()
    ns.settings.collapsedLogZones[TIRISFAL] = nil
    ns.Log.handleMapChanged(1458)
    ns.Log.showZonePage(TIRISFAL)
    ns.Log.showZonePage(ORGRIMMAR)
    ns.Log.showZone(UNDERCITY)
    ns.Log.showAvailable(506)
    ns.Log.showAvailable(501)
    state.questLog = {}
    state.watchedQuestIds = {}
    ns.Log.refresh()
    ns.MapPins.create()
    ns.MapPins.refresh()
    ns.MinimapPins.create()
    ns.MinimapPins.refresh()
    ns.MinimapPins.move()
end)

test("highlighting a quest slides a zoomed-in map to it", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    local entry = ns.Model.composeEntry(201, ns.Model.getPlayer())
    local pannedX, zoomPercent = nil, 0
    WorldMapFrame.IsShown = function()
        return true
    end
    WorldMapFrame.GetMapID = function()
        return 1420
    end
    WorldMapFrame.GetCanvasZoomPercent = function()
        return zoomPercent
    end
    WorldMapFrame.PanTo = function(_, x)
        pannedX = x
    end
    ns.MapDock.showQuestPlace(entry.zoneId, entry.places[1])
    expectEqual(pannedX, nil, "a map zoomed all the way out stays put")
    zoomPercent = 0.5
    ns.MapDock.showQuestPlace(entry.zoneId, entry.places[1])
    expectEqual(type(pannedX), "number", "a zoomed-in map slides to the place")
end)

test('a quest that starts from a dropped item is marked with the item, a quest giver with the "!"', function()
    local ns = createAddon()
    ns.Availability.prepare()
    local fromItem, fromGiver
    for _, mark in ipairs(getMarks(ns.MapMarks.compose(1420), "giver")) do
        if mark.questId == 519 then
            fromItem = mark
        elseif ns.Location.getStarterPlaces(mark.questId)[1] then
            fromGiver = mark -- a quest someone hands out
        end
    end
    expectEqual(
        fromItem ~= nil and fromItem.itemIcon ~= nil,
        true,
        "the item's icon on a quest that starts from a drop"
    )
    expectEqual(fromGiver ~= nil and fromGiver.itemIcon, nil, 'a quest giver keeps the "!"')
    ns.MapMarks.draw(WorldMapFrame)
end)

test("any unfinished quest followed shows where it will be handed in, as a grey ?", function()
    local ns, state = createAddon()
    -- Bandit Trouble: kills in Tirisfal Glades, handed in in Undercity
    setQuest(state, 201, false, { killObjective(5, 12) })
    local function pendingOn(mapId)
        local count = 0
        for _, mark in ipairs(ns.MapMarks.compose(mapId)) do
            count = count + (mark.isPending and 1 or 0)
        end
        return count
    end
    expectEqual(pendingOn(1458), 0, "not followed: none")
    ns.Focus.set(201)
    expectEqual(pendingOn(1458), 1, "followed: a grey ? at Undercity's turn-in, though its kills are elsewhere")
    setQuest(state, 201, true, { killObjective(12, 12) })
    expectEqual(pendingOn(1458), 0, "ready: the ordinary ? instead")
end)

test("a quest's colour comes from its ID: the same after every reload, nothing saved", function()
    local ns = createAddon()
    local watched = { 501, 502 }
    ns.QuestState.getWatchedQuestIds = function()
        return { unpack(watched) }
    end
    ns.QuestState.getWatchKey = function()
        return table.concat(watched, ",")
    end
    local first, second = ns.MapMarks.getQuestColor(1, 501), ns.MapMarks.getQuestColor(2, 502)
    expectEqual(first ~= second, true, "two tracked quests, two colours")
    expectEqual(ns.MapMarks.getQuestColor(7, 501), first, "its place in the tracker does not matter")
    -- Tracked in another order (as after a reload): the same colours
    watched = { 502, 501 }
    expectEqual(ns.MapMarks.getQuestColor(1, 501), first, "the same colour in any order")
    -- A quest whose own colour another tracked quest already has: the lower ID keeps it, it takes the next free one
    watched = { 501, 502, 513 } -- 513's own colour is 501's (twelve colours on)
    local third = ns.MapMarks.getQuestColor(1, 513)
    expectEqual(ns.MapMarks.getQuestColor(1, 501), first, "the lower ID keeps its colour")
    expectEqual(ns.MapMarks.getQuestColor(1, 502), second, "and the others keep theirs")
    expectEqual(third ~= first and third ~= second, true, "the newcomer takes a colour of its own")
    expectEqual(ns.settings.questColors, nil, "nothing is saved")
end)
test("marks that fall on a dungeon's entrance become one dungeon mark, counting what is inside", function()
    local ns, state = createAddon()
    addDungeon()
    ns.settings.shouldShowMapPins = true
    setQuest(state, 601, false, { killObjective(0, 1) }) -- its work is in the keep
    ns.Availability.prepare()
    ns.Tracker.create()
    local marks = ns.MapMarks.compose(1421) -- Silverpine, where the keep's entrance is
    local dungeonMarks, otherAtEntrance = {}, 0
    for _, mark in ipairs(marks) do
        if mark.kind == "dungeon" then
            dungeonMarks[#dungeonMarks + 1] = mark
        elseif mark.zoneId == 209 then
            otherAtEntrance = otherAtEntrance + 1
        end
    end
    expectEqual(#dungeonMarks, 1, "one mark for the keep")
    expectEqual(otherAtEntrance, 0, "nothing else piled on its entrance")
    expectEqual(dungeonMarks[1] and dungeonMarks[1].logCount, 1, "the quest in the log, counted")
    expectEqual(dungeonMarks[1] and dungeonMarks[1].giverCount >= 1, true, "and the ones to pick up inside")
    local button = ns.MapMarks.createMarkButton(UIParent)
    ns.MapMarks.applyMarkLook(button, dungeonMarks[1], 1) -- drawn
end)

test("a dungeon's mark is its entrance circled by its quests' own marks, six at most", function()
    local ns = createAddon()
    local members = {}
    for questId = 701, 708 do
        members[#members + 1] = {
            kind = questId % 2 == 0 and "giver" or "objective",
            questId = questId,
            glyph = "kill",
            number = 1,
            lines = { "q" },
        }
    end
    members[#members + 1] = { kind = "objective", questId = 701, glyph = "loot", number = 1, lines = { "q" } } -- the same quest again
    local mark = {
        kind = "dungeon",
        dungeonId = 209,
        x = 0.5,
        y = 0.5,
        questId = 701,
        members = members,
        logCount = 4,
        giverCount = 4,
        lines = { "Keep" },
    }
    local button = ns.MapMarks.createMarkButton(UIParent)
    local width = ns.MapMarks.applyMarkLook(button, mark, 1)
    expectEqual(#button.orbiting, 6, "six quests round the entrance")
    expectEqual(width, (ns.MapMarks.getFootprint(mark)), "laid out as large as it is drawn")
    local isShown = {}
    for _, orbiting in ipairs(button.orbiting) do
        orbiting.Show = function(self)
            isShown[self] = true
        end
        orbiting.Hide = function(self)
            isShown[self] = false
        end
    end
    mark.members = { members[1] }
    ns.MapMarks.applyMarkLook(button, mark, 1)
    local shown = 0
    for _, orbiting in ipairs(button.orbiting) do
        if isShown[orbiting] then
            shown = shown + 1
        end
    end
    expectEqual(shown, 1, "drawn again with fewer, the rest are hidden")
end)

test("selecting a dungeon's quest never moves the marks round its entrance", function()
    local ns = createAddon()
    local function layout(focusedQuestId)
        local members = {}
        for _, questId in ipairs({ 704, 701, 703, 702 }) do
            members[#members + 1] = {
                kind = questId == 704 and "giver" or "objective",
                questId = questId,
                glyph = "kill",
                lines = { "q" },
                isFocused = questId == focusedQuestId,
            }
        end
        -- The group lists the focused quest first, as its tooltip does
        table.sort(members, function(a, b)
            return a.isFocused and not b.isFocused
        end)
        local button = ns.MapMarks.createMarkButton(UIParent)
        local places = {}
        ns.MapMarks.applyMarkLook(button, {
            kind = "dungeon",
            dungeonId = 209,
            x = 0.5,
            y = 0.5,
            questId = 701,
            members = members,
            logCount = 3,
            giverCount = 1,
            lines = { "Keep" },
        }, 1)
        for index, orbiting in ipairs(button.orbiting) do
            places[orbiting.mark.questId] = index
        end
        return places
    end
    local first, second = layout(701), layout(703)
    for questId, place in pairs(first) do
        expectEqual(second[questId], place, "quest " .. questId .. " keeps its place round the entrance")
    end
    expectEqual(first[704] == 4, true, "quests to pick up after those in the log")
end)

test("a dungeon's mark sits on the entrance icon Leatrix Maps draws near it", function()
    local ns = createAddon()
    local raidIcon = CreateFrame("Frame", nil, UIParent)
    raidIcon.isLeaMapsPin, raidIcon.data = true, { "Raid", 47, 36 }
    local flightIcon = CreateFrame("Frame", nil, UIParent)
    flightIcon.isLeaMapsPin, flightIcon.data = true, { "FlightH", 46, 36.5 }
    local canvas = {
        GetChildren = function()
            return raidIcon, flightIcon
        end,
    }
    local entrances = ns.MapMarks.getEntrancePins(nil, canvas)
    expectEqual(#entrances, 1, "only entrance icons count")
    expectEqual(entrances[1].isRaid, true, "a raid's")
    local near = { kind = "dungeon", x = 0.46, y = 0.365, members = {} }
    local far = { kind = "dungeon", x = 0.2, y = 0.8, members = {} }
    local attached = ns.MapMarks.attachToEntrances({ near, far, { kind = "objective", x = 0.47, y = 0.36 } }, entrances)
    expectEqual(near.x == 0.47 and near.y == 0.36, true, "moved onto the icon")
    expectEqual(near.entrancePin, raidIcon, "attached to it")
    expectEqual(near.isRaid, true, "a raid, as the icon says")
    expectEqual(far.entrancePin, nil, "a dungeon far from any icon keeps its own")
    expectEqual(attached[raidIcon], true, "the icon is no obstacle to our marks")
    local width = ns.MapMarks.getFootprint(near)
    expectEqual(width > ns.MapMarks.getFootprint(far), true, "the quests circle the larger icon further out")
end)

test("a dungeon's quests keep off another addon's pin by its entrance", function()
    local ns = createAddon()
    local members = {}
    for questId = 701, 706 do
        members[#members + 1] = { kind = "objective", questId = questId, glyph = "kill", lines = { "q" } }
    end
    local mark = { kind = "dungeon", members = members }
    local free = ns.MapMarks.chooseOrbitAngles(mark, { left = 100, top = 100 }, {})
    expectEqual(#free, 6, "one place per quest")
    expectEqual(free[2], math.pi / 3, "a sixth of a turn apart when nothing is in the way")
    -- A pin over the lower right of the entrance, as Leatrix Maps' arrow by Razorfen Kraul
    local arrow = { left = 108, top = 106, right = 140, bottom = 140 }
    mark.members = { members[1], members[2], members[3], members[4] }
    local angles = ns.MapMarks.chooseOrbitAngles(mark, { left = 100, top = 100 }, { arrow })
    expectEqual(#angles, 4, "still one place per quest")
    for index, angle in ipairs(angles) do
        local radius = mark.orbitRadius or 22 -- further out when the pin leaves too little room
        local x, y = 100 + radius * math.sin(angle), 100 - radius * math.cos(angle)
        expectEqual(
            x + 9 > arrow.left and x - 9 < arrow.right and y + 9 > arrow.top and y - 9 < arrow.bottom,
            false,
            "nothing under the pin (" .. string.format("%.2f", angle) .. ")"
        )
        local nextAngle = angles[index + 1] or (angles[1] + 2 * math.pi)
        local chord = 2 * radius * math.sin((nextAngle - angle) / 2)
        expectEqual(chord >= 18, true, "the marks clear of one another (" .. string.format("%.1f", chord) .. ")")
    end
end)

test("hovering a quest's area or spawn mark finds its quest, the focused one first where areas overlap", function()
    local ns = createAddon()
    local areas = {
        { points = { { x = 4, y = 4 }, { x = 6, y = 6 } }, reach = 5, questId = 201 },
        { points = { { x = 9, y = 9 }, { x = 11, y = 11 } }, reach = 5, questId = 301, isFocused = true },
    }
    local spots = { { x = 2, y = 2, radius = 3, questId = 401, note = "Kraul Bat - 9%" } }
    local quests = ns.MapHover.findQuests(spots, areas, 7, 7, 7, 7)
    expectEqual(#quests, 2, "both overlapping areas")
    expectEqual(quests[1].questId, 301, "the focused quest first")
    quests = ns.MapHover.findQuests(spots, areas, 2.5, 2, 2.5, 2)
    expectEqual(
        #quests == 1 and quests[1].questId == 401 and quests[1].note ~= nil,
        true,
        "a spawn mark: its quest, with what is there"
    )
    expectEqual(#ns.MapHover.findQuests(spots, areas, 30, 30, 30, 30), 0, "nothing away from them")
end)

test("alt-click on the map focuses the quest whose area is under the cursor; several overlapping ask which", function()
    local ns, state = createAddon()
    setQuest(state, 201, false)
    setQuest(state, 301, false)
    local under = {}
    ns.MapHover.updateMap = function() end
    ns.MapHover.getMapQuests = function()
        return under
    end
    local menus = {}
    local savedMenuUtil, savedControl, savedAlt = MenuUtil, IsControlKeyDown, IsAltKeyDown
    MenuUtil = {
        CreateContextMenu = function(owner, generator)
            local entries = {}
            local root = {
                CreateTitle = function() end,
                CreateDivider = function() end,
                CreateRadio = function(_, text, isSelected, choose, data)
                    entries[#entries + 1] = { text = text, data = data, choose = choose }
                end,
                CreateButton = function(_, text, choose)
                    entries[#entries + 1] = { text = text, choose = choose }
                end,
            }
            generator(owner, root)
            menus[#menus + 1] = entries
        end,
    }
    local map = { ScrollContainer = {} }
    local isControl, isAlt = false, false
    IsControlKeyDown = function()
        return isControl
    end
    IsAltKeyDown = function()
        return isAlt
    end

    under = { { questId = 201 } }
    expectEqual(ns.MapHover.handleMapClick(map, "LeftButton"), false, "a plain click is the game's")
    isControl = true
    expectEqual(
        ns.MapHover.handleMapClick(map, "LeftButton"),
        false,
        "a ctrl-click is the game's waypoint, areas or not"
    )
    isControl, isAlt = false, true
    local selected
    ns.Log.isOpen = function()
        return true
    end
    ns.Log.selectQuest = function(questId)
        selected = questId
    end
    expectEqual(ns.MapHover.handleMapClick(map, "LeftButton"), true, "an alt-click on a quest's area is ours")
    expectEqual(ns.Focus.get(), 201, "and puts it in focus")
    expectEqual(selected, 201, "and opens it in the quest window beside the map")
    selected = nil
    ns.MapHover.handleMapClick(map, "LeftButton")
    expectEqual(ns.Focus.get(), nil, "again on the focused one: let go, as on its mark")
    expectEqual(selected, nil, "and not selected again in the quest window")

    under = { { questId = 201 }, { questId = 301 }, { questId = 999 } } -- (999: not in the log, nothing to focus)
    expectEqual(ns.MapHover.handleMapClick(map, "LeftButton"), true, "overlapping areas: ours")
    expectEqual(#menus, 1, "a menu asks which")
    local menu = menus[1]
    expectEqual(#menu, 2, "with the two quests of the log, not the one outside it")
    menu[2].choose(menu[2].data)
    expectEqual(ns.Focus.get(), 301, "choosing one focuses it")

    under = {}
    expectEqual(ns.MapHover.handleMapClick(map, "LeftButton"), false, "an alt-click on bare land goes on to the game")
    under = { { questId = 999 } }
    expectEqual(ns.MapHover.handleMapClick(map, "LeftButton"), false, "and on a quest not in the log too")
    MenuUtil, IsControlKeyDown, IsAltKeyDown = savedMenuUtil, savedControl, savedAlt
end)

test("the herb and ore spots the game may show are known while their tracking is on, and only then", function()
    local ns = createAddon()
    ns.GatheringNodes = { herb = { 1618 }, ore = { 1731 } }
    ns.Database.getObjectField = function(objectId, field)
        if field ~= "spawns" then
            return nil
        end
        if objectId == 1618 then
            return { [17] = { { 50, 50 }, { -1, -1 } } }
        end -- (the second: inside an instance)
        if objectId == 1731 then
            return { [17] = { { 10, 10 } } }
        end
    end
    ns.Database.getUiMapId = function()
        return 10
    end
    ns.Geometry.getWorldPosition = function(_, x, y)
        return 1, 1000 - y * 10, 1000 - x * 10
    end -- 10 yards a percent
    local savedMinimap = C_Minimap
    local herbsOn, oresOn = false, false
    C_Minimap = {
        GetNumTrackingTypes = function()
            return 2
        end,
        GetTrackingInfo = function(index)
            if index == 1 then
                return { name = "Find Herbs", texture = 133939, active = herbsOn, spellID = 2383 }
            end
            return { name = "Find Minerals", texture = 136025, active = oresOn, spellID = 2580 }
        end,
    }
    local out = {}
    local player = { continentId = 1, north = 500, west = 510 } -- 10 yards from the herb (at 500, 500)
    ns.GatheringSpots.readTracking()
    expectEqual(ns.GatheringSpots.collectNear(player, 100, out), 0, "nothing while neither is tracked")
    herbsOn = true
    ns.GatheringSpots.readTracking()
    expectEqual(ns.GatheringSpots.getTrackedKey(), "h", "Find Herbs on")
    ns.GatheringSpots.finishBuilding() -- (in the game, a few herbs a frame)
    local count = ns.GatheringSpots.collectNear(player, 100, out)
    expectEqual(count, 1, "the herb near, not the ore (not tracked), not the one inside an instance")
    expectEqual(out[1] == 500 and out[2] == 500, true, "where its spawn is in the world")
    expectEqual(ns.GatheringSpots.isNear(out, count, 503, 504, 6), true, "a mark 5 yards off lies on it")
    expectEqual(ns.GatheringSpots.isNear(out, count, 520, 500, 6), false, "one 20 yards off does not")
    expectEqual(
        ns.GatheringSpots.collectNear({ continentId = 2, north = 500, west = 500 }, 100, out),
        0,
        "another continent: none"
    )
    oresOn = true
    ns.GatheringSpots.readTracking()
    ns.GatheringSpots.finishBuilding()
    expectEqual(
        ns.GatheringSpots.collectNear({ continentId = 1, north = 900, west = 900 }, 20, out),
        1,
        "with Find Minerals the ore too"
    )

    -- Gathered: the herb looted beside the player is gone from the minimap, its spot the marks' again for a while
    local now = 1000
    local savedTime, savedCount, savedSource, savedPosition =
        GetTime, GetNumLootItems, GetLootSourceInfo, ns.Geometry.getPlayerPosition
    GetTime = function()
        return now
    end
    GetNumLootItems = function()
        return 1
    end
    GetLootSourceInfo = function()
        return "GameObject-0-4170-0-12-1618-0000ABCDEF"
    end
    ns.Geometry.getPlayerPosition = function()
        return { continentId = 1, north = 503, west = 503 }
    end
    ns.GatheringSpots.handleLootOpened()
    expectEqual(ns.GatheringSpots.collectNear(player, 100, out), 0, "the herb just gathered: its spot given back")
    now = now + 700
    expectEqual(ns.GatheringSpots.collectNear(player, 100, out), 1, "grown back after a while: kept clear again")
    GetLootSourceInfo = function()
        return "Creature-0-4170-0-12-3244-0000ABCDEF"
    end
    ns.GatheringSpots.handleLootOpened()
    expectEqual(ns.GatheringSpots.collectNear(player, 100, out), 1, "loot from a creature gives nothing back")
    GetTime, GetNumLootItems, GetLootSourceInfo, ns.Geometry.getPlayerPosition =
        savedTime, savedCount, savedSource, savedPosition
    C_Minimap = savedMinimap
end)

test("a quest area's edge on the minimap is cut at its round rim", function()
    local ns = createAddon()
    local from, to = ns.MinimapPins.clipToCircle({ x = -20, y = 0 }, { x = 20, y = 0 }, 10)
    expectEqual(from.x == -10 and to.x == 10, true, "a line across: the part inside")
    from, to = ns.MinimapPins.clipToCircle({ x = 0, y = 0 }, { x = 5, y = 0 }, 10)
    expectEqual(from.x == 0 and to.x == 5, true, "a line inside: whole")
    expectEqual(
        ns.MinimapPins.clipToCircle({ x = -20, y = 15 }, { x = 20, y = 15 }, 10),
        nil,
        "a line outside: nothing"
    )
end)

test("a quest area's tooltip lists what drops an item objective, with the chances", function()
    local ns = createAddon()
    local item = {
        type = "item",
        label = "Kraul Guano",
        text = "Kraul Guano: 0/12",
        isFinished = false,
        fulfilled = 0,
        required = 12,
    }
    ns.QuestState.isInLog = function()
        return true
    end
    ns.QuestState.getQuest = function()
        return { title = "Going, Going, Guano!", objectives = { item } }
    end
    ns.Location.getObjectiveTarget = function()
        return { itemId = 5175 }
    end
    ns.Drops.getZones = function()
        return {
            {
                sources = {
                    { name = "Kraul Bat", chance = 0.09 },
                    { name = "Greater Kraul Bat", chance = 0.08 },
                    { name = "Bat Three", chance = 0.05 },
                    { name = "Bat Four", chance = 0.01 },
                },
            },
        }
    end
    local lines = {}
    local tooltip = {
        AddLine = function(_, text)
            lines[#lines + 1] = text
        end,
        AddDoubleLine = function(_, left, right)
            lines[#lines + 1] = left .. "|" .. right
        end,
    }
    ns.MapHover.addQuestLines(tooltip, 1109, nil, true)
    local text = table.concat(lines, "\n")
    expectEqual(
        text:find("Kraul Bat|" .. ns.Drops.formatChance(0.09), 1, true) ~= nil,
        true,
        "the likeliest creature with its chance"
    )
    expectEqual(text:find("Bat Four", 1, true), nil, "three at most")
    expectEqual(text:find("+ 1 more", 1, true) ~= nil, true, "the rest counted")
    lines = {}
    ns.MapHover.addQuestLines(tooltip, 1109, "Kraul Bat - 9%", true)
    expectEqual(
        table.concat(lines, "\n"):find("Greater Kraul Bat", 1, true),
        nil,
        "a spawn mark names its own creature instead"
    )
end)

test("the minimap's marks follow its shape: round by default, square where a minimap addon makes it square", function()
    local ns = createAddon()
    local player, corner = { north = 0, west = 0 }, { north = 80, west = -80 } -- up and to the right
    expectEqual(
        select(1, ns.MinimapPins.getOffset(player, corner, 100, nil, false)),
        nil,
        "past a round minimap's edge"
    )
    GetMinimapShape = function()
        return "SQUARE"
    end
    local right, up = ns.MinimapPins.getOffset(player, corner, 100, nil, false)
    expectEqual(right ~= nil and up ~= nil, true, "inside a square one's corner")
    local onRimRight, onRimUp, isOnRim = ns.MinimapPins.getOffset(player, { north = 300, west = -60 }, 100, nil, true)
    expectEqual(
        isOnRim and math.abs(math.max(math.abs(onRimRight), math.abs(onRimUp)) - 0.94) < 0.001,
        true,
        "kept on the square's rim"
    )
    GetMinimapShape = function()
        return "CORNER-TOPRIGHT"
    end
    expectEqual(
        select(1, ns.MinimapPins.getOffset(player, corner, 100, nil, false)),
        nil,
        "a round upper right quarter"
    )
    expectEqual(
        select(1, ns.MinimapPins.getOffset(player, { north = -80, west = 80 }, 100, nil, false)) ~= nil,
        true,
        "a square lower left one"
    )
    GetMinimapShape = nil
    local from, to = ns.MinimapPins.clipToSquare({ x = -20, y = 5 }, { x = 20, y = 5 }, 10)
    expectEqual(from.x == -10 and to.x == 10, true, "a line cut at a square's edges")
    expectEqual(
        ns.MinimapPins.clipToSquare({ x = -20, y = 15 }, { x = 20, y = 15 }, 10),
        nil,
        "outside the square: nothing"
    )
end)

test("the game's own quest areas on the minimap are hidden while this addon's marks replace the game's", function()
    local ns = createAddon()
    local savedMinimap, alphas = Minimap, {}
    Minimap = {
        SetQuestBlobInsideAlpha = function(_, alpha)
            alphas.inside = alpha
        end,
        SetQuestBlobOutsideAlpha = function(_, alpha)
            alphas.outside = alpha
        end,
        SetQuestBlobRingAlpha = function(_, alpha)
            alphas.ring = alpha
        end,
    }
    ns.settings.shouldShowMapPins, ns.settings.shouldHideBuiltInMapPins, ns.settings.shouldShowMinimapPins =
        true, true, true
    ns.MinimapPins.applyBuiltInAreas()
    expectEqual(alphas.inside == 0 and alphas.outside == 0 and alphas.ring == 0, true, "see-through")
    local printed
    local savedPrint = ns.print
    ns.print = function(text)
        printed = text
    end
    ns.settings.shouldHideBuiltInMapPins = false
    ns.MinimapPins.applyBuiltInAreas()
    expectEqual(
        printed ~= nil and printed:find("/reload", 1, true) ~= nil,
        true,
        "given back with a reload, as the game cannot say how they looked"
    )
    ns.print, Minimap = savedPrint, savedMinimap
end)

test("a quest area's edge on the minimap never runs across a party member or the player", function()
    local ns = createAddon()
    local pieces = ns.MinimapPins.cutAround({ x = -20, y = 0 }, { x = 20, y = 0 }, { { x = 0, y = 0, radius = 5 } })
    expectEqual(#pieces, 2, "cut in two round the member")
    expectEqual(pieces[1].to.x == -5 and pieces[2].from.x == 5, true, "the gap as wide as the circle")
    expectEqual(
        #ns.MinimapPins.cutAround({ x = -20, y = 9 }, { x = 20, y = 9 }, { { x = 0, y = 0, radius = 5 } }),
        1,
        "clear of it: whole"
    )
end)

test("a quest area's tooltip reads as the game's: title, then the objectives still to do", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(2, 8), killObjective(5, 5) })
    local lines = {}
    local tooltip = {
        AddLine = function(_, text)
            lines[#lines + 1] = text
        end,
        AddDoubleLine = function(_, left, right)
            lines[#lines + 1] = left .. "|" .. right
        end,
    }
    ns.MapHover.addQuestLines(tooltip, 201, "Kraul Bat - 9%", true)
    local quest = ns.QuestState.getQuest(201)
    expectEqual(lines[1], string.format("[%d] %s", quest.level, quest.title), "the title first, with the quest's level")
    -- A group quest: the "+" after the level, the players icon, and what kind of group quest under the title
    ns.QuestState.getGroupInfo = function()
        return { kindText = "Group quest", size = 3 }
    end
    local groupLines = {}
    ns.MapHover.addQuestLines({
        AddLine = function(_, text)
            groupLines[#groupLines + 1] = text
        end,
        AddDoubleLine = function(_, left)
            groupLines[#groupLines + 1] = left
        end,
    }, 201, nil, true)
    expectEqual(
        groupLines[1]:find("[" .. quest.level .. "+] " .. quest.title, 1, true) == 1
            and groupLines[1]:find("GlyphPlayers", 1, true) ~= nil,
        true,
        "a group quest's title: level+, then the players icon"
    )
    expectEqual(groupLines[2], "Group quest", "and its kind under it")
    local dashes = 0
    for _, line in ipairs(lines) do
        if line:sub(1, 2) == "- " then
            dashes = dashes + 1
        end
    end
    expectEqual(dashes, 1, "only the objective not done yet")
    expectEqual(lines[#lines], "Kraul Bat - 9%", "what is at the spawn, last")
end)

test("a spawn icon under another addon's pin moves to the free cell beside it", function()
    local ns = createAddon()
    ns.MapMarks.IS_LAYOUT_ON = true -- what this checks is the laying out, switched off for now
    local group =
        { points = { { x = 100, y = 100, glyph = "kill", questId = 1 } }, color = { 1, 1, 1 }, isFocused = false }
    local pin = { left = 90, top = 90, right = 112, bottom = 112 }
    local icons = ns.MapMarks.placeIcons({ group }, { pin }, 15)
    expectEqual(#icons, 1, "still shown")
    local icon = icons[1]
    expectEqual(
        icon.x + 6 <= pin.left or icon.x - 6 >= pin.right or icon.y + 6 <= pin.top or icon.y - 6 >= pin.bottom,
        true,
        "the icon clear of the pin (its glow may reach under)"
    )
    expectEqual(
        math.abs(icon.x - 100) <= 40 and math.abs(icon.y - 100) <= 40,
        true,
        "next to its spawn, two cells at most"
    )
    -- Under its own quest's mark (zoomed out, the area no bigger than the mark): left out, not pushed out of the area
    local ownMark = { left = 90, top = 90, right = 112, bottom = 112, questId = 1 }
    expectEqual(#ns.MapMarks.placeIcons({ group }, { ownMark }, 15), 0, "under its own quest's mark: left out")
    local otherMark = { left = 90, top = 90, right = 112, bottom = 112, questId = 2 }
    expectEqual(#ns.MapMarks.placeIcons({ group }, { otherMark }, 15), 1, "under another quest's mark: steps aside")
end)

test("an area follows its spawns: a lone one's reach is a circle, close ones melt into one round shape", function()
    local ns = createAddon()
    local function getArea(shape)
        local total = 0
        for _, triangle in ipairs(shape.triangles) do
            local a, b, c = triangle[1], triangle[2], triangle[3]
            total = total + math.abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        end
        return total
    end
    local one = ns.MapMarks.composeAreaShape({ { x = 0, y = 0 } }, 10, 1)
    expectEqual(
        math.abs(getArea(one) - math.pi * 100) / (math.pi * 100) < 0.03,
        true,
        "one spawn: a circle's area (" .. getArea(one) .. ")"
    )
    for _, edge in ipairs(one.edges) do
        for _, point in ipairs(edge) do
            local distance = math.sqrt(point.x ^ 2 + point.y ^ 2)
            expectEqual(math.abs(distance - 10) < 0.15, true, "its edge on the reach (" .. distance .. ")")
        end
    end
    -- Two rings overlapping: one shape, smaller than two whole circles; far apart: two whole circles
    local near = ns.MapMarks.composeAreaShape({ { x = 0, y = 0 }, { x = 12, y = 0 } }, 10, 1)
    local far = ns.MapMarks.composeAreaShape({ { x = 0, y = 0 }, { x = 50, y = 0 } }, 10, 1)
    local openBetween = 0
    for _, edge in ipairs(near.edges) do
        for _, point in ipairs(edge) do
            if point.x > 3 and point.x < 9 and math.abs(point.y) < 6 then
                openBetween = openBetween + 1
            end
        end
    end
    expectEqual(openBetween, 0, "close spawns melt into one shape, nothing open between them")
    expectEqual(math.abs(getArea(far) - 2 * math.pi * 100) / (2 * math.pi * 100) < 0.03, true, "far apart: two circles")
    local middleEdges = 0
    for _, edge in ipairs(far.edges) do
        if edge[1].x > 15 and edge[1].x < 35 then
            middleEdges = middleEdges + 1
        end
    end
    expectEqual(middleEdges, 0, "the land between them open")
    expectEqual(
        ns.MapMarks.isInsideArea({ points = { { x = 0, y = 0 } }, reach = 10 }, 6, 6),
        true,
        "inside: within reach"
    )
    expectEqual(ns.MapMarks.isInsideArea({ points = { { x = 0, y = 0 } }, reach = 10 }, 9, 9), false, "outside")
end)

test("the zone map is drawn on its own: the world map's drawing stays the world map's", function()
    local ns = createAddon()
    local zoneMap = CreateFrame("Frame")
    ns.MapMarks.draw(WorldMapFrame)
    local worldDrawn = ns.MapMarks.getDrawn(WorldMapFrame)
    ns.MapMarks.draw(zoneMap)
    local zoneDrawn = ns.MapMarks.getDrawn(zoneMap)
    expectEqual(zoneDrawn ~= worldDrawn, true, "two drawings")
    expectEqual(ns.MapMarks.getDrawn(WorldMapFrame), worldDrawn, "the world map's kept")
    expectEqual(ns.MapMarks.getDrawn().map, WorldMapFrame, "hovering asks about the world map")
    expectEqual(zoneDrawn.map, zoneMap, "the zone map's own")
end)

test("an area's fill is cut from its outline: few triangles, holes left open", function()
    local ns = createAddon()
    local function getArea(triangles)
        local total = 0
        for _, triangle in ipairs(triangles) do
            local a, b, c = triangle[1], triangle[2], triangle[3]
            total = total + math.abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        end
        return total
    end
    -- A ring of spawns round an empty middle: a shape with a hole
    local ring = {}
    for step = 1, 24 do
        local angle = step * math.pi / 12
        ring[#ring + 1] = { x = 40 * math.cos(angle), y = 40 * math.sin(angle) }
    end
    local shape = ns.MapMarks.composeAreaShape(ring, 10, 2)
    local cellCount = 0
    for _ in pairs(shape.edges) do
        cellCount = cellCount + 1
    end
    expectEqual(
        #shape.triangles <= 2 * #shape.edges + 10,
        true,
        "about one triangle a point of the outline (" .. #shape.triangles .. ")"
    )
    -- The middle open: no triangle covers the centre
    local isCentreCovered = false
    for _, triangle in ipairs(shape.triangles) do
        local a, b, c = triangle[1], triangle[2], triangle[3]
        local function side(p, q)
            return (q.x - p.x) * (0 - p.y) - (q.y - p.y) * (0 - p.x)
        end
        local s1, s2, s3 = side(a, b), side(b, c), side(c, a)
        if (s1 >= 0 and s2 >= 0 and s3 >= 0) or (s1 <= 0 and s2 <= 0 and s3 <= 0) then
            isCentreCovered = true
        end
    end
    expectEqual(isCentreCovered, false, "the hole left open")
    local lone = ns.MapMarks.composeAreaShape({ { x = 0, y = 0 } }, 10, 1)
    expectEqual(
        math.abs(getArea(lone.triangles) - math.pi * 100) / (math.pi * 100) < 0.04,
        true,
        "a lone spawn: still its circle"
    )
end)

test("a quest giver's mark says what kind of quest it is", function()
    local ns = createAddon()
    local atlases = {}
    C_Texture = {
        GetAtlasInfo = function(name)
            return { name = name }
        end,
    }
    local button = ns.MapMarks.createMarkButton(UIParent)
    local original = button.bang.SetAtlas
    button.bang.SetAtlas = function(texture, name)
        atlases[#atlases + 1] = name
        if original then
            original(texture, name)
        end
    end
    for _, mark in ipairs({
        { kind = "giver", questId = 1 },
        { kind = "giver", questId = 2, isLowLevel = true },
        { kind = "giver", questId = 3, isRepeatable = true },
        { kind = "turnIn", questId = 4 },
    }) do
        mark.lines = { "q" }
        ns.MapMarks.applyMarkLook(button, mark, 1)
    end
    C_Texture = nil
    expectEqual(table.concat(atlases, " "), "QuestNormal TrivialQuests QuestDaily QuestTurnin", "the game's own marks")
end)

test("a quest's creatures that walk a patrol have it drawn, on the map of the zone it is in", function()
    local ns, state = createAddon()
    -- Bandit Trouble's bandits in Tirisfal Glades walk a road, and one more stands on one spot
    local Npc = LibQuestieDB.Npc
    local savedNpc = Npc.Get
    Npc.Get = function(id, field)
        if id == 5001 and field == "waypoints" then
            return { [85] = { { { 40, 40 }, { 45, 42 }, { 50, 40 } }, { { 60, 60 } } } }
        end
        return savedNpc(id, field)
    end
    setQuest(state, 201, false, { killObjective(5, 12) })
    local patrols = ns.Location.getObjectivePatrols(201)
    expectEqual(#patrols, 1, "one patrol: a path of a single point is no patrol")
    expectEqual(#patrols[1].points, 3, "with its three points")
    local lines = ns.MapMarks.getQuestPatrolLines(201, 1420)
    expectEqual(#lines == 1 and #lines[1], 3, "on Tirisfal Glades' map")
    expectEqual(lines[1][2].x, 0.45, "at its place on that map")
    expectEqual(#ns.MapMarks.getQuestPatrolLines(201, 1458), 0, "not on Undercity's")
    Npc.Get = savedNpc
end)

test("a quest that starts from a dropped item is had from the creatures that drop it, whose paths are drawn", function()
    local ns = createAddon()
    local Quest, Npc = LibQuestieDB.Quest, LibQuestieDB.Npc
    local savedQuest, savedNpc = Quest.Get, Npc.Get
    -- A scroll the Bloodsail captain drops starts it; he walks the shore
    Quest.Get = function(id, field)
        if id == 9500 then
            return ({ name = "The Scroll", startedBy = { {}, {}, { 7001 } } })[field]
        end
        return savedQuest(id, field)
    end
    Npc.Get = function(id, field)
        if id == 5002 and field == "waypoints" then
            return { [85] = { { { 20, 20 }, { 30, 25 } } } }
        end
        return savedNpc(id, field)
    end
    local npcIds = ns.Location.getStarterNpcIds(9500)
    expectEqual(#npcIds == 1 and npcIds[1], 5002, "the creature that drops Wolf Fang")
    expectEqual(#ns.MapMarks.getPatrolLines(ns.Location.getNpcPatrols(5002), 1420), 1, "and its path on the map")
    Quest.Get, Npc.Get = savedQuest, savedNpc
end)

test("a quest giver who walks about has the path drawn while their mark is pointed at, and only then", function()
    local ns = createAddon()
    local Quest, Npc = LibQuestieDB.Quest, LibQuestieDB.Npc
    local savedQuest, savedNpc = Quest.Get, Npc.Get
    Quest.Get = function(id, field)
        if id == 9501 then
            return ({ name = "The Walker's Errand", startedBy = { { 5002 } } })[field]
        end
        return savedQuest(id, field)
    end
    Npc.Get = function(id, field)
        if id == 5002 and field == "waypoints" then
            return { [85] = { { { 20, 20 }, { 30, 25 }, { 40, 20 } } } }
        end
        return savedNpc(id, field)
    end
    ns.MapMarks.draw(WorldMapFrame) -- Tirisfal Glades
    expectEqual(ns.MapMarks.showHoverPatrols(9501), 2, "pointed at: both legs of the path")
    ns.MapMarks.hideHoverPatrols()
    expectEqual(#ns.MapMarks.getGiverPatrolLines(1420), 0, "not pointed at nor selected: no path")
    Quest.Get, Npc.Get = savedQuest, savedNpc
end)

test(
    "the minimap shows where the quest selected on the Available tab starts: the creatures that drop its item",
    function()
        local ns, state = createAddon()
        state.playerX, state.playerY = 0.6, 0.5 -- among the bandits, who drop Bandit Orders
        ns.Availability.prepare()
        ns.Log.create()
        ns.MapDock.create()
        ns.MapDock.apply()
        ns.Log.toggle()
        ns.Log.showAvailable(519) -- Orders from the Road starts from Bandit Orders
        expectEqual(ns.Log.getSelectedAvailableQuestId(), 519, "selected on the Available tab")
        local _, spots = ns.MinimapPins.compose(100)
        local goldSpots = 0
        for _, spot in ipairs(spots) do
            if spot.questId == 519 and spot.color then
                goldSpots = goldSpots + 1
            end
        end
        expectEqual(goldSpots >= 2, true, "the bandits' spawns in range, in the gold of the quest's \"!\"")
        ns.settings.arePanelsHidden = true -- the quest log put away, to walk there
        ns.MapDock.apply()
        expectEqual(ns.Log.isOpen(), false, "the quest log is closed")
        local _, spotsClosed = ns.MinimapPins.compose(100)
        local stillShown = 0
        for _, spot in ipairs(spotsClosed) do
            if spot.questId == 519 then
                stillShown = stillShown + 1
            end
        end
        expectEqual(stillShown >= 2, true, "still shown on the minimap with the quest log closed")
    end
)

test("the minimap shows the zone's quest givers as the game's \"!\" until the game's own comes", function()
    local ns, state = createAddon()
    ns.Availability.prepare()
    local found
    for _, x in ipairs({ 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 }) do
        for _, y in ipairs({ 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8 }) do
            state.playerX, state.playerY = x, y
            for _, shown in ipairs((ns.MinimapPins.compose(233))) do
                if shown.data.kind == "giver" and shown.isGameLook then
                    found = found or shown
                end
            end
        end
    end
    expectEqual(found ~= nil, true, "a giver in view has a mark drawn as the game's")
    local colour = ns.MapMarks.getIconColour(ns.MapMarks.getIconKind(found.data))
    expectEqual(
        colour == "gold" or colour == "grey" or colour == "blue",
        true,
        "the game's \"!\" art, in its kind's colour"
    )
    expectEqual(found.handoverYards, 120, "handed to the game's own once near")
    expectEqual(
        ns.MinimapPins.isHandedOver(found, { north = found.place.north, west = found.place.west }),
        true,
        "standing at the giver, the game's own shows"
    )
end)

test("a patrol answers the pointer only on its line, not round it", function()
    local ns = createAddon()
    local patrol = {
        isPatrol = true,
        questId = 801,
        points = { { x = 0, y = 0 }, { x = 100, y = 0 } },
        segments = { { 0, 0, 100, 0 } },
    }
    expectEqual(#ns.MapHover.findQuests({}, { patrol }, 50, 3, 50, 3), 1, "on the line")
    expectEqual(#ns.MapHover.findQuests({}, { patrol }, 50, 20, 50, 20), 0, "beside it: nothing")
    expectEqual(#ns.MapHover.findQuests({}, { patrol }, 130, 0, 130, 0), 0, "past its end: nothing")
end)

test("spawns all in one spot are one place, not an area: the quest's mark shows it", function()
    local ns = createAddon()
    local points = {}
    for index, spot in ipairs({ { 50, 50 }, { 50.2, 50.1 }, { 50.1, 50.3 } }) do
        points[index] = { x = spot[1] / 100, y = spot[2] / 100, place = { zoneId = 85, x = spot[1], y = spot[2] } }
    end
    expectEqual(#ns.MapMarks.composeFittedShapes(201, 1420, points, true), 0, "no area round a single spot")
end)

test("on a square minimap, what is drawn reaches into its corners, so nothing pops in inside them", function()
    local ns = createAddon()
    local saved = GetMinimapShape
    GetMinimapShape = function()
        return "ROUND"
    end
    local round = ns.MinimapPins.getReach(100)
    GetMinimapShape = function()
        return "SQUARE"
    end
    local square = ns.MinimapPins.getReach(100)
    GetMinimapShape = saved
    expectEqual(
        math.abs(square - round * math.sqrt(2)) < 1e-9,
        true,
        "a square minimap sees its corners, out to the diagonal"
    )
end)
test('hovering the game\'s own "!" or "?" on the minimap lists what that person offers and takes', function()
    local ns = createAddon()
    local lines, _, questIds = ns.MapHover.composeGameMarkLines({
        -- A shared "!": the person's name first, then each quest, as the marks are composed
        {
            kind = "giver",
            questIds = { 189, 581 },
            lines = { "Gemmil", "[38] Bloodscalp Ears", "[37] Hunt for Yenniku" },
        },
        { kind = "turnIn", questId = 638, lines = { "[36] Trollbane", "Turn in to Gemmil" } },
        { kind = "giver", questId = 201, lines = { "[13] Bandit Trouble - Envoy Maldrek" } },
        -- The minimap's giver: its quests alone, no name before them
        { kind = "giver", questId = 605, questIds = { 605 }, lines = { "[22] Wait for It - Envoy Maldrek" } },
        { kind = "objective", lines = { "[30] Something else" } },
    })
    expectEqual(
        #lines,
        5,
        "each quest offered, and each to hand in; not the person's name (the game's tooltip says it); nothing else"
    )
    expectEqual(
        lines[1]:find("AvailableQuestIcon", 1, true) ~= nil and lines[1]:find("Bloodscalp Ears", 1, true) ~= nil,
        true,
        'an offer with the "!"'
    )
    expectEqual(
        lines[3]:find("ActiveQuestIcon", 1, true) ~= nil and lines[3]:find("Trollbane", 1, true) ~= nil,
        true,
        'a hand-in with the "?", its title only'
    )
    expectEqual(lines[4]:find("Envoy Maldrek", 1, true), nil, "a single giver's line without the person's name")
    expectEqual(
        lines[5]:find("Wait for It", 1, true) ~= nil,
        true,
        "a minimap giver's one quest (the case that showed nothing)"
    )
    expectEqual(
        table.concat(questIds, ","),
        "189,581,638,201,605",
        "each line knows its quest, for its level and experience"
    )
    -- With the level, group mark and experience, as every quest tooltip: the "!" icon stays in front of the level
    expectEqual(
        ns.QuestTooltip.formatTitle(lines[4], 201):find("AvailableQuestIcon:0|t [13] Bandit Trouble", 1, true) ~= nil,
        true,
        "the icon, then the level and the title"
    )
    expectEqual(#ns.MapHover.composeGameMarkLines({}), 0, "nobody under the cursor: nothing")
end)

test("the minimap follows a change of the quest in focus at once, not once the player moves", function()
    local ns = createAddon()
    local refreshes = 0
    local saved = ns.MinimapPins.refresh
    ns.MinimapPins.refresh = function()
        refreshes = refreshes + 1
    end
    ns.emit("FOCUS_CHANGED", 42)
    ns.MinimapPins.refresh = saved
    expectEqual(refreshes, 1, "the quest in focus changed: the minimap drawn again")
end)

test("the minimap's spawn icons are smaller zoomed out, full size zoomed in", function()
    local ns = createAddon()
    expectEqual(ns.MinimapPins.getIconScale(233), 0.75, "fully zoomed out: three quarters")
    expectEqual(ns.MinimapPins.getIconScale(150), 1, "from 150 yards in: full size")
    expectEqual(ns.MinimapPins.getIconScale(66), 1, "zoomed in: full size")
    local between = ns.MinimapPins.getIconScale(190)
    expectEqual(between > 0.75 and between < 1, true, "in between: in between")
end)

test("a quest's areas in the world are found again for the same spawns in new tables", function()
    local ns = createAddon()
    -- Two camps in Tirisfal: three spawns close together, one far off
    local function makePoints()
        local points = {}
        for index, spot in ipairs({ { 60, 50 }, { 61, 51 }, { 60.5, 52 }, { 20, 20 } }) do
            points[index] = { x = spot[1] / 100, y = spot[2] / 100, place = { zoneId = 85, x = spot[1], y = spot[2] } }
        end
        return points
    end
    local first = ns.MapMarks.composeStableAreas(makePoints())
    expectEqual(#first, 2, "two areas")
    -- The quest's places worked out again: the same spots, new tables (the cache is kept by where they are)
    local again = ns.MapMarks.composeStableAreas(makePoints())
    expectEqual(#again, 2, "the same two areas, not none")
    expectEqual(#again[1].points == 3 and #again[2].points == 1, true, "each with its spawns")
    expectEqual(again[1].x == first[1].x and again[1].y == first[1].y, true, "the mark on the same spawn")
end)

test("two objectives of the quest in focus sharing a mark hold each spawn once per objective", function()
    local ns, state = createAddon()
    state.questLog[201] = { isComplete = false, objectives = { killObjective(5, 12), killObjective(0, 3) } }
    state.watchedQuestIds[1] = 201
    LibQuestieDB.Quest.Get = (function(original)
        return function(id, field)
            if id == 201 and field == "objectives" then
                return { { { 5001 }, { 5001 } } }
            end
            return original(id, field)
        end
    end)(LibQuestieDB.Quest.Get)
    ns.Tracker.create()
    ns.Focus.set(201)
    local marks = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#marks[1].labels, 2, "the shared mark")
    expectEqual(#marks[1].points, 4, "two spawns of each objective")
    expectEqual(#marks[1].spawnPoints, 4, "its spawns once for each objective, not again for the dots")
    expectEqual(marks[1].points ~= marks[1].spawnPoints, true, "two lists of its own")
end)

test("cycling a quest's zones gets past a dungeon whose entrance is in a zone listed too", function()
    local ns = createAddon()
    addDungeon() -- Shadowfang Keep (209), entered from Silverpine Forest (130)
    local entry = { questId = 777, zoneIds = { SILVERPINE, 209, TIRISFAL }, allPlaces = {} }
    local shownZoneId = SILVERPINE
    ns.MapDock.getShownZoneId = function()
        return shownZoneId
    end
    ns.MapDock.showQuestPlace = function(zoneId)
        shownZoneId = ns.Database.getMapZoneId(zoneId)
    end
    local cycled = {}
    for click = 1, 4 do
        ns.MapDock.showNextQuestZone(entry)
        cycled[click] = ns.settings.cycledQuestZones[777]
    end
    expectEqual(cycled[1], 209, "from Silverpine to the dungeon, shown on Silverpine's map")
    expectEqual(cycled[2], TIRISFAL, "and on past it")
    expectEqual(cycled[3], SILVERPINE, "then back to the first")
    expectEqual(cycled[4], 209, "and round again")
end)

test("taking our waypoint away leaves a pin the player put down since", function()
    local ns = createAddon()
    local userPoint, clearCount = nil, 0
    C_Map.SetUserWaypoint = function(point)
        userPoint = point
    end
    C_Map.GetUserWaypoint = function()
        return userPoint
    end
    C_Map.ClearUserWaypoint = function()
        userPoint, clearCount = nil, clearCount + 1
    end
    UiMapPoint = {
        CreateFromCoordinates = function(uiMapId, x, y)
            return { uiMapID = uiMapId, position = { x = x, y = y } }
        end,
    }
    local entry = { questId = 201, title = "Bandits", places = { { zoneId = TIRISFAL, x = 60, y = 50 } } }
    expectEqual(ns.Waypoints.set(entry), true, "our waypoint is set")
    ns.Waypoints.clear()
    expectEqual(clearCount == 1 and userPoint == nil, true, "ours is taken away")
    ns.Waypoints.set(entry)
    userPoint = { uiMapID = userPoint.uiMapID, position = { x = 0.2, y = 0.3 } } -- the player's own pin, in its place
    ns.Waypoints.clear()
    expectEqual(clearCount == 1 and userPoint ~= nil, true, "the player's pin stays")
    C_Map.SetUserWaypoint, C_Map.GetUserWaypoint, C_Map.ClearUserWaypoint, UiMapPoint = nil, nil, nil, nil
end)

test("the world map opened again is drawn again when the quest it shows in full is another now", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(0, 12) })
    ns.Tracker.create()
    local shownQuestId = 201 -- the quest the maps show in full: the one selected in the quest window while it is open
    ns.MapMarks.getFocusedQuestId = function()
        return shownQuestId
    end
    ns.MapPins.refresh()
    local queued = 0
    local savedQueue = ns.MapPins.queueRefresh
    ns.MapPins.queueRefresh = function()
        queued = queued + 1
    end
    ns.MapPins.handleWorldMapShown()
    expectEqual(queued, 0, "nothing changed: kept from the last opening")
    -- Drawn with another quest selected than the one the window opens on again
    shownQuestId = 301
    ns.MapPins.handleWorldMapShown()
    expectEqual(queued, 1, "another quest in full now: drawn again")
    ns.MapPins.queueRefresh = savedQueue
end)

test("the followed quest's glow on the minimap comes back with its mark", function()
    local ns, state = createAddon()
    state.playerX, state.playerY = 0.6, 0.5 -- on the first bandit spawn
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    Minimap.GetWidth = function()
        return 140
    end
    C_Minimap = {
        GetViewRadius = function()
            return 100
        end,
    }
    local glows = {}
    local createMarkButton = ns.MapMarks.createMarkButton
    ns.MapMarks.createMarkButton = function(...)
        local button = createMarkButton(...)
        local glow = button.glow
        glow.isShownNow = true
        rawset(glow, "Show", function(self)
            self.isShownNow = true
        end)
        rawset(glow, "Hide", function(self)
            self.isShownNow = false
        end)
        rawset(glow, "SetShown", function(self, isShown)
            self.isShownNow = isShown == true
        end)
        rawset(glow, "IsShown", function(self)
            return self.isShownNow
        end)
        glows[#glows + 1] = glow
        return button
    end
    local function countShown()
        local count = 0
        for _, glow in ipairs(glows) do
            count = count + (glow.isShownNow and 1 or 0)
        end
        return count
    end
    ns.MinimapPins.create()
    ns.MinimapPins.refresh()
    local before = countShown()
    expectEqual(before > 0, true, "the followed quest's mark glows")
    state.playerX, state.playerY = 0.1, 0.1 -- far off: its mark out of view, the rim's pointer in its stead
    ns.MinimapPins.move()
    state.playerX, state.playerY = 0.6, 0.5
    ns.MinimapPins.move()
    expectEqual(countShown(), before, "back in view, its glow with it")
    C_Minimap = nil
end)

test("a minimap drawing that fails takes off what was drawn before", function()
    local ns, state = createAddon()
    state.playerX, state.playerY = 0.6, 0.5
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    ns.MinimapPins.create()
    ns.MinimapPins.refresh()
    local spotPool, shownSpots = ns.MinimapPins.getSpotPool()
    expectEqual(#shownSpots > 0, true, "drawn")
    local function countIn()
        local count = 0
        for _, spot in ipairs(spotPool) do
            count = count + (spot.isIn and 1 or 0)
        end
        return count
    end
    expectEqual(countIn() > 0, true, "its spawn icons on the minimap")
    local compose = ns.MinimapPins.compose
    ns.MinimapPins.compose = function()
        error("broken quest data")
    end
    local isFine, problem = pcall(ns.MinimapPins.refresh)
    ns.MinimapPins.compose = compose
    expectEqual(
        isFine == false and tostring(problem):find("broken quest data", 1, true) ~= nil,
        true,
        "the error is still told"
    )
    _, shownSpots = ns.MinimapPins.getSpotPool()
    expectEqual(#shownSpots == 0 and countIn() == 0, true, "nothing left standing from before")
    -- Switched off: nothing chosen
    ns.MinimapPins.refresh()
    ns.settings.shouldShowMinimapPins = false
    ns.MinimapPins.refresh()
    _, shownSpots = ns.MinimapPins.getSpotPool()
    expectEqual(#shownSpots, 0, "the minimap's marks off: none")
end)
