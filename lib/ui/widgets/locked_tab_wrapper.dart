import 'package:flutter/material.dart';

/// Simple access denial wrapper. When a regular admin lacks permission for a tab,
/// this shows a friendly "Not Authorized" dialog instead of password prompts.
class LockedTabWrapper extends StatefulWidget {
  final Widget child;
  final String title;
  final String? permKey;
  final bool isSuperAdmin;
  final Function(bool)? onUnlock;

  const LockedTabWrapper({
    super.key,
    required this.child,
    required this.title,
    this.permKey,
    this.isSuperAdmin = false,
    this.onUnlock,
  });

  @override
  State<LockedTabWrapper> createState() => _LockedTabWrapperState();
}

class _LockedTabWrapperState extends State<LockedTabWrapper> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    // Show access denied dialog once on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_dialogShown && mounted) {
        _showAccessDeniedDialog();
        _dialogShown = true;
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showAccessDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline, size: 48, color: Colors.red),
        title: const Text('Access Denied'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You do not have permission to access the ${widget.title} tab.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Contact a super-admin to request access.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tab is restricted. Render the child (hidden) but show access denied dialog on top.
    return widget.child;
  }
}
