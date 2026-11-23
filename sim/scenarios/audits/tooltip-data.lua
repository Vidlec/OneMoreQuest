-- Real data for the tooltip mockups: quests in the log and to pick up near Grom'gol, with what a tooltip could say.
setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
for _, questId in ipairs({ 190, 185, 194, 568 }) do pcall(accept, questId) end
wait(3)
local addon = require("addons").byName["onemorequest"].private
local D = addon.Database
local function dump(questId)
    local rewards = addon.QuestState.getRewards(questId)
    local items = {}
    for _, item in ipairs(rewards.items or {}) do items[#items + 1] = tostring(item.name) .. " x" .. tostring(item.count) end
    local choices = {}
    for _, item in ipairs(rewards.choices or {}) do choices[#choices + 1] = tostring(item.name) end
    local entry = addon.Model.composeEntry(questId, addon.Model.getPlayer())
    local objectives = {}
    for _, objective in ipairs(entry and entry.objectives or {}) do objectives[#objectives + 1] = tostring(objective.text or objective.label) end
    local chain = addon.Chain.getStep(questId)
    io.write(string.format("TIP %d | %s | level %s req %s | xp %s | money %s | items %s | choices %s\n", questId, tostring(D.getQuestField(questId, "name")),
        tostring(D.getQuestField(questId, "questLevel")), tostring(D.getQuestField(questId, "requiredLevel")), tostring(rewards.experience), tostring(rewards.money),
        table.concat(items, ", "), table.concat(choices, ", ")))
    local text = D.getQuestField(questId, "objectivesText")
    io.write("TIP   objectivesText: ", type(text) == "table" and table.concat(text, " ") or tostring(text), "\n")
    io.write("TIP   description: ", tostring(addon.QuestState.getDescription(questId)), "\n")
    io.write("TIP   objectives: ", table.concat(objectives, " / "), "\n")
    io.write("TIP   chain: ", chain and (tostring(chain.index) .. " of " .. tostring(chain.total)) or "-", "\n")
    local starters = D.getQuestField(questId, "startedBy")
    local finisher = D.getQuestField(questId, "finishedBy")
    local npc = starters and starters[1] and starters[1][1]
    local finishNpc = finisher and finisher[1] and finisher[1][1]
    io.write("TIP   giver: ", tostring(npc and D.getNpcField(npc, "name")), " | turn in: ", tostring(finishNpc and D.getNpcField(finishNpc, "name")), "\n")
end
for _, questId in ipairs({ 190, 185, 194, 568 }) do pcall(dump, questId) end
-- Quests to pick up here
local count = 0
for _, questId in ipairs(addon.Availability.getZoneQuestIds and addon.Availability.getZoneQuestIds(33) or {}) do
    if count < 6 and addon.Availability.isAvailable and addon.Availability.isAvailable(questId) then
        count = count + 1
        pcall(dump, questId)
    end
end
