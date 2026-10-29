# Stremio Mobile source audit - 2026-10-29

Adds optional **Stremio ARM64** and **Stremio ARM32** entries under
**Media & streaming** for [issue #63](https://github.com/doudar/Openpelo/issues/63).
Neither entry has a recommendation ID or is selected by default. Both use the
official Android Mobile client for touchscreens. No Android TV APK or third-party
add-on is bundled or configured; third-party add-ons and streaming-source support
are outside OpenPelo's scope.

## Release choice

At audit time, the [official downloads page](https://www.stremio.com/downloads)
linked Mobile **2.3.2** APKs on `dl.strem.io`, while the
[October 27 announcement](https://blog.stremio.com/stremio-tech-update-88-stremio-android-mobile-update/)
announced Mobile **2.5.0** without direct APK links. A fresh fetch of the downloads
page confirmed the same 2.3.2 URLs. Pin the published, verified 2.3.2 artifacts
rather than construct an unverified 2.5.0 URL. This is not a claim that 2.3.2 is
the latest release. Revisit the pin when official newer APK links are published,
then repeat the source, metadata, and checksum checks.

Like Plex and VLC's pinned downloads, these immutable URLs include SHA-256
checksums. Unlike Jellyfin's GitHub release selector, these entries do not discover
new versions automatically. Users should choose one build; ARM64 is preferred
when available. A device advertising both ARM ABIs can see both entries, as with
other compatible catalog variants. Both builds use package `com.stremio.one`.

## Verified artifacts

| Build | Official APK filename | Bytes | Minimum API | Native ABI |
| --- | --- | ---: | ---: | --- |
| ARM64 | `com.stremio.one-2.3.2-7145730-arm64-v8a.apk` | 94,307,844 | 24 (Android 7) | `arm64-v8a` |
| ARM32 | `com.stremio.one-2.3.2-5048578-armeabi-v7a.apk` | 90,242,210 | 24 (Android 7) | `armeabi-v7a` |

Both are under `https://dl.strem.io/android/v2.3.2-android/`. Full-file SHA-256:

- ARM64: `b5ad3fef7f47a37c30e578252368a8c16f886186bf4157f095dcd32358e6c91d`
- ARM32: `fb79f0d1398c2422819173e85a1b6d6d68543e1fc9cf24a5ffd724bb63903235`

The production `tool/audit_catalog.dart` passed against a temporary catalog
containing these two entries: HTTPS delivery, bounded byte ranges, ZIP structure,
manifest, native ABIs, package ID, and version **2.3.2** were verified. Full APKs
were downloaded locally, hashed, and inspected with the production
`ApkProbeService.inspectFile`; Android SDK `aapt dump badging` independently
confirmed the metadata. No APK binaries are committed.

Checks using the inspected metadata accepted API 24 with the matching ABI and
rejected API 23, x86, and unknown ABIs. SDK/ABI information is not hardcoded into
the catalog: the existing runtime probe and device filter remain authoritative.
The existing installer still validates APK/ZIP structure, the configured hash,
and downloaded APK metadata before installation. No validation bypass was added.

## Remaining validation

No device was connected or APK installed. These checks establish metadata and
download compatibility only. Physical Peloton validation remains required for
installation, sign-in, landscape touchscreen navigation, and playback. Codec,
audio, subtitles, network sources, and any DRM/service behavior remain untested.
In particular, devices below API 24 must be filtered out; the ARM32 build is not
a promise of Gen 1 support.
