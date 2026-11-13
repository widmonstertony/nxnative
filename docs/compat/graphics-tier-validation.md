# Frozen iPad graphics-tier and incremental-build checks

These compatibility patches target the already installed TonTon engine; they
are not a merge of the current translator. Game bodies, original saves and
shader-library chains remain unchanged. Current main retains its upstream whole-GPU default; the frozen host patch retains its operation-mode default. The SDK-query fix is in
`dm/host/hle_oe.c`; the companion patches preserve it in the frozen host and
keep Air's shelf from overwriting the title's explicit selection.

M2 60.96 reached Mario Bros. Circuit 50cc with 1280x720 scene attachments,
1920x1080 UI composition and actual MetalFX output at 2732x1536. Late sampled
race windows were below the 60 FPS target. See the [game note](../../dm/games/0400C3F00006E000/README.md#tonton-ipad-compatibility-validation-2026-11-12)
for measurements and experimental 540p failures. No failed 540p candidate was
installed on Air. Air 60.75's installed profile was read back; a fresh Air
race remains unchecked.

Validation:

- `python3 -m unittest discover -s dm/host/tests -p test_graphics_tier.py`:
  two tests pass, covering both operation modes, malformed/default values,
  explicit tiers, legacy spelling and canonical precedence. The C fixture
  compiles and executes the actual SDK-query helper and both exports.
- `python3 -m unittest discover -s dm/tools/tests -p test_docs.py`: 11 pass.
- `regress.py check --baseline HEAD --games 0400C3F00006E000 --quick
  --no-smoke` was attempted with the local games directory. It exits 2:
  no Mac build of this title exists there. This is not a regression pass;
  device race evidence supplies the narrow runtime check.
- Installed host/framework signatures, unchanged resource identities and
  original save SHA-256 values were checked on device after each update.
  Tests use an independent save copy with cloud sync disabled, then remove
  their temporary environment overrides.

## Existing Samurai finisher throughput

`m2-bounded-finisher.patch` changes orchestration only, on the frozen
`a3a5cfdab59c` chain. It does not change translator source, profile inputs or
finished shaders. The running controller was not restarted. Independent
12-key benchmarks compared all 53 output files byte for byte:

| Workers | Serial comparison | Parallel comparison | Equal files |
|---|---:|---:|---:|
| 2 | 12.6 s | 9.6 s | 53/53 |
| 4 | 17.9 s | 6.9 s | 53/53 |

These are small-batch measurements under concurrent load, not a promise of
whole-build speedup. The patched runner requires the verified benchmark
receipts and at least 36.5 GiB free for two finishers or 38.75 GiB for four;
otherwise it falls back to the original serial microbatch. Reserves and
batch limits remain enforced. Completed output is reused. Final table merge,
component-only delivery, and device gameplay remain separate gates.
