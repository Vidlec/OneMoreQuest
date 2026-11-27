--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- Hovering a quest in the quest window's list, with the map open: what of the OTHER quests' drawing changes at all,
-- frame by frame (a piece hidden, faded, recoloured, given another picture, moved to another level). Only the
-- hovered quest's own pieces should change; anything else that does is a blink the player sees.
local W, sim = require("widgets"), require("sim")
local mapcost = require("mapcost")
local RIVER_MAP = 2548
setProfile({ level = 42, race = "Orc", class = "WARRIOR" })
moveTo(RIVER_MAP, 0.794, 0.527)
local accepted = mapcost.trackZoneQuests(accept, tonumber(mapcost.option("FLASH_QUESTS") or "8"))
local addon = require("addons").byName["onemorequest"].private
addon.Focus.set(accepted[1])
wait(2)
local map = G.WorldMapFrame
key("M")
wait(4)
addon.MapMarksWorld.finish(map)
wait(1)

-- Every region of ours on the map with how it looks: shown, its alpha through its frames, colour, picture, level
local function read()
    local seen = {}
    local function walk(frame, alpha, isShown)
        isShown = isShown and frame:IsShown()
        alpha = alpha * (frame:GetAlpha() or 1)
        local level = frame.GetFrameLevel and frame:GetFrameLevel() or 0
        for _, region in ipairs(W.state[frame].regions or {}) do
            local r, g, b, a = 1, 1, 1, 1
            if region.GetVertexColor then
                r, g, b, a = region:GetVertexColor()
            end
            local picture = region.GetTexture and tostring(region:GetTexture())
                or region.GetText and region:GetText()
                or ""
            seen[region] = string.format(
                "%s a%.2f c%.2f,%.2f,%.2f,%.2f L%d %s",
                (isShown and region:IsShown()) and "shown" or "hidden",
                alpha * (region:GetAlpha() or 1),
                r or 1,
                g or 1,
                b or 1,
                a or 1,
                level,
                picture
            )
        end
        for _, child in ipairs(W.state[frame].children or {}) do
            walk(child, alpha, isShown)
        end
    end
    for _, layer in ipairs(mapcost.getLayers(addon, map)) do
        walk(layer, 1, true)
    end
    return seen
end

