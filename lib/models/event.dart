class Event {
  final String id;
  final String title;
  final String? intent;
  final String? startTimeUTC;
  final String? soundUrl;
  final String? visualUrl;
  final String? mediaUrl; // Added for User compatibility
  final List<String>? attachmentUrls; // Generic uploaded attachments (docs/audio/images)
  final String? learnMoreContent; // Markdown content for Learn More
  final String? learnMoreYoutubeUrl; // YouTube embed URL
  final String? viewerSourceType; // 'youtube' | 'media' | 'other'
  final bool learnMoreShowViewer; // Toggle to show/hide viewer section in Learn More
  final List<String>? learnMoreFiles; // File URLs for uploads
  final String? learnMoreThumbnailUrl; // Thumbnail to represent uploaded blog/content
  final String? noticeBoardText; // Notice board message
  final String? noticeBoardCtaLabel; // CTA label for join button
  final String? noticeBoardCtaUrl; // CTA deep link/url
  final String? noticeBoardBgColor; // Hex color for Notice Board background (without #)
  final String? noticeBoardBgImage; // URL for Notice Board background image
  final int? flexibleDurationMinutes; // Flexible duration in minutes
  final int? durationSeconds; // Exact duration in seconds
  final bool isPublished; // Published to users
  final bool isDraft; // Draft state
  final bool? autoNotify; // Auto-send push notification on publish
  final String? notifyTitle; // Notification title
  final String? notifyBody; // Notification body
  final bool isAutomated; // Enable automated execution
  final String? recurrenceType; // 'None', 'Daily', 'Weekly', 'Monthly'
  final int? noticeBoardVisibilityAfterMinutes;
  final int? noticeBoardShowBeforeMinutes;
  final String? updatedAt;

  Event({
    required this.id,
    required this.title,
    this.intent,
    this.startTimeUTC,
    this.soundUrl,
    this.visualUrl,
    this.mediaUrl,
    this.attachmentUrls,
    this.learnMoreContent,
    this.learnMoreYoutubeUrl,
  this.viewerSourceType,
    this.learnMoreShowViewer = true,
    this.learnMoreFiles,
    this.learnMoreThumbnailUrl,
    this.noticeBoardText,
    this.noticeBoardCtaLabel,
    this.noticeBoardCtaUrl,
    this.noticeBoardBgColor,
    this.noticeBoardBgImage,
    this.flexibleDurationMinutes,
    this.durationSeconds,
    this.isPublished = false,
    this.isDraft = true,
    this.autoNotify,
    this.notifyTitle,
    this.notifyBody,
    this.isAutomated = false,
    this.recurrenceType,
    this.noticeBoardVisibilityAfterMinutes,
    this.noticeBoardShowBeforeMinutes,
    this.isRecurring,
    this.isRandomized,
    this.useTrendingIntent,
    this.originTimeZone,
    this.originTime,
    this.updatedAt,
    this.type,
  });

  final bool? isRecurring;
  final bool? isRandomized;
  final bool? useTrendingIntent;
  final String? originTimeZone;
  final String? originTime;
  final String? type; // 'global' or 'national'

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'intent': intent,
        'startTimeUTC': startTimeUTC,
        'soundUrl': soundUrl,
        'visualUrl': visualUrl,
        'mediaUrl': mediaUrl,
        'type': type,
    'attachmentUrls': attachmentUrls,
        'learnMoreContent': learnMoreContent,
        'learnMoreYoutubeUrl': learnMoreYoutubeUrl,
  'viewerSourceType': viewerSourceType,
        'learnMoreShowViewer': learnMoreShowViewer,
        'learnMoreFiles': learnMoreFiles,
        'learnMoreThumbnailUrl': learnMoreThumbnailUrl,
        'noticeBoardText': noticeBoardText,
        'noticeBoardCtaLabel': noticeBoardCtaLabel,
        'noticeBoardCtaUrl': noticeBoardCtaUrl,
        'noticeBoardBgColor': noticeBoardBgColor,
        'noticeBoardBgImage': noticeBoardBgImage,
        'flexibleDurationMinutes': flexibleDurationMinutes,
        'durationSeconds': durationSeconds,
        'isPublished': isPublished,
        'isDraft': isDraft,
        'autoNotify': autoNotify,
        'notifyTitle': notifyTitle,
        'notifyBody': notifyBody,
        'isAutomated': isAutomated,
        'recurrenceType': recurrenceType,
        'noticeBoardVisibilityAfterMinutes': noticeBoardVisibilityAfterMinutes,
        'noticeBoardShowBeforeMinutes': noticeBoardShowBeforeMinutes,
        'isRecurring': isRecurring,
        'isRandomized': isRandomized,
        'useTrendingIntent': useTrendingIntent,
        'originTimeZone': originTimeZone,
        'originTime': originTime,
        'updatedAt': updatedAt,
      };

  static Event fromJson(Map<String, dynamic> j) => Event(
        id: j['id'] as String,
        title: j['title'] as String,
        intent: j['intent'] as String?,
        startTimeUTC: j['startTimeUTC'] as String?,
        soundUrl: j['soundUrl'] as String?,
        visualUrl: j['visualUrl'] as String?,
        mediaUrl: j['mediaUrl'] as String?,
        type: j['type'] as String?, // Added type mapping
        attachmentUrls: (j['attachmentUrls'] as List?)?.cast<String>(),
        learnMoreContent: j['learnMoreContent'] as String?,
        learnMoreYoutubeUrl: j['learnMoreYoutubeUrl'] as String?,
  viewerSourceType: j['viewerSourceType'] as String?,
        learnMoreShowViewer: j['learnMoreShowViewer'] as bool? ?? true,
        learnMoreFiles: (j['learnMoreFiles'] as List?)?.cast<String>(),
        learnMoreThumbnailUrl: j['learnMoreThumbnailUrl'] as String?,
        noticeBoardText: j['noticeBoardText'] as String?,
        noticeBoardCtaLabel: j['noticeBoardCtaLabel'] as String?,
        noticeBoardCtaUrl: j['noticeBoardCtaUrl'] as String?,
        noticeBoardBgColor: j['noticeBoardBgColor'] as String?,
        noticeBoardBgImage: j['noticeBoardBgImage'] as String?,
        flexibleDurationMinutes: j['flexibleDurationMinutes'] as int?,
        durationSeconds: j['durationSeconds'] as int?,
        isPublished: j['isPublished'] as bool? ?? false,
        isDraft: j['isDraft'] as bool? ?? true,
        autoNotify: j['autoNotify'] as bool?,
        notifyTitle: j['notifyTitle'] as String?,
        notifyBody: j['notifyBody'] as String?,
        isAutomated: j['isAutomated'] as bool? ?? false,
        recurrenceType: j['recurrenceType'] as String?,
        noticeBoardVisibilityAfterMinutes: j['noticeBoardVisibilityAfterMinutes'] as int?,
        noticeBoardShowBeforeMinutes: j['noticeBoardShowBeforeMinutes'] as int?,
        isRecurring: j['isRecurring'] as bool?,
        isRandomized: j['isRandomized'] as bool?,
        useTrendingIntent: j['useTrendingIntent'] as bool?,
        originTimeZone: j['originTimeZone'] as String?,
        originTime: j['originTime'] as String?,
        updatedAt: j['updatedAt'] as String?,
      );

  Event copyWith({
    String? id,
    String? title,
    String? intent,
    String? startTimeUTC,
    String? soundUrl,
    String? visualUrl,
    String? mediaUrl,
    List<String>? attachmentUrls,
    String? learnMoreContent,
    String? learnMoreYoutubeUrl,
  String? viewerSourceType,
    bool? learnMoreShowViewer,
    List<String>? learnMoreFiles,
    String? learnMoreThumbnailUrl,
    String? noticeBoardText,
    String? noticeBoardCtaLabel,
    String? noticeBoardCtaUrl,
    String? noticeBoardBgColor,
    String? noticeBoardBgImage,
    int? flexibleDurationMinutes,
    int? durationSeconds,
    bool? isPublished,
    bool? isDraft,
    bool? autoNotify,
    String? notifyTitle,
    String? notifyBody,
    bool? isAutomated,
    String? recurrenceType,
    int? noticeBoardVisibilityAfterMinutes,
    int? noticeBoardShowBeforeMinutes,
    bool? isRecurring,
    bool? isRandomized,
    bool? useTrendingIntent,
    String? originTimeZone,
    String? originTime,
    String? updatedAt,
    String? type,
  }) {
    return Event(
      id: id ?? this.id,
      title: title ?? this.title,
      intent: intent ?? this.intent,
      startTimeUTC: startTimeUTC ?? this.startTimeUTC,
      soundUrl: soundUrl ?? this.soundUrl,
      visualUrl: visualUrl ?? this.visualUrl,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      type: type ?? this.type,
  attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      learnMoreContent: learnMoreContent ?? this.learnMoreContent,
      learnMoreYoutubeUrl: learnMoreYoutubeUrl ?? this.learnMoreYoutubeUrl,
  viewerSourceType: viewerSourceType ?? this.viewerSourceType,
      learnMoreShowViewer: learnMoreShowViewer ?? this.learnMoreShowViewer,
      learnMoreFiles: learnMoreFiles ?? this.learnMoreFiles,
      learnMoreThumbnailUrl: learnMoreThumbnailUrl ?? this.learnMoreThumbnailUrl,
      noticeBoardText: noticeBoardText ?? this.noticeBoardText,
      noticeBoardCtaLabel: noticeBoardCtaLabel ?? this.noticeBoardCtaLabel,
      noticeBoardCtaUrl: noticeBoardCtaUrl ?? this.noticeBoardCtaUrl,
      noticeBoardBgColor: noticeBoardBgColor ?? this.noticeBoardBgColor,
      noticeBoardBgImage: noticeBoardBgImage ?? this.noticeBoardBgImage,
      flexibleDurationMinutes: flexibleDurationMinutes ?? this.flexibleDurationMinutes,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isPublished: isPublished ?? this.isPublished,
      isDraft: isDraft ?? this.isDraft,
      autoNotify: autoNotify ?? this.autoNotify,
      notifyTitle: notifyTitle ?? this.notifyTitle,
      notifyBody: notifyBody ?? this.notifyBody,
      isAutomated: isAutomated ?? this.isAutomated,
      recurrenceType: recurrenceType ?? this.recurrenceType,
      noticeBoardVisibilityAfterMinutes: noticeBoardVisibilityAfterMinutes ?? this.noticeBoardVisibilityAfterMinutes,
      noticeBoardShowBeforeMinutes: noticeBoardShowBeforeMinutes ?? this.noticeBoardShowBeforeMinutes,
      isRecurring: isRecurring ?? this.isRecurring,
      isRandomized: isRandomized ?? this.isRandomized,
      useTrendingIntent: useTrendingIntent ?? this.useTrendingIntent,
      originTimeZone: originTimeZone ?? this.originTimeZone,
      originTime: originTime ?? this.originTime,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
