# Release preparation

## Public beta packages

The `Package macOS beta` workflow verifies packaging on `main` pushes without publishing, and publishes when the maintainer pushes a `v*-beta.*` tag. It tests the tagged source, builds on a macOS ARM64 runner, verifies both archives, then publishes a GitHub prerelease with DMG, ZIP, SHA256 checksums, installation notes and a manifest. The job uses GitHub’s scoped `contents: write` token; no maintainer API token or signing key is committed. CI uses an isolated signing directory in runner temporary storage; local builds keep their existing signing identity. Only an explicitly authorized maintainer should push a publishing tag.

```sh
python3 scripts/build-opus.py
python3 scripts/check-release.py
python3 scripts/audit-localization.py --check
swift test
./build-app.sh --output dist/public-build/Xvico.app --without-apple-runtime --release-version 1.0.0-beta.1
python3 scripts/package-release.py --app dist/public-build/Xvico.app --version 1.0.0-beta.1
```

The isolated output does not replace `dist/Xvico.app`. Packaging uses `ditto` to preserve bundle symlinks, verifies strict/deep signatures, checks the mounted read-only DMG and extracted ZIP, and rejects included PacketLogger/PacketDecoder binaries. It never launches the app, installs a driver, changes privacy permissions or starts capture. Generated assets stay under ignored `dist/releases/`.

The initial download is Apple Silicon only, macOS 13+. It is self-signed and **not notarized**; signature integrity does not establish Apple trust. Fresh hosted runners use disposable identities, so future beta updates can require new privacy approval and helper installation. Do not promise persistent identity across these builds. README and release notes must make these limits visible. Do not disable Gatekeeper or remove quarantine automatically.

Siri Remote audio requires the user to obtain official Apple tools separately and import PacketLogger.app through Voice Settings. The public app imports only the two expected components, verifies Apple signatures and rejects escaping links, without altering the app bundle. Source developers can alternatively use `scripts/prepare-packetlogger.py`. Apple redistribution rights are not granted by this project.

## Production and compliance checks

1. Run all source, localization and software checks. Review `git diff --cached` and `git diff --cached --check`; never stage caches, dist, evidence, recordings, captures, preferences or signing material.
2. For a production release, supply a stable Developer ID signing identity and notarization workflow for the app and helpers. Update the embedded helper trust fingerprint consistently. The local development signing script is not a replacement for this process.
3. Retain asset/source authorizations covering the planned distribution and all third-party notices. Supply complete corresponding source/build instructions for GPL binaries, without applying the root commercial restriction to those components. The matching source tag and Opus source link are included in both archives and release notes.
4. Do not redistribute Apple binaries without the corresponding rights. The public packaging script deliberately rejects them.
5. Test reconnects, repeated voice sessions, stop/quit cleanup and input-method behavior on real hardware. Build and archive verification do not replace hardware acceptance across all supported systems.
6. Publish a new immutable version tag only after reviewing the source and release notes. Correct a failed release in a new tag; do not silently overwrite a published binary.

The root license permits personal and internal business use. Paid distribution, sales and commercial Xvico services need separate written authorization. This is a source-available release, not an OSI-approved open-source license. Third-party rights remain governed by their own licenses.
