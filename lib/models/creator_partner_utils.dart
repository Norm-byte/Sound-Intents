/// Pure policy helpers for the admin creator-partner workspace.
String partnerText(Object? value) => value?.toString().trim() ?? '';

String normalizePartnerCode(String value) => value.trim().toUpperCase();

bool validPartnerCode(String value) =>
    RegExp(r'^[A-Z0-9][A-Z0-9_-]{2,63}$').hasMatch(normalizePartnerCode(value));

String partnerStatus(Map<String, dynamic> data) {
  final status = partnerText(data['status']).toLowerCase();
  if (status == 'archived') return 'archived';
  if (status == 'paused' || status == 'inactive' || data['isActive'] == false) {
    return 'paused';
  }
  return 'active';
}

String partnerUserName(Map<String, dynamic> data) {
  for (final key in ['username', 'userName', 'displayName', 'fullName', 'name']) {
    final value = partnerText(data[key]);
    if (value.isNotEmpty) return value;
  }
  return 'Unknown user';
}

DateTime? partnerDate(Object? value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num && value.isFinite) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return null;
}

bool partnerDateInRange(DateTime? value, DateTime? start, DateTime? end) {
  if (start == null && end == null) return true;
  if (value == null) return false;
  final local = value.toLocal();
  final first = start == null ? null : DateTime(start.year, start.month, start.day);
  final afterLast = end == null ? null : DateTime(end.year, end.month, end.day + 1);
  return (first == null || !local.isBefore(first)) &&
      (afterLast == null || local.isBefore(afterLast));
}

String partnerEnvironment(Map<String, dynamic> event) {
  final environment = partnerText(event['environment']).toUpperCase();
  if (environment == 'PRODUCTION') return 'production';
  if (environment == 'SANDBOX' || environment == 'TEST') return 'test';
  return 'unknown';
}

/// Match the webhook's plan aliases while preserving unrecognized products.
String normalizePartnerPlan(Object? value) {
  final raw = partnerText(value);
  final lower = raw.toLowerCase();
  if (lower.contains('starter')) return 'starter';
  if (lower.contains('harmony100')) return 'harmony100';
  return raw;
}

/// Overlay only this seller's production status onto attributed user rows.
/// Event time orders status updates; receipt time breaks ties, never sandbox.
List<Map<String, dynamic>> partnerSubscriberSnapshots(
  List<Map<String, dynamic>> users,
  List<Map<String, dynamic>> statuses,
  String? sellerId,
) {
  final production = <String, Map<String, dynamic>>{};
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  for (final status in statuses) {
    final userId = partnerText(status['userId']);
    if (sellerId == null || partnerText(status['sellerId']) != sellerId ||
        userId.isEmpty || partnerEnvironment(status) != 'production') continue;
    final previous = production[userId];
    if (previous != null) {
      final order = (partnerDate(status['lastEventAt']) ?? epoch)
          .compareTo(partnerDate(previous['lastEventAt']) ?? epoch);
      if (order < 0 || (order == 0 &&
          (partnerDate(status['lastReceivedAt']) ?? epoch)
              .isBefore(partnerDate(previous['lastReceivedAt']) ?? epoch))) continue;
    }
    production[userId] = status;
  }
  return users.map((user) {
    final status = production[partnerText(user['id'])];
    if (status == null) return <String, dynamic>{...user};
    final expiry = partnerDate(status['expiresAt']);
    return <String, dynamic>{
      ...user,
      'subscriptionPlan': normalizePartnerPlan(status['plan']),
      'status': status['active'] == true ? 'active' : 'expired',
      'willRenew': status['willRenew'],
      'expiresAt': expiry,
      'subscriptionExpiresAt': expiry,
      'renewalDate': expiry,
      'subscriptionLastSyncedAt': partnerDate(status['lastReceivedAt']) ??
          partnerDate(status['lastEventAt']),
      'subscriptionSyncSource': 'webhook',
    };
  }).toList();
}

