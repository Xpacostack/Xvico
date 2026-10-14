# Contributing

Read LICENSE and THIRD_PARTY_NOTICES.md. This project is source-available and does not grant unrestricted commercial redistribution rights for its own code.

On macOS, run `python3 scripts/build-opus.py`, `swift test`, `python3 scripts/audit-localization.py --check` and `python3 scripts/check-release.py`. Run `./build-app.sh` for packaged app/backend changes. Tests must not start capture, install drivers, modify privacy permissions, or post simulated keyboard events to the desktop.

Describe the observed issue, resulting behavior and relevant validation. Preserve third-party notices. GPL changes stay under their applicable GPL terms.

Before merging contributions to Xvico's own code, maintainers must obtain an explicit contribution agreement permitting distribution under both the source-available and separate commercial licenses. Opening an issue or a pull request alone is not represented as copyright assignment. Do not import third-party code under that agreement.

Never include private signing material, Bluetooth captures, speech recordings, preference exports, personal logs or local absolute paths.
