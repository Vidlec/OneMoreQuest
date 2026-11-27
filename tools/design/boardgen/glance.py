"""A Design-board artboard: the chronicle's At a glance page, redesigned with the days' ledger."""
import os, sys
OUT = sys.argv[1]
# The chronicle mockups' pieces (window, headings, coins, tiles, bars)
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "chronicle2.py")).read().split("# ---- The day's numbers")[0].replace("OUT = sys.argv[1]", ""))

CH = ["At a glance", "Days", "Journal", "Zones", "Kills & luck"]
WEEK = [("Wed", 6, 18400, 12600, 0.8), ("Thu", 11, 41200, 30100, 1.9), ("Fri", 0, 0, 0, 0), ("Sat", 19, 91300, 48200, 3.6),
        ("Sun", 14, 52100, 39800, 2.4), ("Mon", 9, 26600, 21000, 1.4), ("Today", 11, 91300, 42820, 2.85)]

def bars(values, color, height=54, labels=True, highlight_last=True, fmt=str, isShort=False):
    top = max(v for v in values) or 1
    out = ""
    for i, v in enumerate(values):
        h = max(2, round(height * v / top)) if v else 2
        last = highlight_last and i == len(values) - 1
        out += (f'<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;gap:2px">'
                f'<span style="font-size:10.5px;color:#5a4526">{fmt(v) if v else ""}</span>'
                f'<span style="width:70%;height:{h}px;border-radius:2px 2px 0 0;background:{color};{"box-shadow:0 0 0 1.5px #3a2400;" if last else "opacity:.8;"}"></span></div>')
    lab = "".join(f'<span style="flex:1;text-align:center;font-size:10.5px;color:{"#3a2400" if i == len(WEEK) - 1 else "#7a6a4a"};font-weight:{700 if i == len(WEEK) - 1 else 400}">{(d[0][0] if d[0] != "Today" else "T") if isShort else d[0]}</span>' for i, d in enumerate(WEEK)) if labels else ""
    return (f'<div style="display:flex;align-items:flex-end;height:{height + 16}px;border-bottom:1.5px solid rgba(90,60,20,.5)">{out}</div>'
            f'<div style="display:flex;margin-top:2px">{lab}</div>')

def gk(v):
    return f"{v // 10000}g" if v >= 10000 else (f"{v // 100}s" if v else "")

def strip(cells):
    out = ""
    for icon, value, label in cells:
        out += (f'<div style="display:flex;gap:7px;align-items:center;flex:1;min-width:0"><span style="width:30px;height:30px;border-radius:4px;flex:none;background:{icon};box-shadow:inset 0 0 0 1px #000,inset 0 0 6px #0008"></span>'
                f'<div style="min-width:0"><div style="font:600 15px \'Source Sans 3\';color:#fff;white-space:nowrap">{value}</div><div style="font-size:11px;color:#d8c9a0">{label}</div></div></div>')
    rows = [cells[i:i + 3] for i in range(0, len(cells), 3)]
    html = ""
    for r in rows:
        html += '<div style="display:flex;gap:10px;padding:6px 8px">' + "".join(
            f'<div style="display:flex;gap:7px;align-items:center;flex:1;min-width:0"><span style="width:30px;height:30px;border-radius:4px;flex:none;background:{icon};box-shadow:inset 0 0 0 1px #000,inset 0 0 6px #0008"></span>'
            f'<div style="min-width:0"><div style="font:600 15px \'Source Sans 3\';color:#fff;white-space:nowrap">{value}</div><div style="font-size:11px;color:#d8c9a0">{label}</div></div></div>' for icon, value, label in r) + '</div>'
    return f'<div style="background:linear-gradient(#3a2614,#24170b);border:1px solid #000;box-shadow:inset 0 0 0 1px #6b4a26;border-radius:3px;margin:4px 0 6px">{html}</div>'

GOLDI, XPI, QI, TI, KI, LI = "linear-gradient(135deg,#f6d36b,#a8741a)", "linear-gradient(135deg,#c86cff,#5a1a8a)", "linear-gradient(135deg,#efe2c0,#a8946a)", "linear-gradient(135deg,#e8c66a,#6a4a1a)", "linear-gradient(135deg,#d0603a,#4a1a0a)", "linear-gradient(135deg,#7ab0ff,#1a3a7a)"

