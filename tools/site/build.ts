// Builds OneMoreQuest's product page into dist/site: bun run site. The release workflow publishes it on GitHub Pages.
//
// - index.html: the opening (the name, the headline, how to get it and what it needs, the first feature's picture as
//   the showcase), the README's pitch, then the features of site/site.json in their chapters, each with its
//   screenshot (site/media/<id>.webp, made by bun run media), a closing call to get it, and the README's what it needs,
//   commands and credits on one parchment.
// - changelog.html: an index of the versions, then each version of CHANGELOG.md with a link of its own (#v0-16-0); a
//   version with highlights (site/releases/<version>.json) opens with them, each with its screenshot.
// - curseforge-description.html: the same page as CurseForge's project description takes it (pasted once by hand:
//   its pictures are the site's own, so a release's new screenshots show there too).
//
// The pictures are drawn at site.json's pictureScale (bun run media) and shown at half their pixels: sharp on a
// high-density screen at as large as the page lets them be. Its type is close to the game's own Friz Quadrata (which
// is not free): Cinzel for the name and headings (site/fonts), Marcellus for the text (the addon's Media/Fonts); both
// under the SIL Open Font License, shipped with their licences. Its design system: DESIGN.md.
//
// A feature whose picture is missing is shown with its text alone, and said so (a warning in GitHub Actions).

import { existsSync } from "node:fs";
import { copyFile, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { escapeHtml, getVersionAnchor, renderMarkdown } from "./markdown.ts";
import { listReleasePictures, type Release, readRelease } from "./releases.ts";

const ROOT = join(import.meta.dir, "..", "..");
const ADDON = join(ROOT, "addons", "OneMoreQuest");
const SITE = join(ROOT, "site");
const OUT = join(ROOT, "dist", "site");
// The type, with the licences beside it (SIL Open Font License): Marcellus from the addon's Media/Fonts, Cinzel from
// site/fonts
const ADDON_FONTS = ["Marcellus-Regular.ttf", "Marcellus-OFL.txt"];
const SITE_FONTS = ["Cinzel-Variable.ttf", "Cinzel-OFL.txt"];
// Device pixels per CSS pixel the pictures are shown at: sharp on a high-density screen
const DISPLAY_DENSITY = 2;
// The README's lines the page says elsewhere (the footer says who World of Warcraft belongs to)
const SAID_ELSEWHERE = /^World of Warcraft belongs to Blizzard/;

type Feature = {
  id: string;
  title: string;
  text: string;
  alt: string;
  chapter: string;
  layout: "wide" | "split";
  /** The pictureScale this feature's picture is drawn at, when not the site's (a small window drawn larger) */
  scale?: number;
};
type Chapter = { id: string; title: string };
type SiteSettings = {
  headline: string;
  introParagraphs: number;
  pictureScale: number;
  url: string;
  curseforge: string;
  github: string;
  requirement: { name: string; url: string; note: string };
  chapters: Chapter[];
  features: Feature[];
};
/** A screenshot: its file and its size as shown (CSS pixels: its pixels over the display density) */
type Picture = { file: string; width: number; height: number };

const readToc = async () => {
  const toc = await readFile(join(ADDON, "OneMoreQuest.toc"), "utf8");
  const getField = (name: string) => new RegExp(`^## ${name}: (.*)$`, "m").exec(toc)?.[1]?.trim() ?? "";
  const version = getField("Version");
  if (!version) {
    throw new Error("the TOC has no ## Version");
  }
  return { version, notes: getField("Notes") };
};

// The README's sections by their ## heading; "" is what comes before the first (its title and opening)
const readReadmeSections = async () => {
  const readme = await readFile(join(ADDON, "README.md"), "utf8");
  const sections = new Map<string, string>();
  let name = "";
  let lines: string[] = [];
  for (const line of readme.split("\n")) {
    const heading = /^## (.*)$/.exec(line);
    if (heading) {
      sections.set(name, lines.join("\n"));
      name = (heading[1] ?? "").trim();
      lines = [];
    } else if (!SAID_ELSEWHERE.test(line)) {
      lines.push(line);
    }
  }
  sections.set(name, lines.join("\n"));
  return sections;
};

/** A WebP's size in pixels, from its first chunk: VP8X (lossy with alpha, as bun run media writes), VP8L
 * (lossless) or VP8 (lossy) */
const readWebpSize = (bytes: Buffer) => {
  if (bytes.length < 30 || bytes.toString("latin1", 0, 4) !== "RIFF" || bytes.toString("latin1", 8, 12) !== "WEBP") {
    return undefined;
  }
  const chunk = bytes.toString("latin1", 12, 16);
  if (chunk === "VP8X") {
    return { width: 1 + bytes.readUIntLE(24, 3), height: 1 + bytes.readUIntLE(27, 3) };
  }
  if (chunk === "VP8L") {
    const bits = bytes.readUInt32LE(21);
    return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >>> 14) & 0x3fff) };
  }
  if (chunk === "VP8 ") {
    return { width: bytes.readUInt16LE(26) & 0x3fff, height: bytes.readUInt16LE(28) & 0x3fff };
  }
  return undefined;
};

