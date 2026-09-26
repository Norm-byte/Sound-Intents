import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../../models/media_item.dart';
import '../../services/media_library_service.dart';
import '../widgets/video_widgets.dart';

class LivingCanvasStudioTab extends StatefulWidget {
  const LivingCanvasStudioTab({super.key});

  @override
  State<LivingCanvasStudioTab> createState() => _LivingCanvasStudioTabState();
}

class _LivingCanvasStudioTabState extends State<LivingCanvasStudioTab> {
  final MediaLibraryService _mediaLibrary = MediaLibraryService();
  final ScrollController _hourStripController = ScrollController();
  VideoPlayerController? _audioPreviewController;

  bool _loading = true;
  bool _saving = false;
  bool _clearing = false;
  bool _clearingLane = false;
  bool _diagnosing = false;
  bool _auditing = false;
  bool _publishing = false;
  bool _audioPreviewPlaying = false;
  bool _mutingVideoAudio = false;
  bool _backgroundPreviewPlaying = true;
  final GlobalKey<_UnmutedVideoPreviewState> _backgroundPreviewKey = GlobalKey();
  bool _globalThumbprintModeActive = false;
  int _lane = 0;
  int _hour = 12;

  bool _showPin = false;
  bool _showGoodometer = false;
  bool _showDateTime = false;
  String _canvasScope = 'national';
  String _selectedTimeZoneLabel = 'UTC';
  int _selectedTimeZoneOffset = 0;
  final _title = TextEditingController();
  final _durationSeconds = TextEditingController(text: '30');
  final _mediaUrl = TextEditingController();
  final _audioUrl = TextEditingController();
  final _glow = TextEditingController(text: 'FFD54F');
  final _pinText = TextEditingController();
  final _thanksTitle = TextEditingController(text: 'Thank you');
  final _thanksBody = TextEditingController(text: 'Your intent has joined this shared moment.');
  final _thankYouDisplaySeconds = TextEditingController(text: '3');

  // Repeating slot records, keyed by '${scope}_${HH}${MM}'. Draft-only until published.
  Map<String, Map<String, dynamic>> _draftDefaults = const {};
  Map<String, Map<String, dynamic>> _liveDefaults = const {};

  final List<Map<String, dynamic>> _timeZones = const [
    {'label': 'UTC', 'offset': 0},
    {'label': 'London (Auto DST)', 'offset': 0},
    {'label': 'Paris (Auto DST)', 'offset': 1},
    {'label': 'New York (Auto DST)', 'offset': -5},
    {'label': 'Los Angeles (Auto DST)', 'offset': -8},
    {'label': 'Tokyo (JST)', 'offset': 9},
    {'label': 'Sydney (Auto DST)', 'offset': 10},
  ];

  String get _selectedDefaultKey =>
      '${_canvasScope}_${_hour.toString().padLeft(2, '0')}${_lane.toString().padLeft(2, '0')}';

  String _normalizeTimeZoneLabel(String? rawLabel) {
    final label = (rawLabel ?? 'UTC').trim();
    switch (label) {
      case 'London (GMT)':
      case 'London (BST)':
      case 'London (Auto DST)':
        return 'London (Auto DST)';
      case 'Paris (CET)':
      case 'Paris (CEST)':
      case 'Paris (Auto DST)':
        return 'Paris (Auto DST)';
      case 'New York (EST)':
      case 'New York (EDT)':
      case 'New York (Auto DST)':
        return 'New York (Auto DST)';
      case 'Los Angeles (PST)':
      case 'Los Angeles (PDT)':
      case 'Los Angeles (Auto DST)':
        return 'Los Angeles (Auto DST)';
      case 'Sydney (AEST)':
      case 'Sydney (AEDT)':
      case 'Sydney (Auto DST)':
        return 'Sydney (Auto DST)';
      default:
        return label;
    }
  }

  DateTime _lastSundayOfMonth(int year, int month) {
    final firstOfNextMonth = month == 12
        ? DateTime(year + 1, 1, 1)
        : DateTime(year, month + 1, 1);
    final lastOfMonth = firstOfNextMonth.subtract(const Duration(days: 1));
    return lastOfMonth.subtract(Duration(days: lastOfMonth.weekday % 7));
  }

  DateTime _nthSundayOfMonth(int year, int month, int n) {
    final firstDay = DateTime(year, month, 1);
    final daysUntilSunday = (DateTime.sunday - firstDay.weekday + 7) % 7;
    return firstDay.add(Duration(days: daysUntilSunday + ((n - 1) * 7)));
  }

  bool _isEuropeDst(DateTime date) {
    final start = _lastSundayOfMonth(date.year, 3);
    final end = _lastSundayOfMonth(date.year, 10);
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && d.isBefore(end);
  }

  bool _isUsDst(DateTime date) {
    final start = _nthSundayOfMonth(date.year, 3, 2);
    final end = _nthSundayOfMonth(date.year, 11, 1);
    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(start) && d.isBefore(end);
  }

  bool _isSydneyDst(DateTime date) {
    final start = _nthSundayOfMonth(date.year, 10, 1);
    final end = _nthSundayOfMonth(date.year, 4, 1);
    final d = DateTime(date.year, date.month, date.day);
    if (d.month >= 10) return !d.isBefore(start);
    if (d.month <= 4) return d.isBefore(end);
    return false;
  }

