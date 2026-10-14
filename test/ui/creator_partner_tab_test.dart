import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_admin/models/creator_partner_utils.dart';
import 'package:harmony_admin/services/creator_partner_service.dart';
import 'package:harmony_admin/ui/tabs/seller_management_tab.dart';

class _Repository implements CreatorPartnerRepository {
  final loads = <String?>[];
  final savedProfiles = <Map<String, dynamic>>[];
  final settlements = <String>[];
  final created = <String>[];
  final deactivated = <String>[];
  final statuses = <Map<String, dynamic>>[];
  Completer<CreatorPartnerData>? pending;
  bool fail = false;
  final sellers = <Map<String, dynamic>>[
    {'id': 'seller-1', 'name': 'Creator One', 'email': 'one@example.com', 'phone': '123',
      'country': 'GB', 'notes': 'Profile notes', 'status': 'active', 'isActive': true},
    {'id': 'seller-2', 'name': 'Creator Two', 'status': 'archived', 'isActive': false},
  ];
  final events = <Map<String, dynamic>>[
    {'eventId': 'production-event', 'sellerId': 'seller-1', 'userId': 'user-1',
      'type': 'INITIAL_PURCHASE', 'environment': 'PRODUCTION', 'transactionId': 'tx-1',
      'store': 'APP_STORE', 'productId': 'harmony100_monthly',
      'purchasedAt': DateTime(2026, 10, 14), 'receivedAt': DateTime(2026, 10, 14)},
    {'eventId': 'sandbox-event', 'sellerId': 'seller-1', 'userId': 'user-1',
      'type': 'RENEWAL', 'environment': 'SANDBOX', 'transactionId': 'tx-test',
      'store': 'APP_STORE', 'productId': 'harmony100_monthly',
      'purchasedAt': DateTime(2026, 10, 14)},
  ];

  @override
  Future<CreatorPartnerData> load(String? sellerId) async {
    loads.add(sellerId);
    if (fail) throw StateError('Permission denied');
    if (pending != null) return pending!.future;
    return data(sellerId);
  }

  CreatorPartnerData data(String? sellerId) => CreatorPartnerData(sellers: sellers,
    integration: {'configured': true, 'lastEventAt': DateTime(2026, 10, 14)},
    codes: sellerId == 'seller-1' ? [
      {'id': 'code-1', 'sellerId': 'seller-1', 'code': 'ONE-123', 'isActive': true, 'status': 'active'},
    ] : [],
    subscribers: partnerSubscriberSnapshots(sellerId == 'seller-1' ? [
      {'id': 'user-1', 'userName': 'Fan One', 'status': 'active', 'subscriptionPlan': 'Harmony100',
        'willRenew': true, 'renewalDate': DateTime(2026, 11, 14), 'assignedSellerAt': DateTime(2026, 10, 14)},
      {'id': 'user-2', 'username': 'Fan Two', 'status': 'expired', 'subscriptionPlan': 'Starter', 'willRenew': false},
    ] : [], statuses, sellerId),
    events: sellerId == 'seller-1' ? partnerPaymentHistory(events, []) : []);

  @override
  Future<String> saveSeller(String? id, Map<String, dynamic> profile) async {
    savedProfiles.add(profile);
    return id ?? 'seller-1';
  }
  @override
  String generateCode() => 'NEW-1234';
  @override
  Future<String> createCode(String sellerId, String raw, {String? replacesId}) async {
    created.add('$sellerId:$raw:$replacesId');
    return raw;
  }
  @override
  Future<void> deactivateCode(String sellerId, String codeId) async => deactivated.add('$sellerId:$codeId');
  @override
  Future<void> recordSettlement(Map<String, dynamic> event, String reference) async {
    settlements.add('${event['eventId']}:$reference');
    final stored = events.firstWhere((row) => row['eventId'] == event['eventId']);
    stored['payoutRecorded'] = true;
    stored['paidAt'] = DateTime(2026, 10, 14);
    stored['accountingReference'] = reference;
  }
}

