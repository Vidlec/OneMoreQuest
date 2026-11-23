"""A Design-board artboard: making the selected quest to pick up easy to spot among many."""
import os, random, sys
OUT, MAP_BG, ICONS = sys.argv[1], sys.argv[2], sys.argv[3]
MAP_W, MAP_H, SHEET = 1500, 1000, 1024
TILE_W, TILE_H = 420, 280
# QuestNormal in the game's object icons sheet
LEFT, RIGHT, TOP = 0.7138671875, 0.7763671875, 0.1279296875

def bang(x, y, size=19, style=""):
    k = size / ((RIGHT - LEFT) * SHEET)
    return (f'<div style="position:absolute;left:{x - size / 2:.1f}px;top:{y - size / 2:.1f}px;width:{size}px;height:{size}px;'
            f'background-image:url({ICONS});background-size:{SHEET * k:.1f}px;background-position:{-LEFT * SHEET * k:.1f}px {-TOP * SHEET * k:.1f}px;{style}"></div>')

def glow(x, y, size, alpha=0.5, color="255,209,0"):
    return (f'<div style="position:absolute;left:{x - size / 2:.1f}px;top:{y - size / 2:.1f}px;width:{size}px;height:{size}px;border-radius:50%;'
            f'background:radial-gradient(circle, rgba({color},{alpha}) 0%, rgba({color},{alpha * 0.55}) 35%, rgba({color},0) 70%)"></div>')

random.seed(4)
OTHERS = [(random.uniform(30, 390), random.uniform(30, 250)) for _ in range(22)]
SELECTED = (215, 150)
OTHERS = [p for p in OTHERS if abs(p[0] - SELECTED[0]) > 28 or abs(p[1] - SELECTED[1]) > 28]

def selected(style):
    x, y = SELECTED
    if style == "now":
        return glow(x, y, 29, 0.5) + bang(x, y)
    if style == "bigger":
        return glow(x, y, 46, 0.85) + bang(x, y, 28)
    if style == "pulse":
        ring = (f'<div style="position:absolute;left:{x - 16}px;top:{y - 16}px;width:32px;height:32px;border-radius:50%;'
                f'border:2.5px solid #ffd100;box-sizing:border-box;animation:pulse 1.6s ease-out infinite"></div>')
        return glow(x, y, 40, 0.75) + ring + bang(x, y, 24)
    if style == "beacon":
        beam = (f'<div style="position:absolute;left:{x - 9}px;top:{y - 70}px;width:18px;height:60px;'
                f'background:linear-gradient(to top, rgba(255,209,0,0.75), rgba(255,209,0,0));border-radius:9px 9px 0 0"></div>')
        return beam + glow(x, y, 40, 0.8) + bang(x, y, 24)
    if style == "ring":
        ring = (f'<div style="position:absolute;left:{x - 18}px;top:{y - 18}px;width:36px;height:36px;border-radius:50%;box-sizing:border-box;'
                f'border:3px solid #ffd100;box-shadow:0 0 0 1.5px #3a2400, inset 0 0 0 1.5px #3a2400, 0 0 12px 3px rgba(255,209,0,0.55);'
                f'background:rgba(20,14,4,0.45)"></div>')
        return ring + bang(x, y, 24)
    return ""

def tile(style, dim_others=False):
    others = "".join(bang(x, y, 19, "opacity:0.45;filter:saturate(0.6)" if dim_others else "") for x, y in OTHERS)
    bx, by = -(0.46 * MAP_W - TILE_W / 2), -(0.36 * MAP_H - TILE_H / 2)
    return (f'<div style="position:relative;width:{TILE_W}px;height:{TILE_H}px;border:1px solid #000;overflow:hidden;'
            f'background-image:url({MAP_BG});background-size:{MAP_W}px auto;background-position:{bx:.0f}px {by:.0f}px">{others}{selected(style)}</div>')

VARIANTS = [
    ("now", False, "Now", "The \"!\" with a soft gold glow, the same size as the rest. Easy to lose among many.", False),
    ("bigger", False, "A. Bigger and brighter", "The selected \"!\" half as big again, in a strong gold glow. Simple, and still the game's own mark.", False),
    ("pulse", False, "B. Pulsing ring", "A gold ring that keeps rippling out from it, like a ping: the eye goes there at once. Moves, so it is never missed.", False),
    ("beacon", False, "C. Beacon", "A short gold beam rising from it, as a quest beacon in the world: plain from far away, even zoomed out.", False),
    ("ring", False, "D. Gold ring", "Larger, in a dark disc with a bright gold ring round it, as a focused quest's coin is: still, crisp, unmistakable.", False),
    ("ring", True, "E. Gold ring, the rest faded", "D, and while a quest is selected the other \"!\" fade back; they return as it is let go. The strongest.", True),
]

def cell(style, dim, title, text, recommended):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if recommended else ""
    flag += ' <span style="font:600 10px/1 \'Source Sans 3\';color:#d8cfa8;border:1px solid #6b6450;border-radius:3px;padding:1px 5px;margin-left:6px">Now</span>' if style == "now" else ""
    return (f'<div style="display:flex;flex-direction:column;gap:8px"><div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:34px">{text}</div>{tile(style, dim)}</div>')

width, height = 30 * 2 + 3 * 420 + 2 * 26, 30 * 2 + 40 + 2 * 380
cells = "".join(cell(*v) for v in VARIANTS)
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Selected quest to pick up</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600&amp;display=swap">
<style>body{{margin:0}} @keyframes pulse {{ 0% {{ transform: scale(0.7); opacity: 1 }} 100% {{ transform: scale(2.1); opacity: 0 }} }}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:grid;grid-template-columns:repeat(3,420px);column-gap:26px;row-gap:30px;align-content:start;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
<div style="grid-column:1/-1;font-size:13px;color:#d8cfa8">The quest selected on the Available tab, in the middle, among the zone's other quests to pick up: ways to make it easy to spot.</div>
{cells}
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
open(os.path.join(OUT, "PickupHighlight.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
