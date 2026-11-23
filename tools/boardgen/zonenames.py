"""A Design-board artboard: zone headings with names in line, other name colours, and where you are."""
import os, sys
OUT, ART = sys.argv[1], sys.argv[2]
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "partyicon.py")).read()
exec(src.split("ROWS_PLAIN = ")[0].replace("OUT, ART = sys.argv[1], sys.argv[2]", ""))
exec(("def col(" + src.split("def col(")[1].split("cols = (")[0]).replace("1.6", "1.4"))
W = 314  # the quest list as the game draws it: 330, less its scroll bar
BAND, OPEN, SHUT = image("band", "questlog-reward-top-frame.png"), image("open", "campaign_headericon_open.png"), image("shut", "campaign_headericon_closed.png")
DUNGEON, FOOD = image("dungeon", "dungeon.png"), image("food", "inv_misc_food_15.png")
PIN, PIN_BIG = image("pin", "waypoint-mappin-chaticon.png"), image("pinbig", "waypoint-mappin-tracked.png")
NAME_WHITE, NAME_SOFT, LILAC_SOFT = "#ffffff", "#e8dcc0", "#d6c2f2"

# name, kind, quests, ready, open, you are here, holds a tracked quest
HEADS = [("The Barrens", "zone", 4, 2, True, True, True), ("Cooking", "category", 1, 0, False, False, False), ("Silverpine Forest", "zone", 1, 1, False, False, True),
         ("Thunder Bluff", "zone", 1, 1, False, False, False), ("Undercity", "zone", 1, 1, False, False, False), ("Razorfen Kraul", "dungeon", 1, 0, False, False, True),
         ("Thousand Needles", "zone", 1, 0, False, False, False), ("Wailing Caverns", "dungeon", 2, 0, False, False, False)]
MUTED, LILAC_MUTED = "#9a8e74", "#8f80a8"

def tracked_color(kind, is_tracked):
    """A heading with a tracked quest in it reads bright; one without, muted"""
    if kind == "dungeon":
        return LILAC_SOFT if is_tracked else LILAC_MUTED
    return NAME_WHITE if is_tracked else MUTED
BARRENS_ROWS = [("[13] Raptor Thieves", "✓ Gazrog", dashed(), "1/2", 5, True, GREEN, False),
                ("[20] The Guns of Northwatch", "1 of 4 done", coin(KILL), "", 5, False, WHITE, True)]

def img(src, w, h=None, extra=""):
    return f'<span style="display:inline-block;width:{w}px;height:{h or w}px;flex:none;background:{src} center/contain no-repeat;{extra}"></span>'
def kind_icon(kind, size=15):
    if kind == "dungeon":
        return img(DUNGEON, size)
    if kind == "category":
        return f'<span style="display:inline-block;width:{size}px;height:{size}px;flex:none;background:{FOOD} center/115%;box-shadow:0 0 0 1px #000"></span>'
    return ""
def counts(count, ready, lead=""):
    parts = ([lead] if lead else []) + ([f'<span style="color:{GREEN}">{ready} ready</span>'] if ready else []) + [f'{count} {"quest" if count == 1 else "quests"}']
    return f'<span style="font:11px {FRIZ};color:{TAN};white-space:nowrap">{" · ".join(parts)}</span>'
def band(inner, extra=""):
    return (f'<div style="position:relative;display:flex;align-items:center;gap:6px;height:34px;margin:0 0 2px;padding:0 10px 0 6px;'
            f'background:{BAND} center/100% 100% no-repeat;{extra}">{inner}</div>')
def name(text, color, size=14):
    return f'<span style="font:{size}px {FRIZ};color:{color};text-shadow:1px -1px 0 #000;white-space:nowrap;min-width:0;overflow:hidden;text-overflow:ellipsis">{text}</span>'
def rows():
    out = ""
    for title, sub, mark, chain, silver, can_share, sub_color, focused in BARRENS_ROWS:
        r = row(title, sub, mark, chain, silver, extra_right=party(15) if can_share else "", selected=focused, sub_color=sub_color)
        out += r.replace("box-shadow:inset 0 0 0 1px #c9a227;", "box-shadow:inset 0 0 0 1px #c9a227,inset -3px 0 0 #ffd100;") if focused else r
    return out + '<div style="height:6px"></div>'
def build(head):
    html = ""
    for item in HEADS:
        html += head(*item)
        if item[4]:
            html += rows()
    return panel(html)

def fold(is_open):
    return img(OPEN if is_open else SHUT, 18)