// A screenshot's size, from its header (width and height on the page keep it from jumping as pictures load)
const readPicture = async (id: string): Promise<Picture | undefined> => {
  const file = join(SITE, "media", `${id}.webp`);
  if (!existsSync(file)) {
    return undefined;
  }
  const size = readWebpSize(await readFile(file));
  if (!size) {
    throw new Error(`site/media/${id}.webp is not a WebP`);
  }
  const toShown = (pixels: number) => Math.round(pixels / DISPLAY_DENSITY);
  return { file, width: toShown(size.width), height: toShown(size.height) };
};

const warn = (message: string) => {
  console.warn(process.env.GITHUB_ACTIONS ? `::warning::${message}` : `warning: ${message}`);
};

const composePage = (title: string, description: string, body: string, settings: SiteSettings) => `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${escapeHtml(title)}</title>
<meta name="description" content="${escapeHtml(description)}">
<meta name="theme-color" content="#15110c">
<meta property="og:title" content="${escapeHtml(title)}">
<meta property="og:description" content="${escapeHtml(description)}">
<meta property="og:image" content="${escapeHtml(new URL("media/quest-log.webp", settings.url).href)}">
<link rel="icon" href="logo.png">
<link rel="preload" href="fonts/Cinzel-Variable.ttf" as="font" type="font/ttf" crossorigin>
<link rel="preload" href="fonts/Marcellus-Regular.ttf" as="font" type="font/ttf" crossorigin>
<link rel="stylesheet" href="style.css">
</head>
<body>
<a class="skip" href="#main">Skip to the content</a>
${body}
<footer class="footer">
  <p>Made for WoW: Forever. Free software under the GNU GPL v3:
  <a href="${escapeHtml(settings.github)}">the source on GitHub</a>. Quest data from QuestieDB (GPL v3).</p>
  <p>World of Warcraft belongs to Blizzard Entertainment; this addon isn't made or endorsed by Blizzard.
  The type is Cinzel and Marcellus (SIL Open Font License).</p>
</footer>
</body>
</html>
`;

const composeHeader = (
  settings: SiteSettings,
  isHome: boolean,
) => `<header class="masthead${isHome ? " masthead-over" : ""}">
  <a class="brand" href="./" aria-label="OneMoreQuest, home"><img src="logo.png" width="40" height="40" alt=""><span>OneMoreQuest</span></a>
  <nav class="nav" aria-label="Pages">
    <a href="./"${isHome ? ' aria-current="page"' : ""}>Features</a>
    <a href="changelog.html"${isHome ? "" : ' aria-current="page"'}>Changelog</a>
    <a href="${escapeHtml(settings.github)}">Source</a>
  </nav>
</header>`;

const composeImage = (id: string, alt: string, picture: Picture, isEager: boolean) =>
  `<img src="media/${escapeHtml(id)}.webp" width="${picture.width}" height="${picture.height}" alt="${escapeHtml(alt)}"${isEager ? ' fetchpriority="high"' : ' loading="lazy" decoding="async"'}>`;

