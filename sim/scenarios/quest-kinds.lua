-- Quests by kind: the "!" and "?" in each kind's colour, event quests while their event runs, raid quests switched
-- off, and the "!" button at the map's lower right that hides the quest givers on the map (not the minimap).
G.GetMinimapShape = function()
    return "SQUARE"
end
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29) -- Grom'gol Base Camp, Stranglethorn
for _, questId in ipairs({ 185, 190 }) do
    pcall(accept, questId)
end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local scene = require("scene")
key("M")
wait(2)

---Counts the map's quest giver marks, and the pictures every "!" and "?" is drawn with.
local function count()
    local givers, pictures = 0, {}
    for _, item in ipairs(scene.export()) do
        local atlas = tostring(item.atlas or "")
        atlas = ({
            questnormal = "QuestNormal",
            trivialquests = "TrivialQuests",
            questdaily = "QuestDaily",
            questlegendary = "QuestLegendary",
            questturnin = "QuestTurnin",
        })[atlas:lower()] or atlas
        if
            atlas == "QuestNormal"
            or atlas == "TrivialQuests"
            or atlas == "QuestDaily"
            or atlas == "QuestLegendary"
            or atlas == "QuestTurnin"
        then
            pictures[atlas] = (pictures[atlas] or 0) + 1
            if atlas ~= "QuestTurnin" then
                givers = givers + 1
            end
        end
    end
    local text = {}
    for atlas, number in pairs(pictures) do
        text[#text + 1] = atlas .. "=" .. number
    end
    table.sort(text)
    return givers, table.concat(text, " ")
end

local shown, pictures = count()
io.write(string.format("KINDS givers shown %d (%s)\n", shown, pictures))
saveScene("map-givers")
-- The "!" button: hides the givers on the map
local toggle
for _, child in ipairs({ G.WorldMapFrame:GetChildren() }) do
    if child.icon and child:IsShown() and child:GetWidth() == 30 then
        toggle = child
    end
end
expect(toggle ~= nil, 'the "!" button is on the map')
local left, bottom = toggle:GetRect()
io.write(string.format("KINDS button at %.0f, %.0f\n", left or -1, bottom or -1))
toggle:GetScript("OnClick")(toggle)
wait(1.5)
local hidden = count()
io.write(string.format("KINDS givers after the button %d\n", hidden))
expect(hidden < shown, 'fewer "!" with the givers hidden')
saveScene("map-givers-hidden")
toggle:GetScript("OnClick")(toggle)
wait(1.5)
expect(count() == shown, "back again")
-- Every kind in a colour of its own: the giver marks recoloured
addon.settings.questIconNormal = "purple"
addon.SettingsPage.apply()
wait(1.5)
saveScene("map-givers-purple")
addon.settings.questIconNormal = "gold"
-- Event quests and raid quests switched off: what is offered changes, nothing breaks
io.write(
    string.format(
        "KINDS events running: winterVeil %s, darkmoonFaire %s, hallowsEnd %s\n",
        tostring(addon.Events.isActive("winterVeil")),
        tostring(addon.Events.isActive("darkmoonFaire")),
        tostring(addon.Events.isActive("hallowsEnd"))
    )
)
addon.settings.shouldShowEvents, addon.settings.shouldShowRaid = false, false
addon.SettingsPage.apply()
wait(1.5)
addon.settings.shouldShowEvents, addon.settings.shouldShowRaid = true, true
addon.SettingsPage.apply()
wait(1.5)
key("M")
wait(1)
-- The settings page with the icon colours
local section
for index, each in ipairs(addon.SettingsPage.SECTIONS) do
    if each.title == "Quests to pick up" then
        section = index
    end
end
addon.Log.openSettings(section)
wait(1)
expectText("Include event quests")
expectText("Quest icons")
saveScene("settings-icons")
