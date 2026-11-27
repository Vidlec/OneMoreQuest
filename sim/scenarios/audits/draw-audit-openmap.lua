--@login race=Orc,class=WARRIOR,level=42
--@addons QuestieDB, OneMoreQuest, OpenMap
-- Everything OneMoreQuest draws on the world map and the minimap, and what it costs frame by frame while the player
-- uses them (sim/lib/drawaudit.lua): on OpenMap's joined-up map.
require("drawaudit").run({
    setProfile = setProfile,
    moveTo = moveTo,
    accept = accept,
    wait = wait,
    key = key,
    hold = hold,
    zoomMinimap = zoomMinimap,
    expect = expect,
})
