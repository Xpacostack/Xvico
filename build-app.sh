#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$PROJECT_DIR/dist/Xvico.app"

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
mkdir -p "$APP_PATH/Contents/Resources/VoiceTools"
cp "$PROJECT_DIR/.build/voice-tools/"Xvibe* "$PROJECT_DIR/.build/voice-tools/XvicoMicrophoneControl" "$APP_PATH/Contents/Resources/VoiceTools/"
cp "$PROJECT_DIR/ThirdParty/SiriRemoteVoiceBridge/LICENSE" "$APP_PATH/Contents/Resources/VoiceTools/LICENSE"
cp "$PROJECT_DIR/ThirdParty/SiriRemoteVoiceBridge/SOURCE.md" "$APP_PATH/Contents/Resources/VoiceTools/SOURCE.md"
mkdir -p "$APP_PATH/Contents/Resources/AudioBackend"
cp -R "$PROJECT_DIR/.build/audio-backend/XvibeMicrophone.driver" "$APP_PATH/Contents/Resources/AudioBackend/"
cp "$PROJECT_DIR/.build/audio-backend/XvibeAudioRouter" "$PROJECT_DIR/.build/audio-backend/XvibeBackendHelper" "$PROJECT_DIR/.build/audio-backend/XvibeBackendRunner" "$APP_PATH/Contents/Resources/AudioBackend/"
cp "$PROJECT_DIR/.build/audio-backend/XvicoVoiceDaemon" "$APP_PATH/Contents/Resources/AudioBackend/"
cp "$PROJECT_DIR/.build/audio-backend/libopus.0.dylib" "$PROJECT_DIR/.build/audio-backend/"*.md "$PROJECT_DIR/.build/audio-backend/"*LICENSE* "$APP_PATH/Contents/Resources/AudioBackend/"
if [[ -d "$PROJECT_DIR/.build/voice-runtime/PacketLoggerRuntime" ]]; then
    cp -R "$PROJECT_DIR/.build/voice-runtime/PacketLoggerRuntime" "$APP_PATH/Contents/Resources/"
fi
# A changed ad hoc cdhash makes macOS treat every rebuild as different code.
# Sign and verify the staged bundle before replacing the installed development app.
python3 "$PROJECT_DIR/scripts/sign-local.py" "$APP_PATH"
rm -rf "$DESTINATION_APP"
mv "$APP_PATH" "$DESTINATION_APP"
printf '%s\n' "$DESTINATION_APP"
