#!/usr/bin/env python3
"""Inventory game IPAs for a future single-bundle library without copying game data.

This is deliberately a validation gate, not an IPA merger: the current host
compiles a separate profile into each executable. A catalog entry must never
be presented as a runnable game in a shared host until multiplexing exists.
"""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path
import re
import zipfile

TITLE = re.compile(r"[0-9A-Fa-f]{16}\Z")
PREFIX = "Payload/DmIOS.app/"


def version(value):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", value):
        raise ValueError(f"invalid OS version {value!r}")
    return tuple(int(piece) for piece in value.split("."))


def inspect(ipa, target_os):
    ipa = Path(ipa)
    with zipfile.ZipFile(ipa) as archive:
        names = set(archive.namelist())
        required = (PREFIX + "Info.plist", PREFIX + "DmIOS", PREFIX + "dm/launcher.json",
                    PREFIX + "dm/shader_map.tsv")
        missing = [name for name in required if name not in names]
        if missing:
            raise ValueError(f"{ipa.name}: missing {', '.join(missing)}")
        info = plistlib.loads(archive.read(required[0]))
        settings = json.loads(archive.read(required[2]))
        title = settings.get("game", "")
        if not TITLE.fullmatch(title):
            raise ValueError(f"{ipa.name}: invalid title ID")
        bundle_id = info.get("CFBundleIdentifier", "")
        if not bundle_id.lower().endswith(title.lower()):
            raise ValueError(f"{ipa.name}: bundle/title mismatch")
        minimum = info.get("MinimumOSVersion", "")
        if version(minimum) > version(target_os):
            raise ValueError(f"{ipa.name}: needs iOS {minimum}, target is {target_os}")
        if any(part.startswith("._") for name in names for part in name.split("/")):
            raise ValueError(f"{ipa.name}: AppleDouble metadata")
        exe = archive.read(required[1])
        return {"title_id": title.upper(), "name": info.get("CFBundleDisplayName", title),
                "source_bundle_id": bundle_id, "minimum_os": minimum,
                "source_version": info.get("CFBundleVersion", ""),
                "host_sha256": hashlib.sha256(exe).hexdigest(),
                "ipa_bytes": ipa.stat().st_size,
                "status": "requires_shared_host_and_per_game_resource_namespace"}


def build(paths, target_os):
    games = [inspect(path, target_os) for path in paths]
    titles = [game["title_id"] for game in games]
    if len(set(titles)) != len(titles):
        raise ValueError("duplicate game title ID")
    games.sort(key=lambda game: game["title_id"])
    return {"schema": 1, "target_os": target_os, "game_count": len(games),
            "source_ipa_bytes": sum(game["ipa_bytes"] for game in games),
            "games": games, "shared_host_ready": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-os", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("ipa", nargs="+", type=Path)
    args = parser.parse_args()
    result = build(args.ipa, args.target_os)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
