# Frozen classic NVN backend

This is the classic NVN implementation from fork commit
`b5ac83de5c3c01ab30b3e0dbac8eaf32fe2f9b14`, kept as one coherent ABI.
All NVN translation units and headers select it together on iOS/tvOS 16/17;
`DM_NVN_MODERN_RENDERER=1` selects the current upstream implementation.
macOS uses the current upstream implementation unless a regression explicitly
sets `DM_NVN_LEGACY_RENDERER_TEST=1` for every translation unit.

The upstream owner registry, queue records, texture layout and reflection cannot
be mixed with the classic renderer's private registry. The wrappers prevent
that combination. The classic GL interop, audio lifecycle, signed image loader
and embedding tool are retained alongside this backend for the same reason.

Classic shader chain: `c6c6ac82aed1`, recorded in `dmsh_chain.h`. It is independent
of the current modern chain. Existing libraries are never relabelled or copied
into the modern chain. To compile fresh classic shader libraries, use the shader
tools and profile inputs at the pinned commit, with each title's own output.
The current root translator follows upstream and builds modern libraries.
Packing checks the backend chain and profile input stamps and refuses mismatches.
Classic multi-program embedding is not supported; use the modern renderer for
`PROGRAMS_TSV`. The retained game library uses its explicit namespace format.

Validation does not install builds on iOS devices or change existing game saves.

## Selective timing backport

The frame-step controller now follows the upstream bounded-average lateness and
clock-ramp recovery rules. The classic caller uses the loaded stub's `STEP_MAX`
contract and retains 60 Hz units; it does not enable modern 120 Hz pacing or alter
shader/reflection layouts. `t_fstep_legacy` runs the same simulated timing routes
as the modern controller. Source validation is separate from a device update.
