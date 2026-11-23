local _, ns = ...

-- Spoken Places docks its place story to the world map's right edge, with a side tab down that edge that opens it:
-- where OneMoreQuest's window stands. While the window is docked they are moved beside the window instead: the tab
-- down its right edge, the story to its right when the screen has room for it. Without that room the story stays
-- folded to its tab until the player opens it (it then stands over the map's right side, never over the quest
-- window), so the map is never covered unasked. Spoken places and shows them again itself whenever the map changes;
-- each time, they are moved on. Only where they stand and whether the story shows are changed, never Spoken's
-- settings: its own "folded" choice stays the player's.
local FRAME_NAMES = { panel = "SpokenPlacesPanel", tab = "SpokenPlacesPanelToggle" }
local TAB_TOP = 30 -- as Spoken places its tab down the map's edge
local TAB_INSIDE_TOP = 100 -- inside the map's right edge: below the map's own buttons in its top right corner
local PANEL_GAP = 2

local state = {
    isDocked = false,
    isFitting = false,
    hasMoved = false,
    isAsked = false, -- the player opened the story since the map opened: shown over the map when it cannot go beside
    hooked = {},
}

---@return number? right The right edge of a region on screen, in the screen's own units
local function getScreenRight(region)
    local right = region and region.GetRight and region:GetRight()
    return right and right * (region:GetEffectiveScale() or 1) or nil
end

---@return number width A region's width on screen, in the screen's own units
local function getScreenWidth(region)
    return (region and region.GetWidth and region:GetWidth() or 0) * (region and region.GetEffectiveScale and region:GetEffectiveScale() or 1)
end

---@return boolean hasRoom Whether a region fits on screen right of the window
local function fitsRightOf(window, region)
    local windowRight, screenRight = getScreenRight(window), getScreenRight(UIParent)
    return windowRight ~= nil and screenRight ~= nil and screenRight - windowRight >= getScreenWidth(region) + PANEL_GAP
end

local function placeBesideWindow(window, map, panel, tab)
    if tab then
        tab:ClearAllPoints()
        if fitsRightOf(window, tab) then
            tab:SetPoint("TOPLEFT", window, "TOPRIGHT", 0, -TAB_TOP)
        else
            -- (the window reaches the screen's edge: inside the map's right edge, by the window)
            tab:SetPoint("TOPRIGHT", map, "TOPRIGHT", 0, -TAB_INSIDE_TOP)
        end
    end
    if panel then
        panel:ClearAllPoints()
        if fitsRightOf(window, panel) then
            panel:SetPoint("TOPLEFT", window, "TOPRIGHT", PANEL_GAP, 0)
            panel:SetPoint("BOTTOMLEFT", window, "BOTTOMRIGHT", PANEL_GAP, 0)
        else
            panel:SetPoint("TOPRIGHT", map, "TOPRIGHT", 0, 0)
            panel:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", 0, 0)
        end
    end
end

---Without room beside the window, the story Spoken shows unasked is folded to its tab: shown only, not its setting.
local function foldUnasked(window, panel, tab)
    if panel and tab and not state.isAsked and panel:IsShown() and not fitsRightOf(window, panel) then
        panel:Hide()
        tab:Show()
    end
end

---Back on the map's edge, as Spoken places them, until it places them again itself.
local function placeOnMapEdge(map, panel, tab)
    if tab then
        tab:ClearAllPoints()
        tab:SetPoint("TOPLEFT", map, "TOPRIGHT", 0, -TAB_TOP)
    end
    if panel then
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", map, "TOPRIGHT", PANEL_GAP, 0)
        panel:SetPoint("BOTTOMLEFT", map, "BOTTOMRIGHT", PANEL_GAP, 0)
    end
end

local function placeAll(window, map, panel, tab)
    if state.isDocked and window and window:IsShown() then
        state.hasMoved = true
        placeBesideWindow(window, map, panel, tab)
        foldUnasked(window, panel, tab)
    elseif state.hasMoved then
        state.hasMoved = false
        placeOnMapEdge(map, panel, tab)
    end
end

local function fit()
    local window, map = _G.TrailheadLog, WorldMapFrame
    local panel, tab = _G[FRAME_NAMES.panel], _G[FRAME_NAMES.tab]
    if state.isFitting or not (map and (panel or tab)) then
        return
    end
    state.isFitting = true -- placing and showing them calls the hooks below
    -- (a frame of Spoken's not as it was is passed over: Spoken's own placing stands)
    pcall(placeAll, window, map, panel, tab)
    state.isFitting = false
end

---Hooks what Spoken does to its frames, once each, as they come to be: placing them, showing them, and the player
---opening the story (its tab, or Spoken's own call for it). Each part is looked for; one missing is passed over.
local function hookSpoken()
    if not hooksecurefunc then
        return
    end
    for _, name in pairs(FRAME_NAMES) do
        local frame = _G[name]
        if type(frame) == "table" and not state.hooked[frame] then
            state.hooked[frame] = true
            for _, method in ipairs({ "SetPoint", "Show", "SetShown" }) do
                if type(frame[method]) == "function" then
                    hooksecurefunc(frame, method, fit)
                end
            end
        end
    end
    local places = _G.SpokenPlaces
    if type(places) == "table" and type(places.SetMapPanelCollapsed) == "function" and not state.hooked[places] then
        state.hooked[places] = true
        hooksecurefunc(places, "SetMapPanelCollapsed", function(self, isCollapsed)
            state.isAsked = isCollapsed == false
            -- (run after Spoken's own: the story it just showed was folded again, as not yet asked for)
            if state.isAsked and type(self.RefreshPanel) == "function" then
                self:RefreshPanel()
            end
        end)
    end
    local map = WorldMapFrame
    if map and map.HookScript and not state.hooked[map] then
        state.hooked[map] = true
        -- Asked for until the map closes: the next time it opens, the story waits on its tab again
        map:HookScript("OnHide", function()
            state.isAsked = false
        end)
    end
end

ns.Compatibility.register({
    name = "Spoken_Places",
    label = "Spoken Places",
    about = "Its place story and tab stand beside the quest window instead of over it; without room there, the story "
        .. "waits on its tab instead of covering the map.",
    onDockChanged = function(isDocked)
        state.isDocked = isDocked == true
        -- Spoken builds them once it has set up; from then on each time it places or shows them, they are moved on
        hookSpoken()
        fit()
    end,
})
