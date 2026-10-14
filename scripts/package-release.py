#!/usr/bin/env python3
"""Package an already signed public beta; never installs or launches the app."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
REPOSITORY = 'https://github.com/Xpacostack/Xvico'


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def output(*args):
    return subprocess.check_output([str(a) for a in args], text=True).strip()


def verify(app, version):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info.get('CFBundleIdentifier') != 'work.xvibe.remote' or info.get('XvicoReleaseVersion') != version:
        raise SystemExit('Wrong application identity or release version')
    architectures = output('/usr/bin/lipo', '-archs', app / 'Contents/MacOS/Xvico').split()
    if architectures != ['arm64']:
        raise SystemExit('This beta requires an arm64 build')
    if any(p.name in ('PacketLoggerRuntime', 'PacketDecoder.framework', 'packetlogger') for p in app.rglob('*')):
        raise SystemExit('Apple runtime must not be redistributed in this public package')
    for relative in ['Legal/LICENSE', 'Legal/THIRD_PARTY_NOTICES.md', 'Legal/Opus-LICENSE.txt',
                     'Legal/VoiceHelperProtocol-MIT.swift', 'VoiceTools/LICENSE', 'AudioBackend/LICENSE']:
        if not (app / 'Contents/Resources' / relative).is_file():
            raise SystemExit('Missing license notice: ' + relative)
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
    return info, architectures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--version', required=True)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/releases')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+-beta\.\d+', args.version):
        parser.error('Only explicitly labeled beta versions are supported')
    app = args.app.resolve(); dest = args.output.resolve()
    info, architectures = verify(app, args.version)
    dest.mkdir(parents=True, exist_ok=True)
    base = 'Xvico-' + args.version + '-macos-arm64'
    dmg = dest / (base + '.dmg'); archive = dest / (base + '.zip')
    notes = f'''# Xvico {args.version}

## 下载与安装 / Download and install

- Apple Silicon (M1 or later), macOS 13+. Intel Macs are not supported by this build.
- 下载 DMG，打开后将 Xvico 拖入 Applications；ZIP 为备用包。
- Download the DMG and drag Xvico to Applications; ZIP is an alternative.
- 本测试版使用自签名，尚未经过 Apple 公证。macOS 可能阻止首次打开；请核对来源与 SHA256 后，按系统设置 → 隐私与安全性中的提示处理。无需关闭 Gatekeeper。
- This beta is self-signed and not Apple-notarized. macOS may block the first launch. Verify the source and SHA256, then follow System Settings → Privacy & Security. Do not disable Gatekeeper.
- 按键、触控和 Mac 麦克风不需要 Apple PacketLogger。遥控器麦克风需自行从 Apple 官方工具获取 PacketLogger.app，在语音设置中导入，并亲自批准后端安装/采集。
- Buttons, touch controls and the Mac microphone do not require PacketLogger. Siri Remote audio requires your own official Apple PacketLogger.app, imported in Voice Settings, followed by explicit backend approval.
- 官方工具 / Official tools: https://developer.apple.com/download/all/
- 该包未附带 Apple 二进制。导入不会修改应用签名，也不会自动启动采集。
- Apple binaries are excluded. Importing does not alter the app signature or start capture.
- GitHub-hosted builds use a disposable signing identity. Future beta updates may require renewed macOS privacy approval and helper installation. This is not a production Developer ID release.

## 源码与许可证 / Source and licenses

- 对应版本的完整项目、GPL 组件源码和构建脚本 / Matching project, GPL component source and build scripts: {REPOSITORY}/tree/v{args.version}
- Source archive: {REPOSITORY}/archive/refs/tags/v{args.version}.tar.gz
- Pinned Opus source: https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz ; checksum and build inputs: scripts/build-opus.py in the matching source tag.
- 项目自有材料采用 Xvico Source Available License；个人和企业内部使用免费，对外售卖、付费分发和提供商业 Xvico 服务须书面授权。GPL、MIT、Opus 组件保留各自许可，不受根商业限制替代。
- Project-owned material is source-available: personal and internal business use is free; sales, paid distribution and commercial Xvico services require written authorization. GPL, MIT and Opus components retain their own licenses and rights.
- App bundle: Contents/Resources/Legal, VoiceTools/LICENSE and AudioBackend/LICENSE.

软件检查不代表所有遥控器型号、输入法和 macOS 版本均已实机验证。
Software checks do not establish hardware acceptance across every remote, input method or macOS version.
'''
    notes_path = dest / 'INSTALL.md'; notes_path.write_text(notes)
    with tempfile.TemporaryDirectory(prefix='xvico-package-') as temporary:
        stage = Path(temporary) / 'disk'; stage.mkdir()
        run('/usr/bin/ditto', app, stage / 'Xvico.app')
        (stage / 'Applications').symlink_to('/Applications')
        (stage / 'INSTALL.md').write_text(notes)
        run('/usr/bin/hdiutil', 'create', '-volname', 'Xvico ' + args.version,
            '-srcfolder', stage, '-format', 'UDZO', '-ov', dmg)
        run('/usr/bin/hdiutil', 'verify', dmg)
        mounted = plistlib.loads(subprocess.check_output([
            '/usr/bin/hdiutil', 'attach', '-readonly', '-nobrowse', '-plist', str(dmg)]))
        mount = next(e['mount-point'] for e in mounted['system-entities'] if 'mount-point' in e)
        try: verify(Path(mount) / 'Xvico.app', args.version)
        finally: run('/usr/bin/hdiutil', 'detach', mount)
        if archive.exists(): archive.unlink()
        # Include installation and source notices in the ZIP as well as the app.
        zip_stage = Path(temporary) / base; zip_stage.mkdir()
        run('/usr/bin/ditto', app, zip_stage / 'Xvico.app')
        (zip_stage / 'INSTALL.md').write_text(notes)
        run('/usr/bin/ditto', '-c', '-k', '--keepParent', zip_stage, archive)
        extracted = Path(temporary) / 'extracted'
        run('/usr/bin/ditto', '-x', '-k', archive, extracted)
        verify(extracted / base / 'Xvico.app', args.version)
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [dmg, archive]}
    (dest / 'SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()))
    manifest = {'version': args.version, 'sourceCommit': output('git', '-C', ROOT, 'rev-parse', 'HEAD'),
                'sourceDirty': bool(output('git', '-C', ROOT, 'status', '--porcelain')),
                'architectures': architectures, 'minimumMacOS': info['LSMinimumSystemVersion'],
                'signing': 'self-signed beta, not notarized', 'appleRuntimeIncluded': False,
                'verification': ['strict/deep code signature', 'DMG checksum and mounted app', 'extracted ZIP app'],
                'sha256': hashes}
    (dest / 'release-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__': main()
