# Pokemon Legends: Z-A 2.0.2: the native clock interval follows the host's
# adaptive frame step. Fixed addresses apply only to the verified main build.
from nso_asm import ADRP, B, LDP_POST, STP_PRE


def frame_step(ctx):
    # main+0x1b29660 chooses a zero-based interval (0=60, 1=30, 2=20 fps),
    # sets graphics object+0x140, and dispatches it to each unpaused clock.
    # Clock adapters (main+0x1b2a0e4, +0x1b5407c, +0x29f4214) turn that
    # interval into nanoseconds through the unchanged table at +0x3393e20.
    # The settings' signed byte at +0x20 imposes a 30 fps floor. Replacing
    # that floor alone loses real time when a frame misses 60: instead use
    # the host's step, including its extra vsync when repaying a late frame.
    # x19 is the framework, x21 the measured duration. Both remain intact;
    # x20 is restored by the original epilogue. The original two calls below
    # already clobber caller-saved registers, including LR (saved in prologue).
    ctx.site(0x1b296d8, '3481c039')  # ldrsb w20,[x9,#0x20]
    ctx.site(0x1b296e8, '68a79797000040f9e103142a3846f397')
    ctx.site(0x1b29738, '4830029008010091')
    start = ctx.here()
    ctx.emit(STP_PRE(16, 17, 31, -16))
    ctx.emit(ADRP(16, ctx.here(), ctx.state))
    # Branch displacements include the relocated calls and final jump below.
    for word in (
        0xb9400211,  # ldr w17,[x16]           target fps (float bits)
        0x34000231,  # cbz w17,off (+17 words) target 0: exact original path
        0xb9402214,  # ldr w20,[x16,#0x20]     step in vsyncs
        0x350000b4,  # cbnz w20,step (+5 words)
        0x52a83e14,  # mov w20,#0x41f00000     float bits of 30
        0x6b14023f,  # cmp w17,w20
        0x1a9f17f4,  # cset w20,eq
        0x11000694,  # add w20,w20,#1         before first present: 1 at 60, 2 at 30
        0xf9401a11,  # step: ldr x17,[x16,#0x30]
        0x8b344231,  # add x17,x17,w20,uxtw
        0xf9001a11,  # str x17,[x16,#0x30]     count actual native clock steps
        0x51000694,  # sub w20,w20,#1         native zero-based interval
        LDP_POST(16, 17, 31, 16),
    ):
        ctx.emit(word)
    ctx.emit(B(ctx.here(), 0x113488) | 0x80000000)  # original graphics singleton getter
    ctx.emit(0xf9400000)                            # ldr x0,[x0]
    ctx.emit(0x2a1403e1)                            # mov w1,w20
    ctx.emit(B(ctx.here(), 0x17fafd4) | 0x80000000)  # original graphics interval setter
    ctx.emit(B(ctx.here(), 0x1b29738))               # native paused/unpaused clock dispatch
    ctx.emit(LDP_POST(16, 17, 31, 16))              # off: registers and flags unchanged
    ctx.emit(0x39c08134)                            # original ldrsb w20,[x9,#0x20]
    ctx.emit(B(ctx.here(), 0x1b296dc))
    ctx.put(0x1b296d8, [B(0x1b296d8, start)],
            'native clock interval from the host frame step; target 0 preserves the original selector')


FRAME_STEP = {'b1f12fd919eae86ab8a978317677e64b': frame_step}

BINDING = [
    {'what': 'adaptive 30/60 fps native clock interval', 'now': 'build', 'goal': 'game',
     'purpose': 'frame rate', 'why': "Trinity's clock and graphics interval selector",
     'blocked': 'this build\'s clock adapter has not been validated for function matching across game builds'},
]

# TonTon build-specific allocator cut and independent diagnostics.
# Pokémon Legends: Z-A (0100F43008C44000): the rewriter's patches of this game's own builds. dm/tools/patch_nso.py loads every profile's patches.py and applies those of a module's NSO build ID;
# CUTS, OBS and FRAME_STEP as described there ("Registered patches"). Patches of Nintendo SDK module builds are in dm/tools/sdk_patches.py
CUTS = {
  # Pokémon Legends: Z-A 2.0.2 (v393216) main: nninitStartup (main+0x1b2e650) initializes its StandardAllocator with virtual address memory over 12 GB of address space (main+0x1b3e3e4), which
  # the Switch's 64 GB alias region holds and an iPhone's single 6 GB reservation cannot. The allocator commits pages as it goes and the pool (3.2 GB) bounds what it maps (profile mem_map_limit);
  # its largest block is nninitStartup's own probe of pool − used (3.15 GB, allocated and freed at once), so 4 GB of address space holds it
  'b1f12fd919eae86ab8a978317677e64b': [
    (0x1b3e3e4, '6200c0d2', '2200c0d2', 'StandardAllocator::Initialize(nullptr, size): address space mov x2,#0x300000000 → mov x2,#0x100000000 (12 GB → 4 GB)'),
  ],
}

# No timing behavior changes by default. Both callbacks return without touching
# guest registers unless their diagnostics / experiment is explicitly enabled.
# hle_za_timing.c checks the same build ID again at runtime.
OBS = {
  'b1f12fd919eae86ab8a978317677e64b': [
    # Clock channel 0 returns {total_ns, delta_ns}. The next instructions convert
    # delta_ns / 1e9 to float and hand it to engine updates (main+0x1b29314/334).
    (0x1b292dc, 26, 'fd400400', 'Trinity base-clock delta: orig ldr d0,[x0,#8]; observe game seconds versus monotonic time'),
    # Generic layout visibility, filtered by the exact WazaLayoutView vtable in
    # the host. Diagnostics only: no input remapping or register changes.
    (0x425c70, 28, 'f9405408', 'Layout visibility: orig ldr x8,[x0,#0xa8]; observe the actual battle move layout, not ZL alone'),
    (0x2b7bfbc, 29, 'a9be7bfd', 'Waza layout destructor: orig stp x29,x30,[sp,#-0x20]!; expire the observed skill context'),
    (0x1802f50, 30, '3cc04120', 'HUD rectangle: orig ldur q0,[x9,#4]; optional screen-aspect shadow rectangle'),
  ],
}

BINDING += [{"what": 'Z-A startup cuts and camera, HUD and clock observations', "now": "build", "goal": "unreviewed", "purpose": 'runtime', "why": "Exact instructions and offsets are verified only for the registered builds; general matching has not been reviewed."}]
