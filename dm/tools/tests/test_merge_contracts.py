"""Cross-component contracts that an upstream/compatibility merge must preserve.

No owned game binary, shader cache or device is used.
"""
import ast
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'dm/games'))
import game
import runtime_profiles


class Profiles(unittest.TestCase):
    def test_every_generated_constant_has_a_runtime_representation(self):
        # A newly merged game.py constant must never silently use another title's
        # compile-time default in the unified host.
        special = {'MODULES', 'NMOD', 'DISPLAY_VERSIONS', 'SHARED_FONT_TTF',
                   'NVN_API_MAJOR', 'NVN_API_MINOR'}
        for p in game.all_games():
            names = set(runtime_profiles.constants(p))
            self.assertFalse(names - set(runtime_profiles.FIELDS) - special, p.id)

    def test_new_engine_values_remain_per_title_after_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            profiles = []
            for i in range(2):
                p = root / f'010000000000000{i}'; p.mkdir()
                template = (REPO / 'dm/games/01001F5010DFA000/game.tsv').read_text()
                overrides = {'title_id': p.name, 'program_id': p.name,
                             'name': f'Fixture {i}', 'ue_texture_pool': str(256 + i),
                             'ue_fps_cvar': f'Frame.Limit{i}',
                             'enc_thread': 'on' if i else 'off',
                             'shader_key_skip': f'{hex(0x760 + i * 16)}+{hex(8 + i * 8)}'}
                rows = [line for line in template.splitlines()
                        if line.split('\t', 1)[0] not in overrides]
                rows += [f'{key}\t{value}' for key, value in overrides.items()]
                p.joinpath('game.tsv').write_text('\n'.join(rows) + '\n')
                profiles.append(game.Game(p))
            runtime_profiles.generate(root / 'gen', profiles)
            code = '''#include "game_profile.h"
#include <assert.h>
#include <stdlib.h>
#include <string.h>
int main(int argc,char **argv){int i=atoi(argv[1]);
 assert(argc==2); assert(dm_profile_select(i?"0100000000000001":"0100000000000000"));
 assert(DM_GAME_UE_TEXTURE_POOL==256+i); assert(DM_GAME_ENC_THREAD==i);
 assert(!strcmp(DM_GAME_UE_FPS_CVAR,i?"Frame.Limit1":"Frame.Limit0"));
 assert(DM_GAME_SHADER_KEY_SKIP_OFF==0x760+16*i); assert(DM_GAME_SHADER_KEY_SKIP_LEN==8+8*i);
 assert(!dm_profile_select(i?"0100000000000000":"0100000000000001")); return 0;}
'''
            root.joinpath('test.c').write_text(code)
            subprocess.run(['clang', '-Wall', '-Werror', '-fsanitize=address,undefined',
                            '-I', str(root / 'gen'), '-I', str(REPO / 'dm/host'),
                            str(root / 'test.c'), str(root / 'gen/game_profile_runtime.c'),
                            '-o', str(root / 'test')], check=True)
            for i in range(2): subprocess.run([str(root / 'test'), str(i)], check=True)


