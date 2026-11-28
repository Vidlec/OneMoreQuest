// Writes the release notes for the version in the TOC: its highlights when it has some (site/releases/<version>.json,
// their pictures the product page's), its section of CHANGELOG.md, how to install, and the zip's SHA-256 checksum with
// how to check it.
//
//     bun tools/release/notes.ts [--checksums dist/SHA256SUMS.txt] [--out dist/release-notes.md] [--changelog-only]
//
// The GitHub release appends the merged pull requests to these (gh release create --generate-notes).

import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { composeChangelogWithHighlights } from "../site/releases.ts";
import { ADDON_NAME, isFile, REPO_ROOT, readChangelog, readToc, runTool } from "./addon.ts";

export const composeNotes = (version: string, changelog: string, checksums: string) => {
  const zipName = `${ADDON_NAME}-${version}.zip`;
  const lines = [
    changelog.trimEnd(),
    "",
    "## Install",
    "",
    `Download \`${zipName}\` below and unpack it into the game's \`Interface/AddOns\` folder, so that` +
      ` \`Interface/AddOns/${ADDON_NAME}/${ADDON_NAME}.toc\` exists. OneMoreQuest needs QuestieDB.`,
    "",
  ];
  if (checksums.trim()) {
    lines.push(
      "## Checksum",
      "",
      "SHA-256 of the zip (also in `SHA256SUMS.txt`):",
      "",
      "```",
      checksums.trim(),
      "```",
      "",
      "To check it, in the folder you downloaded both files to:",
      "",
      "- Linux and macOS: `sha256sum -c SHA256SUMS.txt` (macOS: `shasum -a 256 -c SHA256SUMS.txt`)",
      `- Windows (PowerShell): \`(Get-FileHash ${zipName} -Algorithm SHA256).Hash\` and compare it with the line above`,
      "",
    );
  }
  return lines.join("\n");
};

if (import.meta.main) {
  await runTool(() => {
    const { values } = parseArgs({
      options: {
        checksums: { type: "string", default: join(REPO_ROOT, "dist", "SHA256SUMS.txt") },
        out: { type: "string", default: join(REPO_ROOT, "dist", "release-notes.md") },
        "changelog-only": { type: "boolean", default: false },
      },
    });
    const toc = readToc();
    const changelog = readChangelog(toc.version);
    const checksums = isFile(values.checksums) ? readFileSync(values.checksums, "utf8") : "";
    const notes = composeChangelogWithHighlights(toc.version, changelog);
    const text = values["changelog-only"] ? changelog : composeNotes(toc.version, notes, checksums);
    mkdirSync(dirname(resolve(values.out)), { recursive: true });
    writeFileSync(values.out, text);
    console.log(values.out);
  });
}
