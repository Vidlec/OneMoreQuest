---
name: OneMoreQuest
description: The product page and changelog of a WoW: Forever quest addon, in the game's dusk colours and carved type
colors:
  earth: "#15110c"
  leather: "#221a12"
  sky: "#1d3550"
  parchment: "#ecdcbd"
  parchment-quiet: "#b8a684"
  gold: "#e2b04a"
  gold-deep: "#8f6a26"
  gold-shadow: "#4a3510"
  scroll: "#e9d6ae"
  scroll-edge: "#c9a96e"
  ink: "#2a1f12"
  ink-brown: "#5b3a12"
  ink-red: "#66220b"
  plate-ink: "#24180a"
  plate-edge: "#f4d68c"
typography:
  code:
    fontFamily: "ui-monospace, SF Mono, Consolas, monospace"
    fontSize: "0.86em"
    fontWeight: 400
  display:
    fontFamily: "Cinzel, Marcellus, Georgia, serif"
    fontSize: "clamp(30px, 6.2vw, 88px)"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "0.02em"
  headline:
    fontFamily: "Cinzel, Marcellus, Georgia, serif"
    fontSize: "clamp(32px, 4.6vw, 54px)"
    fontWeight: 700
    lineHeight: 1.15
    letterSpacing: "0.02em"
  title:
    fontFamily: "Cinzel, Marcellus, Georgia, serif"
    fontSize: "clamp(25px, 2.6vw, 34px)"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "0.01em"
  body:
    fontFamily: "Marcellus, Iowan Old Style, Georgia, serif"
    fontSize: "18px"
    fontWeight: 400
    lineHeight: 1.7
  lead:
    fontFamily: "Marcellus, Iowan Old Style, Georgia, serif"
    fontSize: "21px"
    fontWeight: 400
    lineHeight: 1.6
  label:
    fontFamily: "Marcellus, Iowan Old Style, Georgia, serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.5
  button:
    fontFamily: "Cinzel, Marcellus, Georgia, serif"
    fontSize: "17px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0.03em"
rounded:
  sm: "3px"
  md: "4px"
spacing:
  gutter: "24px"
  feature: "72px"
  chapter: "112px"
  text: "36rem"
  wide: "70rem"
  stage: "85rem"
components:
  button-primary:
    backgroundColor: "{colors.gold}"
    textColor: "{colors.plate-ink}"
    typography: "{typography.button}"
    rounded: "{rounded.sm}"
    padding: "13px 28px"
  button-quiet:
    backgroundColor: "#1c160f"
    textColor: "{colors.gold}"
    typography: "{typography.button}"
    rounded: "{rounded.sm}"
    padding: "13px 28px"
  button-quiet-hover:
    backgroundColor: "{colors.leather}"
    textColor: "{colors.parchment}"
  nav-link:
    textColor: "{colors.parchment-quiet}"
    typography: "{typography.body}"
    padding: "10px 0"
  nav-link-current:
    textColor: "{colors.parchment}"
  scroll:
    backgroundColor: "{colors.scroll}"
    textColor: "{colors.ink}"
    rounded: "{rounded.md}"
    padding: "44px 8px 28px"
---

# Design System: OneMoreQuest

## Overview

**Creative North Star: "The Quest Board at Dusk"**

Evening in a questing town: the day's work posted in gold and ink, and the windows themselves the notices. The page
is the game's own hour of rest, a steel-blue sky over umber earth, and on that ground stand OneMoreQuest's windows,
large and lifted, as they stand over the world in the game. Words are few and set in carved capitals and flared
letters; gold marks only what matters (the name, the headings, the one way to act); the page ends on a sheet of
parchment written in ink.

The pictures are the product. They are drawn from the game (AddonSim, `bun run media`) as the windows alone on a
transparent ground, and the page gives them the most room it has: a stage wider than the reading column, and on a
phone a size their text can be read at, panned sideways. Everything else steps back for them.

It is a fantasy game's page without a game company's assets: no Blizzard logos, fonts or art, only the addon's
screenshots, its logo and free type chosen to stand close to the game's own Friz Quadrata.

