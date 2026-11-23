"""A Design-board artboard: the Chronicle's Today panel and Kills and luck page, drawn with the game's own page."""
import os, sys, base64
OUT, ART = sys.argv[1], sys.argv[2]
def uri(name):
    return "data:image/png;base64," + base64.b64encode(open(os.path.join(ART, name), "rb").read()).decode()
IMAGES = {}  # each image once, as a CSS variable
def image(key, file):
    IMAGES[key] = uri(file)
    return f"var(--{key})"
def icon(name):
    key = "i-" + name.lower().replace("_", "-")
    return IMAGES.get(key) and f"var(--{key})" or image(key, "icon-" + name.lower() + ".png")
PAGE, BAND = image("page", "questdetailsbackgrounds.png"), image("band", "questlog-reward-top-frame.png")

# The addon's colours (Widgets.COLORS, ChroniclePage)
INK, SOFT, BROWN = "#291f0f", "#594a30", "#7a4f00"
BETTER, WORSE = "#2e7a2e", "#a33324"
STRIP_LABEL, LUCKY, UNLUCKY = "#d9cfa8", "#8ad18a", "#ff7a59"
QUALITY = {"green": "#1eff00", "blue": "#0070dd", "white": INK}
FRIZ, MORPH = "Marcellus,Georgia,serif", "Metamorphous,Georgia,serif"
W, PAD = 410, 18

def coins(copper, color=INK, size=12):
    g, s, c = copper // 10000, (copper // 100) % 100, copper % 100
    def coin(n, col):
        return (f'{n}<span style="display:inline-block;width:{size - 2}px;height:{size - 2}px;border-radius:50%;'
                f'background:radial-gradient(circle at 35% 30%,#fffa,{col} 62%);box-shadow:0 0 0 .5px #0008;margin:0 3px 0 1px;vertical-align:-1px"></span>')
    parts = ([coin(g, "#e8b923")] if g else []) + ([coin(s, "#c7c7cf")] if (s or g) else []) + ([coin(c, "#c0773a")] if c or not (g or s) else [])
    return f'<span style="white-space:nowrap;color:{color}">{"".join(parts)}</span>'

def page(title, note, body, height):
    return (f'<div style="position:relative;width:{W}px;height:{height}px;background:{PAGE} 0 0/100% 100%;font:13px/1.35 {FRIZ};color:{INK};overflow:hidden">'
            f'<div style="position:relative;height:44px;background:{BAND} 0 0/100% 100%;padding:7px 14px 0;box-sizing:border-box">'
            f'<div style="font:16px {FRIZ};color:#ffd100;text-shadow:1px -1px 0 #000">{title}</div>'
            f'<div style="font:10.5px {FRIZ};color:#fff;text-shadow:1px -1px 0 #000">{note}</div></div>'
            f'<div style="padding:10px {PAD}px 0">{body}</div></div>')

def heading(text, note=""):
    n = f'<span style="font:10.5px {FRIZ};color:{SOFT}">{note}</span>' if note else ""
    return (f'<div style="display:flex;align-items:baseline;justify-content:space-between;margin:8px 0 7px;padding-bottom:3px;border-bottom:2px solid {BROWN}">'
            f'<span style="font:15px {MORPH};color:{INK};font-variant:small-caps">{text}</span>{n}</div>')

def framed(name, size=32):
    return (f'<span style="display:inline-block;width:{size}px;height:{size}px;flex:none;background:{icon(name)} center/118%;'
            f'box-shadow:0 0 0 1px #000,0 0 0 2px #6b4a26,1px 2px 3px #0006"></span>')

