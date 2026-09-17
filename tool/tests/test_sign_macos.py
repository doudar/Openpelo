import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('sign_macos', ROOT / 'tool/sign_macos.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class MacSigningTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'Open Pelo.app'
        self.write('Contents/Info.plist', plistlib.dumps({
            'CFBundleExecutable': 'openpelo',
            'NSLocalNetworkUsageDescription': 'Connect to your Peloton.',
            'NSBonjourServices': ['_adb._tcp', '_adb-tls-pairing._tcp', '_adb-tls-connect._tcp'],
        }))
        self.macho('Contents/MacOS/openpelo')
        self.macho('Contents/Frameworks/Mpv.framework/Versions/A/Mpv')
        self.macho('Contents/Frameworks/media_kit_video.framework/media_kit_video')
        self.macho('Contents/Helpers/connection-helper')
        self.write('Contents/Resources/assets/scrcpy-server-v3.3.4', b'PK\x03\x04jar')
        self.write('Contents/Resources/assets/scrcpy-LICENSE.txt', b'Apache license')
        self.write('Contents/Resources/unrelated.txt', b'ordinary resource')
        self.entitlements = Path(self.temp.name) / 'Release.entitlements'
        self.expected = {'com.apple.security.network.client': True,
                         'com.apple.security.network.server': True,
                         'com.apple.security.app-sandbox': False}
        self.entitlements.write_bytes(plistlib.dumps(self.expected))

    def write(self, relative, data):
        path = self.app / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return path

    def macho(self, relative):
        return self.write(relative, b'\xcf\xfa\xed\xfe' + bytes(32))

    def test_signs_inside_out_with_only_outer_release_entitlements(self):
        calls = []

        def run(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, plistlib.dumps(self.expected))

        signing.sign_app(self.app, 'Developer ID Application: Example', self.entitlements, run)
        signs = [args for args in calls if '--sign' in args]
        self.assertEqual(signs[-1][-1], str(self.app))
        binary = str(self.app / 'Contents/Frameworks/Mpv.framework/Versions/A/Mpv')
        framework = str(self.app / 'Contents/Frameworks/Mpv.framework')
        paths = [args[-1] for args in signs]
        self.assertLess(paths.index(binary), paths.index(framework))
        self.assertIn(str(self.app / 'Contents/Helpers/connection-helper'), paths)
        self.assertNotIn(str(self.app / 'Contents/MacOS/openpelo'), paths)
        self.assertTrue(all('--deep' not in args for args in signs))
        self.assertTrue(all('--entitlements' not in args for args in signs[:-1]))
        self.assertIn('--entitlements', signs[-1])
        self.assertTrue(all('--timestamp' in args for args in signs))
        self.assertTrue(any('--verify' in args and '--strict' in args for args in calls))

    def test_adhoc_build_does_not_request_timestamp(self):
        calls = []

        def run(args, **kwargs):
            calls.append(args)
            return subprocess.CompletedProcess(args, 0, plistlib.dumps(self.expected))

        signing.sign_app(self.app, '-', self.entitlements, run)
        self.assertTrue(all('--timestamp=none' in args for args in calls if '--sign' in args))

    def test_signing_failure_aborts_before_signing_outer_app(self):
        def run(args, **kwargs):
            raise subprocess.CalledProcessError(1, args)

        with self.assertRaises(subprocess.CalledProcessError):
            signing.sign_app(self.app, '-', self.entitlements, run)

    def test_entitlement_mismatch_and_debug_permission_are_rejected(self):
        for actual in ({}, {**self.expected, 'com.apple.security.get-task-allow': True}):
            def run(args, **kwargs):
                return subprocess.CompletedProcess(args, 0, plistlib.dumps(actual))
            with self.assertRaises(ValueError):
                signing.verify_signed_entitlements(self.app, self.expected, run)

    def test_missing_decoder_dependency_is_rejected(self):
        (self.app / 'Contents/Frameworks/Mpv.framework/Versions/A/Mpv').unlink()
        (self.app / 'Contents/Frameworks/Mpv.framework/Versions/A').rmdir()
        (self.app / 'Contents/Frameworks/Mpv.framework/Versions').rmdir()
        (self.app / 'Contents/Frameworks/Mpv.framework').rmdir()
        with self.assertRaisesRegex(ValueError, 'Mpv.framework'):
            signing.validate_bundle(self.app)

    def test_symlinks_do_not_duplicate_frameworks_or_escape_app(self):
        framework = self.app / 'Contents/Frameworks/Mpv.framework'
        external = Path(self.temp.name) / 'external'
        external.mkdir()
        (external / 'helper').write_bytes(b'\xcf\xfa\xed\xfe' + bytes(32))
        try:
            (framework / 'Mpv').symlink_to('Versions/A/Mpv')
            (self.app / 'Contents/Frameworks/external').symlink_to(external, target_is_directory=True)
        except OSError as error:
            self.skipTest(f'Symlink creation is unavailable: {error}')
        targets = signing.signing_targets(self.app)
        self.assertNotIn(framework / 'Mpv', targets)
        self.assertNotIn(external / 'helper', targets)
        self.assertTrue(all(path.is_relative_to(self.app) for path in targets))

    def test_source_declares_local_network_and_adb_services(self):
        info = signing.read_plist(ROOT / 'macos/Runner/Info.plist')
        self.assertTrue(info['NSLocalNetworkUsageDescription'].strip())
        self.assertIn('_adb-tls-connect._tcp', info['NSBonjourServices'])


if __name__ == '__main__':
    unittest.main()
