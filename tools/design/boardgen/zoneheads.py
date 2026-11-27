"""A Design-board artboard: six designs for the quest list's zone headings, every state a heading has."""
import os, sys
OUT, ART = sys.argv[1], sys.argv[2]
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "partyicon.py")).read()
exec(src.split("ROWS_PLAIN = ")[0].replace("OUT, ART = sys.argv[1], sys.argv[2]", ""))
exec("def col(" + src.split("def col(")[1].split("cols = (")[0])
PLATE, BAND = image("plate", "ui-character-info-title.png"), image("band", "questlog-reward-top-frame.png")
OPEN, SHUT = image("open", "campaign_headericon_open.png"), image("shut", "campaign_headericon_closed.png")
PLUS = image("plus", "common-button-list-plus.png")
TURNIN, DUNGEON, ARROW = image("turnin", "questturnin.png"), image("dungeon", "dungeon.png"), image("arrow", "minimaparrow.png")
FOOD, MAPICON = image("food", "inv_misc_food_15.png"), image("mapicon", "inv_misc_map_01.png")
LILAC = "#c9a8f0"

def img(src, w, h=None, extra=""):
    return f'<span style="display:inline-block;width:{w}px;height:{h or w}px;flex:none;background:{src} center/contain no-repeat;{extra}"></span>'
def share():
    return f'<span style="display:inline-flex">{party(15)}</span>'

GROUPS = [
    {"name": "The Barrens", "kind": "zone", "count": 4, "ready": 2, "open": True, "current": True, "onMap": True, "tracked": True, "levels": "10-25",
     "rows": [("[13] Raptor Thieves", "✓ Gazrog", dashed(), "1/2", 5, True, GREEN, False),
              ("[15] The Disruption Ends", "1 of 3 done", coin(KILL), "2/2", 5, True, WHITE, False),
              ("[18] Raptor Horns", "✓ Mebok Mizzyrix", dashed(), "1/2", 5, False, GREEN, False),
              ("[20] The Guns of Northwatch", "1 of 4 done", coin(KILL), "", 5, False, WHITE, True)]},
    {"name": "Wailing Caverns", "kind": "dungeon", "count": 3, "ready": 0, "open": False, "levels": "15-25"},
    {"name": "Cooking", "kind": "category", "count": 1, "ready": 0, "open": True, "levels": "",
     "rows": [("[10] Dig Rat Stew", "Dig Rat 3/8", dashed(), "", 2, False, WHITE, False)]},
    {"name": "Silverpine Forest", "kind": "zone", "count": 1, "ready": 1, "open": False, "tracked": True, "levels": "10-20"},
    {"name": "Undercity", "kind": "zone", "count": 1, "ready": 1, "open": False, "levels": ""},
]

def name_color(group):
    if group.get("onMap"):
        return WHITE
    return LILAC if group["kind"] == "dungeon" else GOLD
def lead_icons(group, size=14):
    out = ""
    if group.get("current"):
        out += img(ARROW, 12, 12, "opacity:.9")
    if group["kind"] == "dungeon":
        out += img(DUNGEON, size)
    elif group["kind"] == "category":
        out += f'<span style="display:inline-block;width:{size}px;height:{size}px;flex:none;background:{FOOD} center/115%;box-shadow:0 0 0 1px #000"></span>'
    return out
def fold_plus(group):
    return img(MINUS, 13, 4) if group["open"] else img(PLUS, 13, 13)
def fold_campaign(group):
    return img(OPEN if group["open"] else SHUT, 18)
def tracked_edge(group):
    return f'<span style="position:absolute;left:0;top:4px;bottom:4px;width:3px;background:{GOLD}"></span>' if group.get("tracked") else ""
def turnin(count):
    return f'<span style="display:inline-flex;align-items:center;gap:1px;font:12px {FRIZ};color:{WHITE}">{img(TURNIN, 15)}{count}</span>' if count else ""

def rows_of(group):
    out = ""
    for title, sub, mark, chain, silver, can_share, sub_color, focused in group.get("rows", []):
        r = row(title, sub, mark, chain, silver, extra_right=share() if can_share else "", selected=focused, sub_color=sub_color)
        if focused:
            r = r.replace("box-shadow:inset 0 0 0 1px #c9a227;", "box-shadow:inset 0 0 0 1px #c9a227,inset -3px 0 0 #ffd100;")
        out += r
    return out

