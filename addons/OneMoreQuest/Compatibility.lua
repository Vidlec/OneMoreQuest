local _, ns = ...

-- Getting along with other addons. Each addon OneMoreQuest has to make room for, or work around, is a provider, in
-- its own file under Compatibility\, registered with Compatibility.register. A provider names the moments it cares
-- about (handlers below); each is called only while its addon is loaded, and an error in one never stops
-- OneMoreQuest or the others.
--
---@class CompatibilityProvider
---@field name string The addon's folder name: "Spoken_Places"
---@field label string The addon's name as players know it, for the About page
---@field about string What OneMoreQuest does with it, in English (translated where shown), for the About page
---@field detect (fun(): boolean)? Whether it applies; without it, while the addon is loaded
---@field getStatus (fun(): string?)? Something about it the player should know now, added to its About line
---@field onLoginSettled (fun())? A few seconds after logging in, once the screen has settled
---@field onDockChanged (fun(isDocked: boolean))? OneMoreQuest's window docked beside the windowed map, or not any more
---@field placesMap (fun(): boolean)? The addon keeps the map where the player moved it, so the game's window layout must
---not move it when OneMoreQuest makes room beside the map
---@field announces (fun(kind: string): boolean)? The addon itself tells the group this kind of quest news in chat
---("objective": an objective done; "ready": a quest ready to hand in), so OneMoreQuest keeps quiet about it
---@field getMapView (fun(map: table): MapView?)? The addon shows more on this map than the game's map underneath (the
---neighbouring zones, joined on): how to place any zone's point on the map, and which zones are in view; nil while it
---shows only the game's map
---
---@class MapView
---@field project fun(placeMapId: number, x: number, y: number, mapId: number): number?, number? A point of a zone's
---map (fractions) on the map shown, in that map's fractions (past 0 and 1 where the view reaches beyond it); nil
---where the addon cannot place it (the game's own reckoning is used then)
---@field getZoneMapIds fun(mapId: number, bounds: table): number[] The zones' maps (uiMapIds) in view
---@field getZoneMapIdAt fun(mapId: number, x: number, y: number): number? The zone's map (uiMapId) whose land is at a
---point of the map shown; nil where none is (the sea)
local Compatibility = {
    providers = {}, ---@type CompatibilityProvider[]
}
ns.Compatibility = Compatibility

local SETTLE_SECONDS = 5 -- after logging in, before onLoginSettled

---@param provider CompatibilityProvider
function Compatibility.register(provider)
    Compatibility.providers[#Compatibility.providers + 1] = provider
end

---@return CompatibilityProvider? provider The provider for an addon, by its folder name
function Compatibility.getProvider(name)
    for _, provider in ipairs(Compatibility.providers) do
        if provider.name == name then
            return provider
        end
    end
    return nil
end

Compatibility.isAddOnLoaded = ns.isAddOnLoaded

local function isApplying(provider)
    if provider.detect then
        local isFine, isDetected = pcall(provider.detect)
        return isFine and isDetected == true
    end
    return Compatibility.isAddOnLoaded(provider.name)
end

---The addons OneMoreQuest works with now: every provider whose addon is loaded, for the About page.
---@return { label: string, text: string }[] integrations
function Compatibility.getIntegrations()
    local integrations = {}
    for _, provider in ipairs(Compatibility.providers) do
        if provider.about and isApplying(provider) then
            local isFine, status = true, nil
            if provider.getStatus then
                isFine, status = pcall(provider.getStatus)
            end
            local text = ns.L(provider.about) .. (isFine and type(status) == "string" and (" " .. status) or "")
            integrations[#integrations + 1] = { label = provider.label or provider.name, text = text }
        end
    end
    return integrations
end

---Tells every provider that cares about a moment, while its addon is loaded. An error in one goes to the game's
---error handler, as any addon error does, and the rest carry on.
function Compatibility.notify(handlerName, ...)
    for _, provider in ipairs(Compatibility.providers) do
        local handler = provider[handlerName]
        if handler and isApplying(provider) then
            local isFine, problem = pcall(handler, ...)
            if not isFine and geterrorhandler then
                geterrorhandler()(problem)
            end
        end
    end
end

---@return boolean isPlaced Another addon keeps the map where the player put it (MapDock then keeps it there)
function Compatibility.isMapPlacedByAddOn()
    for _, provider in ipairs(Compatibility.providers) do
        if provider.placesMap and isApplying(provider) then
            local isFine, isPlaced = pcall(provider.placesMap)
            if isFine and isPlaced then
                return true
            end
        end
    end
    return false
end

---OneMoreQuest's window docked beside the map, or not: now, and again a moment later for what other addons place
---as the map settles.
---@return boolean isAnnounced A loaded addon tells the group this kind of quest news itself
function Compatibility.isAnnouncedByAddOn(kind)
    for _, provider in ipairs(Compatibility.providers) do
        if provider.announces and isApplying(provider) then
            local isFine, isAnnounced = pcall(provider.announces, kind)
            if isFine and isAnnounced then
                return true
            end
        end
    end
    return false
end

---@return MapView? view How another addon shows more than the game's map on this one (Compatibility: getMapView);
---nil when none does
function Compatibility.getMapView(map)
    for _, provider in ipairs(Compatibility.providers) do
        if provider.getMapView and isApplying(provider) then
            local isFine, view = pcall(provider.getMapView, map)
            if isFine and type(view) == "table" then
                return view
            end
        end
    end
    return nil
end

function Compatibility.handleDockChanged(isDocked)
    Compatibility.notify("onDockChanged", isDocked)
    if C_Timer then
        C_Timer.After(0, function() Compatibility.notify("onDockChanged", isDocked) end)
    end
end

function Compatibility.create()
    if C_Timer then
        C_Timer.After(SETTLE_SECONDS, function() Compatibility.notify("onLoginSettled") end)
    end
end

ns.registerModule({ name = "Compatibility", create = Compatibility.create })
