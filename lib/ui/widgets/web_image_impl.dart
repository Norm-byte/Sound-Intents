import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;

class WebImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  
  const WebImage({super.key, required this.imageUrl, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    // Unique view key based on URL AND a random persistent ID to force freshness if needed
    // However, for performance, we should just use the URL hash if it's stable.
    // Issue: If the widget is rebuilt but the URL hasn't changed, we want the same view.
    // If the URL changes, we want a new view.
    final String viewType = 'img-${imageUrl.hashCode}';
    
    // Always register/overwrite to ensure the factory is there.
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final img = html.ImageElement()
        ..src = imageUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = fit == BoxFit.cover ? 'cover' : 'contain'
        ..style.border = 'none'
        // Ensure it doesn't capture clicks if it's just a background
        ..style.pointerEvents = 'none'; 
      return img;
    });

    // Use Key to force Flutter to treat it as a new widget if URL changes
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: HtmlElementView(
        key: ValueKey(viewType),
        viewType: viewType,
      ),
    );
  }
}
