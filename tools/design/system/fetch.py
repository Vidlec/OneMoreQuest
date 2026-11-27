import os, sys, subprocess
sys.path.insert(0, "/Users/vidler/AddonSim")
import assets
OUT = sys.argv[1]
store = assets.Assets("/Users/vidler/AddonSim/cache")
store.wait_ready(60)
TEXTURES = {
    "Frames": ["dialogframe/ui-dialogbox-border", "dialogframe/ui-dialogbox-background", "dialogframe/ui-dialogbox-header", "dialogframe/ui-dialogbox-gold-border",
               "tooltips/ui-tooltip-border", "tooltips/ui-tooltip-background", "questframe/questbg", "chatframe/chatframebackground"],
    "Buttons": ["buttons/ui-panel-button-up", "buttons/ui-panel-button-down", "buttons/ui-panel-button-highlight", "buttons/ui-panel-button-disabled",
                "buttons/ui-checkbox-up", "buttons/ui-checkbox-check", "buttons/ui-panel-minimizebutton-up", "buttons/ui-scrollbar-scrollupbutton-up",
                "buttons/ui-scrollbar-knob", "buttons/ui-sliderbar-button-horizontal", "paperdollinfoframe/ui-character-activetab",
                "paperdollinfoframe/ui-character-inactivetab", "common/common-input-border"],
    "Items": ["buttons/ui-quickslot2", "buttons/ui-emptyslot-white", "questframe/ui-questitemnameframe", "questframe/ui-questitemhighlight",
              "paperdoll/ui-paperdoll-slot-chest"],
    "Bars": ["targetingframe/ui-statusbar"],
    "Money": ["moneyframe/ui-goldicon", "moneyframe/ui-silvericon", "moneyframe/ui-coppericon"],
    "Icons": ["icons/inv_misc_coin_01", "icons/xp_icon", "icons/inv_scroll_03", "icons/ability_tracking", "icons/inv_misc_pocketwatch_01", "icons/inv_misc_ticket_tarot_madness"],
}
ATLASES = ["questnormal", "questturnin", "trivialquests", "questdaily", "dungeon", "raid"]
report = []
for group, paths in TEXTURES.items():
    os.makedirs(os.path.join(OUT, group), exist_ok=True)
    for path in paths:
        data = store.png("interface/" + path)
        name = path.split("/")[-1] + ".png"
        if data:
            open(os.path.join(OUT, group, name), "wb").write(data)
            report.append((group, name, len(data)))
        else:
            report.append((group, name, "MISSING"))
os.makedirs(os.path.join(OUT, "Map marks"), exist_ok=True)
for name in ATLASES:
    info = store.atlas(name)
    if not info:
        report.append(("Map marks", name, "NO ATLAS")); continue
    sheet = store.png(info["fdid"])
    sheet_path = os.path.join(OUT, "raw-" + name + ".png")
    open(sheet_path, "wb").write(sheet)
    w = int(subprocess.check_output(["sips", "-g", "pixelWidth", sheet_path]).decode().split()[-1])
    h = int(subprocess.check_output(["sips", "-g", "pixelHeight", sheet_path]).decode().split()[-1])
    x, y = round(info["left"] * w), round(info["top"] * h)
    cw, ch = round((info["right"] - info["left"]) * w), round((info["bottom"] - info["top"]) * h)
    out = os.path.join(OUT, "Map marks", name + ".png")
    subprocess.check_call(["sips", "-c", str(ch), str(cw), "--cropOffset", str(y), str(x), sheet_path, "--out", out], stdout=subprocess.DEVNULL)
    os.remove(sheet_path)
    report.append(("Map marks", name + ".png", f"{cw}x{ch}"))
for r in report:
    print(*r)
