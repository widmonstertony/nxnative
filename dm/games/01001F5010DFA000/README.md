# Pokemon Legends: Arceus

Current preparation: owned update 1.1.1, main build `aee8f150dda1b5a838806e1a5ea6827a`. The full profile and shader tables are still provisional in the external game work directory. Gameplay and device validation remain open.

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
