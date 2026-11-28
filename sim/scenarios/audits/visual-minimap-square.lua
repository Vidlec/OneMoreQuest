-- The square minimap (Forever's own) draws its areas' fills on a canvas slid under the minimap, where a round one
-- places each triangle at every move. Both ways must draw the same picture: the same walk recorded with the canvas
-- (VISUAL_LABEL=canvas) and without (VISUAL_LABEL=nocanvas, which also sets CANVAS_OFF=1), then
--   bun sim/scenarios/audits/visual-diff.ts nocanvas canvas
-- Only what shows on the minimap is recorded: what its square cuts away entirely is left out, and places are
-- rounded to half a pixel (the two ways work them out by different sums).
local scene = require("scene")
local sim = require("sim")
local W = require("widgets")
local label = os.getenv("VISUAL_LABEL") or "run"
local folder = scenariosDir .. "/.visual/" .. label
sim.makeDirectory(scenariosDir .. "/.visual")
sim.makeDirectory(folder)
G.GetMinimapShape = function()
    return os.getenv("MINIMAP_SHAPE") or "SQUARE"
end

local function half(value)
    return string.format("%.1f", math.floor(value * 2 + 0.5) / 2)
end
local function whole(value)
    if os.getenv("RAW_LINES") == "1" then
        return string.format("%.3f", value)
    end
    return string.format("%d", math.floor(value + 0.5))
end
---@return number? x1, number? y1, number? x2, number? y2 The part of a line inside a box, or nil when none is
local function clipLine(x1, y1, x2, y2, left, top, right, bottom)
    local enter, leave = 0, 1
    local dx, dy = x2 - x1, y2 - y1
    for _, edge in ipairs({ { -dx, x1 - left }, { dx, right - x1 }, { -dy, y1 - top }, { dy, bottom - y1 } }) do
        local p, q = edge[1], edge[2]
        if p == 0 then
            if q < 0 then
                return nil
            end
        else
            local t = q / p
            if p < 0 then
                enter = math.max(enter, t)
            else
                leave = math.min(leave, t)
            end
        end
    end
    if enter >= leave then
        return nil
    end
    return x1 + dx * enter, y1 + dy * enter, x1 + dx * leave, y1 + dy * leave
end
local function canonical(value, depth)
    local kind = type(value)
    if kind == "number" then
        return half(value)
    elseif kind == "table" then
        if (depth or 0) > 4 then
            return "{...}"
        end
        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        local parts = {}
        for _, key in ipairs(keys) do
            if key ~= "i" and key ~= "cl" then
                parts[#parts + 1] = tostring(key) .. "=" .. canonical(value[key], (depth or 0) + 1)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

local function record(state)
    -- Placed for where the player stands at this very moment, whichever way the marks are placed (move by move
    -- they follow in half-pixel steps, a few times a second; on the canvas, every frame)
    require("addons").byName["onemorequest"].private.MinimapPins.move()
    local rect = W.computeRect(G.Minimap)
    local left, right = rect[1], rect[3]
    local top, bottom = sim.screenHeight - rect[4], sim.screenHeight - rect[2]
    local lines, kinds = {}, {}
    for _, item in ipairs(scene.export()) do
        -- What lies on the minimap, and is not cut away entirely by the frame that cuts it
        -- (a line is told by its two ends)
        local boxLeft, boxTop =
            item.x or math.min(item.x1 or 0, item.x2 or 0), item.y or math.min(item.y1 or 0, item.y2 or 0)
        local boxRight = item.x and item.x + (item.w or 0) or math.max(item.x1 or 0, item.x2 or 0)
        local boxBottom = item.y and item.y + (item.h or 0) or math.max(item.y1 or 0, item.y2 or 0)
        local isOnMinimap = boxRight > left and boxLeft < right and boxBottom > top and boxTop < bottom
        local isCutAway = item.cl
            and (
                boxRight <= item.cl[1]
                or boxLeft >= item.cl[1] + item.cl[3]
                or boxBottom <= item.cl[2]
                or boxTop >= item.cl[2] + item.cl[4]
            )
        if isOnMinimap and not isCutAway then
            -- A fill's triangle is told by its corners on screen, whichever way its box was worked out
            if item.poly then
                local corners, xs, ys = {}, {}, {}
                for index = 1, 8, 2 do
                    xs[#xs + 1], ys[#ys + 1] =
                        item.x + item.poly[index] * item.w, item.y + item.poly[index + 1] * item.h
                    corners[#corners + 1] = half(xs[#xs]) .. "," .. half(ys[#ys])
                end
                table.sort(corners)
                -- Only a triangle that really reaches into what cuts it (its box may, while it passes the corner by):
                -- no line along one of its sides has the whole of the cutting box on its far side
                local isShowing = true
                do -- (the minimap's own square: what cuts a fill on a square minimap, whichever way it was placed)
                    local boxX = { left, right, right, left }
                    local boxY = { top, top, bottom, bottom }
                    for index = 1, #xs do
                        local nextIndex = index % #xs + 1
                        local edgeX, edgeY = xs[nextIndex] - xs[index], ys[nextIndex] - ys[index]
                        if edgeX ~= 0 or edgeY ~= 0 then
                            local inside, outside = 0, 0 -- the triangle's own side of this edge, by its other corners
                            for other = 1, #xs do
                                local cross = edgeX * (ys[other] - ys[index]) - edgeY * (xs[other] - xs[index])
                                if cross > 1e-6 then
                                    inside = inside + 1
                                elseif cross < -1e-6 then
                                    outside = outside + 1
                                end
                            end
                            local sign = inside >= outside and 1 or -1
                            local isBoxBeyond = true
                            for corner = 1, 4 do
                                local cross = (edgeX * (boxY[corner] - ys[index]) - edgeY * (boxX[corner] - xs[index]))
                                    * sign
                                if cross > 0.5 then
                                    isBoxBeyond = false
                                end
                            end
                            if isBoxBeyond then
                                isShowing = false
                            end
                        end
                    end
                end
                if isShowing then
                    lines[#lines + 1] = "triangle "
                        .. table.concat(corners, " ")
                        .. " c="
                        .. canonical(item.c)
                        .. " a="
                        .. tostring(item.a)
                end
            elseif item.k == "ln" then
                -- A line is told by the part of it that shows: a pixel inside the edge of the frame that cuts it,
                -- as the lines cut in Lua end (the canvas's are cut by the frame alone); whichever end comes first
                local x1, y1, x2, y2 = item.x1, item.y1, item.x2, item.y2
                if item.cl then
                    x1, y1, x2, y2 = clipLine(
                        x1,
                        y1,
                        x2,
                        y2,
                        item.cl[1] + 1,
                        item.cl[2] + 1,
                        item.cl[1] + item.cl[3] - 1,
                        item.cl[2] + item.cl[4] - 1
                    )
                end
                if x1 and (x2 - x1) ^ 2 + (y2 - y1) ^ 2 > 1 then
                    if x1 > x2 or (x1 == x2 and y1 > y2) then
                        x1, y1, x2, y2 = x2, y2, x1, y1
                    end
                    lines[#lines + 1] = string.format(
                        "line %s,%s %s,%s th=%s c=%s a=%s",
                        whole(x1),
                        whole(y1),
                        whole(x2),
                        whole(y2),
                        half(item.th or 0),
                        canonical(item.c),
                        tostring(item.a)
                    )
                end
            else
                lines[#lines + 1] = canonical(item)
            end
            kinds[item.k] = (kinds[item.k] or 0) + 1
        end
    end
    table.sort(lines)
    local out = io.open(folder .. "/" .. state .. ".txt", "w")
    out:write(table.concat(lines, "\n"), "\n")
    out:close()
    io.write(
        "VISUAL ",
        state,
        ": ",
        #lines,
        " items on the minimap; icons laid out ",
        tostring(require("addons").byName["onemorequest"].private.MinimapPins.layoutCount),
        " times\n"
    )
end

setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29) -- Grom'gol Base Camp, Stranglethorn
local accepted = {}
for _, questId in ipairs({
    185,
    186,
    187,
    188,
    189,
    190,
    191,
    192,
    193,
    194,
    195,
    196,
    197,
    568,
    569,
    570,
    572,
    573,
    581,
    582,
}) do
    accept(questId)
    accepted[#accepted + 1] = questId
end
local addon = require("addons").byName["onemorequest"].private
addon.MinimapPins.isCanvasOff = os.getenv("CANVAS_OFF") == "1"
wait(3)
addon.MinimapPins.refresh()
wait(1)
record("m01-standing")
face(45)
hold("W", 2)
wait(0.3)
record("m02-walked-2s")
hold("W", 4)
wait(0.3)
record("m03-walked-6s")
addon.Focus.set(accepted[4])
wait(1.2)
record("m04-followed-a-quest")
zoomMinimap(2)
wait(1.2)
record("m05-zoomed-in")
hold("W", 3)
wait(0.3)
record("m06-walked-zoomed-in")
zoomMinimap(0)
wait(1.2)
record("m07-zoomed-out")
progress(accepted[1], 1, 1)
wait(1)
record("m08-a-kill-counted")
face(200)
hold("W", 5)
wait(0.3)
record("m09-walked-back")
if os.getenv("M09_AGAIN") == "1" then
    addon.MinimapPins.refresh()
    wait(0.2)
    record("m09b-chosen-again")
end
addon.Focus.set(nil)
wait(1.2)
record("m10-nothing-followed")
