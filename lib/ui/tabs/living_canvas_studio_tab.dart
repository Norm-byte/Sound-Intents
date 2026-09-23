import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LivingCanvasStudioTab extends StatefulWidget {
  const LivingCanvasStudioTab({super.key});

  @override
  State<LivingCanvasStudioTab> createState() => _LivingCanvasStudioTabState();
}

class _LivingCanvasStudioTabState extends State<LivingCanvasStudioTab> {
  bool _isLoading = true;
  bool _isSaving = false;

  bool _isThumbprintModeActive = false;
  bool _showPinCard = false;
  bool _loopAudio = true;
  bool _playOnThumbprintTapOnly = false;
  bool _showGoodometerGraph = false;

  String _titleMode = 'manual';
  String _backgroundMode = 'image';
  String _audioMode = 'preset';
  String _presetTrackId = '528hz';

  final _manualTitleController = TextEditingController(text: 'Living Canvas');
  final _quoteCollectionController = TextEditingController(text: 'living_canvas_quotes');
  final _backgroundImageUrlController = TextEditingController();
  final _backgroundVideoUrlController = TextEditingController();
  final _carouselUrlsController = TextEditingController();
  final _carouselRotateMinutesController = TextEditingController(text: '10');
  final _customAudioUrlController = TextEditingController();
  final _thumbprintGlowColorController = TextEditingController(text: 'FFD54F');
  final _pinCardTextController = TextEditingController();
  final _thankYouTitleController = TextEditingController(text: 'Thank you');
  final _thankYouBodyController = TextEditingController(
    text: 'Your intent has joined this shared moment.',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manualTitleController.dispose();
    _quoteCollectionController.dispose();
    _backgroundImageUrlController.dispose();
    _backgroundVideoUrlController.dispose();
    _carouselUrlsController.dispose();
    _carouselRotateMinutesController.dispose();
    _customAudioUrlController.dispose();
    _thumbprintGlowColorController.dispose();
    _pinCardTextController.dispose();
    _thankYouTitleController.dispose();
    _thankYouBodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('living_canvas')
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      _isThumbprintModeActive = data['isThumbprintModeActive'] == true;
      _showPinCard = data['showPinCard'] == true;
      _loopAudio = data['loopAudio'] != false;
      _playOnThumbprintTapOnly = data['playOnThumbprintTapOnly'] == true;
      _showGoodometerGraph = data['showGoodometerGraph'] == true;
      _titleMode = (data['titleMode'] as String?) ?? 'manual';
      _backgroundMode = (data['backgroundMode'] as String?) ?? 'image';
      _audioMode = (data['audioMode'] as String?) ?? 'preset';
      _presetTrackId = (data['presetTrackId'] as String?) ?? '528hz';
      _manualTitleController.text = (data['manualTitle'] as String?) ?? 'Living Canvas';
      _quoteCollectionController.text = (data['quoteCollectionId'] as String?) ?? 'living_canvas_quotes';
      _backgroundImageUrlController.text = (data['backgroundImageUrl'] as String?) ?? '';
      _backgroundVideoUrlController.text = (data['backgroundVideoUrl'] as String?) ?? '';
      _carouselUrlsController.text = ((data['carouselImageUrls'] as List?) ?? const [])
          .map((e) => e.toString())
          .join('\n');
      _carouselRotateMinutesController.text =
          ((data['carouselRotateMinutes'] as num?)?.toInt() ?? 10).toString();
      _customAudioUrlController.text = (data['customAudioUrl'] as String?) ?? '';
      _thumbprintGlowColorController.text = (data['thumbprintGlowColor'] as String?) ?? 'FFD54F';
      _pinCardTextController.text = (data['pinCardText'] as String?) ?? '';
      _thankYouTitleController.text = (data['thankYouTitle'] as String?) ?? 'Thank you';
      _thankYouBodyController.text =
          (data['thankYouBody'] as String?) ?? 'Your intent has joined this shared moment.';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final carouselUrls = _carouselUrlsController.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final rotateMinutes = int.tryParse(_carouselRotateMinutesController.text.trim()) ?? 10;
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('living_canvas')
          .set({
        'isThumbprintModeActive': _isThumbprintModeActive,
        'titleMode': _titleMode,
        'manualTitle': _manualTitleController.text.trim(),
        'quoteCollectionId': _quoteCollectionController.text.trim(),
        'backgroundMode': _backgroundMode,
        'backgroundImageUrl': _backgroundImageUrlController.text.trim(),
        'backgroundVideoUrl': _backgroundVideoUrlController.text.trim(),
        'carouselImageUrls': carouselUrls,
        'carouselRotateMinutes': rotateMinutes.clamp(1, 240),
        'audioMode': _audioMode,
        'presetTrackId': _presetTrackId,
        'customAudioUrl': _customAudioUrlController.text.trim(),
        'loopAudio': _loopAudio,
        'playOnThumbprintTapOnly': _playOnThumbprintTapOnly,
        'thumbprintGlowColor': _thumbprintGlowColorController.text.trim(),
        'showPinCard': _showPinCard,
        'pinCardText': _pinCardTextController.text.trim(),
        'thankYouTitle': _thankYouTitleController.text.trim(),
        'thankYouBody': _thankYouBodyController.text.trim(),
        'showGoodometerGraph': _showGoodometerGraph,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Living Canvas settings saved')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section(
              title: 'Release-safe master control',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activate Thumbprint Mode'),
                  subtitle: const Text('Default off. Turning this off must leave the existing app experience unchanged.'),
                  value: _isThumbprintModeActive,
                  onChanged: (v) => setState(() => _isThumbprintModeActive = v),
                ),
              ],
            ),
            _section(
              title: 'Title source',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _titleMode,
                  decoration: const InputDecoration(labelText: 'Title source'),
                  items: const [
                    DropdownMenuItem(value: 'manual', child: Text('Manual text')),
                    DropdownMenuItem(value: 'quote_collection', child: Text('Automated quote collection')),
                  ],
                  onChanged: (v) => setState(() => _titleMode = v ?? 'manual'),
                ),
                TextField(controller: _manualTitleController, decoration: const InputDecoration(labelText: 'Manual title')),
                TextField(controller: _quoteCollectionController, decoration: const InputDecoration(labelText: 'Quote collection id')),
              ],
            ),
            _section(
              title: 'Background rotation',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _backgroundMode,
                  decoration: const InputDecoration(labelText: 'Background mode'),
                  items: const [
                    DropdownMenuItem(value: 'image', child: Text('Single image')),
                    DropdownMenuItem(value: 'video', child: Text('Looping MP4 video')),
                    DropdownMenuItem(value: 'carousel', child: Text('Timed image carousel')),
                  ],
                  onChanged: (v) => setState(() => _backgroundMode = v ?? 'image'),
                ),
                TextField(controller: _backgroundImageUrlController, decoration: const InputDecoration(labelText: 'Image URL')),
                TextField(controller: _backgroundVideoUrlController, decoration: const InputDecoration(labelText: 'MP4 URL')),
                TextField(
                  controller: _carouselUrlsController,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Carousel image URLs (one per line)'),
                ),
                TextField(
                  controller: _carouselRotateMinutesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Carousel rotate minutes'),
                ),
              ],
            ),
            _section(
              title: 'Slot audio',
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _audioMode,
                  decoration: const InputDecoration(labelText: 'Audio mode'),
                  items: const [
                    DropdownMenuItem(value: 'preset', child: Text('Preset')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom upload URL')),
                    DropdownMenuItem(value: 'silent', child: Text('Silent')),
                  ],
                  onChanged: (v) => setState(() => _audioMode = v ?? 'preset'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _presetTrackId,
                  decoration: const InputDecoration(labelText: 'Preset track'),
                  items: const [
                    DropdownMenuItem(value: '528hz', child: Text('528Hz')),
                    DropdownMenuItem(value: 'singing_bowl', child: Text('Singing bowl')),
                    DropdownMenuItem(value: 'rainfall', child: Text('Rainfall')),
                    DropdownMenuItem(value: 'soft_chime', child: Text('Soft chime')),
                  ],
                  onChanged: (v) => setState(() => _presetTrackId = v ?? '528hz'),
                ),
                TextField(controller: _customAudioUrlController, decoration: const InputDecoration(labelText: 'Custom audio URL')),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Loop audio'), value: _loopAudio, onChanged: (v) => setState(() => _loopAudio = v)),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Play on thumbprint tap only'), value: _playOnThumbprintTapOnly, onChanged: (v) => setState(() => _playOnThumbprintTapOnly = v)),
              ],
            ),
            _section(
              title: 'Touchpoint and overlays',
              children: [
                TextField(controller: _thumbprintGlowColorController, decoration: const InputDecoration(labelText: 'Thumbprint glow color (hex)')),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show floating pin card'), value: _showPinCard, onChanged: (v) => setState(() => _showPinCard = v)),
                TextField(controller: _pinCardTextController, maxLines: 3, decoration: const InputDecoration(labelText: 'Pin card text')),
                TextField(controller: _thankYouTitleController, decoration: const InputDecoration(labelText: 'Thank-you title')),
                TextField(controller: _thankYouBodyController, maxLines: 3, decoration: const InputDecoration(labelText: 'Thank-you body')),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Show Goodometer graph'), value: _showGoodometerGraph, onChanged: (v) => setState(() => _showGoodometerGraph = v)),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Living Canvas Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}
