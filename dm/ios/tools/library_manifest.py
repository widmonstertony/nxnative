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


def inspect_mac_app(path, target_os):
    app = Path(path)
    content = app / "Contents"
    info = plistlib.loads((content / "Info.plist").read_bytes())
    title = info.get("DMTitleID", "")
    if not TITLE.fullmatch(title):
        raise ValueError(f"{app.name}: invalid Mac title ID")
    minimum = info.get("LSMinimumSystemVersion", "")
    if version(minimum) > version(target_os):
        raise ValueError(f"{app.name}: needs macOS {minimum}, target is {target_os}")
    if info.get("LSArchitecturePriority") != ["arm64"]:
        raise ValueError(f"{app.name}: unsupported Mac architecture")
    if not info.get("CFBundleIdentifier", "").lower().endswith(title.lower()):
        raise ValueError(f"{app.name}: bundle/title mismatch")
    host = content / "MacOS/dmhost"
    settings = content / "Resources/dm/launcher.json"
    if not host.is_file() or not settings.is_file():
        raise ValueError(f"{app.name}: incomplete host or settings")
    if json.loads(settings.read_text())["game"].upper() != title.upper():
        raise ValueError(f"{app.name}: settings/title mismatch")
    return {"title_id": title.upper(), "name": info.get("CFBundleDisplayName", title),
            "source_bundle_id": info["CFBundleIdentifier"], "minimum_os": minimum,
            "source_version": info.get("CFBundleVersion", ""),
            "host_sha256": hashlib.sha256(host.read_bytes()).hexdigest(),
            "status": "requires_shared_host_and_per_game_resource_namespace"}


def build(paths, target_os, mac_apps=(), target_macos=None):
    games = [inspect(path, target_os) for path in paths]
    titles = [game["title_id"] for game in games]
    if len(set(titles)) != len(titles):
        raise ValueError("duplicate game title ID")
    games.sort(key=lambda game: game["title_id"])
    mac_games = [inspect_mac_app(path, target_macos) for path in mac_apps] if target_macos else []
    mac_titles = [game["title_id"] for game in mac_games]
    if len(set(mac_titles)) != len(mac_titles):
        raise ValueError("duplicate Mac game title ID")
    mac_games.sort(key=lambda game: game["title_id"])
    return {"schema": 1, "target_os": target_os, "target_macos": target_macos,
            "game_count": len(games), "mac_game_count": len(mac_games),
            "source_ipa_bytes": sum(game["ipa_bytes"] for game in games),
            "games": games, "mac_games": mac_games, "shared_host_ready": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-os", required=True)
    parser.add_argument("--target-macos", help="macOS version for --mac-app entries")
    parser.add_argument("--mac-app", action="append", type=Path, default=[])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("ipa", nargs="+", type=Path)
    args = parser.parse_args()
    if args.mac_app and not args.target_macos:
        parser.error("--mac-app requires --target-macos")
    result = build(args.ipa, args.target_os, args.mac_app, args.target_macos)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
