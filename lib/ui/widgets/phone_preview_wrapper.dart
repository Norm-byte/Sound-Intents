import 'package:flutter/material.dart';

class PhonePreviewWrapper extends StatelessWidget {
  final Widget child;
  final String deviceName;
  final Size screenSize;

  const PhonePreviewWrapper({
    super.key,
    required this.child,
    this.deviceName = 'iPhone 14 Pro',
    this.screenSize = const Size(393, 852), // iPhone 14 Pro logical resolution
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(deviceName, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Container(
            width: screenSize.width,
            height: screenSize.height,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: Colors.grey.shade800, width: 8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 5,
                )
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(42), // slightly less than container
              child: Container(
                color: Colors.white, // App background
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
