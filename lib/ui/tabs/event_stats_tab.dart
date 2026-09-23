import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:async';

class EventStatsTab extends StatefulWidget {
  const EventStatsTab({super.key});

  @override
  State<EventStatsTab> createState() => _EventStatsTabState();
}

class _EventStatsTabState extends State<EventStatsTab> {
  bool _isSavingOverlay = false;
  bool _isSavingCommunity = false;
  bool _isSavingWorldwideUsers = false;
  bool _isSavingInternationalJoined = false;
  bool _isSavingRegionalUsers = false;
  bool _isSavingEventViewers = false;
  bool _isSavingThumbprints = false;
  bool _showLiveStats = false;
  bool _showCommunityLiveCounter = false;
  bool _overlayShowTimezoneFlags = false;
  bool _communityShowTimezoneFlags = false;
  int _worldwideUserTotal = 0;
  int _internationalJoinedTotal = 0;
  int _eventLiveViewerTotal = 0;
  int _thumbprintTotal = 0;
  int _worldwideUserTotalAdjustment = 0;
  int _internationalJoinedAdjustment = 0;
  Map<String, int> _regionalUserTotals = const {};
  Map<String, int> _regionalUserCountAdjustments = const {};
  String _selectedRegion = 'BST';
  int _eventLiveViewerAdjustment = 0;
  int _thumbprintAdjustment = 0;

  @override
  void initState() {
    super.initState();
    _loadStatsSettings();
    _loadDerivedCounts();
  }

  // Kept separate so a failed live query cannot blank the saved settings.
  Future<void> _loadDerivedCounts() async {
    final now = DateTime.now();
    var nearestInternationalJoined = 0;
    var liveViewers = 0;
    var thumbprints = 0;

    try {
      final globalEvents = await FirebaseFirestore.instance
          .collection('global_events')
          .get();
      var nearestInternationalDistance = const Duration(days: 36500);
      for (final eventDoc in globalEvents.docs) {
        final data = eventDoc.data();
        if (data['isPublished'] != true || data['isDraft'] == true) continue;
        final rawStart = data['startTimeUTC'] ?? data['startTime'];
        final start = rawStart is String ? DateTime.tryParse(rawStart) : null;
        if (start == null) continue;
        final distance = start.difference(now).abs();
        if (distance < nearestInternationalDistance) {
          nearestInternationalDistance = distance;
          nearestInternationalJoined =
              (data['participantCount'] as num?)?.toInt() ?? 0;
        }
      }
    } catch (_) {
      // Leave the joined total at zero when events cannot be read.
    }

    try {
      final eventViewerRoots = await FirebaseFirestore.instance
          .collection('event_live_viewers')
          .get();
      final cutoff =
          Timestamp.fromDate(now.subtract(const Duration(seconds: 15)));
      for (final eventDoc in eventViewerRoots.docs) {
        thumbprints += (eventDoc.data()['thumbprintCount'] as num?)?.toInt() ?? 0;
        final sessions = await eventDoc.reference
            .collection('sessions')
            .where('lastSeenAt', isGreaterThan: cutoff)
            .get();
        liveViewers += sessions.docs
            .where((session) =>
                session.data()['source'] != 'backend_live_counter_bridge_v3')
            .length;
      }
    } catch (_) {
      // Leave the viewer total at zero when sessions cannot be read.
    }

    if (!mounted) return;
    setState(() {
      _internationalJoinedTotal = nearestInternationalJoined;
      _eventLiveViewerTotal = liveViewers;
      _thumbprintTotal = thumbprints;
    });
  }

