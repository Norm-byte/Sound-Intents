class Event {
  final String id;
  final String title;
  final String? intent;
  final String? startTimeUTC;
  final String? soundUrl;
  final String? visualUrl;

  Event({required this.id, required this.title, this.intent, this.startTimeUTC, this.soundUrl, this.visualUrl});

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'intent': intent,
        'startTimeUTC': startTimeUTC,
        'soundUrl': soundUrl,
        'visualUrl': visualUrl,
      };

  static Event fromJson(Map<String, dynamic> j) => Event(
        id: j['id'] as String,
        title: j['title'] as String,
        intent: j['intent'] as String?,
        startTimeUTC: j['startTimeUTC'] as String?,
        soundUrl: j['soundUrl'] as String?,
        visualUrl: j['visualUrl'] as String?,
      );
}
