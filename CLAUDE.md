# WowAddons: OneMoreQuest

OneMoreQuest (OMQ) is a quest addon for **WoW: Forever** (client 1.60.1, interface 16001, Lua 5.1): a quest log beside
the map, a tracker grouped by zone, and quest areas and marks on the map and minimap. Built on QuestieDB.

- **The addon:** `addons/OneMoreQuest/`, in Lua, exactly as it goes into the game's `Interface\AddOns` folder (the
  game's `OneMoreQuest` folder is a junction to it). The simulator, the unit tests and the release all use it.
- **The simulator:** AddonSim, a repo of its own (https://github.com/Vidlec/wow-client-sim), checked out beside this
  one as `../AddonSim` and linked in with `bun link` (`node_modules/addonsim`). Its own guide for agents is
  `node_modules/addonsim/AGENTS.md`.

README.md lists the folders. This file says how to work in them.

## Ground rules

- **Don't commit or push** unless asked. Leave changes for the user to review.
- **Forever only.** Use the C_ API (`C_Item.GetItemInfo`). An older client's global alone (`GetItemInfo`) does not
  exist on Forever: behind `GetItemInfo and ...` the feature silently never runs. A fallback after the C_ function is
  excused on its line: `-- luacheck: ignore 113 (an older client's fallback)`.
- **Rules come from data.** Never hardcode quest ids in the addon (scenarios may name the quests they test). What
  holds a quest back, where it is, what it unlocks: read from QuestieDB (`ns.Database`) and the addon's indexes.
- **Behave like the game.** When the game has a native behaviour (M opens the map, L the quest log, right click
  resets, Esc closes), match it exactly. Ask what the game does before inventing.
- **Other addons are there.** Questie, OpenMap, Leatrix Maps, MapUtils, TomTom, Auctionator and others take over
  frames and send messages. Each gets a provider in `Compatibility/`. Be resilient: check before use, never error on
  their absence or on a format change (the Questie party-message bug: nothing is sent until a peer is heard, and
  only what that version is known to read).
- **Every player-facing string** goes through `ns.L("...")` (counts: `ns.Lp(n, "%d quest", "%d quests")`) and gets
  its Czech translation in `Locales/` (`Czech*.lua`; a count has three forms). `tests/Language.lua` fails on a
  phrase whose values differ between the languages, and draws every window in Czech.
- **Every setting** is a key in `Core/Core.lua`'s `DEFAULT_SETTINGS` (saved values of another type are reset at
  login, so a default's type is its contract: use `0`, not `false`, for "unset" numbers) and an option in
  `Core/Settings.lua`. `tests/Log.lua` fails on a switch nothing reads.
- **Player-facing changes** get a line in `addons/OneMoreQuest/CHANGELOG.md` under the next version, in the game's
  voice. A release is cut from that section.
- **Don't over-engineer, don't leave diagnostics in.** A debug command or a recorder added to find a bug comes out
  once the bug is fixed (or goes behind a setting the user asked for).

## Writing the addon

### Lua

The addon is Lua 5.1, as the game runs it (LuaJIT in the simulator: write nothing LuaJIT-only).

- **Format and lint.** StyLua formats it (`stylua.toml`: 120 columns, 4 spaces, double quotes). luacheck lints it and
  knows every Forever global (`.luacheck/forever-globals.lua`; regenerate with `bun run luacheck:globals` after a client
  update), so a misspelled or missing API name is caught. Lua uses `function` as every file does.
- **A file** starts `local addonName, ns = ...` (or `local _, ns = ...`), makes its module a local table, puts it on
  `ns` (`ns.Prices = Prices`), and ends by registering what it does at each moment: `ns.registerModule({ name = ...,
  create = ..., refresh = ..., events = {...}, changes = {...} })` (Core runs modules in TOC order).
- **Nothing global.** Every name is local to its file; files share only through `ns`. A global leaks into every other
  addon (luacheck fails on it). The only globals are the saved variables, the frames the game needs by name
  (`OneMoreQuestLog`...) and the slash command.
- **Comments say why**, in full sentences, and LuaLS annotations (`---@param`, `---@return`) document what a function
  takes and gives. Keep them when changing code: they are the design notes.
- **Lua's traps:**
  - `local a, b = x and f()` keeps only f's first value: b is always nil (luacheck says "never set").
  - `0` and `""` are true; only `nil` and `false` are false. Compare with `== nil` where a value can be `false`.
  - `#t` is undefined on a table with holes; `table.remove` inside `ipairs` skips entries; `pairs` has no order.
  - `string.find(s, plain)` needs its fourth argument `true` for a plain needle, or `%` patterns apply.
  - `unpack` has a limit (a few thousand values): copy a long list with a loop.
  - A scope holds about 200 locals and a function about 60 upvalues: group a file's constants in tables when it grows.
- **Defensive where the game or other addons decide.** Check what another addon or a saved file gives before using it
  (types, lengths, bounds); a party message from another player is untrusted input. Run a third party's callback with
  `pcall`. Never let one bad quest stop a whole pass (skip it, report once).
- **Combat lockdown:** protected frames (secure buttons, the game's own panels) cannot be shown, hidden, moved or
  created in combat. Check `InCombatLockdown()`, and do it after the fight (a module's `afterCombat`).
- `sim/plugins/questie/` is Questie's own code, copied unchanged: neither formatted nor linted.

### Style: readable by a stranger

The house style follows the lua-users Lua Style Guide (http://lua-users.org/wiki/LuaStyleGuide). Where it leaves a
choice, this code base's way below wins, because consistency within the project matters more than any one rule.

- **Small functions that do one thing.** A function reads top to bottom without scrolling. Keep cyclomatic complexity
  at 25 or below (luacheck fails the addon's code above it) and nesting at 3 or 4 levels. When a function grows:
  - pull each step out into a named local function (`local function readRewards(questId)`), so the caller reads as a
    list of steps;
  - return early instead of nesting `if`s;
  - make a long `if`/`elseif` chain on a value a table of handlers (`local HANDLERS = { kind = function ... end }`).
- **One responsibility per module (SRP).** A module owns one thing: its data and the only code that changes it. Other
  modules call its functions, never reach into its tables. A file that does several unrelated things gets split by
  responsibility, and its TOC line becomes several.
- **DRY with judgement.** Code repeated three times, or twice in logic that must stay in step (a cache key and its
  invalidation, two lists drawn alike), becomes one function in the module that owns the concept. Helpers used across
  areas go in `UI/Widgets.lua` (drawing) or the owning module. Never create a grab-bag `Utils`. Two lines that merely
  look alike are not duplication.
- **KISS.** Plain tables and functions; no class systems, no metatable tricks, no indirection a reader must chase.
  Each abstraction must make its callers simpler. Delete dead code and settings nothing reads.
- **Open for extension through data (OCP).** New quest kinds, map layers, compatibility providers and settings are
  added as entries (a provider in `Compatibility/`, a module spec, a row in a table of kinds), not as `if` branches
  spread through callers.
- **Names say what, comments say why.**
  - Wide scope gets a descriptive name; a small loop gets `i`, `k`, `v`, `_`.
  - Booleans and predicates start `is`, `has`, `should`, `can` (`isComplete`, `hasTomTom()`).
  - Functions are verbs (`getQuestPlace`, `composeFeatures`).
  - Constants are `ALL_CAPS`; modules and namespaces are `PascalCase`; everything else is `camelCase`.
  - No abbreviations a newcomer must decode (`questId`, not `qid`).
- **Comments.** A space after `--`. A file opens with what it is for. Each public function gets a `---` summary and
  `---@param` / `---@return` where its types are not obvious. An inline comment explains why, never restates the code.
  No `end -- if` markers: a block too long to see its end is split instead.
- **Lua idioms** (from the guide):
  - `if value then` rather than `~= nil`, unless `false` is a meaning of its own.
  - `x = x or default`. Use `a and b or c` only when `b` can never be false or nil.
  - `next(t) == nil` for an empty table; `t[#t + 1] = v` to append.
  - Narrow a local's scope with `do ... end` when a few values serve one step.
  - No deprecated 5.1 functions (`table.getn`, `table.foreach`). The `debug` library is for the tracing tools only.
- **Low cognitive load.** A reader holds a few things at a time:
  - no function with more than about 5 parameters (pass a table of options);
  - no boolean parameters whose meaning is invisible at the call (`draw(true, false)`): name them in an options
    table, or make two functions;
  - no hidden state changed far from where it is read;
  - one level of abstraction per function.

### A new file

Put it in its area's folder (Core, Data, Quests, Loot, Chronicle, Party, UI, Tracker, Log, Map, Map/Marks, Gamepad,
Compatibility) and add its line to `OneMoreQuest.toc` in load order. The TOC is the only list: the unit tests
(`tests/run.lua` reads it), the simulator and the release all follow it, and the release build fails on a Lua file no
TOC line loads.

## The UI kit and the design system

Everything must look like part of Forever's own UI, never an addon bolted on.

- **The design system** is in `tools/design/system/site/project/`. `README.md` has the rules, `tokens.json` and
  `tokens.css` the colours, fonts and sizes taken from the client, and `components/` one folder per component:
  Window, InsetPanel, StatList, SkillBar, Slots, RedButton, CheckBox, SearchBox, Tooltip, SpellbookPage, Money,
  MapMarks, Cover. `gallery.html` shows them. Read its README before designing a window. In short:
  - **Two materials, never mixed.** Dark iron and stone (windows, panels, lists, tooltips; gold labels, white
    values, 1px black shadow). Parchment only for pages that are read (ink, Morpheus headings, no shadow).
  - **Structure.** A Window holds InsetPanels. Sections get a carved title plate and ruled label/value lines.
    Progress is the SkillBar. Things are icons in their frames. Actions are RedButtons along the bottom.
  - **Type.** Friz Quadrata for text, Morpheus for quest titles and headings, Arial Narrow for numbers.
  - **Colour by meaning.** Quest difficulty, item quality and class colours, green and red for gains and losses.
  - **The game's art only.** Its atlases and `Interface\Icons`; no emoji, no line icons.
  - **Voice.** The game's: sentence case, "20 / 75", "850 experience".
- **The kit in code** is `UI/Widgets.lua` (`ns.Widgets`):
  - `Widgets.COLORS`, for iron and parchment.
  - Fonts: `getFont` / `setTextFont` / `applyFonts`, which handle the Czech look-alikes.
  - Formatting: `formatMoney`, `formatDistance`, `formatQuestTitle`, `getDifficultyColor`.
  - Portraits, and `setMinimalCheckLook` for Forever's checkbox.
  - **The Canvas** (`Widgets.createCanvas`): every window's content. It lays out pooled texts, rects, dots, images,
    icons, framed icons, stat bars, marks, portraits and buttons at exact positions (`addText`, `addRect`,
    `addImage`, `addIcon`, `addFramedIcon`, `addStatBar`, `addMark`, `addPortrait`, `addButton`), then `finish`.
    It owns scrolling (`getScroll`, `setScroll`, `scrollIntoView`).
  - **Pooled widgets are reused across drawings:** never tag one with your own fields (a stale tag sent clicks to
    the wrong rows); find buttons by their `data`.
- **Each part's look:** the quest window's in `Log/Base.lua` (`ns.LogStyle`), the map's in `Map/Marks/Look.lua` and
  `Layout.lua` (`ns.MapMarksStyle`), the frame round the window in `UI/WindowBorder.lua`, the tracker's in
  `Tracker/TrackerLook.lua`. Add to these rather than hardcoding colours or sizes in a drawing.
- **Mockups:** when the user asks for a design, mock it up first, with variants, in the design system's look, as an
  Artifact page they open in the browser (inline widgets have not shown for them). Build only the variant they pick.

## Performance

The addon runs inside the game's frame. A stutter is a bug. The rules:

- **A frame's budget.** Core's redraw of everything takes at most 3 ms a frame (`REFRESH_SHARE_MILLISECONDS`), and the
  rest waits a frame. Background work is sliced by the clock (`debugprofilestop`), not by a count:
  - the quest index after login: 4 ms, 12 ms while the window waits for it;
  - area shapes: 4 ms;
  - the kept map drawing: 3 ms with the map open, 1 ms closed, and at most 300 pieces a frame;
  - herb and ore spots: 1 ms.

  A frame over 16 ms is traced (Core's `TRACE_SLOW_MILLISECONDS`).
- **Widget calls cost most.** Every call crosses from Lua into the game. Don't call `SetPoint`, `SetText`, `Show`,
  `SetAlpha` or `SetVertexColor` when nothing changed (the map layers guard each call). Reuse pooled regions, never
  create in a loop, and hide what is not shown with its anchors cleared: the game lays out every anchored region
  on each drag frame, hidden or not.
- **No garbage in hot paths.** No tables, closures or string building per frame or per mark (`Geometry` reuses one
  vector). Cache per frame what many callers ask (`ns.frameNumber`: the player's position). Key caches by what they
  depend on and invalidate them on the event that changes it (`Availability.getChangeKey()`).
- **Don't redraw or re-sort what did not change.** A hover must change only the hovered quest's pieces: the
  others' areas and marks must not blink. Spawn marks are sorted again only in the zones whose own quests changed,
  once.
- **Measure, don't guess.** The audits in `sim/scenarios/audits/` count and time each thing the addon does. Run
  the one for the area you touch before and after a change, and say the numbers:
  - `api-budget.lua`: widget calls and creations per action, counted, so the numbers hold on any machine;
  - `openmap-cost.lua`: with OpenMap, the cost per thing done with the map, and who asked for each redraw;
  - `map-world-cost.lua`: many quests tracked; time, calls, the worst frame. Options go in `sim/lib/mapcost.options`
    (`WORLD_RENDERER=classic`, `MAPCOST_TOP=30`, `WORLD_IDLE=25`);
  - `hover-blink.lua`: what changes for the other quests on a hover;
  - `focus-flash.lua`, `minimap-move-cost.lua`, `zoom-cost.lua`, `window-steady.lua`, `profile-*.lua`.

  Pictures to compare: `map-world-look.lua` / `map-plain-look.lua`, then `bun addonsim shot`.

## Build, test, look

```
bun run test:unit        # the unit tests (their own fake game, no simulator): about 2 s
bun run test             # the unit tests, then every simulator scenario (about 25 s): before you finish
bun run lint             # StyLua + luacheck (Lua) and Biome (the tools' TypeScript, JSON): before you finish
bun run typecheck        # the tools' TypeScript
bun run format           # Biome and StyLua write their fixes
bun run zip              # the release zip and SHA256SUMS.txt into dist/
```

The simulator:

```
bun addonsim run <scenario>        # one scenario of sim/scenarios in a warm game: PASSED/FAILED, failures as file:line
bun addonsim ui [text]             # the shown frames: label, ref (#id or name), x,y WxH, "text"
bun addonsim shot [--frame <ref>]  # a PNG of the screen (prints its path): look at what you changed
bun addonsim eval '<lua>'          # Lua in the game: the steps (accept(844), click("Accept"), wait(1)), G = game globals
bun addonsim state                 # character, position, quest log, chat
bun addonsim test                  # the whole suite
bun addonsim docs [step]           # every scenario step
```

- The first command starts a daemon that keeps a game booted. Commands then take about 0.1 s, and `run` about 1 s
  plus the scenario. After `run`, the game stays where the scenario ended, so look at it. After an edit, the daemon
  boots a fresh game by itself.
- The game's clock moves only in steps (`wait(1)`). Globals work by bare name and as `G.X`.
- In Git Bash write `bun addonsim slash omq`, not `/omq` (Bash turns `/omq` into a path).
- **Known flake:** `hover-areas.lua` sometimes fails in the full suite and passes alone. Rerun it alone before
  calling it broken.
- For a small visual tweak, the unit tests plus one `run` are enough; for logic, add or extend a scenario.
- **A new scenario** is a file in `sim/scenarios`. Its first lines may set `--@login race=Orc,class=WARRIOR,level=12`,
  `--@addons ...` or `--@locale deDE`. Golden snapshots are in `sim/scenarios/golden/` (`bun addonsim test --update`
  rewrites them). Compare floats with a tolerance.
- **To drive the game with tools,** use a `.mcp.json` here, not committed:
  `{ "mcpServers": { "addonsim": { "command": "bun", "args": ["addonsim", "mcp"] } } }`.
  Tools: `run`, `test`, `eval`, `ui`, `screenshot`, `click`, `key`, `event`, `slash`, `reload`, `state`, `docs`,
  `data`.

Before finishing: `bun run lint`, `bun run typecheck`, `bun run test`. Say what you ran and what it printed; a check you
skipped is said too.

## Data and tools

- **The data generators:**
  - `bun tools/data/make-crafted-items.ts [build]` regenerates `Data/CraftedItems.lua` from the client's tables;
  - `bun addonsim test sim/tools/gathering-nodes.lua` regenerates `Data/GatheringNodes.lua`.

  Generated files are never edited by hand.
- **Releasing** (README.md, Releasing): a merge to main that raises `## Version:` and the Title's version in the TOC,
  with that version's CHANGELOG section, builds the zip, creates the GitHub release (notes, checksum), and uploads to
  CurseForge once its secret is set. The release scripts are in `tools/release/` (Python, standard library).
- **CI** (`.github/workflows/checks.yml`) runs the format, lint and unit checks and the release build on every
  pull request. The simulator's scenarios run on a developer's machine only.
- **Design boards and the design system's sources** are in `tools/design/`. They are not shipped and not linted.

## Setup on a fresh machine

```
git clone https://github.com/Vidlec/wow-client-sim.git AddonSim
cd AddonSim && bun install && bun link && bun run tools:lua
cd ../WowAddons && bun install
```

AddonSim also needs LuaJIT (`winget install DEVCOM.LuaJIT`) and its first-run setup (the game's AddOns folder, the
interface source, the game's files): `cd AddonSim && bun run start` once, then follow the page. Its settings are in
`%APPDATA%\AddonSim\settings.json`; its downloaded data (`cache/`, `interface/`, `saved/`) is in its checkout. For the
game itself, point the game's `Interface\AddOns\OneMoreQuest` at this repo's `addons/OneMoreQuest` (a junction).

## Windows: links and deleting

`node_modules/addonsim` and the game's AddOns folder are directory junctions. A recursive delete of a folder that holds
one (`git worktree remove --force`, `rm -rf`, `rmdir /s`) can follow the junction and empty its target: this once
wiped the AddonSim checkout. Before deleting a folder that may hold a junction (a worktree after `bun install`, a
copied `node_modules`), remove the junction itself first (`cmd /c rmdir <link>`, which leaves the target alone), or
leave the folder in the temp directory.
