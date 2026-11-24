setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
local accepted = {}
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
    accepted[#accepted + 1] = questId
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local scene, sim, W = require("scene"), require("sim"), require("widgets")
key("M")
wait(2)
addon.Focus.set(accepted[4])
wait(1)
io.write(
    "FOLLOWED ",
    tostring(addon.Focus.get()),
    " selected ",
    tostring(addon.Log.getSelectedQuestId()),
    " map focus ",
    tostring(addon.MapMarks.getFocusedQuestId()),
    "\n"
)
local draws = 0
local original = addon.MapMarks.draw
addon.MapMarks.draw = function(...)
    draws = draws + 1
    return original(...)
end
scene.input({ type = "move", x = 757, y = 225 })
wait(1)
io.write(
    "HOVERED quest: ",
    tostring(addon.Log.getHoveredQuestId()),
    " map focus ",
    tostring(addon.MapMarks.getFocusedQuestId()),
    " draws ",
    draws,
    "\n"
)
local focus = sim.motionFocus
local chain, f = {}, focus
while f and #chain < 8 do
    chain[#chain + 1] = tostring(f.GetName and f:GetName() or f)
    f = f.GetParent and f:GetParent()
end
io.write("PARENTS ", table.concat(chain, " < "), "\n")
