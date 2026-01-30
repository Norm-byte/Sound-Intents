import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/monetization_offer.dart';

class MonetizationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // LIVE collection (Readable by User App)
  final String _liveCollection = 'product_tiers';
  
  // DRAFT collection (Admin Workspace)
  final String _draftCollection = 'product_tiers_draft';

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
    final docRef = _firestore.collection(_draftCollection).doc(offer.id.isEmpty ? null : offer.id);
    await docRef.set(offer.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteDraftOffer(String offerId) async {
    await _firestore.collection(_draftCollection).doc(offerId).delete();
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
