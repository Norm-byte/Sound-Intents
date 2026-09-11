import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

class YoutubeEmbedCheckResult {
  final bool checked;
  final bool embeddable;
  final String? reason;

  YoutubeEmbedCheckResult({
    required this.checked,
    required this.embeddable,
    this.reason,
  });
}

/// Calls the `checkYoutubeEmbeddable` Cloud Function before a YouTube video
/// is published, so admins are warned when a creator has disabled embedding.
class YoutubeEmbedCheckService {
  static Future<YoutubeEmbedCheckResult> check(String videoId) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('checkYoutubeEmbeddable')
          .call({'videoId': videoId});
      final data = Map<String, dynamic>.from(result.data as Map);
      return YoutubeEmbedCheckResult(
        checked: data['checked'] == true,
        embeddable: data['embeddable'] != false,
        reason: data['reason'] as String?,
      );
    } catch (e) {
      // Fail open: a check-service outage must never block admin publishing.
      return YoutubeEmbedCheckResult(
        checked: false,
        embeddable: true,
        reason: 'Check failed: $e',
      );
    }
  }

  /// Returns true if the caller should proceed with publishing [videoId].
  /// Blocks with a dialog only when the API positively confirms embedding is
  /// disabled; any other outcome (including a failed check) proceeds with a
  /// best-effort notice rather than stopping the admin's work.
  static Future<bool> confirmBeforePublish(
    BuildContext context,
    String videoId,
  ) async {
    final result = await check(videoId);
    if (!context.mounted) return false;

    if (result.checked && !result.embeddable) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Embedding disabled by creator'),
          content: Text(
            result.reason == 'Video not found, private, or already removed.'
                ? 'This video could not be published: it is private, removed, or the ID is invalid.'
                : 'This video cannot be published: the creator has disabled embedding on third-party apps. Please choose a different video.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return false;
    }

    if (!result.checked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not verify embeddability (${result.reason ?? 'unknown reason'}). Proceeding anyway.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }

    return true;
  }
}
