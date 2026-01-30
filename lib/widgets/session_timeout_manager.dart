// ignore_for_file: library_private_types_in_public_api

import 'dart:async';
import 'package:flutter/material.dart';

/// A wrapper widget that tracks user activity and logs out after inactivity.
class SessionTimeoutManager extends StatefulWidget {
  final Widget child;
  final Duration timeoutDuration;
  final VoidCallback onTimeout;

  const SessionTimeoutManager({
    super.key,
    required this.child,
    required this.timeoutDuration,
    required this.onTimeout,
  });

  @override
  _SessionTimeoutManagerState createState() => _SessionTimeoutManagerState();
}

class _SessionTimeoutManagerState extends State<SessionTimeoutManager> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.timeoutDuration, widget.onTimeout);
  }

  void _handleUserInteraction([_]) {
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    // Wrap with Listener to detect touch/mouse events
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleUserInteraction,
      onPointerMove: _handleUserInteraction,
      onPointerUp: _handleUserInteraction,
      child: MouseRegion(
          onHover: _handleUserInteraction,
          child: widget.child
      ),
    );
  }
}
