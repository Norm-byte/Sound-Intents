import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LivingCanvasStudioTab extends StatefulWidget {
  const LivingCanvasStudioTab({super.key});

  @override
  State<LivingCanvasStudioTab> createState() => _LivingCanvasStudioTabState();
}

class _LivingCanvasStudioTabState extends State<LivingCanvasStudioTab> {
  bool _loading = true;
  bool _saving = false;
  bool _publishing = false;
  DateTime _date = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  int _lane = 0;
  int _hour = 12;

  bool _active = false;
  bool _showPin = false;
  bool _showGoodometer = false;
  bool _loopAudio = true;
  bool _tapAudioOnly = false;
  String _backgroundMode = 'image';
  final _title = TextEditingController(text: 'Living Canvas');
  final _duration = TextEditingController(text: '30');
  final _imageUrl = TextEditingController();
  final _videoUrl = TextEditingController();
  final _carouselUrls = TextEditingController();
  final _carouselMinutes = TextEditingController(text: '10');
  final _audioUrl = TextEditingController();
  final _glow = TextEditingController(text: 'FFD54F');
  final _pinText = TextEditingController();
  final _thanksTitle = TextEditingController(text: 'Thank you');
  final _thanksBody = TextEditingController(text: 'Your intent has joined this shared moment.');

  Map<String, Map<String, dynamic>> _drafts = const {};
  Map<String, Map<String, dynamic>> _published = const {};

