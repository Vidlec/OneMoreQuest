-- The marks audit, shared by the zone files: a busy quest log in one zone, a party standing on the worst spots
-- (on the focused quest's mark, on a spawn square, beside the player, on a quest giver), another addon's pins on
-- our marks, then what the player sees on the world map (zoomed out and in) and the minimap (three zooms).
return function(steps, zone)
    local G, game, sim = steps.G, require("game"), require("sim")
    local markaudit = require("markaudit")
    local addon = require("addons").byName["onemorequest"].private
    steps.moveTo(zone.uiMapId, zone.x, zone.y)

    -- Up to ten quests of the zone near the character's level, as a player picks them up
    local Q, accepted = G.LibQuestieDB.Quest, {}
    for questId = 1, 9500 do
        local isRead, zoneOrSort = pcall(Q.Get, questId, "zoneOrSort")
        if isRead and zoneOrSort == zone.areaId then
            local level = Q.Get(questId, "questLevel") or 0
            local objectives = Q.Get(questId, "objectives")
            if level <= zone.level + 2 and level >= zone.level - 6 and type(objectives) == "table" and #accepted < 10 then
                if game.acceptQuest(questId) ~= false then accepted[#accepted + 1] = questId end
            end
        end
    end
    steps.wait(1.5)
    if accepted[1] then addon.Focus.set(accepted[1]) end
    steps.wait(1)

    -- Where to put the party: on our marks and squares, where they are hardest to see
    local marks = addon.MapMarks.compose(zone.uiMapId)
    local focusedMark, spotPoint, giverMark
    for _, mark in ipairs(marks) do
        if mark.isFocused and not focusedMark then focusedMark = mark end
        if mark.kind == "giver" and not giverMark then giverMark = mark end
        if not spotPoint and mark.points and mark.points[3] then spotPoint = mark.points[3] end
        if not spotPoint and mark.fadedPoints and mark.fadedPoints[3] then spotPoint = mark.fadedPoints[3] end
    end
    local places = {
        { "Garra", "WARRIOR", focusedMark },
        { "Brakka", "PRIEST", spotPoint },
        { "Questa", "HUNTER", { x = game.profile.x + 0.004, y = game.profile.y } },
        { "Tusk", "ROGUE", giverMark },
    }
    for _, entry in ipairs(places) do
        steps.joinParty({ name = entry[1], class = entry[2], level = zone.level, addon = "none" })
        local place = entry[3] or { x = game.profile.x, y = game.profile.y + 0.01 }
        steps.memberMoveTo(entry[1], zone.uiMapId, place.x, place.y)
    end

    -- Another addon's pins, as the shared map-pin library (HereBeDragons) makes them: on the world map's canvas at
    -- the area-POI level, and on the minimap as frames parented to it; put on our marks
    local function makeOtherPin(parent, size, level)
        local pin = G.CreateFrame("Button", nil, parent)
        pin:SetSize(size, size)
        pin:SetFrameLevel(level)
        local icon = pin:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(pin)
        icon:SetTexture(134400)
        local W = require("widgets")
        W.state[pin].creator, W.state[icon].creator = "OtherAddon", "OtherAddon"
        return pin
    end
    -- On the world map through the map's own pin pool, as HereBeDragons does (AcquirePin + SetPosition)
    local otherPins = {}
    for index = 1, math.min(3, #marks) do
        -- The game's own map (the whole interface) makes pins from a template or a pool put in its pinPools: as
        -- HereBeDragons does, a pool whose frames are the game's map pins (MapCanvasPinMixin)
        local map = G.WorldMapFrame
        if G.MapCanvasPinMixin and map.pinPools and not map.pinPools.OtherAddonPinTemplate then
            map.pinPools.OtherAddonPinTemplate = G.CreateFramePool("Button", map:GetCanvas(), nil,
                function(_, pin) pin:Hide(); pin:ClearAllPoints() end, false,
                function(pin) G.Mixin(pin, G.MapCanvasPinMixin) end)
        end
        local pin = map:AcquirePin("OtherAddonPinTemplate")
        pin:SetSize(16, 16)
        pin:SetFrameLevel(2023)
        local icon = pin:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints(pin)
        icon:SetTexture(134400)
        local W = require("widgets")
        W.state[pin].creator, W.state[icon].creator = "OtherAddon", "OtherAddon"
        -- Kept the same size on screen at any zoom, as such pins are, from the moment they are put on the map
        pin:SetScale(1 / G.WorldMapFrame:GetCanvasScale())
        pin:SetPosition(marks[index].x, marks[index].y)
        otherPins[#otherPins + 1] = pin
    end

    local results = {}
    local function measure(view, title)
        steps.wait(0.3)
        steps.saveScene((view .. "-" .. title):gsub("[^%w]+", "-"))
        local report = markaudit.measure(view)
        if report then
            print(markaudit.describe(report, zone.name .. ": " .. title))
            results[#results + 1] = report
        else
            print("== " .. zone.name .. ": " .. title .. ": nothing to measure")
        end
    end

    steps.key("M")
    steps.wait(0.5)
    G.WorldMapFrame:SetMapID(zone.uiMapId)
    measure("map", "world map, zoomed out")
    -- Zoomed in on the player
    local container = G.WorldMapFrame.ScrollContainer
    steps.zoomMap(1)
    G.WorldMapFrame:PanTo(game.profile.x, game.profile.y)
    for _, pin in ipairs(otherPins) do pin:SetScale(1 / G.WorldMapFrame:GetCanvasScale()) end
    measure("map", "world map, zoomed in on the player")
    steps.key("M")
    steps.wait(0.3)

    -- The minimap: another addon's pins on it too, at the nearest of our places
    local minimapPin = makeOtherPin(G.Minimap, 12, G.Minimap:GetFrameLevel() + 5)
    minimapPin:SetPoint("CENTER", G.Minimap, "CENTER", 18, 10)
    for _, zoom in ipairs({ 0, 2, 5 }) do
        steps.zoomMinimap(zoom)
        measure("minimap", "minimap, zoom " .. zoom .. " (" .. math.floor(G.C_Minimap.GetViewRadius()) .. " yards)")
    end
    return results
end
