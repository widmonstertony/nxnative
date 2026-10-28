# Compatibility fork status

This fork preserves platform compatibility alongside upstream fixes. Game files,
extracted code, shaders, signing certificates, provisioning profiles and keys are
not distributed here.

## Source branches

- `ios16-pokemon-za-port`: iOS 16.1/17 host baseline, the older-GPU rendering path,
  tvOS source and Z-A compatibility. This update preserves all existing platform
  code and publishes the pending launcher, display and old-renderer repairs.
- [iphone-ipad-game-fixes](https://github.com/widmonstertony/nxnative/tree/iphone-ipad-game-fixes):
  current iPhone frontend, Chinese settings, full touch and keyboard controls,
  exact-build Arceus/Violet display adapters, Arceus timing and throwing controls,
  packing repairs and the Metal 4 dual-source fix. Its modern host retains its
  modern deployment requirement; it is not a binary replacement for iOS 16.

These branches have different renderer interfaces. Publishing both preserves the
tested source without claiming that replacing the legacy renderer with the
modern one would preserve iOS 16/17 support.

## Validation recorded on 2026-10-28

The compatibility launcher and host completed an Xcode build targeting iOS 16.1.
The pending-source publication also passed 79 iOS tool tests, the shader-table
metadata test, and the Z-A display/timing checks. These checks do not prove that
all games render correctly on the A10X: black characters, fragment image atomics,
matching shader companions and resource-container paths still require device
repair and verification. iOS 17-specific device testing is not newly claimed by
this publication.

The modern Arceus update was installed on the iPhone Air as version 20261028.6,
after a complete app-data backup and version readback. Its shader chain rebuilt
12,851 shaders for macOS/iOS. The dual-source regression passed 159 GPU checks in
each deferred-rendering mode, plus 48 depth/stencil and 51 texture-clear checks.
The user owns gameplay testing. Sustained 120 fps, frame generation and internal
resolution upscaling remain separate work; these are not established by fixing
the Metal compiler crash.

Remaining exported games are being built in a continuous bounded-parallel batch.
An unsigned IPA is preparation, not proof of device compatibility or playability.
Per-game failures and unavailable signing must remain visible instead of being
counted as successful delivery. Current device work excludes Apple TV.
