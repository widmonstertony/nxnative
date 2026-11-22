# iOS 16 / iOS 17 compatibility status

## Published source and compatibility branch

[`ios16-ios17-compat`](https://github.com/widmonstertony/nxnative/tree/ios16-ios17-compat)
is the fork's compatibility branch for ongoing device work. It was renamed
from `ios16-pokemon-za-port` to describe its shared scope: all games, iOS 16.1/17,
legacy GPUs and the optional modern Metal 4 target. Published fixes are
also synchronized to the fork's `main`. Historical snapshots are not
alternative supported releases. The [README game table](../README.md#tonton-gamebox-game-fixes-and-verification)
has the current device evidence.
Start with the [build and installation guide](ios16-ios17.md).

## Upstream integration and resource compatibility

Upstream `372a8d8a0404bd0d0bdc9928a674b0d9c0104b5e` was fetched and fully merged
on 2026-11-01, including the previous full integration through `8ea27784`.
The merged upstream changes include the bounded Need for Speed Bundle 2 reader
and independent mmap/mprotect failure fixtures; the fork retains its alias
exposure checks.
This is a merge, not a rebase or a claim that merely fetching updated the fork.
Use isolated, pinned upstream builds for new releases. Do not update a deployed
game's shader chain merely because the fork's source branches are synchronized.

The full integration preserves signed executable mappings and per-game
frameworks, legacy shader reflection/atomic companions, input semantics,
Chinese settings and exact-build observation IDs. Existing frozen builds and
installed resources retain their original identities. The merged shader chain
is `aefa4b269cfc`: **complete matching resources must be rebuilt per game before
shipping a new host from this source**. Old `ea90` resources cannot be relabelled.
The source merge itself did not replace installed applications.

## Build targets

| Setting | Deployment minimum | Capability boundary |
|---|---|---|
| `DM_IOS_RENDERER=legacy` | iOS/iPadOS 16.1 | Traditional Metal; strict per-game resource checks |
| `DM_LEGACY_TARGET=a10x` | Inherits legacy minimum | Older-GPU companions required; unsupported layered/sampler/image operations block delivery |
| `DM_LEGACY_TARGET=m2` | Inherits legacy minimum | Tested M2 iPad capability selection; not an A10X fallback |
| `DM_IOS_RENDERER=metal4` | iOS/iPadOS 26.0 | Modern backend on compatible hardware; experimental optical-flow interpolation |

Source for other platforms is retained. Later Switch 2 phone and iPad results
are recorded per game in the README; upstream Mac results are not device proof.

## Device evidence and open work — 2026-11-01

The following are user/device observations from this fork, not a blanket list
of supported titles. Installation, shader compilation and successful gameplay
are recorded separately. Older [renderer checkpoints](ios16-compatibility.md)
remain available as historical evidence.

| Game / target | Confirmed evidence | Remaining limits |
|---|---|---|
| Need for Speed / M2 and Air | User confirms gameplay after missing runtime shader resources were delivered | Intermittent scenery artifacts and audio stalls reported; no complete performance/stability pass |
| Pokken / M2 | User confirms picture restored after matching runtime stages were supplied | Broader scenes, A10X and long-run stability not certified |
| Animal Crossing / M2 | User confirms playable | Air executable-image repair installed; post-update gameplay unconfirmed |
| Witcher 3 / M2, iPadOS 16.1 | User now confirms playable after full SDK, shader companion, binding and installed entitlement repairs | 30 FPS and remaining picture anomalies reported; frame timing and rendering still under investigation |
| Arceus / Air | User confirms third-person picture restored in the unified app | Reproducible task-end null-object crash remains open; diagnostic tracing is not a root-cause fix |
| Arceus / A10X, iPadOS 17.7 | Not installed | Two layered vertex and eighteen sampler-limit paths fail the resource audit |
| Z-A / iPhone/iPad | Multiple device packages installed with code/table/save readback | Do not infer all scenes or older-GPU combinations are stable from installation |
| Tsukihime / M2 and Air | Matching resources audited and hosts compiled | Complete resource delivery and gameplay not verified |
| Other newly built titles | Several shader builds completed | Per-device resource audit, signed host/table binding, delivery and user testing still required |

Full-game performance and correctness need the actual game/version/device.
A successful source build, IPA, cover, directory or FPS counter is not a
playability result. Broad frame-rate removal is still being validated against
each game's simulation clock; no stable 120 FPS is promised.

## Non-Switch runtimes in TonTon

GTA uses a separate native engine, not the Nintendo conversion pipeline.
The current Dawn integration requires iOS 17 or newer; an iOS 16 renderer port
is still open. Air engine packaging does not establish complete data delivery.

Full Red Alert 2 and Yuri's Revenge are being integrated through a separate
static x86 recompilation/Win32 compatibility route. Both native engine
frameworks compile for iOS 16.1. M2 non-game probes verify memory, fonts,
storage and framework loading without calling the game entry. SDL lifecycle,
return-to-library, input, suspend/resume and full campaigns still need work.
The existing browser/Wine route can start but has severe performance problems;
it is not presented as the finished native solution.

## Validation scope

The full upstream merge passed 110 tool/iOS Python test files (1,020 cases),
37 graphics Python files (189 cases), the production host suite and 284 real
legacy GPU checks. Optional dependency skips remain. Five-profile unified-host
Xcode builds passed for both deployment targets, iOS 16.1 and modern Metal 4.
Those are unsigned synthetic fixtures without commercial assets; they were not
installed or presented as working game releases. The five-game regression
harness was attempted but blocked by missing local game builds, so no complete
five-game gameplay result is claimed.

Screen XBAY layout and Backbone printed-letter semantics are preserved.
Keyboard J=A / K=B / U=X / I=Y and Return=A / Backspace=B are retained; hardware
keyboard/controller presence hides touch controls. Chinese labels preserve
underlying configuration values. Frame generation is experimental image optical
flow, not native MetalFX frame interpolation. Game assets, extracted code,
shader libraries, keys, saves and signing credentials are not distributed here.

## M2 original-chain recovery — 2026-11-17

M2 build 60.128 targets iPadOS 16.1. The device reconnect changed its network
address; it did not justify resending existing ROMs. The refreshed shelf
reports 26 of 28 entries ready. This is a resource preflight, not a gameplay
pass. Emiya and Arceus remain blocked by incompatible frameworks.

- **Fate/Samurai Remnant:** original chain `a3a5cfdab59c`, profile inputs
  `27b06696f9dc`. The continuation's 10,391 queued keys are complete; this
  excludes historically completed libraries that are not physically recovered.
  The installed Half2 adapter and a hash-bound source companion removed the
  observed vertex-input/source failures. Fourteen actual scene-requested groups
  were built with the frozen chain for 16.1 and installed as 63 small files.
  The retest reached the first assassin battle with the player, enemies and
  terrain visible at about 30 FPS. A prior isolated run also checked movement
  and an attack advancing the stance tutorial. Full-log review found five
  additional cutscene keys: these were compiled and installed as 19 small
  files, with SHA-256 readback; the subsequent visual retest is pending.
  Buffer-texture alignment, texture-type and integer-vertex warnings remain.
- **Tears of the Kingdom:** same original chain, profile inputs
  `ed3afea18bbf`. Its 8,306 queued continuation keys are complete. The 60.127
  isolated run reached the underground stairs, showing Link, Zelda and the
  environment; controller input moved Link. Later scenes and sustained frame
  rate have not been certified.
- **Ocarina of Time:** the v131072 replacement reused the installed ROM, with
  nine resource changes and an index update. Its first controllable village
  scene still causes a GPU address fault on 60.128. Shader-validation and
  fragment-isolation attempts did not produce a root-cause fix. See the
  [device finding](../dm/games/0400486024DEC000/README.md#fork-m2-ipados-161-checkpoint-2026-11-17).

Samurai and Tears retain conservative bindings generated from their exact
original-profile maps: every C1 bank is exclusive/full and CB extents are not
narrowed. Their identity stamps explicitly describe partial libraries. No
modern-chain table or library was relabelled. All completed isolated runs
used scratch saves with cloud sync disabled; original save fingerprints
matched after cleanup. New scene-only deltas do not reset the primary build
checkpoints. The Mac build page records installation and scene tests separately.

## iPad launch audit — 2026-11-21

The installed M2 build 60.128 reports 26 of 28 entries ready. Emiya and
Arceus are blocked at framework preflight: their signed manifests identify
chains `11f9fb19e60d` and `ea90ed511690`, while the shared renderer expects
`a3a5cfdab59c`. Samurai and another ready title report missing or mismatched
non-point sources. The first controllable Ocarina scene remains open.

The A10X build 60.120 reports 14 of 24 entries ready. Its retained logs
show distinct failures: Mario Kart World lacks its signed title framework
and the embedded fallback aborts on missing `__DM0LmainW`. Naruto requests
a `0x81e00000` heap against a `0x8000000` cap. Need for Speed Hot Pursuit
crashes in `objc_retain` after rendering a scene. Pokken's command-buffer
assertion has an [encoder-ordering candidate](../dm/games/0100B3F000BE2000/README.md#classic-metal-encoder-ordering-2026-11-21).
Each requires its own device check. The audit read the current shelf and
the last retained game logs. It did not launch games or change saves.
