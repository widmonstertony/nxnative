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
