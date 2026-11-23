-- One character's session, played for every race and class by `bun run test:sim --each-character
-- sim/scenarios/each-character/session.lua` (each a fresh login): at home, the quest lists ready, then the quest log,
-- the Available tab and the chronicle at a starting level, a middle level and the top. Fails on any Lua error,
-- and when a level 1 character has nothing to pick up where it starts.
local HOMES = { -- where each race starts (uiMapId, x, y), and its capital for the top level
    Human = { 1429, 0.48, 0.42, 1453 }, Dwarf = { 1426, 0.29, 0.71, 1455 }, Gnome = { 1426, 0.29, 0.71, 1455 },
    NightElf = { 1438, 0.58, 0.44, 1457 }, Orc = { 1411, 0.43, 0.68, 1454 }, Troll = { 1411, 0.43, 0.68, 1454 },
    Scourge = { 1420, 0.31, 0.66, 1458 }, Tauren = { 1412, 0.45, 0.76, 1456 },
}
local _, race = G.UnitRace("player")
local _, class = G.UnitClass("player")
local home = HOMES[race]
local trailhead = require("addons").byName["onemorequest"].private

setProfile({ level = 1 })
moveTo(home[1], home[2], home[3])
-- The addon prepares its quest lists in the background after login: wait for it, as a player would
for _ = 1, 120 do
    if trailhead.Availability.isReady() then break end
    wait(0.5)
end
expect(trailhead.Availability.isReady(), "the quest lists are ready within a minute of logging in")
key("M")
wait(0.3)
for _, level in ipairs({ 1, 30, 60 }) do
    setProfile({ level = level })
    if level == 60 then moveTo(home[4], 0.5, 0.5) end
    fire("PLAYER_LEVEL_UP", level)
    wait(0.5)
    click("Available")
    wait(0.2)
    if level == 1 then
        local zoneId = trailhead.Model.getPlayer().zoneId
        local toPickUp = 0
        for _, quest in ipairs(zoneId and trailhead.Availability.getQuests(zoneId, {}) or {}) do
            if not quest.availableAtLevel then toPickUp = toPickUp + 1 end
        end
        expect(toPickUp > 0, string.format("a level 1 %s %s has something to pick up where it starts", race, class))
    end
    click("My quests")
    slash("/omq chronicle")
    slash("/omq chronicle")
end
