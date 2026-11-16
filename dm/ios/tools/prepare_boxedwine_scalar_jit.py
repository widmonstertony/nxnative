#!/usr/bin/env python3
"""Apply the optional scalar-JIT compatibility patch to its exact upstream pin.

This prepares sources only. It does not build, install, or establish iOS speed.
"""
from pathlib import Path
import argparse
import subprocess

PIN = "2be9ff442feac29755a46693cd989960eeac8786"


def prepare(source: Path) -> None:
    source = source.resolve(strict=True)
    patch = Path(__file__).with_name("boxedwine_ios16_scalar_jit.patch")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
    if head != PIN:
        raise SystemExit(f"Expected BoxedWine {PIN}, found {head}; review the patch against this revision first")
    if subprocess.run(["git", "apply", "--reverse", "--check", str(patch)],
                      cwd=source, capture_output=True).returncode == 0:
        print("Scalar-JIT patch already applied; build and CPU/iOS checks still required")
        return
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=source, text=True).strip():
        raise SystemExit("Refusing to patch an unrelated dirty BoxedWine checkout")
    subprocess.run(["git", "apply", "--check", str(patch)], cwd=source, check=True)
    subprocess.run(["git", "apply", str(patch)], cwd=source, check=True)
    print("Scalar-JIT source prepared; build and CPU/iOS checks still required")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    prepare(parser.parse_args().source)
