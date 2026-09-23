import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../models/media_item.dart';
import '../../services/media_library_service.dart';
import '../widgets/video_widgets.dart';
import 'web_pdf_shim.dart' if (dart.library.io) 'web_pdf_shim_stub.dart';

class NoticeboardStudioTab extends StatefulWidget {
  const NoticeboardStudioTab({super.key});

  @override
  State<NoticeboardStudioTab> createState() => _NoticeboardStudioTabState();
}

class _NoticeboardStudioTabState extends State<NoticeboardStudioTab> {
  final MediaLibraryService _mediaLibrary = MediaLibraryService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hideLegacyEventsTab = false;
  bool _enableNoticeboardStudioFeed = true;
  bool _remindMeEnabled = false;
  bool _learnMoreEnabled = false;
  bool _phonePreviewShowingLearnMore = false;
  bool _phonePreviewRemindMeRequested = false;
  String _borderTheme = 'standard';
  String _selectedCardId = 'draft_main';

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _learnMoreLabelController = TextEditingController(text: 'Learn More');
  final _learnMoreContentUrlController = TextEditingController();
  final _linkedSlotIdController = TextEditingController();
  final _showBeforeHoursController = TextEditingController(text: '24');
  final _hideAfterHoursController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _titleController,
      _bodyController,
      _imageUrlController,
      _learnMoreLabelController,
      _learnMoreContentUrlController,
    ]) {
      controller.addListener(_refreshPreview);
    }
    _load();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      _titleController,
      _bodyController,
      _imageUrlController,
      _learnMoreLabelController,
      _learnMoreContentUrlController,
    ]) {
      controller.removeListener(_refreshPreview);
    }
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    _learnMoreLabelController.dispose();
    _learnMoreContentUrlController.dispose();
    _linkedSlotIdController.dispose();
    _showBeforeHoursController.dispose();
    _hideAfterHoursController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('noticeboard_studio')
          .get();
      final settings = settingsDoc.data() ?? const <String, dynamic>{};
      _hideLegacyEventsTab = settings['hideLegacyEventsTab'] == true;
      _enableNoticeboardStudioFeed = settings['enableNoticeboardStudioFeed'] != false;
      await _loadCard(_selectedCardId);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCard(String cardId) async {
    final cardDoc = await FirebaseFirestore.instance
        .collection('noticeboard_studio_cards')
        .doc(cardId)
        .get();
    final card = cardDoc.data() ?? const <String, dynamic>{};
    _selectedCardId = cardId;
    _borderTheme = (card['borderTheme'] as String?) ?? 'standard';
    _remindMeEnabled = card['remindMeEnabled'] == true;
    _phonePreviewRemindMeRequested = false;
    _learnMoreEnabled = card['learnMoreEnabled'] == true;
    _titleController.text = (card['title'] as String?) ?? '';
    _bodyController.text = (card['body'] as String?) ?? '';
    _imageUrlController.text = (card['imageUrl'] as String?) ?? '';
    _learnMoreLabelController.text = (card['learnMoreLabel'] as String?) ?? 'Learn More';
    _learnMoreContentUrlController.text = (card['learnMoreContentUrl'] as String?) ?? '';
    _linkedSlotIdController.text = (card['linkedSlotId'] as String?) ?? '';
    _showBeforeHoursController.text = ((card['showBeforeHours'] as num?)?.toInt() ?? 24).toString();
    _hideAfterHoursController.text = ((card['hideAfterHours'] as num?)?.toInt() ?? 0).toString();
  }

  Map<String, dynamic> _cardData({required bool published}) {
    return {
      'title': _titleController.text.trim(),
      'body': _bodyController.text.trim(),
      'imageUrl': _imageUrlController.text.trim(),
      'borderTheme': _borderTheme,
      'learnMoreEnabled': _learnMoreEnabled,
      'learnMoreLabel': _learnMoreLabelController.text.trim().isEmpty
          ? 'Learn More'
          : _learnMoreLabelController.text.trim(),
      'learnMoreContentUrl': _learnMoreContentUrlController.text.trim(),
      'linkedSlotId': _linkedSlotIdController.text.trim(),
      'remindMeEnabled': _remindMeEnabled,
      'showBeforeHours': (int.tryParse(_showBeforeHoursController.text.trim()) ?? 24).clamp(0, 720),
      'hideAfterHours': (int.tryParse(_hideAfterHoursController.text.trim()) ?? 0).clamp(0, 720),
      'published': published,
      'updatedAt': FieldValue.serverTimestamp(),
      if (published) 'publishedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _save({required bool published}) async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('noticeboard_studio').set({
        'hideLegacyEventsTab': _hideLegacyEventsTab,
        'enableNoticeboardStudioFeed': _enableNoticeboardStudioFeed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('noticeboard_studio_cards')
          .doc(_selectedCardId)
          .set(_cardData(published: published), SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(published ? 'Noticeboard published' : 'Noticeboard draft saved')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _recallSelected() async {
    await FirebaseFirestore.instance.collection('noticeboard_studio_cards').doc(_selectedCardId).set({
      'published': false,
      'recalledAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Noticeboard recalled')));
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedCardId == 'draft_main') return;
    await FirebaseFirestore.instance.collection('noticeboard_studio_cards').doc(_selectedCardId).delete();
    await _loadCard('draft_main');
    if (mounted) setState(() {});
  }

  void _createNewDraft() {
    _selectedCardId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
    _titleController.clear();
    _bodyController.clear();
    _imageUrlController.clear();
    _learnMoreEnabled = false;
    _learnMoreLabelController.text = 'Learn More';
    _learnMoreContentUrlController.clear();
    _linkedSlotIdController.clear();
    _remindMeEnabled = false;
    _phonePreviewRemindMeRequested = false;
    _showBeforeHoursController.text = '24';
    _hideAfterHoursController.text = '0';
    setState(() {});
  }

  Future<void> _pickMediaUrl({required Set<String> allowedTypes, required TextEditingController target}) async {
    String? selectedSection = 'All';
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
                        Expanded(child: Text('Select Media', style: Theme.of(context).textTheme.titleLarge)),
                        SizedBox(
                          width: 260,
                          child: StreamBuilder<List<MediaItem>>(
                            stream: _mediaLibrary.getMediaStream(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const LinearProgressIndicator();
                              final sections = snapshot.data!.map((item) => item.section).toSet().toList()..sort();
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
                      child: StreamBuilder<List<MediaItem>>(
                            stream: _mediaLibrary.getMediaStream(section: selectedSection == 'All' ? null : selectedSection),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                              final items = snapshot.data!.where((item) => allowedTypes.contains(item.type)).toList();
                              if (items.isEmpty) return const Center(child: Text('No matching media found.'));
                              return GridView.builder(
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  final lower = item.url.toLowerCase();
                                  final isYoutube = item.type == 'youtube' || lower.contains('youtube') || lower.contains('youtu.be');
                                  final isVideo = item.type == 'video' || isYoutube;
                                  final preview = item.type == 'image'
                                      ? Image.network(item.url, fit: BoxFit.cover)
                                      : isVideo
                                          ? VideoGridItem(url: item.url, type: isYoutube ? 'youtube' : 'upload', enablePreview: true, autoPlay: false)
                                          : const Center(child: Icon(Icons.insert_drive_file, size: 48));
                                  return InkWell(
                                    onTap: () => Navigator.pop(context, item),
                                    child: Card(
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(children: [
                                        Expanded(child: IgnorePointer(child: preview)),
                                        Padding(
                                          padding: const EdgeInsets.all(4),
                                          child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        ),
                                      ]),
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

  Future<void> _testLearnMore() async {
    final url = _learnMoreContentUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add Learn More content first')));
      return;
    }
    setState(() => _phonePreviewShowingLearnMore = true);
  }

  Widget _buildLearnMorePreviewContent() {
    final url = _learnMoreContentUrlController.text.trim();
    if (url.isEmpty) {
      return const Center(
        child: Text('No Learn More content selected', style: TextStyle(color: Colors.white54)),
      );
    }

    final lower = url.toLowerCase();
    final isImage = lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp');
    final isYoutube = lower.contains('youtube') || lower.contains('youtu.be');
    final isVideo = isYoutube || lower.endsWith('.mp4') || lower.endsWith('.mov') || lower.endsWith('.webm');
    final isPdf = lower.contains('.pdf');
    final viewId = 'noticeboard-learn-more-inline-${url.hashCode}';
    if (isYoutube) {
      final id = _youtubeId(url);
      if (id != null) {
        registerPdfViewFactory(viewId, 'https://www.youtube.com/embed/$id?autoplay=0&playsinline=1&rel=0');
      }
    } else if (!isImage && !isVideo && !isPdf) {
      registerPdfViewFactory(viewId, url);
    }

    if (isImage) {
      return InteractiveViewer(child: Image.network(url, fit: BoxFit.contain));
    }
    if (isYoutube) {
      return HtmlElementView(viewType: viewId);
    }
    if (isPdf) {
      return SfPdfViewer.network(
        url,
        enableDoubleTapZooming: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
      );
    }
    if (isVideo) {
      return VideoGridItem(url: url, type: 'upload', enablePreview: false, autoPlay: true);
    }
    return HtmlElementView(viewType: viewId);
  }

  String? _youtubeId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.queryParameters.containsKey('v')) return uri.queryParameters['v'];
      if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) return uri.pathSegments.first;
      final shorts = uri.pathSegments.indexOf('shorts');
      if (shorts >= 0 && shorts + 1 < uri.pathSegments.length) return uri.pathSegments[shorts + 1];
      final embed = uri.pathSegments.indexOf('embed');
      if (embed >= 0 && embed + 1 < uri.pathSegments.length) return uri.pathSegments[embed + 1];
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final wide = MediaQuery.of(context).size.width >= 1100;
    final editor = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [_buildSettingsCard(), const SizedBox(height: 12), _buildCardList(), const SizedBox(height: 12), _buildEditorCard()],
      ),
    );
    final preview = _buildPhonePreview();
    return wide
        ? Row(children: [Expanded(flex: 3, child: editor), VerticalDivider(width: 1, color: Colors.grey.shade300), SizedBox(width: 390, child: preview)])
        : Column(children: [Expanded(child: editor), SizedBox(height: 520, child: preview)]);
  }

  Widget _buildSettingsCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Navigation override toggles', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Hide legacy Events tab'),
              subtitle: const Text('Default off. User app will ignore this until mobile integration is deliberately built.'),
              value: _hideLegacyEventsTab,
              onChanged: (v) => setState(() => _hideLegacyEventsTab = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enable Noticeboard Studio feed'),
              value: _enableNoticeboardStudioFeed,
              onChanged: (v) => setState(() => _enableNoticeboardStudioFeed = v),
            ),
          ]),
        ),
      );

  Widget _buildCardList() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Noticeboards', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              OutlinedButton.icon(onPressed: _createNewDraft, icon: const Icon(Icons.add), label: const Text('New draft')),
            ]),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('noticeboard_studio_cards').orderBy('updatedAt', descending: true).limit(25).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Text('No Studio noticeboards yet.');
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final doc in docs)
                      ChoiceChip(
                        selected: doc.id == _selectedCardId,
                        label: Text('${doc.data()['published'] == true ? 'LIVE' : 'DRAFT'} • ${(doc.data()['title'] as String?)?.isEmpty == false ? doc.data()['title'] : doc.id}'),
                        onSelected: (_) async {
                          await _loadCard(doc.id);
                          if (mounted) setState(() {});
                        },
                      ),
                  ],
                );
              },
            ),
          ]),
        ),
      );

  Widget _buildEditorCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Editing $_selectedCardId', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            DropdownButtonFormField<String>(
              initialValue: _borderTheme,
              decoration: const InputDecoration(labelText: 'Border theme'),
              items: const [
                DropdownMenuItem(value: 'standard', child: Text('Standard')),
                DropdownMenuItem(value: 'wood', child: Text('Wood')),
                DropdownMenuItem(value: 'gold', child: Text('Gold')),
                DropdownMenuItem(value: 'glass', child: Text('Glass')),
              ],
              onChanged: (v) => setState(() => _borderTheme = v ?? 'standard'),
            ),
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: _bodyController, maxLines: 4, decoration: const InputDecoration(labelText: 'Body')),
            Row(children: [
              Expanded(child: TextField(controller: _imageUrlController, decoration: const InputDecoration(labelText: 'Noticeboard image URL'))),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: () => _pickMediaUrl(allowedTypes: {'image'}, target: _imageUrlController), icon: const Icon(Icons.image), label: const Text('Media Library')),
              IconButton(onPressed: () => setState(() => _imageUrlController.clear()), icon: const Icon(Icons.clear), tooltip: 'Remove image'),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show Learn More button'),
              value: _learnMoreEnabled,
              onChanged: (v) => setState(() => _learnMoreEnabled = v),
            ),
            if (_learnMoreEnabled) ...[
              TextField(controller: _learnMoreLabelController, decoration: const InputDecoration(labelText: 'Learn More button label')),
              Row(children: [
                Expanded(child: TextField(controller: _learnMoreContentUrlController, decoration: const InputDecoration(labelText: 'Learn More content URL'))),
                const SizedBox(width: 8),
                OutlinedButton.icon(onPressed: () => _pickMediaUrl(allowedTypes: {'image', 'video', 'youtube', 'document', 'other'}, target: _learnMoreContentUrlController), icon: const Icon(Icons.perm_media), label: const Text('Media Library')),
                IconButton(onPressed: () => setState(() => _learnMoreContentUrlController.clear()), icon: const Icon(Icons.clear), tooltip: 'Remove Learn More'),
                IconButton(onPressed: _testLearnMore, icon: const Icon(Icons.open_in_browser), tooltip: 'Test'),
              ]),
            ],
            TextField(controller: _linkedSlotIdController, decoration: const InputDecoration(labelText: 'Linked slot id for Remind Me')),
            Row(children: [
              Expanded(child: TextField(controller: _showBeforeHoursController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Show before hours'))),
              const SizedBox(width: 12),
              Expanded(child: TextField(controller: _hideAfterHoursController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Hide after hours'))),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Enable Remind Me module'), value: _remindMeEnabled, onChanged: (v) => setState(() => _remindMeEnabled = v)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(onPressed: _isSaving ? null : () => _save(published: false), icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: const Text('Save draft')),
              ElevatedButton.icon(onPressed: _isSaving ? null : () => _save(published: true), icon: const Icon(Icons.publish), label: const Text('Publish noticeboard')),
              OutlinedButton.icon(onPressed: _recallSelected, icon: const Icon(Icons.undo), label: const Text('Recall')),
              OutlinedButton.icon(onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline), label: const Text('Delete')),
            ]),
          ]),
        ),
      );

  Widget _buildPhonePreview() {
    final borderColor = switch (_borderTheme) { 'wood' => const Color(0xFF8D6E63), 'gold' => const Color(0xFFFFD54F), 'glass' => Colors.white70, _ => Colors.white24 };
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.all(18),
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 19,
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.black87, width: 8), color: const Color(0xFF111827)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: _phonePreviewShowingLearnMore
                  ? Column(
                      children: [
                        Container(
                          height: 48,
                          color: Colors.black,
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: 'Back to noticeboard',
                                icon: const Icon(Icons.arrow_back, color: Colors.white),
                                onPressed: () => setState(() => _phonePreviewShowingLearnMore = false),
                              ),
                              const Expanded(
                                child: Text('Learn More', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _buildLearnMorePreviewContent()),
                      ],
                    )
                  : Stack(children: [
                      Positioned.fill(child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1E293B), Color(0xFF020617)])))),
                      Center(
                    child: Container(
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: _borderTheme == 'glass' ? 0.32 : 0.55), borderRadius: BorderRadius.circular(14), border: Border.all(color: borderColor, width: _borderTheme == 'gold' ? 2 : 1)),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_imageUrlController.text.trim().isNotEmpty) ...[
                          ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(_imageUrlController.text.trim(), height: 120, fit: BoxFit.cover)),
                          const SizedBox(height: 12),
                        ],
                        Text(_titleController.text.trim().isEmpty ? 'Noticeboard title' : _titleController.text.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text(_bodyController.text.trim().isEmpty ? 'Noticeboard body text appears here.' : _bodyController.text.trim(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        if (_learnMoreEnabled) ...[
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: _testLearnMore,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amberAccent,
                              foregroundColor: Colors.black87,
                            ),
                            child: Text(_learnMoreLabelController.text.trim().isEmpty ? 'Learn More' : _learnMoreLabelController.text.trim()),
                          ),
                        ],
                        if (_remindMeEnabled) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => setState(() => _phonePreviewRemindMeRequested = true),
                            icon: Icon(_phonePreviewRemindMeRequested ? Icons.notifications_active : Icons.notifications_none),
                            label: Text(_phonePreviewRemindMeRequested ? 'Notification requested' : 'Remind Me'),
                          ),
                        ],
                      ]),
                    ),
                    ),
                  ]),
            ),
          ),
        ),
      ),
    );
  }
}
