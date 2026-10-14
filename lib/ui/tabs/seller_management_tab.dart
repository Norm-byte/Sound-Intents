import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/creator_partner_utils.dart';
import '../../services/creator_partner_service.dart';

/// Mounted through the existing seller_management admin permission gate.
class SellerManagementTab extends StatefulWidget {
  final CreatorPartnerRepository? repository;
  const SellerManagementTab({super.key, this.repository});
  @override
  State<SellerManagementTab> createState() => _SellerManagementTabState();
}

class _SellerManagementTabState extends State<SellerManagementTab> {
  late final CreatorPartnerRepository _service;
  late Future<CreatorPartnerData> _data;
  String? _sellerId;
  String _sellerSearch = '';
  String _sellerStatus = 'all';
  String _subscriberSearch = '';
  String _plan = 'all';
  String _subscriptionStatus = 'all';
  String _autoRenew = 'all';
  String _dateField = 'assignedSellerAt';
  DateTimeRange? _subscriberRange;
  String _eventSearch = '';
  String _environment = 'production';
  String _eventType = 'all';
  DateTimeRange? _eventRange;
  bool _busy = false;
  final _pageScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _service = widget.repository ?? CreatorPartnerService();
    _data = _service.load(null);
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  DateTime? _date(Object? value) => value is Timestamp ? value.toDate() : partnerDate(value);

  String _formatDate(Object? value) {
    final date = _date(value);
    return date == null ? 'Not available' : DateFormat('yyyy-MM-dd HH:mm').format(date.toLocal());
  }

  Object? _expiry(Map<String, dynamic> user) =>
      user['expiresAt'] ?? user['subscriptionExpiresAt'] ?? user['renewalDate'];

  Object? _lastSync(Map<String, dynamic> user) =>
      user['subscriptionSyncSource'] == 'webhook' ? user['subscriptionLastSyncedAt'] :
      user['subscriptionLastSyncedAt'] ?? user['lastSubscriptionSyncAt'] ??
      user['subscriptionUpdatedAt'] ?? user['lastSyncAt'];

  void _refresh() {
    if (!mounted) return;
    final future = _service.load(_sellerId);
    setState(() { _data = future; });
  }

