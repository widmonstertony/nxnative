#!/usr/bin/env python3
"""Run the production data importer on complete/corrupt/hostile inboxes."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ResourceImport(unittest.TestCase):
    def test_import_integrity_and_existing_data(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            harness = root / 'test.m'
            harness.write_text('''#import "ResourceImport.h"
int main(int argc,char **argv){@autoreleasepool{
    NSString *documents=[NSString stringWithUTF8String:argv[1]];
    NSMutableArray *r=[NSMutableArray new];
    if(argc>2){id tasks=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[2]]] options:0 error:nil];
        [r addObjectsFromArray:TonTonSeedResourceImportTasks(documents,tasks)];}
    [r addObjectsFromArray:TonTonImportPendingResources(documents)];
    NSData *json=[NSJSONSerialization dataWithJSONObject:r options:0 error:nil];
    fwrite(json.bytes,1,json.length,stdout);
}}''')
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wno-deprecated-declarations',
                            '-framework', 'Foundation', '-I', str(ROOT / 'LibraryApp/Sources'),
                            str(harness), '-o', str(root / 'test')], check=True)

            def run(case, mutate=lambda *_: None):
                documents = root / case
                inbox = documents / 'TonTonIncoming/test'
                inbox.mkdir(parents=True)
                chunks = []
                content = b''
                for i, data in enumerate([b'owned first chunk', bytes(range(256)) * 8192]):
                    digest = hashlib.sha256(data).hexdigest()
                    name = f'{i:04d}-{digest}.part'
                    (inbox / name).write_bytes(data)
                    chunks.append(dict(file=name, bytes=len(data), sha256=digest))
                    content += data
                manifest = dict(schema=1, game_id='sample', resource_name='game.zip', bytes=len(content),
                                sha256=hashlib.sha256(content).hexdigest(), chunks=chunks,
                                card=dict(name='Owned test game', version='1.2'))
                save = documents / 'Games/sample/UserData/save/main'
                save.parent.mkdir(parents=True)
                save.write_bytes(b'never change this save')
                mutate(documents, inbox, manifest)
                (inbox / 'ImportTask.json').write_text(json.dumps(manifest))
                result = json.loads(subprocess.check_output([str(root / 'test'), str(documents)]))
                self.assertEqual(save.read_bytes(), b'never change this save')
                return documents, inbox, content, result

            docs, inbox, content, result = run('complete')
            self.assertEqual(result[0]['status'], 'imported')
            self.assertEqual((docs / 'Games/sample/Resources/game.zip').read_bytes(), content)
            self.assertEqual(json.loads((docs / 'Games/sample/GameCard.json').read_text())['version'], '1.2')
            self.assertEqual(len(list(inbox.glob('*.part'))), 2)  # inputs retained
            self.assertEqual(json.loads(subprocess.check_output([str(root / 'test'), str(docs)])), [])
            (inbox / 'ImportResult.json').unlink()
            self.assertEqual(json.loads(subprocess.check_output([str(root / 'test'), str(docs)]))[0]['status'], 'imported')

            def corrupt(documents, inbox, manifest):
                path = inbox / manifest['chunks'][1]['file']
                path.write_bytes(b'x' * path.stat().st_size)
            docs, inbox, _, result = run('corrupt', corrupt)
            self.assertEqual(result[0]['status'], 'failed')
            self.assertFalse((docs / 'Games/sample/Resources/game.zip').exists())
            self.assertEqual(list(inbox.glob('.assembling-*')), [])

            for key, value in [('game_id', '../escape'), ('resource_name', '../file.zip'),
                               ('resource_name', 'DmGame.framework'), ('bytes', 1), ('sha256', '0' * 64)]:
                _, _, _, result = run(f'invalid-{key}-{len(list(root.iterdir()))}',
                                       lambda d, i, m, k=key, v=value: m.update({k: v}))
                self.assertEqual(result[0]['status'], 'failed')

            def duplicate(d, i, m): m['chunks'][1] = m['chunks'][0]
            self.assertEqual(run('duplicate', duplicate)[3][0]['status'], 'failed')

            def symlink(d, i, m):
                path = i / m['chunks'][0]['file']
                outside = root / 'outside'
                outside.write_bytes(path.read_bytes())
                path.unlink()
                path.symlink_to(outside)
            self.assertEqual(run('symlink', symlink)[3][0]['status'], 'failed')

            def existing(d, i, m):
                path = d / 'Games/sample/Resources/game.zip'
                path.parent.mkdir()
                path.write_bytes(b'keep original resource')
            docs, _, _, result = run('existing', existing)
            self.assertEqual(result[0]['status'], 'failed')
            self.assertEqual((docs / 'Games/sample/Resources/game.zip').read_bytes(), b'keep original resource')

            def empty_romfs(d, i, m):
                m.update(resource_name='romfs.img', replace_empty_placeholder=True)
                path = d / 'Games/sample/Resources/romfs.img'
                path.parent.mkdir()
                path.touch()
            docs, _, content, result = run('empty-romfs-explicit', empty_romfs)
            self.assertEqual(result[0]['status'], 'imported')
            self.assertEqual((docs / 'Games/sample/Resources/romfs.img').read_bytes(), content)
            retained = docs / 'Games/sample/Resources' / result[0]['retained_empty_placeholder']
            self.assertTrue(retained.is_file())
            self.assertEqual(retained.read_bytes(), b'')

            def empty_without_opt_in(d, i, m):
                empty_romfs(d, i, m)
                m.pop('replace_empty_placeholder')
            docs, _, _, result = run('empty-romfs-default', empty_without_opt_in)
            self.assertEqual(result[0]['status'], 'failed')
            self.assertEqual((docs / 'Games/sample/Resources/romfs.img').read_bytes(), b'')

            def corrupt_empty(d, i, m):
                empty_romfs(d, i, m)
                corrupt(d, i, m)
            docs, _, _, result = run('corrupt-empty-romfs', corrupt_empty)
            self.assertEqual(result[0]['status'], 'failed')
            self.assertEqual((docs / 'Games/sample/Resources/romfs.img').read_bytes(), b'')
            self.assertEqual(list((docs / 'Games/sample/Resources').glob('*.empty-before-import-*')), [])

            def nonempty_opt_in(d, i, m):
                empty_romfs(d, i, m)
                (d / 'Games/sample/Resources/romfs.img').write_bytes(b'original game')
            docs, _, _, result = run('nonempty-romfs-opt-in', nonempty_opt_in)
            self.assertEqual(result[0]['status'], 'failed')
            self.assertEqual((docs / 'Games/sample/Resources/romfs.img').read_bytes(), b'original game')

            def linked_empty(d, i, m):
                empty_romfs(d, i, m)
                path = d / 'Games/sample/Resources/romfs.img'
                outside = root / 'empty-outside'
                outside.touch()
                path.unlink()
                path.symlink_to(outside)
            docs, _, _, result = run('linked-empty-romfs', linked_empty)
            self.assertEqual(result[0]['status'], 'failed')
            self.assertTrue((docs / 'Games/sample/Resources/romfs.img').is_symlink())

            # Metadata delivered in the app bundle needs no external write into
            # another app's sandbox. Only existing transfer directories qualify.
            docs, inbox, content, _ = run('seed-task')
            manifest = json.loads((inbox / 'ImportTask.json').read_text())
            (inbox / 'ImportTask.json').unlink()
            (inbox / 'ImportResult.json').unlink()
            seed = root / 'bundled-tasks.json'
            seed.write_text(json.dumps([dict(inbox='test', manifest=manifest)]))
            result = json.loads(subprocess.check_output([str(root / 'test'), str(docs), str(seed)]))
            self.assertEqual(result[0]['status'], 'imported')
            self.assertEqual((docs / 'Games/sample/Resources/game.zip').read_bytes(), content)
            original = (inbox / 'ImportTask.json').read_bytes()
            seed.write_text(json.dumps([dict(inbox='test', manifest={'schema': 'invalid'})]))
            self.assertEqual(json.loads(subprocess.check_output([str(root / 'test'), str(docs), str(seed)])), [])
            self.assertEqual((inbox / 'ImportTask.json').read_bytes(), original)
            for name in ['../escape', '/outside', 'test/child']:
                seed.write_text(json.dumps([dict(inbox=name, manifest=manifest)]))
                result = json.loads(subprocess.check_output([str(root / 'test'), str(docs), str(seed)]))
                self.assertEqual(result[0]['status'], 'failed')
            (docs / 'TonTonIncoming/link').symlink_to(inbox, target_is_directory=True)
            seed.write_text(json.dumps([dict(inbox='link', manifest=manifest)]))
            result = json.loads(subprocess.check_output([str(root / 'test'), str(docs), str(seed)]))
            self.assertEqual(result[0]['status'], 'failed')
            seed.write_text(json.dumps([dict(inbox='missing', manifest=manifest)]))
            self.assertEqual(json.loads(subprocess.check_output([str(root / 'test'), str(docs), str(seed)])), [])
            self.assertFalse((docs / 'TonTonIncoming/missing').exists())


if __name__ == '__main__': unittest.main()
