"""A Design-board artboard: the party on quests with nothing to count - deliveries, escorts, explore."""
import os, sys, base64
OUT, PORTRAITS = sys.argv[1], sys.argv[2]
def uri(name):
    return "data:image/png;base64," + base64.b64encode(open(f"{PORTRAITS}/{name}.png", "rb").read()).decode()
GOLD, TAN, GREEN, GREY, RED = "#ffd100", "#c8b48a", "#7ce07c", "#8a8578", "#ff5a4a"
# state: ready / going / done / can / cannot / unknown
BADGES = {
    "ready": ("✓", GREEN, "ready", "#2f7a2f"),
    "going": ("…", "#e8e2d0", "not yet", "#5a4526"),
    "done": ("✓", GREEN, "done", "#2f7a2f"),
    "can": ("!", GOLD, "can take", "#8a5a00"),
    "cannot": ("✕", RED, "lvl 10", "#a33224"),
    "unknown": ("?", "#bbb", "?", "#7a6a4a"),
}
ON_QUEST = ("ready", "going")
DELIVERY = {"title": "[12] Report to Sergra", "line": "Turn in to Sergra Darkthorn", "party": [
    ("Garra Windmane", "GW", "male-tauren", "#aad372", "ready"),
    ("Brakka Thunderhoof", "BT", "female-orc", "#c69b6d", "done"),
    ("Mirandel Ashvale", "MA", "female-scourge", "#ffffff", "can"),
    ("Olen Rusk", "OR", "male-troll", "#3fc7eb", "unknown")]}
ESCORT = {"title": "[16] Free From the Hold", "line": "Keep Gilthares alive to Ratchet", "party": [
    ("Garra Windmane", "GW", "male-tauren", "#aad372", "ready"),
    ("Brakka Thunderhoof", "BT", "female-orc", "#c69b6d", "going"),
    ("Mirandel Ashvale", "MA", "female-scourge", "#ffffff", "cannot"),
    ("Olen Rusk", "OR", "male-troll", "#3fc7eb", "going")]}

def portrait(state, image, size, light):
    on = state in ON_QUEST
    filt = "" if on else "filter:grayscale(1) brightness(.8);"
    ring = "#c9a227" if on else "#6b6450"
    face = (f'<span style="position:relative;display:inline-block;width:{size}px;height:{size}px;border-radius:50%;'
            f'background:#000 url({uri(image)}) center/112% no-repeat;{filt}box-shadow:0 0 0 2px {ring},0 0 0 3px #000"></span>')
    if state == "going":
        return face
    glyph, color, _, _ = BADGES[state]
    b = max(12, round(size * 0.5))
    tag = (f'<span style="position:absolute;right:{-size * 0.2:.0f}px;bottom:{-size * 0.1:.0f}px;width:{b}px;height:{b}px;border-radius:50%;background:#1a140b;'
           f'box-shadow:0 0 0 1.5px {color},0 0 0 2.5px #000;display:flex;align-items:center;justify-content:center;font:800 {b * 0.62:.0f}px/1 \'Source Sans 3\';color:{color}">{glyph}</span>')
    return f'<span style="position:relative;display:inline-block">{face}{tag}</span>'

def head(member, col, size, light):
    name, short, image, color, state = member
    on = state in ON_QUEST
    text = (color if on else GREY) if light else ("#2b1d0e" if on else "#8a7a5a")
    return (f'<div style="display:flex;flex-direction:column;align-items:center;gap:4px;width:{col}px">{portrait(state, image, size, light)}'
            f'<span style="font:700 11px/1.1 \'Source Sans 3\';color:{text}">{short}</span></div>')

def cell(state, col, light):
    glyph, color, word, ink = BADGES[state]
    c = color if light else ink
    if state == "going":
        c = "#e8e2d0" if light else "#5a4526"
    return f'<span style="width:{col}px;text-align:center;font-size:11.5px;color:{c};white-space:nowrap">{word}</span>'

def frame_dark(title, inner, width=340):
    t = (f'<div style="display:flex;align-items:center;gap:6px;margin-bottom:2px"><span style="width:14px;height:14px;border-radius:50%;background:radial-gradient(circle at 38% 32%,#ffe58a,#e3b23c 55%,#9c6a12);border:1px solid #5a3a08"></span>'
         f'<span style="color:#fff">{title}</span></div>')
    return (f'<div style="width:{width}px;background:rgba(0,0,0,.55);border-radius:4px;padding:8px 8px 10px;font:13px/1.35 \'Source Sans 3\';color:#e8e2d0">{t}{inner}</div>')

def frame_page(inner, width=420):
    return (f'<div style="width:{width}px;background:linear-gradient(#e9d7ad,#d9c391);border-radius:3px;padding:12px 14px;font:13px/1.4 \'Source Sans 3\';color:#2b1d0e;box-shadow:inset 0 0 18px rgba(80,50,10,.35)">'
            f'<div style="font:400 17px Marcellus,Georgia;color:#3a2400;margin-bottom:6px">Party</div>{inner}</div>')

