import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import 'event_repository.dart';

/// Local storage implementation of EventRepository.
/// Uses browser localStorage for persistence.
class LocalEventRepository implements EventRepository {
  final String _key = 'harmony_events';

  @override
  Future<List<Event>> loadEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final List<dynamic> data = jsonDecode(raw);
      return data.map((e) => Event.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveEvent(Event event) async {
    final events = await loadEvents();
    final index = events.indexWhere((e) => e.id == event.id);
    if (index != -1) {
      events[index] = event;
    } else {
      events.insert(0, event);
    }
    await saveEvents(events);
  }

  @override
  Future<void> saveEvents(List<Event> events) async {
    final data = events.map((e) => e.toJson()).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  @override
  Future<void> deleteEvent(String id) async {
    final events = await loadEvents();
    events.removeWhere((e) => e.id == id);
    await saveEvents(events);
  }

  @override
  Future<void> publishEvent(Event event) async {
    // For local storage, publishing just means marking isPublished = true
    final updated = event.copyWith(isPublished: true, isDraft: false);
    await saveEvent(updated);
  }

  @override
  Future<Event?> getEventById(String id) async {
    final events = await loadEvents();
    try {
      return events.firstWhere((e) => e.id == id);
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<List<Event>>? eventsStream() => null;
}