def strip(cells, columns=3):
    rows = [cells[i:i + columns] for i in range(0, len(cells), columns)]
    html = ""
    for r in rows:
        html += '<div style="display:flex;padding:5px 6px">' + "".join(
            f'<div style="display:flex;gap:7px;align-items:center;flex:1;min-width:0">{framed(ic)}'
            f'<div style="min-width:0"><div style="font:16px {FRIZ};color:{col};white-space:nowrap;text-shadow:1px -1px 0 #000">{value}</div>'
            f'<div style="font:10.5px {FRIZ};color:{lc or STRIP_LABEL};white-space:nowrap">{label}</div></div></div>'
            for ic, value, label, col, lc in [(c + (None,) * (5 - len(c)))[:5] if len(c) < 5 else c for c in [(x[0], x[1], x[2], x[3] if len(x) > 3 and x[3] else "#fff", x[4] if len(x) > 4 else None) for x in r]]) + '</div>'
    return (f'<div style="background:linear-gradient(#382614 50%,#291a0d 50%);box-shadow:0 0 0 1px #000,inset 0 0 0 1px #6b4a26;margin:2px 0 10px">{html}</div>')

def fact(label, value, color=INK, sub=""):
    s = f'<div style="font:10.5px {FRIZ};color:{SOFT};margin-top:-1px">{sub}</div>' if sub else ""
    return (f'<div style="padding:2px 0 4px"><div style="display:flex;gap:10px;font:13px {FRIZ}"><span style="color:{SOFT};flex:none">{label}</span>'
            f'<span style="flex:1;text-align:right;color:{color}">{value}</span></div>{s}</div>')

def entry(ic, value, label, note="", note_color=SOFT, value_html=None):
    n = f' <span style="color:{note_color}">{note}</span>' if note else ""
    return (f'<div style="display:flex;gap:9px;align-items:center;min-width:0">{framed(ic)}<div style="min-width:0">'
            f'<div style="font:16px {FRIZ};color:{INK};white-space:nowrap">{value_html or value}</div>'
            f'<div style="font:10.5px {FRIZ};color:{SOFT};white-space:nowrap">{label}{n}</div></div></div>')

def record(ic, kind, what, numbers, color=SOFT):
    """A highlight: what kind of record, what holds it, its numbers, beside the icon of what it was for"""
    return (f'<div style="display:flex;gap:9px;align-items:flex-start;min-width:0">{framed(ic)}<div style="min-width:0;margin-top:-2px">'
            f'<div style="font:10.5px {FRIZ};color:{SOFT}">{kind}</div>'
            f'<div style="font:14px/17px {FRIZ};color:{INK}">{what}</div>'
            f'<div style="font:10.5px {FRIZ};color:{color}">{numbers}</div></div></div>')

def grid(cells, gap="12px 14px"):
    return f'<div style="display:grid;grid-template-columns:1fr 1fr;gap:{gap};margin:2px 0 6px">{"".join(cells)}</div>'

def item(name, quality="white"):
    color = QUALITY[quality]
    shadow = "text-shadow:0 0 1px #000a;" if quality != "white" else ""
    return f'<span style="color:{color};{shadow}">[{name}]</span>'

# ---- The rest of At a glance, the same under each Today ---------------------------------------------------------
def altogether():
    return heading("Altogether", "since 9 Nov") + strip([
        ("INV_Scroll_03", "312", "Quests done"), ("INV_Misc_Coin_01", coins(342100, "#fff"), "Gold earned, net"), ("XP_Icon", "412,600", "Experience"),
        ("INV_Misc_PocketWatch_01", "31 h 12 m", "Time played"), ("Ability_Tracking", "2,914", "Kills"), ("INV_Misc_Ticket_Tarot_Madness", "+8%", "Luck with drops", LUCKY)])
def records():
    return heading("Records") + fact("Best day for gold", coins(91300) + f' <span style="color:{SOFT};font-size:11px">Sat</span>') + \
        fact("Best day for experience", f'48,200 <span style="color:{SOFT};font-size:11px">Sat</span>') + \
        fact("Most quests in a day", f'19 <span style="color:{SOFT};font-size:11px">Sat</span>') + fact("Days in a row", "6")
GLANCE_NOTE = "Level 30 · kept since 9 Nov"
TODAY_NOTE = "Tuesday 17 November · 2 h 51 m so far"

def today_a():
    body = heading("Today", TODAY_NOTE) + grid([
        entry("INV_Misc_Coin_01", "", "Gold, net ·", "2.2x average", BETTER, coins(91300, INK, 13)),
        entry("XP_Icon", "42,820", "Experience ·", "1.4x average", BETTER),
        entry("INV_Scroll_03", "11", "Quests · average 10"),
        entry("Achievement_Level_30", "29 to 30", "Level · next in 1 h 32 m"),
    ])
    return page("At a glance", GLANCE_NOTE, body + altogether() + records(), 450)

