#!/usr/bin/env python3
"""Stage a user-supplied Apple-signed runtime; never extract another app's payload."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, type=Path,
                    help='Runtime root, or PacketLogger.app with the signed CLI and framework in Contents')
args = parser.parse_args()
source = args.source.expanduser().resolve()
if source.suffix == '.app': source = source / 'Contents'
components = [('Resources/packetlogger', 'com.apple.packetlogger'),
              ('Frameworks/PacketDecoder.framework', 'com.apple.PacketDecoder')]
def verify(base):
    for relative, identifier in components:
        target = base / relative
        if not target.exists(): raise SystemExit(f'Missing official runtime component: {relative}')
        subprocess.run(['/usr/bin/codesign', '--verify', '--strict', '--all-architectures', '-R',
                        f'=identifier "{identifier}" and anchor apple', str(target)], check=True)
verify(source)
work = root / '.build/voice-runtime'
work.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix='packetlogger-stage-', dir=work) as directory:
    staged = Path(directory) / 'PacketLoggerRuntime'
    for relative, _ in components:
        destination = staged / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['/usr/bin/ditto', str(source / relative), str(destination)], check=True)
    verify(staged)
    out = work / 'PacketLoggerRuntime'
    if out.exists(): shutil.rmtree(out)
    shutil.move(staged, out)
print('Staged unchanged Apple-signed runtime for this local build; no installation or capture started.')
