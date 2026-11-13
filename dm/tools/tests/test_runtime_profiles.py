"""Profile selection stays locked until a completed independent-engine teardown."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'dm/games'))
from game import Game
from runtime_profiles import generate


@unittest.skipUnless(shutil.which('clang'), 'needs clang')
class ProfileSelection(unittest.TestCase):
    def test_only_the_selected_profile_can_release_the_switch_gate(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            profiles = []
            for suffix in ('001', '002'):
                title = '0100000000F0F' + suffix
                folder = p / title
                folder.mkdir()
                (folder / 'game.tsv').write_text(
                    f'title_id\t{title}\nname\tTest\nprogram_id\t{title}\n'
                    'modules\tmain\nromfs_marker\tromfs.img\n'
                    'mem_reserve\t0x100000\nmem_alias\t0x100000\n'
                    'mem_stack\t0x100000\napp_pool\t0x100000\n'
                    'build\tv0\t1.0.0\tmain=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n')
                profiles.append(Game(folder))
            generate(p, profiles)
            (p / 'test.c').write_text(r'''
#include "game_profile_runtime.h"
#include <assert.h>
int main(void) {
    const dm_game_profile *a = dm_profile_find("0100000000f0f001");
    const dm_game_profile *b = dm_profile_find("0100000000F0F002");
    assert(a && b && a != b);
    assert(!dm_profile_release_selection(0));
    assert(dm_profile_select(a->id));
    assert(!dm_profile_select(b->id));
    assert(!dm_profile_release_selection(b));
    assert(!dm_profile_release_selection(0));
    assert(dm_profile_current() == a);
    assert(!dm_profile_select(b->id));
    assert(dm_profile_release_selection(a));
    assert(dm_profile_select(b->id));
    assert(dm_profile_current() == b);
    assert(!dm_profile_release_selection(a));
    assert(dm_profile_release_selection(b));
    assert(dm_profile_select(a->id));
}
''')
            subprocess.run(['clang', '-Wall', '-Werror', '-I', str(ROOT / 'dm/host'),
                            str(p / 'game_profile_runtime.c'), str(p / 'test.c'),
                            '-o', str(p / 'test')], check=True)
            subprocess.run([str(p / 'test')], check=True)