def level_bar(level=30, share=0.42, rested=0.18):
    return (f'<div style="display:flex;align-items:center;gap:8px;margin:2px 0 8px"><span style="font:400 18px Marcellus,Georgia;color:#3a2400">{level}</span>'
            f'<div style="flex:1;height:12px;border-radius:2px;background:rgba(60,40,10,.25);box-shadow:0 0 0 1px rgba(60,40,10,.5);position:relative;overflow:hidden">'
            f'<span style="position:absolute;left:0;top:0;bottom:0;width:{share * 100}%;background:linear-gradient(#b05cf0,#6a2aa0)"></span>'
            f'<span style="position:absolute;left:{share * 100}%;top:0;bottom:0;width:{rested * 100}%;background:rgba(70,120,230,.55)"></span></div>'
            f'<span style="font:400 18px Marcellus,Georgia;color:#a89470">{level + 1}</span></div>'
            f'<div style="font-size:11.5px;color:#5a4526;margin-top:-6px;margin-bottom:6px">42% of level 30 · rested to 60% · next level in about 1 h 32 m at this week\'s pace</div>')

def records(n=6):
    recs = [("Best day for gold", coins(91300), "Sat"), ("Best day for experience", "48,200", "Sat"), ("Fastest level", "22 in 58 m", "Thu 12 Nov"),
            ("Most quests in a day", "19", "Sat"), ("Luckiest drop", item("Elder's Mantle", "blue"), "1.2%"), ("Days in a row", "6", "now")]
    return "".join(row(a, f'{b} <span style="color:#7a6a4a;font-size:11px">{c}</span>') for a, b, c in recs[:n])

# A: the dashboard - totals, the week as three small charts, records
def glance_a():
    p = h1("Vidler, level 30", "kept since 12 Nov · 31 h played over 9 days")
    p += level_bar()
    p += strip([(QI, "312", "Quests done"), (GOLDI, coins(342100, 13, "#fff"), "Gold earned, net"), (XPI, "412,600", "Experience"),
                (TI, "31 h 12 m", "Time played"), (KI, "2,914", "Kills"), (LI, "+8%", "Luck with drops")])
    p += h2("The last seven days", "quests · gold · experience")
    p += '<div style="display:flex;gap:14px">'
    for title, idx, col, fmt in [("Quests", 1, "#c8a23a", str), ("Gold", 2, "#e0b84a", gk), ("Experience", 3, "#9a5ad0", lambda v: f"{v // 1000}k")]:
        p += f'<div style="flex:1"><div style="font-size:11.5px;color:#5a4526;margin-bottom:2px">{title}</div>{bars([d[idx] for d in WEEK], col, 46, fmt=fmt, isShort=True)}</div>'
    p += '</div>'
    p += h2("Records")
    p += records()
    return window(CH, "At a glance", "", p, width=660, height=640)

# B: today first - today's card, the week with a switch, totals small, records
def glance_b():
    p = h1("Today", "Tuesday 17 November · 2 h 51 m so far")
    p += (f'<div style="display:flex;gap:10px;margin:4px 0 8px">'
          + "".join(f'<div style="flex:1;background:rgba(255,248,225,.5);box-shadow:inset 0 0 0 1px rgba(90,60,20,.3);border-radius:4px;padding:7px 9px">'
                    f'<div style="font-size:11px;color:#5a4526">{l}</div><div style="font:600 16px \'Source Sans 3\'">{v}</div><div style="font-size:11px;color:{c}">{s}</div></div>'
                    for l, v, s, c in [("Gold, net", coins(91300, 13), "▲ 2.2× your average day", "#2f7a2f"), ("Experience", "42,820", "▲ 1.4× average", "#2f7a2f"),
                                       ("Quests", "11", "average 10", "#5a4526"), ("Level", "29 → 30", "next in 1 h 32 m", "#5a4526")])
          + '</div>')
    p += h2("This week", '<span style="background:#3a2400;color:#ffd100;border-radius:3px;padding:1px 6px">Gold</span> <span style="color:#7a6a4a">Experience</span> <span style="color:#7a6a4a">Quests</span> <span style="color:#7a6a4a">Time</span>')
    p += bars([d[2] for d in WEEK], "#e0b84a", 70, fmt=gk)
    p += h2("Since 12 November", "9 days, 31 h")
    p += row("Quests done", "312 · 10 an hour")
    p += row("Gold earned, net", coins(342100) + ' <span style="color:#7a6a4a;font-size:11px">· 1g 10s an hour</span>')
    p += row("Experience", "412,600 · 13,200 an hour")
    p += row("Kills · luck with drops", "2,914 · +8%")
    p += h2("Records")
    p += records(4)
    return window(CH, "At a glance", "", p, width=660, height=640)