def level_bar(share=0.42, rested=0.18):
    return (f'<div style="display:flex;align-items:center;gap:8px;margin:4px 0 2px"><span style="font:13px {FRIZ};color:{SOFT}">30</span>'
            f'<div style="flex:1;height:9px;background:#0002;box-shadow:0 0 0 1px {BROWN};position:relative">'
            f'<span style="position:absolute;left:0;top:0;bottom:0;width:{share * 100}%;background:linear-gradient(#b05cf0,#6a2aa0)"></span>'
            f'<span style="position:absolute;left:{share * 100}%;top:0;bottom:0;width:{rested * 100}%;background:#4a78e655"></span></div>'
            f'<span style="font:13px {FRIZ};color:{SOFT}">31</span></div>')
def today_b():
    body = heading("Today", TODAY_NOTE)
    body += fact("Gold, net", coins(91300), sub=f'<span style="color:{BETTER}">2.2x your average day</span>')
    body += fact("Experience", "42,820", sub=f'<span style="color:{BETTER}">1.4x your average day</span>')
    body += fact("Quests", "11", sub="your average day: 10")
    body += fact("Level", "29 to 30", sub="42% into 30 · next level in 1 h 32 m at today's pace")
    body += level_bar()
    return page("At a glance", GLANCE_NOTE, body + altogether() + records(), 525)

def today_c():
    body = heading("Today", TODAY_NOTE) + strip([
        ("INV_Misc_Coin_01", coins(91300, "#fff"), "2.2x average", "#fff", LUCKY), ("XP_Icon", "42,820", "1.4x average", "#fff", LUCKY),
        ("INV_Scroll_03", "11", "Quests · avg 10"),
        ("Achievement_Level_30", "29 to 30", "next in 1 h 32 m"), ("INV_Misc_PocketWatch_01", "2 h 51 m", "Played"), ("Ability_Tracking", "214", "Kills")])
    return page("At a glance", GLANCE_NOTE, body + altogether() + records(), 470)

# ---- Kills and luck ----------------------------------------------------------------------------------------------
KILLS_NOTE = "Kills for quest drops against what an average player needs"
def kills_strip():
    return strip([("Ability_Tracking", "412", "Kills for drops"), ("INV_Misc_Note_01", "388", "Expected"), ("INV_Misc_Ticket_Tarot_Madness", "-6%", "Luck", UNLUCKY)])
TOP = [("Witchwing Harpy", 74), ("Kolkar Marauder", 61), ("Sunscale Lashtail", 38), ("Zhevra Runner", 26), ("Venture Co. Peon", 22)]
def top_killed(count):
    return heading("Killed most for drops", f"top {count}") + "".join(fact(name, str(kills)) for name, kills in TOP[:count])

def kills_a():
    body = kills_strip() + heading("Highlights") + grid([
        record("INV_Misc_MonsterClaw_04", "Luckiest", "Raptor Thieves", "14 kills, 26 expected", BETTER),
        record("INV_Feather_04", "Unluckiest", "Harpy Raiders", "41 kills, 18 expected", WORSE),
        record("INV_Misc_Gem_Pearl_04", "Rarest drop", item("Thunderhawk Wings"), "a 6% chance, on the 3rd kill"),
        record("INV_Bracer_04", "Longest hunt", "Centaur Bracers", "62 kills for 15"),
        record("INV_Misc_MonsterTail_03", "Longest dry spell", "17 kills", "for a Harpy Talon"),
        record("INV_Misc_Dice_01", "Dropped on the first kill", "9 times", "of 46 drops"),
    ], gap="10px 12px") + top_killed(5)
    return page("Kills and luck", KILLS_NOTE, body, 530)

