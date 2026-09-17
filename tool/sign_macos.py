"""Sign an OpenPelo release inside out, then verify its code and permissions.

Use a Developer ID identity for distribution, or '-' for local/PR validation.
This script requires macOS codesign; its planning tests run on any platform.
"""

import argparse
import os
from pathlib import Path
import plistlib
import subprocess


CODESIGN = '/usr/bin/codesign'
CODE_BUNDLES = {'.framework', '.app', '.xpc', '.appex', '.bundle'}
MACHO_MAGIC = {
    b'\xfe\xed\xfa\xce', b'\xce\xfa\xed\xfe',
    b'\xfe\xed\xfa\xcf', b'\xcf\xfa\xed\xfe',
    b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca',
    b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca',
}


def read_plist(path):
    with Path(path).open('rb') as source:
        return plistlib.load(source)


def signing_targets(app):
    """Find native code, including extensionless helpers, without following links.

    Framework version symlinks must not cause a later signing pass to invalidate
    an already sealed framework. Sign real files and enclosing code bundles once.
    """
    targets = set()
    for directory, dirs, files in os.walk(app, followlinks=False):
        dirs[:] = [name for name in dirs if not (Path(directory) / name).is_symlink()]
        for name in files:
            path = Path(directory) / name
            if path.is_symlink():
                continue
            with path.open('rb') as source:
                if source.read(4) not in MACHO_MAGIC:
                    continue
            targets.add(path)
            for parent in path.parents:
                if parent == app:
                    break
                if parent.suffix in CODE_BUNDLES:
                    targets.add(parent)
    # The outer app seals its own executable when signed last.
    executable = read_plist(app / 'Contents/Info.plist')['CFBundleExecutable']
    targets.discard(app / 'Contents/MacOS' / executable)
    return sorted(targets, key=lambda path: (-len(path.parts), str(path)))


def validate_bundle(app):
    info = read_plist(app / 'Contents/Info.plist')
    if not str(info.get('NSLocalNetworkUsageDescription', '')).strip():
        raise ValueError('Built app is missing its local-network usage description')
    services = set(info.get('NSBonjourServices', []))
    if not {'_adb._tcp', '_adb-tls-pairing._tcp', '_adb-tls-connect._tcp'} <= services:
        raise ValueError('Built app is missing ADB Bonjour service declarations')
    frameworks = app / 'Contents/Frameworks'
    for name in ('Mpv.framework', 'media_kit_video.framework'):
        if not (frameworks / name).is_dir():
            raise ValueError(f'Missing native viewer dependency: {name}')
    if not list(app.rglob('scrcpy-server-v3.3.4')):
        raise ValueError('Built app is missing the bundled scrcpy server')
    if not list(app.rglob('scrcpy-LICENSE.txt')):
        raise ValueError('Built app is missing the scrcpy license')


def verify_signed_entitlements(app, expected, run=subprocess.run):
    result = run(
        [CODESIGN, '--display', '--entitlements', '-', '--xml', str(app)],
        check=True, capture_output=True,
    )
    actual = plistlib.loads(result.stdout)
    for key, value in expected.items():
        if actual.get(key) != value:
            raise ValueError(f'Signed app entitlement does not match: {key}')
    if actual.get('com.apple.security.get-task-allow'):
        raise ValueError('Release app must not allow debugger attachment')


def sign_app(app, identity, entitlements, run=subprocess.run):
    app = Path(app).resolve(strict=True)
    entitlements = Path(entitlements).resolve(strict=True)
    if app.suffix != '.app' or not app.is_dir():
        raise ValueError('Expected a built .app directory')
    if not identity.strip():
        raise ValueError('Signing identity must not be empty')
    expected = read_plist(entitlements)
    validate_bundle(app)
    common = [CODESIGN, '--force', '--verbose', '--options', 'runtime',
              '--timestamp=none' if identity == '-' else '--timestamp',
              '--sign', identity]
    for target in signing_targets(app):
        # Retain any helper's own permissions; never apply app entitlements to
        # every nested framework or executable.
        run([*common, '--preserve-metadata=entitlements', str(target)], check=True)
    run([*common, '--entitlements', str(entitlements), str(app)], check=True)
    # --deep is appropriate for verification, never used above for signing.
    run([CODESIGN, '--verify', '--deep', '--strict', '--verbose=2', str(app)], check=True)
    verify_signed_entitlements(app, expected, run)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--identity', required=True)
    parser.add_argument('--entitlements', type=Path,
                        default=Path('macos/Runner/Release.entitlements'))
    args = parser.parse_args()
    sign_app(args.app, args.identity, args.entitlements)


if __name__ == '__main__':
    main()