# A. The character window's carved plate
def head_a(group):
    return (f'<div style="position:relative;display:flex;align-items:center;gap:6px;height:28px;margin:6px 4px 2px;padding:0 10px 0 12px;'
            f'background:{PLATE} center/100% 100% no-repeat">{tracked_edge(group)}{lead_icons(group)}'
            f'<span style="font:13.5px {FRIZ};color:{name_color(group)};text-shadow:1px -1px 0 #000">{group["name"]}</span>'
            f'<span style="font:11px {FRIZ};color:{TAN}">({group["count"]})</span><span style="flex:1"></span>{turnin(group["ready"])}'
            f'<span style="margin-left:6px">{fold_plus(group)}</span></div>')

# B. A dark wooden band, the quest page's title band
def head_b(group):
    right = []
    if group["ready"]:
        right.append(f'<span style="color:{GREEN}">{group["ready"]} ready</span>')
    right.append(f'<span style="color:{TAN}">{group["count"]} {"quest" if group["count"] == 1 else "quests"}</span>')
    glow = "box-shadow:inset 0 0 0 1px #c9a22788;" if group.get("onMap") else ""
    return (f'<div style="position:relative;display:flex;align-items:center;gap:6px;height:30px;margin:6px 0 2px;padding:0 10px 0 6px;'
            f'background:{BAND} center/100% 100% no-repeat;{glow}">{tracked_edge(group)}{fold_campaign(group)}{lead_icons(group)}'
            f'<span style="flex:1;font:14px {FRIZ};color:{name_color(group)};text-shadow:1px -1px 0 #000">{group["name"]}</span>'
            f'<span style="font:11px {FRIZ}">{" · ".join(right)}</span></div>')

# C. The classic quest log: a + or - in front, the count after the name
def head_c(group):
    ready = f'<span style="font:11px {FRIZ};color:{GREEN}">{group["ready"]} ready</span>' if group["ready"] else ""
    fill = "background:linear-gradient(90deg,#ffd10022,transparent 80%);" if group.get("onMap") else ""
    return (f'<div style="position:relative;display:flex;align-items:center;gap:6px;height:26px;margin:6px 0 4px;padding:0 10px 0 6px;{fill}'
            f'border-bottom:2px solid #7a4f00;box-shadow:0 1px 0 #ffffff14">{tracked_edge(group)}{fold_campaign(group)}{lead_icons(group)}'
            f'<span style="font:14px {FRIZ};color:{name_color(group)};text-shadow:1px -1px 0 #000">{group["name"]}</span>'
            f'<span style="font:11.5px {FRIZ};color:{TAN}">({group["count"]})</span><span style="flex:1"></span>{ready}</div>')

# D. Two lines: the name, and what is there in words
def head_d(group):
    parts = []
    if group["levels"]:
        parts.append("Levels " + group["levels"])
    parts.append(f'{group["count"]} {"quest" if group["count"] == 1 else "quests"}')
    if group["ready"]:
        parts.append(f'<span style="color:{GREEN}">{group["ready"]} to hand in</span>')
    fill = "background:#ffd10014;" if group.get("onMap") else "background:#ffffff08;"
    return (f'<div style="position:relative;display:flex;align-items:center;gap:7px;padding:5px 10px 5px 12px;margin:6px 0 2px;{fill}'
            f'border-bottom:1px solid #6b5a3a">{tracked_edge(group)}{lead_icons(group, 16)}'
            f'<div style="flex:1"><div style="font:14px {FRIZ};color:{name_color(group)};text-shadow:1px -1px 0 #000">{group["name"]}</div>'
            f'<div style="font:10.5px {FRIZ};color:{TAN}">{" · ".join(parts)}</div></div>{fold_plus(group)}</div>')

# E. A rounded dark bar, stronger, with the game's marks for the numbers
def head_e(group):
    rim = "#c9a227" if group.get("onMap") else "#5a4a30"
    badge = (f'<span style="min-width:16px;height:16px;padding:0 4px;box-sizing:border-box;border-radius:8px;background:#000;box-shadow:inset 0 0 0 1px #6b5a3a;'
             f'font:11px/16px {FRIZ};color:{TAN};text-align:center">{group["count"]}</span>')
    return (f'<div style="position:relative;display:flex;align-items:center;gap:6px;height:26px;margin:6px 3px 3px;padding:0 8px 0 10px;border-radius:4px;'
            f'background:linear-gradient(#3a2c18,#1f170d);box-shadow:inset 0 0 0 1px {rim},0 1px 3px #0008">{tracked_edge(group)}{lead_icons(group)}'
            f'<span style="flex:1;font:13.5px {FRIZ};color:{name_color(group)};text-shadow:1px -1px 0 #000">{group["name"]}</span>'
            f'{turnin(group["ready"])}{badge}<span style="margin-left:3px">{fold_plus(group)}</span></div>')

