# nxnative

Play your own Nintendo Switch and Switch 2 games natively on Apple silicon Macs, iPhone and iPad. One script packs your game into a Mac app or an unsigned IPA that you sideload.

It is not an emulator: the game's own code runs directly on the Apple chip, with Switch graphics rebuilt on Metal. Nothing from any game is in this repository, and the project is not affiliated with Nintendo or any game publisher.

[Games](#games) · [Community front ends](#community-front-ends) · [Requirements](#requirements) · [How to play](#how-to-play) · [Discussions](#discussions) · [For developers](#for-developers)

## TonTon Gamebox build tracks

- **New builds:** this `main` integrates [nxnative upstream `3c4de03c`](https://github.com/seedds/nxnative/commit/3c4de03c71e45651d1f3440e149cb4c47811ec3d). Use a separate checkout at the selected commit and a new per-title job directory. See [the Rust build workflow](docs/tonton-new-builds.md).
- **Installed and in-progress titles:** keep the exact engine, shader chain and artifact set already recorded by each job. The [pre-sync compatibility source](https://github.com/widmonstertony/nxnative/tree/a86d90baf72c52349460907040f97b9634df2ed5) and [iPadOS 16.1/17 maintenance branch](https://github.com/widmonstertony/nxnative/tree/ios16-ios17-compat) retain the legacy renderer and TonTon device work. This merge does not port those changes into the new engine, change a device install, or reuse an old shader cache.

## TonTon Gamebox: game fixes and verification

Add each published game fix here with its affected device, what changed, and
the deepest scene actually verified. A signed install or a successful shader
build is not a gameplay pass. Keep earlier observations in the
[device history](https://github.com/widmonstertony/nxnative/tree/a86d90baf72c52349460907040f97b9634df2ed5/docs/fork-status.md) and exact backports in the
[engine notes](https://github.com/widmonstertony/nxnative/tree/a86d90baf72c52349460907040f97b9634df2ed5/dm/ios/Engines/NxNative/README.md).

Air build 60.61 defaults compatible native Switch games to handheld mode and
MetalFX spatial upscaling, with a per-game override. Handheld mode leaves the
render size to each game. The compatibility renderer now also has a classic
MetalFX path: local GPU validation covered both 1280×720 and 960×540 input,
including color and aspect-ratio bars. Deployment and game-by-game validation
of that renderer on iPad are pending.

M2 build 60.86 introduced uncapped rendering with a separate elapsed-time
game clock for Pokémon Violet 4.0.0 and Pokémon Legends: Z-A. Settings
and retained game data were read back; normal simulation speed still needs
a gameplay check.

The M2 delivery also trialed a targeted Metal 3 mesh fix for Ocarina of
Time and Mario Kart World. It turns an invalid generated triangle into a
degenerate triangle without changing valid indices or the shader
argument layout. The four Ocarina libraries and the two Kart libraries
with matching descriptors were read back on-device with rollback copies
retained. This is an installation result: Ocarina's first 3D scene and
Kart race stability and frame rate remain open. The old iPad's Kart game data is present, but the runnable framework is still missing.

| Game | What this fork changed | Verified result and open issues |
| --- | --- | --- |
| Mario Kart World | Restored movie texture views, terrain uploads and sparse mappings; fixed black scenery with conditional clears; reduced upload and pipeline work; restored Air's 60 Hz pacing ([movie](https://github.com/widmonstertony/nxnative/commit/3d0a3a0), [clears](https://github.com/widmonstertony/nxnative/commit/381ed5f), [upload cache](https://github.com/widmonstertony/nxnative/commit/e221694), [pacing](https://github.com/widmonstertony/nxnative/commit/e847a4c)) | Air player confirmed the black scenery was gone, but reported low race performance and intermittent race-entry crashes. Air logs still show 1080p input to MetalFX even in handheld mode. On M2, free roam rendered in a prior test; mesh faults and race performance remain open. |
| Zelda: Ocarina of Time | Corrected opening movie decoding on Metal 3 and handled the offline play-report request that aborted at the end of the opening ([movie](https://github.com/widmonstertony/nxnative/commit/4f25737), [M2](https://github.com/widmonstertony/nxnative/commit/ed552f8), [Air](https://github.com/widmonstertony/nxnative/commit/4ecd063)) | M2 60.90 installed the [scoped 60 Hz pacing fix](https://github.com/widmonstertony/nxnative/pull/3) and reached the title in an isolated device test; the forest save and first controllable 3D scene are still unverified on that build. Air previously reached the title; the player later reported a crash. |
| Zelda: Tears of the Kingdom | Restored missing shared-font assets; exposed a real 3D render-scale control and corrected the FPS overlay toggle for data-only games ([controls](https://github.com/widmonstertony/nxnative/commit/86e676d), [overlay](https://github.com/widmonstertony/nxnative/commit/acb19b6)) | Air player confirmed the game opened and later reported less stutter and no FPS overlay. Sustained 60 fps has not been verified. |
| Pokémon Violet | Restored the shared fonts and offline Pokémon GO Plus + startup; on legacy Metal, bound the existing iPad game framework to its validated shader chain and supplied the matching raster and image-atomic companions. | M2 60.84 is installed with the existing 4.0.0 ROM and saves verified unchanged. The legacy character capture binding is included; the post-load scene still needs verification. See the [device test notes](https://github.com/widmonstertony/nxnative/tree/a86d90baf72c52349460907040f97b9634df2ed5/dm/games/01008F6008C5E000/README.md#m2-ipad-update-400) for the scope of verification. Air title entry still needs a player retest. The [uncapped timing candidate](https://github.com/widmonstertony/nxnative/tree/a86d90baf72c52349460907040f97b9634df2ed5/dm/games/01008F6008C5E000/README.md#m2-ipad-uncapped-render-timing-candidate) passed local clock tests; device gameplay is pending. |
| Pokémon Legends: Z-A, Switch 2 Edition | Bound the newer transform-feedback parameters on legacy Metal without changing shaders using the old ABI. Earlier repairs filled missing Metal 3 shader variants and added a Metal 4 compute archive path ([shader loading](https://github.com/widmonstertony/nxnative/commit/2d1396b), [pipeline cache](https://github.com/widmonstertony/nxnative/commit/d24d7c2)) | M2 build 60.82 restored the third-person player model in the same hotel room and save where 60.81 omitted it. Camera rotation and player movement were checked on the device; later city scenes were not part of this check. The uncapped timing path has a local regression test; player movement speed in the reported scene still needs an A/B check. |
| Hyrule Warriors: Age of Imprisonment | New build uses the upstream field and shader fixes below. | The Air shader build and signed candidate are complete locally. The full game image has not been imported or launched on Air. |
| Fate/Samurai Remnant | Resumable shader compilation and validated transfer batches. | A completed batch is staged; the full Air build and first launch are still pending. |
| Crisis Core: Final Fantasy VII Reunion | Adjusted Air address-space reservation and added an M2 renderer repair for buffer atomics. | Air reached the title and later passed the previously crashing scene, with stutter reported. On M2, 20 runtime components were installed and read back with the existing ROM and saves intact; gameplay on that build is unverified. |
| Animal Crossing: New Horizons | Restored the missing M2 runtime components for the existing game data. | Eight runtime components were installed and read back on M2; gameplay on that build is unverified. The Air player confirmed the title launched. |
| Pokkén Tournament DX | Repaired the old iPad's rendering path for its existing installation. | Old iPad 60.97 reached the training HUD; fighters were still missing. This is not a gameplay pass. |
| NieR:Automata | Tracked separately on the legacy renderer. | Old iPad game data is present; the A10X runtime is still missing. |
| Pokémon Pokopia | Restored missing graphics libraries and fixed Switch 2 virtual microphone enumeration ([service fix](https://github.com/widmonstertony/nxnative/commit/646c4ab)) | Reached gameplay in device testing; the player reported character-preview rendering defects on Air and M2. |
| The Witcher 3 | Repaired Air startup after tracing the executable's address-space reservation; verified the exact installed framework ([Air repair](https://github.com/widmonstertony/nxnative/commit/33b0df4)) | Air player confirmed title/game entry. M2 character materials still render incorrectly in some scenes. Old iPad game data is present; its A10X runtime is still missing. |
| Naruto Shippuden: Ultimate Ninja Storm 4 | Fixed the OpenGL ES startup path, framebuffer queries, and NVN/GL texture and fence sharing ([startup](https://github.com/widmonstertony/nxnative/commit/f691081), [framebuffer](https://github.com/widmonstertony/nxnative/commit/2eddd56), [texture sharing](https://github.com/widmonstertony/nxnative/commit/175301f)) | Air player reached battle on one build. Later reports of black characters and another battle-entry crash are still open. |
| Fate visual novels | Repaired native OpenGL framebuffer entry points needed during story initialization ([framebuffer aliases](https://github.com/widmonstertony/nxnative/commit/845c721)) | Air player verified both title screens display at the correct size and Hollow Ataraxia can enter the story. This does not cover the rest of each title. |
| Need for Speed Hot Pursuit Remastered | Fixed initial texture content, race button mapping, audio buffering and elapsed game time ([textures](https://github.com/widmonstertony/nxnative/commit/ffed898), [input and audio](https://github.com/widmonstertony/nxnative/commit/16cecc6), [timing](https://github.com/widmonstertony/nxnative/commit/d59fd00)) | Device gameplay confirmed; no long race performance guarantee. |
| GTA V | Uses the Gamebox mode picker with the separate native iPadOS 16 engine ([mode picker](https://github.com/widmonstertony/nxnative/commit/421e5cd)) | Air player confirmed gameplay and access to per-game settings. |
| Red Alert 2 and Yuri's Revenge | Added native entry and touch controls: tap for left click, drag to select, two-finger tap for right click ([touch](https://github.com/widmonstertony/nxnative/commit/3cd0d50)) | Old iPad testing confirmed map interaction in the original app. The updated signed Gamebox on that device requires the retail-resource restoration before it can be retested. |

Library changes include [private CloudKit save transport](https://github.com/widmonstertony/nxnative/commit/4fe54cb),
[independent game engines](https://github.com/widmonstertony/nxnative/commit/2798a14),
[verified single-file shader images](https://github.com/widmonstertony/nxnative/commit/b51852e),
and [Air game-paced presentation](https://github.com/widmonstertony/nxnative/commit/75f30d7).
The [private CloudKit setup](docs/tonton-cloudkit.md) reuses the same
per-account container for iPhone, iPad, Mac and the Apple TV compatibility
build. Automatic synchronization needs no iCloud Drive folder. A test
save transferred between the two iPads, and the signed Mac mini probe
uploaded and restored a new test save. Apple TV is bound to the container;
device restore verification on Apple TV and a fresh Air cross-device
readback are still pending.

### Upstream game fixes on main

These commits are in `main` for new builds. The device checks above apply
only to the cited compatibility builds; an upstream Mac fix does not
establish that the same scene works on an iPhone or iPad.

| Game | Integrated upstream fix |
| --- | --- |
| Ocarina of Time | [60 Hz simulation on slow frames](https://github.com/seedds/nxnative/commit/7d8dcdf8), [dynamic resolution and timing improvements measured on M4 Pro](https://github.com/seedds/nxnative/commit/04419bc2), and [mist depth artifacts](https://github.com/seedds/nxnative/commit/877c7eca). |
| Mario Kart World | [Slow-frame simulation timing](https://github.com/seedds/nxnative/commit/7d8dcdf8), [shadow mip texture views](https://github.com/seedds/nxnative/commit/32335650), [missing vegetation](https://github.com/seedds/nxnative/commit/e07cba1c), and [Mac sparse textures and mesh pipelines](https://github.com/seedds/nxnative/commit/1d4b8e82). |
| Hyrule Warriors: Age of Imprisonment | [First playable field on Mac](https://github.com/seedds/nxnative/commit/d70ee900), [constant-bank performance](https://github.com/seedds/nxnative/commit/3ace3df3), and [two remaining shader translations](https://github.com/seedds/nxnative/commit/c94ce657). |
| Pokémon Pokopia | [Faster shader translation](https://github.com/seedds/nxnative/commit/ed3c93ee) and [lower build memory use](https://github.com/seedds/nxnative/commit/e70fd69d). These changes do not fix the character-preview defect reported on devices. |
| Pokémon Violet | [Offline Bluetooth LE startup on 3.0.1](https://github.com/seedds/nxnative/commit/235eb516). The M2 4.0.0 renderer repair is tracked separately above. |
| Animal Crossing: New Horizons | [Native aspect ratio for taller screens](https://github.com/seedds/nxnative/commit/b6e1f005). |
| Tears of the Kingdom | [Mac Game Mode opt-out for GPU clock throttling](https://github.com/seedds/nxnative/commit/cb59a672). |

## Discussions

## Games

The full [tested games table](dm/games/README.md#games) includes original Switch games, tested builds, engines and graphics APIs. Each game's note records its tested platforms, progress and known issues.

These Switch 2 games have passed Mac gameplay testing. Build them from a [`.nup` file or a dump folder](#switch-2-games):

- [Donkey Kong Bananza](dm/games/040074A01BF12000/README.md)
- [Fire Emblem Fortune's Weave](dm/games/04007EF01F8AE000/README.md) — up to 120 fps
- [Hyrule Warriors: Age of Imprisonment](dm/games/04003F40232DE000/README.md)
- [Kirby Air Riders](dm/games/040077201BE50000/README.md)
- [Mario Kart World](dm/games/0400C3F00006E000/README.md)
- [Mario Tennis Fever](dm/games/0400D4201C6EA000/README.md)
- [Nintendo Switch Sports Resort](dm/games/04008E001F098000/README.md)
- [Pokémon Pokopia](dm/games/0400A3A01EE4C000/README.md)
- [PRAGMATA](dm/games/0400C76024710000/README.md)
- [Splatoon Raiders](dm/games/0400380020056000/README.md)
- [Star Fox](dm/games/0400E88025B1A000/README.md)
- [The Legend of Zelda: Ocarina of Time](dm/games/0400486024DEC000/README.md)
- [Yoshi and the Mysterious Book](dm/games/0400245021D2C000/README.md)

## Community front ends

Community projects build on nxnative with tools to turn your games into apps for your iPhone, iPad or Mac without the command line, and libraries to organize and launch them. They are separate projects: questions and bugs about them go to their own pages.

- [NX2Apple](https://github.com/LNPANDY/NX2Apple) — Mac builder with a shared iPhone/iPad game library.
- [NX Play](https://github.com/varyform/nx-native-wrapper) — Mac library with device installs and save sync.
- [NxNative Launcher](https://github.com/rennan101/nxnative_Launcher) — Mac launcher with guided builds and controller mapping.
- [LumaNX](https://github.com/Xc1Ym/LumaNX) — Mac game builder with IPA export.
- [GameCase](https://github.com/Tiaoge-tou/GameCase) — iOS game library based on LiveContainer.

## Requirements

- **Mac:** Apple silicon, macOS 26.6 or later. Building games requires Xcode 27.2.
- **iPhone:** A17 Pro chip or later, with iOS 26 or later.
- **iPad:** M1 chip or later, with iPadOS 26 or later.

The games' textures are BC-compressed, which older iPhones cannot read. Switch 2 builds are tested on the Mac; check each game's note for device-specific validation.

For a game without a profile, the script writes a survey and tries a provisional build with guessed settings. That build may not start; see [Port another game](docs/development.md#port-another-game).

## How to play

Switch 2 games are built from one `.nup` file or a folder of their files, not from NSPs, and use the Mac workflow described in [Switch 2 games](#switch-2-games).

### Build from the command line

You need a Mac with macOS 26.6 or later, [Xcode](https://developer.apple.com/download/all/?q=Xcode%2027.2) 27.2, [Homebrew](https://brew.sh) and Python 3.12 or newer (an arm64 one, not an Intel Homebrew's). An iPhone build also needs Xcode's iOS platform (Xcode → Settings → Components).

The shaders are built with Xcode 27.2's Metal compiler. Select it before step 1: `sudo xcode-select -s /Applications/Xcode.app`. With several Xcode versions installed, name this one `Xcode-27.2.app` and select it with `sudo xcode-select -s /Applications/Xcode-27.2.app`.

**1. Install the tools** (only once), in Terminal:

```
xcodebuild -downloadComponent MetalToolchain
git clone https://github.com/seedds/nxnative.git && cd nxnative
brew install xcodegen zstd glslang
python3 -m pip install lz4 "capstone>=5,<6" fonttools nsz zbic "backports.zstd; python_version < '3.14'"
```

**2. Put your game in a folder**: the game, plus its update and DLC if you have them (`.nsp`, `.xci`, `.nsz` or `.xcz`):

```
~/Games/MarioWonder/
  Super Mario Bros. Wonder [010015100B514000][v0].nsp
  Super Mario Bros. Wonder [010015100B514800][v327680].nsp
```

**3. Build**, with your game folder and your `prod.keys`:

```
python3 scripts/build_ipa_from_nsp.py ~/Games/MarioWonder -k ~/keys/prod.keys
```

The IPA appears in the game's folder. The first build takes 30–60 minutes and needs free disk space of about twice the game's size plus 10 GB; building again is much faster.

To play on the Mac instead, add `--platform mac-app`: you get a Mac app of the game to open from Finder. All options: [The packing script in detail](docs/development.md#the-packing-script-in-detail).

### Install

Install the IPA on your iPhone or iPad with a sideloading tool such as AltStore, Sideloadly or LiveContainer. If your tool offers **Increased Memory Limit**, turn it on: the bigger games need it.

Game too big to install? Build again with `--romfs separate`, and run the command the script prints once to copy the game files to your phone ([Quick reinstalls](docs/development.md#quick-reinstalls)). With AltServer, also add `--shader-files`: it cannot install a file of 2 GiB or more.

Controls, saves and settings: [Playing](docs/playing.md).

### Switch 2 games

A Switch 2 game is built from one [NUP](https://github.com/a55uka/nup) container (a `.nup` file) or a folder of its files, not from NSPs. Neither needs `prod.keys`. A game this project has no profile for is surveyed and gets a provisional profile, as NSPs do ([Port another game](docs/development.md#port-another-game)), which may not boot. This upstream workflow builds a Mac app. See [TonTon device verification](#tonton-gamebox-game-fixes-and-verification) for the separately maintained mobile builds.

**From a `.nup` file**, which holds the base game, its updates and DLC in one file. Give the file, or a folder that holds it:

```
python3 scripts/build_ipa_from_nsp.py ~/Games/DonkeyKongBananza.nup --platform mac-app
```

[Hyrule Warriors: Age of Imprisonment](dm/games/04003F40232DE000/README.md) is played this way: its 47 GB NUP unpacks in under five minutes. A NUP that carries the game's control data (its NACP) and icon gives the app the game's name and icon; otherwise the name comes from the game's profile and the app has no icon unless you give it one with `--icon <image>` (`ICON` in Spyder; a JPEG or PNG of any size).

A NUP without the base game also works, when its base package is empty or it has none and its updates are marked `standalone_update`: the update is taken as the whole game, and the script says so. If the game then stops on missing files, that update holds only what changed: pack a NUP with the base game. The newest update is selected by default; `--package v<N>` selects another version in the container. Such a container has no `v0` (base game) to select.

**From a folder of files**. The script expects this layout (`updates` and `dlc` are optional):

```
~/Games/DonkeyKongBananza/
  base/exefs/                     main, main.npdm, sdk, rtld
  base/romfs/
  updates/458752/exefs/           the update's version, as a decimal number
  updates/458752/romfs/           the patched RomFS, not a patch
  dlc/040074a01bf13001/0/romfs/   the DLC's title ID
```

```
python3 scripts/build_ipa_from_nsp.py ~/Games/DonkeyKongBananza --platform mac-app
```

An update's folder alone will do (no `base/`), and so will `exefs/` and `romfs/` directly in the folder, as `nup extract` writes them, which count as `base/`. The app has no icon, because the folder holds none; `--icon <image>` (`ICON` in Spyder) gives it one. To turn such a folder into a NUP: `nup pack ~/Games/DonkeyKongBananza game.nup`.

## Discussions

Questions, how a game runs on your Mac or iPhone, and ideas go in [Discussions](https://github.com/seedds/nxnative/discussions); [Issues](https://github.com/seedds/nxnative/issues) are for bugs, with the log. Ocarina of Time's performance (frame rate, resolution, which Macs hold 60 fps) is followed in [Ocarina of Time: state on main](https://github.com/seedds/nxnative/discussions/1789).

## For developers

[How it works](docs/development.md) · [Game notes](dm/games/README.md#games) · [Bring-up and debugging](docs/agents/README.md) · [Front ends](docs/frontends.md) · [Contributing](CONTRIBUTING.md)

## Acknowledgements

This project is built on other people's work ([licenses](dm/third_party/README.md)):

- **[d2r-mobile](https://github.com/jhaizhou-ops/d2r-mobile)** (MIT) developed this native-execution approach, for Diablo II: Resurrected. nxnative started as a copy of its generic parts: the NSO rewriter, the host that stands in for Horizon, the NVN-on-Metal layer and the iOS app shell. Fixes go both ways.
- **Ryujinx** (MIT): its shader translator (`Ryujinx.Graphics.Shader`, `Ryujinx.Common` and `Spv.Generator` 1.3.2, in `dm/third_party/ryujinx` with a few fixes listed in [its README](dm/third_party/ryujinx/README.md)) turns the games' shaders into SPIR-V. Its emulation of the kernel and system services is also a reference when the host's behaviour is in doubt.
- **[Atmosphère](https://github.com/Atmosphere-NX/Atmosphere)**: its kernel, mesosphère, is the reference for Horizon's synchronization semantics (address arbiter, condition variables).
- **[LibHac](https://github.com/Thealexbarney/LibHac)**: reads NSPs and layers updates over the base game in `dm/tools/nx_extract`.
- **[SPIRV-Cross](https://github.com/KhronosGroup/SPIRV-Cross)**: SPIR-V to Metal Shading Language.
- **[glslang](https://github.com/KhronosGroup/glslang)** compiles the GLSL of OpenGL games to SPIR-V for it.
- **[MacNativeGames](https://github.com/ly05010419/MacNativeGames)** (MIT): the GPU widening of 8-bit indices and in-pass clears in `dm/gfx/nvn/nvn_mtl.m`, and the visibility-counter lowering in the shader translator.

## License

MIT ([LICENSE](LICENSE)). Third-party code keeps its own license ([dm/third_party](dm/third_party/README.md)).