// A picture as large as the page lets it be; on a phone it keeps a readable size and pans sideways
const composeShot = (id: string, alt: string, picture: Picture | undefined, className = "shot", isEager = false) =>
  picture
    ? `<figure class="${className}"><div class="pan" tabindex="0" role="group" aria-label="Screenshot">${composeImage(id, alt, picture, isEager)}</div></figure>`
    : "";

// How to get it: the two ways, and what it needs (QuestieDB) right beside them; in full at the page's end, in a line
// at its opening (where the picture needs the room)
const composeGetting = (settings: SiteSettings, version: string, isFull: boolean) => `<div class="get">
  <p class="actions">
    <a class="button" href="${escapeHtml(settings.curseforge)}">Install with CurseForge</a>
    <a class="button button-quiet" href="${escapeHtml(`${settings.github}/releases/latest`)}">Download the zip</a>
  </p>
  <p class="requirement">Needs <a href="${escapeHtml(settings.requirement.url)}">${escapeHtml(settings.requirement.name)}</a>, ${escapeHtml(settings.requirement.note)}.${
    isFull
      ? " The CurseForge app keeps both up to date; the zip goes in your Interface/AddOns folder."
      : ` Version ${escapeHtml(version)}: <a href="changelog.html#${getVersionAnchor(version)}">what's new</a>.`
  }</p>
</div>`;

const composeFeature = (feature: Feature, pictures: Map<string, Picture>, isFlipped: boolean) => {
  const picture = pictures.get(feature.id);
  return `<article class="feature feature-${feature.layout}${isFlipped ? " feature-flip" : ""}" id="${escapeHtml(feature.id)}">
  <div class="feature-text"><h3>${escapeHtml(feature.title)}</h3><p>${escapeHtml(feature.text)}</p></div>
  ${composeShot(feature.id, feature.alt, picture)}
</article>`;
};

// The features in their chapters (site.json's order), the showcase left out: it is the opening's. A window set beside
// its words (split) changes sides from one to the next, page-wide
const composeChapters = (settings: SiteSettings, pictures: Map<string, Picture>, showcaseId: string | undefined) => {
  let splitCount = 0;
  const flips = new Map(
    settings.features.map((feature) => [
      feature.id,
      feature.layout === "split" && feature.id !== showcaseId && splitCount++ % 2 === 1,
    ]),
  );
  return settings.chapters
    .map((chapter) => {
      const features = settings.features.filter((item) => item.chapter === chapter.id && item.id !== showcaseId);
      if (!features.length) {
        return "";
      }
      return `<section class="chapter" id="${escapeHtml(chapter.id)}" aria-labelledby="${escapeHtml(chapter.id)}-title">
<h2 class="chapter-title" id="${escapeHtml(chapter.id)}-title">${escapeHtml(chapter.title)}</h2>
${features.map((feature) => composeFeature(feature, pictures, flips.get(feature.id) ?? false)).join("\n")}
</section>`;
    })
    .join("\n");
};

// The README's opening, without its title and tagline (the page has its own): its first paragraphs, the pitch (the
// rest of it says what the features below show)
const composeIntro = (sections: Map<string, string>, paragraphCount: number) =>
  renderMarkdown(
    (sections.get("") ?? "")
      .split("\n")
      .filter((line) => !/^# /.test(line) && !/^_.*_$/.test(line.trim()) && !/^Made for /.test(line))
      .join("\n")
      .trim()
      .split(/\n\s*\n/)
      .slice(0, paragraphCount)
      .join("\n\n"),
  );

const EXTRAS = ["You'll need", "Works with", "Commands", "Credits"];
// The README's list of what has no picture of its own (group play, the controller...), after the chapters
const ALSO = "Also in the box";

const composeHome = (
  toc: { version: string; notes: string },
  settings: SiteSettings,
  sections: Map<string, string>,
  pictures: Map<string, Picture>,
) => {
  const extras = EXTRAS.filter((name) => sections.has(name))
    .map(
      (name) =>
        `<section class="extra"><h2>${escapeHtml(name)}</h2>${renderMarkdown(sections.get(name) ?? "")}</section>`,
    )
    .join("\n");
  const [showcase] = settings.features;
  const showcasePicture = showcase && pictures.get(showcase.id);
  return `${composeHeader(settings, true)}
