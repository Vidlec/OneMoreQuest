// Builds OneMoreQuest's release zip and its checksums.
//
//     bun tools/release/build-zip.ts [--out DIR]
//
// The zip holds one folder, OneMoreQuest, as the game's AddOns folder wants it: the TOC, every file the TOC loads,
// the Media folder, and the licence, readme and changelog. What goes in is read from the TOC, so a file added there
// ships without another list to keep. It fails, saying why, when the TOC names a file that is not there, or a Lua file
// in the addon is loaded by nothing (forgotten in the TOC).
//
// The zip is the same, byte for byte, for the same files (fixed dates, sorted names), so its checksum can be checked
// against the release's: SHA256SUMS.txt beside it (sha256sum -c SHA256SUMS.txt).
//
// Writes OneMoreQuest-<version>.zip and SHA256SUMS.txt into --out (default: dist/ in the repository). In GitHub
// Actions it also sets the step's outputs: version, zip, checksums, prerelease.

import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, relative, resolve, sep } from "node:path";
import { parseArgs } from "node:util";
import { ADDON_DIR, ADDON_NAME, isFile, REPO_ROOT, ReleaseError, readToc, runTool, setStepOutputs } from "./addon.ts";

// Shipped beside what the TOC loads (Media whole: its pictures are named by the code, some built at run time)
const EXTRA_FILES = [`${ADDON_NAME}.toc`, "LICENSE.md", "README.md", "CHANGELOG.md"];
const EXTRA_FOLDERS = ["Media"];
// Never shipped: the unit tests and their fake game
const NOT_SHIPPED = ["tests/"];

/** Every file under a folder, as paths relative to base with forward slashes */
const walkFiles = (folder: string, base: string): string[] => {
  const found: string[] = [];
  let entries: string[];
  try {
    entries = readdirSync(folder);
  } catch {
    return found;
  }
  for (const name of entries) {
    const path = join(folder, name);
    if (statSync(path).isDirectory()) {
      found.push(...walkFiles(path, base));
    } else {
      found.push(relative(base, path).split(sep).join("/"));
    }
  }
  return found;
};

export const listFiles = (addonDir: string) => {
  const toc = readToc(addonDir);
  const files = new Set([...toc.files, ...EXTRA_FILES]);
  for (const folder of EXTRA_FOLDERS) {
    for (const name of walkFiles(join(addonDir, folder), addonDir)) {
      files.add(name);
    }
  }
  const missing = [...files].filter((name) => !isFile(join(addonDir, name))).sort();
  if (missing.length) {
    throw new ReleaseError(`the TOC or the release names files that are not there: ${missing.join(", ")}`);
  }
  const loaded = new Set(toc.files);
  const unloaded = walkFiles(addonDir, addonDir).filter(
    (name) => name.endsWith(".lua") && !loaded.has(name) && !NOT_SHIPPED.some((prefix) => name.startsWith(prefix)),
  );
  if (unloaded.length) {
    throw new ReleaseError(
      `Lua files no TOC line loads (add them to the TOC or delete them): ${unloaded.sort().join(", ")}`,
    );
  }
  return [...files].sort();
};

// The zip's fixed date and time, 2020-01-01 00:00:00, as MS-DOS writes them
const DOS_TIME = 0;
const DOS_DATE = ((2020 - 1980) << 9) | (1 << 5) | 1;
// Made on Unix (its file modes in the external attributes), version 2.0; each file rw-r--r--
const MADE_BY = (3 << 8) | 20;
const NEEDED = 20;
const DEFLATE = 8;
const FILE_MODE = 0o644 << 16;
// Bit 11: the name is UTF-8 (set only when it is not plain ASCII, as Python's zipfile does)
const UTF8_FLAG = 0x800;

type Entry = { name: Buffer; flags: number; crc: number; data: Uint8Array; size: number; offset: number };

