"""Uploads the release zip to CurseForge through its upload API (https://support.curseforge.com, "CurseForge Upload
API"): the file, its display name, its changelog (CHANGELOG.md's section, as Markdown), the game versions it is for,
its release type, and its relations (from .pkgmeta).

    python tools/release/curseforge.py --zip dist/OneMoreQuest-0.16.0.zip [--dry-run]
    python tools/release/curseforge.py --list-versions [filter]

Settings come from the environment (GitHub: a secret and repository variables):

    CURSEFORGE_API_TOKEN      the API token (https://authors.curseforge.com/#/settings/api-tokens); a secret
    CURSEFORGE_PROJECT_ID     the project's number (its overview page shows it)
    CURSEFORGE_GAME_VERSIONS  the game versions, comma separated: their ids (12345) or their names as CurseForge
                              lists them ("1.15.7"); --list-versions shows them
    CURSEFORGE_RELEASE_TYPE   release, beta or alpha (default: release; beta for a version like 1.2.3-beta1)

--dry-run prints what would be sent and sends nothing (no token needed unless versions are given by name).
Standard library only."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from addon import ADDON_NAME, ReleaseError, read_changelog, read_relations, read_toc  # noqa: E402

API = os.environ.get("CURSEFORGE_API_URL", "https://wow.curseforge.com/api")
RELEASE_TYPES = ("release", "beta", "alpha")
USER_AGENT = f"{ADDON_NAME}-release-script"


def request(method: str, path: str, token: str, body: bytes | None = None, content_type: str | None = None):
    headers = {"X-Api-Token": token, "User-Agent": USER_AGENT, "Accept": "application/json"}
    if content_type:
        headers["Content-Type"] = content_type
    for attempt in range(1, 4):
        call = urllib.request.Request(f"{API}{path}", data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(call, timeout=120) as response:
                return json.loads(response.read().decode("utf-8") or "null")
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", "replace")[:2000]
            if error.code >= 500 and attempt < 3:
                print(f"CurseForge answered {error.code}; trying again ({attempt}/3)", file=sys.stderr)
                time.sleep(5 * attempt)
                continue
            raise ReleaseError(f"CurseForge {method} {path}: HTTP {error.code}: {detail}") from None
        except urllib.error.URLError as error:
            if attempt < 3:
                time.sleep(5 * attempt)
                continue
            raise ReleaseError(f"CurseForge {method} {path}: {error.reason}") from None
    raise ReleaseError(f"CurseForge {method} {path}: no answer")


def list_game_versions(token: str) -> list[dict]:
    versions = request("GET", "/game/versions", token)
    if not isinstance(versions, list):
        raise ReleaseError("CurseForge's game versions are not a list: " + json.dumps(versions)[:300])
    return versions


def resolve_game_versions(wanted: str, token: str) -> list[int]:
    names = [part.strip() for part in wanted.split(",") if part.strip()]
    if not names:
        raise ReleaseError(
            "CURSEFORGE_GAME_VERSIONS is not set: name the game versions this file is for"
            " (python tools/release/curseforge.py --list-versions shows CurseForge's)"
        )
    if all(name.isdigit() for name in names):
        return [int(name) for name in names]
    if not token:
        raise ReleaseError("game versions given by name need CURSEFORGE_API_TOKEN to be looked up")
    known = list_game_versions(token)
    ids = []
    for name in names:
        if name.isdigit():
            ids.append(int(name))
            continue
        matches = [entry for entry in known if entry.get("name") == name or entry.get("slug") == name]
        if not matches:
            close = sorted({entry.get("name", "") for entry in known if name.split(".")[0] in str(entry.get("name"))})
            raise ReleaseError(f"CurseForge has no game version named {name!r}; close ones: {', '.join(close[:20])}")
        if len(matches) > 1:
            listed = ", ".join(f"{entry['id']} (type {entry.get('gameVersionTypeID')})" for entry in matches)
            raise ReleaseError(f"several game versions are named {name!r}: {listed}; give the id instead")
        ids.append(int(matches[0]["id"]))
    return ids


def compose_metadata(version: str, changelog: str, game_versions: list[int], release_type: str) -> dict:
    metadata = {
        "changelog": changelog,
        "changelogType": "markdown",
        "displayName": f"{ADDON_NAME} {version}",
        "gameVersions": game_versions,
        "releaseType": release_type,
    }
    relations = read_relations()
    if relations:
        metadata["relations"] = {"projects": relations}
    return metadata


def encode_multipart(metadata: dict, zip_path: str) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    with open(zip_path, "rb") as handle:
        data = handle.read()
    parts = [
        f"--{boundary}\r\n".encode(),
        b'Content-Disposition: form-data; name="metadata"\r\n',
        b"Content-Type: application/json\r\n\r\n",
        json.dumps(metadata).encode("utf-8"),
        f"\r\n--{boundary}\r\n".encode(),
        f'Content-Disposition: form-data; name="file"; filename="{os.path.basename(zip_path)}"\r\n'.encode(),
        b"Content-Type: application/zip\r\n\r\n",
        data,
        f"\r\n--{boundary}--\r\n".encode(),
    ]
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--zip", help="the zip to upload (dist/OneMoreQuest-<version>.zip)")
    parser.add_argument("--dry-run", action="store_true", help="print what would be sent, send nothing")
    parser.add_argument("--list-versions", nargs="?", const="", metavar="FILTER", help="list CurseForge's game versions")
    args = parser.parse_args()
    token = os.environ.get("CURSEFORGE_API_TOKEN", "").strip()
    try:
        if args.list_versions is not None:
            if not token:
                raise ReleaseError("CURSEFORGE_API_TOKEN is needed to list the game versions")
            for entry in list_game_versions(token):
                line = f"{entry.get('id'):>8}  type {entry.get('gameVersionTypeID'):>6}  {entry.get('name')}"
                if args.list_versions.lower() in line.lower():
                    print(line)
            return 0
        if not args.zip or not os.path.isfile(args.zip):
            raise ReleaseError(f"no zip to upload: {args.zip!r} (build it first: python tools/release/build_zip.py)")
        toc = read_toc()
        changelog = read_changelog(toc.version)
        release_type = os.environ.get("CURSEFORGE_RELEASE_TYPE", "").strip().lower()
        release_type = release_type or ("beta" if toc.is_prerelease else "release")
        if release_type not in RELEASE_TYPES:
            raise ReleaseError(f"CURSEFORGE_RELEASE_TYPE is {release_type!r}: one of {', '.join(RELEASE_TYPES)}")
        project = os.environ.get("CURSEFORGE_PROJECT_ID", "").strip()
        wanted = os.environ.get("CURSEFORGE_GAME_VERSIONS", "")
        if args.dry_run:
            game_versions = resolve_game_versions(wanted, token) if wanted.strip() else []
            metadata = compose_metadata(toc.version, changelog, game_versions, release_type)
            print(f"POST {API}/projects/{project or '<CURSEFORGE_PROJECT_ID>'}/upload-file")
            print(f"file: {args.zip} ({os.path.getsize(args.zip) // 1024} KB)")
            print(json.dumps(metadata, indent=2, ensure_ascii=False))
            return 0
        if not token:
            raise ReleaseError("CURSEFORGE_API_TOKEN is not set")
        if not project.isdigit():
            raise ReleaseError(f"CURSEFORGE_PROJECT_ID is {project!r}: the project's number")
        game_versions = resolve_game_versions(wanted, token)
        metadata = compose_metadata(toc.version, changelog, game_versions, release_type)
        body, content_type = encode_multipart(metadata, args.zip)
        answer = request("POST", f"/projects/{project}/upload-file", token, body, content_type)
        file_id = answer.get("id") if isinstance(answer, dict) else None
        if not file_id:
            raise ReleaseError("CurseForge took the upload but gave no file id: " + json.dumps(answer)[:300])
        print(f"uploaded {os.path.basename(args.zip)} to CurseForge: file {file_id} ({release_type})")
        github_output = os.environ.get("GITHUB_OUTPUT")
        if github_output:
            with open(github_output, "a", encoding="utf-8") as handle:
                handle.write(f"file_id={file_id}\n")
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
