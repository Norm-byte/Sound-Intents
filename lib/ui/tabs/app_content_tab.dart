import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';
// ignore: deprecated_member_use
import '../../services/media_library_service.dart';
import '../../models/media_item.dart';
import '../widgets/video_widgets.dart';

const int kMaxActiveReels = 30;

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
  String? _backgroundAudioUrl;
  bool _showBackground = false;
  String? _logoUrl;
  double _logoSize = 80.0;
  bool _showBulletin = false;
  bool _showFeatured = false;
  String _featuredType = 'youtube'; // 'youtube' or 'video' or 'image'
  bool _showReelCarousel = false;
  int _reelAutoRotateSeconds = 8;
  List<Map<String, dynamic>> _reelItems = [];

  int get _activeReelCount =>
      _reelItems.where((item) => item['enabled'] != false).length;

  // Video Controller for Background Preview only
  VideoPlayerController? _backgroundVideoController;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  @override
  void dispose() {
    _backgroundVideoController?.dispose();
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
        _backgroundAudioUrl = data['backgroundAudioUrl'] as String?;
        final savedShowBackground = data['showBackground'];
        _showBackground = savedShowBackground is bool
          ? savedShowBackground
          : _backgroundImageUrl != null;

        _showBulletin = data['appContentShowBulletin'] ?? false;
        _bulletinController.text = data['appContentBulletinText'] ?? '';

        _showFeatured = data['showFeatured'] ?? false;
        _featuredType = data['featuredType'] ?? 'youtube';
        _featuredUrlController.text = data['featuredUrl'] ?? '';
        _featuredTitleController.text = data['featuredTitle'] ?? '';
        _featuredBodyController.text = data['featuredBody'] ?? '';
        _logoUrl = data['logoUrl'] as String?;
        _logoSize = (data['logoSize'] as num?)?.toDouble() ?? 80.0;

        _showReelCarousel = data['showReelCarousel'] ?? false;
        _reelAutoRotateSeconds =
            (data['reelAutoRotateSeconds'] as num?)?.toInt() ?? 8;
        final rawReels = data['reelItems'];
        if (rawReels is List) {
          _reelItems = rawReels
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        } else {
          _reelItems = [];
        }

        if (_showBackground &&
            _backgroundImageUrl != null &&
            _isVideo(_backgroundImageUrl!)) {
          _initBackgroundVideo(_backgroundImageUrl!);
        }
      } else {
        // Defaults
        _titleController.text = 'Welcome to Harmony';
        _messageController.text = 'Your journey begins here.';
      }

      // Backward compatibility: if home_screen has no logo, fall back to welcome_screen.
      if (_logoUrl == null) {
        final welcomeDoc = await FirebaseFirestore.instance
            .collection('app_config')
            .doc('welcome_screen')
            .get();
        if (welcomeDoc.exists) {
          final welcomeData = welcomeDoc.data()!;
          _logoUrl = welcomeData['logoUrl'] as String?;
          _logoSize = (welcomeData['logoSize'] as num?)?.toDouble() ?? 80.0;
        }
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

  Future<void> _saveContent() async {
    print('Saving content...');
    final user = FirebaseAuth.instance.currentUser;
    print('Current User: ${user?.uid}');

    if (_activeReelCount > kMaxActiveReels) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You have $_activeReelCount active reels. Maximum allowed is $kMaxActiveReels.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
        'backgroundAudioUrl': _backgroundAudioUrl,
        'showBackground': _showBackground,
        'appContentShowBulletin': _showBulletin,
        'appContentBulletinText': _bulletinController.text.trim(),
        'showFeatured': _showFeatured,
        'featuredType': _featuredType,
        'featuredUrl': _featuredUrlController.text.trim(),
        'featuredTitle': _featuredTitleController.text.trim(),
        'featuredBody': _featuredBodyController.text.trim(),
        'logoUrl': _logoUrl,
        'logoSize': _logoSize,
        'showReelCarousel': _showReelCarousel,
        'reelAutoRotateSeconds': _reelAutoRotateSeconds,
        'reelItems': _reelItems,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 60));

      // Welcome logo controls are stored on welcome_screen.
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('welcome_screen')
          .set({
        'logoUrl': _logoUrl,
        'logoSize': _logoSize,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 60));

      // Confirm publish reached the backend (not only local cache).
      final serverDoc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('home_screen')
          .get(const GetOptions(source: Source.server));
      final serverData = serverDoc.data() ?? <String, dynamic>{};
      final publishedShowBulletin =
          serverData['appContentShowBulletin'] == true;
        final publishedShowBackground = serverData['showBackground'] == true;
      final publishedBulletinText =
          (serverData['appContentBulletinText'] as String? ?? '').trim();
        final publishedShowFeatured = serverData['showFeatured'] == true;
        final publishedShowReelCarousel =
          serverData['showReelCarousel'] == true;
        final publishedFeaturedUrl =
          (serverData['featuredUrl'] as String? ?? '').trim();
        final publishedFeaturedType =
          (serverData['featuredType'] as String? ?? '').trim();
        final publishedLogoUrl = (serverData['logoUrl'] as String?) ?? '';
        final publishedLogoSize =
          (serverData['logoSize'] as num?)?.toDouble() ?? 80.0;
        final publishedReelAutoRotateSeconds =
          (serverData['reelAutoRotateSeconds'] as num?)?.toInt() ?? 8;
        final publishedReelItems = (serverData['reelItems'] as List?) ?? const [];
      final expectedBulletinText = _bulletinController.text.trim();
        final expectedFeaturedUrl = _featuredUrlController.text.trim();
        final expectedFeaturedType = _featuredType.trim();
      final expectedLogoUrl = _logoUrl ?? '';
      if (publishedShowBulletin != _showBulletin ||
          publishedShowBackground != _showBackground ||
          publishedBulletinText != expectedBulletinText ||
          publishedShowFeatured != _showFeatured ||
          publishedShowReelCarousel != _showReelCarousel ||
          publishedFeaturedUrl != expectedFeaturedUrl ||
          publishedFeaturedType != expectedFeaturedType ||
          publishedLogoUrl != expectedLogoUrl ||
          (publishedLogoSize - _logoSize).abs() > 0.01 ||
          publishedReelAutoRotateSeconds != _reelAutoRotateSeconds ||
          publishedReelItems.length != _reelItems.length) {
        throw Exception(
          'Publish verification failed: server home_screen values do not match the latest save.',
        );
      }

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

  Future<void> _pickFromMediaLibrary({
    required bool isBackground,
    String? typeFilter,
  }) async {
    String? selectedSection;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: StatefulBuilder(builder: (context, setState) {
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
                      typeFilter == 'audio'
                        ? 'Select Background Audio'
                        : isBackground
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
                          if (!snapshot.hasData)
                            return const LinearProgressIndicator();
                          final allItems = snapshot.data!;
                          final sections = allItems
                              .map((e) => e.section)
                              .toSet()
                              .toList()
                            ..sort();

                          return DropdownButton<String>(
                            value: selectedSection,
                            hint: const Text('Select Category'),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                  value: 'All', child: Text('All Categories')),
                              ...sections.map((s) =>
                                  DropdownMenuItem(value: s, child: Text(s))),
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
                    stream:
                        _mediaLibrary.getMediaStream(section: selectedSection),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      final allFiles = (snapshot.data ?? []).where((item) {
                        if (typeFilter == null || typeFilter.isEmpty) {
                          return true;
                        }
                        return item.type.toLowerCase() == typeFilter.toLowerCase();
                      }).toList();

                      if (allFiles.isEmpty) {
                        return const Center(
                            child: Text('No media found in this section.'));
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
                          final isYoutube = item.type == 'youtube' ||
                              urlLower.contains('youtu');
                          final isVideo = item.type == 'video' ||
                              isYoutube ||
                              urlLower.contains('.mp4') ||
                              urlLower.contains('.mov');
                            final isAudio = item.type == 'audio' ||
                              urlLower.contains('.mp3') ||
                              urlLower.contains('.wav') ||
                              urlLower.contains('.aac') ||
                              urlLower.contains('.m4a') ||
                              urlLower.contains('.ogg') ||
                              urlLower.contains('.flac');
                          final isImage = item.type == 'image' ||
                              (!isVideo &&
                                !isAudio &&
                                  (urlLower.contains('.jpg') ||
                                      urlLower.contains('.jpeg') ||
                                      urlLower.contains('.png') ||
                                      urlLower.contains('.webp')));
                          final isPdf = urlLower.contains('.pdf');

                          return InkWell(
                            onTap: () {
                              // Use the parent context's setState to update the main widget
                              this.setState(() {
                                if (typeFilter == 'audio') {
                                  if (!isAudio) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Only audio files can be selected here.'),
                                      ),
                                    );
                                    return;
                                  }
                                  _backgroundAudioUrl = item.url;
                                  return;
                                }

                                if (isBackground) {
                                  if (isPdf) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'PDF cannot be used as background')));
                                    return;
                                  }
                                  if (isAudio) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Use Background Audio selector for audio tracks.'),
                                      ),
                                    );
                                    return;
                                  }
                                  _backgroundImageUrl = item.url;
                                  _showBackground = true;
                                  if (_showBackground && isVideo && !isYoutube) {
                                    _initBackgroundVideo(item.url);
                                  } else {
                                    _backgroundVideoController?.dispose();
                                    _backgroundVideoController = null;
                                  }
                                } else {
                                  _featuredUrlController.text = item.url;
                                  _showFeatured = true;
                                  if (isYoutube) {
                                    _featuredType = 'youtube';
                                  } else if (isVideo) {
                                    _featuredType = 'video';
                                    // HtmlVideoPreview handles its own initialization — no controller needed.
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
                                        ? Image.network(
                                            item.url,
                                            fit: BoxFit.cover,
                                            errorBuilder: (ctx, _, __) =>
                                                const Center(
                                                    child: Icon(
                                                        Icons.broken_image)),
                                          )
                                        : (isVideo || isYoutube)
                                            ? VideoGridItem(
                                                url: item.url,
                                                type: isYoutube
                                                    ? 'youtube'
                                                    : 'upload',
                                                enablePreview: false,
                                              )
                                            : isAudio
                                                ? Container(
                                                    color: Colors.blueGrey.shade50,
                                                    child: const Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(Icons.audiotrack, size: 40, color: Colors.blueGrey),
                                                        SizedBox(height: 4),
                                                        Text(
                                                          'AUDIO',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.blueGrey,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  )
                                            : Container(
                                                color: Colors.grey.shade200,
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      isPdf
                                                          ? Icons.picture_as_pdf
                                                          : Icons
                                                              .insert_drive_file,
                                                      size: 40,
                                                      color: isPdf
                                                          ? Colors.red
                                                          : Colors.grey,
                                                    ),
                                                    if (isPdf)
                                                      const Text('PDF',
                                                          style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold))
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
        }),
      ),
    );
  }

  Future<void> _pickLogoFromMediaLibrary() async {
    String? selectedSection;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              width: 800,
              height: 600,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select App Logo',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Text('Filter by Section: '),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StreamBuilder<List<MediaItem>>(
                          stream: _mediaLibrary.getMediaStream(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const LinearProgressIndicator();
                            }
                            final allItems = snapshot.data!;
                            final sections = allItems
                                .map((e) => e.section)
                                .toSet()
                                .toList()
                              ..sort();

                            return DropdownButton<String>(
                              value: selectedSection,
                              hint: const Text('Select Category'),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(
                                  value: 'All',
                                  child: Text('All Categories'),
                                ),
                                ...sections.map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setDialogState(() => selectedSection = val);
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
                      stream:
                          _mediaLibrary.getMediaStream(section: selectedSection),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(child: Text('Error: ${snapshot.error}'));
                        }
                        final allFiles = snapshot.data ?? [];
                        if (allFiles.isEmpty) {
                          return const Center(
                            child: Text('No media found in this section.'),
                          );
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
                            final lower = item.url.toLowerCase();
                            final isImage = item.type == 'image' ||
                                lower.contains('.jpg') ||
                                lower.contains('.jpeg') ||
                                lower.contains('.png') ||
                                lower.contains('.webp');

                            return InkWell(
                              onTap: () {
                                if (!isImage) {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Logo must be an image (PNG/JPG/WEBP).'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }
                                setState(() => _logoUrl = item.url);
                                Navigator.pop(context);
                              },
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: isImage
                                          ? Image.network(
                                              item.url,
                                              fit: BoxFit.cover,
                                              errorBuilder: (ctx, _, __) =>
                                                  const Center(
                                                      child: Icon(
                                                          Icons.broken_image)),
                                            )
                                          : Container(
                                              color: Colors.grey.shade200,
                                              child: const Center(
                                                child: Icon(
                                                  Icons.block,
                                                  color: Colors.redAccent,
                                                ),
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
          },
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

  String _detectContentType(String url, {String? mediaTypeHint}) {
    final lower = url.toLowerCase();
    if (lower.contains('youtu')) return 'youtube';
    if (mediaTypeHint == 'video' ||
        lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('video')) {
      return 'video';
    }
    if (lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp')) {
      return 'image';
    }
    if (lower.contains('.pdf')) return 'pdf';
    return 'link';
  }

  Future<void> _addReelFromMediaLibrary() async {
    String? selectedSection;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              width: 900,
              height: 620,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Add Reel from Media Library',
                          style: Theme.of(context).textTheme.titleLarge),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Text('Filter by Section: '),
                      const SizedBox(width: 16),
                      Expanded(
                        child: StreamBuilder<List<MediaItem>>(
                          stream: _mediaLibrary.getMediaStream(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const LinearProgressIndicator();
                            }
                            final allItems = snapshot.data!;
                            final sections = allItems
                                .map((e) => e.section)
                                .toSet()
                                .toList()
                              ..sort();

                            return DropdownButton<String>(
                              value: selectedSection,
                              hint: const Text('Select Category'),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(
                                  value: 'All',
                                  child: Text('All Categories'),
                                ),
                                ...sections.map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setDialogState(() => selectedSection = val);
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
                      stream: _mediaLibrary.getMediaStream(
                          section: selectedSection),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                              child: Text('Error: ${snapshot.error}'));
                        }
                        final allFiles = snapshot.data ?? [];
                        if (allFiles.isEmpty) {
                          return const Center(
                              child: Text('No media found in this section.'));
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
                            final type = _detectContentType(
                              item.url,
                              mediaTypeHint: item.type,
                            );

                            return InkWell(
                              onTap: () {
                                if (_activeReelCount >= kMaxActiveReels) {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Maximum $kMaxActiveReels active reels reached. Disable one before adding another.',
                                      ),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                setState(() {
                                  _showReelCarousel = true;
                                  _reelItems.add({
                                    'url': item.url,
                                    'type': type,
                                    'title': item.name,
                                    'caption': '',
                                    'enabled': true,
                                  });
                                });
                                Navigator.pop(context);
                                if (mounted) {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text('Reel added: ${item.name}'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              child: Card(
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: type == 'image'
                                          ? Image.network(
                                              item.url,
                                              fit: BoxFit.cover,
                                              errorBuilder: (ctx, _, __) =>
                                                  const Center(
                                                      child: Icon(
                                                          Icons.broken_image)),
                                            )
                                          : (type == 'video' ||
                                                  type == 'youtube')
                                              ? IgnorePointer(
                                                  child: VideoGridItem(
                                                    url: item.url,
                                                    type: type == 'youtube'
                                                        ? 'youtube'
                                                        : 'upload',
                                                    enablePreview: false,
                                                  ),
                                                )
                                              : Container(
                                                  color: Colors.grey.shade200,
                                                  child: Center(
                                                    child: Icon(
                                                      type == 'pdf'
                                                          ? Icons.picture_as_pdf
                                                          : Icons.link,
                                                      size: 38,
                                                      color: type == 'pdf'
                                                          ? Colors.red
                                                          : Colors.blueGrey,
                                                    ),
                                                  ),
                                                ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(6.0),
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
          },
        ),
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

                const SizedBox(height: 24),
                _buildSectionHeader('Visuals'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Home Background'),
                  subtitle: const Text(
                    'Show the selected background on Home and enable the speaker control',
                  ),
                  value: _showBackground,
                  onChanged: (value) => setState(() {
                    _showBackground = value;
                    if (!_showBackground) {
                      _backgroundVideoController?.dispose();
                      _backgroundVideoController = null;
                    } else if (_backgroundImageUrl != null &&
                        _isVideo(_backgroundImageUrl!)) {
                      _initBackgroundVideo(_backgroundImageUrl!);
                    }
                  }),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Background Image'),
                  subtitle: Text(
                    _backgroundImageUrl != null
                        ? 'Image selected'
                        : 'No image selected (app gradient background)',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (_backgroundImageUrl != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _backgroundImageUrl = null;
                            _backgroundVideoController?.dispose();
                            _backgroundVideoController = null;
                          }),
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: () => _pickFromMediaLibrary(isBackground: true),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Select Background'),
                      ),
                    ],
                  ),
                ),

                if (_backgroundImageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                          color: Colors.grey.shade200,
                          image: !_isVideo(_backgroundImageUrl!)
                              ? DecorationImage(
                                  image: NetworkImage(_backgroundImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _isVideo(_backgroundImageUrl!)
                            ? const Icon(Icons.videocam, color: Colors.black54)
                            : null,
                      ),
                    ),
                  ),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Background Audio'),
                  subtitle: Text(
                    _backgroundAudioUrl != null
                        ? 'Audio track selected'
                        : 'No background audio (silent)',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (_backgroundAudioUrl != null)
                        TextButton(
                          onPressed: () => setState(() => _backgroundAudioUrl = null),
                          child: const Text(
                            'Remove',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: () => _pickFromMediaLibrary(
                          isBackground: true,
                          typeFilter: 'audio',
                        ),
                        icon: const Icon(Icons.audiotrack),
                        label: const Text('Select Audio'),
                      ),
                    ],
                  ),
                ),
                if (_backgroundAudioUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(Icons.audiotrack, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _backgroundAudioUrl!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 16),
                const SizedBox(height: 32),

                // 2. App Logo (Welcome Screen)
                _buildSectionHeader('App Logo (Welcome Screen)'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Logo source'),
                  subtitle: Text(
                    _logoUrl != null ? 'Custom logo selected' : 'Default icon',
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (_logoUrl != null)
                        TextButton(
                          onPressed: () => setState(() => _logoUrl = null),
                          child: const Text('Remove',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ElevatedButton.icon(
                        onPressed: _pickLogoFromMediaLibrary,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Select Logo'),
                      ),
                    ],
                  ),
                ),
                if (_logoUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _logoUrl!,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                              child: Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Logo size'),
                          Slider(
                            value: _logoSize,
                            min: 40,
                            max: 160,
                            divisions: 24,
                            label: '${_logoSize.round()} px',
                            onChanged: (v) => setState(() => _logoSize = v),
                          ),
                          Text('${_logoSize.round()} px'),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        const Text('Logo size'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Slider(
                            value: _logoSize,
                            min: 40,
                            max: 160,
                            divisions: 24,
                            label: '${_logoSize.round()} px',
                            onChanged: (v) => setState(() => _logoSize = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${_logoSize.round()} px'),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 32),

                // 3. Bulletin Board
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

                // 4. Featured Content
                _buildSectionHeader('Featured Content'),
                SwitchListTile(
                  title: const Text('Show Featured Content'),
                  subtitle: const Text('Display a video or image thumbnail'),
                  value: _showFeatured,
                  onChanged: (v) => setState(() {
                    _showFeatured = v;
                  }),
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

                const SizedBox(height: 32),

                // 6. Reel Carousel
                _buildSectionHeader('Reel Carousel (Home Loop)'),
                SwitchListTile(
                  title: const Text('Enable Reel Carousel'),
                  subtitle: const Text(
                    'Loop user reels (MP4/YouTube/images/links) on the Home screen',
                  ),
                  value: _showReelCarousel,
                  onChanged: (v) => setState(() {
                    _showReelCarousel = v;
                  }),
                ),
                if (_showReelCarousel) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Active reels: $_activeReelCount/$kMaxActiveReels',
                    style: TextStyle(
                      color: _activeReelCount > kMaxActiveReels
                          ? Colors.red
                          : Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 520) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Auto-rotate every'),
                            Slider(
                              value: _reelAutoRotateSeconds.toDouble(),
                              min: 4,
                              max: 20,
                              divisions: 16,
                              label: '$_reelAutoRotateSeconds s',
                              onChanged: (v) => setState(
                                  () => _reelAutoRotateSeconds = v.round()),
                            ),
                            Text('$_reelAutoRotateSeconds seconds'),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          const Text('Auto-rotate every'),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Slider(
                              value: _reelAutoRotateSeconds.toDouble(),
                              min: 4,
                              max: 20,
                              divisions: 16,
                              label: '$_reelAutoRotateSeconds s',
                              onChanged: (v) => setState(
                                  () => _reelAutoRotateSeconds = v.round()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$_reelAutoRotateSeconds seconds'),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _addReelFromMediaLibrary,
                        icon: const Icon(Icons.video_library),
                        label: const Text('Add Reel from Library'),
                      ),
                      const SizedBox(width: 12),
                      if (_reelItems.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () => setState(() => _reelItems.clear()),
                          icon: const Icon(Icons.delete_sweep),
                          label: const Text('Clear All'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_reelItems.isEmpty)
                    const Text(
                      'No reels added yet. Add clips from Media Library to start the carousel.',
                      style: TextStyle(color: Colors.grey),
                    )
                  else
                    Column(
                      children: List.generate(_reelItems.length, (index) {
                        final item = _reelItems[index];
                        final title = (item['title'] as String?) ?? '';
                        final caption = (item['caption'] as String?) ?? '';
                        final url = (item['url'] as String?) ?? '';
                        final type = (item['type'] as String?) ?? 'video';
                        final enabled = item['enabled'] != false;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '${index + 1}. ${title.isEmpty ? 'Untitled Reel' : title}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Switch(
                                      value: enabled,
                                      onChanged: (v) {
                                        if (v &&
                                            !enabled &&
                                            _activeReelCount >=
                                                kMaxActiveReels) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Maximum $kMaxActiveReels active reels reached.',
                                              ),
                                              backgroundColor: Colors.orange,
                                            ),
                                          );
                                          return;
                                        }

                                        setState(
                                          () => _reelItems[index]['enabled'] = v,
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.arrow_upward),
                                      onPressed: index == 0
                                          ? null
                                          : () => setState(() {
                                                final tmp =
                                                    _reelItems[index - 1];
                                                _reelItems[index - 1] =
                                                    _reelItems[index];
                                                _reelItems[index] = tmp;
                                              }),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.arrow_downward),
                                      onPressed: index == _reelItems.length - 1
                                          ? null
                                          : () => setState(() {
                                                final tmp =
                                                    _reelItems[index + 1];
                                                _reelItems[index + 1] =
                                                    _reelItems[index];
                                                _reelItems[index] = tmp;
                                              }),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () => setState(
                                          () => _reelItems.removeAt(index)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Chip(label: Text(type.toUpperCase())),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        url,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: title,
                                  decoration: const InputDecoration(
                                    labelText: 'Display Title',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) =>
                                      _reelItems[index]['title'] = v,
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: caption,
                                  decoration: const InputDecoration(
                                    labelText: 'Caption (optional)',
                                    border: OutlineInputBorder(),
                                  ),
                                  maxLines: 2,
                                  onChanged: (v) =>
                                      _reelItems[index]['caption'] = v,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
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

        // Right Side: Preview Panel (wider for better content visibility)
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('LIVE PREVIEW',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Container(
                      width: 420,
                      height: 850,
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
                                image: _showBackground &&
                                        _backgroundImageUrl != null &&
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
                                    child: _showBackground &&
                                      _backgroundImageUrl != null &&
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
                            if (_showBackground &&
                                _backgroundImageUrl != null &&
                                _isVideo(_backgroundImageUrl!))
                              Container(
                                  color: Colors.black.withOpacity(
                                      0.4)), // Overlay for video legibility

                            if (_showBackground && _backgroundImageUrl != null)
                              Positioned(
                                right: 14,
                                top: 14,
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.34),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.32),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.volume_up_rounded,
                                    color: Colors.white70,
                                    size: 22,
                                  ),
                                ),
                              ),

                            // Content
                            SafeArea(
                              child: SingleChildScrollView(
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // App Bar Mock
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const SizedBox(width: 24),
                                          const Text('Harmony',
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 24),
                                        ],
                                      ),
                                      const SizedBox(height: 40),

                                      // Main Text
                                      if (_logoUrl != null)
                                        SizedBox(
                                          width: _logoSize,
                                          height: _logoSize,
                                          child: Image.network(
                                            _logoUrl!,
                                            fit: BoxFit.contain,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const SizedBox.shrink(),
                                          ),
                                        )
                                      else
                                        const SizedBox.shrink(),
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
                                            color: Colors.white70,
                                            fontSize: 16),
                                        textAlign: TextAlign.center,
                                      ),

                                      const SizedBox(height: 32),

                                      // Bulletin Board
                                      if (_showBulletin)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.white.withOpacity(0.15),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color: Colors.white30),
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

                                      if (_showFeatured)
                                        Builder(builder: (_) {
                                          final featuredTitle =
                                              _featuredTitleController.text.trim();
                                          final featuredBody =
                                              _featuredBodyController.text.trim();
                                          final enabledReels = _reelItems
                                              .where((item) =>
                                                  item['enabled'] != false &&
                                                  ((item['url'] as String?)
                                                              ?.trim()
                                                              .isNotEmpty ??
                                                          false))
                                              .toList();

                                          Widget featuredCard() {
                                            return Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color:
                                                    Colors.white.withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                border: Border.all(
                                                    color: Colors.white24),
                                              ),
                                              child: Stack(
                                                children: [
                                                  Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      if (featuredTitle
                                                          .isNotEmpty)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  bottom: 8,
                                                                  right: 72),
                                                          child: Text(
                                                            featuredTitle,
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 16,
                                                            ),
                                                            textAlign:
                                                                TextAlign.left,
                                                          ),
                                                        ),
                                                      if (featuredBody
                                                          .isNotEmpty)
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .only(
                                                                  bottom: 12,
                                                                  right: 72),
                                                          child: Text(
                                                            featuredBody,
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .white70,
                                                              fontSize: 14,
                                                            ),
                                                            textAlign:
                                                                TextAlign.left,
                                                          ),
                                                        ),
                                                      _buildFeaturedPreview(),
                                                    ],
                                                  ),
                                                  if (_showReelCarousel &&
                                                      enabledReels.isNotEmpty)
                                                    Positioned(
                                                      top: 0,
                                                      right: 0,
                                                      child: Tooltip(
                                                        message: 'Open Reels',
                                                        child: GestureDetector(
                                                          onTap:
                                                              _openReelsFullscreenPreview,
                                                          child: const Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .play_circle_fill_rounded,
                                                                color: Colors
                                                                    .white70,
                                                                size: 26,
                                                              ),
                                                              SizedBox(
                                                                  width: 4),
                                                              Text(
                                                                'Reels',
                                                                style:
                                                                    TextStyle(
                                                                  color: Colors
                                                                      .white70,
                                                                  fontSize: 13,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            );
                                          }

                                          return featuredCard();
                                        })
                                      else if (_showReelCarousel)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.white.withOpacity(0.08),
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color: Colors.white24),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Row(
                                                children: [
                                                  Icon(Icons.slideshow,
                                                      color: Colors.amber,
                                                      size: 16),
                                                  SizedBox(width: 8),
                                                  Text(
                                                    'Reel Carousel',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton.icon(
                                                  onPressed:
                                                      _openReelsFullscreenPreview,
                                                  icon: const Icon(Icons
                                                      .play_circle_fill_rounded),
                                                  label: const Text(
                                                      'Open Reels Full Screen'),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      const SizedBox(height: 32),
                                      const SizedBox(height: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Bottom navigation mock (matches user app tab layout)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.36),
                                  border: Border(
                                    top: BorderSide(color: Colors.white.withOpacity(0.16)),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _PreviewNavItem(
                                      icon: Icons.home,
                                      label: 'Home',
                                      selected: true,
                                    ),
                                    _PreviewNavItem(
                                      icon: Icons.event,
                                      label: 'Events',
                                    ),
                                    _PreviewNavItem(
                                      icon: Icons.chat,
                                      label: 'Community',
                                    ),
                                    _PreviewNavItem(
                                      icon: Icons.lightbulb_outline,
                                      label: 'Topics',
                                    ),
                                    _PreviewNavItem(
                                      icon: Icons.person_outline,
                                      label: 'My Harmony',
                                    ),
                                  ],
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
        // Wrap in a fixed-height box so the 16:9 thumbnail is not squashed.
        return SizedBox(
          height: 210,
          child: VideoGridItem(
            url: _featuredUrlController.text,
            type: 'youtube',
            enablePreview: true,
          ),
        );
      case 'video':
        // Use HtmlVideoPreview — much more reliable on Flutter Web than VideoPlayerController.
        // The native browser <video> element handles CORS, range requests and codecs directly.
        return SizedBox(
          height: 300,
          child: HtmlVideoPreview(
            url: _featuredUrlController.text,
            autoPlay: true,
            loop: true,
            muted: true,
            controls: true,
          ),
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
                  Text("Image not found",
                      style: TextStyle(color: Colors.white54, fontSize: 10)),
                ],
              ),
            ),
          ),
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildReelPreview() {
    final enabledItems =
        _reelItems.where((e) => e['enabled'] != false).toList();
    if (enabledItems.isEmpty) {
      return const Text(
        'Carousel enabled but no active reels.',
        style: TextStyle(color: Colors.white70),
      );
    }

    final item = enabledItems.first;
    final type = (item['type'] as String?) ?? 'video';
    final url = (item['url'] as String?) ?? '';
    final title = (item['title'] as String?) ?? 'Reel';
    final caption = (item['caption'] as String?) ?? '';

    Widget media;
    if (type == 'youtube') {
      media = SizedBox(
        height: 340,
        child: VideoGridItem(url: url, type: 'youtube', enablePreview: true),
      );
    } else if (type == 'video') {
      media = SizedBox(
        height: 340,
        child: HtmlVideoPreview(
          url: url,
          autoPlay: true,
          loop: true,
          muted: true,
          controls: false,
          objectFit: 'cover',
        ),
      );
    } else if (type == 'image') {
      media = SizedBox(
        height: 340,
        child: Image.network(url, fit: BoxFit.cover),
      );
    } else {
      media = SizedBox(
        height: 120,
        child: Center(
          child: Text(
            type == 'pdf' ? 'PDF Reel' : 'Link Reel',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.slideshow, color: Colors.amber, size: 16),
            const SizedBox(width: 8),
            Text(
              'Reel Carousel (${enabledItems.length} active)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        media,
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        if (caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              caption,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
      ],
    );
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

  /// Pop-out dialog showing the featured content at full usable size.
  void _openFullSizePreview() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: _featuredType == 'video'
                  ? HtmlVideoPreview(
                      url: _featuredUrlController.text,
                      autoPlay: true,
                      loop: false,
                      muted: false,
                      controls: true,
                    )
                  : _buildFeaturedPreview(),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openReelsFullscreenPreview() {
    final active = _reelItems.where((item) {
      final enabled = (item['enabled'] as bool?) ?? true;
      final url = (item['url'] as String?)?.trim() ?? '';
      return enabled && url.isNotEmpty;
    }).toList();

    if (active.isEmpty) return;

    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: false,
        builder: (_) => _AdminReelsFullscreenPreview(items: active),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin preview flip card — mirrors the user app _FlipContentCard exactly.
// Front face: featured content + amber carousel icon (top-right) + swipe.
// Back face: reel carousel + back arrow (top-left). Carousel taps are
// reserved for pause/play/swipe between items.
// ---------------------------------------------------------------------------
class _AdminPreviewFlipCard extends StatefulWidget {
  final Widget frontCard;
  final Widget backContent;

  const _AdminPreviewFlipCard({
    required this.frontCard,
    required this.backContent,
  });

  @override
  State<_AdminPreviewFlipCard> createState() => _AdminPreviewFlipCardState();
}

class _AdminPreviewFlipCardState extends State<_AdminPreviewFlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _animation = Tween<double>(begin: 0.0, end: pi).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _animation.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _showBack = false);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flipToCarousel() {
    if (_showBack) return;
    setState(() => _showBack = true);
    _controller.forward();
  }

  void _flipToFront() {
    if (!_showBack) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        final angle = _animation.value;
        final isShowingFront = angle <= pi / 2;

        final Widget face = isShowingFront
            ? _buildFrontFace()
            : Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()..rotateY(pi),
                child: _buildBackFace(),
              );

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: face,
        );
      },
    );
  }

  Widget _buildFrontFace() {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 300) _flipToCarousel();
      },
      child: Stack(
        children: [
          widget.frontCard,
          Positioned(
            top: 0,
            right: 0,
            child: Tooltip(
              message: 'View Reel Carousel',
              child: GestureDetector(
                onTap: _flipToCarousel,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.view_carousel_outlined,
                    color: Colors.amberAccent,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackFace() {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0).abs() > 300) _flipToFront();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(
              message: 'Back to featured',
              child: TextButton.icon(
                onPressed: _flipToFront,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Back to Featured'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.black.withOpacity(0.45),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            widget.backContent,
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin reel carousel preview — auto-rotating PageView of all enabled items.
// Uses web-compatible widgets (HtmlVideoPreview / VideoGridItem / Image).
// Mirrors the user app _HomeReelCarousel behaviour.
// ---------------------------------------------------------------------------
class _AdminReelCarouselPreview extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int autoRotateSeconds;

  const _AdminReelCarouselPreview({
    required this.items,
    required this.autoRotateSeconds,
  });

  @override
  State<_AdminReelCarouselPreview> createState() =>
      _AdminReelCarouselPreviewState();
}

class _AdminReelCarouselPreviewState
    extends State<_AdminReelCarouselPreview> {
  late final PageController _pageController;
  Timer? _autoRotateTimer;
  int _currentPage = 0;

  List<Map<String, dynamic>> get _enabledItems =>
      widget.items.where((item) {
        final enabled = (item['enabled'] as bool?) ?? true;
        final url = (item['url'] as String?)?.trim() ?? '';
        return enabled && url.isNotEmpty;
      }).toList();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoRotate();
  }

  @override
  void didUpdateWidget(covariant _AdminReelCarouselPreview old) {
    super.didUpdateWidget(old);
    if (old.items != widget.items ||
        old.autoRotateSeconds != widget.autoRotateSeconds) {
      if (_currentPage >= _enabledItems.length) _currentPage = 0;
      _startAutoRotate();
    }
  }

  void _startAutoRotate() {
    _autoRotateTimer?.cancel();
    final active = _enabledItems;
    if (active.length < 2) return;
    final secs = widget.autoRotateSeconds.clamp(4, 20);
    _autoRotateTimer = Timer.periodic(Duration(seconds: secs), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_currentPage + 1) % active.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _autoRotateTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildItemMedia(Map<String, dynamic> item) {
    final url = (item['url'] as String?)?.trim() ?? '';
    final type =
        ((item['type'] as String?)?.toLowerCase().trim()) ?? 'video';

    if (type == 'youtube') {
      return SizedBox(
        height: 200,
        child: VideoGridItem(url: url, type: 'youtube', enablePreview: true),
      );
    }
    if (type == 'image') {
      return SizedBox(
        height: 200,
        child: Image.network(url, fit: BoxFit.cover, width: double.infinity),
      );
    }
    // video (default)
    return SizedBox(
      height: 200,
      child: HtmlVideoPreview(
        url: url,
        autoPlay: true,
        loop: true,
        muted: true,
        controls: false,
        objectFit: 'cover',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _enabledItems;
    if (active.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Carousel enabled but no active reels.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.slideshow, color: Colors.amber, size: 16),
            const SizedBox(width: 8),
            Text(
              'Reel Carousel (${active.length} active)',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: PageView.builder(
            controller: _pageController,
            itemCount: active.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final item = active[index];
              final title = (item['title'] as String?)?.trim() ?? '';
              final caption = (item['caption'] as String?)?.trim() ?? '';

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.black54,
                  child: Column(
                    children: [
                      Expanded(child: _buildItemMedia(item)),
                      if (title.isNotEmpty || caption.isNotEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (title.isNotEmpty)
                                Text(
                                  title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11),
                                ),
                              if (caption.isNotEmpty)
                                Text(
                                  caption,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (active.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${_currentPage + 1} / ${active.length}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }
}

class _PreviewNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;

  const _PreviewNavItem({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.amber : Colors.white70;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _AdminReelsFullscreenPreview extends StatefulWidget {
  final List<Map<String, dynamic>> items;

  const _AdminReelsFullscreenPreview({required this.items});

  @override
  State<_AdminReelsFullscreenPreview> createState() =>
      _AdminReelsFullscreenPreviewState();
}

class _AdminReelsFullscreenPreviewState
    extends State<_AdminReelsFullscreenPreview> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Widget _buildMedia(Map<String, dynamic> item) {
    final url = (item['url'] as String?)?.trim() ?? '';
    final type = ((item['type'] as String?)?.toLowerCase().trim()) ?? 'video';

    if (type == 'youtube') {
      return VideoGridItem(url: url, type: 'youtube', enablePreview: true);
    }
    if (type == 'image') {
      return Image.network(url, fit: BoxFit.cover, width: double.infinity);
    }
    return HtmlVideoPreview(
      url: url,
      autoPlay: true,
      loop: false,
      muted: false,
      controls: true,
      objectFit: 'cover',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            allowImplicitScrolling: true,
            itemCount: widget.items.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final title = (item['title'] as String?)?.trim() ?? '';
              final caption = (item['caption'] as String?)?.trim() ?? '';

              return Stack(
                children: [
                  Positioned.fill(child: _buildMedia(item)),
                  if (title.isNotEmpty || caption.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black87],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (title.isNotEmpty)
                              Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            if (caption.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  caption,
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          Positioned(
            left: 12,
            top: 12,
            child: CircleAvatar(
              backgroundColor: Colors.black.withOpacity(0.55),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_currentPage + 1} / ${widget.items.length}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
