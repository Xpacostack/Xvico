#!/usr/bin/env python3
"""Build the pinned official Opus source locally; install no system packages."""
from pathlib import Path
import hashlib
import os
import shutil
import subprocess
import tarfile
import urllib.request

root = Path(__file__).resolve().parent.parent
work = root / ".build" / "voice-runtime"
out = root / "Sources" / "XvicoApp" / "Resources" / "VoiceRuntime"
version = "1.6.1"
digest = "6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"
work.mkdir(parents=True, exist_ok=True)
archive = work / f"opus-{version}.tar.gz"
if not archive.exists():
    urllib.request.urlretrieve(f"https://downloads.xiph.org/releases/opus/opus-{version}.tar.gz", archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != digest:
    raise SystemExit("Official Opus source SHA256 mismatch")
source = work / f"opus-{version}"
if not source.exists():
    with tarfile.open(archive) as tar:
        for item in tar.getmembers():
            target = (work / item.name).resolve()
            if work.resolve() not in target.parents or not (item.isfile() or item.isdir()):
                raise SystemExit("Unexpected Opus archive path")
        tar.extractall(work)
env = dict(os.environ, MACOSX_DEPLOYMENT_TARGET="13.0")
makefile = source / "Makefile"
if not makefile.exists() or f"abs_srcdir = {source}" not in makefile.read_text():
    subprocess.run(["./configure", "--disable-static", "--enable-shared", "--disable-doc",
                    "--disable-extra-programs", "--disable-intrinsics"], cwd=source, env=env, check=True)
subprocess.run(["make", "-j4"], cwd=source, env=env, check=True)
out.mkdir(parents=True, exist_ok=True)
shutil.copy2(source / ".libs" / "libopus.0.dylib", out / "libopus.0.dylib")
shutil.copy2(source / "COPYING", out / "Opus-LICENSE.txt")
(out / "SOURCE.txt").write_text(f"Opus {version}\nhttps://opus-codec.org/downloads/\n"
                               f"Source archive SHA256: {digest}\nBuilt locally for macOS 13+.\n")
subprocess.run(["/usr/bin/install_name_tool", "-id", "@rpath/libopus.0.dylib", str(out / "libopus.0.dylib")], check=True)
print(out / "libopus.0.dylib")
