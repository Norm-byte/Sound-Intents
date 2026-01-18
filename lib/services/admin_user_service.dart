import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/admin_user.dart';

class AdminUserService {
  AdminUserService();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _adminsCol => _db.collection('admin_users');
  CollectionReference<Map<String, dynamic>> get _requestsCol => _db.collection('admin_access_requests');

  Future<bool> hasAnyAdmins() async {
    final snap = await _adminsCol.limit(1).get();
    return snap.docs.isNotEmpty;
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> currentAdminDocStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      // Return a stream that completes immediately with a non-existing snapshot
      return _adminsCol.doc('_none_').snapshots();
    }
    return _adminsCol.doc(uid).snapshots();
  }

  Future<AdminUser?> getCurrentAdminUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _adminsCol.doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return AdminUser.fromJson(data);
  }

  Future<void> createSuperAdminForCurrentUser({required String displayName}) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user');
    }
    final admin = AdminUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: displayName.isEmpty ? (user.email ?? 'Super Admin') : displayName,
      role: 'super-admin',
      isActive: true,
      createdAt: DateTime.now(),
      lastLogin: DateTime.now(),
    );
    await _adminsCol.doc(user.uid).set(admin.toJson());
  }

  Future<void> updateAdmin(AdminUser admin) async {
    await _adminsCol.doc(admin.uid).set(admin.toJson(), SetOptions(merge: true));
  }

  Stream<List<AdminUser>> streamAdmins() {
    return _adminsCol.snapshots().map((qs) => qs.docs
        .map((d) => AdminUser.fromJson(d.data()))
        .toList());
  }

  Future<void> updateLastLoginNow() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _adminsCol.doc(uid).set({'lastLogin': DateTime.now().toIso8601String()}, SetOptions(merge: true));
  }

  // Access Request management
  Future<bool> hasPendingRequestForCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    final doc = await _requestsCol.doc(uid).get();
    return doc.exists;
  }

  Future<void> requestAccess() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No authenticated user');
    await _requestsCol.doc(user.uid).set({
      'uid': user.uid,
      'email': user.email,
      'requestedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
  }

  Stream<List<Map<String, dynamic>>> streamAccessRequests() {
    return _requestsCol.orderBy('requestedAt', descending: true).snapshots().map(
          (qs) => qs.docs.map((d) => {'id': d.id, ...d.data()}).toList(),
        );
  }

  Stream<QuerySnapshot> getAccessRequestsStream() {
    return _requestsCol
        .where('status', isEqualTo: 'pending')
        // .orderBy('requestedAt', descending: true) // Removed to avoid index requirement
        .snapshots();
  }

  Future<void> approveRequest({required String requestId, required String uid, required String email}) async {
    // When approving, create a basic admin record (inactive=false/true?)
    final admin = AdminUser(
      uid: uid,
      email: email,
      displayName: email,
      role: 'admin',
      isActive: true,
      createdAt: DateTime.now(),
      lastLogin: null,
    );
    await _adminsCol.doc(uid).set(admin.toJson());
    await _requestsCol.doc(requestId).update({'status': 'approved'});
  }

  Future<void> approveAccessRequest(String requestId, String role) async {
    // Get the request document
    final requestDoc = await _requestsCol.doc(requestId).get();
    if (!requestDoc.exists) throw Exception('Request not found');
    
    final data = requestDoc.data()!;
    final uid = data['uid'] as String;
    final email = data['email'] as String;
    final displayName = data['displayName'] as String? ?? email;
    
    // Create admin record
    final admin = AdminUser(
      uid: uid,
      email: email,
      displayName: displayName,
      role: role,
      isActive: true,
      createdAt: DateTime.now(),
      lastLogin: null,
    );
    await _adminsCol.doc(uid).set(admin.toJson());
    
    // Mark request as approved
    await _requestsCol.doc(requestId).update({'status': 'approved', 'approvedAt': FieldValue.serverTimestamp()});
  }

  Future<void> rejectRequest(String requestId) async {
    await _requestsCol.doc(requestId).update({'status': 'rejected'});
  }

  Future<void> rejectAccessRequest(String requestId) async {
    await _requestsCol.doc(requestId).update({
      'status': 'rejected',
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> redeemVipCode(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('No authenticated user');

    // 1. Check if code exists and is valid
    final codeQuery = await _db.collection('vip_codes')
        .where('code', isEqualTo: code)
        .where('isRedeemed', isEqualTo: false)
        .limit(1)
        .get();

    if (codeQuery.docs.isEmpty) {
      throw Exception('Invalid or already redeemed code.');
    }

    final codeDoc = codeQuery.docs.first;
    final codeData = codeDoc.data();
    
    // Check expiration
    if (codeData['expiresAt'] != null) {
      final expiresAt = DateTime.parse(codeData['expiresAt']);
      if (DateTime.now().isAfter(expiresAt)) {
        throw Exception('Code has expired.');
      }
    }

    // 2. Create AdminUser
    final role = codeData['role'] ?? 'admin'; // Default to admin if not specified
    final permissions = List<String>.from(codeData['permissions'] ?? []);

    final admin = AdminUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName ?? user.email ?? 'Admin User',
      role: role,
      isActive: true,
      createdAt: DateTime.now(),
      lastLogin: DateTime.now(),
      permissions: permissions,
    );

    // 3. Transaction to ensure atomicity
    await _db.runTransaction((transaction) async {
      // Mark code as redeemed
      transaction.update(codeDoc.reference, {
        'isRedeemed': true,
        'redeemedBy': user.uid,
        'redeemedAt': FieldValue.serverTimestamp(),
      });

      // Create admin user
      transaction.set(_adminsCol.doc(user.uid), admin.toJson());
    });
  }
}
