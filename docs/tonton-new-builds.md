# TonTon: building a new title

Use a clean, separate checkout of `main` at the selected engine commit. Keep
it at that commit until the build and device checks are done. Existing builds
keep their original source directories, chain versions, caches and resources.
Do not reuse a legacy job directory or migrate an installed title just because
`main` has changed.

Use the macOS arm64 [nxkit v0.9.3 release](https://github.com/v0lumehi/nxkit/releases/tag/v0.9.3).
Verify the archive SHA-256 before unpacking it:
`7434d704a590de4ef964fc5467b89f8b0f0f8f25f7279d3fdf00503ebc8bc088`.
The runner also checks the unpacked binary's digest and records the engine
commit in the job receipt. Keep the source packages and all build data outside
the engine checkout. Pick a fresh job directory for each command below.

```sh
python3 scripts/build_tonton_new.py plan /path/to/game.nup \
  --nxb /path/to/nxb --job /path/to/new-job/plan

python3 scripts/build_tonton_new.py extract-switch2 /path/to/game.nup \
  --nxb /path/to/nxb --job /path/to/new-job/extract --version 196608

python3 scripts/build_tonton_new.py build-mac /path/to/game.nup \
  --nxb /path/to/nxb --job /path/to/new-job/mac
```

Select the actual numeric NUP version from the owned package; `196608` is an
example. For Switch packages, give `plan` or `build-mac` the directory of
owned packages and pass `--keys /path/to/prod.keys`. An iOS plan only prints
the stage graph; it neither compiles nor installs. The Rust shader front end
is disabled in this workflow while its device output is unverified.

For Air, use Rust extraction where supported, verify the selected build ID
and extracted outputs, then use this engine's reference iOS build path with
`DM_IOS_RENDERER=metal4` and title-specific Metal 4 shaders. Keep the runtime
and shader chain together. Use the reference stage if Rust returns unsupported;
validate both before activating any device resource. The Rust iOS packaging
path has not been verified as an Air Metal 4 substitute, and a Mac build is
not evidence of iPadOS 16.1 support.

## Main integration verified on 2026-11-12

The main integration includes nxnative upstream
[`a780d2cd`](https://github.com/seedds/nxnative/commit/a780d2cd6ce5317940e4ff78125ca7a4a4874420),
with TonTon private CloudKit transport, Chinese Mac settings, per-game desktop
controls and the legacy elapsed-time frame-step path retained. Derived profiles
can reuse the built-in keyboard preset while keeping their own shader tables.

Validation compiled the complete arm64 Mac host with the Ocarina profile and
the standalone TonTon app. Synthetic checks passed for NVN (318), save sync
including private transport and interrupted-pull recovery (117), save metadata
(204), keyboard mapping (22) and physical controller mapping (34). All 23 desktop
profiles parsed; settings persistence and the Mac packaging tests passed. No
installed game was rebuilt onto the new shader chain during this integration,
and gameplay acceptance remains with the player.
