# Pokken Tournament DX

Provisional external profile, owned base 1.3.3, main build
`49690ba2efdcd7a76a506749e1b4494c`. This note does not register a playable game.

## Found on this game

- [Legacy depth prediction](../../../docs/reference/rendering.md#legacy-depth-prediction-and-secondary-blend-sources): fragment `6d348d1e77602543_b` reports the same invalid-depth error for both depth-less and Depth16 descriptors. The shared precompile guard is GPU-regression tested.
- The A10X log also records unbound vertex constant bank 1 and an address fault. The unified zero uniform bank prevents the unbound read from sharing the writable storage sink; installation alone does not prove the game is fixed.
- [Missing captured stages](../../../docs/reference/shaders.md#captured-nvn-stages-missing-from-the-offline-map): M2 captures `7f80dae1c4528abc`, `c0eb687c3323a8ea`, `2e5f3ae7af089b5c`, and `264c9a364b6ad468` have verified control/code identities. Only the first shares an exact code area with existing static programs; no alias to a similar shader is used. All 158 stages in the augmented external profile translate successfully. Rebuild and device installation are tracked separately from gameplay, which the user tests.

The minimum-16.1 legacy host `20261029.2` was installed on both iPads with code/version readback. The augmented-resource `20261029.3` update is installed on both devices. The user still reports black on M2; the new log no longer reports those four missing stages but still reports unbound constants. Resource completion alone did not fix the picture.

### Compact binding replay repair (2026-10-29)

[Compact buffer bindings](../../../docs/reference/rendering.md#compact-buffer-bindings-lost-by-legacy-replay)
were silently discarded by this game's frozen legacy host. The production
recorder/replay regression passes 252 checks; the old host fails all 112 compact
binding checks. Minimum-16.1 build `20261029.5` includes the shared host repair
without changing the frozen shader chain. Packaging and device installation are
in progress; this does not establish a corrected picture or gameplay.

Device confirmation: both iPads have `20261029.5` installed with code/version
and saved-state readback. The user confirmed that M2's picture is restored after
relaunch and Start. This confirms the compact binding repair for that scene;
full gameplay, A10X rendering and performance remain unverified. The next M2 log
still exposes additional runtime stages, so coverage is not complete. Five
additional exact captures were saved and validated outside the repository. The
expanded matching 163-stage macOS/iOS set compiles successfully; a later host
rebuild and package must carry it. The installed `.5` still contains 158 stages,
and the user's current game was not interrupted.
