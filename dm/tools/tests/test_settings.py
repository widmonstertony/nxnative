"""Offer the resolution control only when the rewritten build supports it."""
from pathlib import Path
import sys,tempfile,unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'games'))
import settings

class ResolutionSetting(unittest.TestCase):
    def test_verified_rewrite_required(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(settings.nacp,'languages',return_value=['en-US']):
            p=Path(tmp)/'main.fixups.tsv'
            for header,supported in [('# BUILD_ID\t3c10ec35c5ef4c3686b4053afb0e58e7\n',False),
                                     ('# DYNAMIC_RESOLUTION\t1\n',True),('',False)]:
                p.write_text(header)
                rows=settings.build('010056B015FE8000',tmp,'unused')['settings']
                dr=[s for s in rows if s['env']=='DM_DYNAMIC_RESOLUTION']
                self.assertEqual(bool(dr),supported)
                if dr:self.assertEqual((dr[0]['kind'],dr[0]['default']),('toggle','0'))
                fps=next(s for s in rows if s['env']=='DM_FPS_TARGET')
                self.assertEqual(fps['default'],'60')
                self.assertEqual(fps['options'],[['30','30 fps'],['60','60 fps']])

class ArceusFrameGeneration(unittest.TestCase):
    def test_exact_build_capability_controls_defaults(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(settings.nacp,'languages',return_value=['en-US']):
            p=Path(tmp)/'main.fixups.tsv'
            for header,supported in [('',False),('# ARCEUS_TIMING\t1\n',True)]:
                p.write_text(header)
                rows={r['env']:r for r in settings.build('01007EF00011E000',tmp,'unused')['settings']}
                self.assertEqual('DM_FRAMEGEN' in rows,supported)
                if supported:
                    self.assertEqual(rows['DM_FRAMEGEN']['default'],'opticalflow')
                    self.assertEqual(rows['DM_OPMODE']['default'],'0')
                    self.assertEqual(rows['DM_PRESENT_UPSCALE']['default'],'metalfx')
                    self.assertIn(['off','Off'],rows['DM_FRAMEGEN']['options'])

if __name__=='__main__':unittest.main()
