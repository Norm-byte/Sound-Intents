import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_admin/models/creator_partner_utils.dart';

void main() {
  Map<String, dynamic> purchase() => {
    'eventId': 'event-1', 'sellerId': 'seller-1', 'userId': 'user-1',
    'transactionId': 'tx-1', 'type': 'INITIAL_PURCHASE', 'environment': 'PRODUCTION',
    'store': 'APP_STORE', 'productId': 'harmony100_monthly',
    'purchasedAt': DateTime(2026, 10, 14),
  };

  test('normalization is trim plus uppercase and preserves meaningful separators', () {
    expect(normalizePartnerCode('  creator-ab_12  '), 'CREATOR-AB_12');
    expect(validPartnerCode('abc-123'), isTrue);
    for (final code in ['', 'ab', 'a/bc', 'a bc', '..', 'éabc', 'a' * 65]) {
      expect(validPartnerCode(code), isFalse, reason: code);
    }
  });

  test('legacy inactive maps to paused and archive overrides activity flag', () {
    expect(partnerStatus({'status': 'inactive', 'isActive': true}), 'paused');
    expect(partnerStatus({'status': 'archived', 'isActive': true}), 'archived');
    expect(partnerStatus({'status': 'active', 'isActive': false}), 'paused');
    expect(partnerStatus({'isActive': true}), 'active');
  });

  test('identity resolves existing username/userName and name fallback fields', () {
    expect(partnerUserName({'username': ' ', 'userName': 'Creator', 'name': 'Real name'}), 'Creator');
    expect(partnerUserName({'username': 'preferred', 'userName': 'other'}), 'preferred');
    expect(partnerUserName({'displayName': 'Display'}), 'Display');
    expect(partnerUserName({'fullName': 'Full'}), 'Full');
    expect(partnerUserName({'name': 'Name'}), 'Name');
    expect(partnerUserName({}), 'Unknown user');
  });

  test('date conversion accepts ISO and webhook milliseconds, rejects missing values', () {
    expect(partnerDate('2026-10-14T12:00:00Z'), DateTime.utc(2026, 10, 14, 12));
    expect(partnerDate(0), DateTime.fromMillisecondsSinceEpoch(0, isUtc: true));
    expect(partnerDate('invalid'), isNull);
    expect(partnerDate(double.nan), isNull);
  });

  test('date range includes entire final day and excludes missing dates when filtered', () {
    final start = DateTime(2026, 10, 1);
    final end = DateTime(2026, 10, 14);
    expect(partnerDateInRange(DateTime(2026, 10, 14, 23, 59, 59), start, end), isTrue);
    expect(partnerDateInRange(DateTime(2026, 10, 15), start, end), isFalse);
    expect(partnerDateInRange(DateTime(2026, 9, 30, 23), start, end), isFalse);
    expect(partnerDateInRange(null, start, end), isFalse);
    expect(partnerDateInRange(null, null, null), isTrue);
  });

  test('subscriber filters combine plan status renew search and dates', () {
    final user = {'userName': 'CreatorFan', 'id': 'user-123', 'accountReference': 'AC-42',
      'subscriptionPlan': 'Harmony100', 'status': 'active', 'willRenew': true};
    expect(partnerSubscriberMatches(user, search: ' ac-42 ', plan: 'Harmony100', status: 'active',
      autoRenew: 'yes', date: DateTime(2026, 10, 14), start: DateTime(2026, 10, 1)), isTrue);
    expect(partnerSubscriberMatches(user, search: 'CREATORFAN'), isTrue);
    expect(partnerSubscriberMatches(user, search: 'user-123'), isTrue);
    expect(partnerSubscriberMatches(user, plan: 'Starter'), isFalse);
    expect(partnerSubscriberMatches(user, status: 'expired'), isFalse);
    expect(partnerSubscriberMatches(user, autoRenew: 'no'), isFalse);
    expect(partnerSubscriberMatches(user, autoRenew: 'unknown'), isFalse);
    expect(partnerSubscriberMatches({...user, 'willRenew': null}, autoRenew: 'unknown'), isTrue);
    expect(partnerSubscriberMatches({...user, 'willRenew': false}, autoRenew: 'no'), isTrue);
  });

  test('production is explicit; sandbox/test and unknown cannot settle', () {
    expect(partnerEnvironment({'environment': 'production'}), 'production');
    expect(partnerEnvironment({'environment': 'SANDBOX'}), 'test');
    expect(partnerEnvironment({'environment': 'TEST'}), 'test');
    expect(partnerEnvironment({}), 'unknown');
    for (final environment in ['SANDBOX', 'TEST', '', 'UNKNOWN']) {
      expect(canRecordPartnerSettlement({...purchase(), 'environment': environment}), isFalse);
    }
  });

  test('production status overrides app snapshot without mutating inputs', () {
    final user = <String, dynamic>{
      'id': 'user-1', 'assignedSellerId': 'seller-1', 'username': 'Fan',
      'subscriptionPlan': 'Starter', 'status': 'trial', 'willRenew': true,
      'expiresAt': DateTime(2026), 'renewalDate': DateTime(2026),
      'subscriptionLastSyncedAt': DateTime(2026),
    };
    final status = <String, dynamic>{
      'userId': 'user-1', 'sellerId': 'seller-1', 'environment': 'PRODUCTION',
      'plan': 'harmony100_monthly', 'active': false, 'willRenew': null,
      'expiresAt': DateTime.utc(2026, 11, 14).millisecondsSinceEpoch,
      'lastEventAt': DateTime.utc(2026, 10, 14).millisecondsSinceEpoch,
      'lastReceivedAt': DateTime.utc(2026, 10, 14, 12).millisecondsSinceEpoch,
    };
    final decorated = partnerSubscriberSnapshots([user], [status], 'seller-1').single;
    expect(decorated['subscriptionPlan'], 'harmony100');
    expect(decorated['status'], 'expired');
    expect(decorated['willRenew'], isNull);
    expect(decorated['renewalDate'], DateTime.utc(2026, 11, 14));
    expect(decorated['expiresAt'], DateTime.utc(2026, 11, 14));
    expect(decorated['subscriptionLastSyncedAt'], DateTime.utc(2026, 10, 14, 12));
    expect(decorated['subscriptionSyncSource'], 'webhook');
    expect(decorated['username'], 'Fan');
    expect(decorated['assignedSellerId'], 'seller-1');
    expect(partnerSubscriberMatches(decorated, plan: 'harmony100', status: 'expired',
      autoRenew: 'unknown'), isTrue);
    expect(user['subscriptionPlan'], 'Starter');
    expect(user['status'], 'trial');
    expect(status['expiresAt'], isA<int>());
  });

  test('sandbox, unknown environment and mismatched identities retain all app values', () {
    final user = <String, dynamic>{'id': 'user-1', 'subscriptionPlan': 'Starter',
      'status': 'active', 'willRenew': true, 'renewalDate': DateTime(2026, 11, 14),
      'lastSyncAt': DateTime(2026, 10, 14)};
    final status = <String, dynamic>{'userId': 'user-1', 'sellerId': 'seller-1',
      'environment': 'PRODUCTION', 'plan': 'harmony100', 'active': false};
    for (final override in [
      {'environment': 'SANDBOX'}, {'environment': 'TEST'}, {'environment': ''},
      {'sellerId': 'seller-2'}, {'userId': 'user-2'}, {'userId': ''},
    ]) {
      expect(partnerSubscriberSnapshots([user], [{...status, ...override}], 'seller-1').single,
        user, reason: '$override');
    }
    expect(partnerSubscriberSnapshots([user], [], 'seller-1').single, user);
    expect(partnerSubscriberSnapshots([user], [status], null).single, user);
    expect(partnerSubscriberSnapshots([], [status], 'seller-1'), isEmpty);
  });

  test('latest production event wins even over newer sandbox or late old receipts', () {
    final status = <String, dynamic>{'userId': 'user-1', 'sellerId': 'seller-1',
      'environment': 'PRODUCTION', 'plan': 'starter', 'active': true,
      'willRenew': false, 'lastEventAt': 2000, 'lastReceivedAt': 3000};
    final stale = {...status, 'active': false, 'lastEventAt': 1000, 'lastReceivedAt': 6000};
    final sandbox = {...status, 'environment': 'SANDBOX', 'active': false,
      'lastEventAt': 9000, 'lastReceivedAt': 9000};
    for (final statuses in [[stale, status, sandbox], [sandbox, status, stale]]) {
      final result = partnerSubscriberSnapshots([{'id': 'user-1'}], statuses, 'seller-1').single;
      expect(result['status'], 'active');
      expect(result['willRenew'], isFalse);
      expect(result['subscriptionPlan'], 'starter');
      expect(result['subscriptionLastSyncedAt'], partnerDate(3000));
    }
    final tied = {...status, 'willRenew': true, 'lastReceivedAt': 4000};
    expect(partnerSubscriberSnapshots([{'id': 'user-1'}], [tied, status], 'seller-1')
      .single['willRenew'], isTrue);
  });

  test('webhook null expiry clears old dates and event time is a sync fallback', () {
    final user = <String, dynamic>{'id': 'user-1', 'expiresAt': DateTime(2026),
      'subscriptionExpiresAt': DateTime(2026), 'renewalDate': DateTime(2026)};
    final status = <String, dynamic>{'userId': 'user-1', 'sellerId': 'seller-1',
      'environment': 'PRODUCTION', 'plan': 'future_product', 'active': true,
      'willRenew': true, 'expiresAt': null, 'lastEventAt': 2000};
    final result = partnerSubscriberSnapshots([user], [status], 'seller-1').single;
    expect(result['subscriptionPlan'], 'future_product');
    expect(result['expiresAt'], isNull);
    expect(result['subscriptionExpiresAt'], isNull);
    expect(result['renewalDate'], isNull);
    expect(result['subscriptionLastSyncedAt'], partnerDate(2000));
  });

  test('event plans normalize product-only records and preserve unknown products', () {
    for (final entry in {
      'starter_monthly:starter-monthly': 'starter',
      'Harmony100_monthly': 'harmony100',
      'new_product': 'new_product',
    }.entries) {
      final event = <String, dynamic>{'product': entry.key, 'receivedAt': 2000};
      final result = partnerPaymentHistory([event], []).single;
      expect(result['productId'], entry.key);
      expect(result['plan'], entry.value);
      expect(result['receivedAt'], 2000);
      expect(event.containsKey('plan'), isFalse);
      expect(partnerPaymentHistory([{...event, 'plan': ' '}], []).single['plan'], entry.value);
    }
    expect(partnerPaymentHistory([{'product': 'starter_monthly', 'plan': 'harmony100'}], [])
      .single['plan'], 'harmony100');
    expect(partnerPaymentHistory([{'productId': 'starter_monthly'}], []).single['plan'], 'starter');
  });

  test('only production initial purchase and renewal may settle', () {
    expect(canRecordPartnerSettlement(purchase()), isTrue);
    expect(canRecordPartnerSettlement({...purchase(), 'type': 'RENEWAL'}), isTrue);
    for (final type in ['CANCELLATION', 'EXPIRATION', 'REFUND', 'REVERSAL',
      'BILLING_ISSUE', 'TRANSFER', 'PRODUCT_CHANGE', 'UNCANCELLATION', 'TEST']) {
      expect(canRecordPartnerSettlement({...purchase(), 'type': type}), isFalse, reason: type);
    }
  });

  test('snapshot data and incomplete event evidence never settle', () {
    expect(canRecordPartnerSettlement({'status': 'active', 'willRenew': true}), isFalse);
    for (final field in ['eventId', 'sellerId', 'userId', 'transactionId', 'purchasedAt']) {
      expect(canRecordPartnerSettlement({...purchase()}..remove(field)), isFalse, reason: field);
    }
    expect(canRecordPartnerSettlement({...purchase(), 'purchasedAt': 'invalid'}), isFalse);
  });

  test('already settled and reversed purchases are disabled', () {
    for (final field in ['payoutRecorded', 'isReversal', 'isReversed', 'reversed', 'refunded']) {
      expect(canRecordPartnerSettlement({...purchase(), field: true}), isFalse, reason: field);
    }
    for (final field in ['paidAt', 'reversedAt', 'refundedAt']) {
      expect(canRecordPartnerSettlement({...purchase(), field: DateTime(2026)}), isFalse, reason: field);
    }
  });

  test('linked production reversal blocks purchase but cancellation and test refund do not', () {
    final reversal = {...purchase(), 'eventId': 'refund-1', 'type': 'REFUND'};
    expect(partnerSettlementEligible(purchase(), [purchase(), reversal]), isFalse);
    expect(partnerSettlementEligible(purchase(), [{...reversal,
      'transactionId': 'refund-tx', 'reversedTransactionId': 'tx-1'}]), isFalse);
    expect(partnerSettlementEligible(purchase(), [{...reversal, 'type': 'CANCELLATION'}]), isTrue);
    expect(partnerSettlementEligible(purchase(), [{...reversal, 'environment': 'SANDBOX'}]), isTrue);
    expect(partnerSettlementEligible(purchase(), [{...reversal, 'transactionId': 'other',
      'originalTransactionId': 'other-lineage'}]), isTrue);
  });

  test('trial, transfer, support cancellation and refund lineage require review', () {
    expect(canRecordPartnerSettlement({...purchase(), 'periodType': 'TRIAL'}), isFalse);
    expect(canRecordPartnerSettlement({...purchase(), 'reviewReason': 'review'}), isFalse);
    final event = {...purchase(), 'originalTransactionId': 'original'};
    expect(partnerSettlementEligible(event, [{...event, 'type': 'REFUND', 'transactionId': 'later'}]), isFalse);
    expect(partnerSettlementEligible(event, [{...event, 'type': 'CANCELLATION', 'cancelReason': 'CUSTOMER_SUPPORT'}]), isFalse);
    expect(partnerSettlementEligible(event, [{...event, 'type': 'TRANSFER', 'affectedUserIds': ['user-1']}]), isFalse);
  });

  test('settlement receipts overlay same transaction only and preserve raw event data', () {
    final event = {...purchase(), 'productId': null, 'product': 'backend-product'};
    final receipt = {...event, 'recordedAt': DateTime(2026, 10, 15), 'accountingReference': 'AC-1'};
    final history = partnerPaymentHistory([event], [receipt]);
    expect(history.single['productId'], 'backend-product');
    expect(history.single['payoutRecorded'], isTrue);
    expect(history.single['paidAt'], DateTime(2026, 10, 15));
    expect(history.single['accountingReference'], 'AC-1');
    expect(event.containsKey('payoutRecorded'), isFalse);
    for (final override in [
      {'environment': 'SANDBOX'}, {'transactionId': 'other'}, {'sellerId': 'other'},
      {'userId': 'other'}, {'store': 'PLAY_STORE'},
    ]) {
      expect(partnerPaymentHistory([event], [{...receipt, ...override}]).single['payoutRecorded'], isNull);
    }
  });
}