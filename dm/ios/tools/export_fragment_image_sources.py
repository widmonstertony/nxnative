#!/usr/bin/env python3
"""Export proven RG11B10 fragment image writes to a shadow buffer."""
import argparse
import hashlib
import json
from pathlib import Path
import re


SLOT = 29
KIND = "fragment-image-rg11b10-v1"
PROOF = "fragment-image-rg11b10-shadow-v1"


def digest(data):
    return hashlib.sha256(data).hexdigest()


HELPER = r"""
// The host validates an RG11B10Float destination and supplies its initialized shadow.
static inline uint dm_rshift_rne(uint value, uint shift) {
    if (!shift) return value;
    if (shift >= 32u) return 0u;
    uint result = value >> shift;
    uint mask = (1u << shift) - 1u;
    uint remainder = value & mask;
    uint halfway = 1u << (shift - 1u);
    return result + uint(remainder > halfway || (remainder == halfway && (result & 1u)));
}

static inline uint dm_pack_ufloat(float value, uint mantissa_bits) {
    uint bits = as_type<uint>(value), sign = bits >> 31u;
    uint exponent = (bits >> 23u) & 255u, fraction = bits & 0x7fffffu;
    uint exponent_mask = 31u << mantissa_bits;
    if (exponent == 255u) return fraction ? exponent_mask | 1u : (sign ? 0u : exponent_mask);
    if (sign || exponent == 0u) return 0u;
    int target_exponent = int(exponent) - 127 + 15;
    if (target_exponent >= 31) return exponent_mask;
    if (target_exponent <= 0) {
        int shift = 9 - (int(exponent) - 127) - int(mantissa_bits);
        uint rounded = shift > 31 ? 0u : dm_rshift_rne((1u << 23u) | fraction, uint(shift));
        return min(rounded, 1u << mantissa_bits);
    }
    uint rounded = dm_rshift_rne(fraction, 23u - mantissa_bits);
    if (rounded == (1u << mantissa_bits)) {
        rounded = 0u;
        target_exponent++;
        if (target_exponent >= 31) return exponent_mask;
    }
    return (uint(target_exponent) << mantissa_bits) | rounded;
}

static inline uint dm_pack_rg11b10(float4 value) {
    return dm_pack_ufloat(value.x, 6u) |
           (dm_pack_ufloat(value.y, 6u) << 11u) |
           (dm_pack_ufloat(value.z, 5u) << 22u);
}

static inline void dm_rg11b10_store(device atomic_uint* image, float4 value,
                                    uint2 xy, uint layer, constant uint* layout) {
    uint width = layout[0], height = layout[1], layers = layout[2];
    uint words = layout[3], row_words = layout[4], image_words = layout[5];
    if (xy.x >= width || xy.y >= height || layer >= layers || words != 1u) return;
    ulong at = ulong(layer) * image_words + ulong(xy.y) * row_words + ulong(xy.x);
    atomic_store_explicit(image + at, dm_pack_rg11b10(value), memory_order_relaxed);
}

"""


