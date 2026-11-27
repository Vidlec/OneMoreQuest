# OneMoreQuest

A quest addon for WoW: Forever: a quest log beside the map, a tracker grouped by zone, and map marks showing where
to go. Built on QuestieDB. The player-facing description is [addons/OneMoreQuest/README.md](addons/OneMoreQuest/README.md);
what changed in each version is [addons/OneMoreQuest/CHANGELOG.md](addons/OneMoreQuest/CHANGELOG.md).

Downloads: the [releases](../../releases) (each with its SHA-256 checksum) and CurseForge.

## The repository

```
addons/OneMoreQuest/       the addon (Lua 5.1), as it goes into the game's Interface/AddOns folder
  OneMoreQuest.toc         what the game loads, in order: the one list of the addon's files
  CHANGELOG.md             each version's notes (a release takes its own section)
  Core/                    the namespace, settings, locale, geometry
  Data/                    QuestieDB access and the addon's own data tables (some generated: see tools/data)
  Quests/                  quest state, chains, availability, spoilers, focus, events
  Loot/                    drops, prices, profit, crafting, kill counts
  Chronicle/               the character's quest history and its pages
  Party/                   party messages (OneMoreQuest's own and Questie's), announcements
  UI/                      shared widgets, the window border, tooltips, nameplates
  Tracker/                 the tracker
  Log/                     the quest window beside the map, and the quest diagram
  Map/                     the world map and minimap: docking, pins, hover; Map/Marks/ draws the areas and marks
  Gamepad/                 the controller support
  Compatibility/           getting along with other addons, one file each
  Locales/, Translators/   Czech, and the translation addons quest texts come from
  Media/                   pictures and fonts
  tests/                   unit tests in a fake game (not shipped)
sim/                       the simulator's scenarios, plugins and helpers (AddonSim)
tools/
  release/                 the release: zip, notes, CurseForge upload (Python, standard library only)
  data/                    generators of the addon's data tables
  design/                  design boards and the design system's sources (not shipped)
docs/                      history kept for the record
.github/workflows/         checks on every pull request; the release on every merge to main
```

## Developing

The addon is tested in AddonSim, a simulator of the client in a repository of its own, checked out beside this one.
[CLAUDE.md](CLAUDE.md) has the commands; in short:

```
git clone https://github.com/Vidlec/wow-client-sim.git AddonSim
cd AddonSim && bun install && bun link && bun run tools:lua
cd ../WowAddons && bun install
bun run lint            # StyLua and luacheck (Lua; every Forever global known), Biome (the tools' TypeScript)
bun run typecheck       # the tools' TypeScript
bun run test            # the unit tests, then every simulator scenario
bun run zip             # the release zip into dist/
```

Add a Lua file to the addon by adding it to `OneMoreQuest.toc`: the unit tests, the simulator and the release all
load the TOC's list, and the release build fails on a Lua file the TOC does not load. CLAUDE.md has the conventions.

## Releasing

A release goes out when a pull request that raises the version is merged to main:

1. In the pull request, raise `## Version:` and the version in `## Title:` in `addons/OneMoreQuest/OneMoreQuest.toc`,
   and write the version's section in `CHANGELOG.md` (`## 1.2.3`). A version like `1.2.3-beta1` is a pre-release.
2. Merge it. The Release workflow runs the checks, builds `OneMoreQuest-<version>.zip` and `SHA256SUMS.txt`, creates
   the GitHub release `v<version>` (the changelog section, how to install, the checksum, and the merged pull
   requests), and uploads the zip to CurseForge.

A merge that does not raise the version releases nothing. The zip is built byte for byte the same from the same
files, so anyone can rebuild it (`bun run zip`) and compare its checksum.

### CurseForge

The upload (`tools/release/curseforge.py`) needs, under Settings > Secrets and variables > Actions:

| Name                       | Kind               | Value                                                                                      |
| -------------------------- | ------------------ | ------------------------------------------------------------------------------------------ |
| `CURSEFORGE_API_TOKEN`     | secret             | an API token from https://authors.curseforge.com/#/settings/api-tokens                     |
| `CURSEFORGE_PROJECT_ID`    | variable           | the project's number, shown on its overview page                                           |
| `CURSEFORGE_GAME_VERSIONS` | variable           | the game versions the file is for, comma separated: ids, or names as CurseForge lists them |
| `CURSEFORGE_RELEASE_TYPE`  | variable, optional | `release`, `beta` or `alpha` (default `release`; `beta` for a pre-release)                 |

To find the game version's id or name, with the token in the environment:

```
CURSEFORGE_API_TOKEN=... python tools/release/curseforge.py --list-versions 1.15
```

Until the token is set the upload is skipped (the workflow says so). The file's relations on CurseForge (QuestieDB
required, the optional addons) come from `addons/OneMoreQuest/.pkgmeta`. To see what would be sent without sending
it: `python tools/release/curseforge.py --zip dist/OneMoreQuest-<version>.zip --dry-run`. A release whose CurseForge
upload failed can be retried from Actions > Release > Run workflow, with "Upload to CurseForge" ticked.

## Licence

GPL-3.0 (OneMoreQuest includes GPL data from Questie): [addons/OneMoreQuest/LICENSE.md](addons/OneMoreQuest/LICENSE.md).
