import 'apk_metadata.dart';

class AppModel {
  final String name;
  final String description;
  final String url;
  final String? assetName;
  final String? assetPattern;
  final String? packageId;
  final String? sha256;
  final String category;
  final String? recommendationId;
  final int recommendationPriority;
  final ApkMetadata? metadata;
  final String? resolvedDownloadUrl;
  bool isSelected = false;

  AppModel({
    required this.name,
    required this.description,
    required this.url,
    this.assetName,
    this.assetPattern,
    this.packageId,
    this.sha256,
    this.category = 'Other',
    this.recommendationId,
    this.recommendationPriority = 0,
    this.metadata,
    this.resolvedDownloadUrl,
  });

  AppModel withProbe(ApkMetadata metadata, String downloadUrl) => AppModel(
    name: name,
    description: description,
    url: url,
    assetName: assetName,
    assetPattern: assetPattern,
    packageId: metadata.packageId ?? packageId,
    sha256: sha256,
    category: category,
    recommendationId: recommendationId,
    recommendationPriority: recommendationPriority,
    metadata: metadata,
    resolvedDownloadUrl: downloadUrl,
  );

  factory AppModel.fromJson(String name, Map<String, dynamic> json) {
    return AppModel(
      name: name,
      description: json['description'] ?? '',
      url: json['url'] ?? '',
      assetName: json['asset_name'] ?? json['package_name'],
      assetPattern: json['asset_pattern'],
      packageId: json['package_id'] ?? json['package'],
      sha256: json['sha256'],
      category: json['category'] as String? ?? 'Other',
      recommendationId: json['recommendation_id'] as String?,
      recommendationPriority: json['recommendation_priority'] as int? ?? 0,
    );
  }
}
