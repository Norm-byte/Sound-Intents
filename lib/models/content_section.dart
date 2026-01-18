class ContentSection {
  final String id;
  final String title;
  final String? featuredContentId;
  final int order;
  final List<String> subcategories; // New field
  final Map<String, String>? subcategoryFeaturedContentIds; // New Map for subcategory specific featured content

  ContentSection({
    required this.id,
    required this.title,
    this.featuredContentId,
    required this.order,
    this.subcategories = const [],
    this.subcategoryFeaturedContentIds,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'featuredContentId': featuredContentId,
      'order': order,
      'subcategories': subcategories,
      'subcategoryFeaturedContentIds': subcategoryFeaturedContentIds,
    };
  }

  factory ContentSection.fromMap(String id, Map<String, dynamic> map) {
    return ContentSection(
      id: id,
      title: map['title'] ?? '',
      featuredContentId: map['featuredContentId'],
      order: map['order'] ?? 0,
      subcategories: List<String>.from(map['subcategories'] ?? []),
      subcategoryFeaturedContentIds: (map['subcategoryFeaturedContentIds'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
    );
  }
}
