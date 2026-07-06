class InstalledAppModel {
  final String packageName;
  final String label;
  final bool isSystemApp;

  const InstalledAppModel({
    required this.packageName,
    required this.label,
    required this.isSystemApp,
  });
}
