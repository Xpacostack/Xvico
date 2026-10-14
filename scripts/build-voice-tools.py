#!/usr/bin/env python3
from pathlib import Path
import subprocess
import platform

root = Path(__file__).resolve().parent.parent
source = root / "ThirdParty/SiriRemoteVoiceBridge"
out = root / ".build/voice-tools"
out.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
flags = ["swiftc", "-O", "-sdk", sdk, "-target", f"{platform.machine()}-apple-macos13.0"]
subprocess.run(flags + [str(source / n) for n in ["VoiceFrameParser.swift", "PklgTailReader.swift", "FrameReader.swift"]] + ["-o", str(out / "XvibeFrameReader")], check=True)
subprocess.run(flags + [str(source / "Capture.swift"), str(root / "ThirdParty/XvicoAudioBackend/Support/SessionDirectory.swift"), "-parse-as-library", "-o", str(out / "XvibeVoiceCapture")], check=True)
print("Voice reader and temporary privileged capture helper built; no system settings changed.")
subprocess.run(flags + [str(source / "MicrophoneControl.swift"), "-parse-as-library", "-o", str(out / "XvicoMicrophoneControl")], check=True)
