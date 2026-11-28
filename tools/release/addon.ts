// What the release tools know about the addon, read from its own files (nothing kept by hand twice):
//
// - the TOC: its version, its title, and the files the game loads, in order;
// - CHANGELOG.md: the notes of each version (a "## <version>" heading, up to the next one);
// - .pkgmeta: the addon's relations on CurseForge (required-dependencies, optional-dependencies, tools-used...).
//
// Used by build-zip.ts, notes.ts and curseforge.ts.

import { existsSync, readFileSync, statSync } from "node:fs";
import { join, normalize } from "node:path";

export const REPO_ROOT = normalize(join(import.meta.dir, "..", ".."));
export const ADDON_NAME = "OneMoreQuest";
export const ADDON_DIR = join(REPO_ROOT, "addons", ADDON_NAME);

// A version as the TOC writes it: 1.2.3, or 1.2.3-beta1 for a pre-release
const VERSION_PATTERN = /^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$/;

/** Something in the addon's files a release cannot go out with: said in a sentence, for the CI log */
export class ReleaseError extends Error {}

export type Toc = {
  version: string;
  title: string;
  interface: string;
  /** As the game loads them, with forward slashes */
  files: string[];
  isPrerelease: boolean;
};

export const isFile = (path: string) => existsSync(path) && statSync(path).isFile();

export const readToc = (addonDir: string = ADDON_DIR): Toc => {
  const path = join(addonDir, `${ADDON_NAME}.toc`);
  if (!isFile(path)) {
    throw new ReleaseError(`${path} is not there: no addon to release`);
  }
  const lines = readFileSync(path, "utf8")
    .replace(/^﻿/, "")
    .split(/\r?\n/)
    .map((line) => line.trim());
  const tags = new Map<string, string>();
  const files: string[] = [];
  for (const line of lines) {
    if (line.startsWith("##")) {
      const body = line.slice(2);
      const colon = body.indexOf(":");
      const key = colon === -1 ? body : body.slice(0, colon);
      tags.set(key.trim(), colon === -1 ? "" : body.slice(colon + 1).trim());
    } else if (line && !line.startsWith("#")) {
      files.push(line.replaceAll("\\", "/"));
    }
  }
  const version = tags.get("Version") ?? "";
  if (!VERSION_PATTERN.test(version)) {
    throw new ReleaseError(`${path}: '## Version: ${version}' is not a version like 1.2.3`);
  }
  const title = tags.get("Title") ?? "";
  // The title shows the version in the game's AddOns list ("OneMoreQuest v0.16.0"): raised with the Version line
  if (!title.includes(`v${version}|r`)) {
    throw new ReleaseError(`${path}: the Title (${title}) does not show the version ${version}: raise both together`);
  }
  return { version, title, interface: tags.get("Interface") ?? "", files, isPrerelease: version.includes("-") };
};

const escapeRegExp = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** The notes under "## <version>" in CHANGELOG.md, without the heading */
export const readChangelog = (version: string, addonDir: string = ADDON_DIR) => {
  const path = join(addonDir, "CHANGELOG.md");
  const text = readFileSync(path, "utf8").replaceAll("\r\n", "\n");
  const heading = new RegExp(`^## ${escapeRegExp(version)}[ \\t]*\\n`, "m").exec(text);
  const rest = heading ? text.slice(heading.index + heading[0].length) : "";
  const next = /^## /m.exec(rest);
  const notes = (next ? rest.slice(0, next.index) : rest).trim();
  if (!heading || !notes) {
    throw new ReleaseError(`${path}: no notes under '## ${version}': write what changed before releasing it`);
  }
  return `${notes}\n`;
};

// .pkgmeta's lists (the BigWigs packager's names) and what CurseForge's upload API calls each relation
const PKGMETA_RELATIONS = new Map([
  ["required-dependencies", "requiredDependency"],
  ["optional-dependencies", "optionalDependency"],
  ["tools-used", "tool"],
  ["embedded-libraries", "embeddedLibrary"],
  ["incompatible", "incompatible"],
]);

export type Relation = { slug: string; type: string };

/** The addon's CurseForge relations from .pkgmeta. Only its simple lists are read ("key:" then "  - slug" lines),
 * which is all the file holds. */
export const readRelations = (addonDir: string = ADDON_DIR): Relation[] => {
  const path = join(addonDir, ".pkgmeta");
  const relations: Relation[] = [];
  if (!isFile(path)) {
    return relations;
  }
  let current: string | undefined;
  for (const raw of readFileSync(path, "utf8").split(/\r?\n/)) {
    const line = (raw.split("#", 1)[0] ?? "").trimEnd();
    if (!line) {
      continue;
    }
    if (!/^[ \t-]/.test(line)) {
      current = PKGMETA_RELATIONS.get(line.replace(/:+$/, "").trim());
      continue;
    }
    const item = line.trim();
    if (current && item.startsWith("- ")) {
      relations.push({ slug: item.slice(2).trim(), type: current });
    }
  }
  return relations;
};

/** Runs a tool's main: a ReleaseError is said in a line and exits 1 (anything else is a bug: its stack) */
export const runTool = async (main: () => Promise<void> | void) => {
  try {
    await main();
  } catch (error) {
    if (error instanceof ReleaseError) {
      console.error(`error: ${error.message}`);
      process.exit(1);
    }
    throw error;
  }
};

/** In GitHub Actions, the step's outputs (key=value lines into $GITHUB_OUTPUT) */
export const setStepOutputs = async (outputs: Record<string, string>) => {
  const path = process.env.GITHUB_OUTPUT;
  if (!path) {
    return;
  }
  const lines = Object.entries(outputs).map(([key, value]) => `${key}=${value}\n`);
  const { appendFileSync } = await import("node:fs");
  appendFileSync(path, lines.join(""));
};
