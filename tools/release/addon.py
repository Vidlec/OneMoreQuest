"""What the release tools know about the addon, read from its own files (nothing kept by hand twice):

- the TOC: its version, its title, and the files the game loads, in order;
- CHANGELOG.md: the notes of each version (a "## <version>" heading, up to the next one);
- .pkgmeta: the addon's relations on CurseForge (required-dependencies, optional-dependencies, tools-used...).

Used by build_zip.py, notes.py and curseforge.py; standard library only, Python 3.9 and later."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass, field

REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ADDON_NAME = "OneMoreQuest"
ADDON_DIR = os.path.join(REPO_ROOT, "addons", ADDON_NAME)

# A version as the TOC writes it: 1.2.3, or 1.2.3-beta1 for a pre-release
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?$")


class ReleaseError(Exception):
    """Something in the addon's files a release cannot go out with: said in a sentence, for the CI log."""


@dataclass
class Toc:
    version: str
    title: str
    interface: str
    files: list[str] = field(default_factory=list)  # as the game loads them, with forward slashes

    @property
    def is_prerelease(self) -> bool:
        return "-" in self.version


def read_toc(addon_dir: str = ADDON_DIR) -> Toc:
    path = os.path.join(addon_dir, f"{ADDON_NAME}.toc")
    if not os.path.isfile(path):
        raise ReleaseError(f"{path} is not there: no addon to release")
    with open(path, encoding="utf-8-sig") as handle:
        lines = [line.strip() for line in handle]
    tags: dict[str, str] = {}
    files: list[str] = []
    for line in lines:
        if line.startswith("##"):
            key, _, value = line[2:].partition(":")
            tags[key.strip()] = value.strip()
        elif line and not line.startswith("#"):
            files.append(line.replace("\\", "/"))
    version = tags.get("Version", "")
    if not VERSION_PATTERN.match(version):
        raise ReleaseError(f"{path}: '## Version: {version}' is not a version like 1.2.3")
    title = tags.get("Title", "")
    # The title shows the version in the game's AddOns list ("OneMoreQuest v0.16.0"): raised with the Version line
    if f"v{version}|r" not in title:
        raise ReleaseError(f"{path}: the Title ({title}) does not show the version {version}: raise both together")
    return Toc(version=version, title=title, interface=tags.get("Interface", ""), files=files)


def read_changelog(version: str, addon_dir: str = ADDON_DIR) -> str:
    """The notes under '## <version>' in CHANGELOG.md, without the heading."""
    path = os.path.join(addon_dir, "CHANGELOG.md")
    with open(path, encoding="utf-8") as handle:
        text = handle.read().replace("\r\n", "\n")
    match = re.search(rf"^## {re.escape(version)}[ \t]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match or not match.group(1).strip():
        raise ReleaseError(f"{path}: no notes under '## {version}': write what changed before releasing it")
    return match.group(1).strip() + "\n"


# .pkgmeta's lists (the BigWigs packager's names) and what CurseForge's upload API calls each relation
PKGMETA_RELATIONS = {
    "required-dependencies": "requiredDependency",
    "optional-dependencies": "optionalDependency",
    "tools-used": "tool",
    "embedded-libraries": "embeddedLibrary",
    "incompatible": "incompatible",
}


def read_relations(addon_dir: str = ADDON_DIR) -> list[dict[str, str]]:
    """The addon's CurseForge relations from .pkgmeta: [{"slug": ..., "type": ...}]. Only its simple lists are read
    ("key:" then "  - slug" lines), which is all the file holds."""
    path = os.path.join(addon_dir, ".pkgmeta")
    relations: list[dict[str, str]] = []
    if not os.path.isfile(path):
        return relations
    current = None
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.split("#", 1)[0].rstrip()
            if not line:
                continue
            if not line.startswith((" ", "\t", "-")):
                key = line.rstrip(":").strip()
                current = PKGMETA_RELATIONS.get(key)
                continue
            item = line.strip()
            if current and item.startswith("- "):
                relations.append({"slug": item[2:].strip(), "type": current})
    return relations