void main() {
  Future<void> mount(WidgetTester tester, _Repository repository) async {
    tester.view.physicalSize = const Size(1500, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SellerManagementTab(repository: repository))));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, String name) async {
    await tester.ensureVisible(find.textContaining(name).first);
    await tester.tap(find.textContaining(name).first);
    await tester.pumpAndSettle();
  }

  testWidgets('selects seller cards, shows snapshots separately, refresh re-queries selected seller', (tester) async {
    final repository = _Repository();
    await mount(tester, repository);
    expect(repository.loads, [null]);
    await select(tester, 'Creator One • active');
    expect(repository.loads, [null, 'seller-1']);
    expect(find.textContaining('Snapshot status — NOT transaction proof'), findsOneWidget);
    expect(find.text('Fan One'), findsOneWidget);
    expect(find.text('Fan Two'), findsOneWidget);
    expect(find.textContaining('Event: production-event'), findsOneWidget);
    expect(find.textContaining('Event: sandbox-event'), findsNothing);
    expect(find.textContaining('Commission'), findsNothing);
    await tester.ensureVisible(find.text('Refresh Metrics Data'));
    await tester.tap(find.text('Refresh Metrics Data'));
    await tester.pumpAndSettle();
    expect(repository.loads.last, 'seller-1');
    expect(repository.loads.length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('subscriber search resolves userName and filters account references', (tester) async {
    await mount(tester, _Repository());
    await select(tester, 'Creator One • active');
    final field = find.widgetWithText(TextFormField, 'Search username / account');
    await tester.ensureVisible(field);
    await tester.enterText(field, 'user-2');
    await tester.pumpAndSettle();
    expect(find.text('Fan One'), findsNothing);
    expect(find.text('Fan Two'), findsOneWidget);
    expect(find.text('Selected-seller subscribers (1 / 2)'), findsOneWidget);
  });

  testWidgets('webhook and app sync are labelled and production plan is filterable', (tester) async {
    final repository = _Repository();
    repository.statuses.addAll([
      {'userId': 'user-1', 'sellerId': 'seller-1', 'environment': 'PRODUCTION',
        'plan': 'starter_monthly', 'active': false, 'willRenew': null,
        'expiresAt': DateTime.utc(2026, 12, 14).millisecondsSinceEpoch,
        'lastReceivedAt': DateTime.utc(2026, 10, 14, 12).millisecondsSinceEpoch},
      {'userId': 'user-2', 'sellerId': 'seller-1', 'environment': 'SANDBOX',
        'plan': 'harmony100_monthly', 'active': true, 'willRenew': true},
    ]);
    await mount(tester, repository);
    await select(tester, 'Creator One • active');
    expect(find.textContaining('Webhook last sync:'), findsOneWidget);
    expect(find.text('App last sync: Not available'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    final plan = find.widgetWithText(DropdownButtonFormField<String>, 'Plan');
    await tester.ensureVisible(plan);
    await tester.tap(plan);
    await tester.pumpAndSettle();
    await tester.tap(find.text('starter').last);
    await tester.pumpAndSettle();
    expect(find.text('Fan One'), findsOneWidget);
    expect(find.text('Fan Two'), findsNothing);
    expect(find.text('Selected-seller subscribers (1 / 2)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product-only webhook shows normalized plan and supports plan search', (tester) async {
    final repository = _Repository();
    repository.events.first.remove('productId');
    repository.events.first['product'] = 'starter_monthly:monthly';
    await mount(tester, repository);
    await select(tester, 'Creator One • active');
    expect(find.textContaining('Product: starter_monthly:monthly • Plan: starter'), findsOneWidget);
    final search = find.widgetWithText(TextFormField, 'Search payment events');
    await tester.ensureVisible(search);
    await tester.enterText(search, 'starter');
    await tester.pumpAndSettle();
    expect(find.textContaining('Event: production-event'), findsOneWidget);
    await tester.enterText(search, 'harmony100');
    await tester.pumpAndSettle();
    expect(find.textContaining('Event: production-event'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('archived seller disables code creation and retains history workspace', (tester) async {
    await mount(tester, _Repository());
    await select(tester, 'Creator Two • archived');
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create code'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('Selected-seller subscribers'), findsOneWidget);
    expect(find.text('Fan One'), findsNothing);
  });

  testWidgets('manual settlement requires accounting reference and calls repository once', (tester) async {
    final repository = _Repository();
    await mount(tester, repository);
    await select(tester, 'Creator One • active');
    await tester.ensureVisible(find.text('Record manual settlement'));
    await tester.tap(find.text('Record manual settlement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm paid and record'));
    await tester.pumpAndSettle();
    expect(find.text('Accounting reference is required'), findsOneWidget);
    expect(repository.settlements, isEmpty);
    await tester.enterText(find.widgetWithText(TextFormField, 'Accounting reference'), ' AC-100 ');
    await tester.tap(find.text('Confirm paid and record'));
    await tester.pumpAndSettle();
    expect(repository.settlements, ['production-event:AC-100']);
    expect(find.text('Record manual settlement'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacement stays on same seller and deactivation is confirmed', (tester) async {
    final repository = _Repository();
    await mount(tester, repository);
    await select(tester, 'Creator One • active');
    await tester.ensureVisible(find.text('Replacement new code'));
    await tester.tap(find.text('Replacement new code'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create code').last);
    await tester.pumpAndSettle();
    expect(repository.created, ['seller-1:NEW-1234:code-1']);
    await tester.ensureVisible(find.text('Deactivate'));
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();
    expect(repository.deactivated, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(repository.deactivated, ['seller-1:code-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('linked reversal removes settlement affordance', (tester) async {
    final repository = _Repository();
    repository.events.add({...repository.events.first, 'eventId': 'refund-event', 'type': 'REFUND'});
    await mount(tester, repository);
    await select(tester, 'Creator One • active');
    expect(find.text('Record manual settlement'), findsNothing);
  });

  testWidgets('loading another seller never shows prior subscriber/payment data', (tester) async {
    final repository = _Repository();
    await mount(tester, repository);
    await select(tester, 'Creator One • active');
    repository.pending = Completer<CreatorPartnerData>();
    await tester.ensureVisible(find.textContaining('Creator Two • archived'));
    await tester.tap(find.textContaining('Creator Two • archived'));
    await tester.pump();
    expect(find.text('Fan One'), findsNothing);
    expect(find.textContaining('Event: production-event'), findsNothing);
    repository.pending!.complete(repository.data('seller-2'));
    await tester.pumpAndSettle();
    expect(find.text('Fan One'), findsNothing);
  });

  testWidgets('query failures display an error rather than fabricated zero metrics', (tester) async {
    final repository = _Repository()..fail = true;
    await mount(tester, repository);
    expect(find.text('Data unavailable'), findsOneWidget);
    expect(find.textContaining('Permission denied'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Creator Partner Sellers'), findsOneWidget);
  });

  testWidgets('plan and auto-renew filters compose and test events cannot settle', (tester) async {
    await mount(tester, _Repository());
    await select(tester, 'Creator One • active');
    final plan = find.widgetWithText(DropdownButtonFormField<String>, 'Plan');
    await tester.ensureVisible(plan);
    await tester.tap(plan);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Starter').last);
    await tester.pumpAndSettle();
    expect(find.text('Fan One'), findsNothing);
    expect(find.text('Fan Two'), findsOneWidget);
    final renew = find.widgetWithText(DropdownButtonFormField<String>, 'Auto-renew');
    await tester.ensureVisible(renew);
    await tester.tap(renew);
    await tester.pumpAndSettle();
    await tester.tap(find.text('yes').last);
    await tester.pumpAndSettle();
    expect(find.text('Selected-seller subscribers (0 / 2)'), findsOneWidget);
    final environment = find.widgetWithText(DropdownButtonFormField<String>, 'Environment');
    await tester.ensureVisible(environment);
    await tester.tap(environment);
    await tester.pumpAndSettle();
    await tester.tap(find.text('test').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Event: sandbox-event'), findsOneWidget);
    expect(find.textContaining('Event: production-event'), findsNothing);
    expect(find.text('Record manual settlement'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('soft archive saves only profile and status without financial fields', (tester) async {
    final repository = _Repository();
    await mount(tester, repository);
    await select(tester, 'Creator One • active');
    await tester.ensureVisible(find.text('Edit / change status'));
    await tester.tap(find.text('Edit / change status'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('archived').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(repository.savedProfiles.single, {
      'name': 'Creator One', 'email': 'one@example.com', 'phone': '123',
      'country': 'GB', 'notes': 'Profile notes', 'status': 'archived',
    });
    expect(repository.deactivated, isEmpty);
    expect(repository.settlements, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow viewport keeps subscriber and event sections scrollable without overflow', (tester) async {
    await mount(tester, _Repository());
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await select(tester, 'Creator One • active');
    await tester.ensureVisible(find.textContaining('Selected-seller subscribers'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Record manual settlement'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}