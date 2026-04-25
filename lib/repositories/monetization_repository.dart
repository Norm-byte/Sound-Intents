import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/monetization_offer.dart';

class MonetizationDraftSet {
  final String id;
  final String name;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  MonetizationDraftSet({
    required this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
  });

  factory MonetizationDraftSet.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MonetizationDraftSet(
      id: doc.id,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? data['name'] as String
          : 'Untitled Draft',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class MonetizationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // LIVE collection (Readable by User App)
  final String _liveCollection = 'product_tiers';
  
  // DRAFT collection (Admin Workspace)
  final String _draftCollection = 'product_tiers_draft';

  // Named draft set metadata collection (Admin workspace presets)
  final String _draftSetsCollection = 'product_tier_draft_sets';

  /// Get DRAFT offers for editing
  Stream<List<MonetizationOffer>> getDraftOffersStream() {
    return _firestore.collection(_draftCollection).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => MonetizationOffer.fromFirestore(doc))
          .toList();
    });
  }

  /// Save changes to DRAFT
  Future<void> saveDraftOffer(MonetizationOffer offer) async {
    final docRef = _firestore.collection(_draftCollection).doc(offer.id);
    await docRef.set(offer.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteDraftOffer(String offerId) async {
    await _firestore.collection(_draftCollection).doc(offerId).delete();
  }

  Future<void> clearDraftOffers() async {
    final drafts = await _firestore.collection(_draftCollection).get();
    final batch = _firestore.batch();
    for (final doc in drafts.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  Stream<List<MonetizationDraftSet>> getDraftSetsStream() {
    return _firestore
        .collection(_draftSetsCollection)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MonetizationDraftSet.fromFirestore(doc))
          .toList();
    });
  }

  Future<String> createDraftSet({
    required String name,
    required bool fromCurrentDraft,
  }) async {
    final docRef = _firestore.collection(_draftSetsCollection).doc();
    final now = FieldValue.serverTimestamp();

    await docRef.set({
      'name': name,
      'createdAt': now,
      'updatedAt': now,
    });

    if (fromCurrentDraft) {
      await saveCurrentDraftToSet(docRef.id);
    }

    return docRef.id;
  }

  Future<void> renameDraftSet({
    required String setId,
    required String name,
  }) async {
    await _firestore.collection(_draftSetsCollection).doc(setId).set({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> deleteDraftSet(String setId) async {
    final offers = await _firestore
        .collection(_draftSetsCollection)
        .doc(setId)
        .collection('offers')
        .get();

    final batch = _firestore.batch();
    for (final doc in offers.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_firestore.collection(_draftSetsCollection).doc(setId));
    await batch.commit();
  }

  Future<void> saveCurrentDraftToSet(String setId) async {
    final currentDraft = await _firestore.collection(_draftCollection).get();
    final setOffersRef = _firestore
        .collection(_draftSetsCollection)
        .doc(setId)
        .collection('offers');

    final existingSetOffers = await setOffersRef.get();

    final batch = _firestore.batch();
    for (final doc in existingSetOffers.docs) {
      batch.delete(doc.reference);
    }

    for (final doc in currentDraft.docs) {
      batch.set(setOffersRef.doc(doc.id), doc.data());
    }

    batch.set(
      _firestore.collection(_draftSetsCollection).doc(setId),
      {'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<void> loadSetToCurrentDraft(String setId) async {
    final setOffers = await _firestore
        .collection(_draftSetsCollection)
        .doc(setId)
        .collection('offers')
        .get();

    final currentDraft = await _firestore.collection(_draftCollection).get();

    final batch = _firestore.batch();

    for (final doc in currentDraft.docs) {
      batch.delete(doc.reference);
    }

    for (final doc in setOffers.docs) {
      batch.set(_firestore.collection(_draftCollection).doc(doc.id), doc.data());
    }

    await batch.commit();
  }

  /// PUBLISH: Copy all Drafts to Live
  Future<void> publishToLive() async {
    final batch = _firestore.batch();
    
    // 1. Get all Drafts
    final drafts = await _firestore.collection(_draftCollection).get();
    
    // 2. Get all Live (to delete obsolete ones)
    final live = await _firestore.collection(_liveCollection).get();
    
    // Delete all live docs first (simplest sync strategy)
    // Or we could do a smart diff, but full replacement ensures 1:1 match
    for (var doc in live.docs) {
      batch.delete(doc.reference);
    }
    
    // Write drafts to live
    for (var doc in drafts.docs) {
      final liveRef = _firestore.collection(_liveCollection).doc(doc.id);
      batch.set(liveRef, doc.data());
    }
    
    await batch.commit();
  }

  /// SYNC: Copy Live to Draft (Discard Draft changes)
  Future<void> syncFromLive() async {
    final batch = _firestore.batch();
    
    // 1. Get Live
    final live = await _firestore.collection(_liveCollection).get();
    
    // 2. Delete all drafts
    final drafts = await _firestore.collection(_draftCollection).get();
    for (var doc in drafts.docs) {
      batch.delete(doc.reference);
    }
    
    // 3. Copy Live to Draft
    for (var doc in live.docs) {
      final draftRef = _firestore.collection(_draftCollection).doc(doc.id);
      batch.set(draftRef, doc.data());
    }
    
    await batch.commit();
  }
}
