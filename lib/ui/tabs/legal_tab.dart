import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/media_library_service.dart';
import '../../models/media_item.dart';

// Conditional import for web shim
import 'web_pdf_shim.dart' if (dart.library.io) 'web_pdf_shim_stub.dart';

class LegalTab extends StatefulWidget {
  const LegalTab({super.key});

  @override
  State<LegalTab> createState() => _LegalTabState();
}

class _LegalTabState extends State<LegalTab> {
  // Locking State - RESTORED
  bool _isLocked = true;
  bool _isLoadingLockState = true;
  final _unlockController = TextEditingController();
  String? _storedSecurityPassword;
  String? _storedVipCode;
  String? _storedDirectVipCode;

  // Legal Content State
  String _selectedDocId = 'terms';
  Map<String, String?> _pdfUrls = {};
  bool _isLoading = true;

  final List<Map<String, dynamic>> _documents = [
    {'title': 'Terms & Conditions', 'id': 'terms', 'hasCheckbox': true},
    {'title': 'Legal', 'id': 'legal', 'hasCheckbox': false},
    {'title': 'About', 'id': 'about', 'hasCheckbox': false},
  ];

  @override
  void initState() {
    super.initState();
    _loadLockState();
    _loadAllDocs();
  }

  Future<void> _loadLockState() async {
    setState(() => _isLoadingLockState = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. Get Security Password
      final userDoc = await FirebaseFirestore.instance
          .collection('admin_users')
          .doc(user.uid)
          .get();

      _storedSecurityPassword = userDoc.data()?['security_password'];

      // 2. Get VIP Code
      final vipQuery = await FirebaseFirestore.instance
          .collection('vip_codes')
          .where('assignee', isEqualTo: user.email)
          .get();

      if (vipQuery.docs.isNotEmpty) {
        final superAdminCode = vipQuery.docs.firstWhere(
            (d) => d.data()['type'] == 'super_admin',
            orElse: () => vipQuery.docs.first);
        _storedVipCode = superAdminCode.data()['code'];
      }

      final directVipCode = userDoc.data()?['vipCode'];
      if (directVipCode != null) {
        _storedDirectVipCode = directVipCode;
      }

      // Auto-unlock if no password set
      if (_storedSecurityPassword == null) {
        setState(() => _isLocked = false);
      }
    } catch (e) {
      debugPrint('Error loading lock state: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLockState = false);
    }
  }

  Future<void> _attemptUnlock() async {
    final input = _unlockController.text.trim();
    if (input.isEmpty) return;

    bool unlocked = false;
    if (_storedSecurityPassword != null && input == _storedSecurityPassword)
      unlocked = true;
    if (_storedVipCode != null && input == _storedVipCode) unlocked = true;
    if (_storedDirectVipCode != null && input == _storedDirectVipCode)
      unlocked = true;

    if (!unlocked) {
      try {
        final query = await FirebaseFirestore.instance
            .collection('vip_codes')
            .where('code', isEqualTo: input)
            .where('type', isEqualTo: 'super_admin')
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();

        if (query.docs.isNotEmpty) {
          unlocked = true;
        }
      } catch (e) {
        debugPrint('Error checking VIP code: $e');
      }
    }

    if (unlocked) {
      setState(() {
        _isLocked = false;
        _unlockController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect password or VIP code'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPdfViewer(String url) {
    if (kIsWeb) {
      final String viewType = 'iframe-${url.hashCode}';
      // Append params to hide toolbar, navpanes, and scrollbars
      final String embedUrl = '$url#toolbar=0&navpanes=0&scrollbar=0';
      registerPdfViewFactory(viewType, embedUrl);
      return HtmlElementView(viewType: viewType);
    }

    return SfPdfViewer.network(
      url,
    );
  }

/*
  Future<void> _attemptUnlock() async {
    ... Removed ...
  }
*/

  Future<void> _loadAllDocs() async {
    setState(() => _isLoading = true);
    try {
      for (var doc in _documents) {
        final snapshot = await FirebaseFirestore.instance
            .collection('app_config')
            .doc(doc['id'])
            .get();
        if (snapshot.exists) {
          _pdfUrls[doc['id']] = snapshot.data()?['pdfUrl'];
        }
      }
    } catch (e) {
      debugPrint('Error loading docs: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFromMediaLibrary(String docId) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _MediaPickerDialog(),
    );

    if (result != null) {
      setState(() {
        _pdfUrls[docId] = result;
      });
      _publish(docId);
    }
  }

  Future<void> _publish(String docId) async {
    final doc = _documents.firstWhere((d) => d['id'] == docId);
    final url = _pdfUrls[docId];

    if (url == null) return;

    try {
      await FirebaseFirestore.instance.collection('app_config').doc(docId).set({
        'pdfUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
        'title': doc['title'],
        'hasCheckbox': doc['hasCheckbox'],
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${doc['title']} updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error publishing: $e');
    }
  }

  Future<void> _delete(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc(docId)
          .delete();
      setState(() {
        _pdfUrls[docId] = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document removed')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLockState) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_isLocked) {
      return Center(
        child: Card(
          elevation: 4,
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock, size: 64, color: Colors.indigo),
                const SizedBox(height: 24),
                const Text(
                  'Legal Tab Locked',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please enter your Security Password or VIP Code to access legal document management.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _unlockController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password / VIP Code',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key),
                  ),
                  onSubmitted: (_) => _attemptUnlock(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _attemptUnlock,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final selectedDoc = _documents.firstWhere((d) => d['id'] == _selectedDocId);
    final selectedUrl = _pdfUrls[_selectedDocId];

    return Row(
      children: [
        // Left Side: Controls
        Container(
          width: 400,
          color: Colors.white,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Legal Documents',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('Select a document to view and edit.'),
              const SizedBox(height: 24),

              // Document List
              Expanded(
                child: ListView(
                  children:
                      _documents.map((doc) => _buildDocCard(doc)).toList(),
                ),
              ),

              const Divider(height: 32),

              // Action Buttons for Selected Doc
              // ALWAYS SHOW BUTTONS regardless of whether a URL exists yet,
              // so user can upload the first one.
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _pickFromMediaLibrary(_selectedDocId),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Upload / Change PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ALWAYS SHOW PUBLISH/REMOVE BUTTONS (User Request)
              // Even if no URL is selected yet, show them (maybe disabled or just let them fail gracefully)
              // But user specifically asked for "the same three buttons to appear".
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (selectedUrl == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Please upload a PDF first.')));
                      return;
                    }
                    _publish(_selectedDocId);
                  },
                  icon: const Icon(Icons.publish),
                  label: const Text('Publish Changes'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    if (selectedUrl == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Nothing to remove.')));
                      return;
                    }
                    _delete(_selectedDocId);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text('Remove Document',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Right Side: Full Screen Phone Preview
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
                    backgroundColor: Colors.white,
                    appBar: AppBar(
                      backgroundColor: const Color(0xFF1A1A2E),
                      title: Text(selectedDoc['title'],
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18)),
                      centerTitle: true,
                      leading:
                          const Icon(Icons.arrow_back, color: Colors.white),
                      elevation: 0,
                    ),
                    body: Stack(
                      children: [
                        if (_isLoading)
                          const Center(child: CircularProgressIndicator())
                        else if (selectedUrl != null)
                          Container(
                            color: Colors.white,
                            child: _buildPdfViewer(selectedUrl),
                          )
                        else
                          Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.picture_as_pdf,
                                    size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text(
                                  'No PDF Selected for\n${selectedDoc['title']}',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 16),
                                ),
                              ],
                            ),
                          ),

                        // Conditional Checkbox Overlay (Only for Terms)
                        if (selectedDoc['id'] == 'terms')
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, -2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: false,
                                    onChanged: (_) {},
                                    activeColor: Colors.indigo,
                                  ),
                                  const Expanded(
                                    child: Text(
                                      'I agree to the Terms & Conditions',
                                      style: TextStyle(fontSize: 14),
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
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDocCard(Map<String, dynamic> doc) {
    final isSelected = _selectedDocId == doc['id'];
    final hasFile = _pdfUrls[doc['id']] != null;

    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.indigo.shade50 : Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Colors.indigo, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedDocId = doc['id']),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.indigo : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.description,
                  color: isSelected ? Colors.white : Colors.grey,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc['title'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.indigo : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile ? 'PDF Uploaded' : 'No file selected',
                      style: TextStyle(
                        color: hasFile ? Colors.green : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPickerDialog extends StatefulWidget {
  const _MediaPickerDialog();

  @override
  State<_MediaPickerDialog> createState() => _MediaPickerDialogState();
}

class _MediaPickerDialogState extends State<_MediaPickerDialog> {
  final MediaLibraryService _mediaService = MediaLibraryService();
  String _selectedSection = 'Blogs'; // Default to Blogs as requested

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 900,
        height: 700,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Select PDF from Media Library',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Row(
                children: [
                  // Sidebar Sections
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      border: Border(
                          right: BorderSide(color: Colors.grey.shade300)),
                    ),
                    child: StreamBuilder<List<String>>(
                      stream: _mediaService.getSectionsStream(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const Center(
                              child: CircularProgressIndicator());
                        final sections = ['All', ...snapshot.data!];

                        return ListView.builder(
                          itemCount: sections.length,
                          itemBuilder: (context, index) {
                            final section = sections[index];
                            final isSelected = _selectedSection == section;
                            return ListTile(
                              title: Text(section),
                              selected: isSelected,
                              selectedTileColor: Colors.indigo.shade50,
                              onTap: () =>
                                  setState(() => _selectedSection = section),
                            );
                          },
                        );
                      },
                    ),
                  ),

                  // Grid Content
                  Expanded(
                    child: StreamBuilder<List<MediaItem>>(
                      stream: _mediaService.getMediaStream(
                          section: _selectedSection),
                      builder: (context, snapshot) {
                        if (snapshot.hasError)
                          return Center(
                              child: Text('Error: ${snapshot.error}'));
                        if (!snapshot.hasData)
                          return const Center(
                              child: CircularProgressIndicator());

                        final items = snapshot.data!;
                        // Filter for PDFs
                        final pdfs = items
                            .where((item) =>
                                item.name.toLowerCase().endsWith('.pdf') ||
                                item.type == 'pdf' ||
                                item.url.contains('.pdf'))
                            .toList();

                        if (pdfs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.picture_as_pdf,
                                    size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text('No PDFs found in "$_selectedSection"'),
                                const SizedBox(height: 8),
                                const Text(
                                    'Try selecting "All" or uploading to "Blogs" first.',
                                    style: TextStyle(color: Colors.grey)),
                              ],
                            ),
                          );
                        }

                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: 0.8,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: pdfs.length,
                          itemBuilder: (context, index) {
                            final item = pdfs[index];
                            return InkWell(
                              onTap: () => Navigator.pop(context, item.url),
                              child: Card(
                                elevation: 2,
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        color: Colors.red.shade50,
                                        child: const Center(
                                          child: Icon(Icons.picture_as_pdf,
                                              size: 48, color: Colors.red),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.section,
                                            style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey.shade600),
                                          ),
                                        ],
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
            ),
          ],
        ),
      ),
    );
  }
}
