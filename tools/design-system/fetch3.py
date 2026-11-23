import os, sys, subprocess, json
sys.path.insert(0, "/Users/vidler/AddonSim")
import assets
OUT = sys.argv[1]
store = assets.Assets("/Users/vidler/AddonSim/cache")
store.wait_ready(60)
def dims(path):
    w = int(subprocess.check_output(["sips", "-g", "pixelWidth", path]).decode().split()[-1])
    h = int(subprocess.check_output(["sips", "-g", "pixelHeight", path]).decode().split()[-1])
    return w, h
sizes = {}
for name in ["QuestDetailsBackgrounds", "questlog-reward-top-frame", "UI-Frame-InnerTopTile"]:
    info = store.atlas(name + "-c60") or store.atlas(name)
    if not info: print("NO", name); continue
    sheet = os.path.join(OUT, "_s.png"); open(sheet, "wb").write(store.png(info["fdid"]))
    w, h = dims(sheet)
    x, y = round(info["left"] * w), round(info["top"] * h)
    cw, ch = round((info["right"] - info["left"]) * w), round((info["bottom"] - info["top"]) * h)
    out = os.path.join(OUT, name.lower() + ".png")
    subprocess.check_call(["sips", "-c", str(ch), str(cw), "--cropOffset", str(y), str(x), sheet, "--out", out], stdout=subprocess.DEVNULL)
    os.remove(sheet); sizes[name] = [cw, ch, info["width"], info["height"]]
ICONS = ["INV_Misc_Coin_01", "XP_Icon", "INV_Scroll_03", "INV_Misc_PocketWatch_01", "Ability_Tracking", "INV_Misc_Ticket_Tarot_Madness",
         "INV_Misc_MonsterClaw_04", "INV_Feather_04", "INV_Misc_MonsterTail_03", "INV_Misc_Head_Centaur_01", "INV_Bracer_04", "INV_Misc_Pelt_Wolf_01",
         "INV_Misc_Note_01", "INV_Misc_Bone_01", "INV_Misc_Gem_Pearl_04", "Spell_Holy_SealOfSacrifice", "INV_Misc_Organ_03", "Achievement_Level_30",
         "INV_Misc_Bag_10", "Ability_Hunter_SniperShot", "INV_Misc_Rune_01", "Spell_Nature_Polymorph", "INV_Misc_Dice_01", "INV_Misc_Dice_02", "Ability_Rogue_Sprint"]
for icon in ICONS:
    data = store.png("interface/icons/" + icon.lower())
    if not data: print("NO ICON", icon); continue
    open(os.path.join(OUT, "icon-" + icon.lower() + ".png"), "wb").write(data)
print(sizes)
