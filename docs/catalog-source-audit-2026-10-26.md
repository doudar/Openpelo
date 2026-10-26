# Application source audit — 2026-10-26

Audited all 39 entries from `main` at `27ca5f1`, then the two new entries and
the replacement VLC URL. No APKs were installed and no device was connected.
The isolated checkout preserves the existing OpenRide and QZ additions.

## Changes

- **Plex:** add the archived Android mobile client **10.26.0.2578**, ARM64,
  minimum API 23 (Android 6), package `com.plexapp.android`. The APK comes
  directly from `downloads.plex.tv`, linked in Plex's
  [official 10.26.0 announcement](https://forums.plex.tv/t/plex-for-android/29115/525).
  Its description explicitly says archived and retains the publisher's
  **Plex Pass required** notice. This is the Google Play mobile-capable Kepler
  build from before the redesigned mobile client, not a newer TV-only APK.
  The [current mobile announcements](https://forums.plex.tv/t/909610) point to
  Google Play, and Plex's public downloads API did not list an Android APK.
  This entry therefore does **not** promise the latest mobile version or
  automatic version discovery. The published CDN URL responded without login;
  no credentials, cookies, access-control bypass, or third-party mirror were used.
- **Jellyfin:** add the official [Android mobile client](https://github.com/jellyfin/jellyfin-android),
  using the latest stable release's `jellyfin-android-v*-libre-release.apk`.
  The narrow pattern excludes debug APKs, proprietary builds, Android App
  Bundles, and the separate [Android TV client](https://github.com/jellyfin/jellyfin-androidtv).
  At audit time it selected **2.7.3**, package `org.jellyfin.mobile`, minimum
  API 21 (Android 5), with ARM32, ARM64, x86, and x86_64 native libraries.
  It requires a Jellyfin server and Android System WebView.
- **VLC Legacy:** replace the `get.videolan.org` mirror dispatcher with
  [VideoLAN's official archive](https://download.videolan.org/pub/videolan/vlc-android/3.2.12/VLC-Android-3.2.12-armeabi-v7a.apk).
  The dispatcher returned HTTP 200 to a byte-range request, which the production
  probe correctly rejects. Its HEAD redirect reached a live mirror; this was
  **range-incompatible delivery, not a confirmed 404**. The official archive
  passed the same production probe for version 3.2.12, minimum API 17, ARM32.
  The version is unchanged.
- Pin SHA-256 for the two immutable Plex and VLC URLs after downloading their
  complete APKs locally and computing the hashes. No APK binaries are committed.

## Method and limits

`dart run tool/audit_catalog.dart` resolves latest GitHub releases using the
production `selectApkAssetName`, then calls the production `ApkProbeService`.
It checks HTTPS redirects, bounded byte ranges, ZIP metadata and Android manifest
fields. Exact filenames take priority; otherwise the configured glob must match
one APK (or a release with only one APK can be selected). Direct versioned URLs
remain pinned; they do not discover newer versions automatically.

OpenPelo derives minimum SDK, native ABIs, package ID and version from each APK,
then filters against the selected device's API and supported ABIs. It caches
successful probes for 24 hours and retries unavailable sources after one hour.
The catalog refresh button forces a recheck. Static `abi` fields are ignored.
The production installer also rechecks downloaded APKs and configured hashes.

All original sources other than the VLC dispatcher passed the live metadata
probe, including OpenGApps, F-Droid, Mozilla, GitHub and Steam. No 404/410,
login gate or bot challenge was observed in those successful checks. This does
not guarantee future availability: rate limits, bot protection, redirects and
upstream release asset names can change. An HTTP error alone should not be
classified as a dead link or worked around using an arbitrary mirror.

Working pinned releases were retained, including older Firefox, launcher,
file-manager and media builds. Accessibility of an old APK does not establish
that it is maintained or that its online services still work. Existing “Gen 1”
descriptions are not evidence of compatibility (some of those APKs require API
21 or 23); the manifest-based filter remains authoritative for SDK/ABI checks.
No playback, sign-in, DRM, Google services, WebView behavior, server compatibility,
or Peloton hardware functionality was tested. In particular, Plex is an archived
client with no verified current mobile APK update path in this catalog.

## Observed APK metadata

All rows below passed the production probe; VLC uses the replacement archive.
`none` means no native libraries were found, not a hardware test.

| Application | Version | Minimum API | Native ABIs |
| --- | --- | ---: | --- |
| SmartSpin2k | 2.0.5 | 24 | arm64-v8a, armeabi-v7a, x86_64 |
| Grupetto | v0.0.43 | 21 | none |
| OpenRide | 1.0.0-real | 29 | arm64-v8a |
| QZ Standard Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ NordicTrack Treadmill Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ NordicTrack Bike Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ NordicTrack Rower Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ FitPro Treadmill Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ FitPro Bike Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ FitPro Elliptical Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ FitPro Rower Nightly | 2.22.0 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ Peloton Bike Nightly | 2.21.6 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| QZ Peloton Bike+ Nightly | 2.21.5 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Google Text-to-Speech | googletts.google-speech-apk_20220321.02_p2.439618283 | 23 | arm64-v8a |
| Google Text-to-Speech Legacy | 3.16.6.232892818 | 19 | armeabi-v7a |
| Lawnchair Launcher | 15.Beta 2 | 26 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Kvaesitso | 1.35.4-fdroid | 26 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| FireFox Focus | 133.0.3 | 21 | arm64-v8a |
| Fulguris | 2.0.10 | 21 | none |
| EinkBro | 16.7.1 | 24 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Aurora Store | 4.7.5 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| FDroid | 2.0.2 | 24 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Obtanium | 1.7.3 | 26 | arm64-v8a |
| Moonlight Streaming | 12.1 | 16 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| MaterialFiles | 1.7.5 | 23 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| KISS Launcher | 3.21.3 | 15 | none |
| Lawnchair Launcher Gen 1 | 1.2.0.1884 | 21 | none |
| Firefox ESR | 68.11.0 | 16 | armeabi-v7a |
| Emby | 3.5.71 | 21 | arm64-v8a |
| LibreTube | 32.1 | 26 | none |
| NewPipe | 0.29.1 | 23 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| SkyTubeLegacy | 2.999 | 14 | none |
| NewPipe Legacy | 0.21.16 | 19 | none |
| Simple File Manager | 6.16.1 | 23 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Simple Gallery | 6.28.1 | 23 | arm64-v8a, armeabi, armeabi-v7a, mips, mips64, x86, x86_64 |
| Amaze File Manager | 3.10 | 19 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| RadioDroid | 0.86 | 16 | none |
| Steam Link | 1.4.3 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| Plex | 10.26.0.2578 | 23 | arm64-v8a |
| Jellyfin | 2.7.3 | 21 | arm64-v8a, armeabi-v7a, x86, x86_64 |
| VLC Legacy | 3.2.12 | 17 | armeabi-v7a |
