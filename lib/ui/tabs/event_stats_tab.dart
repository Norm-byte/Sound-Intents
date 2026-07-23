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
  bool _showLiveStats = false;
  bool _showCommunityLiveCounter = false;
  bool _overlayShowTimezoneFlags = false;
  bool _communityShowTimezoneFlags = false;

  @override
  void initState() {
    super.initState();
    _loadStatsSettings();
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
        // Always include dormant override viewers when overlay is enabled.
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
