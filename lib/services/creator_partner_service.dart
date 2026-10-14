import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/creator_partner_utils.dart';

class CreatorPartnerData {
  final List<Map<String, dynamic>> sellers;
  final List<Map<String, dynamic>> codes;
  final List<Map<String, dynamic>> subscribers;
  final List<Map<String, dynamic>> events;
  final Map<String, dynamic> integration;
  const CreatorPartnerData({required this.sellers, required this.codes,
    required this.subscribers, required this.events, required this.integration});
}

abstract class CreatorPartnerRepository {
  Future<CreatorPartnerData> load(String? sellerId);
  Future<String> saveSeller(String? id, Map<String, dynamic> profile);
  String generateCode();
  Future<String> createCode(String sellerId, String raw, {String? replacesId});
  Future<void> deactivateCode(String sellerId, String codeId);
  Future<void> recordSettlement(Map<String, dynamic> event, String reference);
}

class CreatorPartnerService implements CreatorPartnerRepository {
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;
  CreatorPartnerService({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : firestore = firestore ?? FirebaseFirestore.instance,
        functions = functions ?? FirebaseFunctions.instance;

  List<Map<String, dynamic>> _rows(QuerySnapshot<Map<String, dynamic>> snapshot) =>
      snapshot.docs.map((doc) => <String, dynamic>{
        for (final entry in doc.data().entries)
          entry.key: entry.value is Timestamp
              ? (entry.value as Timestamp).toDate() : entry.value,
        'id': doc.id,
      }).toList();

  Future<CreatorPartnerData> load(String? sellerId) async {
    // Refresh must fetch server data, not mistake a stale cache for a new sync.
    const server = GetOptions(source: Source.server);
    final sellers = firestore.collection('sellers').get(server);
    final integration = firestore.collection('seller_integration_config').doc('revenuecat').get(server);
    final codes = sellerId == null ? null : firestore.collection('seller_codes')
        .where('sellerId', isEqualTo: sellerId).get(server);
    final users = sellerId == null ? null : firestore.collection('users')
        .where('assignedSellerId', isEqualTo: sellerId).get(server);
    final events = sellerId == null ? null : firestore.collection('seller_subscription_events')
        .where('sellerId', isEqualTo: sellerId).get(server);
    // The callable owns immutable receipts; no direct webhook payout writes.
    final settlements = sellerId == null ? null : firestore.collection('seller_partner_settlements')
        .where('sellerId', isEqualTo: sellerId).get(server);
    final statuses = sellerId == null ? null : firestore.collection('partner_subscription_status')
        .where('sellerId', isEqualTo: sellerId).get(server);
    final results = await Future.wait<Object?>([
      sellers, integration, codes ?? Future<Object?>.value(),
      users ?? Future<Object?>.value(), events ?? Future<Object?>.value(),
      settlements ?? Future<Object?>.value(), statuses ?? Future<Object?>.value(),
    ]);
    List<Map<String, dynamic>> rows(int index) => results[index] == null
        ? [] : _rows(results[index] as QuerySnapshot<Map<String, dynamic>>);
    final paymentEvents = partnerPaymentHistory(rows(4), rows(5));
    final subscribers = partnerSubscriberSnapshots(rows(3), rows(6), sellerId);
    return CreatorPartnerData(sellers: rows(0), codes: rows(2), subscribers: subscribers, events: paymentEvents,
      integration: (results[1] as DocumentSnapshot<Map<String, dynamic>>).data() ?? {});
  }

  Future<String> saveSeller(String? id, Map<String, dynamic> profile) async {
    final ref = id == null ? firestore.collection('sellers').doc() : firestore.collection('sellers').doc(id);
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (id != null && !existing.exists) throw StateError('Seller no longer exists.');
      transaction.set(ref, {
        ...profile, 'isActive': profile['status'] == 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
    // Merge preserves legacy commissions, currency and other stored fields.
    return ref.id;
  }

  String generateCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final code = List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)]).join();
    return '${code.substring(0, 4)}-${code.substring(4)}';
  }

  Future<String> createCode(String sellerId, String raw, {String? replacesId}) async {
    final code = normalizePartnerCode(raw.trim().isEmpty ? generateCode() : raw);
    if (!validPartnerCode(code)) throw ArgumentError('Use 3–64 letters, numbers, hyphens or underscores.');
    // Historic random-ID docs are checked too. New writers reserve the normalized
    // code as the document ID atomically. Inactive codes stay permanently reserved.
    final legacy = await firestore.collection('seller_codes')
        .where('normalizedCode', isEqualTo: code).limit(1)
        .get(const GetOptions(source: Source.server));
    if (legacy.docs.isNotEmpty) throw StateError('Code already exists, even if inactive.');
    final ref = firestore.collection('seller_codes').doc(code);
    final sellerRef = firestore.collection('sellers').doc(sellerId);
    final oldRef = replacesId == null ? null : firestore.collection('seller_codes').doc(replacesId);
    await firestore.runTransaction((transaction) async {
      final seller = await transaction.get(sellerRef);
      final reservation = await transaction.get(ref);
      final old = oldRef == null ? null : await transaction.get(oldRef);
      if (!seller.exists || partnerStatus(seller.data()!) != 'active') {
        throw StateError('Only an active seller can create a code.');
      }
      if (reservation.exists) throw StateError('Code already exists.');
      if (old != null && (!old.exists || old.data()?['sellerId'] != sellerId)) {
        throw StateError('Replacement must belong to the same seller.');
      }
      transaction.set(ref, {
        'sellerId': sellerId, 'code': code, 'normalizedCode': code,
        'isActive': true, 'status': 'active',
        'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp(),
        if (oldRef != null) 'replacesCodeId': oldRef.id,
      });
      if (oldRef != null) transaction.update(oldRef, {
        'isActive': false, 'status': 'inactive', 'replacementCodeId': ref.id,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
    return code;
  }

  Future<void> deactivateCode(String sellerId, String codeId) async {
    final ref = firestore.collection('seller_codes').doc(codeId);
    await firestore.runTransaction((transaction) async {
      final code = await transaction.get(ref);
      if (!code.exists || code.data()?['sellerId'] != sellerId) {
        throw StateError('Code does not belong to the selected seller.');
      }
      transaction.update(ref, {'isActive': false, 'status': 'inactive', 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  Future<void> recordSettlement(Map<String, dynamic> event, String reference) async {
    if (!canRecordPartnerSettlement(event) || reference.trim().isEmpty) {
      throw StateError('A confirmed production purchase/renewal and accounting reference are required.');
    }
    // No direct payout writes: the callable owns auth, reversal checks and idempotency.
    await functions.httpsCallable('recordSellerPartnerSettlement').call({
      'eventId': partnerText(event['eventId']), 'accountingReference': reference.trim(),
    });
  }
}