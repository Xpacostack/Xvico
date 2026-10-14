#!/usr/bin/env python3
"""Verify the same certificate identifies two different executables. Never run them."""
from pathlib import Path
import plistlib
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent


def command(args):
    result = subprocess.run(args, capture_output=True, text=True, check=True)
    return result.stdout + result.stderr


with tempfile.TemporaryDirectory(prefix="xvibe-signing-check-") as folder:
    builds = []
    for version in (1, 2):
        root = Path(folder) / str(version)
        app = root / "Xvico.app"
        macos = app / "Contents/MacOS"
        macos.mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "work.xvibe.remote", "CFBundleExecutable": "Xvico",
            "CFBundlePackageType": "APPL", "CFBundleVersion": str(version),
        }))
        source = root / "main.c"
        source.write_text(f"int main(void) {{ return {version}; }}\n")
        command(["/usr/bin/clang", str(source), "-o", str(macos / "Xvico")])
        command(["python3", str(project / "scripts/sign-local.py"), str(app)])
        requirement = next(line.removeprefix("designated => ") for line in
                           command(["/usr/bin/codesign", "-d", "-r-", str(app)]).splitlines()
                           if line.startswith("designated => "))
        details = command(["/usr/bin/codesign", "-d", "--verbose=4", str(app)])
        digest = next(line for line in details.splitlines() if line.startswith("CDHash="))
        builds.append((app, requirement, digest))
    assert builds[0][1] == builds[1][1], "Requirement changed"
    assert builds[0][2] != builds[1][2], "Executables did not produce distinct signatures"
    for app, _, digest in builds:
        command(["/usr/bin/codesign", "--verify", "--strict", "--test-requirement", "=" + builds[0][1], str(app)])
        print(digest)
    print("PASS: distinct compiled executables, identical certificate-bound designated requirement, cross-verification passed.")
    print("This verifies signing identity continuity, not macOS privacy authorization or remote output.")
