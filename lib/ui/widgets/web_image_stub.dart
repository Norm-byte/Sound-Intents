import 'package:flutter/material.dart';

class WebImage extends StatelessWidget {
  final String imageUrl;
  final BoxFit fit;
  
  const WebImage({super.key, required this.imageUrl, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl, 
      fit: fit,
      errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
    );
  }
}
