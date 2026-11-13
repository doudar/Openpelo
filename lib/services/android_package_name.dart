/// Android application IDs are two or more dot-separated segments, each a
/// Java identifier: a letter followed by letters, digits or underscores.
final RegExp _androidPackageNamePattern = RegExp(
  r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
);

/// Whether [value] is a well-formed Android application ID.
///
/// Package names are interpolated into device shell commands, so anything
/// that is not a plain dotted identifier is rejected before it gets there.
bool isValidAndroidPackageName(String value) =>
    _androidPackageNamePattern.hasMatch(value);
