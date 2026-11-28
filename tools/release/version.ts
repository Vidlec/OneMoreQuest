// Sets the addon's version. package.json's "version" is the one written by hand; the TOC's "## Version:" and the
// version in its "## Title:" (the game reads the TOC itself, so it must say it too) are written from it here, and
// CHANGELOG.md gets the version's section heading to write its notes under.
//
//     bun run release:version 0.17.0        that version
//     bun run release:version patch         0.16.1 -> 0.16.2 (minor: 0.17.0, major: 1.0.0)
//     bun run release:version               the TOC set to package.json's version, as it is
//
// The release tools fail on a TOC whose version is not package.json's (addon.ts, readToc), so CI catches a TOC
// raised by hand.

import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import {
  ADDON_DIR,
  ADDON_NAME,
  REPO_ROOT,
  ReleaseError,
  readPackageVersion,
  runTool,
  VERSION_PATTERN,
} from "./addon.ts";

const STEPS = ["major", "minor", "patch"] as const;

/** The version a step up from this one gives (a pre-release's suffix dropped), or the version given as it is */
export const composeNextVersion = (current: string, wanted: string) => {
  const step = STEPS.indexOf(wanted as (typeof STEPS)[number]);
  if (step === -1) {
    if (!VERSION_PATTERN.test(wanted)) {
      throw new ReleaseError(`'${wanted}' is not a version like 1.2.3 (or major, minor, patch)`);
    }
    return wanted;
  }
  const parts = (current.split("-")[0] ?? "").split(".").map(Number);
  const raised = parts.map((part, index) => (index < step ? part : index === step ? part + 1 : 0));
  return raised.join(".");
};

/** Writes the version into package.json's "version" line, the rest of the file left as it is */
const writePackageVersion = (version: string) => {
  const path = join(REPO_ROOT, "package.json");
  const text = readFileSync(path, "utf8");
  const line = /^(\s*"version":\s*")[^"]*(")/m;
  if (!line.test(text)) {
    throw new ReleaseError(`${path} has no "version" line`);
  }
  writeFileSync(path, text.replace(line, `$1${version}$2`));
};

/** Writes the version into the TOC's "## Version:" line and its title's "v<version>|r" */
const writeTocVersion = (version: string) => {
  const path = join(ADDON_DIR, `${ADDON_NAME}.toc`);
  const text = readFileSync(path, "utf8");
  const versionLine = /^## Version:.*$/m;
  const titleVersion = /^(## Title:.*\bv)[0-9A-Za-z.-]+(\|r)/m;
  if (!versionLine.test(text) || !titleVersion.test(text)) {
    throw new ReleaseError(`${path}: no '## Version:' line, or no 'v<version>|r' in its '## Title:'`);
  }
  writeFileSync(path, text.replace(versionLine, `## Version: ${version}`).replace(titleVersion, `$1${version}$2`));
};

/** Adds "## <version>" above the newest section of CHANGELOG.md when the version has none; true when it did */
const addChangelogHeading = (version: string) => {
  const path = join(ADDON_DIR, "CHANGELOG.md");
  const text = readFileSync(path, "utf8");
  if (text.split(/\r?\n/).some((line) => line.trim() === `## ${version}`)) {
    return false;
  }
  const newest = /^## /m.exec(text);
  const at = newest ? newest.index : text.length;
  writeFileSync(path, `${text.slice(0, at)}## ${version}\n\n${text.slice(at)}`);
  return true;
};

if (import.meta.main) {
  await runTool(() => {
    const current = readPackageVersion();
    const wanted = process.argv[2];
    const version = wanted ? composeNextVersion(current, wanted) : current;
    writePackageVersion(version);
    writeTocVersion(version);
    const isHeadingAdded = addChangelogHeading(version);
    console.log(`${ADDON_NAME} ${version} (was ${current}): package.json and ${ADDON_NAME}.toc`);
    if (isHeadingAdded) {
      console.log(`CHANGELOG.md has a '## ${version}' section now: write what changed under it`);
    }
  });
}