def matching_paren(text, open_at):
    depth = 0
    for index in range(open_at, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    raise ValueError("Unbalanced image write")


def split_arguments(text):
    parts, start, depth = [], 0, 0
    for index, char in enumerate(text):
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
        elif char == "," and depth == 0:
            parts.append(text[start:index].strip())
            start = index + 1
    parts.append(text[start:].strip())
    return parts


def lower(source, meta):
    if meta.get("stage") != "ps" or meta.get("msl_entry_kind") != "fragment":
        raise ValueError("Only fragment entries are supported")
    raster = meta.get("raster")
    if not isinstance(raster, dict) or raster.get("discard") != 0 or raster.get("sample_mask") != 0 or raster.get("colors") != []:
        raise ValueError("Fragment discard, sample mask or color outputs are unproven")
    images = [item for item in meta.get("bindings", []) if item.get("kind") == "img"]
    if len(images) != 1 or images[0].get("msl_type") != "texture2d_array<float, access::write>":
        raise ValueError("Exactly one write-only float 2D-array image is required")
    image = images[0]
    if not isinstance(image.get("arg_id"), int) or not isinstance(image.get("reg"), int):
        raise ValueError("Image reflection is incomplete")
    if re.search(r"\bdm_(?:rg11b10|pack_ufloat|rshift_rne)", source) or re.search(r"\[\[\s*buffer\s*\(\s*29\s*\)\s*\]\]", source):
        raise ValueError("Compatibility symbols or buffer slot are occupied")

    name = re.escape(image["msl_name"])
    declaration = re.compile(r"texture2d_array\s*<\s*float\s*,\s*access::write\s*>\s*" + name + r"\s*\[\[\s*id\s*\(\s*" + str(image["arg_id"]) + r"\s*\)\s*\]\]")
    if len(declaration.findall(source)) != 1:
        raise ValueError("Image declaration does not match reflection")
    entry = re.escape(meta.get("entry", ""))
    signature = re.search(r"fragment\s+void\s+" + entry + r"\s*\((.*?)\)\s*\{", source, re.S)
    if not signature:
        raise ValueError("Fragment entry signature is unsupported")
    argument = re.search(r"constant\s+\w+\s*&\s*(\w+)\s*\[\[\s*buffer\s*\(\s*0\s*\)\s*\]\]", signature.group(1))
    if not argument:
        raise ValueError("Argument buffer parameter is unsupported")
    qualified = argument.group(1) + "." + image["msl_name"]

    replacements = []
    cursor = 0
    needle = qualified + ".write("
    while True:
        begin = source.find(needle, cursor)
        if begin < 0:
            break
        open_at = begin + len(needle) - 1
        close_at = matching_paren(source, open_at)
        args = split_arguments(source[open_at + 1:close_at])
        if len(args) != 3 or not re.fullmatch(r"uint2\s*\(.+\)", args[1], re.S) or not re.fullmatch(r"uint\s*\(.+\)", args[2], re.S):
            raise ValueError("Image write arguments are unsupported")
        replacement = f"dm_rg11b10_store({qualified}, {args[0]}, {args[1]}, {args[2]}, dm_image_layout)"
        replacements.append((begin, close_at + 1, replacement))
        cursor = close_at + 1
    if not replacements:
        raise ValueError("No image writes found")
    if source.count(qualified) != len(replacements):
        raise ValueError("Image is used outside proven write calls")
    without_writes = source
    for begin, end, replacement in reversed(replacements):
        without_writes = without_writes[:begin] + replacement + without_writes[end:]
    lowered = declaration.sub("device atomic_uint* " + image["msl_name"], without_writes)
    signature = re.search(r"fragment\s+void\s+" + entry + r"\s*\((.*?)\)\s*\{", lowered, re.S)
    insert = signature.end(1)
    lowered = lowered[:insert] + f", constant uint* dm_image_layout [[buffer({SLOT})]]" + lowered[insert:]
    fragment_at = re.search(r"fragment\s+void\s+" + entry, lowered).start()
    lowered = lowered[:fragment_at] + HELPER + lowered[fragment_at:]
    return lowered, {
        "proof": PROOF,
        "parameter_slot": SLOT,
        "image_aid": image["arg_id"],
        "image_reg": image["reg"],
        "pixel_format": 92,
        "write_count": len(replacements),
        "preserves_fragment_coverage": True,
    }


def export(cache, libraries, output, chain, keys):
    if cache.name != "b-" + chain or libraries.name != "b-" + chain:
        raise ValueError("Source and library directories must match the host chain")
    output.mkdir(parents=True, exist_ok=True)
    records = {}
    for reflection in sorted(libraries.glob("*_b.json")):
        if reflection.stem not in keys:
            continue
        meta = json.loads(reflection.read_text())
        if meta.get("stage") != "ps" or not any(item.get("kind") == "img" for item in meta.get("bindings", [])):
            continue
        original_path = cache / (reflection.stem + ".metal")
        if not original_path.exists():
            continue
        original = original_path.read_bytes()
        try:
            companion, record = lower(original.decode(), meta)
        except ValueError:
            continue
        data = companion.encode()
        filename = reflection.stem + ".metal"
        (output / filename).write_bytes(data)
        record.update(source=filename, source_sha256=digest(data),
                      base_library_sha256=digest((libraries / (reflection.stem + ".metallib")).read_bytes()),
                      reflection_sha256=digest(reflection.read_bytes()), original_source_sha256=digest(original))
        records[reflection.stem] = record
    (output / "manifest.json").write_text(json.dumps({"schema": 1, "chain": chain, "kind": KIND, "shaders": records}, separators=(",", ":")) + "\n")
    return records


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("cache", "libraries", "output"):
        parser.add_argument(name, type=Path)
    parser.add_argument("--key", action="append", required=True,
                        help="Shader key whose RG11B10Float destination was observed")
    args = parser.parse_args()
    header = Path(__file__).resolve().parents[2] / "gfx/nvn/dmsh_chain.h"
    match = re.search(r'#define\s+DMSH_CHAIN\s+"([a-f0-9]+)"', header.read_text())
    if match is None:
        parser.error(f"No valid DMSH_CHAIN in {header}")
    chain = match.group(1)
    records = export(args.cache, args.libraries, args.output, chain, set(args.key))
    print(f"Exported {len(records)} RG11B10 fragment-image companions (chain {chain})")
