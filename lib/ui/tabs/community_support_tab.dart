import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'community_tab.dart' show kPostRetentionDayOptions;
import '../../services/storage_service.dart';

// Built-in icon options. Material has no literal "praying hands" glyph, so
// this starts on the closest stock icon; admin can upload real artwork via
// "Custom" mode at any time, which takes over everywhere without a rebuild.
const Map<String, IconData> kSupportBuiltInIcons = {
  'front_hand': Icons.front_hand,
  'volunteer_activism': Icons.volunteer_activism,
  'shield_outlined': Icons.shield_outlined,
  'self_improvement': Icons.self_improvement,
  'favorite': Icons.favorite,
};

const Map<String, String> kSupportBuiltInIconLabels = {
  'front_hand': 'Raised Hand (default)',
  'volunteer_activism': 'Caring Hands',
  'shield_outlined': 'Shield',
  'self_improvement': 'Reflection',
  'favorite': 'Heart',
};

class CommunitySupportTab extends StatefulWidget {
  const CommunitySupportTab({super.key});

  @override
  State<CommunitySupportTab> createState() => _CommunitySupportTabState();
}

class _CommunitySupportTabState extends State<CommunitySupportTab> {
  final StorageService _storage = StorageService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingIcon = false;

  bool _isSupportFeatureEnabled = false;
  final _buttonTextController = TextEditingController(text: 'Community Support');

  String _iconMode = 'builtin'; // 'builtin' | 'custom' | 'text'
  String _iconBuiltInKey = 'front_hand';
  String? _iconCustomUrl;
  final _textLabelController = TextEditingController(text: 'Community Served');
  final _textColorController = TextEditingController(text: 'FFEB3B');

  bool _enableOnboardingPopup = true;
  final _popupTitleController =
      TextEditingController(text: 'Welcome to Community Support');
  final _popupBodyController = TextEditingController(
    text:
        'This is a space to ask for support from the community. Share what you need, '
        'and others can offer support in return.',
  );
  final _popupButtonTextController = TextEditingController(text: 'Enter');

  int _postRetentionDays = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _buttonTextController.dispose();
    _textLabelController.dispose();
    _textColorController.dispose();
    _popupTitleController.dispose();
    _popupBodyController.dispose();
    _popupButtonTextController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final supportDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_support')
          .get();
      final settingsDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_settings')
          .get();

      if (supportDoc.exists) {
        final data = supportDoc.data()!;
        _isSupportFeatureEnabled = data['isSupportFeatureEnabled'] == true;
        _buttonTextController.text =
            (data['supportButtonText'] as String?)?.trim().isNotEmpty == true
                ? data['supportButtonText']
                : 'Community Support';
        _iconMode = (data['supportIconMode'] as String?) ?? 'builtin';
        _iconBuiltInKey = kSupportBuiltInIcons.containsKey(data['supportIconBuiltInKey'])
            ? data['supportIconBuiltInKey']
            : 'front_hand';
        _iconCustomUrl = data['supportIconCustomUrl'] as String?;
        _textLabelController.text =
            (data['supportTextLabel'] as String?)?.trim().isNotEmpty == true
                ? data['supportTextLabel']
                : 'Community Served';
        _textColorController.text =
            (data['supportTextColor'] as String?)?.trim().isNotEmpty == true
                ? data['supportTextColor']
                : 'FFEB3B';
        _enableOnboardingPopup = data['enableOnboardingPopup'] != false;
        _popupTitleController.text =
            (data['supportPopupTitle'] as String?)?.trim().isNotEmpty == true
                ? data['supportPopupTitle']
                : _popupTitleController.text;
        _popupBodyController.text =
            (data['supportPopupBody'] as String?)?.trim().isNotEmpty == true
                ? data['supportPopupBody']
                : _popupBodyController.text;
        _popupButtonTextController.text =
            (data['supportPopupButtonText'] as String?)?.trim().isNotEmpty == true
                ? data['supportPopupButtonText']
                : 'Enter';
      }

