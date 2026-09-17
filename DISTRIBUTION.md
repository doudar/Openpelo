# OpenPelo Distribution Guide

Flutter desktop applications must be distributed with their supporting
libraries and data directory; the executable is not standalone.

## Windows

```powershell
flutter build windows --release
```

The bundle is written to `build\windows\x64\runner\Release`. Zip the entire
directory, or create the installer used by CI:

```powershell
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" `
  "/DMyAppVersion=1.0.72" `
  "windows\InnoSetupScript.iss"
```

The installer is written to `dist\OpenPelo_Setup_Windows.exe`.

## macOS

```bash
flutter build macos --release
```

Distribute the complete `openpelo.app` bundle. The GitHub Actions workflow
signs the application and DMG, submits it for notarization, and staples the
ticket only on trusted `main` builds where signing secrets are available.
It uses `tool/sign_macos.py` to sign native components before the outer app,
apply the release entitlements, and verify the result. Pull-request builds
exercise the same script with an ad-hoc identity. CI validates the stapled DMG
and checks its Gatekeeper assessment before publishing it. Hardware validation
steps are in [CONTRIBUTING.md](./CONTRIBUTING.md#macos-permissions-and-release-verification).

## Linux

```bash
flutter build linux --release
tar -czf OpenPelo-Linux.tar.gz -C build/linux/x64/release/bundle .
```

Distribute the complete bundle, not only the `openpelo` executable.

## Bundled ADB

The archives under `ADB/` are Flutter assets. At runtime OpenPelo extracts the
appropriate archive into the user's application-support directory. When these
archives are updated, replace Windows, macOS, and Linux together and verify
that every `source.properties` reports the intended Platform-Tools revision.

## Mobile signing

Android release builds are deliberately unsigned unless
`android/key.properties` supplies `storeFile`, `storePassword`, `keyAlias`, and
`keyPassword`. Never distribute an Android build signed with Flutter's debug
key. Apple mobile distribution likewise requires a registered bundle ID and
valid signing profile.
