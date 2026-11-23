"""A Design-board artboard: the party in the tracker and on the quest page."""
import os, sys
OUT = sys.argv[1]

# Up to four others: one without the quest, one done, one whose progress is not known (no addon, out of range)
ME = {"name": "You", "short": "Y", "color": "#ffffff"}
PARTY = [
    {"name": "Garra", "short": "GA", "color": "#aad372", "has": True, "counts": [4, 7, 1, 0, 3, 2]},
    {"name": "Brakka Stone", "short": "BS", "color": "#c69b6d", "has": True, "counts": [7, 10, 2, 1, 5, 6]},
    {"name": "Mira Dawnfield", "short": "MD", "color": "#ffffff", "has": False, "counts": None},
    {"name": "Olen Rusk", "short": "OR", "color": "#3fc7eb", "has": True, "counts": None},
]
OBJECTIVES = [("Plainstrider Beak", 7), ("Zhevra Hoof", 10), ("Kolkar Leader slain", 2), ("Barak's Head", 1), ("Centaur Bracers", 5), ("Raptor Head", 6)]
MINE = [3, 10, 0, 0, 5, 1]
GOLD, TAN, AMBER, GREEN, GREY = "#ffd100", "#c8b48a", "#ffb84d", "#7ce07c", "#8a8578"

def count_text(count, required):
    if count is None:
        return f'<span style="color:{GREY}">?</span>'
    if count >= required:
        return f'<span style="color:{GREEN}">✓</span>'
    return f'<span>{count}</span>'

def dot(member, size=9, hollow=False):
    if hollow:
        return f'<span title="{member["name"]}" style="display:inline-block;width:{size}px;height:{size}px;border-radius:50%;box-sizing:border-box;border:1.5px solid {member["color"]};opacity:.55"></span>'
    return f'<span title="{member["name"]}" style="display:inline-block;width:{size}px;height:{size}px;border-radius:50%;background:{member["color"]};box-shadow:0 0 0 1px #000"></span>'

def badge(member, size=18):
    style = f"border:1.5px solid {member['color']};color:{member['color']}" if member.get("has", True) else f"border:1.5px dashed {GREY};color:{GREY}"
    return f'<span title="{member["name"]}" style="display:inline-flex;align-items:center;justify-content:center;width:{size}px;height:{size}px;border-radius:50%;background:#1a140b;{style};font:700 {size * 0.45:.0f}px/1 \'Source Sans 3\'">{member["short"]}</span>'

# --- Tracker ----------------------------------------------------------------------------------------------------
def tracker_frame(inner, width=250):
    return (f'<div style="width:{width}px;background:rgba(0,0,0,.55);border-radius:4px;padding:8px 8px 10px;font:13px/1.35 \'Source Sans 3\';color:#e8e2d0">'
            f'<div style="display:flex;justify-content:space-between;border-bottom:1px solid #6b5a2e;padding-bottom:3px;margin-bottom:6px">'
            f'<span style="font:400 13px Marcellus,Georgia;color:{GOLD}">Quests</span><span style="color:{TAN}">The Barrens</span></div>{inner}</div>')

def tracker_title(extra=""):
    return (f'<div style="display:flex;align-items:center;gap:6px"><span style="width:14px;height:14px;border-radius:50%;background:radial-gradient(circle at 38% 32%,#ffe58a,#e3b23c 55%,#9c6a12);border:1px solid #5a3a08;flex:none"></span>'
            f'<span style="color:#fff;flex:1">[14] Centaur and Beast</span>{extra}</div>')

