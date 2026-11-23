"""A Design-board artboard: six ways for the quest list to mark the zone you are in."""
import os, sys
OUT, ART = sys.argv[1], sys.argv[2]
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "zonenames.py")).read()
exec(src.split("# A. What a heading is")[0].replace("OUT, ART = sys.argv[1], sys.argv[2]", "").replace(
    'exec(("def col(" + src.split("def col(")[1].split("cols = (")[0]).replace("1.6", "1.4"))',
    'exec(("def col(" + src.split("def col(")[1].split("cols = (")[0]).replace("1.6", "1.4"))'))
HEADS = [("The Barrens", "zone", 4, 2, True, True, True), ("Cooking", "category", 1, 0, False, False, False), ("Hillsbrad Foothills", "zone", 2, 1, False, False, True),
         ("Silverpine Forest", "zone", 1, 1, False, False, True), ("Thunder Bluff", "zone", 1, 1, False, False, False),
         ("Razorfen Kraul", "dungeon", 1, 0, False, False, True), ("Wailing Caverns", "dungeon", 2, 0, False, False, False)]

def base(title, kind, is_tracked, size=14, color=None):
    return name(title, color or tracked_color(kind, is_tracked), size) + kind_icon(kind, 14)

# A. The game's gold map pin at the right end, still
def head_a(title, kind, count, ready, is_open, is_here, is_tracked):
    pin = img(PIN_BIG, 18) if is_here else ""
    return band(f'{fold(is_open)}{base(title, kind, is_tracked)}<span style="flex:1"></span>{counts(count, ready)}{pin}')

# B. Gold is where you are: only that name is gold
def head_b(title, kind, count, ready, is_open, is_here, is_tracked):
    return band(f'{fold(is_open)}{base(title, kind, is_tracked, color=GOLD if is_here else None)}<span style="flex:1"></span>{counts(count, ready)}')

# C. The band lit: a fine gold rim round your zone's band
def head_c(title, kind, count, ready, is_open, is_here, is_tracked):
    lit = "box-shadow:inset 0 0 0 1px #c9a22799,inset 0 -2px 0 #ffd10066;" if is_here else ""
    return band(f'{fold(is_open)}{base(title, kind, is_tracked)}<span style="flex:1"></span>{counts(count, ready)}', lit)

# D. A gold line under the band, as the game marks a chosen tab
def head_d(title, kind, count, ready, is_open, is_here, is_tracked):
    line = (f'<span style="position:absolute;left:10px;right:10px;bottom:7px;height:2px;border-radius:1px;'
            f'background:linear-gradient(90deg,transparent,#ffd100 18%,#ffd100 82%,transparent);box-shadow:0 0 4px #ffd10088"></span>') if is_here else ""
    return band(f'{line}{fold(is_open)}{base(title, kind, is_tracked)}<span style="flex:1"></span>{counts(count, ready)}')

# E. "here" in words, at the start of the right side
def head_e(title, kind, count, ready, is_open, is_here, is_tracked):
    lead = f'<span style="color:{GOLD}">here</span>' if is_here else ""
    return band(f'{fold(is_open)}{base(title, kind, is_tracked)}<span style="flex:1"></span>{counts(count, ready, lead)}')

# F. A gold edge down the band's left side
def head_f(title, kind, count, ready, is_open, is_here, is_tracked):
    edge = '<span style="position:absolute;left:0;top:4px;bottom:9px;width:3px;background:#ffd100;box-shadow:0 0 4px #ffd10088"></span>' if is_here else ""
    return band(f'{edge}{fold(is_open)}{base(title, kind, is_tracked)}<span style="flex:1"></span>{counts(count, ready)}')

LEGEND = ('<div style="font-size:12px;color:#a8a080;line-height:1.5;max-width:1500px">You are in <b style="color:#d8cfa8">The Barrens</b>. '
          'As built: names white when a tracked quest is inside and muted when none is, a dungeon’s gate or a category’s picture after the name. '
          'Each design marks only the zone you are in; hovering it says “You are here” in every one.</div>')
row1 = (col("A. Map pin", "The game's gold map pin, still, at the right end of the band, where the flame was.", build(head_a), "Recommended")
        + col("B. Gold name", "Only the zone you are in has a gold name; nothing is added. Gold reads as “you” in the game's own lists.", build(head_b))
        + col("C. Lit band", "A fine gold rim round your zone's band, a little brighter along its foot.", build(head_c)))
row2 = (col("D. Gold underline", "A short gold line under the name and counts, softly glowing, as the game marks the chosen tab.", build(head_d))
        + col("E. In a word", "“here” in gold at the start of the right side, before the counts.", build(head_e))
        + col("F. Gold edge", "A gold edge down the left of your zone's band, as the settings and chronicle mark the chosen section.", build(head_f)))
width = 30 * 2 + 3 * (round(W * 1.4) + 20) + 2 * 36
height = int(sys.argv[3]) if len(sys.argv) > 3 else 1300
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Marking the zone you are in</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600;700&amp;display=swap">
<style>body{{margin:0}} :root{{{"".join(f"--{k}:url({v});" for k, v in IMAGES.items())}}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:flex;flex-direction:column;gap:28px;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
{LEGEND}
<div style="display:flex;gap:36px;align-items:flex-start">{row1}</div>
<div style="display:flex;gap:36px;align-items:flex-start">{row2}</div>
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
open(os.path.join(OUT, "HereZone.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height, len(board) // 1024, "KB")
