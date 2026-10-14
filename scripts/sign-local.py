#!/usr/bin/env python3
"""Persistent local development identity; never grants macOS privacy permissions.

Keys stay outside the repository. No trust settings, login keychain, or global
keychain search list changes are made. Only codesign may access the signing key.
"""
import hashlib
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

os.umask(0o077)
legacy_root = Path.home() / "Library/Application Support/Xvibe/DevelopmentSigning"
root = legacy_root if legacy_root.exists() else Path.home() / "Library/Application Support/Xvico/DevelopmentSigning"
root.mkdir(parents=True, exist_ok=True, mode=0o700)
keychain = root / "identity.keychain-db"
password_file = root / "keychain-password"
certificate = root / "certificate.der"


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, **kwargs)
    if result.returncode:
        # Arguments can contain locally generated keychain passwords. Never log them.
        raise RuntimeError(result.stderr.decode(errors="replace").strip() or "Signing command failed")
    return result.stdout


if not keychain.exists():
    if password_file.exists() or certificate.exists():
        raise SystemExit("Incomplete signing identity. Preserve the existing files and repair explicitly; do not regenerate automatically.")
    password = secrets.token_hex(32)
    password_file.write_text(password)
    # security create-keychain adds the new keychain to the search list. Restore
    # the exact prior list immediately; codesign selects this keychain explicitly.
    import shlex
    previous = shlex.split(run(["/usr/bin/security", "list-keychains", "-d", "user"]).decode())
    try:
        run(["/usr/bin/security", "create-keychain", "-p", password, str(keychain)])
    finally:
        run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *previous])
    with tempfile.TemporaryDirectory(dir=root) as folder:
        temp = Path(folder)
        config = temp / "certificate.cnf"
        config.write_text("""[req]
distinguished_name=subject
x509_extensions=extensions
prompt=no
[subject]
CN=Xvico Local Development
[extensions]
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
""")
        run(["/usr/bin/openssl", "req", "-new", "-x509", "-newkey", "rsa:3072", "-nodes",
             "-days", "3650", "-config", str(config), "-keyout", str(temp / "key.pem"), "-out", str(temp / "cert.pem")])
        run(["/usr/bin/openssl", "x509", "-in", str(temp / "cert.pem"), "-outform", "DER", "-out", str(certificate)])
        run(["/usr/bin/openssl", "pkcs12", "-export", "-inkey", str(temp / "key.pem"), "-in", str(temp / "cert.pem"),
             "-out", str(temp / "identity.p12"), "-passout", "stdin"], input=password.encode() + b"\n")
        run(["/usr/bin/security", "import", str(temp / "identity.p12"), "-k", str(keychain), "-P", password,
             "-x", "-T", "/usr/bin/codesign"])

if not password_file.exists() or not certificate.exists():
    raise SystemExit("Signing keychain exists but identity metadata is missing; refusing to replace it.")
password = password_file.read_text()
run(["/usr/bin/security", "unlock-keychain", "-p", password, str(keychain)])
fingerprint = hashlib.sha1(certificate.read_bytes()).hexdigest().upper()
if sys.argv[1:] == ["--fingerprint"]:
    print(fingerprint)
    raise SystemExit(0)
if len(sys.argv) != 2:
    raise SystemExit("Usage: sign-local.py /absolute/path/Xvico.app")
app = Path(sys.argv[1]).resolve()
# Sign our locally built codec before sealing the app's resource bundle. Keep the
# outer designated requirement and identity unchanged across updates.
for library in (app / "Contents" / "Resources").rglob("libopus.0.dylib"):
    run(["/usr/bin/codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain),
         "--timestamp=none", str(library)])
voice_tools = app / "Contents" / "Resources" / "VoiceTools"
for tool in voice_tools.iterdir() if voice_tools.is_dir() else []:
    if tool.name in ("LICENSE", "SOURCE.md"): continue
    run(["/usr/bin/codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain),
         "--timestamp=none", str(tool)])
for tool in (app / 'Contents/Resources/AudioBackend').glob('Xvibe*'):
    run(['/usr/bin/codesign', '--force', '--sign', fingerprint, '--keychain', str(keychain),
         '--timestamp=none', str(tool)])
daemon = app/'Contents/Resources/AudioBackend/XvicoVoiceDaemon'
if daemon.exists():
    run(['/usr/bin/codesign', '--force', '--sign', fingerprint, '--keychain', str(keychain),
         '--identifier', 'work.xvico.voice-service', '--timestamp=none', str(daemon)])
import plistlib
info_path = app/'Contents/Info.plist'
info = plistlib.loads(info_path.read_bytes())
info['XvicoVoiceServiceSigningIdentity'] = fingerprint
info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))
run(["/usr/bin/codesign", "--force", "--sign", fingerprint, "--keychain", str(keychain),
     "--timestamp=none", "--requirements", f'=designated => identifier "work.xvibe.remote" and certificate leaf = H"{fingerprint}"', str(app)])
run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)])
print("Signed with persistent Xvico local development identity; privacy permissions unchanged.")
