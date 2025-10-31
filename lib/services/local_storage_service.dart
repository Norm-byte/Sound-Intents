import 'dart:convert';
import 'dart:html' as html;
import '../models/event.dart';

class LocalStorageService {
  final String _key = 'harmony_events';

  Future<List<Event>> loadEvents() async {
    try {
      final raw = html.window.localStorage[_key];
      if (raw == null) return [];
      final List<dynamic> data = jsonDecode(raw);
      return data.map((e) => Event.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveEvents(List<Event> events) async {
    final data = events.map((e) => e.toJson()).toList();
    html.window.localStorage[_key] = jsonEncode(data);
  }
}
