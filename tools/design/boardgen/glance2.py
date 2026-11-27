"""A Design-board artboard: the Today panel without white boxes, and Kills and luck as bounded summaries, built from
the game's own parts (the WoW Forever UI system)."""
import os, sys, base64
OUT, RAW = sys.argv[1], sys.argv[2]
def uri(path):
    return "data:image/png;base64," + base64.b64encode(open(os.path.join(RAW, path), "rb").read()).decode()
PARCH, NAMEFRAME, SLOT = uri("Frames/questbg.png"), uri("Items/ui-questitemnameframe.png"), uri("Items/ui-quickslot2.png")
ICON = {k: uri(f"Icons/{v}.png") for k, v in [("coin", "inv_misc_coin_01"), ("xp", "xp_icon"), ("scroll", "inv_scroll_03"), ("kills", "ability_tracking"),
                                              ("time", "inv_misc_pocketwatch_01"), ("luck", "inv_misc_ticket_tarot_madness")]}
GOLD, SILVER, COPPER = uri("Money/ui-goldicon.png"), uri("Money/ui-silvericon.png"), uri("Money/ui-coppericon.png")
INK, BROWN, TITLE = "#2e1e0f", "#7d590d", "#000000"
FRIZ, MORPH = "'Marcellus', Georgia, serif", "'Metamorphous', Georgia, serif"

def money(g, s, c=None, color=INK, size=13):
    out = f'{g}<img src="{GOLD}" width="{size - 1}" style="margin:0 5px 0 2px;vertical-align:-2px">{s}<img src="{SILVER}" width="{size - 1}" style="margin:0 0 0 2px;vertical-align:-2px">'
    if c is not None:
        out += f' {c}<img src="{COPPER}" width="{size - 1}" style="margin:0 0 0 2px;vertical-align:-2px">'
    return f'<span style="white-space:nowrap;color:{color}">{out}</span>'

def page(title, note, inner, height):
    return (f'<div style="width:520px;height:{height}px;background:#3a2a17 url({PARCH}) 0 0/600px 600px;box-shadow:inset 0 0 0 2px #1a120a,0 6px 18px #0008;overflow:hidden;font:13px/1.35 {FRIZ};color:{INK}">'
            f'<div style="background:linear-gradient(#2b1c10,#1e140b);padding:8px 16px 7px;border-bottom:1px solid #000"><div style="font:16px {FRIZ};color:#ffd100">{title}</div>'
            f'<div style="font-size:11.5px;color:#e8dcc0">{note}</div></div><div style="padding:12px 18px">{inner}</div></div>')

def heading(text, note=""):
    return (f'<div style="display:flex;align-items:baseline;margin:6px 0 6px;border-bottom:2px solid rgba(125,89,13,.55)"><span style="font:17px {MORPH};color:{TITLE};flex:1">{text}</span>'
            f'<span style="font-size:11.5px;color:#5a4526">{note}</span></div>')

def strip(cells, columns=3):
    rows = [cells[i:i + columns] for i in range(0, len(cells), columns)]
    html = ""
    for r in rows:
        html += '<div style="display:flex;gap:8px;padding:6px 8px">' + "".join(
            f'<div style="display:flex;gap:8px;align-items:center;flex:1;min-width:0"><img src="{ICON[icon]}" width="32" height="32" style="box-shadow:0 0 0 1px #000;flex:none">'
            f'<div style="min-width:0"><div style="font:16px {FRIZ};color:#fff;white-space:nowrap;text-shadow:1px -1px 0 #000">{value}</div>'
            f'<div style="font-size:11px;color:{sub_color or "#d8c9a0"};white-space:nowrap">{label}</div></div></div>' for icon, value, label, sub_color in r) + '</div>'
    return f'<div style="background:linear-gradient(#3a2614,#24170b);border:1px solid #000;box-shadow:inset 0 0 0 1px #6b4a26;margin:4px 0 8px">{html}</div>'

