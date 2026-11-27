import os, sys, subprocess, json
sys.path.insert(0, "/Users/vidler/AddonSim")
import assets
OUT = sys.argv[1]
store = assets.Assets("/Users/vidler/AddonSim/cache")
store.wait_ready(60)
GROUPS = {
 "Window": ["UI-Frame-PortraitMetal-CornerTopLeft", "UI-Frame-Metal-CornerTopRight", "UI-Frame-Metal-CornerBottomLeft", "UI-Frame-Metal-CornerBottomRight",
            "_UI-Frame-Metal-EdgeTop", "_UI-Frame-Metal-EdgeBottom", "!UI-Frame-Metal-EdgeLeft", "!UI-Frame-Metal-EdgeRight", "_UI-Frame-TopTileStreaks", "RedButton-Exit"],
 "Inset": ["UI-Frame-InnerTopLeft", "UI-Frame-InnerTopRight", "UI-Frame-InnerBotLeftCorner", "UI-Frame-InnerBotRight", "_UI-Frame-InnerTopTile",
           "_UI-Frame-InnerBotTile", "!UI-Frame-InnerLeftTile", "!UI-Frame-InnerRightTile"],
 "Tooltip": ["Tooltip-NineSlice-CornerTopLeft", "Tooltip-NineSlice-CornerTopRight", "Tooltip-NineSlice-CornerBottomLeft", "Tooltip-NineSlice-CornerBottomRight",
             "_Tooltip-NineSlice-EdgeTop", "_Tooltip-NineSlice-EdgeBottom", "!Tooltip-NineSlice-EdgeLeft", "!Tooltip-NineSlice-EdgeRight", "Tooltip-NineSlice-Center"],
 "Lists": ["UI-Character-Info-Title", "UI-Character-Info-ScrollLine-Long", "UI-Character-Info-ScrollLine", "UI-Character-Info-GearSlot", "spellbook-skilllinetab", "common-button-list-minus", "common-button-list-plus",
           "campaign_headericon_open", "campaign_headericon_closed", "checkbox-minimal", "checkmark-minimal", "common-dropdown-a-button",
           "common-search-border-left", "common-search-border-middle", "common-search-border-right", "common-search-magnifyingglass"],
 "Bars": ["common-stat-bar-BG", "common-stat-bar-blue", "common-stat-bar-white"],
 "Buttons": ["128-RedButton-Left", "_128-RedButton-Center", "128-RedButton-Right", "128-RedButton-Left-Pressed", "_128-RedButton-Center-Pressed", "128-RedButton-Right-Pressed",
             "128-RedButton-Left-Disabled", "_128-RedButton-Center-Disabled", "128-RedButton-Right-Disabled", "128-RedButton-Highlight"],
 "Professions": ["Professions-Slot-Frame", "heavybronze-frame-basic"],
 "Spellbook": ["spellbook-Page-Left", "spellbook-Page-Right", "spellbook-divider", "spellbook-item-backplate"],
}
FILES = {"Window": ["frameGeneral/ui-background-rock", "frameGeneral/ui-background-marble"]}
sizes = {}
def dims(path):
    w = int(subprocess.check_output(["sips", "-g", "pixelWidth", path]).decode().split()[-1])
    h = int(subprocess.check_output(["sips", "-g", "pixelHeight", path]).decode().split()[-1])
    return w, h
for group, names in GROUPS.items():
    os.makedirs(os.path.join(OUT, group), exist_ok=True)
    for name in names:
        # Forever's own variant ("-c60", Classic 60) where it has one
        info, used = store.atlas(name + "-c60"), name + "-c60"
        if not info:
            info, used = store.atlas(name), name
        if not info:
            print("NO ATLAS", name); continue
        sheet = store.png(info["fdid"])
        if not sheet:
            print("NO SHEET", name); continue
        sheet_path = os.path.join(OUT, "_sheet.png"); open(sheet_path, "wb").write(sheet)
        w, h = dims(sheet_path)
        x, y = round(info["left"] * w), round(info["top"] * h)
        cw, ch = max(1, round((info["right"] - info["left"]) * w)), max(1, round((info["bottom"] - info["top"]) * h))
        file = name.strip("_!").lower() + ".png"
        out = os.path.join(OUT, group, file)
        subprocess.check_call(["sips", "-c", str(ch), str(cw), "--cropOffset", str(y), str(x), sheet_path, "--out", out], stdout=subprocess.DEVNULL)
        sizes[f"{group}/{file}"] = {"atlas": used, "pixels": [cw, ch], "drawn": [info["width"], info["height"]], "tilesH": info.get("tilesH"), "tilesV": info.get("tilesV")}
        os.remove(sheet_path)
for group, paths in FILES.items():
    for path in paths:
        data = store.png("interface/" + path)
        if not data:
            print("NO FILE", path); continue
        file = path.split("/")[-1] + ".png"
        out = os.path.join(OUT, group, file); open(out, "wb").write(data)
        sizes[f"{group}/{file}"] = {"file": "Interface\\" + path.replace("/", "\\"), "pixels": list(dims(out))}
json.dump(sizes, open(os.path.join(OUT, "sizes.json"), "w"), indent=1)
for k, v in sizes.items():
    print(k, v.get("pixels"), v.get("drawn"))
