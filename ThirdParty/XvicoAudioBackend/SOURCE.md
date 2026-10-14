# CoreAudio backend

Source: https://github.com/mkliu/SiriRemoteVibe
Revision: 98cfcb3f61eb8e88c6fd6d47b1ca503ab058b294
License: GPL-3.0; see LICENSE. BlackHole copyright and license are retained in driver/vendor/BlackHole-LICENSE.txt. Local changes remain under the GPL.

Xvico adaptations use distinct bundle/factory/device identifiers and shared-memory names, expose a single input-only device, do not produce fallback Mac-microphone audio, and never change the default system input during installation. Producer shared memory is read-only to other users. Session signaling uses pinned directory descriptors and no-follow exclusive file creation. Helper trust is generated from the current builder's certificate rather than a maintainer's hard-coded certificate.

Duplicate packet parser copies were removed; the GPL sources in ThirdParty/SiriRemoteVoiceBridge are shared by both tools. The old simulator for an obsolete built-in-microphone fallback was removed; HAL contracts, marker security, packet parsing and monitor-ring tests are compiled and run by the build script.

Build `python3 scripts/build-opus.py` then `python3 scripts/build-audio-backend.py` with macOS/Xcode tools. These commands build and test process-local components, without installing into CoreAudio or starting capture. The scripts, Support files, shared GPL parsers and pinned Opus source are the corresponding build inputs. No upstream system installer is run.

The local `VoiceDaemon.swift` provides opt-in persistent authorization through a root-owned, demand-launched XPC endpoint. Its shared Objective-C wire contract is `Sources/XvicoApp/Voice/VoiceHelperProtocol.swift`, also supplied as a build input. `BackendHelper.swift` installs/removes verified service payloads only after administrator approval. Both XPC peers pin the signing identity; the daemon derives caller identity and accepts no executable paths or arbitrary commands. `BackendRunner.swift` uses its protected executable directory so the temporary and persistent launch paths share the same capture/router implementation. The idle service never starts diagnostics, records audio or changes the default microphone.

Public-package adaptations accept a separately supplied Apple runtime through the fixed per-user import location. Only PacketLogger and PacketDecoder components are copied; protected staging rejects external links and re-verifies Apple signatures before execution. Apple binaries are not part of this source or the public installer. Matching build inputs also include the separately MIT-licensed `Sources/XvicoApp/Voice/VoiceHelperProtocol.swift` runtime layout contract where used. These local implementation changes remain GPL-licensed.