/// Only webhook evidence can enter settlement; the callable must independently
/// revalidate authorization, transaction identity, reversals and idempotency.
bool canRecordPartnerSettlement(Map<String, dynamic> event) {
  final type = partnerText(event['type']).toUpperCase();
  return partnerEnvironment(event) == 'production' &&
      (type == 'INITIAL_PURCHASE' || type == 'RENEWAL') &&
      partnerText(event['eventId']).isNotEmpty &&
      partnerText(event['sellerId']).isNotEmpty &&
      partnerText(event['userId']).isNotEmpty &&
      partnerText(event['transactionId']).isNotEmpty &&
      partnerText(event['store']).isNotEmpty &&
      partnerText(event['productId'] ?? event['product']).isNotEmpty &&
      partnerText(event['periodType']).toUpperCase() != 'TRIAL' &&
      partnerText(event['reviewReason']).isEmpty &&
      partnerDate(event['purchasedAt']) != null &&
      event['payoutRecorded'] != true && event['paidAt'] == null &&
      event['isReversal'] != true && event['isReversed'] != true &&
      event['reversed'] != true && event['refunded'] != true &&
      event['reversedAt'] == null && event['refundedAt'] == null;
}

bool partnerSettlementEligible(Map<String, dynamic> event, List<Map<String, dynamic>> history) {
  if (!canRecordPartnerSettlement(event)) return false;
    const reversalTypes = {'REFUND', 'REFUND_REVERSED', 'REVOKE', 'REVOCATION', 'CHARGEBACK', 'PURCHASE_REFUNDED', 'REVERSAL'};
  final transaction = partnerText(event['transactionId']);
    final original = partnerText(event['originalTransactionId']);
  return !history.any((other) =>
      partnerEnvironment(other) == 'production' &&
      partnerText(other['sellerId']) == partnerText(event['sellerId']) &&
      ((partnerText(other['type']).toUpperCase() == 'TRANSFER' &&
        (other['affectedUserIds'] is List &&
          (other['affectedUserIds'] as List).contains(event['userId']))) ||
      ((reversalTypes.contains(partnerText(other['type']).toUpperCase()) ||
        (partnerText(other['type']).toUpperCase() == 'CANCELLATION' &&
          partnerText(other['cancelReason']).toUpperCase() == 'CUSTOMER_SUPPORT')) &&
      (partnerText(other['transactionId']) == transaction ||
        partnerText(other['reversedTransactionId']) == transaction ||
        (original.isNotEmpty && partnerText(other['originalTransactionId']) == original) ||
        (partnerText(other['originalTransactionId']).isEmpty &&
          partnerText(other['userId']) == partnerText(event['userId']))))));
}

bool partnerSubscriberMatches(
  Map<String, dynamic> user, {
  String search = '', String plan = 'all', String status = 'all',
  String autoRenew = 'all', DateTime? date, DateTime? start, DateTime? end,
}) {
  final haystack = [partnerUserName(user), user['id'], user['accountReference'], user['email']]
      .map(partnerText).join(' ').toLowerCase();
  return haystack.contains(search.trim().toLowerCase()) &&
      (plan == 'all' || partnerText(user['subscriptionPlan']) == plan) &&
      (status == 'all' || partnerText(user['status']) == status) &&
      (autoRenew == 'all' ||
          (autoRenew == 'yes' && user['willRenew'] == true) ||
          (autoRenew == 'no' && user['willRenew'] == false) ||
          (autoRenew == 'unknown' && user['willRenew'] is! bool)) &&
      partnerDateInRange(date, start, end);
}

/// Decorate webhook history with immutable callable settlement evidence;
/// support the backend product alias without changing raw stored data.
List<Map<String, dynamic>> partnerPaymentHistory(
  List<Map<String, dynamic>> events, List<Map<String, dynamic>> settlements,
) => events.map((event) {
  Map<String, dynamic>? receipt;
  for (final settlement in settlements) {
    if (partnerText(settlement['sellerId']) == partnerText(event['sellerId']) &&
        partnerText(settlement['userId']) == partnerText(event['userId']) &&
        partnerEnvironment(settlement) == partnerEnvironment(event) &&
        partnerText(settlement['store']) == partnerText(event['store']) &&
        partnerText(event['transactionId']).isNotEmpty &&
        partnerText(settlement['transactionId']) == partnerText(event['transactionId'])) {
      receipt = settlement;
      break;
    }
  }
  return <String, dynamic>{
    ...event, 'productId': event['productId'] ?? event['product'],
    'plan': normalizePartnerPlan(partnerText(event['plan']).isNotEmpty
        ? event['plan'] : event['productId'] ?? event['product']),
    if (receipt != null) ...{
      'payoutRecorded': true, 'paidAt': receipt['paidAt'] ?? receipt['recordedAt'],
      'accountingReference': receipt['accountingReference'],
    },
  };
}).toList();