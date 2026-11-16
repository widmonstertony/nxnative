# TonTon Mac frontend and engine update

The Mac frontend reuses NX2Apple at `d0adbda8f505a137ef254e4b7e7e58744244255c`.
Its source and MIT notices are under `contrib/tonton/nx2apple`. The engine includes
upstream `32faef7c039d868e2430ce28aec020c9b3997013`, plus NX2Apple's Mac controls, Home menu, background pause,
runtime profiles, library metadata, input deadzones, Joy-Con and Steam Controller
support. The upstream bounded post-completion ring is retained instead of the
older NX2Apple ring workaround. Aliased pool storage flags and capture metadata
are integrated alongside upstream's existing address and sampler bounds.

TonTon keeps its existing app identity and private CloudKit container. Its signed
broker handles both desktop and console launches, retaining divergent progress.
Custom save paths and folder transports retain their locations. Installation and
library discovery never import or replace game saves. The frontend imports the
23 installed applications and the three pending catalog entries without moving
their resources. Existing game preferences are kept, including the Legends mouse
camera and spatial I/J/K/L bindings. The generic upstream keyboard layout does
not replace these per-game desktop profiles.

`python3 scripts/build_tonton_mac.py OUTPUT.app --existing INSTALLED.app
--build-path BUILD_FOLDER` generates the shared native desktop editor and cloud
transport, builds the pinned Swift package, and retains the existing icon,
provisioning profile and bundle metadata. Sign the candidate with its original
CloudKit entitlements before installation. A plain NX2Apple self-update cannot
replace this signed TonTon identity.

The Builds page reads per-game update receipts: queued, running, built, installed,
failed or waiting for inputs/space. Each game has its own work directory and log.
A new host must use libraries from its actual translation chain. Existing apps
stay installed until their candidate is complete, signed and checked; a running
game is never replaced. Builds use Mac Metal shaders and the local GPU archive.

The original media audit reads package content metadata on read-only Tony Drive
and TonyBigDri mounts. The installed Switch 1 versions match the newest matching
packages found in this audit. Z-A's NUP has v393216, Ocarina's standalone update
v131072, Pokopia's ZIP v327680, and Kart World's ZIP the base version. No newer
version is inferred from a filename or from a profile for another build. Official
updates require complete matching code and resources. A source merge or signed
app is not a gameplay pass.

Validated before deployment: the complete modern Mac host links; the retained
classic iOS 16.1 selection compiles 85 units; 84 Mac packing tests and 22 launcher
settings tests pass. Input tests validate all 23 desktop profiles and the two
Legends bindings; Home menu, stick deadzone and controller routing tests pass.
Individual game rebuild and player acceptance results are recorded separately.

Frontend checks: 327 core cases pass. Nine upstream outer-repository checks
(Brewfile and Python/iOS/Qt localization-source inventory) are inapplicable to
the vendored Mac-only package and are excluded explicitly. Metal checks pass
36 aliased-pool cases, 117 presentation cases and 35 sparse-binding cases.
