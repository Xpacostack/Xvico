# Siri Remote voice tools

Source: https://github.com/mkliu/SiriRemoteVibe
Revision: 98cfcb3f61eb8e88c6fd6d47b1ca503ab058b294
License: GPL-3.0; see LICENSE. Local modifications remain GPL-licensed.

The packet parsers originate upstream and are shared with the audio router. Xvico adds bounded malformed-record handling. MicrophoneControl.swift preserves the upstream IOKit device operation as an independent command-line tool. FrameReader.swift is the separate binary frame-stream wrapper. Capture.swift implements an explicitly started, administrator-approved local session with diagnostic restoration and pinned directory descriptors. Sessions have no fixed duration deadline and end on stop, interruption, client loss or capture failure.

Build with `python3 scripts/build-voice-tools.py` on macOS with Xcode command-line tools. This builds programs only and does not install a driver or start capture. Sources, including `ThirdParty/XvicoAudioBackend/Support/SessionDirectory.swift`, and the root scripts form the corresponding build source.

Public-package adaptations accept a separately supplied Apple runtime through the fixed per-user import location. Only PacketLogger and PacketDecoder components are copied; protected staging rejects external links and re-verifies Apple signatures before execution. Apple binaries are not part of this source or the public installer. Matching build inputs also include the separately MIT-licensed `Sources/XvicoApp/Voice/VoiceHelperProtocol.swift` runtime layout contract where used. These local implementation changes remain GPL-licensed.
