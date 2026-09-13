class Subject {
  final String id;
  final String name;
  final String slug;
  final int displayOrder;
  final bool isActive;

  const Subject({
    required this.id,
    required this.name,
    required this.slug,
    required this.displayOrder,
    required this.isActive,
  });

  factory Subject.fromJson(Map<String, dynamic> json) => Subject(
        id: json['id'] as String,
        name: json['name'] as String,
        slug: json['slug'] as String,
        displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'slug': slug,
        'display_order': displayOrder,
        'is_active': isActive,
      };
}