def reward(icon, value, label, label_color="#d8c9a0", value_color="#fff"):
    return (f'<div style="position:relative;width:232px;height:46px">'
            f'<div style="position:absolute;left:30px;top:-9px;width:200px;height:64px;background:url({NAMEFRAME}) 0 0/200px 64px no-repeat"></div>'
            f'<img src="{ICON[icon]}" width="39" height="39" style="position:absolute;left:0;top:3px;box-shadow:0 0 0 1px #000">'
            f'<div style="position:absolute;left:47px;top:6px;width:170px;font:14px {FRIZ};color:{value_color};text-shadow:1px -1px 0 #000;white-space:nowrap">{value}</div>'
            f'<div style="position:absolute;left:47px;top:24px;width:170px;font:11px {FRIZ};color:{label_color};white-space:nowrap">{label}</div></div>')

def fact(label, value, note="", note_color="#5a4526"):
    n = f'<span style="font-size:11.5px;color:{note_color};margin-left:8px">{note}</span>' if note else ""
    return f'<div style="display:flex;align-items:baseline;padding:2px 0"><span style="flex:1;color:#5a4526">{label}</span><span>{value}</span>{n}</div>'

GOOD, BAD = "#7ce07c", "#ff7a6a"
GOOD_INK, BAD_INK = "#2f6b2f", "#9a2a1c"
NOTE = "Tuesday 17 November · 2 h 56 m so far"

# --- Today
today_a = page("At a glance", "Level 30 · kept since 7 Nov", heading("Today", NOTE) + strip([
    ("coin", money(8, 27, color="#fff", size=15), "Gold, net · 2.3x average", GOOD), ("xp", "34,472", "Experience · 1.1x average", GOOD),
    ("scroll", "7", "Quests · average 6", None), ("time", "29 to 30", "Level · next in 1 h 37 m", None)], 2) + heading("Altogether", "since 8 Nov") +
    '<div style="height:44px;background:rgba(0,0,0,.15);border:1px dashed rgba(90,60,20,.4);display:flex;align-items:center;justify-content:center;font-size:12px;color:#5a4526">the Altogether strip, as now</div>', 330)
today_b = page("At a glance", "Level 30 · kept since 7 Nov", heading("Today", NOTE) +
    '<div style="display:grid;grid-template-columns:1fr 1fr;gap:12px 14px;margin:8px 0 6px">' +
    reward("coin", money(8, 27, color="#fff", size=14), "Gold, net · 2.3x average", GOOD) + reward("xp", "34,472", "Experience · 1.1x average", GOOD) +
    reward("scroll", "7", "Quests · average 6") + reward("time", "29 to 30", "Level · next in 1 h 37 m") + '</div>' + heading("Altogether", "since 8 Nov") +
    '<div style="height:44px;background:rgba(0,0,0,.15);border:1px dashed rgba(90,60,20,.4);display:flex;align-items:center;justify-content:center;font-size:12px;color:#5a4526">the Altogether strip, as now</div>', 330)
today_c = page("At a glance", "Level 30 · kept since 7 Nov", heading("Today", NOTE) +
    '<div style="display:grid;grid-template-columns:1fr 1fr;gap:0 26px">' +
    fact("Gold, net", money(8, 27)) + fact("Experience", "34,472") + fact("", f'<span style="color:{GOOD_INK}">2.3x average</span>') + fact("", f'<span style="color:{GOOD_INK}">1.1x average</span>') +
    '</div><div style="height:6px"></div><div style="display:grid;grid-template-columns:1fr 1fr;gap:0 26px">' +
    fact("Quests", "7") + fact("Level", "29 to 30") + fact("", '<span style="color:#5a4526">average 6</span>') + fact("", '<span style="color:#5a4526">next in 1 h 37 m</span>') +
    '</div>' + heading("Altogether", "since 8 Nov") +
    '<div style="height:44px;background:rgba(0,0,0,.15);border:1px dashed rgba(90,60,20,.4);display:flex;align-items:center;justify-content:center;font-size:12px;color:#5a4526">the Altogether strip, as now</div>', 330)

# --- Kills and luck
def line_bar(kills, expected, width=150):
    total = max(kills, expected)
    unlucky = kills > expected
    return (f'<span style="display:inline-block;position:relative;width:{width}px;height:7px;background:#2a2014;box-shadow:0 0 0 1px #5a4526;vertical-align:1px">'
            f'<span style="position:absolute;left:0;top:0;bottom:0;width:{100 * kills / total:.0f}%;background:{"#b04a2a" if unlucky else "#4a8a3a"}"></span>'
            f'<span style="position:absolute;left:{100 * expected / total:.0f}%;top:-3px;bottom:-3px;width:2px;background:#ffd100"></span></span>')

