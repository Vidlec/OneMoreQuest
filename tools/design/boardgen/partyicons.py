"""A Design-board artboard: the party as a row of faces with a status icon each; the rest on hover."""
import os, sys, base64, math
OUT, PORTRAITS = sys.argv[1], sys.argv[2]
def uri(name):
    return "data:image/png;base64," + base64.b64encode(open(f"{PORTRAITS}/{name}.png", "rb").read()).decode()
GOLD, TAN, GREEN, GREY, RED = "#ffd100", "#c8b48a", "#7ce07c", "#8a8578", "#ff5a4a"
OBJECTIVES = [("Plainstrider Beak", 7), ("Zhevra Hoof", 10), ("Kolkar Leader slain", 2), ("Barak Kodobane's Head", 1), ("Centaur Bracers", 5), ("Raptor Head", 6)]
MINE = [3, 10, 0, 0, 5, 1]
PARTY = [
    {"name": "Garra Windmane", "short": "GW", "img": "male-tauren", "color": "#aad372", "state": "going", "counts": [4, 7, 1, 0, 3, 6]},
    {"name": "Brakka Thunderhoof", "short": "BT", "img": "female-orc", "color": "#c69b6d", "state": "ready", "counts": [7, 10, 2, 1, 5, 6]},
    {"name": "Mirandel Ashvale", "short": "MA", "img": "female-scourge", "color": "#ffffff", "state": "cannot", "why": "Can't have it yet: level 9, the quest needs 10"},
    {"name": "Olen Rusk", "short": "OR", "img": "male-troll", "color": "#3fc7eb", "state": "done", "why": "Done it already"},
]
# status: icon, colour, ring colour, whether the face is greyed
STATUS = {
    "going": ("…", "#e8e2d0", "#c9a227", False, "In progress"),
    "ready": ("✓", GREEN, "#c9a227", False, "Ready to turn in"),
    "done": ("✓", "#a9a497", "#6b6450", True, "Done it already"), # grey: done before, not a turn-in waiting
    "can": ("!", GOLD, "#6b6450", True, "Can take it"),
    "cannot": ("✕", RED, "#6b6450", True, "Can't have it"),
    "unknown": ("?", "#bbb", "#6b6450", True, "Unknown"),
}

def share(m):
    if "share" in m:
        return m["share"]
    if "counts" not in m:
        return None
    return sum(min(c, OBJECTIVES[i][1]) for i, c in enumerate(m["counts"])) / sum(r for _, r in OBJECTIVES)

def face(m, size, ring_style):
    icon, color, ring, grey, _ = STATUS[m["state"]]
    filt = "filter:grayscale(1) brightness(.8);" if grey else ""
    img = (f'<span style="position:absolute;inset:0;border-radius:50%;background:#000 url({uri(m["img"])}) center/112% no-repeat;{filt}"></span>')
    if ring_style == "progress" and m["state"] in ("going", "ready"):
        p = share(m)
        deg = 360 * p
        frame = (f'<span style="position:absolute;inset:-3px;border-radius:50%;background:conic-gradient({GOLD} 0 {deg:.0f}deg, #3a3222 {deg:.0f}deg 360deg);'
                 f'-webkit-mask:radial-gradient(circle, transparent {size / 2 - 0.5}px, #000 {size / 2}px);mask:radial-gradient(circle, transparent {size / 2 - 0.5}px, #000 {size / 2}px)"></span>')
        edge = f'<span style="position:absolute;inset:-4px;border-radius:50%;box-shadow:0 0 0 1px #000"></span>'
    else:
        frame = f'<span style="position:absolute;inset:-2px;border-radius:50%;box-shadow:0 0 0 2px {ring},0 0 0 3px #000"></span>'
        edge = ""
    show_badge = not (ring_style == "progress" and m["state"] == "going")
    b = max(10, round(size * 0.55))
    badge = (f'<span style="position:absolute;right:{-size * 0.22:.0f}px;bottom:{-size * 0.14:.0f}px;width:{b}px;height:{b}px;border-radius:50%;background:#1a140b;'
             f'box-shadow:0 0 0 1px {color},0 0 0 2px #000;display:flex;align-items:center;justify-content:center;font:800 {b * 0.7:.0f}px/1 \'Source Sans 3\';color:{color}">{icon}</span>') if show_badge else ""
    return f'<span title="{m["name"]}" style="position:relative;display:inline-block;flex:none;width:{size}px;height:{size}px">{edge}{frame}{img}{badge}</span>'

def row(size, gap, ring_style, hovered=None):
    out = ""
    for index, m in enumerate(PARTY):
        hl = "outline:1px solid rgba(255,209,0,.0);" if index != hovered else ""
        out += f'<span style="display:inline-flex">{face(m, size, ring_style)}</span>'
    return f'<span style="display:inline-flex;gap:{gap}px;align-items:center">{out}</span>'

def tooltip(m):
    _, color, _, _, label = STATUS[m["state"]]
    lines = f'<div style="color:{m["color"]};font-size:13px">{m["name"]}</div>'
    if "counts" in m:
        lines += f'<div style="color:{color}">{label}</div>'
        for i, (n, r) in enumerate(OBJECTIVES):
            c = m["counts"][i]
            lines += (f'<div style="display:flex;gap:16px;justify-content:space-between;color:{"#888" if c >= r else "#fff"}"><span>{n}</span>'
                      f'<span>{"✓" if c >= r else f"{c}/{r}"}</span></div>')
    else:
        lines += f'<div style="color:{color}">{m["why"]}</div>'
    return f'<div style="background:#0b0b10;border:1px solid #5a5a66;border-radius:4px;padding:6px 9px;font:12px/1.5 \'Source Sans 3\';color:#ddd;width:220px">{lines}</div>'

