"""Compares two records of what was drawn (sim/scenarios/audits/visual-baseline.lua): python visual-diff.py before after
Says, for each state, how many drawn items are in one and not the other, and shows the first few."""
import collections
import os
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".visual")
first, second = sys.argv[1], sys.argv[2]
show = int(sys.argv[3]) if len(sys.argv) > 3 else 3
total = 0
for name in sorted(os.listdir(os.path.join(root, first))):
    path_a, path_b = os.path.join(root, first, name), os.path.join(root, second, name)
    if not os.path.exists(path_b):
        print(f"{name}: missing in {second}")
        total += 1
        continue
    a = collections.Counter(open(path_a, encoding="utf-8").read().splitlines())
    b = collections.Counter(open(path_b, encoding="utf-8").read().splitlines())
    only_a, only_b = a - b, b - a
    # Lines told by their two ends ("line x,y x,y ..."): the same line when each end is within a pixel (the two
    # ways of drawing work the ends out by different sums, and the ends are rounded)
    def ends(text):
        parts = text.split(" ")
        if len(parts) < 3 or parts[0] != "line":
            return None
        try:
            return [float(value) for value in (parts[1] + "," + parts[2]).split(",")], " ".join(parts[3:])
        except ValueError:
            return None
    for line_a in list(only_a.elements()):
        parsed_a = ends(line_a)
        if not parsed_a:
            continue
        for line_b in list(only_b.elements()):
            parsed_b = ends(line_b)
            if parsed_b and parsed_a[1] == parsed_b[1] and all(abs(x - y) <= 1.01 for x, y in zip(parsed_a[0], parsed_b[0])):
                only_a[line_a] -= 1
                only_b[line_b] -= 1
                only_a, only_b = +only_a, +only_b
                break
    count = sum(only_a.values()) + sum(only_b.values())
    total += count
    print(f"{name}: {'same' if count == 0 else f'{sum(only_a.values())} only in {first}, {sum(only_b.values())} only in {second}'} ({sum(a.values())} items)")
    for line in list(only_a)[:show]:
        print(f"    - {line[:260]}")
    for line in list(only_b)[:show]:
        print(f"    + {line[:260]}")
print("IDENTICAL" if total == 0 else f"{total} differences")