  int _offsetForZone(String label, DateTime date) {
    final normalized = _normalizeTimeZoneLabel(label).toLowerCase();
    if (normalized == 'utc') return 0;
    if (normalized.contains('tokyo')) return 9;
    if (normalized.contains('london')) return _isEuropeDst(date) ? 1 : 0;
    if (normalized.contains('paris')) return _isEuropeDst(date) ? 2 : 1;
    if (normalized.contains('new york')) return _isUsDst(date) ? -4 : -5;
    if (normalized.contains('los angeles')) return _isUsDst(date) ? -7 : -8;
    if (normalized.contains('sydney')) return _isSydneyDst(date) ? 11 : 10;
    return 0;
  }

  DateTime _slotStartUtc() {
    final now = DateTime.now();
    if (_canvasScope == 'international') {
      final originDateTime = DateTime.utc(now.year, now.month, now.day, _hour, _lane);
      return originDateTime.subtract(Duration(hours: _selectedTimeZoneOffset));
    }
    return DateTime(now.year, now.month, now.day, _hour, _lane).toUtc();
  }

  String _formatUtcPreview(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm').format(dt);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _hourStripController.dispose();
    _audioPreviewController?.dispose();
    for (final c in [_title, _durationSeconds, _mediaUrl, _audioUrl, _glow, _pinText, _thanksTitle, _thanksBody, _thankYouDisplaySeconds]) {
      c.dispose();
    }
    super.dispose();
  }