  void _selectSeller(String id) {
    setState(() {
      _sellerId = id;
      _subscriberSearch = '';
      _plan = _subscriptionStatus = _autoRenew = 'all';
      _subscriberRange = _eventRange = null;
      _eventSearch = '';
      _eventType = 'all';
      _data = _service.load(id);
    });
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text), backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      _refresh();
    } catch (error) {
      _message('Operation failed: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSeller({Map<String, dynamic>? seller}) async {
    final values = <String, String>{
      for (final field in ['name', 'email', 'phone', 'country', 'notes'])
        field: partnerText(seller?[field]),
    };
    String status = seller == null ? 'active' : partnerStatus(seller);
    final form = GlobalKey<FormState>();
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(seller == null ? 'New Creator Partner Seller' : 'Edit seller profile'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final field in values.keys)
              Padding(padding: const EdgeInsets.only(bottom: 12), child: TextFormField(
                initialValue: values[field], onChanged: (value) => values[field] = value,
                decoration: InputDecoration(labelText: field[0].toUpperCase() + field.substring(1)),
                maxLines: field == 'notes' ? 3 : 1,
                validator: field == 'name' ? (value) =>
                    (value ?? '').trim().isEmpty ? 'Name is required' : null : null,
              )),
            _dropdown('Status', status, const ['active', 'paused', 'archived'],
                (value) => update(() => status = value)),
            const SizedBox(height: 12),
            const Text('Paused/archived sellers cannot issue usable referral codes. '
                'Archiving keeps profiles, codes, attribution and payment history; nothing is deleted.'),
          ]),
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(dialogContext, <String, dynamic>{
              for (final entry in values.entries) entry.key: entry.value.trim(),
              'country': values['country']!.trim().toUpperCase(), 'status': status,
            });
          }, child: const Text('Save profile')),
        ],
      )),
    );
    if (payload == null || !mounted) return;
    await _run(() async {
      final id = await _service.saveSeller(seller == null ? null : partnerText(seller['id']), payload);
      if (mounted) _selectSeller(id);
      _message('Seller profile saved.');
    });
  }

  Future<void> _createCode(Map<String, dynamic> seller, {Map<String, dynamic>? replaces}) async {
    final sellerId = partnerText(seller['id']);
    var enteredCode = _service.generateCode();
    final form = GlobalKey<FormState>();
    final raw = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(replaces == null ? 'Create referral code' : 'Replace referral code'),
      content: SizedBox(width: 420, child: Form(key: form, child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Seller: ${partnerText(seller['name'])}'),
          if (replaces != null) Text('Old code ${partnerText(replaces['code'])} will be deactivated atomically. '
              'Existing subscribers stay assigned to this seller.'),
          const SizedBox(height: 12),
          TextFormField(initialValue: enteredCode, onChanged: (value) => enteredCode = value,
            decoration: const InputDecoration(labelText: 'Unique referral code'),
            validator: (value) => validPartnerCode(value ?? '') ? null : 'Use 3–64 letters, numbers, - or _.'),
          const SizedBox(height: 12),
          const Text('Codes are trimmed and uppercased. Previously used codes cannot be reused.'),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (form.currentState!.validate()) Navigator.pop(context, enteredCode);
        }, child: const Text('Create code')),
      ],
    ));
    if (raw == null || !mounted) return;
    await _run(() async {
      final code = await _service.createCode(sellerId, raw,
          replacesId: replaces == null ? null : partnerText(replaces['id']));
      _message('Referral code created: $code');
    });
  }

  Future<void> _deactivateCode(Map<String, dynamic> code) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Deactivate referral code?'),
      content: Text('${partnerText(code['code'])} will stop accepting new referrals. '
          'Existing attribution and history are retained.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Deactivate')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    await _run(() => _service.deactivateCode(partnerText(code['sellerId']), partnerText(code['id'])));
  }

  Future<void> _recordSettlement(Map<String, dynamic> event) async {
    if (!canRecordPartnerSettlement(event)) return;
    var enteredReference = '';
    final form = GlobalKey<FormState>();
    final reference = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Record manual settlement'),
      content: SizedBox(width: 480, child: Form(key: form, child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Production ${partnerText(event['type'])}\nEvent: ${partnerText(event['eventId'])}\n'
              'Transaction: ${partnerText(event['transactionId'])}'),
          const SizedBox(height: 12),
          const Text('Confirm this purchase/renewal has been checked and the partner settlement '
              'has actually been paid. This records accounting evidence only; it does not send money.'),
          const SizedBox(height: 12),
          TextFormField(onChanged: (value) => enteredReference = value,
            decoration: const InputDecoration(labelText: 'Accounting reference'),
            validator: (value) {
              final reference = (value ?? '').trim();
              if (reference.isEmpty) return 'Accounting reference is required';
              if (reference.length > 200 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(reference)) {
                return 'Use at most 200 characters without control characters';
              }
              return null;
            }),
        ],
      ))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (form.currentState!.validate()) Navigator.pop(context, enteredReference.trim());
        }, child: const Text('Confirm paid and record')),
      ],
    ));
    if (reference == null || !mounted) return;
    await _run(() async {
      await _service.recordSettlement(event, reference);
      _message('Settlement recorded by the backend.');
    });
  }

  Future<void> _pickRange(bool events) async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2000),
      lastDate: DateTime(2100), initialDateRange: events ? _eventRange : _subscriberRange);
    if (range != null && mounted) setState(() {
      if (events) { _eventRange = range; } else { _subscriberRange = range; }
    });
  }

  Widget _dropdown(String label, String value, List<String> options, ValueChanged<String> changed) {
    final safeValue = options.contains(value) ? value : options.first;
    return SizedBox(width: 190, child: DropdownButtonFormField<String>(
      initialValue: safeValue, key: ValueKey('$label:$safeValue:${options.join(',')}'),
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: options.map((option) => DropdownMenuItem(value: option,
          child: Text(option == 'all' ? 'All' : option))).toList(),
      onChanged: (value) { if (value != null) changed(value); },
    ));
  }

  Widget _search(String label, String value, ValueChanged<String> changed) => SizedBox(
    width: 280, child: TextFormField(key: ValueKey('$label:$_sellerId'), initialValue: value,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder()), onChanged: changed,
    ),
  );

  Widget _rangeControls(bool events) {
    final range = events ? _eventRange : _subscriberRange;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      OutlinedButton.icon(onPressed: () => _pickRange(events), icon: const Icon(Icons.date_range),
        label: Text(range == null ? (events ? 'Purchase date range' : 'Snapshot date range')
            : '${DateFormat('yyyy-MM-dd').format(range.start)} – ${DateFormat('yyyy-MM-dd').format(range.end)}')),
      if (range != null) IconButton(tooltip: 'Clear date range', icon: const Icon(Icons.clear),
        onPressed: () => setState(() { if (events) { _eventRange = null; } else { _subscriberRange = null; } })),
    ]);
  }

  Widget _section(String title, Widget child, {Widget? action}) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(padding: const EdgeInsets.all(20), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge), if (action != null) action,
        ]),
        const SizedBox(height: 16), child,
      ],
    )),
  );

  Widget _sellerCards(CreatorPartnerData data) {
    final sellers = data.sellers.where((seller) {
      final haystack = ['name', 'email', 'phone', 'country', 'notes', 'id']
          .map((key) => partnerText(seller[key])).join(' ').toLowerCase();
      return haystack.contains(_sellerSearch.toLowerCase().trim()) &&
          (_sellerStatus == 'all' || partnerStatus(seller) == _sellerStatus);
    }).toList()..sort((a, b) => partnerText(a['name']).compareTo(partnerText(b['name'])));
    return _section('Creator Partner Sellers', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _search('Search seller profiles', _sellerSearch, (value) => setState(() => _sellerSearch = value)),
        _dropdown('Seller status', _sellerStatus, const ['all', 'active', 'paused', 'archived'],
            (value) => setState(() => _sellerStatus = value)),
      ]),
      const SizedBox(height: 16),
      if (sellers.isEmpty) const Text('No matching sellers. Create a profile or change filters.'),
      SizedBox(height: sellers.isEmpty ? 0 : 280, child: ListView.builder(
        itemCount: sellers.length,
        itemBuilder: (context, index) {
          final seller = sellers[index];
          final selected = seller['id'] == _sellerId;
          return Card(color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
            child: ListTile(selected: selected, leading: Icon(selected ? Icons.check_circle : Icons.badge_outlined),
              title: Text('${partnerText(seller['name'])} • ${partnerStatus(seller)}'),
              subtitle: Text('${partnerText(seller['email'])}  ${partnerText(seller['phone'])}\n'
                  '${partnerText(seller['country'])} • ${partnerText(seller['notes'])}'),
              isThreeLine: true, onTap: _busy ? null : () => _selectSeller(partnerText(seller['id'])),
            ),
          );
        },
      )),
    ]), action: FilledButton.icon(onPressed: _busy ? null : () => _editSeller(),
        icon: const Icon(Icons.add), label: const Text('New seller')));
  }

  Widget _profile(Map<String, dynamic> seller) => _section('Selected seller profile',
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectableText('${partnerText(seller['name'])}\nEmail: ${partnerText(seller['email'])}\n'
          'Phone: ${partnerText(seller['phone'])}\nCountry: ${partnerText(seller['country'])}\n'
          'Status: ${partnerStatus(seller)}\nNotes: ${partnerText(seller['notes'])}\n'
          'Seller reference: ${partnerText(seller['id'])}'),
      if (partnerStatus(seller) != 'active') const Padding(padding: EdgeInsets.only(top: 12),
        child: Text('Referral use is blocked while this seller is paused or archived. '
            'Historical subscriber and payment records remain visible.')),
    ]), action: OutlinedButton.icon(onPressed: _busy ? null : () => _editSeller(seller: seller),
        icon: const Icon(Icons.edit_outlined), label: const Text('Edit / change status')));

  Widget _codes(CreatorPartnerData data, Map<String, dynamic> seller) {
    final canCreate = !_busy && partnerStatus(seller) == 'active';
    return _section('Referral codes', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Copy or deactivate codes; replace with a new unique code for the same seller. '
          'Codes and historical attribution are never deleted.'),
      const SizedBox(height: 12),
      if (data.codes.isEmpty) const Text('No referral codes for this seller.'),
      for (final code in data.codes)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Wrap(
          spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SelectableText('${partnerText(code['code'])} • '
                '${code['isActive'] == true && code['status'] == 'active' ? 'Active' : 'Inactive'}'),
            OutlinedButton.icon(icon: const Icon(Icons.copy), label: const Text('Copy'), onPressed: () async {
              await Clipboard.setData(ClipboardData(text: partnerText(code['code'])));
              _message('Code copied.');
            }),
            if (code['isActive'] == true)
              TextButton(onPressed: _busy ? null : () => _deactivateCode(code), child: const Text('Deactivate')),
            TextButton(onPressed: canCreate ? () => _createCode(seller, replaces: code) : null,
                child: const Text('Replacement new code')),
          ],
        )),
    ]), action: FilledButton.icon(onPressed: canCreate ? () => _createCode(seller) : null,
        icon: const Icon(Icons.add), label: const Text('Create code')));
  }

  List<String> _options(List<Map<String, dynamic>> rows, String field) =>
      ['all', ...({...rows.map((row) => partnerText(row[field]))}..remove('')..remove('all')).toList()..sort()];

  Widget _subscribers(CreatorPartnerData data) {
    final rows = data.subscribers.where((user) => partnerSubscriberMatches(user,
      search: _subscriberSearch, plan: _plan, status: _subscriptionStatus, autoRenew: _autoRenew,
      date: _date(_dateField == 'expiry' ? _expiry(user) : _dateField == 'sync' ? _lastSync(user) : user['assignedSellerAt']),
      start: _subscriberRange?.start, end: _subscriberRange?.end,
    )).toList();
    return _section('Selected-seller subscribers (${rows.length} / ${data.subscribers.length})',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Snapshot status — NOT transaction proof. These are current user subscription '
          'snapshots, not verified purchases or amounts due. Production webhook status is used when available; '
          'otherwise the app snapshot is retained. Sandbox does not override production. '
          'Only users assigned to this seller are queried.'),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _search('Search username / account', _subscriberSearch, (value) => setState(() => _subscriberSearch = value)),
          _dropdown('Plan', _plan, _options(data.subscribers, 'subscriptionPlan'), (value) => setState(() => _plan = value)),
          _dropdown('Snapshot status', _subscriptionStatus, _options(data.subscribers, 'status'),
              (value) => setState(() => _subscriptionStatus = value)),
          _dropdown('Auto-renew', _autoRenew, const ['all', 'yes', 'no', 'unknown'], (value) => setState(() => _autoRenew = value)),
          _dropdown('Date field', _dateField, const ['assignedSellerAt', 'expiry', 'sync'], (value) => setState(() => _dateField = value)),
          _rangeControls(false),
        ]),
        const SizedBox(height: 16),
        if (rows.isEmpty) const Text('No attributed subscribers match. Missing attribution is not inferred from a raw referral code.'),
        if (rows.isNotEmpty) _table([
          'Username', 'Account reference', 'Plan', 'Snapshot status', 'Will renew',
          'Expiry date', 'Attribution date', 'Last subscription sync',
        ], rows.map((user) => [
          partnerUserName(user), partnerText(user['accountReference']).isEmpty ? partnerText(user['id'])
              : '${partnerText(user['accountReference'])}\n${partnerText(user['id'])}',
          partnerText(user['subscriptionPlan']), partnerText(user['status']),
          user['willRenew'] == true ? 'Yes' : user['willRenew'] == false ? 'No' : 'Unknown',
          _formatDate(_expiry(user)), _formatDate(user['assignedSellerAt']),
          '${user['subscriptionSyncSource'] == 'webhook' ? 'Webhook' : 'App'} last sync: ${_formatDate(_lastSync(user))}',
        ]).toList()),
      ]),
    );
  }

  Widget _table(List<String> headings, List<List<String>> rows) => SizedBox(height: 340,
    child: Scrollbar(child: SingleChildScrollView(primary: false,
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, primary: false,
        child: DataTable(columns: headings.map((heading) => DataColumn(label: Text(heading))).toList(),
          rows: rows.map((row) => DataRow(cells: row.map((value) => DataCell(
              SelectableText(value.isEmpty ? 'Not available' : value))).toList())).toList()),
      ),
    )),
  );

  Widget _events(CreatorPartnerData data) {
    final rows = data.events.where((event) {
      final haystack = ['eventId', 'userId', 'transactionId', 'accountingReference', 'productId', 'plan']
          .map((field) => partnerText(event[field])).join(' ').toLowerCase();
      return (_environment == 'all' || partnerEnvironment(event) == _environment) &&
          (_eventType == 'all' || partnerText(event['type']) == _eventType) &&
          haystack.contains(_eventSearch.toLowerCase().trim()) &&
          partnerDateInRange(_date(event['purchasedAt']), _eventRange?.start, _eventRange?.end);
    }).toList()..sort((a, b) => (_date(b['receivedAt']) ?? DateTime(1970))
        .compareTo(_date(a['receivedAt']) ?? DateTime(1970)));
    return _section('Webhook payment history (${rows.length} / ${data.events.length})',
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Separate webhook event evidence. Cancellations, expirations, reversals and test '
            'events are not payable purchases. No commission, FX or financial totals are calculated. '
            'Settlement eligibility is rechecked by the authenticated backend.'),
        const SizedBox(height: 16),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _dropdown('Environment', _environment, const ['production', 'test', 'unknown', 'all'],
              (value) => setState(() => _environment = value)),
          _dropdown('Event type', _eventType, _options(data.events, 'type'), (value) => setState(() => _eventType = value)),
          _search('Search payment events', _eventSearch, (value) => setState(() => _eventSearch = value)),
          _rangeControls(true),
        ]),
        const SizedBox(height: 16),
        if (rows.isEmpty) const Text('No webhook events match. A user snapshot is not a substitute for webhook payment history.'),
        if (rows.isNotEmpty) SizedBox(height: 440, child: ListView.builder(
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final event = rows[index];
            final eligible = partnerSettlementEligible(event, data.events);
            return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${partnerText(event['type'])} • ${partnerEnvironment(event)}',
                      style: Theme.of(context).textTheme.titleMedium),
                  if (eligible) FilledButton.tonal(onPressed: _busy ? null : () => _recordSettlement(event),
                      child: const Text('Record manual settlement')),
                ]),
                const SizedBox(height: 8),
                SelectableText('Event: ${partnerText(event['eventId'])}\n'
                    'User: ${partnerText(event['userId'])} • Seller: ${partnerText(event['sellerId'])}\n'
                    'Product: ${partnerText(event['productId'])} • Plan: ${partnerText(event['plan'])}\n'
                    'Store: ${partnerText(event['store'])} • Environment: ${partnerText(event['environment'])}\n'
                    'Purchased: ${_formatDate(event['purchasedAt'])} • Expires: ${_formatDate(event['expiresAt'])}\n'
                    'Received: ${_formatDate(event['receivedAt'])}\nTransaction: ${partnerText(event['transactionId'])}\n'
                    '${event['amount'] == null ? '' : 'Reported amount (unmodified): ${partnerText(event['amount'])} ${partnerText(event['currency'])}\n'}'
                    'Payout recorded: ${event['payoutRecorded'] == true ? 'Yes' : 'No'}\n'
                    'Paid at: ${_formatDate(event['paidAt'])}\nAccounting reference: ${partnerText(event['accountingReference'])}'),
                if (!eligible && event['payoutRecorded'] != true) const Padding(padding: EdgeInsets.only(top: 8),
                  child: Text('Not eligible: requires an unreversed production purchase/renewal, '
                      'event and transaction identity, purchase date and no prior settlement.')),
              ],
            )));
          },
        )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<CreatorPartnerData>(future: _data,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != ConnectionState.done;
      // Never show previous seller results during a new seller's load.
      final data = loading || snapshot.hasError ? null : snapshot.data;
      Map<String, dynamic>? seller;
      if (data != null) {
        for (final candidate in data.sellers) {
          if (candidate['id'] == _sellerId) { seller = candidate; break; }
        }
      }
      return Scrollbar(controller: _pageScroll, child: SingleChildScrollView(
        controller: _pageScroll, padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 16, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Creator Partners', style: Theme.of(context).textTheme.headlineMedium),
            OutlinedButton.icon(onPressed: _busy || loading ? null : _refresh,
                icon: const Icon(Icons.refresh), label: const Text('Refresh Metrics Data')),
          ]),
          const SizedBox(height: 8),
          const Text('Admin-only seller profiles, attribution snapshots and webhook payment evidence.'),
          const SizedBox(height: 16),
          if (_busy || loading) const LinearProgressIndicator(),
          if (snapshot.hasError && !loading) _section('Data unavailable', Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Could not query creator-partner data: ${snapshot.error}'),
              const Text('No missing data is presented as zero or as a confirmed payment.'),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ],
          )),
          if (data != null) ...[
            _section('RevenueCat webhook integration', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Configured: ${data.integration['configured'] == true ? 'Yes' : 'No / not configured'}'),
              Text('Last event received: ${_formatDate(data.integration['lastEventAt'])}'),
              const Text('Configuration status is not proof of a specific payment. Refresh re-queries '
                  'Firestore; it does not trigger billing or fabricate events.'),
            ])),
            _sellerCards(data),
            if (seller == null) const Text('Select a seller card to view codes, subscribers and payment history.'),
            if (seller != null) ...[_profile(seller), _codes(data, seller), _subscribers(data), _events(data)],
          ],
        ]),
      ));
    },
  );
}
