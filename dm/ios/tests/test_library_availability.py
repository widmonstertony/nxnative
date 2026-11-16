#!/usr/bin/env python3
"""Exercise first-launch cartridges and interrupted resource transfers."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


class LibraryAvailability(unittest.TestCase):
    def test_filesystem_readiness(self):
        harness = r'''
#import <Foundation/Foundation.h>
#import "LibraryAvailability.h"
#include <assert.h>
static const dm_game_profile profile={.romfs_marker="data/marker.bin"};
const dm_game_profile *dm_profile_find(const char *id) {
    return !strcmp(id,"0100000000000000") ? &profile : NULL;
}
static void writeFile(NSString *p, NSString *text) {
    [NSFileManager.defaultManager createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    assert([text writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]);
}
static void expect(NSString *root, NSString *bundle, NSString *code) {
    NSDictionary *s=TonTonGameReadiness(@"0100000000000000",root,bundle);
    assert([s[@"code"] isEqual:code]); assert([s[@"ready"] boolValue]==[code isEqual:@"ready"]);
}
int main(int argc,char **argv) {@autoreleasepool{
    NSString *root=[NSString stringWithUTF8String:argv[1]],*bundle=[root stringByAppendingPathComponent:@"bundled"];
    NSString *slot=[root stringByAppendingPathComponent:@"0100000000000000"];
    NSString *res=[slot stringByAppendingPathComponent:@"Resources"];
    NSString *stamp=[res stringByAppendingPathComponent:@"msl/b-" DMSH_CHAIN "/inputs.tsv"];
    expect(root,bundle,@"shader_resources_missing");
    writeFile([res stringByAppendingPathComponent:@"dm/shader_map.tsv"],@"map");
    writeFile(stamp,@"game\t0100000000000001\n");
    expect(root,bundle,@"shader_identity_mismatch");
    writeFile(stamp,@"# identity\ngame\t0100000000000000\ninputs\t123\n");
    expect(root,bundle,@"game_data_incomplete");
    NSString *romfs=[res stringByAppendingPathComponent:@"romfs.img"];
    writeFile(romfs,@""); expect(root,bundle,@"game_data_incomplete");
    writeFile(romfs,@"data"); expect(root,bundle,@"ready");
    // No UserData/save folder exists: the runtime creates it at first boot.
    assert(![NSFileManager.defaultManager fileExistsAtPath:[slot stringByAppendingPathComponent:@"UserData"]]);
    [NSFileManager.defaultManager removeItemAtPath:romfs error:nil];
    [NSFileManager.defaultManager createDirectoryAtPath:romfs withIntermediateDirectories:YES attributes:nil error:nil];
    expect(root,bundle,@"game_data_incomplete");
    [NSFileManager.defaultManager removeItemAtPath:romfs error:nil];
    writeFile([slot stringByAppendingPathComponent:@"UserData/romfs/data/marker.bin"],@"marker");
    expect(root,bundle,@"ready");
    [NSFileManager.defaultManager removeItemAtPath:[slot stringByAppendingPathComponent:@"UserData"] error:nil];
    writeFile([res stringByAppendingPathComponent:@"romfs/data/marker.bin"],@"marker");
    expect(root,bundle,@"ready");
    assert([TonTonGameReadiness(@"unknown",root,bundle)[@"code"] isEqual:@"host_missing"]);
    // Both supported bundle layouts retain first-launch behavior.
    NSString *bundledSlot=[bundle stringByAppendingPathComponent:@"0100000000000000"];
    assert([NSFileManager.defaultManager moveItemAtPath:slot toPath:bundledSlot error:nil]);
    expect(root,bundle,@"ready");
    assert([NSFileManager.defaultManager moveItemAtPath:[bundledSlot stringByAppendingPathComponent:@"Resources"] toPath:[root stringByAppendingPathComponent:@"flat"] error:nil]);
    [NSFileManager.defaultManager removeItemAtPath:bundledSlot error:nil];
    assert([NSFileManager.defaultManager moveItemAtPath:[root stringByAppendingPathComponent:@"flat"] toPath:bundledSlot error:nil]);
    expect(root,bundle,@"ready");
    puts("11 cartridge readiness checks passed");
}}
'''
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            (p / 'test.m').write_text(harness)
            # Use the production profile ABI, with one asset-free test profile.
            profile_dir = p / 'include'
            profile_dir.mkdir()
            (profile_dir / 'game_profile_runtime.h').write_text(
                '#include <string.h>\ntypedef struct {const char *romfs_marker;} dm_game_profile;\n'
                'const dm_game_profile *dm_profile_find(const char *);\n')
            (profile_dir / 'dmsh_chain.h').write_text('#define DMSH_CHAIN "testchain"\n')
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-framework', 'Foundation',
                            '-I', str(profile_dir), '-I', str(ROOT / 'dm/ios/LibraryApp/Sources'),
                            str(p / 'test.m'), '-o', str(p / 'test')], check=True)
            fixture = p / 'fixture'
            (fixture / 'bundled').mkdir(parents=True)
            subprocess.run([str(p / 'test'), str(fixture)], check=True)


if __name__ == '__main__':
    unittest.main()
