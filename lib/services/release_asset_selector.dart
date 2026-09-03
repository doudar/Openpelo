String selectApkAssetName(
  Iterable<String> assetNames, {
  String? exactName,
  String? globPattern,
}) {
  final apkNames = assetNames
      .where((name) => name.toLowerCase().endsWith('.apk'))
      .toList(growable: false);

  if (exactName != null && apkNames.contains(exactName)) {
    return exactName;
  }

  if (globPattern != null && globPattern.trim().isNotEmpty) {
    final matcher = _globToRegExp(globPattern.trim());
    final matches = apkNames.where(matcher.hasMatch).toList(growable: false);
    if (matches.length == 1) return matches.single;
    if (matches.isEmpty) {
      throw StateError('No APK asset matched "$globPattern".');
    }
    throw StateError('Multiple APK assets matched "$globPattern": $matches');
  }

  if (apkNames.length == 1) return apkNames.single;
  if (apkNames.isEmpty) {
    throw StateError('The release does not contain an APK asset.');
  }
  throw StateError(
    'The release contains multiple APK assets; configure asset_pattern: $apkNames',
  );
}

RegExp _globToRegExp(String pattern) {
  final escaped = RegExp.escape(pattern).replaceAll(r'\*', '.*');
  return RegExp('^$escaped\$', caseSensitive: false);
}