class SignedEmbedding(unittest.TestCase):
    PG = 0x4000

    def fixture(self, root, name, negative=False):
        pg = self.PG
        root.joinpath(name + '.patched.bin').write_bytes(
            b''.join(bytes([i + 1]) * pg for i in range(5)))
        fields = dict(TEXT_END=pg, PATCH_OFF=-pg if negative else pg * 3,
                      KEY_PAGE_OFF=pg * (6 if negative else 2), KEY_PAGE_SIZE=pg,
                      FILE_IMAGE_LEN=pg * 3, BACK_LEN=pg if negative else 0)
        root.joinpath(name + '.fixups.tsv').write_text(
            ''.join(f'# {key} {value:#x}\n' for key, value in fields.items()))

    def embed(self, root, names, namespace=None):
        args = [sys.executable, str(REPO / 'dm/ios/tools/gen_embed.py')]
        if namespace: args += ['--namespace', namespace]
        return subprocess.run(args + [str(root), str(root / 'embed.S')] + names,
                              capture_output=True, text=True)

    def sections(self, root):
        subprocess.run(['xcrun', '-sdk', 'iphoneos', 'clang', '-arch', 'arm64',
                        '-c', str(root / 'embed.S'), '-o', str(root / 'embed.o')], check=True)
        data = root.joinpath('embed.o').read_bytes()
        self.assertEqual(struct.unpack_from('<I', data)[0], 0xfeedfacf)
        result, at = {}, 32
        for _ in range(struct.unpack_from('<I', data, 16)[0]):
            cmd, size = struct.unpack_from('<II', data, at)
            if cmd == 0x19:
                for n in range(struct.unpack_from('<I', data, at + 64)[0]):
                    sec = at + 72 + n * 80
                    name, segment, _, length, offset = struct.unpack_from('<16s16sQQI', data, sec)
                    result[(segment.rstrip(b'\0').decode(), name.rstrip(b'\0').decode())] = data[offset:offset + length]
            at += size
        return result

    def test_signed_contiguous_text_keeps_rw_hole_and_exact_patch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.fixture(root, 'main')
            output = self.embed(root, ['main'], '00')
            self.assertEqual(output.returncode, 0, output.stderr)
            self.assertEqual(output.stdout.count('-segprot,__DM00mainW,rw,rw'), 1)
            sec = self.sections(root); pg = self.PG
            self.assertEqual(sec['__TEXT', '__dm00mainimg'],
                             b'\1' * pg + b'\0' * (pg * 2) + b'\4' * pg + b'\5' * pg)
            self.assertEqual(sec['__DM00mainW', '__img'], b'\2' * pg + b'\3' * pg)

    def test_upstream_negative_backpatch_preserves_both_code_ends(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.fixture(root, 'main', negative=True)
            output = self.embed(root, ['main'])
            self.assertEqual(output.returncode, 0, output.stderr)
            self.assertEqual(output.stdout.count('-segprot,__DMmainW,rw,rw'), 1)
            sec = self.sections(root); pg = self.PG
            self.assertEqual(sec['__TEXT', '__dmmainx0'], b'\1' * pg)
            self.assertEqual(sec['__DMmainW', '__img'], b'\2' * pg + b'\3' * pg)
            self.assertEqual(sec['__TEXT', '__dmmainx1'], b'\4' * pg)
            self.assertEqual(sec['__TEXT', '__dmmainx2'], b'\5' * pg)

    def test_packed_nro_table_and_namespaced_refusal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); self.fixture(root, 'main'); self.fixture(root, 'nro0')
            root.joinpath('nro.tsv').write_text('nro0\tfixture\n')
            output = self.embed(root, ['main'])
            self.assertEqual(output.returncode, 0, output.stderr)
            sec = self.sections(root); table = sec['__DATA', '__dm_nro_tab']
            self.assertEqual(len(table), 80)
            self.assertEqual(table[:32].rstrip(b'\0'), b'nro0')
            self.assertEqual(struct.unpack_from('<6Q', table, 32),
                             (0, self.PG, 0, self.PG * 2, 0, self.PG * 2))
            output = self.embed(root, ['main'], '00')
            self.assertNotEqual(output.returncode, 0)
            self.assertIn('namespaced NRO', output.stderr)


class ObservationABI(unittest.TestCase):
    def test_persisted_gates_and_new_upstream_region_do_not_collide(self):
        header = (REPO / 'dm/host/dm.h').read_text()
        ids = dict((k, int(v)) for k, v in re.findall(r'\b(OBS_[A-Z_]+)\s*=\s*(\d+)', header))
        self.assertEqual(len(ids.values()), len(set(ids.values())))
        self.assertEqual(ids['OBS_ZA_CLOCK_DELTA'], 26)
        self.assertEqual(ids['OBS_ARCEUS_TASK_TRACE'], 36)
        self.assertEqual(ids['OBS_UE_REGION'], 37)
        tree = ast.parse((REPO / 'dm/tools/patch_nso.py').read_text())
        emitted = {}
        for node in tree.body:
            if not isinstance(node, ast.Assign): continue
            try: value = ast.literal_eval(node.value)
            except (ValueError, TypeError): continue
            for target in node.targets:
                if isinstance(target, (ast.Tuple, ast.List)) and isinstance(value, (tuple, list)):
                    emitted.update((key.id, val) for key, val in zip(target.elts, value)
                                   if isinstance(key, ast.Name) and key.id.startswith('OBS_'))
        for key, value in emitted.items():
            self.assertEqual(ids[key], value, key)


if __name__ == '__main__': unittest.main()
