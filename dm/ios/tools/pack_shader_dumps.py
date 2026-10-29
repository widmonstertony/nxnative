#!/usr/bin/env python3
"""Validate captured NVN shaders and export offline translator input packages.

Outputs contain game data: use an external game work directory. Merge the
generated map rows into that game's provisional profile, rebuild its complete
shader set and stamp, then rebuild the host. This does not translate at runtime.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct


def validate(key, control, code):
    if not re.fullmatch(r"[0-9a-f]{16}", key):
        raise ValueError("Invalid capture key")
    if len(control) != 0x880 or control[:4] != bytes.fromhex("34127698"):
        raise ValueError("Expected the complete captured control section")
    n = struct.unpack_from("<I", control, 0x20)[0]
    n = n if 0x760 <= n < 0x880 else 0x880
    if struct.unpack_from("<I", control, 0x704)[0] != len(code):
        raise ValueError("Control and code length disagree")
    if hashlib.sha256(control[:n] + code).hexdigest()[:16] != key:
        raise ValueError("Capture key does not match its control and code")
    if code[:4] != bytes.fromhex("78563412") or len(code) < 0x80:
        raise ValueError("Only captured graphics shaders are supported")
    word = struct.unpack_from("<I", code, 0x30)[0]
    stage = (word >> 10) & 15
    stage = 1 if stage == 0 and word & 31 == 1 else stage
    if stage not in (1, 5):
        raise ValueError("Capture needs a separate tessellation/geometry proof")
    if b"BTCDBTCD" in control + code or bytes.fromhex("34127698") in code:
        raise ValueError("Capture contains a package delimiter")
    header = bytearray(b"BTCDBTCD" + bytes(0x30))
    struct.pack_into("<2I", header, 0x28, len(control), len(code))
    return ("vs" if stage == 1 else "ps"), bytes(header) + code + control


def pack(dumps, output):
    captures = []
    for path in sorted(dumps.glob("*.ctl")):
        control, code = path.read_bytes(), path.with_suffix(".code").read_bytes()
        stage, record = validate(path.stem, control, code)
        captures.append((path.stem, stage, record))
    if not captures:
        raise ValueError("No captured shaders")
    # Validation finishes before creating any output; never overwrite a build.
    output.mkdir(parents=True, exist_ok=False)
    rows = ["package\tindex\tstage\tdm_ctl_sha16\tsource"]
    groups = {"vs": [], "ps": []}
    evidence = []
    for key, stage, record in captures:
        index = len(groups[stage]); groups[stage].append(record)
        rows.append(f"{stage}_capture.bin\t{index}\t{'vertex' if stage == 'vs' else 'pixel'}\t{key}\truntime-capture/{key}")
        evidence.append({"key": key, "stage": stage, "record_sha256": hashlib.sha256(record).hexdigest()})
    for stage, records in groups.items():
        if records:
            (output / (stage + "_capture.bin")).write_bytes(b"".join(records))
    (output / "shader_map.tsv").write_text("\n".join(rows) + "\n")
    (output / "capture-proof.json").write_text(json.dumps(evidence, indent=2) + "\n")
    return len(captures)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dumps", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    print(f"Validated {pack(args.dumps, args.output)} captured shaders")
