# Release preparation

1. On macOS, run `python3 scripts/check-release.py`, `python3 scripts/audit-localization.py --check`, `swift test` and `./build-app.sh`.
2. Verify `codesign --verify --strict --deep dist/Xvico.app`. Public binary distribution needs the maintainer's production signing/notarization workflow; a local development signature is not notarization.
3. Review `git diff --cached` and `git diff --cached --check`. Never stage build caches, dist, evidence, recordings, captures, preferences or signing material.
4. Retain asset/source authorizations covering the planned distribution and all third-party notices. Supply complete corresponding source/build instructions for GPL binaries, without applying the root commercial restriction to those components.
5. Apple binaries are excluded from this Git source distribution. Do not include them in public binaries without the corresponding rights.
6. Test reconnects, repeated voice sessions, stop/quit cleanup and input-method behavior on real hardware. Software tests do not replace these checks.
7. Create a remote under the maintainer's chosen account and push only when publishing is explicitly requested.

The root license permits personal and internal business use. Paid distribution, sales and commercial Xvico services need separate written authorization. This is a source-available release, not an OSI-approved open-source license.
