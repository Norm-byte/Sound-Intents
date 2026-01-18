import 'dart:typed_data';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/media_item.dart';
import 'storage_service.dart';

class MediaLibraryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StorageService _storageService = StorageService();

  // --- Media Items ---

  /// Test connection by attempting to list and write a small file.
  Future<String> runDiagnostics() async {
    final sb = StringBuffer();
    sb.writeln('Starting Diagnostics...');
    
    // 1. Check Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      sb.writeln('❌ Auth: Not logged in.');
      return sb.toString();
    }
    sb.writeln('✅ Auth: Logged in as ${user.email}');

    // 2. Check Firestore Read
    try {
      await _firestore.collection('media_settings').doc('sections').get();
      sb.writeln('✅ Firestore Read: Success');
    } catch (e) {
      sb.writeln('❌ Firestore Read: Failed ($e)');
    }

    // 3. Check Storage Write (Simple)
    try {
      final ref = FirebaseStorage.instance.ref().child('diagnostics/test_${DateTime.now().millisecondsSinceEpoch}.txt');
      final data = Uint8List.fromList('Test'.codeUnits);
      await ref.putData(data).timeout(const Duration(seconds: 10));
      sb.writeln('✅ Storage Write: Success');
      // Cleanup
      await ref.delete();
    } catch (e) {
      sb.writeln('❌ Storage Write: Failed ($e)');
      if (e.toString().contains('unknown')) {
        sb.writeln('   -> Likely CORS issue. Browser blocked the request.');
      }
    }

    return sb.toString();
  }

  /// Adds an external media link (e.g. YouTube) to the library without uploading a file.
  Future<void> addExternalMedia({
    required String name,
    required String url,
    required String type,
    required String section,
  }) async {
    final mediaItem = MediaItem(
      id: '',
      name: name,
      url: url,
      path: '', // No storage path for external media
      type: type,
      section: section,
      uploadedAt: DateTime.now(),
    );
    
    await _firestore.collection('media_library').add(mediaItem.toMap());
  }

  /// Uploads a file to Storage and creates a metadata record in Firestore.
  Future<void> uploadMedia({
    required Uint8List bytes,
    required String fileName,
    required String section,
  }) async {
    print('MediaLibraryService: Starting upload for $fileName (${bytes.lengthInBytes} bytes) to section $section');
    
    final fileExt = fileName.split('.').last;
    final type = _inferTypeFromName(fileName);
    
    // Upload to Storage
    final safeSection = section.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final path = 'media/$safeSection/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    
    final ref = FirebaseStorage.instance.ref().child(path);
    final metadata = SettableMetadata(contentType: _inferContentType(fileExt));
    
    try {
      // Add timeout to upload
      print('MediaLibraryService: Executing putData...');
      await ref.putData(bytes, metadata).timeout(
        const Duration(minutes: 10), // Increased to 10 minutes for large files
        onTimeout: () {
          print('MediaLibraryService: putData timed out!');
          throw TimeoutException('Upload timed out after 10 minutes');
        },
      );
      print('MediaLibraryService: putData complete.');
      
      final url = await ref.getDownloadURL().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Getting download URL timed out'),
      );
      print('MediaLibraryService: Got URL: $url');

      // Create Firestore Record
      final mediaItem = MediaItem(
        id: '', // Firestore will generate
        name: fileName,
        url: url,
        path: path,
        type: type,
        section: section,
        uploadedAt: DateTime.now(),
      );

      print('MediaLibraryService: Saving to Firestore...');
      await _firestore.collection('media_library').add(mediaItem.toMap()).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException('Saving metadata timed out'),
      );
      print('MediaLibraryService: Firestore save complete.');
    } on FirebaseException catch (e) {
      print('MediaLibraryService: Firebase Error: ${e.code} - ${e.message}');
      throw Exception('Firebase Error (${e.code}): ${e.message}');
    } catch (e) {
      print('MediaLibraryService: Error during upload process: $e');
      rethrow;
    }
  }

  /// Get media items, optionally filtered by section.
  Stream<List<MediaItem>> getMediaStream({String? section}) {
    // Fetch ALL items ordered by date.
    // We filter client-side to avoid needing a composite index (section + uploadedAt) in Firestore.
    Query query = _firestore.collection('media_library').orderBy('uploadedAt', descending: true);

    return query.snapshots().map((snapshot) {
      final allItems = snapshot.docs.map((doc) => MediaItem.fromFirestore(doc)).toList();
      
      if (section != null && section != 'All') {
        return allItems.where((item) => item.section == section).toList();
      }
      return allItems;
    });
  }

  /// Delete media item from Firestore and Storage.
  Future<void> deleteMedia(MediaItem item) async {
    // Delete from Storage
    try {
      await FirebaseStorage.instance.ref(item.path).delete();
    } catch (e) {
      // Ignore if file not found (maybe already deleted)
      print('Error deleting file from storage: $e');
    }

    // Delete from Firestore
    await _firestore.collection('media_library').doc(item.id).delete();
  }

  // --- Sections ---

  /// Get list of available sections.
  Stream<List<String>> getSectionsStream() {
    return _firestore.collection('media_settings').doc('sections').snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) {
        return []; // No default sections
      }
      final data = doc.data()!;
      final rawList = data['list'];
      final List<dynamic> sections = (rawList is List) ? rawList : [];
      return sections.map((e) => e.toString()).toList()..sort();
    });
  }

  /// Add a new section.
  Future<void> addSection(String sectionName) async {
    final docRef = _firestore.collection('media_settings').doc('sections');
    
    // Use simple get/set instead of transaction to avoid web interop issues
    try {
      final snapshot = await docRef.get().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('Reading sections timed out'),
      );
      
      if (!snapshot.exists) {
        await docRef.set({
          'list': [sectionName]
        }).timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TimeoutException('Creating section timed out'),
        );
      } else {
        final data = snapshot.data();
        final rawList = data?['list'];
        // Ensure we have a growable list and handle potential type mismatches
        final List<dynamic> currentList = (rawList is List) ? List.from(rawList) : [];

        if (!currentList.contains(sectionName)) {
          currentList.add(sectionName);
          await docRef.update({'list': currentList}).timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException('Updating sections timed out'),
          );
        }
      }
    } catch (e) {
      print('Error in addSection: $e');
      rethrow;
    }
  }

  /// Rename a section.
  Future<void> updateSection(String oldName, String newName) async {
    if (oldName == 'All') throw Exception('Cannot rename default sections');
    
    final docRef = _firestore.collection('media_settings').doc('sections');
    
    try {
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        final rawList = data?['list'];
        final List<dynamic> currentList = (rawList is List) ? List.from(rawList) : [];

        final index = currentList.indexOf(oldName);
        if (index != -1) {
          currentList[index] = newName;
          await docRef.update({'list': currentList});
          
          // Also update all media items in this section
          final batch = _firestore.batch();
          final mediaQuery = await _firestore.collection('media_library').where('section', isEqualTo: oldName).get();
          for (var doc in mediaQuery.docs) {
            batch.update(doc.reference, {'section': newName});
          }
          await batch.commit();
        }
      }
    } catch (e) {
      print('Error updating section: $e');
      rethrow;
    }
  }

  /// Delete a section.
  Future<void> deleteSection(String sectionName) async {
    if (sectionName == 'All') throw Exception('Cannot delete default sections');

    final docRef = _firestore.collection('media_settings').doc('sections');
    
    try {
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        final rawList = data?['list'];
        final List<dynamic> currentList = (rawList is List) ? List.from(rawList) : [];

        if (currentList.contains(sectionName)) {
          currentList.remove(sectionName);
          await docRef.update({'list': currentList});
          
          // Move all media items in this section to 'Uncategorized'
          final batch = _firestore.batch();
          final mediaQuery = await _firestore.collection('media_library').where('section', isEqualTo: sectionName).get();
          for (var doc in mediaQuery.docs) {
            batch.update(doc.reference, {'section': 'Uncategorized'});
          }
          await batch.commit();
        }
      }
    } catch (e) {
      print('Error deleting section: $e');
      rethrow;
    }
  }

  /// Move media item to another section.
  Future<void> moveMedia(MediaItem item, String newSection) async {
    print('Moving media ${item.id} from ${item.section} to $newSection');
    try {
      await _firestore.collection('media_library').doc(item.id).update({'section': newSection});
      print('Move successful');
    } catch (e) {
      print('Error moving media: $e');
      rethrow;
    }
  }

  /// Rename media item.
  Future<void> renameMedia(MediaItem item, String newName) async {
    print('Renaming media ${item.id} to $newName');
    try {
      await _firestore.collection('media_library').doc(item.id).update({'name': newName});
      print('Rename successful');
    } catch (e) {
      print('Error renaming media: $e');
      rethrow;
    }
  }

  /// Copy media item to another section.
  Future<void> copyMedia(MediaItem item, String newSection) async {
    try {
      final newItem = MediaItem(
        id: '', // Firestore will generate
        name: item.name,
        url: item.url,
        path: item.path, // Points to same storage file
        type: item.type,
        section: newSection,
        uploadedAt: DateTime.now(),
      );
      await _firestore.collection('media_library').add(newItem.toMap());
    } catch (e) {
      print('Error copying media: $e');
      rethrow;
    }
  }

  String _inferTypeFromName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.webm') || lower.endsWith('.mov') || lower.endsWith('.m4v') || lower.endsWith('.avi')) return 'video';
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.gif') || lower.endsWith('.webp')) return 'image';
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.aac') || lower.endsWith('.m4a')) return 'audio';
    if (lower.endsWith('.pdf') || lower.endsWith('.doc') || lower.endsWith('.docx') || lower.endsWith('.ppt') || lower.endsWith('.pptx') || lower.endsWith('.txt')) return 'document';
    return 'other';
  }

  String _inferContentType(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'm4a':
        return 'audio/mp4';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}
