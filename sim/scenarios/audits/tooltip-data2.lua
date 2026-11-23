setProfile({ level = 36, race = "Troll", class = "HUNTER" })
moveTo(1434, 0.325, 0.29)
wait(2)
local addon = require("addons").byName["onemorequest"].private
local D = addon.Database
local wanted = { ["Goblin Sponsorship"] = true, ["Panther Mastery"] = true, ["Bloodscalp Ears"] = true, ["Hunt for Yenniku"] = true, ["Raptor Mastery"] = true }
for _, questId in ipairs(D.getQuestIds()) do
    local name = D.getQuestField(questId, "name")
    if wanted[name] then
        local text = D.getQuestField(questId, "objectivesText")
        local step = addon.Chain.getStep(questId)
        local stepText = "-"
        if type(step) == "table" then
            local parts = {}
            for k, v in pairs(step) do if type(v) ~= "table" then parts[#parts + 1] = k .. "=" .. tostring(v) end end
            stepText = table.concat(parts, " ")
        end
        io.write(string.format("TIP %d %s [%s] req %s xp(36) %s xp(30) %s | %s | chain %s\n", questId, name, tostring(D.getQuestField(questId, "questLevel")),
            tostring(D.getQuestField(questId, "requiredLevel")), tostring(D.getQuestExperience(questId, 36)), tostring(D.getQuestExperience(questId, 30)),
            type(text) == "table" and table.concat(text, " ") or tostring(text), stepText))
    end
end
