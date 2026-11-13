# TonTon upstream optimization audit

Audited through November 13, 2026 (Pacific) against upstream [`df9ca262`](https://github.com/seedds/nxnative/commit/df9ca26217962a8463c91458d37a1a07be138256). This is a bounded source snapshot, not a claim about unreviewed open pull requests or future upstream changes.

## Integration and deployment are separate

The publication merge includes all 19 upstream commits missing from the fork at the start of this audit and five subsequent commits through the snapshot above, including texture-pool views, virtual-pool mappings, texture reads, tessellation, pipeline prediction, HID vibration sessions and save-fetch/conflict safety. Existing TonTon CloudKit dispatch, collision-safe temporary names, per-game graphics settings and the coherent classic backend are retained.

The modern chain is regenerated for the merged tool sources. It is for new builds only. Running shader jobs, old per-game hosts, manifests and their exact resource stamps remain pinned; no old library is relabelled or automatically rebuilt. New source integration does not install those changes into a frozen iPad engine.

## Compatibility work by mechanism

| Upstream improvement | Source status | Device boundary |
| --- | --- | --- |
| [Frame-step stability](https://github.com/seedds/nxnative/commit/1e3fd031) and [MKW 1.8.0 fingerprint](https://github.com/seedds/nxnative/commit/6815810d) | Present in modern source | Classic CPU controller backported with the loaded `STEP_MAX` contract; both 86-case timing suites pass. Device deployment is pending. Do not apply 1.8.0 addresses to the installed v0 build. |
| [Dynamic-resolution heap recycling](https://github.com/seedds/nxnative/commit/707cac95) | Present in modern source | Classic private ownership/residency records differ; requires a measured backport, not copying the modern registry into it. |
| [Conditional-render evaluation](https://github.com/seedds/nxnative/commit/a2514d7d) | Present in modern source | Keep the deployed MKW black-scenery repair until an equivalent classic path passes a race. |
| [Compute grids larger than 384 threads](https://github.com/seedds/nxnative/commit/529cf68c) | Present in modern translator | Shader-chain change: use only matching rebuilt libraries. Existing jobs continue on their original chain. |
| [Cube/layered pool views](https://github.com/seedds/nxnative/commit/38521863), [virtual pools](https://github.com/seedds/nxnative/commit/9ae18913), [readback ordering](https://github.com/seedds/nxnative/commit/a9005a51) | Integrated in publication source | Modern GPU tests cover the merge; classic implementations need separate review. |
| [Sparse texture binding notes](https://github.com/seedds/nxnative/commit/df9ca262) | Integrated in modern source; mappings invalidate overlapping textures without rebuilding every table on unrelated serial changes. | Relevant to sparse-terrain games including MKW; old renderer requires an ownership-aware backport and device measurement. |
| [Dynamic-resolution DLSS input ranges](https://github.com/seedds/nxnative/commit/0534d04f) | Integrated in the modern MetalFX path; scalers follow texture identity and accept content within the advertised size range. | Applies where a title actually calls this DLSS path; does not automatically reduce every game's scene resolution or add temporal upscaling to classic hosts. |
| [External presentation texture lifetime](https://github.com/seedds/nxnative/commit/d77edb18) | Integrated for GL/Vulkan; classic registry gains its own release bridge after GPU readers complete. | Prevents swapchain/window replacements retaining old images; source validation is separate from mobile installation. |
| [Domain-to-geometry capture](https://github.com/seedds/nxnative/commit/8472ffbc) and [geometry bit-mask handling](https://github.com/seedds/nxnative/commit/529c5faa) | Integrated in modern host/translator with a regenerated chain. | New matching builds only; no shader relabelling or restart of existing jobs. |
| [GPU compiler bit-mask encoding](https://github.com/seedds/nxnative/commit/3d687bf6) | Integrated in modern translator | New chain only; no blanket old-game rebuild. |
| [Save readability](https://github.com/seedds/nxnative/commit/aacb4411), [late fetch isolation](https://github.com/seedds/nxnative/commit/9ef08c89), [conflict choice](https://github.com/seedds/nxnative/commit/3b102271) | Integrated with TonTon private CloudKit transport retained | Local synthetic save tests are separate from live iPhone/iPad/Mac/Apple TV exchange; that four-device test remains open. |

## Every installed title, plus the new Fate request

“No title-specific upstream profile” means no directory for this title ID in the audited upstream tree. It does **not** mean the shared engine has no applicable improvements, nor does it imply that this fork has validated every upstream optimization on that title. Readiness is not a gameplay pass.

| Game / title ID | Upstream coverage and fork work | Actual validation / remaining work |
| --- | --- | --- |
| [Mario Kart World](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/0400C3F00006E000)<br>`0400C3F00006E000` | Frame pacing, recycled dynamic-resolution textures, sparse terrain and conditional rendering. | M2 60.99: full scene/HUD in an actual 50cc race; scene color/depth 960×540, MetalFX active; last measured window 48 FPS at thermal level 2. Earlier 60.97/98 candidates rejected. Air 60.75 retains tier override; the 540p guest candidate is not installed on Air. The additional classic pacing backport passes CPU tests but is not yet deployed. |
| [Zelda: Ocarina of Time](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/0400486024DEC000)<br>`0400486024DEC000` | Asynchronous movie decoding, dirty-page tracking, relaxed draw barriers, border specialization and pipeline prediction. | Air player reached gameplay but later reported crashes; M2 forest/GPU-memory and scene-transition work remains open. Upstream Mac performance does not certify these devices. |
| [Pokémon Pokopia](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/0400A3A01EE4C000)<br>`0400A3A01EE4C000` | Generic NVN memory, shader/pipeline and queue improvements; TonTon adds measured scene caps and audio/QoS fixes. | Air 60.74 player reported smooth gameplay and normal sound. M2 60.94 first-map tutorial: 55.4–60 FPS; cold pipelines and character-preview defects remain open. |
| [Pokémon Legends: Z-A](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/0100F43008C44000)<br>`0100F43008C44000` | Trinity rendezvous ordering, offline pipeline archive handling, generic conditional rendering. | M2 60.82 restored the player model in the same hotel save. City performance and uncapped simulation timing need A/B verification. |
| [Pokémon Violet](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/01008F6008C5E000)<br>`01008F6008C5E000` | Trinity rendezvous ordering and offline Bluetooth LE services; shared NVN/texture improvements. | M2 runtime components read back; post-load rendering and simulation speed remain open. Air performance requires player retest. |
| [Zelda: Tears of the Kingdom](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/0100F2C0115B6000)<br>`0100F2C0115B6000` | Conditional rendering and shader/texture/barrier fixes in its upstream profile and the common renderer. | Air player confirmed entry, overlay disabled and reduced stutter. Matching M2 components continue on the frozen chain; no sustained 60 FPS claim. |
| [Animal Crossing: New Horizons](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/01006F8002326000)<br>`01006F8002326000` | Conditional rendering and common NVN/host changes. | Air player confirmed launch; eight missing M2 components installed/read back. M2 gameplay on that build remains unverified. |
| [Pokémon Legends: Arceus](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/01001F5010DFA000)<br>`01001F5010DFA000` | The upstream title profile plus common NVN/host changes. | Air player confirmed launch and restored aiming controls. M2 exact framework/chain binding remains open; existing data is retained. |
| [Need for Speed Hot Pursuit Remastered](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/010029B0118E8000)<br>`010029B0118E8000` | Bounded Bundle 2 reader and common runtime changes; TonTon input, texture and audio repairs. | Device gameplay confirmed; no long-race performance guarantee. |
| [NieR:Automata](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/0100B8E016F76000)<br>`0100B8E016F76000` | The upstream title profile and common NVN/shader changes. | Old iPad original data present; A10X runtime incomplete. No old-iPad gameplay pass. |
| [STEINS;GATE RE:BOOT](https://github.com/seedds/nxnative/tree/df9ca26217962a8463c91458d37a1a07be138256/dm/games/01008BC024FDE000)<br>`01008BC024FDE000` | The upstream title profile and common runtime changes. | M2 readiness record present. This audit did not perform a story/gameplay test. |
| Fate/Samurai Remnant<br>`0100B0701AA78000` | No title-specific upstream profile at this snapshot; common NVN/host changes must be assessed against its frozen shader chain. | Air: 77,671 shaders and final image/tables read back, can open; user gameplay pending. M2 missing shaders continue independently; no body re-upload. |
| Fate/EXTELLA LINK<br>`010051400B17A000` | No title-specific upstream profile. Air uses NX2Apple `d0adbda8` / engine base `0c078130` plus its 44-patch queue and the local depth/stencil linear-view fix. M2 retains the coherent `a3a5cfdab59c` classic chain. | 1.0.2 + 58 DLC verified/extracted; 1,488 discovered shader stages compiled for each device lineage. Air 60.78 installed and launch-ready; 27 existing directories and original body identities retained. M2 original body SHA-256 verified, compatible host signed; component delivery/install pending. Mac first-frame crash fixed; mobile combat and complete shader coverage remain open. |
| Crisis Core: Final Fantasy VII Reunion<br>`0100D09016C6A000` | No title-specific upstream profile; common NVN/shader/host fixes need compatibility verification. | Air passed a previously crashing scene, with stutter. M2 component repair installed/read back; latest gameplay unverified. |
| Naruto Shippuden: Ultimate Ninja Storm 4<br>`010020100CF62000` | No title-specific upstream profile. Generic GL/NVN interop fixes and TonTon battle/memory repairs apply through its retained engine. | Air reached battle on one build; black characters and later battle-entry crashes remain open. |
| The Witcher 3<br>`0100E67012924000` | No title-specific upstream profile. TonTon has REDengine extraction and raw sampler/unsigned fragment fixes. | Air player confirmed title/game entry. M2 character materials still incorrect; no visual pass. |
| Everyday Today’s MENU for EMIYA Family<br>`01005E6010114000` | No title-specific upstream profile; retained engine and DLC/resource work are TonTon-specific. | Air player selected Simplified Chinese in the game and confirmed it. M2 matching runtime components remain incomplete. |
| Pokkén Tournament DX<br>`0100B3F000BE2000` | No title-specific upstream profile; generic captured-shader and legacy renderer fixes. | Old iPad training HUD reached, fighters missing; not a gameplay pass. |
| Fate/stay night REMASTERED<br>`010023301E41C000` | No title-specific upstream profile; TonTon GL framebuffer and sizing repairs. | Air player confirmed correct title-screen size; full story coverage not tested. |
| Fate/hollow ataraxia REMASTERED<br>`010070E022546000` | No title-specific upstream profile; TonTon GL framebuffer aliases and story-init repair. | Air player confirmed Start enters the story without the reported crash. |
| Witch on the Holy Night<br>`0100751018DBA000` | No title-specific upstream profile; TonTon retained-engine startup fix. | Air player confirmed title/game entry; no full-route test. |
| Tsukihime -A piece of blue glass moon-<br>`010057A01E4D4000` | No title-specific upstream profile; retained GL engine and startup diagnostics. | Earlier M2 pink startup later recovered according to the player; no sustained-rendering claim. |
| Knowledge, or Know Lady<br>`0100FFE0241AC000` | No title-specific upstream profile; TonTon Unity asynchronous prefab-loading fix. | M2 title menu measured, Air player confirmed title/video entry after Loading repair. |
| Ladies, Don’t Tempt My Immortality<br>`01003CC0253DE000` | No title-specific upstream profile; generic retained Unity/runtime changes. | M2 readiness record present; this audit did not test a story scene. |
| Grand Theft Auto V<br>`gta5` | Uses the separate native GTA engine, not nxnative upstream shader optimizations. | Air gameplay/mode picker confirmed. M2 embedded-engine experience still requires comparison; preserve mode picker and saves. |
| Command & Conquer: Red Alert 2<br>`redalert2` | Separate native engine; nxnative renderer optimizations do not apply. TonTon touch controls are maintained separately. | Player confirmed playable; touch patch compiled/pushed. Updated old-iPad retail-resource restoration and test remain open. |
| Command & Conquer: Yuri’s Revenge<br>`yurisrevenge` | Separate native engine; nxnative renderer optimizations do not apply. | Player confirmed playable; same touch and device-restoration limits as Red Alert 2. |

## Evidence and scope

M2 MKW 60.99 pass dump F32060 shows 960×540 color and depth scene attachments and a complete scene viewport. The captured race picture retains the scene and HUD. The last sampled window is 48 FPS at thermal level 2; this is a visual/resolution pass, **not** a 60 FPS pass. The test used an isolated save and disabled save synchronization; original saves were SHA-256 unchanged.

Fate/EXTELLA LINK’s new engine first aborted in `linear_fit` when Metal was asked for a depth/stencil linear-texture alignment. The fix routes these formats through normal depth/stencil textures. The 73-case linear texture test passes with Metal validation; a 45-second Mac run reaches 1,200 frames without that assertion. This is Mac startup evidence, not combat or full shader coverage. Air installation and launch-readiness are separately recorded below.

Builds and game-derived data remain outside Git. This document contains no original game files, keys or save contents.

## Classic pacing backport (source validated; not deployed)

The retained CPU-only controller now uses upstream bounded-average lateness, the cheapest of the last three costs, probe clock-ramp recovery and the loaded stub's largest step. It keeps classic 60 Hz units and all shader, recorder and texture layouts unchanged. Both modern and classic selections pass the same 86 simulated timing checks, including transient pipeline hitches, sustained overload, maximum step, thermal/movie recovery and real-time game-speed accounting. Existing MKW device performance above predates this backport. The linked classic recorder/backend GPU suite also passes all 296 checks after a rebuild; test dependencies now include classic headers and implementation includes.

## Publication checks

The merged source passes 59 focused Python tests (two optional Metal/translator cases skipped), the six-suite modern/classic GPU selection (linear readback, pool type bridges in both encoding modes, first virtual mapping, render-target recycling on/off, classic pipelines, frame-step controller), 123 save transport checks and 209 save metadata/recovery checks. The fork keeps its `mkstemp` reservation; the late-fetch test verifies that the abandoned worker removes only its own reserved file. The source merge is not a five-game mobile regression pass. Existing device evidence above remains authoritative.

The full five-game Mac harness was not run for this merge: the retained five-game archive has shader fixtures and reports but no longer has the `tools/dmhost`, rewritten modules and complete build layout required by `regress.py`. Those historic reports are not reused as a new pass. The C compile database was generated; `clang-tidy` is unavailable on this Mac, so no tidy pass is claimed.

## November 13 follow-up

The five newly published upstream commits are included through `df9ca262`.
The classic Vulkan bridge must not call modern ownership functions: it waits
for its own present tickets and in-flight readers, then removes the external
texture from its private serial registry and residency records, without
parking it on a deferred queue that Vulkan never drains. No shader ABI changes.
The current device builds are unchanged by this source publication.

Follow-up checks: 64 focused Python cases pass (eight optional GPU/translator
cases skipped); explicit GPU routes pass sparse-pool cache (26 checks), modern
and classic swapchain recreation (140 recreations / 420 retired images each),
MetalFX dynamic-resolution output (21 checks with encoding off and 21 on), and
the three tessellation fixture cases. These synthetic checks do not replace the
missing five-game/device gameplay regression described above.

## iOS shell functions (November 13)

NX2Apple was checked at [`d0adbda8`](https://github.com/LNPANDY/NX2Apple/commit/d0adbda8f505a137ef254e4b7e7e58744244255c), with engine base `0c078130f6db7d0d32c1dc28146feaf97713f008` and its 44-patch queue. This modern engine is independent of the running classic shader jobs. Later seedds commits through `fb510cce` were inspected, not claimed as integrated by this lifecycle change.

| Requested function | Current implementation / deployment | Remaining validation |
| --- | --- | --- |
| Quit game without closing Gamebox | Optional image-owned lifecycle ABI; complete host teardown precedes writable-segment restoration and returning the original library window. Air 60.78 new EXTELLA LINK engine includes it. | Device quit, relaunch and switching to an old game. Classic/shared engines still need their own complete teardown implementation; a library update alone cannot enable it. |
| Home held for two seconds; in-game quit menu | Upstream modern engine carries its controller prompt and quit menu. TonTon glue uses a framework-local return handler and Chinese return-to-library wording. | Real controller hold/confirm on the new engine. Do not resolve a global return callback for an older engine lacking teardown. |
| Touch layout, button toggles, controller remapping and unobtrusive menu | New engine includes NX2Apple pad geometry, mapped physical input and idle menu behavior. The TonTon in-game menu exposes offered layouts and toggles. Existing Air MCON fix is retained. | Full visual layout editor/global remapping shell integration and checks across older engines are still open. |
| One shell, independently versioned engines | Stable v1 manifest/identity/chain gates retained; lifecycle is an optional capability, not a shader ABI bump. New Air Fate uses `a5e7fb6e4fa4`; M2 Fate uses `a3a5cfdab59c`. | New and old engine switching on-device; never relabel libraries or rebuild already finished games for a shell update. |
| Single-file shader resources | Each new Fate shader set is delivered as a mapped image with matching tables and stamp. | 1,488 discovered stages are not evidence of complete game coverage. |
| File-backed virtual memory | Modern independent engine retains its upstream file-mapping path. | Does not remove iOS physical-memory limits or establish a Mario Kart race pass. |
| Automatic iCloud saves | TonTon private CloudKit transport remains in the fork. Quit flushes before teardown. | Live save exchange among iPhone, iPad, Mac and Apple TV remains unverified. No original saves were changed for these delivery checks. |
| Cover Flow / console shell / iPhone Duo | Upstream feature identified. | Full TonTon UI integration is not yet deployed; do not label it complete. |

M2 60.101 reached a real Mario Bros. Circuit 50cc race with an isolated save, 960x540 scene attachments and MetalFX. The final composite remains 1920x1080 before scaling to 2732x1536; this is not a direct 540p MetalFX input claim. Sampled race rate is 48–49 FPS at thermal state 0. Disabling the learned warm manifest avoided the earlier GPU address fault in this control run; the underlying warm-pipeline failure is still open, and this diagnostic setting is not a completed optimization.

Lifecycle checks: seven focused Python tests pass, including a real Mach-O static-state restoration exercise, image/chain/capability ownership and profile selection/release behavior. Modern and classic GPU depth tests each pass 12 checks under Metal validation. These tests do not replace on-device quit/relaunch or gameplay. The source reach is limited to explicitly opted-in independent engines and depth/stencil linear views, so these focused checks were used instead of claiming the unavailable five-game harness.
