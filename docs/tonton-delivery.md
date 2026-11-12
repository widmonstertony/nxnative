# TonTon delivery recovery, November 12

The installed games retain their existing source revisions and shader
chains. No shader-chain update or completed-game rebuild is part of this
recovery. New titles use a separate pinned Rust build workflow described
in [the build notes](tonton-new-builds.md).

## Air

Fate/Samurai Remnant resumed from 74,010 completed Metal 4 shader families
out of 77,671, using the existing `a3a5cfdab59c` chain. Only missing work
is compiled on the internal SSD. Batches stay within the disk reserve and
use the previously validated parallel finisher. Compilation and delivery
are separate processes, so transfers do not serialize compilation.

A CoreDevice enumeration omitted a previously delivered file even though
a named-file readback returned the correct bytes. The recovery helper
`dm/tools/tonton_air_inventory.py` repairs an omitted inventory row only
after checking the retained source size and SHA-256 against a full device
readback. Too many omissions stop the batch for another inventory attempt;
a content mismatch stops it for review. This helper never writes to a
device. Existing transfer checkpoints and per-file receipts remain intact.
The 2,350-file interrupted checkpoint was subsequently verified without
reuploading those files. This is transfer evidence, not a launch result.

The final readiness stamp still requires complete compilation, matching
runtime tables, fonts, signed framework identity and shader-image readback.
The library must not expose an incomplete title as playable.

## iPads

The M2 service address changed to `192.168.68.89`; the old iPad remains
`192.168.68.72`. Both paid Gameboxes were reachable on November 12. Their
existing base-image transfer receipts are complete; repeating those base
uploads does not supply a missing compatible engine.

The old iPad received the previously absent legacy Mario Kart World
shader image (498,145,683 bytes) and missing runtime tables. The complete
image was SHA-256 checked on-device. Its 23,291,263,499-byte ROM retained
the same size and filesystem identity. The app was not replaced and saves
were not modified. Launch and rendering validation remain outstanding.

The M2 availability snapshot still rejects the frameworks for Today's
Menu for the Emiya Family, Fate/Samurai Remnant, Tears of the Kingdom and
Legends: Arceus. Their old framework chains must be matched with the
correct renderer and resources before activation. A completed ROM upload
is not evidence that these four runtimes are ready.

## Newly supplied originals

- Fate/EXTELLA LINK: base `010051400B17A000`, update `131072` (1.0.2),
  and 58 DLC packages. Every RAR member passed CRC and SHA-256 reading.
  The DLC archive filename is misleading: its internal package IDs are
  in the matching `010051400B17B...` range. Originals were not modified.
- Red Dead Redemption Switch 2 export: readable NUP index, update
  `458752` and an add-on. Full payload verification remains pending.
- Cyberpunk 2077: readable NUP index, base and update `262144`.
  Full payload verification remains pending.
- BIOHAZARD RE4 GOLD: seven RAR volumes are being verified as one archive.
  macOS `._` metadata files are excluded from the volume set. No large
  extraction has been placed on the compiler's internal SSD.

These inputs are queued for separate bring-up; they are not advertised
as playable. The verified Rust 0.9.3 binary passes its tool self-check.
Its unvalidated native iOS shader frontend remains disabled. Archive
verification, build completion and device gameplay are distinct gates.

## Space recovery

Only superseded generated app bundles and completed Violet generated
MSL text were removed. Latest signed candidates, current repair evidence,
compiled libraries, source packages and saves were retained. APFS clone
sizes are logical sizes, so deleting a large old app does not necessarily
reclaim that many physical bytes. Compiler decisions use actual free
space rather than summing the apparent sizes of deleted bundles.
