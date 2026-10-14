# Third-party notices

The root Xvico source-available license does not replace the following licenses.

| Component | Source | License and scope |
| --- | --- | --- |
| SiriRemoteVibe packet tools, microphone control and backend | https://github.com/mkliu/SiriRemoteVibe at `98cfcb3f61eb8e88c6fd6d47b1ca503ab058b294` | GPL-3.0; `ThirdParty/SiriRemoteVoiceBridge/` and `ThirdParty/XvicoAudioBackend/`, including local changes |
| BlackHole-derived HAL plug-in | Existential Audio Inc.; original copyright retained in `SiriRemoteMic.c` | GPL-3.0; `ThirdParty/XvicoAudioBackend/driver/vendor/BlackHole-LICENSE.txt` |
| Opus 1.6.1 | https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz | BSD-style license in `ThirdParty/Opus/LICENSE`; built locally, binary not committed |
| Apple PacketLogger / PacketDecoder | User-supplied Apple developer tools | Apple's terms; excluded from Git. No Apple binary redistribution rights are granted here |

GPL components keep their original licenses and corresponding source. They are built as separate command-line programs and a HAL plug-in. The application uses process arguments, data streams and system audio interfaces. A process boundary alone is not a legal guarantee about combined-work classification; distributions must comply with the applicable GPL obligations. Do not apply the root commercial restriction to GPL components on their own.

The main app's `RemoteMicrophoneControl.swift` is a process client. Its device-control implementation and upstream attribution are in `ThirdParty/SiriRemoteVoiceBridge/MicrophoneControl.swift`; that GPL implementation is not compiled into the main application executable. Shared packet parsers have one source implementation and remain GPL-licensed. Local modifications are described in each component's SOURCE.md.

The small XPC wire contract in `Sources/XvicoApp/Voice/VoiceHelperProtocol.swift` is separately MIT-licensed, with its full notice in the file, so it can be supplied with the GPL helper's corresponding build inputs. This exception covers only that interface/contract file. The app uses XPC to communicate with the separately built GPL voice daemon; the daemon implementation is not compiled into the main app.

The maintainer supplied or authorized the 3D model and brand/contact artwork. Maintainers must retain the authorization records covering the planned asset distribution. No Apple endorsement or right to impersonate Xvico/XPaco is implied.

When distributing GPL binaries, provide complete corresponding source and build instructions under the GPL. Independent third-party rights remain available regardless of the root license.