local function watch(name, seconds, body)
    local before = read()
    local changes, total = {}, 0
    local tick = sim.tick
    local frame = 0
    sim.tick = function(elapsed)
        local a, b = tick(elapsed)
        frame = frame + 1
        local now = read()
        for region, was in pairs(before) do
            local is = now[region]
            if is ~= was and was:find("^shown") then
                local key = string.format("frame %d: %s  ->  %s", frame, was, tostring(is))
                changes[key] = (changes[key] or 0) + 1
                total = total + 1
            end
        end
        before = now
        return a, b
    end
    local isFine, problem = pcall(function()
        body()
        for _ = 1, math.floor(seconds / 0.016) do
            sim.tick(0.016)
        end
    end)
    sim.tick = tick
    if not isFine then
        error(problem, 0)
    end
    local lines = {}
    for key, count in pairs(changes) do
        lines[#lines + 1] = string.format("   x%-4d %s", count, key)
    end
    table.sort(lines)
    print(string.format("== %s: %d changes to pieces that were shown", name, total))
    for index = 1, math.min(#lines, 40) do
        print(lines[index])
    end
end

watch("nothing done (a second of frames)", 1, function() end)
watch("a quest hovered in the list", 1.2, function()
    hover(G.C_QuestLog.GetTitleForQuestID(accepted[3]))
end)
expect(addon.Log.getHoveredQuestId() == accepted[3], "the list's quest is hovered")
watch("another hovered", 1.2, function()
    hover(G.C_QuestLog.GetTitleForQuestID(accepted[4]))
end)
expect(addon.Log.getHoveredQuestId() == accepted[4], "the other quest is hovered")
watch("the hover gone", 1.2, function()
    require("scene").input({ type = "move", x = 5, y = 5 })
end)

-- What OneMoreQuest's code does to its pieces on the map during a hover, by method, a frame at a time: also what
-- leaves a piece as it was (hidden and shown again, its anchors cleared and set, its picture given again), which a
-- look at the pieces before and after cannot show, and which the game may still draw as a blink.
do
    local WATCHED = {
        "Hide",
        "Show",
        "SetShown",
        "SetAlpha",
        "SetScale",
        "SetParent",
        "ClearAllPoints",
        "SetPoint",
        "SetAllPoints",
        "SetFrameLevel",
        "SetFrameStrata",
        "SetTexture",
        "SetAtlas",
        "SetVertexColor",
        "SetDesaturated",
        "AddMaskTexture",
        "RemoveMaskTexture",
        "SetDrawLayer",
        "SetSize",
        "SetTexCoord",
        "SetVertexOffset",
        "SetRotation",
        "SetBlendMode",
        "SetText",
        "SetColorTexture",
    }
    local isOurs = {} -- every frame and region under our layers on the map
    local function mark(frame)
        isOurs[frame] = true
        for _, region in ipairs(W.state[frame].regions or {}) do
            isOurs[region] = true
        end
        for _, child in ipairs(W.state[frame].children or {}) do
            mark(child)
        end
    end
    for _, layer in ipairs(mapcost.getLayers(addon, map)) do
        mark(layer)
    end
    local calls, isOn = {}, false
    local tickNumber = 0
    -- (the layers everything hangs from, by name: a call on one of them is a call on all it holds)
    local roles = {}
    do
        local drawn, markLayer, areaLayer = addon.MapMarks.getDrawn(map)
        roles[markLayer or false], roles[areaLayer or false] = "the old marks' layer", "the old areas' layer"
        roles[drawn.pinLayer or false], roles[drawn.glowLayer or false] = "the marks' layer", "the glows' layer"
        for index, root in ipairs(addon.MapMarksWorld.getLayers(map)) do
            roles[root] = "the kept drawing's root " .. index
        end
    end
    for _, definition in pairs(W.types) do
        for _, name in ipairs(WATCHED) do
            local method = definition.methods[name]
            if type(method) == "function" then
                definition.methods[name] = function(self, ...)
                    if isOn and isOurs[self] then
                        local key = name .. " on " .. (roles[self] or "a piece")
                        if name == "Hide" or name == "Show" or name == "ClearAllPoints" or name == "SetShown" then
                            -- (who asked: the line of OneMoreQuest's code, and how much hangs from the piece)
                            local where = "?"
                            for level = 2, 8 do
                                local info = debug.getinfo(level, "Sl")
                                if info and info.source:find("OneMoreQuest", 1, true) then
                                    where = info.source:match("([%w_]+%.lua)$") .. ":" .. info.currentline
                                    break
                                end
                            end
                            local state = W.state[self]
                            local held = state and (#(state.children or {}) + #(state.regions or {})) or 0
                            key = key .. " @" .. where .. " holding " .. held .. " tick " .. tickNumber
                        end
                        calls[key] = (calls[key] or 0) + 1
                    end
                    return method(self, ...)
                end
            end
        end
    end
    local function watchCalls(name, seconds, body)
        calls, isOn = {}, true
        tickNumber = 0
        body()
        for _ = 1, math.floor(seconds / 0.016) do
            tickNumber = tickNumber + 1
            sim.tick(0.016)
        end
        isOn = false
        local parts = {}
        for method, count in pairs(calls) do
            parts[#parts + 1] = string.format("%s %d", method, count)
        end
        table.sort(parts)
        print("== calls on our pieces, " .. name .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "none"))
    end
    watchCalls("nothing done", 1, function() end)
    watchCalls("a quest hovered", 1.2, function()
        hover(G.C_QuestLog.GetTitleForQuestID(accepted[3]))
    end)
    watchCalls("the hover gone", 1.2, function()
        require("scene").input({ type = "move", x = 5, y = 5 })
    end)
    watchCalls("the marks drawn again, nothing changed", 1.2, function()
        addon.MapPins.refresh()
    end)
end

-- What a player's blink report showed (/omq blink): six of seven hovers changed which quests the kept drawing
-- shows (a quest that shows other places in focus than out of it, or shows only in focus), and each had every
-- quest's spawn marks sorted and laid out again, 266 tiles. The spawn marks are sorted by what the quests show out
-- of focus: a change that is only the quest in focus' leaves the sorting as it is.
do
    local World = addon.MapMarksWorld
    local world = World.worlds[map]
    local function copy(features)
        local list = {}
        for index, feature in ipairs(features) do
            list[index] = feature
        end
        return list
    end
    -- (world.stamp counts the times a space's spawn marks were sorted; the work is done before it is read)
    local function set(features)
        World.setFeatures(map, features)
        World.finish(map)
        wait(0.1)
        World.finish(map)
    end
    local base = addon.MapMarks.composeFeatures(false)
    set(copy(base))
    local stamp = world.stamp
    set(copy(base))
    expect(world.stamp == stamp, "the same quests given again sort nothing")
    set(addon.MapMarks.composeFeatures(false))
    expect(world.stamp == stamp, "nor the same quests composed anew")
    -- The third quest comes into focus and shows other places than it did (its item's creatures, each by itself)
    local changed = copy(base)
    local was = changed[3]
    local focused = {}
    for key, value in pairs(was) do
        focused[key] = value
    end
    focused.parts, focused.partList, focused.isRanked, focused.trails = nil, nil, nil, nil
    focused.isFocused, focused.contentKey, focused.steadyKey = true, was.contentKey .. "|in focus", was.contentKey
    changed[3] = focused
    set(changed)
    expect(world.stamp == stamp, "a quest showing other places in focus does not sort every quest's spawn marks again")
    -- A quest shown only while it is pointed at comes, and goes
    local withGuest = copy(base)
    local guest = {}
    for key, value in pairs(base[1]) do
        guest[key] = value
    end
    guest.key, guest.questId, guest.steadyKey, guest.isFocused = "quest:999999", 999999, false, true
    guest.parts, guest.partList, guest.isRanked, guest.trails = nil, nil, nil, nil
    withGuest[#withGuest + 1] = guest
    set(withGuest)
    expect(world.stamp == stamp, "nor does a quest that shows only while pointed at")
    set(copy(base))
    expect(world.stamp == stamp, "nor its going")
    -- What a quest shows out of focus changing (an objective done: other places) does sort them again
    local progressed = copy(base)
    local moved = {}
    for key, value in pairs(base[2]) do
        moved[key] = value
    end
    moved.contentKey, moved.steadyKey = base[2].contentKey .. "|fewer", base[2].contentKey .. "|fewer"
    moved.parts, moved.partList, moved.isRanked, moved.trails = nil, nil, nil, nil
    progressed[2] = moved
    -- (only the spaces it has spawns in: the others' marks stay as they stand)
    local own, sorted = 0, 0
    for _, space in ipairs(world.spaceList) do
        if space.index then
            sorted = sorted + 1
            local kept = world.featureByKey[base[2].key]
            local part = kept.parts and kept.parts[space.key]
            if part and part.points and #part.points > 0 then
                own = own + 1
            end
        end
    end
    set(progressed)
    print(
        string.format(
            "== spaces sorted: %d, with the changed quest's spawns: %d, sorted again: %d",
            sorted,
            own,
            world.stamp - stamp
        )
    )
    expect(
        own == 0 or world.stamp > stamp,
        "a quest showing other places out of focus sorts its spaces again, as it must"
    )
    expect(world.stamp - stamp <= own, "and only the spaces it has spawns in, each once")
    stamp = world.stamp
    -- The quests in another order: sorted again only where two of them share a space
    local swapped = copy(progressed)
    swapped[1], swapped[#swapped] = swapped[#swapped], swapped[1]
    set(swapped)
    print(string.format("== sorted again for another order: %d of %d", world.stamp - stamp, sorted))
    expect(world.stamp - stamp <= sorted, "another order sorts each space at most once")
    World.setFeatures(map, addon.MapMarks.composeFeatures(false))
    addon.MapPins.refresh()
    wait(1)
end
