"""A Design-board artboard: party members who do not have the quest - can take it, done it, cannot have it, unknown."""
import os, sys, base64
OUT, PORTRAITS = sys.argv[1], sys.argv[2]
def uri(name):
    return "data:image/png;base64," + base64.b64encode(open(f"{PORTRAITS}/{name}.png", "rb").read()).decode()
GOLD, TAN, GREEN, GREY, RED = "#ffd100", "#c8b48a", "#7ce07c", "#8a8578", "#ff5a4a"
OBJECTIVES = [("Plainstrider Beak", 7), ("Zhevra Hoof", 10), ("Kolkar Leader slain", 2), ("Barak's Head", 1), ("Centaur Bracers", 5), ("Raptor Head", 6)]
MINE = [3, 10, 0, 0, 5, 1]
# state: has / done / can / cannot / unknown
PARTY = [
    {"name": "Garra Windmane", "short": "GW", "portrait": "male-tauren", "color": "#aad372", "state": "has", "counts": [4, 7, 1, 0, 3, 6]},
    {"name": "Brakka Thunderhoof", "short": "BT", "portrait": "female-orc", "color": "#c69b6d", "state": "done", "why": "Done it already"},
    {"name": "Mirandel Ashvale", "short": "MA", "portrait": "female-scourge", "color": "#ffffff", "state": "can", "why": "Can take it: Sergra Darkthorn, The Crossroads"},
    {"name": "Olen Rusk", "short": "OR", "portrait": "male-troll", "color": "#3fc7eb", "state": "cannot", "why": "Can't have it yet: level 9, the quest needs 10"},
]
UNKNOWN = {"name": "Teska Vale", "short": "TV", "portrait": "male-troll", "color": "#f48cba", "state": "unknown", "why": "Not on the quest; whether done or able, unknown (no OneMoreQuest)"}

BADGES = {  # the mark on the portrait's corner and in the column
    "done": ("✓", "#1a140b", GREEN, "done"),
    "can": ("!", "#1a140b", GOLD, "can take"),
    "cannot": ("✕", "#1a140b", RED, "lvl 10"),
    "unknown": ("?", "#1a140b", "#bbb", "?"),
}

def portrait(m, size, badge):
    has = m["state"] == "has"
    filt = "" if has else "filter:grayscale(1) brightness(.8);"
    ring = "#c9a227" if has else "#6b6450"
    face = (f'<span style="position:relative;display:inline-block;width:{size}px;height:{size}px;border-radius:50%;'
            f'background:#000 url({uri(m["portrait"])}) center/112% no-repeat;{filt}box-shadow:0 0 0 2px {ring},0 0 0 3px #000"></span>')
    if not badge or has:
        return face
    glyph, back, color, _ = BADGES[m["state"]]
    b = max(12, round(size * 0.5))
    tag = (f'<span style="position:absolute;right:{-size * 0.2:.0f}px;bottom:{-size * 0.1:.0f}px;width:{b}px;height:{b}px;border-radius:50%;background:{back};'
           f'box-shadow:0 0 0 1.5px {color},0 0 0 2.5px #000;display:flex;align-items:center;justify-content:center;font:800 {b * 0.62:.0f}px/1 \'Source Sans 3\';color:{color}">{glyph}</span>')
    return f'<span style="position:relative;display:inline-block">{face}{tag}</span>'

def head(m, col, size, light, badge):
    color = (m["color"] if m["state"] == "has" else GREY) if light else ("#2b1d0e" if m["state"] == "has" else "#8a7a5a")
    return (f'<div title="{m["name"]}: {m.get("why", "")}" style="display:flex;flex-direction:column;align-items:center;gap:4px;width:{col}px">{portrait(m, size, badge)}'
            f'<span style="font:700 11px/1.1 \'Source Sans 3\';color:{color}">{m["short"]}</span></div>')

def count(m, i, light):
    req = OBJECTIVES[i][1]
    c = m["counts"][i]
    text = f"{c}/{req}"
    if c >= req:
        return f'<span style="color:{GREEN if light else "#2f7a2f"}">{text}</span>'
    if c == 0:
        return f'<span style="color:{GREY if light else "#8a7a5a"}">{text}</span>'
    return text

def column_fill(m, rows, row_height, light, style):
    """A non-holder's column, over all the objective rows"""
    glyph, _, color, word = BADGES[m["state"]]
    if style == "empty":
        return ""
    if style == "word":
        ink = color if light else {"done": "#2f7a2f", "can": "#8a5a00", "cannot": "#a33224", "unknown": "#7a6a4a"}[m["state"]]
        return (f'<div style="position:absolute;inset:2px 3px;border-radius:6px;background:{"rgba(255,255,255,.05)" if light else "rgba(90,60,20,.10)"};'
                f'display:flex;flex-direction:column;align-items:center;justify-content:center;gap:2px">'
                f'<span style="font:800 15px/1 \'Source Sans 3\';color:{ink}">{glyph}</span>'
                f'<span style="font:600 9.5px/1.1 \'Source Sans 3\';color:{ink};writing-mode:vertical-rl;transform:rotate(180deg);letter-spacing:.5px">{word}</span></div>')
    return ""

