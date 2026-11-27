-- What the minimap tells the hover of: its spawn icons and areas, on a square minimap (icons on their canvas)
G.GetMinimapShape = function()
    return os.getenv("MINIMAP_SHAPE") or "SQUARE"
end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({
    185,
    186,
    187,
    188,
    189,
    190,
    191,
    192,
    193,
    194,
    195,
    196,
    197,
    568,
    569,
    570,
    572,
    573,
    581,
    582,
}) do
    accept(questId)
end
local addon = require("addons").byName["onemorequest"].private
addon.MinimapPins.isCanvasOff = os.getenv("CANVAS_OFF") == "1"
wait(2)
addon.MinimapPins.refresh()
wait(0.5)
local spots, areas = addon.MinimapPins.getDrawn()
io.write(string.format("HOVER standing: %d spots, %d areas\n", #spots, #areas))
face(45)
hold("W", 2)
wait(0.3)
spots, areas = addon.MinimapPins.getDrawn()
io.write(string.format("HOVER walked: %d spots, %d areas\n", #spots, #areas))
key("M")
wait(1.5)
spots, areas = addon.MinimapPins.getDrawn()
io.write(string.format("HOVER map open: %d spots, %d areas\n", #spots, #areas))
for index = 1, math.min(3, #spots) do
    io.write(
        string.format(
            "HOVER spot %d: %.1f, %.1f quest %s\n",
            index,
            spots[index].x,
            spots[index].y,
            tostring(spots[index].questId)
        )
    )
end
