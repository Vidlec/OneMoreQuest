// A version's highlights: site/releases/<version>.json, written by hand for a release worth showing (a summary, and
// what is new, each with its screenshot from site/media). The changelog page shows them above the version's notes;
// the GitHub release and CurseForge's file changelog open with them (tools/release/notes.ts, curseforge.ts); bun run
// media makes their pictures. A version without the file has its notes alone.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const RELEASES = join(import.meta.dir, "..", "..", "site", "releases");

export type Highlight = { picture: string; title: string; text: string; alt?: string };
export type Release = { summary: string; highlights: Highlight[] };

export const readRelease = (version: string): Release | undefined => {
  const path = join(RELEASES, `${version}.json`);
  return existsSync(path) ? (JSON.parse(readFileSync(path, "utf8")) as Release) : undefined;
};

/** Every picture the releases' highlights show (bun run media makes them) */
export const listReleasePictures = () =>
  existsSync(RELEASES)
    ? readdirSync(RELEASES)
        .filter((name) => name.endsWith(".json"))
        .flatMap((name) => readRelease(name.slice(0, -".json".length))?.highlights.map((item) => item.picture) ?? [])
    : [];

/** The site's address (site/site.json's url) */
export const readSiteUrl = () => {
  const path = join(RELEASES, "..", "site.json");
  return existsSync(path) ? ((JSON.parse(readFileSync(path, "utf8")) as { url?: string }).url ?? "") : "";
};

/** A version's notes with its highlights before them (when it has some and the site has an address) */
export const composeChangelogWithHighlights = (version: string, changelog: string) => {
  const release = readRelease(version);
  const siteUrl = readSiteUrl();
  return release && siteUrl ? `${composeHighlightsMarkdown(release, siteUrl)}\n---\n\n${changelog}` : changelog;
};

/** The highlights as Markdown, their pictures by the published site's address (siteUrl), for a release's notes */
export const composeHighlightsMarkdown = (release: Release, siteUrl: string) =>
  [
    release.summary,
    "",
    ...release.highlights.flatMap((item) => [
      `### ${item.title}`,
      "",
      item.text,
      "",
      `![${item.alt ?? item.title}](${new URL(`media/${item.picture}.webp`, siteUrl).href})`,
      "",
    ]),
  ].join("\n");
