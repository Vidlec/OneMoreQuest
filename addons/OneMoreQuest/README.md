# OneMoreQuest

_Just one more quest_

The game's quest log files every quest under the zone where you **picked it up**. Take a quest in the Barrens
that sends you to Stonetalon, with the turn-in back in Orgrimmar, and the log keeps it under the Barrens the whole
way.

OneMoreQuest files it under the zone you have to **go to next**. Open the log in any zone and that's your to-do
list: what to kill, loot or talk to there, where exactly, and who takes it back.

It looks and behaves like part of the game: its window frames, quest page, buttons and map marks. Don't like a
part of it? The quest log, the tracker, the map marks and the quests to pick up can each be switched back to the
game's own, or all of them at once.

Made for **WoW: Forever**.

## What's in it

- **A quest log beside the map.** The map opens with OneMoreQuest's window docked beside it, with three tabs: My
  quests, Available and Dungeons. Drag the grip at its corner to make the map and the window larger.
- **Every quest's page.** What to do and where, which creatures drop each item and how often, a kill counter
  against the usual number of kills, where to hand it in, its rewards and what it's roughly worth, its chain ("2 of
  5"), the quests it needs first and the ones it unlocks.
- **The quest diagram.** A quest's whole chain as a tree: what comes before, what follows, where each quest
  stands for you.
- **Map and minimap marks.** A gold mark for each tracked quest showing what to do there (a sword, a sack, a
  pointing hand, a speech bubble) and the game's "?" where it's ready to hand in, the givers of quests you can pick
  up, and where each quest's creatures and items are, in a colour of its own: soft shadows, ovals or traced outlines.
- **A tracker grouped by zone.** The same marks as the map's, with chain steps, clickable quest items, filters for
  the quests here, ready or in focus, and a waypoint on the quest in focus (TomTom's arrow when you have it).
- **Quests to pick up.** The Available tab lists everything you can pick up in a zone and what to do next: pick
  up now, opens from your log, opens after a pick-up, needs a level. Hide the quests you don't want to see.
- **Dungeons.** Every dungeon with quests for you, by level: its way in, what to pick up before you go, what's
  found inside, which lead-ins open the rest. Forever's own dungeons are learned as you run them.
- **Your chronicle.** A record of your character's questing, written as you play: totals and records, each day's
  gold, experience, kills and loot, a journal of every quest handed in, and how much of each zone you've done.
- **Spoilers your way.** Four presets, from Guide (everything) to Purist (your log and the tracker's counts),
  then each kind of hint by hand. Stuck? "Need a hint?" tells you a little at a time.

## Also in the box

- Group play: share exact quest progress with your party (Questie users included), see who can take a quest, and
  announce in chat when a quest is ready.
- Controller support with the game's Gamepad UI: the quest window, the tracker, the settings and the map's marks
  all work with a pad.
- Quest icons on nameplates, quest drops on creature tooltips, and the quests an item is for on its tooltip.
- Accept quests and hand them in as you talk to givers, if you like.
- Holiday and world event quests only while the event runs; dungeon, raid, PvP and repeatable quests in colours
  and marks of their own.
- A warning as your log fills, with the quests worth dropping.
- English and Czech (Settings, About, Language).

## You'll need

- **QuestieDB**, the WoW: Forever build (required): the quests, creatures and items it all comes from.

## Works with

- **Auctionator**: auction prices in what a quest is worth.
- **Tnny's Mob Loot**: drop rates, and how lucky your kills have been.
- **TomTom**: its arrow for waypoints.
- **Questie**: progress shared with Questie users in your group, and your Questie journey in the chronicle.
- **ForeverDungeonJournal**: more dungeons and their quests.
- **MapUtils**, **OpenMap**, **Leatrix Maps**: marks on their maps, the window moving with them.
- **Spoken**, **WowfCZ**, **Azeroth česky**: narration and Czech quest texts, on the quest page.

## Commands

- `/omq` shows or hides the tracker.
- `/omq settings` opens the settings (also the cog in the quest window's title).
- `/omq log` opens the map with the quest window; `/omq available` opens the Available tab.
- `/omq spoilers guide`, `hints`, `explorer` or `purist` picks how much it tells you.
- `/omq lock` locks the tracker; `/omq reset` puts the tracker and the window back where they started.
- `/omq missing` lists quests the game offered that the quest data lacks, to report.

## Credits

Quest data from **QuestieDB** (GPL-3.0). The list of quests that aren't in the game comes from **Questie**
(GPL-3.0). OneMoreQuest is free software under the GNU GPL v3 (see `LICENSE.md`).

The scroll in the logo is painted by **MELLE**, from the
[Fantasy parchment set](https://opengameart.org/content/fantasy-parchment-set) on OpenGameArt (CC0).

The quest data is only as good as what players record. **[QuestieTrace](https://www.curseforge.com/wow/addons/questietrace)**
records quest givers, drops and progress as you play, for the Questie team, and has a WoW: Forever build. Running
it alongside helps fill the gaps OneMoreQuest works around, such as the Forever dungeons QuestieDB doesn't list
yet.

World of Warcraft belongs to Blizzard Entertainment; this addon isn't made or endorsed by Blizzard.
