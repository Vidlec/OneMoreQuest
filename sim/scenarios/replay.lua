-- Playing back a session recorded in the game (here a sample in the recorder's shape): the character, the
-- quest it accepted, the fight that counts as a kill for its drop objective, its count, and where it walked.
local count = replay(scenariosDir .. "/fixtures/sample-recording.lua")
expect(count == 10, "every recorded moment played")
local omq = require("addons").byName["onemorequest"].private
expect(G.C_QuestLog.GetLogIndexForQuestID(844) ~= nil, "the recorded quest is in the log")
local objective = omq.QuestState.getQuest(844).objectives[1]
expect(objective.fulfilled == 1, "with the recorded count of 1 beak")
local progress = omq.KillCounter.getProgress(844, 1, objective)
expect(progress and progress.kills == 1, "the recorded fight counted as a kill for the beaks")
local x, y = require("game").profile.x, require("game").profile.y
expect(math.abs(x - 0.505) < 0.001 and math.abs(y - 0.29) < 0.001, "the character stands where the recording ends")
