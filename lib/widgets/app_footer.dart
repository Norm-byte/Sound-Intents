import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../build_info.dart';

class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final host = Uri.base.host; // works on web; empty on some platforms
    final env = host.isEmpty ? (kReleaseMode ? 'release' : 'debug') : host;
    return Material(
      color: Colors.grey.shade100,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 14, color: Colors.black54),
            const SizedBox(width: 6),
            Text('Env: $env', style: const TextStyle(fontSize: 12, color: Colors.black87)),
            const VerticalDivider(width: 16),
            Text('Build: ${BuildInfo.version} • ${BuildInfo.timestamp}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
