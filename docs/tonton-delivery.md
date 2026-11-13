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
tables are complete. The final 6,126,960,433-byte image passed full
SHA-256 device readback (`3abb4050b485899fda6b01ee023b20bf45f08001a91ce43fa092d669014f82c0`).
After refreshing the shelf, the actual Air library reported `ready` /
`can open`, first on 60.70 and again after the 60.72 host update. The
250,134 earlier loose overrides remain. No ROM was reuploaded and no save
was changed. The user performs the gameplay check; readiness is not a
gameplay pass.

The published readiness stamp matches runtime tables, fonts, signed
framework identity and shader-image readback. The library must not expose
an incomplete title as playable.

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
  this partial discovery is not a complete port or a gameplay result. All 1,488 discovered shader records compiled successfully for Mac and
  iOS, including their generated companion libraries. The new pinned
  iOS output has an 18.0 minimum and is not the M2 legacy runtime. Shader
  coverage outside the 187 discovered containers and query defaults still
  require inspection before runtime validation.
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

Completed Air Samurai generated MSL/CAS intermediates were removed only
after final-table, image-readback and device-readiness checks. Actual SSD
free space increased by 27.66 GiB; compiled libraries, final tables,
archives and receipts were retained. APFS deferred reclamation subsequently
raised free space further and M2's retained dispatcher resumed.

## Air scene-resolution audit

Air 60.72 was signed and installed in place on November 12. Existing game
frameworks and entitlements are byte-identical to 60.70, including iCloud
and memory permissions. One small Pokopia contract was added. Its actual
run logged `scene cap 1280x720, 7 dynamic lists lowered`; this confirms the
loader ran the data change, not its sustained performance. The user's run
still showed stutter and crackle, with roughly 28–44 fps in the later
scene and serious thermal state. Audio callbacks had zero underruns in
the initial 48 kHz route, then hundreds per 2,000 callbacks after a move
to a 44.1 kHz Bluetooth route. That correlation is diagnostic evidence,
not proof that the route caused every underrun. Pokopia's next-boot
configuration and adjustable per-game schema were changed to 540p plus
MetalFX and fully read back. The next actual run confirmed the 540p cap,
and the player reported less stutter but persistent crackling. Audio
starvation later also occurred on the built-in-speaker route. A Pokopia-only
`DM_RT=0` comparison was confirmed in the next launch but did not resolve
crackling. Audio repair remains open; opt-in producer/release progress
telemetry is installed on Air 60.73, without changing buffer release timing.
Its Pokopia-only switch was written and fully read back. The ineffective
real-time override was removed; 540p plus MetalFX remains. All 26 game
directories were retained and the checked ROM sizes matched before/after.
The update did not start a game or write a save. A diagnostic scene run is
pending; this is not an audio repair claim.

Audio diagnostics validation: the current host and the exact legacy source
both passed 29 callback/statistics/release checks. The current fixture also
passed ASan/UBSan. Existing AudioOut lifecycle/surround tests and the
100,000-buffer SPSC fixture passed. The compilation database was generated;
clang-tidy could not run because LLVM 23 is not installed. The narrow
Pokopia regression command returned `ERROR` because no Mac build is
registered in its isolated test root; it is not a gameplay pass. This
opt-in instrumentation does not change PCM consumption or release timing.

The batch audit recovered 23 retained native-game logs. Several are from
November 5–8 and predate current settings. Violet, Arceus, Need for Speed,
Z-A, Tears of the Kingdom, NieR, The Witcher 3 and Crisis Core have retained
720p-to-MetalFX evidence. A 1080p allocated window does not contradict a
720p crop (Violet is an example). Pokopia, Kart, Samurai and the retained
independent Ocarina path need separate scene-size verification; some older
logs also have upscaling disabled. These are not all marked complete.

Validation for the new contract: seven portable C-backed unit cases,
eleven docs checks, the owned embedded image's nine original lists, iOS
loader/menu compilation, identical exported symbols, signed-package
framework/entitlement comparison, in-place installation and resource-path
checks. `regress.py check --games 0400A3A01EE4C000 --no-smoke` could not run:
there is no matching Mac build registered for this retained Air version.
No Mac gameplay regression pass is claimed.
