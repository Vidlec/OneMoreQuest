--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=20
-- Quest details on a page of their own (the Quest window setting, asked for by a player: "it makes things so wide"):
-- the window one pane wide beside the map, a click on a quest opens its page in the list's place with its buttons
-- under it, and the strip over it goes back to the list.
setProfile({ level = 20 })
moveTo(1413, 0.52, 0.30) -- The Barrens, by the Crossroads
local addon = require("addons").byName["onemorequest"].private
local GUNS_OF_NORTHWATCH, DISRUPTION_ENDS = 891, 872
accept(GUNS_OF_NORTHWATCH)
accept(DISRUPTION_ENDS)
wait(1.5)
key("M")
wait(0.8)
local window = addon.Log.getWindow()
local twoPanes = window:GetWidth()

addon.settings.questDetails = "own"
addon.Log.refresh()
wait(0.3)
expect(
    window:GetWidth() < twoPanes * 0.6,
    "one pane: " .. math.floor(window:GetWidth()) .. " wide, from " .. math.floor(twoPanes)
)
expect(not addon.Log.isPageSpread(), "the list shows as the map opens")
expect(G.WorldMapFrame:IsVisible() and window:IsVisible(), "the map and the window both open")
saveScene("own-page-list")

click("The Guns of Northwatch")
wait(0.3)
local frame = window
expect(addon.Log.isPageSpread(), "a click opens the quest's page")
expect(frame.backStrip:IsVisible(), "under the way back")
expect(frame.bar:IsVisible() and frame.trackButton:IsVisible(), "the page's buttons under it")
expect(not addon.Log.getListCanvas().frame:IsVisible(), "in the list's place")
expectText("Abandon")
expect(addon.Log.getPageCanvas().frame.ScrollBar:IsVisible(), "the long page scrolls: its scroll bar shows")
saveScene("own-page-quest")

click(frame.backStrip)
wait(0.3)
expect(not addon.Log.isPageSpread() and addon.Log.getListCanvas().frame:IsVisible(), "the strip goes back to the list")
expect(not frame.bar:IsVisible(), "the buttons go with the page")
local pageScrollBar = addon.Log.getPageCanvas().frame.ScrollBar
expect(not (pageScrollBar and pageScrollBar:IsVisible()), "and its scroll bar, which is the window's own child")

-- Opened from the map: its page at once
local entry
for _, group in ipairs(addon.Model.compose(nil).groups) do
    for _, candidate in ipairs(group.entries) do
        entry = candidate.questId == DISRUPTION_ENDS and candidate or entry
    end
end
addon.Log.selectQuest(DISRUPTION_ENDS)
wait(0.3)
expect(
    addon.Log.isPageSpread() and addon.Log.getSelectedQuestId() == DISRUPTION_ENDS,
    "a quest opened from the map shows on its page"
)

-- Back beside the list
addon.settings.questDetails = "beside"
addon.Log.refresh()
wait(0.3)
expect(math.abs(window:GetWidth() - twoPanes) < 1, "beside the list: both panes again")
expect(
    not frame.backStrip:IsVisible() and addon.Log.getListCanvas().frame:IsVisible(),
    "the list and the page side by side"
)

-- With a controller: A on a quest opens its page in the list's place, B goes back to its row
if addon.Gamepad and G.GamepadMainActionBarFrame then
    addon.settings.questDetails = "own"
    key("M") -- (closed: opened again by itself, as with the pad)
    wait(0.5)
    local omq = require("omqpad").start()
    gamepadInterface(true)
    addon.MapDock.open()
    wait(0.5)
    expect(omq.isOwn("PADDDOWN"), "the window has the pad")
    expect(addon.Log.isNarrow() and not addon.Log.isPageSpread(), "one pane, the list in it")
    pad("PAD1")
    wait(0.3)
    expect(addon.Log.isPageSpread(), "A opens the quest's page in the list's place")
    pad("PAD2")
    wait(0.3)
    expect(not addon.Log.isPageSpread() and window:IsVisible(), "B goes back to the list, the window still open")
    local bar = addon.Log.getPageCanvas().frame.ScrollBar
    expect(not (bar and bar:IsVisible()), "the page's scroll bar went with it")
else
    print("skipped the controller part: the game's gamepad interface is not loaded (light mode)")
end
