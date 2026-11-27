# OneMoreQuest

_Just one more quest_

The game's quest log sorts quests by where you **picked them up**. You grab a quest in the Barrens, it sends
you to Stonetalon, the turn-in is back in Orgrimmar, and the log files it under the Barrens the whole time.

OneMoreQuest groups your quests by where you actually have to **go next**. Open the log, look at the zone
you're in, and that's your to-do list.

Also in the box: a quest log right next to the map, quests you can pick up nearby, quest marks on the map and
minimap, a tracker grouped by zone, and a rough idea of what each quest is worth.

It keeps track of quest chains too. Every quest shows which step of its chain it is ("1 of 7"), and its page
lists the whole chain, so you know what's coming next and how far you've got.

It comes with its own tracker as well, in place of the game's. Your tracked quests are grouped by zone,
numbered like their marks on the map, with chain steps, quest items you can click, and what's ready to hand
in. Hover a quest for the details.

And it helps you find new quests. The Available tab lists everything you can pick up in a zone, with the
givers marked on the map: quests from NPCs, quests that start from an item a mob drops, chains that lead into a
dungeon, and what you still need before a quest opens up. It also shows how much of the zone you've already
done. The Dungeons tab lists every dungeon with quests for you, by level: where its way in is, what to pick up
before you go, what's found inside, and which lead-ins open the rest.

I wanted it to feel like part of the game, not an addon bolted on top, so everything uses the game's own look:
its window frames, quest page, buttons, checkboxes and map marks.
Don't like a part of it? Each piece (the quest log, the tracker, the map marks, the quests to pick up) can be switched back to the game's own
in the settings, or all of it at once.

Made for **WoW: Forever**.

## You'll need

- **QuestieDB** (required, the WoW: Forever build)
- **Auctionator** (optional, for auction prices)
- **Tnny's Mob Loot** (optional, for drop rates)
- **TomTom** (optional, its arrow for waypoints)

## Commands

`/omq` toggles the tracker, `/omq settings` opens the settings. The cog in the quest log and the minimap
button do the same.

## Credits

Quest data from **QuestieDB** (GPL-3.0). The list of quests that aren't in the game comes from **Questie**
(GPL-3.0). OneMoreQuest is free software under the GNU GPL v3 (see `LICENSE.md`).

The scroll in the logo is painted by **MELLE**, from the
[Fantasy parchment set](https://opengameart.org/content/fantasy-parchment-set) on OpenGameArt (CC0).

The quest data is only as good as what players record. **[QuestieTrace](https://www.curseforge.com/wow/addons/questietrace)** records quest givers, drops and progress as you play, for the Questie team, and has a WoW: Forever build. Running it alongside helps fill the gaps OneMoreQuest works around, such as the Forever dungeons QuestieDB doesn't list yet.

World of Warcraft belongs to Blizzard Entertainment; this addon isn't made or endorsed by Blizzard.
