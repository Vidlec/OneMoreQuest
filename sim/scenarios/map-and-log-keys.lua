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

-- Each key has its version of the map, as the game's own keys do: a key closes its own, and on the other's brings out
-- its own, never closing the map
press("M")
press("L")
expect(map:IsShown() and addon.Log.isOpen(), "the quest log key on the map key's version: the map stays, its version")
press("L")
expect(not map:IsShown(), "pressed again, the quest log key closes its version")
press("L")
press("M")
expect(map:IsShown() and addon.Log.isOpen(), "the map key on the quest log key's version: the map stays, its version")
press("M")
expect(not map:IsShown(), "pressed again, the map key closes its version")

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

-- The quest log key on the map open alone brings the quest log out, the map staying; the map key then puts the log
-- away again and keeps the map as it was set up, as the game's own map key does
press("L")
expect(map:IsShown() and addon.Log.isOpen(), "the quest log key on the lone map shows the quest log")
press("M")
expect(map:IsShown() and not addon.Log.isOpen(), "the map key puts the log away, the map staying as it was")
press("M")
expect(not map:IsShown(), "pressed again, the map key closes it")

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
expect(map:IsShown() and not addon.Log.isOpen(), "the map key puts that log away, the map staying")
press("M")
press("M")
expect(map:IsShown() and not addon.Log.isOpen(), "and the next plain opening is the map alone again")
press("M")
addon.settings.arePanelsHidden = false

-- The full-screen map, the quest log key, then the map key: the map key brings the full-screen map back, as it was
-- before the quest log key took it out of full screen (it does not close the map)
press("M")
map:HandleUserActionMaximizeSelf() -- (the map's own maximize button)
wait(0.5)
expect(map:IsShown() and map:IsMaximized(), "the map is full screen")
press("L")
expect(map:IsShown() and not map:IsMaximized() and addon.Log.isOpen(), "the quest log key shows the map with the log")
press("M")
expect(map:IsShown(), "the map key keeps the map open")
expect(map:IsMaximized() and not addon.Log.isOpen(), "full screen again, the quest log put away")
press("M")
expect(not map:IsShown(), "and pressed again, the map key closes it")
-- Afterwards the map key opens the map as the player last left it (full screen) and the log key still the pair
press("M")
expect(map:IsShown() and map:IsMaximized(), "the map key opens the full-screen map")
press("L")
expect(map:IsShown() and not map:IsMaximized() and addon.Log.isOpen(), "the quest log key: windowed, with the log")
press("L")
expect(not map:IsShown(), "the quest log key closes the pair")
-- From a closed map, the player's size being full screen: the quest log key opens the map windowed with the log,
-- and the map key then makes it full screen
press("L")
expect(map:IsShown() and not map:IsMaximized() and addon.Log.isOpen(), "the quest log key opens the windowed pair")
press("M")
expect(map:IsShown() and map:IsMaximized(), "the map key makes it full screen")
press("M")
expect(not map:IsShown(), "and closes it")
map:HandleUserActionMinimizeSelf() -- (the player's size back to windowed, for the scenarios after)
map:Hide()

-- Each key opens the map as the player left it: where they moved it, how large they made it, full screen or not; the
-- quest log key the same windowed map with the log beside it
local MapDock = addon.MapDock
local function getMapBox()
    return { math.floor(map:GetLeft() + 0.5), math.floor(map:GetTop() + 0.5), math.floor(map:GetWidth() + 0.5) }
end
local function isSameBox(a, b)
    return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end
press("M")
expect(map:IsShown() and not map:IsMaximized() and addon.Log.isOpen(), "the windowed map with its log")
MapDock.startMapDrag() -- (the quest window's title strip, dragged)
map:ClearAllPoints()
map:SetPoint("TOPLEFT", G.UIParent, "TOPLEFT", 120, -90)
MapDock.stopMapDrag()
MapDock.startResize(false) -- (the grip at the quest window's corner)
MapDock.resizeTo(160, 110)
MapDock.stopResize()
wait(0.5)
local leftAs = getMapBox()
press("M")
expect(not map:IsShown(), "the map key closes it")
press("M")
expect(isSameBox(getMapBox(), leftAs), "and opens it where it was, as large: " .. table.concat(getMapBox(), ","))
expect(addon.Log.isOpen(), "with its log, as it was")
press("L")
expect(
    isSameBox(getMapBox(), leftAs),
    "the quest log key keeps it, now its version: " .. table.concat(getMapBox(), ",")
)
expect(addon.Log.isOpen(), "with its log")
press("L")
expect(not map:IsShown(), "pressed again, the quest log key closes it")
press("L")
expect(isSameBox(getMapBox(), leftAs), "and opens it where it was, as large: " .. table.concat(getMapBox(), ","))
expect(addon.Log.isOpen(), "with its log")
-- Full screen, left so by the map key: opened full screen again; the quest log key: the same windowed map, its log
map:HandleUserActionMaximizeSelf()
wait(0.5)
press("M")
press("M")
expect(map:IsShown() and map:IsMaximized(), "the map key opens it full screen, as it was left")
press("L")
expect(isSameBox(getMapBox(), leftAs), "the quest log key: the windowed map where it was, as large")
expect(addon.Log.isOpen(), "with its log")
press("M")
expect(map:IsShown() and map:IsMaximized(), "the map key: full screen again")
press("M")
expect(not map:IsShown(), "and closed")
map:HandleUserActionMinimizeSelf() -- (the player's size back to windowed)
map:Hide()
-- The log put away by the arrow: the map key opens the map alone, where it was, as large; the quest log key the same
-- map with its log, and the map key then puts the log away, the map staying as it was
addon.settings.arePanelsHidden = true
press("M")
expect(isSameBox(getMapBox(), leftAs) and not addon.Log.isOpen(), "the map alone, where it was, as large")
press("M")
press("L")
expect(isSameBox(getMapBox(), leftAs) and addon.Log.isOpen(), "the quest log key: the same map with its log")
press("M")
expect(map:IsShown() and isSameBox(getMapBox(), leftAs), "the map key puts the log away, the map as it was")
expect(not addon.Log.isOpen(), "without its log")
press("M")
expect(not map:IsShown(), "and closes it")
-- (back as it came, for the scenarios after)
addon.settings.arePanelsHidden = false
MapDock.resetSize()
MapDock.resetMapSpot()
