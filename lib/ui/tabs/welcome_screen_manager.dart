import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/media_library_service.dart';
import '../../models/media_item.dart';
import '../widgets/web_image.dart';

class WelcomeScreenManager extends StatefulWidget {
  const WelcomeScreenManager({super.key});

  @override
  State<WelcomeScreenManager> createState() => _WelcomeScreenManagerState();
}

class _WelcomeScreenManagerState extends State<WelcomeScreenManager> {
  final MediaLibraryService _mediaLibrary = MediaLibraryService();

  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _buttonTextController = TextEditingController();
  
  String? _backgroundImageUrl;
  String? _logoUrl;
  double _logoSize = 80.0;
  bool _isLoading = false;
  bool _isSaving = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _applyDefaults();
    _loadConfig();
  }

  void _applyDefaults() {
    _titleController.text = 'Harmony by Intent';
    _subtitleController.text = 'Connect with simultaneous intent.\nExperience peace together.';
    _buttonTextController.text = 'Get Started';
    _backgroundImageUrl = null;
    _logoUrl = null;
    _logoSize = 80.0;
  }

  String _friendlyFirestoreError(Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '').trim();
    final lower = raw.toLowerCase();
    if (lower.contains('permission-denied')) {
      return 'Permission denied while loading Welcome Screen config.';
    }
    if (lower.contains('unavailable') || lower.contains('network') || lower.contains('timeout')) {
      return 'Network timeout while loading Welcome Screen config.';
    }
    if (raw.length > 180) {
      return 'Failed to load Welcome Screen config from Firestore.';
    }
    return raw;
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('welcome_screen')
          .get()
          .timeout(const Duration(seconds: 20));

      if (doc.exists) {
        final data = doc.data()!;
        _titleController.text = data['title'] ?? 'Harmony by Intent';
        _subtitleController.text = data['subtitle'] ?? 'Connect with simultaneous intent.\nExperience peace together.';
        _buttonTextController.text = data['buttonText'] ?? 'Get Started';
        _backgroundImageUrl = data['backgroundImageUrl'];
        _logoUrl = data['logoUrl'];
        _logoSize = (data['logoSize'] ?? 80.0).toDouble();
      } else {
        _applyDefaults();
      }
      _loadError = null;
    } catch (e) {
      _applyDefaults();
      _loadError = _friendlyFirestoreError(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_loadError!), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('welcome_screen')
          .set({
        'title': _titleController.text,
        'subtitle': _subtitleController.text,
        'buttonText': _buttonTextController.text,
        'backgroundImageUrl': _backgroundImageUrl,
        'logoUrl': _logoUrl,
        'logoSize': _logoSize,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Welcome screen updated successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving config: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImage({required Function(String) onSelect}) async {
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 800,
          height: 600,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text('Select Image', style: Theme.of(context).textTheme.titleLarge),
              const Divider(),
              Expanded(
                child: StreamBuilder<List<MediaItem>>(
                  stream: _mediaLibrary.getMediaStream(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            _friendlyFirestoreError(snapshot.error!),
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final images = snapshot.data!.where((i) => i.type == 'image').toList();
                    
                    if (images.isEmpty) return const Center(child: Text('No images found in library'));

                    return GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: images.length,
                      itemBuilder: (context, index) {
                        final item = images[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              Column(
                                children: [
                                  Expanded(child: WebImage(imageUrl: item.url, fit: BoxFit.cover)),
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              Positioned.fill(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      print('Selected image: ${item.url}');
                                      onSelect(item.url);
                                      Navigator.pop(context);
                                    },
                                  ),
                                ),
                              ),
                            ],
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Editor
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade200),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _loadError!,
                            style: TextStyle(color: Colors.red.shade900),
                          ),
                        ),
                        TextButton(
                          onPressed: _loadConfig,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ],
                const Text('Welcome Screen Configuration', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _subtitleController,
                  decoration: const InputDecoration(labelText: 'Subtitle', border: OutlineInputBorder()),
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _buttonTextController,
                  decoration: const InputDecoration(labelText: 'Button Text', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                const Text('Visuals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),

                // Background Image Picker
                ListTile(
                  title: const Text('Background Image'),
                  subtitle: Text(_backgroundImageUrl != null ? 'Image Selected' : 'No Image Selected (Default Gradient)'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_backgroundImageUrl != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _backgroundImageUrl = null),
                        ),
                      IconButton(
                        icon: const Icon(Icons.image),
                        onPressed: () => _pickImage(onSelect: (url) {
                          print('Setting background URL: $url');
                          setState(() => _backgroundImageUrl = url);
                        }),
                      ),
                    ],
                  ),
                ),

                // Logo Picker
                ListTile(
                  title: const Text('Custom Logo'),
                  subtitle: Text(_logoUrl != null ? 'Custom Logo Selected' : 'Default Icon'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_logoUrl != null)
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _logoUrl = null),
                        ),
                      IconButton(
                        icon: const Icon(Icons.image),
                        onPressed: () => _pickImage(onSelect: (url) => setState(() => _logoUrl = url)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const Text('Logo Size', style: TextStyle(fontWeight: FontWeight.w500)),
                Slider(
                  value: _logoSize,
                  min: 40,
                  max: 300,
                  divisions: 26,
                  label: '${_logoSize.round()} px',
                  onChanged: (v) => setState(() => _logoSize = v),
                ),

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveConfig,
                    icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Saving...' : 'Publish Changes'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Preview
        Expanded(
          flex: 1,
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background
                if (_backgroundImageUrl != null)
                  WebImage(imageUrl: _backgroundImageUrl!, fit: BoxFit.cover)
                else
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF3F51B5), Color(0xFF9C27B0)], // Indigo to Purple
                      ),
                    ),
                  ),
                
                // Content Overlay
                Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo
                          Container(
                            width: 200,
                            height: 200,
                            alignment: Alignment.center,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: _logoUrl != null 
                              ? Transform.scale(
                                  scale: _logoSize / 200.0,
                                  child: Container(
                                    width: 200, height: 200,
                                    alignment: Alignment.center,
                                    child: WebImage(imageUrl: _logoUrl!, fit: BoxFit.contain)
                                  ),
                                )
                              : Icon(Icons.spa, size: _logoSize, color: Colors.white),
                          ),
                          const SizedBox(height: 40),
                          Text(
                            _titleController.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _subtitleController.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 40),
                          
                          // Button
                          SizedBox(
                            width: double.infinity,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                _buttonTextController.text,
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
