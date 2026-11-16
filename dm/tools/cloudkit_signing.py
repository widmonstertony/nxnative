#!/usr/bin/env python3
"""Prepare CloudKit metadata for an existing app identity, using an Apple profile."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import plistlib
import re
import subprocess


CONTAINERS = "com.apple.developer.icloud-container-identifiers"
SERVICES = "com.apple.developer.icloud-services"
ENVIRONMENT = "com.apple.developer.icloud-container-environment"
APP_IDS = ("application-identifier", "com.apple.application-identifier")


def as_list(value):
    return [value] if isinstance(value, str) else value


def configure(profile, info, entitlements, app_id, container, environment):
    if not re.fullmatch(r"iCloud\.[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", container):
        raise ValueError("Expected an explicit iCloud container identifier")
    if environment not in ("Development", "Production"):
        raise ValueError("Expected Development or Production")
    bundle_id = info["CFBundleIdentifier"]
    prefix, _, target_id = app_id.partition(".")
    # XcodeGen writes a placeholder to prepared project Info.plists.
    if bundle_id in ("$(PRODUCT_BUNDLE_IDENTIFIER)", "${PRODUCT_BUNDLE_IDENTIFIER}"):
        bundle_id = target_id
    if not prefix or not target_id or target_id != bundle_id or "$" in app_id or "*" in app_id:
        raise ValueError("Existing app identifier does not match this bundle")
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime) or expires.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError("The provisioning profile has expired")
    allowed = profile["Entitlements"]
    if app_id not in [allowed.get(key) for key in APP_IDS]:
        raise ValueError("The profile does not authorize the exact existing app identifier")
    for key in APP_IDS:
        if key in entitlements and entitlements[key] != app_id:
            raise ValueError("Changing the existing app identifier is not supported")
    # Apple development profiles may grant all iCloud services with "*".
    # Keep the requested app entitlement restricted to CloudKit and require
    # the specific container in the profile either way.
    services = as_list(allowed.get(SERVICES, []))
    if container not in as_list(allowed.get(CONTAINERS, [])) or not {"CloudKit", "*"}.intersection(services):
        raise ValueError("The profile does not authorize CloudKit for this container")
    environments = as_list(allowed.get(ENVIRONMENT, []))
    if environment not in environments:
        raise ValueError("The profile does not authorize this iCloud environment")
    if info.get("DMCloudSaveContainer", container) != container:
        raise ValueError("Changing an existing iCloud container is not supported")
    if ENVIRONMENT in entitlements and entitlements[ENVIRONMENT] != environment:
        raise ValueError("Changing the existing iCloud environment is not supported")
    if CONTAINERS in entitlements and container not in as_list(entitlements[CONTAINERS]):
        raise ValueError("Changing an existing iCloud container is not supported")
    return (
        {**info, "CFBundleIdentifier": bundle_id, "DMCloudSaveContainer": container},
        {**entitlements, CONTAINERS: [container], SERVICES: ["CloudKit"], ENVIRONMENT: environment},
    )


def read_profile(path):
    cms = subprocess.run(["/usr/bin/security", "cms", "-D", "-i", str(path)],
                         check=True, capture_output=True).stdout
    return plistlib.loads(cms)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for arg in ("profile", "info", "entitlements", "output"):
        parser.add_argument(f"--{arg}", required=True, type=Path)
    parser.add_argument("--app-identifier", required=True)
    parser.add_argument("--container", required=True)
    parser.add_argument("--environment", required=True, choices=("Development", "Production"))
    args = parser.parse_args()
    try:
        info, entitlements = configure(
            read_profile(args.profile), plistlib.loads(args.info.read_bytes()),
            plistlib.loads(args.entitlements.read_bytes()), args.app_identifier,
            args.container, args.environment)
        # Only write to a fresh staging directory, never to a live or signed app.
        args.output.mkdir()
        (args.output / "Info.plist").write_bytes(plistlib.dumps(info))
        (args.output / "CloudKit.entitlements").write_bytes(plistlib.dumps(entitlements))
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