<main id="main">
<section class="hero">
  <h1 class="title">OneMoreQuest</h1>
  <p class="tagline">${escapeHtml(settings.headline)}</p>
  ${composeGetting(settings, toc.version, false)}
  ${showcase ? composeShot(showcase.id, showcase.alt, showcasePicture, "showcase", true) : ""}
</section>
<section class="intro" aria-label="Why">${composeIntro(sections, settings.introParagraphs)}</section>
${composeChapters(settings, pictures, showcasePicture ? showcase?.id : undefined)}
${
  sections.has(ALSO)
    ? `<section class="also" aria-labelledby="also-title"><h2 id="also-title">${escapeHtml(ALSO)}</h2>${renderMarkdown(sections.get(ALSO) ?? "")}</section>`
    : ""
}
<section class="closing" aria-labelledby="closing-title">
  <h2 id="closing-title">Just one more quest</h2>
  ${composeGetting(settings, toc.version, true)}
</section>
<div class="scroll">${extras}</div>
</main>`;
};

// A version's highlights (site/releases/<version>.json): its summary, then each new thing with its picture, large
const composeHighlights = (release: Release, pictures: Map<string, Picture>) => `<div class="highlights">
<p class="summary">${escapeHtml(release.summary)}</p>
${release.highlights
  .map(
    (item) => `<article class="feature feature-wide">
  <div class="feature-text"><h3>${escapeHtml(item.title)}</h3><p>${escapeHtml(item.text)}</p></div>
  ${composeShot(item.picture, item.alt ?? item.title, pictures.get(item.picture))}
</article>`,
  )
  .join("\n")}
</div>`;

// The changelog: an index of the versions, then each version a section, its heading (with its link, #v0-16-0), its
// highlights when it has some, then its notes. (CHANGELOG.md's own opening speaks to whoever writes it: left out.)
const composeChangelog = async (settings: SiteSettings, pictures: Map<string, Picture>) => {
  const changelog = (await readFile(join(ADDON, "CHANGELOG.md"), "utf8")).replaceAll("\r\n", "\n");
  const [, ...versions] = changelog.replace(/^# .*\n/, "").split(/^## /m);
  const parsed = versions.map((text) => {
    const newline = text.indexOf("\n");
    return {
      version: (newline === -1 ? text : text.slice(0, newline)).trim(),
      notes: newline === -1 ? "" : text.slice(newline + 1),
    };
  });
  const index = parsed
    .map(
      ({ version }, position) =>
        `<li><a class="version-link" href="#${getVersionAnchor(version)}">${escapeHtml(version)}</a>${position === 0 ? ' <span class="version-latest">latest</span>' : ""}</li>`,
    )
    .join("");
  const sections = parsed.map(({ version, notes }, position) => {
    const release = readRelease(version);
    return `<section class="release${release ? " release-highlighted" : ""}" aria-labelledby="${getVersionAnchor(version)}">
<h2 id="${getVersionAnchor(version)}">${position === 0 ? "What's new in " : ""}${escapeHtml(version)}</h2>
${release ? composeHighlights(release, pictures) : ""}
<div class="notes">${renderMarkdown(notes, { headingShift: 1 })}</div>
</section>`;
  });
  return `${composeHeader(settings, false)}
