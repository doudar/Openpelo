class AppModel {
  final String name;
  final String description;
  final String url;
  final String? assetName;
  final String? assetPattern;
  final String? packageId;
  final String? sha256;
  final String? abi;
  bool isSelected = false;

  AppModel({
    required this.name,
    required this.description,
    required this.url,
    this.assetName,
    this.assetPattern,
    this.packageId,
    this.sha256,
    this.abi,
  });

  factory AppModel.fromJson(String name, Map<String, dynamic> json) {
    return AppModel(
      name: name,
      description: json['description'] ?? '',
      url: json['url'] ?? '',
      assetName: json['asset_name'] ?? json['package_name'],
      assetPattern: json['asset_pattern'],
      packageId: json['package_id'] ?? json['package'],
      sha256: json['sha256'],
      abi: json['abi'],
    );
  }
}