      if (settingsDoc.exists) {
        final days = (settingsDoc.data()!['postRetentionDays'] as num?)?.toInt();
        if (days != null && kPostRetentionDayOptions.contains(days)) {
          _postRetentionDays = days;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load Community Support settings: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadIcon() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;

    setState(() => _isUploadingIcon = true);
    try {
      final ext = file.name.split('.').last.toLowerCase();
      final url = await _storage.uploadBytes(
        Uint8List.fromList(file.bytes!),
        fileExt: ext,
        folder: 'community_support_icons',
      );
      setState(() {
        _iconCustomUrl = url;
        _iconMode = 'custom';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Icon upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingIcon = false);
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_support')
          .set({
        'isSupportFeatureEnabled': _isSupportFeatureEnabled,
        'supportButtonText': _buttonTextController.text.trim(),
        'supportIconMode': _iconMode,
        'supportIconBuiltInKey': _iconBuiltInKey,
        'supportIconCustomUrl': _iconCustomUrl,
        'supportTextLabel': _textLabelController.text.trim(),
        'supportTextColor': _textColorController.text.trim(),
        'enableOnboardingPopup': _enableOnboardingPopup,
        'supportPopupTitle': _popupTitleController.text.trim(),
        'supportPopupBody': _popupBodyController.text.trim(),
        'supportPopupButtonText': _popupButtonTextController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Shared with the Live Feed tab's dropdown — same field, same value.
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_settings')
          .set({'postRetentionDays': _postRetentionDays}, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Community Support settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _iconPreview() {
    if (_iconMode == 'text') {
      final color = _parseHexColor(_textColorController.text) ?? Colors.amber;
      return Text(
        _textLabelController.text.isEmpty ? 'Community Served' : _textLabelController.text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
      );
    }
    if (_iconMode == 'custom' && _iconCustomUrl != null) {
      return Image.network(_iconCustomUrl!, width: 32, height: 32, fit: BoxFit.contain);
    }
    return Icon(kSupportBuiltInIcons[_iconBuiltInKey] ?? Icons.front_hand, size: 28);
  }

  Color? _parseHexColor(String hex) {
    final cleaned = hex.trim().replaceAll('#', '');
    if (cleaned.length != 6 && cleaned.length != 8) return null;
    final value = int.tryParse(cleaned.length == 6 ? 'FF$cleaned' : cleaned, radix: 16);
    return value == null ? null : Color(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Community Support',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                          'Master toggle. While off, the Home Screen button and Support feed are hidden from every user.'),
                      value: _isSupportFeatureEnabled,
                      onChanged: (v) => setState(() => _isSupportFeatureEnabled = v),
                    ),
                    const Divider(),
                    TextField(
                      controller: _buttonTextController,
                      decoration: const InputDecoration(
                        labelText: 'Home Screen button text',
                        border: OutlineInputBorder(),
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
                    const Text('Icon / Badge', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text(
                      'Displayed on the Support button, My Impact, and Past Intents. Changing this updates all three at once.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: _iconPreview(),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'builtin', label: Text('Built-in')),
                              ButtonSegment(value: 'custom', label: Text('Custom upload')),
                              ButtonSegment(value: 'text', label: Text('Text label')),
                            ],
                            selected: {_iconMode},
                            onSelectionChanged: (s) => setState(() => _iconMode = s.first),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_iconMode == 'builtin')
                      DropdownButton<String>(
                        value: _iconBuiltInKey,
                        isExpanded: true,
                        items: kSupportBuiltInIcons.keys
                            .map((key) => DropdownMenuItem(
                                  value: key,
                                  child: Row(
                                    children: [
                                      Icon(kSupportBuiltInIcons[key]),
                                      const SizedBox(width: 8),
                                      Text(kSupportBuiltInIconLabels[key] ?? key),
                                    ],
                                  ),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _iconBuiltInKey = v);
                        },
                      ),
                    if (_iconMode == 'custom')
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isUploadingIcon ? null : _pickAndUploadIcon,
                            icon: _isUploadingIcon
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.upload),
                            label: Text(_isUploadingIcon ? 'Uploading...' : 'Upload icon image'),
                          ),
                          const SizedBox(width: 12),
                          if (_iconCustomUrl == null)
                            const Text('No custom icon uploaded yet',
                                style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ],
                      ),
                    if (_iconMode == 'text')
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _textLabelController,
                            decoration: const InputDecoration(
                              labelText: 'Text label',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _textColorController,
                            decoration: const InputDecoration(
                              labelText: 'Text color (hex, e.g. FFEB3B)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ],
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
                    const Text('Post Retention', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text(
                      'Shared with the Live Feed tab — changing it here updates both.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 8),
                    DropdownButton<int>(
                      value: _postRetentionDays,
                      items: kPostRetentionDayOptions
                          .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _postRetentionDays = v);
                      },
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Onboarding pop-up',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text(
                          'Shown the first time a user taps the Support button (per device).'),
                      value: _enableOnboardingPopup,
                      onChanged: (v) => setState(() => _enableOnboardingPopup = v),
                    ),
                    const Divider(),
                    TextField(
                      controller: _popupTitleController,
                      decoration: const InputDecoration(
                        labelText: 'Pop-up title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _popupBodyController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Pop-up body',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _popupButtonTextController,
                      decoration: const InputDecoration(
                        labelText: 'Pop-up button text',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Saving...' : 'Save Settings'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
