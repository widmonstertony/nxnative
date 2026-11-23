"""Rebuild the affected Pokopia Metal 3 shaders for iPadOS 16.1.

The M2 compiler rejects packed half-to-integer lowering in these particular
shaders. Keep the shader reflection and replace the bitcasts with binary16
conversion using integer operations. Only the known shader sources are accepted.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

CHAIN = "a432daafc3d0"
NONPOINT_VERTEX = "9b42a7d8889b9cd8_b"
SHADERS = {
    "45afc24df093ab72_b": ("2034707eaad9cb94eb9add7f4431105b7f179b776930543100a39fe68e047601", 52, "ps"),
    "754327f84eca6eed_b": ("ecaffc48450bac192054b375efd4ad17f1a75be89977737316ea299cca024fed", 4, "ps"),
    "8743dd823fc8e863_b": ("e8f4e1f0eeb917c4186eb545a56aafdad026f487e4189bcdf213a74d60e17b41", 400, "ps"),
    NONPOINT_VERTEX: ("3ed512f2769dd8c7ad072c671c561110b8bd3c98adc7cd497c35df304f681b78", 186, "vs"),
}
PACKED_CAST = re.compile(r"as_type<uint>\(half2\(|float2\(as_type<half2>\(")

HEADER = r'''
static inline uint dm_f32_to_f16_bits(float value)
{
    uint bits = as_type<uint>(value);
    uint sign = (bits >> 16u) & 0x8000u;
    uint exponent = (bits >> 23u) & 255u;
    uint mantissa = bits & 0x7fffffu;
    if (exponent == 255u)
        return sign | 0x7c00u | (mantissa ? ((mantissa >> 13u) | 0x200u) : 0u);
    if (exponent > 142u) return sign | 0x7c00u;
    if (exponent < 102u) return sign;
    uint significand = mantissa | 0x800000u;
    uint shift = exponent < 113u ? 126u - exponent : 13u;
    uint tie = (significand >> shift) & 1u;
    uint rounded = (significand + (1u << (shift - 1u)) - 1u + tie) >> shift;
    return sign | (rounded + (exponent >= 113u ? ((exponent - 113u) << 10u) : 0u));
}

static inline float dm_f16_bits_to_f32(uint bits)
{
    uint sign = (bits & 0x8000u) << 16u;
    uint exponent = (bits >> 10u) & 31u;
    uint mantissa = bits & 1023u;
    if (exponent == 31u)
        return as_type<float>(sign | 0x7f800000u | (mantissa ? ((mantissa << 13u) | 0x400000u) : 0u));
    if (exponent) return as_type<float>(sign | ((exponent + 112u) << 23u) | (mantissa << 13u));
    if (!mantissa) return as_type<float>(sign);
    uint lead = 31u - clz(mantissa);
    return as_type<float>(sign | ((lead + 103u) << 23u) | ((mantissa << (23u - lead)) & 0x7fffffu));
}

static inline uint dm_pack_f16x2(float2 value)
{
    return dm_f32_to_f16_bits(value.x) | (dm_f32_to_f16_bits(value.y) << 16u);
}

static inline float2 dm_unpack_f16x2(uint bits)
{
    return float2(dm_f16_bits_to_f32(bits), dm_f16_bits_to_f32(bits >> 16u));
}
'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def closing_parenthesis(text, start):
    depth = 0
    for end in range(start, len(text)):
        if text[end] == "(":
            depth += 1
        elif text[end] == ")":
            depth -= 1
            if depth == 0:
                return end
    raise ValueError("Unbalanced generated shader expression")


def transform(source, key):
    digest, expected, _ = SHADERS[key]
    if sha(source) != digest:
        raise ValueError(f"{key}: source does not match the installed shader chain")
    text = source.decode()
    count = 0
    while match := PACKED_CAST.search(text):
        start = match.end() - 1
        end = closing_parenthesis(text, start)
        if text[end + 1:end + 2] != ")":
            raise ValueError(f"{key}: unexpected packed conversion")
        function = "dm_pack_f16x2" if match[0].startswith("as_type") else "dm_unpack_f16x2"
        text = text[:match.start()] + function + text[start:end + 1] + text[end + 2:]
        count += 1
    anchor = "using namespace metal;"
    if count != expected or re.search(r"\bhalf(?:[234])?\b", text) or text.count(anchor) != 1:
        raise ValueError(f"{key}: expected {expected} packed conversions, replaced {count}")
    return text.replace(anchor, anchor + "\n" + HEADER, 1)


def build(source, installed, output):
    if output.exists() or output.is_symlink():
        raise FileExistsError("Use a new output directory")
    manifest_path = installed / "nonpoint-v1" / "manifest.json"
    manifest = json.loads(manifest_path.read_bytes())
    if manifest.get("schema") != 1 or manifest.get("chain") != CHAIN:
        raise ValueError("Non-point manifest belongs to a different shader chain")
    record = manifest["shaders"][NONPOINT_VERTEX]
    original_source = (manifest_path.parent / (NONPOINT_VERTEX + ".metal")).read_bytes()
    original_library = (installed / (NONPOINT_VERTEX + ".metallib")).read_bytes()
    if (sha(original_source) != record["source_sha256"] or
            sha(original_library) != record["library_sha256"] or
            original_source != (source / (NONPOINT_VERTEX + ".metal")).read_bytes()):
        raise ValueError("Installed non-point source or library does not match its manifest")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output.parent) as name:
        stage = Path(name) / "result"
        stage.mkdir()
        for key, (_, _, expected_stage) in SHADERS.items():
            info = (installed / (key + ".json")).read_bytes()
            metadata = json.loads(info)
            if (metadata["key"], metadata["stage"], metadata["chain"]) != (key, expected_stage, CHAIN):
                raise ValueError(f"{key}: incompatible reflection")
            (stage / (key + ".json")).write_bytes(info)
            msl = Path(name) / (key + ".metal")
            msl.write_text(transform((source / msl.name).read_bytes(), key))
            air = msl.with_suffix(".air")
            library = stage / (key + ".metallib")
            subprocess.run([
                "xcrun", "-sdk", "iphoneos", "metal", "-target", "air64-apple-ios16.1",
                "-std=metal3.0", "-O1", "-fmetal-math-mode=safe", "-fpreserve-invariance",
                "-fwrapv", "-fmodules-cache-path=" + str(Path(name) / "module-cache"),
                "-c", str(msl), "-o", str(air),
            ], check=True)
            subprocess.run(["xcrun", "-sdk", "iphoneos", "metallib", str(air), "-o", str(library)], check=True)
            if not library.read_bytes().startswith(b"MTLB"):
                raise ValueError(f"{key}: invalid Metal library")
            if key == NONPOINT_VERTEX:
                nonpoint = stage / "nonpoint-v1"
                nonpoint.mkdir()
                data = msl.read_bytes()
                (nonpoint / msl.name).write_bytes(data)
                record.update(source_sha256=sha(data), library_sha256=sha(library.read_bytes()))
                (nonpoint / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False) + "\n")
        stage.rename(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="Directory of the retained .metal files")
    parser.add_argument("installed", type=Path, help="Existing b-a432daafc3d0 directory")
    parser.add_argument("output", type=Path, help="New overlay directory for the repaired libraries")
    args = parser.parse_args()
    build(args.source, args.installed, args.output)
