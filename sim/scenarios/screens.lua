-- The map and OneMoreQuest's window on screens players have: with the UI scale off (the game draws the
-- interface pixel for pixel) and on. Each time the window must be wholly on screen. (Lying over the minimap is
-- fine: the game's own windows do while open.)
local W = require("widgets")

setProfile({ level = 30, race = "Scourge", class = "MAGE" })
moveTo(1413, 0.52, 0.31)
accept(844)
wait(0.5)

local function rect(frame)
    local found = W.computeRect(frame)
    return found and { left = found[1], bottom = found[2], right = found[3], top = found[4] }
end

local SCREENS = {
    { 1366, 768 },
    { 1920, 1080 },
    { 2560, 1440 },
    { 3440, 1440 },
    { 1920, 1200 },
    { 1920, 1080, 1.0 },
    { 1920, 1080, 0.8 },
    { 2560, 1440, 1.0 },
}
for _, size in ipairs(SCREENS) do
    local width, height, uiScale = size[1], size[2], size[3]
    local label = string.format("%dx%d, UI scale %s", width, height, uiScale and tostring(uiScale) or "off")
    screen(width, height, uiScale)
    if not G.WorldMapFrame:IsShown() then
        key("M")
    end
    wait(0.5)
    local screenRect = {
        left = 0,
        bottom = 0,
        right = G.GetScreenWidth() * G.UIParent:GetScale(),
        top = G.GetScreenHeight() * G.UIParent:GetScale(),
    }
    local log, map = rect(G.OneMoreQuestLog), rect(G.WorldMapFrame)
    expect(log ~= nil, label .. ": the quest window is open")
    if log then
        expect(
            log.left >= -1 and log.right <= screenRect.right + 1 and log.bottom >= -1 and log.top <= screenRect.top + 1,
            string.format(
                "%s: the quest window is on screen (it reaches %d of %d)",
                label,
                math.floor(log.right),
                math.floor(screenRect.right)
            )
        )
    end
    expect(map and map.left >= -1 and map.top <= screenRect.top + 1, label .. ": the map is on screen")
end
screen(1366, 768)
