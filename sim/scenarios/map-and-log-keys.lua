--@addons QuestieDB, OneMoreQuest
--@login race=Orc,class=WARRIOR,level=6
-- The map and the quest log open as the game's own do: the arrow on the map is the lasting choice of whether the
-- quest log shows with the map; the map's key (M) opens the map by it, with the quest log or alone; the quest
-- log's key (L) opens the map with the quest log whatever the arrow says, for that opening, and leaves the
-- arrow's choice as it is.
setProfile({ level = 6, race = "Orc", class = "WARRIOR" })
moveTo(1411, 0.43, 0.68)
local addon = require("addons").byName["onemorequest"].private
accept(788)
wait(2)
local map = G.WorldMapFrame

-- A key pressed is a key held while its command runs: the quest log's key is known by that (both keys run the
-- game's map command, which an addon's own could not in a fight)
local heldKey
local isKeyDown = G.IsKeyDown
G.IsKeyDown = function(key)
    return key == heldKey or (isKeyDown ~= nil and isKeyDown(key) == true)
end
local function press(name)
    heldKey = name
    key(name)
    heldKey = nil
    wait(0.6)
end

-- As it comes: the quest log shows with the map (the game's own first setting)
press("M")
expect(map:IsShown() and addon.Log.isOpen(), "at first the map key opens the map with the quest log")
press("M")
expect(not map:IsShown(), "and closes it")

-- The arrow puts the quest log away, for good: the map key then opens the map alone
press("M")
addon.settings.arePanelsHidden = true -- (the arrow on the map)
addon.MapDock.apply()
expect(map:IsShown() and not addon.Log.isOpen(), "the arrow folds the quest log away")
press("M")
press("M")
expect(map:IsShown() and not addon.Log.isOpen(), "the map key opens the map alone from then on")
saveScene("map-alone")
press("M")

-- The quest log key opens the map with the quest log all the same
press("L")
expect(map:IsShown() and addon.Log.isOpen(), "the quest log key opens the map with the quest log")
expect(addon.settings.arePanelsHidden == true, "without changing the arrow's choice")
saveScene("map-with-log")
press("L")
expect(not map:IsShown(), "pressed again, it closes the pair")
-- and the map key after it still opens the map alone
press("M")
expect(map:IsShown() and not addon.Log.isOpen(), "the map key still opens the map alone")

-- The quest log key on the map open alone brings the quest log out, the map staying
press("L")
expect(map:IsShown() and addon.Log.isOpen(), "the quest log key on the lone map shows the quest log")
press("M")
expect(not map:IsShown(), "the map key closes it")

-- A quest clicked in the tracker opens the pair for that opening only
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
click(trackerRow(788))
wait(1.5)
expect(map:IsShown() and addon.Log.isOpen(), "a quest asked for opens the map with the quest log")
press("M")
press("M")
expect(map:IsShown() and not addon.Log.isOpen(), "and the next plain opening is the map alone again")
press("M")
addon.settings.arePanelsHidden = false
