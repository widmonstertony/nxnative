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

The **+** button imports an existing prepared game folder into that layout,
or moves a raw NSP/XCI/NSZ/NCA into `Documents/Imports` as a pending card.
Raw packages need the usual extraction, guest patching and shader build before
they can run. Adding an unregistered guest program also requires rebuilding
and signing the host app; the file picker alone cannot add executable code to
an already signed iOS binary.

The same host cannot start a second game in the current process. The selected
profile and graphics state are process-wide and initialize once. A return to
the library and subsequent game switch needs a controlled host teardown or a
fresh process launch; the current card flow starts one game per app launch.
