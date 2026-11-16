# Resource-only shader updates

A successful base metallib build or a matching base-library hash does not prove
that an iOS compatibility resource update is complete. Legacy non-point vertex,
dual-source, guarded-index, layered, sampler and image companions can live in
subdirectories of `msl/b-<chain>`. Preserve the entire tree when packaging it.
`shader_resource_archive.package` recursively inventories and SHA-256 verifies
the resulting ZIP; `verify` rejects missing, extra, duplicate or altered entries.
Its `companions_only` option prepares a delta without retransmitting base files.
Call it only on completed, immutable build output, never on active caches.

One observed Witcher 3 update copied only immediate files with `iterdir()`. All
base libraries reached the device, but `nonpoint-v1` and the other companion
directories did not. The runtime then reported `Missing or mismatched non-point
source` and rejected multiple triangle pipelines. This delivery defect is
separate from an earlier damaged guest SDK and does not require relabelling or
recompiling the base shader chain.

For a repair, check the manifest schema and host chain, the exact source hash,
and the hash of each original library on the destination. Validate the extracted
files before activation. Stop the app for the directory switch, preserve its
CPU tables and saves, and read back the final file hashes. Keep hash rejection
enabled; a missing companion is not permission to load a source from another
chain. Successful delivery and offline Metal compilation still require the
user to confirm the affected scene's appearance.

The archive regression covers nested sources and manifests, detection of the
old flat ZIP, a companion-only delta, symlink rejection and exclusive creation.
