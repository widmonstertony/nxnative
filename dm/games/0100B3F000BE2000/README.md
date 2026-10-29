# Pokken Tournament DX

Provisional external profile, owned base 1.3.3, main build
`49690ba2efdcd7a76a506749e1b4494c`. This note does not register a playable game.

## Found on this game

- [Legacy depth prediction](../../../docs/reference/rendering.md#legacy-depth-prediction-and-secondary-blend-sources): fragment `6d348d1e77602543_b` reports the same invalid-depth error for both depth-less and Depth16 descriptors. The shared precompile guard is GPU-regression tested.
- The A10X log also records unbound vertex constant bank 1 and an address fault. The unified zero uniform bank prevents the unbound read from sharing the writable storage sink; installation alone does not prove the game is fixed.
- [Missing captured stages](../../../docs/reference/shaders.md#captured-nvn-stages-missing-from-the-offline-map): M2 captures `7f80dae1c4528abc`, `c0eb687c3323a8ea`, `2e5f3ae7af089b5c`, and `264c9a364b6ad468` have verified control/code identities. Only the first shares an exact code area with existing static programs; no alias to a similar shader is used. All 158 stages in the augmented external profile translate successfully. Rebuild and device installation are tracked separately from gameplay, which the user tests.

The minimum-16.1 legacy host `20261029.2` was installed on both iPads with code/version readback. M2 remains black and still exposes the four missing stages; that installation is not a completed rendering fix. The augmented-resource `20261029.3` update is uploading to both devices.
