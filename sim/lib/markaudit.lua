-- Measures what a player sees of the marks on the world map or the minimap, from what is drawn, in the order it
-- is drawn: each pin (all its pieces) is one unit, sorted by who drew it and what it is: our marks, our spawn
-- squares, party members, the player, other addons' pins, the game's. Then it counts the units that overlap,
-- by kind, and how much of each party member (and the player) is covered by something drawn over it.
local sim = require("sim")
local W = require("widgets")
local scene = require("scene")

local markaudit = {}
local G, S = sim.G, W.state

local LAYER_RANK = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local MAX_UNIT_SIZE = 80 -- anything larger is a layer, a tile or a window, not a pin
local SEE_THROUGH_ALPHA = 0.3 -- a fill fainter than this leaves what is under it plain to see
local SPOT_SIZE = 6 -- our textures this small are spawn squares
local CROWDED_GAP = 3 -- a party member nearer than this to one of ours (and not under it) is crowded

local function intersect(first, second)
    local left, bottom = math.max(first[1], second[1]), math.max(first[2], second[2])
    local right, top = math.min(first[3], second[3]), math.min(first[4], second[4])
    if right - left > 0.5 and top - bottom > 0.5 then
        return { left, bottom, right, top }
    end
    return nil
end

local function union(first, second)
    if not first then
        return { second[1], second[2], second[3], second[4] }
    end
    return {
        math.min(first[1], second[1]),
        math.min(first[2], second[2]),
        math.max(first[3], second[3]),
        math.max(first[4], second[4]),
    }
end

local function getAlpha(object)
    local alpha = 1
    while object do
        local s = S[object]
        if not s then
            break
        end
        alpha = alpha * (s.alpha or 1)
        object = s.parent
    end
    return alpha
end

---The surface the marks are drawn on, and the area of the screen that shows it.
local function getSurface(view)
    if view == "minimap" then
        local minimap = G.Minimap
        local rect = minimap and minimap:IsVisible() and W.computeRect(minimap)
        if not rect then
            return nil
        end
        return { frame = minimap, rect = rect, isRound = true }
    end
    local map = G.WorldMapFrame
    local container = map and map:IsVisible() and map.ScrollContainer
    local rect = container and W.computeRect(container)
    if not rect then
        return nil
    end
    return { frame = container.Child, rect = rect }
end

local function isInside(surface, rect)
    local x, y = (rect[1] + rect[3]) / 2, (rect[2] + rect[4]) / 2
    local area = surface.rect
    if surface.isRound then
        local radius = (area[3] - area[1]) / 2
        local centerX, centerY = (area[1] + area[3]) / 2, (area[2] + area[4]) / 2
        return (x - centerX) ^ 2 + (y - centerY) ^ 2 <= radius * radius
    end
    return x >= area[1] and x <= area[3] and y >= area[2] and y <= area[4]
end

local function isUnder(frame, ancestor)
    while frame do
        if frame == ancestor then
            return true
        end
        frame = S[frame] and S[frame].parent
    end
    return false
end

---The pin a piece belongs to: the highest small frame above it that still holds it.
local function findUnitRoot(region, surface)
    local root = region
    local parent = S[region].parent
    local regionRect = W.computeRect(region)
    while parent and parent ~= surface.frame and parent ~= G.UIParent do
        local rect = W.computeRect(parent)
        if
            not rect
            or rect[3] - rect[1] > MAX_UNIT_SIZE
            or rect[4] - rect[2] > MAX_UNIT_SIZE
            or not intersect(rect, regionRect)
        then
            break
        end
        root = parent
        parent = S[parent].parent
    end
    return root
end

local function classify(root, region)
    local role = S[region].markRole or S[root].markRole
    if role then
        return role
    end
    local creator = S[root].creator or S[region].creator
    if creator == "OneMoreQuest" then
        -- A hollow ring drawn round someone covers nothing
        local texture = type(S[region].texture) == "string" and S[region].texture or ""
        if texture:find("AreaRing", 1, true) then
            return "our ring"
        end
        -- Icons and areas: an icon of what to do, its soft glow, and the areas' fill and edge
        if
            (texture:find("Glyph", 1, true) or texture:find("Cursor", 1, true) or texture:find("Media\\Icon", 1, true))
            and root == region
        then
            return "our icon"
        end
        if texture:find("SoftDot", 1, true) and root == region then
            return "our glow"
        end
        if root == region then
            local rect = W.computeRect(region)
            local layerRect = S[region].parent and W.computeRect(S[region].parent)
            local isOnBigLayer = layerRect and (layerRect[3] - layerRect[1] > MAX_UNIT_SIZE)
            if rect and not isOnBigLayer and rect[3] - rect[1] <= SPOT_SIZE and rect[4] - rect[2] <= SPOT_SIZE then
                return "our spot"
            end
            return "our area"
        end
        return "our mark"
    end
    if creator and not creator:match("^Blizzard_") then
        return "other addon"
    end
    return "game"