def meter(luck, width=W - 2 * PAD, height=12, label=True):
    # -30% .. +30%: unlucky on the left, lucky on the right, the average in the middle
    span = 0.3
    x = 50 + 50 * max(-span, min(span, luck)) / span
    fill_left, fill_width = (x, 50 - x) if luck < 0 else (50, x - 50)
    color = WORSE if luck < 0 else BETTER
    return (f'<div style="position:relative;height:{height}px;background:#0001;box-shadow:0 0 0 1px {BROWN}">'
            f'<span style="position:absolute;top:0;bottom:0;left:{fill_left}%;width:{fill_width}%;background:{color};opacity:.85"></span>'
            f'<span style="position:absolute;top:-3px;bottom:-3px;left:50%;width:2px;margin-left:-1px;background:#c9a227;box-shadow:0 0 0 1px #0006"></span></div>'
            + (f'<div style="display:flex;justify-content:space-between;font:10.5px {FRIZ};color:{SOFT};margin-top:3px"><span>unlucky</span><span>average</span><span>lucky</span></div>' if label else ""))
def kills_b():
    body = (f'<div style="text-align:center;margin:4px 0 2px"><div style="font:22px {MORPH};color:{WORSE}">6% unlucky</div>'
            f'<div style="font:12px {FRIZ};color:{SOFT}">412 kills for drops, where an average player needs 388</div></div>')
    body += meter(-0.06, height=14)
    body += heading("By level")
    for band, luck, kills in [("Levels 1 to 9", 0.12, 48), ("Levels 10 to 19", -0.03, 131), ("Levels 20 to 29", -0.11, 197), ("Level 30", 0.04, 36)]:
        text = f'{"+" if luck > 0 else ""}{round(luck * 100)}%'
        body += (f'<div style="display:flex;align-items:center;gap:10px;margin:5px 0"><span style="width:104px;flex:none;font:12.5px {FRIZ};color:{SOFT}">{band}</span>'
                 f'<div style="flex:1">{meter(luck, height=8, label=False)}</div>'
                 f'<span style="width:74px;flex:none;text-align:right;font:12.5px {FRIZ};color:{BETTER if luck > 0 else WORSE}">{text} <span style="color:{SOFT};font-size:10.5px">{kills} kills</span></span></div>')
    body += heading("Records")
    body += fact("Luckiest", "Raptor Thieves", sub="14 kills for 12 Raptor Heads, 26 expected")
    body += fact("Unluckiest", "Harpy Raiders", sub="41 kills for 8 Harpy Talons, 18 expected")
    body += fact("Rarest drop", item("Thunderhawk Wings"), sub="a 6% chance, on the 3rd kill")
    body += fact("Killed most", "Witchwing Harpy", sub="74 kills, for three quests")
    return page("Kills and luck", KILLS_NOTE, body, 515)

def luck_bar(kills, expected):
    total = max(kills, expected)
    unlucky = kills > expected
    return (f'<div style="position:relative;height:8px;background:#0001;box-shadow:0 0 0 1px {BROWN};margin:3px 0 2px">'
            f'<span style="position:absolute;left:0;top:0;bottom:0;width:{100 * kills / total:.1f}%;background:{WORSE if unlucky else BETTER};opacity:.85"></span>'
            f'<span style="position:absolute;top:-2px;bottom:-2px;left:{100 * expected / total:.1f}%;width:2px;margin-left:-1px;background:#c9a227;box-shadow:0 0 0 1px #0006"></span></div>')
def kills_c():
    body = kills_strip() + heading("Latest hunts", "the last 4 · the rest in the Journal")
    for title, item_name, kills, expected, ic in [("Harpy Raiders", "8 Harpy Talons", 41, 18, "INV_Feather_04"), ("Centaur Bracers", "15 Centaur Bracers", 62, 55, "INV_Bracer_04"),
                                                   ("Raptor Thieves", "12 Raptor Heads", 14, 26, "INV_Misc_MonsterClaw_04"), ("Plainstrider Menace", "7 Plainstrider Beaks", 19, 21, "INV_Misc_Bone_01")]:
        gap = kills - expected
        body += (f'<div style="display:flex;gap:9px;align-items:center;margin:6px 0">{framed(ic, 26)}<div style="flex:1;min-width:0">'
                 f'<div style="display:flex;font:13px {FRIZ}"><span style="flex:1">{title}</span><span style="color:{WORSE if gap > 0 else BETTER}">{"+" if gap > 0 else ""}{gap} kills</span></div>'
                 f'{luck_bar(kills, expected)}<div style="font:10.5px {FRIZ};color:{SOFT}">{item_name} in {kills} kills, {expected} expected</div></div></div>')
    body += heading("Records")
    body += fact("Luckiest", "Raptor Thieves · 12 fewer kills")
    body += fact("Unluckiest", "Harpy Raiders · 23 more kills")
    body += fact("Rarest drop", item("Thunderhawk Wings") + " · 6%")
    body += fact("Killed most", "Witchwing Harpy · 74")
    return page("Kills and luck", KILLS_NOTE, body, 515)

