-- Counting kills for drop objectives on this client, whose combat log addons may no longer read: a creature
-- the player fights and kills counts, one someone else tapped does not.
setProfile({ level = 33, race = "Scourge", class = "MAGE" })
moveTo(1420, 0.85, 0.32) -- Tirisfal Glades, near the Scarlet Monastery
accept(1113) -- Hearts of Zeal: hearts dropped by the Scarlet Crusade
wait(0.5)
local dropperId = G.LibQuestieDB.Item.Get(G.LibQuestieDB.Quest.Get(1113, "objectives")[3][1][1], "npcDrops")[1]
expect(dropperId ~= nil, "Hearts of Zeal's heart drops from a creature")

kill(dropperId, false)
kill(dropperId, false)
kill(dropperId, false)
kill(dropperId, false, true) -- tapped by someone else
wait(0.5)

local omq = require("addons").byName["onemorequest"].private
local objectiveIndex
for index, objective in ipairs(omq.QuestState.getQuest(1113).objectives) do
    if objective.type == "item" then
        objectiveIndex = index
    end
end
local progress =
    omq.KillCounter.getProgress(1113, objectiveIndex, omq.QuestState.getQuest(1113).objectives[objectiveIndex])
expect(progress and progress.kills == 3, "the three kills the player made are counted, not the tapped one")

-- Where the game hides unit identities from addons (PvP, some instances), a kill cannot be told apart: it
-- counts nothing, and nothing breaks
restrict({ identity = true, threat = true })
kill(dropperId, false)
wait(0.5)
local hidden =
    omq.KillCounter.getProgress(1113, objectiveIndex, omq.QuestState.getQuest(1113).objectives[objectiveIndex])
expect(hidden and hidden.kills == 3, "a kill with a hidden identity is not counted, and raises no error")
restrict({})

-- Farming through nameplates, untargeted, with hearts dropping a quarter of the time: every kill counts
seed(7)
local drops = hunt(dropperId, 20, 0.25, "nameplate")
local farmed =
    omq.KillCounter.getProgress(1113, objectiveIndex, omq.QuestState.getQuest(1113).objectives[objectiveIndex])
expect(
    farmed and farmed.kills == 23,
    "20 nameplate kills counted on top of the 3 (got " .. tostring(farmed and farmed.kills) .. ")"
)
expect(drops >= 1 and drops <= 12, "about a quarter of them dropped a heart (got " .. drops .. ")")

-- Killed without ever being a unit the player sees (area damage with nameplates off): the game gives an addon
-- no way to know it was the player's, so it is not counted
kill(dropperId, { loot = false, via = "unseen" })
wait(0.2)
local unseen =
    omq.KillCounter.getProgress(1113, objectiveIndex, omq.QuestState.getQuest(1113).objectives[objectiveIndex])
expect(unseen and unseen.kills == 23, "an unseen kill is not counted")
