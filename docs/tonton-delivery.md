# TonTon delivery recovery, November 12

The installed games retain their existing source revisions and shader
chains. No shader-chain update or completed-game rebuild is part of this
recovery. New titles use a separate pinned Rust build workflow described
in [the build notes](tonton-new-builds.md).

## Air

Fate/Samurai Remnant completed all 77,671 Metal 4 shader families on
November 12, resuming from 74,010 using the existing `a3a5cfdab59c` chain. Only missing work
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

A further 2,334-file checkpoint passed complete size and SHA-256 readback
without retransmission. The delivery controller retains its successful
paired-service route while batches make progress, instead of repeatedly
forcing a large CoreDevice enumeration. New loose batches stop when shader
compilation finishes, allowing final packed delivery to take over.

The final runtime-table analysis had inherited a one-CPU environment.
The orchestration now assigns four processes to that read-only analysis;
the chain tools and shader source remain unchanged. Both final runtime
tables are now complete. The final image and device readiness checks
remain pending.

The final readiness stamp still requires matching runtime tables, fonts,
signed framework identity and shader-image readback.
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
were not modified. After publishing the matching identity stamp, the
device's library reported `ready` / `can open`. Launch and rendering
validation remain outstanding; readiness is not a gameplay pass.

M2 Samurai shader production also resumed in serial microbatches on the
internal SSD, retaining the frozen legacy renderer and existing outputs.
The dispatcher yields when free space would cross its 25.75 GiB reserve,
so the Air producer and final delivery have priority.

The M2 availability snapshot still rejects the frameworks for Today's
Menu for the Emiya Family, Fate/Samurai Remnant, Tears of the Kingdom and
Legends: Arceus. Their old framework chains must be matched with the
correct renderer and resources before activation. A completed ROM upload
is not evidence that these four runtimes are ready.

## Newly supplied originals

- Fate/EXTELLA LINK: base `010051400B17A000`, update `131072` (1.0.2),
  and 58 DLC packages. Every RAR member passed CRC and SHA-256 reading.
  The DLC archive filename is misleading: its internal package IDs are
  in the matching `010051400B17B...` range. All three originals were moved
  to the external archive after full SHA-256 readback; their Downloads
  paths are links. All 60 extracted NSPs were separately verified. Rust
  build planning and the executable survey passed using the existing
  local keys. The isolated engine is pinned to `0c078130`; installed and
  in-progress games retain their earlier engine revisions. The survey
  found SDK 5.5. A verified archive index located 187 shader containers;
  scanning those and `main` found 1,488 shader records. Rust and reference
  splitting produced byte-identical map/facts/pair tables and matching
  payloads, but the Rust package records had zero lookup keys at header
  offset 8. Reference packages retain the verified keys and are selected
  for compilation. Other asset containers have not yet been scanned;
  this partial discovery is not a complete port or a gameplay result. Six
  representative shaders (two per stage) compiled successfully for Mac and
  iOS, including their generated companion libraries. Four query defaults
  still require inspection before runtime validation.
- Red Dead Redemption Switch 2 export: readable NUP index, update
  `458752` and an add-on. Full payload verification remains pending.
- Cyberpunk 2077: readable NUP index, base and update `262144`.
  Full payload verification remains pending.
- BIOHAZARD RE4 GOLD: seven RAR volumes passed verification as one archive:
  all 19 regular members passed CRC and SHA-256 reading (28,861,835,455
  unpacked bytes). The latest supplied executable set is update `131072`.
  macOS `._` metadata files are excluded from the volume set. No large
  extraction has been placed on the compiler's internal SSD.

Per the revised scope, non-Fate additions stop at external archival and
pre-build inspection for now. New Fate bring-up may proceed. None of
these inputs is advertised as playable. The verified Rust 0.9.3 binary passes its tool self-check.
Its unvalidated native iOS shader frontend remains disabled. Archive
verification, build completion and device gameplay are distinct gates.

## Space recovery

Only superseded generated app bundles and completed Violet generated
MSL text were removed. Latest signed candidates, current repair evidence,
compiled libraries, source packages and saves were retained. A second pass
removed three superseded Air app bundles, reclaiming about 614 MB of actual
free space; the latest and immediately preceding signed Air candidates
remain available. APFS clone
sizes are logical sizes, so deleting a large old app does not necessarily
reclaim that many physical bytes. Compiler decisions use actual free
space rather than summing the apparent sizes of deleted bundles.
