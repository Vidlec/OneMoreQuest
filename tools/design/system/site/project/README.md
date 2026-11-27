Build OneMoreQuest's windows from Forever's own window kit, so nothing looks bolted on. Every value here comes from the WoW Forever client (build 1.60.1): its templates (PortraitFrameTemplate, InsetFrameTemplate, NineSliceLayouts and Forever's own overrides), its atlases (Forever's variants end in `-c60`), its font styles (FontStyles.xml) and its colour table (GlobalColor). In an addon, inherit the game's templates and set atlases by name; never ship copies of the art.

## Two materials

- **Dark iron and stone**: windows, panels, lists, bars, tooltips. Forever's heavy bronze-and-iron frame (Window), rock and marble grounds, sunken panels (InsetPanel). Labels gold (`normal-font`, GameFontNormal), values white (`highlight-font`), state colours bright (`green-font`, `red-font`, `disabled-font`).
- **Parchment**: only for pages that are read, as the spellbook's (SpellbookPage). Dark ink (`parchment-text`), a large dark heading (`parchment-title`) over a drawn rule (`spellbook-divider`), entries as an icon with its name. Parchment carries **no boxes, fills or borders**.

Never mix them: no gold or white text on parchment, no ink on iron, no light rounded cards anywhere.

## Structure inside a window

- A window is a Window (portrait, title, close), holding one or more InsetPanels.
- Sections: a carved title plate (`UI-Character-Info-Title-c60`) with its name centred, then label-and-value lines ruled by `UI-Character-Info-ScrollLine-c60` (StatList).
- Collapsible groups: the group's name in gold, `common-button-list-minus` / `-plus` at the right (StatList).
- Progress: the SkillBar, its value centred in white.
- Things: an icon in its frame (Slots), never a bare square.
- Actions: RedButtons along the bottom; a CheckBox for options; a SearchBox and dropdown button above lists.

## Type

- Friz Quadrata (`Fonts\FRIZQT__.TTF`) for nearly everything: GameFontNormalSmall 10, GameFontNormal 12, QuestFont 13, GameFontNormalLarge 16, GameFontNormalHuge 20.
- Morpheus (`Fonts\MORPHEUS.ttf`) for quest titles and decorative headings: QuestTitleFont 18, QuestFont_Large 15, Fancy22Font 22.
- Arial Narrow (`Fonts\ARIALN.TTF`) for numbers on bars and icons, and chat.
- On iron, text has a 1px black shadow; on parchment none.
- These pages show close free faces in their place (Marcellus, Metamorphous, Archivo Narrow); the real ones are the game's and are not copied here.

## Colour by meaning

- Quest levels: `difficulty-impossible` to `difficulty-trivial` against the player's level.
- Items: `quality-poor` to `quality-artifact` on names only.
- People: `class-warrior` to `class-druid` on names.
- Gains and losses: `green-font` and `red-font` on iron.

## Showing numbers

1. **A stat line**: label left in gold, value right in white, on a ruled line (StatList).
2. **A bar**: the SkillBar with "20 / 75" centred.
3. **An icon with a number**: a Slot with its count bottom-right, or an icon beside a label and value.

## Iconography

- Icons are the game's `Interface\Icons\*`, always inside a frame (Slots), cropped a little when the frame has none.
- Map and NPC marks are the game's atlases (MapMarks), never redrawn or recoloured.
- No emoji, no line-icon sets.

## Voice

- Short labels in sentence case, as the game writes them: "Track Recipe", "Show low-level quests", "Turn in to Rane Yorick".
- Numbers the game's way: "20 / 75", "6/10 Theramore Medal", "850 experience", "2 h 51 m".