def tracker(inner, title="[14] Centaur and Beast", chain=""):
    t = (f'<div style="display:flex;align-items:center;gap:6px;margin-bottom:3px"><span style="width:14px;height:14px;border-radius:50%;background:radial-gradient(circle at 38% 32%,#ffe58a,#e3b23c 55%,#9c6a12);border:1px solid #5a3a08;flex:none"></span>'
         f'<span style="color:#fff;flex:1">{title}</span>{chain}</div>')
    return f'<div style="width:262px;background:rgba(0,0,0,.55);border-radius:4px;padding:8px 8px 10px;font:13px/1.35 \'Source Sans 3\';color:#e8e2d0">{t}{inner}</div>'

def objectives(light, indent):
    return "".join(f'<div style="padding-left:{indent}px;font-size:12.5px"><span style="color:{GOLD if light else "#6a3d00"}">{MINE[i]}/{r}</span> {n}</div>' for i, (n, r) in enumerate(OBJECTIVES))

def page(strip_html):
    return (f'<div style="width:400px;background:linear-gradient(#e9d7ad,#d9c391);border-radius:3px;padding:12px 14px;font:13px/1.4 \'Source Sans 3\';color:#2b1d0e;box-shadow:inset 0 0 18px rgba(80,50,10,.35)">'
            f'<div style="display:flex;align-items:center;gap:8px;border-top:1px solid rgba(90,60,20,.6);padding-top:8px"><span style="color:#5a4526">⌄</span><span style="font:400 17px Marcellus,Georgia;color:#3a2400;flex:1">Party</span>{strip_html}</div>'
            f'<div style="font-size:11.5px;color:#6b5636;margin-top:6px">Hover a face for their name and progress, or why not.</div></div>')

chain = '<span style="font-size:11px;color:#b8ad8c;border:1px solid #5d5440;border-radius:8px;padding:0 6px">⛓ 5 of 5</span>'
def column(title, text, ring_style, rec=False):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if rec else ""
    strip_tracker = f'<div style="padding-left:20px;margin:5px 0 6px">{row(18, 9, ring_style)}</div>'
    # The party right under the title, then the player's own progress (or the turn-in) below it
    t1 = tracker(strip_tracker + objectives(True, 20))
    t2 = tracker(strip_tracker + f'<div style="padding-left:20px;font-size:12.5px;color:{GREEN}">Turn in to Rane Yorick</div>', "[12] Ivar the Foul", chain)
    t3 = ""
    tips = f'<div style="display:flex;gap:10px">{tooltip(PARTY[0])}{tooltip(PARTY[2])}</div>'
    steps = ""
    if ring_style == "progress":
        # The ring from nothing done to ready, at the quest page's size and the tracker's
        for value, label in [(0, "0%, just taken"), (0.25, "25%"), (0.5, "50%"), (0.9, "90%"), (1, "ready")]:
            sample = {"name": label, "img": "male-tauren", "state": "ready" if value == 1 else "going", "share": value}
            steps += (f'<div style="display:flex;flex-direction:column;align-items:center;gap:6px;width:76px">'
                      f'<span style="display:flex;gap:10px;align-items:center">{face(sample, 24, "progress")}{face(sample, 18, "progress")}</span>'
                      f'<span style="font-size:11px;color:#d8cfa8">{label}</span></div>')
        steps = (f'<div style="font-size:11px;color:{TAN};margin-top:4px">The ring as progress grows, at the quest page\'s size and the tracker\'s</div>'
                 f'<div style="display:flex;gap:6px;background:rgba(0,0,0,.55);border-radius:4px;padding:10px">{steps}</div>')
    return (f'<div style="display:flex;flex-direction:column;gap:10px;width:470px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:52px">{text}</div>'
            f'<div style="font-size:11px;color:{TAN}">Tracker: the party under the title, your progress below; then a quest ready to hand in</div>{t1}{t2}{t3}'
            f'<div style="font-size:11px;color:{TAN};margin-top:4px">Quest page: the faces in the Party row</div>{page(row(24, 10, ring_style))}'
            f'<div style="font-size:11px;color:{TAN};margin-top:4px">Hovering Garra, then Mirandel</div>{tips}{steps}</div>')

legend = ""
for key in ["going", "ready", "done", "can", "cannot", "unknown"]:
    icon, color, ring, grey, label = STATUS[key]
    sample = {"name": label, "img": "male-tauren", "state": key, "counts": [4, 7, 1, 0, 3, 6] if key in ("going",) else [7, 10, 2, 1, 5, 6]}
    legend += f'<div style="display:flex;align-items:center;gap:10px;font-size:12px;color:#d8cfa8;margin:6px 0">{face(sample, 20, "badge")}<span style="width:22px"></span>{label}</div>'
cols = (column("A. A status badge on each face", "One row of faces, each with a badge: … in progress, green ✓ ready (gold ring), grey ✓ done it already (greyed face), ! can take it, ✕ can't, ? unknown. Hover gives the full name and every count, or the reason.", "badge", True)
        + column("B. A progress ring round each face", "As A, but a member on the quest has a ring that fills with their progress (all objectives together) instead of the … badge; ✓ once ready. Shows how far along at a glance.", "progress")
        + f'<div style="display:flex;flex-direction:column;gap:6px;width:240px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">States</div>{legend}</div>')
width, height = 30 * 2 + 2 * 470 + 240 + 2 * 40, 1000
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Party as faces</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700;800&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5">The party as a row of faces, a status on each instead of words; names, counts and reasons on hover. Garra in progress, Brakka ready, Mirandel too low, Olen done it already.</div>
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
open(os.path.join(OUT, "PartyFaces.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
