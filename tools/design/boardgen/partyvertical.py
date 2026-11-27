"""A Design-board artboard: vertical party layouts - portraits in a row under each objective, or a row per member."""
import os, sys, base64
OUT, PORTRAITS = sys.argv[1], sys.argv[2]
def uri(name):
    return "data:image/png;base64," + base64.b64encode(open(f"{PORTRAITS}/{name}.png", "rb").read()).decode()
GOLD, TAN, GREEN, GREY, RED = "#ffd100", "#c8b48a", "#7ce07c", "#8a8578", "#ff5a4a"
OBJECTIVES = [("Plainstrider Beak", 7), ("Zhevra Hoof", 10), ("Kolkar Leader slain", 2), ("Barak Kodobane's Head", 1), ("Centaur Bracers", 5), ("Raptor Head", 6)]
MINE = [3, 10, 0, 0, 5, 1]
PARTY = [
    {"name": "Garra Windmane", "short": "GW", "img": "male-tauren", "color": "#aad372", "state": "has", "counts": [4, 7, 1, 0, 3, 6]},
    {"name": "Brakka Thunderhoof", "short": "BT", "img": "female-orc", "color": "#c69b6d", "state": "has", "counts": [7, 10, 2, 1, 5, 6]},
    {"name": "Mirandel Ashvale", "short": "MA", "img": "female-scourge", "color": "#ffffff", "state": "cannot", "why": "Level 9, the quest needs 10", "word": "lvl 10"},
    {"name": "Olen Rusk", "short": "OR", "img": "male-troll", "color": "#3fc7eb", "state": "done", "why": "Done it already", "word": "done"},
]
BADGE = {"done": ("✓", GREEN), "can": ("!", GOLD), "cannot": ("✕", RED), "unknown": ("?", "#bbb")}

def face(m, size, light=True):
    on = m["state"] == "has"
    filt = "" if on else "filter:grayscale(1) brightness(.8);"
    ring = "#c9a227" if on else "#6b6450"
    f = (f'<span title="{m["name"]}" style="position:relative;display:inline-block;flex:none;width:{size}px;height:{size}px;border-radius:50%;'
         f'background:#000 url({uri(m["img"])}) center/112% no-repeat;{filt}box-shadow:0 0 0 {1.5 if size < 20 else 2}px {ring},0 0 0 {2.5 if size < 20 else 3}px #000"></span>')
    if on:
        return f
    g, c = BADGE[m["state"]]
    b = max(9, round(size * 0.55))
    tag = (f'<span style="position:absolute;right:{-size * 0.25:.0f}px;bottom:{-size * 0.15:.0f}px;width:{b}px;height:{b}px;border-radius:50%;background:#1a140b;'
           f'box-shadow:0 0 0 1px {c},0 0 0 2px #000;display:flex;align-items:center;justify-content:center;font:800 {b * 0.65:.0f}px/1 \'Source Sans 3\';color:{c}">{g}</span>')
    return f'<span style="position:relative;display:inline-block;flex:none">{f}{tag}</span>'

def count_html(c, req, light):
    if c >= req:
        return f'<span style="color:{GREEN if light else "#2f7a2f"};font-weight:700">✓</span>'
    col = (GREY if light else "#8a7a5a") if c == 0 else ("#e8e2d0" if light else "#2b1d0e")
    return f'<span style="color:{col}">{c}/{req}</span>'

def tracker(inner, title="[14] Centaur and Beast", chain=""):
    t = (f'<div style="display:flex;align-items:center;gap:6px;margin-bottom:3px"><span style="width:14px;height:14px;border-radius:50%;background:radial-gradient(circle at 38% 32%,#ffe58a,#e3b23c 55%,#9c6a12);border:1px solid #5a3a08;flex:none"></span>'
         f'<span style="color:#fff;flex:1">{title}</span>{chain}</div>')
    return f'<div style="width:262px;background:rgba(0,0,0,.55);border-radius:4px;padding:8px 8px 10px;font:13px/1.35 \'Source Sans 3\';color:#e8e2d0">{t}{inner}</div>'