  Future<void> _loadStatsSettings() async {
    try {
      final homeDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .get();
      final communityDoc = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('community_settings')
        .get();

      if (mounted) {
      final homeData = homeDoc.data() ?? <String, dynamic>{};
      final communityData = communityDoc.data() ?? <String, dynamic>{};
        setState(() {
        _showLiveStats = homeData['showLiveStats'] ?? false;
        _overlayShowTimezoneFlags = homeData['statsShowTimezoneFlags'] == true;
        _worldwideUserTotal =
          (homeData['worldwideUserTotal'] as num?)?.toInt() ?? 0;
        _worldwideUserTotalAdjustment =
          (homeData['worldwideUserTotalAdjustment'] as num?)?.toInt() ?? 0;
        _internationalJoinedAdjustment =
          (homeData['internationalJoinedAdjustment'] as num?)?.toInt() ?? 0;
        _regionalUserTotals = Map<String, int>.fromEntries(
          Map<String, dynamic>.from(
            homeData['regionalUserTotals'] as Map? ?? const <String, dynamic>{},
          ).entries.map((entry) => MapEntry(entry.key, (entry.value as num?)?.toInt() ?? 0)),
        );
        _regionalUserCountAdjustments = Map<String, int>.fromEntries(
          Map<String, dynamic>.from(
            homeData['regionalUserCountAdjustments'] as Map? ?? const <String, dynamic>{},
          ).entries.map((entry) => MapEntry(entry.key, (entry.value as num?)?.toInt() ?? 0)),
        );
        if (!_regionalUserTotals.containsKey(_selectedRegion) &&
            _regionalUserTotals.isNotEmpty) {
          _selectedRegion = _regionalUserTotals.keys.first;
        }
        _eventLiveViewerAdjustment =
          (homeData['eventLiveViewerAdjustment'] as num?)?.toInt() ?? 0;
        _thumbprintAdjustment =
          (homeData['thumbprintCountAdjustment'] as num?)?.toInt() ?? 0;

        if (communityData.containsKey('showCommunityLiveCounter')) {
          _showCommunityLiveCounter = communityData['showCommunityLiveCounter'] == true;
        } else {
          _showCommunityLiveCounter = homeData['showCommunityLiveCounter'] == true;
        }

        if (communityData.containsKey('statsShowTimezoneFlags')) {
          _communityShowTimezoneFlags =
              communityData['statsShowTimezoneFlags'] == true;
        } else {
          _communityShowTimezoneFlags = homeData['statsShowTimezoneFlags'] == true;
        }
        });
      }
    } catch (_) {
      // Keep defaults in preview mode.
    }
  }

