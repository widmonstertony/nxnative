"""The offline dual-source entry must preserve normal MRT and fetch variants."""
import ast
from pathlib import Path
import re
import sys
import unittest
from typing import Any
TOOLS = Path(__file__).resolve().parents[2] / 'gfx/tools'
sys.path.insert(0, str(TOOLS))
import dmsh_fetch
ns: dict[str, Any] = {'re': re}
nodes: list[ast.stmt] = [n for n in ast.parse((TOOLS / 'dmsh_build.py').read_text()).body if isinstance(n, ast.FunctionDef) and n.name == 'fs_dual']
exec(compile(ast.Module(body=nodes, type_ignores=[]), 'dmsh_build.py', 'exec'), ns)
SOURCE = """#include <metal_stdlib>
using namespace metal;
struct main0_out
{
    float4 a [[color(0)]];
    float4 b [[color(1)]];
    float z [[depth(any)]];
};
fragment main0_out main0()
{
    main0_out out = {};
    out.a = float4(.1);
    out.b = float4(.6);
    out.z = .75;
    return out;
}
"""
class DualSource(unittest.TestCase):
    def test_secondary_remap_preserves_values_and_depth(self):
        extra = ns['fs_dual'](SOURCE)
        self.assertIn('float4 b [[color(0), index(1)]];', extra)
        self.assertIn('float z [[depth(any)]];', extra)
        self.assertIn('return main0_out_d{out.a, out.b, out.z};', extra)
        self.assertIn('out.b = float4(.6);', extra)
        self.assertIn('float4 b [[color(1)]];', SOURCE + extra)
    def test_no_secondary_and_integer_outputs_do_not_get_float_variant(self):
        for src in [SOURCE.replace('color(1)', 'color(2)'), SOURCE.replace('float4 b', 'uint4 b')]:
            self.assertIsNone(ns['fs_dual'](src))
    def test_fetch_generator_uses_only_original_entry(self):
        plain = SOURCE.replace('float z [[depth(any)]];','').replace('    out.z = .75;\n','').replace(' a ', ' m_0 ').replace(' b ', ' m_1 ').replace('out.a', 'out.m_0').replace('out.b', 'out.m_1')
        base, _ = dmsh_fetch.variant(plain, [], om_only_ok=True)
        with_dual, _ = dmsh_fetch.variant(plain + ns['fs_dual'](plain), [], om_only_ok=True)
        self.assertIsNotNone(base)
        assert base is not None and with_dual is not None
        self.assertEqual(base.rstrip(), with_dual.rstrip())
if __name__ == '__main__': unittest.main()
