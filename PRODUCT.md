# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The product itself is an addon inside the World of Warcraft: Forever client (Lua, the game's own UI); this record's
web surfaces are its product page and changelog (https://vidlec.github.io/OneMoreQuest/, built by
`tools/site/build.ts`) and its CurseForge description.

## Users

Players of World of Warcraft: Forever levelling through quests, new and returning alike. They are in the game, zone by
zone, with a log full of quests that send them elsewhere, and they want to know where to go next without leaving the
game's own look. OneMoreQuest replaces the game's quest log, tracker and map marks for them.

## Product Purpose

OneMoreQuest groups a player's quests by where they actually have to go next, not where they picked them up, so the
zone they are in is their to-do list. Around that it puts a quest log beside the map, a tracker grouped by zone, quest
marks on the map and minimap, the quests they can pick up nearby (Available), dungeons with their quests, quest chains
and a diagram of them, a chronicle of what they have done, and a rough idea of what each quest is worth. Success: a
player opens the log in any zone and knows what to do there, and reaches for "just one more quest".

## Positioning

Sorted by where to go next. The game's log files a quest under the zone it was picked up in; OneMoreQuest files it
under the zone the player has to go to next, and everything else (the marks, the tracker, Available) serves that.
Neither the game's own log nor Questie sorts quests this way.

## Operating Context

- Played inside the WoW: Forever client, with the map open beside the quest log; by mouse or by controller (the game's
  gamepad interface).
- Built on QuestieDB (required): its quest, creature and item data. Optional companions: Auctionator (prices), Tnny's
  Mob Loot (drop rates), TomTom (waypoints), MapUtils, OpenMap, translation addons.
- Distributed on CurseForge (https://www.curseforge.com/wow/addons/onemorequest) and as GitHub releases.
- Developed and tested in AddonSim, a simulator of the client; the product page's screenshots come from it.

## Capabilities and Constraints

- For WoW: Forever only: the C_ API, never an older client's globals alone.
- Every rule comes from data; no quest ids are hardcoded in the addon.
- Each part (the quest log, the tracker, the map marks, the quests to pick up) can be switched back to the game's own
  in the settings, or all of it at once.
- Spoilers are the player's choice: four presets (Guide, Hints, Explorer, Purist) and each kind by hand; the quest's
  own text is never touched.
- Languages: English, with Czech and the game's other locales through translation addons.
- Free software under the GNU GPL v3.

## Brand Commitments

- Name: OneMoreQuest; tagline: "Just one more quest". The voice is plain, friendly and specific, in the player's
  words ("where to go next", "what to pick up"), as the addon's README speaks.
- It feels like part of the game, not an addon bolted on top: the game's own window frames, quest page, buttons and
  marks.
- No Blizzard assets on the product's own pages: no Blizzard logos, fonts or extracted art. Screenshots of the addon in
  the game's interface are fine. World of Warcraft belongs to Blizzard Entertainment; the addon isn't made or endorsed
  by Blizzard, and the pages say so.
- Credit QuestieDB (and Questie's data) as the source wherever the product is presented, with its GPL licence.

## Evidence on Hand

- Screenshots of every feature, drawn in AddonSim: `site/media/*.webp` (made by `bun run media` from
  `sim/scenarios/media/`).
- The README (`addons/OneMoreQuest/README.md`) and every version's notes (`addons/OneMoreQuest/CHANGELOG.md`); release
  highlights in `site/releases/<version>.json`.
- The logo: `addons/OneMoreQuest/Media/Logo64.png` (a scroll painted by MELLE, CC0).
- Absent, and not to be invented: download counts, ratings, reviews, testimonials, player numbers.

## Product Principles

1. Where to go next comes first: every surface answers "what do I do here, now".
2. Part of the game: it looks and behaves like the game's own interface, and each part can step aside for the game's.
3. Truth from data: quests, chains, spawns and drops come from QuestieDB and the client, never typed in by hand.
4. The player decides how much is told (spoilers), and nothing they did not ask for is pushed at them.
5. Show, don't claim: the addon is presented through its real windows, not through numbers it does not have.