<main class="changelog" id="main">
<h1>Changelog</h1>
<p class="changelog-lede">What changed in each version of OneMoreQuest, newest first.</p>
<nav class="versions" aria-label="Versions"><ol>${index}</ol></nav>
${sections.join("\n")}
<p class="to-top"><a href="#main">Back to the top</a></p>
</main>`;
};

// CurseForge's description: plain HTML its editor keeps (headings, paragraphs, lists, links, pictures by full URL)
const composeCurseForgeDescription = (
  settings: SiteSettings,
  sections: Map<string, string>,
  pictures: Map<string, Picture>,
) => {
  const features = settings.features
    .map((feature) => {
      const shot = pictures.get(feature.id);
      const picture = shot
        ? `<p><img src="${escapeHtml(new URL(`media/${feature.id}.webp`, settings.url).href)}" alt="${escapeHtml(feature.alt)}" width="${shot.width}" height="${shot.height}"></p>`
        : "";
      return `<h2>${escapeHtml(feature.title)}</h2>\n<p>${escapeHtml(feature.text)}</p>\n${picture}`;
    })
    .join("\n");
  const extras = EXTRAS.filter((name) => sections.has(name))
    .map((name) => `<h2>${escapeHtml(name)}</h2>\n${renderMarkdown(sections.get(name) ?? "")}`)
    .join("\n");
  return `${composeIntro(sections, settings.introParagraphs)}
<p><strong>Made for WoW: Forever.</strong> Needs <a href="${escapeHtml(settings.requirement.url)}">${escapeHtml(settings.requirement.name)}</a>, ${escapeHtml(settings.requirement.note)}. More pictures and every version's notes:
<a href="${escapeHtml(settings.url)}">${escapeHtml(settings.url)}</a></p>
${features}
${sections.has(ALSO) ? `<h2>${escapeHtml(ALSO)}</h2>\n${renderMarkdown(sections.get(ALSO) ?? "")}` : ""}
${extras}
<p>World of Warcraft belongs to Blizzard Entertainment; this addon isn't made or endorsed by Blizzard.</p>
`;
};

const main = async () => {
  const settings: SiteSettings = JSON.parse(await readFile(join(SITE, "site.json"), "utf8"));
  const toc = await readToc();
  const sections = await readReadmeSections();
  const pictures = new Map<string, Picture>();
  for (const feature of settings.features) {
    const picture = await readPicture(feature.id);
    if (picture) {
      pictures.set(feature.id, picture);
    } else {
      warn(`site/media/${feature.id}.webp is missing: "${feature.title}" is shown without its picture (bun run media)`);
    }
  }
  // (and the releases' highlights' pictures, for the changelog)
  for (const id of listReleasePictures()) {
    const picture = pictures.get(id) ?? (await readPicture(id));
    if (picture) {
      pictures.set(id, picture);
    } else {
      warn(`site/media/${id}.webp is missing: a release's highlight is shown without its picture (bun run media)`);
    }
  }

  await rm(OUT, { recursive: true, force: true });
  await mkdir(join(OUT, "media"), { recursive: true });
  await mkdir(join(OUT, "fonts"), { recursive: true });
  const title = `OneMoreQuest: ${toc.notes.split(":")[0]}`;
  const home = composePage(title, toc.notes, composeHome(toc, settings, sections, pictures), settings);
  await writeFile(join(OUT, "index.html"), home);
  await writeFile(
    join(OUT, "changelog.html"),
    composePage(
      "OneMoreQuest: changelog",
      "What changed in each version of OneMoreQuest.",
      await composeChangelog(settings, pictures),
      settings,
    ),
  );
  await writeFile(join(OUT, "curseforge-description.html"), composeCurseForgeDescription(settings, sections, pictures));
  await copyFile(join(SITE, "style.css"), join(OUT, "style.css"));
  await copyFile(join(ADDON, "Media", "Logo64.png"), join(OUT, "logo.png"));
  for (const font of ADDON_FONTS) {
    await copyFile(join(ADDON, "Media", "Fonts", font), join(OUT, "fonts", font));
  }
  for (const font of SITE_FONTS) {
    await copyFile(join(SITE, "fonts", font), join(OUT, "fonts", font));
  }
  for (const [id, picture] of pictures) {
    await copyFile(picture.file, join(OUT, "media", `${id}.webp`));
  }
  await writeFile(join(OUT, ".nojekyll"), "");
  console.log(`the site for OneMoreQuest ${toc.version}: dist/site (${pictures.size} pictures)`);
};

await main();