kills_strip = strip([("kills", "616", "Kills for drops", None), ("scroll", "564", "Expected", None), ("luck", "-9%", "Luck", BAD)], 3)
kills_a = page("Kills and luck", "Kills for quest drops against what an average player needs", kills_strip +
    heading("Highlights") +
    fact("Unluckiest", "Ignition · 77 kills, 50 expected", "") + f'<div style="margin:-2px 0 4px">{line_bar(77, 50, 470)}</div>' +
    fact("Luckiest", "Verog the Dervish · 23 kills, 33 expected", "") + f'<div style="margin:-2px 0 4px">{line_bar(23, 33, 470)}</div>' +
    fact("Most kills for one quest", "Ignition · 77") +
    fact("Rarest drop", "Barak's Head · a 2% chance, after 31 kills") +
    fact("First kill", "Theramore Medal · dropped from the first Marine") +
    fact("Most killed", "Kolkar Centaur · 214") +
    heading("Creatures", "the five most killed") +
    "".join(fact(n, str(k)) for n, k in [("Kolkar Centaur", 214), ("Sunscale Scytheclaw", 131), ("Razormane Geomancer", 96), ("Theramore Marine", 74), ("Thunderhead", 61)]), 640)
def top3(title, rows, bar=True):
    out = heading(title, "top 3")
    for name, k, e in rows:
        out += fact(name, f"{k} kills, {e} expected") + (f'<div style="margin:-2px 0 3px">{line_bar(k, e, 470)}</div>' if bar else "")
    return out
kills_b = page("Kills and luck", "Kills for quest drops against what an average player needs", kills_strip +
    top3("Unluckiest quests", [("Ignition", 77, 50), ("Enraged Thunder Lizards", 54, 40), ("Weapons of Choice", 42, 30)]) +
    top3("Luckiest quests", [("Verog the Dervish", 23, 33), ("Centaur Bracers", 18, 25), ("Raptor Thieves", 12, 16)]) +
    heading("Most killed", "top 3") + "".join(fact(n, str(k)) for n, k in [("Kolkar Centaur", 214), ("Sunscale Scytheclaw", 131), ("Razormane Geomancer", 96)]), 640)

def col(title, text, pic, rec=False, width=540):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if rec else ""
    return (f'<div style="display:flex;flex-direction:column;gap:10px;width:{width}px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:52px">{text}</div>{pic}</div>')

todays = (col("A. The reward strip", "Today on the same dark wood as Altogether below it and the quest page's rewards: icon, number, and the comparison under it in green or red. Two by two.", today_a, True)
          + col("B. Reward name frames", "Each number beside its icon in the game's reward name frame, as a quest's rewards are shown on its page.", today_b)
          + col("C. Lines of text", "No frame at all: label and number in ink, the comparison under each in dark green or red, as the quest page's own text.", today_c))
kills = (col("A. Highlights", "The totals, then one line each for what stands out (unluckiest and luckiest quest with their bars, most kills for one quest, rarest drop, quickest drop, most killed) and the five creatures killed most. The same length however many quests.", kills_a, True)
         + col("B. Top threes", "The totals, then three short lists: the three unluckiest quests, the three luckiest, the three creatures killed most. The same length however many quests.", kills_b))
width, height = 30 * 2 + 3 * 540 + 2 * 40, 1340
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Chronicle, game parts</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Metamorphous&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5">Built only from the game's own parts (the WoW Forever UI system): the parchment, the dark reward strip, the reward name frame, the game's icons and coins, Morpheus headings and ink text. No light boxes.</div>
<div style="font:400 22px Marcellus,Georgia;color:#f0e2b6">At a glance: Today</div>
<div style="display:flex;gap:40px;align-items:flex-start">{todays}</div>
<div style="font:400 22px Marcellus,Georgia;color:#f0e2b6;margin-top:6px">Kills and luck: the same length, however many quests</div>
<div style="display:flex;gap:40px;align-items:flex-start">{kills}</div>
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
open(os.path.join(OUT, "ChronicleGameParts.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height, len(board))
