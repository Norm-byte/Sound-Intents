import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _publishing = false;
  bool _audioPreviewPlaying = false;
  bool _globalThumbprintModeActive = false;
  DateTime _date = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  int _lane = 0;
  int _hour = 12;

  bool _showPin = false;
  bool _showGoodometer = false;
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

  Map<String, Map<String, dynamic>> _drafts = const {};
  Map<String, Map<String, dynamic>> _published = const {};

  static const Set<String> _slotComparisonFields = {
    'slotId',
    'canvasScope',
    'dateKey',
    'weekKey',
    'startTimeUTC',
    'originTimeZone',
    'originTimeZoneOffset',
    'originLocalDateTime',
    'hour',
    'laneMinute',
    'durationSeconds',
    'title',
    'mediaUrl',
    'backgroundImageUrl',
    'audioMode',
    'chimeAudioUrl',
    'customAudioUrl',
    'thumbprintGlowColor',
    'showPinCard',
    'pinCardText',
    'thankYouTitle',
    'thankYouBody',
    'showGoodometerGraph',
  };

  final List<Map<String, dynamic>> _timeZones = const [
    {'label': 'UTC', 'offset': 0},
    {'label': 'London (Auto DST)', 'offset': 0},
    {'label': 'Paris (Auto DST)', 'offset': 1},
    {'label': 'New York (Auto DST)', 'offset': -5},
    {'label': 'Los Angeles (Auto DST)', 'offset': -8},
    {'label': 'Tokyo (JST)', 'offset': 9},
    {'label': 'Sydney (Auto DST)', 'offset': 10},
  ];

  String get _dateKey => DateFormat('yyyyMMdd').format(_date);
  DateTime get _weekStart => _date.subtract(Duration(days: _date.weekday - DateTime.monday));
  DateTime get _weekEndExclusive => _weekStart.add(const Duration(days: 7));
  String get _weekKey => DateFormat('yyyyMMdd').format(_weekStart);
  String _slotId(int hour, int lane) => 'lc_${_canvasScope}_${hour.toString().padLeft(2, '0')}${lane.toString().padLeft(2, '0')}_$_dateKey';
  String get _selectedSlotId => _slotId(_hour, _lane);

  String? get _existingSelectedSlotId {
    for (final entry in {..._published, ..._drafts}.entries) {
      final data = entry.value;
      if ((data['hour'] as num?)?.toInt() == _hour &&
          (data['laneMinute'] as num?)?.toInt() == _lane) {
        return entry.key;
      }
    }
    return null;
  }

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
    if (_canvasScope == 'international') {
      final originDateTime = DateTime.utc(_date.year, _date.month, _date.day, _hour, _lane);
      return originDateTime.subtract(Duration(hours: _selectedTimeZoneOffset));
    }
    return DateTime(_date.year, _date.month, _date.day, _hour, _lane).toUtc();
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
    for (final c in [_title, _durationSeconds, _mediaUrl, _audioUrl, _glow, _pinText, _thanksTitle, _thanksBody]) {
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

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await _loadDefaults();
      await _loadSlots();
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
    _apply(data);
  }

  Future<void> _loadSlots() async {
    final drafts = await FirebaseFirestore.instance
      .collection('draft_living_canvas_slots')
      .where('weekKey', isEqualTo: _weekKey)
      .where('canvasScope', isEqualTo: _canvasScope)
      .get();
    final published = await FirebaseFirestore.instance
      .collection('living_canvas_slots')
      .where('weekKey', isEqualTo: _weekKey)
      .where('canvasScope', isEqualTo: _canvasScope)
      .get();
    _drafts = {for (final d in drafts.docs) d.id: d.data()};
    _published = {for (final d in published.docs) d.id: d.data()};
    await _removeStaleDrafts();
  }

  Future<void> _removeStaleDrafts() async {
    final staleDraftIds = _drafts.entries
        .where((entry) {
          final published = _published[entry.key];
          if (published == null) return false;
          return _slotComparisonFields.every(
            (field) => entry.value[field] == published[field],
          );
        })
        .map((entry) => entry.key)
        .toList();
    if (staleDraftIds.isEmpty) return;

    try {
      final batch = FirebaseFirestore.instance.batch();
      for (final id in staleDraftIds) {
        batch.delete(
          FirebaseFirestore.instance
              .collection('draft_living_canvas_slots')
              .doc(id),
        );
      }
      await batch.commit();
      _drafts = Map<String, Map<String, dynamic>>.from(_drafts)
        ..removeWhere((id, _) => staleDraftIds.contains(id));
    } catch (e) {
      debugPrint('Could not remove stale Living Canvas drafts: $e');
    }
  }

  void _loadSelectedSlot() {
    final existingId = _existingSelectedSlotId;
    final data = existingId == null
      ? null
      : (_drafts[existingId] ?? _published[existingId]);
    _apply(data ?? const <String, dynamic>{});
  }

  void _apply(Map<String, dynamic> data) {
    _showPin = data['showPinCard'] == true;
    _showGoodometer = data['showGoodometerGraph'] == true;
    _canvasScope = (data['canvasScope'] as String?) ?? _canvasScope;
    _selectedTimeZoneLabel = _normalizeTimeZoneLabel(data['originTimeZone'] as String?);
    _selectedTimeZoneOffset = _offsetForZone(_selectedTimeZoneLabel, _date);
    _title.text = (data['title'] as String?) ?? '';
    _durationSeconds.text = ((data['durationSeconds'] as num?)?.toInt() ?? (data['durationMinutes'] as num?)?.toInt() ?? 30).toString();
    _mediaUrl.text = (data['mediaUrl'] as String?) ?? (data['backgroundImageUrl'] as String?) ?? (data['backgroundVideoUrl'] as String?) ?? '';
    _audioUrl.text =
      (data['chimeAudioUrl'] as String?) ?? (data['customAudioUrl'] as String?) ?? '';
    _glow.text = (data['thumbprintGlowColor'] as String?) ?? 'FFD54F';
    _pinText.text = (data['pinCardText'] as String?) ?? '';
    _thanksTitle.text = (data['thankYouTitle'] as String?) ?? 'Thank you';
    _thanksBody.text = (data['thankYouBody'] as String?) ?? 'Your intent has joined this shared moment.';
  }

  Map<String, dynamic> _data({required bool published}) {
    final start = _slotStartUtc();
    return {
      'slotId': _selectedSlotId,
      'canvasScope': _canvasScope,
      'dateKey': _dateKey,
      'weekKey': _weekKey,
      'startTimeUTC': start.toIso8601String(),
        'originTimeZone': _canvasScope == 'international' ? _selectedTimeZoneLabel : null,
        'originTimeZoneOffset': _canvasScope == 'international' ? _selectedTimeZoneOffset : null,
        'originLocalDateTime': _canvasScope == 'international'
          ? DateTime.utc(_date.year, _date.month, _date.day, _hour, _lane).toIso8601String()
          : null,
      'hour': _hour,
      'laneMinute': _lane,
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
      'showGoodometerGraph': _showGoodometer,
      'published': published,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('draft_living_canvas_slots').doc(_existingSelectedSlotId ?? _selectedSlotId).set(_data(published: false), SetOptions(merge: true));
      await _saveDefaults(showSnack: false);
      await _loadSlots();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Living Canvas draft saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save Living Canvas draft: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearSelectedSlot() async {
    final slotLabel = '${DateFormat('MMM d').format(_date)} '
        '${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Thumbprint slot?'),
        content: Text(
          'This removes the $slotLabel draft and published slot, plus its repeating default. '
          'It will no longer play for this week or future dates.',
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
      final matchesSelectedSlot = (MapEntry<String, Map<String, dynamic>> entry) =>
          (entry.value['hour'] as num?)?.toInt() == _hour &&
          (entry.value['laneMinute'] as num?)?.toInt() == _lane;
      final draftIds = _drafts.entries
          .where(matchesSelectedSlot)
          .map((entry) => entry.key);
      final publishedIds = _published.entries
          .where(matchesSelectedSlot)
          .map((entry) => entry.key);
      final configRef = FirebaseFirestore.instance
          .collection('app_config')
          .doc('living_canvas');
      final config = await configRef.get();
      final repeatingDefaults = Map<String, dynamic>.from(
        (config.data()?['repeatingDefaults'] as Map?) ??
            const <String, dynamic>{},
      );
      final defaultKey = '${_canvasScope}_${_hour.toString().padLeft(2, '0')}${_lane.toString().padLeft(2, '0')}';
      final removedDefault = repeatingDefaults.remove(defaultKey) != null;

      final batch = FirebaseFirestore.instance.batch();
      for (final id in draftIds) {
        batch.delete(
          FirebaseFirestore.instance
              .collection('draft_living_canvas_slots')
              .doc(id),
        );
      }
      for (final id in publishedIds) {
        batch.delete(
          FirebaseFirestore.instance
              .collection('living_canvas_slots')
              .doc(id),
        );
      }
      if (removedDefault) {
        batch.set(configRef, {
          'repeatingDefaults': repeatingDefaults,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
      await _loadSlots();
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

  Future<void> _saveDefaults({bool showSnack = true}) async {
    final data = Map<String, dynamic>.from(_data(published: false))
      ..remove('slotId')
      ..remove('canvasScope')
      ..remove('dateKey')
      ..remove('weekKey')
      ..remove('startTimeUTC')
      ..remove('hour')
      ..remove('laneMinute')
      ..remove('published');
    final configRef = FirebaseFirestore.instance.collection('app_config').doc('living_canvas');
    final existing = await configRef.get();
    final repeatingDefaults = Map<String, dynamic>.from(
      (existing.data()?['repeatingDefaults'] as Map?) ?? const <String, dynamic>{},
    );
    final defaultKey = '${_canvasScope}_${_hour.toString().padLeft(2, '0')}${_lane.toString().padLeft(2, '0')}';
    repeatingDefaults[defaultKey] = data;
    await configRef.set({
      ...data,
      'repeatingDefaults': repeatingDefaults,
    }, SetOptions(merge: true));
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved as repeating default')));
    }
  }

  Future<void> _publishWeek() async {
    setState(() => _publishing = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('draft_living_canvas_slots')
          .where('weekKey', isEqualTo: _weekKey)
          .where('canvasScope', isEqualTo: _canvasScope)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data())..['published'] = true;
        batch.set(FirebaseFirestore.instance.collection('living_canvas_slots').doc(doc.id), data, SetOptions(merge: true));
        batch.delete(doc.reference);
      }
      await batch.commit();
      await _loadSlots();
      _loadSelectedSlot();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Published ${snap.docs.length} ${_canvasScope == 'international' ? 'International' : 'National'} slot${snap.docs.length == 1 ? '' : 's'} for week of ${DateFormat('MMM d').format(_weekStart)}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not publish Living Canvas week: $e')));
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null) return;
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    await _loadSlots();
    _loadSelectedSlot();
    if (mounted) setState(() {});
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
              Expanded(child: Text('Living Canvas ${_canvasScope == 'international' ? 'International' : 'National'} week: ${DateFormat('MMM d').format(_weekStart)} - ${DateFormat('MMM d').format(_weekEndExclusive.subtract(const Duration(days: 1)))}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
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
              OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), label: const Text('Pick date')),
              const SizedBox(width: 8),
              ElevatedButton.icon(onPressed: _publishing ? null : _publishWeek, icon: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.publish), label: Text(_publishing ? 'Publishing...' : 'Publish week')),
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
                  onSelectionChanged: (v) async {
                    setState(() {
                      _canvasScope = v.first;
                      _selectedTimeZoneOffset = _offsetForZone(_selectedTimeZoneLabel, _date);
                    });
                    await _loadSlots();
                    _loadSelectedSlot();
                    if (mounted) setState(() {});
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
                          _selectedTimeZoneOffset = _offsetForZone(_selectedTimeZoneLabel, _date);
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
                final londonLocal = utcDateTime.add(Duration(hours: _offsetForZone('London (Auto DST)', _date)));
                final parisLocal = utcDateTime.add(Duration(hours: _offsetForZone('Paris (Auto DST)', _date)));
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
                    final matchingIds = {..._drafts, ..._published}.entries.where((entry) =>
                      (entry.value['hour'] as num?)?.toInt() == hour &&
                      (entry.value['laneMinute'] as num?)?.toInt() == _lane);
                    final hasDraft = matchingIds.any((entry) => _drafts.containsKey(entry.key));
                    final hasPublished = matchingIds.any((entry) => _published.containsKey(entry.key));
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
            Text('Editing ${_canvasScope == 'international' ? 'International' : 'National'} ${DateFormat('MMM d').format(_date)} ${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Canvas title')),
            TextField(controller: _durationSeconds, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration (Seconds)', helperText: 'Enter exact seconds (e.g. 10), matching the current event editors')),
            Row(children: [
              Expanded(child: TextField(controller: _mediaUrl, decoration: const InputDecoration(labelText: 'Background image/video URL'))),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _pickMediaUrl(allowedTypes: {'image', 'video', 'youtube'}, target: _mediaUrl),
                icon: const Icon(Icons.perm_media),
                label: const Text('Media Library'),
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
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show Goodometer graph'), subtitle: const Text('National view shows National; World view will include World + National when built.'), value: _showGoodometer, onChanged: (v) => setState(() => _showGoodometer = v)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(onPressed: _saving ? null : _saveDraft, icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: Text(_saving ? 'Saving...' : 'Save slot draft')),
              OutlinedButton.icon(onPressed: _clearing ? null : _clearSelectedSlot, icon: _clearing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.delete_outline), label: Text(_clearing ? 'Clearing...' : 'Clear slot')),
              OutlinedButton.icon(onPressed: () => _saveDefaults(), icon: const Icon(Icons.copy_all), label: const Text('Save as repeating default')),
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
    final isVideo = mediaPath.endsWith('.mp4') || mediaPath.endsWith('.mov') || mediaPath.endsWith('.webm') || mediaPath.endsWith('.mpeg4');
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
              image: mediaUrl.isNotEmpty && !isVideo ? DecorationImage(image: NetworkImage(mediaUrl), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.28), BlendMode.darken)) : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                if (isVideo)
                  Positioned.fill(
                    child: VideoGridItem(
                      url: mediaUrl,
                      type: 'upload',
                      enablePreview: false,
                      autoPlay: true,
                    ),
                  ),
                Positioned(top: 18, left: 16, child: _previewPill('${_canvasScope == 'international' ? 'World' : 'National'} • 128 live')),
                Positioned(top: 18, right: 16, child: _previewPill('Exit Event')),
                if (_title.text.trim().isNotEmpty)
                  Positioned(top: 54, left: 18, right: 18, child: Column(children: [Text(_title.text.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text('${DateFormat('EEE MMM d').format(_date)} • ${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white70, fontSize: 12))])),
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