  Future<void> _saveOverlaySettings() async {
    setState(() => _isSavingOverlay = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .set({
        'showLiveStats': _showLiveStats,
        'statsOverlayPosition': 'bottom',
        'statsParticipantMetric': 'all_viewers',
        'statsShowTimezoneFlags': _overlayShowTimezoneFlags,
        // Include dormant-active participants in displayed count as requested.
        'statsIncludeDormantOverrides': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Event overlay settings published'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingOverlay = false);
    }
  }

  Future<void> _saveCommunitySettings() async {
    setState(() => _isSavingCommunity = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .set({
        'showCommunityLiveCounter': _showCommunityLiveCounter,
        'statsShowTimezoneFlags': _communityShowTimezoneFlags,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_settings')
          .set({
        'showCommunityLiveCounter': _showCommunityLiveCounter,
        'statsShowTimezoneFlags': _communityShowTimezoneFlags,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Community live counter settings published'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingCommunity = false);
    }
  }

  Future<void> _saveDisplayAddition(
    String field,
    int value,
    void Function(bool) setSaving,
  ) async {
    setSaving(true);
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .set({
        field: value,
        'counterAdjustmentsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Counter display addition published'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setSaving(false);
    }
  }

  Future<void> _saveRegionalDisplayAddition() async {
    setState(() => _isSavingRegionalUsers = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .set({
        'regionalUserCountAdjustments': _regionalUserCountAdjustments,
        'counterAdjustmentsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Regional counter display addition published'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Publish failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingRegionalUsers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Event Stats',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Two focused controls: event overlay and community room live counter.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Event Overlay',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fixed to the current Android-style bottom-left position. Dormant override viewers are always included automatically.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Show Live Stats Overlay'),
                            value: _showLiveStats,
                            onChanged: _isSavingOverlay
                                ? null
                                : (value) => setState(() => _showLiveStats = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _isSavingOverlay ? null : _saveOverlaySettings,
                          icon: const Icon(Icons.publish, size: 16),
                          label: Text(_isSavingOverlay ? 'Publishing...' : 'Publish'),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Flags on Overlay'),
                      subtitle: const Text('Display country flags when available'),
                      value: _overlayShowTimezoneFlags,
                      onChanged: _isSavingOverlay
                          ? null
                          : (value) => setState(() => _overlayShowTimezoneFlags = value),
                    ),
                    const SizedBox(height: 8),
                    const _EventOverlayLiveMonitorCard(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Counter Display Additions',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'True counts remain unchanged. Each plus mock value affects only its matching display.',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    _CounterAdditionRow(
                      label: 'International Users',
                      trueCount: _worldwideUserTotal,
                      trueLabel: 'live accounts',
                      value: _worldwideUserTotalAdjustment,
                      saving: _isSavingWorldwideUsers,
                      onChanged: (value) => setState(
                        () => _worldwideUserTotalAdjustment = value,
                      ),
                      onPublish: () => _saveDisplayAddition(
                        'worldwideUserTotalAdjustment',
                        _worldwideUserTotalAdjustment,
                        (saving) => setState(() => _isSavingWorldwideUsers = saving),
                      ),
                    ),
                    _CounterAdditionRow(
                      label: 'International Joined',
                      trueCount: _internationalJoinedTotal,
                      trueLabel: 'current/upcoming event',
                      value: _internationalJoinedAdjustment,
                      saving: _isSavingInternationalJoined,
                      onChanged: (value) => setState(
                        () => _internationalJoinedAdjustment = value,
                      ),
                      onPublish: () => _saveDisplayAddition(
                        'internationalJoinedAdjustment',
                        _internationalJoinedAdjustment,
                        (saving) => setState(() => _isSavingInternationalJoined = saving),
                      ),
                    ),
                    _CounterAdditionRow(
                      // Rebuild per region so the mock field reloads on switch.
                      key: ValueKey('regional-$_selectedRegion'),
                      label: 'Regional Users',
                      trueCount: _regionalUserTotals[_selectedRegion] ?? 0,
                      trueLabel: _selectedRegion,
                      value: _regionalUserCountAdjustments[_selectedRegion] ?? 0,
                      saving: _isSavingRegionalUsers,
                      onChanged: (value) => setState(
                        () => _regionalUserCountAdjustments = {
                          ..._regionalUserCountAdjustments,
                          _selectedRegion: value,
                        },
                      ),
                      onPublish: _saveRegionalDisplayAddition,
                      leading: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Region',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value:
                                  _regionalUserTotals.containsKey(_selectedRegion)
                                      ? _selectedRegion
                                      : null,
                              isExpanded: true,
                              hint: const Text('Select region'),
                              items: _regionalUserTotals.keys
                                  .map((region) => DropdownMenuItem(
                                        value: region,
                                        child: Text(
                                          '$region · ${regionCountryLabel(region)}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: _isSavingRegionalUsers
                                  ? null
                                  : (region) {
                                      if (region != null) {
                                        setState(() => _selectedRegion = region);
                                      }
                                    },
                            ),
                          ),
                        ),
                      ),
                    ),
                    _CounterAdditionRow(
                      label: 'Live Event Viewers',
                      trueCount: _eventLiveViewerTotal,
                      trueLabel: 'active sessions now',
                      value: _eventLiveViewerAdjustment,
                      saving: _isSavingEventViewers,
                      onChanged: (value) => setState(
                        () => _eventLiveViewerAdjustment = value,
                      ),
                      onPublish: () => _saveDisplayAddition(
                        'eventLiveViewerAdjustment',
                        _eventLiveViewerAdjustment,
                        (saving) => setState(() => _isSavingEventViewers = saving),
                      ),
                    ),
                    _CounterAdditionRow(
                      label: 'Thumbprints',
                      trueCount: _thumbprintTotal,
                      trueLabel: 'thumbprint taps',
                      value: _thumbprintAdjustment,
                      saving: _isSavingThumbprints,
                      onChanged: (value) => setState(
                        () => _thumbprintAdjustment = value,
                      ),
                      onPublish: () => _saveDisplayAddition(
                        'thumbprintCountAdjustment',
                        _thumbprintAdjustment,
                        (saving) => setState(() => _isSavingThumbprints = saving),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Community Room Counter',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Show Community Room Live Counter'),
                            value: _showCommunityLiveCounter,
                            onChanged: _isSavingCommunity
                                ? null
                                : (value) =>
                                    setState(() => _showCommunityLiveCounter = value),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed:
                              _isSavingCommunity ? null : _saveCommunitySettings,
                          icon: const Icon(Icons.publish, size: 16),
                          label:
                              Text(_isSavingCommunity ? 'Publishing...' : 'Publish'),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show Flags in Community Header'),
                      subtitle: const Text('Display active country flags/timezones'),
                      value: _communityShowTimezoneFlags,
                      onChanged: _isSavingCommunity
                          ? null
                          : (value) =>
                              setState(() => _communityShowTimezoneFlags = value),
                    ),
                    const SizedBox(height: 8),
                    const _CommunityRoomLiveMonitorCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Country hints for the timezone codes stored on user accounts.
const Map<String, String> _regionCountryLabels = {
  'GMT': 'UK, Ireland, Portugal, Iceland',
  'BST': 'UK, Ireland',
  'WET': 'Portugal, Canary Islands',
  'WEST': 'Portugal, Canary Islands',
  'CET': 'France, Germany, Spain, Italy, Poland',
  'CEST': 'France, Germany, Spain, Italy, Poland',
  'EET': 'Greece, Finland, Romania, Ukraine',
  'EEST': 'Greece, Finland, Romania, Ukraine',
  'EST': 'US East, Canada East',
  'EDT': 'US East, Canada East',
  'CST': 'US Central, Mexico',
  'CDT': 'US Central, Mexico',
  'MST': 'US Mountain',
  'MDT': 'US Mountain',
  'PST': 'US West, Canada West',
  'PDT': 'US West, Canada West',
  'AEST': 'Australia East',
  'AEDT': 'Australia East',
  'AWST': 'Australia West',
  'NZST': 'New Zealand',
  'NZDT': 'New Zealand',
  'IST': 'India, Sri Lanka',
  'SAST': 'South Africa',
  'JST': 'Japan',
  'KST': 'South Korea',
  'HKT': 'Hong Kong',
  'SGT': 'Singapore',
  'GST': 'UAE, Gulf States',
  'BRT': 'Brazil',
  'UTC': 'Coordinated Universal Time',
  'Unknown': 'Region not yet reported',
};

String regionCountryLabel(String region) =>
    _regionCountryLabels[region.trim().toUpperCase()] ??
    _regionCountryLabels[region.trim()] ??
    'Region unmapped';

class _CounterAdditionRow extends StatefulWidget {
  final String label;
  final int trueCount;
  final String trueLabel;
  final Widget? leading;
  final int value;
  final bool saving;
  final ValueChanged<int> onChanged;
  final VoidCallback onPublish;

  const _CounterAdditionRow({
    super.key,
    required this.label,
    required this.trueCount,
    required this.trueLabel,
    this.leading,
    required this.value,
    required this.saving,
    required this.onChanged,
    required this.onPublish,
  });

  @override
  State<_CounterAdditionRow> createState() => _CounterAdditionRowState();
}

class _CounterAdditionRowState extends State<_CounterAdditionRow> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value.toString());

  @override
  void didUpdateWidget(covariant _CounterAdditionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Show published or region-switched values without interrupting typing.
    final shown = int.tryParse(_controller.text.trim()) ?? 0;
    if (widget.value != shown) {
      _controller.text = widget.value.toString();
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trueDisplay = widget.trueCount.toString();
    final totalDisplay = (widget.trueCount + widget.value).toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label),
                if (widget.leading != null)
                  widget.leading!
                else
                  Text(widget.trueLabel),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: _CounterValueBox(label: 'True', value: trueDisplay),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 108,
            child: TextFormField(
              controller: _controller,
              enabled: !widget.saving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Plus mock',
                border: OutlineInputBorder(),
              ),
              onChanged: (rawValue) {
                final parsed = int.tryParse(rawValue.trim()) ?? 0;
                widget.onChanged(parsed < 0 ? 0 : parsed);
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: _CounterValueBox(label: 'Total', value: totalDisplay),
          ),
          IconButton(
            tooltip: 'Publish this counter addition',
            onPressed: widget.saving ? null : widget.onPublish,
            icon: widget.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish),
          ),
        ],
      ),
    );
  }
}

class _CounterValueBox extends StatelessWidget {
  final String label;
  final String value;

  const _CounterValueBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value),
    );
  }
}

class _EventOverlayLiveMonitorCard extends StatefulWidget {
  const _EventOverlayLiveMonitorCard();

  @override
  State<_EventOverlayLiveMonitorCard> createState() =>
      _EventOverlayLiveMonitorCardState();
}

class _EventOverlayLiveMonitorCardState extends State<_EventOverlayLiveMonitorCard> {
  Timer? _timer;
  int _activeViewers = 0;
  int _activeEvents = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final root = await FirebaseFirestore.instance
          .collection('event_live_viewers')
          .get();

      final cutoff = DateTime.now().subtract(const Duration(seconds: 15));
      int totalViewers = 0;
      int eventsWithViewers = 0;

      for (final eventDoc in root.docs) {
        final sessions = await eventDoc.reference.collection('sessions').get();
        final activeForEvent = sessions.docs.where((s) {
          final ts = s.data()['lastSeenAt'];
          if (ts is! Timestamp) return false;
          return ts.toDate().isAfter(cutoff);
        }).length;

        if (activeForEvent > 0) {
          eventsWithViewers++;
          totalViewers += activeForEvent;
        }
      }

      if (!mounted) return;
      setState(() {
        _activeViewers = totalViewers;
        _activeEvents = eventsWithViewers;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeViewers = 0;
        _activeEvents = 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.query_stats, color: Colors.blueAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loading
                  ? 'Loading live overlay stats...'
                  : 'Live now: $_activeViewers viewers across $_activeEvents active event overlay(s)',
              style: const TextStyle(color: Colors.black87, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Refresh now',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
    );
  }
}

class _CommunityRoomLiveMonitorCard extends StatefulWidget {
  const _CommunityRoomLiveMonitorCard();

  @override
  State<_CommunityRoomLiveMonitorCard> createState() =>
      _CommunityRoomLiveMonitorCardState();
}

class _CommunityRoomLiveMonitorCardState
    extends State<_CommunityRoomLiveMonitorCard> {
  Timer? _timer;
  int _activeUsers = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 15));
      final active = await FirebaseFirestore.instance
          .collection('room_live_presence')
          .doc('community_room')
          .collection('sessions')
          .where('lastSeenAt', isGreaterThan: Timestamp.fromDate(cutoff))
          .get();

      if (!mounted) return;
      setState(() {
        _activeUsers = active.docs.length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activeUsers = 0;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_2, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loading
                  ? 'Loading Community Room live users...'
                  : 'Community Room live now: $_activeUsers user(s)',
              style: const TextStyle(color: Colors.black87, fontSize: 12),
            ),
          ),
          IconButton(
            tooltip: 'Refresh now',
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
    );
  }
}
