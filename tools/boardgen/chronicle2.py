"""A Design-board artboard: chronicle improvements - a Days chapter (three layouts) and the other ideas."""
import os, sys
OUT = sys.argv[1]
GOLD, TAN, INK, SOFT, GREEN, RED = "#ffd100", "#c8b48a", "#2b1d0e", "#5a4526", "#2f7a2f", "#a33224"
QUALITY = {"green": "#1eff00", "blue": "#0070dd", "purple": "#a335ee", "white": "#ffffff"}

def coins(copper, size=11, color=INK):
    g, s, c = copper // 10000, (copper // 100) % 100, copper % 100
    def coin(n, col):
        return f'{n}<span style="display:inline-block;width:{size - 2}px;height:{size - 2}px;border-radius:50%;background:radial-gradient(circle at 35% 30%,#fff8,{col} 60%);box-shadow:0 0 0 .5px #0006;margin:0 3px 0 2px;vertical-align:-1px"></span>'
    parts = []
    if g: parts.append(coin(g, "#e8b923"))
    if s or g: parts.append(coin(s, "#c7c7cf"))
    parts.append(coin(c, "#c0773a"))
    return f'<span style="white-space:nowrap;color:{color}">{"".join(parts)}</span>'

def window(chapters, chosen, list_extra, page_html, width=640, height=None):
    rows = ""
    for name in chapters:
        on = name == chosen
        rows += (f'<div style="display:flex;align-items:center;gap:8px;padding:7px 10px;border-radius:3px;{"background:#3a2f1a;box-shadow:inset 0 0 0 1px #6b5a3a;" if on else ""}">'
                 f'<span style="width:18px;height:18px;border-radius:3px;background:#3d3326;box-shadow:inset 0 0 0 1px #6b5a3a"></span>'
                 f'<span style="font:400 13px Marcellus,Georgia;color:{GOLD if on else "#e8dcc0"}">{name}</span></div>')
    h = f"height:{height}px;" if height else ""
    return (f'<div style="width:{width}px;{h}display:flex;flex-direction:column;background:#16130f;border:2px solid #6b5a3a;border-radius:5px;overflow:hidden">'
            f'<div style="height:28px;display:flex;align-items:center;justify-content:center;background:linear-gradient(#2a2118,#1a1510);border-bottom:1px solid #6b5a3a;font:400 15px Marcellus,Georgia;color:{GOLD}">Chronicle</div>'
            f'<div style="display:flex;flex:1;min-height:0"><div style="width:170px;flex:none;padding:8px;display:flex;flex-direction:column;gap:2px;background:#1c1812;border-right:1px solid #3a3022">{rows}{list_extra}</div>'
            f'<div style="flex:1;padding:14px 16px;background:linear-gradient(#e9d7ad,#d9c391);box-shadow:inset 0 0 22px rgba(80,50,10,.35);font:13px/1.4 \'Source Sans 3\';color:{INK};overflow:hidden">{page_html}</div></div></div>')

CHAPTERS = ["At a glance", "Days", "Journal", "Zones", "Kills & luck"]

def h1(text, note=""):
    n = f'<span style="font:12px \'Source Sans 3\';color:{SOFT};margin-left:8px">{note}</span>' if note else ""
    return f'<div style="font:400 20px Marcellus,Georgia;color:#3a2400;margin-bottom:6px">{text}{n}</div>'

def h2(text, right=""):
    return (f'<div style="display:flex;align-items:baseline;border-top:1px solid rgba(90,60,20,.55);box-shadow:0 1px 0 rgba(255,245,210,.5) inset;padding-top:6px;margin:10px 0 4px">'
            f'<span style="font:400 15px Marcellus,Georgia;color:#3a2400;flex:1">{text}</span><span style="font-size:12px">{right}</span></div>')

def row(label, value, sub="", color=INK, indent=0):
    s = f'<span style="color:{SOFT};font-size:11.5px;margin-left:6px">{sub}</span>' if sub else ""
    return f'<div style="display:flex;padding-left:{indent}px;font-size:12.5px;line-height:19px"><span style="flex:1;color:{color}">{label}{s}</span><span>{value}</span></div>'

