# Pokémon Legends: Arceus (`01001F5010DFA000`)

Update 1.1.1 (`v262144`) over the base game, SDK 11.4.0. Game Freak's engine between Pokémon Sword's ([0100ABF008968000](../0100ABF008968000/README.md)) and the Trinity engine of Pokémon Scarlet and Legends: Z-A, on NVN, with Havok physics, Wwise sound and Pia / NPLN networking. Modules `main`, `subsdk0` (the movie module, which the profile does not load: `main` takes nothing from it the host does not supply), `subsdk1` (GLSLC) and `sdk`; the `sdk` build (`b39add63…`) is Kirby and the Forgotten Land's ([01004D300C5AE000](../01004D300C5AE000/README.md)). Started from the provisional profile the NSP script wrote from its survey (`dm/games/profile_guess.py`). Plays on the Mac at 30 fps, as on the Switch, from the first boot to free movement on the Obsidian Fieldlands beach (a short check, below). An unsigned IPA is built (4.2 GB); iOS is untested.

## What it needs

| Setting | Where | Why |
|---|---|---|
| 5 GB block: `mem_reserve 0x140000000`, `mem_alias 0x118000000` (4.38 GB), `sys_resource 0x1000000` | [`game.tsv`](game.tsv) | the NPDM declares 16 MB of system resource (virtual address memory); `nninitStartup` sets a 0.02 GB heap and initializes malloc's StandardAllocator over 32 GB of address space (`main+0x2779d8c`), which the host gives 4.06 GB ([StandardAllocators over 12 to 62 GB of address space](../../../docs/reference/memory.md#standardallocators-over-12-to-62-gb-of-address-space)) |
| Node area cut and 2 MB alignment of large regions (SDK 20's) | `dm/tools/sdk_patches.py` SDK-wide rules, `sdk` build `b39add63…` (Kirby's) | without the alignment the 4.06 GB region goes to the next 1 GB boundary past the node area and does not fit ([1 GB alignment of regions of 1 GB and more](../../../docs/reference/memory.md#1-gb-alignment-of-regions-of-1-gb-and-more)) |
| `dual_want.tsv` | profile | two post-effect pixel shaders are blended with their output 1 as the second source ([A written secondary blend source](../../../docs/reference/rendering.md#a-written-secondary-blend-source-nvn-dual-source-blending)) |
| `depth_mode zero` | `game.tsv` | the game sets the near=0 depth mode, so the pipeline bases made before it runs take the `main0_z` vertex entries |
| `pad_layout full` | `game.tsv` | the 3D gamepad layout: the camera is on the right stick |
| The capture demo's empty result | [`patches.py`](patches.py) `MATCH_CUTS` | a workaround for a null read in the game's own code, whose cause is open: [Crash in the capture demo](#crash-in-the-capture-demo) |

No host code keyed to this game.

## Bring-up

- **Resolved: a `Break` in `nninitStartup`** (`Break#1 reason=0` at `sdk+0x39fb54`, from `StandardAllocator::Initialize` at `sdk+0x2f98e4` ← `main+0x2779d8c`). The host's cap lowered the allocator's 32 GB to 4.06 GB, but this `sdk` build aligns a region of 1 GB or more to 1 GB, so the region would have started at alias +1 GB and ended past the 4.38 GB alias region. The SDK-wide node-area patch matched this build (implementation 3), the alignment patch had no implementation for SDK 11.4: its placement helper (`sdk+0x34e1d8`) is the SDK 12.3.9 one with 8 more bytes. It is now the alignment patch's second implementation, and both cuts are registered for this build: a build a profile was brought up on takes only registered cuts, so with this profile in `dm/games` the SDK-wide rules no longer reached it (the `Break` came back once). The region lands at alias +0.06 GB.
- **Resolved: an abort on Metal's compiler queue** a few seconds into the language screen (`[AGX] Failed assertion "error == MTLCompilerErrorNoError"` in `findOrCreateComputeFastClearPipeline`, `MTLCompilerService` crash reports in `AGCLLVMStatelessFragmentObject::buildBlendFactor`), with or without the pipeline prebuild. The pipeline was `ha_post_effects.bnsh` variation 4 (`f4f36a03b0c6691d`): an RGBA16Float target blended with destination factor `SRC1_ALPHA`, the shader writing outputs 0 and 1. A temporary log of each blended attachment in `pso_desc` named it as the last pipeline before the abort. `DM_NVN_DUAL_WANT` then listed a second one, `ff45da02e225f961`, in the first minute.
- `[RED] no render target could get an MTLTexture` once at boot ([Passes with no render target](../../../docs/reference/rendering.md#passes-with-no-render-target)); no other red line on the route below.
- The NSP script's rewrite step was reused after the alignment rule was added: it keyed only the patch files that name one of the modules' builds ([The packing script in detail](../../../docs/development.md#the-packing-script-in-detail)).

## Crash in the capture demo

Open: the cause; the crash is worked around ([GitHub issue #712](https://github.com/seedds/nxnative/issues/712)).

- **Symptom:** `CRASH sig=11 addr=0x118 pc=main+0x16e34fc lr=main+0x16e34ac` on `JobThread2`, x8 = 0, after 37 to 65 minutes of normal play on the Mac, with no `[RED]` line before it. Three reporters; the first lost all three sessions of one day to it. The backtrace is always `main+0x19d244c main+0x1cd25e0 main+0x1cceda8 main+0xace34c main+0x1bd9e9c`, and the last frame takes about 1 ms of GPU time.
- **What the code does:** the capture demo task (`main+0x1ccf1a4`; `bin/demo/graphic/system_resource/capture/ob0201_00/anm/capture_animcfg.tracn`, `ThrowableObject`, `my_poke_ball`) builds a ball object and calls `main+0x19d2368`, which calls `main+0x16e33ec` on a 0x1d0-byte object held at `+0x130` of a 0x2e8-byte owner. That function locks the weak reference at `this+0x88` (`main+0x16e9e98`) and reads `[result + 0x118]` with no check. Two things give a null result: the reference itself is null, or its object is dead. The crash log cannot tell them apart.
- **What was measured:** the object's constructor zeroes `+0x88` (`main+0x18954c4`, frame 4595 on the first load) and the field setup's state 0x18 fills it (`main+0x1877a4c` through `main+0x16dde90`, frame 4648): 53 frames with a null reference in that run. That state runs on whichever thread takes the job: the main thread in that run, `JobThread1` (frame 5548) in another. The part of the task that was read has no check for this. At the crash the main thread and `JobThread1` are parked in the job wait, so nothing else is running on that object at that instant. No host service is on the path.
- **Not established:** which null path the crashes take; whether the owner is rebuilt for each scene (one reporter's single hit was followed by a new scene's textures). The likely reading is an order the game does not enforce between the task's own loading and the field setup, which the host's timing exposes. A fresh save does not reach the path: 9 minutes of the route below never called `main+0x19d2368`.
- **Workaround:** `patches.py` returns the function's empty result (`{0, 0}` through x20) on both null paths, before it takes any reference. All 12 direct reads of the result (the ball's `+0x810`, `main+0x19cbcd0` to `main+0x19d1fac`) null-check it; three other places copy it as a reference (`main+0x19cc230`, `main+0x19d2074`, `main+0x19d257c`), whose users were not followed. The room for the check is two of the function's five identical blocks, so the abort stub stays. It is function-matched on 1.1.1 ([function-matched cuts](../../../docs/reference/rewriter.md#function-matched-cuts-for-unregistered-builds)); other builds are unchecked and get a red line if the function differs.
- **Checked:** the rewriter matches the rule once and writes the five cuts, and the game then boots on the Mac to the field setup with no crash (200 s, on the disk's older shader libraries). The patched function run on the module's own bytes in a small interpreter: both null paths return `{0, 0}` with the stack and callee-saved registers restored, and never reach `main+0x16e34fc`; a live object goes on to `main+0x16e3420` as before. The issue's earlier form of the cuts, with the same effect, ran about 7 hours on the Mac with no crash, and the skip was seen once (id 1, frame 142020, followed by 55 minutes of play). These cuts have not met the path in play, and any visible effect on that one ball is unknown.
- **To settle the cause:** `DM_PROBE=main:16e341c,main:16e3828` on a save with Poké Balls, with `DM_PROBE=main:16dde90` to see the order.

## Performance and memory

- On the Mac (M6): 30 fps as on the Switch (`power` lines: 30.0 fps, CPU 0.64 W, about 20% of a core), with long frames of 100–260 ms where new pipelines are first built (that run's archive was made for the near=−w depth mode, before `depth_mode zero`; the Mac build from this profile makes the near=0 bases, not measured on the route since). Resident memory 2.7 GB and 1.46 GB of Metal allocations on the beach after 7.5 minutes.

## Files and shaders

- RomFS 6.0 GB, 19,101 files: effects (`bin/effect`, 2.5 GB), 678 GFPAK archives under `bin/archive` (1.6 GB, every entry Oodle Kraken: [Oodle entries of GFPAK archives](../../../docs/reference/shaders.md#oodle-entries-of-gfpak-archives)), Wwise banks (`bin/sound/NX64/wwise/bank/Default.pck` is the `romfs_marker`), message tables, compiled scripts (`bin/haxe`, `.blua`), and Trinity-style model files (`.trmdl`, `.trmsh`, `.trmtr`). The game probes `arc/data.trpfd` and `arc/data.trfmd` (Trinity's pack index), which it does not ship.
- Shaders: 12,851, by where each first appears: 11,352 in the effects' particle files (`.ptcl`), 1,386 in the loose BNSH files of `system_resource/gfx2/shader` (materials, terrain, water, grass, lighting, shadows, post effects), 73 in the GFPAKs, 40 in `main`. 6,156 pixel shaders, 5,474 of them write exactly colours 0 and 1.

## Mac routes

- The work folder's `run/boot.sh <log> [secs] VAR=value…` runs `build/plahost` (a renamed copy of the host) on the NSP script's build, RomFS image and shader libraries; `run/ctl.sh` and `run/step.sh <shot> [wait] <presses…>` are Sword's (presses through `DM_CTL`, screenshots of the next frame). Run headless.
- From a fresh save (`DM_KBD=<name>` answers the name): A at the language screen (about 70 s after start with the archive opening and the first shaders), A presses through Arceus's questions and the name, the fall through the rift, waking on the beach, Professor Laventon and the three Pokémon, then the player walks (`LUp`, `LRight`).
- The route checked on the Mac: language, name, the opening, the beach with Laventon, Cyndaquil, Rowlet and Oshawott, and a walk through the grass toward the first marker. The game had not saved yet, so there is no reference save.

## Found on this game

General changes first needed here; each applies to every game:

- **Function-matched cuts take branches inside the matched function, and read the trap word `0xe7ffdefe`** (`nso_match.py`): [Function-matched cuts](../../../docs/reference/rewriter.md#function-matched-cuts-for-unregistered-builds).
- **The node area and 32 MB region alignment cuts of `sdk` `b39add63…`, and the SDK 11.4.0 implementation of the SDK-wide alignment patch** (`sdk_patches.py` `MATCH_CUTS`; the build's row was removed on 2026-10-29, as the rules give the same cuts): [1 GB alignment of regions of 1 GB and more](../../../docs/reference/memory.md#1-gb-alignment-of-regions-of-1-gb-and-more).
- **Dual-source blending for NVN shaders** (`dmsh_entry.py` `fs_dual`, `main0_d`, the profile's `dual_want.tsv`, `DM_NVN_DUAL_WANT`; `pso_desc` `pso_reads_src1`): [A written secondary blend source (NVN dual-source blending)](../../../docs/reference/rendering.md#a-written-secondary-blend-source-nvn-dual-source-blending).
- **The NSP script's rewrite key always covers `sdk_patches.py`** (`patch_files`): [The packing script in detail](../../../docs/development.md#the-packing-script-in-detail).

## iOS 16/17 fork observations

# Pokemon Legends: Arceus

Current preparation: owned update 1.1.1, main build `aee8f150dda1b5a838806e1a5ea6827a`. The full profile and shader tables are still provisional in the external game work directory. Gameplay and device validation remain open.

## Mission-completion crash tracing

Two retained Air reports, including one from the standalone app, fault at
`main+0x16e34fc`: the original instruction reads an allocator at offset `0x118`
through a null resolved scene owner. The user encountered this at mission
completion, before manually saving. These reports do not establish a save-write
failure or a GPU fault, and existing saves do not recover the unsaved mission.

Six exact-build observation sites trace resource-service initialization, owner
assignment, request entry, weak-owner resolution, the failing allocator read,
and destruction. The callback uses kernel-mediated reads, captures control-block
counts and type ancestry, and retains a 32-entry ring with thread identity. It
dumps that history before the original null read; no guest reference, register,
allocator or return value is changed. Unsupported build/layout/gate combinations
remain inactive. This is diagnostic instrumentation, not a lifetime repair or a
guarantee that another crash has the same cause. Matching rewritten code and
fixup/gate/observation tables must be delivered together.

`make -C dm/host/tests GAME=0100F43008C44000 arceus-task-trace arceus-display`
checks inaccessible/overflow/null reads, reference snapshots, bounded history,
all six callbacks, unchanged guest registers, and camera/HUD regressions without
game assets. The generic profile used to compile the tests does not select a
different game at runtime.

## Legacy iPad rendering repair

M2 build `20261029.1` installs but the user reports a gray scene. The log shows
depth pipeline rejection and real SRC1-blended fragments with two written
outputs (`f4f36a03b0c6691d_b`, `ff45da02e225f961_b`). The shared
[depth prediction and secondary blend repair](../../../docs/reference/rendering.md#legacy-depth-prediction-and-secondary-blend-sources)
preserves these outputs instead of disabling their blending. The complete M2
minimum-16.1 host and full package `20261029.2` build successfully; installation
and user evaluation are separate checkpoints.

The A10X package is still blocked by two layered shaders with vertex/storage
dependencies and eighteen genuinely used sampler sets exceeding Tier 1. The
strict audit remains enabled. Bounded image atomics alone do not establish
A10X support, and this game has not been installed on that iPad.

The exact-build display observation sites adapt six camera aspect constants and the original HUD rectangle to the current window. The original instructions and full GPR/SIMD gate preservation were inspected before enabling these sites. No executable memory is modified at runtime. The HUD table is borrowed through thread-local storage; the original table stays untouched. Geometry follows the author's [ultrawide patch](https://github.com/Fl4sh9174/Switch-Emulator-Ultrawide-FPS-Mods), parameterized for the actual device.

GFPAK type 3 archives require the game's own Oodle decoder. The earlier baseline skipped 678 archives and is not a completed build. The source survey now detects those archives before the split; corrected shaders must be rebuilt. The shared touch surface retains every native button and keyboard direction.

High frame rates: an exact-build native observation adapter now targets 30/60/120, publishing paused-aware elapsed nanoseconds and replacing two fixed animation steps. Its original instruction signatures are checked by the rewriter. CPU tests verify one second of game steps per real second at 20/30/47/60/120 fps. Like the public dynamic patch it bounds a long hitch to a 1/15-second step; under sustained rates below 15 fps the game can slow down. Real-device high-FPS and gameplay-speed validation remain open; this is not a measured 120 fps claim. Upscaling/interpolation need render-scale, motion/depth and pacing validation per device.

Air bring-up found an immediate deliberate exit 42 in `nninitStartup`, with
`sdk+0x2f98e4` returning from the allocator assertion. The SDK had the matched
62 MB node-area cuts but no large-region alignment cut. At alias base
`0x7010000000`, its 1 GB placement starts 768 MB into the alias region, so the host-capped 4.0625 GB
reservation cannot fit the 4.375 GB alias region. The exact SDK build
`b39add63421be525d352e576dab438d3` now keeps both node-area cuts and changes
the large-region alignment at `+0x34e244` from 1 GB to 32 MB. This is the
existing platform-limit mechanism documented in
[memory](../../../docs/reference/memory.md#1-gb-alignment-of-regions-of-1-gb-and-more).
Replacement build `20261028.2` and its signature passed verification. The SDK patch registry regression suite passed 15 tests. After an interrupted first wireless update, a same-bundle retry completed at 09:00 PDT with app-data and save verification. The allocator startup assertion is resolved and the intro renders with standard pipelines; full gameplay validation remains pending.

The first external exFAT build compiled all 12,782 shaders but failed while generating c1_full.tsv: AppleDouble `._*.metal` files were read as UTF-8 MSL. Both c1_guard.py and cb_extent.py now exclude those metadata entries. A regression invokes both real table tools on a valid shader beside binary sidecars and checks the real safety/extent rows. The corrected Oodle split found 12,851 shaders (69 additional keys); all compiled for the modern iOS host. The isolated iOS 16 compatibility build passed its 85-key probe, but the full set encountered a fragment image atomic operation unavailable at that deployment target. That build is paused with its cache retained; older-device support still requires a proper image-atomic compatibility path.

Air version 20261028.2 reaches the intro after the SDK allocator repair. Enabling Metal 4 pipelines then crashes Apple's MTLCompilerService in buildBlendFactor: two fragment shaders use secondary-source blend factors but their second output is emitted as MRT1 instead of color(0), index(1). The standard pipeline reports and skips the invalid PSOs rather than crashing. Versions .3–.5 deliberately kept Metal 4 unavailable pending a real dual-source variant; this is an explicitly open rendering workaround, not a completed shader fix. Temporary startup diagnostics ignored saved choices; those must be removed during delivery.

Air `20261028.3` was installed over Wi-Fi after a fresh complete191-file data backup and hash checks. The initial language menu rendered at119.96fps in the first measurement; a further33000 frames over296.341 seconds measured83.5–120.34fps, without crash markers. The default120 option and its explanation were visually verified in the Chinese launcher. Normal launcher startup and saved choices are restored. This proves the menu exceeds the old30fps cap, not open-world/battle performance or full gameplay-speed/input correctness; those remain open.

The user subsequently reported a stretched intro at43fps. The live scene log
measures roughly29–60fps with target120 still active,1920x1080 docked output,
thermal state2, and sampled GPU submissions taking17–40ms. The final bilinear
present pass is around0.5ms; changing that pass alone does not reduce the
preceding3D rendering load. Sustained120 and internal-resolution/upscaling
improvements remain open.

Static analysis found an additional camera descriptor setter at
`main+0x124ea80`: it copies descriptor aspect at`+0x20` into the camera at
`+0x240`, independently of the six constructor constants. Build`.4` adds a
byte-checked observation at`+0x124eac4` before`STR w10,[x8,#0x240]`.
It substitutes the device ratio only for the original16:9 input, preserving
square/offscreen/custom ratios and unrelated registers. The callback logs
corrections so the affected camera path can be identified in real scene logs.
Three device-ratio tests verify equal projected horizontal/vertical lengths,
custom-ratio preservation, and the existing HUD behavior;32 relevant tool
tests and the full iOS build pass. No shader-chain change is involved. This
exact-build change reaches only Arceus, so other game runtime regressions are
outside its scope. The reported cinematic's visual correction is still
unverified; the user now owns gameplay testing, and compilation/installation
of later games must not wait for an agent-driven gameplay test.

Touch throwing: the Air packing recipe enables `DM_THROW_ZR=1`, adding a
larger left-side Throw button (with a Chinese label) above the movement stick. Hold it to
prepare a throw, drag an independent right-side finger to aim, then release
the left finger to throw. It is a momentary alias of native ZR, not the ZL
focus toggle. The existing ZR stays available. Both use the same touch-owner
aggregation, so releasing either alias cannot release the other held finger;
sliding outside the shortcut retains ownership until release or cancellation.
The right camera finger keeps its ownership when crossing face buttons.
The shared frontend supports this opt-in without changing other games'
layouts or native controller/keyboard bits. Version`20261028.5` builds with
the existing exact modules, shaders, fullscreen and timing adapter retained.
Gameplay usability testing belongs to the user; installation status is in
the delivery receipt, not inferred from this source change.

### Metal 4 dual-source repair (2026-10-28)

The generic NVN offline chain now emits a distinct secondary-source entry for the two-output floating-point shaders. Both originally failing fragments (`f4f36a03b0c6691d`, `ff45da02e225f961`) with vertex `5356a9470575174c` compile on both Metal pipeline paths on an M4. The GPU regression reports 159 checks, zero failures in both TBDR modes; production NVN passes preserve extra-target clears and split dual/MRT transitions within a submission. Existing depth/stencil and texture-clear suites pass 48 and 51 checks; iOS metallib compilation also passes. Full chain 45d6a61446ec completed all 12,851 shaders on macOS/iOS with matching input stamps and generated c1/extent tables; the matching Air host passed its full Xcode build and version 20261028.6 was installed over Wi-Fi after a complete app-data backup and version readback. On-device gameplay stability of this repair remains for the user to test; no 120 fps performance claim follows from compiler correctness. The exact-build launcher restriction is removed only from the newly matched delivery. Ordinary MRT outputs, fullscreen/timing patches, and the left-hand throwing control are retained. See [dual-source blending](../../../docs/reference/rendering.md#dual-source-blending-from-output-location-1).


### Experimental image interpolation and spatial upscaling

The modern host adds a Chinese launcher choice for experimental image optical flow, alongside MetalFX spatial scaling. The exact-build defaults select native handheld mode and this combination; existing preferences are preserved. With a target above 60 and interpolation enabled, the elapsed-clock adapter requests at most 60 real frames, paired with intermediate pictures on a 120 Hz display. Turning interpolation off retains the existing real-120 target option. The counter distinguishes rendering submissions from actual displayed pictures. This is not Apple's depth/motion-based MetalFX frame interpolator, and neither sustained 120 fps nor improved latency has been measured on Air. Cuts/invalid motion keep current pixels; fast game HUD motion may still distort. The user tests gameplay after a backed-up same-bundle update. See [image optical-flow presentation](../../../docs/reference/rendering.md#experimental-image-optical-flow-presentation) for resource lifetime, pacing, fallback and tests. The shader chain and older-device compatibility work are unchanged.

### iOS Backbone input update

See [Backbone button letters and automatic touch visibility](../../../docs/reference/services.md#backbone-button-letters-and-automatic-touch-visibility). The host preserves touch layout and keyboard semantics; device button testing remains with the user.

Current M2 status (2026-10-29): minimum-16.1 build `20261029.2` was
installed with matching code/version and unchanged saved-state hashes. Both
secondary-source entries load, and the depth compiler errors no longer appear.
The user still reports a gray scene, so the rendering repair remains open;
the render-target failure and pass contents require further device diagnostics.
A10X remains uninstalled because its strict resource audit still rejects two
layered and eighteen sampler-limit paths.

### Compact binding replay repair (2026-10-29)

[Compact buffer bindings](../../../docs/reference/rendering.md#compact-buffer-bindings-lost-by-legacy-replay)
were silently discarded by this game's frozen legacy host. The production
recorder/replay regression passes 252 checks; the old host fails all 112 compact
binding checks. Minimum-16.1 build `20261029.5` includes the shared host repair
without changing the frozen shader chain. Packaging and device installation are
in progress; this does not establish a corrected picture or gameplay.

Delivery update: M2 `20261029.5` is now installed with exact executable/code-section and saved-state hashes verified. The user tests whether its gray scene is repaired. A10X remains uninstalled; its strict resource blockers are unchanged.

### iPad fullscreen HUD bounds (2026-10-29)

The user reports fullscreen UI outside the iPad picture. The shared
[narrow-screen HUD bounds repair](../../../docs/reference/rendering.md#fullscreen-hud-extends-past-a-narrow-device-canvas)
keeps the HUD inside the native canvas without stretching the camera or changing
input layout. Callback and geometry tests cover iPad ratios; updated device
builds and user evaluation are pending.

### Border correction and the atomic companion remain separate checks

The matching-chain rebuild rejects fragment `aa3ec7536a84d1e3` with
`Unproven image companion binding: border`: the upstream border rewrite added
a twin sampler and correction buffer to this shader's reflection. The legacy
renderer now binds these through its production argument encoder, including
constant sampler IDs and private argument-buffer layouts; see
[Border colours Metal has no sampler state for](../../../docs/reference/rendering.md#border-colours-metal-has-no-sampler-state-for).
Synthetic Metal GPU checks cover corrected pixels and replacing the sampler
while a submission retains its twin. The atomic-companion reflection validator
still rejects this unproven combination. This host support alone neither
completes the companion integration nor establishes A10X gameplay support.
