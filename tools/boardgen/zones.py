"""A Design-board artboard: ways to draw quest areas, on the real Barrens map and minimap."""
import math, os, random, sys
OUT, MAP_BG, MINI_BG = sys.argv[1], sys.argv[2], sys.argv[3]

MAP_W, MAP_H = 1500, 1000  # the Barrens map art drawn at this size
TILE_W, TILE_H = 420, 270
BLUE, ORANGE = "#4c9eff", "#e8743b"
GOLD = "#ffd100"
REACH, SOFTNESS, CELL = 22.0, 0.85, 2.0

random.seed(7)
def cluster(cx, cy, count, spread):
    return [(cx + random.gauss(0, spread), cy + random.gauss(0, spread * 0.8)) for _ in range(count)]

# Two quests whose spawns overlap: one along a valley, one in two groups
QUESTS = {
    "blue": cluster(150, 120, 14, 28) + cluster(230, 160, 10, 22),
    "orange": cluster(250, 110, 12, 24) + cluster(340, 190, 9, 18) + [(80, 230)],
}

def contour(points):
    """Marching squares on the soft-glow field: closed loops of points (in tile pixels)."""
    spread = SOFTNESS * REACH
    threshold = math.exp(-REACH * REACH / (2 * spread * spread))
    def value(x, y):
        return sum(math.exp(-((px - x) ** 2 + (py - y) ** 2) / (2 * spread * spread)) for px, py in points) - threshold
    xs = [p[0] for p in points]; ys = [p[1] for p in points]
    margin = 3 * spread
    x0, y0 = min(xs) - margin, min(ys) - margin
    cols, rows = int((max(xs) + margin - x0) / CELL) + 1, int((max(ys) + margin - y0) / CELL) + 1
    grid = [[value(x0 + c * CELL, y0 + r * CELL) for c in range(cols + 1)] for r in range(rows + 1)]
    segments = []
    def cross(a, b, va, vb):
        t = va / (va - vb)
        return (round(a[0] + (b[0] - a[0]) * t, 3), round(a[1] + (b[1] - a[1]) * t, 3))
    for r in range(rows):
        for c in range(cols):
            corners = [(x0 + c * CELL, y0 + r * CELL), (x0 + (c + 1) * CELL, y0 + r * CELL),
                       (x0 + (c + 1) * CELL, y0 + (r + 1) * CELL), (x0 + c * CELL, y0 + (r + 1) * CELL)]
            values = [grid[r][c], grid[r][c + 1], grid[r + 1][c + 1], grid[r + 1][c]]
            found = []
            for side in range(4):
                n = (side + 1) % 4
                if (values[side] > 0) != (values[n] > 0):
                    found.append(cross(corners[side], corners[n], values[side], values[n]))
            if len(found) == 2:
                segments.append((found[0], found[1]))
            elif len(found) == 4:
                segments.append((found[0], found[1])); segments.append((found[2], found[3]))
    # Chain into loops
    by_end = {}
    for i, (a, b) in enumerate(segments):
        by_end.setdefault(a, []).append(i); by_end.setdefault(b, []).append(i)
    used, loops = set(), []
    for i, (a, b) in enumerate(segments):
        if i in used: continue
        used.add(i); loop = [a, b]
        while True:
            nxt = next((j for j in by_end.get(loop[-1], []) if j not in used), None)
            if nxt is None: break
            used.add(nxt); sa, sb = segments[nxt]
            loop.append(sb if sa == loop[-1] else sa)
        loops.append(loop)
    return loops

def path_d(loops, dx=0, dy=0, k=1.0):
    parts = []
    for loop in loops:
        if len(loop) < 3: continue
        pts = " L".join(f"{(x + dx) * k:.1f},{(y + dy) * k:.1f}" for x, y in loop[::2])
        parts.append("M" + pts + " Z")
    return " ".join(parts)

SHAPES = {name: contour(pts) for name, pts in QUESTS.items()}

KILL = '<path d="M2.6 9.4 L8.8 3.2 L10 2 M3.2 6.6 L5.4 8.8 M1.8 10.2 L2.8 9.2" fill="none" stroke="{c}" stroke-width="1.6" stroke-linecap="round"></path>'
SACK = '<path d="M4.4 4.7 L3.1 2.3 L5.1 3.2 L6 2 L6.9 3.2 L8.9 2.3 L7.6 4.7 Z M4.1 5.4 H7.9 Q10.6 7.2 10 9.4 Q9.4 11.1 6 11.1 Q2.6 11.1 2 9.4 Q1.4 7.2 4.1 5.4 Z" fill="{c}"></path>'

