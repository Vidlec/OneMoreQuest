// The product page's screenshots: bun run media [id ...]. Plays each feature's scenario of site/site.json
// and of every release's highlights (site/releases) (sim/scenarios/media/<id>.lua, which saves the scene "<id>" with
// only the windows it shows) in the simulator's warm
// game, then draws that scene headless into site/media/<id>.webp: those windows alone, cut to them, on a transparent
// background. Commit the pictures with the change they show: the release publishes them with the site.
//
// Needs what the simulator's scenarios need (the game's files, the interface source, QuestieDB in its AddOns folder)
// and Chrome or Edge for the drawing (AddonSim's shot): run on a developer's machine, not in CI.

import { existsSync, readdirSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { connect } from "addonsim";
import { listReleasePictures } from "./releases.ts";

const ROOT = join(import.meta.dir, "..", "..");
const SCENARIOS = join(ROOT, "sim", "scenarios", "media");
const MEDIA = join(ROOT, "site", "media");

// (scale: the device pixels a screen point is drawn at, for a small window drawn larger; else site.json's pictureScale)
type Feature = { id: string; title: string; scale?: number };
type Simulator = Awaited<ReturnType<typeof connect>>;

const captureFeature = async (sim: Simulator, feature: Feature, scale: number) => {
  const scenario = `sim/scenarios/media/${feature.id}.lua`;
  const run = await sim.run(scenario);
  if (!run.passed) {
    const failures = run.failures.map((failure) => `  ${failure.file}:${failure.line}: ${failure.message}`);
    return `${scenario} failed:\n${failures.join("\n")}`;
  }
  const out = join(MEDIA, `${feature.id}.webp`);
  try {
    await sim.shot({ scene: `${feature.id}/${feature.id}`, out, scale });
  } catch (error) {
    return `the picture of ${scenario} was not drawn: ${error instanceof Error ? error.message : String(error)}`;
  }
  console.log(`site/media/${feature.id}.webp  ${feature.title}`);
  return undefined;
};

const main = async () => {
  const settings: { pictureScale: number; features: Feature[] } = JSON.parse(
    await readFile(join(ROOT, "site", "site.json"), "utf8"),
  );
  // The pictures to make: the features' and the releases' highlights' (site/releases), each once
  const pictures: Feature[] = [...settings.features];
  for (const id of listReleasePictures()) {
    if (!pictures.some((picture) => picture.id === id)) {
      pictures.push({ id, title: `a release's highlight` });
    }
  }
  const pictureIds = new Set(pictures.map((picture) => picture.id));
  const scenarioIds = readdirSync(SCENARIOS)
    .filter((name) => name.endsWith(".lua"))
    .map((name) => name.slice(0, -".lua".length));
  const problems: string[] = [];
  for (const picture of pictures) {
    if (!existsSync(join(SCENARIOS, `${picture.id}.lua`))) {
      problems.push(`the picture "${picture.id}" has no scenario: sim/scenarios/media/${picture.id}.lua`);
    }
  }
  for (const id of scenarioIds) {
    if (!pictureIds.has(id)) {
      problems.push(`sim/scenarios/media/${id}.lua is no picture of site/site.json's features or site/releases`);
    }
  }
  const wanted = process.argv.slice(2);
  for (const id of wanted) {
    if (!pictureIds.has(id)) {
      problems.push(`no picture "${id}" (${[...pictureIds].join(", ")})`);
    }
  }
  if (problems.length) {
    console.error(problems.join("\n"));
    process.exit(1);
  }
  const chosen = pictures.filter((picture) => wanted.length === 0 || wanted.includes(picture.id));
  const sim = await connect();
  try {
    for (const feature of chosen) {
      const problem = await captureFeature(sim, feature, feature.scale ?? settings.pictureScale);
      if (problem) {
        problems.push(problem);
      }
    }
  } finally {
    await sim.close();
  }
  if (problems.length) {
    console.error(`\n${problems.join("\n\n")}`);
    process.exit(1);
  }
  console.log(`${chosen.length} pictures in site/media: look at them, then commit them`);
};

await main();
