import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/event.dart';
import 'event_repository.dart';

/// Firestore implementation of EventRepository.
/// Reads and writes events to the Firestore 'events' collection.
class FirestoreEventRepository implements EventRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'events';

  @override
  Future<List<Event>> loadEvents() async {
    try {
      final snapshot = await _firestore
          .collection(_collection)
          .orderBy('startTimeUTC', descending: true)
          .get();
      return snapshot.docs
          .map((doc) => Event.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<void> saveEvent(Event event) async {
    await _firestore.collection(_collection).doc(event.id).set(event.toJson());
  }

  @override
  Future<void> saveEvents(List<Event> events) async {
    final batch = _firestore.batch();
    for (final event in events) {
      final docRef = _firestore.collection(_collection).doc(event.id);
      batch.set(docRef, event.toJson());
    }
    await batch.commit();
  }

  @override
  Future<void> deleteEvent(String id) async {
    await _firestore.collection(_collection).doc(id).delete();
  }

  @override
  Future<void> publishEvent(Event event) async {
    final updated = event.copyWith(isPublished: true, isDraft: false);
    await saveEvent(updated);
  }

  @override
  Future<Event?> getEventById(String id) async {
    try {
      final doc = await _firestore.collection(_collection).doc(id).get();
      if (!doc.exists) return null;
      return Event.fromJson({...doc.data()!, 'id': doc.id});
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<List<Event>>? eventsStream() {
    return _firestore
        .collection(_collection)
        .orderBy('startTimeUTC', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Event.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }

  Stream<List<Event>>? globalEventsStream() {
    return _firestore
        .collection('global_events')
        .orderBy('id')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Event.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }

  // --- Global Events (Event Creator Tab) ---

  Future<List<Event>> loadGlobalEvents() async {
    try {
      final snapshot = await _firestore
          .collection('global_events')
          .orderBy('id')
          .get();
      return snapshot.docs
          .map((doc) => Event.fromJson({...doc.data(), 'id': doc.id}))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveGlobalEvents(List<Event> events) async {
    final batch = _firestore.batch();
    for (final event in events) {
      final docRef = _firestore.collection('global_events').doc(event.id);
      batch.set(docRef, event.toJson());
    }
    await batch.commit();
  }

  Future<void> saveGlobalEvent(Event event) async {
    await _firestore.collection('global_events').doc(event.id).set(event.toJson());
  }

  Future<void> deleteGlobalEvent(String id) async {
    await _firestore.collection('global_events').doc(id).delete();
  }
}
