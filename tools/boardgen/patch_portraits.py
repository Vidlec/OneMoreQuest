import sys, base64
p, portraits = sys.argv[1], sys.argv[2]
s = open(p).read()
def patch(old, new):
    global s
    assert old in s, old[:60]; s = s.replace(old, new, 1)
uris = {}
for name in ["male-tauren", "female-orc", "male-troll", "female-scourge"]:
    uris[name] = "data:image/png;base64," + base64.b64encode(open(f"{portraits}/{name}.png", "rb").read()).decode()
patch('''GOLD, TAN, GREEN, GREY''', f'''PORTRAITS = {uris!r}
GOLD, TAN, GREEN, GREY''')
patch('''    {"name": "Garra Windmane", "short": "GW",''', '''    {"name": "Garra Windmane", "short": "GW", "portrait": "male-tauren",''')
patch('''    {"name": "Brakkastonex Thunderhoofs", "short": "BT",''', '''    {"name": "Brakkastonex Thunderhoofs", "short": "BT", "portrait": "female-orc",''')
patch('''    {"name": "Mirandel Ashvale", "short": "MA",''', '''    {"name": "Mirandel Ashvale", "short": "MA", "portrait": "female-scourge",''')
patch('''    {"name": "Olen Rusk", "short": "OR",''', '''    {"name": "Olen Rusk", "short": "OR", "portrait": "male-troll",''')
# The avatar: the character's portrait in a round gold frame, as the game's unit frames; greyed without the quest
patch('''def avatar(m, size, dark=True):''', '''def avatar(m, size, dark=True, badge=False):
    image = PORTRAITS[m["portrait"]]
    filt = "" if m["has"] else "filter:grayscale(1) brightness(.75);"
    ring = "#c9a227" if m["has"] else "#6b6450"
    face = (f'<span style="position:relative;display:inline-block;width:{size}px;height:{size}px;border-radius:50%;'
            f'background:#000 url({image}) center/112% no-repeat;{filt}box-shadow:0 0 0 2px {ring},0 0 0 3px #000,inset 0 0 4px #000"></span>')
    if not badge:
        return face
    b = max(13, round(size * 0.5))
    color = m["color"] if m["has"] else GREY
    tag = (f'<span style="position:absolute;left:{-size * 0.18:.0f}px;bottom:{-size * 0.14:.0f}px;width:{b}px;height:{b}px;border-radius:50%;'
           f'background:#16120a;box-shadow:0 0 0 1.5px #c9a227,0 0 0 2.5px #000;display:flex;align-items:center;justify-content:center;'
           f'font:700 {b * 0.46:.0f}px/1 \\'Source Sans 3\\';color:{color}">{m["short"]}</span>')
    return f'<span style="position:relative;display:inline-block">{face}{tag}</span>'

def initials(m, width, light):
    color = m["color"] if light else ("#3a2400" if m["color"] == "#ffffff" else "#2b1d0e")
    if not m["has"]:
        color = GREY if light else "#8a7a5a"
    return f'<span title="{m["name"]}" style="display:block;width:{width}px;text-align:center;font:700 11px/1.1 \\'Source Sans 3\\';color:{color}">{m["short"]}</span>'

def old_avatar(m, size, dark=True):''')
patch('''    if place == "split":
        parts = [label(m, width, light, "first"), avatar(m, size), label(m, width, light, "last")]
    else:
        parts = [label(m, width, light), avatar(m, size)] if place == "above" else [avatar(m, size), label(m, width, light)]''', '''    if place == "badge":
        parts = [avatar(m, size, badge=True)]
    else:
        parts = [initials(m, width, light), avatar(m, size)] if place == "above" else [avatar(m, size), initials(m, width, light)]''')
patch('''gap:2px;width:{width}px">''', '''gap:4px;width:{width}px" title="{m['name']}">''')
patch('''    heads = "".join(head(m, col, 20, place, True) for m in PARTY)''', '''    heads = "".join(head(m, col, 24, place, True) for m in PARTY)''')
patch('''    heads = "".join(head(m, col, 26, place, False) for m in PARTY)''', '''    heads = "".join(head(m, col, 32, place, False) for m in PARTY)''')
patch('''    col = 56''', '''    col = 50''')
patch('''cols = (column("A. Name below the avatar",''', '''cols = (column("A. Initials below the portrait",''')
patch('''"The avatar heads the column, first and last name under it on two lines, next to the numbers they label. A name longer than the column is cut with \\"…\\"; hover shows it whole.",
               tracker("below") + page("below"), True)''', '''"The character's portrait heads the column, its initials under it, right over the counts. Hover shows the full name.",
               tracker("below") + page("below"))''')
patch('''column("B. Name above the avatar", "First and last name on top, the avatar right over its column of counts, so the circle sits closest to the numbers.",''', '''column("B. Initials above the portrait", "The initials on top, the portrait right over its column of counts.",''')
patch('''column("C. First name above, last name below", "The avatar between the two names: the first name over it, the last name under it. As compact as A and B, with the circle in the middle of the name.",
                 tracker("split") + page("split")))''', '''column("C. Initials in a badge on the portrait", "As the game's unit frame shows the level: the initials in a small round badge at the portrait's corner. The shortest header, nothing to line up.",
                 tracker("badge") + page("badge"), True))''')
patch('''Initials in the avatar, the character's name with it. Every character has a first and a last name; the initials are their first letters. Brakkastonex Thunderhoofs shows how a long name is cut. Mirandel Ashvale does not have the quest (dashed), Olen Rusk does not share progress.''', '''Each member's portrait, as the game's unit frames show it (in game their own face; here the game's race portraits stand in), with the initials of their first and last name. Mirandel Ashvale does not have the quest (greyed), Olen Rusk does not share progress. Hovering a portrait gives the full name.''')
open(p, "w").write(s)
print("patched")
