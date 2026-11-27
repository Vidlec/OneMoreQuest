"""Writes the release notes for the version in the TOC: its section of CHANGELOG.md, how to install, and the zip's
SHA-256 checksum with how to check it.

    python tools/release/notes.py [--checksums dist/SHA256SUMS.txt] [--out dist/release-notes.md]

The GitHub release appends the merged pull requests to these (gh release create --generate-notes)."""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from addon import ADDON_NAME, REPO_ROOT, ReleaseError, read_changelog, read_toc  # noqa: E402


def compose(version: str, changelog: str, checksums: str) -> str:
    zip_name = f"{ADDON_NAME}-{version}.zip"
    lines = [changelog.rstrip(), "", "## Install", ""]
    lines += [
        f"Download `{zip_name}` below and unpack it into the game's `Interface/AddOns` folder, so that"
        f" `Interface/AddOns/{ADDON_NAME}/{ADDON_NAME}.toc` exists. OneMoreQuest needs QuestieDB.",
        "",
    ]
    if checksums.strip():
        lines += [
            "## Checksum",
            "",
            "SHA-256 of the zip (also in `SHA256SUMS.txt`):",
            "",
            "```",
            checksums.strip(),
            "```",
            "",
            "To check it, in the folder you downloaded both files to:",
            "",
            "- Linux and macOS: `sha256sum -c SHA256SUMS.txt` (macOS: `shasum -a 256 -c SHA256SUMS.txt`)",
            f"- Windows (PowerShell): `(Get-FileHash {zip_name} -Algorithm SHA256).Hash` and compare it with the line above",
            "",
        ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--checksums", default=os.path.join(REPO_ROOT, "dist", "SHA256SUMS.txt"))
    parser.add_argument("--out", default=os.path.join(REPO_ROOT, "dist", "release-notes.md"))
    parser.add_argument("--changelog-only", action="store_true", help="only the CHANGELOG section (for CurseForge)")
    args = parser.parse_args()
    try:
        toc = read_toc()
        changelog = read_changelog(toc.version)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    checksums = ""
    if os.path.isfile(args.checksums):
        with open(args.checksums, encoding="utf-8") as handle:
            checksums = handle.read()
    text = changelog if args.changelog_only else compose(toc.version, changelog, checksums)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print(args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
