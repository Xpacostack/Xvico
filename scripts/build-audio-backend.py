#!/usr/bin/env python3
"""Build isolated HAL/router artifacts and process-local contracts; no installation."""
from pathlib import Path
import subprocess, shutil, platform
import json

root = Path(__file__).resolve().parent.parent
src = root / 'ThirdParty/XvicoAudioBackend'
out = root / '.build/audio-backend'
out.mkdir(parents=True, exist_ok=True)
sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
driver = out / 'XvibeMicrophone.driver'
(driver / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
shutil.copy2(src / 'driver/Info.plist', driver / 'Contents/Info.plist')
c = ['clang', '-O2', '-Wall', '-Wextra', '-Werror', '-isysroot', sdk, '-mmacosx-version-min=13.0']
def run(args): subprocess.run([str(x) for x in args], check=True)
run(c + ['-bundle', '-include', src/'driver/SiriRemoteMic.config.h', src/'driver/SiriRemoteMic.c',
         '-framework', 'CoreFoundation', '-framework', 'CoreAudio', '-framework', 'Accelerate',
         '-o', driver/'Contents/MacOS/SiriRemoteMic'])
run(['codesign', '--force', '--sign', '-', driver])
run(c + [src/'driver/srm_driver_contract_test.c', '-framework', 'CoreFoundation', '-framework', 'CoreAudio', '-o', out/'driver-contract'])
run([out/'driver-contract', driver/'Contents/MacOS/SiriRemoteMic'])
for name in ['SiriRemoteMicRingWriter', 'MonitorAudioRing']:
    run(c + ['-c', src/f'router/{name}.c', '-o', out/f'{name}.o'])
opus = root/'.build/voice-runtime/opus-1.6.1'
(out/'include').mkdir(exist_ok=True)
include = out/'include/opus'
if include.is_symlink() and include.resolve() != (opus/'include').resolve(): include.unlink()
if not include.exists(): include.symlink_to(opus/'include', target_is_directory=True)
shutil.copy2(opus/'.libs/libopus.0.dylib', out/'libopus.0.dylib')
run(['swiftc', '-O', '-sdk', sdk, '-target', f'{platform.machine()}-apple-macos13.0',
     '-import-objc-header', src/'router/router_shim.h', '-I'+str(out/'include'),
     '-L'+str(out), '-lopus.0', '-Xlinker', '-rpath', '-Xlinker', '@loader_path',
     '-framework', 'AVFoundation', src/'OpusVoiceDecoder.swift',
     *[root/f'ThirdParty/SiriRemoteVoiceBridge/{n}.swift' for n in ['VoiceFrameParser','PklgTailReader']],
     *[src/f'router/{n}.swift' for n in ['MonitorPlayer','SiriRemoteMicRouter']],
     out/'SiriRemoteMicRingWriter.o', out/'MonitorAudioRing.o', '-o', out/'XvibeAudioRouter'])
run(['install_name_tool', '-change', '/usr/local/lib/libopus.0.dylib', '@rpath/libopus.0.dylib', out/'XvibeAudioRouter'])
fingerprint = subprocess.check_output(['python3', root/'scripts/sign-local.py', '--fingerprint'], text=True).strip()
if len(fingerprint) != 40 or any(char not in '0123456789ABCDEF' for char in fingerprint):
    raise SystemExit('Invalid local code-signing certificate fingerprint')
identity = out/'BackendSigningIdentity.swift'
identity.write_text('enum BackendSigningIdentity { static let fingerprint = ' + json.dumps(fingerprint) + ' }\n')
for source, name in [('BackendHelper.swift', 'XvibeBackendHelper'), ('BackendRunner.swift', 'XvibeBackendRunner'), ('VoiceDaemon.swift', 'XvicoVoiceDaemon')]:
    run(['swiftc', '-O', '-sdk', sdk, '-target', f'{platform.machine()}-apple-macos13.0', '-parse-as-library', src/'Support/SessionDirectory.swift', root/'Sources/XvicoApp/Voice/VoiceHelperProtocol.swift', identity, src/source, '-o', out/name])
for name in ['LICENSE', 'SOURCE.md']: shutil.copy2(src/name, out/name)
shutil.copy2(src/'driver/vendor/BlackHole-LICENSE.txt', out/'BlackHole-LICENSE.txt')
print('Audio backend built and HAL contract passed. Nothing installed into CoreAudio.')

run(['swiftc', '-O', '-parse-as-library', src/'Support/SessionDirectory.swift', src/'Support/SessionDirectoryTests.swift', '-o', out/'session-directory-tests'])
run([out/'session-directory-tests'])

run(['swiftc', '-O', '-parse-as-library', root/'ThirdParty/SiriRemoteVoiceBridge/VoiceFrameParser.swift', root/'ThirdParty/SiriRemoteVoiceBridge/PklgTailReader.swift', src/'router/test_parser.swift', '-o', out/'parser-tests'])
run([out/'parser-tests'])
run(c + [src/'router/MonitorAudioRing.c', src/'router/test_monitor_ring.c', '-o', out/'monitor-ring-tests'])
run([out/'monitor-ring-tests'])
