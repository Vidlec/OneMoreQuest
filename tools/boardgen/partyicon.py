"""A Design-board artboard: four ways to use the game's party icon on the quest list's rows."""
import os, sys, base64
OUT, ART = sys.argv[1], sys.argv[2]
IMAGES = {}
def image(key, file):
    if key not in IMAGES:
        IMAGES[key] = "data:image/png;base64," + base64.b64encode(open(os.path.join(ART, file), "rb").read()).decode()
    return f"var(--{key})"
PARTY, CHAIN, RING = image("party", "friends-icon-friendsingroup-c60.png"), image("chain", "Chain.png"), image("ring", "RingDashed.png")
KILL, LOOT, TILDE = image("kill", "GlyphKill.png"), image("loot", "GlyphLoot.png"), image("tilde", "Tilde.png")
RULE, MINUS = image("rule", "ui-character-info-scrollline-long.png"), image("minus", "common-button-list-minus.png")
GOLD, TAN, GREEN, WHITE, GREY = "#ffd100", "#d9cfa8", "#7ce07c", "#ffffff", "#9a9a9a"
FRIZ = "Marcellus,Georgia,serif"
W = 236  # the list's width in the game

def masked(src, color, size):
    return (f'<span style="display:inline-block;width:{size}px;height:{size}px;background:{color};'
            f'-webkit-mask:{src} center/contain no-repeat;mask:{src} center/contain no-repeat;vertical-align:middle"></span>')
def coin(glyph):
    return (f'<span style="position:relative;display:inline-block;width:18px;height:18px;border-radius:50%;flex:none;'
            f'background:radial-gradient(circle at 35% 30%,#ffe9a0,#f0b429 55%,#a8741a);box-shadow:0 0 0 1px #3a2400">'
            f'<span style="position:absolute;inset:3px">{masked(glyph, "#2a1a05", 12)}</span></span>')
def dashed():
    return f'<span style="display:inline-block;width:18px;height:18px;flex:none;opacity:.7;background:{RING} center/contain no-repeat"></span>'
def party(size=15, opacity=1):
    return f'<span style="display:inline-block;width:{size}px;height:{size}px;flex:none;opacity:{opacity};background:{PARTY} center/contain no-repeat;vertical-align:middle"></span>'
def money(silver):
    return (f'{masked(TILDE, TAN, 10)} {silver}<span style="display:inline-block;width:8px;height:8px;border-radius:50%;margin-left:2px;'
            f'background:radial-gradient(circle at 35% 30%,#fff,#b8b8c0 60%)"></span>')

def row(title, sub, mark, chain="", silver=5, extra_right="", sub_extra="", selected=False, hover=False, title_color=GREY, sub_color=GREEN):
    bg = "background:#4a3a1c;box-shadow:inset 0 0 0 1px #c9a227;" if selected else ("background:#ffffff10;" if hover else "")
    chain_html = f'{masked(CHAIN, TAN, 11)} {chain}' if chain else ""
    return (f'<div style="display:flex;gap:7px;padding:5px 8px 5px 6px;{bg}">{mark}'
            f'<div style="flex:1;min-width:0"><div style="display:flex;align-items:center;gap:6px">'
            f'<span style="flex:1;font:12.5px {FRIZ};color:{WHITE if selected else title_color};white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{title}</span>'
            f'{extra_right}<span style="font:11px {FRIZ};color:{TAN};white-space:nowrap">{chain_html}</span></div>'
            f'<div style="display:flex;gap:6px;font:11px {FRIZ}"><span style="flex:1;color:{sub_color};white-space:nowrap">{sub}{sub_extra}</span>'
            f'<span style="color:{TAN};white-space:nowrap">{money(silver)}</span></div></div></div>')

def heading(name, right="", color=GOLD):
    return (f'<div style="position:relative;display:flex;align-items:center;gap:6px;padding:4px 8px 7px 8px;margin-top:4px">'
            f'<span style="width:3px;height:14px;background:{GOLD}"></span>'
            f'<span style="flex:1;font:13px {FRIZ};color:{color}">{name}</span>{right}'
            f'<span style="font:11px {FRIZ};color:{GREEN}">✓ 2</span><span style="font:11px {FRIZ};color:{TAN}">4</span>'
            f'<span style="display:inline-block;width:13px;height:4px;background:{MINUS} 0 0/13px 4px;margin-left:4px"></span>'
            f'<span style="position:absolute;left:0;right:0;bottom:0;height:6px;background:{RULE} 0 0/100% 6px"></span></div>')

def tooltip(lines, width=230):
    return (f'<div style="width:{width}px;background:#0b0d1acc;border:1px solid #8a8a8a;border-radius:4px;padding:7px 9px;'
            f'font:12px/1.4 {FRIZ};color:#fff;box-shadow:0 3px 10px #000a">{lines}</div>')

def hover_note(tip):
    return f'<div style="margin-top:10px;font:11px {FRIZ};color:#a8a080">Hovering the icon:</div><div style="margin-top:4px">{tip}</div>'

def panel(rows, note_html=""):
    return (f'<div style="width:{W}px;background:#16120d;box-shadow:0 0 0 1px #3a3022;padding:4px 0 8px">{rows}</div>{note_html}')