# ---- The board ---------------------------------------------------------------------------------------------------------
ZOOM = 1.5
def col(title, text, html, tag=""):
    t = f'<span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">{tag}</span>' if tag else ""
    return (f'<div style="display:flex;flex-direction:column;gap:10px;width:{round(W * ZOOM)}px">'
            f'<div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{t}</div>'
            f'<div style="font-size:12.5px;color:#d8cfa8;line-height:1.45;min-height:54px">{text}</div>'
            f'<div style="zoom:{ZOOM}">{html}</div></div>')
def row_of(title, text, cols):
    return (f'<div style="display:flex;flex-direction:column;gap:12px"><div style="font:400 22px Marcellus,Georgia,serif;color:#fff">{title}</div>'
            f'<div style="font-size:13px;color:#d8cfa8;line-height:1.5;max-width:1300px">{text}</div>'
            f'<div style="display:flex;gap:40px;align-items:flex-start">{cols}</div></div>')

today = row_of("Today, without the white boxes",
    "The page is the game's own parchment (QuestDetailsBackgrounds, under the quest log's dark title band), and parchment in Forever's windows carries no boxes. Three ways to show today's four numbers; Altogether and Records below stay as they are.",
    col("A. Entries", "Each number beside its icon, as the spellbook lists its spells: the figure large in ink, what it is and how it compares under it, green when better than your average day. No frames, two to a row.", today_a(), "Recommended")
    + col("B. Ledger lines", "Label and figure on one line, as Records already are, with the comparison under it; the level gets the experience bar, rested part in blue. Plainest; reads as one list with Records.", today_b())
    + col("C. On the dark wood", "The same dark wood as Altogether (the quest page's rewards band), six cells: figures in white, comparisons in green or red. The most game-like, but two dark bands stacked is heavy.", today_c()))
kills = row_of("Kills and luck, with a fixed size",
    "No list of every drop quest, which grows without end: only highlights, a few top lines and, at most, the latest few hunts. Every part has a set number of lines, so the page is the same size after 10 quests or 500.",
    col("A. Highlights", "The totals, then six records as entries with the item's icon: luckiest and unluckiest quest, rarest drop, longest hunt, longest dry spell, drops on the first kill. Then the five creatures killed most for drops.", kills_a(), "Recommended")
    + col("B. Luck meter", "One answer first: how lucky you are overall, on a meter from unlucky to lucky round the average player. Then luck by level (at most six bands), and four records as lines.", kills_b())
    + col("C. Latest hunts", "The totals, the last four drop quests with their bars (the Journal keeps the rest), then the records as short lines. Closest to the page today, cut to a fixed length.", kills_c()))

width = 30 * 2 + 3 * round(W * ZOOM) + 2 * 40
height = int(sys.argv[3]) if len(sys.argv) > 3 else 2000
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Chronicle in the game's look</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Metamorphous&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}} :root{{{"".join(f"--{k}:url({v});" for k, v in IMAGES.items())}}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:44px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
{today}
{kills}
<div style="font-size:12px;color:#a8a080">Drawn at 1.5x the game's size. The page art, title band and icons are the game's own; fonts are close free stand-ins for Friz Quadrata and Morpheus. Numbers are examples.</div>
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
open(os.path.join(OUT, "ChronicleInGame.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height, len(board) // 1024, "KB")