**Key Characteristics:**

- Dusk sky over umber earth; parchment for words, forged gold for what matters, ink on the closing parchment.
- Cinzel's carved capitals for the name and headings, Marcellus's flared letters for everything read.
- Screenshots as the architecture: a stage of 85rem against a reading column of 36rem.
- Chapters, each opened by the one ornament: a gold rule with a diamond.
- Lifted, never glowing: soft, offset, neutral shadows; light only as sky and horizon.

## Colors

A warm dusk: one cool sky above warm earth, gold as the only accent, parchment as the only light ground.

### Primary

- **Forged Gold** (gold): the name, headings, links, the primary plate and the focus ring. Its rarity is its weight.
- **Tarnished Gold** (gold-deep): rules, the current page's underline, the quiet plate's edge, the scrollbar.
- **Gold's Shadow** (gold-shadow): the carved 2-3px drop under gold headings, never a glow.

### Secondary

- **Dusk Sky** (sky): the top of the opening and of the closing, fading into earth; with a lighter steel blue
  (`#3d658f` at 0.45-0.6 alpha) as the sky's own light at the horizon. Never a text or button colour.

### Neutral

- **Umber Earth** (earth): the page's ground.
- **Saddle Leather** (leather): code and the quiet plate's hover.
- **Parchment** (parchment): body text, the tagline, the current nav link.
- **Weathered Parchment** (parchment-quiet): secondary text (a feature's description, notes' labels, the footer);
  on the opening's sky it lightens to `#d6c6a2` to keep 4.5:1.
- **Scroll** (scroll), **Scroll Edge** (scroll-edge): the closing parchment, darkening to its edges.
- **Ink** (ink), **Ink Brown** (ink-brown), **Ink Red** (ink-red): text, headings and links written on the parchment.
- **Plate Ink** (plate-ink), **Plate Edge** (plate-edge): the primary plate's lettering and its lit upper edge.

### Named Rules

**The One Gold Rule.** Gold is for the name, headings, links and the primary plate. A paragraph is never gold; a
background is never gold except the plate.

**The Sky Is Light Rule.** Blue appears only as the sky and its glow at the horizon, behind content, never on it.

## Typography

**Display Font:** Cinzel (with Marcellus, Georgia)
**Body Font:** Marcellus (with Iowan Old Style, Georgia)
**Mono Font:** the system's monospace (ui-monospace, SF Mono, Consolas), for commands only (`/omq`)

**Character:** Cinzel's inscriptional capitals carry the voice of an old carved notice; Marcellus's flared roman
keeps the same chisel in readable lowercase. Together they stand in for the game's Friz Quadrata, which is not free.
Both are under the SIL Open Font License and ship with the site (Cinzel in `site/fonts`, Marcellus from the addon's
`Media/Fonts`).

### Hierarchy

- **Display** (700, clamp(30px, 6.2vw, 88px), 1): the name, once, in the opening; the changelog's title.
- **Headline** (700, clamp(32px, 4.6vw, 54px), 1.15): a chapter's title, the closing call, the latest version.
- **Title** (600, clamp(25px, 2.6vw, 34px), 1.15): a feature's or a highlight's name.
- **Lead** (21px, 1.6): the opening's pitch and a release's summary, at most 36rem wide.
- **Body** (18px, 1.7): everything read, in a column of 36rem (about 65 characters).
- **Label** (16px): the requirement line, the version index.

### Named Rules

**The Carved Shadow Rule.** Gold display type casts a short solid shadow straight down (`0 2-3px 0`, gold-shadow),
as if cut into the page. It never glows.

**The rem Column Rule.** Reading widths are set in rem, not ch, so a large heading and the text under it share one
left edge.

## Layout

Three widths: the reading column (36rem) for running text, the wide row (70rem) for a feature's title beside its
description and for the parchment, and the stage (85rem) for screenshots. A 24px gutter on every side.

