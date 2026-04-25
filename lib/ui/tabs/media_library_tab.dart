import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'web_pdf_shim.dart' if (dart.library.io) 'web_pdf_shim_stub.dart';
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
          key: ValueKey(item.id),
          item: item,
          onTap: () => _showMediaDetails(item),
          onDelete: () => _confirmDelete(item),
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
                      tooltip: 'Open YouTube',
                      icon: const Icon(Icons.open_in_new, color: Colors.red),
                      onPressed: () async {
                        final youtubeUri = Uri.parse('https://www.youtube.com');
                        final didLaunch = await launchUrl(
                          youtubeUri,
                          mode: LaunchMode.externalApplication,
                        );
                        if (!didLaunch && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not open YouTube.')),
                          );
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
            const SnackBar(content: Text('Generating video thumbnail...'), duration: Duration(seconds: 1)),
          );
        }
        thumbnailBytes = await ThumbnailGenerator.generateVideoThumbnail(fileBytes);
      } else if (file.name.toLowerCase().endsWith('.pdf')) {
        // Try to generate thumbnail for PDF
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Generating PDF thumbnail...'), duration: Duration(seconds: 1)),
          );
        }
        thumbnailBytes = await ThumbnailGenerator.generatePdfThumbnail(fileBytes);
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
    // Robust Video Detection (Align with Grid Logic)
    final urlLower = item.url.toLowerCase();
    
    // Clean URL to handle query parameters
    final cleanUrl = urlLower.split('?').first;
    
    final isYoutube = item.type == 'youtube' || urlLower.contains('youtube') || urlLower.contains('youtu.be');
    final isVideo = item.type == 'video' || isYoutube || 
                   cleanUrl.endsWith('.mp4') || cleanUrl.endsWith('.mov') || 
                   cleanUrl.endsWith('.webm') || cleanUrl.endsWith('.avi');

    final isImage = item.type == 'image' || 
                    cleanUrl.endsWith('.jpg') || cleanUrl.endsWith('.jpeg') || 
                    cleanUrl.endsWith('.png') || cleanUrl.endsWith('.gif') || 
                    cleanUrl.endsWith('.webp') || cleanUrl.endsWith('.bmp');
                    
    final isPdf = item.type == 'pdf' || cleanUrl.endsWith('.pdf');
    final isDoc = item.type == 'document' || 
                  cleanUrl.endsWith('.doc') || cleanUrl.endsWith('.docx') || 
                  cleanUrl.endsWith('.ppt') || cleanUrl.endsWith('.pptx') || 
                  cleanUrl.endsWith('.pptm') || cleanUrl.endsWith('.xls') || 
                  cleanUrl.endsWith('.xlsx') || cleanUrl.endsWith('.txt');

    // Unified Document Viewer (PDF)
    if (isPdf) {
      final viewType = 'pdf-view-${item.id}-${DateTime.now().millisecondsSinceEpoch}';
      // Use native browser PDF viewer via IFrame
      // Append toolbar=0 to try and hide the toolbar (works in some browsers)
      final pdfUrl = '${item.url}#toolbar=0&navpanes=0&scrollbar=0';
      registerPdfViewFactory(viewType, pdfUrl);

      showDialog(
        context: context,
        builder: (context) {
          final size = MediaQuery.of(context).size;
          final screenWidth = size.width;
          final screenHeight = size.height;

          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            backgroundColor: Colors.transparent,
            child: Container(
              width: screenWidth * 0.9,
              height: screenHeight * 0.9,
              constraints: BoxConstraints(maxWidth: screenWidth * 0.9, maxHeight: screenHeight * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close Preview',
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                        child: HtmlElementView(viewType: viewType),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    // Docs Viewer (Word, PPT, etc.)
    if (isDoc) {
      final viewType = 'doc-view-${item.id}-${DateTime.now().millisecondsSinceEpoch}';
      // Use Google Docs Viewer for compatibility
      final viewerUrl = 'https://docs.google.com/gview?url=${Uri.encodeComponent(item.url)}&embedded=true';
      
      registerPdfViewFactory(viewType, viewerUrl);
      
      showDialog(
        context: context,
        builder: (context) {
          final size = MediaQuery.of(context).size;
          final screenWidth = size.width;
          final screenHeight = size.height;

          return Dialog(
            insetPadding: const EdgeInsets.all(24),
            backgroundColor: Colors.transparent,
            child: Container(
              width: screenWidth * 0.9,
              height: screenHeight * 0.9,
              constraints: BoxConstraints(maxWidth: screenWidth * 0.9, maxHeight: screenHeight * 0.9),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   // Header
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(8),
                        topRight: Radius.circular(8),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            item.name,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Close Preview',
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                        child: HtmlElementView(viewType: viewType),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    // Interactive Video Player
    if (isVideo) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              isYoutube 
                ? Center(child: YouTubePlayerWidget(videoId: _getYoutubeId(item.url) ?? ''))
                : Center(child: FullVideoPlayer(url: item.url)),
              Positioned(
                top: 20,
                right: 20,
                child: SafeArea(
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 20,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 24),
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Close',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // Interactive Image Preview
    if (isImage) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                child: WebImage(
                  imageUrl: item.url,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 24),
                    onPressed: () => Navigator.pop(context),
                  ),
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
  final VoidCallback onRename;


  const _MediaCard({
    super.key,
    required this.item, 
    required this.onTap, 
    required this.onDelete,
    required this.onRename,
  });

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
    String? extension;
    for (var ext in renderableExtensions) {
      if (lowerName.endsWith(ext) || lowerUrl.endsWith(ext)) {
        isRenderableImage = true;
        extension = ext;
        break;
      }
    }

    // Try to detect other extensions for rich preview
    if (!isRenderableImage) {
      if (lowerName.endsWith('.pdf') || lowerUrl.endsWith('.pdf')) extension = '.pdf';
      else if (lowerName.endsWith('.doc') || lowerUrl.endsWith('.doc') || lowerName.endsWith('.docx') || lowerUrl.endsWith('.docx')) extension = '.doc';
      else if (lowerName.endsWith('.ppt') || lowerUrl.endsWith('.ppt') || lowerName.endsWith('.pptx') || lowerUrl.endsWith('.pptx') || lowerName.endsWith('.pptm') || lowerUrl.endsWith('.pptm')) extension = '.ppt';
      else if (lowerName.endsWith('.xls') || lowerUrl.endsWith('.xls') || lowerName.endsWith('.xlsx') || lowerUrl.endsWith('.xlsx')) extension = '.xls';
      else if (lowerName.endsWith('.txt') || lowerUrl.endsWith('.txt')) extension = '.txt';
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
      // Rich File Type Preview
      Color fileColor = color;
      IconData fileIcon = icon;
      String label = extension?.replaceAll('.', '').toUpperCase() ?? item.type.toUpperCase();
      
      if (extension == '.pdf') {
        fileColor = Colors.red.shade400;
        fileIcon = Icons.picture_as_pdf;
      } else if (extension == '.doc') {
        fileColor = Colors.blue.shade600;
        fileIcon = Icons.description;
      } else if (extension == '.ppt') {
        fileColor = Colors.orange.shade600;
        fileIcon = Icons.slideshow;
      } else if (extension == '.xls') {
        fileColor = Colors.green.shade600;
        fileIcon = Icons.table_chart;
      }

      content = Container(
        color: fileColor.withOpacity(0.15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(fileIcon, size: 48, color: fileColor),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: fileColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    // Wrap InkWell in Material to ensure splash effects are visible
    // and use ignorePointer for the content if it's a web view to prevent it from stealing clicks
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Content Layer
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: color.withOpacity(0.1),
                  child: IgnorePointer(child: content),
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
          // Interaction Layer - Full Cover InkWell
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                splashColor: Colors.black12,
                highlightColor: Colors.black12,
                hoverColor: Colors.black.withOpacity(0.05),
              ),
            ),
          ),
          
          // Action Button Layer (More Vert)
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
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
