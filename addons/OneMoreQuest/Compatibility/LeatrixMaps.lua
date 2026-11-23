local _, ns = ...

-- Leatrix Maps: with its map frame unlocked, it keeps the map where the player dragged it. It puts the map back there
-- when the map lays itself out (SynchronizeDisplayState, OnFrameSizeChanged), which the game does as its own quest
-- panel opens with the map. OneMoreQuest keeps that panel closed, so on opening the game's window layout would leave
-- the map at its usual spot on the left. So the place Leatrix Maps last put the map is remembered here, and the map
-- goes back to it whenever OneMoreQuest's window docks beside it. Only the map's anchor is set; nothing of the game's
-- or Leatrix Maps' own is called.
local placed -- { point, relativeTo, relativePoint, x, y }: where Leatrix Maps last put the windowed map
local isHooked = false

local function rememberPlace()
    local map = WorldMapFrame
    if map and not (map.IsMaximized and map:IsMaximized()) and map:GetNumPoints() == 1 then
        placed = { map:GetPoint(1) }
    end
end

---Hooks after Leatrix Maps' own (it hooked at load, so its run first): its placements, and the player's drags.
local function hookMap()
    local map = WorldMapFrame
    if isHooked or not map or not hooksecurefunc then
        return
    end
    isHooked = true
    rememberPlace() -- placed by Leatrix Maps at load, before the map was first opened
    for _, method in ipairs({ "SynchronizeDisplayState", "OnFrameSizeChanged" }) do
        if map[method] then
            hooksecurefunc(map, method, rememberPlace)
        end
    end
    hooksecurefunc(map, "StopMovingOrSizing", function()
        -- Leatrix Maps anchors the dragged map by its top left corner straight after; read it once that is done
        if C_Timer then
            C_Timer.After(0, rememberPlace)
        end
    end)
end

ns.Compatibility.register({
    name = "Leatrix_Maps",
    label = "Leatrix Maps",
    about = "The map stays where you moved it when OneMoreQuest's window opens beside it.",
    detect = function()
        return ns.isAddOnLoaded("Leatrix_Maps") and type(_G.LeaMapsDB) == "table" and _G.LeaMapsDB.UnlockMap == "On"
    end,
    placesMap = function()
        return true
    end,
    onLoginSettled = hookMap,
    onDockChanged = function(isDocked)
        hookMap()
        local map = WorldMapFrame
        if isDocked and placed and map and map:IsShown() and not (map.IsMaximized and map:IsMaximized()) then
            map:ClearAllPoints()
            map:SetPoint(unpack(placed))
        end
    end,
})
