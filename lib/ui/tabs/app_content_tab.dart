import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import '../../services/media_library_service.dart';
import '../../models/media_item.dart';
import '../widgets/video_widgets.dart';

class AppContentTab extends StatefulWidget {
  const AppContentTab({super.key});

  @override
  State<AppContentTab> createState() => _AppContentTabState();
}

class _AppContentTabState extends State<AppContentTab> {
  // Services
  final MediaLibraryService _mediaLibrary = MediaLibraryService();

  // Controllers
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _bulletinController = TextEditingController();
  final _featuredUrlController = TextEditingController();
  final _featuredTitleController = TextEditingController();
  final _featuredBodyController = TextEditingController();

  // State Variables
  bool _isLoading = false;
  bool _isSaving = false;

  // Config Data
  String? _backgroundImageUrl;
  bool _showBulletin = false;
  bool _showLiveStats = false;
  bool _showFeatured = false;
  String _featuredType = 'youtube'; // 'youtube' or 'video' or 'image'

  // Video Controllers for Preview
  VideoPlayerController? _backgroundVideoController;
  VideoPlayerController? _featuredVideoController;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _backgroundVideoController?.dispose();
    _featuredVideoController?.dispose();
    super.dispose();
  }

  Future<void> _loadContent() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        _titleController.text = data['title'] ?? 'Welcome to Harmony';
        _messageController.text =
            data['message'] ?? 'Your journey begins here.';
        _backgroundImageUrl = data['backgroundImageUrl'];

        _showBulletin = data['showBulletin'] ?? false;
        _bulletinController.text = data['bulletinText'] ?? '';

        _showLiveStats = data['showLiveStats'] ?? false;

        _showFeatured = data['showFeatured'] ?? false;
        _featuredType = data['featuredType'] ?? 'youtube';
        _featuredUrlController.text = data['featuredUrl'] ?? '';
        _featuredTitleController.text = data['featuredTitle'] ?? '';
        _featuredBodyController.text = data['featuredBody'] ?? '';

        // Initialize featured video if needed
        if (_showFeatured &&
            _featuredType == 'video' &&
            _featuredUrlController.text.isNotEmpty) {
          _initFeaturedVideo(_featuredUrlController.text);
        }

        if (_backgroundImageUrl != null && _isVideo(_backgroundImageUrl!)) {
          _initBackgroundVideo(_backgroundImageUrl!);
        }
      } else {
        // Defaults
        _titleController.text = 'Welcome to Harmony';
        _messageController.text = 'Your journey begins here.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading content: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool _isVideo(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('video');
  }

  Future<void> _initBackgroundVideo(String url) async {
    _backgroundVideoController?.dispose();
    _backgroundVideoController =
        VideoPlayerController.networkUrl(Uri.parse(url));
    await _backgroundVideoController!.initialize();
    _backgroundVideoController!.setLooping(true);
    _backgroundVideoController!.setVolume(0);
    _backgroundVideoController!.play();
    if (mounted) setState(() {});
  }

  Future<void> _initFeaturedVideo(String url) async {
    _featuredVideoController?.dispose();
    _featuredVideoController = VideoPlayerController.networkUrl(Uri.parse(url));
    await _featuredVideoController!.initialize();
    _featuredVideoController!.setLooping(true);
    _featuredVideoController!.setVolume(0); // Mute by default for preview
    _featuredVideoController!.play();
    if (mounted) setState(() {});
  }

  Future<void> _saveContent() async {
    print('Saving content...');
    final user = FirebaseAuth.instance.currentUser;
    print('Current User: ${user?.uid}');

    setState(() => _isSaving = true);
    try {
      // Removed explicit enableNetwork call as it can be unstable

      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .set({
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'backgroundImageUrl': _backgroundImageUrl,
        'showBulletin': _showBulletin,
        'bulletinText': _bulletinController.text.trim(),
        'showLiveStats': _showLiveStats,
        'showFeatured': _showFeatured,
        'featuredType': _featuredType,
        'featuredUrl': _featuredUrlController.text.trim(),
        'featuredTitle': _featuredTitleController.text.trim(),
        'featuredBody': _featuredBodyController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 60));

      print('Content saved successfully');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Changes published successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error saving content: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error Publishing'),
            content: SingleChildScrollView(
              child: SelectableText(
                  'Failed to publish changes.\n\nError details: $e\n\nPlease check your internet connection and try again.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickFromMediaLibrary({required bool isBackground}) async {
    String? selectedSection;
    
    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: StatefulBuilder(
          builder: (context, setState) {
            return Container(
              width: 800,
              height: 600,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          isBackground
                              ? 'Select Background'
                              : 'Select Featured Content',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  // Section Filter (Dynamic from Media Library)
                  Row(
                    children: [
                      const Text('Filter by Section: '),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StreamBuilder<List<MediaItem>>(
                          stream: _mediaLibrary.getMediaStream(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) return const LinearProgressIndicator();
                            final allItems = snapshot.data!;
                            final sections = allItems.map((e) => e.section).toSet().toList()..sort();
                            
                            return DropdownButton<String>(
                              value: selectedSection,
                              hint: const Text('Select Category'),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(value: 'All', child: Text('All Categories')),
                                ...sections.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  selectedSection = val;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<List<MediaItem>>(
                      stream: _mediaLibrary.getMediaStream(section: selectedSection),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}'));
                        }
                        final allFiles = snapshot.data ?? [];

                        if (allFiles.isEmpty) {
                          return const Center(
                              child: Text(
                                  'No media found in this section.'));
                        }

                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: allFiles.length,
                          itemBuilder: (context, index) {
                            final item = allFiles[index];
                            final urlLower = item.url.toLowerCase();
                            
                            // Robust type detection
                            final isYoutube = item.type == 'youtube' || urlLower.contains('youtu');
                            final isVideo = item.type == 'video' || isYoutube || urlLower.contains('.mp4') || urlLower.contains('.mov');
                            final isImage = item.type == 'image' || 
                                           (!isVideo && (urlLower.contains('.jpg') || urlLower.contains('.jpeg') || urlLower.contains('.png') || urlLower.contains('.webp')));
                            final isPdf = urlLower.contains('.pdf');

                            return InkWell(
                              onTap: () {
                                // Use the parent context's setState to update the main widget
                                this.setState(() {
                                  if (isBackground) {
                                    if (isPdf) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF cannot be used as background')));
                                        return; 
                                    }
                                    _backgroundImageUrl = item.url;
                                    if (isVideo && !isYoutube) {
                                      _initBackgroundVideo(item.url);
                                    } else {
                                      _backgroundVideoController?.dispose();
                                      _backgroundVideoController = null;
                                    }
                                  } else {
                                    _featuredUrlController.text = item.url;
                                    if (isYoutube) {
                                       _featuredType = 'youtube';
                                    } else if (isVideo) {
                                        _featuredType = 'video';
                                        _initFeaturedVideo(item.url);
                                    } else if (isPdf) {
                                      _featuredType = 'pdf';
                                    } else {
                                      _featuredType = 'image';
                                    }
                                  }
                                });
                                Navigator.pop(context);
                              },
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: isImage
                                          ? Image.network(item.url,
                                              fit: BoxFit.cover,
                                              errorBuilder: (ctx, _, __) => const Center(child: Icon(Icons.broken_image)),
                                          )
                                          : (isVideo || isYoutube)
                                              ? VideoGridItem(
                                                  url: item.url,
                                                  type: isYoutube ? 'youtube' : 'upload',
                                                  enablePreview: false,
                                                )
                                              : Container(
                                                  color: Colors.grey.shade200,
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(
                                                        isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file,
                                                        size: 40,
                                                        color: isPdf ? Colors.red : Colors.grey,
                                                      ),
                                                      if (isPdf) 
                                                        const Text('PDF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
                                                    ],
                                                  ),
                                                ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                        textAlign: TextAlign.center,
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
            );
          }
        ),
      ),
    );
  }

  Future<void> _showYouTubeDialog() async {
    final controller = TextEditingController();
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add YouTube Video'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'YouTube URL',
            hintText: 'https://www.youtube.com/watch?v=...',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  _featuredUrlController.text = controller.text;
                  _featuredType = 'youtube';
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Side: Editor
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Home Screen Configuration',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                    'Customize the landing page experience for your users.'),
                const SizedBox(height: 32),

                // 1. Main Content
                _buildSectionHeader('Main Content'),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Headline Title',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    labelText: 'Sub-headline Message',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_backgroundImageUrl != null)
                      Container(
                        width: 60,
                        height: 60,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade200,
                          image: _backgroundImageUrl != null &&
                                  !_isVideo(_backgroundImageUrl!)
                              ? DecorationImage(
                                  image: NetworkImage(_backgroundImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _backgroundImageUrl != null &&
                                _isVideo(_backgroundImageUrl!)
                            ? const Icon(Icons.videocam, color: Colors.black54)
                            : null,
                      ),
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () =>
                                _pickFromMediaLibrary(isBackground: true),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Select from Library'),
                          ),
                          if (_backgroundImageUrl != null)
                            TextButton(
                              onPressed: () => setState(() {
                                _backgroundImageUrl = null;
                                _backgroundVideoController?.dispose();
                                _backgroundVideoController = null;
                              }),
                              child: const Text('Remove',
                                  style: TextStyle(color: Colors.red)),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // 2. Bulletin Board
                _buildSectionHeader('Bulletin Board Overlay'),
                SwitchListTile(
                  title: const Text('Show Bulletin Board'),
                  subtitle:
                      const Text('Display a text overlay for announcements'),
                  value: _showBulletin,
                  onChanged: (v) => setState(() => _showBulletin = v),
                ),
                if (_showBulletin)
                  TextField(
                    controller: _bulletinController,
                    decoration: const InputDecoration(
                      labelText: 'Bulletin Text',
                      border: OutlineInputBorder(),
                      helperText: 'Keep it short and punchy.',
                    ),
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                  ),

                const SizedBox(height: 32),

                // 3. Live Stats
                _buildSectionHeader('Live Stats'),
                SwitchListTile(
                  title: const Text('Show Live Stats'),
                  subtitle:
                      const Text('Display active user count or other metrics'),
                  value: _showLiveStats,
                  onChanged: (v) => setState(() => _showLiveStats = v),
                ),

                const SizedBox(height: 32),

                // 4. Featured Content
                _buildSectionHeader('Featured Content'),
                SwitchListTile(
                  title: const Text('Show Featured Content'),
                  subtitle: const Text('Display a video or image thumbnail'),
                  value: _showFeatured,
                  onChanged: (v) => setState(() => _showFeatured = v),
                ),
                if (_showFeatured) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _featuredTitleController,
                    decoration: const InputDecoration(
                      labelText: 'Content Title',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _featuredBodyController,
                    decoration: const InputDecoration(
                      labelText: 'Content Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _pickFromMediaLibrary(isBackground: false),
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Select from Library'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _showYouTubeDialog,
                          icon: const Icon(Icons.link),
                          label: const Text('YouTube Link'),
                          style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_featuredUrlController.text.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade50,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _featuredType == 'youtube'
                                ? Icons.play_circle_fill
                                : _featuredType == 'video'
                                    ? Icons.video_file
                                    : _featuredType == 'pdf'
                                        ? Icons.picture_as_pdf
                                        : Icons.image,
                            color: Colors.indigo,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected Content: ${_featuredType.toUpperCase()}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  _featuredUrlController.text,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () => setState(() {
                              _featuredUrlController.clear();
                              _featuredType = 'image'; // Reset to default
                            }),
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 48),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _saveContent,
                          icon: const Icon(Icons.save),
                          label:
                              Text(_isSaving ? 'Saving...' : 'PUBLISH CHANGES'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    if (_isSaving)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Force Reset',
                          onPressed: () => setState(() => _isSaving = false),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),

        // Right Side: Phone Preview
        Expanded(
          flex: 4, // Increased flex from 2 to 4 for larger preview
          child: Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              children: [
                const Text('LIVE PREVIEW',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 16),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.contain, // Ensure it scales up to fill available space
                    child: Container(
                      width: 375,
                      height: 812,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(40),
                        border:
                            Border.all(color: Colors.grey.shade800, width: 8),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 20,
                              spreadRadius: 5),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: Stack(
                          children: [
                            // Background
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.indigo.shade900,
                                    Colors.purple.shade900
                                  ],
                                ),
                                image: _backgroundImageUrl != null &&
                                        !_isVideo(_backgroundImageUrl!)
                                    ? DecorationImage(
                                        image:
                                            NetworkImage(_backgroundImageUrl!),
                                        fit: BoxFit.cover,
                                        colorFilter: ColorFilter.mode(
                                            Colors.black.withOpacity(0.4),
                                            BlendMode.darken),
                                      )
                                    : null,
                              ),
                              child: _backgroundImageUrl != null &&
                                      _isVideo(_backgroundImageUrl!) &&
                                      _backgroundVideoController != null &&
                                      _backgroundVideoController!
                                          .value.isInitialized
                                  ? SizedBox.expand(
                                      child: FittedBox(
                                        fit: BoxFit.cover,
                                        child: SizedBox(
                                          width: _backgroundVideoController!
                                              .value.size.width,
                                          height: _backgroundVideoController!
                                              .value.size.height,
                                          child: VideoPlayer(
                                              _backgroundVideoController!),
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            if (_backgroundImageUrl != null &&
                                _isVideo(_backgroundImageUrl!))
                              Container(
                                  color: Colors.black.withOpacity(
                                      0.4)), // Overlay for video legibility

                            // Content
                            SafeArea(
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                    // App Bar Mock
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Icon(Icons.menu,
                                            color: Colors.white),
                                        const Text('Harmony',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold)),
                                        const Icon(Icons.notifications,
                                            color: Colors.white),
                                      ],
                                    ),
                                    const SizedBox(height: 40),

                                    // Main Text
                                    const Icon(Icons.spa,
                                        size: 60, color: Colors.white70),
                                    const SizedBox(height: 16),
                                    Text(
                                      _titleController.text.isEmpty
                                          ? 'Title'
                                          : _titleController.text,
                                      style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _messageController.text.isEmpty
                                          ? 'Message'
                                          : _messageController.text,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 16),
                                      textAlign: TextAlign.center,
                                    ),

                                    const SizedBox(height: 32),

                                    // Bulletin Board
                                    if (_showBulletin)
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border:
                                              Border.all(color: Colors.white30),
                                        ),
                                        child: Column(
                                          children: [
                                            const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.push_pin,
                                                    color: Colors.amber,
                                                    size: 16),
                                                SizedBox(width: 8),
                                                Text('NOTICE BOARD',
                                                    style: TextStyle(
                                                        color: Colors.amber,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 12)),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _bulletinController.text.isEmpty
                                                  ? '...'
                                                  : _bulletinController.text,
                                              style: const TextStyle(
                                                  color: Colors.white),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),

                                    const SizedBox(height: 16),

                                    // Featured Content
                                    if (_showFeatured)
                                      Container(
                                        constraints: const BoxConstraints(minHeight: 150),
                                        width: double.infinity,
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        alignment: Alignment.center,
                                        child: _buildFeaturedPreview(),
                                      ),

                                    const SizedBox(height: 32),

                                    // Live Stats
                                    if (_showLiveStats)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.green.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color: Colors.green
                                                  .withOpacity(0.5)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.circle,
                                                color: Colors.green, size: 12),
                                            SizedBox(width: 8),
                                            Text('124 Users Online',
                                                style: TextStyle(
                                                    color: Colors.greenAccent,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ),

                                    const SizedBox(height: 20),
                                  ],
                                ),
                              ),
                             ), 
                            ),
                          ],
                        ),
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

  Widget _buildFeaturedPreview() {
    if (_featuredUrlController.text.isEmpty) {
      return const Icon(Icons.perm_media, color: Colors.white54);
    }

    switch (_featuredType) {
      case 'youtube':
        // Use VideoGridItem for consistent YouTube preview
        return VideoGridItem(
          url: _featuredUrlController.text,
          type: 'youtube',
          enablePreview: true,
        );
      case 'video':
        // Use VideoGridItem for consistent Video preview
        return VideoGridItem(
          url: _featuredUrlController.text,
          type: 'upload',
          enablePreview: true,
        );
      case 'pdf':
        return const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 48),
            SizedBox(height: 8),
            Text('PDF Document',
                style: TextStyle(color: Colors.white, fontSize: 10)),
          ],
        );
      case 'image':
        return ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: Image.network(
            _featuredUrlController.text,
            fit: BoxFit.contain,
            width: double.infinity,
            errorBuilder: (context, error, stackTrace) => Container(
               height: 150,
               alignment: Alignment.center,
               child: const Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 children: [
                   Icon(Icons.broken_image, color: Colors.white54, size: 40),
                   SizedBox(height: 8),
                   Text("Image not found", style: TextStyle(color: Colors.white54, fontSize: 10)),
                 ],
               ),
            ),
          ),
        );
      default:
        return const SizedBox();
    }
  }

  String? _getYoutubeId(String url) {
    final regExp = RegExp(
      r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
      caseSensitive: false,
      multiLine: false,
    );
    final match = regExp.firstMatch(url);
    if (match != null && match.groupCount >= 7) {
      return match.group(7);
    }
    return null;
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo)),
          const Divider(),
        ],
      ),
    );
  }
}
