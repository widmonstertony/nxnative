# TonTon desktop controls

## Reused upstream components

- [NX2Apple 2ff32201](https://github.com/LNPANDY/NX2Apple/tree/2ff32201cdfcc15a28ba96de3d29cf58fb7f7a29): patch 0003's `input_map.h`, parser regression suite and `NXCore/ControllerMap.swift`. The Mac frontend uses its ordered `DM_KEYMAP` and `DM_PAD_MAP` protocol. Bindings are per-game `launcher.DM_KEYMAP` / `launcher.DM_PAD_MAP` preferences, shared by standalone launch and TonTon. Explicit environment and env.txt values retain precedence. `DM_SAVED_CHOICES=0` leaves stored choices unchanged.
- [NxNative Launcher public fork 15279447](https://github.com/vrieza/nxnative_Launcher/tree/1527944707c800593f98186f3812ce0eddf146f5): relative cursor capture with `CGAssociateMouseAndMouseCursorPosition(false)`, mouse-to-stick radial deadzone compensation, 120 Hz ticker and 18 ms stop, Escape and focus release. Motion is accumulated and normalized by elapsed ticker time. This is an accessible public snapshot; the original owner's repository was unavailable during review.

The imported MIT notices ship in `DesktopControlsNotices.txt` in each app. NX2navi's restricted additions are not imported.

## TonTon adaptations

`desktop.tsv` supplies each game's keyboard and mouse defaults. All per-game values live in the profile, outside the host. Profiles distinguish stick movement, steering, D-pad navigation and games without movement. Original J/K/U/I aliases remain unless a user mapping moves that function. `Run` selects the full stick range for games that use analog movement; games with a dedicated sprint/dash button bind Shift to that button instead. A right-stick camera retains the game's original camera curve and speed limit.

The upstream key map is extended with key codes 128–130 for mouse left/right/middle and the `Run` function. Modifier events use Shift, Control and Option virtual keys. Physical controller mapping is applied in the common physical input publisher, before the existing A/B and X/Y swaps, without remapping keyboard or scripted events.

The old boundary-warp approach did not keep physical mouse movement disconnected from the system cursor. The frontend now keeps that disconnection for the duration of capture, in both fullscreen and windowed play. AppKit global points are converted to Quartz global points using the primary display's point rectangle, not its physical pixel height. This supports Retina scaling and displays above or left of the primary. Touch games retain a visible, bounded virtual pointer; camera games hide it and consume relative deltas.

Escape or F8 releases capture. Clicking inside the game recaptures it without sending an accidental camera-mode attack. Focus loss, minimization, text entry, controller prompts, quit prompts and close release capture. The help dialog also releases capture. F1 displays the effective keyboard map, including custom mappings.

UI strings use the system-selected Simplified or Traditional Chinese bundle localization. Game interface language remains a separate setting, as offered by the game's own resources.

## Validation

Pure input tests cover all 23 installed profiles, alias release, normalized diagonal movement, walk/full-speed selection, remapped movement and buttons, mouse direction/inversion, stop and focus reset. NX2Apple's parser suite covers valid and invalid mappings. The shared settings and Mac packer tests check persistence and launcher rules without opening game saves.

Installation updates each game's matching host and the settings launcher; game code, ROM resources, shader chain and save directories are unchanged. Gameplay and physical multi-display acceptance are left to the player as requested. No gameplay or multi-display pass is claimed.
