import sys
p=sys.argv[1]; s=open(p).read()
def patch(old,new):
    global s
    assert old in s, old[:60]; s=s.replace(old,new,1)
patch('''    {"name": "Garra", "short": "GA",''','''    {"name": "Garra Windmane", "short": "GW",''')
patch('''    {"name": "Brakkastonex", "short": "BR",''','''    {"name": "Brakkastonex Thunderhoofs", "short": "BT",''')
patch('''    {"name": "Mirandel", "short": "MI",''','''    {"name": "Mirandel Ashvale", "short": "MA",''')
patch('''    {"name": "Olenrusk", "short": "OL",''','''    {"name": "Olen Rusk", "short": "OR",''')
patch('''def label(m, width, light):''','''def label(m, width, light, part=None):''')
patch('''    return (f'<span style="display:block;width:{width}px;text-align:center;font:600 10.5px/1.1 \\'Source Sans 3\\';color:{color};'
            f'white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{m["name"]}</span>')''','''    first, last = m["name"].split(" ", 1)
    words = [first, last] if part is None else [first if part == "first" else last]
    return "".join(f'<span style="display:block;width:{width}px;text-align:center;font:600 10.5px/1.15 \\'Source Sans 3\\';color:{color};'
                   f'white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{word}</span>' for word in words)''')
patch('''    parts = [label(m, width, light), avatar(m, size)] if place == "above" else [avatar(m, size), label(m, width, light)]''','''    if place == "split":
        parts = [label(m, width, light, "first"), avatar(m, size), label(m, width, light, "last")]
    else:
        parts = [label(m, width, light), avatar(m, size)] if place == "above" else [avatar(m, size), label(m, width, light)]''')
patch('''                 tracker("above") + page("above")))''','''                 tracker("above") + page("above"))
        + column("C. First name above, last name below", "The avatar between the two names: the first name over it, the last name under it. As compact as A and B, with the circle in the middle of the name.",
                 tracker("split") + page("split")))''')
patch('''width, height = 30 * 2 + 2 * 400 + 40, 900''','''width, height = 30 * 2 + 3 * 400 + 2 * 40, 940''')
patch('''The avatar heads the column and the name reads under it, next to the numbers it labels. Long names are cut with \\"…\\"; hover shows them whole.''','''The avatar heads the column, first and last name under it on two lines, next to the numbers they label. A name longer than the column is cut with \\"…\\"; hover shows it whole.''')
patch('''The name on top, the avatar right over its column of counts, so the circle sits closest to the numbers.''','''First and last name on top, the avatar right over its column of counts, so the circle sits closest to the numbers.''')
patch('''WoW names are one word of up to 12 letters (Brakkastonex here is the longest kind), so the initials are its first two letters. Mirandel does not have the quest (dashed), Olenrusk does not share progress.''','''Every character has a first and a last name; the initials are their first letters. Brakkastonex Thunderhoofs shows how a long name is cut. Mirandel Ashvale does not have the quest (dashed), Olen Rusk does not share progress.''')
open(p,'w').write(s)
print("patched")
