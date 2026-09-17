import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_model.dart';
import '../models/device_model.dart';
import 'apk_probe_service.dart';

class CatalogSnapshot {
  final Map<String, AppModel> verifiedApps;
  final Map<String, String> unavailable;
  const CatalogSnapshot(this.verifiedApps, this.unavailable);

  Map<String, AppModel> forDevice(DeviceModel device) {
    final api = device.apiLevel;
    if (api == null) return {};
    final abis = device.supportedAbis.isNotEmpty
        ? device.supportedAbis
        : [if (device.abi != null) device.abi!];
    return Map.fromEntries(
      verifiedApps.entries.where(
        (entry) => entry.value.metadata!.supportsDevice(api, abis),
      ),
    );
  }
}

/// Revalidates once per day, with a one-hour retry for unavailable sources.
/// Only ZIP metadata and the manifest are transferred by the probe service.
class CatalogService {
  static const _cacheKey = 'apk_catalog_probe_v1';
  static const refreshInterval = Duration(hours: 24);
  static const retryInterval = Duration(hours: 1);
  final ApkProbeService probeService;
  final DateTime Function() _now;
  final Map<String, _CachedProbe> _cache = {};
  Future<void>? _restore;
  Future<CatalogSnapshot>? _inFlight;

  CatalogService({ApkProbeService? probeService, DateTime Function()? now})
    : probeService = probeService ?? ApkProbeService(),
      _now = now ?? DateTime.now;

  Future<CatalogSnapshot> refresh(
    Iterable<AppModel> sources, {
    required Future<String> Function(AppModel) resolveUrl,
    bool force = false,
  }) async {
    final pending = _inFlight;
    if (pending != null) {
      final result = await pending;
      if (!force) return result;
    }
    final work = _refresh(sources.toList(), resolveUrl, force);
    _inFlight = work;
    try {
      return await work;
    } finally {
      if (identical(_inFlight, work)) _inFlight = null;
    }
  }

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_cacheKey);
      if (text == null) return;
      final data = jsonDecode(text) as Map<String, dynamic>;
      for (final entry in data.entries) {
        try {
          _cache[entry.key] = _CachedProbe.fromJson(
            entry.value as Map<String, dynamic>,
          );
        } catch (_) {
          // A corrupt entry must not prevent checking other sources.
        }
      }
    } catch (_) {
      // Cache is optional. Probe normally if storage is unavailable.
    }
  }

  Future<CatalogSnapshot> _refresh(
    List<AppModel> sources,
    Future<String> Function(AppModel) resolveUrl,
    bool force,
  ) async {
    await (_restore ??= _restoreCache());
    final verified = <String, AppModel>{};
    final unavailable = <String, String>{};
    var next = 0;
    Future<void> worker() async {
      while (next < sources.length) {
        final app = sources[next++];
        final key = jsonEncode([
          app.url,
          app.assetName,
          app.assetPattern,
          app.sha256,
        ]);
        var cached = _cache[key];
        final age = cached == null ? null : _now().difference(cached.checkedAt);
        final ttl = cached?.result == null ? retryInterval : refreshInterval;
        if (force || age == null || age.isNegative || age >= ttl) {
          try {
            final downloadUrl = await resolveUrl(app);
            final uri = Uri.parse(downloadUrl);
            if (uri.scheme != 'https') {
              throw const FormatException('APK source must use HTTPS.');
            }
            final result = await probeService.probe(
              uri,
              previous: cached?.downloadUrl == downloadUrl
                  ? cached?.result
                  : null,
            );
            cached = _CachedProbe(_now(), downloadUrl, result, null);
          } catch (error) {
            // Never keep an unavailable/stale APK marked installable.
            cached = _CachedProbe(_now(), null, null, error.toString());
          }
          _cache[key] = cached;
        }
        final result = cached!.result;
        if (result != null && cached.downloadUrl != null) {
          verified[app.name] = app.withProbe(
            result.metadata,
            cached.downloadUrl!,
          );
        } else {
          unavailable[app.name] = cached.error ?? 'Could not verify this APK.';
        }
      }
    }

    await Future.wait(
      List.generate(sources.length.clamp(0, 3), (_) => worker()),
    );
    final activeKeys = sources
        .map(
          (app) => jsonEncode([
            app.url,
            app.assetName,
            app.assetPattern,
            app.sha256,
          ]),
        )
        .toSet();
    _cache.removeWhere((key, _) => !activeKeys.contains(key));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode(_cache.map((key, value) => MapEntry(key, value.toJson()))),
      );
    } catch (_) {
      // Continue with the in-memory cache.
    }
    return CatalogSnapshot({
      for (final app in sources)
        if (verified.containsKey(app.name)) app.name: verified[app.name]!,
    }, unavailable);
  }
}

class _CachedProbe {
  final DateTime checkedAt;
  final String? downloadUrl;
  final ApkProbeResult? result;
  final String? error;
  const _CachedProbe(this.checkedAt, this.downloadUrl, this.result, this.error);

  Map<String, dynamic> toJson() => {
    'checkedAt': checkedAt.toUtc().toIso8601String(),
    'downloadUrl': downloadUrl,
    'result': result?.toJson(),
    'error': error,
  };

  factory _CachedProbe.fromJson(Map<String, dynamic> json) => _CachedProbe(
    DateTime.parse(json['checkedAt'] as String),
    json['downloadUrl'] as String?,
    json['result'] == null
        ? null
        : ApkProbeResult.fromJson(json['result'] as Map<String, dynamic>),
    json['error'] as String?,
  );
}
