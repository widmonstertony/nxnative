# Signed game frameworks in TonTon

TonTon adopts the game-image boundary of [NX2Apple Route C](https://github.com/LNPANDY/NX2Apple/tree/87c6b7fb93bb0a9fb4299ab27ae05d3012d8cca5/frontend-ios)
and patches 0045–0051. Attribution is retained in
`dm/ios/LibraryApp/NX2Apple-LICENSE`. The existing UIKit library remains usable
on iOS 16/17. NX2Apple's current Swift package requires iOS 26.

`build_game_framework.py` converts already rewritten modules to a signed
`DmGame<TITLEID>.framework`. It uses this fork's own `gen_embed.py`, signed
__TEXT layout and current shader-chain header. It does not change shader
translation or stamp older output as newer. Executable game code must be
embedded under the app's Frameworks directory and re-signed with the complete
app. An NSP in Documents is input for a Mac build, not executable code.

At launch, `LibraryFramework.h` validates schema, title, module order, loader,
minimum OS, shader chain and `tonton-signed-text-v1` ABI. It rejects packed NROs
until that route has a matching loader. All CPU module tables must also equal
the selected resource tables. The signed marker's actual image is selected
before host preload; host HLE tables remain in the app. Framework sections
need no cross-game namespace. The handle stays loaded for the process lifetime.
No code is loaded from writable Documents paths. A cartridge without a framework
continues using its existing signed embedded image.

Game assets, settings, logs and saves keep their existing per-title directories.
The framework's module tables and image go to the loader while shader paths
continue pointing at the selected cartridge's resources. New frameworks cannot
silently replace task-crash tracking or other exact-build CPU tables.

The first delivered adapter is NFS, built for iOS 16.1 and installed with the
Air 20261101.14 and M2 20261101.25 hosts. The full Xcode builds, framework
signature and identity gates pass. Existing saves and Arceus trace tables were
read back unchanged. Games were not automatically launched. Runtime framework
loading and audio improvement still need the owner's normal play session.
Other cartridges have not all been converted to frameworks. The existing
profile registry still limits which titles this host can launch; this change
alone does not turn it into an arbitrary-NSP interpreter.

Air's installed NFS metadata predates three timing annotation changes although
its six signed guest image/data sections exactly match the current framework.
The delivery retained Air's installed CPU tables byte for byte after comparing
all six sections, preserving its previous timing behavior. M2's tables match
the generated framework directly. No game assets or generated modules belong
in the source repository.
