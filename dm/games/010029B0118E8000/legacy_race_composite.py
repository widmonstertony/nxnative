#!/usr/bin/env python3
"""Prepare the A10X race and paint compositors from a3a5cfdab59c MSL."""

import argparse
import re
from pathlib import Path


def replace(source, pattern, substitute, expected):
    output, count = re.subn(pattern, substitute, source)
    if count != expected:
        raise ValueError(f"Expected {expected} matching expressions, found {count}")
    return output


def repair_hdr_samples(source, border_index, first_sample, samples):
    hdr = "spvDescriptorSet0.fp_t_tcb_8"
    hdr_sample = (
        re.escape(f"dm_bs({hdr}.sample({hdr}Smplr, ")
        + r"(select\((_\d+), float2\(0\.0\), isnan\(\2\)\))"
        + re.escape(f"), spvDescriptorSet0.dm_border, {border_index}u, {hdr}, {hdr}Smplr_w, ")
        + r"\1\)"
    )
    # The full-resolution HDR image uses transparent black outside its edges.
    # This sampler implements that border on the A10X at the only bound mip.
    source = replace(
        source, hdr_sample, lambda m: f"{hdr}.sample(sceneSampler, {m[1]}, level(0))", samples
    )
    return replace(
        source, re.escape(first_sample),
        "    constexpr sampler sceneSampler(coord::normalized, address::clamp_to_zero, filter::linear);\n"
        + first_sample, 2,
    )


def repair_race(source):
    source = repair_hdr_samples(source, 1, "    float _88 =", 10)
    # The depth buffer is Depth32Float_Stencil8. Sample its depth aspect at
    # the same argument slot with the nearest filter requested by the game.
    source = replace(
        source, re.escape("texture2d<float> fp_t_tcb_10 [[id(2)]]"),
        "depth2d<float> fp_t_tcb_10 [[id(2)]]", 1,
    )
    return replace(
        source, r"    float _80 = dm_bs\(spvDescriptorSet0\.fp_t_tcb_10\.sample[^\n]+;",
        "    constexpr sampler sceneDepth(coord::normalized, address::clamp_to_edge, filter::nearest);\n"
        "    float _80 = spvDescriptorSet0.fp_t_tcb_10.sample("
        "sceneDepth, select(_562, float2(0.0), isnan(_562)), level(0));", 2,
    )


def repair_paint(source):
    return repair_hdr_samples(source, 2, "    float3 _88 =", 2)


def repair_paint_transition(source):
    # Camera transitions switch to a second compositor with the same HDR
    # texture and sampler, but no depth input and different argument indices.
    return repair_hdr_samples(source, 0, "    float3 _70 =", 2)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original_msl", type=Path)
    parser.add_argument("patched_msl", type=Path)
    args = parser.parse_args()
    recipes = {
        "bb746472ac3e7420_b.metal": repair_paint,
        "56adc6eb3a054e0e_b.metal": repair_paint_transition,
        "c85f31db03049b39_b.metal": repair_race,
    }
    recipe = recipes.get(args.original_msl.name)
    if recipe is None:
        parser.error("expected the retained paint or race compositor source")
    if args.original_msl.resolve() == args.patched_msl.resolve():
        parser.error("use a separate output path")
    args.patched_msl.write_text(recipe(args.original_msl.read_text()))
