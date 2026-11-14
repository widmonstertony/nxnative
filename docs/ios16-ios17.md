# Build and install on iOS 16 / iOS 17

The TonTon build page on `main` supports explicit **iOS/iPadOS 16.1** and
**17.0** classic targets. iOS 16.0 is not supported. The historical
`ios16-ios17-compat` branch records the standalone legacy port. Game and device
compatibility are separate: check the [device status](fork-status.md) before building.

## Build in TonTon Gamebox on Mac

Use **Build → iPhone / iPad → Minimum iOS / iPadOS**. For iPadOS 16.1,
choose 16.1+; choose 17+ only if the device has been updated. Select **M2 iPad**
for the validated M2 capability rules, or **Conservative (A10X)** for older
hardware. Choose a game and its matching update and DLC, then set **Save to**
to a volume with room for the build and exported IPA. Encrypted packages
require your own keys; a supported extracted game folder does not.

**Build & export** uses the existing progress view, log and build queue. The
queued job stores its OS and GPU choice. Repeating the same choice reuses that
job's checkpoints; a different choice has its own work directory and output
name. A classic toolchain snapshot is shared per output folder. The tool checks
the IPA's `MinimumOSVersion` and the linked iOS arm64 binaries before reporting
success and writes a `.build-report.json` beside it. Classic exports use the
pinned engine, shader translator and ABI together; new modern builds use the
current engine. The experimental Rust builder is not used for the validated
classic export contract.

These exports contain a single game's runtime, shaders, base data and selected
add-ons, for external signing and sideloading. They do not replace an existing
multi-game Gamebox or give legacy engines an in-process return to the library.
Very large IPAs may exceed a sideloader's extraction limit. The compile/link
fixtures for 16.1 and 17 were verified with Xcode; they do not constitute
per-game or on-device gameplay tests.

To build the same Mac application from the repository:

```sh
python3 scripts/build_tonton_mac.py 'build/TonTon Gamebox.app' \
  --build-path build/mac-builder --python /path/to/venv/bin/python3
```

A fresh app is signed locally and uses the existing TonTon application identity.
Use `--existing` to preserve an existing bundle's metadata and resources and
`--sign` with the authorized Mac identity when repackaging a provisioned app.
The fresh local build does not acquire CloudKit entitlements on its own.

## Get the compatibility source

```sh
git clone --branch ios16-ios17-compat https://github.com/widmonstertony/nxnative.git
cd nxnative
```

Existing clones of the former branch can follow the rename without recreating
or deleting their work:

```sh
git branch -m ios16-pokemon-za-port ios16-ios17-compat
git fetch origin
git branch --set-upstream-to=origin/ios16-ios17-compat ios16-ios17-compat
```

The rename retains history. The fork's `main` now also carries the integrated
Mac build UI and explicit classic target selection. Community launchers must actually
use this fork and branch to pick up its compatibility code. A link in a
launcher's README does not mean its current binary includes this backend.

## Prepare the build Mac and game files

