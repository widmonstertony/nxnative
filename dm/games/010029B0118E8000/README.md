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

Current: the user still reports a black scene on M2 with `20261029.5`.
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

[Legacy CPU-written BC readback](../../../docs/reference/nvn-objects.md#legacy-cpu-written-bc-textures-return-zero-blocks)
also lacked the modern path's ownership check. Its exact no-BC regression now
passes, with a failing pre-fix control. This is separate from recompressing a
truly GPU-written BC image, which remains unsupported. The device log alone
does not establish the failing texture's ownership. Build `.6` will contain
both the resource coverage and CPU read fix; installation and user picture
confirmation remain pending.

### Format-view consumer crash (2026-10-29)

Current: both `.6` iPad logs reproduce SIGSEGV in `legacy_use_resource`
right after an integer-to-normalized format-view upgrade. The [ended consumer
encoder](../../../docs/reference/rendering.md#legacy-format-view-copies-end-a-live-consumer-encoder)
fix moves that copy before encoder selection and preserves the producer's GPU
writes. `.7` will include this repair and automatic hardware-input overlay
hiding. A black scene may have additional causes; installation does not certify
picture recovery. GPU-written BC recompression remains open.
