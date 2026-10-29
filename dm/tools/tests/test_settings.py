"""Offer the resolution control only when the rewritten build supports it."""
from pathlib import Path
import sys,tempfile,unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'games'))
import settings

class ArceusFrameGeneration(unittest.TestCase):
    def test_exact_build_capability_controls_defaults(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(settings.nacp,'languages',return_value=['en-US']),patch.dict(settings.os.environ,DM_IOS_RENDERER='metal4'):
            p=Path(tmp)/'main.fixups.tsv'
            for header,supported in [('',False),('# ARCEUS_TIMING\t1\n',True),('# ZA_TIMING\t1\n',True)]:
                p.write_text(header)
                rows={r['env']:r for r in settings.build('01007EF00011E000',tmp,'unused')['settings']}
                self.assertEqual('DM_FRAMEGEN' in rows,supported)
                if supported:
                    self.assertEqual(rows['DM_FRAMEGEN']['default'],'opticalflow')
                    self.assertEqual(rows['DM_OPMODE']['default'],'0')
                    self.assertEqual(rows['DM_PRESENT_UPSCALE']['default'],'metalfx')
                    self.assertIn(['off','Off'],rows['DM_FRAMEGEN']['options'])

    def test_legacy_build_does_not_offer_unimplemented_interpolation(self):
        with tempfile.TemporaryDirectory() as tmp,patch.object(settings.nacp,'languages',return_value=['en-US']),patch.dict(settings.os.environ,DM_IOS_RENDERER='legacy',SETTINGS_PLATFORM='ios'):
            (Path(tmp)/'main.fixups.tsv').write_text('# ARCEUS_TIMING\t1\n')
            rows={r['env']:r for r in settings.build('01007EF00011E000',tmp,'unused')['settings']}
            self.assertNotIn('DM_FRAMEGEN',rows)
            self.assertIn('DM_ARCEUS_FPS',rows)

if __name__=='__main__':unittest.main()
