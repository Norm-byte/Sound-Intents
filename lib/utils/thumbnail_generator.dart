// ignore: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:js_util' as js_util; // For PDF.js main interop

class ThumbnailGenerator {

  /// Generates a JPEG thumbnail from PDF bytes using PDF.js.
  static Future<Uint8List?> generatePdfThumbnail(Uint8List pdfBytes) async {
    final completer = Completer<Uint8List?>();
    String? blobUrl;
    
    try {
      final pdfjsLib = js_util.getProperty(html.window, 'pdfjsLib');
      if (pdfjsLib == null) {
        print('ThumbnailGenerator: PDF.js library not found on window object.');
        return null;
      }

      // Create a Blob URL - this is much safer for passing data to JS than raw bytes
      final blob = html.Blob([pdfBytes], 'application/pdf');
      blobUrl = html.Url.createObjectUrl(blob);
      print('ThumbnailGenerator: Created Blob URL for PDF: $blobUrl');

      // pdfjsLib.getDocument(url).promise
      final loadingTask = js_util.callMethod(pdfjsLib, 'getDocument', [blobUrl]);
      final docPromise = js_util.getProperty(loadingTask, 'promise');
      final pdfDoc = await js_util.promiseToFuture(docPromise);
      print('ThumbnailGenerator: PDF Document loaded successfully');

      // doc.getPage(1)
      final pagePromise = js_util.callMethod(pdfDoc, 'getPage', [1]);
      final page = await js_util.promiseToFuture(pagePromise);

      // page.getViewport({ scale: 0.5 }) -> Smaller scale for thumbnail
      final viewportConfig = js_util.newObject();
      js_util.setProperty(viewportConfig, 'scale', 0.5);
      final viewport = js_util.callMethod(page, 'getViewport', [viewportConfig]);

      // Create canvas
      final canvas = html.CanvasElement();
      final context = canvas.context2D;
      
      // Force dimensions to be integers
      final vHeight = js_util.getProperty(viewport, 'height');
      final vWidth = js_util.getProperty(viewport, 'width');
      canvas.height = (vHeight is num ? vHeight : double.parse(vHeight.toString())).toInt();
      canvas.width = (vWidth is num ? vWidth : double.parse(vWidth.toString())).toInt();

      // Render context
      final renderContext = js_util.newObject();
      js_util.setProperty(renderContext, 'canvasContext', context);
      js_util.setProperty(renderContext, 'viewport', viewport);

      // page.render(renderContext).promise
      final renderTask = js_util.callMethod(page, 'render', [renderContext]);
      final renderPromise = js_util.getProperty(renderTask, 'promise');
      await js_util.promiseToFuture(renderPromise);
      print('ThumbnailGenerator: Page rendered to canvas');

      // Convert canvas to Blob -> Bytes
      // 0.7 quality JPEG
      final blobCompleter = Completer<html.Blob>();
      canvas.toBlob('image/jpeg', 0.7).then((blob) {
         if (blob != null) {
           blobCompleter.complete(blob);
         } else {
           completer.complete(null);
         }
      });
      
      final resultBlob = await blobCompleter.future;
      final reader = html.FileReader();
      reader.readAsArrayBuffer(resultBlob);
      await reader.onLoadEnd.first;
      
      completer.complete(reader.result as Uint8List?);

    } catch (e) {
      print('ThumbnailGenerator: Error generating PDF thumbnail: $e');
      if (!completer.isCompleted) completer.complete(null);
    } finally {
      // Cleanup: Revoke the Object URL to free memory
      if (blobUrl != null) {
        html.Url.revokeObjectUrl(blobUrl);
      }
    }

    return completer.future;
  }

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
