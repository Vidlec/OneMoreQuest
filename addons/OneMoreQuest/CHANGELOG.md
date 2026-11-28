# Changelog

What changed in each version of OneMoreQuest. A release takes its notes from its own section here.

## 0.16.2

**New**

- A Wowhead link for every quest: "Wowhead" at the end of the line under a quest's title, and "Wowhead link" in the quest menus of the quest list, the Available tab and the tracker. The game opens no web page for an addon, so a small panel opens beside it with the link selected: Ctrl+C copies it, the panel says so and closes, Esc or a click elsewhere closes it. It opens Wowhead's Classic database in the game's language where Wowhead has a site in it.

**Fixed**

- An elite or rare quest creature's nameplate shows the game's elite mark again: OneMoreQuest's icon stood right over it. The icon now stands before the elite mark (or a raid mark), its glow clear of it, at every icon size; on a plain creature's plate it stays where it was.

## 0.16.1

**Fixed**

- M and L work as the game's own keys do, each with its own version of the map: M the map as you left it (full screen or not, the quest log as the arrow says), L the map with its quest log. A key closes its own version, and on the other's it brings out its own instead of closing the map: the full-screen map, then L, shows the map with the quest log; M then makes it full screen again (it closed the map, and the map opened small from then on). Each opens the map where you moved it and as large as you made it.

## 0.16.0

**New**

- What a quest unlocks, and what it needs. A quest that opens others shows a small key with "+2" (how many) in the tracker and in the quest window's list; its tooltip and its page name them, under "Before and after": the quests that must be done first and the quests it opens.
- Quest diagram: a window of its own, opened from a quest's page ("Quest diagram"). The whole chain as a tree from top to bottom, what comes before above and what follows below, each quest with its level, where it stands for you (done, in your log, ready to take, locked) and its giver; a click on a quest shows its full page beside the tree. Tall and wide trees fit themselves to the window, or scroll: drag to move, Shift and the wheel go sideways, Ctrl and the wheel or the buttons zoom. The window can be resized by its corner.
- The Available tab tells you what to do next. Its quests come in sections: Pick up now, Opens from your log (hand in a quest you have), Opens after a pick-up, Needs a level, Needs something else; each says what opens it and how many steps away it is, with its experience and how far its giver is. All, Now, Soon and Later narrow the list.
- The quest window can be resized with the map: drag the grip at its lower right corner. Down makes the map larger and the window as tall beside it, with more rows; right makes its page wider; the text stays as it is. Hold Shift to scale the window, text and all, or Ctrl to size the quest window alone. A right click puts the usual size back. With OpenMap, the grip sizes the map through OpenMap's own, and the reset puts OpenMap's map back to its usual size where it stands.
- The map and the quest log open as the game's own do: M opens the map, L the map with the quest log beside it; the arrow on the map's edge shows or hides the log for good, as the game's own button does.
- The quest window's list shows how many of your party are on each quest (a small group mark with the count), as the game's own log does.
- Quest areas have a new look, Shadows (Settings > Map and minimap, Drawn as): a soft tinted shadow where each quest's spawns are, no rings and no lines, the quietest on the map and the lightest to draw. Ovals and Traced stay. In Shadows the settings show what applies to it: Shadow strength in place of Fill and Outline.
- The quest that drops from a creature or a chest, picked on the Available tab, shows where it drops with the same areas and marks as your own quests, in the look you chose.
- The slash command is /omq (and /onemorequest); every mention of the addon's old name is gone.

**Fixed**

- Party members with Questie no longer see "Questie: [ERROR] Error reading QuestieComm message" over and over: OneMoreQuest sent your quest log in a form Questie stopped reading in its newer versions. It now sends the form every Questie version reads (old ones too), sends nothing until it has heard a Questie in the party, and only what that version is known to understand, so a later change of Questie's messages makes OneMoreQuest quiet rather than noisy.
- The world map with many quests tracked is far lighter: the areas and spawn marks stay on the map and are only moved as it zooms and pans, instead of being drawn again for every view. (/omq drawing classic puts the old drawing back, to tell a fault apart; /omq drawing kept the new one.)
- Pointing at a quest in the quest window's list no longer makes every other quest's areas and marks blink on the map: only the quest pointed at changes.
- A quest taken, done or progressed sorts the spawn marks again only in the zones where it has spawns, and once; the other zones' marks stay as they stand.
- With OpenMap, the map moved by the quest window's title strip stays where you drop it (it snapped back), and the grip resizes the map.
- The chronicle's days now keep the day's notable loot (green and better): on WoW Forever none was ever kept, since the item's quality was asked of a function this client does not have.
- Herbs and ore you gather are now counted by kind in the chronicle's days (the same cause).
- With Spoilers on, quest items you loot are remembered (the same cause).
- Items in the chronicle (a quest's reward, the day's loot) show their names in their quality's colours.
- With MapUtils, each dungeon's quest mark sits on MapUtils' own entrance icon, one mark per entrance, instead of beside it.

## 0.15.2

**Fixed**

- Quest details on a page of their own: going back from a quest's page to the list left the page's scroll bar standing beside the window.

## 0.15.1

**New**

- Quest details on a page of their own, as the game's own quest log (Settings > Quest window > Quest details): a click on a quest opens its page in the list's place, with its buttons under it, and the strip over it goes back to the list. The quest window is then half as wide beside the map. A quest opened from the map or the tracker opens on its page; the focus moving only highlights its quest in the list. With a controller, A opens the page and B goes back. "Beside the list" stays the default.

## 0.15.0

**New**

- Controller support: with the game's gamepad interface on (WoW Forever's Gamepad UI), OneMoreQuest's quest window stands in for the game's quest log beside the map, made for the controller. It works the controller entirely by itself (its own cursor, buttons, prompts and menus) and never touches the game's own controller navigation, so the game never refuses its own actions ("blocked", a dead d-pad), and it leaves the map to the game's own keys. It switches with the interface as it changes; in a fight it lets the controller go and takes it again after.
  - The map opens with the quest log holding the controller, its cursor on the open quest. D-pad left (with nothing to the left) goes to the map; the map's own Quests (d-pad right) comes back. One focus glow goes round the map and the quest log together, and the prompts under the window look like the map's own.
  - The list and the quest's details stand side by side, as with the mouse. The details follow the cursor as it walks the list; A or d-pad right goes into them, d-pad left or B comes back to the quest. Up and down stay in the list or in the details; zone headings are stops, folded or not.
  - The right stick scrolls the list or the details, whichever the cursor is in, and the cursor stays in the middle as it scrolls (the details follow once it rests); the camera is left alone meanwhile.
  - X tracks or untracks the quest, held puts it in focus or lets go (its progress runs round the button); on Available X shows the quest's giver on the map, on Dungeons the entrance. Y opens the quest's menu (Share, Abandon...); on the details, the page's buttons, which have no bar of their own with a controller. LB and RB change tabs and show beside them, as in the game's own windows; View goes to the search box; A on a dropdown opens its choices; A on the page's title links the quest in chat. B goes back one step; with nothing to go back to, it is the map's own and closes it.
  - The party on a quest's page is a row a member, with where they are with it: A shares the quest with a member who can take it, Y whispers. With a full log, Available opens with a banner that opens the quests worth dropping: each is one stop, A opens it, Y has Abandon (asked first), B closes them.
