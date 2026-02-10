// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui' as ui;

class ThumbnailGenerator {
  /// Generates a JPEG thumbnail from video bytes (Web only).
  /// Returns null if generation fails.
  static Future<Uint8List?> generateVideoThumbnail(Uint8List videoBytes) async {
    final completer = Completer<Uint8List?>();

    try {
      // Create a Blob from the video bytes
      final blob = html.Blob([videoBytes]);
      final url = html.Url.createObjectUrl(blob);

      final video = html.VideoElement()
        ..crossOrigin = 'anonymous'
        ..src = url
        ..muted = true
        ..autoplay = false;

      // Wait for metadata to load (to get dimensions)
      video.onLoadedMetadata.listen((_) {
        // Seek to 1 second or 50% if short, just to ensure we have a frame
        video.currentTime = 1.0; 
      });

      // Wait for seek to complete (the frame is ready)
      video.onSeeked.listen((_) {
        try {
          // Draw video frame to canvas
          final canvas = html.CanvasElement(
            width: video.videoWidth,
            height: video.videoHeight,
          );
          final ctx = canvas.context2D;
          ctx.drawImage(video, 0, 0);

          // Export to Blob (JPEG)
          // toBlob is async
          canvas.toBlob('image/jpeg', 0.7).then((thumbnailBlob) {
             final reader = html.FileReader();
             reader.onLoadEnd.listen((e) {
               html.Url.revokeObjectUrl(url); // Clean up video URL
               completer.complete(reader.result as Uint8List?);
             });
             reader.readAsArrayBuffer(thumbnailBlob);
          }).catchError((e) {
            html.Url.revokeObjectUrl(url);
            completer.complete(null);
          });
          
        } catch (e) {
          html.Url.revokeObjectUrl(url);
          completer.complete(null);
        }
      });

      // Handle errors
      video.onError.listen((e) {
        html.Url.revokeObjectUrl(url);
        if (!completer.isCompleted) completer.complete(null);
      });

      // Timeout safety
      Future.delayed(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          html.Url.revokeObjectUrl(url);
          completer.complete(null);
        }
      });

    } catch (e) {
      if (!completer.isCompleted) completer.complete(null);
    }

    return completer.future;
  }
}
