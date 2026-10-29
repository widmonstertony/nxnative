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

Current: the user still reports a black scene on M2 with `20261029.2`.
Its runtime log names ten stages absent from the offline map and a BC texture
readback that returns zeroes; neither issue is resolved by the depth fix.
A diagnostic build captures exact missing control/code bytes for offline
translation. No alias to a similar program or successful-rendering claim is made.

### Compact binding replay repair (2026-10-29)

[Compact buffer bindings](../../../docs/reference/rendering.md#compact-buffer-bindings-lost-by-legacy-replay)
were silently discarded by this game's frozen legacy host. The production
recorder/replay regression passes 252 checks; the old host fails all 112 compact
binding checks. Minimum-16.1 build `20261029.5` includes the shared host repair
without changing the frozen shader chain. Packaging and device installation are
in progress; this does not establish a corrected picture or gameplay.

Delivery update: M2 `20261029.5` is now installed with exact executable/code-section and saved-state hashes verified; user picture confirmation is pending. The A10X installer returned `installApplication returned NO` for the same verified upload, then its MCP briefly disconnected. Readback after reconnection confirms `.2` remains installed. The new upload and diagnostics are preserved; no uninstall or blind retry was performed. The old iPad was running an unrelated game, so further installation diagnostics wait for the user to return to MCP.