ROWS_PLAIN = [("[13] Raptor Thieves", "✓ Gazrog", dashed(), "1/2", 5), ("[15] The Disruption Ends", "1 of 3 done", coin(KILL), "2/2", 5),
              ("[18] Raptor Horns", "✓ Mebok Mizzyrix", dashed(), "1/2", 5), ("[20] The Guns of Northwatch", "1 of 4 done", coin(KILL), "", 5)]

def option_a():
    rows = heading("The Barrens")
    for index, (title, sub, mark, chain, silver) in enumerate(ROWS_PLAIN):
        icon = (f'<span title="" style="display:inline-flex;padding:1px;border-radius:3px;{"background:#ffffff18;box-shadow:0 0 0 1px #ffd10066;" if index == 3 else ""}">{party(15)}</span>') if index in (1, 3) else ""
        rows += row(title, sub, mark, chain, silver, extra_right=icon, hover=index == 3,
                    sub_color=WHITE if "done" in sub else GREEN, title_color=WHITE if index == 3 else GREY)
    tip = tooltip(f'<div style="color:{GOLD}">Share with your party</div>'
                  f'<div><span style="color:#c69b6d">Brakka Stone</span> <span style="color:{GREEN}">can take it</span></div>'
                  f'<div><span style="color:#3fc7eb">Mira Ashvale</span> <span style="color:#ff7a59">level 12, too low</span></div>'
                  f'<div style="color:#9a9a9a;font-size:11px;margin-top:3px">Click to share</div>')
    return panel(rows, hover_note(tip))

def option_b():
    rows = heading("The Barrens", right=f'<span style="display:inline-flex;align-items:center;gap:2px;margin-right:6px">{party(14, .9)}<span style="font:11px {FRIZ};color:{TAN}">2</span></span>')
    for title, sub, mark, chain, silver in ROWS_PLAIN:
        rows += row(title, sub, mark, chain, silver, sub_color=WHITE if "done" in sub else GREEN)
    rows += heading("Silverpine Forest") .replace("✓ 2", "✓ 1").replace(">4<", ">1<")
    tip = tooltip(f'<div style="color:{GOLD}">2 quests here someone has not got</div><div>The Disruption Ends: <span style="color:#c69b6d">Brakka</span></div>'
                  f'<div>The Guns of Northwatch: <span style="color:#c69b6d">Brakka</span>, <span style="color:#3fc7eb">Mira</span></div>')
    return panel(rows, hover_note(tip))

def option_c():
    rows = heading("The Barrens")
    for index, (title, sub, mark, chain, silver) in enumerate(ROWS_PLAIN):
        rows += row(title, sub, mark, chain, silver, extra_right=party(15) if index == 3 else "", selected=index == 3,
                    sub_color=WHITE if "done" in sub else GREEN)
    tip = tooltip(f'<div style="color:{GOLD}">Not everyone in your party has it</div>'
                  f'<div><span style="color:#c69b6d">Brakka Stone</span> <span style="color:{GREEN}">can take it</span></div>'
                  f'<div><span style="color:#3fc7eb">Mira Ashvale</span> <span style="color:#ff7a59">level 12, too low</span></div>')
    return panel(rows, hover_note(tip))

def option_d():
    rows = heading("The Barrens")
    extras = {1: f' · {party(12)} <span style="color:{TAN}">2 of 4</span>', 3: f' · {party(12)} <span style="color:{TAN}">1 of 4</span>'}
    for index, (title, sub, mark, chain, silver) in enumerate(ROWS_PLAIN):
        rows += row(title, sub, mark, chain, silver, sub_extra=extras.get(index, ""), sub_color=WHITE if "done" in sub else GREEN)
    return panel(rows)

def col(title, text, html, tag=""):
    t = f'<span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">{tag}</span>' if tag else ""
    return (f'<div style="display:flex;flex-direction:column;gap:10px;width:{round(W * 1.6) + 20}px">'
            f'<div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{t}</div>'
            f'<div style="font-size:12.5px;color:#d8cfa8;line-height:1.45;min-height:72px">{text}</div>'
            f'<div style="zoom:1.6">{html}</div></div>')

cols = (col("A. A share button, when it helps", "Shown only on a quest a party member could take but has not, while you can share it: Disruption Ends and Guns of Northwatch here, nothing on the rest. Hover says who, and why the others can't; a click shares it with the party.", option_a(), "Recommended")
        + col("B. On the zone heading", "One icon and a count on the zone's heading: how many quests here someone in the party has not got. The rows stay as they are; hover the heading's icon for which quests and who.", option_b())
        + col("C. On the selected row only", "Only the selected quest shows it, when someone lacks it; hover says who and why. Nothing on the other rows.", option_c())
        + col("D. On the second line", 'In the quiet second line, as text: the icon and how many of the party are on it, "2 of 4". Only in a party.', option_d()))
width = 30 * 2 + 4 * (round(W * 1.6) + 20) + 3 * 36
height = 760
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Party icon on quest rows</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}} :root{{{"".join(f"--{k}:url({v});" for k, v in IMAGES.items())}}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:18px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5;max-width:1200px">The game's group icon (friends-icon-friendsingroup-c60, Forever's) on the quest list, four ways, so it never clutters a row that has nothing to say. Party: Brakka Stone (can take The Disruption Ends and The Guns of Northwatch) and Mira Ashvale (level 12). Drawn at 1.6x the game's size; the rows are as the list draws them now.</div>
<div style="display:flex;gap:36px;align-items:flex-start">{cols}</div>
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
open(os.path.join(OUT, "PartyIcon.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height, len(board) // 1024, "KB")
