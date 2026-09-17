# Contributing to OpenPelo

This guide covers building OpenPelo, updating its app catalog, and refreshing
the documentation screenshots. For installation and everyday use, see the
[README](./README.md).

## Build from source

### Requirements

- Flutter 3.44.4 or newer
- Dart 3.10 or newer
- Platform prerequisites from Flutter's desktop setup guide
- Inno Setup 6 when creating the Windows installer

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

Use `-d macos` or `-d linux` on those platforms. Release bundles are created
with:

```powershell
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

See [DISTRIBUTION.md](./DISTRIBUTION.md) for packaging details.

### Refresh the README screenshots

The [screenshot script](./tool/capture_readme_screenshots_test.dart) renders the
production screens and dialogs with sample data. It does not initialize ADB or
connect to a device. From the repository root, run:

```powershell
flutter test tool/capture_readme_screenshots_test.dart
```

It writes five PNGs to [`images/screenshots`](./images/screenshots). The script
uses Windows Segoe UI by default; on another platform, set
`OPENPELO_SCREENSHOT_FONT` to the absolute path of a local TrueType font.
Review the generated images before committing them with UI changes.

## Application catalog

Applications are defined in `apps_config.json`:

```json
{
  "apps": {
    "Example App": {
      "url": "https://github.com/example/app/releases/latest",
      "asset_name": "example-arm64.apk",
      "asset_pattern": "example-*-arm64.apk",
      "package_id": "com.example.app",
      "sha256": "optional-lowercase-sha256",
      "description": "Description shown in OpenPelo",
      "abi": "arm64-v8a"
    }
  }
}
```

- `url` must use HTTPS. GitHub latest-release URLs and API URLs are resolved
  to release assets automatically.
- `asset_name` is the preferred APK filename.
- `asset_pattern` is an optional glob used when release filenames contain a
  changing version. Ambiguous matches are rejected.
- `package_id` is the optional Android application ID used when resolving an
  incompatible-signature reinstall.
- `sha256` is an optional integrity checksum. Add it whenever the URL points
  to an immutable, versioned APK.
- `abi` is `arm64-v8a` or `armeabi-v7a`.

## Automated builds

GitHub Actions formats, analyzes, and tests the project before building
Windows, macOS, and Linux artifacts. Pull requests receive validation builds;
the macOS app is ad-hoc signed to exercise packaging without release secrets.
Trusted pushes to `main` use Developer ID signing and notarize the macOS DMG,
bump the patch version, tag it, and publish a GitHub release.

The Windows installer version is injected from `version.json` by the workflow.
Mobile releases require their own signing configuration; Android release
credentials belong in an untracked `android/key.properties` file.

### macOS permissions and release verification

`macos/Runner/Info.plist` declares local-network use and the ADB Bonjour service
types. On macOS 15 and newer, users may need to allow OpenPelo in **Privacy &
Security → Local Network**. The viewer receives the Peloton's video over ADB;
it does not capture the Mac desktop or require Mac Screen Recording permission.

The Mac build resolves the native CocoaPods dependencies and retains the
resulting `Podfile.lock` as the `macOS-resolved-dependencies` CI artifact. Update
the checked-in lockfile from a successful Mac build when dependencies change.
Do not synthesize its checksums on another platform.

`tool/sign_macos.py` checks the built app's network declarations, viewer
frameworks, scrcpy server and license, then signs native code from the inside
out. It applies `Release.entitlements` to the outer app and verifies the finished
signature and embedded entitlements. Run it after the release build:

```sh
python3 tool/sign_macos.py build/macos/Build/Products/Release/openpelo.app \
  --identity 'Developer ID Application: YOUR SIGNING IDENTITY'
```

Use `--identity -` for an ad-hoc local build. Such a build is not a notarized
distribution build. Portable signing-plan tests run with
`python3 -m unittest discover -s tool/tests -p 'test_*.py'`.

Before releasing viewer changes, test the signed/notarized application from
Finder on a Mac with a Peloton attached. A terminal launch can have different
local-network permission behavior. Confirm catalog refresh, USB and Wi-Fi ADB,
the local-network prompt and recovery after denying permission, embedded video
and controls, and recording to the selected folder. Close the viewer while
recording and verify the saved MP4 plays. Cover Intel and Apple Silicon when
available. CI signature checks do not establish these hardware results.

## Download validation

Review catalog changes carefully. Downloads must use HTTPS and are checked for
APK/ZIP structure. Immutable downloads can also be pinned with SHA-256.
Android performs its normal package-signing checks during installation.
