"""Builds OneMoreQuest's release zip and its checksums.

    python tools/release/build_zip.py [--out DIR]

The zip holds one folder, OneMoreQuest, as the game's AddOns folder wants it: the TOC, every file the TOC loads,
the Media folder, and the licence, readme and changelog. What goes in is read from the TOC, so a file added there
ships without another list to keep. It fails, saying why, when the TOC names a file that is not there, or a Lua file
in the addon is loaded by nothing (forgotten in the TOC).

The zip is the same, byte for byte, for the same files (fixed dates, sorted names), so its checksum can be checked
against the release's: SHA256SUMS.txt beside it (sha256sum -c SHA256SUMS.txt).

Writes OneMoreQuest-<version>.zip and SHA256SUMS.txt into --out (default: dist/ in the repository). In GitHub
Actions it also sets the step's outputs: version, zip, checksums, prerelease."""

from __future__ import annotations

import argparse
import hashlib
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from addon import ADDON_DIR, ADDON_NAME, REPO_ROOT, ReleaseError, read_toc  # noqa: E402

# Shipped beside what the TOC loads (Media whole: its pictures are named by the code, some built at run time)
EXTRA_FILES = [f"{ADDON_NAME}.toc", "LICENSE.md", "README.md", "CHANGELOG.md"]
EXTRA_FOLDERS = ["Media"]
# Never shipped: the unit tests and their fake game
NOT_SHIPPED = ("tests/",)
FIXED_DATE = (2020, 1, 1, 0, 0, 0)


def list_files(addon_dir: str) -> list[str]:
    toc = read_toc(addon_dir)
    files = set(toc.files) | set(EXTRA_FILES)
    for folder in EXTRA_FOLDERS:
        for base, _, names in os.walk(os.path.join(addon_dir, folder)):
            for name in names:
                files.add(os.path.relpath(os.path.join(base, name), addon_dir).replace(os.sep, "/"))
    missing = sorted(name for name in files if not os.path.isfile(os.path.join(addon_dir, name)))
    if missing:
        raise ReleaseError("the TOC or the release names files that are not there: " + ", ".join(missing))
    loaded = set(toc.files)
    unloaded = []
    for base, _, names in os.walk(addon_dir):
        for name in names:
            relative = os.path.relpath(os.path.join(base, name), addon_dir).replace(os.sep, "/")
            if relative.endswith(".lua") and relative not in loaded and not relative.startswith(NOT_SHIPPED):
                unloaded.append(relative)
    if unloaded:
        raise ReleaseError(
            "Lua files no TOC line loads (add them to the TOC or delete them): " + ", ".join(sorted(unloaded))
        )
    return sorted(files)


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 16), b""):
            digest.update(block)
    return digest.hexdigest()


def build(addon_dir: str, out_dir: str) -> dict[str, str]:
    toc = read_toc(addon_dir)
    os.makedirs(out_dir, exist_ok=True)
    zip_path = os.path.join(out_dir, f"{ADDON_NAME}-{toc.version}.zip")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in list_files(addon_dir):
            info = zipfile.ZipInfo(f"{ADDON_NAME}/{name}", date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(os.path.join(addon_dir, name), "rb") as handle:
                archive.writestr(info, handle.read())
    checksums_path = os.path.join(out_dir, "SHA256SUMS.txt")
    with open(checksums_path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"{sha256(zip_path)}  {os.path.basename(zip_path)}\n")
    return {
        "version": toc.version,
        "zip": zip_path,
        "checksums": checksums_path,
        "prerelease": "true" if toc.is_prerelease else "false",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out", default=os.path.join(REPO_ROOT, "dist"), help="where to write the zip (default dist/)")
    parser.add_argument("--addon", default=ADDON_DIR, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        result = build(os.path.abspath(args.addon), os.path.abspath(os.path.expanduser(args.out)))
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    size = os.path.getsize(result["zip"]) // 1024
    print(f"{result['zip']} ({size} KB)")
    with open(result["checksums"], encoding="utf-8") as handle:
        print(handle.read().strip())
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as handle:
            for key, value in result.items():
                handle.write(f"{key}={value}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
