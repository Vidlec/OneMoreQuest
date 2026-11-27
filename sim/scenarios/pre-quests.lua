--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=4
-- Pre-quests: a quest that other quests wait for, without being a step of their chain, says so where a chain's step
-- says "1 of 3": in the tracker, in the quest log's list and on the quest's page; and the quest diagram, a window
-- of its own opened from the page. Cutting Teeth (Valley of Trials) opens three quests at once for an orc warrior, a
-- fork no chain joins: Sting of the Scorpid, Galgar's Cactus Apple Surprise and the warrior's Simple Parchment.
setProfile({ level = 4, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68) -- Durotar, the Valley of Trials
local addon = require("addons").byName["onemorequest"].private
local CUTTING_TEETH, STING_OF_THE_SCORPID, CACTUS_APPLE = 788, 789, 4402
accept(CUTTING_TEETH)
wait(2)

-- The data rule, on the real database
local Chain = addon.Chain
local function list(questIds)
    local sorted = { unpack(questIds) }
    table.sort(sorted)
    return table.concat(sorted, ",")
end
expect(Chain.getStep(CUTTING_TEETH) == nil, "Cutting Teeth is no step of a chain")
expect(
    list(Chain.getUnlockedQuestIds(CUTTING_TEETH)) == "789,2383,4402",
    "it unlocks both: " .. list(Chain.getUnlockedQuestIds(CUTTING_TEETH))
)
expect(list(Chain.getRequiredQuestIds(STING_OF_THE_SCORPID)) == "788", "and Sting of the Scorpid followed it")

-- The tracker: the branching mark and "+3" right of the title, the quests by name in the row's tooltip
local function trackerRow(questId, frame)
    frame = frame or G.UIParent
    for _, child in ipairs({ frame:GetChildren() }) do
        if child.entry and child.entry.questId == questId and child:IsVisible() and child.isTitle then
            return child
        end
        local found = trackerRow(questId, child)
        if found then
            return found
        end
    end
end
local row = trackerRow(CUTTING_TEETH)
expect(row ~= nil, "the quest has a row in the tracker")
expect(row.rightText:GetText() == "+3", "which says +3: " .. tostring(row.rightText:GetText()))
expect(row.chainIcon:IsShown() and tostring(row.chainIcon:GetTexture()):find("Unlock"), "beside the branching mark")
hover(row)
wait(0.3)
expectText("Unlocks 3 quests")
expectText("Sting of the Scorpid")
saveScene("tracker")
hover({ 5, 5 })

-- The quest log: the same mark in the list, the quests under "Before and after" on the page
key("M")
wait(1)
click("Cutting Teeth")
wait(0.5)
expectText("+3")
expectText("Before and after")
expectText("Unlocks:")
saveScene("log-page")

-- The diagram: its own window, opened from the page
addon.Log.getPageCanvas():setScroll(2000) -- (to the page's end, where the button is)
wait(0.3)
expectText("Galgar's Cactus Apple Surprise")
expectText("Quest diagram")
click("Quest diagram")
wait(0.5)
local window = addon.LogDiagram.getWindow()
expect(window ~= nil and window:IsVisible(), "the button opens the diagram's window")
local function getBoxes()
    local boxes = {}
    for _, box in ipairs(window.boxes) do
        boxes[box.questId] = box
    end
    return boxes
end
local boxes = getBoxes()
expect(boxes[CUTTING_TEETH].depth == 0, "the quest itself")
expect(boxes[STING_OF_THE_SCORPID].depth == 1 and boxes[CACTUS_APPLE].depth == 1, "the quests it unlocks under it")
expect(window.selectedQuestId == CUTTING_TEETH, "its own page beside the tree at first")
expect(window.page.header.title:GetText() == "Cutting Teeth", "the quest window's page, with its header")
expect(not window.rootButton:IsShown(), "no Diagram from here for the quest it is of")
expect(addon.Log.getPageCanvas().frame:IsVisible(), "the quest window's own page still stands")
saveScene("diagram")

-- A click on a box shows that quest's page beside the tree: Sting of the Scorpid's, from the Available tab's
click(boxes[STING_OF_THE_SCORPID].button)
wait(0.5)
expect(window.selectedQuestId == STING_OF_THE_SCORPID and window.questId == CUTTING_TEETH, "a click picks the quest")
expect(window.page.header.title:GetText() == "Sting of the Scorpid", "and shows its page")
expectText("Needed first:") -- the page names what it follows
saveScene("diagram-page")
-- Diagram from here turns the tree to it: Cutting Teeth is then what came before, above it
expect(window.rootButton:IsShown(), "Diagram from here is offered")
click(window.rootButton)
wait(0.5)
boxes = getBoxes()
expect(window.questId == STING_OF_THE_SCORPID and window:IsVisible(), "the tree turns to the quest")
expect(boxes[CUTTING_TEETH].depth == -1, "and the quest it followed stands above it")

-- A quest that opens a dozen at once: they wrap into rows of three, all in view with nothing to scroll
local GREAT_OUTDOORS = 96604
addon.LogDiagram.show(GREAT_OUTDOORS, true)
wait(0.5)
local wrapRows, widest = 0, 0
for _, box in ipairs(window.boxes) do
    wrapRows = math.max(wrapRows, (box.wrapRow or 0) + 1)
    widest = math.max(widest, box.slot)
end
expect(#window.boxes > 6, "many quests under it: " .. #window.boxes)
expect(wrapRows > 1 and widest <= 2, "in rows of three: " .. wrapRows .. " rows")
expect(window.tree.maxSideScroll == 0, "so nothing runs off the side")
saveScene("diagram-wide")

-- A long chain is taller than the pane: it scrolls, and opens with its quest in view
local ISHAMUHALE = 882
addon.LogDiagram.show(ISHAMUHALE, true)
wait(0.5)
expect((window.tree.canvas.maxScroll or 0) > 0, "a tall tree scrolls")
local before = window.tree.canvas:getScroll()
addon.LogDiagram.pan(0, 60)
expect(window.tree.canvas:getScroll() > before, "and moves when dragged")
saveScene("diagram-tall")

-- Zooming: the + over the tree draws it larger, the percentage between the buttons fits it to the pane again
local fitted = window.tree.scale
click(window.zoomInButton)
wait(0.2)
expect(window.tree.scale > fitted, "the + button draws the tree larger: " .. window.tree.scale)
expect(window.zoomText:GetText() == math.floor(window.tree.scale * 100 + 0.5) .. "%", "and says how large")
click(window.zoomOutButton)
click(window.zoomOutButton)
wait(0.2)
expect(window.tree.scale < fitted, "the - button draws it smaller: " .. window.tree.scale)
saveScene("diagram-zoomed-out")
click(window.zoomFitButton)
wait(0.2)
expect(window.tree.scale == fitted, "a click on the percentage fits it again")

-- Its size: the grip in its corner makes it larger or smaller (here set as a drag would), the tree's pane taking
-- the change; kept with the settings; a right click on the grip puts the usual size back
local usualWidth, usualPane = window:GetWidth(), window.tree.paneWidth
expect(window.sizeGrip ~= nil and window.sizeGrip:IsVisible(), "a grip in the window's corner")
addon.LogDiagram.setSize(980, 700)
wait(0.3)
expect(
    math.abs(window:GetWidth() - usualWidth - 220) < 1,
    "the window is as much wider: " .. (window:GetWidth() - usualWidth)
)
expect(math.abs(window.tree.paneWidth - usualPane - 220) < 1, "the tree's pane takes the change")
expect(
    math.abs(window:GetHeight() - 700) < 1 and addon.settings.diagramHeight == 700,
    "taller, and kept with the settings"
)
saveScene("diagram-resized")
click(window.sizeGrip, "RightButton")
wait(0.3)
expect(math.abs(window:GetWidth() - usualWidth) < 1, "a right click on the grip: the usual size")

click(window.closeButton)
wait(0.3)
expect(not window:IsVisible(), "the close button closes it")

-- Handed in: the quest it unlocked, once in the log, says what it followed in its tooltip
complete(CUTTING_TEETH)
turnIn(CUTTING_TEETH)
accept(STING_OF_THE_SCORPID)
key("M")
wait(2)
row = trackerRow(STING_OF_THE_SCORPID)
expect(row ~= nil, "the next quest is tracked")
hover(row)
wait(0.3)
expectText("Follows Cutting Teeth")

-- In the diagram a quest done has a page too: when it was done, and the quests around it
addon.LogDiagram.show(STING_OF_THE_SCORPID, true)
wait(0.5)
window = addon.LogDiagram.getWindow()
for _, box in ipairs(window.boxes) do
    if box.questId == CUTTING_TEETH then
        expect(box.state == "done", "the quest handed in is marked done")
        click(box.button)
    end
end
wait(0.5)
expect(window.page.header.title:GetText() == "Cutting Teeth", "its page shows")
expect(window.openButton:GetText() == "Read in the Chronicle", "and its button leads to the Chronicle")
saveScene("diagram-done")
