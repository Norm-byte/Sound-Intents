import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class NoticeboardStudioTab extends StatefulWidget {
  const NoticeboardStudioTab({super.key});

  @override
  State<NoticeboardStudioTab> createState() => _NoticeboardStudioTabState();
}

class _NoticeboardStudioTabState extends State<NoticeboardStudioTab> {
  bool _isLoading = true;
  bool _isSaving = false;

  bool _hideLegacyEventsTab = false;
  bool _enableNoticeboardStudioFeed = true;
  bool _remindMeEnabled = false;
  String _borderTheme = 'standard';

  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _learnMoreUrlController = TextEditingController();
  final _linkedSlotIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _imageUrlController.dispose();
    _learnMoreUrlController.dispose();
    _linkedSlotIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final settingsDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('noticeboard_studio')
          .get();
      final cardDoc = await FirebaseFirestore.instance
          .collection('noticeboard_studio_cards')
          .doc('draft_main')
          .get();
      final settings = settingsDoc.data() ?? const <String, dynamic>{};
      final card = cardDoc.data() ?? const <String, dynamic>{};
      _hideLegacyEventsTab = settings['hideLegacyEventsTab'] == true;
      _enableNoticeboardStudioFeed = settings['enableNoticeboardStudioFeed'] != false;
      _borderTheme = (card['borderTheme'] as String?) ?? 'standard';
      _remindMeEnabled = card['remindMeEnabled'] == true;
      _titleController.text = (card['title'] as String?) ?? '';
      _bodyController.text = (card['body'] as String?) ?? '';
      _imageUrlController.text = (card['imageUrl'] as String?) ?? '';
      _learnMoreUrlController.text = (card['learnMoreUrl'] as String?) ?? '';
      _linkedSlotIdController.text = (card['linkedSlotId'] as String?) ?? '';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('noticeboard_studio')
          .set({
        'hideLegacyEventsTab': _hideLegacyEventsTab,
        'enableNoticeboardStudioFeed': _enableNoticeboardStudioFeed,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('noticeboard_studio_cards')
          .doc('draft_main')
          .set({
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'imageUrl': _imageUrlController.text.trim(),
        'borderTheme': _borderTheme,
        'learnMoreUrl': _learnMoreUrlController.text.trim(),
        'linkedSlotId': _linkedSlotIdController.text.trim(),
        'remindMeEnabled': _remindMeEnabled,
        'published': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Noticeboard Studio settings saved')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testWebviewUrl() async {
    final url = _learnMoreUrlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a Learn More URL first')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Webview URL'),
        content: SelectableText(url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Card builder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                    TextField(controller: _imageUrlController, decoration: const InputDecoration(labelText: 'Image URL')),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _learnMoreUrlController, decoration: const InputDecoration(labelText: 'Learn More URL'))),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _testWebviewUrl,
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('Test Webview'),
                        ),
                      ],
                    ),
                    TextField(controller: _linkedSlotIdController, decoration: const InputDecoration(labelText: 'Linked slot id for Remind Me')),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Remind Me module'),
                      value: _remindMeEnabled,
                      onChanged: (v) => setState(() => _remindMeEnabled = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Noticeboard Studio Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
