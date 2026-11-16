# Bounded game-resource delivery

Large device-copy operations can fail while leaving a zero-byte `romfs.img`.
Delivering a directory or showing a cartridge is not evidence that its RomFS
arrived. Inspect the actual destination, then transfer bounded data chunks and
read them back for SHA-256 verification. Keep a resumable ledger. The app's
normal sandbox importer verifies every chunk and the complete image before
publishing the resource. No device-permission change is required.

The importer rejects different existing resources by default. A task may opt in
with `replace_empty_placeholder: true` only for a regular, zero-byte
`Resources/romfs.img`. After assembly and integrity checks, it rechecks the
placeholder's size, device and inode, retains that empty file under a unique
name, and moves the completed image into place. It attempts to restore the
placeholder if publishing fails. Nonempty resources, symlinks, saves and input
chunks are retained. An already matching complete resource is idempotent.

Run `python3 dm/ios/tests/test_resource_import.py` for the production Objective-C
importer's integrity, invalid-path, existing-resource and empty-placeholder
cases. A passing host test or full Xcode build does not prove device delivery;
check the in-app receipt, installed version and actual resource identity too.
