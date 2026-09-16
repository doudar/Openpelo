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
Windows, macOS, and Linux artifacts. Pull requests receive unsigned validation
builds. Trusted pushes to `main` additionally sign and notarize the macOS DMG,
bump the patch version, tag it, and publish a GitHub release.

The Windows installer version is injected from `version.json` by the workflow.
Mobile releases require their own signing configuration; Android release
credentials belong in an untracked `android/key.properties` file.

## Download validation

Review catalog changes carefully. Downloads must use HTTPS and are checked for
APK/ZIP structure. Immutable downloads can also be pinned with SHA-256.
Android performs its normal package-signing checks during installation.