def one_row(quest, light, mine):
    col, size = (40, 22) if light else (52, 30)
    heads = "".join(head(m, col, size, light) for m in quest["party"])
    you = f'<span style="width:44px;text-align:right;margin-right:4px;font-size:10.5px;font-weight:600;color:{TAN if light else "#2b1d0e"}">you</span>'
    header = f'<div style="display:flex;align-items:flex-end;margin:2px 0 4px"><span style="flex:1"></span>{you}{heads}</div>'
    cells = "".join(cell(m[4], col, light) for m in quest["party"])
    mine_glyph = (f'<span style="width:44px;text-align:right;margin-right:4px;font-size:11.5px;color:{(GREEN if light else "#2f7a2f") if mine else ("#e8e2d0" if light else "#5a4526")}">{"ready" if mine else "not yet"}</span>')
    rule = "" if light else "border-top:1px solid rgba(90,60,20,.15);"
    row = (f'<div style="display:flex;font-size:12px;line-height:19px;{rule}"><span style="flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{quest["line"]}</span>{mine_glyph}{cells}</div>')
    return header + row

def faces_only(quest, light):
    size = 22 if light else 30
    faces = ""
    for m in quest["party"]:
        name, short, image, color, state = m
        _, c, word, ink = BADGES[state]
        text = (color if state in ON_QUEST else GREY) if light else ("#2b1d0e" if state in ON_QUEST else "#8a7a5a")
        wcol = (c if light else ink) if state != "going" else ("#cfc8b0" if light else "#5a4526")
        faces += (f'<div style="display:flex;flex-direction:column;align-items:center;gap:3px;width:{56 if light else 72}px">{portrait(state, image, size, light)}'
                  f'<span style="font:700 11px/1.1 \'Source Sans 3\';color:{text}">{short}</span><span style="font:600 10.5px/1 \'Source Sans 3\';color:{wcol}">{word}</span></div>')
    line = f'<div style="font-size:12px;margin:2px 0 6px;padding-left:{20 if light else 0}px;color:{"#e8e2d0" if light else "#2b1d0e"}">{quest["line"]}</div>' if light else ""
    return line + f'<div style="display:flex;gap:2px;justify-content:{"flex-end" if light else "flex-start"}">{faces}</div>'

def tracker_line(quest):
    return f'<div style="padding-left:20px;font-size:12px;color:#7ce07c">{quest["line"]}</div>'

def col(title, text, pictures, recommended=False):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if recommended else ""
    return (f'<div style="display:flex;flex-direction:column;gap:12px;width:440px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:36px">{text}</div>{pictures}</div>')

a = (frame_dark(DELIVERY["title"], one_row(DELIVERY, True, True)) + frame_dark(ESCORT["title"], one_row(ESCORT, True, False))
     + frame_page(one_row(DELIVERY, False, True)) + frame_page(one_row(ESCORT, False, False)))
b = (frame_dark(DELIVERY["title"], faces_only(DELIVERY, True)) + frame_dark(ESCORT["title"], faces_only(ESCORT, True))
     + frame_page(faces_only(DELIVERY, False)) + frame_page(faces_only(ESCORT, False)))
legend_items = [("ready", "On it and ready to turn in (nothing to do, or the escort/explore done)"),
                ("going", "On it, not done yet: the escort or exploring still ahead"),
                ("done", "Done it already (their OneMoreQuest)"), ("can", "Can take it"), ("cannot", "Can't have it; why on hover"),
                ("unknown", "Not on it; the rest unknown (no OneMoreQuest)")]
legend = ""
for state, text in legend_items:
    glyph, color, word, _ = BADGES[state]
    legend += f'<div style="display:flex;gap:8px;font-size:12px;color:#d8cfa8"><span style="width:52px;color:{color};font-weight:700">{word}</span>{text}</div>'
cols = (col("A. One row, a cell each", "The same table as quests with counts, with a single row: the turn-in or the event. Each member's cell says ready, not yet, or why they are not on it.", a, True)
        + col("B. Portraits only", "No table at all: the portraits in a row, each with its state under the initials. Lighter, but looks different from quests with counts.", b)
        + col("States", "The \"not on it\" states are the ones for quests with counts. Ready or not yet comes from the game's own party lines, or their OneMoreQuest / Questie.",
              f'<div style="display:flex;flex-direction:column;gap:7px">{legend}</div>'))
width, height = 30 * 2 + 3 * 440 + 2 * 40, 820
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Party on quests without counts</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700;800&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5">Quests with nothing to count: a delivery (talk to someone and turn in) and an escort. In the tracker and on the quest page.</div>
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
open(os.path.join(OUT, "PartySimple.dc.html"), "w", encoding="utf-8").write(board.replace('</div><div style="width:420px', '</div><div style="height:10px"></div><div style="width:420px').replace('</div><div style="width:340px', '</div><div style="height:10px"></div><div style="width:340px'))
print("ok", width, height)
