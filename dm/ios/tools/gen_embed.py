# Keep the signed guest image format paired with its loader.
import os, runpy, sys
from pathlib import Path
modern = os.environ.get('DM_IOS_RENDERER', 'legacy') == 'metal4' or '--tag' in sys.argv or '--jit' in sys.argv
runpy.run_path(str(Path(__file__).with_name('gen_embed_modern.py' if modern else 'gen_embed_legacy.py')), run_name='__main__')