def tiles(items):
    out = ""
    for label, value in items:
        out += (f'<div style="flex:1;background:rgba(255,248,225,.45);box-shadow:inset 0 0 0 1px rgba(90,60,20,.25);border-radius:4px;padding:6px 8px">'
                f'<div style="font-size:11px;color:{SOFT}">{label}</div><div style="font:600 15px \'Source Sans 3\'">{value}</div></div>')
    return f'<div style="display:flex;gap:6px;margin:4px 0 2px">{out}</div>'

def item(name, quality, note=""):
    return f'<span style="color:{QUALITY[quality] if quality != "white" else INK};text-shadow:0 0 1px #0008">[{name}]</span>{f"<span style=\"color:{SOFT};font-size:11.5px\"> {note}</span>" if note else ""}'

def stacked(parts, total, height=12):
    legend = "".join(f'<span style="display:inline-flex;align-items:center;gap:4px;margin-right:10px;font-size:11.5px"><span style="width:9px;height:9px;border-radius:2px;background:{c}"></span>{n} <b>{lab}</b></span>' for n, v, c, lab in [(p[0], p[1], p[2], p[3]) for p in parts])
    return (f'<div style="display:flex;height:{height}px;border-radius:3px;overflow:hidden;box-shadow:0 0 0 1px rgba(60,40,10,.45)">{"".join(f"<span style=\"width:{100 * p[1] / total:.1f}%;background:{p[2]}\"></span>" for p in parts)}</div>'
            f'<div style="margin-top:4px;line-height:1.7">{legend}</div>')

# ---- The day's numbers --------------------------------------------------------------------------------
GOLD_IN = [("Coins looted", 21840, "from 214 kills"), ("Quest rewards", 18350, "11 quests"), ("Sold to vendors", 31720, "grey and white loot"),
           ("Auction house", 45000, "2 sales, by mail"), ("Other", 1200, "")]
GOLD_OUT = [("Repairs", 3120, ""), ("Training", 9000, "Frostbolt 5, Arcane Missiles 4"), ("Flights", 1460, "2 flights"), ("Bought", 2400, "water, arrows")]
XP_PARTS = [("Quests", 21400, "11 quests"), ("Kills", 14820, "214 kills"), ("Rested bonus", 5260, "on kills"), ("Discovery", 1340, "3 places")]
income, spend = sum(v for _, v, _ in GOLD_IN), sum(v for _, v, _ in GOLD_OUT)
xp_total = sum(v for _, v, _ in XP_PARTS)

def day_list():
    days = [("Today", "+9g 13s", "+1 level"), ("Yesterday", "+4g 02s", "+2 levels"), ("Sat 14 Nov", "+6g 88s", "+1 level"), ("Fri 13 Nov", "−1g 20s", "")]
    out = '<div style="height:10px"></div><div style="font:600 11px \'Source Sans 3\';color:#b8ad8c;padding:0 6px 4px">DAYS</div>'
    for i, (d, g, l) in enumerate(days):
        out += (f'<div style="padding:5px 8px;border-radius:3px;{"background:#2c2416;" if i == 0 else ""}"><div style="font-size:12.5px;color:{"#fff" if i == 0 else "#e8dcc0"}">{d}</div>'
                f'<div style="font-size:11px;color:#b8ad8c">{g}{" · " + l if l else ""}</div></div>')
    return out

