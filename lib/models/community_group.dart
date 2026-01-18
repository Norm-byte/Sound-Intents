import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class CommunityGroup {
  final String id;
  final String name;
  final String description;
  final String iconName; // "public", "favorite", etc.
  final int colorValue;
  final int memberCount; // For display/manual override, or we can fetch real count later
  final int sortOrder;
  final bool isPublished; // Controls visibility in the User App
  final bool isPaused;    // Controls ability to post/interact (Maintenance Mode)

  CommunityGroup({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    required this.colorValue,
    this.memberCount = 0,
    this.sortOrder = 0,
    this.isPublished = false, // Default to hidden
    this.isPaused = false,    // Default to active
  });

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'iconName': iconName,
      'colorValue': colorValue,
      'memberCount': memberCount,
      'sortOrder': sortOrder,
      'isPublished': isPublished,
      'isPaused': isPaused,
    };
  }

  // Create from Firestore Document
  factory CommunityGroup.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CommunityGroup(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      iconName: data['iconName'] ?? 'group',
      colorValue: data['colorValue'] ?? 0xFFFFFFFF,
      memberCount: data['memberCount'] ?? 0,
      sortOrder: data['sortOrder'] ?? 0,
      isPublished: data['isPublished'] ?? false,
      isPaused: data['isPaused'] ?? false,
    );
  }

  // Copy with
  CommunityGroup copyWith({
    String? id,
    String? name,
    String? description,
    String? iconName,
    int? colorValue,
    int? memberCount,
    int? sortOrder,
    bool? isPublished,
    bool? isPaused,
  }) {
    return CommunityGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      iconName: iconName ?? this.iconName,
      colorValue: colorValue ?? this.colorValue,
      memberCount: memberCount ?? this.memberCount,
      sortOrder: sortOrder ?? this.sortOrder,
      isPublished: isPublished ?? this.isPublished,
      isPaused: isPaused ?? this.isPaused,
    );
  }

  // Helper to get IconData from string name (simplified for now)
  IconData get iconData {
    switch (iconName) {
      case 'public': return Icons.public;
      case 'psychology': return Icons.psychology;
      case 'favorite': return Icons.favorite;
      case 'wb_sunny': return Icons.wb_sunny;
      case 'nature': return Icons.nature;
      case 'self_improvement': return Icons.self_improvement;
      case 'spa': return Icons.spa;
      case 'music_note': return Icons.music_note;
      default: return Icons.group;
    }
  }
}