def page(inner):
    return (f'<div style="width:400px;background:linear-gradient(#e9d7ad,#d9c391);border-radius:3px;padding:12px 14px;font:13px/1.4 \'Source Sans 3\';color:#2b1d0e;box-shadow:inset 0 0 18px rgba(80,50,10,.35)">'
            f'<div style="display:flex;align-items:center;gap:8px;border-top:1px solid rgba(90,60,20,.6);padding-top:6px;margin-bottom:8px"><span style="color:#5a4526">⌄</span><span style="font:400 17px Marcellus,Georgia;color:#3a2400;flex:1">Party</span>{{STRIP}}</div>{inner}</div>')

def strip(size, gap, light, with_initials=False):
    out = ""
    for m in PARTY:
        ini = f'<span style="font:700 9.5px/1 \'Source Sans 3\';color:{(m["color"] if light else "#2b1d0e") if m["state"] == "has" else GREY}">{m["short"]}</span>' if with_initials else ""
        out += f'<span style="display:inline-flex;flex-direction:column;align-items:center;gap:3px">{face(m, size, light)}{ini}</span>'
    return f'<span style="display:inline-flex;gap:{gap}px;align-items:flex-start">{out}</span>'

# A: under each objective, the party's faces in a row, each with its count
def a_rows(light, size, indent):
    out = ""
    on = [m for m in PARTY if m["state"] == "has"]
    for i, (name, req) in enumerate(OBJECTIVES):
        mine = f'<span style="color:{GOLD if light else "#6a3d00"}">{MINE[i]}/{req}</span>' if MINE[i] < req else f'<span>{MINE[i]}/{req}</span>'
        out += f'<div style="padding-left:{indent}px;font-size:12.5px;margin-top:3px">{mine} {name}</div>'
        chips = "".join(f'<span style="display:inline-flex;align-items:center;gap:4px;margin-right:10px">{face(m, size, light)}<span style="font-size:11.5px">{count_html(m["counts"][i], req, light)}</span></span>' for m in on)
        out += f'<div style="padding-left:{indent + 2}px;margin:2px 0 4px;display:flex;flex-wrap:wrap">{chips}</div>'
    return out

# B: under each objective, only who is still short of it
def b_rows(light, size, indent):
    out = ""
    on = [m for m in PARTY if m["state"] == "has"]
    for i, (name, req) in enumerate(OBJECTIVES):
        mine = f'<span style="color:{GOLD if light else "#6a3d00"}">{MINE[i]}/{req}</span>' if MINE[i] < req else f'<span>{MINE[i]}/{req}</span>'
        short = [m for m in on if m["counts"][i] < req]
        done = len(on) - len(short)
        chips = "".join(f'<span style="display:inline-flex;align-items:center;gap:3px;margin-left:8px">{face(m, size, light)}<span style="font-size:11.5px">{count_html(m["counts"][i], req, light)}</span></span>' for m in short)
        tick = f'<span style="margin-left:8px;font-size:11px;color:{GREEN if light else "#2f7a2f"}">✓{done}</span>' if done else ""
        out += (f'<div style="padding-left:{indent}px;font-size:12.5px;margin:3px 0;display:flex;align-items:center;flex-wrap:wrap">'
                f'<span style="flex:1 1 auto;min-width:0">{mine} {name}</span><span style="display:inline-flex;align-items:center">{chips}{tick}</span></div>')
    return out

# C: a row per member, full name, their counts in the objectives' order
def c_rows(light, size, indent):
    out = ""
    for m in PARTY:
        name_col = (m["color"] if light else "#2b1d0e") if m["state"] == "has" else (GREY if light else "#8a7a5a")
        if m["state"] == "has":
            if all(c >= OBJECTIVES[i][1] for i, c in enumerate(m["counts"])):
                right = f'<span style="color:{GREEN if light else "#2f7a2f"}">ready</span>'
            else:
                left = [f'{OBJECTIVES[i][0].split()[0]} {c}/{OBJECTIVES[i][1]}' for i, c in enumerate(m["counts"]) if c < OBJECTIVES[i][1]]
                right = f'<span style="color:{"#cfc8b0" if light else "#5a4526"}">' + ", ".join(left) + '</span>'
        else:
            g, c = BADGE[m["state"]]
            right = f'<span style="color:{c if light else ("#2f7a2f" if m["state"] == "done" else "#a33224")}">{m["why"]}</span>'
        out += (f'<div style="padding-left:{indent}px;display:flex;align-items:center;gap:8px;margin:5px 0">{face(m, size, light)}'
                f'<div style="min-width:0;flex:1;line-height:1.2"><div style="font-size:12px;font-weight:600;color:{name_col}">{m["name"]}</div>'
                f'<div style="font-size:11.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{right}</div></div></div>')
    return out

