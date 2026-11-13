# Pokémon Pokopia (`0400A3A01EE4C000`)

A Switch 2 game: update v655360 (the title screen says Ver. 2.0.1), SDK 20.5.25 built for the Switch 2 (`Ounce`). Koei Tecmo's KTGL engine on NVN2, modules `main`, `subsdk0` (WebM movies) and `sdk`. **Plays on the Mac**: the opening, the character choice and the first area's tutorial at about 60 fps, including 31 minutes of the user's playtest with no GPU error and no crash. A save from an earlier run loads and continues. No IPA has been built.

## What it needs

| Setting | Where | Why |
|---|---|---|
| `mem_reserve 0x270000000`, `app_pool 0x240000000` | [`game.tsv`](game.tsv) | Donkey Kong Bananza's 9 GB layout, not measured here. The NPDM declares no system resource |
| `mem_used 0x5600000` | `game.tsv` | the rewritten modules take 82 MB, more than the default 64 MB that `SetHeapSize` checks the game's request against |
| `pad_layout full` | `game.tsv` | |
| `depth_mode zero` | `game.tsv` | the game sets near = 0 (the log's `depth mode` line). Without the key the pipeline archive made offline holds the other entry point, and the host refuses it |

## Files

- A dump folder whose `updates/<version>/` holds the whole RomFS; [`pack_dump.py`](../../../scripts/pack_dump.py) packs it without a base RomFS. RomFS: the newer RDB (as ROMANCE OF THE THREE KINGDOMS 8 REMAKE's) under `motor_asset_re/KIDS_PLATFORM_OUNCE`, and a `LD_C0_R.BIN` / `LI_C0_R.IDX` LINKDATA pair.
- Shaders: 131,426 in [`shader_map.tsv`](shader_map.tsv) ([KTGL on NVN2](../../../docs/reference/shaders.md#ktgl-on-nvn2-switch-2-glslc-outputs-and-ld_--li_-linkdata)). The Mac playtest's library held only the 8,157 that its runs asked for (with their pixel shaders), listed in [`shader_seen.tsv`](shader_seen.tsv); the NSP script's `--seen-shaders` builds those alone ([Building selected Mac shaders](../../../docs/development.md#building-selected-mac-shaders)). Such a library has no stamp and no `c1_full.tsv`, and each start logs that in red. On chain `20b9b1c2e4e4` an M4 Pro with other jobs running took 18 minutes for the 8,158 shaders of the list and the last logs (Metal's compile cache held nearly all of its libraries: 113 compiled), or 16 minutes with all of them cached, then about 5 minutes for the 7.9 GB Mac app. That app boots to walking at about 16.7 ms a frame with no GPU error and no shader reported missing, and later areas are untested on it. The NSP script builds all 131,426: an estimated 2.5 hours on an M4 Pro (from 1,001 shaders; no full build has run) since [the builder stopped keeping the 4.4 GB of packages in memory](../../../docs/reference/shaders.md#a-shader-build-that-keeps-its-packages-in-memory-runs-one-worker-at-a-time) and [its compiles stopped instantiating Metal's texture classes again](../../../docs/reference/shaders.md#each-metal-compile-instantiates-metals-texture-classes-again) and [its Python stopped limiting it](../../../docs/reference/shaders.md#rewrites-that-try-every-character-of-a-large-source) (before all of these, players saw about one shader a second and ETAs of 20 to 200 hours: GitHub issue #1036). The map's 105,534 pixel shaders each have `_ba` and `_bl` libraries, 57% of its compiles before those whose MSL matches another's, while the runs on the 8,157-shader library opened none of them (file access times; 7,985 of its 8,157 `_b` libraries were opened). Those runs only reached the first area (open).
- No `pso_manifest.tsv` yet, so each start also logs a red line for the missing seed list. In the runs here no draw waited on it.

## Shaders

- Resolved: `cc679c7b4d3e703c` did not translate (`LDC with a bindless bank or an address mode`): an indexed read of c1 with the bank in the address register, found on Hyrule Warriors: Age of Imprisonment, which ships the same shader ([LDC with the bank in its address register](../../../docs/reference/shaders.md#ldc-with-the-bank-in-its-address-register-is)); all 8,158 shaders of the playtest library now translate, and the walk below logged no shader failing to load. The census also lists f55 three times, two more of that LDC and 16 BRX with no target: whether they are the forms since translated ([Barrier moves around warp shuffles](../../../docs/reference/shaders.md#barrier-moves-around-warp-shuffles)) is not checked (open).
- A `3D binding fallback` line fires once at about frame 2100: a 2D 8x8 texture in a 3D slot. The shader is not identified (open).

## Rendering

- Frames take about 16.7 ms. A cold file cache, as after a reboot, keeps the game on the loading icon for over a minute, and a clean run there says nothing: check that `[nvn] frame N: … calls` reached about 3,500.
- The lit HDR target is RG11B10, exposure a 2x1 RGBA32F image, tone map `075fd7285c64b798` with a 32³ LUT, final `ed5f4c6386ca621d`, the luminance histogram compute `2118ab534fac88c6`.
- `texraw` pads rows: an RG11B10 dump has a 16-byte stride with 4-byte pixels at the head of each row. It returns one slice of a 3D texture, and serials shift between runs.

## Driving it on the Mac

The first boot shows the language list: `A`, `LUp`, `A` picks English. The character choice takes `LLeft` before `A`. From a warm cache, `A A LLeft A A Plus` reaches walking in about 300 s. On later boots, `A` at the title screen a few times continues the save and reaches walking in about 110 s. The work folder has `run/boot.sh`, `run/hdrive.sh` (no window, timed control lines) and `run/spam.sh`. The packed app takes about a minute to reach the language list (14 s of it the prepare step on a second start), so the fixed times in `run/spam.sh` miss it: press the keys once the list shows.

## TonTon Air scene resolution cap (v327680)

The separate TonTon Air library retains main build
`816c5358e8178d802fcec4a7ce5a741a`, not the v655360 Mac build above.
Its retained November 8 device log shows a 1920x1080 window and MetalFX
present scaling to 2240x1260, followed by serious thermal state and roughly
43–48 fps. Handheld mode alone did not cap its scene resolution.

A mobile stopgap now limits the game's own dynamic-resolution choices,
using [`resolution_levels.tsv`](resolution_levels.tsv). The v327680
selector at main+0x1fb7a0 references all nine lists in that contract;
width/height getters at +0x103a1d0/+0x103a210 read its 34-level table.
The default cap is 1280x720, with `DM_WINDOW_SIZE=960x540` or `original`
overrides. `DM_RESOLUTION_LEVELS_PATH` lets a multi-game front end select
this exact profile's contract. Fixed addresses run only for that build ID,
after every original table/list value and writable range has been checked.
A failed check writes nothing. The table, maximum target allocations,
signed code and shader chain stay unchanged. UI and output texture sizes
can therefore still be 1080p; this is a scene cap, not proof of a 720p
presentation texture or of the size of every intermediate pass.

The principle was researched in the author's
[BananaNative Android branch](https://github.com/Raphix91/BananaNative/tree/bfc32425f3d2391401b71dfda0cb09e6686fb79a)
and independently implemented here for signed iOS data mappings; that
branch's v655360 addresses are not used. Local validation covered the
owned v327680 embedded image (all nine lists, unchanged code/table,
720p/540p/original, wrong builds and rejected corrupt contracts) and the
small Air loader/menu rebuild. Air 60.72 was installed in place; the actual run logged the 1280x720 cap
and seven lowered lists. The user still reported crackling and stutter:
late-scene measurements were about 28–44 fps with serious thermal state.
Audio underruns appeared after the route changed from 48 kHz CarPlay to
44.1 kHz Bluetooth, without establishing sole causation. The next 960x540 plus MetalFX run logged nine lowered lists and the
player reported reduced stutter, with crackling still present. After about
14,000 callbacks its four-block PCM queue collapsed toward zero; later
2,000-callback windows contained 1,943–1,996 underruns, including the
48 kHz built-in-speaker route. This rules out treating Bluetooth rate
conversion as the sole explanation. Rendering still worked at roughly
24–43 fps in the hot state, with expensive real-time render-thread budgets
and 63 interactive workers. A per-game `DM_RT=0` comparison was written
and read back, then confirmed in the next launch. The player still heard
crackling; scene windows contained 5–857 underruns per 2,000 callbacks.
The switch alone did not solve the defect. Air 60.73 is installed with opt-in
[producer/release progress](../../../docs/reference/audio.md#distinguishing-pcm-production-from-release-notification-starvation)
without altering PCM production or release semantics.

The 60.73 speaker-route run logged 5,043 underrun callbacks out of 44,000
(240 frames / 5 ms each). The worst 2,000-callback window zero-filled
5,920 ms. `AU_capacity_bytes` remained exactly four times requested frames,
so this run does not support an oversized-AudioUnit-buffer explanation.
Release notifications continued to complete and released buffers continued
to be reclaimed; the cumulative checkpoints cannot establish the latency
of an individual notification, wake or mix. They do not prove that the
notifier is fault-free.

A subsequent bounded `DM_HITCH_DUMP=35:45` run identified the producer as
`KTSL2AudioOut` (guest priority 30, waiting in `WaitSynchronization` through
main+0x10ecb64). All 24 snapshots found it waiting there, one during mutex
reacquisition; these are frame-hitch samples, not samples triggered by an
audio underrun. The same host assigns priority-39/44 workers and that audio
thread the same interactive QoS by default. A per-game comparison
uses existing `DM_QOS_MAP=1`, `DM_QOS_EDGES=30,44`: audio remains interactive,
workers in 39–44 become user-initiated, and lower-priority workers become
utility. The 540p plus MetalFX cap is retained; hitch dumps are removed for
the comparison. The next launch confirmed those bands, logged zero underruns
through 16,000 device callbacks, and the player reported much less crackling.
The scene still ran at about 41–45 fps: frame p50 21.7–23.2 ms, GPU p50
10.4–11.3 ms, submit/present p50 16.9–17.4 ms. MetalFX presentation took
about 2.6–2.9 ms separately; these overlapping intervals must not be added
as a serial critical path. The device was already in thermal state 2.
This supports retaining the narrow comparison for now; it is not a permanent
all-scene audio fix or a new default for other games.

The next per-game comparison enables existing `DM_PRESENT_SNAP=2`, absent
from the measured launch, to release swapchain textures after a queued copy
rather than the display tick ([frame buffering](../../../docs/settings.md#frame-buffering)).
It retains the audio bands, 540p cap and MetalFX. The next launch confirmed
snapshot buffering; the player reported only a slight improvement. Later
scene windows still had frame p50 22.1–23.2 ms and p95 33.0–56.8 ms, with
GPU p50 near 10 ms and submit/present near 17 ms. No audio underrun was
logged through 42,000 callbacks. This did not meet the smoothness target.

A subsequent `DM_QOS_EDGES=39,44` comparison keeps the priority-39 graphics
dispatcher interactive alongside priority-30 audio, while priority-44 workers
remain user-initiated. Its launch confirmed those bands. The player reported
normal sound but continued severe stutter. The last three scene windows ran
at 47.6–48.6 fps, frame p50 19.46–19.95 ms and p95 27.14–29.77 ms,
submit/present p50 13.53–13.71 ms, GPU p50 12.26–12.59 ms. The run logged
zero underruns through 30,000 callbacks and thermal state 2. These are
successive manually reproduced runs, not a controlled matched-state speedup.
The bands are retained provisionally; sustained 60 fps remains open.

The retained host already has the texture-view cache, serial-hashed
CPU-written-texture membership, binary-search memory-pool lookup and
main-thread QoS initialization. Reapplying those upstream changes is not an
identified missing fix. Existing `DM_NVN_CPUPROF=1` and `DM_NVN_WAITS=1`
diagnostics were enabled for Pokopia alone and read back, awaiting a new
representative scene capture; nested CPU phase timings overlap. No new host,
shader rebuild or game launch was performed for this diagnostic step.

Upstream's frame-buffering phone measurements are for Breath of the Wild,
not proof of a Pokopia gain. The
[iPhone-specific Pokopia Native guide](https://pokopia-native.vercel.app/iphone)
reports a default 30 fps target and serious thermal state after about six
minutes, with render-scale reduction as its mitigation. Its custom scaling
and Android/Vulkan frame generation cannot be assumed to exist in this
retained Metal runtime. No sustained 60 fps or universal resolution control
is claimed.

The subsequent full-timing run reproduced the stutter but exposed
[missing queued-thread CPU reports](../../../docs/reference/frame-rate.md#cpu-phase-reports-miss-the-queued-submission-thread): only small texture/index
counts were reported, and full per-operation timing increased submission CPU
time to about 18–19 ms. Those timings are perturbed diagnostics, not a new
baseline regression. Temporary CPU/wait flags were removed and read back;
the change takes effect on restart. A narrow host-only diagnostic correction
is installed as Air 60.74 after compile, link and signature checks. Installation
retained all 26 game directories and the checked ROM sizes. It reports each
submitting thread and samples each phase,
without changing shaders, game code, rendering semantics or saves. A
`DM_NVN_CPUPROF=64` capture confirmed the actual priority-39 graphics
submission thread in the reports. On the next user-tested scene the player
reported no stutter and no audio interruptions. The final four 300-frame
windows ran at 58.8–59.9 fps, frame p50 16.63–16.74 ms and p95
18.03–20.06 ms; GPU p50 was 11.66–11.86 ms. The last six audio windows
(12,000 callbacks) had zero underruns, with the PCM queue averaging four
blocks. The full 18,000-callback capture included 100 underruns (499.4 ms
zero padding) in the window spanning callbacks 4,001–6,000, which also
contained a background/foreground transition; that coincidence does not
establish sole causation. Thermal state still reported 2. This is a successful scene retest, not proof
of sustained 60 fps across all areas or of one change being the sole cause:
these runs were not matched for thermal state, route and scene progression.
The tested 540p plus MetalFX, snapshot and QoS settings are retained; the
uninstalled O3 candidate is not credited with this result. The four diagnostic
tests pass against both host source versions, and all 11 documentation tests
pass. The gameplay regression harness was
not configured (`REGRESS_ROOT` / `REGRESS_GAMES`); no harness pass is claimed.

The retained Air renderer compile command ends in `-O1`, overriding an earlier
`-O3`. The same diagnostic source was compiled separately with effective
`-O3` for a possible CPU-cost comparison. That object is not installed, and
compile success alone establishes no gameplay speedup.

## Open

- The picture has not been compared with a Switch 2. The user's playtest found it fine. Sunlit ground matches published iPhone shots of the game. Shaded ground and walls are lavender. The player carries fine contour lines, already present in colour target 5435, which may be the material. In some moving shots far blocks showed through near ones; this has not been rechecked since the fixes below.
- Only the first area has been played on this build. A new save written through the game has not been checked: the 31-minute playtest wrote none.
- The pipeline archive saved nothing on the walk from the language list to the first area, on the partial library: archive lookups found 0 and found none 655 times, and 216 bases were compiled, though the host's probe found the archive's bases. The draws' pairs seem not to be those of `shader_pairs.tsv`, which come from BNSH variations. Whether a full library differs is not checked.
- An IPA has not been built. A full iOS shader build would be needed first.

## Found on this game

- [CPU phase reports miss the queued submission thread](../../../docs/reference/frame-rate.md#cpu-phase-reports-miss-the-queued-submission-thread).

- [Distinguishing PCM production from release-notification starvation](../../../docs/reference/audio.md#distinguishing-pcm-production-from-release-notification-starvation): Air crackling remains under investigation; no repaired-audio claim.
- [One compile for a pixel shader's side entry points](../../../docs/reference/shaders.md#one-compile-for-a-pixel-shaders-side-entry-points): 57% of the map's compiles were `_ba` and `_bl` libraries; a cold build of 1,021 shaders now takes 48% of the CPU on the Mac's flags and 47% on the iPhone's.
- [KTGL on NVN2: Switch 2 GLSLC outputs and LD_ / LI_ LINKDATA](../../../docs/reference/shaders.md#ktgl-on-nvn2-switch-2-glslc-outputs-and-ld_--li_-linkdata): the split found almost none of its shaders.
- [HADD2 and HMUL2 with an immediate](../../../docs/reference/shaders.md#hadd2-and-hmul2-with-an-immediate): the GPU hang and 88 ms frames.
- [Scaled shared memory addresses](../../../docs/reference/shaders.md#scaled-shared-memory-addresses): stride 3 in use, on accesses of every size.
- [HFMA2 .H0_NH1](../../../docs/reference/shaders.md#hfma2-h0_nh1).
- [Ampere instructions new in Pokémon Pokopia](../../../docs/reference/shaders.md#ampere-instructions-new-in-pokémon-pokopia).
- [A shader build that keeps its packages in memory runs one worker at a time](../../../docs/reference/shaders.md#a-shader-build-that-keeps-its-packages-in-memory-runs-one-worker-at-a-time): the full build at one or two shaders a second (resolved).
- [Each Metal compile instantiates Metal's texture classes again](../../../docs/reference/shaders.md#each-metal-compile-instantiates-metals-texture-classes-again): the full build's remaining hours.
- [Rewrites that try every character of a large source](../../../docs/reference/shaders.md#rewrites-that-try-every-character-of-a-large-source): the builder's Python limited the full build at about 0.12 s a shader, 0.05 s after.
- [A library that depends on its source's file name](../../../docs/reference/shaders.md#a-library-that-depends-on-its-sources-file-name): two `_bl` files differed between cold builds of the same code.
- [Integer buffer textures read through float slots](../../../docs/reference/rendering.md#integer-buffer-textures-read-through-float-slots).
- [The Joy-Con mouse pointer](../../../docs/reference/services.md#the-joy-con-mouse-pointer) and [GameShare guest displays](../../../docs/reference/services.md#gameshare-guest-displays): boot aborts.
- [Block-compressed storage the CPU wrote before first use](../../../docs/reference/nvn-objects.md#block-compressed-storage-the-cpu-wrote-before-first-use): its `IMAGE` BC1 / BC7 icons showed other items' pictures once their storage was reused (resolved).
- [VOTEU writes the uniform predicate](../../../docs/reference/shaders.md#voteu-writes-the-uniform-predicate): 471 of its shaders change; in the first area only the full-screen `075fd7285c64b798` draws, its votes all false, so the picture is unchanged there.

- [A handheld setting leaves the scene at 1080p](../../../docs/reference/rendering.md#a-handheld-setting-leaves-the-scene-at-1080p).
