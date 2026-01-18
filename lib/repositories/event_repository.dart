import '../models/event.dart';

/// Abstract repository for Event persistence.
/// Allows switching between local storage and Firestore implementations.
abstract class EventRepository {
  /// Load all events from the repository.
  Future<List<Event>> loadEvents();

  /// Save a single event (create or update).
  Future<void> saveEvent(Event event);

  /// Save multiple events (batch operation).
  Future<void> saveEvents(List<Event> events);

  /// Delete an event by ID.
  Future<void> deleteEvent(String id);

  /// Stream of events (optional, for real-time updates from Firestore).
  Stream<List<Event>>? eventsStream() => null;

  /// Publish an event (mark as published and sync to backend if needed).
  Future<void> publishEvent(Event event);

  /// Load a single event by ID.
  Future<Event?> getEventById(String id);
}