def icons(name, glyph, color, focused, k=1.0, dx=0, dy=0):
    out = []
    taken = set()
    for x, y in QUESTS[name]:
        cell = (round(x / 15), round(y / 15))
        if cell in taken: continue
        taken.add(cell)
        cx, cy = cell[0] * 15 + dx, cell[1] * 15 + dy
        cx, cy = cx * k, cy * k
        a = 1 if focused else 0.6
        out.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="7.5" fill="url(#glow-{name})" opacity="{0.85 if focused else 0.4}"></circle>')
        g = glyph.replace("{c}", "#fff3d0")
        e = glyph.replace("{c}", "#1a1208").replace('stroke-width="1.6"', 'stroke-width="3.2"').replace('fill="#1a1208"', 'fill="#1a1208" stroke="#1a1208" stroke-width="1.8"')
        out.append(f'<g transform="translate({cx - 5:.1f},{cy - 5:.1f}) scale(0.833)" opacity="{a}">{e}{g}</g>')
    return "".join(out)

def defs():
    out = []
    for name, color in (("blue", BLUE), ("orange", ORANGE)):
        out.append(f'<radialGradient id="glow-{name}"><stop offset="0" stop-color="{color}" stop-opacity="1"></stop><stop offset="1" stop-color="{color}" stop-opacity="0"></stop></radialGradient>')
        out.append(f'<pattern id="hatch-{name}" width="6" height="6" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="2" height="6" fill="{color}"></rect></pattern>')
    out.append('<filter id="blur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="5"></feGaussianBlur></filter>')
    out.append('<filter id="blur-soft" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3"></feGaussianBlur></filter>')
    return "<defs>" + "".join(out) + "</defs>"

def area(style, name, color, focused, d, uid):
    """One quest's area in a style."""
    f = focused
    if style == "now":
        return (f'<path d="{d}" fill="{color}" fill-opacity="{0.22 if f else 0.08}" fill-rule="nonzero"></path>'
                f'<path d="{d}" fill="none" stroke="#0a0f1f" stroke-opacity="{0.45 if f else 0.2}" stroke-width="4" stroke-linejoin="round"></path>'
                f'<path d="{d}" fill="none" stroke="{color}" stroke-opacity="{0.95 if f else 0.5}" stroke-width="2" stroke-linejoin="round"></path>')
    if style == "glow":
        return f'<path d="{d}" fill="{color}" fill-opacity="{0.42 if f else 0.18}" filter="url(#blur)"></path>'
    if style == "inner":
        clip = f'<clipPath id="clip-{uid}"><path d="{d}"></path></clipPath>'
        return (clip + f'<g clip-path="url(#clip-{uid})"><path d="{d}" fill="{color}" fill-opacity="{0.06 if f else 0.03}"></path>'
                f'<path d="{d}" fill="none" stroke="{color}" stroke-opacity="{0.75 if f else 0.35}" stroke-width="14" filter="url(#blur-soft)"></path></g>'
                f'<path d="{d}" fill="none" stroke="{color}" stroke-opacity="{0.9 if f else 0.4}" stroke-width="1.2"></path>')
    if style == "outline":
        dash = "" if f else ' stroke-dasharray="6 4"'
        return (f'<path d="{d}" fill="none" stroke="#0a0f1f" stroke-opacity="{0.4 if f else 0.2}" stroke-width="4" stroke-linejoin="round"{dash}></path>'
                f'<path d="{d}" fill="none" stroke="{color}" stroke-opacity="{1 if f else 0.65}" stroke-width="2" stroke-linejoin="round"{dash}></path>')
    if style == "hatch":
        return (f'<path d="{d}" fill="url(#hatch-{name})" fill-opacity="{0.45 if f else 0.2}"></path>'
                f'<path d="{d}" fill="none" stroke="{color}" stroke-opacity="{0.9 if f else 0.45}" stroke-width="1.5"></path>')
    if style == "dots":
        return (f'<path d="{d}" fill="{color}" fill-opacity="{0.12 if f else 0.05}"></path>'
                f'<path d="{d}" fill="none" stroke="#0a0f1f" stroke-opacity="{0.5 if f else 0.25}" stroke-width="4.5" stroke-linecap="round" stroke-dasharray="0.1 7"></path>'
                f'<path d="{d}" fill="none" stroke="{color}" stroke-opacity="{1 if f else 0.55}" stroke-width="3" stroke-linecap="round" stroke-dasharray="0.1 7"></path>')
    # the game's own look: soft gold, the same for every quest
    return (f'<path d="{d}" fill="{GOLD}" fill-opacity="{0.2 if f else 0.12}"></path>'
            f'<path d="{d}" fill="none" stroke="#5a3a08" stroke-opacity="{0.6 if f else 0.35}" stroke-width="5" filter="url(#blur-soft)"></path>')

def scene(style, k=1.0, dx=0, dy=0, with_icons=True, uid=""):
    out = []
    for name, color, focused in (("orange", ORANGE, False), ("blue", BLUE, True)):
        d = path_d(SHAPES[name], dx, dy, k)
        out.append(area(style, name, color, focused, d, uid + name))
    if with_icons:
        out.append(icons("orange", SACK, ORANGE, False, k, dx, dy))
        out.append(icons("blue", KILL, BLUE, True, k, dx, dy))
    return "".join(out)

