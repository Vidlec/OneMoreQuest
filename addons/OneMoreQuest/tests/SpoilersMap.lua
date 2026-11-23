-- Tests: spoilers on the world map, the minimap and the waypoint: quests to pick up, where objectives are, where to
-- hand in, the map's fog, peeking with Alt, and Guide drawing exactly what it always did.

---@return string text A mark list as words, to compare two drawings
local function describeMarks(marks)
    local parts = {}
    for _, mark in ipairs(marks) do
        parts[#parts + 1] = string.format("%s:%s:%.4f:%.4f:%s:%d", mark.kind, tostring(mark.questId), mark.x, mark.y,
            table.concat(mark.lines or {}, "/"), #(mark.spawnPoints or mark.points or {}))
    end
    return table.concat(parts, "\n")
end

local function startSpoilers(ns, choices)
    ns.Spoilers.create()
    for category, choice in pairs(choices) do
        ns.Spoilers.setChoice(category, choice)
    end
end

local function hasLine(mark, text)
    for _, line in ipairs(mark.lines or {}) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

---Every spot of a zone's map in fog (nothing explored), until put back.
local function fogEverything()
    local saved = { info = C_MapExplorationInfo, layers = C_Map.GetMapArtLayers }
    C_MapExplorationInfo = { GetExploredMapTextures = function() return {} end }
    C_Map.GetMapArtLayers = function() return { { layerWidth = 1002, layerHeight = 668 } } end
    return function()
        C_MapExplorationInfo, C_Map.GetMapArtLayers = saved.info, saved.layers
    end
end

test("in Guide the maps draw exactly what they did, and nothing of the spoilers is asked", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    setQuest(state, 301, false, { killObjective(2, 12), itemObjective(0, 4) })
    ns.Tracker.create()
    ns.Focus.set(201)
    ns.Availability.prepare()
    local before = describeMarks(ns.MapMarks.compose(1420))
    ns.Spoilers.create()
    expectEqual(ns.MapMarks.getSpoilers(), nil, "nothing held back")
    expectEqual(describeMarks(ns.MapMarks.compose(1420)), before, "the same marks, in the same places")
    expectEqual(ns.MapPins.getDataKey():find("|guide", 1, true) ~= nil, true, "the maps' key says Guide, and stays so")
    local entry = ns.Model.composeEntry(201, ns.Model.getPlayer())
    expectEqual(ns.MapMarks.getShownStep(entry, ns.MapMarks.getSpoilers(true)), nil, "the minimap shows the quest's own places")
    expectEqual(ns.Waypoints.getQuestPlace(entry) ~= nil, true, "the waypoint goes to its place")
end)

test("rough: a dashed circle round each area, its middle moved off, covering every spawn; no spawns, no shapes", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    local exact = getMarks(ns.MapMarks.compose(1420), "objective")
    startSpoilers(ns, { objectives = "rough" })
    local marks = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#marks, #exact, "a mark for each area, as before")
    for index, mark in ipairs(marks) do
        expectEqual(mark.isRough, true, "a rough mark")
        expectEqual(mark.roughCircles ~= nil and #mark.roughCircles, 1, "its circle")
        expectEqual(#mark.points + #mark.areas + #(mark.spawnPoints or {}), 0, "no spawn and no area of its own")
        expectEqual(hasLine(mark, "Somewhere here"), true, "it says so")
        expectEqual(mark.x ~= exact[index].x or mark.y ~= exact[index].y, true, "not on the area's own spot")
    end
    -- In the world: every place of the area within the circle, the middle not the area's middle
    local places = ns.Location.getObjectiveInfo(201, "monster", 1)
    local circles = ns.MapMarks.getRoughCircles(201, 1, places)
    expectEqual(ns.MapMarks.getRoughCircles(201, 1, places), circles, "worked out once")
    for _, circle in ipairs(circles) do
        local uiMapId = ns.Database.getUiMapId(circle.place.zoneId)
        local _, north, west = ns.Geometry.getWorldPosition(uiMapId, circle.place.x, circle.place.y)
        for _, place in ipairs(circle.places) do
            local _, placeNorth, placeWest = ns.Geometry.getWorldPosition(ns.Database.getUiMapId(place.zoneId), place.x, place.y)
            expectEqual(ns.Geometry.getDistance(north, west, placeNorth, placeWest) <= circle.radiusYards, true, "a spawn inside its circle")
        end
    end
    ns.Focus.set(nil)
    local quiet = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#quiet, 1, "out of focus one mark")
    expectEqual(#quiet[1].roughCircles, #circles, "with every circle")
    ns.MapPins.create()
    ns.MapPins.refresh() -- draws the circles
    local drawn = ns.MapMarks.getDrawn()
    local isHovered = false
    for _, area in ipairs(drawn.areas) do
        isHovered = isHovered or area.note == "Somewhere here"
    end
    expectEqual(isHovered, true, "a circle answers the pointer")
    local entry = ns.Model.composeEntry(201, ns.Model.getPlayer())
    expectEqual(ns.Waypoints.getQuestPlace(entry), nil, "no waypoint to the exact place")
end)

test("rough: who drops the item is named as chosen, the chances only with chances", function()
    local ns, state = createAddon()
    addProfitData()
    setQuest(state, 301, false, { killObjective(12, 12), itemObjective(0, 4) })
    ns.Tracker.create()
    ns.Focus.set(301)
    ns.Drops.getZones = function() return { { sources = { { npcId = 5002, name = "Silverpine Wolf", chance = 0.25 } } } } end
    startSpoilers(ns, { objectives = "rough", drops = "names" })
    local marks = getMarks(ns.MapMarks.compose(1421), "objective")
    expectEqual(#marks > 0, true, "a rough mark")
    expectEqual(hasLine(marks[1], "Dropped by Silverpine Wolf"), true, "the creature named")
    expectEqual(hasLine(marks[1], "%"), false, "no chance")
    ns.Spoilers.setChoice("drops", "chances")
    expectEqual(hasLine(getMarks(ns.MapMarks.compose(1421), "objective")[1], "25%"), true, "with the chance")
    ns.Spoilers.setChoice("drops", "found")
    expectEqual(hasLine(getMarks(ns.MapMarks.compose(1421), "objective")[1], "Dropped by"), false, "none dropped it yet")
    ns.Spoilers.getMemory().drops[7001] = { [5002] = true }
    expectEqual(hasLine(getMarks(ns.MapMarks.compose(1421), "objective")[1], "Dropped by Silverpine Wolf"), true, "once it dropped")
    removeProfitData()
end)

test("found: only where the player saw the objective move on, said to be found; nothing before", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    startSpoilers(ns, { objectives = "found" })
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "objective"), 0, "nothing found yet: nothing drawn")
    local entry = ns.Model.composeEntry(201, ns.Model.getPlayer())
    expectEqual(ns.MapMarks.getShownStep(entry, ns.MapMarks.getSpoilers(true)).isHidden, true, "nothing on the minimap")
    ns.Spoilers.getMemory().found[201] = { [1] = { { zoneId = TIRISFAL, x = 60, y = 50 }, { zoneId = TIRISFAL, x = 61, y = 50.5 } } }
    local marks = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#marks, 1, "one mark where it was found")
    expectEqual(hasLine(marks[1], "Found by you"), true, "said to be found")
    expectEqual(#marks[1].spawnPoints, 2, "each place found its spot")
    expectEqual(marks[1].spawnPoints[1].note, "Found by you", "and its spot's tooltip says so")
    expectEqual(ns.Spoilers.getMemory().found[201][1][1].north, nil, "the saved places are left as saved")
    ns.MapPins.create()
    ns.MapPins.refresh()
end)

test("hidden objectives draw nothing, on the map, the minimap or as a waypoint; the turn-in stays as chosen", function()
    local ns, state = createAddon()
    state.playerX, state.playerY = 0.6, 0.5
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    startSpoilers(ns, { objectives = "hidden" })
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "objective"), 0, "no objective's mark")
    local pending = ns.MapMarks.compose(1458)
    expectEqual(#pending == 1 and pending[1].isPending, true, "where it will be handed in, in grey")
    for _, shown in ipairs((ns.MinimapPins.compose(100))) do
        expectEqual(shown.data.questId ~= 201, true, "nothing of it on the minimap")
    end
    local entry = ns.Model.composeEntry(201, ns.Model.getPlayer())
    expectEqual(ns.Waypoints.getQuestPlace(entry), nil, "no waypoint")
    ns.Spoilers.setChoice("turnIn", "hidden")
    expectEqual(#ns.MapMarks.compose(1458), 0, "the grey ? held back too")
end)

test("the minimap: a rough quest is a dashed ring with its mark, no spawn icons", function()
    local ns, state = createAddon()
    state.playerX, state.playerY = 0.6, 0.5 -- on the first bandit spawn
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    startSpoilers(ns, { objectives = "rough" })
    local composed, spots, areas = ns.MinimapPins.compose(100)
    local rings = 0
    for _, area in ipairs(areas) do
        expectEqual(area.isRough, true, "only rings, no shapes and no walks")
        expectEqual(#area.triangles, 0, "no fill")
        rings = rings + 1
    end
    expectEqual(rings > 0, true, "a ring round where it is")
    expectEqual(#spots, 0, "no spawn icons")
    local hasPointer = false
    for _, shown in ipairs(composed) do
        hasPointer = hasPointer or shown.isKeptOnRim
    end
    expectEqual(hasPointer, true, "the followed quest still points the way, to its circle")
end)

test("quests to pick up: all, only givers met, none", function()
    local ns = createAddon()
    ns.Availability.prepare()
    local allCount = #getMarks(ns.MapMarks.compose(1420), "giver")
    expectEqual(allCount > 0, true, "givers in Guide")
    startSpoilers(ns, { pickup = "none" })
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "giver"), 0, "none")
    ns.Spoilers.setChoice("pickup", "met")
    local metCount = 0
    for _, mark in ipairs(getMarks(ns.MapMarks.compose(1420), "giver")) do
        expectEqual(mark.itemIcon == nil, false, "only quests no one gives (a dropped item's) need a drop or a kill")
        metCount = metCount + 1
    end
    ns.Spoilers.getMemory().met[9003] = true
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "giver") > metCount, true, "the giver met shows their quests")
end)

test("where to hand in: shown, once met, hidden", function()
    local ns, state = createAddon()
    setQuest(state, 201, true, { killObjective(12, 12) })
    startSpoilers(ns, { turnIn = "hidden" })
    expectEqual(#getMarks(ns.MapMarks.compose(1458), "turnIn"), 0, "hidden")
    ns.Spoilers.setChoice("turnIn", "met")
    expectEqual(#getMarks(ns.MapMarks.compose(1458), "turnIn"), 0, "not met yet")
    ns.Spoilers.getMemory().met[9002] = true
    expectEqual(#getMarks(ns.MapMarks.compose(1458), "turnIn"), 1, "met: the ?")
    local entry = ns.Model.composeEntry(201, ns.Model.getPlayer())
    expectEqual(ns.Waypoints.getQuestPlace(entry) ~= nil, true, "and the waypoint may lead there")
end)

test("the map's fog: no giver and no rough circle in land not explored, unless a hint showed it all", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    ns.Availability.prepare()
    local restore = fogEverything()
    startSpoilers(ns, { objectives = "rough", pickup = "all" })
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "giver"), 0, "no giver in fog")
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "objective"), 0, "no circle in fog")
    ns.Spoilers.giveHint(201, ns.Spoilers.HINT_EXACT)
    local marks = getMarks(ns.MapMarks.compose(1420), "objective")
    expectEqual(#marks > 0 and marks[1].isRough, nil, "the hint shows it exactly, fog or not")
    restore()
end)

test("Alt held over the world map shows everything there, once a peek, and nowhere else", function()
    local ns, state = createAddon()
    setQuest(state, 201, false, { killObjective(5, 12) })
    ns.Tracker.create()
    ns.Focus.set(201)
    startSpoilers(ns, { objectives = "hidden" })
    ns.MapPins.create()
    local key = ns.MapPins.getDataKey()
    local savedAlt, savedContainer = IsAltKeyDown, WorldMapFrame.ScrollContainer
    WorldMapFrame.ScrollContainer = { IsMouseOver = function() return true end }
    IsAltKeyDown = function() return true end
    ns.MapHover.handleModifierChange("LALT", 1)
    expectEqual(ns.MapMarks.isPeeking(), true, "peeking")
    expectEqual(ns.MapPins.getDataKey() ~= key, true, "the map is drawn again for it")
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "objective") > 0, true, "the world map shows the objectives")
    expectEqual(#getMarks(ns.MapMarks.compose(1420, true), "objective"), 0, "the minimap does not")
    expectEqual(ns.Spoilers.getMemory().peeks, 1, "counted once")
    IsAltKeyDown = function() return false end
    ns.MapHover.handleModifierChange("LALT", 0)
    expectEqual(ns.MapMarks.isPeeking(), false, "let go: back as chosen")
    expectEqual(#getMarks(ns.MapMarks.compose(1420), "objective"), 0, "held back again")
    IsAltKeyDown, WorldMapFrame.ScrollContainer = savedAlt, savedContainer
end)

test("a quest area's drop lines follow the drops choice: chances, names, those that dropped it, none", function()
    local ns = createAddon()
    local item = { type = "item", label = "Kraul Guano", text = "Kraul Guano: 0/12", isFinished = false, fulfilled = 0, required = 12 }
    ns.QuestState.isInLog = function() return true end
    ns.QuestState.getQuest = function() return { title = "Going, Going, Guano!", objectives = { item } } end
    ns.Location.getObjectiveTarget = function() return { itemId = 5175 } end
    ns.Drops.getZones = function()
        return { { sources = { { npcId = 1, name = "Kraul Bat", chance = 0.09 }, { npcId = 2, name = "Greater Kraul Bat", chance = 0.08 } } } }
    end
    local lines
    local tooltip = { AddLine = function(_, text) lines[#lines + 1] = text end, AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. "|" .. right end }
    local function read()
        lines = {}
        ns.MapHover.addDropLines(tooltip, 1109, 1)
        return table.concat(lines, "\n")
    end
    expectEqual(read():find("Kraul Bat|", 1, true) ~= nil, true, "Guide: with the chance")
    startSpoilers(ns, { drops = "names" })
    expectEqual(read():find("|", 1, true), nil, "names: no chance")
    expectEqual(read():find("Kraul Bat", 1, true) ~= nil, true, "but the name")
    ns.Spoilers.setChoice("drops", "found")
    expectEqual(read(), "", "found: none dropped it yet")
    ns.Spoilers.getMemory().drops[5175] = { [2] = true }
    expectEqual(read(), "   Greater Kraul Bat", "only the one that dropped it")
    ns.Spoilers.setChoice("drops", "hidden")
    expectEqual(read(), "", "hidden: nothing")
end)

test("rough circles: the same creatures give the same circle, whatever the quest or objective", function()
    local ns = createAddon()
    local places = ns.Location.getObjectiveInfo(201, "monster", 1)
    local first = ns.MapMarks.getRoughCircles(201, 1, places)
    local other = ns.MapMarks.getRoughCircles(9999, 3, places)
    expectEqual(#first > 0 and #first == #other, true, "as many circles")
    for index, circle in ipairs(first) do
        expectEqual(other[index].place.x, circle.place.x, "the same middle across")
        expectEqual(other[index].place.y, circle.place.y, "the same middle down")
        expectEqual(other[index].radiusYards, circle.radiusYards, "the same reach")
    end
end)