/** A zip of the files given (name in the zip, bytes), deflated at level 9, the same bytes each time */
export const composeZip = (files: { name: string; bytes: Uint8Array<ArrayBuffer> }[]) => {
  const parts: Uint8Array[] = [];
  const entries: Entry[] = [];
  let offset = 0;
  for (const file of files) {
    const name = Buffer.from(file.name, "utf8");
    const flags = /^[\x20-\x7e]*$/.test(file.name) ? 0 : UTF8_FLAG;
    const data = Bun.deflateSync(file.bytes, { level: 9 });
    const entry: Entry = { name, flags, crc: Bun.hash.crc32(file.bytes), data, size: file.bytes.length, offset };
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0);
    header.writeUInt16LE(NEEDED, 4);
    header.writeUInt16LE(flags, 6);
    header.writeUInt16LE(DEFLATE, 8);
    header.writeUInt16LE(DOS_TIME, 10);
    header.writeUInt16LE(DOS_DATE, 12);
    header.writeUInt32LE(entry.crc, 14);
    header.writeUInt32LE(data.length, 18);
    header.writeUInt32LE(entry.size, 22);
    header.writeUInt16LE(name.length, 26);
    header.writeUInt16LE(0, 28);
    parts.push(header, name, data);
    offset += header.length + name.length + data.length;
    entries.push(entry);
  }
  const directoryStart = offset;
  for (const entry of entries) {
    const header = Buffer.alloc(46);
    header.writeUInt32LE(0x02014b50, 0);
    header.writeUInt16LE(MADE_BY, 4);
    header.writeUInt16LE(NEEDED, 6);
    header.writeUInt16LE(entry.flags, 8);
    header.writeUInt16LE(DEFLATE, 10);
    header.writeUInt16LE(DOS_TIME, 12);
    header.writeUInt16LE(DOS_DATE, 14);
    header.writeUInt32LE(entry.crc, 16);
    header.writeUInt32LE(entry.data.length, 20);
    header.writeUInt32LE(entry.size, 24);
    header.writeUInt16LE(entry.name.length, 28);
    header.writeUInt32LE(FILE_MODE, 38);
    header.writeUInt32LE(entry.offset, 42);
    parts.push(header, entry.name);
    offset += header.length + entry.name.length;
  }
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(offset - directoryStart, 12);
  end.writeUInt32LE(directoryStart, 16);
  parts.push(end);
  return Buffer.concat(parts);
};

const sha256 = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex");

export const build = (addonDir: string, outDir: string) => {
  const toc = readToc(addonDir);
  mkdirSync(outDir, { recursive: true });
  const zipPath = join(outDir, `${ADDON_NAME}-${toc.version}.zip`);
  const zip = composeZip(
    listFiles(addonDir).map((name) => ({ name: `${ADDON_NAME}/${name}`, bytes: readFileSync(join(addonDir, name)) })),
  );
  writeFileSync(zipPath, zip);
  const checksumsPath = join(outDir, "SHA256SUMS.txt");
  writeFileSync(checksumsPath, `${sha256(zip)}  ${basename(zipPath)}\n`);
  return {
    version: toc.version,
    zip: zipPath,
    checksums: checksumsPath,
    prerelease: toc.isPrerelease ? "true" : "false",
  };
};

const expandHome = (path: string) => (path === "~" || path.startsWith("~/") ? join(homedir(), path.slice(1)) : path);

if (import.meta.main) {
  await runTool(async () => {
    const { values } = parseArgs({
      options: {
        out: { type: "string", default: join(REPO_ROOT, "dist") },
        addon: { type: "string", default: ADDON_DIR },
      },
    });
    const result = build(resolve(values.addon), resolve(expandHome(values.out)));
    console.log(`${result.zip} (${Math.floor(statSync(result.zip).size / 1024)} KB)`);
    console.log(readFileSync(result.checksums, "utf8").trim());
    await setStepOutputs(result);
  });
}
