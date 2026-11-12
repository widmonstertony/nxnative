"""Reconcile omitted CoreDevice rows by hashing named-file readbacks.

This does not copy to a device or infer that an absent row is a missing file.
Callers must already hold their device transport lock.
"""
import hashlib
from pathlib import Path
import re
import tempfile


def reconcile_listing(listing, expected, source, copy_from, remote, *, scratch=None, limit=64):
    """Return a listing plus proof of each recovered omission.

    expected contains previously observed sizes and, when available, hashes.
    Existing rows are left intact for the caller's size/conflict checks.
    An unbounded omission is a retryable inventory failure, never permission
    to resend the directory. Every recovered row requires a full SHA-256.
    """
    missing = sorted(expected.keys() - listing.keys())
    if len(missing) > limit:
        raise RuntimeError("Air inventory temporarily incomplete; preserve checkpoint and retry")
    result = dict(listing)
    proofs = {}
    for name in missing:
        if not re.fullmatch(r"[0-9a-f]{16}_b[a-z0-9]*\.(?:json|metallib)", name):
            raise ValueError(f"Cannot reconcile an unrecognized runtime member: {name}")
        local = Path(source) / name
        if not local.is_file() or local.is_symlink():
            raise ValueError(f"No retained source for omitted runtime member: {name}")
        row = expected[name]
        if local.stat().st_size != row["size"]:
            raise ValueError(f"Retained source size changed: {name}")
        with local.open("rb") as data:
            digest = hashlib.file_digest(data, "sha256").hexdigest()
        if row.get("sha256", digest) != digest:
            raise ValueError(f"Retained source digest changed: {name}")
        with tempfile.TemporaryDirectory(dir=scratch, prefix="air-inventory-readback-") as td:
            returned = Path(td) / name
            copy_from(remote + "/" + name, returned)
            if not returned.is_file() or returned.is_symlink() or returned.stat().st_size != row["size"]:
                raise ValueError(f"Omitted device member size mismatch: {name}")
            with returned.open("rb") as data:
                returned_digest = hashlib.file_digest(data, "sha256").hexdigest()
            if returned_digest != digest:
                raise ValueError(f"Omitted device member digest mismatch: {name}")
        result[name] = {"name": name, "metadata": {"size": row["size"]},
                        "resources": {"isSymbolicLink": False},
                        "tonton_named_readback_sha256": digest}
        proofs[name] = {"size": row["size"], "sha256": digest}
    return result, proofs
