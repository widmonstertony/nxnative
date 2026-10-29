# Compatibility fork status

## One development branch

[`ios16-pokemon-za-port`](https://github.com/widmonstertony/nxnative/tree/ios16-pokemon-za-port)
is the only maintained compatibility branch. It contains the shared iOS 16.1/17
host, older-GPU renderer, Chinese launcher, touch/keyboard/controller input,
per-build game adapters and optional modern rendering features. `main` remains
the upstream baseline. There are no separate development branches per game or
per iOS version. Historical branches are preserved as `archive/20261029/*` tags;
they are reference snapshots, not alternative releases. All future fixes belong
on this branch. Per-game builds freeze its commit and select a build target;
they must not grow independently maintained source branches.

The consolidation imports the iPhone feature changes through `0dcbf32` and the
isolated Arceus compatibility changes, preserving the legacy uniform zero-bank
fix from `4ba6add`. Upstream-only changes on the former modern branch are retained
in its archive tag; this consolidation is not an upstream rebase. Existing
background builds retain their frozen source and shader chain. They must not be
silently switched to the consolidated source or have their caches relabelled.

## Build targets

- Default `DM_IOS_RENDERER=legacy`: iOS/iPadOS 16.1 minimum, traditional Metal
  command encoders. `DM_LEGACY_TARGET=a10x` requires all older-GPU companions;
  `m2` permits only the documented Apple8 layered rendering and Tier2 sampler
  capabilities. Both targets reject unsupported native image atomics.
- `DM_IOS_RENDERER=metal4`: iOS 26 minimum and the modern renderer, including
  experimental image optical-flow interpolation. It is an explicit build target,
  not a change to the minimum version of the compatibility build. One source
  branch does not mean one Metal 4 executable can run on every older device.
- tvOS source is retained. Current delivery work does not operate TVs.

Exact-build fullscreen and timing adapters remain gated by module identity,
original instructions and observation sites. The screen XBAY layout, keyboard
J=A / K=B / U=X / I=Y, Backbone printed letters and controller-connected touch
hiding are preserved. Chinese labels do not change configuration values.

Changing the shader tools changes `DMSH_CHAIN`. Generate the header and rebuild
matching resources before packaging a game; never stamp old libraries with the
new chain. A successful host compile is not a matching resource build.

## Current device failures (2026-10-29)

| Game / target | Confirmed result | Open work |
|---|---|---|
| Arceus / M2, iPadOS 16.1 | `20261029.2` installed, code/version and saved-state readback passed | User still reports gray screen; native depth/SRC1 compiler errors are gone, but a render-target setup failure remains under investigation |
| Arceus / A10X, iPadOS 17.7 | Not installed | Two layered and eighteen sampler-limit paths fail the strict resource audit |
| Pokken / both iPads | `20261029.5` installed on both; user confirms M2 picture restored | Full gameplay/performance and A10X picture remain unverified. Five further exact runtime captures compile in a matching 163-stage set; a later host/package is still required |
| Need for Speed / both iPads | Repair `20261029.2` installed, code/version and saved-state readback passed | M2 still black; ten missing runtime stages and unsupported BC readback need investigation. A10X gameplay is unverified |
| Animal Crossing / A10X | Shader compilation completed | Eleven unsupported-resource paths block packaging |
| Witcher 3 US / A10X | Shader compilation completed | Eighteen unsupported-resource paths block packaging |

The shared legacy recorder/replay mismatch is now reproduced: compact uniform
and single-vertex bindings were silently ignored. The fixed real-producer test
passes 252 checks; reverting the four replay changes fails exactly 112 binding
checks. Version `20261029.5` rebuilds all three affected hosts with the repair,
retaining each existing shader chain. M2 Pokken's restored picture is user-confirmed; the other target/game pictures remain
unconfirmed. Full game-route tests remain with the user; no five-game smoke
or performance result is claimed.

Air Arceus `20261029.9` and Z-A `20261029.124` were installed with version and
save/settings readback. Their modern image-only interpolation remains experimental;
no stable 120 fps or complete game-HUD isolation is claimed. The user tests
actual gameplay. An IPA, successful installation or a running frame counter does
not establish playability. A newly consolidated source revision is not already
installed on any device.

Game assets, extracted code, shader libraries, game keys, signing credentials
and provisioning profiles are not distributed in this repository.

## Consolidation checks

The unified source passes both complete unsigned synthetic iOS builds: minimum
OS 16.1 without the modern frame-generator class, and minimum OS 26.0 with it.
The fixture tests compile Swift, link the real host and stage synthetic resources;
they do not contain or launch a game. Tool tests: 491 run/17 skipped; graphics
Python tests: 96 run/4 skipped; iOS tests: 82 passed. Host service, timing and
display tests and both EGL import modes pass. Python lint reports zero new
findings without changing its baseline.

M4 GPU checks cover optical flow in RGBA/BGRA (18 each), paired presentation with
and without MetalFX (14 each), secondary blend sources (130), and three-pass
legacy image shadow/discard/copyback (610). These establish the tested resource
semantics on M4, not A10X playability. The user requested gameplay testing remain
with them; no multi-game gameplay route is claimed. The new shared shader chain
must be rebuilt per game before a delivery from this branch can be installed.
