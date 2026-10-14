#!/usr/bin/env python3
"""Check the source distribution only; never inspect user preferences or captures."""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
TEXT = {'.swift', '.py', '.sh', '.json', '.strings', '.md', '.plist', '.h', '.c', '.yml', '.txt'}
REQUIRED = ['LICENSE', 'COMMERCIAL_LICENSE.md', 'THIRD_PARTY_NOTICES.md',
            'README.md', 'SECURITY.md', 'CONTRIBUTING.md', 'docs/RELEASE.md', 'Package.swift']
BLOCKED_PARTS = {'.build', 'dist', 'evidence', 'backups', '__pycache__', '.git'}
BLOCKED_SUFFIXES = {'.dylib', '.pklg', '.wav', '.pcm', '.p12', '.pfx', '.pem', '.key', '.pyc'}
SECRETS = [re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
           re.compile(r'\bgh[pousr]_[A-Za-z0-9]{30,}\b'),
           re.compile(r'\bgithub_pat_[A-Za-z0-9_]{30,}\b')]

def source_files():
    if (ROOT / '.git').is_dir():
        result = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '-z'], cwd=ROOT, capture_output=True, check=True)
        tracked = result.stdout.decode().split('\0')
        if any(tracked): return [ROOT / name for name in tracked if name]
    files = []
    for path in ROOT.rglob('*'):
        relative = path.relative_to(ROOT)
        if any(part in BLOCKED_PARTS for part in relative.parts): continue
        if relative.parts[:4] == ('Sources', 'XvicoApp', 'Resources', 'VoiceRuntime') and path.name != '.gitkeep': continue
        if path.is_file(): files.append(path)
    return files

def main():
    problems = []
    for name in REQUIRED:
        if not (ROOT / name).is_file(): problems.append({'file': name, 'problem': 'missing required release document'})
    paths = source_files()
    for path in paths:
        relative = path.relative_to(ROOT)
        if any(part in BLOCKED_PARTS or part.endswith('.app') or 'keychain' in part for part in relative.parts) or path.suffix in BLOCKED_SUFFIXES:
            problems.append({'file': str(relative), 'problem': 'private/generated artifact in source distribution'})
            continue
        if path.suffix not in TEXT and path.name not in ('LICENSE', '.gitignore', '.gitattributes'): continue
        text = path.read_text()
        if any(pattern.search(text) for pattern in SECRETS):
            problems.append({'file': str(relative), 'problem': 'possible credential/private key; inspect locally'})
        if ('/' + 'Users/') in text:
            problems.append({'file': str(relative), 'problem': 'machine-specific absolute path'})
        if path.suffix in {'.swift', '.py', '.json', '.strings'} and ('vo' + 'xa') in text.lower():
            problems.append({'file': str(relative), 'problem': 'retired reference name in active source'})
    package = (ROOT / 'Package.swift').read_text()
    if '.package(path:' in package or '../outputs/' in package:
        problems.append({'file': 'Package.swift', 'problem': 'external local source dependency'})
    result = {'checkedSourceFiles': len(paths), 'problems': problems,
              'scope': 'Source tree checks; not a legal clearance, notarization, hardware test or full secret audit'}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if problems else 0

if __name__ == '__main__': sys.exit(main())
