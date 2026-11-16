"""External-volume AppleDouble sidecars are not shader-table inputs."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'
KEY = '0000000000000001'


class ShaderTableMetadata(unittest.TestCase):
    def test_binary_metadata_is_ignored_and_real_shader_is_analyzed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            shaders = root / 'b-fixture'
            shaders.mkdir()
            source = 'uint4 c = (*vp_c1)._m0[unknown];\nuint4 a = (*spvDescriptorSet0.vp_c3)._m0[2u];\n'
            reflection = {'c1': '00' * 16, 'bindings': [{'kind': 'cbuf', 'reg': 3, 'msl_name': 'vp_c3'}]}
            (shaders / (KEY + '_b.metal')).write_text(source)
            (shaders / (KEY + '_b.json')).write_text(json.dumps(reflection))
            # This metadata binary reproduces the UTF-8 failure from exFAT.
            metadata = b'\x00\x05\x16\x07' + b'\xb0' * 64
            (shaders / ('._' + KEY + '_b.metal')).write_bytes(metadata)
            (shaders / ('._' + KEY + '_b.json')).write_bytes(metadata)
            for tool, expected in [('c1_guard.py', KEY), ('cb_extent.py', KEY + '\t3:48')]:
                with self.subTest(tool=tool):
                    output = root / (tool + '.tsv')
                    run = subprocess.run([sys.executable, str(TOOLS / tool), str(shaders), str(output)],
                                         capture_output=True, text=True, timeout=60)
                    self.assertEqual(run.returncode, 0, run.stderr)
                    rows = [line for line in output.read_text().splitlines() if line and not line.startswith('#')]
                    self.assertEqual(rows, [expected])


if __name__ == '__main__':
    unittest.main()
