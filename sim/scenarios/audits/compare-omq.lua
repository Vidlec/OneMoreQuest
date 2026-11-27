--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- The comparison's play (sim/lib/compare.lua) with these addons loaded: run each of compare-omq, compare-questie and
-- compare-none, and read them side by side.
require("compare").run(
    { setProfile = setProfile, moveTo = moveTo, accept = accept, wait = wait, key = key },
    "OneMoreQuest"
)
