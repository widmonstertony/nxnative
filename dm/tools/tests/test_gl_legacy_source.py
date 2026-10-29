"""Compile legacy GL source with real glslang/SPIRV-Cross, without game assets."""
import hashlib,importlib.util,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('gl_shaders',ROOT/'dm/gfx/tools/gl_shaders.py')
assert spec is not None and spec.loader is not None
gl=importlib.util.module_from_spec(spec);spec.loader.exec_module(gl)
class LegacyGL(unittest.TestCase):
    def test_real_translation_and_metal_compilation(self):
        sources=[('vert',b'attribute vec4 POSITION;\nuniform mat4 gMVP;\nvoid main(){gl_Position=gMVP*POSITION;}'),
                 ('frag',b'void main(){gl_FragColor=vec4(1.0);}'),
                 ('vert',b'#version 120\nvarying vec2 uv; attribute vec4 pos; void main(){uv=pos.xy;gl_Position=pos;}'),
                 ('frag',b'#version 120\nvarying vec2 uv; uniform sampler2D image;void main(){gl_FragColor=texture2D(image,uv);}')]
        with tempfile.TemporaryDirectory() as d:
            for stage,source in sources:
                with self.subTest(stage=stage,source=source):
                    key=hashlib.sha256(source).hexdigest()[:16]
                    result=gl.translate(source,stage,key,d);self.assertIsInstance(result,tuple,result)
                    msl,fields=result;self.assertIn('gl_'+key+'_'+stage[0],pathlib.Path(msl).read_text())
                    r=subprocess.run(['xcrun','-sdk','iphoneos','metal','-c','-mios-version-min=16.1',msl,'-o',str(pathlib.Path(d)/(key+'.air'))],capture_output=True,text=True)
                    self.assertEqual(r.returncode,0,r.stderr)
                    if b'POSITION' in source:self.assertTrue(any(f.startswith('a:POSITION=') for f in fields))
    def test_modern_source_unchanged(self):
        source='#version 320 es\nprecision highp float; void main(){}\n'
        self.assertEqual(gl.legacy_interface(source,'frag'),source)
    def test_appledouble_is_not_a_shader(self):
        with tempfile.TemporaryDirectory() as d:
            p=pathlib.Path(d);(p/'one.vert').write_bytes(b'void main(){}')
            (p/'._one.vert').write_bytes(b'\x00\x05\x16\x07\x00\x02\x00\x00metadata')
            (p/'._real.vert').write_bytes(b'void main(){}')
            self.assertEqual(len(list(gl.sources([d]))),2)
if __name__=='__main__':unittest.main()
