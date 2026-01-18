import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_storage/firebase_storage.dart';

/// StorageService abstracts Firebase Storage uploads for web admin.
/// It accepts raw bytes and a suggested file extension, uploading to
/// a structured path and returning a downloadable URL.
class StorageService {
  FirebaseStorage get _storage => FirebaseStorage.instance;

  /// Uploads data to Firebase Storage.
  /// [bytes]: Raw file data.
  /// [fileExt]: e.g. 'png', 'mp3', 'pdf'. Used to set contentType.
  /// [folder]: logical folder (defaults to 'uploads').
  /// Returns download URL or throws.
  Future<String> uploadBytes(Uint8List bytes, {required String fileExt, String folder = 'uploads'}) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final path = '$folder/$id.$fileExt';
    final ref = _storage.ref().child(path);
    final metadata = SettableMetadata(contentType: _inferContentType(fileExt));
    await ref.putData(bytes, metadata);
    return await ref.getDownloadURL();
  }

  /// Upload with progress callback [onProgress] reporting 0.0..1.0.
  Future<String> uploadBytesWithProgress(
    Uint8List bytes, {
    required String fileExt,
    String folder = 'uploads',
    void Function(double progress)? onProgress,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final path = '$folder/$id.$fileExt';
    final ref = _storage.ref().child(path);
    final metadata = SettableMetadata(contentType: _inferContentType(fileExt));
    final task = ref.putData(bytes, metadata);
    await for (final snapshot in task.snapshotEvents) {
      final total = snapshot.totalBytes;
      final transferred = snapshot.bytesTransferred;
      if (total > 0 && onProgress != null) {
        onProgress((transferred / total).clamp(0.0, 1.0));
      }
    }
    return await ref.getDownloadURL();
  }

  /// Uploads and then appends to an existing list of attachments.
  Future<List<String>> uploadAndAppend(Uint8List bytes, {required String fileExt, List<String>? existing, String folder = 'attachments'}) async {
    final url = await uploadBytes(bytes, fileExt: fileExt, folder: folder);
    final list = <String>[...(existing ?? const <String>[]), url];
    return list;
  }

  /// Uploads a base64 data URL (e.g., video thumbnail) to storage.
  /// Extracts bytes from the data URL and uploads as PNG.
  /// Returns download URL or null on failure.
  Future<String?> uploadDataUrl(String dataUrl, {String folder = 'thumbnails'}) async {
    try {
      // Parse data:image/png;base64,<data>
      if (!dataUrl.startsWith('data:')) return null;
      final parts = dataUrl.split(',');
      if (parts.length != 2) return null;
      
      // Decode base64 to bytes
      final bytes = base64.decode(parts[1]);
      
      return await uploadBytes(bytes, fileExt: 'png', folder: folder);
    } catch (e) {
      return null;
    }
  }

  /// Deletes a file from Firebase Storage by its download URL.
  Future<void> deleteByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (_) {
      // Ignore deletion failures to avoid blocking UI
    }
  }

  String _inferContentType(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'webp':
        return 'image/${ext == 'jpg' ? 'jpeg' : ext}';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
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
      case 'docx':
        return 'application/msword';
      case 'txt':
        return 'text/plain';
      case 'md':
        return 'text/markdown';
      default:
        return 'application/octet-stream';
    }
  }
}
