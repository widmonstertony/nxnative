#!/usr/bin/env python3
"""Serialize IPA builds that generate one checkout's shared Gen directory."""
import fcntl
import hashlib
import os
from pathlib import Path
import sys
import tempfile

if __name__ == '__main__':
    source, *command = sys.argv[1:]
    if not command:
        raise SystemExit('usage: build_lock.py <ios source directory> <command> [args...]')
    key = hashlib.sha256(str(Path(source).resolve()).encode()).hexdigest()[:24]
    path = Path(tempfile.gettempdir()) / f'nxnative-ipa-{key}.lock'
    with path.open('a') as lock:
        print('Waiting for the shared iOS build directory lock', flush=True)
        fcntl.flock(lock, fcntl.LOCK_EX)
        os.set_inheritable(lock.fileno(), True)
        os.environ['DM_IOS_BUILD_LOCK_OWNER'] = str(os.getpid())
        os.execvp(command[0], command)
