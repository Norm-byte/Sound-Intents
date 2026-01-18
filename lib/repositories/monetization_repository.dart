import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/monetization_offer.dart';

class MonetizationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _collection = 'product_tiers'; // As recommended earlier

  Stream<List<MonetizationOffer>> getOffersStream() {
    return _firestore.collection(_collection).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => MonetizationOffer.fromFirestore(doc))
          .toList();
    });
  }

  Future<void> saveOffer(MonetizationOffer offer) async {
    final docRef = _firestore.collection(_collection).doc(offer.id.isEmpty ? null : offer.id);
    // If id was empty, we need to update the object with the new ID if we were returning it,
    // but here we just write to the ref.
    await docRef.set(offer.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteOffer(String offerId) async {
    await _firestore.collection(_collection).doc(offerId).delete();
  }

  Future<void> setActiveOffer(String offerId, bool isActive) async {
    await _firestore.collection(_collection).doc(offerId).update({'isActive': isActive});
  }
}
