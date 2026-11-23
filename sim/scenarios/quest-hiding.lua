-- Hiding a quest to pick up: from the list's menu or the map's "!", the settings' list of hidden quests bringing it
-- back; the Ahn'Qiraj War Effort's quests (the Commendation Signets) hidden unless asked for, as Questie.
setProfile({ level = 43, race = "Orc", class = "WARRIOR" })
moveTo(1454, 0.42, 0.38) -- Orgrimmar
wait(3)
local addon = require("addons").byName["onemorequest"].private
local scene = require("scene")
addon.settings.shouldShowRepeatable = true
addon.SettingsPage.apply(); wait(1)
local function isListed(questId)
    for _, quest in ipairs(addon.Availability.getQuests(addon.Model.getPlayer().zoneId, { shouldShowLowLevel = true })) do
        if quest.questId == questId then return true end
    end
    return false
end
expect(not isListed(8815), "the Commendation Signets hidden, as Questie")
addon.settings.shouldShowAQWarEffort = true
addon.SettingsPage.apply(); wait(1)
expect(isListed(8815), "shown when asked for")
addon.settings.shouldShowAQWarEffort = false
addon.SettingsPage.apply(); wait(1)
expect(isListed(2981), "A Threat in Feralas offered")
-- The menus open without errors
addon.Log.showAvailable(); wait(1)
addon.Log.openQuestMenu(2981, false); wait(0.5)
key("ESCAPE"); wait(0.5)
addon.QuestHiding.hide(2981); wait(1.5)
expect(not isListed(2981), "hidden")
-- The settings' list of hidden quests
local section
for index, each in ipairs(addon.SettingsPage.SECTIONS) do
    if each.title == "Quests to pick up" then section = index end
end
addon.Log.openSettings(section); wait(1)
local pageX, pageY
for _, item in ipairs(scene.export()) do
    if item.k == "s" and item.lines and item.lines[1] == "Which quests" and item.cl then
        pageX, pageY = item.cl[1] + item.cl[3] / 2, item.cl[2] + item.cl[4] / 2
    end
end
for _ = 1, 40 do wheel({ pageX or 1100, pageY or 400 }, -1) end
wait(0.5)
expectText("Hidden quests")
expectText("A Threat in Feralas")
expectText("Show again")
saveScene("hidden-list")
addon.QuestHiding.unhide(2981); wait(1.5)
expect(isListed(2981), "brought back")
