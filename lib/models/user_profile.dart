import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String status; // active, trial, suspended
  final int eventsJoined;
  final int messagesReceived;
  final String subscriptionPlan;
  final String? renewalDate;
  final String? joinDate;
  final String? lastActive;
  final DateTime? suspensionExpiry;
  final String? lastAdminAction;
  final bool willRenew; // From RevenueCat

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.eventsJoined,
    required this.messagesReceived,
    required this.subscriptionPlan,
    this.renewalDate,
    this.joinDate,
    this.lastActive,
    this.suspensionExpiry,
    this.lastAdminAction,
    this.willRenew = false,
  });

  factory UserProfile.fromFirestore(String id, Map<String, dynamic> data) {
    String? parseDate(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is Timestamp) {
        return DateFormat('MMM d, yyyy').format(value.toDate());
      }
      return null;
    }

    String safeString(dynamic value, String fallback) {
      if (value is String) return value;
      if (value != null) return value.toString();
      return fallback;
    }

    int safeInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return UserProfile(
      id: id,
      name: safeString(data['name'], 'Unknown User'),
      email: safeString(data['email'], 'no-email@example.com'),
      status: safeString(data['status'], 'trial'),
      eventsJoined: safeInt(data['eventsJoined']),
      messagesReceived: safeInt(data['messagesReceived']),
      subscriptionPlan: safeString(data['subscriptionPlan'], 'Free'),
      renewalDate: parseDate(data['renewalDate']),
      joinDate: parseDate(data['joinDate']),
      lastActive: parseDate(data['lastActive']),
      suspensionExpiry: (data['suspensionExpiry'] as Timestamp?)?.toDate(),
      lastAdminAction: data['lastAdminAction'] as String?,
      willRenew: data['willRenew'] as bool? ?? false,
    );
  }


  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'status': status,
      'eventsJoined': eventsJoined,
      'messagesReceived': messagesReceived,
      'subscriptionPlan': subscriptionPlan,
      'renewalDate': renewalDate,
      'joinDate': joinDate,
      'lastActive': lastActive,
      'suspensionExpiry': suspensionExpiry,
      'lastAdminAction': lastAdminAction,
      'willRenew': willRenew,
    };
  }

  UserProfile copyWith({
    String? name,
    String? email,
    String? status,
    int? eventsJoined,
    int? messagesReceived,
    String? subscriptionPlan,
    String? renewalDate,
    String? joinDate,
    String? lastActive,
    DateTime? suspensionExpiry,
    String? lastAdminAction,
    bool? willRenew,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      status: status ?? this.status,
      eventsJoined: eventsJoined ?? this.eventsJoined,
      messagesReceived: messagesReceived ?? this.messagesReceived,
      subscriptionPlan: subscriptionPlan ?? this.subscriptionPlan,
      renewalDate: renewalDate ?? this.renewalDate,
      joinDate: joinDate ?? this.joinDate,
      lastActive: lastActive ?? this.lastActive,
      suspensionExpiry: suspensionExpiry ?? this.suspensionExpiry,
      lastAdminAction: lastAdminAction ?? this.lastAdminAction,
      willRenew: willRenew ?? this.willRenew,
    );
  }
}
