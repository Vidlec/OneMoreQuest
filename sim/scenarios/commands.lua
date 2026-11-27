-- Every /omq command does what it says, and says so in the chat.
setProfile({ level = 30, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844)
wait(1)
local addon = require("addons").byName["onemorequest"].private
local settings = addon.settings

-- No word: the tracker shows or hides
local wasShown = G.OneMoreQuestTracker and G.OneMoreQuestTracker:IsShown()
slash("/omq")
wait(0.2)
expect(G.OneMoreQuestTracker:IsShown() ~= wasShown, "/omq shows or hides the tracker")
slash("/omq")
wait(0.2)
expect(G.OneMoreQuestTracker:IsShown() == wasShown, "and again brings it back")

slash("/omq settings")
wait(0.3)
expect(addon.Log.isShowingSettings(), "/omq settings opens the settings")
key("ESCAPE")
wait(0.2)

slash("/omq log")
wait(0.3)
expect(G.OneMoreQuestLog and G.OneMoreQuestLog:IsShown(), "/omq log opens the quest log")
slash("/omq available")
wait(0.3)
expect(addon.Log.isShowingAvailable(), "/omq available opens the quests to pick up")
key("ESCAPE")
wait(0.2)

clearChat()
local isLocked = settings.isLocked
slash("/omq lock")
expect(settings.isLocked ~= isLocked, "/omq lock locks or unlocks the tracker")
expectChat(settings.isLocked and "tracker locked" or "tracker unlocked")
slash("/omq lock")

-- Dragged by its title while unlocked, the tracker stays where it was put; /omq reset brings it back
if settings.isLocked then
    slash("/omq lock")
end
local function trackerLeft()
    return math.floor(G.OneMoreQuestTracker:GetLeft() + 0.5)
end
local homeLeft = trackerLeft()
drag("Quests", { dx = -300, dy = 100 })
wait(0.2)
expect(
    math.abs(trackerLeft() - (homeLeft - 300)) <= 8,
    string.format("the tracker moved with the drag (%d to %d)", homeLeft, trackerLeft())
)
expect(settings.position ~= nil, "and its place is kept")
local movedLeft = trackerLeft()
slash("/omq lock")
drag("Quests", { dx = 200, dy = 0 })
wait(0.2)
expect(trackerLeft() == movedLeft, "locked, it does not move")
slash("/omq lock")
slash("/omq reset")
wait(0.2)
expect(settings.position == nil and trackerLeft() == homeLeft, "/omq reset puts it back")

for _, case in ipairs({
    { "builtin", "shouldHideBuiltInTracker", "built-in tracker" },
    { "pins", "shouldShowMapPins", "map pins" },
    { "mapbuiltin", "shouldHideBuiltInMapPins", "quest markers" },
    { "givers", "shouldShowAvailableOnMap", "quest givers" },
    { "key", "shouldReplaceQuestLog", "the map shows" },
}) do
    clearChat()
    local before = settings[case[2]]
    slash("/omq " .. case[1])
    expect(settings[case[2]] ~= before, "/omq " .. case[1] .. " switches " .. case[2])
    expectChat(case[3], "/omq " .. case[1] .. " says so")
    slash("/omq " .. case[1]) -- and back
    expect(settings[case[2]] == before, "/omq " .. case[1] .. " twice puts it back")
end

clearChat()
slash("/omq kills")
wait(0.2)
expect(
    #require("sim").chat > 0 or addon.Log.isShowingChronicle and addon.Log.isShowingChronicle(),
    "/omq kills answers"
)
clearChat()
slash("/omq missing")
expect(#require("sim").chat > 0, "/omq missing answers")
clearChat()
slash("/omq nonsense")
expectChat("commands:", "an unknown word lists the commands")
for _, alias in ipairs({ "/onemorequest" }) do
    local shown = G.OneMoreQuestTracker:IsShown()
    slash(alias)
    wait(0.1)
    expect(G.OneMoreQuestTracker:IsShown() ~= shown, alias .. " works as /omq does")
    slash(alias)
end
