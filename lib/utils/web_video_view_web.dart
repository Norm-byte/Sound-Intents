import 'package:flutter/material.dart';
// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'dart:async';

int _webVideoViewCounter = 0;

Widget buildWebVideoViewFromUrl(String url, {double height = 180, double borderRadius = 8}) {
  final viewId = 'video_view_${_webVideoViewCounter++}';
  ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) {
    final video = html.VideoElement()
      ..src = url
      ..controls = true
      ..preload = 'auto'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..attributes['playsinline'] = 'true';
    // Add error handling to show friendly message if video fails to load
    video.onError.listen((e) {
      video.style.background = '#f5f5f5';
      video.innerText = 'Video format not supported or failed to load';
    });
    return video;
  });
  return SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: HtmlElementView(viewType: viewId),
    ),
  );
}

Widget buildWebVideoViewFromBytes(Uint8List bytes, {double height = 180, double borderRadius = 8}) {
  final viewId = 'video_view_${_webVideoViewCounter++}';
  ui_web.platformViewRegistry.registerViewFactory(viewId, (int _) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrl(blob);
    final video = html.VideoElement()
      ..src = url
      ..controls = true
      ..preload = 'auto'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover'
      ..attributes['playsinline'] = 'true';
    // Add error handling
    video.onError.listen((e) {
      video.style.background = '#f5f5f5';
      video.innerText = 'Video format not supported or failed to load';
    });
    // Do not revoke URL immediately; keep for full playback. It will be GC'd on page unload.
    return video;
  });
  return SizedBox(
    height: height,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: HtmlElementView(viewType: viewId),
    ),
  );
}

/// Video metadata result including thumbnail and duration
class VideoMetadata {
  final String? thumbnailDataUrl;
  final String? durationFormatted; // e.g., "2:34"
  final double? durationSeconds;

  VideoMetadata({this.thumbnailDataUrl, this.durationFormatted, this.durationSeconds});
}

/// Captures the first frame of a video as a base64-encoded PNG thumbnail
/// and extracts duration. Returns metadata or null if capture fails.
/// Width/height are responsive - defaults to 320x180 for better quality.
Future<VideoMetadata?> captureVideoMetadata(
  Uint8List videoBytes, {
  int width = 320,
  int height = 180,
}) async {
  try {
    final blob = html.Blob([videoBytes]);
    final url = html.Url.createObjectUrl(blob);
    final video = html.VideoElement()
      ..src = url
      ..muted = true
      ..style.display = 'none';
    html.document.body!.append(video);

    final completer = Completer<VideoMetadata?>();
    
    // Set up timeout
    Timer(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        video.remove();
        html.Url.revokeObjectUrl(url);
        completer.complete(null);
      }
    });

    video.onLoadedMetadata.listen((_) async {
      if (completer.isCompleted) return;
      try {
        // Extract duration
        final durationSec = video.duration.isFinite ? video.duration.toDouble() : 0.0;
        final minutes = (durationSec / 60).floor();
        final seconds = (durationSec % 60).floor();
        final durationStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

        // Seek to a frame slightly in (avoid black first frame)
        video.currentTime = durationSec > 0.5 ? 0.5 : 0.1;
        await Future.delayed(const Duration(milliseconds: 150));

        final canvas = html.CanvasElement(width: width, height: height);
        final ctx = canvas.context2D;
        ctx.drawImageScaled(video, 0, 0, width, height);
        
        final dataUrl = canvas.toDataUrl('image/png');
        video.remove();
        html.Url.revokeObjectUrl(url);
        
        completer.complete(VideoMetadata(
          thumbnailDataUrl: dataUrl,
          durationFormatted: durationStr,
          durationSeconds: durationSec,
        ));
      } catch (e) {
        video.remove();
        html.Url.revokeObjectUrl(url);
        completer.complete(null);
      }
    });

    video.onError.listen((e) {
      if (!completer.isCompleted) {
        video.remove();
        html.Url.revokeObjectUrl(url);
        completer.complete(null);
      }
    });

    video.load();
    return await completer.future;
  } catch (e) {
    return null;
  }
}

/// Legacy thumbnail-only capture for backward compatibility
Future<String?> captureVideoThumbnail(Uint8List videoBytes, {int width = 320, int height = 180}) async {
  final metadata = await captureVideoMetadata(videoBytes, width: width, height: height);
  return metadata?.thumbnailDataUrl;
}