# A. What a heading is, after its name; where you are as the game's map pin
def head_a(title, kind, count, ready, is_open, is_here, is_tracked):
    color = tracked_color(kind, is_tracked)
    after = kind_icon(kind, 14) + (img(PIN_BIG, 17) if is_here else "")
    return band(f'{fold(is_open)}{name(title, color)}{after}<span style="flex:1"></span>{counts(count, ready)}')

# B. Gold is where you are: every other name in parchment white; icons in a column of their own
def head_b(title, kind, count, ready, is_open, is_here, is_tracked):
    color = GOLD if is_here else tracked_color(kind, is_tracked)
    column = f'<span style="width:16px;flex:none;display:inline-flex;justify-content:center">{kind_icon(kind, 15)}</span>'
    return band(f'{fold(is_open)}{column}{name(title, color)}<span style="flex:1"></span>{counts(count, ready)}')

# C. The + or - at the right; the left column says what the heading is, the pin where you are
def head_c(title, kind, count, ready, is_open, is_here, is_tracked):
    color = tracked_color(kind, is_tracked)
    lead = img(PIN_BIG, 18) if is_here else kind_icon(kind, 16)
    column = f'<span style="width:20px;flex:none;display:inline-flex;justify-content:center">{lead}</span>'
    return band(f'{column}{name(title, color)}<span style="flex:1"></span>{counts(count, ready)}{fold(is_open)}')

# D. In words, no icons: "dungeon", "profession", and "you are here"
def head_d(title, kind, count, ready, is_open, is_here, is_tracked):
    color = tracked_color(kind, is_tracked)
    tag = {"dungeon": "dungeon", "category": "profession"}.get(kind, "")
    tag_html = f'<span style="font:10.5px {FRIZ};color:#a89a78;white-space:nowrap;flex:none">{tag}</span>' if tag else ""
    if is_here:
        tag_html = f'<span style="font:10.5px {FRIZ};color:{GOLD};white-space:nowrap;flex:none">you are here</span>'
    return band(f'{fold(is_open)}{name(title, color)}{tag_html}<span style="flex:1"></span>{counts(count, ready)}')

# E. Where you are is the lit heading: a gold rim and gold name; the rest white, icons after the name
def head_e(title, kind, count, ready, is_open, is_here, is_tracked):
    color = GOLD if is_here else tracked_color(kind, is_tracked)
    lit = "box-shadow:inset 0 0 0 1px #c9a227,inset 0 0 12px #ffd10033;" if is_here else ""
    return band(f'{fold(is_open)}{name(title, color)}{kind_icon(kind, 14)}<span style="flex:1"></span>{counts(count, ready)}', lit)

LEGEND = (f'<div style="font-size:12px;color:#a8a080;line-height:1.5;max-width:1500px">The headings as in the sim: you are in <b style="color:#d8cfa8">The Barrens</b> (open, two of its rows shown); '
          f'<b style="color:#d8cfa8">Cooking</b> is a category; <b style="color:#d8cfa8">Razorfen Kraul</b> and <b style="color:#d8cfa8">Wailing Caverns</b> are dungeons. '
          f'In every design the names start at the same place, whatever icon a heading has. A zone holding a tracked quest has a bright name, one without a muted name: <b style="color:#d8cfa8">The Barrens</b>, <b style="color:#d8cfa8">Silverpine Forest</b> and <b style="color:#d8cfa8">Razorfen Kraul</b> hold tracked quests.</div>')
row1 = (col("A. Icons after the name", "The name always right after the + or -; what the heading is follows it (the gate, the dish), and where you are is the game's gold map pin after the name. Names in white, dungeons lilac.", build(head_a), "Recommended")
        + col("B. Gold is where you are", "Only the zone you are in has a gold name; the rest are parchment white. The icons keep a column of their own after the + or -, empty for a plain zone, so names line up.", build(head_b))
        + col("C. The + or - at the right", "The fold button moves to the right end. The left column says what the heading is: the game's map pin where you are, the gate for a dungeon, the dish for cooking, nothing for a zone.", build(head_c)))
row2 = (col("D. In words", "No icons at all: “dungeon” or “profession” in small letters after the name, and “you are here” in gold in the same place.", build(head_d))
        + col("E. The lit heading", "Your zone's band has a gold rim and a gold name; every other name is white, with its icon after the name as in A.", build(head_e)))
width = 30 * 2 + 3 * (round(W * 1.4) + 20) + 2 * 36
height = int(sys.argv[3]) if len(sys.argv) > 3 else 1500
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Zone heading names</title>
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
open(os.path.join(OUT, "ZoneNames.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height, len(board) // 1024, "KB")
