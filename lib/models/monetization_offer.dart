import 'package:cloud_firestore/cloud_firestore.dart';

class MonetizationOffer {
  final String id;
  final String title;
  final String description;
  final bool isActive;
  final String revenueCatOfferingId; // Links to RevenueCat Offering
  final AppUsageLimits limits;
  final PaywallPresentation? presentation;

  MonetizationOffer({
    required this.id,
    required this.title,
    required this.description,
    required this.isActive,
    required this.revenueCatOfferingId,
    required this.limits,
    this.presentation,
  });

  factory MonetizationOffer.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MonetizationOffer(
      id: doc.id,
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      isActive: data['isActive'] ?? false,
      revenueCatOfferingId: data['revenueCatOfferingId'] ?? '',
      limits: AppUsageLimits.fromMap(data['limits'] ?? {}),
      presentation: data.containsKey('presentation')
          ? PaywallPresentation.fromMap(data['presentation'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'isActive': isActive,
      'revenueCatOfferingId': revenueCatOfferingId,
      'limits': limits.toMap(),
      if (presentation != null) 'presentation': presentation!.toMap(),
    };
  }
}

class AppUsageLimits {
  final int maxMonthlySends; // Deprecated, kept for backward compatibility if needed, but primary is now Daily
  final int maxDailySends;   // New primary limit
  final int maxActiveForums;
  final int maxMediaStorageMb;
  final bool allowVideoUploads;
  final int monthlyImageUploadLimit;
  final int myHarmonyVaultMaxImages;
  final int feedImageExpiryDays;

  AppUsageLimits({
    this.maxMonthlySends = 1500, // Approx 50/day * 30
    this.maxDailySends = 50,
    this.maxActiveForums = 1,
    this.maxMediaStorageMb = 100,
    this.allowVideoUploads = false,
    this.monthlyImageUploadLimit = 0,
    this.myHarmonyVaultMaxImages = 0,
    this.feedImageExpiryDays = 5,
  });

  factory AppUsageLimits.fromMap(Map<String, dynamic> map) {
    return AppUsageLimits(
      maxMonthlySends: map['maxMonthlySends'] ?? 1500,
      maxDailySends: map['maxDailySends'] ?? 50,
      maxActiveForums: map['maxActiveForums'] ?? 1,
      maxMediaStorageMb: map['maxMediaStorageMb'] ?? 100,
      allowVideoUploads: map['allowVideoUploads'] ?? false,
      monthlyImageUploadLimit: map['monthlyImageUploadLimit'] ?? 0,
      myHarmonyVaultMaxImages: map['myHarmonyVaultMaxImages'] ?? 0,
      feedImageExpiryDays: map['feedImageExpiryDays'] ?? 5,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'maxMonthlySends': maxMonthlySends,
      'maxDailySends': maxDailySends,
      'maxActiveForums': maxActiveForums,
      'maxMediaStorageMb': maxMediaStorageMb,
      'allowVideoUploads': allowVideoUploads,
      'monthlyImageUploadLimit': monthlyImageUploadLimit,
      'myHarmonyVaultMaxImages': myHarmonyVaultMaxImages,
      'feedImageExpiryDays': feedImageExpiryDays,
    };
  }
}

class PaywallPresentation {
  final String headline;
  final String subheadline;
  final String? backgroundImageUrl;
  final String primaryColorHex;
  final String ctaText;

  PaywallPresentation({
    required this.headline,
    required this.subheadline,
    this.backgroundImageUrl,
    required this.primaryColorHex,
    required this.ctaText,
  });

  factory PaywallPresentation.fromMap(Map<String, dynamic> map) {
    return PaywallPresentation(
      headline: map['headline'] ?? '',
      subheadline: map['subheadline'] ?? '',
      backgroundImageUrl: map['backgroundImageUrl'],
      primaryColorHex: map['primaryColorHex'] ?? '#000000',
      ctaText: map['ctaText'] ?? 'Subscribe',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'headline': headline,
      'subheadline': subheadline,
      'backgroundImageUrl': backgroundImageUrl,
      'primaryColorHex': primaryColorHex,
      'ctaText': ctaText,
    };
  }
}