def tracker_now():
    lines = "".join(f'<div style="padding-left:20px;font-size:12px"><span style="color:{GOLD}">{i + 1}</span> {name} {MINE[i]}/{req}</div>' for i, (name, req) in enumerate(OBJECTIVES))
    header = f'<div style="padding-left:20px;font-size:12px;color:{TAN};display:flex"><span style="width:84px">Party</span>' + "".join(f'<span style="width:24px;text-align:right;color:{GOLD}">{i + 1}</span>' for i in range(6)) + '</div>'
    rows = ""
    for m in PARTY:
        cells = (f'<span style="color:{AMBER}">does not have it</span>' if not m["has"] else
                 "".join(f'<span style="width:24px;text-align:right">{count_text(m["counts"][i] if m["counts"] else None, OBJECTIVES[i][1])}</span>' for i in range(6)))
        rows += f'<div style="padding-left:20px;font-size:12px;display:flex"><span style="width:84px;color:{m["color"]};white-space:nowrap;overflow:hidden">{m["name"]}</span>{cells}</div>'
    extra = f'<span style="color:{TAN};font-size:11px">GA BS OR</span>'
    return tracker_frame(tracker_title(extra) + lines + '<div style="height:4px"></div>' + header + rows)

def tracker_dots():
    dots = "".join(dot(m, 8, hollow=not m["has"]) for m in PARTY)
    lines = ""
    for i, (name, req) in enumerate(OBJECTIVES):
        # behind: who of the party still needs this objective
        need = [m for m in PARTY if m["has"] and m["counts"] and m["counts"][i] < req]
        mark = "".join(dot(m, 6) for m in need)
        lines += f'<div style="padding-left:20px;font-size:12px;display:flex;align-items:center;gap:6px"><span style="flex:1">{name} {MINE[i]}/{req}</span><span style="display:flex;gap:2px">{mark}</span></div>'
    tip = (f'<div style="margin-top:8px;background:#0b0b0b;border:1px solid #555;border-radius:3px;padding:6px 8px;font-size:11.5px;color:#ddd">'
           f'<div style="color:{GOLD}">Hover a dot or the quest</div>'
           + "".join(f'<div><span style="color:{m["color"]}">{m["name"]}</span> · ' + ("does not have it" if not m["has"] else ("progress unknown" if not m["counts"] else f'{sum(1 for i, c in enumerate(m["counts"]) if c >= OBJECTIVES[i][1])}/6 done')) + '</div>' for m in PARTY) + '</div>')
    return tracker_frame(tracker_title(f'<span style="display:flex;gap:3px">{dots}</span>') + lines) + tip

def tracker_inline():
    lines = ""
    for i, (name, req) in enumerate(OBJECTIVES):
        others = " ".join(f'<span style="color:{m["color"]}">{count_text(m["counts"][i], req) if m["counts"] else count_text(None, req)}</span>' for m in PARTY if m["has"])
        lines += (f'<div style="padding-left:20px;font-size:12px;display:flex"><span style="flex:1;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{name}</span>'
                  f'<span style="width:34px;text-align:right">{MINE[i]}/{req}</span><span style="width:58px;text-align:right;font-size:11px">{others}</span></div>')
    head = (f'<div style="padding-left:20px;font-size:10.5px;color:{TAN};display:flex"><span style="flex:1"></span><span style="width:34px;text-align:right">you</span>'
            f'<span style="width:58px;text-align:right">' + " ".join(f'<span style="color:{m["color"]}">{m["short"]}</span>' for m in PARTY if m["has"]) + '</span></div>')
    return tracker_frame(tracker_title(f'<span style="display:flex;gap:3px">{"".join(dot(m, 8, hollow=not m["has"]) for m in PARTY)}</span>') + head + lines)

def tracker_bars():
    lines = ""
    for i, (name, req) in enumerate(OBJECTIVES):
        bars = ""
        for m in [dict(ME, counts=MINE, has=True)] + [m for m in PARTY if m["has"]]:
            if m["counts"] is None:
                bars += f'<div title="{m["name"]}: unknown" style="flex:1;height:3px;background:repeating-linear-gradient(90deg,#555 0 3px,transparent 3px 5px)"></div>'
            else:
                share = min(1, m["counts"][i] / req)
                bars += f'<div title="{m["name"]}" style="flex:1;height:3px;background:#2a2620"><div style="width:{share * 100:.0f}%;height:100%;background:{m["color"]}"></div></div>'
        lines += (f'<div style="padding-left:20px;font-size:12px"><div style="display:flex"><span style="flex:1">{name}</span><span>{MINE[i]}/{req}</span></div>'
                  f'<div style="display:flex;gap:2px;margin:1px 0 3px">{bars}</div></div>')
    return tracker_frame(tracker_title(f'<span style="display:flex;gap:3px">{"".join(dot(m, 8, hollow=not m["has"]) for m in PARTY)}</span>') + lines)

