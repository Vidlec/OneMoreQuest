-- The tracker grows only downwards: wherever it is dragged, its top stays put as quests are added, and a place
-- saved the old way (by the middle of an edge) is turned into its top corner.
setProfile({ level = 14, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844)
wait(1)
local addon = require("addons").byName["onemorequest"].private
local tracker = G.TrailheadTracker
local function top()
    return math.floor(tracker:GetTop() + 0.5)
end

drag("Quests", { dx = -400, dy = 150 })
wait(0.3)
local placedTop, placedHeight = top(), tracker:GetHeight()
expect(
    tostring(addon.settings.position[1]):find("^TOP"),
    "dragged, the tracker is kept by its top (" .. tostring(addon.settings.position[1]) .. ")"
)
for _, questId in ipairs({ 869, 845, 855, 871, 821 }) do
    accept(questId)
end
wait(1)
expect(tracker:GetHeight() > placedHeight + 20, "more quests make it taller")
expect(math.abs(top() - placedTop) <= 1, string.format("its top stays where it was put (%d, was %d)", top(), placedTop))

-- A place saved by the middle of the right edge, as dragging used to keep it
addon.settings.position = { "RIGHT", "RIGHT", -90, -40 }
addon.Tracker.resetPosition()
wait(0.3)
local oldTop = top()
expect(tostring(addon.settings.position[1]):find("^TOP"), "an old place is turned into the top corner")
abandon(821)
abandon(871)
wait(1)
expect(math.abs(top() - oldTop) <= 1, string.format("and the top stays as quests go (%d, was %d)", top(), oldTop))
