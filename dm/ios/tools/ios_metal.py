# The single compile standard for the iOS shader packaging chain: MSL from any source (PC chain / constant patches / in future, the Switch original translated via Ryujinx) → iphoneos metallib.
# Compile parameters are defined only once, here; the chain.metal record in the reflection json is generated from the same parameters, record == actual.
import os, subprocess, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../gfx/tools')); import dmsh_pch, dmsh_legacy_atomic   # the precompiled header, which changes no output (so RECORD does not name it)
# -fmetal-math-mode=relaxed: keep fast math's reassociation / contraction, but forbid assuming there are no NaN / Inf. The translated shaders reproduce Maxwell's NaN semantics with isnan selects (8337 / 12809 use them),
# and the default fast mode lets each GPU's backend compiler treat them as always false; on the A20 Pro the opening course's odd frames had 727k NaN pixels in the main image (a few dozen with the same AIR on the M4 Pro), which became the black band / black-edged glow
# -fpreserve-invariance: [[invariant]] position outputs only agree across shaders with this flag (as dmsh_chain.py's MAC_METAL: a depth pre-pass followed by a less-or-equal G-buffer)
# -O1: -O2's switch folding leaves a control-flow graph Apple's GPU backend can only lower slowly into very large code (as dmsh_chain.py's MAC_METAL)
# IOS_FLAGS: the iPhone shader libraries' deployment target and math mode, which vk_shaders.py and gl_shaders.py pass too (one place for the version)
IOS_MIN_FLAG = '-mios-version-min=16.1'
IOS_FLAGS = [IOS_MIN_FLAG, '-fmetal-math-mode=relaxed']
METAL = ['xcrun', '-sdk', 'iphoneos', 'metal', '-c', '-O1', *IOS_FLAGS, '-fpreserve-invariance', '-fwrapv']   # -fwrapv: see dmsh_chain.py MAC_METAL
METALLIB = ['xcrun', '-sdk', 'iphoneos', 'metallib']
# Per-vertex fragment inputs require MSL 4.0 / iOS 26. Device-scope
# sequential fences emitted for NVN MEMBAR also need a newer MSL. Keep
# classic libraries on their requested deployment baseline.
METAL4, METAL4_FLAG = b'vertex_value<', '-std=metal4.0'
DEVICE_FENCE = 'memory_order_seq_cst, thread_scope_device'
MODERN = ['-mios-version-min=26.0' if option == IOS_MIN_FLAG else option for option in METAL] + [METAL4_FLAG]
RECORD = ' '.join(METAL) + f' ({METAL4_FLAG} for a source using vertex_value); ' + ' '.join(METALLIB) + '; legacy-image-atomic-buffer-v1'
if os.environ.get('DM_IOS_DEPLOYMENT_TARGET') == '26.0':
    RECORD += '; device-scope sequential fences: ' + ' '.join(MODERN)
DEPTH = ['-fbracket-depth=1024']

def compile(msl, air, lib):
    with open(msl) as f: source = f.read()
    v4 = METAL4.decode() in source
    modern_fence = DEVICE_FENCE in source and os.environ.get('DM_IOS_DEPLOYMENT_TARGET') == '26.0'
    lowered = None
    try:
        if dmsh_legacy_atomic.needed(source):
            text, _ = dmsh_legacy_atomic.lower(source)
            lowered = air + '.legacy.metal'
            with open(lowered, 'w') as f: f.write(text)
        flags = MODERN if modern_fence else METAL + ([METAL4_FLAG] if v4 else [])
        dmsh_pch.compile(flags + DEPTH, lowered or msl, air)
        subprocess.run([*METALLIB, air, '-o', lib], check=True)
    finally:
        if lowered and os.path.exists(lowered): os.unlink(lowered)
