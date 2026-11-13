# Upstream and branch consolidation, 2026-11-12

Upstream snapshot: `seedds/nxnative` main
`c409041eac20bc429dddf6e8a5f542de5a75c235`.
The compatibility branch was 580 upstream commits behind before this merge.
The source merge includes those commits, the compute threadgroup limit
correction for M1/M2, and the subsequent shared-memory fence reachability
optimization. It does not deploy a new engine into installed games.

The current Mac/Metal 4 path follows upstream. The complete classic NVN ABI,
GL interop, iOS frontend, audio lifecycle and signed-image loader are retained
as separate source units selected together for iOS 16/17. The classic engine's
chain and shader libraries keep their original identity; see
[its README](../dm/gfx/nvn/legacy/README.md). Current translator outputs must
not be relabelled as classic libraries. Classic multi-program embedding is
rejected explicitly; the modern path supports upstream's tagged programs.

Validated locally before consolidation:

- Modern NVN GPU tests: 318 checks, zero failures.
- Classic NVN GPU/pipeline tests: 296 checks, zero failures.
- 83 C/Objective-C units compiled for arm64 iOS 16.1, zero failures.
- All iOS Swift sources typechecked for iOS 16.1.
- 104 shader-chain, extraction, frame-step, signing, settings and cache tests.
- 11 compatibility contracts and legacy image-atomic tests.
- Mac app packing suite executed; its failed schema/ABI-input cases were fixed
  and rerun individually. Other-GPU prewarm uses synthetic fixtures only.

Not validated: gameplay on five rebuilt game/shader pairs or any iOS device.
The existing apps, original game packages, game caches and save directories
were not replaced or modified by this source merge. An engine/shader upgrade
still needs its own game acceptance pass. No fresh gameplay FPS is claimed.

All six retired origin branches and four local build branches have been merged.
`main` and `ios16-ios17-compat` are aligned before their obsolete refs are removed.
The four dirty build worktrees have reviewable patch archives under
`contrib/tonton/archived-worktrees/20261112`; their files and caches remain intact.
A full Mac host linked successfully after consolidation. The final native save,
keyboard, controller and audio tests all passed with isolated fixture data.