  String get _dateKey => DateFormat('yyyyMMdd').format(_date);
  String _slotId(int hour, int lane) => 'lc_${hour.toString().padLeft(2, '0')}${lane.toString().padLeft(2, '0')}_$_dateKey';
  String get _selectedSlotId => _slotId(_hour, _lane);

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in [_title, _duration, _imageUrl, _videoUrl, _carouselUrls, _carouselMinutes, _audioUrl, _glow, _pinText, _thanksTitle, _thanksBody]) {
      c.dispose();
    }
    super.dispose();
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
    _apply(doc.data() ?? const <String, dynamic>{});
  }

  Future<void> _loadSlots() async {
    final drafts = await FirebaseFirestore.instance.collection('draft_living_canvas_slots').where('dateKey', isEqualTo: _dateKey).get();
    final published = await FirebaseFirestore.instance.collection('living_canvas_slots').where('dateKey', isEqualTo: _dateKey).get();
    _drafts = {for (final d in drafts.docs) d.id: d.data()};
    _published = {for (final d in published.docs) d.id: d.data()};
  }

  void _loadSelectedSlot() {
    final data = _drafts[_selectedSlotId] ?? _published[_selectedSlotId];
    if (data != null) _apply(data);
  }

  void _apply(Map<String, dynamic> data) {
    _active = data['isThumbprintModeActive'] == true;
    _showPin = data['showPinCard'] == true;
    _showGoodometer = data['showGoodometerGraph'] == true;
    _loopAudio = data['loopAudio'] != false;
    _tapAudioOnly = data['playOnThumbprintTapOnly'] == true;
    _backgroundMode = (data['backgroundMode'] as String?) ?? 'image';
    _title.text = (data['title'] as String?) ?? 'Living Canvas';
    _duration.text = ((data['durationMinutes'] as num?)?.toInt() ?? 30).toString();
    _imageUrl.text = (data['backgroundImageUrl'] as String?) ?? '';
    _videoUrl.text = (data['backgroundVideoUrl'] as String?) ?? '';
    _carouselUrls.text = ((data['carouselImageUrls'] as List?) ?? const []).map((e) => e.toString()).join('\n');
    _carouselMinutes.text = ((data['carouselRotateMinutes'] as num?)?.toInt() ?? 10).toString();
    _audioUrl.text =
      (data['chimeAudioUrl'] as String?) ?? (data['customAudioUrl'] as String?) ?? '';
    _glow.text = (data['thumbprintGlowColor'] as String?) ?? 'FFD54F';
    _pinText.text = (data['pinCardText'] as String?) ?? '';
    _thanksTitle.text = (data['thankYouTitle'] as String?) ?? 'Thank you';
    _thanksBody.text = (data['thankYouBody'] as String?) ?? 'Your intent has joined this shared moment.';
  }

  Map<String, dynamic> _data({required bool published}) {
    final start = DateTime(_date.year, _date.month, _date.day, _hour, _lane).toUtc();
    return {
      'slotId': _selectedSlotId,
      'dateKey': _dateKey,
      'startTimeUTC': start.toIso8601String(),
      'hour': _hour,
      'laneMinute': _lane,
      'durationMinutes': (int.tryParse(_duration.text.trim()) ?? 30).clamp(1, 240),
      'isThumbprintModeActive': _active,
      'title': _title.text.trim(),
      'backgroundMode': _backgroundMode,
      'backgroundImageUrl': _imageUrl.text.trim(),
      'backgroundVideoUrl': _videoUrl.text.trim(),
      'carouselImageUrls': _carouselUrls.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      'carouselRotateMinutes': (int.tryParse(_carouselMinutes.text.trim()) ?? 10).clamp(1, 240),
      'audioMode': _audioUrl.text.trim().isEmpty ? 'silent' : 'custom',
      'chimeAudioUrl': _audioUrl.text.trim(),
      'customAudioUrl': _audioUrl.text.trim(),
      'loopAudio': _loopAudio,
      'playOnThumbprintTapOnly': _tapAudioOnly,
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
    await FirebaseFirestore.instance.collection('draft_living_canvas_slots').doc(_selectedSlotId).set(_data(published: false), SetOptions(merge: true));
    await _saveDefaults(showSnack: false);
    await _loadSlots();
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Living Canvas draft saved')));
    }
  }

  Future<void> _saveDefaults({bool showSnack = true}) async {
    final data = Map<String, dynamic>.from(_data(published: false))
      ..remove('slotId')
      ..remove('dateKey')
      ..remove('startTimeUTC')
      ..remove('hour')
      ..remove('laneMinute')
      ..remove('published');
    await FirebaseFirestore.instance.collection('app_config').doc('living_canvas').set(data, SetOptions(merge: true));
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved as repeating default')));
    }
  }

  Future<void> _publishDate() async {
    setState(() => _publishing = true);
    final snap = await FirebaseFirestore.instance.collection('draft_living_canvas_slots').where('dateKey', isEqualTo: _dateKey).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      final data = Map<String, dynamic>.from(doc.data())..['published'] = true;
      batch.set(FirebaseFirestore.instance.collection('living_canvas_slots').doc(doc.id), data, SetOptions(merge: true));
    }
    await batch.commit();
    await _loadSlots();
    if (mounted) {
      setState(() => _publishing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Published ${snap.docs.length} slot${snap.docs.length == 1 ? '' : 's'}')));
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
            Row(children: [
              Expanded(child: Text('Living Canvas schedule: ${DateFormat('EEE, MMM d, yyyy').format(_date)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.calendar_month), label: const Text('Pick date')),
              const SizedBox(width: 8),
              ElevatedButton.icon(onPressed: _publishing ? null : _publishDate, icon: _publishing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.publish), label: Text(_publishing ? 'Publishing...' : 'Publish date')),
            ]),
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
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 24,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, hour) {
                  final id = _slotId(hour, _lane);
                  final hasDraft = _drafts.containsKey(id);
                  final hasPublished = _published.containsKey(id);
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
                    },
                  );
                },
              ),
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
            Text('Editing ${DateFormat('MMM d').format(_date)} ${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Thumbprint mode active for this slot'), subtitle: const Text('Off means this slot is inert. Existing Events/Noticeboards are not changed.'), value: _active, onChanged: (v) => setState(() => _active = v)),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Canvas title')),
            TextField(controller: _duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duration minutes')),
            DropdownButtonFormField<String>(initialValue: _backgroundMode, decoration: const InputDecoration(labelText: 'Background mode'), items: const [DropdownMenuItem(value: 'image', child: Text('Single image')), DropdownMenuItem(value: 'video', child: Text('Looping MP4 video')), DropdownMenuItem(value: 'carousel', child: Text('Timed image carousel'))], onChanged: (v) => setState(() => _backgroundMode = v ?? 'image')),
            TextField(controller: _imageUrl, decoration: const InputDecoration(labelText: 'Image URL / Media Library image URL')),
            TextField(controller: _videoUrl, decoration: const InputDecoration(labelText: 'MP4 URL / Media Library video URL')),
            TextField(controller: _carouselUrls, maxLines: 4, decoration: const InputDecoration(labelText: 'Carousel image URLs (one per line)')),
            TextField(controller: _carouselMinutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Carousel rotate minutes')),
            TextField(controller: _audioUrl, decoration: const InputDecoration(labelText: 'Event-start chime/audio URL')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Loop audio'), value: _loopAudio, onChanged: (v) => setState(() => _loopAudio = v)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Play audio only after thumbprint tap'), value: _tapAudioOnly, onChanged: (v) => setState(() => _tapAudioOnly = v)),
            TextField(controller: _glow, decoration: const InputDecoration(labelText: 'Thumbprint glow color (hex)')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show floating pin card'), value: _showPin, onChanged: (v) => setState(() => _showPin = v)),
            TextField(controller: _pinText, maxLines: 3, decoration: const InputDecoration(labelText: 'Pin card text')),
            TextField(controller: _thanksTitle, decoration: const InputDecoration(labelText: 'Thank-you title')),
            TextField(controller: _thanksBody, maxLines: 3, decoration: const InputDecoration(labelText: 'Thank-you body')),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show Goodometer graph'), value: _showGoodometer, onChanged: (v) => setState(() => _showGoodometer = v)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(onPressed: _saving ? null : _saveDraft, icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: Text(_saving ? 'Saving...' : 'Save slot draft')),
              OutlinedButton.icon(onPressed: () => _saveDefaults(), icon: const Icon(Icons.copy_all), label: const Text('Save as repeating default')),
            ]),
          ]),
        ),
      );

  Widget _preview() {
    final glow = _hex(_glow.text) ?? Colors.amber;
    final carousel = _carouselUrls.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final image = _backgroundMode == 'carousel' ? (carousel.isEmpty ? null : carousel.first) : (_backgroundMode == 'image' ? _imageUrl.text.trim() : null);
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
              image: image != null && image.isNotEmpty ? DecorationImage(image: NetworkImage(image), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.28), BlendMode.darken)) : null,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(children: [
                if (_backgroundMode == 'video') const Center(child: Icon(Icons.movie_filter, color: Colors.white38, size: 72)),
                Positioned(top: 22, left: 18, right: 18, child: Column(children: [Text(_title.text.trim().isEmpty ? 'Living Canvas' : _title.text.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text('${DateFormat('EEE MMM d').format(_date)} • ${_hour.toString().padLeft(2, '0')}:${_lane.toString().padLeft(2, '0')}', style: const TextStyle(color: Colors.white70, fontSize: 12))])),
                if (_showPin && _pinText.text.trim().isNotEmpty) Positioned(left: 18, right: 18, top: 96, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)), child: Text(_pinText.text.trim(), style: const TextStyle(color: Colors.white70, fontSize: 12)))),
                Center(child: Container(width: 150, height: 150, decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: glow.withValues(alpha: 0.55), blurRadius: 32, spreadRadius: 12)], border: Border.all(color: glow, width: 2), color: Colors.black.withValues(alpha: 0.24)), child: Icon(Icons.fingerprint, size: 92, color: glow))),
                if (_showGoodometer) Positioned(left: 18, right: 18, bottom: 92, child: Row(children: [Expanded(child: _bar('National', 0.62, Colors.amberAccent)), const SizedBox(width: 8), Expanded(child: _bar('World', 0.46, Colors.lightBlueAccent))])),
                Positioned(left: 18, right: 18, bottom: 24, child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(14)), child: Column(children: [Text(_thanksTitle.text.trim().isEmpty ? 'Thank you' : _thanksTitle.text.trim(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(_thanksBody.text.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11))]))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bar(String label, double value, Color color) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)), const SizedBox(height: 4), ClipRRect(borderRadius: BorderRadius.circular(999), child: LinearProgressIndicator(value: value, minHeight: 8, color: color, backgroundColor: Colors.white24))]);

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