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

After the audit, three Samurai non-point sources were recovered from the
original 16.1 build. The installed library and reflection files matched the
backup by SHA-256 for every recovered source. The source files and their
manifest were verified after import. The subsequent launch did not produce
a fresh title log. Diagnostic overrides were restored and the original save
fingerprint matched.

The M2's 60.128 app still shows the legacy shelf. That release reused the
60.127 host executable and replaced only the Ocarina framework. The A10X
60.120 app already shows the wide banner and vertical artwork grid. The shared
library source for that layout compiles for an ARM64 iPadOS 16.1 deployment
target with availability checks. A follow-up confirmed that the M2 bundle
already contains the previously shipped artwork library. Its entry in the
executable's dynamic-library list was lost when the legacy host was reused.
The re-linked 60.129 candidate restores that one entry to the original M2
executable while preserving its 37 file-backed sections byte for byte.
The installed app's developer team signed the candidate for iPadOS 16.1.
The app-only delta reused the M2's existing installation cache. On 2026-11-22
the M2 registered 60.129 and opened the wide artwork banner and vertical game
grid, which matched the old iPad's 60.120 shelf. The installed app files,
run-time frameworks, game files and original save fingerprints were checked
before and after the update.

## Upstream integration and iPad crash fixes — 2026-11-22

The source now includes upstream `3dd1f7a6`. The legacy renderer keeps its
shader chain, and the modern chain is `aa98ae5541fa`. The merge combines
Ocarina's render-scale and GPU-only memory-pool changes with the fork's
window sizing and real-time clock support. The memory-pool and capture
fixtures ran on Mac. The iPad village-scene GPU fault still needs a device
retest. The disk-full shader cache tests verified removal of partial outputs
and preservation of an existing complete image.

- **Pokkén on A10X** — End texture blits before starting the render encoder,
  preserving the command-buffer fence between them.
- **Need for Speed Hot Pursuit on A10X** — Retain transient texture views
  through resource declaration to address the recorded `objc_retain` crash.

The classic GPU suite passed 299 checks, and the modified renderer compiled
for iOS 16.1. On the old iPad's existing 60.120 installation, scratch-save
tests reached the Need for Speed opening video after about 78 seconds and
the Pokkén title sequence after about 54 seconds without reproducing an
exit. The tests did not cover a race or battle, and the two new renderer
fixes still need an in-game test after installation. The original saves
matched their fingerprints after both tests.

On M2 60.129, Ocarina reached its opening movie with a scratch save. The
retest did not reach the village GPU-fault checkpoint. Crisis Core
reproduced an immediate abort before rendering: its main module has
`PATCH_OFF=-0x2000000`, and the signed execute mapping returned read-only
permissions on iPadOS 16.1. The experimental `DM_IOS_SIGNED_FRONT=1` legacy
layout places the front patch and code in one signed image and maps only the
data hole writable. A local iOS 16.1 link and code-signing check preserved the
exact original code, patch and writable-section bytes for all three modules.
This layout requires its matching loader and shader chain before delivery.

The later M2 60.130 test reproduced an allocation failure when replacing
pages inside the signed image. Build 60.132 changed the protection of the
reserved data hole in place. It passed that abort and ran through video
decode, but rendered black because its retained renderer looked for loose
shader files while the existing 3.15 GB library is an image. Build 60.133
restores the image reader without changing the image, the guest modules or
the iPad's saved data. Fourteen legacy vertex companions were verified
against the exact Metal libraries in that image. With the companions, the
title screen and new-game setup render on the M2. Ocarina's 60.132 retest
reached the village transition with MetalFX and a 0.5 render scale. The GPU
still faulted in a 128×128 pass using fragment shader `ccfff02a2829b620`.
The village is unverified.

