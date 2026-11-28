# OneMoreQuest

A quest addon for WoW: Forever: a quest log beside the map, a tracker grouped by zone, and map marks showing where
to go. Built on QuestieDB. The player-facing description is [addons/OneMoreQuest/README.md](addons/OneMoreQuest/README.md);
what changed in each version is [addons/OneMoreQuest/CHANGELOG.md](addons/OneMoreQuest/CHANGELOG.md).

Downloads: the [releases](../../releases) (each with its SHA-256 checksum) and
[CurseForge](https://www.curseforge.com/wow/addons/onemorequest). The product page, with screenshots:
https://vidlec.github.io/OneMoreQuest/.

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
sim/                       the simulator's scenarios, plugins and helpers (AddonSim); sim/scenarios/media/ the
                           product page's screenshots
site/                      the product page: its features and links (site.json), its style, its screenshots (media/)
tools/
  release/                 the release: zip, notes, CurseForge upload (TypeScript, run by Bun; no dependencies)
  site/                    the product page's build (bun run site) and its screenshots (bun run media)
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
bun run release:version # the next version (patch, minor, major or 1.2.3) into package.json and the TOC
bun run release:dry-run # the zip, then what the CurseForge upload would send (nothing is sent)
bun run site            # the product page into dist/site
bun run site:preview    # the product page served as GitHub Pages does, and CurseForge's description
bun run media           # the product page's screenshots into site/media (the simulator, headless)
```

Add a Lua file to the addon by adding it to `OneMoreQuest.toc`: the unit tests, the simulator and the release all
load the TOC's list, and the release build fails on a Lua file the TOC does not load. CLAUDE.md has the conventions.

## Releasing

A release goes out when a pull request that raises the version is merged to main:

1. In the pull request, raise the version: `bun run release:version patch` (or `minor`, `major`, or a version like
   `1.2.3`). It sets `"version"` in `package.json`, the one place the version is kept, writes it into the TOC's
   `## Version:` and `## Title:`, and adds the version's section to `CHANGELOG.md` (`## 1.2.3`): write what changed
   under it. A version like `1.2.3-beta1` is a pre-release. The build fails on a TOC whose version is not
   package.json's.
2. Merge it. The Release workflow runs the checks, builds `OneMoreQuest-<version>.zip` and `SHA256SUMS.txt`, creates
   the GitHub release `v<version>` (the changelog section, how to install, the checksum, and the merged pull
   requests), and uploads the zip to CurseForge.

A merge that does not raise the version releases nothing. The zip is built byte for byte the same from the same
files and the same Bun (`packageManager` in package.json), so anyone can rebuild it (`bun run zip`) and compare its
checksum.

### CurseForge

The upload (`tools/release/curseforge.ts`) needs, under Settings > Secrets and variables > Actions:

| Name                       | Kind               | Value                                                                                      |
| -------------------------- | ------------------ | ------------------------------------------------------------------------------------------ |
| `CURSEFORGE_API_TOKEN`     | secret             | an API token from https://authors.curseforge.com/#/settings/api-tokens                     |
| `CURSEFORGE_PROJECT_ID`    | variable           | the project's number, shown on its overview page                                           |
| `CURSEFORGE_GAME_VERSIONS` | variable           | the game versions the file is for, comma separated: ids, or names as CurseForge lists them |
| `CURSEFORGE_RELEASE_TYPE`  | variable, optional | `release`, `beta` or `alpha` (default `release`; `beta` for a pre-release)                 |

To find the game version's id or name, with the token in the environment:

```
CURSEFORGE_API_TOKEN=... bun tools/release/curseforge.ts --list-versions 1.60
```

WoW: Forever 1.60.1 is `17053`.

Until the token is set the upload is skipped (the workflow says so). The file's relations on CurseForge (QuestieDB
required, the optional addons) come from `addons/OneMoreQuest/.pkgmeta`. To see what would be sent without sending
it: `bun run release:dry-run` (with `CURSEFORGE_GAME_VERSIONS` and `CURSEFORGE_PROJECT_ID` in the environment to see
them too). A release whose CurseForge
upload failed can be retried from Actions > Release > Run workflow, with "Upload to CurseForge" ticked.

### The product page

https://vidlec.github.io/OneMoreQuest/ is built from the addon's README.md (its opening, what it needs, its commands,
its credits), CHANGELOG.md (every version, each with a link of its own), the TOC's version and notes, and
`site/site.json` (the headline, the links, and the features, each with its screenshot). The Release workflow
publishes it on every merge to main, before the release (Settings > Pages > Source: GitHub Actions). `bun run site`
builds it into `dist/site`; `bun run site:preview` builds it and serves it as GitHub Pages does
(http://127.0.0.1:4321/OneMoreQuest/), with CurseForge's description at http://127.0.0.1:4321/curseforge/. Its type
is Cinzel (`site/fonts`) and Marcellus (the addon's `Media/Fonts`), free stand-ins for the game's Friz Quadrata.
Its design system is `DESIGN.md` (with `PRODUCT.md`, the product it presents).

Screenshots are made in the simulator and committed: `bun run media [feature ...]` plays each feature's scenario
(`sim/scenarios/media/<id>.lua`, which saves the windows it shows with `saveScene(id, { only = {...} })`) and draws
it headless into `site/media/<id>.webp` (WebP, with its alpha: a tenth of a PNG), those windows alone on a transparent background. Look at them, then commit
them with the change they show. A new feature is an entry in `site.json` and a scenario of the same name. The
pictures are drawn at twice the screen's size (`pictureScale`) and shown at their own, so they stay sharp.

A release worth showing gets highlights: `site/releases/<version>.json` (a summary, and each new thing with its
picture, a scenario in `sim/scenarios/media` like the features'). The changelog page opens that version with them,
and the GitHub release's notes and CurseForge's file changelog start with them (their pictures the product page's,
published before the release).

CurseForge's project description is set by hand, once: paste `dist/site/curseforge-description.html` (its HTML
source) into the description's source view. Its pictures are the site's own, so each release's new screenshots show
there too. Each file's changelog on CurseForge links to its version on the product page. The gallery is uploaded by
hand.

## Licence

GPL-3.0 (OneMoreQuest includes GPL data from Questie): [addons/OneMoreQuest/LICENSE.md](addons/OneMoreQuest/LICENSE.md).
