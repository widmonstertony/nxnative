"""Regress nested legacy companions disappearing from a resource-only update."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location('shader_resource_archive', Path(__file__).parents[1] / 'tools/shader_resource_archive.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class ShaderArchiveTests(unittest.TestCase):
    def test_nested_and_base_resources_roundtrip(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'b-test'; root.mkdir()
            (root / 'base.metallib').write_bytes(b'library')
            companion = root / 'nonpoint-v1'; companion.mkdir()
            (companion / 'shader.metal').write_bytes(b'point-size variant')
            (companion / 'manifest.json').write_text('{}')
            archive = Path(folder) / 'all.zip'
            files = mod.package(root, archive, 'msl/b-test')
            self.assertEqual(len(files), 3)
            self.assertIn('msl/b-test/nonpoint-v1/shader.metal', files)
            # The previous top-level-only archive must fail completeness.
            broken = Path(folder) / 'broken.zip'
            with zipfile.ZipFile(broken, 'w') as output:
                output.write(root / 'base.metallib', 'msl/b-test/base.metallib')
            with self.assertRaises(ValueError): mod.verify(broken, files)
            delta = mod.package(root, Path(folder) / 'delta.zip', companions_only=True)
            self.assertEqual(set(delta), {'nonpoint-v1/shader.metal', 'nonpoint-v1/manifest.json'})

    def test_reject_symlink_and_overwrite(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'tree'; root.mkdir()
            (root / 'file').write_bytes(b'x')
            archive = Path(folder) / 'all.zip'
            mod.package(root, archive)
            with self.assertRaises(FileExistsError): mod.package(root, archive)
            (root / 'link').symlink_to(root / 'file')
            with self.assertRaises(ValueError): mod.inventory(root)


if __name__ == '__main__': unittest.main()