end

---Everything drawn on the surface that is the size of a pin, as units in drawing order.
---@param view "map"|"minimap"
---@return table[]? units { kind, rect, order, root, label }
function markaudit.collect(view)
    local surface = getSurface(view)
    if not surface then
        return nil
    end
    local units, byRoot, order = {}, {}, 0
    for _, frame in ipairs(scene.getSortedFrames()) do
        local fs = S[frame]
        if isUnder(frame, surface.frame) and getAlpha(frame) > 0.05 then
            local regions = {}
            for _, region in ipairs(fs.regions) do
                local rs = S[region]
                if rs and rs.shown and rs.parent == frame and rs.type ~= "MaskTexture" and rs.type ~= "FontString" then
                    regions[#regions + 1] = region
                end
            end
            table.sort(regions, function(first, second)
                local a, b = S[first], S[second]
                local layerA, layerB = LAYER_RANK[a.layer or "ARTWORK"] or 3, LAYER_RANK[b.layer or "ARTWORK"] or 3
                if layerA ~= layerB then
                    return layerA < layerB
                end
                if (a.sublevel or 0) ~= (b.sublevel or 0) then
                    return (a.sublevel or 0) < (b.sublevel or 0)
                end
                return a.id < b.id
            end)
            for _, region in ipairs(regions) do
                order = order + 1
                local rect = W.computeRect(region)
                local alpha = getAlpha(region)
                if
                    rect
                    and alpha > 0.05
                    and rect[3] - rect[1] <= MAX_UNIT_SIZE
                    and rect[4] - rect[2] <= MAX_UNIT_SIZE
                    and rect[3] - rect[1] > 0.5
                    and isInside(surface, rect)
                    and intersect(rect, surface.rect)
                then
                    local root = findUnitRoot(region, surface)
                    local unit = byRoot[root]
                    if not unit then
                        unit = { root = root, kind = classify(root, region), order = order, alpha = alpha }
                        byRoot[root] = unit
                        units[#units + 1] = unit
                    end
                    -- A line covers only where it runs, not its whole box; a fill this faint is seen through
                    if S[region].type == "Line" and root == region then
                        local x1, y1, x2, y2 = W.getLineEnds(region)
                        if x1 then
                            unit.segment = {
                                x1 = x1,
                                y1 = y1,
                                x2 = x2,
                                y2 = y2,
                                half = (S[region].thickness or 1) * W.getEffectiveScale(region) / 2,
                            }
                        end
                    end
                    local color = S[region].color
                    if color and (color[4] or 1) * alpha < SEE_THROUGH_ALPHA and root == region then
                        unit.isSeeThrough = true
                    end
                    local inset = S[region].markInset
                    if inset then
                        local insetX, insetY = (rect[3] - rect[1]) * inset, (rect[4] - rect[2]) * inset
                        rect = { rect[1] + insetX, rect[2] + insetY, rect[3] - insetX, rect[4] - insetY }
                    end
                    unit.rect = union(unit.rect, rect)
                    unit.order = math.max(unit.order, order)
                    unit.alpha = math.max(unit.alpha, alpha)
                    if not unit.label then
                        local mark = root.mark
                        unit.label = (mark and mark.questId and ("quest " .. mark.questId))
                            or S[root].name
                            or S[region].atlas
                    end
                end
            end
        end
    end
    return units
end

---@return boolean isOn A point is on a unit: within a line's thickness of it, or inside anything else's box
local function isOnUnit(other, x, y)
    local segment = other.segment
    if segment then
        local dx, dy = segment.x2 - segment.x1, segment.y2 - segment.y1
        local length = dx * dx + dy * dy
        local t = length > 0 and math.max(0, math.min(1, ((x - segment.x1) * dx + (y - segment.y1) * dy) / length)) or 0
        local px, py = segment.x1 + dx * t, segment.y1 + dy * t
        return (x - px) ^ 2 + (y - py) ^ 2 <= (segment.half + 0.5) ^ 2
    end
    return x >= other.rect[1] and x <= other.rect[3] and y >= other.rect[2] and y <= other.rect[4]
end

---How much of a unit's area the units drawn after it cover (sampled on a grid).
local function getCoveredFraction(unit, units)
    local covered, samples = 0, 0
    local rect = unit.rect
    for column = 0, 4 do
        for row = 0, 4 do
            local x = rect[1] + (rect[3] - rect[1]) * (column + 0.5) / 5
            local y = rect[2] + (rect[4] - rect[2]) * (row + 0.5) / 5
            samples = samples + 1
            for _, other in ipairs(units) do
                if
                    other ~= unit
                    and other.order > unit.order
                    and other.kind ~= "party"
                    and other.kind ~= "player"
                    and other.kind ~= "our ring"
                    and other.kind ~= "our glow"
                    and not other.isSeeThrough
                    and isOnUnit(other, x, y)
                then
                    covered = covered + 1
                    break
                end
            end
        end
    end
    return covered / samples
end

---The overlaps on a surface, by the kinds of the two units, and what covers the party.
---@return table? report { counts = { [kind] = n }, overlaps = { ["a / b"] = n }, examples = { ["a / b"] = text },
---party = { { kind, label, covered, coveredBy, crowdedBy } } }
function markaudit.measure(view)
    local units = markaudit.collect(view)
    if not units then
        return nil
    end
    local report = { view = view, counts = {}, overlaps = {}, examples = {}, party = {} }
    for _, unit in ipairs(units) do
        report.counts[unit.kind] = (report.counts[unit.kind] or 0) + 1
    end
    for firstIndex = 1, #units do
        local first = units[firstIndex]
        for secondIndex = firstIndex + 1, #units do
            local second = units[secondIndex]
            if intersect(first.rect, second.rect) then
                local kinds = { first.kind, second.kind }
                table.sort(kinds)
                local key = kinds[1] .. " / " .. kinds[2]
                -- With another addon's pin, which is on top matters: ours under theirs is fine
                if (first.kind == "other addon") ~= (second.kind == "other addon") then
                    local theirs, ours =
                        first.kind == "other addon" and first or second, first.kind == "other addon" and second or first
                    if ours.order < theirs.order then
                        key = key .. " (ours under)"
                    end
                end
                report.overlaps[key] = (report.overlaps[key] or 0) + 1
                if not report.examples[key] then
                    report.examples[key] = string.format(
                        "%s and %s at %d, %d",
                        tostring(first.label),
                        tostring(second.label),
                        math.floor(first.rect[1]),
                        math.floor(sim.screenHeight - first.rect[4])
                    )
                end
            end
        end
    end
    for _, unit in ipairs(units) do
        if unit.kind == "party" or unit.kind == "player" then
            local entry = {
                kind = unit.kind,
                covered = getCoveredFraction(unit, units),
                coveredBy = {},
                crowdedBy = {},
                x = math.floor((unit.rect[1] + unit.rect[3]) / 2),
                y = math.floor(sim.screenHeight - (unit.rect[2] + unit.rect[4]) / 2),
            }
            for _, other in ipairs(units) do
                if other ~= unit and other.kind ~= "party" and other.kind ~= "player" and other.kind ~= "our ring" then
                    if other.order > unit.order and intersect(unit.rect, other.rect) then
                        entry.coveredBy[#entry.coveredBy + 1] = other.kind
                    elseif not intersect(unit.rect, other.rect) then
                        local gapX = math.max(other.rect[1] - unit.rect[3], unit.rect[1] - other.rect[3], 0)
                        local gapY = math.max(other.rect[2] - unit.rect[4], unit.rect[2] - other.rect[4], 0)
                        if math.max(gapX, gapY) < CROWDED_GAP then
                            entry.crowdedBy[#entry.crowdedBy + 1] = other.kind
                        end
                    elseif other.order < unit.order then
                        entry.crowdedBy[#entry.crowdedBy + 1] = other.kind .. " (under)"
                    end
                end
            end
            report.party[#report.party + 1] = entry
        end
    end
    return report
end

---The report as lines of text.
function markaudit.describe(report, title)
    local lines = { "== " .. (title or report.view) }
    local kinds = {}
    for kind, count in pairs(report.counts) do
        kinds[#kinds + 1] = kind .. " " .. count
    end
    table.sort(kinds)
    lines[#lines + 1] = "  drawn: " .. table.concat(kinds, ", ")
    local keys = {}
    for key in pairs(report.overlaps) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        lines[#lines + 1] =
            string.format("  overlap %-26s %4d   e.g. %s", key, report.overlaps[key], report.examples[key])
    end
    if #keys == 0 then
        lines[#lines + 1] = "  no overlaps"
    end
    for _, entry in ipairs(report.party) do
        local coveredBy, crowdedBy = {}, {}
        for _, kind in ipairs(entry.coveredBy) do
            coveredBy[kind] = (coveredBy[kind] or 0) + 1
        end
        for _, kind in ipairs(entry.crowdedBy) do
            crowdedBy[kind] = (crowdedBy[kind] or 0) + 1
        end
        local function list(counts)
            local parts = {}
            for kind, count in pairs(counts) do
                parts[#parts + 1] = kind .. " x" .. count
            end
            table.sort(parts)
            return #parts > 0 and table.concat(parts, ", ") or "nothing"
        end
        lines[#lines + 1] = string.format(
            "  %-6s at %4d, %3d: %3d%% covered (by %s); crowded by %s",
            entry.kind,
            entry.x,
            entry.y,
            math.floor(entry.covered * 100 + 0.5),
            list(coveredBy),
            list(crowdedBy)
        )
    end
    return table.concat(lines, "\n")
end

return markaudit
