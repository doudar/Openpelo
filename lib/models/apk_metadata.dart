/// Compatibility information read from an APK rather than inferred from its name.
class ApkMetadata {
  final int minSdk;
  final List<String> nativeAbis;
  final String? packageId;
  final String? versionName;

  ApkMetadata({
    required this.minSdk,
    required List<String> nativeAbis,
    this.packageId,
    this.versionName,
  }) : nativeAbis = List.unmodifiable(nativeAbis);

  /// An APK with no native libraries can run on any supported CPU architecture.
  bool supportsDevice(int api, List<String> abis) {
    if (api < minSdk) return false;
    return nativeAbis.isEmpty || nativeAbis.any(abis.contains);
  }

  Map<String, dynamic> toJson() => {
    'minSdk': minSdk,
    'nativeAbis': nativeAbis,
    if (packageId != null) 'packageId': packageId,
    if (versionName != null) 'versionName': versionName,
  };

  factory ApkMetadata.fromJson(Map<String, dynamic> json) => ApkMetadata(
    minSdk: json['minSdk'] as int,
    nativeAbis: (json['nativeAbis'] as List).cast<String>(),
    packageId: json['packageId'] as String?,
    versionName: json['versionName'] as String?,
  );
}
