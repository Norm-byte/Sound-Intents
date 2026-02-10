import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/media_library_service.dart';
import '../../models/media_item.dart';
import '../../utils/thumbnail_generator.dart';
import '../widgets/video_widgets.dart';
import '../widgets/web_image.dart';

class MediaLibraryTab extends StatefulWidget {
  const MediaLibraryTab({super.key});

  @override
  State<MediaLibraryTab> createState() => _MediaLibraryTabState();
}

class _MediaLibraryTabState extends State<MediaLibraryTab> {
  final MediaLibraryService _mediaService = MediaLibraryService();
  
  String _viewMode = 'grid';
  String _selectedSection = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Sidebar: Sections
        Container(
          width: 250,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(right: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Library Sections',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: Colors.indigo),
                      tooltip: 'Add Section',
                      onPressed: _showAddSectionDialog,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<String>>(
                  stream: _mediaService.getSectionsStream(),
                  builder: (context, sectionsSnapshot) {
                    if (sectionsSnapshot.hasError) return const Center(child: Text('Error loading sections'));
                    if (!sectionsSnapshot.hasData) return const Center(child: CircularProgressIndicator());

                    final sections = ['All', ...sectionsSnapshot.data!];

                    return StreamBuilder<List<MediaItem>>(
                      stream: _mediaService.getMediaStream(), // Fetch all items to check counts
                      builder: (context, itemsSnapshot) {
                        final allItems = itemsSnapshot.data ?? [];
                        
                        // Calculate which sections have content
                        final sectionsWithContent = <String>{};
                        for (var item in allItems) {
                          sectionsWithContent.add(item.section);
                        }

                        return ListView.builder(
                          itemCount: sections.length,
                          itemBuilder: (context, index) {
                            final section = sections[index];
                            final isSelected = _selectedSection == section;
                            final hasContent = sectionsWithContent.contains(section);
                            
                            // Determine style based on content presence
                            final textStyle = TextStyle(
                              color: isSelected 
                                  ? Colors.indigo 
                                  : (hasContent ? Colors.blue.shade700 : Colors.black),
                              fontWeight: (isSelected || hasContent) ? FontWeight.bold : FontWeight.normal,
                              shadows: hasContent && !isSelected ? [
                                Shadow(color: Colors.blue.withOpacity(0.3), blurRadius: 4)
                              ] : null,
                            );

                            return ListTile(
                              title: Text(section, style: textStyle),
                              selected: isSelected,
                              selectedTileColor: Colors.indigo.shade50,
                              selectedColor: Colors.indigo,
                              leading: Icon(
                                section == 'All' ? Icons.dashboard : Icons.folder,
                                color: isSelected 
                                    ? Colors.indigo 
                                    : (hasContent ? Colors.blue.shade700 : Colors.grey),
                              ),
                              onTap: () => setState(() => _selectedSection = section),
                              trailing: (section == 'All') 
                                ? null 
                                : PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    onSelected: (value) {
                                      if (value == 'edit') _showEditSectionDialog(section);
                                      if (value == 'delete') _confirmDeleteSection(section);
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Rename')),
                                      const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Right Content: Media Grid
        Expanded(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Row(
                  children: [
                    Text(
                      _selectedSection,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search in $_selectedSection...',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'grid', icon: Icon(Icons.grid_view)),
                        ButtonSegment(value: 'list', icon: Icon(Icons.list)),
                      ],
                      selected: {_viewMode},
                      onSelectionChanged: (s) => setState(() => _viewMode = s.first),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _isUploading ? null : _showUploadDialog,
                      icon: _isUploading 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_upload),
                      label: Text(_isUploading ? 'Uploading...' : 'Upload Media'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.bug_report, color: Colors.grey),
                      tooltip: 'Run Diagnostics',
                      onPressed: _runDiagnostics,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Content
              Expanded(
                child: StreamBuilder<List<MediaItem>>(
                  stream: _mediaService.getMediaStream(section: _selectedSection),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                    final items = snapshot.data!.where((item) {
                      return _searchQuery.isEmpty || 
                             item.name.toLowerCase().contains(_searchQuery.toLowerCase());
                    }).toList();

                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              'No media in $_selectedSection',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                            ),
                          ],
                        ),
                      );
                    }

                    return _viewMode == 'grid' 
                        ? _buildGridView(items) 
                        : _buildListView(items);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _runDiagnostics() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final result = await _mediaService.runDiagnostics();
    
    if (mounted) {
      Navigator.pop(context); // Close loading
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Diagnostics Result'),
          content: SingleChildScrollView(child: Text(result)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showRenameMediaDialog(MediaItem item) async {
    final controller = TextEditingController(text: item.name);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Media'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty || newName == item.name) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context);
              try {
                await _mediaService.renameMedia(item, newName);
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Media renamed successfully')));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(List<MediaItem> items) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.8,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _MediaCard(
          item: item,
          onTap: () => _showMediaDetails(item),
          onDelete: () => _confirmDelete(item),
          onCopy: () => _showMoveMediaDialog(item, isCopy: true),
          onMove: () => _showMoveMediaDialog(item, isCopy: false),
          onRename: () => _showRenameMediaDialog(item),
        );
      },
    );
  }

  Widget _buildListView(List<MediaItem> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: _buildIcon(item.type),
            title: Text(item.name),
            subtitle: Text('${item.section} • ${item.uploadedAt.toString().split(' ')[0]}'),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'rename') _showRenameMediaDialog(item);
                if (value == 'copy') _showMoveMediaDialog(item, isCopy: true);
                if (value == 'move') _showMoveMediaDialog(item, isCopy: false);
                if (value == 'delete') _confirmDelete(item);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'copy', child: Row(children: [Icon(Icons.file_copy, size: 18), SizedBox(width: 8), Text('Copy to...')])),
                const PopupMenuItem(value: 'move', child: Row(children: [Icon(Icons.drive_file_move, size: 18), SizedBox(width: 8), Text('Move to...')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
              ],
            ),
            onTap: () => _showMediaDetails(item),
          ),
        );
      },
    );
  }

  Widget _buildIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'audio':
        icon = Icons.audiotrack;
        color = Colors.purple;
        break;
      case 'image':
        icon = Icons.image;
        color = Colors.blue;
        break;
      case 'video':
        icon = Icons.videocam;
        color = Colors.red;
        break;
      case 'pdf':
      case 'doc':
      case 'document':
        icon = Icons.description;
        color = Colors.orange;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }
    return CircleAvatar(
      backgroundColor: color.withOpacity(0.1),
      child: Icon(icon, color: color),
    );
  }

  // --- Dialogs ---

  void _showAddSectionDialog() {
    final controller = TextEditingController();
    bool isAdding = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Section'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Section Name',
              hintText: 'e.g., 3:00 am, Meditation',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            enabled: !isAdding,
          ),
          actions: [
            TextButton(
              onPressed: isAdding ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isAdding ? null : () async {
                if (controller.text.trim().isNotEmpty) {
                  setState(() => isAdding = true);
                  try {
                    await _mediaService.addSection(controller.text.trim());
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('Section added successfully')),
                      );
                    }
                  } catch (e) {
                    debugPrint('Error adding section: $e');
                    if (mounted) {
                      setState(() => isAdding = false); // Fix: Reset loading state
                      
                      String msg = 'Error adding section: $e';
                      if (e.toString().contains('Timeout')) {
                        msg = 'Request timed out. Please check the sidebar to see if it appeared.';
                      }
                      
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text(msg), backgroundColor: Colors.orange),
                      );
                    }
                  }
                }
              },
              child: isAdding 
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showUploadDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Media'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.indigo),
              title: const Text('Upload Local File'),
              subtitle: const Text('Upload images, audio, or video from your device'),
              onTap: () {
                Navigator.pop(context);
                _showLocalFileUploadDialog();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.red),
              title: const Text('Add YouTube Link'),
              subtitle: const Text('Add a link to a YouTube video'),
              onTap: () {
                Navigator.pop(context);
                _showAddYoutubeLinkDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showAddYoutubeLinkDialog() {
    final urlController = TextEditingController();
    final nameController = TextEditingController();
    String targetSection = _selectedSection;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add YouTube Link'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StreamBuilder<List<String>>(
                  stream: _mediaService.getSectionsStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const LinearProgressIndicator();
                    final sections = snapshot.data!;
                    
                    // Determine valid dropdown value
                    String dropdownValue = targetSection;
                    if (dropdownValue == 'All' || (!sections.contains(dropdownValue) && sections.isNotEmpty)) {
                      dropdownValue = sections.contains('General') ? 'General' : (sections.isNotEmpty ? sections.first : 'Uncategorized');
                      // Update the variable so it matches what the user sees
                      targetSection = dropdownValue;
                    }

                    return DropdownButtonFormField<String>(
                      initialValue: dropdownValue,
                      items: sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (val) => setState(() => targetSection = val!),
                      decoration: const InputDecoration(
                        labelText: 'Target Section',
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: urlController,
                        decoration: const InputDecoration(
                          labelText: 'YouTube URL',
                          hintText: 'https://youtube.com/watch?v=...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.link),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.open_in_new, color: Colors.red),
                      tooltip: 'Open YouTube',
                      onPressed: () async {
                        final Uri url = Uri.parse('https://www.youtube.com');
                        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch YouTube')));
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name / Title',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (urlController.text.isNotEmpty && nameController.text.isNotEmpty) {
                  Navigator.pop(context);
                  try {
                    await _mediaService.addExternalMedia(
                      name: nameController.text.trim(),
                      url: urlController.text.trim(),
                      type: 'video',
                      section: targetSection,
                    );
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('YouTube link added successfully')));
                  } catch (e) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Add Link'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocalFileUploadDialog() {
    // Use ValueNotifier to handle section updates reactively
    final ValueNotifier<String> sectionNotifier = ValueNotifier<String>(_selectedSection);
    PlatformFile? selectedFile;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Upload Media'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section Selector
                const Text('Target Section:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                StreamBuilder<List<String>>(
                  stream: _mediaService.getSectionsStream(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const LinearProgressIndicator();
                    final sections = snapshot.data!;
                    
                    // Determine valid dropdown value
                    String currentSection = sectionNotifier.value;
                    String validSection = currentSection;
                    
                    // If current selection is 'All' or invalid, pick a default
                    if (validSection == 'All' || (!sections.contains(validSection) && sections.isNotEmpty)) {
                      if (sections.contains('General')) {
                        validSection = 'General';
                      } else if (sections.isNotEmpty) {
                        validSection = sections.first;
                      } else {
                        validSection = 'Uncategorized';
                      }
                      // Update notifier if changed (schedule post-frame to avoid build error)
                      if (validSection != currentSection) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          sectionNotifier.value = validSection;
                        });
                      }
                    }

                    if (sections.isEmpty) {
                      return const Text('No sections available. Please add a section first.', style: TextStyle(color: Colors.red));
                    }

                    return ValueListenableBuilder<String>(
                      valueListenable: sectionNotifier,
                      builder: (context, value, child) {
                        // Ensure value is valid for dropdown
                        final dropdownValue = sections.contains(value) ? value : validSection;
                        return DropdownButtonFormField<String>(
                          initialValue: dropdownValue,
                          items: sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              sectionNotifier.value = val;
                            }
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            helperText: 'Select the section where this file will appear',
                          ),
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 24),

                // File Picker Area
                GestureDetector(
                  onTap: () async {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.any, // Changed to allow all files to avoid confusion
                      withData: true, // Ensure bytes are loaded on web
                    );
                    if (result != null) {
                      setState(() => selectedFile = result.files.first);
                    }
                  },
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Center(
                      child: selectedFile == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.cloud_upload, size: 40, color: Colors.grey),
                                SizedBox(height: 8),
                                Text('Click to select file'),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle, size: 40, color: Colors.green),
                                const SizedBox(height: 8),
                                Text(selectedFile!.name, textAlign: TextAlign.center),
                                Text('${(selectedFile!.size / 1024).toStringAsFixed(1)} KB', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Note: If upload fails with "unknown error", it is likely a browser security (CORS) issue. Try running the app with web security disabled.',
                  style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ValueListenableBuilder<String>(
              valueListenable: sectionNotifier,
              builder: (context, section, child) {
                final bool isValid = section != 'All' && selectedFile != null;
                return ElevatedButton(
                  onPressed: isValid ? () async {
                    Navigator.pop(context); // Close dialog
                    _performUpload(selectedFile!, section);
                  } : null,
                  child: const Text('Upload'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performUpload(PlatformFile file, String section) async {
    // Check Auth
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: You are not logged in.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isUploading = true);
    try {
      // On web, file.bytes should be populated if withData: true was used.
      // If not, we might need to read it from the file path (not possible on web) or stream.
      // Since we used withData: true, bytes should be there.
      
      Uint8List? fileBytes = file.bytes;
      
      if (fileBytes == null) {
         // Fallback or error
         throw Exception('File content is empty or could not be read.');
      }

      Uint8List? thumbnailBytes;
      if (file.name.toLowerCase().endsWith('.mp4') || 
          file.name.toLowerCase().endsWith('.mov') || 
          file.name.toLowerCase().endsWith('.webm')) {
        // Try to generate thumbnail for video
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Generating thumbnail...'), duration: Duration(seconds: 1)),
          );
        }
        thumbnailBytes = await ThumbnailGenerator.generateVideoThumbnail(fileBytes);
      }
      
      await _mediaService.uploadMedia(
        bytes: fileBytes,
        fileName: file.name,
        section: section,
        thumbnailBytes: thumbnailBytes,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload successful!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Upload error: $e');
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Upload Failed'),
            content: SingleChildScrollView(
              child: SelectableText('Error details:\n$e'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  String? _getYoutubeId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.first;
      }
      if (uri.host.contains('youtube.com')) {
        return uri.queryParameters['v'];
      }
    } catch (_) {}
    return null;
  }

  void _showMediaDetails(MediaItem item) {
    // If it's a video, play it directly
    if (item.type == 'video') {
      final isYoutube = item.url.contains('youtube.com') || item.url.contains('youtu.be');
      
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.center,
            children: [
              isYoutube 
                ? YouTubePlayerWidget(videoId: _getYoutubeId(item.url) ?? '')
                : FullVideoPlayer(url: item.url),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: ${item.type}'),
            Text('Section: ${item.section}'),
            Text('Uploaded: ${item.uploadedAt}'),
            const SizedBox(height: 16),
            SelectableText(item.url, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showMoveMediaDialog(item, isCopy: true);
            },
            icon: const Icon(Icons.file_copy),
            label: const Text('Copy to...'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showMoveMediaDialog(item, isCopy: false);
            },
            icon: const Icon(Icons.drive_file_move),
            label: const Text('Move'),
          ),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: item.url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('URL copied!')),
              );
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy URL'),
          ),
        ],
      ),
    );
  }

  void _showEditSectionDialog(String oldName) {
    final controller = TextEditingController(text: oldName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Section'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty && controller.text.trim() != oldName) {
                Navigator.pop(context);
                try {
                  await _mediaService.updateSection(oldName, controller.text.trim());
                  if (mounted) {
                    if (_selectedSection == oldName) {
                      setState(() => _selectedSection = controller.text.trim());
                    }
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section renamed')));
                  }
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSection(String sectionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Section'),
        content: Text('Delete "$sectionName"? All media in this section will be moved to "Uncategorized".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _mediaService.deleteSection(sectionName);
                if (mounted) {
                  if (_selectedSection == sectionName) {
                    setState(() => _selectedSection = 'All');
                  }
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Section deleted')));
                }
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showMoveMediaDialog(MediaItem item, {bool isCopy = false}) {
    // Use a ValueNotifier to manage the selected section state
    final ValueNotifier<String> targetSectionNotifier = ValueNotifier<String>(item.section);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isCopy ? 'Copy Media' : 'Move Media'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isCopy ? 'Copy to section:' : 'Move to section:'),
              const SizedBox(height: 8),
              StreamBuilder<List<String>>(
                stream: _mediaService.getSectionsStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final sections = snapshot.data!;
                  
                  if (sections.isEmpty) {
                    return const Text('No sections available.', style: TextStyle(color: Colors.red));
                  }

                  return ValueListenableBuilder<String>(
                    valueListenable: targetSectionNotifier,
                    builder: (context, currentTarget, child) {
                      // Ensure the current target is valid
                      String validTarget = currentTarget;
                      if (!sections.contains(validTarget)) {
                        // If current section is not in list (e.g. 'All' or deleted), pick first available
                        validTarget = sections.first;
                        // Update notifier if we changed it (post-frame to be safe)
                        if (validTarget != currentTarget) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            targetSectionNotifier.value = validTarget;
                          });
                        }
                      }

                      return DropdownButtonFormField<String>(
                        initialValue: validTarget,
                        items: sections.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                        onChanged: (val) {
                          if (val != null) targetSectionNotifier.value = val;
                        },
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ValueListenableBuilder<String>(
              valueListenable: targetSectionNotifier,
              builder: (context, target, child) {
                return ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final cleanTarget = target.trim();
                    // Allow move if target is different OR if we are copying
                    // Also allow move if the item's current section is invalid (not in list)
                    if (cleanTarget != item.section || isCopy) {
                      try {
                        if (isCopy) {
                          await _mediaService.copyMedia(item, cleanTarget);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Media copied successfully')));
                        } else {
                          await _mediaService.moveMedia(item, cleanTarget);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Media moved successfully')));
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                      }
                    } else {
                       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item is already in this section')));
                    }
                  },
                  child: Text(isCopy ? 'Copy' : 'Move'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(MediaItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Media'),
        content: Text('Are you sure you want to delete "${item.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _mediaService.deleteMedia(item);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onMove;
  final VoidCallback onRename;

  const _MediaCard({
    required this.item, 
    required this.onTap, 
    required this.onDelete,
    required this.onCopy,
    required this.onMove,
    required this.onRename,
  });

  String? _getYoutubeId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.first;
      }
      if (uri.host.contains('youtube.com')) {
        return uri.queryParameters['v'];
      }
    } catch (_) {}
    return null;
  }

  String? _getYoutubeThumbnail(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('youtube.com')) {
        return 'https://img.youtube.com/vi/${uri.queryParameters['v']}/0.jpg';
      } else if (uri.host.contains('youtu.be')) {
        return 'https://img.youtube.com/vi/${uri.pathSegments.first}/0.jpg';
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    IconData icon;
    Color color;

    // Determine icon/color first as fallback
    switch (item.type) {
      case 'audio':
        icon = Icons.audiotrack;
        color = Colors.purple;
        break;
      case 'image':
        icon = Icons.image;
        color = Colors.blue;
        break;
      case 'video':
        icon = Icons.videocam;
        color = Colors.red;
        break;
      case 'pdf':
      case 'doc':
      case 'document':
        icon = Icons.description;
        color = Colors.orange;
        break;
      default:
        icon = Icons.insert_drive_file;
        color = Colors.grey;
    }

    // Helper to check if it's a video (including YouTube)
    bool isVideo = item.type == 'video' || item.url.contains('youtube') || item.url.contains('youtu.be') || item.url.endsWith('.mp4') || item.url.endsWith('.mov') || item.url.endsWith('.webm') || item.url.endsWith('.avi');

    // Helper to check if it's an image that we can actually render in the browser
    // Note: item.type might be 'image' for HEIC/TIFF, but browsers can't render those natively.
    bool isRenderableImage = false;
    final String lowerName = item.name.toLowerCase();
    final String lowerUrl = item.url.toLowerCase().split('?').first;
    
    final renderableExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.wbmp', '.svg'];
    
    // Check extension
    for (var ext in renderableExtensions) {
      if (lowerName.endsWith(ext) || lowerUrl.endsWith(ext)) {
        isRenderableImage = true;
        break;
      }
    }

    // Try to build thumbnail content
    if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty) {
      // Use pre-generated thumbnail if available
      content = WebImage(
        imageUrl: item.thumbnailUrl!,
        fit: BoxFit.cover,
      );
      // Overlay play icon for video clarity
      if (isVideo) {
        content = Stack(
          fit: StackFit.expand,
          children: [
            content,
            Container(
              color: Colors.black26,
              child: const Center(child: Icon(Icons.play_circle_fill, size: 48, color: Colors.white)),
            ),
          ],
        );
      }
    } else if (isVideo) {
        // Use the smart VideoGridItem as fallback
        content = VideoGridItem(
          url: item.url,
          type: item.url.contains('youtu') ? 'youtube' : 'upload',
          enablePreview: false, // Don't play on hover/tap, just show thumb
          autoPlay: false, // Don't autoplay grid
        );
    } else if (isRenderableImage) {
      content = WebImage(
        imageUrl: item.url,
        fit: BoxFit.cover,
      );
    } else {
      content = Center(child: Icon(icon, size: 48, color: color.withOpacity(0.5)));
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color: color.withOpacity(0.1),
                    child: content,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        item.section,
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(8)),
                ),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    if (value == 'rename') onRename();
                    if (value == 'copy') onCopy();
                    if (value == 'move') onMove();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'copy', child: Text('Copy to...')),
                    const PopupMenuItem(value: 'move', child: Text('Move to...')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
