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
process-global `dm_shell_return_to_library`. Export the stable v1 symbols plus
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
