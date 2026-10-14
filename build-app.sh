#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$PROJECT_DIR/dist/Xvico.app"
INCLUDE_APPLE_RUNTIME=true
RELEASE_VERSION=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            [[ $# -ge 2 ]] || { print -u2 'Missing output app path'; exit 2; }
            APP_PATH="$2"; shift 2 ;;
        --without-apple-runtime) INCLUDE_APPLE_RUNTIME=false; shift ;;
        --release-version)
            [[ $# -ge 2 ]] || { print -u2 'Missing release version'; exit 2; }
            RELEASE_VERSION="$2"; shift 2 ;;
        *) print -u2 'Usage: build-app.sh [--output path/Xvico.app] [--without-apple-runtime] [--release-version version]'; exit 2 ;;
    esac
done
[[ "$APP_PATH" == /* ]] || APP_PATH="$PROJECT_DIR/$APP_PATH"
[[ "$APP_PATH" == *.app ]] || { print -u2 'Output must be an .app bundle'; exit 2; }

cd "$PROJECT_DIR"
python3 scripts/build-opus.py
python3 scripts/build-voice-tools.py
python3 scripts/build-audio-backend.py
swift build -c release
mkdir -p "$PROJECT_DIR/dist"
BUILD_DIRECTORY="$(mktemp -d "$PROJECT_DIR/dist/.build-app.XXXXXX")"
trap 'rm -rf "$BUILD_DIRECTORY"' EXIT
DESTINATION_APP="$APP_PATH"
APP_PATH="$BUILD_DIRECTORY/Xvico.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$PROJECT_DIR/.build/release/Xvico" "$APP_PATH/Contents/MacOS/Xvico"
cp -R "$PROJECT_DIR/.build/release/Xvico_XvicoApp.bundle" "$APP_PATH/Contents/Resources/"
cp -R "$PROJECT_DIR/Sources/XvicoApp/Resources/Localization/"*.lproj "$APP_PATH/Contents/Resources/"
cp "$PROJECT_DIR/Assets/Xvico.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/AppInfo.plist" "$APP_PATH/Contents/Info.plist"
if [[ -n "$RELEASE_VERSION" ]]; then
    python3 - "$APP_PATH/Contents/Info.plist" "$RELEASE_VERSION" <<'PY'
import plistlib, re, sys
from pathlib import Path
version = sys.argv[2]
match = re.fullmatch(r'(\d+\.\d+\.\d+)-beta\.(\d+)', version)
if not match: raise SystemExit('Expected a version such as 1.0.0-beta.1')
path = Path(sys.argv[1]); info = plistlib.loads(path.read_bytes())
info['CFBundleShortVersionString'] = match[1]
info['CFBundleVersion'] = str(1000 + int(match[2]))
info['XvicoReleaseVersion'] = version
path.write_bytes(plistlib.dumps(info, sort_keys=False))
PY
fi
mkdir -p "$APP_PATH/Contents/Resources/Legal"
cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/COMMERCIAL_LICENSE.md" "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_PATH/Contents/Resources/Legal/"
cp "$PROJECT_DIR/Sources/XvicoApp/Voice/VoiceHelperProtocol.swift" "$APP_PATH/Contents/Resources/Legal/VoiceHelperProtocol-MIT.swift"
cp "$PROJECT_DIR/ThirdParty/Opus/LICENSE" "$APP_PATH/Contents/Resources/Legal/Opus-LICENSE.txt"
mkdir -p "$APP_PATH/Contents/Resources/VoiceTools"
cp "$PROJECT_DIR/.build/voice-tools/"Xvibe* "$PROJECT_DIR/.build/voice-tools/XvicoMicrophoneControl" "$APP_PATH/Contents/Resources/VoiceTools/"
cp "$PROJECT_DIR/ThirdParty/SiriRemoteVoiceBridge/LICENSE" "$APP_PATH/Contents/Resources/VoiceTools/LICENSE"
cp "$PROJECT_DIR/ThirdParty/SiriRemoteVoiceBridge/SOURCE.md" "$APP_PATH/Contents/Resources/VoiceTools/SOURCE.md"
mkdir -p "$APP_PATH/Contents/Resources/AudioBackend"
cp -R "$PROJECT_DIR/.build/audio-backend/XvibeMicrophone.driver" "$APP_PATH/Contents/Resources/AudioBackend/"
cp "$PROJECT_DIR/.build/audio-backend/XvibeAudioRouter" "$PROJECT_DIR/.build/audio-backend/XvibeBackendHelper" "$PROJECT_DIR/.build/audio-backend/XvibeBackendRunner" "$APP_PATH/Contents/Resources/AudioBackend/"
cp "$PROJECT_DIR/.build/audio-backend/XvicoVoiceDaemon" "$APP_PATH/Contents/Resources/AudioBackend/"
cp "$PROJECT_DIR/.build/audio-backend/libopus.0.dylib" "$PROJECT_DIR/.build/audio-backend/"*.md "$PROJECT_DIR/.build/audio-backend/"*LICENSE* "$APP_PATH/Contents/Resources/AudioBackend/"
if [[ "$INCLUDE_APPLE_RUNTIME" == true && -d "$PROJECT_DIR/.build/voice-runtime/PacketLoggerRuntime" ]]; then
    cp -R "$PROJECT_DIR/.build/voice-runtime/PacketLoggerRuntime" "$APP_PATH/Contents/Resources/"
fi
# A changed ad hoc cdhash makes macOS treat every rebuild as different code.
# Sign and verify the staged bundle before replacing the installed development app.
python3 "$PROJECT_DIR/scripts/sign-local.py" "$APP_PATH"
mkdir -p "$(dirname "$DESTINATION_APP")"
rm -rf "$DESTINATION_APP"
mv "$APP_PATH" "$DESTINATION_APP"
printf '%s\n' "$DESTINATION_APP"
