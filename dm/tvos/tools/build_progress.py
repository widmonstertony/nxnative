#!/usr/bin/env python3
"""Publish tvOS pipeline stages to a registered Mac gamebox device task."""
import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import tempfile


def publish(path, state, detail, completed=0, total=0, pid=None):
    if path is None:
        return
    if not 0 <= completed <= total:
        raise ValueError('invalid progress count')
    path = Path(path)
    data = dict(state=state, detail=detail, completed=completed, total=total,
                updated=datetime.now().astimezone().isoformat(), pid=pid)
    with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent,
                                     prefix=path.name + '.', delete=False) as temporary:
        try:
            json.dump(data, temporary, ensure_ascii=False)
            temporary.close()
            os.replace(temporary.name, path)
        finally:
            Path(temporary.name).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-file', type=Path, required=True)
    parser.add_argument('--state', required=True,
                        choices=['running', 'compiled', 'installed', 'needs_attention', 'tested', 'stopped'])
    parser.add_argument('--detail', required=True)
    parser.add_argument('--completed', type=int, default=0)
    parser.add_argument('--total', type=int, default=0)
    parser.add_argument('--pid', type=int)
    args = parser.parse_args()
    publish(args.state_file, args.state, args.detail, args.completed, args.total, args.pid)


if __name__ == '__main__':
    main()
