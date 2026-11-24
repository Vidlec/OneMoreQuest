--@login race=Scourge,class=MAGE,level=30
-- OneMoreQuest in Czech: every window drawn, nothing of its own left in English where a translation is due, and
-- no text cut short for room (Czech runs longer). Names from the game stay English and are not counted.
setProfile({ level = 30 })
moveTo(1413, 0.52, 0.30) -- The Barrens
local addon = require("addons").byName["onemorequest"].private
for _, questId in ipairs({ 869, 865, 872, 891, 914, 962, 1486, 862 }) do
    accept(questId)
end
complete(869)
wait(1.5)
addon.Locale.setLanguage("cs")
wait(1)
key("M")
wait(1)

local cut = {}
local function collectCut(frame, where)
    if not frame or not frame.IsVisible or not frame:IsVisible() then
        return
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.IsTruncated and region:IsVisible() and region:IsTruncated() then
            local text = region:GetText() or ""
            cut[#cut + 1] = where .. ": " .. text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        collectCut(child, where)
    end
end
local function look(where)
    wait(0.5)
    saveScene(where)
    collectCut(G.TrailheadLog, where)
    collectCut(G.TrailheadTracker, where)
end

look("quests")
addon.Log.selectQuest(891)
look("quest-page")
click("Dostupné")
look("available")
for index = 1, #addon.SettingsPage.SECTIONS do
    addon.Log.openSettings(index)
    look("settings-" .. index)
end
addon.Log.toggleChronicle()
for index = 1, #addon.ChroniclePage.CHAPTERS do
    addon.ChroniclePage.chapterIndex = index
    addon.Log.refresh()
    look("chronicle-" .. index)
end

local missing = {}
for english in pairs(addon.Locale.missing) do
    missing[#missing + 1] = english
end
table.sort(missing)
for _, english in ipairs(missing) do
    print("MISSING", english)
end
for _, text in ipairs(cut) do
    print("CUT", text)
end
print("SUMMARY", #missing, "untranslated,", #cut, "cut short")
expect(#missing == 0, "every phrase OneMoreQuest showed has its Czech (" .. #missing .. " without)")
