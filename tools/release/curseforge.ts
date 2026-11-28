// Uploads the release zip to CurseForge through its upload API (https://support.curseforge.com, "CurseForge Upload
// API"): the file, its display name, its changelog (the version's highlights when it has some, then CHANGELOG.md's
// section, as Markdown, with a link to the version on the product page), the game versions it is for, its release type, and its relations (from .pkgmeta).
//
//     bun tools/release/curseforge.ts --zip dist/OneMoreQuest-0.16.0.zip [--dry-run]
//     bun tools/release/curseforge.ts --list-versions [filter]
//
// Settings come from the environment (GitHub: a secret and repository variables):
//
//     CURSEFORGE_API_TOKEN      the API token (https://authors.curseforge.com/#/settings/api-tokens); a secret
//     CURSEFORGE_PROJECT_ID     the project's number (its overview page shows it)
//     CURSEFORGE_GAME_VERSIONS  the game versions, comma separated: their ids (12345) or their names as CurseForge
//                               lists them ("1.15.7"); --list-versions shows them
//     CURSEFORGE_RELEASE_TYPE   release, beta or alpha (default: release; beta for a version like 1.2.3-beta1)
//
// --dry-run prints what would be sent and sends nothing (no token needed unless versions are given by name).

import { readFileSync, statSync } from "node:fs";
import { basename, join } from "node:path";
import { parseArgs } from "node:util";
import { getVersionAnchor } from "../site/markdown.ts";
import { composeChangelogWithHighlights } from "../site/releases.ts";
import {
  ADDON_NAME,
  isFile,
  REPO_ROOT,
  ReleaseError,
  readChangelog,
  readRelations,
  readToc,
  runTool,
  setStepOutputs,
} from "./addon.ts";

const API = process.env.CURSEFORGE_API_URL ?? "https://wow.curseforge.com/api";
const RELEASE_TYPES = ["release", "beta", "alpha"];
const USER_AGENT = `${ADDON_NAME}-release-script`;
const TRIES = 3;
const TIMEOUT_MS = 120_000;

const wait = (ms: number) => new Promise((done) => setTimeout(done, ms));