- Controller, the settings and the chronicle: their sections show as the cursor comes onto them, LB/RB go to the section before or after, A goes into the one shown and B back to its row, then out. Reset to defaults is under Y; in the journal, B closes a quest's story first.
- Controller, the tracker: the game's quests shortcut (the shortcuts' modifier held, d-pad up) gives OneMoreQuest's tracker the controller when it stands in for the game's, with its own cursor and prompts. Each quest is one stop: A focuses it (or lets go), X opens it in the quest log, Y has its menu, where its item can be put on the gamepad's action bar; B goes back to the game.
- Controller, the map: the map's own cursor points at OneMoreQuest's marks as at the game's pins, with their tooltips (details shown at once: a pad has no Shift). On a zone's map, A on a quest's mark or its area opens it in the quest log (several areas: a menu to choose) and the quest log takes the controller, its row in the middle of the list; d-pad left or B give the controller back to the map. Held A puts the quest in focus or lets go, as Alt-click does with the mouse. On a continent's or the world's map A stays the map's own.
- PvP quests can have a colour of their own (Settings > Quests to pick up, Quest icons: red to start with) and their own quest marks (Settings > Map and minimap, Your quests' marks), as dungeon, raid, event and repeatable quests have: a battleground's quest, or one the game marks PvP.
- A new colour for quests' "!", "?" and coins: pink.
- The My quests tab shows how full the quest log is, "My quests (31/40)" (amber nearly full, red full), in place of the count beside the tabs; the Dungeons tab shows no count.

**Fixed**

- The size chosen for marks on the minimap now applies to the quest givers' "!" and the turn-ins' "?" there too (they always stayed at the game's size).
- A quest ready to hand in shows its "?" on the map and the minimap even when it is not tracked (one past the game's limit of tracked quests had none until it was picked in the list).

## 0.14.1

**Fixed**

- Smoother world map with OpenMap: zooming or panning into another zone draws the quest marks once, after OpenMap has put that zone's map underneath, instead of twice.
- Zooming the world map no longer resizes every area line and spawn icon while the marks are about to be drawn again anyway, nor when the zoom ends where it started (as the map opens).
- Opening the map no longer draws the quest window beside it twice.
- Walking with a round minimap costs much less: the quest areas' pieces keep their colour, size and shape as you walk, and only their place is set again (less than half the work each second).
- A kill, the quest window, the tracker and the maps ask the game less: what it says of each quest is read once until the quest log changes, not by each of them in turn, and the zone of every spawn is worked out once.
- Opening the map again with nothing changed no longer places every quest mark anew.
- The map and the minimap keep each tracked quest's spawns and areas from one drawing to the next instead of working them all out again: a hover, the focus moving, the map opened again, a kill and walking on all make far less work and garbage (with OpenMap too, while its view stays where it is).
- A quest's areas laid out again (OpenMap putting another map underneath, a zoom) take back their own pieces, and the frames after the map opens lay out fewer pieces each, so none of them takes long.
- The Available tab opens faster the first time: what holds back each quest of your zone is worked out in the background after login.

## 0.14.0

**New**

- Spoilers: choose how much OneMoreQuest tells you, per character, in Settings > Spoilers or with /omq spoilers. Four presets: Guide (everything, as before), Hints (rough areas, who drops items without chances, how many steps a chain has), Explorer (only what you have found: givers and turn-ins you met, places where your objectives moved on, creatures you killed, dungeons you entered; the map fills in as you play, and respects the map's fog) and Purist (your log and the tracker's counts). Nine kinds can be fine-tuned: quests to pick up, where objectives are, where to hand in, what drops the items, creatures you need, quest chains, rewards and numbers, dungeons, hints.
- "Need a hint?" on the quest page and in the tracker's right-click menu, wherever something is held back: one step at a time, the zone, roughly where, then exactly where. With "Offered", it suggests itself on a quest you have been stuck on. Holding Alt over the world map shows everything for a moment.
- The Chronicle marks quests found yourself (done with spoilers on and no hint) with a star, and counts them and the hints used.
- The tracker's sort menu switches the spoiler preset.
- The quest page header has the game's gold filigree and corner flourishes, and your faction's wax seal.
- Settings' choices are dark bronze-rimmed slabs, the chosen one gold-rimmed and lit from within.
- A dungeon or raid quest's tooltip names its dungeon: "Dungeon quest · Razorfen Downs" (unless your Spoilers keep the dungeon back).
- "Focus quests you accept" (Settings > Tracker): off, the quest you were on stays in focus when you accept another.
- A quest page with nothing to scroll has no scroll bar strip: the parchment, its header and the rewards reach the window's edge. The wax seal is bigger.

**Fixed**

- Zooming the world map in from far out no longer shows a dark blot under your party (and you beside them): the soft patch under each member's dot keeps its size while the map zooms.
- A stray "Only when asked" (or another settings word) no longer shows in the top left corner of a quest's page after you open the settings.
- The tracker stays where you put it after a login: the game no longer moves it back from its own layout file.
- The quest page's scroll bar reaches its end when the page is scrolled to its end.
- Resizing the map (and the quest window beside it) redraws the page: its scrolling and scroll bar follow the new height.
- The quest page header fits its lines: a tall one (a long title, the narration's Play row) no longer covers the page's first lines, and there is no empty band under its last line, with or without the Play row.

## 0.13.1

**New**

- A quest chain on the quest page (My quests and the Available tab) shows what the rest of it gives, above its steps, in the game's framed parchment panel: the last quest's reward (each item's framed icon with its name beside it, the items to choose between side by side), and everything left from this quest on: experience with its icon, money, reputation and how many more items come on the way.
- The steps of a chain still to come open where they are: a click on one in your log opens it on My quests, any other on the Available tab at its zone, the steps not yet available too; its tooltip says after which step it can be picked up.
- A step of a chain already done opens in the Chronicle: its story in the Journal (its tooltip says when it was handed in), or the quests done before the Chronicle began.

**Fixed**

- The tracker stays under every window, as the game's own does: the map and the quest window moved over it no longer show its lines through their pages.
- A chain's step opened on the Available tab shows its page even when it is hidden there (a low-level quest, or one not to be taken yet with low-level quests hidden).
- The first opening of the map after you log in no longer waits on the quest window being built: a few seconds after login, out of a fight, it is made and drawn once where it cannot be seen, so its pictures are already loaded.
- The quest page's header art meets the line beside the quest list: its darker left rim no longer stands there as a second, slightly offset edge.
- Switching the language the first time in a session now takes effect at once.
- One part of the add-on failing no longer stops the parts after it; a damaged saved-variables file or saved dungeon record no longer stops the add-on loading.
- Holiday quests follow the calendar across midnight and into a new month.
- A creature's minimap icon no longer depends on which quest used it first; a quest chain has the same length and position whichever of its quests you look at.
- Dungeon entrances are no longer learned from the graveyard, an inn or a summons in a city.
- A repeatable quest handed in can be taken again in the same session.
- The quest-log-full suggestions judge "another continent" from where the quest leads now, not where it was picked up.
- The Available tab: quests the game offers respect your own filters (hidden quests, raids, events); an offer for a quest that has since closed is forgotten instead of listed and noted as missed; a quest whose prerequisite has an either-or alternative counts the alternative; a quest no longer appears twice.
- Profit: an item the game does not have no longer stays "loading"; quest drops in dungeons are shared with the party; herb and ore nodes count every time you gather them; fishing is no longer counted as opening chests (the Chronicle says "fished").
- Party sync: only your group can ask for your quest log; joining a group no longer makes everyone re-send their whole log; a malformed Questie message can no longer freeze the game; grey quests are never accepted automatically.
- Tracker: no longer drifts at login when its size is not 100%; the fold button works while it is folded for a fight; the ready sound plays for quests not shown.
- Quest page and log: Dungeons tab buttons no longer stay over the settings and the Chronicle; a drop-zone link no longer changes the Available tab's choice; a dungeon with no known level no longer causes an error; a quest chosen from the map or tracker is shown even with a search typed; quests opened on the Dungeons tab show on the map.
- Map: a reopened map highlights the quest that is selected; "Also in" cycling gets past a dungeon; clearing the add-on's waypoint no longer removes one you placed; quests no longer lose their marks; the focused quest's marks no longer hold spawns twice.
- Minimap: the followed quest's glow comes back when its mark does; a failed draw no longer leaves old marks; with minimap marks off, the add-on's own arrow and party dots are hidden too.
- Chronicle: a quest is no longer both "Luckiest" and "Unluckiest"; the journal shows older quests past 300 ("Show older quests"); searching is quicker; Czech month and weekday names.

## 0.13.0

**New**

- Low-level quests stay hidden unless their chain leads to a dungeon's (or a raid's) quest in your range: a lead-in worth doing still shows, with where it leads. Under Quests to pick up, "Still show those leading to a dungeon quest" (on) and "Still show those leading to any quest in range" (off; earlier versions showed those).
- Your quests' marks by kind: a dungeon, raid, event or repeatable quest in your log can show its coin in the kind's colour, with the game's own icon for the kind (the dungeon swirl, the raid's, the event horn, the recurring arrows) in place of what to do, or both. On the map, the minimap, the tracker and the quest log, under Map and minimap, Your quests' marks; the "!" and "?" stay the game's.
- The tracker reads over grass, leaves, rock and snow: its text has a thin black outline by default. Under Tracker, Text: the font (the game's own, Friz Quadrata, Arial Narrow, Morpheus, Skurri, and the shipped Marcellus and Metamorphous, plus any font shared through SharedMedia), the outline (none, thin, thick), the shadow (off, soft, strong), high-contrast text, and the size of titles and of objectives. In Czech a font without the Czech letters is drawn in its look-alike.
- The tracker's dark background is now Off, Dark box, Soft bands (dark only behind each zone and quest) or On hover (the box while the pointer is on the tracker).
- The tracker's title band: a gold arrow (or a click anywhere on the band) folds the tracker and unfolds it; the log's count beside the title, orange when two places or fewer are left; how many quests are ready. Pointing at the band brings in filters: All, Here (the zone you are in, following you), Ready and Focus, remembered, with the chosen one's icon left on the band; a sort button (as tracked, nearest, by level, most done); and a resize button.
- Resizing the tracker: the resize button shows its outline at the most it may take, with arrows to drag on the left edge (width), the bottom edge (height) and the bottom-left corner (both), its size written in it; Done, Put back, or Escape. Its height can also be set under Tracker, Look and place ("Height"); past it, the tracker scrolls. This replaces the grip at the title's left end.
- Click a quest's icon in the tracker to put it in focus, or take the focus off.
- Hovering a quest in the tracker shows what each item still to get drops from, with the chance.
- Item tooltips (your bags, the bank, links) name the quests an item is for: each quest's level and experience, and how many it wants and how many are still to get.
- In a fight, a click on a quest in the tracker opens the quest window by itself (the game opens no map in a fight); move it by its title. If it is still open when the fight ends, the map opens with it.
- Out of a fight, drag the quest window's title strip to move the map with it; the map opens there again. /omq reset puts it back.
- Alt-click a quest's area on the world map to focus that quest and open it in the quest window; where areas overlap, a menu asks which. (Ctrl-click stays the game's waypoint.)
- With Find Herbs or Find Minerals on, the minimap's quest spawn markers stay off the spots where a herb or a vein of that kind can show, so they never cover one; once you gather a node, the marker on its spot comes back while the node grows again.
- A full quest log takes one line at the top of the list: the count, a bar, and a "to drop" button that opens a small window with the quests worth dropping and their Abandon buttons.
- OneMoreQuest keeps its own last Lua errors with where they happened (/omq errors lists them, /omq errors clear empties the list), so an error seen in the game can be looked at afterwards.

**Fixed**

- Spoken Places: with the quest window docked and no room for its place story to the window's right, the story no longer opens over the map by itself. It waits on its tab, inside the map's right edge, until you click it; it then opens over the map's right side as before, and folds back to its tab the next time the map opens. Spoken's own settings are left as they are.
- The quest log's count beside the tabs is no longer cut off ("20/20 full so…"): only the count, amber when the log is nearly full and red when it is full; the panel over the list says it in words.
- Zooming the map with many quests' areas and spawns shown no longer stutters, OpenMap's gliding zoom above all: while the zoom moves, only the quest marks follow it; the spawn marks, the areas' outlines and the walks catch up once it stops (about four times less work at each wheel step), and a zoom that changes how many spawns show draws them again only once it has stopped.
- Alt-click on the map works with OpenMap, which used to take every click on the map for its zoom.
- A creature's nameplate icon no longer covers its elite or rare dragon.
- The quests' outlines on the minimap run under your arrow and your party's dots instead of being cut round them (less to draw as you move).
- A quest you take the focus off while it is open in the quest window no longer stays highlighted on the map.
- The tracker's sort menu stays open as the pointer moves onto it.

## 0.12.0

**New**

- Event quests: a holiday's or a world event's quests (the Darkmoon Faire, the Lunar Festival, Hallow's End, Winter Veil and the others) are offered on the map and in the Available list while the event runs, and only then. The game's calendar says which events run where the realm fills it in; otherwise their usual days, the Lunar Festival's by year, Noblegarden on Easter Sunday and the Darkmoon Faire in its week of each month. Switch them off under Quests to pick up, "Include event quests".
- Raid quests can be left out of the map and the Available list: "Include raid quests".
- Quest icons coloured by kind: the "!" and "?" of event, raid, dungeon, repeatable, low-level and every other quest each take a colour of your choosing (gold, blue, green, orange, purple, red or grey), on the map, the minimap, the zone map, the Available and Dungeons lists and the tooltips. They start as event green, raid orange, repeatable blue and low level grey; "Put back" sets the game's own colours.
- A "!" button at the lower right of the map hides the quest givers' marks on the map, and brings them back; the quest you selected on the Available tab keeps its mark, and the minimap keeps them all. It makes room for other addons' buttons.
- Areas: their fill and their outline can each be switched off (outlines alone, or the fill alone), and each has its strength, from 10% to 200% of the look chosen. A part switched off is not drawn at all, so the map has less to draw.
- Tracker: its opacity, the whole of it with its item buttons, and how dark its background is, under Tracker, Look and place.
- Hide any quest you can pick up: right-click it in the Available list, or its giver's "!" on the map or the minimap, and choose "Hide this quest". The hidden quests are listed at the end of Quests to pick up, each with a button that brings it back; they stay hidden for every character.
- "Include low-level quests" also switches the game's own "Low-Level Quests" tracking on the minimap (its grey "!" near the NPC), as it is flipped.

**Fixed**

- The Ahn'Qiraj War Effort's quests, the cities' Commendation Signets among them, are no longer offered: the event is over on every realm, and Forever has no Commendation Officers. As in Questie, "Include the Ahn'Qiraj War Effort quests" brings them back (most of them are repeatable, so they show with repeatable quests included).

## 0.11.1

**New**

- Quest tooltips show the experience a quest gives, at the right of its title: on the quest marks of the map and the minimap (each quest a giver offers has its own), on spawn and area tooltips, in the tracker and on creatures' tooltips. Not shown once you are at the top level.
- Hold Shift over a quest's tooltip for its details: what it asks in one sentence, each objective with its count, the rewards and where to hand it in; for a quest you can pick up, the level it needs. The tooltip changes the moment Shift is pressed or let go.
- Quest tooltips always show the quest's level, and a group quest is marked as in the quest list ("[37+]" and the players icon with how many it suggests), with its kind (group, dungeon or raid quest) under the title.
- The same on every "!" and "?": OneMoreQuest's on the map and the minimap, those drawn in the game's look, the lines added under the game's own minimap tooltip, and the list at a dungeon's entrance.

## 0.11.0

**Much lighter on the game**

- The tracker, the quest window, the map and the minimap now change only what actually changed, instead of drawing everything again. A kill or a loot that counts no longer redraws the map or the minimap at all: they are drawn again only when a quest really moves on (an objective done, a quest taken or handed in).
- Minimap: laid out once for the land around you and slid under the minimap as you walk, instead of being chosen again every few steps. Icons, areas and marks move with the land exactly.
- The Available tab opens faster: which quests you can pick up is worked out in the background, a little each frame, not all at once as the tab opens.
- In the quest list and the Available tab, quests folded away under a zone are not drawn until the zone is opened.

**New**

- Spawn markers can be chosen on their own (Settings, Map and minimap, Spawn markers): icons on a glow (as before), icons on small dark plates, the game's own art (skull, chest, star), small squares, or none. Also their size on the map and on the minimap, the glow on or off, and whether the markers of quests not in focus are fainter, as strong as the focused quest's, or hidden. The icon beside a creature's nameplate follows the kind chosen.
- A new "Shapes" look for the areas: bold shapes with a bright edge in each quest's colour, after the game's own quest areas. It takes the place of the old blocky Shapes.
- On the minimap, pointing at the game's own "!" or "?" lists the quests that person offers and the ones handed in to them.
- Settings, Quest window: "Suggest quests to drop" switches off the box over the quest list that names quests worth abandoning as the log fills up.

**Changes**

- Tracker: a click on a quest opens it in the quest log, Ctrl-click focuses it (or takes the focus off), Shift-click links it in chat, as in the quest list and on the map; right-click still has everything. (A click used to focus.)
- Settings: the one "Look" choice is now two, "Areas" (light areas, shapes, none, or the game's own) and "Spawn markers". What you had picked is kept: Icons and areas = light areas with icons, Icons only = no areas with icons, Shapes = shapes with no markers, Squares = no areas with squares.
- Settings: "Game's areas" is now simply the game's own quest markers, the same as switching Map marks off; the tile and the switch show each other's state. If you had it picked, Map marks are now off.
- Switching "Map marks" off also switches on the game's own "Quest Objectives" map filter (and switching them on switches it off again), so the game's markers actually show.
- Settings: when a part is switched off (quest log, tracker, map marks, quests to pick up), its settings are greyed out, and their page has a button to switch it back on.
- Minimap: areas and spawn markers look as they do on the map (the same strength, edge and glow); they used to be drawn half see-through and looked washed out.
- Minimap: spawn icons stand on their own spawns, as on the map, no longer lined up on a grid, and they are smaller when zoomed out all the way.

**Fixes**

- The quest window's close button puts the panels away even when the game will not close the map for an addon.
- Minimap: icons, areas and marks no longer shift slightly against the land while you walk.
- Minimap: a spawn icon coming into view shows at once, not a few steps late.
- Minimap: on a square minimap, the followed quest's pointer no longer stands as a second mark in a corner while its place is already in view.
- Minimap: a "!" or "?" drawn in the game's look stood beside its place the first time it was shown.
- A quest's nameplate icon no longer covers the elite or rare ornament.
- Available tab: the number of quests beside each zone follows "Include repeatable quests" and "Include PvP quests" as soon as they are changed.
- Switching "Map marks" off brings the game's own quest markers back on the open map at once, not only when the map is next opened.

## 0.10.0

**New**

- Your quest history from Questie: its journey (each quest accepted and completed, with when and at what level, and the levels you reached) fills the chronicle with the quests you did before OneMoreQuest, with their dates. A quest both know is one entry: OneMoreQuest's own record first, Questie's filling in what it lacks. OneMoreQuest keeps a copy while Questie is on, so it stays when you turn Questie off.
- A better journal: the quests on the page, day by day, with a search (title, zone, giver or what it asked for) and filters for the day (today, yesterday, this week or any recent day), the zone, the kind of quest and the history it came from. Click a quest for its story; Back, in its header or the bar, returns to the list where you were. Quests from another addon's history are tagged with its name.
- Quest icons on nameplates: a sword over a creature your quests still need killed, a sack over one that drops what they still need, glowing in the quest's colour. Left, above or right of the nameplate, at any size, with a preview in the settings; they follow the game's nameplate scale.
- Quest dialogs: accept quests as they are offered (never grey ones) and hand them in when ready (never when there is a reward to choose or a cost). Hold Shift as you talk to answer yourself.
- Sizes for big and ultrawide screens: the tracker and the quest window each have a size (70% to 160%, text and all), and the tracker can be dragged wider or narrower by the gold grip at its title's left end.
- Tracker: order a zone's quests as tracked, nearest first, by level or by how much is done; ready quests on one line; hide objectives that are done (on the quest's page too); a dark background; show, fold or hide it in combat, and in dungeons and raids.
- Map and minimap: the size of the map's marks and of the minimap's; areas only for the quest in focus; minimap marks faded over your arrow; no marks on continent and world maps; a new look, Icons only, with no areas at all.
- Quests to pick up: low level can mean a number of levels below you, not only what the game greys out.

**Changes**

- The settings are redesigned in the game's own look for a panel of controls: dark marble, groups under the character window's carved title plates, the game's checkboxes and red buttons. Settings that need another one stand under it and grey out while it is off. Group chat has a section of its own; the map's area look moved to Map and minimap.
- The language is a dropdown with each language's flag.
- Map areas are tighter round their spawns, and a quest whose spawns all stand in one spot gets no area: its mark stands on them.
- Everything new is in Czech too, and a few long Czech lines in the Available list are shorter.

**Fixes**

- Clicking a quest's mark on the minimap, or on the map without the quest window, now opens the quest, as its tooltip says.
- Choosing the language (or resetting the settings) now switches the fonts and translated texts at once, not after a reload.
- On a square minimap, spawn icons and marks in its corners now show as soon as the corner is in view, not only as you come near.
- With OpenMap, the game's own areas look drew one zone's areas stretched over the whole joined map; each zone now gets its own.
- An area could be drawn as an outline with no fill.

## 0.9.0

**The map, rebuilt to be steady and quick**

- A quest's mark stands on one of its real spawns, the one nearest the middle of its area, worked out once from where they are in the world. It stays on that spot at every zoom, in every view and on every map, instead of a middle that could fall where nothing is.
- Zooming is smooth: every mark stays on its spot and only scales with the map, at every step. Marks are no longer moved apart where they overlap, so nothing jumps or rearranges itself while you zoom or pan.
- Zoomed out, marks are drawn smaller (down to under half size), so they cover less of the map.
- Spawn icons are thinned in steps, in the world: zooming out only takes some away and zooming in only adds them back, each on its own spawn. The map and the minimap keep the same ones, and the map is only drawn again when the zoom crosses a step.
- A quest's areas are worked out once on their zone's own map and fitted onto whatever map shows them, the minimap included, so panning and zooming never work them out again. Continent and zoomed-out maps show them too.
- Zooming across a zone's edge, marks no longer stand for a moment where the last zone had them: they wait until drawn for the new one.
- Walking creatures' and quest givers' paths are a dashed line, like a trail on a paper map, on the map and the minimap: no more dark dots at every bend.

**Quest givers and turn-ins**

- One "!" for each quest giver and one "?" for each NPC you hand quests in to: the quests of one NPC share a mark, with how many beside it, as the game counts a stack of items. Pointing at it names the NPC and lists them all. Ready and not-ready turn-ins (the grey "?") keep separate marks; a quest that starts from a dropped item keeps its own.
- An NPC who both takes quests in and gives new ones has one mark, as the game marks them: "?!", the two signs side by side, with the number of quests it has for you in all, when a quest is ready there; else the "!", its tooltip saying what you will hand in there later.

**Quest log and tracker**

- Track or untrack a whole zone at once: right-click a zone's heading in the quest log for Track all and Untrack all, or a zone in the tracker for Untrack all, as on the game's own tracker.
- The quest you choose in the list keeps its title's colour; the game's glow round it is enough to show it.

**Dungeons**

- A dungeon's page is a plan for the run, in the look of the quest pages: the game's title bar with its levels and the way in (click it to see it on the map); a bar of its quests done, in your log, to pick up and for later; the run at a glance on dark wood (experience left, money, reward items, quests done, experience in all, and how much of your level the rest would fill); then the route: Before you go (what to pick up, by place, nearest first), Inside (what each quest in your log still needs, and the quests found in there) and Hand in (where each goes after the run); then Later (what has to wait, and why) and Done here.
- Colours mean only how hard a quest is: a dungeon's levels show each end in its own colour (`30` grey, `34` yellow), and a quest you can't take yet keeps its colour with a padlock in front, instead of turning grey like a quest too low for experience.
- A dungeon's done quests are listed under it too, last, with a green check, so an all-done dungeon opens to show what you did there.

**Other map addons**

- OpenMap: on its joined-up world map, quest marks and givers show in every zone in view, placed where OpenMap draws that land, and follow as you pan.
- MapUtils: on its one map, quest marks and givers show on every zone in view; the map stays where you dragged it when OneMoreQuest's window opens beside it; its dungeon entrances carry OneMoreQuest's dungeon marks; and as it draws quest givers and turn-ins of its own, OneMoreQuest asks once whether to turn those off in MapUtils (its other icons stay).

## 0.8.5

**Changes**

- The journal's quest card is filled out: the quest's name on its zone's banner with its level, place and chain step under it; only the tiles that say something (no "0 kills" or "-" money for a quest that had none); its chain as numbered stones with the next step and how long the chain has taken; and how much of the level it filled. The list shows each quest's kind, titles on two lines instead of cut off, and each day's count.
- Quest announcements can be shown to you alone when you play solo (Settings, Tracker), in your own chat window only.
- Kill counting in a group: a one-of-a-kind creature (a named one like Fozruk, a boss) drops its quest item for everyone on the quest, so its drop chance is no longer split between party members. A party of four no longer expects 5 kills for an 86% drop.
- Available tab: quests you can't take yet show a padlock and what to do about it, such as "Needs Harpy Raiders first: you can take it now", "2 quests first, from Harpy Raiders: in your log" or "Needs level 23 · you are 18". The nearest to unlocking come first.
- My quests: once the log has 5 places or fewer left, a gauge of its places shows at the top with up to three quests worth dropping and why (grey with no experience left, on another continent, or taken days ago), each with an Abandon button that asks first. Never a quest ready to hand in, nor the one you follow. It uses the game's own log limit.
- In a group, a zone's heading has the party icon when someone could take quests of yours there: a click offers them all, a second apart, and its tooltip says who gets which. Also in the zone's right-click menu.
- Fixed: quests offered in a quest giver's greeting window (the list some givers show before the quest text) were never learned, as their quest IDs were lost while reading them.
- A new logo: a sealed quest scroll, painted by MELLE (Fantasy parchment set, OpenGameArt, CC0). It's also the icon in the game's addon list.
- The quest list lies on the game's own quest log art: its dark book behind the list, its soft yellow glow round the quest you chose, its yellow check on quests ready to hand in, and a gold glow under the zone you are in.
- The Available tab has a search, beside the location: it keeps the quests whose title, giver or start item matches, and names the other zones with matching quests, a click away.
- An objective the quest database puts nowhere on the map now says what you can do instead: how many wait in your bank, what the rest cost at the Auction House (with Auctionator) and where it comes from when that is known. Point at it to see what the quest itself says.
- The chronicle draws what it keeps. Days opens on a calendar of the month, each day shaded by the quests done. Records are framed plaques, zones are cards on their own map art with how much is done, and a journal entry is a quest card: its zone's map art as a banner, what the quest asked, and how it went on the game's reward tiles.
- Spawn icons on the map shrink as you zoom out, so they keep to where the spawns really are.
- Each quest's colour on the map comes from the quest itself, so it is the same after every reload, and there are twelve colours instead of six.
- The quest in focus stands out more on the map and the minimap: its area is filled and edged more strongly, and its spawn icons are a little larger and glow brighter.
- A creature's patrol is drawn as a trail, on the map and the minimap: footsteps along its way, a ring where it turns, both ends filled in. Point at the trail itself (not near it) for the quest and who walks there.
- On the minimap, spawn icons no longer go missing near other addons' frames: under one, a spawn steps beside it, and frames you cannot see take no room.
- Map marks sit closer together: spawn icons on a finer grid, nearly touching, and quest marks no longer keep as wide a berth from each other or from other addons' pins, so each stays nearer its real spot.
- Tell your group in chat, as Questie can: when a quest is ready to hand in, and when an objective is done ("OneMoreQuest: Packaged Tonics 1/1 for [Ward Restocking]"). Two switches under Settings, Tracker, both off until you turn them on. While Questie announces objectives itself, OneMoreQuest leaves them to it.

**Fixes**

- A dungeon learned from your runs no longer breaks the Available tab's list when it shows its note.
- Kill counting is sturdier. A creature killed once counts as one kill: a death the game reported more than once (Fozruk, seen through several units in a group) was counted again. A creature killed in one blow counts even when the game tells its death first. A creature someone else took over is not counted as yours. And after a quest item is lost (destroyed or traded), the next drop is still noticed.
- My quests marks the zone you are in again: its heading's gold edge was drawn under the window's border, so it never showed.

## 0.8.4

**Fixes**

- Why a party member can't take a quest is shown in your own language: a member playing OneMoreQuest in Czech no longer shows you Czech reasons ("Po Pozvednutí ducha 3/7"), and the quest it names is in your language too. A member on an older version still sends their own words.

## 0.8.3

**Quest data**

- When a quest giver's list leaves out a quest the quest database says they should give (Drum Fel's Call to Arms, which needs The Hammer May Fall first, unknown to the database), OneMoreQuest learns it: the quest moves to "not yet", saying "Not offered by Drum Fel when you asked", and its "!" goes from the map. It comes back once they offer it, once you hand in any quest, or once you go up a level.
- With DungeonJournal installed, Forever's own quest givers the quest database has no place for are found where the journal says they stand: the Deathstalker Agent outside the Excavation Site in the Wetlands, for Dragonmaw Rumors and Open the Maw.

**Dungeons tab**

- A lead-in already in your log is listed under the dungeon quest it opens (Dragonmaw Rumors under Open the Maw), with the arrow, not left out.

**Quest page**

- The warnings about lead-ins say plainly what is at stake: "Do Trollbane first, or it is lost once you take this" on the quest a lead-in leads to, and "Lead-in to Sigil of Strom: lost once you take that quest" on the lead-in (a lead-in is no longer offered once you have accepted the quest it leads to). The quest each names is a link: click it to go to that quest.

**Fixes**

- A quest ready to hand in to someone whose place nobody knows is listed in My quests under its own zone or dungeon, not under "Unknown location".
- The minimap shows the quests to pick up around you, as the map does: every quest giver in view has a "!" drawn just like the game's, which hands over to the game's own once you are near enough for the game to show it (the game draws one only from about 120 yards). Before, a giver who did not stand within that range showed nothing on the minimap.
- The quest selected on the Available tab shows where it starts on the minimap too, as on the world map: when it starts from an item creatures drop (or from several givers about), their spawns and areas, in the gold of its "!". They stay on the minimap after you close the quest log, while you walk there, until you choose another quest, deselect it, or pick it up.

## 0.8.2

**Dungeons tab**

- A third tab in the quest log, Dungeons: every dungeon and raid with quests for you, sorted by level. Select one to see its page: its levels and where its way in is, and its quests by what to do about them (in your log, pick up before you go, found inside, behind a lead-in, not yet). Its quests also unfold under it in the list; select one to see how to pick it up. "Show entrance" turns the map to its way in.
- A lead-in is listed under the quest it leads to, with a gold arrow from it up into that quest, not on its own; a quest already in your log shows the game's own "?" (grey while you work on it, yellow when it is ready to hand in).
- With the DungeonJournal addon installed, a "Dungeon Journal" button opens the journal on that dungeon.
- Dungeons are no longer locations on the Available tab (nor in its location menu); a dungeon's gate on the map, or one of its quests clicked on the map, opens the Dungeons tab. A quest picked up in a zone that leads into a dungeon is still listed there, saying which dungeon it leads to.

**Quest data**

- With the DungeonJournal addon installed, OneMoreQuest knows Forever's own dungeons from the start: the Drowned City, Blackmaw Hold, Alcaz Prison and Krol'dok Stronghold are listed with their quests and marked at their entrances before you have ever been inside. A quest the quest database files nowhere, such as Ancient Gurubashi Idol, goes under its dungeon instead of its quest giver's zone.
- Quest data now comes from several sources in turn: QuestieDB first, then DungeonJournal, then what OneMoreQuest learned by playing. Each detail is taken from the first that has it, so a later source only fills in what an earlier one leaves out.

**Map**

- Creatures that walk a patrol (Sharptalon round his part of Ashenvale) have their path drawn on the map and the minimap, in their quest's colour, as Questie shows them: for every tracked quest whose creatures to kill, or whose items' droppers, patrol. In every look of the marks.
- Quest givers who walk about (and, for a quest that starts from a dropped item such as The Runed Scroll, the creatures that drop it) have their path drawn in the gold of their "!" while you point at it on the map, and for the quest selected on the Available tab on the map and the minimap, with the path of whom it is handed in to. Only those: drawn for every giver, they ran together on shared roads.
- The glow round a quest giver's "!" and a ready "?" is smaller: a halo round the mark, not a disc behind it.
- The spawn icons on the minimap (the "icons and areas" look) are smaller, 7 across instead of 9, with a little room between them; as many are shown as before.
- The minimap's spawn icons, squares, areas and patrol paths are drawn half see-through, so the game's herb, ore and other gathering blips under them still show (the game tells addons nowhere where those are). Quest marks stay solid.
- The "Shapes" look draws quest areas the way the game draws its own: rough, rounded shapes on a coarse grid (nearby spawns melt into one), with a thick dark edge and a see-through fill, in the quest's own colour (its objectives in lighter steps of it, as their rows on the quest page and the map's tooltip).

**Fixes**

- Opening the world or a continent map no longer turns the Available tab into an "Unknown location" listing quests from elsewhere, with their "!" scattered across the world map (some twice); the tab keeps the zone it had. A quest giver no longer shows as "Unknown location" when their place is known.
- Showing or hiding low-level quests on the Available tab updates the map and the minimap at once; their "!" used to change only once the map was moved.
- Handing in the quest in focus no longer sets off "Auras cannot be accessed when secret while tainted" errors from the game's objective tracker. OneMoreQuest now changes the game's quest focus only when you choose one; when a quest leaves the log, the game drops its own focus on it.

## 0.8.1

**Quest data**

- OneMoreQuest notices where WoW: Forever's quests differ from the quest database: a quest it does not have, a giver or turn-in it does not list, or objective items under another name or number. They go into the /omq missing report beside the missed quests, to send so QuestieDB can be brought up to date; the About page says how many there are. The list starts afresh when QuestieDB updates.

**Performance**

- Lighter while questing: the windows and map no longer redraw for game updates that changed nothing they show. A kill or loot that moves no quest along, an item that no quest needs, walking from one part of a zone into the next, and group updates with the same people now cost nothing; bursts of item details from the game are drawn once they settle.

**Map**

- A profession quest whose items you make or buy (On Iron Pauldrons) no longer puts a mark and a spawn square on the minimap at the quest giver before it is ready: it is listed under the quest giver's zone, and marked once it can be handed in.
- The quest you follow, and the one highlighted in the quest log, show where they will be handed in on the world map, as the game's "?" in grey until they are ready (as the game shows it over a quest giver whose quest is not finished); the quest page's turn-in line is grey too until then. The minimap keeps showing only what to do next.
- The minimap no longer loses a turn-in's "?" for a stretch as you walk up to the quest giver: ours stands at their place, drawn just like the game's, while the game cannot show its own yet (only once the server has sent the quest giver, 120 yards out), and the two swap in the same moment, never sitting over each other.
- Quest marks on the map are as large as the game's own quest buttons (20, was 24), and the quest in focus is no larger than the rest: it stands out by its gold ring and glow, as the game's does. The minimap, tracker and quest list marks look as before.

**Fixes**

- With Leatrix Maps' map frame unlocked, the map stays where you moved it when OneMoreQuest's window opens beside it; it used to jump to the game's usual spot on the left. Leatrix Maps is listed on the About page.
- OneMoreQuest's icon shows in the game's addon list (it was a picture the game cannot read).
- The tracker's right-click Open in the quest log turns the map to the quest and pans to it, as clicking it in the quest list does; it used to open the page and leave the map where it was.
- An objective item that players make (an alchemist's elixir, a smith's piece) says so on the quest page: the profession, and the player's own skill when they have it, or to get it from a crafter or the Auction House, in place of "not on the map". From the game's own data, for every crafted item.
- Crafted items say more: once you have opened your profession window, "you know the recipe" for the ones you can make; how many wait in your bank (once you have opened it); and with Auctionator's prices, about what the ones still needed cost at the Auction House (for 4, less any in the bank), to buy rather than make.
- A quest giver or turn-in who also stands in the other faction's towns is sent to where your side can reach: Shrewd Negotiations' Kirin Tor image is turned in at Silverpine Forest for the Horde, not in Southshore or Dalaran, and opening the quest no longer turns the map to Alterac Mountains. The towns are found from the quest database itself (many of one side's people together); one who stands only there (a prisoner in an enemy fort) is still shown.

## 0.8.0

**Čeština / Czech**

- OneMoreQuest speaks Czech: settings, About, Language: Čeština. Its own words only, in the slang of Czech players (questy, dropy, killy, odevzdat); quests, places, people and items keep the names the game gives them. English stays the default.
- In Czech, OneMoreQuest's text uses Marcellus and Metamorphous (free look-alikes of the game's Friz Quadrata and Morpheus, which lack ě č ř ů ň ť ď), and so do tooltips while the game's own font lacks those letters. A Czech addon's fonts, when one has replaced the game's, are left as they are.
- With OneMoreQuest in Czech and Azeroth česky installed and on, quests show its Czech titles and objectives everywhere in OneMoreQuest: the log, the quest page, the Available tab, the tracker, the map and minimap, tooltips and the chronicle. Its own settings decide (its quest-title language among them); quests it doesn't know, and every quest without it, stay in English. The log's search finds a quest by its English title too.
- The same with WoWF.cz (WowfCZ): its Czech titles, objectives and quest stories, following its /wowf settings as they change. With both on, Azeroth česky is used; turn it off (in the addon list or its own settings) and WoWF.cz takes over at once.
- WoWF.cz's Czech narration (dabing), played in its own player and queue: Play/Stop and Queue buttons on the quest page of a quest that has a recording, the same in the quest's right-click menu (quest list and tracker), a speaker on the quest list's rows while a quest plays or waits in the queue (with its place), and in the tracker while it plays.
- In English, the same narration controls play Spoken's English voice-over (Spoken with Spoken Quests and its voice packs), in Spoken's own queue: Play, Queue and Stop as Spoken's own quest log buttons do them.
- Settings, About: a Works with list of every other addon OneMoreQuest works with now, what each brings, and for the translation and narration addons whether they are used now (each is for one language, and can be switched off in its own settings).
- In Czech, the entries of the right-click menus show every Czech letter (the game's menu font lacks ř, ě and the rest).

**Fixes**

- Spoken Places' place story and its tab no longer cover the quest window docked beside the map: the tab sits on the window's edge, and the story opens to the window's right when there is room, else over the map's right side.
- The next step of a chain, offered the moment the step before it is handed in (Blood in the Streets, then Heart of Disruption), is no longer reported as a quest the addon missed: a quest just handed in counts as done at once, before the game marks it completed.
- Counts of one read as one: "1 kill", "1 quest", not "1 kills" (the chronicle's records, kill counts, missed-quest messages).
- In Czech, the quest log's search box says Hledat.
- Drop rates take QuestieDB's own corrections into account, as Questie does: about a hundred quest items whose Wowhead rate was far off (one at 5% that always drops, one at 0.5% that drops three times in four) now show the right chance and kills to go.
- OneMoreQuest checks that the installed QuestieDB is new enough for it, and says so in the chat and on the About page when it is not, or when QuestieDB runs from its raw data.

## 0.7.1

**Minimap**

- A quest's mark stands where the world map has it and stays put as you walk, instead of jumping to whichever spawn is nearest; every spawn keeps its icon (one under a mark steps just beside it).
- Your arrow and your party (as the game draws them, without the rings round party members) are drawn over the marks, so marks no longer step aside for them; marks pack closer together.
- Marks crowding one place, on the map and the minimap, pack closer (their round edges may just overlap), so each stands nearer where it belongs.
- Quest givers and turn-ins are left to the game's own "!" and "?" (with its arrow when the NPC is above or below you); OneMoreQuest no longer draws a second one on top. It still marks what the game cannot: a quest that starts from a dropped item, the quest selected on the Available tab, and the way to the followed quest's turn-in from the minimap's rim.

**Fixes**

- Low-level quests follow the game's own rule: a quest the game shows grey is low-level, and is left out of the Available list until you tick Show low-level quests. The one exception stays listed in grey and says why: a low-level quest whose chain leads into your range ("Low-level, but leads to [27] ..."). Before, the list hid quests by a rule of its own, so a grey quest could still be listed.
- The zone you are in is found by its name too, so its heading's gold edge shows in cities such as Thunder Bluff.

## 0.7.0

**Chronicle**

- Days: a new chapter with a page for each day played, a ledger of the day. Tiles for net gold, experience, quests, kills, deaths and time played; gold line by line, where it came from (coins looted, quest rewards, sold to vendors, the auction house by mail) and where it went (repairs, training, flights, bought), and an hour's worth; experience by source (quests, kills with their rested bonus apart, discovery), an hour's worth and today when the next level comes at that pace; chests and herb and ore nodes opened and what they gave; and the notable things (green and better) looted or chosen as quest rewards. Money or experience the addon cannot place is "other", never guessed. Kept from now on, a small record a day.
- At a glance, redone: today's net gold, experience, quests and level, each beside its icon as the spellbook lists its spells, set against your average day (and when the next level comes at today's pace); everything altogether, from the days kept (gold and experience from every source, every kill); and records, now with the best day for gold and for experience, the most quests in a day and days in a row. The quests-a-day chart is gone: the Days chapter has every day.
- Kills and luck shows highlights instead of every drop quest, so it stays the same size however many quests you hand in: the luckiest and unluckiest quest, the rarest drop, the longest hunt, the longest dry spell before a drop, how often a drop came on the first kill, and the five creatures killed most for drops. Click a highlight for its quest in the Journal. Dry spells and first-kill drops are kept from now on, two small numbers a quest.

**Quest log**

- Zones are headed on the quest page's dark title band, with the game's + and - to fold, and at the right in words how many quests are ready and how many there are ("2 ready · 4 quests").
- A zone's name is white when a tracked quest is in it and muted when none is. A dungeon's gate or a category's picture (cooking, a class) follows the name, so names always start in one place.
- The zone you are in has a gold edge down its left ("You are here" when pointed at). Only the quest inside is highlighted, never the heading.
- A zone name too long for the list ends in "..." and shows whole when pointed at.
- All, Ready and Tracked are the game's dropdown beside the search.
- In a party, a quest one of them could take but has not got shows the game's group icon on its row: hover it for who and why the others can't, click it to share the quest with the party. Nothing shows when sharing would not help. The amber ring on a quest a party member has not got is gone.
- Ctrl-click a quest (in the list, on its page's title or its mark on the map) to put it in focus, or to let go of it.
- A click on the map where there is nothing lets go of the selected quest; dragging the map to move it does not.

**The game's own look**

- Checkboxes are Forever's own, on the quest page, in the tracker, in the settings and for low-level quests.
- Progress bars are the game's own: kills for a drop on the quest page, a zone's quests on the Available tab, and the chronicle's Zones and Journal.
- The chain step is written plainly, without an outline, in the tracker and on the quest page.
- The help mark beside Profit on the quest page is the game's own gold "i".
- The settings list their switches and quick setups on the page, without boxes; the picked look has a gold rim.

**Map and minimap**

- A quest's mark has a soft glow in the colour of its area, linking the two while the mark stays gold: faint out of focus, as strong as the gold glow it replaces when highlighted. A selected quest to pick up that starts from a dropped item glows in the colour of the area where it drops.
- The quest selected on the Available tab is no longer drawn half as big again: it has the gold glow of a highlighted quest ready to hand in.
- A spawn mark that would sit under its own quest's mark is left out (zoomed out, an area can be no bigger than its mark, and spawn marks pushed round it stood outside the area); one under another quest's mark moves just beside it.

**Party**

- Kills are the group's, but a quest item's drops go round between those who still need it, so the average and the kills to go count each kill as a share of a chance: a 50% drop with two of you needing it is a quarter chance a kill. The kill line says "loot shared by 2" meanwhile; once a member has all theirs, the rest of the drops are yours alone.

**Fixes**

- A tracked quest's areas keep their colour: tracking or untracking another quest no longer changes it.
- The + and - of a heading, and other pictures of the game's in the quest log, are no longer drawn cropped (smaller) where a picture was shown before them.
- The track button of a quest in the list is a square round its mark, the same tracked or not; below it, the row selects the quest.
- Highlighting a quest whose objectives each have one spawn (The Relics of Wakening's chests) no longer makes its area vanish.
- The saved file stays small: each chronicle entry keeps only what the quest data cannot give back (about half the size; a character's road to 60 takes about 125 KB instead of 280 KB), and a little after login what was kept for quests done with goes (kill counts and notes of quests no longer in the log, offers and map choices of quests handed in, settings of removed features, the game's answers for older game builds).
- The game's "no such quest" answers are kept by the game's build as meant (they were all kept under one name); the game's own dungeon entrance icons are found for the dungeon marks to circle, as Leatrix Maps' are.
- The Map marks switch in the settings no longer speaks of numbered marks.

## 0.6.0

**Map and minimap**

- One look for quest marks, without numbers. A quest in your log is a gold coin with what it wants there: a sword, a sack, a pointing hand, a speech bubble. Ready to hand in, it is the game's own gold "?"; the hand-in of a quest you have not taken yet is a "?" in a dashed gold outline. The same marks on the map, the minimap, the tracker and the quest log. The pin and ring looks are gone, with their setting.
- A new look for where your quests are, and the new default: each tracked quest's areas in a colour of its own, as soft, round shapes that follow the spawns (nearby spawns melt into one area, the empty land between groups left open), with small icons of what to do on the spawns. Quests not in focus are fainter; the focused or highlighted quest's stay bright. Squares, shapes and "The game's own areas" (the game's quest areas, with OneMoreQuest's icons on the spawns) remain in the settings.
- The minimap shows each tracked quest's areas too, the same shapes as the world map, cut at the minimap's edge and never across your arrow or a party member. Square minimaps (Leatrix Plus and others) are understood. The game's own quest areas are hidden there while OneMoreQuest's replace them.
- Hovering a quest's area or a spawn mark, on the map or the minimap, shows the quest's tooltip as the game does for its own quest areas: the title, what is still to do, the creatures that drop each item with their chances. Hovering another addon's map icon shows its tooltip, not a quest area's under it. `/omq hover` says what hovering finds, to track down a tooltip that does not show.
- The zone map (Shift+M) shows OneMoreQuest's marks and areas too.
- Map marks stay at their places: where they would overlap, each moves only as far as it must, and keeps clear of other addons' pins and the game's. Spawn marks sit close round a quest mark, and one that would sit under another addon's icon moves just beside it.
- Your party members and your own arrow are always drawn over OneMoreQuest's marks; on the minimap nothing of OneMoreQuest's lies on them, and each party member has a ring in their class colour.
- Drawing is much lighter: big quest areas take a tenth of the pieces (the Barrens with ten quests: about 960 instead of 8,800) and are worked out over a few frames the first time, so dragging and opening the map stay smooth; the minimap redraws only when something it shows has changed.

**Dungeons**

- On the map, a dungeon or raid is its entrance icon with each of its quests' marks round it: hover one for that quest, click the entrance for the run plan. With Leatrix Maps, the quests circle Leatrix's entrance icon instead of adding a second one, keep out from under Leatrix's other icons, and leave its zone arrows free to point at and click.
- The highlighted quest of a dungeon (selected, or hovered in the list) is drawn full size with its gold ring and glow among the others; selecting one never moves the dungeon or the marks round it.

**Quests to pick up**

- Quests the database knows from other versions of the game (Season of Discovery's supply crates in the Barrens, such as Crate Return) are no longer offered: OneMoreQuest asks the game once whether it has a quest, and remembers the answer for that game build.
- The quest selected on the Available tab stands out on the map and minimap: its "!" (or item) half as big again, in a strong gold glow. Selecting it shows where it starts; where it is handed in appears only when you press "Show turn-in".
- A quest that starts from a dropped item shows, when selected, where the creatures that drop it are, each in its own colour as on the quest page.
- Quests to pick up use the game's own marks: the gold "!", grey for quests below your level, blue for repeatable ones; a quest that starts from an item shows the item with a small "!".

**Party**

- Under the focused quest's title in the tracker, and across the quest page's Party part (which folds, as Profit does), each party member's face in a ring that fills with their progress on the quest, with a green tick once they are ready to hand it in. Hovering a face gives their full name and every count, or why they are not on it.
- A member without the quest is greyed with a badge: a grey tick for done it already, the quest giver's "!" for can take it, a cross for can't have it (hover says why: their level, race or class, or an earlier quest), "?" when it can't be told. Members running OneMoreQuest answer each other whether they did a quest or could take it.
- A quest's tooltip lists the party as the game's own quest tooltips do: each member's name, then their objectives under it, or why they are not on it.

**Quest log and tracker**

- Right-click on a quest in the log opens a menu: focus, track or untrack, share to chat or with the party, abandon. In the tracker, untracking is in its right-click menu.
- Share quests to chat: shift-click a quest in the tracker, the quest log, on its page's title or on the map.
- The focused quest is the game's own (its super-tracked quest): one focused in the game's quest log or map is the tracker's focus too, and the other way round.
- The quest page shows the quest's level range ("Levels 30–33").
- Kills for a drop say what they mean: "3 kills, no drop yet", then "8 kills for 2 drops · average 6", the kills an average player needs for those drops; the bar turns red only past that. A quest ready to hand in keeps this count on its page.
- A creature's tooltip (hovered, on its nameplate, or on your target's portrait) says what it gives towards your quests: the items it drops for each, their count and chance, and the kills it counts for. A switch in the settings, under Profit and kills.
- The tracker grows only downwards from where you put it.
- On a screen too narrow for the map and the quest window side by side, the quest window is drawn a little smaller so it fits.
- The minimap button is gone: the log opens with M (beside the map) and L.

**Fixes**

- Kills for drop quests are counted again: this client no longer lets addons read the combat log, so a kill is now a creature you or your group fought (seen as your target, mouseover, nameplate or a party member's target) that dies.
- Clients in other languages: kill objectives are told by the game's own wording (German "getötet" and others), so their marks get the swords and their hints find the creature.
- The quest page of a quest whose objective has no known place or source (Elixir of Agony) no longer gives an error.
- Party members' names in quest tooltips are in their class colours again.
- `/omq missing` reports the client's build number.

## 0.5.0

**Dungeons**

- Each dungeon's quests as a plan for one run: in your log, to pick up before you go, found inside, behind a lead-in (the lead-ins named and linked), and not yet, with the reason.
- A dungeon counts only the quests really done inside it; one quest can count for two dungeons.
- The chronicle lists every dungeon with quests for you, started or not, in level order.
- Dungeons the quest database does not know yet (Alcaz Prison, the Drowned City and others) are learned as you run them, and listed in `/omq missing` to pass on.
- Marks piling up on a dungeon's entrance become one dungeon mark with a count; click it to plan the run.
- A zone's list points to the dungeons whose entrance is there, instead of listing their quests twice.

**Quests to pick up**

- Lead-ins come first in "How to start", each a link to its page.
- Quests of one name done back to back (The Sparklematic 5200!) are one row, with "How it goes"; versions of a quest are one row ("any of 3 places").
- Same-named chain steps say what each asks (Test of Lore's six).
- Quests for those who have not learned a profession yet (Camping 101), profession specializations, and quests open only for a while are now offered correctly.
- "After any one of" quests name one you can do, and say another would do.
- A quest after a chain step and above your level says both.
- Objectives with no known place show the quest's own words as the hint.

**Quest log and map**

- Drop locations grouped by zone, each place a link to the map; the map remembers the last place you looked at.
- Quest chains grouped together in "Not yet available".
- Clicking a quest given elsewhere turns the map to its giver and keeps the list where it is; clicking a quest on the map moves the list to where it is listed.
- Group quests by where to go next or where picked up (Settings).
- The log opens at the quest in focus.

**Chronicle** (the book beside the cog)

- Your quest history: at a glance, journal, zones with progress bars, kills and luck.

**Party**

- Quest progress shared with your party, with Questie users too.

**Fixes**

- The mouse wheel no longer zooms the game behind the window.
- Cooking and class quests are no longer hidden in a folded tracker group while you work on them.
- The other faction's version of a quest is no longer counted as yours.
- Profession skill ranks read correctly; quest givers only in the other faction's capitals are out of reach.
