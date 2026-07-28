import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SellerManagementTab extends StatefulWidget {
  const SellerManagementTab({super.key});

  @override
  State<SellerManagementTab> createState() => _SellerManagementTabState();
}

class _RateConfig {
  final double globalDefaultRate;
  final Map<String, double> countryRates;
  final String payoutMode;
  final double fixedStarterGbp;
  final double fixedHarmony100Gbp;

  const _RateConfig({
    required this.globalDefaultRate,
    required this.countryRates,
    required this.payoutMode,
    required this.fixedStarterGbp,
    required this.fixedHarmony100Gbp,
  });
}

class _SellerManagementTabState extends State<SellerManagementTab> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final TextEditingController _payoutCurrencyController = TextEditingController(
    text: 'GBP',
  );
  final TextEditingController _defaultRateController = TextEditingController(
    text: '0.10',
  );
  final TextEditingController _notesController = TextEditingController();

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _codeSellerIdController = TextEditingController();

  final TextEditingController _globalRateController = TextEditingController(
    text: '0.10',
  );
  final TextEditingController _fixedStarterPayoutController =
      TextEditingController(text: '0.50');
  final TextEditingController _fixedHarmony100PayoutController =
      TextEditingController(text: '0.80');
  final TextEditingController _countryRateController = TextEditingController(
    text: '0.10',
  );
  final TextEditingController _countryRateCodeController =
      TextEditingController();

  final ScrollController _sellerListScroll = ScrollController();
  final ScrollController _metricsScroll = ScrollController();

  DateTimeRange? _dateRange;
  String _selectedCountryFilter = 'ALL';
  String? _selectedSellerId;

  bool _savingSeller = false;
  bool _savingCode = false;
  bool _savingRate = false;
  bool _loadingRateSettings = false;
  bool _refreshingFx = false;
  bool _lockingFx = false;
  bool _isSellerActive = true;
  String _payoutMode = 'percentage';

  static const Map<String, String> _countryToCurrency = {
    'GB': 'GBP',
    'US': 'USD',
    'AU': 'AUD',
    'CA': 'CAD',
    'NZ': 'NZD',
    'IE': 'EUR',
    'NL': 'EUR',
    'DE': 'EUR',
    'FR': 'EUR',
    'ES': 'EUR',
    'IT': 'EUR',
    'ZA': 'ZAR',
    'NG': 'NGN',
    'IN': 'INR',
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, now.month, 1),
      end: now,
    );
    _loadRateSettingsIntoForm();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    _payoutCurrencyController.dispose();
    _defaultRateController.dispose();
    _notesController.dispose();
    _codeController.dispose();
    _codeSellerIdController.dispose();
    _globalRateController.dispose();
    _fixedStarterPayoutController.dispose();
    _fixedHarmony100PayoutController.dispose();
    _countryRateController.dispose();
    _countryRateCodeController.dispose();
    _sellerListScroll.dispose();
    _metricsScroll.dispose();
    super.dispose();
  }

  String _normalizeCode(String raw) => raw.trim().toUpperCase();

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    final raw = String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
    return '${raw.substring(0, 4)}-${raw.substring(4, 8)}';
  }

  double _parseRate(String raw, {double fallback = 0.10}) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return fallback;
    if (parsed < 0) return 0;
    if (parsed > 1) return 1;
    return parsed;
  }

  double _parseMoney(String raw, {double fallback = 0}) {
    final parsed = double.tryParse(raw.trim());
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return fallback;
    if (parsed < 0) return 0;
    return parsed;
  }

  Future<void> _loadRateSettingsIntoForm() async {
    setState(() => _loadingRateSettings = true);
    try {
      final globalSnap = await FirebaseFirestore.instance
          .collection('seller_commission_settings')
          .doc('global')
          .get();
      final data = globalSnap.data() ?? {};
      if (!mounted) return;

      setState(() {
        _globalRateController.text =
            ((data['defaultRate'] as num?)?.toDouble() ?? 0.10)
                .toStringAsFixed(2);
        _payoutMode =
            (data['payoutMode'] as String?)?.trim().toLowerCase() ==
                    'fixed_gbp_per_plan'
                ? 'fixed_gbp_per_plan'
                : 'percentage';
        _fixedStarterPayoutController.text =
            ((data['fixedStarterGbp'] as num?)?.toDouble() ?? 0.50)
                .toStringAsFixed(2);
        _fixedHarmony100PayoutController.text =
            ((data['fixedHarmony100Gbp'] as num?)?.toDouble() ?? 0.80)
                .toStringAsFixed(2);
      });
    } catch (_) {
      // Leave defaults in place if settings are missing.
    } finally {
      if (mounted) setState(() => _loadingRateSettings = false);
    }
  }

  Future<void> _saveSeller() async {
    if (_nameController.text.trim().isEmpty) {
      _snack('Seller name is required.', isError: true);
      return;
    }

    setState(() => _savingSeller = true);
    try {
      final payload = {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'country': _countryController.text.trim().toUpperCase(),
        'payoutCurrency': _normalizedPayoutCurrency(),
        'isActive': _isSellerActive,
        'defaultRate': _parseRate(_defaultRateController.text),
        'notes': _notesController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_selectedSellerId == null) {
        await FirebaseFirestore.instance.collection('sellers').add({
          ...payload,
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'active',
        });
      } else {
        await FirebaseFirestore.instance
            .collection('sellers')
            .doc(_selectedSellerId)
            .set(payload, SetOptions(merge: true));
      }

      _clearSellerForm();
      _snack('Seller saved.');
    } catch (e) {
      _snack('Could not save seller: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingSeller = false);
    }
  }

  Future<void> _setSellerActive(String sellerId, bool active) async {
    await FirebaseFirestore.instance.collection('sellers').doc(sellerId).set({
      'isActive': active,
      'status': active ? 'active' : 'inactive',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _setAllSellersActive(bool active) async {
    final sellers = await FirebaseFirestore.instance.collection('sellers').get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in sellers.docs) {
      batch.set(doc.reference, {
        'isActive': active,
        'status': active ? 'active' : 'inactive',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
    _snack(active ? 'All sellers activated.' : 'All sellers deactivated.');
  }

  Future<void> _deleteSeller(String sellerId) async {
    await FirebaseFirestore.instance.collection('sellers').doc(sellerId).delete();

    final codeDocs = await FirebaseFirestore.instance
        .collection('seller_codes')
        .where('sellerId', isEqualTo: sellerId)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    for (final codeDoc in codeDocs.docs) {
      batch.delete(codeDoc.reference);
    }
    await batch.commit();
  }

  Future<void> _saveSellerCode() async {
    final sellerId = _codeSellerIdController.text.trim();
    if (sellerId.isEmpty) {
      _snack('Select a seller first.', isError: true);
      return;
    }

    setState(() => _savingCode = true);
    try {
      final raw = _codeController.text.trim();
      final code = raw.isEmpty ? _generateCode() : _normalizeCode(raw);
      final normalized = _normalizeCode(code);

      final existing = await FirebaseFirestore.instance
          .collection('seller_codes')
          .where('normalizedCode', isEqualTo: normalized)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        _snack('Code already exists. Choose another code.', isError: true);
        return;
      }

      await FirebaseFirestore.instance.collection('seller_codes').add({
        'sellerId': sellerId,
        'code': code,
        'normalizedCode': normalized,
        'isActive': true,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _codeController.clear();
      await Clipboard.setData(ClipboardData(text: code));
      _snack('Seller code created and copied: $code');
    } catch (e) {
      _snack('Could not save seller code: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingCode = false);
    }
  }

  Future<void> _setSellerCodeActive(String codeId, bool active) async {
    await FirebaseFirestore.instance.collection('seller_codes').doc(codeId).set({
      'isActive': active,
      'status': active ? 'active' : 'inactive',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _deleteSellerCode(String codeId) async {
    await FirebaseFirestore.instance.collection('seller_codes').doc(codeId).delete();
  }

  Future<void> _saveGlobalRate() async {
    setState(() => _savingRate = true);
    try {
      final rate = _parseRate(_globalRateController.text);
      final fixedStarter = _parseMoney(_fixedStarterPayoutController.text);
      final fixedHarmony100 =
          _parseMoney(_fixedHarmony100PayoutController.text);
      await FirebaseFirestore.instance
          .collection('seller_commission_settings')
          .doc('global')
          .set({
        'defaultRate': rate,
        'payoutMode': _payoutMode,
        'fixedStarterGbp': fixedStarter,
        'fixedHarmony100Gbp': fixedHarmony100,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _snack('Global payout settings saved.');
    } catch (e) {
      _snack('Could not save global rate: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingRate = false);
    }
  }

  Future<void> _saveCountryRate() async {
    final code = _countryRateCodeController.text.trim().toUpperCase();
    if (code.length < 2) {
      _snack('Country code is required.', isError: true);
      return;
    }

    setState(() => _savingRate = true);
    try {
      final rate = _parseRate(_countryRateController.text);
      await FirebaseFirestore.instance
          .collection('seller_country_rates')
          .doc(code)
          .set({
        'countryCode': code,
        'rate': rate,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _snack('Country rate saved for $code.');
    } catch (e) {
      _snack('Could not save country rate: $e', isError: true);
    } finally {
      if (mounted) setState(() => _savingRate = false);
    }
  }

  void _loadSeller(Map<String, dynamic> data, String sellerId) {
    _selectedSellerId = sellerId;
    _nameController.text = (data['name'] ?? '').toString();
    _emailController.text = (data['email'] ?? '').toString();
    _phoneController.text = (data['phone'] ?? '').toString();
    _countryController.text = (data['country'] ?? '').toString();
    _payoutCurrencyController.text = _sellerCurrencyFromData(data);
    final rate = (data['defaultRate'] as num?)?.toDouble() ?? 0.10;
    _defaultRateController.text = rate.toStringAsFixed(2);
    _notesController.text = (data['notes'] ?? '').toString();
    _isSellerActive = data['isActive'] != false;
    _codeSellerIdController.text = sellerId;
    setState(() {});
  }

  void _clearSellerForm() {
    _selectedSellerId = null;
    _nameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _countryController.clear();
    _payoutCurrencyController.text = 'GBP';
    _defaultRateController.text = '0.10';
    _notesController.clear();
    _isSellerActive = true;
    _codeSellerIdController.clear();
    setState(() {});
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  String _currentMonthKey() {
    final now = DateTime.now().toUtc();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  String _normalizedPayoutCurrency() {
    final normalized = _payoutCurrencyController.text.trim().toUpperCase();
    if (normalized.length == 3) return normalized;
    return 'GBP';
  }

  String _sellerCurrencyFromData(Map<String, dynamic> data) {
    final explicit = (data['payoutCurrency'] ?? '').toString().trim().toUpperCase();
    if (explicit.length == 3) return explicit;

    final country = (data['country'] ?? '').toString().trim().toUpperCase();
    return _countryToCurrency[country] ?? 'GBP';
  }

  Map<String, double> _extractRates(Map<String, dynamic>? docData) {
    final rawRates = docData?['rates'];
    if (rawRates is! Map) return const <String, double>{};
    final rates = <String, double>{};
    rawRates.forEach((key, value) {
      final code = key.toString().trim().toUpperCase();
      final parsed = value is num ? value.toDouble() : double.tryParse(value.toString());
      if (code.isNotEmpty && parsed != null && parsed > 0) {
        rates[code] = parsed;
      }
    });
    rates['GBP'] = 1.0;
    return rates;
  }

  double _gbpToCurrencyRate(
    String currency,
    Map<String, double> monthlyRates,
    Map<String, double> liveRates,
  ) {
    final code = currency.trim().toUpperCase();
    if (code.isEmpty || code == 'GBP') return 1.0;
    if (monthlyRates.containsKey(code)) return monthlyRates[code]!;
    if (liveRates.containsKey(code)) return liveRates[code]!;
    return 1.0;
  }

  String _formatAmount(String currencyCode, num amount) {
    return '${amount.toStringAsFixed(2)} $currencyCode';
  }

  String _formatShortStamp(DateTime? value) {
    if (value == null) return 'Not set';
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<void> _refreshLiveFxRates() async {
    setState(() => _refreshingFx = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('refreshLiveFxRates')
          .call();
      _snack('Live FX rates refreshed.');
    } catch (e) {
      _snack('Could not refresh FX rates: $e', isError: true);
    } finally {
      if (mounted) setState(() => _refreshingFx = false);
    }
  }

  Future<void> _lockCurrentMonthFxSnapshot() async {
    setState(() => _lockingFx = true);
    try {
      final month = _currentMonthKey();
      await FirebaseFunctions.instance
          .httpsCallable('lockCurrentMonthFxSnapshot')
          .call({'month': month});
      _snack('FX snapshot locked for $month.');
    } catch (e) {
      _snack('Could not lock FX snapshot: $e', isError: true);
    } finally {
      if (mounted) setState(() => _lockingFx = false);
    }
  }

  Future<Map<String, dynamic>> _computeMetricsForSeller(
    String sellerId,
    List<Map<String, dynamic>> users,
    _RateConfig rateConfig,
    Map<String, dynamic> sellerData,
  ) async {
    final start = _dateRange?.start;
    final end = _dateRange?.end;
    final sellerDefaultRate = (sellerData['defaultRate'] as num?)?.toDouble() ??
        rateConfig.globalDefaultRate;

    final sellerUsers = users.where((u) {
      return (u['assignedSellerId'] ?? '').toString().trim() == sellerId;
    }).toList();

    int activeSubscribers = 0;
    int willRenewCount = 0;
    int paidMonthlyCount = 0;
    double grossEstimate = 0;
    double residualEstimate = 0;

    for (final user in sellerUsers) {
      final status = (user['status'] ?? '').toString().toLowerCase();
      final isActive = status == 'active';
      final willRenew = user['willRenew'] == true;
      final plan = (user['subscriptionPlan'] ?? '').toString().toLowerCase();
      final renewalDate = _asDate(user['renewalDate']);

      if (isActive) activeSubscribers++;
      if (willRenew) willRenewCount++;

      final monthlyLike = plan.contains('starter') ||
          plan.contains('harmony 100') ||
          plan.contains('monthly');
      if (monthlyLike && isActive) {
        final monthlyValue = _planEstimate(plan);
        if (monthlyValue <= 0) {
          continue;
        }

        final countryCode = _resolveUserCountryCode(user);
        final countryRate = rateConfig.countryRates[countryCode];
        final appliedRate = countryRate ?? sellerDefaultRate;
        final useFixedMode = rateConfig.payoutMode == 'fixed_gbp_per_plan';
        final fixedPayout = _fixedPayoutForPlan(plan, rateConfig);

        if (start == null || end == null) {
          paidMonthlyCount++;
          grossEstimate += monthlyValue;
          residualEstimate += useFixedMode
              ? fixedPayout
              : (monthlyValue * appliedRate);
        } else if (renewalDate != null) {
          final inRange = !renewalDate.isBefore(start) &&
              !renewalDate.isAfter(end.add(const Duration(days: 1)));
          if (inRange) {
            paidMonthlyCount++;
            grossEstimate += monthlyValue;
            residualEstimate += useFixedMode
                ? fixedPayout
                : (monthlyValue * appliedRate);
          }
        }
      }
    }

    final rate = grossEstimate > 0
        ? (residualEstimate / grossEstimate)
        : sellerDefaultRate;

    return {
      'totalAttributedUsers': sellerUsers.length,
      'activeSubscribers': activeSubscribers,
      'willRenewCount': willRenewCount,
      'paidMonthlyCount': paidMonthlyCount,
      'grossEstimate': grossEstimate,
      'rate': rate,
      'residualEstimate': residualEstimate,
      'payoutMode': rateConfig.payoutMode,
    };
  }

  Future<_RateConfig> _loadRateConfig() async {
    final globalSnap = await FirebaseFirestore.instance
        .collection('seller_commission_settings')
        .doc('global')
        .get();
    final globalData = globalSnap.data() ?? {};
    final globalDefaultRate = (globalData['defaultRate'] as num?)?.toDouble() ?? 0.10;
    final payoutMode = (globalData['payoutMode'] as String?)
        ?.trim()
        .toLowerCase() ==
      'fixed_gbp_per_plan'
      ? 'fixed_gbp_per_plan'
      : 'percentage';
    final fixedStarterGbp =
      (globalData['fixedStarterGbp'] as num?)?.toDouble() ?? 0.50;
    final fixedHarmony100Gbp =
      (globalData['fixedHarmony100Gbp'] as num?)?.toDouble() ?? 0.80;

    final countrySnap = await FirebaseFirestore.instance
        .collection('seller_country_rates')
        .get();
    final countryRates = <String, double>{};
    for (final doc in countrySnap.docs) {
      final data = doc.data();
      final countryCode = ((data['countryCode'] ?? doc.id).toString()).trim().toUpperCase();
      final rate = (data['rate'] as num?)?.toDouble();
      if (countryCode.isNotEmpty && rate != null && rate >= 0 && rate <= 1) {
        countryRates[countryCode] = rate;
      }
    }

    return _RateConfig(
      globalDefaultRate: globalDefaultRate,
      countryRates: countryRates,
      payoutMode: payoutMode,
      fixedStarterGbp: fixedStarterGbp,
      fixedHarmony100Gbp: fixedHarmony100Gbp,
    );
  }

  double _fixedPayoutForPlan(String plan, _RateConfig config) {
    if (plan.contains('harmony 100')) return config.fixedHarmony100Gbp;
    if (plan.contains('starter')) return config.fixedStarterGbp;
    return 0;
  }

  String _resolveUserCountryCode(Map<String, dynamic> userData) {
    final cc = (userData['countryCode'] ?? userData['country'] ?? '').toString().trim().toUpperCase();
    return cc.length >= 2 ? cc : 'GB';
  }

  DateTime? _asDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  double _planEstimate(String plan) {
    if (plan.contains('harmony 100')) return 4.99;
    if (plan.contains('starter')) return 2.99;
    return 0;
  }

  String _fmtMoney(num value) => value.toStringAsFixed(2);

  String _fmtRate(num value) => '${(value * 100).toStringAsFixed(2)}%';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('sellers').snapshots(),
      builder: (context, sellerSnapshot) {
        final sellerDocs = sellerSnapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        final countries = <String>{'ALL'};
        for (final doc in sellerDocs) {
          final code = (doc.data()['country'] ?? '').toString().trim().toUpperCase();
          if (code.isNotEmpty) countries.add(code);
        }

        final normalizedSearch = _searchController.text.trim().toLowerCase();

        final filtered = sellerDocs.where((doc) {
          final data = doc.data();
          final country = (data['country'] ?? '').toString().trim().toUpperCase();
          if (_selectedCountryFilter != 'ALL' && country != _selectedCountryFilter) {
            return false;
          }

          if (normalizedSearch.isEmpty) return true;

          final name = (data['name'] ?? '').toString().toLowerCase();
          final email = (data['email'] ?? '').toString().toLowerCase();
          final phone = (data['phone'] ?? '').toString().toLowerCase();
          return name.contains(normalizedSearch) ||
              email.contains(normalizedSearch) ||
              phone.contains(normalizedSearch);
        }).toList()
          ..sort((a, b) {
            final aName = (a.data()['name'] ?? '').toString().toLowerCase();
            final bName = (b.data()['name'] ?? '').toString().toLowerCase();
            return aName.compareTo(bName);
          });

        final monthKey = _currentMonthKey();

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('fx_rates')
              .doc('live_reference')
              .snapshots(),
          builder: (context, liveFxSnapshot) {
            final liveFxData = liveFxSnapshot.data?.data();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('fx_rates_monthly')
                  .doc(monthKey)
                  .snapshots(),
              builder: (context, monthFxSnapshot) {
                final monthlyFxData = monthFxSnapshot.data?.data();

                return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildHeader(
                countries.toList()..sort(),
                liveFxData,
                monthlyFxData,
                monthKey,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildSellerList(filtered)),
                    const SizedBox(width: 12),
                    Expanded(flex: 4, child: _buildSellerEditor()),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 5,
                      child: _buildMetricsPanel(
                        filtered,
                        liveFxData,
                        monthlyFxData,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHeader(
    List<String> countries,
    Map<String, dynamic>? liveFxData,
    Map<String, dynamic>? monthlyFxData,
    String monthKey,
  ) {
    final liveUpdated = _asDate(liveFxData?['updatedAt']);
    final snapshotLocked = _asDate(monthlyFxData?['lockedAt']);
    final hasSnapshot = snapshotLocked != null;
    final hasLive = liveUpdated != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              runSpacing: 10,
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  'Seller Management',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                SizedBox(
                  width: 220,
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Search sellers',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: countries.contains(_selectedCountryFilter)
                        ? _selectedCountryFilter
                        : 'ALL',
                    items: countries
                        .map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedCountryFilter = v);
                    },
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Country',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _pickDateRange,
                  icon: const Icon(Icons.date_range),
                  label: Text(
                    _dateRange == null
                        ? 'All Dates'
                        : '${_dateRange!.start.year}-${_dateRange!.start.month.toString().padLeft(2, '0')}-${_dateRange!.start.day.toString().padLeft(2, '0')} to ${_dateRange!.end.year}-${_dateRange!.end.month.toString().padLeft(2, '0')}-${_dateRange!.end.day.toString().padLeft(2, '0')}',
                  ),
                ),
                OutlinedButton(
                  onPressed: () => _setAllSellersActive(true),
                  child: const Text('Activate All'),
                ),
                OutlinedButton(
                  onPressed: () => _setAllSellersActive(false),
                  child: const Text('Deactivate All'),
                ),
                OutlinedButton.icon(
                  onPressed: _refreshingFx ? null : _refreshLiveFxRates,
                  icon: const Icon(Icons.sync),
                  label: Text(_refreshingFx ? 'Refreshing FX...' : 'Refresh Live FX'),
                ),
                OutlinedButton.icon(
                  onPressed: _lockingFx ? null : _lockCurrentMonthFxSnapshot,
                  icon: const Icon(Icons.lock_clock),
                  label: Text(_lockingFx ? 'Locking...' : 'Lock $monthKey Snapshot'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F8FC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDCE3F0)),
              ),
              child: Wrap(
                runSpacing: 10,
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasLive ? Icons.check_circle : Icons.error_outline,
                        color: hasLive ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Live FX Updated: ${_formatShortStamp(liveUpdated)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasSnapshot ? Icons.lock : Icons.warning_amber,
                        color: hasSnapshot ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$monthKey Snapshot: ${hasSnapshot ? 'Locked' : 'Missing'}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Text(
                    hasSnapshot
                        ? 'Payout conversions use locked monthly rates first. GBP remains your canonical admin reference.'
                        : 'No monthly lock yet. Conversions currently use live FX fallback. GBP remains your canonical admin reference.',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return Card(
      child: Column(
        children: [
          const ListTile(
            dense: true,
            title: Text('Sellers'),
            subtitle: Text('Tap a seller to edit, inspect codes and metrics.'),
          ),
          const Divider(height: 1),
          Expanded(
            child: Scrollbar(
              controller: _sellerListScroll,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _sellerListScroll,
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final sellerId = doc.id;
                  final active = data['isActive'] != false;
                  final name = (data['name'] ?? '').toString();
                  final email = (data['email'] ?? '').toString();
                  final country = (data['country'] ?? '—').toString();

                  return ListTile(
                    selected: _selectedSellerId == sellerId,
                    onTap: () => _loadSeller(data, sellerId),
                    title: Text(name.isEmpty ? 'Unnamed seller' : name),
                    subtitle: Text('$email • $country'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: active,
                          onChanged: (v) => _setSellerActive(sellerId, v),
                        ),
                        IconButton(
                          tooltip: 'Delete seller',
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete seller?'),
                                    content: const Text(
                                      'This removes the seller and all mapped seller codes.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ) ??
                                false;
                            if (!ok) return;
                            await _deleteSeller(sellerId);
                            if (_selectedSellerId == sellerId) {
                              _clearSellerForm();
                            }
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerEditor() {
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Seller Profile',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Seller Name',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Email',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Contact Number',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _countryController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Country Code',
                hintText: 'GB',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _payoutCurrencyController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [LengthLimitingTextInputFormatter(3)],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Payout Currency (ISO)',
                hintText: 'GBP',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _defaultRateController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Default Seller Rate (0.00 to 1.00)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Notes',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _isSellerActive,
              onChanged: (v) => setState(() => _isSellerActive = v),
              title: const Text('Seller Active'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _savingSeller ? null : _saveSeller,
                  icon: const Icon(Icons.save),
                  label: Text(_savingSeller ? 'Saving...' : 'Save Seller'),
                ),
                OutlinedButton.icon(
                  onPressed: _clearSellerForm,
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text(
              'Seller Codes',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeSellerIdController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Seller Doc ID',
              ),
              readOnly: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _codeController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Code (leave blank to auto-generate)',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _savingCode ? null : _saveSellerCode,
              icon: const Icon(Icons.vpn_key),
              label:
                  Text(_savingCode ? 'Saving...' : 'Create / Attach Seller Code'),
            ),
            const SizedBox(height: 8),
            _buildSellerCodeList(),
            const Divider(height: 24),
            const Text(
              'Rates',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _payoutMode,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Payout Mode',
              ),
              items: const [
                DropdownMenuItem(
                  value: 'percentage',
                  child: Text('Percentage (default/country rates)'),
                ),
                DropdownMenuItem(
                  value: 'fixed_gbp_per_plan',
                  child: Text('Fixed GBP per plan (Starter/Harmony 100)'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _payoutMode = value);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _globalRateController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Global Default Rate (0.00 to 1.00)',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fixedStarterPayoutController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Fixed Starter GBP',
                      hintText: '0.50',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fixedHarmony100PayoutController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Fixed Harmony 100 GBP',
                      hintText: '0.80',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _payoutMode == 'fixed_gbp_per_plan'
                  ? 'Fixed mode active: country percentage rates are ignored for payouts. GBP fixed amounts are used per paid plan.'
                  : 'Percentage mode active: global/country rates are used. Fixed GBP fields are saved but not applied.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _savingRate || _loadingRateSettings ? null : _saveGlobalRate,
              child: Text(_savingRate ? 'Saving...' : 'Save Global Payout Settings'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _countryRateCodeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Country Code',
                      hintText: 'US',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _countryRateController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Country Rate',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Country Rate is a percentage override (for example 0.40 = 40%). FX conversion appears in totals, not in this field.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _savingRate ? null : _saveCountryRate,
              child: const Text('Save Country Rate'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerCodeList() {
    final sellerId = _codeSellerIdController.text.trim();
    if (sellerId.isEmpty) {
      return const Text('Select a seller to view or manage codes.');
    }

    return SizedBox(
      height: 180,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('seller_codes')
            .where('sellerId', isEqualTo: sellerId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No seller codes yet.'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final code = (data['code'] ?? '').toString();
              final active = data['isActive'] != false;

              return ListTile(
                dense: true,
                title: Text(code),
                subtitle: Text(active ? 'Active' : 'Inactive'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: active,
                      onChanged: (v) => _setSellerCodeActive(doc.id, v),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: code));
                        _snack('Copied: $code');
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _deleteSellerCode(doc.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMetricsPanel(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sellers,
    Map<String, dynamic>? liveFxData,
    Map<String, dynamic>? monthlyFxData,
  ) {
    final liveRates = _extractRates(liveFxData);
    final monthlyRates = _extractRates(monthlyFxData);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Residual Metrics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Live seller totals from users collection. Sterling is always shown, with local-currency conversion using monthly FX snapshot first and live FX as fallback.',
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<_RateConfig>(
                future: _loadRateConfig(),
                builder: (context, rateSnap) {
                  if (!rateSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final rateConfig = rateSnap.data!;

                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance.collection('users').snapshots(),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final users = userSnapshot.data!.docs
                          .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
                          .toList();

                      return Scrollbar(
                        controller: _metricsScroll,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _metricsScroll,
                          itemCount: sellers.length,
                          itemBuilder: (context, index) {
                            final sellerDoc = sellers[index];
                            final data = sellerDoc.data();
                            final sellerId = sellerDoc.id;
                            final sellerName = (data['name'] ?? 'Unnamed').toString();
                            final sellerCurrency = _sellerCurrencyFromData(data);
                            final rate = (data['defaultRate'] as num?)?.toDouble() ??
                                rateConfig.globalDefaultRate;

                            return FutureBuilder<Map<String, dynamic>>(
                              future: _computeMetricsForSeller(
                                sellerId,
                                users,
                                rateConfig,
                                data,
                              ),
                              builder: (context, snap) {
                                final metrics = snap.data;
                                if (metrics == null) {
                                  return const Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: LinearProgressIndicator(),
                                    ),
                                  );
                                }

                                final totalAttributed =
                                    (metrics['totalAttributedUsers'] as int?) ?? 0;
                                final activeSubscribers =
                                    (metrics['activeSubscribers'] as int?) ?? 0;
                                final willRenewCount =
                                    (metrics['willRenewCount'] as int?) ?? 0;
                                final paidMonthlyCount =
                                    (metrics['paidMonthlyCount'] as int?) ?? 0;
                                final grossEstimate =
                                    (metrics['grossEstimate'] as num?) ?? 0;
                                final rateApplied =
                                    (metrics['rate'] as num?) ?? rate;
                                final residualEstimate =
                                    (metrics['residualEstimate'] as num?) ?? 0;
                                final payoutMode =
                                  (metrics['payoutMode'] as String?) ??
                                    'percentage';
                                final fxRate = _gbpToCurrencyRate(
                                  sellerCurrency,
                                  monthlyRates,
                                  liveRates,
                                );
                                final localGross = grossEstimate * fxRate;
                                final localResidual = residualEstimate * fxRate;

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sellerName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            _chip('Attributed', '$totalAttributed'),
                                            _chip('Active', '$activeSubscribers'),
                                            _chip('Will Renew', '$willRenewCount'),
                                            _chip('Paid Monthly', '$paidMonthlyCount'),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          payoutMode == 'fixed_gbp_per_plan'
                                              ? 'Effective Rate (from fixed GBP): ${_fmtRate(rateApplied)}'
                                              : 'Rate: ${_fmtRate(rateApplied)}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          'Gross Estimate: £${_fmtMoney(grossEstimate)}',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        Text(
                                          'Residual Estimate: £${_fmtMoney(residualEstimate)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        if (sellerCurrency != 'GBP') ...[
                                          Text(
                                            'Gross Estimate (${sellerCurrency}): ${_formatAmount(sellerCurrency, localGross)}',
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                          Text(
                                            'Residual Estimate (${sellerCurrency}): ${_formatAmount(sellerCurrency, localResidual)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.green,
                                            ),
                                          ),
                                          Text(
                                            'FX used: 1 GBP = ${fxRate.toStringAsFixed(4)} $sellerCurrency',
                                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.end,
                                          children: [
                                            TextButton.icon(
                                              onPressed: () {
                                                final report = {
                                                  'sellerId': sellerId,
                                                  'sellerName': sellerName,
                                                  'dateRange': _dateRange == null
                                                      ? 'all'
                                                      : '${_dateRange!.start.toIso8601String()}..${_dateRange!.end.toIso8601String()}',
                                                  'metrics': {
                                                    'totalAttributedUsers': totalAttributed,
                                                    'activeSubscribers': activeSubscribers,
                                                    'willRenewCount': willRenewCount,
                                                    'paidMonthlyCount': paidMonthlyCount,
                                                    'rateApplied': rateApplied,
                                                    'grossEstimate': grossEstimate,
                                                    'residualEstimate': residualEstimate,
                                                    'sellerCurrency': sellerCurrency,
                                                    'gbpToSellerCurrencyFx': fxRate,
                                                    'grossEstimateSellerCurrency': localGross,
                                                    'residualEstimateSellerCurrency': localResidual,
                                                  }
                                                };
                                                Clipboard.setData(
                                                  ClipboardData(
                                                    text: const JsonEncoder.withIndent('  ')
                                                        .convert(report),
                                                  ),
                                                );
                                                _snack('Seller report JSON copied for export/print.');
                                              },
                                              icon: const Icon(Icons.copy),
                                              label: const Text('Copy Report JSON'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value'),
    );
  }
}