The home page runs: the opening (name, headline, how to get it with its requirement, the showcase screenshot, sized
to the window so the whole of it is seen at once), the pitch, three chapters of features, the closing call, the
parchment. A feature is its title and description side by side (stacked under 900px) over its screenshot across the
stage; a small screenshot stands beside its words instead (`feature-split`). Space grows with rank: 72px before a
feature, 112px before a chapter, 128px before the closing.

The changelog is one reading column: its title, a line, an index of every version, then each version; the latest
opens with its highlights across the stage, in the home page's feature layout.

Under 720px the screenshots keep a readable width (up to 720px) and pan sideways in their own scroller, bleeding to
the screen's edges; nothing else scrolls sideways.

## Elevation & Depth

Lifted, never glowing. Things that stand on the ground cast soft, offset, neutral shadows; light belongs only to the
sky and to the horizon behind the showcase.

### Shadow Vocabulary

- **Window on the ground** (`drop-shadow(0 28px 40px rgb(0 0 0 / 0.6)) drop-shadow(0 0 1px rgb(0 0 0 / 0.9))`): every
  screenshot, following the windows' own outline.
- **Plate cast** (`0 8px 18px rgb(0 0 0 / 0.35)`, the quiet plate `0 6px 14px rgb(0 0 0 / 0.3)`): buttons.
- **Parchment** (`0 30px 60px rgb(0 0 0 / 0.55)`): the closing sheet.
- **Horizon light**: a radial gold wash at 0.16 alpha behind the showcase, never on an element's edge.

### Named Rules

**The No Halo Rule.** No zero-offset coloured shadow, box or text. Depth is offset and neutral; light is a
background.

## Shapes

Nearly square: plates and code at 3px, the parchment at 4px. No pills, no rounded cards. The diamond (a square turned
a quarter, gold, ringed in earth) is the one ornament; it opens each chapter on a rule fading out at both ends.

## Components

### Buttons

Forged and engraved, and few: the opening and the closing each have one pair.

- **Shape:** squared (3px).
- **Primary (Install with CurseForge):** a gold plate (`#ecc061` to `#d6a23e`) edged `#f4d68c`, an engraved lower
  edge (`inset 0 -2px 0 #9a7228`), dark ink text (`#24180a`), Cinzel 600 at 17px.
- **Quiet (Download the zip):** a dark plate (`#1c160f`) edged in tarnished gold, gold text.
- **Hover / Focus / Active:** the primary brightens (1.08); the quiet one lightens to leather with parchment text;
  pressing sinks 1px. Focus is a 2px gold ring, 3px out.

### Navigation

Three links at the top right in weathered parchment; the current page in parchment with a tarnished-gold underline.
On the home page the bar lies over the sky and keeps only the logo (the title below is the name).

### Screenshot (signature)

The game's windows alone (`site/media/<id>.webp`, transparent WebP drawn at 3× and shown at half its pixels), on the
ground with the window shadow, as wide as the stage allows. Its alt text says what the windows show, not the heading
above it.

### Parchment (signature)

The closing sheet: what the addon needs, its commands, its credits, in three columns divided by ink rules (stacked
on narrow screens), written in ink, its links in ink red.

## Do's and Don'ts

### Do:

- **Do** give screenshots the stage (85rem) and redraw them (`bun run media`) rather than enlarging a picture past
  half its pixels.
- **Do** write alt text that describes the windows' content.
- **Do** keep QuestieDB, the requirement, beside every way to get the addon.
- **Do** set reading widths in rem (36rem) and keep body text at 18px, 4.5:1 or better.
- **Do** credit QuestieDB and say that World of Warcraft belongs to Blizzard, once, in the footer.

### Don't:

- **Don't** use Blizzard's logos, fonts or extracted art; only the addon's own screenshots.
- **Don't** add download counts, ratings or testimonials that do not exist.
- **Don't** put a glow or zero-offset coloured shadow on anything (The No Halo Rule).
- **Don't** use gold for paragraphs or backgrounds other than the primary plate (The One Gold Rule).
- **Don't** set the page in rounded, equal SaaS cards or put an eyebrow label over a heading.
- **Don't** add the diamond ornament anywhere but a chapter's opening.