def objectives_plain(light, indent):
    return "".join(f'<div style="padding-left:{indent}px;font-size:12.5px"><span style="color:{GOLD if light else "#6a3d00"}">{MINE[i]}/{r}</span> {n}</div>' for i, (n, r) in enumerate(OBJECTIVES))

def turnin_faces(light, size, indent):
    words = {"has": ("ready", GREEN), "cannot": ("lvl 10", RED), "done": ("done", GREEN)}
    chips = ""
    for m in PARTY:
        w, c = words[m["state"]]
        if not light:
            c = {"ready": "#2f7a2f", "lvl 10": "#a33224", "done": "#2f7a2f"}[w]
        chips += f'<span style="display:inline-flex;align-items:center;gap:4px;margin-right:10px">{face(m, size, light)}<span style="font-size:11.5px;color:{c}">{w}</span></span>'
    return (f'<div style="padding-left:{indent}px;font-size:12.5px;color:{GREEN if light else "#2f6b2f"}">Turn in to Rane Yorick</div>'
            f'<div style="padding-left:{indent + 2}px;margin-top:3px;display:flex;flex-wrap:wrap">{chips}</div>')

def col(title, text, pics, rec=False):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if rec else ""
    return (f'<div style="display:flex;flex-direction:column;gap:12px;width:420px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:52px">{text}</div>{pics}</div>')

chain = '<span style="font-size:11px;color:#b8ad8c;border:1px solid #5d5440;border-radius:8px;padding:0 6px">⛓ 5 of 5</span>'
ivar = lambda: tracker(turnin_faces(True, 16, 20), "[12] Ivar the Foul", chain)
A = col("A. Faces under each objective",
        "Each objective on a full-width line, then the party's faces in a row, each with its count (✓ once done). Members without the quest only in the strip at the top. Long names never cut; more members just wrap.",
        tracker(f'<div style="padding-left:20px;margin:2px 0 4px">{strip(16, 6, True)}</div>' + a_rows(True, 14, 20)) + ivar()
        + page(a_rows(False, 18, 0)).replace("{STRIP}", strip(22, 6, False)))
B = col("B. Only who still needs it",
        "As A, but an objective lists only the members still short of it, with their count; the rest fold into ✓2. The shortest: finished objectives take one line.",
        tracker(f'<div style="padding-left:20px;margin:2px 0 4px">{strip(16, 6, True)}</div>' + b_rows(True, 14, 20)) + ivar()
        + page(b_rows(False, 18, 0)).replace("{STRIP}", strip(22, 6, False)), True)
C = col("C. A row per member",
        "Your objectives as now; under them a row per member: face, full name, and what they still need (or ready, or why not). Reads person by person.",
        tracker(objectives_plain(True, 20) + '<div style="height:4px"></div>' + c_rows(True, 20, 20)) + ivar()
        + page(objectives_plain(False, 0) + '<div style="height:6px"></div>' + c_rows(False, 26, 0)).replace("{STRIP}", ""))
width, height = 30 * 2 + 3 * 420 + 2 * 40, 960
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Party, vertical layouts</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700;800&amp;display=swap">
<style>body{{margin:0}} .stack > * + * {{ margin-top: 10px }}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5">A full party of four on a quest with six objectives, in the tracker's real width (260), then a ready quest, then the quest page. Garra and Brakka on it, Mirandel too low, Olen done it already.</div>
<div style="display:flex;gap:40px;align-items:flex-start">{"".join(f'<div class="stack" style="display:flex;flex-direction:column;gap:10px">{c}</div>' for c in [A, B, C])}</div>
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
open(os.path.join(OUT, "PartyVertical.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
