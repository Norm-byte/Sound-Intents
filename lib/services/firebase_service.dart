import 'dart:developer' as developer;
import '../models/event.dart';

/// Lightweight Firebase service stub.
///
/// This file attempts to call Firestore methods only if Firebase is configured.
/// Right now it throws when the Firestore client isn't available. After you add
/// Firebase web config (or run `flutterfire configure`) this can be expanded to
/// perform real writes/reads.
class FirebaseService {
  FirebaseService();

  Future<void> publishEvent(Event e) async {
    // TODO: Implement with cloud_firestore once Firebase is configured.
    developer.log('publishEvent called for ${e.id} — this is a stub until Firebase is configured.');
    throw UnsupportedError('Firebase not configured. Paste Firebase web config and enable Firestore integration.');
  }

  // Add further methods: listEvents, subscribeToEvents, uploadMedia, etc.
}
