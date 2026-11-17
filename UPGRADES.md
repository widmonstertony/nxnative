# 4K, HDR and MetalFX temporal upscaling (ninja8170 integration)

This integration reuses [ninja8170's 4k-hdr-temporal branch](https://github.com/ninja8170/nxnative/tree/4k-hdr-temporal) at `30eb9960`. The original author tested it on an M4 Max MacBook Pro with a 4K HDR TV; the measurements below are theirs. Local TonTon M5 Max validation and its limits are recorded in [the game note](dm/games/0400486024DEC000/README.md#tonton-mac-integration-2026-11-17). HDR remains optional and off by default.

## Every game
- **HDR10 output on the Mac** (`DM_HDR_PRESENT=1`, or **HDR** in the settings window):
  - The game is told its display supports HDR, and its HDR10 picture is shown through EDR.
  - A 2×2 composited sublayer stops macOS sending the HDR layer straight to the display in full screen, which corrupted the picture (`DM_HDR_COMPOSITE`).
  - The reported peak brightness has a 1000-nit floor (`DM_HDR_PEAK`). A TV reporting a 100-nit peak, below paper white, gave black rings in skies.
- **`DM_DISPLAY_BUFFER`** and **`DM_HEAP_EXTRA`:** a larger display buffer and a larger application memory pool, for games pushed to 4K.

## The Legend of Zelda: Ocarina of Time (0400486024DEC000)
- **Native 4K output:** the game's 2560×1440 window is a constant in its startup code. Two patches (`WINDOW_SIZE` in `patches.py`) lift it and the graphics init that reads it.
- **MetalFX temporal upscaling** (`DM_UPSCALER=metalfx-temporal`), which replaces the game's own NDSR upscaler:
  - **Colour** from the network's own input.
  - **Depth** from the game's composite pass. The composite is found by structure: the draw whose output the network's first stage reads. That covers the fog and HDR variants.
  - **Camera motion vectors** rebuilt from depth and the game's previous view-projection matrix.
  - **Sub-pixel jitter** added to the game's camera (Halton sequence).
  - **A reactive mask** for particles, glow and translucent effects.
  - **RCAS sharpening** and an automatic mip bias.
  - **History resets** on cuts, loads, large camera jumps and picture-wide brightness changes.
  - **Per-frame `@tfx_*` diagnostics** in `DM_NVN_TSV`.
- **Result:** with the 2/3 render-scale preset, 3840×2160 at a locked 60 fps on an M4 Max. GPU time is 11.7–14.2 ms against 15.1–20.4 ms for native 4K.

## Mario Kart World 1.8.0 (0400C3F00006E000)
- **A full-resolution hold:** a patch stops dynamic resolution dropping below full size.
- **Native 4K** (with the presets below): 59.9 fps in races, 9.0 ms of GPU per frame.

## Presets
The game-data side is the resolution tables and memory budgets. It lives in [ninja8170/nxnative-4k-presets](https://github.com/ninja8170/nxnative-4k-presets) as recipes you apply to your own dump. No game files are included anywhere.

The new switches are documented in `docs/env_switches.tsv`, `docs/settings.md` and `docs/reference/rendering.md`. Unit tests are in `dm/gfx/tests/t_upscaler_tfx.m` and `dm/host/tests/t_vi_*.c` / `t_window_size.c`.
