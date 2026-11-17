# Graphics preset recipes

Reused from https://github.com/ninja8170/nxnative-4k-presets at
532cf2da64c0ad0ea5d83f875346f6f846aff338. The engine changes originate at
https://github.com/ninja8170/nxnative/tree/4k-hdr-temporal (30eb9960).

These tools and recipes contain no game assets. The Mac packer generates
overlays from the player’s own RomFS, checks the NSO build ID and WINDOW_SIZE
fixup, verifies every original value and reads each edited value back.
Only Ocarina v131072 is automatically enabled. Mario Kart World v0 does not
match the author’s 1.8.0 recipe and is left unchanged. HDR remains optional.

Preset generation requires the `zstandard` package in the builder Python.
The configured local TonTon toolchain already includes it.

The unmodified upstream parser tools are vendored in
`dm/third_party/nxnative-4k-presets/tools/`.