const request = async (method: string, path: string, token: string, body?: Uint8Array, contentType?: string) => {
  const headers: Record<string, string> = {
    "X-Api-Token": token,
    "User-Agent": USER_AGENT,
    Accept: "application/json",
  };
  if (contentType) {
    headers["Content-Type"] = contentType;
  }
  for (let attempt = 1; attempt <= TRIES; attempt++) {
    let response: Response;
    try {
      response = await fetch(`${API}${path}`, {
        method,
        headers,
        ...(body ? { body } : {}),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
    } catch (error) {
      if (attempt < TRIES) {
        await wait(5000 * attempt);
        continue;
      }
      throw new ReleaseError(`CurseForge ${method} ${path}: ${error instanceof Error ? error.message : String(error)}`);
    }
    if (response.ok) {
      const text = await response.text();
      return text ? (JSON.parse(text) as unknown) : null;
    }
    const detail = (await response.text()).slice(0, 2000);
    if (response.status >= 500 && attempt < TRIES) {
      console.error(`CurseForge answered ${response.status}; trying again (${attempt}/${TRIES})`);
      await wait(5000 * attempt);
      continue;
    }
    throw new ReleaseError(`CurseForge ${method} ${path}: HTTP ${response.status}: ${detail}`);
  }
  throw new ReleaseError(`CurseForge ${method} ${path}: no answer`);
};

type GameVersion = { id: number; name?: string; slug?: string; gameVersionTypeID?: number };

const listGameVersions = async (token: string) => {
  const versions = await request("GET", "/game/versions", token);
  if (!Array.isArray(versions)) {
    throw new ReleaseError(`CurseForge's game versions are not a list: ${JSON.stringify(versions).slice(0, 300)}`);
  }
  return versions as GameVersion[];
};

const resolveGameVersions = async (wanted: string, token: string) => {
  const names = wanted
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);
  if (!names.length) {
    throw new ReleaseError(
      "CURSEFORGE_GAME_VERSIONS is not set: name the game versions this file is for" +
        " (bun tools/release/curseforge.ts --list-versions shows CurseForge's)",
    );
  }
  const isId = (name: string) => /^\d+$/.test(name);
  if (names.every(isId)) {
    return names.map(Number);
  }
  if (!token) {
    throw new ReleaseError("game versions given by name need CURSEFORGE_API_TOKEN to be looked up");
  }
  const known = await listGameVersions(token);
  return names.map((name) => {
    if (isId(name)) {
      return Number(name);
    }
    const matches = known.filter((entry) => entry.name === name || entry.slug === name);
    const [match] = matches;
    if (!match) {
      const major = name.split(".")[0] ?? name;
      const close = [
        ...new Set(known.map((entry) => entry.name ?? "").filter((known) => known.includes(major))),
      ].sort();
      throw new ReleaseError(
        `CurseForge has no game version named '${name}'; close ones: ${close.slice(0, 20).join(", ")}`,
      );
    }
    if (matches.length > 1) {
      const listed = matches.map((entry) => `${entry.id} (type ${entry.gameVersionTypeID})`).join(", ");
      throw new ReleaseError(`several game versions are named '${name}': ${listed}; give the id instead`);
    }
    return Number(match.id);
  });
};

/** The changelog's closing line: the version on the product page (its screenshots, every version's notes); empty
 * without a site */
export const composeSiteLink = (version: string) => {
  const settings = join(REPO_ROOT, "site", "site.json");
  if (!isFile(settings)) {
    return "";
  }
  const url = (JSON.parse(readFileSync(settings, "utf8")) as { url?: string }).url ?? "";
  if (!url) {
    return "";
  }
  return `[Screenshots and every version's notes](${url.replace(/\/+$/, "")}/changelog.html#${getVersionAnchor(version)})`;
};

export const composeMetadata = (version: string, changelog: string, gameVersions: number[], releaseType: string) => {
  const link = composeSiteLink(version);
  const metadata: Record<string, unknown> = {
    changelog: link
      ? `${composeChangelogWithHighlights(version, changelog).trimEnd()}\n\n${link}\n`
      : composeChangelogWithHighlights(version, changelog),
    changelogType: "markdown",
    displayName: `${ADDON_NAME} ${version}`,
    gameVersions,
    releaseType,
  };
  const relations = readRelations();
  if (relations.length) {
    metadata.relations = { projects: relations };
  }
  return metadata;
};

const encodeMultipart = (metadata: Record<string, unknown>, zipPath: string) => {
  const boundary = crypto.randomUUID().replaceAll("-", "");
  const parts = [
    Buffer.from(`--${boundary}\r\n`),
    Buffer.from('Content-Disposition: form-data; name="metadata"\r\n'),
    Buffer.from("Content-Type: application/json\r\n\r\n"),
    Buffer.from(JSON.stringify(metadata), "utf8"),
    Buffer.from(`\r\n--${boundary}\r\n`),
    Buffer.from(`Content-Disposition: form-data; name="file"; filename="${basename(zipPath)}"\r\n`),
    Buffer.from("Content-Type: application/zip\r\n\r\n"),
    readFileSync(zipPath),
    Buffer.from(`\r\n--${boundary}--\r\n`),
  ];
  return { body: Buffer.concat(parts), contentType: `multipart/form-data; boundary=${boundary}` };
};

const printGameVersions = async (token: string, filter: string) => {
  if (!token) {
    throw new ReleaseError("CURSEFORGE_API_TOKEN is needed to list the game versions");
  }
  for (const entry of await listGameVersions(token)) {
    const line = `${String(entry.id).padStart(8)}  type ${String(entry.gameVersionTypeID).padStart(6)}  ${entry.name}`;
    if (line.toLowerCase().includes(filter.toLowerCase())) {
      console.log(line);
    }
  }
};

const upload = async (zipPath: string | undefined, isDryRun: boolean, token: string) => {
  if (!zipPath || !isFile(zipPath)) {
    throw new ReleaseError(`no zip to upload: '${zipPath ?? ""}' (build it first: bun tools/release/build-zip.ts)`);
  }
  const toc = readToc();
  const changelog = readChangelog(toc.version);
  const releaseType =
    (process.env.CURSEFORGE_RELEASE_TYPE ?? "").trim().toLowerCase() || (toc.isPrerelease ? "beta" : "release");
  if (!RELEASE_TYPES.includes(releaseType)) {
    throw new ReleaseError(`CURSEFORGE_RELEASE_TYPE is '${releaseType}': one of ${RELEASE_TYPES.join(", ")}`);
  }
  const project = (process.env.CURSEFORGE_PROJECT_ID ?? "").trim();
  const wanted = process.env.CURSEFORGE_GAME_VERSIONS ?? "";
  if (isDryRun) {
    const gameVersions = wanted.trim() ? await resolveGameVersions(wanted, token) : [];
    const metadata = composeMetadata(toc.version, changelog, gameVersions, releaseType);
    console.log(`POST ${API}/projects/${project || "<CURSEFORGE_PROJECT_ID>"}/upload-file`);
    console.log(`file: ${zipPath} (${Math.floor(statSync(zipPath).size / 1024)} KB)`);
    console.log(JSON.stringify(metadata, null, 2));
    return;
  }
  if (!token) {
    throw new ReleaseError("CURSEFORGE_API_TOKEN is not set");
  }
  if (!/^\d+$/.test(project)) {
    throw new ReleaseError(`CURSEFORGE_PROJECT_ID is '${project}': the project's number`);
  }
  const gameVersions = await resolveGameVersions(wanted, token);
  const metadata = composeMetadata(toc.version, changelog, gameVersions, releaseType);
  const { body, contentType } = encodeMultipart(metadata, zipPath);
  const answer = await request("POST", `/projects/${project}/upload-file`, token, body, contentType);
  const fileId = answer && typeof answer === "object" ? (answer as { id?: unknown }).id : undefined;
  if (!fileId) {
    throw new ReleaseError(`CurseForge took the upload but gave no file id: ${JSON.stringify(answer).slice(0, 300)}`);
  }
  console.log(`uploaded ${basename(zipPath)} to CurseForge: file ${fileId} (${releaseType})`);
  await setStepOutputs({ file_id: String(fileId) });
};

if (import.meta.main) {
  await runTool(async () => {
    const { values, positionals } = parseArgs({
      options: {
        zip: { type: "string" },
        "dry-run": { type: "boolean", default: false },
        "list-versions": { type: "boolean", default: false },
      },
      allowPositionals: true,
    });
    const token = (process.env.CURSEFORGE_API_TOKEN ?? "").trim();
    if (values["list-versions"]) {
      await printGameVersions(token, positionals[0] ?? "");
      return;
    }
    await upload(values.zip, values["dry-run"], token);
  });
}