  void _scrollHours(int direction) {
    if (!_hourStripController.hasClients) return;
    final position = _hourStripController.position;
    final target = (_hourStripController.offset + (direction * 280))
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _hourStripController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _scrollToHour(int hour) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hourStripController.hasClients) return;
      final position = _hourStripController.position;
      final target = (hour * 66.0 - 132)
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _hourStripController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _toggleAudioPreview() async {
    final url = _audioUrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose event audio first')),
      );
      return;
    }

    if (_audioPreviewPlaying) {
      await _audioPreviewController?.pause();
      if (mounted) setState(() => _audioPreviewPlaying = false);
      return;
    }

    await _audioPreviewController?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      _audioPreviewController = controller;
      if (mounted) setState(() => _audioPreviewPlaying = true);
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not preview audio: $e')),
      );
    }
  }

  Future<void> _muteBackgroundVideoAudio() async {
    final url = _mediaUrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a background video first')),
      );
      return;
    }

    setState(() => _mutingVideoAudio = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('stripThumbprintVideoAudio')
          .call({'mediaUrl': url});
      final mutedUrl = (result.data as Map)['mutedUrl'] as String?;
      if (mutedUrl == null || mutedUrl.isEmpty) {
        throw Exception('No muted video URL returned');
      }
      setState(() => _mediaUrl.text = mutedUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Background video audio removed. A silent copy is now set.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mute background video audio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _mutingVideoAudio = false);
    }
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await _loadDefaults();
      _loadSelectedSlot();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load Living Canvas data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDefaults() async {
    final doc = await FirebaseFirestore.instance.collection('app_config').doc('living_canvas').get();
    final data = doc.data() ?? const <String, dynamic>{};
    _globalThumbprintModeActive = data['isThumbprintModeActive'] == true;
    _liveDefaults = (data['repeatingDefaults'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key as String, Map<String, dynamic>.from(value as Map)),
    );
    _draftDefaults = (data['repeatingDraftDefaults'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key as String, Map<String, dynamic>.from(value as Map)),
    );
  }

  void _loadSelectedSlot() {
    final key = _selectedDefaultKey;
    final data = _draftDefaults[key] ?? _liveDefaults[key];
    _apply(data ?? const <String, dynamic>{});
  }

  void _apply(Map<String, dynamic> data) {
    _showPin = data['showPinCard'] == true;
    _showGoodometer = data['showGoodometerGraph'] == true;
    _showDateTime = data['showDateTime'] == true;
    _canvasScope = (data['canvasScope'] as String?) ?? _canvasScope;
    _selectedTimeZoneLabel = _normalizeTimeZoneLabel(data['originTimeZone'] as String?);
    _selectedTimeZoneOffset = _offsetForZone(_selectedTimeZoneLabel, DateTime.now());
    _title.text = (data['title'] as String?) ?? '';
    _durationSeconds.text = ((data['durationSeconds'] as num?)?.toInt() ?? (data['durationMinutes'] as num?)?.toInt() ?? 30).toString();
    _mediaUrl.text = (data['mediaUrl'] as String?) ?? (data['backgroundImageUrl'] as String?) ?? (data['backgroundVideoUrl'] as String?) ?? '';
    _audioUrl.text =
      (data['chimeAudioUrl'] as String?) ?? (data['customAudioUrl'] as String?) ?? '';
    _glow.text = (data['thumbprintGlowColor'] as String?) ?? 'FFD54F';
    _pinText.text = (data['pinCardText'] as String?) ?? '';
    _thanksTitle.text = (data['thankYouTitle'] as String?) ?? 'Thank you';
    _thanksBody.text = (data['thankYouBody'] as String?) ?? 'Your intent has joined this shared moment.';
    _thankYouDisplaySeconds.text = ((data['thankYouDisplaySeconds'] as num?)?.toInt() ?? 3).toString();
  }

  Map<String, dynamic> _defaultsPayload() {
    return {
      'canvasScope': _canvasScope,
      'hour': _hour,
      'laneMinute': _lane,
      'originTimeZone': _canvasScope == 'international' ? _selectedTimeZoneLabel : null,
      'originTimeZoneOffset': _canvasScope == 'international' ? _selectedTimeZoneOffset : null,
      'durationSeconds': (int.tryParse(_durationSeconds.text.trim()) ?? 30).clamp(1, 3600),
      'title': _title.text.trim(),
      'mediaUrl': _mediaUrl.text.trim(),
      'backgroundImageUrl': _mediaUrl.text.trim(),
      'audioMode': _audioUrl.text.trim().isEmpty ? 'silent' : 'custom',
      'chimeAudioUrl': _audioUrl.text.trim(),
      'customAudioUrl': _audioUrl.text.trim(),
      'thumbprintGlowColor': _glow.text.trim(),
      'showPinCard': _showPin,
      'pinCardText': _pinText.text.trim(),
      'thankYouTitle': _thanksTitle.text.trim(),
      'thankYouBody': _thanksBody.text.trim(),
      'thankYouDisplaySeconds': (int.tryParse(_thankYouDisplaySeconds.text.trim()) ?? 3).clamp(1, 60),
      'showGoodometerGraph': _showGoodometer,
      'showDateTime': _showDateTime,
      'updatedAt': DateTime.now().toIso8601String(),
    };
  }

  String? _payloadValidationIssue(Map<String, dynamic> data) {
    final mediaUrl = (data['mediaUrl'] as String? ?? '').trim().toLowerCase();
    final standaloneAudio = (data['chimeAudioUrl'] as String? ?? '').trim();
    final isYoutube = mediaUrl.contains('youtube.com') || mediaUrl.contains('youtu.be');
    final eventSeconds = (data['durationSeconds'] as num?)?.toInt() ?? 30;
    final thankYouSeconds = (data['thankYouDisplaySeconds'] as num?)?.toInt() ?? 3;
    if (isYoutube && standaloneAudio.isNotEmpty) {
      return 'YouTube backgrounds cannot be combined with standalone event audio.';
    }
    if (thankYouSeconds > eventSeconds) {
      return 'Thumbprint + thank-you display time cannot exceed the event duration.';
    }
    return null;
  }

  Future<void> _saveAndRepeat() async {
    final payload = _defaultsPayload();
    final validationIssue = _payloadValidationIssue(payload);
    if (validationIssue != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationIssue)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final configRef = FirebaseFirestore.instance.collection('app_config').doc('living_canvas');
      final existing = await configRef.get();
      final draftDefaults = Map<String, dynamic>.from(
        (existing.data()?['repeatingDraftDefaults'] as Map?) ?? const <String, dynamic>{},
      );
      draftDefaults[_selectedDefaultKey] = payload;
      await configRef.set({
        'repeatingDraftDefaults': draftDefaults,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _loadDefaults();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. Publish to make it repeat daily.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save Thumbprint slot: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearSelectedSlot() async {
    final slotLabel = '${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Thumbprint slot?'),
        content: Text(
          'This removes the $slotLabel repeating draft and published slot. '
          'It will stop repeating until you set it up again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Clear slot'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      final key = _selectedDefaultKey;
      final configRef = FirebaseFirestore.instance.collection('app_config').doc('living_canvas');
      await configRef.update({
        'repeatingDefaults.$key': FieldValue.delete(),
        'repeatingDraftDefaults.$key': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Retire any legacy one-off documents so nothing lingers for this hour/lane.
      final legacyDrafts = await FirebaseFirestore.instance
          .collection('draft_living_canvas_slots')
          .where('canvasScope', isEqualTo: _canvasScope)
          .where('hour', isEqualTo: _hour)
          .where('laneMinute', isEqualTo: _lane)
          .get();
      final legacyPublished = await FirebaseFirestore.instance
          .collection('living_canvas_slots')
          .where('canvasScope', isEqualTo: _canvasScope)
          .where('hour', isEqualTo: _hour)
          .where('laneMinute', isEqualTo: _lane)
          .get();
      if (legacyDrafts.docs.isNotEmpty || legacyPublished.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in legacyDrafts.docs) {
          batch.delete(doc.reference);
        }
        for (final doc in legacyPublished.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      await _loadDefaults();
      _loadSelectedSlot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared Thumbprint slot for $slotLabel')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clear Thumbprint slot: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _diagnoseLane() async {
    setState(() => _diagnosing = true);
    try {
      final configRef = FirebaseFirestore.instance.collection('app_config').doc('living_canvas');
      final config = await configRef.get();
      final liveDefaults = Map<String, dynamic>.from(
        (config.data()?['repeatingDefaults'] as Map?) ?? const <String, dynamic>{},
      );
      final draftDefaults = Map<String, dynamic>.from(
        (config.data()?['repeatingDraftDefaults'] as Map?) ?? const <String, dynamic>{},
      );
      final lanePrefix = '${_canvasScope}_';
      final laneSuffix = _lane.toString().padLeft(2, '0');
      final matchingLive = liveDefaults.keys.where((key) => key.startsWith(lanePrefix) && key.endsWith(laneSuffix)).toList();
      final matchingDraft = draftDefaults.keys.where((key) => key.startsWith(lanePrefix) && key.endsWith(laneSuffix)).toList();

      final legacyDrafts = await FirebaseFirestore.instance
          .collection('draft_living_canvas_slots')
          .where('canvasScope', isEqualTo: _canvasScope)
          .where('laneMinute', isEqualTo: _lane)
          .get();
      final legacyPublished = await FirebaseFirestore.instance
          .collection('living_canvas_slots')
          .where('canvasScope', isEqualTo: _canvasScope)
          .where('laneMinute', isEqualTo: _lane)
          .get();

      final buffer = StringBuffer()
        ..writeln('Scope: $_canvasScope   Lane: :${_lane.toString().padLeft(2, '0')}')
        ..writeln()
        ..writeln('repeatingDefaults keys matching this lane (${matchingLive.length}):')
        ..writeln(matchingLive.isEmpty ? '  (none)' : matchingLive.map((k) => '  $k').join('\n'))
        ..writeln()
        ..writeln('repeatingDraftDefaults keys matching this lane (${matchingDraft.length}):')
        ..writeln(matchingDraft.isEmpty ? '  (none)' : matchingDraft.map((k) => '  $k').join('\n'))
        ..writeln()
        ..writeln('living_canvas_slots docs matching canvasScope+laneMinute (${legacyPublished.docs.length}):')
        ..writeln(legacyPublished.docs.isEmpty
            ? '  (none)'
            : legacyPublished.docs.map((d) => '  id=${d.id} hour=${d.data()['hour']} laneMinute=${d.data()['laneMinute']} (${d.data()['hour'].runtimeType})').join('\n'))
        ..writeln()
        ..writeln('draft_living_canvas_slots docs matching canvasScope+laneMinute (${legacyDrafts.docs.length}):')
        ..writeln(legacyDrafts.docs.isEmpty
            ? '  (none)'
            : legacyDrafts.docs.map((d) => '  id=${d.id} hour=${d.data()['hour']} laneMinute=${d.data()['laneMinute']} (${d.data()['hour'].runtimeType})').join('\n'));

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Lane diagnostic'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(child: SelectableText(buffer.toString())),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Diagnostic failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  Future<void> _auditSlots() async {
    setState(() => _auditing = true);
    try {
      await _loadDefaults();
      final rows = <String>[];
      var issueCount = 0;

      void addRows(String status, Map<String, Map<String, dynamic>> source) {
        final keys = source.keys
            .where((key) => key.startsWith('${_canvasScope}_'))
            .toList()
          ..sort();
        for (final key in keys) {
          final data = source[key]!;
          final mediaUrl = (data['mediaUrl'] as String? ?? '').trim().toLowerCase();
          final audioUrl = (data['chimeAudioUrl'] as String? ?? '').trim();
          final customAudioUrl = (data['customAudioUrl'] as String? ?? '').trim();
          final mediaType = mediaUrl.isEmpty
              ? 'none'
              : mediaUrl.contains('youtube.com') || mediaUrl.contains('youtu.be')
                  ? 'YouTube'
                  : RegExp(r'\.(mp4|mov|webm|m4v|mpeg|mpg|avi|mkv)(?:\?|$)').hasMatch(mediaUrl)
                      ? 'video'
                      : 'image';
          final issues = <String>[
            if (_payloadValidationIssue(data) case final issue?) issue,
            if (audioUrl != customAudioUrl) 'audio URL fields do not match',
            if ((data['audioMode'] == 'silent') && audioUrl.isNotEmpty) 'audioMode is silent but audio URL is set',
            if ((data['audioMode'] == 'custom') && audioUrl.isEmpty) 'audioMode is custom but audio URL is blank',
          ];
          issueCount += issues.length;
          rows.add(
            '$key  $status  media=$mediaType  audio=${audioUrl.isEmpty ? 'embedded/none' : 'standalone'}  '
            'event=${data['durationSeconds'] ?? 30}s  thankYou=${data['thankYouDisplaySeconds'] ?? 3}s'
            '${issues.isEmpty ? '' : '  ISSUE: ${issues.join('; ')}'}',
          );
        }
      }

      addRows('PUBLISHED', _liveDefaults);
      addRows('DRAFT', _draftDefaults);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Thumbprint slot audit — $issueCount issue${issueCount == 1 ? '' : 's'}'),
          content: SizedBox(
            width: 820,
            child: SingleChildScrollView(
              child: SelectableText(rows.isEmpty ? 'No slots found for this scope.' : rows.join('\n')),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Slot audit failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _auditing = false);
    }
  }

  Future<void> _clearLane() async {
    final laneLabel = ':${_lane.toString().padLeft(2, '0')}';
    final scopeLabel = _canvasScope == 'international' ? 'International' : 'National';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all timeslots in this lane?'),
        content: Text(
          'This removes every $scopeLabel hour (00:00-23:00) at the $laneLabel lane, '
          'draft and published, plus their repeating defaults. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Clear all in lane'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _clearingLane = true);
    try {
      final configRef = FirebaseFirestore.instance.collection('app_config').doc('living_canvas');
      final config = await configRef.get();
      final liveDefaults = Map<String, dynamic>.from(
        (config.data()?['repeatingDefaults'] as Map?) ?? const <String, dynamic>{},
      );
      final draftDefaults = Map<String, dynamic>.from(
        (config.data()?['repeatingDraftDefaults'] as Map?) ?? const <String, dynamic>{},
      );
      final lanePrefix = '${_canvasScope}_';
      final laneSuffix = _lane.toString().padLeft(2, '0');
      final keysInLane = {...liveDefaults.keys, ...draftDefaults.keys}.where(
        (key) => key.startsWith(lanePrefix) && key.endsWith(laneSuffix),
      ).toList();
      if (keysInLane.isNotEmpty) {
        final updates = <String, dynamic>{
          for (final key in keysInLane) 'repeatingDefaults.$key': FieldValue.delete(),
          for (final key in keysInLane) 'repeatingDraftDefaults.$key': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        await configRef.update(updates);
      }

      // Retire any legacy one-off documents spanning every hour in this lane.
      final legacyDrafts = await FirebaseFirestore.instance
          .collection('draft_living_canvas_slots')
          .where('canvasScope', isEqualTo: _canvasScope)
          .where('laneMinute', isEqualTo: _lane)
          .get();
      final legacyPublished = await FirebaseFirestore.instance
          .collection('living_canvas_slots')
          .where('canvasScope', isEqualTo: _canvasScope)
          .where('laneMinute', isEqualTo: _lane)
          .get();
      if (legacyDrafts.docs.isNotEmpty || legacyPublished.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in legacyDrafts.docs) {
          batch.delete(doc.reference);
        }
        for (final doc in legacyPublished.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      await _loadDefaults();
      _loadSelectedSlot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared $scopeLabel $laneLabel lane (${keysInLane.length} hour${keysInLane.length == 1 ? '' : 's'})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clear the lane: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearingLane = false);
    }
  }

  Future<void> _publishAll() async {
    setState(() => _publishing = true);
    try {
      final configRef = FirebaseFirestore.instance.collection('app_config').doc('living_canvas');
      final existing = await configRef.get();
      final liveDefaults = Map<String, dynamic>.from(
        (existing.data()?['repeatingDefaults'] as Map?) ?? const <String, dynamic>{},
      );
      final draftDefaults = Map<String, dynamic>.from(
        (existing.data()?['repeatingDraftDefaults'] as Map?) ?? const <String, dynamic>{},
      );
      final scopedKeys = draftDefaults.keys
          .where((key) => key.startsWith('${_canvasScope}_'))
          .toList();
      if (scopedKeys.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No ${_canvasScope == 'international' ? 'International' : 'National'} draft slots to publish.')),
          );
        }
        return;
      }
      for (final key in scopedKeys) {
        final data = Map<String, dynamic>.from(draftDefaults[key] as Map);
        final validationIssue = _payloadValidationIssue(data);
        if (validationIssue != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$key: $validationIssue')),
            );
          }
          return;
        }
      }
      for (final key in scopedKeys) {
        liveDefaults[key] = draftDefaults.remove(key);
      }
      await configRef.set({
        'repeatingDefaults': liveDefaults,
        'repeatingDraftDefaults': draftDefaults,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await _loadDefaults();
      _loadSelectedSlot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Published ${scopedKeys.length} ${_canvasScope == 'international' ? 'International' : 'National'} slot${scopedKeys.length == 1 ? '' : 's'} (repeats daily)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not publish Thumbprint slots: $e')));
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _pickMediaUrl({required Set<String> allowedTypes, required TextEditingController target}) async {
    String? selectedSection;
    final selected = await showDialog<MediaItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            child: SizedBox(
              width: 900,
              height: 700,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          allowedTypes.contains('audio')
                              ? 'Select Event Chime / Audio'
                              : 'Select Background Media',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: StreamBuilder<List<MediaItem>>(
                          stream: _mediaLibrary.getMediaStream(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const LinearProgressIndicator();
                            }
                            final sections = snapshot.data!
                                .map((item) => item.section)
                                .toSet()
                                .toList()
                              ..sort();
                            return DropdownButton<String>(
                              value: selectedSection,
                              hint: const Text('Select Category'),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(value: 'All', child: Text('All Categories')),
                                ...sections.map((section) => DropdownMenuItem(value: section, child: Text(section))),
                              ],
                              onChanged: (value) => setDialogState(() => selectedSection = value),
                            );
                          },
                        ),
                      ),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: selectedSection == null
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.category, size: 60, color: Colors.grey),
                              SizedBox(height: 12),
                              Text('Please select a category from the dropdown above'),
                            ],
                          ),
                        )
                      : StreamBuilder<List<MediaItem>>(
                          stream: _mediaLibrary.getMediaStream(
                            section: selectedSection == 'All' ? null : selectedSection,
                          ),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (snapshot.hasError) {
                              return Center(child: Text('Error: ${snapshot.error}'));
                            }
                            final items = (snapshot.data ?? [])
                                .where((item) => allowedTypes.contains(item.type))
                                .toList();
                            if (items.isEmpty) {
                              return Center(
                                child: Text(
                                  'No matching media found in ${selectedSection == 'All' ? 'library' : selectedSection}.',
                                ),
                              );
                            }
                            return GridView.builder(
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 1.0,
                              ),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final isImage = item.type == 'image';
                                final urlLower = item.url.toLowerCase();
                                final isYoutube = item.type == 'youtube' ||
                                    urlLower.contains('youtube') ||
                                    urlLower.contains('youtu.be');
                                final isVideo = item.type == 'video' || isYoutube;

                                Widget preview;
                                if (isImage) {
                                  preview = Image.network(item.url, fit: BoxFit.cover);
                                } else if (isVideo) {
                                  preview = VideoGridItem(
                                    url: item.url,
                                    type: isYoutube ? 'youtube' : 'upload',
                                    enablePreview: true,
                                    autoPlay: false,
                                  );
                                } else {
                                  preview = const Center(child: Icon(Icons.audiotrack, size: 48));
                                }

                                return InkWell(
                                  onTap: () => Navigator.pop(context, item),
                                  child: Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(child: IgnorePointer(child: preview)),
                                        Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                              Text(
                                                '${item.type} • ${item.section}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
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
        },
      ),
    );
    if (selected == null) return;
    setState(() => target.text = selected.url);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final wide = MediaQuery.of(context).size.width > 1150;
    final editor = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_slotStrip(), const SizedBox(height: 12), _editor()]),
    );
    final preview = _preview();
    return wide
        ? Row(children: [Expanded(flex: 3, child: editor), VerticalDivider(width: 1, color: Colors.grey.shade300), SizedBox(width: 390, child: preview)])
        : Column(children: [Expanded(child: editor), SizedBox(height: 520, child: preview)]);
  }

  Widget _slotStrip() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _globalThumbprintModeActive
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _globalThumbprintModeActive
                      ? Colors.green.shade300
                      : Colors.grey.shade300,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _globalThumbprintModeActive
                        ? Icons.fingerprint
                        : Icons.pause_circle_outline,
                    color: _globalThumbprintModeActive
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _globalThumbprintModeActive
                              ? 'Living Canvas / Thumbprint Mode is ACTIVE'
                              : 'Living Canvas / Thumbprint Mode is OFF',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'When off, the user app keeps the current stable National/International event experience.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _globalThumbprintModeActive,
                    onChanged: (v) async {
                      setState(() => _globalThumbprintModeActive = v);
                      await FirebaseFirestore.instance.collection('app_config').doc('living_canvas').set({
                        'isThumbprintModeActive': v,
                        'updatedAt': FieldValue.serverTimestamp(),
                      }, SetOptions(merge: true));
                    },
                  ),
                ],
              ),
            ),
            Row(children: [
              const Expanded(child: Text('Thumbprint Slots — repeats daily until cleared', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _canvasScope == 'international'
                      ? Colors.purple.withValues(alpha: 0.12)
                      : Colors.indigo.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _canvasScope == 'international' ? 'INTERNATIONAL' : 'NATIONAL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: _canvasScope == 'international'
                        ? Colors.purple.shade800
                        : Colors.indigo.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _diagnosing ? null : _diagnoseLane,
                icon: _diagnosing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.search),
                label: Text(_diagnosing ? 'Checking...' : 'Diagnose lane'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _auditing ? null : _auditSlots,
                icon: _auditing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.fact_check_outlined),
                label: Text(_auditing ? 'Auditing...' : 'Audit slots'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _clearingLane ? null : _clearLane,
                icon: _clearingLane
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.playlist_remove),
                label: Text(_clearingLane ? 'Clearing lane...' : 'Clear all in lane'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(onPressed: _publishing ? null : _publishAll, icon: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.publish), label: Text(_publishing ? 'Publishing...' : 'Publish')),
            ]),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Mode:'),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'national', label: Text('National')),
                    ButtonSegment(value: 'international', label: Text('International')),
                  ],
                  selected: {_canvasScope},
                  onSelectionChanged: (v) {
                    setState(() {
                      _canvasScope = v.first;
                      _selectedTimeZoneOffset = _offsetForZone(_selectedTimeZoneLabel, DateTime.now());
                    });
                    _loadSelectedSlot();
                  },
                ),
                if (_canvasScope == 'international') ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedTimeZoneLabel,
                      decoration: const InputDecoration(
                        labelText: 'Origin Time Zone / Country',
                        isDense: true,
                      ),
                      items: _timeZones
                          .map(
                            (tz) => DropdownMenuItem<String>(
                              value: tz['label'] as String,
                              child: Text((tz['label'] as String), overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedTimeZoneLabel = _normalizeTimeZoneLabel(value);
                          _selectedTimeZoneOffset = _offsetForZone(_selectedTimeZoneLabel, DateTime.now());
                        });
                      },
                    ),
                  ),
                ],
              ],
            ),
            if (_canvasScope == 'international') ...[
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final utcDateTime = _slotStartUtc();
                final londonLocal = utcDateTime.add(Duration(hours: _offsetForZone('London (Auto DST)', DateTime.now())));
                final parisLocal = utcDateTime.add(Duration(hours: _offsetForZone('Paris (Auto DST)', DateTime.now())));
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Text(
                    'UTC stored: ${_formatUtcPreview(utcDateTime)}  |  UK view: ${_formatUtcPreview(londonLocal)}  |  Paris view: ${_formatUtcPreview(parisLocal)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
            ],
            const SizedBox(height: 10),
            SegmentedButton<int>(
              segments: const [ButtonSegment(value: 0, label: Text(':00')), ButtonSegment(value: 15, label: Text(':15')), ButtonSegment(value: 30, label: Text(':30')), ButtonSegment(value: 45, label: Text(':45'))],
              selected: {_lane},
              onSelectionChanged: (v) {
                setState(() => _lane = v.first);
                _loadSelectedSlot();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  tooltip: 'Earlier hours',
                  onPressed: () => _scrollHours(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: ListView.separated(
                      controller: _hourStripController,
                      scrollDirection: Axis.horizontal,
                      itemCount: 24,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (context, hour) {
                    final key = '${_canvasScope}_${hour.toString().padLeft(2, '0')}${_lane.toString().padLeft(2, '0')}';
                    final hasDraft = _draftDefaults.containsKey(key);
                    final hasPublished = _liveDefaults.containsKey(key);
                  final color = hasDraft ? Colors.amber.shade700 : (hasPublished ? Colors.green.shade600 : Colors.grey.shade400);
                  return ChoiceChip(
                    selected: hour == _hour,
                    selectedColor: Colors.indigo.shade100,
                    backgroundColor: color.withValues(alpha: 0.25),
                    avatar: Icon(hasDraft ? Icons.edit : (hasPublished ? Icons.check_circle : Icons.circle_outlined), size: 14, color: color),
                    label: Text('${hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}'),
                    onSelected: (_) {
                      setState(() => _hour = hour);
                      _loadSelectedSlot();
                      _scrollToHour(hour);
                    },
                  );
                },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Later hours',
                  onPressed: () => _scrollHours(1),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
              ),
            const SizedBox(height: 8),
            const Wrap(spacing: 12, children: [_LegendDot(color: Colors.green, label: 'Published'), _LegendDot(color: Colors.amber, label: 'Draft'), _LegendDot(color: Colors.grey, label: 'Empty')]),
          ]),
        ),
      );

  Widget _editor() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Editing ${_canvasScope == 'international' ? 'International' : 'National'} ${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')} (repeats daily)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Canvas title')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show date & time on screen'),
              subtitle: const Text('Independent of the title; can be shown with or without one.'),
              value: _showDateTime,
              onChanged: (v) => setState(() => _showDateTime = v),
            ),
            TextField(controller: _durationSeconds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration (Seconds)', helperText: 'Enter exact seconds (e.g. 10), matching the current event editors')),
            Row(children: [
              Expanded(child: TextField(controller: _mediaUrl, decoration: const InputDecoration(labelText: 'Background image/video URL'))),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                onPressed: () => _pickMediaUrl(allowedTypes: {'image', 'video', 'youtube'}, target: _mediaUrl),
                icon: const Icon(Icons.perm_media, size: 18),
                label: const Text('Media'),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                onPressed: _mutingVideoAudio ? null : _muteBackgroundVideoAudio,
                icon: _mutingVideoAudio
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.volume_off, size: 18),
                label: Text(_mutingVideoAudio ? 'Muting...' : 'Mute audio'),
              ),
              const SizedBox(width: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                onPressed: () => _backgroundPreviewKey.currentState?.togglePlayback(),
                icon: Icon(_backgroundPreviewPlaying ? Icons.pause : Icons.play_arrow, size: 18),
                label: Text(_backgroundPreviewPlaying ? 'Pause' : 'Play'),
              ),
              IconButton(
                tooltip: 'Remove background media',
                onPressed: () => setState(() => _mediaUrl.clear()),
                icon: const Icon(Icons.clear),
              ),
            ]),
            Row(children: [
              Expanded(child: TextField(controller: _audioUrl, decoration: const InputDecoration(labelText: 'Event audio / chime URL'))),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickMediaUrl(allowedTypes: {'audio'}, target: _audioUrl),
                icon: const Icon(Icons.library_music),
                label: const Text('Media Library'),
              ),
              IconButton(
                tooltip: _audioPreviewPlaying ? 'Stop audio preview' : 'Preview audio',
                onPressed: _toggleAudioPreview,
                icon: Icon(_audioPreviewPlaying ? Icons.stop_circle : Icons.play_circle),
              ),
              IconButton(
                tooltip: 'Remove event audio',
                onPressed: () async {
                  await _audioPreviewController?.pause();
                  if (mounted) {
                    setState(() {
                      _audioPreviewPlaying = false;
                      _audioUrl.clear();
                    });
                  }
                },
                icon: const Icon(Icons.clear),
              ),
            ]),
            TextField(controller: _glow, decoration: const InputDecoration(labelText: 'Thumbprint glow color (hex)')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final swatch in const ['FFD54F', '4FC3F7', '81C784', 'CE93D8', 'FF8A65', 'FFFFFF'])
                  InkWell(
                    onTap: () => setState(() => _glow.text = swatch),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _hex(swatch) ?? Colors.amber,
                        border: Border.all(color: Colors.black26),
                      ),
                    ),
                  ),
              ],
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Preview tap popup card'), subtitle: const Text('User will see this popup after tapping the thumbprint.'), value: _showPin, onChanged: (v) => setState(() => _showPin = v)),
            TextField(controller: _pinText, maxLines: 3, decoration: const InputDecoration(labelText: 'Tap popup text')),
            TextField(controller: _thanksTitle, decoration: const InputDecoration(labelText: 'Thank-you title')),
            TextField(controller: _thanksBody, maxLines: 3, decoration: const InputDecoration(labelText: 'Thank-you body')),
            TextField(
              controller: _thankYouDisplaySeconds,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Thumbprint + thank-you display (seconds)',
                helperText: 'After a tap, both disappear together; background media continues.',
              ),
            ),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show Goodometer graph'), subtitle: const Text('National view shows National; World view will include World + National when built.'), value: _showGoodometer, onChanged: (v) => setState(() => _showGoodometer = v)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(onPressed: _saving ? null : _saveAndRepeat, icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: Text(_saving ? 'Saving...' : 'Save & Repeat Daily')),
              OutlinedButton.icon(onPressed: _clearing ? null : _clearSelectedSlot, icon: _clearing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline), label: Text(_clearing ? 'Clearing...' : 'Clear slot')),
            ]),
          ]),
        ),
      );

  Widget _preview() => AnimatedBuilder(
    animation: Listenable.merge([
      _title,
      _mediaUrl,
      _glow,
      _pinText,
      _thanksTitle,
      _thanksBody,
    ]),
    builder: (context, _) => _previewContent(),
  );

  Widget _previewContent() {
    final glow = _hex(_glow.text) ?? Colors.amber;
    final mediaUrl = _mediaUrl.text.trim();
    final popupBody = _pinText.text.trim().isNotEmpty
        ? _pinText.text.trim()
        : _thanksBody.text.trim().isNotEmpty
        ? _thanksBody.text.trim()
        : 'Your intent has joined this shared moment.';
    final mediaPath = Uri.tryParse(mediaUrl)?.path.toLowerCase() ?? mediaUrl.toLowerCase().split('?').first;
    final lowerUrl = mediaUrl.toLowerCase();
    final isYoutube = lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be');
    final youtubeId = isYoutube ? _youtubeVideoId(mediaUrl) : null;
    final isVideo = !isYoutube && (
      mediaPath.endsWith('.mp4') ||
      mediaPath.endsWith('.mov') ||
      mediaPath.endsWith('.webm') ||
      mediaPath.endsWith('.m4v') ||
      mediaPath.endsWith('.mpeg') ||
      mediaPath.endsWith('.mpg') ||
      mediaPath.endsWith('.avi') ||
      mediaPath.endsWith('.mkv')
    );
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(18),
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 19,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.black87, width: 8),
              color: const Color(0xFF111827),
              image: mediaUrl.isNotEmpty && !isVideo && !isYoutube ? DecorationImage(image: NetworkImage(mediaUrl), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.28), BlendMode.darken)) : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                if (isYoutube)
                  Positioned.fill(
                    child: YouTubePlayerWidget(videoId: youtubeId ?? ''),
                  )
                else if (isVideo)
                  Positioned.fill(
                    child: _UnmutedVideoPreview(
                      key: _backgroundPreviewKey,
                      url: mediaUrl,
                      onPlaybackChanged: (playing) {
                        if (mounted) setState(() => _backgroundPreviewPlaying = playing);
                      },
                    ),
                  ),
                Positioned(top: 18, left: 16, child: _previewPill('${_canvasScope == 'international' ? 'World' : 'National'} • 128 live')),
                Positioned(top: 18, right: 16, child: _previewPill('Exit Event')),
                if (_title.text.trim().isNotEmpty || _showDateTime)
                  Positioned(top: 54, left: 18, right: 18, child: Column(children: [
                    if (_title.text.trim().isNotEmpty)
                      Text(_title.text.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    if (_showDateTime)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Repeats daily • ${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ),
                  ])),
                if (_showPin)
                  Positioned(
                    left: 18,
                    right: 18,
                    top: 142,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: glow.withValues(alpha: 0.75)),
                        boxShadow: [
                          BoxShadow(color: glow.withValues(alpha: 0.28), blurRadius: 18, spreadRadius: 2),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _thanksTitle.text.trim().isEmpty ? 'Thank you' : _thanksTitle.text.trim(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            popupBody,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                Center(child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: 32, spreadRadius: 12)], border: Border.all(color: glow, width: 2), color: Colors.black.withValues(alpha: 0.24)), child: Icon(Icons.fingerprint, size: 92, color: glow))),
                if (_showGoodometer) Positioned(left: 18, right: 18, bottom: 118, child: Row(children: [Expanded(child: _bar('National', 0.62, Colors.amberAccent)), const SizedBox(width: 8), Expanded(child: _bar('Last high', 0.52, Colors.lightBlueAccent))])),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(String label, double value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)), const SizedBox(height: 4), ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: value, minHeight: 8, color: color, backgroundColor: Colors.white24))]);

  String? _youtubeVideoId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final queryId = uri.queryParameters['v'];
    if (queryId != null && queryId.isNotEmpty) return queryId;
    if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    for (final marker in ['shorts', 'embed', 'v']) {
      final index = uri.pathSegments.indexOf(marker);
      if (index >= 0 && index + 1 < uri.pathSegments.length) {
        return uri.pathSegments[index + 1];
      }
    }
    return null;
  }

  Widget _previewPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 10)),
    );
  }

  Color? _hex(String value) {
    final cleaned = value.trim().replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return null;
    final parsed = int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 10, color: color), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 12))]);
}

