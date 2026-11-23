// The WowAddons project for AddonSim: our addons, the installed ones their scenarios play with, and the simulator
// plugins and helpers that are ours (OneMoreQuest's party protocol, its mark audit). Paths are relative to this file.
import { defineProject } from "addonsim";

export default defineProject({
  // Our addons: discovered from here, before the game's AddOns folder (OneMoreQuest there is a junction to this one)
  addons: ["addons/OneMoreQuest", "addons/QuestieProfit"],
  // From the game's AddOns folder: the quest database OneMoreQuest is built on, and a neighbour it works with
  installed: ["QuestieDB", "ForeverDungeonJournal"],
  // What loads when a scenario names nothing (--@addons): not QuestieProfit, which pulls Questie in with it
  load: ["QuestieDB", "OneMoreQuest", "ForeverDungeonJournal"],
  scenarios: "sim/scenarios",
  plugins: ["sim/plugins/omq-party.lua"],
  luaPath: ["sim/lib"],
  coverage: "OneMoreQuest",
  gallery: "~/Desktop/OneMoreQuest-CurseForge/gallery",
});