The old iPad finally registered 60.131 after its installer had already
reported failure. Both runtime frameworks and the original game images and
saves passed read-back checks. The Need for Speed 60.120 race log showed
eleven missing shader keys and an omitted vertex draw. Those stages were
rebuilt at iPadOS 16.1 on the retained `a3a5cfdab59c` translation chain.
The final signed 60.131 package and its 697-entry map verified on-device.
Four additional vertex companions removed the observed variant warnings. A
[single fragment library update](../dm/games/010029B0118E8000/README.md#menu-text-on-older-apple-gpus-2026-11-22)
restored the text prompts and labels on the old iPad. The original game image
and saves passed read-back checks. The 3D car preview has a separate issue.

### A10X launch audit after 60.134 (2026-11-22)

All 21 installed game images had a corresponding signed framework in the
old iPad's 60.134 installation. The previously missing Mario Kart World
framework was the only framework added in this update. The existing game
images, save fingerprints and both Need for Speed patches verified afterward.

[Mario Kart World](../dm/games/0400C3F00006E000/README.md#a10x-launch-boundary-2026-11-22)
and Pokopia both load their signed modules, then fault at an authenticated
return in their Switch 2 SDKs. The Pokopia device log reports SIGILL at
`sdk+0x1520bc` and the instruction word is `d65f0fff`.
The other 20 locally inspected framework packages had no matches for those
return instructions in their guest text sections. This inventory verifies the
signed components and distinguishes the known Mario Kart fault. Individual
gameplay results for other titles still require a device run.

The in-place A10X updates lowered both instruction families. Mario Kart
World 60.137 and Pokopia 60.140 then reached Metal pool initialization.
Their respective 2.37 GiB and 3.42 GiB buffers exceeded the device's 1 GiB
single-buffer limit. Neither run reached its title screen. The cached
game images and original save fingerprints verified on both updates.

The classic renderer now registers oversized pools logically and creates
page-aligned zero-copy views only as a binding needs them. On the Mac, 100
classic Metal checks and 12 depth/stencil checks passed. The renderer also
compiled for iPadOS 16.1 with an A10 target. The Pokopia 60.144 device build
was relinked on the installed `a432daafc3d0` chain with all six A10X guest
sections unchanged. Installation completed after the device bridge timed
out, as confirmed by MobileInstallation and by reading back the new
framework. The original game image and save fingerprints matched.

60.144 passed that pool initialization on the A10X and rendered more than
600 frames. The system then moved the app out of the foreground. The
matching Jetsam report names `DmIOS` and gives `per-process-limit`. The
same termination recurred with 540p and handheld mode requested. The log
recorded the settings, though it did not confirm a game-side scene cap.
There was no second oversized-buffer assertion in either test.

60.146 tested file-backed guest memory on the same Pokopia chain. The
isolated run stayed in the foreground for more than two minutes and passed
3,500 frames, without the earlier Jetsam termination. The screen still
showed only black behind the controls. This mode was diagnostic and the
temporary override was removed. A second run without MetalFX remained
black after 5,100 frames. Its log names 60 missing per-slice shaders. The
original sources and libraries were recovered for those 60 keys, but all
failed the current exporter's proof rules for per-slice execution. No
unproven sources were installed. Mario Kart World on the same installed
bundle still used its own renderer and reproduced the 2.37 GiB buffer
registration failure. Naruto loaded the signed framework and entered the
guest. Its 2,078 MiB `SetHeapSize` request exceeded the retained 128 MiB
heap region. The guest then terminated during a write with `SIGBUS` at
`sdk+0x50a380`, before drawing. The installed images and original saves
verified after both isolated runs.

60.149 replaced only Mario Kart World's framework with an independent
renderer on the existing `b88c9e5f457c` shader chain. Its six signed guest
sections matched the previous build. This run registered the 2.37 GiB pool
and then hit `SIGILL` at `main+0x343b4a4`. That instruction was `LDSET` in
an old address-rewrite stub. The current rewriter lowers atomics in newly
generated stubs, but the archived image still contained 141 such instructions
across its three modules.

60.150 lowered those retained instructions and registered in place after
MobileInstallation finished its 501.52-second install. The isolated game
got through that instruction and opened its audio renderer. It then aborted
when Metal refused a separate 64.625 MiB no-copy pool that spanned multiple
guest VM regions. The same refusal occurred with file-backed memory disabled,
at the same reported Metal allocation of 4,041.73 MiB. Neither run reached
the title screen. Installed image identities and original save hashes
verified.

60.151 registered classic-renderer pools lazily on A10X and lowered the
window granule to 64 KiB. On the iPad the same Mario Kart World installation
got past the 64.625 MiB pool and submitted more than 212 frames. It stopped
when the first NVN2 mesh draw required a GPU with native mesh shaders
(Apple7 or Mac2). No race was verified on A10X. The game image and original
saves verified after the run. The classic renderer's 113 GPU checks passed
on the Mac.

The A10X shelf reported 14 launchable entries out of 24 on 60.146. The
other ten failed framework preflight. Nine declared a different shader
chain from the shared runtime, and the tenth also lacked a module table
matching its installed resources. Shelf availability does not exercise
the game or guarantee a successful launch.

### M2 Crisis Core first battle (2026-11-22)

On 60.133, the title, new-game setup and opening movie render. The first
battle loads additional pipelines and reaches the guest's fatal allocation
path. The abort stack passes through `main+0xdf7da8`; its enclosing code
references the Unreal out-of-memory message. Reserving 8 GiB of guest alias
address space and testing a 256 MiB texture-streaming pool still produced
the abort. Both settings were restored afterward. Sixty-five non-point
shader companions matched the existing on-device libraries and were installed
without replacing the shader image. A fresh run with all 65 installed
reproduced the same allocation abort at the first battle. The allocator
retries growing its page pool before reaching `main+0xdf7da8`. The 60.141
trace reproduced the same guest abort. The SDK page calls sampled before
it returned success, with roughly 11.5 GiB of process memory still
available.

The 60.143 device build gave Crisis Core 512 MiB more in its application
pool and reused the existing shaders. With an 8 GiB alias reservation for
the diagnostic run, it passed the allocation abort and entered the first
battle tutorial. The HUD and prompts continued to draw, but the 3D scene
behind them remained black. The test used an isolated save and restored the
previous settings afterward.

### M2 Ocarina village transition on 60.133 (2026-11-22)

The same isolated save reproduced the Metal GPU page fault at the village
transition with MetalFX and a 0.5 render scale. The binding capture for
fragment `ccfff02a2829b620` shows a 4×4 2D texture at register 8, while the
shader expects a 3D texture. The legacy adapter logged the incompatibility
and still bound the 2D texture. The faulty draw also uses a nonzero base
vertex. The capture identifies what to isolate in the next replay. The
village has yet to render successfully on this iPad.


### M2 Ocarina same-scene retest on 60.139 (2026-11-22)

The earlier 60.136 candidate used an older runtime that opened the wrong
shader directory and lacked the audio-device service. It was replaced
in place. The 60.139 build reused the six signed guest sections and the
installed `70fa6008c58d` shader chain. The build included a depth-one texture adapter for the same village load. The replay reached the same render pass, then
reported Metal command-buffer error 8. The final samples recorded about
14 GiB of GPU allocations and over 23,000 deferred releases. The village
still did not render. The original save fingerprints matched the baseline.

60.142 forced earlier submission boundaries and waited for deferred
releases between render passes. The retry still returned Metal error 8 at
the village transition. GPU allocation reached 14,791 MiB and one pass
accumulated over 85,000 pending releases before the boundary. The
experimental renderer is retained as a local candidate.

The same 60.143 runtime reproduced the failure in handheld mode with a 0.5
render scale and MetalFX. It played the opening, then returned Metal error 8
while streaming the village. The final sample reported 14,014 MiB of GPU
allocations. The diagnostic overrides were removed after the run.

60.145 also returned Metal error 8 in the same village load with an
experimental in-pass retirement option. Metal's allocation counter went
higher in that run. The option was used with an isolated save and was
removed afterward.

60.147 tested 12 GiB of file-backed guest memory in the same isolated
village transition. The render log reached Metal error 3, a GPU address
fault in pass `p283 128x128 ccfff02a d130`, after allocating 8,548 MiB of
GPU resources. It did not reach playable control. The original save
fingerprints matched after the diagnostic override was removed.

60.148 also backported strong ownership for transient Metal texture views
to the pinned renderer, preserving all six signed guest sections. The same
village transition left the game in the background before showing a usable
scene. Metal's allocation counter reached 19,579 MiB against more than
21,000 resident root textures. No matching system crash report was captured
in this run. The original save fingerprints still match.

### M2 Pokopia cold launch on 60.143 (2026-11-22)

The installed independent runtime loaded from the game shelf with an
isolated save and reached the Chinese language-selection screen. The last
300-frame sample measured 59.9 frames per second and a 16.99 ms median frame
time. The log confirmed a 960×540 cap on the 3D scene's dynamic lists. The
present path still fed the 1920×1080 composite to MetalFX. This run covered
startup and the language menu. The first playable map, face editor and
long-run audio were outside its scope.

A 60.147 continuation reached the rendered Ditto wake-up prompt with no
application exit and no audio underruns in the captured intervals. It used
a copy of the local save, with cloud sync off. The original save hashes
matched. This run ended before the face editor and first playable map.
The archived face-fix libraries, reflection files, and tables still match
all 87 device-side hashes on 60.148.

On 60.148, an isolated run reached the face editor with the 960×540 scene
cap and spatial MetalFX enabled. It rendered the facial features, but the
preview still showed black clothing and arms. The iPad rejected two
render pipelines with an internal compiler error: `d9baed7ec28d3f7e_b` /
`45afc24df093ab72_b` and `9b42a7d8889b9cd8_b` / `8743dd823fc8e863_b`.
Both source pairs compiled in a local M4 pipeline probe. The relationship
between the rejected pipelines and the dark preview is unconfirmed.
Removing the unused point-size output from both triangle variants did not
clear either error on the M2. That diagnostic ended at the character
confirmation screen. The original companion sources and their manifest
were restored and the save hashes matched.
