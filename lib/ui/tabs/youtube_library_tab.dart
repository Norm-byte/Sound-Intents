import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/video_widgets.dart';
// ignore: avoid_web_libraries_in_flutter
// ignore: avoid_web_libraries_in_flutter
import '../../services/media_library_service.dart';
import '../../models/media_item.dart';
import '../../models/content_section.dart';

class YoutubeLibraryTab extends StatefulWidget {
  const YoutubeLibraryTab({super.key});

  @override
  State<YoutubeLibraryTab> createState() => _YoutubeLibraryTabState();
}

class _YoutubeLibraryTabState extends State<YoutubeLibraryTab> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isLoading = false;
  bool _isPublishing = false;
  bool _isLoadingDrafts = true;
  final MediaLibraryService _mediaLibraryService = MediaLibraryService();

  // Draft Collections (Admin edits these)
  final CollectionReference _videosCollection = 
      FirebaseFirestore.instance.collection('youtube_library_draft');
  final CollectionReference _sectionsCollection = 
      FirebaseFirestore.instance.collection('youtube_sections_draft');

  // Live Collections (User App reads these)
  final CollectionReference _liveVideosCollection = 
      FirebaseFirestore.instance.collection('youtube_library');
  final CollectionReference _liveSectionsCollection = 
      FirebaseFirestore.instance.collection('youtube_sections');

  List<ContentSection> _sections = [];
  String? _selectedSectionId;
  String? _selectedSubcategory; // For content creation/editing
  String? _previewSectionId; // For the phone preview navigation
  String? _previewSubcategory; // For subcategory navigation in preview

  @override
  void initState() {
    super.initState();
    _initDrafts();
    _sectionsCollection.orderBy('order').snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _sections = snapshot.docs
              .map((doc) => ContentSection.fromMap(doc.id, doc.data() as Map<String, dynamic>))
              .toList();
        });
      }
    });
  }

  Future<void> _initDrafts() async {
    try {
      // Check if drafts exist
      final draftSections = await _sectionsCollection.limit(1).get();
      final draftVideos = await _videosCollection.limit(1).get();

      if (draftSections.docs.isEmpty && draftVideos.docs.isEmpty) {
        debugPrint('Initializing drafts from live data...');
        
        // Copy Sections
        final liveSections = await _liveSectionsCollection.get();
        final batch = FirebaseFirestore.instance.batch();
        
        for (var doc in liveSections.docs) {
          batch.set(_sectionsCollection.doc(doc.id), doc.data());
        }

        // Copy Videos
        final liveVideos = await _liveVideosCollection.get();
        for (var doc in liveVideos.docs) {
          batch.set(_videosCollection.doc(doc.id), doc.data());
        }

        await batch.commit();
        debugPrint('Drafts initialized.');
      }
    } catch (e) {
      debugPrint('Error initializing drafts: $e');
    } finally {
      if (mounted) setState(() => _isLoadingDrafts = false);
    }
  }

  Future<void> _syncFromLive() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sync from Live?'),
        content: const Text(
          'This will overwrite your current DRAFT with the LIVE content.\n'
          'Use this if you see content in the App that is missing from the Admin panel.\n\n'
          'Warning: Any unsaved draft changes will be lost.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            child: const Text('Overwrite Draft'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoadingDrafts = true);
    try {
      // 1. Delete all Draft Data
      final draftSections = await _sectionsCollection.get();
      final draftVideos = await _videosCollection.get();
      final batch = FirebaseFirestore.instance.batch();

      for (var doc in draftSections.docs) batch.delete(doc.reference);
      for (var doc in draftVideos.docs) batch.delete(doc.reference);

      // 2. Copy Live to Draft
      final liveSections = await _liveSectionsCollection.get();
      final liveVideos = await _liveVideosCollection.get();

      for (var doc in liveSections.docs) {
        batch.set(_sectionsCollection.doc(doc.id), doc.data());
      }
      for (var doc in liveVideos.docs) {
        batch.set(_videosCollection.doc(doc.id), doc.data());
      }

      await batch.commit();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drafts synced from Live successfully')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error syncing: $e')));
    } finally {
      if (mounted) setState(() => _isLoadingDrafts = false);
    }
  }

  Future<void> _publishChanges() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Publish Changes?'),
        content: const Text(
          'This will make all your current changes live to all users.\n\n'
          '1. Current live content will be replaced by your draft content.\n'
          '2. Users will see the new categories and videos immediately.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Publish Live'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isPublishing = true);
    try {
      // 1. Get all Draft Data
      final draftSectionsSnapshot = await _sectionsCollection.get();
      final draftVideosSnapshot = await _videosCollection.get();

      // 2. Get all Live Data (to delete)
      final liveSectionsSnapshot = await _liveSectionsCollection.get();
      final liveVideosSnapshot = await _liveVideosCollection.get();

      final batch = FirebaseFirestore.instance.batch();

      // 3. Delete all Live Data
      for (var doc in liveSectionsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      for (var doc in liveVideosSnapshot.docs) {
        batch.delete(doc.reference);
      }

      // 4. Write Draft Data to Live
      for (var doc in draftSectionsSnapshot.docs) {
        batch.set(_liveSectionsCollection.doc(doc.id), doc.data());
      }
      for (var doc in draftVideosSnapshot.docs) {
        batch.set(_liveVideosCollection.doc(doc.id), doc.data());
      }

      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Changes published successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error publishing: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _extractYoutubeId(String url) {
    if (url.trim().isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    // Handle standard v parameter
    if (uri.queryParameters.containsKey('v')) {
      return uri.queryParameters['v'];
    }

    // Handle youtu.be
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }

    // Handle shorts and live
    if (uri.pathSegments.isNotEmpty) {
      if (uri.pathSegments.contains('shorts')) {
        final index = uri.pathSegments.indexOf('shorts');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }
      if (uri.pathSegments.contains('live')) {
        final index = uri.pathSegments.indexOf('live');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }
    }
    
    return null;
  }

  // --- Section Logic ---

  void _showManageSectionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage Sections'),
        content: SizedBox(
          width: 400,
          height: 400,
          child: StreamBuilder<QuerySnapshot>(
            stream: _sectionsCollection.orderBy('order').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              final sections = docs.map((doc) => ContentSection.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
              
              return Column(
                children: [
                  Expanded(
                    child: ReorderableListView(
                      onReorder: (oldIndex, newIndex) {
                        if (oldIndex < newIndex) {
                          newIndex -= 1;
                        }
                        final item = sections.removeAt(oldIndex);
                        sections.insert(newIndex, item);
                        _updateSectionOrder(sections);
                      },
                      children: sections.map((section) {
                        return ListTile(
                          key: ValueKey(section.id),
                          title: Text(section.title),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _editSection(section),
                                tooltip: 'Edit',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteSection(section.id),
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _titleController,
                          decoration: const InputDecoration(
                            labelText: 'New Section Title',
                            hintText: 'e.g. Meditation',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: _addSection,
                      ),
                    ],
                  ),
                ],
              );
            }
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _addSection() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    try {
      await _sectionsCollection.add({
        'title': title,
        'order': _sections.length,
        'featuredContentId': null,
      });
      _titleController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _deleteSection(String id) async {
    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Section?'),
        content: const Text('This will remove the section and all its content links from the app. The content will remain in the Media Library. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _setLoading(true);
    try {
      // 1. Delete all videos in this section
      final videos = await _videosCollection.where('sectionId', isEqualTo: id).get();
      final batch = FirebaseFirestore.instance.batch();
      for (var doc in videos.docs) {
        batch.delete(doc.reference);
      }
      
      // 2. Delete the section
      batch.delete(_sectionsCollection.doc(id));
      
      await batch.commit();
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section and content links deleted')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _renameSection(String id, String currentTitle) async {
    final controller = TextEditingController(text: currentTitle);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) {
         final controller = TextEditingController(text: currentTitle);
         // Subcategories Controller... simple comma separated for now? Or proper UI?
         // Let's stick to title for this precise dialog, we need a separate Edit Section dialog to manage subcategories properly
         return AlertDialog(
          title: const Text('Rename Section'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Section Title'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      }
    );

    if (newTitle != null && newTitle.isNotEmpty && newTitle != currentTitle) {
      try {
        await _sectionsCollection.doc(id).update({'title': newTitle});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section renamed')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _editSection(ContentSection section) async {
      final titleController = TextEditingController(text: section.title);
      // We'll manage subcategories as a List<String>
      List<String> subcategories = List.from(section.subcategories);
      final subcategoryController = TextEditingController();

      await showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
           builder: (context, setState) {
             return AlertDialog(
               title: const Text('Edit Topic Section'),
               content: SizedBox(
                 width: 400,
                 child: Column(
                   mainAxisSize: MainAxisSize.min,
                   children: [
                     TextField(
                       controller: titleController,
                       decoration: const InputDecoration(labelText: 'Topic Title', border: OutlineInputBorder()),
                     ),
                     const SizedBox(height: 16),
                     const Text('Subcategories', style: TextStyle(fontWeight: FontWeight.bold)),
                     const SizedBox(height: 8),
                     Row(
                       children: [
                         Expanded(
                           child: TextField(
                             controller: subcategoryController,
                             decoration: const InputDecoration(
                               hintText: 'Add subcategory...',
                               border: OutlineInputBorder(),
                               contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                             ),
                           ),
                         ),
                         IconButton(
                           icon: const Icon(Icons.add_circle, color: Colors.indigo),
                           onPressed: () {
                             if (subcategoryController.text.isNotEmpty) {
                               setState(() {
                                 subcategories.add(subcategoryController.text.trim());
                                 subcategoryController.clear();
                               });
                             }
                           },
                         )
                       ],
                     ),
                     const SizedBox(height: 8),
                     SizedBox(
                       height: 150,
                       width: double.maxFinite,
                       child: ListView.builder(
                         shrinkWrap: true,
                         itemCount: subcategories.length,
                         itemBuilder: (ctx, i) => ListTile(
                           dense: true,
                           title: Text(subcategories[i]),
                           trailing: Row(
                             mainAxisSize: MainAxisSize.min,
                             children: [
                               IconButton(
                                 icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                 onPressed: () async {
                                     final newName = await showDialog<String>(
                                       context: context,
                                       builder: (c) {
                                         final tc = TextEditingController(text: subcategories[i]);
                                         return AlertDialog(
                                           title: const Text('Rename Subcategory'),
                                           content: TextField(controller: tc, autofocus: true),
                                           actions: [
                                             TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
                                             ElevatedButton(onPressed: () => Navigator.pop(c, tc.text.trim()), child: const Text('Rename')),
                                           ]
                                         );
                                       }
                                     );
                                     if (newName != null && newName.isNotEmpty) {
                                       setState(() => subcategories[i] = newName);
                                     }
                                 }, 
                               ),
                               IconButton(
                                 icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                 onPressed: () => setState(() => subcategories.removeAt(i)), 
                               ),
                             ],
                           ),
                         ),
                       ),
                     )
                   ],
                 ),
               ),
               actions: [
                 TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                 ElevatedButton(
                   onPressed: () async {
                      try {
                        await _sectionsCollection.doc(section.id).update({
                          'title': titleController.text.trim(),
                          'subcategories': subcategories,
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section updated')));
                      } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                   },
                   child: const Text('Save Changes'),
                 )
               ],
             );
           }
        )
      );
  }

  Future<void> _updateSectionOrder([List<ContentSection>? sections]) async {
    final list = sections ?? _sections;
    final batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < list.length; i++) {
      batch.update(_sectionsCollection.doc(list[i].id), {'order': i});
    }
    await batch.commit();
  }

  // --- Add Content Logic ---

  void _showAddContentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Content Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.youtube_searched_for, color: Colors.red),
              title: const Text('YouTube URL'),
              onTap: () {
                Navigator.pop(context);
                _showAddYoutubeDialog();
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library, color: Colors.indigo),
              title: const Text('Media Library'),
              onTap: () {
                Navigator.pop(context);
                _showMediaLibraryPicker();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAddYoutubeDialog() {
    _urlController.clear();
    _titleController.clear();
    _descriptionController.clear();
    // Default to the currently viewed section if available
    _selectedSectionId = _previewSectionId;
    _selectedSubcategory = _previewSubcategory;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          List<String> availableSubcategories = [];
          if (_selectedSectionId != null) {
            try {
               final section = _sections.firstWhere((s) => s.id == _selectedSectionId);
               availableSubcategories = section.subcategories;
            } catch (_) {}
          }

          return AlertDialog(
            title: const Text('Add YouTube Video'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'YouTube URL',
                    hintText: 'https://www.youtube.com/watch?v=...',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSectionId,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('User Topics Landing View (General)')),
                    ..._sections.map((s) => DropdownMenuItem(value: s.id, child: Text(s.title))),
                  ],
                  onChanged: (value) => setDialogState(() {
                      if (value != _selectedSectionId) {
                        _selectedSectionId = value;
                        _selectedSubcategory = null;
                      }
                  }),
                ),
                const SizedBox(height: 16),
                
                 if (_selectedSectionId != null && availableSubcategories.isNotEmpty) ...[
                   DropdownButtonFormField<String>(
                    initialValue: availableSubcategories.contains(_selectedSubcategory) ? _selectedSubcategory : null,
                    decoration: const InputDecoration(labelText: 'Subcategory'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None (General in Section)')),
                      ...availableSubcategories.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (value) => setDialogState(() => _selectedSubcategory = value),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _addYoutubeVideo();
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addYoutubeVideo() async {
    final url = _urlController.text.trim();
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (url.isEmpty || title.isEmpty) return;

    final videoId = _extractYoutubeId(url);
    if (videoId == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid YouTube URL')));
      return;
    }

    _setLoading(true);
    try {
      final thumbnailUrl = 'https://img.youtube.com/vi/$videoId/0.jpg';
      await _videosCollection.add({
        'type': 'youtube',
        'url': url,
        'title': title,
        'description': description,
        'videoId': videoId,
        'thumbnailUrl': thumbnailUrl,
        'isFeatured': false,
        'sectionId': _selectedSectionId,
        'subcategory': _selectedSubcategory,
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 5));

      // Also save to Media Library
      try {
        await _mediaLibraryService.addExternalMedia(
          name: title,
          url: url,
          type: 'video',
          section: 'General',
        );
      } catch (e) {
        debugPrint('Error saving to Media Library: $e');
        // Don't block success if this fails, but log it
      }
      
      // Clear inputs on success
      _urlController.clear();
      _titleController.clear();
      _descriptionController.clear();
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video added successfully')));
    } catch (e) {
      debugPrint('Error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding video: $e')));
    } finally {
      _setLoading(false);
    }
  }

  void _showMediaLibraryPicker() {
    String? selectedFilterSection;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            child: Container(
              width: 800,
              height: 600,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Header with Filter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select from Library', style: Theme.of(context).textTheme.titleLarge),
                      
                      // Filter Dropdown
                      StreamBuilder<List<MediaItem>>(
                        stream: _mediaLibraryService.getMediaStream(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox();
                          final allItems = snapshot.data!;
                          final sections = allItems.map((e) => e.section).toSet().toList()..sort();
                          
                          return DropdownButton<String>(
                            value: selectedFilterSection,
                            hint: const Text('All Categories'),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('All Categories')),
                              ...sections.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                            ],
                            onChanged: (val) => setState(() => selectedFilterSection = val),
                          );
                        },
                      ),

                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: StreamBuilder<List<MediaItem>>(
                      stream: _mediaLibraryService.getMediaStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        final allItems = snapshot.data!;
                        
                        // Filter items
                        final items = selectedFilterSection == null 
                            ? allItems 
                            : allItems.where((i) => i.section == selectedFilterSection).toList();

                        if (items.isEmpty) {
                          return const Center(child: Text('No items found in this category'));
                        }

                        return GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, crossAxisSpacing: 10, mainAxisSpacing: 10),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return InkWell(
                              onTap: () {
                                Navigator.pop(context);
                                _addLibraryItem(item);
                              },
                              child: Card(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: item.type == 'image' 
                                        ? Image.network(item.url, fit: BoxFit.cover)
                                        : VideoGridItem(
                                            url: item.url, 
                                            type: 'upload',
                                            enablePreview: false, // Disable preview tap to allow selection
                                            autoPlay: false,
                                          ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        }
      ),
    );
  }

  Future<void> _addLibraryItem(MediaItem item) async {
    // Prompt for details
    _titleController.text = item.name;

    _descriptionController.clear();
    // Default to the currently viewed section if available
    _selectedSectionId = _previewSectionId;
    _selectedSubcategory = _previewSubcategory;
    
    // Capture the State context to use safely after dialog pop
    final stateContext = context;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          List<String> availableSubcategories = [];
          if (_selectedSectionId != null) {
            try {
              final section = _sections.firstWhere((s) => s.id == _selectedSectionId);
              availableSubcategories = section.subcategories;
            } catch (_) {}
          }

          return AlertDialog(
            title: const Text('Confirm Details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSectionId,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None (General)')),
                    ..._sections.map((s) => DropdownMenuItem(value: s.id, child: Text(s.title))),
                  ],
                  onChanged: (value) => setDialogState(() {
                      if (value != _selectedSectionId) {
                        _selectedSectionId = value;
                        _selectedSubcategory = null;
                      }
                  }),
                ),
                const SizedBox(height: 16),
                
                 if (_selectedSectionId != null && availableSubcategories.isNotEmpty) ...[
                   DropdownButtonFormField<String>(
                    initialValue: availableSubcategories.contains(_selectedSubcategory) ? _selectedSubcategory : null,
                    decoration: const InputDecoration(labelText: 'Subcategory'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None (General in Section)')),
                      ...availableSubcategories.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (value) => setDialogState(() => _selectedSubcategory = value),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  _setLoading(true);
                  try {
                    // Check if it's a YouTube URL
                    String type = item.type;
                    String thumbnailUrl = item.type == 'image' ? item.url : '';
                    
                    final youtubeId = _extractYoutubeId(item.url);
                    if (youtubeId != null) {
                      type = 'youtube';
                      thumbnailUrl = 'https://img.youtube.com/vi/$youtubeId/0.jpg';
                    }

                    await _videosCollection.add({
                      'type': type, // 'youtube', 'video' or 'image'
                      'url': item.url,
                      'title': _titleController.text,
                      'description': _descriptionController.text,
                      'thumbnailUrl': thumbnailUrl,
                      'isFeatured': false,
                      'sectionId': _selectedSectionId,
                      'subcategory': _selectedSubcategory,
                      'createdAt': FieldValue.serverTimestamp(),
                    }).timeout(const Duration(seconds: 5));
                    if (mounted) ScaffoldMessenger.of(stateContext).showSnackBar(const SnackBar(content: Text('Item added successfully')));
                  } catch (e) {
                    debugPrint('Error adding library item: $e');
                    if (mounted) ScaffoldMessenger.of(stateContext).showSnackBar(SnackBar(content: Text('Error: $e')));
                  } finally {
                    _setLoading(false);
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _setLoading(bool value) {
    if (mounted) {
      setState(() => _isLoading = value);
    }
  }

  Future<void> _uploadLocalFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.bytes != null) {
      final file = result.files.single;
      
      // Prompt for details first
      _titleController.text = file.name;
      _descriptionController.clear();
      // Default to the currently viewed section if available
      _selectedSectionId = _previewSectionId;
      _selectedSubcategory = _previewSubcategory;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            
            List<String> availableSubcategories = [];
            if (_selectedSectionId != null) {
              try {
                final section = _sections.firstWhere((s) => s.id == _selectedSectionId);
                availableSubcategories = section.subcategories;
              } catch (_) {}
            }

            return AlertDialog(
              title: const Text('Upload & Add'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedSectionId,
                    decoration: const InputDecoration(labelText: 'Section'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('User Topics Landing View Topics Landing View (General)')),
                      ..._sections.map((s) => DropdownMenuItem(value: s.id, child: Text(s.title))),
                    ],
                    onChanged: (value) => setDialogState(() {
                        if (value != _selectedSectionId) {
                          _selectedSectionId = value;
                          _selectedSubcategory = null;
                        }
                    }),
                  ),
                  const SizedBox(height: 16),
                  
                  if (_selectedSectionId != null && availableSubcategories.isNotEmpty) ...[
                   DropdownButtonFormField<String>(
                    initialValue: availableSubcategories.contains(_selectedSubcategory) ? _selectedSubcategory : null,
                    decoration: const InputDecoration(labelText: 'Subcategory'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None (General in Section)')),
                      ...availableSubcategories.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (value) => setDialogState(() => _selectedSubcategory = value),
                  ),
                  const SizedBox(height: 16),
                ],

                  TextField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Description'), maxLines: 3),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Upload')),
              ],
            );
          },
        ),
      );

      if (confirm == true) {
        _setLoading(true);
        try {
          final ext = file.name.split('.').last;
          final ref = FirebaseStorage.instance.ref().child('youtube_library/uploads/${DateTime.now().millisecondsSinceEpoch}_${file.name}');
          await ref.putData(file.bytes!, SettableMetadata(contentType: 'video/$ext')); // Assuming video for now
          final url = await ref.getDownloadURL();

          await _videosCollection.add({
            'type': 'upload',
            'url': url,
            'title': _titleController.text,
            'description': _descriptionController.text,
            'thumbnailUrl': '', // No thumbnail generation yet
            'isFeatured': false,
            'sectionId': _selectedSectionId,
            'subcategory': _selectedSubcategory,
            'createdAt': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 10));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File uploaded and added successfully')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        } finally {
          _setLoading(false);
        }
      }
    }
  }

  // --- Feature Logic ---

  Future<void> _setFeatured(String docId) async {
    _setLoading(true);
    try {
      // 1. Unset current featured
      final currentFeatured = await _videosCollection.where('isFeatured', isEqualTo: true).get();
      final batch = FirebaseFirestore.instance.batch();
      
      for (var doc in currentFeatured.docs) {
        batch.update(doc.reference, {'isFeatured': false});
      }

      // 2. Set new featured
      batch.update(_videosCollection.doc(docId), {'isFeatured': true});
      
      await batch.commit();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _setSectionFeatured(String sectionId, String videoId) async {
    _setLoading(true);
    try {
      if (_previewSubcategory != null) {
        // Set FEATURE for SUBCATEGORY
        // We need to use dot notation for nested fields in Firestore update if we want to be precise,
        // BUT 'subcategoryFeaturedContentIds' is a Map.
        // To update a single key in a map field "subcategoryFeaturedContentIds", the syntax is "subcategoryFeaturedContentIds.KeyName".
        
        await _sectionsCollection.doc(sectionId).update({
          'subcategoryFeaturedContentIds.$_previewSubcategory': videoId
        });
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Featured video set for $_previewSubcategory')));
      } else {
        // Set FEATURE for SECTION
        await _sectionsCollection.doc(sectionId).update({'featuredContentId': videoId});
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section featured video updated')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _deleteVideo(String id) async {
    try {
      await _videosCollection.doc(id).delete();
    } catch (e) {
      debugPrint('Error deleting video: $e');
    }
  }

  Future<void> _editVideo(String docId, Map<String, dynamic> data) async {
    _titleController.text = data['title'] ?? '';
    _descriptionController.text = data['description'] ?? '';
    _selectedSectionId = data['sectionId'];
    String? currentSubcategory = data['subcategory'];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          
          List<String> availableSubcategories = [];
          if (_selectedSectionId != null) {
            try {
               final section = _sections.firstWhere((s) => s.id == _selectedSectionId);
               availableSubcategories = section.subcategories;
            } catch (_) {}
          }

          return AlertDialog(
            title: const Text('Edit Details'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedSectionId,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None (General)')),
                    ..._sections.map((s) => DropdownMenuItem(value: s.id, child: Text(s.title))),
                  ],
                  onChanged: (value) => setDialogState(() {
                     if (value != _selectedSectionId) {
                        _selectedSectionId = value;
                        currentSubcategory = null;
                     }
                  }),
                ),
                const SizedBox(height: 16),
                
                if (_selectedSectionId != null && availableSubcategories.isNotEmpty) ...[
                   DropdownButtonFormField<String>(
                    initialValue: availableSubcategories.contains(currentSubcategory) ? currentSubcategory : null,
                    decoration: const InputDecoration(labelText: 'Subcategory'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None (General in Section)')),
                      ...availableSubcategories.map((s) => DropdownMenuItem(value: s, child: Text(s))),
                    ],
                    onChanged: (value) => setDialogState(() => currentSubcategory = value),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(labelText: 'Description'),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  _setLoading(true);
                  try {
                    await _videosCollection.doc(docId).update({
                      'title': _titleController.text.trim(),
                      'description': _descriptionController.text.trim(),
                      'sectionId': _selectedSectionId,
                      'subcategory': currentSubcategory,
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Updated successfully')),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating: $e')),
                      );
                    }
                  } finally {
                    _setLoading(false);
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDrafts) {
      return const Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initializing Draft Environment...'),
        ],
      ));
    }

    return Row(
      children: [
        // Left Side: Controls
        Container(
          width: 300,
          color: Colors.white,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Content Manager', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Changes are saved to draft. Publish to go live.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              
              // Publish Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isPublishing ? null : _publishChanges,
                  icon: _isPublishing 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                      : const Icon(Icons.cloud_upload),
                  label: Text(_isPublishing ? 'Publishing...' : 'Publish Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Sync Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoadingDrafts ? null : _syncFromLive,
                  icon: const Icon(Icons.sync, color: Colors.orange),
                  label: const Text('Sync from Live', style: TextStyle(color: Colors.orange)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: Colors.orange),
                  ),
                ),
              ),
              const Divider(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _showAddContentDialog,
                  icon: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) 
                      : const Icon(Icons.add),
                  label: Text(_isLoading ? 'Processing...' : 'Add Content'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showManageSectionsDialog,
                  icon: const Icon(Icons.category),
                  label: const Text('Manage Sections'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Instructions:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('• Use the "Star" icon on an item to feature it at the top.'),
              const Text('• Only one item can be featured at a time.'),
              const Text('• Use the trash icon to remove content.'),
              
              const Divider(height: 32),
              const Text('Preview Navigation:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.home),
                title: const Text('User Topics Landing View'),
                selected: _previewSectionId == null,
                selectedTileColor: Colors.indigo.withOpacity(0.1),
                onTap: () => setState(() {
                  _previewSectionId = null;
                  _previewSubcategory = null;
                }),
              ),
              ..._sections.map((section) {
                final isSelected = _previewSectionId == section.id;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(isSelected ? Icons.folder_open : Icons.folder),
                      title: Text(section.title),
                      selected: isSelected,
                      selectedTileColor: Colors.indigo.withOpacity(0.1),
                      onTap: () => setState(() {
                        _previewSectionId = section.id;
                        _previewSubcategory = null;
                      }),
                    ),
                    if (isSelected) 
                      ...section.subcategories.map((sub) => ListTile(
                        leading: const SizedBox(width: 24), // Indent
                        contentPadding: const EdgeInsets.only(left: 32, right: 16),
                        title: Text(sub, style: const TextStyle(fontSize: 14)),
                        selected: _previewSubcategory == sub,
                        selectedColor: Colors.purple,
                        onTap: () => setState(() => _previewSubcategory = sub),
                      )),
                  ],
                );
              }),
            ],
          ),
        ),

        // Right Side: Phone Preview (User App Layout)
        Expanded(
          child: Container(
            color: const Color(0xFFE0E0E0),
            child: Center(
              child: Container(
                width: 375, // iPhone width approx
                height: 812, // iPhone height approx
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 30,
                      offset: const Offset(0, 10),
                    )
                  ],
                  border: Border.all(color: Colors.grey.shade800, width: 8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: Scaffold(
                    backgroundColor: Colors.transparent, // Let gradient show if we had one, or just dark
                    body: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Colors.indigo.shade900, Colors.purple.shade900],
                        ),
                      ),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _videosCollection.snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                  const SizedBox(height: 16),
                                  Text('Error loading content: ${snapshot.error}', 
                                    style: const TextStyle(color: Colors.white),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          }

                          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                          
                          final docs = snapshot.data!.docs;
                          // Find featured
                          // For Landing Page: Featured item must have isFeatured=true AND sectionId=null
                          // For Section Page: Featured item is determined by section.featuredContentId
                          
                          final allDocs = docs;
                          
                          if (_previewSectionId == null) {
                            // LANDING PAGE
                            final featuredDoc = allDocs.where((d) {
                              final data = d.data() as Map<String, dynamic>;
                              return data['isFeatured'] == true && data['sectionId'] == null;
                            }).firstOrNull;
                            
                            final otherDocs = allDocs.where((d) => d.id != featuredDoc?.id).toList();

                            // Filter for general videos (sectionId == null) that are NOT the featured one
                            final generalVideos = otherDocs.where((d) {
                              final data = d.data() as Map<String, dynamic>;
                              return data['sectionId'] == null;
                            }).toList();

                            return CustomScrollView(
                              slivers: [
                                const SliverAppBar(
                                  title: Text('Topics'),
                                  backgroundColor: Colors.transparent,
                                  centerTitle: true,
                                  automaticallyImplyLeading: false,
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.all(16),
                                  sliver: SliverList(
                                    delegate: SliverChildListDelegate([
                                      if (featuredDoc != null)
                                        _buildFeaturedItem(featuredDoc)
                                      else
                                        Container(
                                          height: 200,
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                                          ),
                                          child: const Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.star_border, size: 48, color: Colors.white24),
                                                SizedBox(height: 8),
                                                Text('Featured Content Slot', style: TextStyle(color: Colors.white54)),
                                                Text('Star an item to display it here', style: TextStyle(color: Colors.white24, fontSize: 12)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 24),
                                      const Text(
                                        'Explore Topics',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                      const SizedBox(height: 12),
                                    ]),
                                  ),
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  sliver: SliverGrid(
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 4, // 4 Columns
                                      childAspectRatio: 1.0, // Square aspect ratio
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final section = _sections[index];
                                        return InkWell(
                                          onTap: () => setState(() => _previewSectionId = section.id),
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.15),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.white10),
                                            ),
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                                            child: Text(
                                              section.title,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10, // Reduced to 10 for better fit
                                                fontWeight: FontWeight.w600,
                                              ),
                                              textAlign: TextAlign.center,
                                              maxLines: 3, 
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        );
                                      },
                                      childCount: _sections.length,
                                    ),
                                  ),
                                ),
                                // General Videos List removed as requested
                                /* 
                                if (generalVideos.isNotEmpty) ...[
                                  SliverPadding(
                                    padding: const EdgeInsets.all(16),
                                    sliver: SliverList(
                                      delegate: SliverChildListDelegate([
                                        const SizedBox(height: 24),
                                        const Text(
                                          'General Content',
                                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                                        ),
                                        const SizedBox(height: 12),
                                      ]),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    sliver: SliverGrid(
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        childAspectRatio: 0.9,
                                        crossAxisSpacing: 16,

                                        mainAxisSpacing: 16,
                                      ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) => _buildGridItem(generalVideos[index]),
                                        childCount: generalVideos.length,
                                      ),
                                    ),
                                  ),
                                ],
                                */
                                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                                  ],
                                );
                              } else {
                                // SECTION VIEW
                            final section = _sections.firstWhere((s) => s.id == _previewSectionId, orElse: () => ContentSection(id: '', title: 'Unknown', order: 0));
                            final sectionVideos = docs.where((d) => (d.data() as Map<String, dynamic>)['sectionId'] == section.id).toList();
                            
                            // Subcategory View
                            if (_previewSubcategory != null) {
                              final subVideos = sectionVideos.where((d) {
                                final data = d.data() as Map<String, dynamic>;
                                return data['subcategory'] == _previewSubcategory;
                              }).toList();

                              final subFeaturedId = section.subcategoryFeaturedContentIds?[_previewSubcategory];
                              final subFeaturedDoc = subVideos.where((d) => d.id == subFeaturedId).firstOrNull;
                              final subGeneralVideos = subVideos.where((d) => d.id != subFeaturedId).toList();
                              
                              return CustomScrollView(
                                slivers: [
                                  SliverAppBar(
                                    title: Text(_previewSubcategory!),
                                    backgroundColor: Colors.transparent,
                                    leading: IconButton(
                                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                                      onPressed: () => setState(() => _previewSubcategory = null),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.all(16),
                                    sliver: SliverList(
                                      delegate: SliverChildListDelegate([
                                        if (subFeaturedDoc != null)
                                            _buildFeaturedItem(subFeaturedDoc)
                                          else
                                            Container(
                                              height: 150,
                                              decoration: BoxDecoration(
                                                color: Colors.white10,
                                                borderRadius: BorderRadius.circular(16),
                                                border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                                              ),
                                              child: const Center(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(Icons.star_border, size: 32, color: Colors.white24),
                                                    SizedBox(height: 8),
                                                    Text('Feature This Subcategory', style: TextStyle(color: Colors.white54)),
                                                    Text('Star an item in this subcategory', style: TextStyle(color: Colors.white24, fontSize: 10)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          const SizedBox(height: 16),
                                          const Text('Subcategory Content', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                          const SizedBox(height: 8),
                                      ]),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    sliver: SliverGrid(
                                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        childAspectRatio: 0.9,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                      ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) => _buildGridItem(subGeneralVideos[index]),
                                        childCount: subGeneralVideos.length,
                                      ),
                                    ),
                                  ),
                                  const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                                ],
                              );
                            }

                            // Section Landing View
                            final sectionFeaturedId = section.featuredContentId;
                            final sectionFeaturedDoc = sectionVideos.where((d) => d.id == sectionFeaturedId).firstOrNull;
                            
                            // General videos are those without a subcategory (or empty string/null) AND not featured
                            final generalVideos = sectionVideos.where((d) {
                                if (d.id == sectionFeaturedId) return false;
                                final data = d.data() as Map<String, dynamic>;
                                final sub = data['subcategory'];
                                return sub == null || sub == '';
                            }).toList();

                            return CustomScrollView(
                              slivers: [
                                SliverAppBar(
                                  title: Text(section.title),
                                  backgroundColor: Colors.transparent,
                                  leading: IconButton(
                                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                                    onPressed: () => setState(() => _previewSectionId = null),
                                  ),
                                  actions: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_note, color: Colors.white),
                                      tooltip: 'Manage Subcategories',
                                      onPressed: () => _editSection(section),
                                    ),
                                  ],
                                ),
                                SliverPadding(
                                  padding: const EdgeInsets.all(16),
                                  sliver: SliverList(
                                    delegate: SliverChildListDelegate([
                                      if (sectionFeaturedDoc != null)
                                        _buildFeaturedItem(sectionFeaturedDoc)
                                      else
                                        Container(
                                          height: 200,
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(color: Colors.white24, style: BorderStyle.solid),
                                          ),
                                          child: const Center(child: Text('No Section Featured Item', style: TextStyle(color: Colors.white54))),
                                        ),
                                      const SizedBox(height: 24),
                                    ]),
                                  ),
                                ),
                                
                                // Subcategories Grid
                                if (section.subcategories.isNotEmpty) ...[
                                   SliverPadding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      sliver: SliverList(
                                        delegate: SliverChildListDelegate([
                                           const Text('Explore Categories', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                                           const SizedBox(height: 12),
                                        ])
                                      )
                                   ),
                                   SliverPadding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      sliver: SliverGrid(
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 4, // 4 Abreast
                                          childAspectRatio: 1.0,
                                          crossAxisSpacing: 10,
                                          mainAxisSpacing: 10,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) {
                                             final sub = section.subcategories[index];
                                             return InkWell(
                                               onTap: () => setState(() => _previewSubcategory = sub),
                                               child: Container(
                                                 decoration: BoxDecoration(
                                                   color: Colors.white.withOpacity(0.15),
                                                   borderRadius: BorderRadius.circular(12),
                                                   border: Border.all(color: Colors.white10),
                                                 ),
                                                 alignment: Alignment.center,
                                                 padding: const EdgeInsets.all(4),
                                                 child: Text(
                                                   sub,
                                                   style: const TextStyle(
                                                     color: Colors.white,
                                                     fontSize: 12,
                                                     fontWeight: FontWeight.w600,
                                                   ),
                                                   textAlign: TextAlign.center,
                                                   maxLines: 2,
                                                   overflow: TextOverflow.ellipsis,
                                                 ),
                                               ),
                                             );
                                          },
                                          childCount: section.subcategories.length,
                                        ),
                                      ),
                                    ),
                                    const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                                ],
                                
                                // Section General Content
                                if (generalVideos.isNotEmpty) ...[
                                    SliverPadding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      sliver: SliverList(
                                        delegate: SliverChildListDelegate([
                                           const Text('General Content', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                                           const SizedBox(height: 12),
                                        ])
                                      )
                                   ),
                                    SliverPadding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      sliver: SliverGrid(
                                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          childAspectRatio: 0.9,
                                          crossAxisSpacing: 16,
                                          mainAxisSpacing: 16,
                                        ),
                                        delegate: SliverChildBuilderDelegate(
                                          (context, index) => _buildGridItem(generalVideos[index]),
                                          childCount: generalVideos.length,
                                        ),
                                      ),
                                    ),
                                ],
                                const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedItem(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] ?? 'youtube';

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade200.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'FEATURED SPECIAL',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: type == 'youtube'
                  ? () {
                      if (data['url'] != null) {
                        launchUrl(Uri.parse(data['url']));
                      }
                    }
                  : null,
              child: Card(
                margin: EdgeInsets.zero,
                color: Colors.white.withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: VideoGridItem(
                        url: data['url'] ?? '',
                        thumbnailUrl: data['thumbnailUrl'],
                        type: type,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data['title'] ?? 'Untitled',
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            data['description'] ?? '',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Admin Controls Overlay
        Positioned(
          top: 0,
          right: 0,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.star, color: Colors.amber, size: 32),
                onPressed: () {}, // Already featured
                tooltip: 'Currently Featured',
              ),
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.white),
                onPressed: () => _editVideo(doc.id, data),
                tooltip: 'Edit Details',
              ),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => _deleteVideo(doc.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridItem(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] ?? 'youtube';
    
    // Determine if this item is featured in the CURRENT view
    bool isFeaturedInCurrentView = false;
    if (_previewSectionId == null) {
      // Landing View: Check global isFeatured
      isFeaturedInCurrentView = data['isFeatured'] == true;
    } else {
      // Section View: Check if this item is the section's featured item
      final section = _sections.firstWhere((s) => s.id == _previewSectionId, orElse: () => ContentSection(id: '', title: '', order: 0));
      
      if (_previewSubcategory != null) {
        // Checking feature for specific subcategory
        isFeaturedInCurrentView = section.subcategoryFeaturedContentIds?[_previewSubcategory] == doc.id;
      } else {
        // Checking feature for section
        isFeaturedInCurrentView = section.featuredContentId == doc.id;
      }
    }

    return Stack(
      children: [
        InkWell(
          onTap: type == 'youtube'
              ? () {
                  if (data['url'] != null) {
                    launchUrl(Uri.parse(data['url']));
                  }
                }
              : null,
          child: Card(
            margin: EdgeInsets.zero,
            color: Colors.white.withOpacity(0.1),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: VideoGridItem(
                    url: data['url'] ?? '',
                    thumbnailUrl: data['thumbnailUrl'],
                    type: type,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['title'] ?? 'Untitled',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Text(
                            data['description'] ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Admin Controls Overlay
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () {
                  if (_previewSectionId == null) {
                    // Landing View: Toggle global feature
                    _setFeatured(doc.id);
                  } else {
                    // Section View: Toggle section feature
                    _setSectionFeatured(_previewSectionId!, doc.id);
                  }
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Icon(
                    isFeaturedInCurrentView ? Icons.star : Icons.star_border, 
                    color: Colors.amber, 
                    size: 20
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => _editVideo(doc.id, data),
                  tooltip: 'Edit Details',
                ),
              ),
              const SizedBox(width: 4),
              Container(
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  onPressed: () => _deleteVideo(doc.id),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
