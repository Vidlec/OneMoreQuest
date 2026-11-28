// Compares two records of what was drawn (sim/scenarios/audits/visual-baseline.lua):
//
//     bun sim/scenarios/audits/visual-diff.ts before after [shown]
//
// Says, for each state, how many drawn items are in one and not the other, and shows the first few (shown: 3).

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

type Counter = Map<string, number>;

const ROOT = join(import.meta.dir, "..", ".visual");

const countLines = (path: string): Counter => {
  const counter: Counter = new Map();
  const text = readFileSync(path, "utf8");
  // (the lines as Python's splitlines gave them: no empty last one after a final newline)
  for (const line of text.split(/\r\n|\r|\n/).slice(0, text.endsWith("\n") ? -1 : undefined)) {
    counter.set(line, (counter.get(line) ?? 0) + 1);
  }
  return counter;
};

/** What a has more of than b, in a's order */
const subtract = (a: Counter, b: Counter): Counter => {
  const left: Counter = new Map();
  for (const [line, count] of a) {
    const rest = count - (b.get(line) ?? 0);
    if (rest > 0) {
      left.set(line, rest);
    }
  }
  return left;
};

const listElements = (counter: Counter) => [...counter].flatMap(([line, count]) => Array<string>(count).fill(line));

const sumCounts = (counter: Counter) => [...counter.values()].reduce((sum, count) => sum + count, 0);

const takeOne = (counter: Counter, line: string) => {
  const count = (counter.get(line) ?? 0) - 1;
  if (count > 0) {
    counter.set(line, count);
  } else {
    counter.delete(line);
  }
};

// Lines told by their two ends ("line x,y x,y ..."): the same line when each end is within a pixel (the two ways of
// drawing work the ends out by different sums, and the ends are rounded)
const readEnds = (text: string): { ends: number[]; rest: string } | undefined => {
  const parts = text.split(" ");
  if (parts.length < 3 || parts[0] !== "line") {
    return undefined;
  }
  const values = `${parts[1]},${parts[2]}`.split(",");
  const ends = values.map((value) => (value.trim() === "" ? Number.NaN : Number(value)));
  if (ends.some((value, index) => Number.isNaN(value) && values[index]?.trim().toLowerCase() !== "nan")) {
    return undefined;
  }
  return { ends, rest: parts.slice(3).join(" ") };
};

const isSameLine = (a: { ends: number[]; rest: string }, b: { ends: number[]; rest: string }) =>
  a.rest === b.rest &&
  a.ends.slice(0, b.ends.length).every((value, index) => Math.abs(value - (b.ends[index] ?? 0)) <= 1.01);

const compareState = (name: string, first: string, second: string, shown: number) => {
  const pathB = join(ROOT, second, name);
  if (!existsSync(pathB)) {
    console.log(`${name}: missing in ${second}`);
    return 1;
  }
  const a = countLines(join(ROOT, first, name));
  const b = countLines(pathB);
  const onlyA = subtract(a, b);
  const onlyB = subtract(b, a);
  for (const lineA of listElements(onlyA)) {
    const endsA = readEnds(lineA);
    if (!endsA) {
      continue;
    }
    for (const lineB of listElements(onlyB)) {
      const endsB = readEnds(lineB);
      if (endsB && isSameLine(endsA, endsB)) {
        takeOne(onlyA, lineA);
        takeOne(onlyB, lineB);
        break;
      }
    }
  }
  const count = sumCounts(onlyA) + sumCounts(onlyB);
  const verdict = count === 0 ? "same" : `${sumCounts(onlyA)} only in ${first}, ${sumCounts(onlyB)} only in ${second}`;
  console.log(`${name}: ${verdict} (${sumCounts(a)} items)`);
  for (const line of [...onlyA.keys()].slice(0, shown)) {
    console.log(`    - ${line.slice(0, 260)}`);
  }
  for (const line of [...onlyB.keys()].slice(0, shown)) {
    console.log(`    + ${line.slice(0, 260)}`);
  }
  return count;
};

const [first, second, shownText] = process.argv.slice(2);
if (!first || !second) {
  console.error("usage: bun sim/scenarios/audits/visual-diff.ts before after [shown]");
  process.exit(1);
}
const shown = shownText ? Number.parseInt(shownText, 10) : 3;
let total = 0;
for (const name of readdirSync(join(ROOT, first)).sort()) {
  total += compareState(name, first, second, shown);
}
console.log(total === 0 ? "IDENTICAL" : `${total} differences`);
