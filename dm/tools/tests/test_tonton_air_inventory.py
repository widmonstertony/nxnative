"""A directory omission must never authorize an overwrite or hide corruption."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("inventory", Path(__file__).parents[1] / "tonton_air_inventory.py")
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)


class ReconciliationTests(unittest.TestCase):
    def test_omitted_row_needs_matching_named_readback(self):
        name = "0099af1d1fd7960e_ba.metallib"
        payload = b"MTLB retained shader"
        digest = hashlib.sha256(payload).hexdigest()
        with tempfile.TemporaryDirectory() as td:
            source = Path(td)
            (source / name).write_bytes(payload)
            calls = []
            def readback(remote, dest):
                calls.append(remote)
                dest.write_bytes(payload)
            observed = {"retained": {"metadata": {"size": 123}}}
            rows, proof = inventory.reconcile_listing(observed, {name: {"size": len(payload), "sha256": digest}},
                                                       source, readback, "Resources/msl/chain")
            self.assertEqual(calls, ["Resources/msl/chain/" + name])
            self.assertEqual(proof[name]["sha256"], digest)
            self.assertEqual(rows["retained"], observed["retained"])
            self.assertNotIn(name, observed)
            def corrupt_readback(remote, dest):
                dest.write_bytes(b"X" * len(payload))
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                inventory.reconcile_listing({}, {name: {"size": len(payload)}}, source,
                                            corrupt_readback, "Resources/msl/chain")

    def test_large_omission_stops_before_any_transport(self):
        expected = {f"{n:016x}_b.json": {"size": 1} for n in range(65)}
        def forbidden(*args):
            self.fail("Must not access device after an incomplete inventory")
        with self.assertRaisesRegex(RuntimeError, "temporarily incomplete"):
            inventory.reconcile_listing({}, expected, Path("/unused"), forbidden, "remote")


if __name__ == "__main__":
    unittest.main()