Use the compiler/tool dependencies in the [README setup](../README.md#build-from-the-command-line).
The build Mac and Xcode must be recent enough to compile the source; targeting
an older iPad does not mean Xcode from iOS 16 can build the current project.
Use an ARM64 Python 3.12 or newer and install Xcode's iOS and Metal components.

Keep your own base game, matching update and DLC in a separate folder, and
supply your own `prod.keys` for encrypted Nintendo dumps. Never commit keys,
extracted game code, translated game shaders or game assets. Allow space for
extraction, shader caches, Xcode intermediates and the final IPA. Large titles
can take hours; a finished shader compilation alone is not an installed game.

## Choose the actual GPU target

| Build selection | Intended target | What it does not establish |
|---|---|---|
| `DM_IOS_RENDERER=legacy DM_LEGACY_TARGET=a10x` | Conservative older-GPU capability checks, including A10X iPads | Every A10X game works, or every other device has been tested |
| `DM_IOS_RENDERER=legacy DM_LEGACY_TARGET=m2` | Tested iPad14,6 M2 capability path, including native layered rendering and Tier 2 samplers | That these resources can be installed on A10X |
| `DM_IOS_RENDERER=metal4` | Modern backend, minimum iOS 26, supported modern GPU | Metal 4 support on iOS 16/17, or a performance guarantee |

The legacy resource audit verifies non-point variants, layered/sampler
requirements, bounded atomic shadows and fragment image writes. It stops for
unsupported or unproven operations. Keep the generated `legacy-resource-audit.json`
and fix its reported operation; changing an IPA's minimum OS, skipping a failed
shader or renaming its cache is not a compatibility port. Vulkan/OpenGL routes
need their own renderer validation; the NVN audit is not blanket coverage.

## Build an unsigned IPA

For a conservative older-device build:

```sh
DM_IOS_RENDERER=legacy DM_LEGACY_TARGET=a10x \
  python3 scripts/build_ipa_from_nsp.py /path/to/YourGame -k /path/to/prod.keys --gpu none
```

For the M2 capability target, replace `a10x` with `m2`. `--gpu none`
avoids building a modern offline PSO archive for the legacy renderer. The
script prepares the rewritten modules, matching shader libraries, resource
companions and host. Unregistered games receive provisional profiles; the IPA
may still fail at runtime. See the [packing options](development.md#the-packing-script-in-detail)
for language, update selection and separate RomFS packaging.

Shader libraries, reflection, per-game tables and the host must match. After
updating the source, let the build regenerate its resources for the new chain;
do not copy old libraries into a new chain directory. Keep an existing working
installation until its replacement is ready.

## Sign, install and preserve saves

The build produces an IPA for external signing/sideloading. Use your own valid
certificate and provisioning for the actual bundle ID and device. The selected
signing method must preserve the required entitlements; larger games need
`com.apple.developer.kernel.increased-memory-limit`, and profiles requesting
extended virtual addresses also need
`com.apple.developer.kernel.extended-virtual-addressing`. Raising a limit in
source does not grant that permission to an installed application.

Use the same bundle ID for an update and retain its Documents data. Avoid
uninstalling an existing app to test a replacement: uninstalling removes its
local saves. A signing or installation error is different from a runtime crash;
verify which version actually installed before trying again. Separate RomFS
packaging reduces repeat transfers but still requires the complete matching
game data on the device. See [quick reinstalls](development.md#quick-reinstalls)
and [playing, controls and saves](playing.md).

TonTon's multi-game library keeps each game's data under its own slot and
loads Nintendo code from signed frameworks. A cover or imported data directory
does not supply an executable host. Adding a new code module requires a signed
application update; this is not a universal raw-NSP runtime importer.

## Report an older-device issue

Include the device model, exact iOS/iPadOS version, source commit, renderer and
capability target, game title/update, installed app version, resource-audit
result, and the relevant `Documents/log.txt` or per-slot crash log. Describe
whether it fails before the launcher, at game start or in a later scene.
Remove personal data and credentials; do not attach game assets or saves to a
public issue. For graphics failures, include a screenshot and the first GPU or
shader error rather than only the later rejected submissions.

Actual rendering FPS, generated frames and display refresh rate are different.
An unlimited frame-rate setting does not guarantee 60/120 FPS. Experimental
image optical-flow interpolation and spatial MetalFX are not Apple's native
MetalFX frame interpolator, and game-clock correctness still needs per-game
validation. See the [current limits](fork-status.md).


## Frame-rate preference

TonTon's iPhone and iPad library defaults to **Unlimited** (`DM_FRAME_LIMIT=unlimited`),
with **Original game settings** available in global settings. This removes the
host's extra presentation wait. It is not a promise that every game's internal
30-FPS limiter has been removed. Fixed-step adapters and movie clocks still take
precedence where removing them would change game speed. Each engine needs its
own verified limiter/elapsed-time integration; the FPS counter reports measured
frames rather than the display refresh rate.

Witcher 3 build `b151a224a429f9a73abb05c5a3de9468` separately clears its engine
`LimitFPS` under this policy, preserving its dynamic-resolution budgets and
simulation/movie timing. Other builds are not written using these addresses.
Actual uncapped performance and the remaining image fixes require device tests.

Need for Speed build `799d1061182c1302e08e706b84ce76e5` uses measured active
frame durations under the unlimited policy, updating both 2D and 3D timing
together. Its exact-build busy-wait repair is still required. Variable-rate
clock tests pass; real-device performance and driving-speed validation remain
pending. Other engines with fixed-step adapters retain their safety limits
until their own elapsed-time integration is verified.