// Dedicated Thumbprint background preview: unlike VideoGridItem (shared with
// the Media Library grid, which intentionally mutes for thumbnail previews),
// this plays audio so admins can hear whether a raw upload needs muting.
class _UnmutedVideoPreview extends StatefulWidget {
  final String url;
  final ValueChanged<bool>? onPlaybackChanged;

  const _UnmutedVideoPreview({super.key, required this.url, this.onPlaybackChanged});

  @override
  State<_UnmutedVideoPreview> createState() => _UnmutedVideoPreviewState();
}

class _UnmutedVideoPreviewState extends State<_UnmutedVideoPreview> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant _UnmutedVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _init();
  }

  Future<void> _init() async {
    await _controller?.dispose();
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      try {
        await controller.setVolume(1.0);
        await controller.play();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (!controller.value.isPlaying) throw StateError('Unmuted autoplay blocked');
      } catch (_) {
        await controller.setVolume(0);
        await controller.play();
      }
      if (mounted) setState(() {});
      widget.onPlaybackChanged?.call(true);
    } catch (e) {
      debugPrint('Error initializing Thumbprint background preview: $e');
    }
  }

  Future<void> togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      widget.onPlaybackChanged?.call(false);
    } else {
      // A tap is a real user gesture, so audio is guaranteed to be allowed here.
      await controller.setVolume(1.0);
      await controller.play();
      widget.onPlaybackChanged?.call(true);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}