def map_tile(style, uid):
    bx, by = -(0.46 * MAP_W - TILE_W / 2), -(0.36 * MAP_H - TILE_H / 2)
    svg = f'<svg width="{TILE_W}" height="{TILE_H}" style="position:absolute;left:0;top:0">{defs()}{scene(style, uid=uid)}</svg>'
    return (f'<div style="position:relative;width:{TILE_W}px;height:{TILE_H}px;border:1px solid #000;overflow:hidden;'
            f'background-image:url({MAP_BG});background-size:{MAP_W}px auto;background-position:{bx:.0f}px {by:.0f}px">{svg}</div>')

def minimap_tile(style, uid):
    size = 150
    # The minimap shows a closer piece round the player, at twice the map's scale
    svg = (f'<svg width="{size}" height="{size}" style="position:absolute;left:0;top:0">{defs()}'
           f'<clipPath id="round-{uid}"><circle cx="{size/2}" cy="{size/2}" r="{size/2}"></circle></clipPath>'
           f'<g clip-path="url(#round-{uid})">{scene(style, k=2.0, dx=-160, dy=-100, uid=uid + "m")}</g>'
           f'<path d="M{size/2},{size/2 - 7} l5,12 l-5,-3 l-5,3 z" fill="#fff" stroke="#000" stroke-width="1"></path></svg>')
    return (f'<div style="position:relative;width:{size}px;height:{size}px;border-radius:50%;overflow:hidden;flex:none;'
            f'box-shadow:0 0 0 3px #8a6d2b,0 0 0 4px #000;background-image:url({MINI_BG});background-size:300px auto;background-position:-70px -60px">{svg}</div>')

VARIANTS = [
    ("now", "Now", "A light fill in the quest's colour, a coloured edge over a soft dark line. Plain, a little busy where many quests overlap.", False),
    ("glow", "A. Soft glow", "No line: a fill that fades out at its edge, like a heat map. The calmest; overlapping quests blend. Its edge is less exact.", False),
    ("inner", "B. Glowing edge", "A band of colour just inside the edge, fading inward, the middle clear: the map under it stays readable, the edge still plain.", True),
    ("outline", "C. Outline only", "Just the edge, no fill; dashed for quests not in focus. The lightest; overlaps stay readable, but the inside is not shaded.", False),
    ("hatch", "D. Hatched", "Fine diagonal stripes in the quest's colour, a thin edge. Reads as \"in this area\" at a glance, even over busy ground.", False),
    ("dots", "E. Dotted edge", "A dotted edge over a faint fill, as old maps mark a region. Light and a little playful.", False),
    ("game", "F. The game's look", "A soft gold fill with a blurred brown edge, as the game draws its own quest areas; the same for every quest, so quests are told apart only by their icons.", False),
]

def cell(style, title, text, is_recommended, index):
    flag = ' <span style="font:600 10px/1 \'Source Sans 3\';color:#1c1912;background:#ffd100;border-radius:3px;padding:2px 5px;margin-left:6px">Recommended</span>' if is_recommended else ""
    flag += ' <span style="font:600 10px/1 \'Source Sans 3\';color:#d8cfa8;border:1px solid #6b6450;border-radius:3px;padding:1px 5px;margin-left:6px">Now</span>' if style == "now" else ""
    return (f'<div style="display:flex;flex-direction:column;gap:8px">'
            f'<div style="font:400 18px/1.2 Marcellus,Georgia,serif;color:#ffd100">{title}{flag}</div>'
            f'<div style="font-size:12px;line-height:1.45;color:#d8cfa8;min-height:52px">{text}</div>'
            f'<div style="display:flex;gap:14px;align-items:center">{map_tile(style, f"v{index}")}{minimap_tile(style, f"v{index}")}</div></div>')

width, height = 30 * 2 + 2 * 610 + 30, 30 * 2 + 4 * 400 + 60
cells = "".join(cell(s, t, x, r, i) for i, (s, t, x, r) in enumerate(VARIANTS))
legend = ('<div style="grid-column:1/-1;font-size:13px;color:#d8cfa8;line-height:1.5">Ways to draw quest areas: two quests overlapping, '
          '<span style="color:#7cb8ff">blue in focus</span> and <span style="color:#f0a070">orange not</span>, on the map and the minimap. '
          'The shapes are the addon\'s own (each spawn\'s soft glow, merged); only the drawing differs.</div>')
board = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Ways to draw areas</title>
<script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Marcellus&amp;family=Source+Sans+3:wght@400;600&amp;display=swap">
<style>body{{margin:0}}</style>
</helmet>
<div style="width:{width}px;height:{height}px;box-sizing:border-box;padding:30px;display:grid;grid-template-columns:repeat(2,610px);column-gap:30px;row-gap:34px;align-content:start;background:#2b3427;font-family:'Source Sans 3',system-ui,sans-serif;color:#e6e6e6">
{legend}
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
open(os.path.join(OUT, "AreaLooks.dc.html"), "w", encoding="utf-8").write(board)
print("ok", width, height)
