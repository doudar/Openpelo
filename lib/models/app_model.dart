class AppModel {
  final String name;
  final String description;
  final String url;
  final String? package;
  final String? abi;
  bool isSelected = false;

  AppModel({
    required this.name,
    required this.description,
    required this.url,
    this.package,
    this.abi,
  });

  factory AppModel.fromJson(String name, Map<String, dynamic> json) {
    return AppModel(
      name: name,
      description: json['description'] ?? '',
      url: json['url'] ?? '',
      package: json['package'] ?? json['package_name'],
      abi: json['abi'],
    );
  }
}
