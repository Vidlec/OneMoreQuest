local _, ns = ...
local CreateFrame = ns.CreateFrame -- (Core: frames made inside an open gamepad window)

-- The quest log window: a quest's To do list, on its page. Where each objective is done (Spoiled.composeWhere: as
-- much as the Spoilers choices let tell), where a quest's item drops, the event to wait for, and the turn-in.
local Log = ns.Log
local Style, State, Actions = ns.LogStyle, ns.LogState, ns.LogActions
local List, QuestPage, QuestsTab, AvailableTab, SettingsView, Window =
    ns.LogList, ns.LogQuestPage, ns.LogQuestsTab, ns.LogAvailableTab, ns.LogSettingsView, ns.LogWindow
local COLORS, DOT, PADDING = Style.COLORS, Style.DOT, Style.PADDING
local Spoiled = QuestPage.Spoiled
local CHECKBOX_IMAGE, CHECKBOX_SIZE, CHECKBOX_TICK, TO_DO_LEAD =
    QuestPage.CHECKBOX_IMAGE, QuestPage.CHECKBOX_SIZE, QuestPage.CHECKBOX_TICK, QuestPage.TO_DO_LEAD
local addBody, addHeading, addStepLine, composePlaceLine =
    QuestPage.addBody, QuestPage.addHeading, QuestPage.addStepLine, QuestPage.composePlaceLine

---Where each objective of a quest is found.
---@return { objective: table, place: table?, distance: number?, sourceText: string? }[] details In the quest's order
local function composeObjectiveDetails(entry)
    local details, typeIndexes = {}, {}
    local position = ns.Geometry.getPlayerPosition()
    for _, objective in ipairs(entry.objectives) do
        typeIndexes[objective.type] = (typeIndexes[objective.type] or 0) + 1
        local stillNeeded = objective.required
                and objective.required > 0
                and math.max(objective.required - (objective.fulfilled or 0), 0)
            or nil
        local places, sourceText, isCrafted = ns.Location.getObjectiveInfo(
            entry.questId,
            objective.type,
            typeIndexes[objective.type],
            objective.label,
            stillNeeded
        )
        local distance, _, place = ns.Geometry.getNearest(places, position, ns.Database.getUiMapId)
        -- For an item that drops, how often: the chance of its likeliest source, the one worth hunting
        -- For an item that drops: where, zone by zone, each creature with its chance (Drops)
        local zones
        local target = objective.type == "item"
            and ns.Location.getObjectiveTarget(entry.questId, "item", typeIndexes.item)
        if target and target.itemId then
            zones = ns.Drops.getZones(target.itemId)
        end
        details[#details + 1] = {
            objective = objective,
            place = place or places[1],
            distance = distance,
            sourceText = sourceText,
            isCrafted = isCrafted,
            zones = zones and #zones > 0 and zones or nil,
            itemId = target and target.itemId or nil,
            stillNeeded = stillNeeded,
        }
    end
    return details
end

