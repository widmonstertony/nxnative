#!/usr/bin/env python3
"""Run the pinned Rust builder in a separate job for a new TonTon title."""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ENGINE = Path(__file__).resolve().parents[1]
NXB_SHA256 = "0e14356d8c89e323fd2ef2aa5c015c0d90a7ee3b14ac5da06381c3e1198e9065"
GIB = 1024**3


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ENGINE), *args], text=True).strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["plan", "extract-switch2", "build-mac"])
    parser.add_argument("source", type=Path, help="owned .nup file or folder of Switch packages")
    parser.add_argument("--nxb", required=True, type=Path, help="verified nxb 0.9.3 binary")
    parser.add_argument("--job", required=True, type=Path, help="dedicated directory outside the engine and source")
    parser.add_argument("--platform", choices=["ios", "mac-app"], help="target for plan (default: ios)")
    parser.add_argument("--keys", type=Path, help="required by nxb for Switch packages")
    parser.add_argument("--version", type=int, help="exact NUP version for extract-switch2")
    args = parser.parse_args()
    src, job, nxb = (p.resolve() for p in (args.source, args.job, args.nxb))
    is_nup = src.is_file() and src.suffix.lower() == ".nup"
    if not (is_nup or src.is_dir()) or src.is_relative_to(ENGINE):
        parser.error("source must be an owned package outside the engine checkout")
    if job == src or job.is_relative_to(src) or src.is_relative_to(job) or job.is_relative_to(ENGINE):
        parser.error("job and source must be separate from each other and the engine")
    if args.platform and args.mode != "plan":
        parser.error("--platform is only used by plan")
    if args.mode == "extract-switch2":
        if not is_nup or args.version is None or args.version < 0 or args.keys:
            parser.error("extract-switch2 requires a .nup and an explicit nonnegative --version")
    elif args.version is not None:
        parser.error("--version is only used by extract-switch2")
    keys = args.keys.resolve() if args.keys else None
    if keys and (not keys.is_file() or keys.is_relative_to(job) or keys.is_relative_to(ENGINE)):
        parser.error("keep the keys file outside the engine and job")
    if not nxb.is_file() or not os.access(nxb, os.X_OK):
        parser.error("--nxb must be executable")
    with nxb.open("rb") as f:
        if hashlib.file_digest(f, "sha256").hexdigest() != NXB_SHA256:
            parser.error("nxb does not match the pinned macOS arm64 binary")
    if git("status", "--porcelain", "--untracked-files=no"):
        parser.error("use a clean checkout at the chosen engine commit")
    engine_rev = git("rev-parse", "HEAD")
    env = {k: v for k, v in os.environ.items() if not k.startswith(("DM_", "DMSH_", "NXB_"))}
    for key in ("GAME", "IOSOUT", "MACOUT"):
        env.pop(key, None)
    env.update(NXB_OWN_FRONT="0", NXB_OWN_RAW="0", NXB_OWN_RAW_IOS="0")
    cmd = [str(nxb)]
    if args.mode == "extract-switch2":
        cmd += ["extract", "--nup", str(src), "--work", str(job / "extract"), "--version", str(args.version)]
    else:
        platform = (args.platform or "ios") if args.mode == "plan" else "mac-app"
        suffix = ".ipa" if platform == "ios" else ".app"
        cmd += ["build", str(src), "--engine", str(ENGINE), "--platform", platform,
                "--work-dir", str(job / "work"), "-o", str(job / ("game" + suffix))]
        if args.mode == "plan":
            cmd += ["--dry-run"]
        if keys:
            cmd += ["-k", str(keys)]

    job.mkdir(parents=True, exist_ok=True)
    lock = job / ".tonton.lock"
    with lock.open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
        receipt = job / "job.json"
        st = src.stat()
        identity = dict(engine=engine_rev, nxb=NXB_SHA256, source=str(src), inode=st.st_ino,
                        size=st.st_size, mtime_ns=st.st_mtime_ns, mode=args.mode,
                        platform=args.platform, nup_version=args.version)
        if receipt.exists():
            if json.loads(receipt.read_text()) != identity:
                parser.error("job inputs changed; use a fresh directory")
        elif any(p != lock for p in job.iterdir()):
            parser.error("refusing a directory that already contains another build")
        else:
            with receipt.open("x") as out:
                json.dump(identity, out, indent=2)
                out.write("\n")
        if args.mode != "plan" and shutil.disk_usage(job).free < 10 * GIB:
            parser.error("the job volume needs at least 10 GiB free before starting; allow extra space for game data")
        return subprocess.run(cmd, cwd=job, env=env, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
