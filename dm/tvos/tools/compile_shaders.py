#!/usr/bin/env python3
"""Run a pinned Route B translator, emitting its iOS-side libraries for tvOS.

The shader translator and the runtime must come from the same source tree.
The existing chain, reflection, and variant generation stay intact; only
the Apple SDK, deployment target, and recorded compiler command change.
"""
import argparse
import os
from pathlib import Path
import runpy
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-source', type=Path, required=True)
    parser.add_argument('--package', type=Path, required=True, help='Extracted Route B shader packages')
    parser.add_argument('--source-cache', type=Path, required=True)
    parser.add_argument('--metal-directory', type=Path, help='Directory containing the installed metal and metallib tools')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    translator = args.runtime_source.resolve() / 'dm/gfx/tools/dmsh_build.py'
    if not translator.is_file() or not args.package.is_dir():
        parser.error('expected a prepared shader package directory and the matching runtime source checkout')
    if args.output.resolve() == args.source_cache.resolve():
        parser.error('--output and --source-cache must differ')

    sys.path[:0] = [str(translator.parent), str(translator.parents[2] / 'ios/tools')]
    import ios_metal

    # Keep these roots dedicated to tvOS. In particular, never use iOS
    # libraries as an input cache despite the translator's IOSOUT spelling.
    os.environ.pop('DMSH_PREFILL', None)
    os.environ['DMSH_TARGETS'] = 'ios'
    os.environ['IOSOUT'] = str(args.output.resolve())
    prefix = ['xcrun', '-sdk', 'appletvos']
    metal = prefix + ['metal']
    metallib = prefix + ['metallib']
    if args.metal_directory:
        metal = [str(args.metal_directory.resolve() / 'metal')]
        metallib = [str(args.metal_directory.resolve() / 'metallib')]
        if not all(Path(command[0]).is_file() for command in (metal, metallib)):
            parser.error('--metal-directory must contain metal and metallib')
    module_cache = args.source_cache.resolve() / '.clang-modules'
    module_cache.mkdir(parents=True, exist_ok=True)
    ios_metal.METAL = [
        *metal, f'-fmodules-cache-path={module_cache}', '-c', '-target', 'air64-apple-tvos17.0',
        '-fmetal-math-mode=relaxed', '-fpreserve-invariance',
    ]
    ios_metal.METALLIB = metallib
    ios_metal.RECORD = ' '.join(prefix + ['metal'] + ios_metal.METAL[len(metal) + 1:]) + '; xcrun -sdk appletvos metallib'
    sys.argv = [str(translator), str(args.package.resolve()), str(args.source_cache.resolve())]
    runpy.run_path(str(translator), run_name='__main__')


if __name__ == '__main__':
    main()
