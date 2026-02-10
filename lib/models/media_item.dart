import 'package:cloud_firestore/cloud_firestore.dart';

class MediaItem {
  final String id;
  final String name;
  final String url;
  final String path;
  final String type; // 'video' | 'image' | 'audio' | 'other'
  final String section;
  final String? thumbnailUrl;
  final DateTime uploadedAt;

  MediaItem({
    required this.id,
    required this.name,
    required this.url,
    required this.path,
    required this.type,
    required this.section,
    this.thumbnailUrl,
    required this.uploadedAt,
  });

  factory MediaItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MediaItem(
      id: doc.id,
      name: data['name'] ?? '',
      url: data['url'] ?? '',
      path: data['path'] ?? '',
      type: data['type'] ?? 'other',
      section: data['section'] ?? 'General',
      thumbnailUrl: data['thumbnailUrl'],
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'url': url,
      'path': path,
      'type': type,
      'section': section,
      'thumbnailUrl': thumbnailUrl,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
    };
  }
}
