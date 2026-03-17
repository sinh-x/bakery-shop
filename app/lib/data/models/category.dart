class Category {
  final int id;
  final String slug;
  final String name;
  final String codePrefix;
  final int active;

  const Category({
    required this.id,
    required this.slug,
    required this.name,
    required this.codePrefix,
    required this.active,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as int,
        slug: json['slug'] as String,
        name: json['name'] as String,
        codePrefix: json['code_prefix'] as String,
        active: json['active'] as int? ?? 1,
      );
}