# C: the road so far - levels as a journey, then the totals and records
def glance_c():
    p = h1("The road so far", "level 30 · 31 h played since 12 Nov")
    levels = [(22, 58), (23, 74), (24, 81), (25, 77), (26, 96), (27, 108), (28, 91), (29, 130), (30, 112)]
    top = max(m for _, m in levels)
    p += '<div style="display:flex;align-items:flex-end;gap:3px;height:96px;border-bottom:1.5px solid rgba(90,60,20,.5);margin-top:6px">'
    for lv, m in levels:
        h = round(78 * m / top)
        p += (f'<div style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:flex-end;gap:2px"><span style="font-size:10px;color:#5a4526">{m // 60}h{m % 60:02d}</span>'
              f'<span style="width:80%;height:{h}px;border-radius:2px 2px 0 0;background:{"linear-gradient(#b05cf0,#6a2aa0)" if lv != 30 else "repeating-linear-gradient(45deg,#b05cf0 0 4px,#8a4ac0 4px 8px)"}"></span></div>')
    p += '</div><div style="display:flex;gap:3px">' + "".join(f'<span style="flex:1;text-align:center;font-size:10.5px;color:#5a4526">{lv}</span>' for lv, _ in levels) + '</div>'
    p += '<div style="font-size:11.5px;color:#5a4526;margin:4px 0">Time played at each level; level 30 is under way (42%)</div>'
    p += h2("Altogether")
    p += strip([(QI, "312", "Quests done"), (GOLDI, coins(342100, 13, "#fff"), "Gold earned, net"), (XPI, "412,600", "Experience"),
                (TI, "31 h 12 m", "Time played"), (KI, "2,914", "Kills"), (LI, "+8%", "Luck with drops")])
    p += h2("Where the gold came from", "all days")
    p += stacked([("Vendors", 152000, "#b08a5a", "15g"), ("Coins", 101000, "#c8a23a", "10g"), ("Quests", 88000, "#7aa35a", "8g"), ("Auctions", 61000, "#6a8bb0", "6g")], 402000, 10)
    p += h2("Records")
    p += records(4)
    return window(CH, "At a glance", "", p, width=660, height=700)

def col(title, text, pic, rec=False):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if rec else ""
    return (f'<div style="display:flex;flex-direction:column;gap:10px;width:660px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:52px">{text}</div>{pic}</div>')

cols = (col("A. Dashboard", "Your level and how far to the next (rested part in blue); all-time totals on the wood strip (now with gold and every kill, from the ledger); the last seven days as three small charts side by side; records.", glance_a(), True)
        + col("B. Today first", "Today's numbers against your average day, then the week as one chart with a switch (gold, experience, quests, time), the totals since the chronicle began as lines with an hour's worth, and the top records.", glance_b())
        + col("C. The road so far", "The levels as a journey: time played at each, the current one under way; then the totals, where all the gold came from, and records.", glance_c()))
width, height = 30 * 2 + 3 * 660 + 2 * 40, 900
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Chronicle at a glance</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5">The chronicle's first page, redone with the days' ledger: gold and experience from every source, not quest rewards alone. Today the page has six totals, quests a day and records. Numbers are examples.</div>
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
open(os.path.join(OUT, "ChronicleGlance.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
