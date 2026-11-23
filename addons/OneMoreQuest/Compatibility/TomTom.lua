local _, ns = ...

-- TomTom: waypoints go to its arrow when it is installed (Waypoints.lua). Listed on the About page.
ns.Compatibility.register({
    name = "TomTom",
    label = "TomTom",
    about = "Waypoints to quests go to TomTom's arrow.",
    detect = function()
        return ns.Waypoints ~= nil and ns.Waypoints.hasTomTom() == true
    end,
})
