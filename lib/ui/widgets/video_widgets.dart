import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

class VideoGridItem extends StatefulWidget {
  final String url;
  final String? thumbnailUrl;
  final String type; // 'youtube' or 'upload'
  final bool enablePreview;
  final bool autoPlay;

  const VideoGridItem({
    super.key,
    required this.url,
    this.thumbnailUrl,
    required this.type,
    this.enablePreview = true,
    this.autoPlay = true,
  });

  @override
  State<VideoGridItem> createState() => _VideoGridItemState();
}

class _VideoGridItemState extends State<VideoGridItem> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    // Always initialize controller for uploads to show first frame (thumbnail)
    if (widget.type == 'upload' || widget.type == 'video') {
      _initializeController();
    }
  }

  Future<void> _initializeController() async {
    // If it's a YouTube URL, don't try to initialize video player
    if (widget.url.contains('youtube.com') || widget.url.contains('youtu.be')) {
      return;
    }

    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await _controller!.initialize();
      await _controller!.setVolume(0); // Mute for preview
      await _controller!.setLooping(true);
      if (widget.autoPlay) {
        await _controller!.play();
      }
      if (mounted) setState(() => _isInitialized = true);
    } catch (e) {
      debugPrint('Error initializing video preview: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String? _getYoutubeId(String url) {
    if (url.trim().isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      
      // Handle standard v parameter (youtube.com/watch?v=...)
      if (uri.queryParameters.containsKey('v')) {
        return uri.queryParameters['v'];
      }
      
      // Handle youtu.be (youtu.be/ID)
      if (uri.host.contains('youtu.be')) {
        return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      }
      
      // Handle shorts (youtube.com/shorts/ID)
      if (uri.pathSegments.contains('shorts')) {
        final index = uri.pathSegments.indexOf('shorts');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }
      
      // Handle embed (youtube.com/embed/ID)
      if (uri.pathSegments.contains('embed')) {
        final index = uri.pathSegments.indexOf('embed');
        if (index + 1 < uri.pathSegments.length) {
          return uri.pathSegments[index + 1];
        }
      }

      // Fallback for clean paths (youtube.com/v/ID)
      if (uri.host.contains('youtube.com') && uri.pathSegments.isNotEmpty) {
          // Sometimes it is just /ID, but rare.
      }
      
    } catch (_) {}
    return null;
  }

  void _showFullVideo() {
    final isYoutube = widget.type == 'youtube' || 
                      widget.url.contains('youtube.com') || 
                      widget.url.contains('youtu.be');
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand, // Ensure stack fills dialog
          children: [
            isYoutube 
              ? Center(child: YouTubePlayerWidget(videoId: _getYoutubeId(widget.url) ?? ''))
              : Center(child: FullVideoPlayer(url: widget.url)),
            Positioned(
              top: 20,
              right: 20,
              child: SafeArea(
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  radius: 24,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
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
  }

  @override
  Widget build(BuildContext context) {
    // Check if it's YouTube
    // We must check specifically for shorts too if the URL contains it
    if (widget.type == 'youtube' || 
        widget.url.contains('youtube.com') || 
        widget.url.contains('youtu.be')) {
          
      final videoId = _getYoutubeId(widget.url);
      final thumb = (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty)
          ? widget.thumbnailUrl
          : (videoId != null ? 'https://img.youtube.com/vi/$videoId/0.jpg' : null);

      return GestureDetector(
        onTap: widget.enablePreview ? _showFullVideo : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            image: thumb != null
                ? DecorationImage(image: NetworkImage(thumb), fit: BoxFit.cover)
                : null,
            color: Colors.black26,
          ),
          child: const Center(child: Icon(Icons.play_circle_fill, size: 48, color: Colors.white)),
        ),
      );
    }

    // Uploaded Video
    // Even if preview is disabled, we want to try to show the video frame
    // if (!widget.enablePreview) { ... } // Removed to allow thumbnail rendering

    if (!_isInitialized || _controller == null) {
      // If we are still initializing (or failed), show loading or icon
      return Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          color: Colors.black12,
        ),
        child: const Center(
             // Use smaller loader or simple icon while processing
             child: Icon(Icons.videocam, size: 48, color: Colors.grey)
        ),
      );
    }

    return GestureDetector(
      onTap: widget.enablePreview ? _showFullVideo : null,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(_controller!),
            if (widget.enablePreview)
              Container(
                color: Colors.black.withOpacity(0.1),
                child: const Center(child: Icon(Icons.fullscreen, size: 32, color: Colors.white70)),
              ),
          ],
        ),
      ),
    );
  }
}

class YouTubePlayerWidget extends StatelessWidget {
  final String videoId;
  const YouTubePlayerWidget({super.key, required this.videoId});

  @override
  Widget build(BuildContext context) {
    if (videoId.isEmpty) return const Center(child: Text('Invalid YouTube URL', style: TextStyle(color: Colors.white)));

    final String viewId = 'youtube-player-$videoId-${DateTime.now().millisecondsSinceEpoch}';
    
    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
      final iframe = html.IFrameElement()
        ..src = 'https://www.youtube.com/embed/$videoId?autoplay=1&modestbranding=1&rel=0&showinfo=0'
        ..style.border = 'none'
        ..allow = 'autoplay; encrypted-media; picture-in-picture';
      return iframe;
    });

    return Container(
      width: 800,
      height: 450,
      color: Colors.black,
      child: HtmlElementView(viewType: viewId),
    );
  }
}

class FullVideoPlayer extends StatefulWidget {
  final String url;
  const FullVideoPlayer({super.key, required this.url});

  @override
  State<FullVideoPlayer> createState() => _FullVideoPlayerState();
}

class _FullVideoPlayerState extends State<FullVideoPlayer> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        setState(() => _initialized = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) return const Center(child: CircularProgressIndicator());
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller),
          VideoProgressIndicator(_controller, allowScrubbing: true),
          Center(
            child: IconButton(
              icon: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 50,
              ),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders an MP4/video URL using a native browser <video> element via
/// HtmlElementView. This is more reliable on Flutter Web than VideoPlayerController
/// because the browser handles CORS, range requests, and codec support natively.
class HtmlVideoPreview extends StatelessWidget {
  final String url;
  final bool autoPlay;
  final bool loop;
  final bool muted;
  final bool controls;
  final String objectFit;

  const HtmlVideoPreview({
    super.key,
    required this.url,
    this.autoPlay = true,
    this.loop = true,
    this.muted = true,
    this.controls = true,
    this.objectFit = 'contain',
  });

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 48));
    }

    // Unique view ID so each widget instance gets its own element.
    final viewId = 'html-video-${url.hashCode}';

    // ignore: undefined_prefixed_name
    ui_web.platformViewRegistry.registerViewFactory(viewId, (int id) {
      final video = html.VideoElement()
        ..src = url
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = objectFit
        ..style.background = '#000';
      if (controls) video.controls = true;
      if (autoPlay) video.autoplay = true;
      if (loop) video.loop = true;
      if (muted) video.muted = true;
      return video;
    });

    return HtmlElementView(viewType: viewId);
  }
}
