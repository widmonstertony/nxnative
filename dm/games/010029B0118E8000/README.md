# Need for Speed: Hot Pursuit Remastered (`010029B0118E8000`)

Update 1.0.3 (v196608) over the base game (v0), SDK 10.4.1. Criterion's engine (ported by Stellar Entertainment) on NVN, with Bink movies and Criterion's Bundle 2 (`.BNDL`) files. Modules `main`, `subsdk0` (GLSLC, NVN's runtime shader compiler; not loaded, nothing calls it), `subsdk1` (NintendoSDK_movie) and `sdk`.

Status: plays on the Mac (Apple M4, 2026-10-28): boot, the Autolog connection screen (offline, it goes on by itself), the career map, car select and whole races (Grand Ocean Road, Mystic Lake Road, South Face Drive, First Offence with the gold medal), at 60 fps with sound, a Switch Pro Controller and saves. In two sessions of 7 and 11 minutes: no crash, no new red line; at 60 fps 81% of the 300-frame windows held 16.7 ms (the others, menus and loading screens, 18 ms), 0.37% of the frames dropped, GPU 6.3 ms a frame (p50), the main thread about 4 ms.

A contributor's tests on 1.0.3 (routes and durations not recorded):

- **iPhone 18 Pro Max** (`iPhone19,3`, iOS 27.0.1, 2026-10-30; Xcode 27.1, a free Personal Team, `com.apple.developer.kernel.increased-memory-limit`): works and looks good. The log passed 6,000 frames with no crash and no missing shader; sampled windows held about 16.7 ms, which does not measure whole races. Some audio underruns; the same `nvnDeviceGetInteger` and format 0x27 lines as on the Mac.
- **Mac** (Apple M4, macOS 26.6.2, Xcode 27.1, 2026-10-29): reaches the menu at 30 fps, before the 60 fps profile. 55 seconds under Metal API validation: 1,200 frames and the startup logos, no crash or missing shader, all 2,154 shaders compiled.

## What it needs

| Setting | Where | Why |
|---|---|---|
| The shaders of `SHADERS.BNDL` | `shader_split.py` `bnd2_shaders` | the 2,112 GLSLC outputs are in zlib resources of a Criterion Bundle 2 ([GLSLC outputs in Criterion's Bundle 2 resources](../../../docs/reference/shaders.md#glslc-outputs-in-criterions-bundle-2-resources)) |
| `fps_target 60`, `present_interval display` | [`game.tsv`](game.tsv), `hle_fpslock.c` | 60 fps (30 on the Switch), see [Frame rate](#frame-rate) |
| The frame limiter's spin cut (`main+0x4835a4`) | [`patches.py`](patches.py) | the engine's own 30 fps wait |
| `enc_thread on` | `game.tsv`, `nvn_rec.h` | the game waits on its fence every frame; see [Frame rate](#frame-rate) |

The rest of the profile is what `profile_guess.py` made of the survey: the 3.25 GB heap of the hardware pool, no virtual address memory.

The reader's [resource checks](../../../docs/reference/shaders.md#glslc-outputs-in-criterions-bundle-2-resources) change nothing on 1.0.3: over all 3,370 bundles (161 of them stored, the rest compressed; 518,261 blocks) the output is byte for byte that of the unchecked reader, nothing is rejected, and `SHADERS.BNDL` gives the same 2,112 GLSLC outputs.

## Frame rate

- **Current: 60 fps.** The engine has a 60 fps mode: a uint32 at `main+0xf0043c` (0 at boot) makes it take its frame time from the timer object at `[main+0xed96a8]` (+0x30 the frame in system ticks, +0x28 a tenth of it) and step the game by the floats at `[main+0xeffc60]` +0x30 (2D) and +0x50 (3D). All of these already hold 60 fps values when the game runs (320,000 ticks, 1/60 s): the host writes the mode switch (`hle_fpslock.c`, `MODE_U32`) and keeps the others at the target (`TICKS_U32`, `SECS_F32`; at 30 it writes 640,000 and 1/30). At 30 fps the frame limiter (`main+0x483530`) spins on the system tick (`main+0x86f070`) until `[x19+0x20]` ticks per frame have passed; the rewriter cuts its branch back (`main+0x4835a4`), and the host paces the presents (`present_interval display`; the game asks for interval 2). From masagrator's FPSLocker config for this build (FPSLocker-Warehouse, `patches/010029B0118E8000/799D1061182C1302.yaml`; the frame-time instruction found by theboy181); each value was checked in the running game before writing.
- **Resolved: 18.1 ms frames (55 fps) in races at 60.** The game calls `nvnSyncWait` twice a frame on a fence it places after its submission, so with Metal encoding on the submit thread the frame was the game's work (about 4 ms) plus the host's encoding (2.5 ms) plus the GPU (6.3 ms) in series. A lower frame-tick target (66, 80, 120 fps) and handheld mode (GPU 5.4 ms) changed nothing; with `DM_NVN_ENC_THREAD=1` the race frames hold 16.66 ms (p95 16.9–17.5). The profile's `enc_thread on` makes that the Mac default for this game.
- Game speed at 60 was checked by play: races, the timer and the AI run at normal speed.

## Rendering

- **Resolved: a crash at the first loading screen** after `texture upgraded to allow format views` (a 4096x1024 texture, base format 73, sampled as format 70): the upgrade's copy ended the render pass while the draw bound its arguments ([A texture upgrade while a draw binds its arguments ends the pass](../../../docs/reference/rendering.md#a-texture-upgrade-while-a-draw-binds-its-arguments-ends-the-pass)).
- **Current:** `vertex attribute format 0x27 (8 / 16-bit integer) feeds a float input`, converted on the CPU at replay; no visible effect.
- `nvnDeviceGetInteger` items 0x60 and 0x61 are answered 0, as before; no visible effect.

## Services

- Autolog, the game's online layer, finds no network (`nifm` answers as offline) and the game goes on to the career map after its connection screen.

## Found on this game

General changes first needed here; each applies to every game:

- [GLSLC outputs in Criterion's Bundle 2 resources](../../../docs/reference/shaders.md#glslc-outputs-in-criterions-bundle-2-resources) (`shader_split.py`)
- [A texture upgrade while a draw binds its arguments ends the pass](../../../docs/reference/rendering.md#a-texture-upgrade-while-a-draw-binds-its-arguments-ends-the-pass) (`nvn_mtl.m`)
- `hle_fpslock.c`: frame times in system ticks, frame steps in seconds and a mode switch as frame-limit fields; the profile key `enc_thread`

## iOS 16/17 fork observations

# Need for Speed Hot Pursuit Remastered

Provisional external profile, owned base 1.0.3. Gameplay validation remains open;
this note does not register a playable game.

## Found on this game

- The first A10X draw used an unbound vertex constant bank 0 and faulted the GPU. The shared zero uniform bank keeps that read separate from the writable sink.
- [Legacy depth prediction](../../../docs/reference/rendering.md#legacy-depth-prediction-and-secondary-blend-sources): fragment `721bdcf892c65085_b` writes depth. A native reproduction showed an invalid depth-less compilation preventing later valid depth formats from compiling. Rejecting the invalid descriptor before Metal leaves Depth16, Depth32 and Depth32/stencil pipelines available. The actual fragment passes the invalid/valid/invalid regression sequence.

The complete minimum-16.1 repair package `20261029.2` built successfully and was
installed on both iPads with exact code/version and saved-state readback.
The user tests the game; a successful build or installation does not establish
that every black-screen cause is resolved.

Earlier: the user reported a black scene on M2 with `20261029.5`.
Its log contains ten missing stages and a BC texture readback returning zeroes;
the shared compact-binding fix alone did not restore this title.

### Compact binding replay repair (2026-10-29)

[Compact buffer bindings](../../../docs/reference/rendering.md#compact-buffer-bindings-lost-by-legacy-replay)
were silently discarded by this game's frozen legacy host. Minimum-16.1
`20261029.5` is now verified installed on both iPads, including code sections,
version and saved-state fingerprints. The A10X helper initially returned NO and
briefly disconnected, but later readback confirms the same `.5` completed;
no retry or uninstall was needed. This does not establish a corrected picture.

### Runtime coverage and CPU texture reads (2026-10-29)

All ten missing M2 `.5` stages were captured and validated against their actual
control/code hashes: five vertex and five fragment programs. Stable per-key
packages extend the external profile; the complete matching 99-stage Mac/iOS
resource build succeeds. Captures and translated game assets remain outside Git.

[Legacy CPU-owned BC readback](../../../docs/reference/nvn-objects.md#legacy-cpu-owned-bc-textures-return-zero-blocks)
also lacked the modern path's ownership check. Its exact no-BC regression now
passes, with a failing pre-fix control. This is separate from recompressing a
truly GPU-written BC image, which remains unsupported. The device log alone
does not establish the failing texture's ownership. Build `.6` will contain
both the resource coverage and CPU read fix; installation and user picture
confirmation remain pending.

### Format-view consumer crash (2026-10-29)

Both `.6` iPad logs reproduced SIGSEGV in `legacy_use_resource`
right after an integer-to-normalized format-view upgrade. The [ended consumer
encoder](../../../docs/reference/rendering.md#legacy-format-view-copies-end-a-live-consumer-encoder)
fix moves that copy before encoder selection and preserves the producer's GPU
writes. `.7` will include this repair and automatic hardware-input overlay
hiding. A black scene may have additional causes; installation does not certify
picture recovery. GPU-written BC recompression remains open.

### Further runtime coverage and engine frame limits (2026-10-29)

M2 iPad version 20261029.7 reaches rendering after the ended-render-encoder
repair, but the user reports another black screen after entering. The new log
contains five unmapped runtime stages, including a vertex stage. Their complete
control/code captures validate against their keys; rebuilding all 104 stages
with chain `0cb0dfeacee3` succeeds. Rendering after packaging remains untested.

The same log shows 120 Hz callbacks but 29.98 actual presents and interval two.
The engine also busy-waits at `main+0x483588..0x4835a4`. The exact-build
[FPSLocker configuration](https://github.com/masagrator/FPSLocker-Warehouse/blob/v4/SaltySD/plugins/FPSLocker/patches/010029B0118E8000/799D1061182C1302.yaml)
removes that back-edge and changes the 60-fps-mode flag, 19.2-MHz timer target,
timer tolerance and both 2D/3D time-step fields together. The host applies those
same fields only to this build with the asserted instruction repair present.
`DM_NFS_FPS` offers original 30, 30, 60 and experimental 120; display pacing
must also ignore the game's interval-two request. Startup configures both the
NVN pacing rate and its display-link mode, before Metal initialization. An unset target defaults to
120. This is a target, not measured performance: actual gameplay speed,
stability and frame rate at 120 still need the owner's testing.

With TonTon's `DM_FRAME_LIMIT=unlimited` library preference, this same exact-build
adapter now writes one measured active-guest-clock duration to the timer, tolerance
and both 2D/3D consumers, instead of assuming every rendered frame lasts 1/120 s.
The verified busy-wait repair remains required. Eleven production timing cases,
including 400 changing-rate steps at 120/60/40/20 Hz, pass under ASan/UBSan.
The summed simulation time agrees with measured active time in the test; real
device driving speed and suspension behavior remain pending owner testing.
Explicit fixed targets retain their previous behavior with the original-game
library preference. This adapter does not change the race-only drift mapping.

Candidate `20261029.9` passes a full minimum-16.1 host build and legacy resource
audit. Its packaged fixup marker, five added libraries/reflection files,
30/60/120 launcher choices and startup timing entry point were checked. Ten
production timing/pacing cases and nine existing engine-limit cases pass, plus
44 tool/docs/settings/shader-dump/chain tests. Automatic gameplay regression was
not run: the owner explicitly handles gameplay tests. No measured FPS or
corrected-picture claim is made from these build checks.

The owner's `.9` retry still goes black after entering. Its actual device log
now records 119.93 drawable presents/s and no unmapped-stage warnings, so neither
the old 30-fps engine wait nor the five missing stages explains the remaining
picture failure. The BC readback warning persists, but its previous wording
incorrectly inferred a GPU write solely from the absence of a known CPU upload.
The next diagnostic host records bounded descriptor/ownership metadata with
`DM_NVN_BC_READBACK_TRACE=1`, and one pass/binding snapshot every 600 frames with
`DM_NVN_PASSDUMP_EVERY=600`. These switches are opt-in and do not change storage
ownership, recompress textures, or establish that the BC warning causes the
black screen. The owner drives the reproduction; no automatic game launch.

Version `.11` reproduced the same black scene through frame 46,200. The main
1920x1080 scene target was cleared to black with no world draw before the
post-process chain, while UI draws continued at about 119.9 presents/s. The
first concrete data loss occurs at frame 218: a 256x256 BC texture has 26,396
non-zero bytes in its CPU-visible pool, but `ReadTexels` classifies it as having
no CPU content and returns 32,768 zero bytes. The descriptor has no image flag
and no guest GPU write precedes the read; its Metal `ShaderWrite` usage belongs
only to the no-BC decode kernel.

[Legacy CPU-owned BC readback](../../../docs/reference/nvn-objects.md#legacy-cpu-owned-bc-textures-return-zero-blocks)
now records actual guest GPU writes rather than inferring ownership from Metal
usage. A focused regression preserves all 32,768 original blocks and verifies
the GPU-to-CPU ownership transitions. This is the first candidate that repairs
the observed frame-218 data loss; a successful build is not yet a corrected
picture claim, which still requires the owner's device test.

### Initial-pool-content parity (2026-10-30)

The agent reproduced the black UI after confirmed A inputs on M2. The intro
video is visible. In `.19`, a bounded source decode proves serial 207 contains
a valid 256x256 BC3 sRGB opacity image in a CPU_UNCACHED pool (0x22), while
the corresponding GPU RGB and alpha both read zero. No CPU-upload profile
flag or guest GPU write accounts for this initial content.

A separate production-recorder regression exposed missing
[initial pool content](../../../docs/reference/nvn-objects.md#a-pools-storage-at-creation-is-its-textures-content)
semantics in the legacy backend: published initial data was zeroed instead of
uploaded. The modern path already supports it. The compatibility port passes
the GPU regression while keeping unflushed cached storage and COMPRESSIBLE
images excluded, and never reinitializes an existing GPU allocation. This
is a concrete host fix. After the save-preserving `.20` M2 installation,
the same sampled texture's GPU RGB matches the decoded source exactly and
its alpha is restored (mean absolute error 0.85/255, maximum 32/255 after
the BC-to-ASTC path). The EA dialogs now show
text, logos and borders. This verifies that particular data-loss repair,
not the complete 3D picture or gameplay: the bounded A-input reproduction
ends on the user-agreement page. No shader chain or game resources changed.


### Driving-only X/Y and audio underruns (2026-11-01)

The owner confirmed playable graphics but intermittent audio and requested X/Y
functions to exchange only during a race. `nfs_driving_input.h` checks the exact
`799d1061182c1302e08e706b84ce76e5` main image and five instructions before reading
its control groups: CAR enabled, MENU and DEBUG disabled. The host swaps only
X/Y bits after input sources merge. The screen layout and base keyboard or
controller mappings stay unchanged. Unreadable or unknown state keeps native
buttons. The production HID path passes 411 checks including menu transitions,
all face-button combinations and touch/keyboard, controller and script inputs.

The original Air log contains real AudioUnit underruns: some roughly 12-second
intervals inserted 1.9–2.94 seconds of silence. This title now requests a 2.5 ms
session buffer instead of 5 ms, to reduce callbacks consuming several small
guest blocks at once. Actual hardware rate and granted buffer duration remain
logged. Other games keep 5 ms. This is a measured-failure-driven candidate,
not a claim that every source of audio starvation is fixed. Compare new
underrun/silence counters on the owner's next normal play session. The queue
ownership, sample conversion and render backend are unchanged.
