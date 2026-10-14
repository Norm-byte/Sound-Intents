// Firestore's sealed interfaces are intentionally faked only in this test.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_admin/services/creator_partner_service.dart';

// Small read-only Firestore doubles keep these tests independent of Firebase
// initialization and verify seller scoping and server-only reads explicitly.
class _Firestore extends Fake implements FirebaseFirestore {
  final collections = <String, _Collection>{};
  final requested = <String>[];

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    requested.add(path);
    return collections.putIfAbsent(path, _Collection.new);
  }
}

class _Functions extends Fake implements FirebaseFunctions {}

class _Collection extends Fake implements CollectionReference<Map<String, dynamic>> {
  final rows = <Map<String, dynamic>>[];
  final filters = <String, Object?>{};
  final Map<String, dynamic> document = {};
  final sources = <Source?>[];
  Source? get source => sources.isEmpty ? null : sources.last;

  @override
  Query<Map<String, dynamic>> where(Object field, {
    Object? isEqualTo, Object? isNotEqualTo, Object? isLessThan,
    Object? isLessThanOrEqualTo, Object? isGreaterThan,
    Object? isGreaterThanOrEqualTo, Object? arrayContains,
    Iterable<Object?>? arrayContainsAny, Iterable<Object?>? whereIn,
    Iterable<Object?>? whereNotIn, bool? isNull,
  }) {
    filters[field.toString()] = isEqualTo;
    return this;
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    sources.add(options?.source);
    return _Snapshot(rows.map((row) => _Row(row)).toList());
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _Document(this);
}

class _Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  _Snapshot(this.docs);
}

class _Row extends Fake implements QueryDocumentSnapshot<Map<String, dynamic>> {
  final Map<String, dynamic> values;
  _Row(this.values);
  @override
  String get id => values['id'] as String;
  @override
  Map<String, dynamic> data() => values;
}

class _Document extends Fake implements DocumentReference<Map<String, dynamic>> {
  final _Collection owner;
  _Document(this.owner);
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    owner.sources.add(options?.source);
    return _Row({'id': 'revenuecat', ...owner.document});
  }
}

void main() {
  test('selected seller queries production status and preserves Timestamp event conversion', () async {
    final firestore = _Firestore();
    final service = CreatorPartnerService(firestore: firestore, functions: _Functions());
    final received = DateTime.utc(2026, 10, 14, 12);
    firestore.collections['users'] = _Collection()..rows.addAll([
      {'id': 'user-1', 'subscriptionPlan': 'Starter', 'status': 'active', 'willRenew': true},
      {'id': 'user-2', 'subscriptionPlan': 'Harmony100', 'status': 'active', 'willRenew': true},
    ]);
    firestore.collections['partner_subscription_status'] = _Collection()..rows.addAll([
      {'id': 'PRODUCTION_user-1', 'userId': 'user-1', 'sellerId': 'seller-1',
        'environment': 'PRODUCTION', 'plan': 'harmony100', 'active': false,
        'willRenew': null, 'expiresAt': received.millisecondsSinceEpoch,
        'lastEventAt': received.millisecondsSinceEpoch - 1000,
        'lastReceivedAt': received.millisecondsSinceEpoch},
      {'id': 'SANDBOX_user-2', 'userId': 'user-2', 'sellerId': 'seller-1',
        'environment': 'SANDBOX', 'plan': 'starter', 'active': false, 'willRenew': false},
    ]);
    firestore.collections['seller_subscription_events'] = _Collection()..rows.add({
      'id': 'event-1', 'product': 'harmony100_monthly', 'receivedAt': Timestamp.fromDate(received),
    });
    final data = await service.load('seller-1');
    expect(data.subscribers.first['subscriptionPlan'], 'harmony100');
    expect(data.subscribers.first['status'], 'expired');
    expect(data.subscribers.first['willRenew'], isNull);
    expect(data.subscribers.first['subscriptionLastSyncedAt'], received);
    expect(data.subscribers.last['subscriptionPlan'], 'Harmony100');
    expect(data.subscribers.last['status'], 'active');
    expect(data.events.single['plan'], 'harmony100');
    expect((data.events.single['receivedAt'] as DateTime).toUtc(), received);
    for (final path in ['seller_codes', 'seller_subscription_events',
      'seller_partner_settlements', 'partner_subscription_status']) {
      expect(firestore.collections[path]!.filters, {'sellerId': 'seller-1'});
    }
    expect(firestore.collections['users']!.filters, {'assignedSellerId': 'seller-1'});
    for (final collection in firestore.collections.values) {
      expect(collection.source, Source.server);
    }
  });

  test('no selected seller does not query status or subscriber collections', () async {
    final firestore = _Firestore();
    final service = CreatorPartnerService(firestore: firestore, functions: _Functions());
    final data = await service.load(null);
    expect(firestore.requested, ['sellers', 'seller_integration_config']);
    expect(data.subscribers, isEmpty);
    expect(data.events, isEmpty);
  });
}