# --- Quest page -------------------------------------------------------------------------------------------------
def page_frame(inner, width=320):
    return (f'<div style="width:{width}px;background:linear-gradient(#e9d7ad,#d9c391);border-radius:3px;padding:12px 14px;font:13px/1.4 \'Source Sans 3\';color:#2b1d0e;box-shadow:inset 0 0 18px rgba(80,50,10,.35)">'
            f'<div style="font:400 17px Marcellus,Georgia;color:#3a2400;margin-bottom:6px">Party</div>{inner}</div>')

def page_now():
    circles = "".join(badge(m, 20) for m in PARTY if m["has"])
    body = f'<div style="display:flex;gap:4px;margin-bottom:8px">{circles}</div><div style="font-weight:600">Also in The Barrens</div>'
    for m in PARTY:
        if m["has"] and m["counts"]:
            body += f'<div>{m["name"]}</div>' + "".join(f'<div style="padding-left:8px">- {m["counts"][i]}/{req} {name}</div>' for i, (name, req) in enumerate(OBJECTIVES))
    return page_frame(body)

def page_table():
    members = [m for m in PARTY]
    head = '<tr><th></th><th style="text-align:right;padding:0 4px;font-weight:600">You</th>' + "".join(
        f'<th style="padding:0 2px">{badge(m, 22)}</th>' for m in members) + '</tr>'
    rows = ""
    for i, (name, req) in enumerate(OBJECTIVES):
        cells = ""
        for m in members:
            if not m["has"]:
                cells += f'<td style="text-align:center;color:#9a8b6a">–</td>'
            else:
                c = m["counts"][i] if m["counts"] else None
                cells += f'<td style="text-align:center">{count_text(c, req).replace(GREEN, "#2f8a2f").replace(GREY, "#9a8b6a")}</td>'
        rows += (f'<tr><td style="padding:1px 0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:130px">{name}</td>'
                 f'<td style="text-align:right;padding:0 4px">{MINE[i]}/{req}</td>{cells}</tr>')
    legend = '<div style="font-size:11px;color:#6b5636;margin-top:6px">– does not have it · ? not shared (no addon) · ✓ done. Hover a circle for the name.</div>'
    return page_frame(f'<table style="border-collapse:collapse;width:100%;font-size:12.5px">{head}{rows}</table>{legend}')

def page_bars():
    body = '<div style="display:flex;gap:4px;margin-bottom:8px">' + "".join(badge(m, 20) for m in PARTY) + '</div>'
    for i, (name, req) in enumerate(OBJECTIVES):
        bars = ""
        for m in [dict(ME, color="#3a2400", counts=MINE, has=True)] + PARTY:
            if not m["has"]:
                continue
            if m["counts"] is None:
                bars += f'<div title="{m["name"]}: not shared" style="height:4px;margin-top:2px;background:repeating-linear-gradient(90deg,#a89470 0 3px,transparent 3px 6px)"></div>'
            else:
                share = min(1, m["counts"][i] / req)
                col = "#3a2400" if m is not None and m.get("short") == "Y" else m["color"]
                bars += f'<div title="{m["name"]}" style="height:4px;margin-top:2px;background:rgba(60,40,10,.18)"><div style="width:{share * 100:.0f}%;height:100%;background:{col};box-shadow:0 0 0 .5px rgba(0,0,0,.4)"></div></div>'
        body += f'<div style="margin-bottom:6px"><div style="display:flex;font-size:12.5px"><span style="flex:1">{name}</span><span>{MINE[i]}/{req}</span></div>{bars}</div>'
    return page_frame(body)

