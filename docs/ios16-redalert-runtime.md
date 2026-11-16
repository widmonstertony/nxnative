# Red Alert 2 runtime on iOS 16

The full owned EA archive needs both a compatible WebAssembly runtime and the
game's Blowfish COM registration. Importing a ZIP installs neither dependency.
The app runs `cmd.exe /c regsvr32.exe /s Blowfish.dll && gamemd.exe` from the
mounted game directory. Registration uses Wine's normal persistent prefix; it
does not copy EA account state or change host permissions. Failure stops launch.

For iPadOS 16.1 the checked build is official BoxedWine commit
`2be9ff442feac29755a46693cd989960eeac8786`, Emscripten 4.0.23, with
`make release WASM_EXCEPTIONS_FLAG=-fwasm-exceptions TAIL_CALL_FLAG= MAKEFLAGS=-j4`.
The resulting Wasm has no SIMD, tail-call, new exception-reference, or GC
instructions. Merely enabling legacy Wasm exceptions on the JIT build is
insufficient: that build still contains SIMD and tail calls. Do not lower an
Info.plist deployment version to declare those binaries compatible.

The release Wasm SHA-256 is
`b95d8088d70f29cc997a2448d045f57adb6709b9fd87a42c92494c9f2a84610c`.
Bundle the upstream GPL license, corresponding-source revision, build flags and
local shell parser changes with the runtime. Keep the stable localhost origin
and persistent WebKit data store so an app update preserves Wine's saved data.

Validation on 2026-11-01: static instruction audit, compilation with exnref
explicitly disabled, non-game COM registration and query, and the exact Windows
`cmd.exe` registration/query launch sequence passed. The iOS 16.1 app compiled
and was installed on an M2 iPad. Runtime and full owned archive hashes were read
back; ten save files and 84 CPU tables stayed unchanged. No commercial game was
automatically launched. These checks do not establish campaign playability or
interpreter performance; those remain user tests. The official Wine test harness
did not produce a unit-test summary, so its timeout is not a passing Wine suite.

An actual M2 startup log then showed `RangeError: Out of memory` before the Wine
command, while the browser loaded the 1.83 GB game ZIP. The native route now sets
`app-range=true`: `prepare_boxedwine_range.py` adds a read-only Emscripten file
backed by exact HTTP 206 byte ranges instead of downloading the whole archive
into MEMFS. Its LRU holds three 1 MiB blocks. The adapter obtains the node using
`FS.lookupPath`; Emscripten 4's `createDataFile` returns void. It preserves normal
seek/size behavior, rejects writes and mmap, and fails closed on truncated or
incorrect range responses. The normal native local HTTP server serves the data;
no sandbox permission change is involved.

Node regression checks cover binary bytes, cross-block reads, EOF, cache reuse,
read bounds and malformed server responses. An isolated browser also exercised
real synchronous HTTP range requests. These checks do not establish iOS Wine
startup or game playability. Keep the WebKit runtime logs after user launches so
the next initialization failure can be distinguished from the archive OOM.

The corrected range adapter also completed the real BoxedWine non-game
`cmd.exe` COM registration/query sequence with the official Wine11 v24 root.
The probe observed an HTTP 206 read and exit marker 0, with no browser exception.
The generic Wine harness still timed out waiting for its separate test-summary
format; this is dependency-command evidence, not a complete passing Wine suite.


## Optional scalar JIT candidate

The M2 user confirmed that the bounded-reader interpreter build opens the game,
but reported severe lag. Its live log contains main-loop stalls and roughly
70–95 million interpreted guest instructions per second. MIPS is not game FPS;
this is evidence to investigate CPU translation and presentation, not a measured
frame-rate improvement.

`tools/prepare_boxedwine_scalar_jit.py` applies the accompanying GPL-compatible
patch to the exact upstream revision above. Build with
`BOXEDWINE_WASM_JIT_SCALAR_ONLY` as well as `BOXEDWINE_WASM_JIT`, no `-msimd128`,
no tail-call compiler flag, and legacy Wasm exception encoding. Use a separate
build directory so the working interpreter remains available. Retain the bounded
archive adapter, shell environment parser repair, stable HTTP origin and Wine
persistent storage when packaging the candidate.

MMX/SSE and extended-state instructions call the existing interpreter and leave
the compiled activation. Integer string instructions use the existing scalar REP
implementations, including overlap, direction, flags and fault behavior. Disable
XMM preloads in cold memory paths and vector-containing register regions. Merely
removing `-msimd128` or changing vector-local types is insufficient: generated JIT
modules can still contain vector operations even when the host Wasm passes its
static feature audit. The first two candidates exposed exactly that error and
were rejected without device installation.

The corrected candidate passed 1537 non-game CPU checks (integer arithmetic,
carry, REP copy, mixed SSE/MMX and x87 state) and actual Wine COM registration/query
in desktop Chrome, without JIT module compile errors. The test source is
`dm/ios/tests/boxedwine_scalar_cpu_probe.c`. This is a narrow correctness check,
not the complete upstream CPU suite, and is not iPad gameplay or a performance
benchmark. Do not claim a frame-rate gain before measuring the installed runtime
on the target device. Bundle this patch, upstream revision, build flags, GPL
license and corresponding-source link with any distributed candidate.

## Rejected on-device scalar JIT and recovery

The `.34` candidate above failed on the actual M2 iPad running iPadOS 16.1.
Its WebKit log repeatedly rejected both standalone and batched generated modules
with `br / br_if` targets exceeding the control-stack depth, followed by a
terminated WebKit content process. Desktop Chrome's 1537 CPU checks and COM
probe did not cover this engine-specific failure. Do not deploy this candidate
as an iOS 16 compatibility or performance fix; static instruction validation
alone cannot validate dynamically generated modules. Preserve the failing log
and require execution in the target WebKit engine for a replacement candidate.

M2 `.35` restores the bounded-reader interpreter with Wasm SHA-256
`b95d8088d70f29cc997a2448d045f57adb6709b9fd87a42c92494c9f2a84610c`.
The runtime, host code, eight existing guest frameworks, resource bindings,
19 game directories, save hashes and CPU tables were read back after the
overwrite install. No game was automatically launched. This removes the known
JIT regression; it does not resolve the previously reported interpreter lag.

The native wrapper now displays a Chinese failure message when WebKit terminates
or navigation fails, while preserving its diagnostic log and persistent store.
It does not reload automatically, reset Wine, or silently discard saved state.
