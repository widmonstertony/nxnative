# Fate/EXTELLA: The Umbral Star

Base version 1.0.0, SDK 0.12.17, title `010053E002EA2000`. This is the
original cartridge, separate from Fate/EXTELLA LINK.

On iPhone Air 60.88 the cartridge mounted its RomFS, entered `nnMain`, and
initialized NVN before exiting with code 42. The game log's stack trace
identifies `sdk+0x8818c`: `CreateAliasStackUnsafe` aborts after
`AddressSpaceAllocator::AllocateSpace` returns zero. The title profile now
reserves 768 MiB for guarded guest stacks, with the original heap, alias
region, and application pool left at their previous sizes. This adjusts
virtual addressing; it does not commit another 512 MiB of physical memory.
The Metal 4 and iPadOS 16.1 frameworks were rebuilt independently from their
existing rewritten modules and keep their original shader chains.
