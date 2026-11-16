from pathlib import Path
import subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[3]
class AudioBuffer(unittest.TestCase):
    def test_title_specific_request(self):
        code="""
#include <assert.h>
#include "DmAudioBuffer.h"
int main(void){
assert(dm_audio_buffer_seconds(0)==0.005);
assert(dm_audio_buffer_seconds("")==0.005);
assert(dm_audio_buffer_seconds("01001F5010DFA000")==0.005);
assert(dm_audio_buffer_seconds("010029b0118e8000")==0.0025);
assert(dm_audio_buffer_seconds("010029B0118E8000")==0.0025);
assert(dm_audio_buffer_seconds("010029B0118E8000bad")==0.005);
return 0;}
"""
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/'policy.c';p.write_text(code);out=Path(td)/'policy'
            subprocess.run(['xcrun','clang','-Wall','-Werror','-I',str(ROOT/'dm/ios/Sources'),str(p),'-o',str(out)],check=True)
            subprocess.run([str(out)],check=True)
if __name__=='__main__':unittest.main()