def day_a():
    p = h1("Tuesday, 17 November", "2 h 51 m played · Thousand Needles, The Barrens")
    p += tiles([("Level", "29 → 30"), ("Quests", "11"), ("Gold, net", coins(income - spend, 13)), ("Experience", f"{xp_total:,}")])
    p += h2("Gold", coins(income - spend, 12))
    for n, v, sub in GOLD_IN:
        p += row(n, coins(v), sub)
    p += '<div style="height:3px"></div>'
    for n, v, sub in GOLD_OUT:
        p += row(n, f'<span style="color:{RED}">−</span>' + coins(v, color=RED), sub)
    p += row(f'<span style="color:{SOFT}">Per hour</span>', coins((income - spend) * 60 // 171))
    p += h2("Experience", f'<b>{xp_total:,}</b>')
    for n, v, sub in XP_PARTS:
        p += row(n, f"{v:,}", sub, indent=12 if n == "Rested bonus" else 0)
    p += row(f'<span style="color:{SOFT}">Per hour · next level at this pace</span>', "14,970 · 1 h 32 m")
    p += h2("Chests and gathering", "5")
    p += row("Battered Chest ×2", item("Glimmering Mail Pauldrons", "green"))
    p += row("Copper Vein ×3", "7 Copper Ore")
    p += h2("Notable loot", "3")
    p += row(item("Scholarly Robes", "green"), "quest reward")
    p += row(item("Cutthroat's Hat", "green"), "Galak Scout")
    p += row(item("Elder's Mantle", "blue"), "Kolkar Centaur · best of the day")
    return window(CHAPTERS, "Days", day_list(), p, height=820)

def day_b():
    p = h1("Tuesday, 17 November", "2 h 51 m · 29 → 30")
    p += h2("Gold", f'net {coins(income - spend, 12)}')
    colors = ["#c8a23a", "#7aa35a", "#b08a5a", "#6a8bb0", "#9a9a8a"]
    p += stacked([(n, v, colors[i], f"{v // 10000}g {v // 100 % 100}s") for i, (n, v, _) in enumerate(GOLD_IN)], income)
    p += '<div style="font-size:11.5px;color:#5a4526;margin:6px 0 2px">Spent</div>'
    p += stacked([(n, v, ["#b0573a", "#8a5ab0", "#5a9ab0", "#a07a5a"][i], f"{v // 10000}g {v // 100 % 100}s" if v >= 10000 else f"{v // 100}s") for i, (n, v, _) in enumerate(GOLD_OUT)], spend, 8)
    p += h2("Experience", f'<b>{xp_total:,}</b> · 14,970 an hour')
    p += stacked([(n, v, ["#c8a23a", "#b0573a", "#d08a6a", "#6a8bb0"][i], f"{v:,}") for i, (n, v, _) in enumerate(XP_PARTS)], xp_total)
    p += h2("The day in numbers")
    p += tiles([("Quests", "11"), ("Kills", "214"), ("Deaths", "1"), ("Chests", "2")])
    p += tiles([("Nodes", "3"), ("Loot sold", coins(31720)), ("Best drop", item("Elder's Mantle", "blue"))])
    return window(CHAPTERS, "Days", day_list(), p, height=620)

def day_c():
    p = h1("Tuesday, 17 November", "two sessions")
    def session(title, lines):
        out = f'<div style="display:flex;gap:10px;margin-top:8px"><div style="width:58px;flex:none;font:600 12px \'Source Sans 3\';color:#3a2400">{title}</div><div style="flex:1;border-left:2px solid rgba(90,60,20,.4);padding-left:10px">'
        for t, text in lines:
            out += f'<div style="font-size:12.5px;line-height:19px"><span style="color:{SOFT};display:inline-block;width:40px">{t}</span>{text}</div>'
        return out + '</div></div>'
    p += session("09:12 1 h 05 m", [("09:12", "Logged in, Thousand Needles"), ("09:40", "Handed in <b>Free From the Hold</b> · 2,450 xp · " + coins(3500)),
                                     ("09:58", "Battered Chest: " + item("Glimmering Mail Pauldrons", "green")), ("10:17", "Logged out: +" + coins(28430) + ", 14,200 xp")])
    p += session("19:30 1 h 46 m", [("19:41", "Sold loot to Jawn Highmesa · " + coins(31720)), ("20:05", f'<b style="color:#3a2400">Level 30</b> · trained Frostbolt 5 · −' + coins(9000)),
                                     ("20:30", item("Elder's Mantle", "blue") + " from Kolkar Centaur"), ("20:51", "2 auctions sold · " + coins(45000)), ("21:16", "Logged out: +" + coins(62200) + ", 28,620 xp")])
    p += h2("The day", coins(income - spend, 12) + f' · <b>{xp_total:,}</b> xp')
    p += row("Gold: looted, quests, vendors, auctions", coins(income))
    p += row("Spent: repairs, training, flights, bought", '<span style="color:#a33224">−</span>' + coins(spend, color=RED))
    p += row("Experience: quests 21,400 · kills 20,080 (5,260 rested) · discovery 1,340", "")
    return window(CHAPTERS, "Days", day_list(), p, height=620)

# ---- Other ideas ----------------------------------------------------------------------------------------
def level_timeline():
    levels = [(30, "today 20:05", "1 h 52 m", 62, 34, 4, "Thousand Needles"), (29, "yesterday 21:40", "2 h 10 m", 48, 50, 2, "The Barrens, Thousand Needles"),
              (28, "Sun 15 Nov", "1 h 31 m", 70, 27, 3, "The Barrens"), (27, "Sun 15 Nov", "1 h 48 m", 55, 42, 3, "Stonetalon Mountains")]
    p = h1("Levels", "time played at each level, and what its experience came from")
    for lv, when, took, q, k, d, zones in levels:
        bar = (f'<div style="display:flex;height:9px;border-radius:2px;overflow:hidden;margin:3px 0 2px;box-shadow:0 0 0 1px rgba(60,40,10,.4)">'
               f'<span style="width:{q}%;background:#c8a23a"></span><span style="width:{k}%;background:#b0573a"></span><span style="width:{d}%;background:#6a8bb0"></span></div>')
        p += (f'<div style="display:flex;gap:10px;padding:6px 0;border-top:1px solid rgba(90,60,20,.2)"><div style="font:400 22px Marcellus,Georgia;color:#3a2400;width:34px">{lv}</div>'
              f'<div style="flex:1"><div style="display:flex;font-size:12.5px"><span style="flex:1">{when} · took <b>{took}</b></span><span style="color:{SOFT};font-size:11.5px">{zones}</span></div>'
              f'{bar}<div style="font-size:11px;color:{SOFT}">quests {q}% · kills {k}% · discovery {d}%</div></div></div>')
    p += '<div style="font-size:11.5px;color:#5a4526;margin-top:6px">Fastest level: 22, 58 m · slowest: 29</div>'
    return window(["At a glance", "Days", "Levels", "Journal", "Zones"], "Levels", "", p, width=600, height=470)

def recap():
    chat = (f'<div style="background:rgba(0,0,0,.6);border-radius:4px;padding:8px 10px;font:13px/1.5 \'Source Sans 3\';color:#fff;width:600px;box-sizing:border-box">'
            f'<div><span style="color:{GOLD}">OneMoreQuest</span>: Welcome back. Last time (yesterday, 2 h 10 m): <span style="color:#7ce07c">level 29</span>, 14 quests, '
            f'<span style="color:{GOLD}">+4g 02s</span>, 31,800 xp, best drop <span style="color:{QUALITY["green"]}">[Scholarly Robes]</span>.</div></div>')
    toast = (f'<div style="margin-top:10px;width:360px;background:linear-gradient(#2a2118,#1a1510);border:1px solid #6b5a3a;border-radius:6px;padding:10px 12px;font:13px/1.45 \'Source Sans 3\';color:#e8dcc0;box-shadow:0 4px 14px #0008">'
             f'<div style="font:400 15px Marcellus,Georgia;color:{GOLD}">Welcome back</div><div style="color:#b8ad8c;font-size:12px;margin-bottom:6px">Yesterday · 2 h 10 m</div>'
             f'<div style="display:grid;grid-template-columns:1fr 1fr;gap:4px 12px"><span>Level 28 → 29</span><span>14 quests</span><span>+4g 02s</span><span>31,800 xp</span></div>'
             f'<div style="margin-top:6px">Best drop: <span style="color:{QUALITY["green"]}">[Scholarly Robes]</span></div>'
             f'<div style="margin-top:6px;font-size:11.5px;color:#b8ad8c">Click to open the day in the chronicle</div></div>')
    return chat + toast

def calendar():
    import random
    random.seed(3)
    cells = ""
    for name in "Mon Tue Wed Thu Fri Sat Sun".split():
        cells += f'<div style="font-size:10.5px;color:{SOFT};text-align:center">{name}</div>'
    for i in range(-6, 30):
        if i < 0:
            cells += "<div></div>"; continue
        day = i + 1
        played = random.choice([0, 0, 0.5, 1, 1.5, 2.5, 3, 4]) if day <= 17 else None
        if played is None:
            cells += f'<div style="aspect-ratio:1;border-radius:3px;background:rgba(90,60,20,.06);font-size:10px;color:#a89470;padding:2px 3px">{day}</div>'
        else:
            a = min(1, played / 4)
            col = f"rgba(200,150,40,{0.12 + 0.75 * a:.2f})" if played else "rgba(90,60,20,.1)"
            ring = "box-shadow:0 0 0 2px #3a2400;" if day == 17 else ""
            cells += f'<div title="{played} h" style="aspect-ratio:1;border-radius:3px;background:{col};{ring}font-size:10px;color:#3a2400;padding:2px 3px">{day}</div>'
    p = h1("November", "shaded by time played; click a day to open it")
    p += f'<div style="display:grid;grid-template-columns:repeat(7,1fr);gap:4px;max-width:330px">{cells}</div>'
    p += '<div style="display:flex;gap:6px;align-items:center;font-size:11px;color:#5a4526;margin-top:8px">less <span style="width:12px;height:12px;background:rgba(200,150,40,.15);border-radius:2px"></span><span style="width:12px;height:12px;background:rgba(200,150,40,.5);border-radius:2px"></span><span style="width:12px;height:12px;background:rgba(200,150,40,.87);border-radius:2px"></span> more · switch: time, xp, gold, quests</div>'
    return window(["At a glance", "Days", "Calendar", "Journal"], "Calendar", "", p, width=560, height=430)

def records():
    p = h1("Records")
    recs = [("Best day for gold", coins(91300), "Sat 14 Nov"), ("Best day for experience", "48,200", "yesterday"), ("Fastest level", "22 in 58 m", "Thu 12 Nov"),
            ("Most quests in a day", "19", "Sun 15 Nov"), ("Days in a row", "6", "now"), ("Luckiest drop", item("Elder's Mantle", "blue"), "1.2% chance, Kolkar Centaur"),
            ("Most kills in a day", "312", "Sun 15 Nov"), ("Longest without dying", "4 h 20 m played", "")]
    for n, v, when in recs:
        p += (f'<div style="display:flex;align-items:baseline;padding:5px 0;border-top:1px solid rgba(90,60,20,.18)"><span style="flex:1">{n}</span>'
              f'<span style="font-weight:600;margin-right:10px">{v}</span><span style="font-size:11.5px;color:{SOFT};width:150px;text-align:right">{when}</span></div>')
    return window(["At a glance", "Days", "Records", "Journal"], "Records", "", p, width=560, height=380)

def professions():
    p = h1("Professions and reputation", "by day")
    p += h2("Today")
    p += row("Tailoring", "+14 · 112 → 126", "Bolt of Silk Cloth ×9, Azure Silk Pants")
    p += row("First Aid", "+6 · 150 → 156", "Heavy Silk Bandage")
    p += row("Cooking", "+2 · 88 → 90", "")
    p += h2("Reputation")
    p += row("Thunder Bluff", '+1,150 <span style="color:#5a4526">· Friendly 4,200 / 6,000</span>', "quests")
    p += row("Orgrimmar", '+350 <span style="color:#5a4526">· Honored 2,100 / 12,000</span>', "")
    p += row("Ratchet", '+75 <span style="color:#5a4526">· Neutral 1,400 / 3,000</span>', "")
    return window(["At a glance", "Days", "Crafts & standing", "Journal"], "Crafts & standing", "", p, width=560, height=330)

def dungeons():
    p = h1("Dungeon runs")
    runs = [("Razorfen Kraul", "today 20:10", "52 m", "4 of 5 quests", "1 death", [("Gravestone Scepter", "blue"), ("Corpsemaker", "green")], coins(48600)),
            ("Wailing Caverns", "Sat 14 Nov", "1 h 24 m", "5 of 6 quests", "3 deaths", [("Footpads of the Fang", "blue")], coins(31250))]
    for name, when, took, q, deaths, loot, gold in runs:
        p += (f'<div style="padding:7px 0;border-top:1px solid rgba(90,60,20,.25)"><div style="display:flex;align-items:baseline"><span style="font:400 15px Marcellus,Georgia;color:#3a2400;flex:1">{name}</span>'
              f'<span style="font-size:11.5px;color:{SOFT}">{when} · {took}</span></div>'
              f'<div style="font-size:12.5px">{q} · {deaths} · 4 in the group · {gold}</div>'
              f'<div style="font-size:12.5px">{" ".join(item(n, qq) for n, qq in loot)}</div></div>')
    return window(["At a glance", "Days", "Dungeons", "Journal"], "Dungeons", "", p, width=560, height=290)

def col(title, text, pics, rec=False, width=640):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if rec else ""
    return (f'<div style="display:flex;flex-direction:column;gap:10px;width:{width}px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:36px">{text}</div>{pics}</div>')

days = (col("A. A ledger", "A day as an account: tiles for the headlines, then gold in and out line by line (where it came from, where it went, net and per hour), experience by source, chests and nodes, notable loot. Days listed under the chapters.", day_a(), True)
        + col("B. Bars", "The same numbers as stacked bars: one for gold coming in, a thin one for spending, one for experience; hover a part for its number. Quicker to take in, less exact at a glance.", day_b())
        + col("C. The day as it went", "Each session in order with what happened when (hand-ins, chests, levels, sales, best drops), the day's totals under it.", day_c()))
others = (col("Level timeline", "Each level: when reached, time played at it, its zones, and what its experience came from.", level_timeline(), width=600)
          + col("Welcome-back recap", "At login, the last session in a line in the chat; or a small note to click, opening that day.", recap(), width=600)
          + col("Calendar", "A month shaded by time played (or xp, gold, quests); click a day for its page.", calendar(), width=560))
others2 = (col("Records", "Bests and streaks, each with its day.", records(), width=560)
           + col("Professions and reputation", "Skill gained and what was made; reputation gained and where it stands, by day.", professions(), width=560)
           + col("Dungeon runs", "Each run: time inside, quests done there, deaths, group, gold and loot.", dungeons(), width=560))
width, height = 30 * 2 + 3 * 640 + 2 * 40, 2260
note = ("Recorded from now on, per character, one small summary a day (about 300 bytes; notable loot as item numbers, capped): "
        "gold by source from what the game says as it happens (coins looted, a quest's reward, a vendor or the auction mailbox open when money arrives, repairs, trainers, flights); "
        "experience from the game's own messages (kills with the rested part, quests, discovery). Money the addon cannot place is \"other\". Numbers are examples.")
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Chronicle, days and more</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:26px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="padding:10px 14px;background:#00000033;border-left:3px solid #ffd100;font-size:13px;line-height:1.5"><div style="font:400 16px Marcellus,Georgia;color:#ffd100">What it would record</div>{note}</div>
<div style="font:400 24px Marcellus,Georgia;color:#f0e2b6">Days: a page for each day played</div>
<div style="display:flex;gap:40px;align-items:flex-start">{days}</div>
<div style="font:400 24px Marcellus,Georgia;color:#f0e2b6;margin-top:10px">More for the chronicle</div>
<div style="display:flex;gap:40px;align-items:flex-start">{others}</div>
<div style="display:flex;gap:40px;align-items:flex-start">{others2}</div>
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
open(os.path.join(OUT, "ChronicleDays.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
