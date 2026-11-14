# Shared iOS game library host

The library builds **one host executable** for multiple Switch games. The
graphics, input, HLE and loader code is compiled once. Each game still has its
own patched guest program, profile and shader resources; the guest program is
placed in a distinct signed Mach-O section. Selecting a card chooses its
profile and data paths before the host starts.

`dm/ios/tools/library_embed.py` takes a local JSON manifest and generates
`game_profile.h`, `game_profile_runtime.c`, `embed.S` and `link-flags.txt`:

```json
{"games":[
  {"profile":"/absolute/path/to/0100000000000000/profile",
   "patched":"/absolute/path/to/that-games/patched-output"}
]}
```

The Xcode target compiles the generated registry and assembly with
`DM_LIBRARY_HOST=1`, includes `LibraryApp/Sources/main.m`, and uses the
generated link flags. It does not stage a particular game's `romfs.img`,
`msl` or `dm` directory inside the app bundle. Per-game files are stored at
`Documents/Games/<title-id>/Resources` and writable data at
`Documents/Games/<title-id>/UserData`.

`LocalCovers/` is Git ignored; any covers extracted from the owner's games
remain on that device or in its local build. Game resources, saves and signing
material must not be committed. The separate `NXGameLibrary` target remains a
UI-only prototype and is not evidence that the shared host can run a game.

`Sources/LibraryAppearance16.h` draws the same TonTon catalog with a
full-width artwork backdrop on phones and a split composition in landscape.
The artwork grid scrolls vertically, including on phones. Cover images fill
their cards at their original aspect ratio; the card crops any excess. Cover
selection updates the artwork and details; Play validates
the existing game before opening it. Long-press actions and controller
navigation still use the shared library implementation. iOS 26 or later
uses UIKit glass controls; the iOS 16.1 target uses standard button
configurations with the same layout.

The desktop launcher copies its selected hero and thumbnail images to the
paired Gamebox's `Documents/LibraryArtwork/<title-id>/` as `hero.jpg` and
`thumbnail.jpg`. This directory also accepts a shared `banner.jpg` and takes
priority over signed framework banners and cartridge icons. These transfers
do not rebuild games or write to game data or saves.

The **+** button imports an existing prepared game folder into that layout,
or moves a raw NSP/XCI/NSZ/NCA into `Documents/Imports` as a pending card.
Raw packages need the usual extraction, guest patching and shader build before
they can run. Adding an unregistered guest program also requires rebuilding
and signing the host app; the file picker alone cannot add executable code to
an already signed iOS binary.

The original shared host initializes process-wide profile and graphics state
once. An independent game host can return to the shelf in the same process
only if it implements [the optional teardown contract](../Engines/NxNative/README.md#independent-engine-return-to-the-library-air-6078).
