// Builds OneMoreQuest's CraftedItems.lua: every item a profession makes, with the profession and the skill its recipe
// needs, from the game's own data tables for a build (wago.tools, as AddonSim downloads and caches them).
//
//   bun tools/make-crafted-items.ts [build] [addon folder]
//
// Defaults: the simulator's build, and addons/OneMoreQuest. The tables: SpellEffect (effect 24 creates an item), its
// spell's SkillLineAbility (which profession teaches it, from what skill), SkillLine (professions only). Read through
// AddonSim's SDK, which needs no game running for them.
import { statSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { createSim } from "addonsim";

const CREATE_ITEM = 24;
const PROFESSION_CATEGORIES = new Set([9, 11]); // secondary skills (cooking, first aid, fishing) and professions

const projectRoot = resolve(import.meta.dir, "..");
const sim = await createSim({ project: projectRoot });
const [buildArg, addonArg] = process.argv.slice(2);
const addon = resolve(addonArg ?? join(projectRoot, "addons", "OneMoreQuest"));
const number = (value: string | undefined): number => Number.parseInt(value ?? "", 10) || 0;

try {
  const build = buildArg ?? (await sim.build());
  const rows = (table: string) => sim.db2(table, { build });

  const professions = new Map<number, string>();
  for (const row of await rows("SkillLine")) {
    if (PROFESSION_CATEGORIES.has(number(row.CategoryID))) professions.set(number(row.ID), row.DisplayName_lang ?? "");
  }
  const recipes = new Map<number, [number, number]>(); // spell -> [skill line, rank]
  for (const row of await rows("SkillLineAbility")) {
    const skillLine = number(row.SkillLine);
    if (!professions.has(skillLine)) continue;
    const spell = number(row.Spell);
    // The game gives the skill a recipe needs for a few only; most read 1, which is not the real need: 0 (unknown)
    const minimum = number(row.MinSkillLineRank);
    const rank = minimum > 1 ? minimum : 0;
    // A spell taught by two lines (rare) keeps the lowest skill
    const known = recipes.get(spell);
    if (!known || rank < known[1]) recipes.set(spell, [skillLine, rank]);
  }
  const crafted = new Map<number, [number, number]>(); // item -> [skill line, rank]
  for (const row of await rows("SpellEffect")) {
    if (number(row.Effect) !== CREATE_ITEM) continue;
    const item = number(row.EffectItemType);
    const recipe = recipes.get(number(row.SpellID));
    if (!item || !recipe) continue;
    const known = crafted.get(item);
    if (!known || recipe[1] < known[1]) crafted.set(item, recipe);
  }

  const used = [...new Set([...crafted.values()].map(([skill]) => skill))].sort((a, b) => a - b);
  const lines = [
    "local _, ns = ...",
    "",
    "-- Items a profession makes: [item] = { profession's skill line, skill its recipe needs (0: not known) }. Generated from the",
    `-- game's own data (build ${build}) by tools/make-crafted-items.ts; do not edit by hand.`,
    `-- ${used.map((skill) => `${skill} ${professions.get(skill)}`).join(", ")}`,
    "ns.CraftedItems = {",
  ];
  for (const item of [...crafted.keys()].sort((a, b) => a - b)) {
    const [skillLine, rank] = crafted.get(item) ?? [0, 0];
    lines.push(`    [${item}] = { ${skillLine}, ${rank} },`);
  }
  lines.push("}");
  const target = join(addon, "CraftedItems.lua");
  writeFileSync(target, `${lines.join("\n")}\n`);
  const kilobytes = Math.floor(statSync(target).size / 1024);
  console.log(`${crafted.size} crafted items from ${used.length} professions -> ${target} (${kilobytes} KB)`);
} finally {
  await sim.close();
}