def page_cards():
    body = ""
    for m in PARTY:
        if not m["has"]:
            status, bar = f'<span style="color:#8a5a10">does not have it</span>', ""
        elif not m["counts"]:
            status, bar = f'<span style="color:#7a6a4a">progress not shared</span>', ""
        else:
            done = sum(1 for i, c in enumerate(m["counts"]) if c >= OBJECTIVES[i][1])
            total = sum(min(c, OBJECTIVES[i][1]) for i, c in enumerate(m["counts"])) / sum(r for _, r in OBJECTIVES)
            status = f'{done} of 6 done'
            bar = f'<div style="height:4px;background:rgba(60,40,10,.2);margin-top:3px"><div style="width:{total * 100:.0f}%;height:100%;background:{m["color"]};box-shadow:0 0 0 .5px rgba(0,0,0,.5)"></div></div>'
            behind = [OBJECTIVES[i][0] + f' {c}/{OBJECTIVES[i][1]}' for i, c in enumerate(m["counts"]) if c < OBJECTIVES[i][1]]
            bar += (f'<div style="font-size:11px;color:#5a4526;margin-top:2px">still: ' + ", ".join(behind[:3]) + (" …" if len(behind) > 3 else "") + '</div>') if behind else '<div style="font-size:11px;color:#2f8a2f;margin-top:2px">ready to turn in</div>'
        body += (f'<div style="display:flex;gap:8px;align-items:flex-start;padding:5px 0;border-bottom:1px solid rgba(90,60,20,.2)">{badge(m, 24)}'
                 f'<div style="flex:1"><div style="display:flex;justify-content:space-between"><b style="color:#2b1d0e">{m["name"]}</b><span style="font-size:12px">{status}</span></div>{bar}</div></div>')
    return page_frame(body)

TRACKER = [
    ("Now", "Initials after the title; under the quest in focus a table with a numbered column per objective. Cryptic past three objectives; long names are cut.", tracker_now(), False),
    ("A. Dots, who needs what", "A dot per member after the title (hollow: does not have it). Each objective shows the dots of members still short of it; the tooltip names them and their progress.", tracker_dots(), False),
    ("B. Their counts beside yours", "Each objective with your count, then each member's in their class colour (✓ done, ? not shared). Exact at a glance, one line per objective however many.", tracker_inline(), True),
    ("C. A bar each", "Under each objective a thin bar per member in their class colour, yours first; dashed: not shared. Who is behind shows at a glance; numbers on hover.", tracker_bars(), False),
]
PAGE = [
    ("Now", "Initials in circles by \"To do\", then the game's lines member by member: long with six objectives and four members.", page_now(), False),
    ("A. Table", "Objectives down, you and each member across under their circle: every count at once, a dash for not having it, ? when not shared.", page_table(), True),
    ("B. Bars per objective", "Each objective with a bar for you and each member in their class colour: who is behind on what, at a glance.", page_bars(), False),
    ("C. Member cards", "A card per member: has it or not, how far overall, and what is still left. Reads person by person.", page_cards(), False),
]

def section(title, items, column_width):
    cells = ""
    for name, text, picture, recommended in items:
        flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if recommended else ""
        flag += ' <span style="font:600 10px/1 \'Source Sans 3\';color:#d8cfa8;border:1px solid #6b6450;border-radius:3px;padding:1px 5px;margin-left:6px">Now</span>' if name == "Now" else ""
        cells += (f'<div style="display:flex;flex-direction:column;gap:8px;width:{column_width}px"><div style="font:400 17px/1.2 Marcellus,Georgia,serif;color:#ffd100">{name}{flag}</div>'
                  f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:52px">{text}</div>{picture}</div>')
    return (f'<div style="font:400 22px Marcellus,Georgia;color:#f0e2b6;margin:6px 0 2px">{title}</div>'
            f'<div style="display:flex;gap:28px;align-items:flex-start">{cells}</div>')

width, height = 30 * 2 + 4 * 340 + 3 * 28, 1420
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Party in tracker and log</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5">One quest with six objectives (kills and items), a party of four others: <span style="color:#aad372">Garra</span> part way, <span style="color:#c69b6d">Brakka Stone</span> nearly done, Mira Dawnfield without the quest, <span style="color:#3fc7eb">Olen Rusk</span> with it but not sharing progress (no addon). Pick one for the tracker and one for the quest page.</div>
{section("Tracker", TRACKER, 340)}
{section("Quest page", PAGE, 340)}
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
open(os.path.join(OUT, "PartyViews.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
