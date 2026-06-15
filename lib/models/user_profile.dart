import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class UserProfile {
  final String id;
  final String name;
  final String? fullName;
  final String? username;
  final String? displayName;
  final String email;
  final String? country;
  final String? timeZone;
  final String? platform;
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
  final String? vipQuotaTier; // Optional VIP override: starter_access/unlimited_access

  UserProfile({
    required this.id,
    required this.name,
    this.fullName,
    this.username,
    this.displayName,
    required this.email,
    this.country,
    this.timeZone,
    this.platform,
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
    this.vipQuotaTier,
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

    String? parseFirstDate(List<dynamic> values) {
      for (final value in values) {
        final parsed = parseDate(value);
        if (parsed != null && parsed.trim().isNotEmpty) {
          return parsed;
        }
      }
      return null;
    }

    String safeString(dynamic value, String fallback) {
      if (value is String) return value;
      if (value != null) return value.toString();
      return fallback;
    }

    String? safeOptionalString(dynamic value) {
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
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
      fullName: safeOptionalString(data['fullName']),
      username: safeOptionalString(data['username'] ?? data['userName']),
      displayName: safeOptionalString(data['displayName']),
      email: safeString(data['email'], 'no-email@example.com'),
      country: safeOptionalString(data['country'] ?? data['countryCode']),
      timeZone: safeOptionalString(data['timeZone']),
      platform: safeOptionalString(data['platform']),
      status: safeString(data['status'], 'trial'),
      eventsJoined: safeInt(data['eventsJoined']),
      messagesReceived: safeInt(data['messagesReceived']),
      subscriptionPlan: safeString(data['subscriptionPlan'], 'Free'),
      renewalDate: parseDate(data['renewalDate']),
      joinDate: parseFirstDate([
        data['joinDate'],
        data['createdAt'],
        data['created_at'],
        data['signupDate'],
        data['signUpDate'],
        data['accountCreatedAt'],
      ]),
      lastActive: parseDate(data['lastActive']),
      suspensionExpiry: (data['suspensionExpiry'] as Timestamp?)?.toDate(),
      lastAdminAction: data['lastAdminAction'] as String?,
      willRenew: data['willRenew'] as bool? ?? false,
      vipQuotaTier: data['vipQuotaTier'] as String?,
    );
  }


  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'fullName': fullName,
      'username': username,
      'displayName': displayName,
      'email': email,
      'country': country,
      'timeZone': timeZone,
      'platform': platform,
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
      'vipQuotaTier': vipQuotaTier,
    };
  }

  UserProfile copyWith({
    String? name,
    String? fullName,
    String? username,
    String? displayName,
    String? email,
    String? country,
    String? timeZone,
    String? platform,
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
    String? vipQuotaTier,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      country: country ?? this.country,
      timeZone: timeZone ?? this.timeZone,
      platform: platform ?? this.platform,
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
      vipQuotaTier: vipQuotaTier ?? this.vipQuotaTier,
    );
  }
}
