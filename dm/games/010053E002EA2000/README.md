# Fate/EXTELLA: The Umbral Star

Base version 1.0.0, SDK 0.12.17, title `010053E002EA2000`. This is the
original cartridge, separate from Fate/EXTELLA LINK.

On iPhone Air 60.88 the cartridge mounted its RomFS, entered `nnMain`, and
initialized NVN before exiting with code 42. The game log's stack trace
identifies `sdk+0x8818c`: `CreateAliasStackUnsafe` aborts after
`AddressSpaceAllocator::AllocateSpace` returns zero. Air 60.89 still aborts at
the same instruction after enlarging the stack reservation to 768 MiB.

In SDK build `3b353895d8e688841c45c34b45169228`, `nnosInitialize` constructs
the alias and stack allocators at the literal base `0x08000000`. Their free
page queries miss the host's guest block. The host now replaces the two
allocators' page bounds with the alias and stack regions it reports through
GetInfo, after confirming the SDK build and original allocator fields. It
preserves their guards and locks. The Metal 4 and iPadOS 16.1 frameworks reuse
the rewritten modules and their existing shader chains.

The player confirmed that Air 60.90 reaches the title or game after the
correction. On the M2, 60.109 registered the verified game image in the
existing Gamebox and read its 619-entry shader archive, but crashed as the
classic Metal backend queried `minimumLinearTextureAlignmentForPixelFormat:`
for a depth/stencil target. The iPadOS 16.1 framework in 60.110 keeps these
formats out of both linear texture paths and reuses the same shader chain.

On November 16, the M2 running iPadOS 16.1 launched 60.110 from the existing
Gamebox and displayed the title menu. The update checks found the same game
file identities and save digests before and after installation. This check
ended at the title menu; gameplay, language selection and return to the
shelf were not verified.
