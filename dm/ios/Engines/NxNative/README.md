# Patches for pinned iOS engine lineages

The signed iPhone and iPad engines can use different base sources and shader
chains. Apply these patches to the source identified here. Keep the engine's
existing generated shader resources; a launcher update should not change their
chain or replace the game's saved data.

## Mario Kart World: file-backed texture uploads (Air 60.59)

The [mkw-neo upload gate](https://github.com/MenAtCafe/mkw-neo/commit/00d76d51560d)
avoids wiring a large file-backed guest pool when only a packaged texture in
that pool needs an upload. The Air variant checks the live guest reservation
and stages only uploads that would otherwise wire at least 64 MiB and eight
times the texture's size. Wrapped pools, small pools, non-packaged textures
and other titles retain the original path. This retains the 60.56 compute
archives for both Mario Kart World and Pokémon Legends: Z-A.

Apply `mkw-air-file-backed-texture-uploads.patch` to the Air 60.56 renderer
with its chunked guest-file host (865cc35-derived), not to the shared engine
whose host lacks file-backed guest memory. Source SHA-256 before patching:

- `dm/host/hle_svc.c`: `51f35785f230a7c3727f9f4ab7e4b839cd5633ff6c368e9a1b80a2e6dca50044`
- `dm/gfx/nvn/nvn_mtl.m`: `2e311373518793777787f96d233c748a8fbb0fca8a17d3bc8d68e172d02ae40c`

## Tears of the Kingdom: 16-bit depth clears on iPadOS 16.1

The old renderer cleared a 16-bit depth buffer into a different quantization
bin from a fragment writing the same NVN depth. A later equality test then
dropped cave walls and stairs in large rectangular areas. Both legacy Metal
clear paths now use the existing D16 conversion and retain normal depth
testing. The pinned iOS 16/17 builder also applies the fix to its classic
renderer without changing its shader chain.

On M2 (iPadOS 16.1), the isolated 60.122 comparison recovered the walls and
stairs beneath Hyrule Castle; they still rendered after moving Link. The
matching test build also retained the previous experimental BC4 workaround.
The cave check does not establish full shader coverage or other areas'
rendering. The GPU fixture verified both clear paths against fragment writes
at 1,042 depths with the modern and compatibility renderers.

## Ocarina of Time: opening movie on Metal 3 (M2 60.60)

The opening video's decode kernel writes a private RGBA8 target which the
legacy path created without shader-write usage. Promote the exact decoder
output before encoding its dispatch. Scale that decoded frame into the
original movie destination and omit the matched 13 reconstruction dispatches
only when the replacement render pass was successfully encoded. Other
sequences retain the ordinary path. The independent engine keeps shader chain
`70fa6008c58d`; all six guest sections and its sealed shader companions are
byte-identical.

The installed M2 build was checked against the same opening. The opening
video is now visible; GPU median over the first reported 300 frames was
1.93 ms versus 76.50 ms on the preceding build. This does not establish 3D
gameplay performance or completeness.

Apply `ocarina-m2-opening-movie.patch` to the pinned 60.57 Ocarina Metal 3
renderer. Source SHA-256 before patching:

- `dm/gfx/nvn/nvn_mtl_legacy.inc`: `4a5bf9dfb5e825d1ac9e1122c7a53fdd841346a0d47f88ae54100accafcc0c4a`

## Ocarina of Time: offline play-report service (M2 60.61)

After the opening video reached end of stream, the game opened `prepo:u`
directly and aborted with `0xe15` when the service was absent. Admit that name
to the existing in-process HIPC responder only in the Ocarina framework.
The responder does not send telemetry or touch saved data. The Metal 3
renderer, sealed shader chain and all six guest sections stay unchanged.

Apply `ocarina-m2-offline-play-report.patch` to the pinned Ocarina 60.60
engine's `dm/host/hle_sf.c`, whose SHA-256 is
`4e37968a18e54f1a00b4bb516665aaa6973cb96cb8d14f83e608b953cd99b6f4`. Relink just the Ocarina framework;
the shared iOS engine does not use this patch.

## Ocarina of Time: native frame pacing (M2 60.90 candidate)

On the M2, the frozen Ocarina build could inherit the library's uncapped
120 Hz presentation. Earlier device logs measured about 8.33 ms between
presents in that mode and 16.67 ms at the opening with the game's native
pacing. This engine has logic that advances with the frame cadence, so
uncapped presentation can change how fast gameplay runs.

[The scoped patch](ocarina-m2-native-pacing.patch) sets 60 Hz as the display
target and honors the game's own presentation interval after applying global
and per-game settings. Only program `0400486024DEC000` uses the policy, and its
frame-rate setting displays the game's native mode. Apply this patch to the
pinned M2 60.89 Gamebox shell from the directory containing `LibraryApp/`.
The original `LibraryApp/Sources/main.m` SHA-256 is
`cc1c4ce09d27ca76b00f57032c24f3d98e2eb35e1b21cfad71f657550ded58c7`.
Relink the shell; keep the independent Ocarina engine, shader chain, game
resources and saved data unchanged.

The 60.90 shell compiled, linked and passed signature and local pacing
checks. The M2 was unavailable for installation. Validation still requires
the same controllable scene, checking game time against elapsed time; the
earlier opening measurements do not establish gameplay speed.

## Ocarina of Time: offline play report (Air 60.60)

The signed Air 60.59 launcher reached end of stream and aborted with result
`0xe15` when the game opened `prepo:u`. The newer upstream engine intercepts
PlayReport::Send and completes it locally. This older launcher instead
serves that name through its existing offline responder, limited to
program `0400486024DEC000`. No report is sent. The game frameworks, shader
chain and save handling are unchanged.

Apply `ocarina-air-offline-play-report.patch` to `dm/host/hle_sf.c` in the
pinned Air launcher. The original SHA-256 is `4e37968a18e54f1a00b4bb516665aaa6973cb96cb8d14f83e608b953cd99b6f4`.

## Air Gamebox: native graphics settings for data-only games

Apply `air-native-quality-defaults.patch` to the 60.60 Air menu sources
(`main.m` and `GameSettings.h`). Games delivered with a signed Switch
framework but without `launcher.json` can now inherit the library's handheld
and MetalFX defaults and override either setting per game. The framework is
checked before using the fallback; native PC ports stay on their own paths.
Handheld mode is named as such because it does not promise 720p. The patch was
compiled and linked into the candidate mixed-engine shell; install and
gameplay validation are pending.

The same patch exposes the existing 3D render scale for Tears of the Kingdom
and the existing dynamic-resolution switch for NieR. The fallback only shows
these controls if the signed framework advertises the respective fixup.

## Air Gamebox: default frame pacing

Apply `air-library-paced-default.patch` to the Air mixed-engine shell after
the native graphics settings patch. The library defaults to the game's
pacing profile. It keeps an explicit environment profile and lets a saved
per-game choice override it. The display-link fallback now follows the final
choice after the menu and no longer sets 120 Hz pacing before that choice.
The launcher records the effective mode and the explicit present rate, if
any. This does not unlock a game's simulation rate or promise 60 fps.

The two changed shell objects compiled and linked against the Air 60.60
base without rebuilding any cartridge or shader. Installation and gameplay
validation of the revised shell are pending.

## Independent engine: return to the library (Air 60.78)

`air-independent-return-to-library.patch` is the library-entry adapter for the
pinned Air host entry `dm/ios/Sources/main.m` whose pre-adaptation SHA-256 is
`d641dfaa91ba8381a8d8205284f3e41b1361523dddc99f28cf19ff27708148d7`.
Normalize that frozen entry's relative includes of the library headers to
`LibraryRoot.h` and `LibraryFramework.h` before applying the adapter. Add
`IndependentGameLifecycle.h` and `FrameworkSegments.h` to the shell's include
path and regenerate the profile registry with `runtime_profiles.py`.

Compile `IndependentGameShellGlue.m` into the selected modern engine, with
`DM_INDEPENDENT_GAME_TITLE` set to its title ID and all Objective-C classes
namespaced for that framework. It requires NX2Apple's complete teardown patch
`0041` at engine base `0c078130` plus its dependent patch queue, not a classic
host with a no-op shutdown stub. Adapt that engine's `front_ios.m` to obtain
its callback from `dm_tonton_shell_return_handler()` instead of looking up a
process-global `dm_shell_return_to_library`. The
`air-framework-game-menu.patch` applies that binding and the compact glass
menu to the pinned NX2Apple source after its teardown queue has been applied.
Apply it only when building an independent TonTon framework. Export the stable v1 symbols plus
`dm_glue_shell_lifecycle` and `dm_glue_set_return`; retain the exact shader chain.

The shell accepts the optional return callback only when both symbols belong
to the selected signed image and capability equals one. It snapshots writable
static sections before starting the guest. The engine flushes saves, stops
threads/audio/GPU users and removes observers before the callback restores
static state, releases only the expected profile, restores environment and
shows the retained library controller. Allocation failure rejects the new
start rather than retaining an incomplete snapshot. No framework is unloaded.

The Air 60.78 installation preserves all existing frameworks and 27 game
directories; the new Fate card is ready. The new quit/relaunch path has not
been player-tested. M2 60.102 separately installs the classic Fate host with all matched resources and 58 DLC; its card is ready. Classic M2 hosts do not advertise this lifecycle capability yet.

### Classic iPadOS 16.1 return candidate

Apply `m2-independent-return-to-library.patch` to the M2 library entry whose
unmodified SHA-256 is
`42a7cbadda8cec9f746a82174ad58b8afd516ce3fd8ffbcbe999f3f0b6cd4a8b`.
Use the lifecycle headers from the same checkout, including the updated
`IndependentGameHost.h` in both framework and shader-identity checks. The
profile registry must provide `dm_profile_release_selection`.

Build a compatible NVN framework with `--classic-shelf` and the matching
shader/reflection chain. This enables the optional return capability; it is
off by default in the compatible builder. The guest exits at cooperative
thread boundaries before audio, UIKit, GPU, save workers, and guest mappings
are released. A failed or incomplete drain leaves the library closed. Do not
claim support for a title until it exits to the library on iPadOS 16.1 and
another title can start in the same process.

The classic iPad host's retirement path first parks threads at checked guest
boundaries. A native callback or a thread that cannot reach a boundary makes
that attempt time out and releases the parked threads. After commitment the
owner must still wait for the kernel to observe actual pthread exit, including
thread destructors, before reclaiming the mapped gate stacks. Switch 2 video
decoders keep their guest pools mapped until the native workers join and the
GPU is done with their images. This host work does not enable the shell
capability: the owner still has to shut down the remaining host producers and
bind the return callback. Require two successful game launches in one M2
iPadOS 16.1 process before enabling it on the older iPad.

Air Fate's pinned engine also needs `fate-extella-ios-touch-preferences.patch`
on top of its teardown queue (`553db40` in the prepared engine checkout). It
reads version 2 layout coordinates while retaining version 1 presets and
honors the shelf's `DM_TOUCH_FACE_MAP` for touch labels and input, independently
of the physical controller. Rebuild the affected frontend object and relink
the existing framework; no shader or game data rebuild is required.

The experimental Red Alert WebKit runtime has a separate return callback in
source. It stops the web view and local loopback server and preserves the
persistent store. This does not add in-process teardown to the shipped native
Red Alert frameworks.

The November 14 shell restores its library environment before the shelf is
interactive and waits for the framework callback to unwind before restoring
its static data. For a framework with the capability, the ellipsis menu's
**Return to Gamebox** action uses the upstream confirmation dialog. Holding
controller Home also opens the confirmation when iOS routes that button to
the app. Air 60.81 was installed over 60.79 using 25 byte-identical signed
frameworks and the rebuilt Fate framework. The new library launched and
reported 27 games ready. The in-game quit and relaunch have not been
play-tested on this build. The iOS 27.2 bookshelf preview uses the real UIKit glass
button styles; the iOS 16.1 bookshelf build uses its availability-checked
fallback.

## Classic iPad: safe return worker fence (November 16)

The iPadOS 16.1 NVN host has an opt-in fence for library return. After the
guest has retired and the front end has stopped submitting display work, it
waits for pipeline preparation, the classic presenter, explicitly registered
Metal callbacks, and the last archive write. It closes the cheat worker and
the save sender, and refuses to hand back the session while an abandoned
cloud fetch is still running. A test exercises an abandoned fetch blocked on
a FIFO, followed by a successful teardown once the fetch releases it.

The classic front end can close focus admission, remove notification
observers, invalidate the display and FPS timers, and wait until the last
UIKit save task has ended. A session generation outside the restored image
sections prevents a delayed UIKit callback from affecting a new session.

The classic independent EXTELLA framework is the first to opt in. Its
launcher wires the return callback to the library window. Guest workers,
save tasks and Metal have to finish before the launcher restores its
environment. The 60.112 M2 smoke test aborted at startup: remapping a
positive-offset signed game image removed execute access on iPadOS 16.1.
The follow-up leaves code in place and reinitializes only the writable
guest data. On M2 build 60.114 EXTELLA rendered the auto-save prompt,
but the shelf fence declined to detach: the legacy loader did not record
the signed patch extent for positive-offset modules. Build 60.115 records
that extent so the original gate provenance check can accept those SVCs.
M2 build 60.117 rendered the auto-save prompt again after moving packaged
texture resolution and upload to the serialized submission path. The
display worker now only consumes a retained Metal texture. Its exit attempt
identified a final guest worker blocked in `PopNotificationMessage` on a
temporary HLE stack. The worker now verifies its guest frame chain through
the trampoline's saved entry frame and runs pthread cleanup on its original
system stack. On iPadOS 16.1, classic builds leave the optional persistent
Metal binary archive disabled: Metal failed archive serialization and then
crashed in its release path, after the last GPU submission had completed.
The shipped shader libraries and in-memory pipeline cache still work.
On the M2 running iPadOS 16.1, build 60.119 rendered EXTELLA, returned to
the game library after the runtime drained its workers and GPU, and started
EXTELLA LINK under the same process. The test used separate scratch saves
and verified the original saves were unchanged. No game shader chain
changes with this fence. The older iPad received the 60.120 launcher in
place and opened the library. Its game images, save fingerprints and prior
framework list matched the pre-install checks. Older frameworks that do
not declare the safe-return lifecycle still use their original launch
behavior; installing the launcher alone does not opt them in.

For M2's shader recovery, 8,442 of 8,443 archived Samurai Remnant base
shader pairs matched the current inputs after reconstructing the original
Metal compiler identity. Its version output included the Mac's Darwin
version, which changed without changing the compiler build or iOS SDK.
The last pair had no archive index and was rebuilt for the same chain.
All 8,443 pairs and their variants (38,864 files), plus 396 Tears of the
Kingdom sample and opening-scene pairs (1,409 files), passed M2 readback.
The compatible signed frameworks and game data are already on M2. One
Samurai Remnant and 54 Tears of the Kingdom non-point vertex sources were
matched to the original 16.1 libraries by hash and read back on M2. Tears
of the Kingdom also needed two shared fonts from the local library. The
caches are still partial and carry no ready stamp; manual resume requires
both titles to render an actual game scene correctly.