# F. Led by a picture of the place, and a small bar of what is ready
def head_f(group):
    if group["kind"] == "dungeon":
        pic = f'<span style="display:inline-block;width:20px;height:20px;flex:none;background:#000 {DUNGEON} center/80% no-repeat;box-shadow:0 0 0 1px #000,0 0 0 2px #6b4a26"></span>'
    else:
        pic = f'<span style="display:inline-block;width:20px;height:20px;flex:none;background:{FOOD if group["kind"] == "category" else MAPICON} center/118%;box-shadow:0 0 0 1px #000,0 0 0 2px #6b4a26"></span>'
    share_done = group["ready"] / group["count"]
    bar = (f'<span title="" style="position:relative;width:38px;height:9px;border-radius:5px;background:#000;box-shadow:inset 0 0 0 1px #5a4a30;overflow:hidden">'
           f'<span style="position:absolute;left:1px;top:1px;bottom:1px;width:{36 * share_done:.0f}px;border-radius:4px;background:#2e9a3e"></span></span>')
    arrow = img(ARROW, 11, 11, "margin-left:-2px") if group.get("current") else ""
    fill = "background:#ffd10012;" if group.get("onMap") else ""
    return (f'<div style="position:relative;display:flex;align-items:center;gap:7px;height:30px;padding:0 9px 0 9px;margin:6px 0 2px;{fill}border-bottom:1px solid #4a3c26">'
            f'{tracked_edge(group)}{pic}{arrow}<span style="flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font:14px {FRIZ};color:{name_color(group)};text-shadow:1px -1px 0 #000">{group["name"]}</span>'
            f'<span style="font:11px {FRIZ};color:{TAN}">{group["ready"]}/{group["count"]}</span>{bar}{fold_plus(group)}</div>')

def panel_of(head):
    html = ""
    for group in GROUPS:
        html += head(group)
        if group["open"]:
            html += rows_of(group)
    return panel(html)

LEGEND = (f'<div style="font-size:12px;color:#a8a080;line-height:1.5;max-width:1500px">In every panel: <b style="color:#d8cfa8">The Barrens</b> is the zone you are in (the arrow) and the one '
          f'the map shows, holds a tracked quest (the gold edge), is open, 4 quests of which 2 are ready to hand in; its rows carry chains, the party share icon, '
          f'profit, and the focused quest. <b style="color:#d8cfa8">Wailing Caverns</b> is a dungeon, folded. <b style="color:#d8cfa8">Cooking</b> is a category, open. '
          f'<b style="color:#d8cfa8">Silverpine Forest</b> is folded and holds a tracked quest; <b style="color:#d8cfa8">Undercity</b> is folded, its one quest ready.</div>')
row1 = (col("A. Carved plate", "The character window's section plate (UI-Character-Info-Title) behind each zone. The count after the name, “(4)”; at the right only the ready ones, as the game's turn-in “?” and how many; the game's + and -.", panel_of(head_a), "Recommended")
        + col("B. Dark band", "The quest page's dark title band, full width: strong. The campaign + or - in front, the name, and the numbers in words at the right: “2 ready · 4 quests”.", panel_of(head_b))
        + col("C. Classic quest log", "As the classic quest log heads a zone: the + or - in front, the name and its count “(4)”, a firm rule under it; “2 ready” in green at the right when any are.", panel_of(head_c)))
row2 = (col("D. Two lines", "The name, and under it what is there in words: “Levels 10-25 · 4 quests · 2 to hand in”. The tallest; nothing to decode.", panel_of(head_d))
        + col("E. Rounded bar", "The bar as before but stronger: a lit rim, the game's turn-in “?” with how many are ready, then the count in a small dark badge.", panel_of(head_e))
        + col("F. Picture and progress", "Each heading led by a framed picture (the map for a zone, the gate for a dungeon, the category's own), and at the right how many are ready as “2/4” with a small bar.", panel_of(head_f)))
width = 30 * 2 + 3 * (round(W * 1.6) + 20) + 2 * 36
height = int(sys.argv[3]) if len(sys.argv) > 3 else 2400
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Quest list zone headings</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}} :root{{{"".join(f"--{k}:url({v});" for k, v in IMAGES.items())}}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:28px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
{LEGEND}
<div style="display:flex;gap:36px;align-items:flex-start">{row1}</div>
<div style="display:flex;gap:36px;align-items:flex-start">{row2}</div>
</div>
</x-dc>
<script type="text/x-dc" data-dc-script data-props='{{"$preview":{{"width":{width},"height":{height}}}}}'>
class Component extends DCLogic {{
renderVals() {{
return {{}};
}}
}}
</script>
</body>
</html>
'''
open(os.path.join(OUT, "ZoneHeadings.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height, len(board) // 1024, "KB")
