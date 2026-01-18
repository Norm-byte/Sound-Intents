import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'dart:async';

Widget buildWebVideoViewFromUrl(String url, {double height = 180, double borderRadius = 8}) {
  // Non-web platforms: show placeholder
  return Container(
    height: height,
    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(borderRadius)),
    child: const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 48)),
  );
}

Widget buildWebVideoViewFromBytes(Uint8List bytes, {double height = 180, double borderRadius = 8}) {
  // Non-web platforms: show placeholder
  return Container(
    height: height,
    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(borderRadius)),
    child: const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 48)),
  );
}

/// Video metadata result including thumbnail and duration
class VideoMetadata {
  final String? thumbnailDataUrl;
  final String? durationFormatted;
  final double? durationSeconds;

  VideoMetadata({this.thumbnailDataUrl, this.durationFormatted, this.durationSeconds});
}

/// Stub implementation for non-web platforms
Future<VideoMetadata?> captureVideoMetadata(
  Uint8List videoBytes, {
  int width = 320,
  int height = 180,
}) async {
  return null; // Not supported on non-web platforms
}

/// Stub implementation for non-web platforms
Future<String?> captureVideoThumbnail(Uint8List videoBytes, {int width = 320, int height = 180}) async {
  return null; // Not supported on non-web platforms
}
