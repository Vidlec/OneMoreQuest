local _, ns = ...

-- Tnny's Mob Loot: drop rates of quest items, from its data (Loot.lua). Listed on the About page.
ns.Compatibility.register({
    name = "TnnysMobLoot",
    label = "Tnny's Mob Loot",
    about = "Drop rates of quest items: how many kills an item takes, and your luck so far.",
    detect = function()
        return _G.TnnysMobLoot_Forever ~= nil or _G.TnnysMobLoot_Starter ~= nil
    end,
})
