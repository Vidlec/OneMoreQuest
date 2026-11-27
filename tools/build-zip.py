"""Builds the CurseForge zip of OneMoreQuest: the files in release-files.txt, taken from the addon's folder, in a
folder named OneMoreQuest, as OneMoreQuest-<version>.zip (the version read from the TOC). Works on Windows and Mac.

    python build-zip.py [addon folder] [output folder]

Defaults: the addon beside this folder (../addons/OneMoreQuest) and ~/Desktop/OneMoreQuest-CurseForge."""
import os, re, sys, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
source = os.path.expanduser(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "OneMoreQuest")
output = os.path.expanduser(sys.argv[2] if len(sys.argv) > 2 else "~/Desktop/OneMoreQuest-CurseForge")
toc = open(os.path.join(source, "OneMoreQuest.toc"), encoding="utf-8").read()
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
# The title shows the version in the game's AddOns list ("OneMoreQuest v0.16.0"): raised with the Version line
title = re.search(r"^## Title:\s*(.+)$", toc, re.M).group(1)
if f"v{version}|r" not in title:
    sys.exit(f"The TOC's Title ({title.strip()}) does not show the version {version}: raise both together")
target = os.path.join(output, f"OneMoreQuest-{version}.zip")
os.makedirs(output, exist_ok=True)
missing = []
with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
    for line in open(os.path.join(HERE, "release-files.txt"), encoding="utf-8"):
        name = line.strip()
        if not name or name.endswith("/"):
            continue
        path = os.path.join(source, name.split("/", 1)[1])
        if os.path.isfile(path):
            archive.write(path, name)
        else:
            missing.append(name)
print(f"{target} ({os.path.getsize(target) // 1024} KB)")
for name in missing:
    print("not found, left out:", name)
