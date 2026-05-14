import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class LockService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Timer? _presenceTimer;
  Timer? _lockCleanupTimer;

  // Singleton pattern
  static final LockService _instance = LockService._internal();
  factory LockService() => _instance;
  LockService._internal();

  User? get _user => _auth.currentUser;

  /// Start broadcasting presence and cleaning up stale locks
  void startService() {
    _startPresenceHeartbeat();
    // Only run cleanup if we are confident we are the "main" tab or just run it inefficiently from all
    // Ideally, Firestore TTL policies handle this, but for now, client-side cleanup on load is okay.
  }

  void stopService() {
    _presenceTimer?.cancel();
    _lockCleanupTimer?.cancel();
    _setUserOffline();
  }

  // --- PRESENCE ---

  void _startPresenceHeartbeat() {
    _presenceTimer?.cancel();
    // Pulse every 60 seconds
    _presenceTimer = Timer.periodic(const Duration(seconds: 60), (_) => _updatePresence());
    _updatePresence(); // Initial pulse
  }

  Future<void> _updatePresence() async {
    if (_user == null) return;

    try {
      await _firestore.collection('admin_presence').doc(_user!.uid).set({
        'uid': _user!.uid,
        'email': _user!.email,
        'displayName': _user!.displayName ?? _user!.email?.split('@')[0] ?? 'Admin',
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
        'platform': kIsWeb ? 'web' : 'desktop',
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  Future<void> _setUserOffline() async {
    if (_user == null) return;
    try {
      await _firestore.collection('admin_presence').doc(_user!.uid).update({
        'isOnline': false,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Ignore errors on shutdown
    }
  }

  Stream<List<AdminPresence>> getActiveOperators() {
    // Consider "active" as seen in the last 5 minutes
    final cutoff = DateTime.now().subtract(const Duration(minutes: 5));
    
    return _firestore.collection('admin_presence')
        .where('lastSeen', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('lastSeen', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => AdminPresence.fromFirestore(doc.data()))
            .toList());
  }

  // --- LOCKING ---

  /// Tries to acquire a lock on a specific resource (e.g., 'user_123')
  /// Returns null if successful, or the name of the admin who holds the lock.
  Future<String?> acquireLock(String resourceId, String resourceType) async {
    if (_user == null) return 'Not authenticated';

    final lockRef = _firestore.collection('admin_locks').doc('${resourceType}_$resourceId');

    return _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(lockRef);

      if (doc.exists) {
        final data = doc.data()!;
        final lockedByUid = data['lockedByUid'];
        final lockedAt = (data['lockedAt'] as Timestamp).toDate();
        
        // Check if lock is stale (e.g., older than 10 minutes)
        if (DateTime.now().difference(lockedAt).inMinutes > 10) {
          // Steal the lock
        } else if (lockedByUid != _user!.uid) {
          // Lock held by someone else
          return data['lockedByName'] ?? 'Unknown Admin';
        }
      }

      // Create or Update Lock
      transaction.set(lockRef, {
        'resourceId': resourceId,
        'resourceType': resourceType,
        'lockedByUid': _user!.uid,
        'lockedByName': _user!.email?.split('@')[0] ?? 'Admin',
        'lockedAt': FieldValue.serverTimestamp(),
      });

      return null; // Success
    });
  }

  /// Releases a lock on a resource
  Future<void> releaseLock(String resourceId, String resourceType) async {
    if (_user == null) return;
    final lockRef = _firestore.collection('admin_locks').doc('${resourceType}_$resourceId');

    await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(lockRef);
      if (!doc.exists) return;

      final data = doc.data() ?? <String, dynamic>{};
      final lockedByUid = data['lockedByUid'] as String?;
      final lockedAt = (data['lockedAt'] as Timestamp?)?.toDate();
      final isStale =
          lockedAt != null && DateTime.now().difference(lockedAt).inMinutes > 10;

      // Only the lock owner can release a live lock.
      // Any admin may clear a stale lock.
      if (lockedByUid == _user!.uid || isStale) {
        transaction.delete(lockRef);
      }
    });
  }

  /// Check lock status without trying to acquire
  Stream<String?> watchLock(String resourceId, String resourceType) {
    return _firestore.collection('admin_locks').doc('${resourceType}_$resourceId')
        .snapshots()
        .map((doc) {
          if (!doc.exists) return null;
          final data = doc.data()!;
          // Check for stale
          final lockedAt = (data['lockedAt'] as Timestamp?)?.toDate() ?? DateTime.now();
          if (DateTime.now().difference(lockedAt).inMinutes > 10) return null;
          
          return data['lockedByName'] as String?;
        });
  }
}

class AdminPresence {
  final String uid;
  final String email;
  final String displayName;
  final DateTime lastSeen;
  final bool isOnline;

  AdminPresence({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.lastSeen,
    required this.isOnline,
  });

  factory AdminPresence.fromFirestore(Map<String, dynamic> data) {
    return AdminPresence(
      uid: data['uid'] ?? '',
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? 'Admin',
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: data['isOnline'] ?? false,
    );
  }
}
