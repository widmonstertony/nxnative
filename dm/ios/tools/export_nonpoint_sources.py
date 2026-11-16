#!/usr/bin/env python3
"""Export hash-bound raster companions for legacy Metal.

Inputs and outputs contain game-derived data and must stay outside source control.
The runtime checks both source and original library hashes before compiling a
non-point or dual-source variant. Depth-output metadata prevents invalid
speculative pipelines. This export does not change the base translation chain.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def dual_source(data: bytes):
    """Supplement an older library with the same arithmetic and a SRC1 ABI.

    Copy only the primary function; already present uint/mixed entry points
    must not be duplicated. Ordinary MRT keeps the original library/function.
    """
    src = data.decode("utf-8")
    st = re.search(r"struct main0_out\s*\{(.*?)\};", src, re.S)
    fn = re.search(r"\bfragment\s+main0_out\s+main0\s*\(", src)
    if not st or not fn:
        return None
    member_pattern = r"^\s*(\w+)\s+(\w+)\s*(\[\[[^\]]*\]\])?;"
    members = re.findall(member_pattern, st.group(1), re.M)
    if re.sub(member_pattern, "", st.group(1), flags=re.M).strip():
        return None
    colors = [(int(c[1]), ty) for ty, _, at in members if (c := re.search(r"color\((\d+)\)", at))]
    if (len(colors) != 2 or {color for color, _ in colors} != {0, 1} or
            any(not re.fullmatch(r"(?:float|half)[1-4]?", ty) for _, ty in colors) or
            re.search(r"\bindex\s*\(", st.group(1))):
        return None
    start = src.index("{", fn.end())
    end, level = start + 1, 1
    while level and end < len(src):
        level += (src[end] == "{") - (src[end] == "}")
        end += 1
    if level or "return out;" not in src[start:end]:
        raise ValueError("Unrecognized primary fragment body")
    fields = "".join(f"    {ty} {nm} {at.replace('color(1)', 'color(0), index(1)')};\n"
                     for ty, nm, at in members)
    ret = "return main0_out_d{" + ", ".join("out." + nm for _, nm, _ in members) + "};"
    body = re.sub(r"\bfragment\s+main0_out\s+main0\s*\(",
                  "fragment main0_out_d main0_d(", src[fn.start():end], count=1).replace("return out;", ret)
    return (src + "\nstruct main0_out_d {\n" + fields + "};\n" + body + "\n").encode()


def export(cache: Path, libraries: Path, output: Path, chain: str) -> int:
    if cache.name != f"b-{chain}" or libraries.name != f"b-{chain}":
        raise ValueError("Source and library directories must match the host chain")
    records = {}
    depth_outputs = {}
    dual_sources = {}
    output.mkdir(parents=True, exist_ok=True)
    for reflection in sorted(libraries.glob("*_b.json")):
        meta = json.loads(reflection.read_text())
        if meta.get("stage") not in ("vs", "ps"):
            continue
        if meta.get("chain") != chain or meta.get("key") != reflection.stem:
            raise ValueError(f"Mismatched reflection: {reflection.name}")
        source = cache / (reflection.stem + ".metal")
        data = source.read_bytes()
        library = libraries / (reflection.stem + ".metallib")
        if meta.get("stage") == "ps":
            # Reflection predates a depth-output bit. Record the fact from the
            # exact translated source, bound to this packaged library, without
            # changing or relabeling any translated shader.
            if re.search(rb"\[\[\s*depth\s*\(", data):
                depth_outputs[reflection.stem] = {
                    "source_sha256": hashlib.sha256(data).hexdigest(),
                    "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
                }
            if not meta.get("entry_d"):
                alternate = dual_source(data)
                if alternate:
                    dual_sources[reflection.stem] = {
                        "source_sha256": hashlib.sha256(alternate).hexdigest(),
                        "original_source_sha256": hashlib.sha256(data).hexdigest(),
                        "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
                    }
                    (output / (reflection.stem + ".dual.metal")).write_bytes(alternate)
            continue
        if b"[[point_size]]" not in data:
            continue
        records[reflection.stem] = {
            "source_sha256": hashlib.sha256(data).hexdigest(),
            "library_sha256": hashlib.sha256(library.read_bytes()).hexdigest(),
        }
        shutil.copyfile(source, output / source.name)
    manifest = {"schema": 1, "chain": chain, "shaders": records,
                "fragment_depth_outputs": depth_outputs, "fragment_dual_sources": dual_sources}
    (output / "manifest.json").write_text(json.dumps(manifest, separators=(",", ":")) + "\n")
    return len(records)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path)
    parser.add_argument("libraries", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    header = Path(__file__).resolve().parents[2] / "gfx/nvn/dmsh_chain.h"
    match = re.search(r'#define\s+DMSH_CHAIN\s+"([a-f0-9]+)"', header.read_text())
    if match is None:
        raise ValueError(f"No DMSH_CHAIN in {header}")
    chain = match.group(1)
    count = export(args.cache, args.libraries, args.output, chain)
    print(f"Exported {count} chain-matched non-point sources (chain {chain})")
