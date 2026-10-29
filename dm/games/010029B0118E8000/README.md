# Need for Speed Hot Pursuit Remastered

Provisional external profile, owned base 1.0.3. Gameplay validation remains open;
this note does not register a playable game.

## Found on this game

- The first A10X draw used an unbound vertex constant bank 0 and faulted the GPU. The shared zero uniform bank keeps that read separate from the writable sink.
- [Legacy depth prediction](../../../docs/reference/rendering.md#legacy-depth-prediction-and-secondary-blend-sources): fragment `721bdcf892c65085_b` writes depth. A native reproduction showed an invalid depth-less compilation preventing later valid depth formats from compiling. Rejecting the invalid descriptor before Metal leaves Depth16, Depth32 and Depth32/stencil pipelines available. The actual fragment passes the invalid/valid/invalid regression sequence.

The complete minimum-16.1 repair package `20261029.2` built successfully and was
installed on both iPads with exact code/version and saved-state readback.
The user tests the game; a successful build or installation does not establish
that every black-screen cause is resolved.

Current: the user still reports a black scene on M2 with `20261029.2`.
Its runtime log names ten stages absent from the offline map and a BC texture
readback that returns zeroes; neither issue is resolved by the depth fix.
A diagnostic build captures exact missing control/code bytes for offline
translation. No alias to a similar program or successful-rendering claim is made.
