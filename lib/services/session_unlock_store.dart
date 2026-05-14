import 'package:firebase_auth/firebase_auth.dart';

/// Singleton that remembers which tabs have been unlocked during the current
/// browser/app session for the currently signed-in admin.
///
/// Super-admins are always considered unlocked for every key.
/// When the Firebase Auth user changes (sign-out / sign-in) the store resets.
class SessionUnlockStore {
  SessionUnlockStore._();
  static final SessionUnlockStore _instance = SessionUnlockStore._();
  static SessionUnlockStore get instance => _instance;

  final Set<String> _unlockedKeys = {};
  String? _sessionUserId; // tracks which UID the unlocked set belongs to

  /// Returns true if [key] has been unlocked in this session for the current user.
  bool isUnlocked(String key, {required bool isSuperAdmin}) {
    if (isSuperAdmin) return true;
    _checkUserChange();
    return _unlockedKeys.contains(key);
  }

  /// Record that [key] has been successfully unlocked for the current session.
  void markUnlocked(String key) {
    _checkUserChange();
    _unlockedKeys.add(key);
  }

  /// Clear all unlock state (called on sign-out or user change).
  void reset() {
    _unlockedKeys.clear();
    _sessionUserId = null;
  }

  void _checkUserChange() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != _sessionUserId) {
      // Different user (or signed out) — invalidate all previous unlocks.
      _unlockedKeys.clear();
      _sessionUserId = uid;
    }
  }
}
