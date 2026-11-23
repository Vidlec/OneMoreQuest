-- The quest window's close button (the game's own, on the game's frame) closes the map and the window with it.
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({ 185, 186, 187, 188 }) do pcall(accept, questId) end
wait(2)
local addon = require("addons").byName["onemorequest"].private
local W = require("widgets")
local sim = require("sim")
for _, style in ipairs({ "map", "game", "gold", "flat" }) do
    addon.settings.windowBorder = style
    key("M"); wait(2)
    expect(G.WorldMapFrame:IsShown() == true, style .. ": the map is open")
    -- The close button: the shown button of the window's chrome nearest its upper right corner
    local best, bestDistance
    local function look(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsShown() and child:GetObjectType() == "Button" and child:GetScript("OnClick") and (child:GetWidth() or 99) <= 40 then
                local rect = W.computeRect(child)
                local window = W.computeRect(addon.Log.getListCanvas().content:GetParent():GetParent())
                best = best
            end
            if depth < 4 then look(child, depth + 1) end
        end
    end
    local shown = {}
    local function collect(frame, depth)
        for _, child in ipairs({ frame:GetChildren() }) do
            if child:IsVisible() and child:GetObjectType() == "Button" and child:GetScript("OnClick") then
                local rect = W.computeRect(child)
                shown[#shown + 1] = { child = child, x = (rect[1] + rect[3]) / 2, y = sim.screenHeight - (rect[2] + rect[4]) / 2, w = rect[3] - rect[1] }
            end
            if depth < 6 then collect(child, depth + 1) end
        end
    end
    collect(G.UIParent, 0)
    -- Rightmost, topmost small button
    table.sort(shown, function(a, b) return (a.x - a.y * 3) > (b.x - b.y * 3) end)
    local target
    for _, item in ipairs(shown) do
        if item.w <= 40 and item.y < 200 then target = item break end
    end
    io.write(string.format("CLOSE %s: clicking at %.0f, %.0f (button %.0f wide, of %d buttons)\n", style, target.x, target.y, target.w, #shown))
    click({ target.x, target.y }); wait(1)
    io.write(string.format("CLOSE %s: map shown %s\n", style, tostring(G.WorldMapFrame:IsShown())))
    expect(G.WorldMapFrame:IsShown() ~= true, style .. ": the close button closed the map")
    if G.WorldMapFrame:IsShown() then key("M"); wait(1) end
end
