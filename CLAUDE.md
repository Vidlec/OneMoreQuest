# WowAddons

Our WoW: Forever addons: `addons/OneMoreQuest` (OMQ) and `addons/QuestieProfit`. They are tested in AddonSim, a
simulator of the client: a repo of its own beside this one (`../AddonSim`), linked in with `bun link`
(`"addonsim": "link:addonsim"`; node_modules/addonsim points at the checkout). AddonSim's own guide for agents is
`node_modules/addonsim/AGENTS.md`; the essentials are below.

## Setup on a fresh machine

Clone both repos side by side, then:

```
cd AddonSim && bun install && bun link
cd ../WowAddons && bun install
```

AddonSim also needs LuaJIT (`winget install DEVCOM.LuaJIT`) and its first-run setup (the game's AddOns folder, the
interface source): `cd AddonSim && bun run start` once, and follow the page.

## Test and look

```
bun addonsim run <scenario>        # one scenario of sim/scenarios in a warm game: PASSED/FAILED, failures as file:line
bun addonsim ui [text]             # the shown frames: label, ref (#id or name), x,y WxH, "text"
bun addonsim shot [--frame <ref>]  # a PNG of the screen (prints its path)
bun addonsim eval '<lua>'          # Lua in the game: the steps (accept(844), click("Accept"), wait(1)), G = game globals
bun addonsim state                 # character, position, quest log, chat
bun addonsim test                  # the whole suite (40 runs, about 20 s): run it before you finish
bun addonsim docs [step]           # every scenario step
```

- The first command starts a daemon that keeps a game booted (2.7 s once); then commands take about 0.1 s and
  `run` about 1 s plus the scenario's own time. After `run`, the game stays where the scenario ended: look at it.
- The game's clock moves only in steps (`wait(1)`). Game globals work by bare name (`UnitName("player")`) and as
  `G.X`; set one with `G.X = value`.
- `run` prints what the scenario prints (an audit's measurements), then PASSED/FAILED.
- OpenMap's cost to OMQ: `bun addonsim run sim/scenarios/audits/openmap-cost.lua` (widget calls, Lua share by
  addon, redraws and who asked for them, per thing done with the map open).
- After an edit, the daemon boots a fresh game by itself; a command that runs code gets it (and says so).
- In Git Bash write `bun addonsim slash omq`, not `/omq` (Bash turns `/omq` into a path).
- Scenario sim work for small visual tweaks: unit tests plus one `run` at the end are enough.

## Other checks and tools

- OMQ unit tests (their own fake game, no simulator): `cd addons/OneMoreQuest && luajit tests/run.lua`.
- Everything: `bun run test` (the unit tests, then `addonsim test`). `bun run typecheck` checks the TypeScript here.
- The release zip: `python tools/build-zip.py` (to ~/Desktop/OneMoreQuest-CurseForge).
- `bun tools/make-crafted-items.ts [build]` regenerates OMQ's CraftedItems.lua from the client's tables (AddonSim's
  SDK); `bun addonsim test sim/tools/gathering-nodes.lua` regenerates GatheringNodes.lua.
- The simulator's page for this project, to play by hand: `bun run sim` (`addonsim serve`).

## The project

- `addonsim.config.ts`: our addons, the installed ones scenarios load (QuestieDB, ForeverDungeonJournal), the
  scenarios folder `sim/scenarios`, the plugin `sim/plugins/omq-party.lua` (OMQ's party protocol for simulated
  members), Lua modules in `sim/lib`.
- A new scenario is a file in `sim/scenarios`; first lines may set `--@login race=Orc,class=WARRIOR,level=12`,
  `--@addons ...`, `--@locale deDE`. Reference snapshots live in `sim/scenarios/golden/` (`test --update` rewrites).
- `.luarc.json` gives LuaLS the scenario API (`node_modules/addonsim/types`).

## MCP

To drive the game with tools instead of the CLI, a `.mcp.json` in this folder (not committed unless wanted):

```json
{ "mcpServers": { "addonsim": { "command": "bun", "args": ["addonsim", "mcp"] } } }
```

Tools: `run`, `test`, `eval`, `ui`, `screenshot`, `click`, `key`, `event`, `slash`, `reload`, `state`, `docs`, `data`.

## Style

- Arrow functions only, never `function`, in JavaScript and TypeScript. That rule is for JS/TS only: Lua uses
  `function` as each file already does.
- OneMoreQuest's rules come from data: never hardcode quest ids in the addon (scenarios may name the quests they
  test).
- Don't commit: leave changes for the user to review.