def table(light, members, style, badge, col, size, width, label_font):
    heads = "".join(head(m, col, size, light, badge) for m in members)
    rows_html = ""
    n = len(OBJECTIVES)
    row_h = 17 if light else 19
    for i, (name, req) in enumerate(OBJECTIVES):
        cells = ""
        for m in members:
            cells += f'<span style="width:{col}px;text-align:center">{count(m, i, light) if m["state"] == "has" else ""}</span>'
        rule = "" if light else "border-top:1px solid rgba(90,60,20,.15);"
        rows_html += (f'<div style="display:flex;font-size:{label_font}px;line-height:{row_h}px;{rule}"><span style="flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'
                      f'{"" if light else ""}{name}</span><span style="width:40px;text-align:right;margin-right:4px">{MINE[i]}/{req}</span>{cells}</div>')
    # overlays for the non-holders' columns
    overlays = ""
    for index, m in enumerate(members):
        if m["state"] != "has":
            left_from_right = (len(members) - index) * col
            overlays += f'<div style="position:absolute;top:0;bottom:0;right:{left_from_right - col}px;width:{col}px">{column_fill(m, n, row_h, light, style)}</div>'
    you = f'<span style="width:40px;text-align:right;margin-right:4px;font-size:10.5px;color:{TAN if light else "#2b1d0e"};font-weight:600">you</span>'
    header = f'<div style="display:flex;align-items:flex-end;margin:2px 0 4px"><span style="flex:1"></span>{you}{heads}</div>'
    body = f'<div style="position:relative">{rows_html}{overlays}</div>'
    if light:
        title = (f'<div style="display:flex;align-items:center;gap:6px;margin-bottom:2px"><span style="width:14px;height:14px;border-radius:50%;background:radial-gradient(circle at 38% 32%,#ffe58a,#e3b23c 55%,#9c6a12);border:1px solid #5a3a08"></span>'
                 f'<span style="color:#fff">[14] Centaur and Beast</span></div>')
        return (f'<div style="width:{width}px;background:rgba(0,0,0,.55);border-radius:4px;padding:8px 8px 10px;font:13px/1.35 \'Source Sans 3\';color:#e8e2d0">'
                f'<div style="display:flex;justify-content:space-between;border-bottom:1px solid #6b5a2e;padding-bottom:3px;margin-bottom:6px">'
                f'<span style="font:400 13px Marcellus,Georgia;color:{GOLD}">Quests</span><span style="color:{TAN}">The Barrens</span></div>{title}{header}{body}</div>')
    return (f'<div style="width:{width}px;background:linear-gradient(#e9d7ad,#d9c391);border-radius:3px;padding:12px 14px;font:13px/1.4 \'Source Sans 3\';color:#2b1d0e;box-shadow:inset 0 0 18px rgba(80,50,10,.35)">'
            f'<div style="font:400 17px Marcellus,Georgia;color:#3a2400;margin-bottom:6px">Party</div>{header}{body}</div>')

def tooltip_examples():
    lines = ""
    for m in PARTY[1:] + [UNKNOWN]:
        glyph, _, color, _ = BADGES[m["state"]]
        lines += (f'<div style="display:flex;gap:8px;align-items:baseline"><span style="width:12px;color:{color};font-weight:800">{glyph}</span>'
                  f'<span style="color:{m["color"]};min-width:118px;flex:none">{m["name"]}</span><span style="color:#ddd">{m["why"]}</span></div>')
    return (f'<div style="background:#0b0b0b;border:1px solid #555;border-radius:4px;padding:8px 10px;font:12px/1.6 \'Source Sans 3\';color:#ddd;width:420px;box-sizing:border-box">'
            f'<div style="color:{GOLD};margin-bottom:2px">Hovering a portrait</div>{lines}</div>')

def legend():
    items = [("has", "", "#c9a227", "On the quest: their counts in the column, in colour"),
             ("done", "✓", GREEN, "Done it already: greyed, ✓ (needs their OneMoreQuest)"),
             ("can", "!", GOLD, "Can take it: greyed, ! as over a quest giver"),
             ("cannot", "✕", RED, "Can't have it: greyed, ✕; why on hover (level, race, class; an earlier quest with their addon)"),
             ("unknown", "?", "#bbb", "Not on it, and the rest unknown: no OneMoreQuest on their side, and nothing rules them out")]
    out = ""
    for state, glyph, color, text in items:
        mark = f'<span style="display:inline-flex;width:16px;height:16px;border-radius:50%;box-shadow:0 0 0 1.5px {color};align-items:center;justify-content:center;font:800 11px \'Source Sans 3\';color:{color}">{glyph}</span>'
        out += f'<div style="display:flex;gap:8px;align-items:center;font-size:12px;color:#d8cfa8">{mark}{text}</div>'
    return f'<div style="display:flex;flex-direction:column;gap:6px">{out}</div>'

def col(title, text, pictures, recommended=False):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if recommended else ""
    return (f'<div style="display:flex;flex-direction:column;gap:12px;width:440px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:36px">{text}</div>{pictures}</div>')

cols = (col("A. A badge on the portrait", "Greyed portrait with a badge at its corner: ✓ done it, ! can take it, ✕ can't have it, ? unknown. Their column stays empty; hovering says why.",
            table(True, PARTY, "empty", True, 36, 22, 340, 12) + table(False, PARTY, "empty", True, 50, 30, 420, 12.5))
        + col("B. Badge, and the column says it", "As A, and their empty column carries the mark with a word down it (done, can take, lvl 10), so it reads without looking up at the badge.",
              table(True, PARTY, "word", True, 36, 22, 340, 12) + table(False, PARTY, "word", True, 50, 30, 420, 12.5), True)
        + col("Legend and hover", "The same five states everywhere. Without OneMoreQuest on their side only level, race and class can rule a member out; done and earlier quests need their addon to answer.",
              legend() + tooltip_examples()))
width, height = 30 * 2 + 3 * 440 + 2 * 40, 900
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Party member states</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700;800&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5">Layout A, with the members who do not have the quest: <span style="color:#aad372">Garra</span> on it, Brakka done it already, Mirandel can take it, Olen can't have it yet (level 9, needs 10).</div>
<div style="display:flex;gap:40px;align-items:flex-start">{cols}</div>
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
open(os.path.join(OUT, "PartyStates.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
