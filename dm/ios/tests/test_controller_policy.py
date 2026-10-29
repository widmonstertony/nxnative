#!/usr/bin/env python3
"""Test native input bits and the complete controller visibility truth table."""
from pathlib import Path
import subprocess, tempfile, unittest
ROOT=Path(__file__).resolve().parents[3]
class ControllerPolicy(unittest.TestCase):
    def test_controller_letters_and_hotplug_visibility(self):
        code=r'''
#include <assert.h>
#include "DmControllerPolicy.h"
int main(void) {
 assert(dm_controller_is_backbone("Backbone One"));
 assert(dm_controller_is_backbone("BACKBONE"));
 assert(dm_controller_is_backbone("MFi Backbone Pro"));
 assert(!dm_controller_is_backbone("Switch Pro Controller"));
 assert(!dm_controller_is_backbone(0)); assert(!dm_controller_is_backbone("backbon"));
 for(int bits=0;bits<16;bits++) {
  int a=bits&1,b=bits&2,x=bits&4,y=bits&8;
  assert(dm_controller_face_buttons(a,b,x,y,1)==(uint64_t)bits);
  uint64_t n=(a?DM_BTN_B:0)|(b?DM_BTN_A:0)|(x?DM_BTN_Y:0)|(y?DM_BTN_X:0);
  assert(dm_controller_face_buttons(a,b,x,y,0)==n);
 }
 for(int bits=0;bits<32;bits++) {
  int controller=bits&1,keyboard=bits&2,mouse=bits&4,touch=bits&8,keep=bits&16;
  int hidden=dm_controller_hides_touch(controller,keyboard,mouse,touch,keep);
  if(controller) assert(hidden);
  else if(keep) assert(!hidden);
  else assert(hidden==!!(keyboard||(mouse&&!touch)));
 }
 // Already attached, unplugged, and reattached while keep-touch is enabled.
 assert(dm_controller_hides_touch(1,0,0,0,1));
 assert(!dm_controller_hides_touch(0,0,0,0,1));
 assert(dm_controller_hides_touch(1,0,0,1,1));
 return 0;
}
'''
        with tempfile.TemporaryDirectory() as t:
            c=Path(t)/'policy.c';exe=Path(t)/'policy';c.write_text(code)
            subprocess.run(['xcrun','clang','-Wall','-Werror','-I',str(ROOT/'dm/ios/Sources'),'-I',str(ROOT/'dm/host'),str(c),'-o',str(exe)],check=True)
            subprocess.run([str(exe)],check=True)
if __name__=='__main__':unittest.main()