---What can be done about an objective the database puts nowhere on the map: for an item, what waits in the bank,
---what the Auction House asks (with Auctionator) and where it comes from when that is known; for a crafted item, how
---it is made. Without any of these it says why the mark is missing. The quest's own words are on hover.
---@return string text Lines, under the objective
function QuestPage.composeWaysToGet(detail)
    if detail.isCrafted then
        return detail.sourceText or ""
    end
    local ways = {}
    local itemId = detail.objective.type == "item" and detail.itemId or nil
    if itemId then
        local inBank = ns.Crafting.getBankCount(itemId)
        if inBank > 0 then
            ways[#ways + 1] = ns.L("%d in your bank", inBank)
        end
        local toGet = math.max((detail.stillNeeded or 1) - inBank, 0)
        local price = toGet > 0 and ns.Prices.getAuctionPrice(itemId)
        if price then
            ways[#ways + 1] = toGet > 1
                    and ns.L("about %s for %d at the Auction House", ns.Widgets.formatMoney(price * toGet), toGet)
                or ns.L("about %s at the Auction House", ns.Widgets.formatMoney(price))
        end
    end
    if detail.sourceText then
        ways[#ways + 1] = detail.sourceText
    end
    local lines = { ns.L("Not on the map: the quest database does not say where") }
    if #ways > 0 then
        lines[1] = ns.L("Not on the map. Ways to get it:")
        for _, way in ipairs(ways) do
            lines[#lines + 1] = "- " .. way
        end
    end
    lines[#lines + 1] = "|cff8a7350" .. ns.L("Point at it for what the quest says") .. "|r"
    return table.concat(lines, "\n")
end

---The game's tooltip over an objective with no place: what the quest itself says, in the player's language when a
---translation addon gives it, and why there is no mark.
function QuestPage.showQuestWords(button, data)
    local english = ns.Database.getQuestField(data.questId, "objectivesText")
    english = type(english) == "table" and table.concat(english, " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or nil
    local words = english and english ~= "" and ns.QuestText.getObjectives(data.questId, english) or nil
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(data.title or "", 1, 1, 1)
    if words then
        GameTooltip:AddLine(ns.L("The quest says"), 0.6, 0.6, 0.6)
        GameTooltip:AddLine(words, 1, 0.82, 0, true)
    else
        GameTooltip:AddLine(ns.L("The quest says nothing about where"), 0.6, 0.6, 0.6, true)
    end
    GameTooltip:AddLine(
        ns.L("Its place is not in the quest database, so it has no mark on the map."),
        0.6,
        0.6,
        0.6,
        true
    )
    GameTooltip:Show()
end

local function showZonesTooltip(button, entry)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    ns.MapDock.addZonesToTooltip(GameTooltip, entry)
    GameTooltip:Show()
end

---The tooltip follows the click: the arrow moves to the zone now on the map. Turning the map draws the page
---again, which gives the quest a fresh entry, so the quest is known by its number; and once more on the next
---frame, after that drawing.
local function handleZonesClick(entry)
    local questId = entry.questId
    ns.MapDock.showNextQuestZone(entry)
    local function refreshTooltip()
        local owner = GameTooltip:IsShown() and GameTooltip:GetOwner()
        if owner and type(owner.data) == "table" and owner.data.questId == questId then
            showZonesTooltip(owner, owner.data)
        end
    end
    refreshTooltip()
    if C_Timer then
        C_Timer.After(0, refreshTooltip)
    end
end

local dropFolds = {} -- [fold key] = true while a folded part of a drop list is open

local function toggleDropFold(key)
    dropFolds[key] = not dropFolds[key] or nil
    Log.refresh()
end

---@return table? place Where to look first in one of an item's zones: its nearest place there with a known spot
local function getDropZonePlace(zone)
    local _, _, place = ns.Geometry.getNearest(zone.places, ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
    if place then
        return place
    end
    for _, zonePlace in ipairs(zone.places) do
        if zonePlace.x >= 0 then
            return zonePlace
        end
    end
    return zone.places[1]
end

local composeDropZoneLines
do
    local MAX_OPEN_DROP_ZONES = 4 -- zones listed before the rest fold away
    local MAX_ZONE_CREATURES = 2 -- creatures listed in a zone before "+ N more here"

    ---A quiet link that opens or folds a part of a drop list.
    ---@return table line
    local function composeFoldLine(link, key, afterText, spaceBefore, indent)
        return {
            link = link,
            afterText = afterText,
            handleClick = toggleDropFold,
            data = key,
            isQuiet = true,
            spaceBefore = spaceBefore,
            indent = indent,
        }
    end

    ---The one zone an item drops in, to click: "in <zone> x, y", or the dungeon it is inside.
    ---@return table line
    local function composeOneZoneLine(zone, data, handleClick)
        local place = data.place
        return {
            text = place and place.dungeonName and ns.L("Inside %s, entrance in", place.dungeonName) or ns.L("in"),
            link = zone.name .. (place and place.x >= 0 and string.format(" %d, %d", place.x, place.y) or ""),
            handleClick = handleClick,
            data = data,
        }
    end

    ---The line over several zones: how many creatures it drops from, in how many zones.
    ---@return table line
    local function composeDropHeading(zones, getSources)
        local creatureNames, creatureCount = {}, 0
        for _, zone in ipairs(zones) do
            for _, source in ipairs(getSources(zone)) do
                if not creatureNames[source.name] then
                    creatureNames[source.name], creatureCount = true, creatureCount + 1
                end
            end
        end
        return {
            text = creatureCount > 0 and ns.Lp(
                creatureCount,
                "Drops from %d creature in %d zones",
                "Drops from %d creatures in %d zones",
                #zones
            ) or ns.Lp(#zones, "In %d zone", "In %d zones"),
        }
    end

    ---@return string[] facts A zone's levels, and whether the player is there, the map shows it, or it is a dungeon
    local function composeZoneFacts(zone, shownZoneId)
        local facts = {}
        if zone.minLevel then
            facts[#facts + 1] = zone.minLevel == zone.maxLevel and ns.L("level %d", zone.minLevel)
                or ns.L("levels %d-%d", zone.minLevel, zone.maxLevel)
        end
        if zone.isPlayerZone then
            facts[#facts + 1] = ns.L("you are here")
        elseif zone.zoneId == shownZoneId then
            facts[#facts + 1] = ns.L("on the map")
        elseif zone.isDungeon then
            facts[#facts + 1] = ns.L("dungeon")
        end
        return facts
    end

    ---The zones past the first few, folded into one line that names them.
    ---@return table line
    local function composeMoreZonesLine(fittingZones, firstIndex, moreKey)
        local names = {}
        for restIndex = firstIndex, #fittingZones do
            names[#names + 1] = fittingZones[restIndex].name
        end
        local count = #fittingZones - MAX_OPEN_DROP_ZONES
        return composeFoldLine(ns.Lp(count, "+ %d more zone", "+ %d more zones"), moreKey, table.concat(names, ", "), 5)
    end

    ---Where an item drops, as lines for addStepLine. In one zone: each creature with its chance behind a dot in
    ---the colour of its spawn points on the map, then the zone to click. In several: zone by zone, in the order
    ---worth going (Drops.getZones), each zone a link with its levels, its likeliest creatures under it; the
    ---rest of the zones, and the zones for much higher levels, folded into a line each.
    ---@param zones DropZone[]
    ---@param foldKey string Names this list's folds, so each quest's stay as left
    ---@param options { handleClick: function, quest: table?, questId: number?, objectiveShade: number?, isByCreature: boolean? }
    ---@return table[] lines
    function composeDropZoneLines(zones, foldKey, options)
        local lines = {}
        local isByCreature = options.isByCreature ~= false
        -- (Spoilers: with names only, no chances; with "found", only the creatures that dropped it for the player; a
        -- rough area, no spots; objectives found or hidden, no zones at all)
        local view = options.view
        local function getSources(zone)
            return view and Spoiled.keepSources(zone.sources, view, options.itemId) or zone.sources
        end
        local function getDotColor(source)
            if view and view.drops ~= "names" and view.drops ~= "chances" then
                return nil -- (the map colours a creature's places only where drops are named: no square to match)
            end
            return ns.MapMarks.getShadeColor(
                isByCreature and source.shade or options.objectiveShade,
                options.questId or (options.quest and options.quest.questId)
            )
        end
        local function getClickData(zone)
            -- (a rough area: the map turns to the zone, not to a spot in it)
            return {
                zone = zone,
                place = not (view and view.isRough) and getDropZonePlace(zone) or nil,
                quest = options.quest,
                questId = options.questId,
            }
        end
        local function formatSource(source)
            return source.name
                .. (
                    source.chance
                        and not (view and view.isChanceHidden)
                        and (DOT .. ns.Drops.formatChance(source.chance))
                    or ""
                )
        end
        local function addCreatures(zone, indent, firstPrefix)
            local zoneKey = foldKey .. ":" .. zone.zoneId
            local isOpen = dropFolds[zoneKey]
            local sources = getSources(zone)
            for index, source in ipairs(sources) do
                if index > MAX_ZONE_CREATURES and not isOpen then
                    lines[#lines + 1] = composeFoldLine(
                        ns.Lp(#sources - MAX_ZONE_CREATURES, "+ %d more here", "+ %d more here"),
                        zoneKey,
                        nil,
                        nil,
                        indent + 14
                    )
                    return
                end
                -- The first creature after its lead ("Drops from %s"), the next ones after "or"
                local text = firstPrefix and ns.L(index == 1 and firstPrefix or "or %s", formatSource(source))
                    or formatSource(source)
                lines[#lines + 1] = { text = text, dotColor = getDotColor(source), indent = indent }
            end
            if isOpen then
                lines[#lines + 1] = composeFoldLine(ns.L("Show fewer"), zoneKey, nil, nil, indent + 14)
            end
        end

        if #zones == 1 then
            addCreatures(zones[1], 0, "Drops from %s")
            if not (view and view.areZonesHidden) then
                lines[#lines + 1] = composeOneZoneLine(zones[1], getClickData(zones[1]), options.handleClick)
            end
            return lines
        end
        if view and view.areZonesHidden then
            return Spoiled.composeCreatureLines(zones, getSources, formatSource, getDotColor)
        end

        lines[1] = composeDropHeading(zones, getSources)
        local shownZoneId = ns.MapDock.getShownZoneId()
        local function addZone(zone)
            local facts = composeZoneFacts(zone, shownZoneId)
            lines[#lines + 1] = {
                link = zone.name,
                afterText = #facts > 0 and (DOT:gsub("^ ", "") .. table.concat(facts, DOT)) or nil,
                handleClick = options.handleClick,
                data = getClickData(zone),
                spaceBefore = 5,
            }
            addCreatures(zone, 10)
        end
        local fittingZones, highZones = {}, {}
        for _, zone in ipairs(zones) do
            table.insert(zone.isTooHigh and highZones or fittingZones, zone)
        end
        local moreKey, highKey = foldKey .. ":more", foldKey .. ":high"
        for index, zone in ipairs(fittingZones) do
            if index > MAX_OPEN_DROP_ZONES and not dropFolds[moreKey] then
                lines[#lines + 1] = composeMoreZonesLine(fittingZones, index, moreKey)
                break
            end
            addZone(zone)
        end
        if dropFolds[moreKey] then
            lines[#lines + 1] = composeFoldLine(ns.L("Show fewer zones"), moreKey, nil, 5)
        end
        if #highZones == 0 then
            return lines
        end
        if dropFolds[highKey] then
            for _, zone in ipairs(highZones) do
                addZone(zone)
            end
            lines[#lines + 1] = composeFoldLine(ns.L("Hide zones for higher levels"), highKey, nil, 5)
        else
            local lowest = highZones[1].minLevel
            lines[#lines + 1] = composeFoldLine(
                ns.Lp(#highZones, "+ %d zone for higher levels", "+ %d zones for higher levels"),
                highKey,
                lowest and ns.L("(levels %d+)", lowest) or nil,
                3
            )
        end
        return lines
    end
end

---Turns the map to where an objective is done, the place in the middle when the map is zoomed in, and
---remembers the zone: the map returns there whenever the quest is chosen later.
---@param target { questId: number, place: table?, zone: DropZone? }
local function showObjectivePlace(target)
    local place = target.place
    local zoneId = target.zone and target.zone.zoneId or place and (place.mapZoneId or place.groupZoneId)
    if not zoneId then
        return
    end
    ns.settings.cycledQuestZones[target.questId] = zoneId
    ns.MapDock.showQuestPlace(place and (place.mapZoneId or place.groupZoneId) or zoneId, place)
end

-- What the Spoilers choices let the To do list tell of where things are (Spoiled.view, composed with the page)

---@return table[] sources The creatures (and objects) that drop an item that may be named: all of them with names or
---chances; with "found", those that dropped it for the player; none when hidden
function Spoiled.keepSources(sources, view, itemId)
    if view.drops == "names" or view.drops == "chances" or not view.drops then
        return sources
    end
    local kept = {}
    for _, source in ipairs(view.drops == "found" and itemId and sources or {}) do
        if ns.Spoilers.hasSeenDrop(itemId, source.npcId or source.objectId) then
            kept[#kept + 1] = source
        end
    end
    return kept
end

---@return string? text An objective's source in words ("Drops from ..."), as the drops choice lets it be told; how
---a crafted item is made is no spoiler and stays
function Spoiled.keepSourceText(detail, view)
    if detail.isCrafted or not detail.sourceText or view.drops == "names" or view.drops == "chances" then
        return detail.sourceText
    end
    if view.drops == "found" and detail.itemId and ns.Spoilers.hasSeenDrop(detail.itemId) then
        return detail.sourceText
    end
    return nil
end

local MAX_NAMED_CREATURES = 4

---The creatures an item drops from, each once, with no zones: for objectives whose places are held back.
---@return table[] lines
function Spoiled.composeCreatureLines(zones, getSources, formatSource, getDotColor)
    local lines, isNamed, count = {}, {}, 0
    for _, zone in ipairs(zones) do
        for _, source in ipairs(getSources(zone)) do
            if not isNamed[source.name] then
                isNamed[source.name], count = true, count + 1
                if count <= MAX_NAMED_CREATURES then
                    lines[#lines + 1] = {
                        text = ns.L(count == 1 and "Drops from %s" or "or %s", formatSource(source)),
                        dotColor = getDotColor(source),
                    }
                end
            end
        end
    end
    if count > MAX_NAMED_CREATURES then
        local last = lines[#lines]
        last.text = last.text .. ns.Lp(count - MAX_NAMED_CREATURES, " and %d more", " and %d more")
    end
    return lines
end

---A zone named without a spot in it, as a link that turns the map to the zone: a rough area.
---@return table line
function Spoiled.composeZoneLine(questId, zoneId, prefix)
    return {
        text = prefix,
        link = ns.Database.getZoneName(zoneId) or ns.L("Unknown location"),
        handleClick = showObjectivePlace,
        data = { questId = questId, zone = { zoneId = zoneId } },
    }
end

local MAX_FOUND_PLACES = 3 -- the places found listed under an objective, the newest first

---@return table[] lines Where the player saw an objective move on, newest first, each a place to click; or the
---words saying they have not found any yet
function Spoiled.composeFoundLines(questId, objectiveIndex)
    local found = ns.Spoilers.getFoundPlaces(questId, objectiveIndex)
    if #found == 0 then
        return { ns.L("You have not found any yet") }
    end
    local lines = {}
    for index = #found, math.max(#found - MAX_FOUND_PLACES + 1, 1), -1 do
        local spot = found[index]
        local place = {
            mapZoneId = spot.zoneId,
            groupZoneId = spot.zoneId,
            x = math.floor(spot.x + 0.5),
            y = math.floor(spot.y + 0.5),
        }
        lines[#lines + 1] = composePlaceLine(place, {
            suffix = ns.L("found by you"),
            handleClick = showObjectivePlace,
            data = { questId = questId, place = place },
        })
    end
    if #found > MAX_FOUND_PLACES then
        lines[#lines + 1] = ns.Lp(#found - MAX_FOUND_PLACES, "and %d more place", "and %d more places")
    end
    return lines
end

---Where an objective is, as the objectives choice lets it be told: exactly (as in Guide), its zone alone (rough),
---the places the player found (found), or nothing but its source; a hint's first step adds the zone.
---@param zoneId number? The zone of the objective's places, when known
---@param exactLine table? The place as Guide tells it, for "exact"
---@return table lines For addLine: texts and lines, each under the objective
function Spoiled.composeWhere(view, questId, objectiveIndex, sourceText, zoneId, exactLine)
    if view.objectives == "exact" then
        return { exactLine or sourceText }
    end
    local lines = {}
    if view.objectives == "rough" and zoneId then
        lines[1] =
            Spoiled.composeZoneLine(questId, zoneId, sourceText and (sourceText .. DOT:gsub(" $", "")) or ns.L("in"))
        return lines
    end
    lines[1] = sourceText
    if view.objectives == "found" then
        for _, line in ipairs(Spoiled.composeFoundLines(questId, objectiveIndex)) do
            lines[#lines + 1] = line
        end
    end
    if zoneId and view.hint >= ns.Spoilers.HINT_ZONE then
        lines[#lines + 1] = Spoiled.composeZoneLine(questId, zoneId, ns.L("Somewhere in"))
    end
    return lines
end

-- The page's To do list: each objective with where it is done, the event to wait for, the turn-in.
local addToDo
do
    local TEXT_LEFT = PADDING + TO_DO_LEAD -- the list's text, after its checkboxes
    local EARLIER_COLOR, LUCKY_COLOR, UNLUCKY_COLOR, TO_GO_COLOR =
        { 0.62, 0.55, 0.4 }, { 0.25, 0.62, 0.25 }, { 0.75, 0.25, 0.16 }, { 0.42, 0.36, 0.25 }

    local function getTextWidth()
        return State.detail.width - 2 * PADDING - TO_DO_LEAD
    end

    ---One line under a to-do, in small print: a text, or a line for addStepLine (a place to click).
    ---@return number y Below it
    local function addWhereLine(y, line)
        if type(line) == "table" then
            line.font = "GameFontHighlightSmall"
            return y + addStepLine(y, line, TEXT_LEFT, getTextWidth()) + 2
        elseif line and line ~= "" then
            return y
                + State.detail:addText(
                    line,
                    TEXT_LEFT,
                    y,
                    { font = "GameFontHighlightSmall", color = COLORS.softInk, width = getTextWidth() }
                )
                + 2
        end
        return y
    end

    ---A to-do's line, and under it where it is done.
    ---@param where string|table? Under the line: a text, or a line for addStepLine, such as a place to click; or a list
    ---of those, one under the other
    ---@return number y Below them
    local function addLine(y, text, color, where)
        local height =
            State.detail:addText(text, TEXT_LEFT, y, { font = "QuestFont", color = color, width = getTextWidth() })
        y = y + height + 2
        if type(where) == "table" and where.text == nil and where.link == nil then
            for _, line in ipairs(where) do -- (a list: its texts and lines, in order)
                y = addWhereLine(y, line)
            end
        else
            y = addWhereLine(y, where)
        end
        return y + 6
    end

    ---@return string text Under a kill bar: the kills, the drops collected before counting began, who shares the
    ---loot, the kills still to go
    local function composeKillText(progress, textColor)
        local parts = { ns.KillCounter.formatKills(progress, DOT) }
        if (progress.earlierDrops or 0) > 0 then
            parts[#parts + 1] = ns.Lp(progress.earlierDrops, "%d collected earlier", "%d collected earlier")
        end
        if (progress.sharerCount or 1) > 1 then
            -- The drops go round between those who need them: the kills to go are for a turn of theirs each
            parts[#parts + 1] = ns.L("loot shared by %d", progress.sharerCount)
        end
        if progress.remaining >= 0.5 then
            parts[#parts + 1] = ns.Profit.formatEstimateSign(textColor)
                .. " "
                .. ns.Lp(math.floor(progress.remaining + 0.5), "%d kill to go", "%d kills to go")
        end
        return table.concat(parts, DOT)
    end

    ---Kills for a dropped item: a bar the kills fill, a gold line where an average player would be for the drops
    ---got, and a faint part for what is still to come.
    ---@return number y Below the bar and its words
    local function addKillBar(y, progress)
        local earlierKills = progress.earlierKills or 0
        local total = earlierKills + math.max(progress.expected, progress.kills) + progress.remaining
        if total <= 0 then
            return y
        end
        local top, height = y - 4, 13
        local isUnlucky = progress.isUnlucky
        -- Drops collected before counting began: a muted start, as long as their kills would be on average; then
        -- the kills, and the kills still to go
        local innerLeft, innerTop, inner, innerHeight =
            State.detail:addStatBar(TEXT_LEFT, top, getTextWidth(), height, {
                { share = earlierKills / total, color = EARLIER_COLOR },
                { share = progress.kills / total, color = isUnlucky and UNLUCKY_COLOR or LUCKY_COLOR },
                { share = progress.remaining / total, color = TO_GO_COLOR },
            })
        if (progress.drops or 0) > 0 then
            -- Where an average player would be for the drops got
            local mark = State.detail:addImage(
                innerLeft + inner * (earlierKills + progress.expected) / total - 1,
                innerTop - 2,
                2,
                innerHeight + 4,
                "Interface\\Buttons\\WHITE8X8",
                nil,
                nil,
                3
            )
            mark:SetVertexColor(COLORS.gold[1], COLORS.gold[2], COLORS.gold[3])
        end
        local textColor = isUnlucky and COLORS.warning or COLORS.softInk
        local textHeight = State.detail:addText(
            composeKillText(progress, textColor),
            TEXT_LEFT,
            top + height + 2,
            { font = "GameFontHighlightSmall", color = textColor, width = getTextWidth() }
        )
        return top + height + 4 + (type(textHeight) == "number" and textHeight or 12) + 2
    end

    ---An item that drops: each creature with its chance, behind a dot in the colour of its spawn points on the
    ---map, then the place, to click to turn the map there.
    ---@param shading { shades: table, sourceIndex: number? } The objectives' colours on the map
    ---@return number y Below the lines
    local function addSourceLines(y, entry, objectiveIndex, objectiveDetail, shading)
        local view = Spoiled.view
        local lines = composeDropZoneLines(objectiveDetail.zones, "log:" .. entry.questId .. ":" .. objectiveIndex, {
            handleClick = showObjectivePlace,
            questId = entry.questId,
            isByCreature = objectiveIndex == shading.sourceIndex,
            objectiveShade = shading.shades[objectiveIndex],
            view = view,
            itemId = objectiveDetail.itemId,
        })
        if view and view.objectives ~= "exact" and view.objectives ~= "rough" then
            -- (the creatures' zones held back: the places found, or the zone a hint gave)
            local place = objectiveDetail.place
            for _, line in
                ipairs(
                    Spoiled.composeWhere(
                        view,
                        entry.questId,
                        objectiveIndex,
                        nil,
                        place and (place.mapZoneId or place.groupZoneId)
                    )
                )
            do
                lines[#lines + 1] = type(line) == "table" and line or { text = line }
            end
        end
        for _, line in ipairs(lines) do
            line.font = "GameFontHighlightSmall"
            y = y + addStepLine(y, line, TEXT_LEFT, getTextWidth()) + 3
        end
        return y + 6
    end

    ---Where an objective that is not an item that drops is done (those list their creatures by zone): what it is
    ---and where, as the Spoilers choice lets it be told.
    ---@return string|table|nil where For addLine
    ---@return table? unplacedDetail The objective's detail when nothing can be marked on the map
    local function composeObjectiveWhere(entry, objectiveIndex, objectiveDetail)
        local place = objectiveDetail.place
        if not place then
            -- Nothing to mark on the map: what can be done instead, and the quest's own words on hover
            return QuestPage.composeWaysToGet(objectiveDetail), objectiveDetail
        end
        local view = Spoiled.view
        local sourceText = objectiveDetail.sourceText
        local where = (not view or view.objectives == "exact")
                and composePlaceLine(place, {
                    prefix = sourceText and (sourceText .. DOT:gsub(" $", "")) or nil,
                    handleClick = showObjectivePlace,
                    data = { questId = entry.questId, place = place },
                })
            or nil
        if view then
            where = Spoiled.composeWhere(
                view,
                entry.questId,
                objectiveIndex,
                sourceText,
                place.mapZoneId or place.groupZoneId,
                where
            )
        end
        return where
    end

    ---A count reads inside the line, as the game writes it: "4/10 Syndicate Footpad slain".
    ---@return string label
    local function formatObjectiveLabel(objective)
        local label = (objective.shownLabel or objective.label)
        if objective.required <= 1 then
            return label
        end
        local count = objective.fulfilled .. "/" .. objective.required
        return objective.isFinished and (count .. " " .. label) or ("|cff6a3d00" .. count .. "|r " .. label)
    end

    ---One objective: the game's own checkbox, ticked in gold once it is done; its line, where it is done, and the
    ---kills it took so far.
    ---@return number y Below it
    local function addObjective(y, entry, objectiveIndex, objectiveDetail, shading)
        local objective = objectiveDetail.objective
        local color = objective.isFinished and COLORS.softInk or COLORS.ink
        State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_IMAGE)
        if objective.isFinished then
            State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_TICK, nil, 1)
        end
        local label = formatObjectiveLabel(objective)
        if not objective.isFinished and objectiveDetail.zones ~= nil then
            local height =
                State.detail:addText(label, TEXT_LEFT, y, { font = "QuestFont", color = color, width = getTextWidth() })
            y = addSourceLines(y + height + 2, entry, objectiveIndex, objectiveDetail, shading)
        else
            local where, unplacedDetail
            if not objective.isFinished then
                where, unplacedDetail = composeObjectiveWhere(entry, objectiveIndex, objectiveDetail)
            end
            local top = y
            y = addLine(y, label, color, where)
            if unplacedDetail then
                -- Pointed at, the objective shows what the quest itself says, as the game's tooltip
                State.detail:addButton(
                    TEXT_LEFT - TO_DO_LEAD,
                    top - 2,
                    getTextWidth() + TO_DO_LEAD,
                    math.max(y - top - 4, 14),
                    nil,
                    { questId = entry.questId, title = entry.title, label = objective.label },
                    QuestPage.showQuestWords
                )
            end
        end
        local progress = ns.settings.shouldCountKills
            and not objective.isFinished
            and objective.type == "item"
            and ns.KillCounter.getProgress(entry.questId, objectiveIndex, objective)
        if progress then
            y = addKillBar(y, progress)
        end
        return y
    end

    ---No objectives: what the quest asks (waiting, talking) is the one thing to do, at its NPC.
    ---@return number y Below it, unchanged for a quest with objectives
    local function addEventLine(y, entry)
        if not entry.eventText or entry.isTurnIn then
            return y
        end
        State.detail:addIcon(PADDING - 2, y - 2, CHECKBOX_SIZE, CHECKBOX_IMAGE)
        local _, _, eventPlace = ns.Geometry.getNearest(
            ns.Location.getFinisherPlaces(entry.questId),
            ns.Geometry.getPlayerPosition(),
            ns.Database.getUiMapId
        )
        local view = Spoiled.view
        if view and not view.isTurnInShown then
            eventPlace = nil -- (where it happens is the turn-in's place, held back)
        end
        local happensAt = entry.finisherName and ns.L("Happens at %s", entry.finisherName)
            or ns.L("Happens at the quest giver")
        return addLine(
            y,
            entry.eventText,
            COLORS.ink,
            eventPlace and composePlaceLine(eventPlace, { prefix = happensAt .. "," }) or happensAt
        )
    end

    ---The turn-in closes the list: the last thing to do, or the only one left.
    ---@return number y Below it
    local function addTurnInLine(y, entry)
        local finisherPlaces = ns.Location.getFinisherPlaces(entry.questId)
        local _, _, finisherPlace =
            ns.Geometry.getNearest(finisherPlaces, ns.Geometry.getPlayerPosition(), ns.Database.getUiMapId)
        finisherPlace = finisherPlace or finisherPlaces[1]
        -- The map's turn-in mark: the game's "?", grey until the quest is ready, as the map shows it then
        State.detail:addMark(
            PADDING - 1,
            y - 1,
            18,
            { kind = "turnIn", questId = entry.questId, isFocused = false, lines = {}, isPending = not entry.isTurnIn }
        )
        local view = Spoiled.view
        local turnInWhere = finisherPlace and composePlaceLine(finisherPlace) or nil
        if view and view.turnIn == "met" and view.isTurnInShown and finisherPlace then
            turnInWhere = composePlaceLine(finisherPlace, { suffix = ns.L("you have met them") })
        elseif view and not view.isTurnInShown then
            -- Held back: the name alone (the game's own words say it too); "once you met them" says they are not met yet
            turnInWhere = view.turnIn == "met" and ns.L("Not met yet") or nil
        end
        return addLine(
            y,
            entry.finisherName and ns.L("Turn in to %s", entry.finisherName) or ns.L("Turn in to the quest giver"),
            entry.isTurnIn and COLORS.darkGreen or COLORS.ink,
            turnInWhere
        )
    end

    ---Ready to hand in: what the drops took, each counted objective's item with its bar and kills against the kills
    ---an average player would have needed.
    ---@return number y Below them
    local function addTurnInKillBars(y, entry)
        for objectiveIndex, objective in
            ipairs(entry.isTurnIn and ns.settings.shouldCountKills and entry.objectives or {})
        do
            local progress = objective.type == "item"
                and ns.KillCounter.getProgress(entry.questId, objectiveIndex, objective)
            if progress and progress.kills > 0 then
                y = y
                    + 2
                    + State.detail:addText((objective.shownLabel or objective.label), TEXT_LEFT, y, {
                        font = "GameFontHighlightSmall",
                        color = COLORS.softInk,
                        width = getTextWidth(),
                        isSingleLine = true,
                    })
                y = addKillBar(y + 4, progress)
            end
        end
        return y
    end

    ---The other zones the quest leads to; under the mouse every zone, a click turns the map to the next of them.
    ---@return number y Below them
    local function addOtherZones(y, entry)
        local view = Spoiled.view
        if not entry.otherZonesText or (view and view.areZonesHidden) then
            return y
        end
        local top = y
        y = addBody(y, ns.Widgets.formatMoreZones(entry.otherZonesText, "6a3d00"), COLORS.softInk)
        if entry.zoneIds then
            State.detail:addButton(
                PADDING - 4,
                top - 2,
                State.detail.width - 2 * PADDING + 8,
                y - top,
                handleZonesClick,
                entry,
                showZonesTooltip
            )
        end
        return y
    end

    ---What is left to do, counts first, each line with where it is done, ending with the turn-in.
    ---@return number y Below the list
    function addToDo(y, entry, details)
        y = addHeading(y, ns.L("To do"))
        local view = Spoiled.view
        local shades, _, sourceObjectiveIndex = ns.MapMarks.getObjectiveShades(entry)
        local shading = { shades = shades, sourceIndex = sourceObjectiveIndex }
        -- Done objectives left out as the tracker leaves them out, when the player chose that: the page and the
        -- tracker list the same steps. Each keeps its own number, which its colour on the map goes by.
        if view then
            for _, objectiveDetail in ipairs(details) do
                objectiveDetail.sourceText = Spoiled.keepSourceText(objectiveDetail, view)
            end
        end
        local shownIndexes = {}
        for index, objectiveDetail in ipairs(entry.isTurnIn and {} or details) do
            if not (ns.settings.shouldHideDoneObjectives and objectiveDetail.objective.isFinished) then
                shownIndexes[#shownIndexes + 1] = index
            end
        end
        for _, objectiveIndex in ipairs(shownIndexes) do
            y = addObjective(y, entry, objectiveIndex, details[objectiveIndex], shading)
        end
        y = addEventLine(y, entry)
        y = addTurnInLine(y, entry)
        y = addTurnInKillBars(y, entry)
        y = addOtherZones(y, entry)
        return y + 10
    end
end

-- Shared with the other parts of the window
QuestPage.addToDo = addToDo
QuestPage.composeDropZoneLines = composeDropZoneLines
QuestPage.composeObjectiveDetails = composeObjectiveDetails
