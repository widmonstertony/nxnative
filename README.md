# nxnative — iOS 16 / iOS 17 compatibility

**Nintendo Switch native execution for iPhone and iPad, including an iOS/iPadOS 16.1+ legacy Metal backend.** This is [widmonstertony's compatibility fork](https://github.com/widmonstertony/nxnative). Its published fixes are on `main`; device work is also tracked on [`ios16-ios17-compat`](https://github.com/widmonstertony/nxnative/tree/ios16-ios17-compat). It retains the Metal 4 target for supported devices on iOS 26 or later.

Start with the **[iOS 16 / iOS 17 build and installation guide](docs/ios16-ios17.md)** and the **[device compatibility status](docs/fork-status.md)**. An older OS build target does not make every game compatible with every older GPU. The upstream gallery below includes Mac results and is not an iOS 16/17 compatibility list.

| Target | Minimum device OS | Renderer and scope |
|---|---|---|
| iOS 16 / iOS 17 compatibility | iOS / iPadOS **16.1** | Traditional Metal backend; strict per-game resource audit; A10X and M2 have different limits |
| Modern iPhone / iPad | iOS / iPadOS **26.0** | Explicit Metal 4 target; requires compatible hardware |
| Switch 2 | Per game and device | Targeted iPhone Air and M2 builds; see the play-test limits below |

The **[TonTon Mac build page](docs/ios16-ios17.md#build-in-tonton-gamebox-on-mac)** on `main` can build for iOS/iPadOS **16.1**, **17**, or **26 (Metal 4)** using the same game inputs, queue and live progress. Pick **M2 iPad** or the conservative GPU checks for a classic build. For classic targets, choose either a standalone export or **Install in existing TonTon Gamebox**. An in-place install uses a matching signing profile and the game data already on the device.

The former branch name was `ios16-pokemon-za-port`; it was renamed, preserving its history. **Source builds are available; this repository does not distribute ready-to-play games or a universal compatibility guarantee.**

The [Apple TV target](dm/tvos/README.md) includes a TV-native TonTon shelf, shared cover artwork, Remote and gamepad controls, per-title ABXY mapping, and private CloudKit save sync with an authorized profile. The shelf supports Pokémon Legends: Z-A and a separate native runtime for Pokémon Legends: Arceus 1.1.1. Returning to the TV shelf pauses the active game; the two titles retain separate local and CloudKit saves. Arceus was tested on physical Apple TV through the first 3D beach scene with an isolated save. Its TV startup fixes are documented in the [Arceus notes](dm/games/01001F5010DFA000/README.md).

Open **Build → Device builds and transfers** in the Mac Gamebox to filter registered jobs by iPhone, iPad, or Apple TV. Build rows show completed and remaining items; transfer rows use bytes. Compilation, verified delivery, installation, and playtesting are separate milestones. Archived checkpoints still show their recorded counts when matching build inputs are missing. Resume only runs the registered checkpoint controller with its existing build inputs, and a refresh only reads status. The native build and transfer queues remain on the same page.

## TonTon Gamebox: game fixes and verification

The [upstream optimization audit](docs/tonton-upstream-audit.md) covers every installed title and the new Fate/EXTELLA LINK request: upstream source coverage, classic-device backport boundaries, TonTon-only fixes, measured scenes and unresolved issues. The audit now includes upstream through `df9ca262` (November 13): sparse-binding cache updates, dynamic-resolution MetalFX input ranges, GL/Vulkan texture-lifetime repairs, and geometry/tessellation fixes. Source integration is distinct from device installation. The classic frame-step controller also has a targeted upstream backport, with 86 simulated timing checks passing; installation and performance validation are pending.

The [iOS feature deployment matrix](docs/tonton-upstream-audit.md#ios-shell-functions-november-13) records the NX2Apple snapshot, return-to-library boundary, controller/menu features and remaining device checks. The Air glass update pairs the new bookshelf with the safe return menu in Fate/EXTELLA LINK. Older engines do not acquire teardown support merely from a shell update. On the M2 and older iPad, the classic engine still needs its own safe teardown of guest threads, audio and GPU work before it can return to the library and launch another game.

The TonTon bookshelf follows the iOS appearance or an explicit light/dark
choice. It uses native Liquid Glass controls on iOS 26/27 and system
buttons on iOS/iPadOS 16.1. The modern independent host's game menu can
return to the same library process after teardown; see the
[engine integration and validation limits](dm/ios/Engines/NxNative/README.md#independent-engine-return-to-the-library-air-6078).

Air 60.81 was installed over 60.79 and opened on the device. The refreshed
catalog reported all 27 games ready. The update reused 25 signed frameworks,
rebuilt only the Fate/EXTELLA LINK framework and the affected shell objects,
and transferred no game images or retail payloads. Fate's return-to-library
action is included; the in-game quit and relaunch still need a player check.

The TonTon library uses a vertical collection on phones and a Mac-style
layout on roomy iPad windows: a large artwork banner above the library,
with Play and per-game settings on the banner. Compact iPad windows adapt
to the space available. Cover art fills the 16:9 cards just as on the Mac. The paired Mac launcher
can send its chosen cover to the device without rebuilding or resending the game.
The iOS 16.1 deployment target uses these layouts with system button
materials; supported iOS versions use Liquid Glass. See the [library build
and integration notes](dm/ios/LibraryApp/README.md).

Air 60.84 and M2 60.107 on iPadOS 16.1 received the vertical shelf and shared
artwork lookup in place. Twenty-four Switch title banners were verified on
both devices. Air's Fate/EXTELLA LINK independent framework also reads the
current virtual-button layout format and applies the touch ABXY mapping;
in-game control retesting remains open.

The Air Metal 4 build now compiles the device-scope memory fences used by
Fate/EXTELLA with Metal 4 while keeping the classic iOS shader target
unchanged. The original 1.0.0 cartridge passed all 619 shader builds and
linked a separate signed engine for the existing Gamebox. Its cartridge
language flags omit Traditional Chinese, but its resource archive contains
Traditional Chinese fonts and interface assets; in-game language and
rendering still require device testing. A separate 1.0.2 Fate/EXTELLA LINK
cartridge matched the installed build's resource image and all 58 DLC
images byte for byte, so the Air only needed its per-game language preference
changed to Traditional Chinese.

For the original Fate/EXTELLA, Air's cartridge icon was present but the
bookshelf had no artwork entry. The thumbnail was restored and read back
from Air. The iOS card now falls back to the cartridge icon when no custom
artwork or framework banner is available.

The original [Fate/EXTELLA profile](dm/games/010053E002EA2000/README.md)
reserves room for guarded thread stacks. A second Air startup trace showed
that its early SDK ignored the larger range because it used hardcoded address
bounds. The host now gives this SDK the actual alias and stack ranges. This
reuses the game image and shaders. The player confirmed Air 60.90 now reaches
the title or game. On the modern iOS host, Fate/EXTELLA LINK starts in the 3D touch
layout with a directional pad. Its layout choice is saved separately.

Add each published game fix here with its affected device, what changed, and
the deepest scene actually verified. A signed install or a successful shader
build is not a gameplay pass. Keep earlier observations in the
[device history](docs/fork-status.md) and exact backports in the
[engine notes](dm/ios/Engines/NxNative/README.md).

November 17 M2 / iPadOS 16.1 verification: the original-chain continuation
completed its queued 8,306 Tears of the Kingdom and 10,391 Fate/Samurai
Remnant keys without replacing ROMs or original saves. Tears of the Kingdom
reached the underground stairs with Link, Zelda and the environment visible;
Link moved using the isolated controller. Samurai reached its first assassin
battle at about 30 FPS after the installed Half2 adapter was enabled and 14
missing shader groups plus one hash-bound vertex-source companion were
supplied. Five additional cutscene groups were subsequently installed and
read-back verified; their new scene retest is pending. Buffer-texture,
texture-type and integer-vertex warnings remain. These are bounded scene
checks, not full-library recovery or stable 60 FPS results. Conservative
original-profile identities are retained for normal shelf launches, using
full exclusive C1 banks without CB narrowing; they do not certify complete
shader coverage. [Checkpoint details](docs/fork-status.md#m2-original-chain-recovery--2026-11-17).
Ocarina 60.128 still faults the GPU at the first controllable village scene;
reducing deferred-release pressure did not fix the invalid access. See the
[open device finding](dm/games/0400486024DEC000/README.md#fork-m2-ipados-161-checkpoint-2026-11-17).

The [November 21 launch audit](docs/fork-status.md#ipad-launch-audit--2026-11-21)
records the remaining A10X and M2 blockers. Classic Metal fixes for Pokkén's
encoder-ordering assertion and Need for Speed's transient-texture crash pass
the local GPU regression. The [November 22 integration notes](docs/fork-status.md#upstream-integration-and-ipad-crash-fixes--2026-11-22)
list the upstream changes and pending device tests.

Air build 60.61 defaults compatible native Switch games to handheld mode and
MetalFX spatial upscaling, with a per-game override. Handheld mode leaves the
render size to each game. The compatibility renderer also has a classic
MetalFX path. M2 Pokopia 60.94 and MKW 60.101 have device evidence below; this
is not a claim that every iPad title has been validated.

Air 60.72 adds a build-checked Pokopia scene-resolution cap. The actual
Air run confirmed the 720p cap executed, but the user still reported stutter
and audio underruns. The later 540p plus MetalFX run confirmed the cap;
the player reported less stutter but persistent crackling. Per-game settings
expose 720p/540p/original. Disabling render-thread real-time scheduling
was tested and did not eliminate crackling. The later Air 60.74 player retest reported smooth play and normal audio; cold-load and broader scene coverage remain open.
[Resolution findings](dm/games/0400A3A01EE4C000/README.md#tonton-air-scene-resolution-cap-v327680)
distinguish internal scene size from 1080p buffers and final output. This is
not a claim that every title has a tested 720p/540p render path.

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
Kart race stability and frame rate remain open. The old iPad's Kart game data and runtime resources are present; its library now reports ready, but launch and rendering still need validation.

On November 12, the old iPad received the missing 498 MB legacy Kart shader
image and runtime tables, with SHA-256 readback verification. Its existing
ROM identity, installed app and saves were preserved; this resource repair
has not yet been launch-tested. The [delivery notes](docs/tonton-delivery.md)
separate verified transfers from outstanding runtime work.

| Game | What this fork changed | Verified result and open issues |
| --- | --- | --- |
| Mario Kart World | Restored movie texture views, terrain uploads and sparse mappings; fixed black scenery with conditional clears; reduced upload and pipeline work; restored Air's 60 Hz pacing ([movie](https://github.com/widmonstertony/nxnative/commit/3d0a3a0), [clears](https://github.com/widmonstertony/nxnative/commit/381ed5f), [upload cache](https://github.com/widmonstertony/nxnative/commit/e221694), [pacing](https://github.com/widmonstertony/nxnative/commit/e847a4c)) | M2 60.105 on iPadOS 16.1 ran a 50cc race with 540p scene attachments and MetalFX. Observed race windows stayed around 46–50 FPS; cold-load stutter and the warm-manifest fault remain open. The retained-host update did not resend the game body or modify saves. No new Air race result. [Device evidence and limits](dm/games/0400C3F00006E000/README.md#tonton-ipad-compatibility-validation-2026-11-12). |
| Zelda: Ocarina of Time | Corrected opening movie decoding on Metal 3 and handled the offline play-report request that aborted at the end of the opening ([movie](https://github.com/widmonstertony/nxnative/commit/4f25737), [M2](https://github.com/widmonstertony/nxnative/commit/ed552f8), [Air](https://github.com/widmonstertony/nxnative/commit/4ecd063)). A scoped [M2 native pacing patch](dm/ios/Engines/NxNative/README.md#ocarina-of-time-native-frame-pacing-m2-6090-candidate) prevents the game from inheriting uncapped 120 Hz presentation. | M2 60.62 reaches the save list, but loading the forest save still faults in a GPU render pass. The Air fix is installed; completion of the affected section has not been reverified by the player. The signed 60.90 pacing candidate still awaits installation and a gameplay timing check. |
| Zelda: Tears of the Kingdom | Restored missing shared-font assets; exposed a real 3D render-scale control and corrected the FPS overlay toggle for data-only games ([controls](https://github.com/widmonstertony/nxnative/commit/86e676d), [overlay](https://github.com/widmonstertony/nxnative/commit/acb19b6)) | Air player confirmed the game opened and later reported less stutter and no FPS overlay. Sustained 60 fps has not been verified. |
| Pokémon Violet | Restored the shared fonts and offline Pokémon GO Plus + startup; on legacy Metal, bound the existing iPad game framework to its validated shader chain and supplied the matching raster and image-atomic companions. | M2 60.84 is installed with the existing 4.0.0 ROM and saves verified unchanged. The legacy character capture binding is included; the post-load scene still needs verification. See the [device test notes](dm/games/01008F6008C5E000/README.md#m2-ipad-update-400) for the scope of verification. Air title entry still needs a player retest. The [uncapped timing candidate](dm/games/01008F6008C5E000/README.md#m2-ipad-uncapped-render-timing-candidate) passed local clock tests; device gameplay is pending. |
| Pokémon Legends: Z-A, Switch 2 Edition | Bound the newer transform-feedback parameters on legacy Metal without changing shaders using the old ABI. Earlier repairs filled missing Metal 3 shader variants and added a Metal 4 compute archive path ([shader loading](https://github.com/widmonstertony/nxnative/commit/2d1396b), [pipeline cache](https://github.com/widmonstertony/nxnative/commit/d24d7c2)) | M2 build 60.82 restored the third-person player model in the same hotel room and save where 60.81 omitted it. Camera rotation and player movement were checked on the device; later city scenes were not part of this check. The uncapped timing path has a local regression test; player movement speed in the reported scene still needs an A/B check. M2 60.104 on iPadOS 16.1 also passed an [in-place compatibility build smoke test](dm/games/0100F43008C44000/README.md#ipados-161-m2-compatibility-build). |
| Hyrule Warriors: Age of Imprisonment | New build uses the upstream field and shader fixes below. | The Air shader build and signed candidate are complete locally. The full game image has not been imported or launched on Air. |
| Fate/Samurai Remnant | Resumable shader compilation and validated transfer batches. CoreDevice inventory omissions are resolved by named-file SHA-256 readbacks instead of treating a missing row as permission to resend existing resources. | Air completed all 77,671 shaders on the existing chain on November 12. Interrupted 2,350-file and 2,334-file transfer checkpoints passed full readback without retransmission. Final runtime tables and the 6.13 GB shader image are complete and fully read back. Air 60.72 reports ready / can open; gameplay remains for the user to check. |
| Crisis Core: Final Fantasy VII Reunion | Adjusted Air address-space reservation and added an M2 renderer repair for buffer atomics. | Air reached the title and later passed the previously crashing scene, with stutter reported. On M2, 20 runtime components were installed and read back with the existing ROM and saves intact; gameplay on that build is unverified. |
| Animal Crossing: New Horizons | Restored the missing M2 runtime components for the existing game data. | Eight runtime components were installed and read back on M2; gameplay on that build is unverified. The Air player confirmed the title launched. |
| Pokkén Tournament DX | Repaired the old iPad's rendering path for its existing installation. | Old iPad 60.97 reached the training HUD; fighters were still missing. This is not a gameplay pass. |
| NieR:Automata | Tracked separately on the legacy renderer. | Old iPad game data is present; the A10X runtime is still missing. |
| Pokémon Pokopia | Added a build-checked scene cap, priority bands and the independent iPad classic MetalFX path; restored missing graphics libraries and fixed Switch 2 virtual microphone enumeration ([service fix](https://github.com/widmonstertony/nxnative/commit/646c4ab)) | Air 60.74 player retest reported smooth gameplay and normal sound at the retained 540p cap with MetalFX. M2 60.94 first-map tutorial measured 55.4–60 FPS; cold pipeline stalls and character-preview rendering defects remain open. |
| The Witcher 3 | Repaired Air startup after tracing the executable's address-space reservation; verified the exact installed framework ([Air repair](https://github.com/widmonstertony/nxnative/commit/33b0df4)) | Air player confirmed title/game entry. M2 character materials still render incorrectly in some scenes. |
| Naruto Shippuden: Ultimate Ninja Storm 4 | Fixed the OpenGL ES startup path, framebuffer queries, and NVN/GL texture and fence sharing ([startup](https://github.com/widmonstertony/nxnative/commit/f691081), [framebuffer](https://github.com/widmonstertony/nxnative/commit/2eddd56), [texture sharing](https://github.com/widmonstertony/nxnative/commit/175301f)) | Air player reached battle on one build. Later reports of black characters and another battle-entry crash are still open. |
| Fate visual novels | Repaired native OpenGL framebuffer entry points needed during story initialization ([framebuffer aliases](https://github.com/widmonstertony/nxnative/commit/845c721)) | Air player verified both title screens display at the correct size and Hollow Ataraxia can enter the story. This does not cover the rest of each title. |
| Need for Speed Hot Pursuit Remastered | Fixed initial texture content, race button mapping, audio buffering and elapsed game time ([textures](https://github.com/widmonstertony/nxnative/commit/ffed898), [input and audio](https://github.com/widmonstertony/nxnative/commit/16cecc6), [timing](https://github.com/widmonstertony/nxnative/commit/d59fd00)) | Device gameplay confirmed; no long race performance guarantee. |
| Fate/EXTELLA: The Umbral Star | The host maps the original SDK’s alias and stack allocators to the actual guest memory ranges. Classic Metal keeps depth and stencil textures out of its linear texture paths. The original game image and shader chain are reused. | Air 60.90: the player confirmed title or game entry. M2 60.110 on iPadOS 16.1: launched from the existing Gamebox and reached the title menu with visible graphics. In-game language, combat and return to the shelf were outside this check. [Game notes](dm/games/010053E002EA2000/README.md) |
| Fate/EXTELLA LINK | 1.0.2 + 58 DLC; independent Metal 4 and iPadOS 16.1 hosts. Restored the classic shader directory and 11 matching triangle-draw variants on M2. | M2 60.108: launched from the shelf on iPadOS 16.1, restored visible graphics and reached the Traditional Chinese first-launch save prompt. No save was created and combat was not tested. Air has a game-specific return-to-library engine; the quit and launch-next-game flow still needs device testing. |
| Witch on the Holy Night; Tsukihime; STEINS;GATE RE:BOOT; the two Ladies FMV games; Everyday Today’s MENU for EMIYA Family | Retained engines, resource/import or startup fixes where applicable. Upstream title-profile availability varies. | See the [complete title audit](docs/tonton-upstream-audit.md#every-installed-title-plus-the-new-fate-request) for individual tests, missing components, language selection and open defects. |
| GTA V | Uses the Gamebox mode picker with the separate native iPadOS 16 engine ([mode picker](https://github.com/widmonstertony/nxnative/commit/421e5cd)) | Air player confirmed gameplay and access to per-game settings. |
| Red Alert 2 and Yuri's Revenge | Added native entry and touch controls: tap for left click, drag to select, two-finger tap for right click ([touch](https://github.com/widmonstertony/nxnative/commit/3cd0d50)) | Old iPad testing confirmed map interaction in the original app. The updated signed Gamebox on that device requires the retail-resource restoration before it can be retested. |

### TonTon ports without a title-specific upstream profile

At the audited upstream snapshot, the following titles have no dedicated upstream
profile. Their TonTon support, local repairs and unresolved defects are recorded
in the table above and [the per-title audit](docs/tonton-upstream-audit.md#every-installed-title-plus-the-new-fate-request):

- Fate/Samurai Remnant; Fate/EXTELLA LINK; Crisis Core: Final Fantasy VII Reunion.
- Naruto Shippuden: Ultimate Ninja Storm 4; The Witcher 3; Pokkén Tournament DX.
- Fate/stay night REMASTERED; Fate/hollow ataraxia REMASTERED; Witch on the Holy Night; Tsukihime -A piece of blue glass moon-.
- Everyday Today’s MENU for EMIYA Family; Knowledge, or Know Lady; Ladies, Don’t Tempt My Immortality.

Shared engine improvements can still apply to these games. A missing profile is
not a claim that upstream has no useful optimization, and a TonTon entry does
not imply that all devices or all scenes pass. GTA V, Red Alert 2 and Yuri’s
Revenge use separate native engines and are tracked independently of the
nxnative renderer.

Library changes include [private CloudKit save transport](https://github.com/widmonstertony/nxnative/commit/4fe54cb),
[independent game engines](https://github.com/widmonstertony/nxnative/commit/2798a14),
[verified single-file shader images](https://github.com/widmonstertony/nxnative/commit/b51852e),
and [Air game-paced presentation](https://github.com/widmonstertony/nxnative/commit/75f30d7).
CloudKit cross-platform delivery is tracked separately from code integration:
the Mac and Apple TV builds must use the same private container and environment
as the mobile builds, and live save exchange on those devices remains to be verified.

Play your own Nintendo Switch and Switch 2 games natively on Apple silicon Macs, iPhone and iPad. One script packs your game into a Mac app or an unsigned IPA that you sideload.

It is not an emulator: the game's own code runs directly on the Apple chip, with Switch graphics rebuilt on Metal. Nothing from any game is in this repository, and the project is not affiliated with Nintendo or any game publisher.

[Games](#games) · [Community front ends](#community-front-ends) · [Requirements](#requirements) · [How to play](#how-to-play) · [Discussions](#discussions) · [For developers](#for-developers)

## Games

The full [tested games table](dm/games/README.md#games) includes original Switch games, tested builds, engines and graphics APIs. Each game's note records its tested platforms, progress and known issues.

These Switch 2 games have passed Mac gameplay testing. Build them from a [`.nup` file or a dump folder](#switch-2-games):

- [Donkey Kong Bananza](dm/games/040074A01BF12000/README.md)
- [Fast Fusion](dm/games/040041E0212AE000/README.md)
- [Fire Emblem Fortune's Weave](dm/games/04007EF01F8AE000/README.md) — up to 120 fps
- [Hyrule Warriors: Age of Imprisonment](dm/games/04003F40232DE000/README.md)
- [Kirby Air Riders](dm/games/040077201BE50000/README.md)
- [Mario Kart World](dm/games/0400C3F00006E000/README.md)
- [Mario Tennis Fever](dm/games/0400D4201C6EA000/README.md)
- [Nintendo Switch 2 Welcome Tour](dm/games/040057C02159A000/README.md) — Area A tested; exhibits need further testing
- [Nintendo Switch Sports Resort](dm/games/04008E001F098000/README.md)
- [Orbitals](dm/games/040032B023CA4000/README.md) — two players: a controller for player 2
- [Pokémon Pokopia](dm/games/0400A3A01EE4C000/README.md)
- [PRAGMATA](dm/games/0400C76024710000/README.md)
- [Splatoon Raiders](dm/games/0400380020056000/README.md)
- [Star Fox](dm/games/0400E88025B1A000/README.md)
- [Super Mario Bros. Wonder – Nintendo Switch 2 Edition + Meetup in Bellabel Park](dm/games/040015100B514001/README.md)
- [The Legend of Zelda: Ocarina of Time](dm/games/0400486024DEC000/README.md)
- [Yoshi and the Mysterious Book](dm/games/0400245021D2C000/README.md)

## Community front ends

Community projects build on nxnative with tools to turn your games into apps for your iPhone, iPad or Mac without the command line, and libraries to organize and launch them. They are separate projects: questions and bugs about them go to their own pages.

- [NX2Apple](https://github.com/LNPANDY/NX2Apple) — Mac builder with a shared iPhone/iPad game library.
- [NX Play](https://github.com/varyform/nx-native-wrapper) — Mac library with device installs and save sync.
- [NxNative Launcher](https://github.com/rennan101us/nxnative_Launcher) — Mac launcher with guided builds and controller mapping.
- [nxnative Easy](https://github.com/nalancer08/nxnative-easy) — Mac game library with guided builds, iPhone and iPad installation and signature renewal, and iCloud save sync.
- [LumaNX](https://github.com/Xc1Ym/LumaNX) — Mac game builder with IPA export.
- [GameCase](https://github.com/Tiaoge-tou/GameCase) — iOS game library based on LiveContainer.

## Requirements

- **Mac:** Apple silicon, macOS 26.6 or later. Building games requires Xcode 27.2.
- **iPhone:** A17 Pro chip or later, with iOS 26 or later.
- **iPad:** M1 chip or later, with iPadOS 26 or later.

The games' textures are BC-compressed, which older iPhones cannot read. Switch 2 builds are tested on the Mac; check each game's note for device-specific validation.

For a game without a profile, the script writes a survey and tries a provisional build with guessed settings. That build may not start; see [Port another game](docs/development.md#port-another-game).

## How to play

For a Switch 2 game, follow the [Switch 2 build instructions](#switch-2-games) with a `.nup` file or a dump folder.

### Build from the command line

You need a Mac with macOS 26.6 or later, [Xcode](https://developer.apple.com/download/all/?q=Xcode%2027.2) 27.2, [Homebrew](https://brew.sh) and an arm64 build of Python 3.12 or newer. To build an IPA, install Xcode's iOS platform (Xcode → Settings → Components).

The shaders are built with Xcode 27.2's Metal compiler. Select it before step 1: `sudo xcode-select -s /Applications/Xcode.app`. With several Xcode versions installed, name this one `Xcode-27.2.app` and select it with `sudo xcode-select -s /Applications/Xcode-27.2.app`.

**1. Install the tools** (only once), in Terminal:

```
xcodebuild -downloadComponent MetalToolchain
git clone --branch ios16-ios17-compat https://github.com/widmonstertony/nxnative.git
cd nxnative
brew install xcodegen zstd glslang
python3 -m pip install lz4 "capstone>=5,<6" fonttools nsz zbic "backports.zstd; python_version < '3.14'"
```

**2. Put your Switch 1 game in a folder.** Include any updates and DLC you want to pack. The script reads `.nsp`, `.xci`, `.nsz` and `.xcz` files.

```
~/Games/MarioWonder/
  Super Mario Bros. Wonder [010015100B514000][v0].nsp
  Super Mario Bros. Wonder [010015100B514800][v327680].nsp
```

**3. Build**, with your game folder and your `prod.keys`:

```
DM_IOS_RENDERER=legacy DM_LEGACY_TARGET=a10x \
  python3 scripts/build_ipa_from_nsp.py ~/Games/MarioWonder -k ~/keys/prod.keys --gpu none
```

For the tested M2 iPad capability target, use `DM_LEGACY_TARGET=m2`; do not select it for A10X. For a modern build, select `DM_IOS_RENDERER=metal4` explicitly. See the [compatibility guide](docs/ios16-ios17.md) before choosing a target.

The IPA appears in the game's folder only after all build and resource checks pass. Allow at least twice the game's size plus 10 GB of free build space; large shader sets can take several hours. Building again can reuse matching caches.

For a Mac app, add `--platform mac-app` and open the resulting `.app` in Finder. By default, the script saves the IPA or Mac app in the game's folder. See [The packing script in detail](docs/development.md#the-packing-script-in-detail) for all options.

The first build takes 30–60 minutes and needs about twice the game's size plus 10 GB of free disk space. Rebuilding is much faster.

### Install

Install the IPA on your iPhone or iPad with a sideloading tool such as AltStore, Sideloadly or LiveContainer. If your tool offers **Increased Memory Limit**, turn it on: the bigger games need it.

Game too big to install? Build again with `--romfs separate`, and run the command the script prints once to copy the game files to your phone ([Quick reinstalls](docs/development.md#quick-reinstalls)). With AltServer, also add `--shader-files`: it cannot install a file of 2 GiB or more.

If a sideloading tool fails to extract a large IPA, try `--prepare-xcode` and [install from Xcode](docs/development.md#build-and-run-on-a-device-with-xcode).

Controls, saves and settings: [Playing](docs/playing.md).

### Switch 2 games

Build a Switch 2 game from one [NUP](https://github.com/a55uka/nup) container (a `.nup` file) or a dump folder. Both inputs work without `prod.keys`. If the game has no profile in this project, the script surveys it and creates a provisional profile. The resulting build may fail to boot. See [Port another game](docs/development.md#port-another-game).

**From a `.nup` file**, which holds the base game, its updates and DLC in one file. Give the file, or a folder that holds it:

```
python3 scripts/build_ipa_from_nsp.py ~/Games/DonkeyKongBananza.nup --platform mac-app
```

[Hyrule Warriors: Age of Imprisonment](dm/games/04003F40232DE000/README.md) is played this way: its 47 GB NUP unpacks in under five minutes. A NUP that carries the game's control data (its NACP) and icon gives the app the game's name and icon; otherwise the name comes from the game's profile and the app has no icon unless you give it one with `--icon <image>` (`ICON` in Spyder; a JPEG or PNG of any size). The script also reads [NUPs with shifted metadata numbers](docs/reference/packing.md#a-nup-icon-is-written-as-control-data).

A Nintendo Switch 2 Edition of a Switch 1 game can hold both of its programs in one NUP: the Switch 1 program with the game data, and the Switch 2 program, which reads that data from the Switch 1 program and its Switch 2 files from the upgrade add-on. The script packs the Switch 2 program, with the Switch 1 program's game files beside its own and the add-on as DLC; `--program 0` packs the Switch 1 program instead.

A NUP without the base game can have an empty base record or omit the base record entirely. With no base record, every update must be marked `standalone_update`. In either case, the script reports that it is using the selected update as the whole game. That update needs a complete ExeFS and RomFS. If files are missing, pack a NUP with the base game. The script selects the newest update by default. Use `--package v<N>` to select another update. `v0` requires a base game.

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

You can also pass a complete update folder directly, for example `~/Games/DonkeyKongBananza/updates/458752`. The script treats a folder with `exefs/` and `romfs/` at its root as `base/`, including folders made by `nup extract`. Use `--icon <image>` (`ICON` in Spyder) to supply an icon for the app. To turn a dump folder into a NUP, run `nup pack ~/Games/DonkeyKongBananza game.nup`. See [The packing script in detail](docs/development.md#the-packing-script-in-detail) for more options.

## Discussions

Use [Discussions](https://github.com/seedds/nxnative/discussions) for questions, ideas and reports on how games run on your Mac or iPhone. File bug reports in [Issues](https://github.com/seedds/nxnative/issues) and include the log. Follow frame rate, resolution and which Macs hold 60 fps in [Ocarina of Time: state on main](https://github.com/seedds/nxnative/discussions/1789).

Upstream games tested on Mac or iPhone; these results do not certify the legacy target. See the [fork device status](docs/fork-status.md) and the [per-game notes](dm/games/README.md#games) for tested platforms, progress and known issues:

The upstream modern path targets iOS / iPadOS 26 or later and compatible hardware. This fork additionally builds for iOS / iPadOS 16.1 and 17 with a separate legacy backend, BC texture handling and verified shader companions. Layered rendering, sampler limits and image atomics still restrict individual games on older GPUs. A provisional IPA for an unregistered game may not start.

- **Pokémon Violet, legacy iPad:** the shader translator and runtime now accept the read-only border colour block and its matching sampler in the fragment shader that performs an unsigned image atomic max. The original shader compiled for iPadOS 16.1 and its bindings passed the runtime parser on Mac. Device installation and gameplay verification for this change are still pending.

Under a game, "60 fps with 1.2.0" means it runs at 60 fps (30 on the Switch) with that update.

<!-- gallery: written by dm/tools/docs_gallery.py from docs/images/gallery.tsv; change the table, then run it -->
<table>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/donkey-kong-bananza.jpg" width="256" alt="Donkey Kong Bananza"><br><small><b><a href="dm/games/040074A01BF12000/README.md">Donkey Kong Bananza</a></b><br>Switch 2, Mac only, from a dump</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-kart-8-deluxe.jpg" width="256" alt="Mario Kart 8 Deluxe"><br><small><b><a href="dm/games/0100152000022000/README.md">Mario Kart 8 Deluxe</a></b><br>no Mii heads</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-vs-donkey-kong.jpg" width="256" alt="Mario vs. Donkey Kong"><br><small><b><a href="dm/games/0100B99019412000/README.md">Mario vs. Donkey Kong</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/paper-mario-the-thousand-year-door.jpg" width="256" alt="Paper Mario: The Thousand-Year Door"><br><small><b><a href="dm/games/0100ECD018EBE000/README.md">Paper Mario: The Thousand-Year Door</a></b><br>60 fps with 1.0.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-3d-world.jpg" width="256" alt="Super Mario 3D World + Bowser's Fury"><br><small><b><a href="dm/games/010028600EBDA000/README.md">Super Mario 3D World + Bowser's Fury</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-bros-wonder.jpg" width="256" alt="Super Mario Bros. Wonder"><br><small><b><a href="dm/games/010015100B514000/README.md">Super Mario Bros. Wonder</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-galaxy.jpg" width="256" alt="Super Mario Galaxy"><br><small><b><a href="dm/games/010099C022B96000/README.md">Super Mario Galaxy</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-galaxy-2.jpg" width="256" alt="Super Mario Galaxy 2"><br><small><b><a href="dm/games/0100FD8022DAA000/README.md">Super Mario Galaxy 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-odyssey.jpg" width="256" alt="Super Mario Odyssey"><br><small><b><a href="dm/games/0100000000010000/README.md">Super Mario Odyssey</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-breath-of-the-wild.jpg" width="256" alt="The Legend of Zelda: Breath of the Wild"><br><small><b><a href="dm/games/01007EF00011E000/README.md">The Legend of Zelda: Breath of the Wild</a></b><br>60 fps with 1.9.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-links-awakening.jpg" width="256" alt="The Legend of Zelda: Link's Awakening"><br><small><b><a href="dm/games/01006BB00C6F0000/README.md">The Legend of Zelda: Link's Awakening</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-tears-of-the-kingdom.jpg" width="256" alt="The Legend of Zelda: Tears of the Kingdom"><br><small><b><a href="dm/games/0100F2C0115B6000/README.md">The Legend of Zelda: Tears of the Kingdom</a></b><br>60 fps with 1.4.3</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/13-sentinels.jpg" width="256" alt="13 Sentinels: Aegis Rim"><br><small><b><a href="dm/games/01003FC01670C000/README.md">13 Sentinels: Aegis Rim</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/absolum.jpg" width="256" alt="Absolum"><br><small><b><a href="dm/games/0100A83022A22000/README.md">Absolum</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ace-attorney-investigations.jpg" width="256" alt="Ace Attorney Investigations Collection"><br><small><b><a href="dm/games/010005501E68C000/README.md">Ace Attorney Investigations Collection</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/advance-wars-1-2-re-boot-camp.jpg" width="256" alt="Advance Wars 1+2: Re-Boot Camp"><br><small><b><a href="dm/games/0100300012F2A000/README.md">Advance Wars 1+2: Re-Boot Camp</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ai-the-somnium-files.jpg" width="256" alt="AI: THE SOMNIUM FILES"><br><small><b><a href="dm/games/010089B00D09C000/README.md">AI: THE SOMNIUM FILES</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ai-the-somnium-files-nirvana-initiative.jpg" width="256" alt="AI: THE SOMNIUM FILES - nirvanA Initiative"><br><small><b><a href="dm/games/0100713016CCC000/README.md">AI: THE SOMNIUM FILES - nirvanA Initiative</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/animal-crossing-new-horizons.jpg" width="256" alt="Animal Crossing: New Horizons"><br><small><b><a href="dm/games/01006F8002326000/README.md">Animal Crossing: New Horizons</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/animal-well.png" width="256" alt="ANIMAL WELL"><br><small><b><a href="dm/games/010020D01AD24000/README.md">ANIMAL WELL</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/astral-chain.png" width="256" alt="ASTRAL CHAIN"><br><small><b><a href="dm/games/01007300020FA000/README.md">ASTRAL CHAIN</a></b><br>60 fps target with 1.0.1</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/balatro.jpg" width="256" alt="Balatro"><br><small><b><a href="dm/games/0100CD801CE5E000/README.md">Balatro</a></b><br>played by touch</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ball-x-pit.jpg" width="256" alt="BALL x PIT"><br><small><b><a href="dm/games/010086A022444000/README.md">BALL x PIT</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/bayonetta.jpg" width="256" alt="Bayonetta"><br><small><b><a href="dm/games/010076F0049A2000/README.md">Bayonetta</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/bayonetta-2.jpg" width="256" alt="Bayonetta 2"><br><small><b><a href="dm/games/01007960049A0000/README.md">Bayonetta 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/bayonetta-3.jpg" width="256" alt="Bayonetta 3"><br><small><b><a href="dm/games/01004A4010FEA000/README.md">Bayonetta 3</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/big-brain-academy-brain-vs-brain.jpg" width="256" alt="Big Brain Academy: Brain vs. Brain"><br><small><b><a href="dm/games/0100620012D6E000/README.md">Big Brain Academy: Brain vs. Brain</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/brain-memory-training-academy.jpg" width="256" alt="Brain Memory Training Academy"><br><small><b><a href="dm/games/0100F5D01DA3A000/README.md">Brain Memory Training Academy</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/captain-toad-treasure-tracker.jpg" width="256" alt="Captain Toad: Treasure Tracker"><br><small><b><a href="dm/games/01009BF0072D4000/README.md">Captain Toad: Treasure Tracker</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/catherine-full-body.jpg" width="256" alt="Catherine: Full Body"><br><small><b><a href="dm/games/0100BF00112C0000/README.md">Catherine: Full Body</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/celeste.jpg" width="256" alt="Celeste"><br><small><b><a href="dm/games/01002B30028F6000/README.md">Celeste</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/cuphead.jpg" width="256" alt="Cuphead"><br><small><b><a href="dm/games/0100A5C00D162000/README.md">Cuphead</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/dark-souls-remastered-creation.jpg" width="256" alt="DARK SOULS: REMASTERED"><br><small><b><a href="dm/games/01004AB00A260000/README.md">DARK SOULS: REMASTERED</a></b><br>60 fps with 1.0.3</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/digimon-story-cyber-sleuth.jpg" width="256" alt="Digimon Story Cyber Sleuth: Complete Edition"><br><small><b><a href="dm/games/010014E00DB56000/README.md">Digimon Story Cyber Sleuth: Complete Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/donkey-kong-country-tropical-freeze.jpg" width="256" alt="Donkey Kong Country: Tropical Freeze"><br><small><b><a href="dm/games/0100C1F0051B6000/README.md">Donkey Kong Country: Tropical Freeze</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-vii-reimagined.jpg" width="256" alt="DRAGON QUEST VII Reimagined"><br><small><b><a href="dm/games/0100A9D01C446000/README.md">DRAGON QUEST VII Reimagined</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-xi-s.jpg" width="256" alt="DRAGON QUEST XI S: Echoes of an Elusive Age – Definitive Edition"><br><small><b><a href="dm/games/01006C300E9F0000/README.md">DRAGON QUEST XI S: Echoes of an Elusive Age – Definitive Edition</a></b><br>60 fps with 1.0.4</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-resonance.jpg" width="256" alt="FINAL FANTASY RESONANCE"><br><small><b><a href="dm/games/0100606026F12000/README.md">FINAL FANTASY RESONANCE</a></b><br>60 fps with 1.0.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-tactics.jpg" width="256" alt="FINAL FANTASY TACTICS - The Ivalice Chronicles"><br><small><b><a href="dm/games/010038B015560000/README.md">FINAL FANTASY TACTICS - The Ivalice Chronicles</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/fire-emblem-engage.jpg" width="256" alt="Fire Emblem Engage"><br><small><b><a href="dm/games/0100A6301214E000/README.md">Fire Emblem Engage</a></b><br>60 fps with 2.0.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/fire-emblem-three-houses.jpg" width="256" alt="Fire Emblem: Three Houses"><br><small><b><a href="dm/games/010055D009F78000/README.md">Fire Emblem: Three Houses</a></b><br>60 fps with 1.2.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ghost-trick-phantom-detective.jpg" width="256" alt="Ghost Trick: Phantom Detective"><br><small><b><a href="dm/games/010029B018432000/README.md">Ghost Trick: Phantom Detective</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/the-great-ace-attorney-chronicles.jpg" width="256" alt="The Great Ace Attorney Chronicles"><br><small><b><a href="dm/games/010036E00FB20000/README.md">The Great Ace Attorney Chronicles</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hades.jpg" width="256" alt="Hades"><br><small><b><a href="dm/games/0100535012974000/README.md">Hades</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hades-ii.jpg" width="256" alt="Hades II"><br><small><b><a href="dm/games/0100A00019DE0000/README.md">Hades II</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/hollow-knight-silksong.jpg" width="256" alt="Hollow Knight: Silksong"><br><small><b><a href="dm/games/010013C00E930000/README.md">Hollow Knight: Silksong</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hyrule-warriors-age-of-calamity.jpg" width="256" alt="Hyrule Warriors: Age of Calamity"><br><small><b><a href="dm/games/01002B00111A2000/README.md">Hyrule Warriors: Age of Calamity</a></b><br>60 fps with 1.3.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/kirby-and-the-forgotten-land.jpg" width="256" alt="Kirby and the Forgotten Land"><br><small><b><a href="dm/games/01004D300C5AE000/README.md">Kirby and the Forgotten Land</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/luigis-mansion-3.jpg" width="256" alt="Luigi's Mansion 3"><br><small><b><a href="dm/games/0100DCA0064A6000/README.md">Luigi's Mansion 3</a></b><br>60 fps with 1.4.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/metroid-dread.jpg" width="256" alt="Metroid Dread"><br><small><b><a href="dm/games/010093801237C000/README.md">Metroid Dread</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/monster-hunter-rise.jpg" width="256" alt="Monster Hunter Rise"><br><small><b><a href="dm/games/0100B04011742000/README.md">Monster Hunter Rise</a></b><br>60 fps with 16.0.2</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/monster-train-2.jpg" width="256" alt="Monster Train 2"><br><small><b><a href="dm/games/010051701FB46000/README.md">Monster Train 2</a></b><br>60 fps with 1.1.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/octopath-traveler.jpg" width="256" alt="OCTOPATH TRAVELER"><br><small><b><a href="dm/games/010057D006492000/README.md">OCTOPATH TRAVELER</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/octopath-traveler-0.jpg" width="256" alt="Octopath Traveler 0"><br><small><b><a href="dm/games/01005270232F2000/README.md">Octopath Traveler 0</a></b><br>60 fps with 1.0.5</small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/octopath-traveler-ii.jpg" width="256" alt="Octopath Traveler II"><br><small><b><a href="dm/games/0100A3501946E000/README.md">Octopath Traveler II</a></b><br>60 fps with 1.1.1</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/patricks-parabox.jpg" width="256" alt="Patrick's Parabox"><br><small><b><a href="dm/games/0100E44016C22000/README.md">Patrick's Parabox</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/persona-5-royal.jpg" width="256" alt="Persona 5 Royal"><br><small><b><a href="dm/games/01005CA01580E000/README.md">Persona 5 Royal</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/pikmin-4.jpg" width="256" alt="Pikmin 4"><br><small><b><a href="dm/games/0100B7C00933A000/README.md">Pikmin 4</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-brilliant-diamond.jpg" width="256" alt="Pokémon Brilliant Diamond"><br><small><b><a href="dm/games/0100000011D90000/README.md">Pokémon Brilliant Diamond</a></b><br>60 fps with 1.3.0</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-legends-z-a.jpg" width="256" alt="Pokémon Legends: Z-A"><br><small><b><a href="dm/games/0100F43008C44000/README.md">Pokémon Legends: Z-A</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-scarlet.png" width="256" alt="Pokémon Scarlet"><br><small><b><a href="dm/games/0100A3D008C5C000/README.md">Pokémon Scarlet</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-violet.jpg" width="256" alt="Pokémon Violet"><br><small><b><a href="dm/games/01008F6008C5E000/README.md">Pokémon Violet</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-sword.jpg" width="256" alt="Pokémon Sword"><br><small><b><a href="dm/games/0100ABF008968000/README.md">Pokémon Sword</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-shield.jpg" width="256" alt="Pokémon Shield"><br><small><b><a href="dm/games/01008DB008C2C000/README.md">Pokémon Shield</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/portal.jpg" width="256" alt="Portal"><br><small><b><a href="dm/games/01007BB017812000/README.md">Portal</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/raging-loop.jpg" width="256" alt="Raging Loop"><br><small><b><a href="dm/games/010020400E1C2000/README.md">Raging Loop</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/rhythm-heaven-groove.jpg" width="256" alt="Rhythm Heaven Groove"><br><small><b><a href="dm/games/0100D9F01D474000/README.md">Rhythm Heaven Groove</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/romance-of-the-three-kingdoms-8-remake.jpg" width="256" alt="ROMANCE OF THE THREE KINGDOMS 8 REMAKE"><br><small><b><a href="dm/games/0100C2A01A730000/README.md">ROMANCE OF THE THREE KINGDOMS 8 REMAKE</a></b><br>controller only</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/sea-of-stars.jpg" width="256" alt="Sea of Stars"><br><small><b><a href="dm/games/01008C0016544000/README.md">Sea of Stars</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/shin-megami-tensei-v-vengeance.jpg" width="256" alt="SHIN MEGAMI TENSEI V: Vengeance"><br><small><b><a href="dm/games/010069C01AB82000/README.md">SHIN MEGAMI TENSEI V: Vengeance</a></b><br>60 fps with 1.0.3</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/stardew-valley.jpg" width="256" alt="Stardew Valley"><br><small><b><a href="dm/games/0100E65002BB8000/README.md">Stardew Valley</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/steins-gate-reboot.jpg" width="256" alt="STEINS;GATE RE:BOOT"><br><small><b><a href="dm/games/01008BC024FDE000/README.md">STEINS;GATE RE:BOOT</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/super-smash-bros-ultimate.jpg" width="256" alt="Super Smash Bros. Ultimate"><br><small><b><a href="dm/games/01006A800016E000/README.md">Super Smash Bros. Ultimate</a></b><br>offline</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/taiko-risshiden-v-dx.jpg" width="256" alt="Taiko Risshiden V DX"><br><small><b><a href="dm/games/0100346017304000/README.md">Taiko Risshiden V DX</a></b><br>Japanese · played by touch</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/unicorn-overlord.jpg" width="256" alt="Unicorn Overlord"><br><small><b><a href="dm/games/010069401ADB8000/README.md">Unicorn Overlord</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/yoshis-crafted-world.jpg" width="256" alt="Yoshi's Crafted World"><br><small><b><a href="dm/games/01006000040C2000/README.md">Yoshi's Crafted World</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/nier-automata.png" width="256" alt="NieR:Automata The End of YoRHa Edition"><br><small><b><a href="dm/games/010056B015FE8000/README.md">NieR:Automata The End of YoRHa Edition</a></b><br>60 fps with 1.0.3</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/zelda-echoes-of-wisdom.jpg" width="256" alt="The Legend of Zelda: Echoes of Wisdom"><br><small><b><a href="dm/games/01008CF01BAAC000/README.md">The Legend of Zelda: Echoes of Wisdom</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/donkey-kong-country-returns-hd.png" width="256" alt="Donkey Kong Country Returns HD"><br><small><b><a href="dm/games/01009D901BC56000/README.md">Donkey Kong Country Returns HD</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-rabbids-sparks-of-hope.jpg" width="256" alt="Mario + Rabbids Sparks of Hope"><br><small><b><a href="dm/games/0100317013770000/README.md">Mario + Rabbids Sparks of Hope</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/xenoblade-chronicles-2.jpg" width="256" alt="Xenoblade Chronicles 2"><br><small><b><a href="dm/games/0100E95004038000/README.md">Xenoblade Chronicles 2</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/xenoblade-chronicles-3.jpg" width="256" alt="Xenoblade Chronicles 3"><br><small><b><a href="dm/games/010074F013262000/README.md">Xenoblade Chronicles 3</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-crystal-chronicles.jpg" width="256" alt="FINAL FANTASY CRYSTAL CHRONICLES Remastered Edition"><br><small><b><a href="dm/games/0100CE4010AAC000/README.md">FINAL FANTASY CRYSTAL CHRONICLES Remastered Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/return-of-the-obra-dinn.png" width="256" alt="Return of the Obra Dinn"><br><small><b><a href="dm/games/010032E00E6E2000/README.md">Return of the Obra Dinn</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/blasphemous-2.png" width="256" alt="Blasphemous 2"><br><small><b><a href="dm/games/010040801A4C8000/README.md">Blasphemous 2</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/silver-pines.jpg" width="256" alt="Silver Pines"><br><small><b><a href="dm/games/0100D5B026844000/README.md">Silver Pines</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/blasphemous.jpg" width="256" alt="Blasphemous"><br><small><b><a href="dm/games/0100698009C6E000/README.md">Blasphemous</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/final-fantasy-x-x2-hd-remaster.jpg" width="256" alt="FINAL FANTASY X/X-2 HD Remaster"><br><small><b><a href="dm/games/0100BC300CB48000/README.md">FINAL FANTASY X/X-2 HD Remaster</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-rabbids-kingdom-battle.jpg" width="256" alt="Mario + Rabbids Kingdom Battle"><br><small><b><a href="dm/games/010067300059A000/README.md">Mario + Rabbids Kingdom Battle</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/persona-4-golden.jpg" width="256" alt="Persona 4 Golden"><br><small><b><a href="dm/games/010062B01525C000/README.md">Persona 4 Golden</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/xenoblade-chronicles-definitive-edition.jpg" width="256" alt="Xenoblade Chronicles: Definitive Edition"><br><small><b><a href="dm/games/0100FF500E34A000/README.md">Xenoblade Chronicles: Definitive Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/pokemon-legends-arceus.jpg" width="256" alt="Pokémon Legends: Arceus"><br><small><b><a href="dm/games/01001F5010DFA000/README.md">Pokémon Legends: Arceus</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/super-mario-party-jamboree.jpg" width="256" alt="Super Mario Party Jamboree"><br><small><b><a href="dm/games/0100965017338000/README.md">Super Mario Party Jamboree</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/cult-of-the-lamb.jpg" width="256" alt="Cult of the Lamb"><br><small><b><a href="dm/games/01002E7016C46000/README.md">Cult of the Lamb</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/paper-mario-the-origami-king.jpg" width="256" alt="Paper Mario: The Origami King"><br><small><b><a href="dm/games/0100A3900C3E2000/README.md">Paper Mario: The Origami King</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/batman-arkham-knight.jpg" width="256" alt="Batman: Arkham Knight"><br><small><b><a href="dm/games/0100ACD0163D0000/README.md">Batman: Arkham Knight</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/bastion.jpg" width="256" alt="Bastion"><br><small><b><a href="dm/games/010038600B27E000/README.md">Bastion</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/baba-is-you.jpg" width="256" alt="Baba Is You"><br><small><b><a href="dm/games/01002CD00A51C000/README.md">Baba Is You</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-heist-ii.jpg" width="256" alt="SteamWorld Heist II"><br><small><b><a href="dm/games/010089C01E9CA000/README.md">SteamWorld Heist II</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-heist.jpg" width="256" alt="SteamWorld Heist: Ultimate Edition"><br><small><b><a href="dm/games/010016100A186000/README.md">SteamWorld Heist: Ultimate Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/subnautica-below-zero.jpg" width="256" alt="Subnautica: Below Zero"><br><small><b><a href="dm/games/010014C011146000/README.md">Subnautica: Below Zero</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-dig-2.jpg" width="256" alt="SteamWorld Dig 2"><br><small><b><a href="dm/games/0100CA9002322000/README.md">SteamWorld Dig 2</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/streets-of-rage-4.jpg" width="256" alt="Streets of Rage 4"><br><small><b><a href="dm/games/0100EC9010258000/README.md">Streets of Rage 4</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/mario-party-superstars.jpg" width="256" alt="Mario Party Superstars"><br><small><b><a href="dm/games/01006FE013472000/README.md">Mario Party Superstars</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/subnautica.jpg" width="256" alt="Subnautica"><br><small><b><a href="dm/games/0100429011144000/README.md">Subnautica</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/steamworld-dig.jpg" width="256" alt="SteamWorld Dig"><br><small><b><a href="dm/games/01009320084A4000/README.md">SteamWorld Dig</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/team-sonic-racing.jpg" width="256" alt="Team Sonic Racing"><br><small><b><a href="dm/games/010092B0091D0000/README.md">Team Sonic Racing</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/well-dweller.jpg" width="256" alt="Well Dweller"><br><small><b><a href="dm/games/0100217023F6C000/README.md">Well Dweller</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/need-for-speed-hot-pursuit-remastered.jpg" width="256" alt="Need for Speed: Hot Pursuit Remastered"><br><small><b><a href="dm/games/010029B0118E8000/README.md">Need for Speed: Hot Pursuit Remastered</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/ea-sports-fc-27.jpg" width="256" alt="EA SPORTS FC 27"><br><small><b><a href="dm/games/0100C49025D3E000/README.md">EA SPORTS FC 27</a></b><br>60 fps with 1.8d.310c</small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/portal-2.jpg" width="256" alt="Portal 2"><br><small><b><a href="dm/games/0100ABD01785C000/README.md">Portal 2</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/super-monkey-ball-banana-rumble.jpg" width="256" alt="Super Monkey Ball Banana Rumble"><br><small><b><a href="dm/games/010031F019294000/README.md">Super Monkey Ball Banana Rumble</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/atelier-ryza-dx.jpg" width="256" alt="Atelier Ryza: Ever Darkness &amp; the Secret Hideout DX"><br><small><b><a href="dm/games/0100199023B2E000/README.md">Atelier Ryza: Ever Darkness &amp; the Secret Hideout DX</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-iii-hd-2d-remake.jpg" width="256" alt="DRAGON QUEST III HD-2D Remake"><br><small><b><a href="dm/games/01003E601E324000/README.md">DRAGON QUEST III HD-2D Remake</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/hyrule-warriors-definitive-edition.jpg" width="256" alt="Hyrule Warriors: Definitive Edition"><br><small><b><a href="dm/games/0100AE00096EA000/README.md">Hyrule Warriors: Definitive Edition</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/metroid-prime-remastered.jpg" width="256" alt="Metroid Prime Remastered"><br><small><b><a href="dm/games/010012101468C000/README.md">Metroid Prime Remastered</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/dragon-quest-i-ii-hd-2d-remake.jpg" width="256" alt="DRAGON QUEST I &amp; II HD-2D Remake"><br><small><b><a href="dm/games/0100D7C01F254000/README.md">DRAGON QUEST I &amp; II HD-2D Remake</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/dead-cells.jpg" width="256" alt="Dead Cells"><br><small><b><a href="dm/games/0100646009FBE000/README.md">Dead Cells</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/hollow-knight.jpg" width="256" alt="Hollow Knight"><br><small><b><a href="dm/games/0100633007D48000/README.md">Hollow Knight</a></b></small></td>
<td align="center" valign="top" width="33%"><img src="docs/images/triangle-strategy.jpg" width="256" alt="TRIANGLE STRATEGY"><br><small><b><a href="dm/games/0100CC80140F8000/README.md">TRIANGLE STRATEGY</a></b></small></td>
</tr>
<tr>
<td align="center" valign="top" width="33%"><img src="docs/images/castlevania-belmonts-curse.jpg" width="256" alt="Castlevania: Belmont's Curse"><br><small><b><a href="dm/games/0100BA4026E94000/README.md">Castlevania: Belmont's Curse</a></b></small></td>
<td></td>
<td></td>
</tr>
</table>
<!-- end of gallery -->

### For developers
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
