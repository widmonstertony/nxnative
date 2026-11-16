# Engines in the unified library

TonTon is one application, with per-cartridge runtime selection. A shared UI
does not make different instruction sets, graphics APIs or memory requirements
interchangeable. Game data and saves belong to each `Documents/Games/<id>` slot.
Executable Nintendo code belongs to signed frameworks in the application bundle,
never to Documents. New code modules require an application update.

## Nintendo code frameworks

`tools/build_game_framework.py` builds this fork's signed-text ABI using its
actual shader chain. When migrating an existing combined application, use
`--reference-host OLD_EXECUTABLE --namespace XX` to preserve its exact code/data
pages, including padding. Rebuilding from a mutable patched directory is not
evidence of equality to an installed application. Bind all four CPU tables for
every module to the live cartridge resources before signing; an unbound manifest
is deliberately rejected. Preserve the per-device tables and saves.

The old GPU backend and modern backend remain distinct capabilities within the
same source branch. Do not relabel a shader cache or lower a plist deployment
version to manufacture support.

## Optional GTA runtime

`GTAV/TonTonGTAV.m` adapts the MIT `kalki-kgp/gtav-native` UIKit host. Define
`DM_GTA_NATIVE`, include its host headers, link the separately built `libgta.a`
and Dawn libraries, and compile the adapter in the unified host target. Those
inputs and the user's game files are not in this repository. The current Dawn
build requires iOS 17; the adapter rejects earlier systems. The iOS 16 native
Metal route needs a real renderer/BC texture fallback port, not a plist edit.
The current adapter does not implement MetalFX upscaling or frame generation.

## Optional Red Alert runtime

The separate native adapter, `TonTonRedAlert.m`, can also use an existing
`Documents/Games/<id>/UserData/ra2-native-<edition>/EngineFiles` workspace.
For a retained update, keep the signed `NativeEngines.json` and
`NativeRetailManifest.json` and their matching plist revision. Verify both
on-device workspaces against the manifest before omitting `NativeRetail`.
Use a signed `NativeWorkspaceOnly` directory containing a regular marker and
a relative symbolic link to that marker as the framework's non-copyable seed.
The framework accepts the existing matching workspace and rejects copying the
seed into an empty one. The launcher checks the selected workspace's exact
edition/revision and immutable retail hashes; that edition's editable INI is
preserved. Fresh installs still require the full retail source. The retained
package must never be used as a fresh install.

Define `DM_WEB_RUNTIME`, compile `TonTonWebRuntime.m`, link WebKit, and bundle
the official BoxedWine browser runtime under `Runtimes/RedAlert2`. Include its
GPL license and corresponding source reference (https://github.com/danoon2/Boxedwine).
No third-party runtime binary or commercial asset is checked into this tree.
The user's full game ZIP goes in `redalert2/Resources/ra2-ea-full.zip`.

The WebKit runtime uses a loopback-only HTTP origin with streaming/range support
and a persistent data store. The fixed origin preserves Wine's browser storage
between launches. It records JS exceptions and process termination under the
slot's `UserData/Logs`. This is an experimental integration: the current Wine 11
COM/RpcSs startup exception is unresolved. Bundling it does not establish that
campaigns, cutscenes, audio, saves or touch controls work on iOS.

## Switch 2 intake foundation

`tools/inspect_nintendo_dump.py DUMP --expect switch2` inspects the upstream
`base/exefs`, `base/romfs`, `updates/<decimal-version>`, and DLC layout without
changing any input. Updates must contain the full patched RomFS, not a patch
overlay. NPDM program IDs must match. A readable SDK `spec: Ounce` marker
identifies Switch 2; compressed/unrecognized SDKs remain unknown until extracted.
Encrypted NSPs still require the existing extraction step.

The tool reports `inspected_not_compiled` and never marks device compatibility
verified. The iOS fork does not yet integrate the NVN2 backend. Pokémon and Mario
Kart inputs have not been supplied; no title IDs, memory budgets or compatibility
claims are invented for them. Latest upstream evidence is the Donkey Kong Bananza
Mac profile, not an iOS result:
https://github.com/seedds/nxnative/tree/cd859c38a8f8890ddbb57a23d6f45e23ba9e6651/dm/games/040074A01BF12000

## Data inbox import

The library processes `Documents/TonTonIncoming/<transfer>/ImportTask.json`
inside its own sandbox while refreshing its catalog. Schema 1 contains
`game_id`, `resource_name` (ZIP/IMG data only), `bytes`, `sha256`, and ordered
`chunks` with `file`, `bytes` and `sha256`. Optional `card` strings provide the
name, version and size. Chunk filenames are `<index>-<sha256>.part`.

The importer validates every chunk and the combined SHA before atomically
moving the data into the cartridge's Resources. It rejects traversal, links,
duplicate chunks, inconsistent sizes and replacement of different existing
data. Inputs and saves are retained. `ImportResult.json` records success or
failure; an explicit retry removes that receipt after correcting its inputs.
No game is launched by an import. A successful data import is not a runtime
compatibility result.

When the external device service cannot create a task file, a signed delivery
can include `Runtimes/ResourceImports.json`: an array of `{inbox, manifest}`
records. On catalog refresh the app seeds tasks only into already existing,
non-symlink transfer directories inside its own Documents. It never replaces
an existing task or creates a missing transfer. Game archives and credentials
do not belong in this bundle metadata or the source repository.

## Upstream review before changes

Before each source-change batch, run `git fetch upstream main`
and inspect relevant changes in an isolated checkout. Record the upstream SHA
and the actual fixes considered. Bring compatible fixes into
`ios16-ios17-compat` with their tests and preserve platform support. This is
a fetch-and-merge workflow in an isolated checkout; it does not restart the
cancelled recurring upstream rebase or overwrite user work.
