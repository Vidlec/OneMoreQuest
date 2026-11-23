"""A Design-board artboard: ideas for the quest chain step on the quest list's rows."""
import os, sys
OUT, ART = sys.argv[1], sys.argv[2]
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "partyicon.py")).read()
exec(src.split("ROWS_PLAIN = ")[0].replace("OUT, ART = sys.argv[1], sys.argv[2]", ""))
exec("def col(" + src.split("def col(")[1].split("cols = (")[0])
STORY, BOOK = image("story", "questlog-storylineicon.png"), image("book", "campaign-questlog-lorebook.png")
PIP_ON, PIP_OFF = image("pipon", "housing-dashboard-fillbar-pip-complete.png"), image("pipoff", "housing-dashboard-fillbar-pip-incomplete.png")
TICK = image("tick", "questlog-icon-checkmark-yellow.png")

QUESTS = [("[13] Raptor Thieves", "✓ Gazrog", dashed(), 1, 2, GREEN, "[18] Raptor Horns"),
          ("[15] The Disruption Ends", "1 of 3 done", coin(KILL), 2, 2, WHITE, None),
          ("[24] Test of Lore", "1 of 2 done", coin(LOOT), 4, 6, WHITE, "[27] Test of Lore"),
          ("[21] Ziz Fizziks", "✓ Sputtervalve", dashed(), 1, 5, GREEN, "[27] Further Instructions"),
          ("[20] The Guns of Northwatch", "1 of 4 done", coin(KILL), None, None, WHITE, None)]

def icon(src, size, opacity=1):
    return f'<span style="display:inline-block;width:{size}px;height:{size}px;flex:none;opacity:{opacity};background:{src} center/contain no-repeat;vertical-align:-2px"></span>'

def pips(step, total):
    if total > 6:
        return f'{icon(STORY, 12, .9)} <span>{step}/{total}</span>'
    out = ""
    for index in range(1, total + 1):
        if index < step:
            out += f'<span style="display:inline-block;width:6px;height:6px;margin-left:2px;transform:rotate(45deg);background:#c9a227"></span>'
        elif index == step:
            out += f'<span style="display:inline-block;width:7px;height:7px;margin-left:2px;transform:rotate(45deg);background:{GOLD};box-shadow:0 0 4px #ffd100aa"></span>'
        else:
            out += f'<span style="display:inline-block;width:6px;height:6px;margin-left:2px;transform:rotate(45deg);box-shadow:inset 0 0 0 1px #8a7a55"></span>'
    return f'<span style="display:inline-flex;align-items:center;gap:1px;padding-right:2px">{out}</span>'

def make(chain_right=None, chain_sub=None, chain_title=None):
    rows = heading("The Barrens")
    for title, sub, mark, step, total, sub_color, after in QUESTS:
        right = chain_right(step, total, after) if (chain_right and step) else ""
        extra = chain_sub(step, total, after) if (chain_sub and step) else ""
        shown_title = chain_title(title, step, total) if (chain_title and step) else title
        rows += row(shown_title, sub, mark, "", 5, extra_right=f'<span style="font:11px {FRIZ};color:{TAN};white-space:nowrap">{right}</span>' if right else "",
                    sub_extra=extra, sub_color=sub_color)
    return panel(rows)

current = make(lambda step, total, after: f'{masked(CHAIN, TAN, 11)} {step}/{total}')
storyline = make(lambda step, total, after: f'{icon(STORY, 13)} {step}/{total}')
pip_row = make(lambda step, total, after: pips(step, total))
left = make(lambda step, total, after: (f'{icon(STORY, 13)} +{total - step}' if step < total else f'{icon(TICK, 11)} <span style="color:{GOLD}">last</span>'))
second = make(None, lambda step, total, after: f' · <span style="color:{TAN}">{icon(STORY, 11)} {step} of {total}</span>')
book_hover = make(lambda step, total, after: icon(STORY, 13, .85))

def note(text):
    return f'<div style="margin-top:8px;font:11px {FRIZ};color:#a8a080;line-height:1.45">{text}</div>'

def tip_box(lines):
    return f'<div style="margin-top:6px">{tooltip(lines, 250)}</div>'

chain_tip = tip_box(f'<div style="color:{GOLD}">Quest chain, step 1 of 5</div><div style="color:{GOLD}">[21] Ziz Fizziks (this one)</div><div>[27] Further Instructions</div><div>[27] Super Reaper 6000</div><div style="color:#9a9a9a">and 2 more</div>')

cols = (col("Now: the chain and 1/2", "As the list writes it today, for comparison: the chain glyph, then the step.", current)
        + col("A. The game's storyline icon", "The modern quest log's own sign of a quest in a storyline (questlog-storylineicon), with the step. The same reading as now, in the game's own picture.", storyline, "Recommended")
        + col("B. Step pips", "A diamond for each step: done ones gold, this one bright, the rest hollow, so how far along reads at a glance. Over six steps, the storyline icon and 4/11.", pip_row)
        + col("C. Steps to go", "What is left, not where you are: +1 for one more quest after this, a gold tick and “last” on the chain's final step, the one that pays out.", left))
cols2 = (col("D. On the second line", "Moved off the title line, which keeps the whole title: “1 of 3 done · step 2 of 2” with the storyline icon.", second)
         + col("E. Just the icon", "Only the storyline icon at the right; the step and the whole chain in its tooltip on hover. The quietest row.", book_hover + note("Hovering the icon:") + chain_tip))
width = 30 * 2 + 4 * (round(W * 1.6) + 20) + 3 * 36
height = 1370
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Quest chain on quest rows</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}} :root{{{"".join(f"--{k}:url({v});" for k, v in IMAGES.items())}}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:30px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="font-size:13px;color:#d8cfa8;line-height:1.5;max-width:1200px">Ways to show that a quest is a step of a chain, on the quest list's rows. Raptor Thieves (1 of 2), The Disruption Ends (the last of 2), Test of Lore (4 of 6), Ziz Fizziks (1 of 5); The Guns of Northwatch is not in a chain. Drawn at 1.6x the game's size.</div>
<div style="display:flex;gap:36px;align-items:flex-start">{cols}</div>
<div style="display:flex;gap:36px;align-items:flex-start">{cols2}</div>
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
open(os.path.join(OUT, "ChainMarks.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height, len(board) // 1024, "KB")
