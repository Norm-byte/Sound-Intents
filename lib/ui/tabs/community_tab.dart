import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/video_widgets.dart';
import '../../services/translation_service.dart';
import '../../widgets/translatable_text.dart';

class CommunityTab extends StatefulWidget {
  final Function(String userId)? onUserSelected;
  const CommunityTab({super.key, this.onUserSelected});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  final TextEditingController _messageController = TextEditingController(); // For Pinned Message
  final TextEditingController _adminChatController = TextEditingController(); // For Admin Chat
  bool _isMessageLoaded = false;
  
  // Feed Selection State
  String _selectedFeedId = 'global'; // 'global' or groupId
  String _selectedFeedName = 'Global Public Feed';

  // Community view toggle: 'queue' or 'feed'
  String _communityView = 'queue';

  static const Map<String, String> _moderationActionLabels = {
    'no_action': 'No action needed',
    'warned': 'User warned',
    'content_removed': 'Content removed',
    'content_removed_reel': 'Reel removed',
    'user_suspended': 'User suspended',
    'dismissed': 'Dismissed',
  };

  String _currentAdminActor() {
    final admin = FirebaseAuth.instance.currentUser;
    final email = admin?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    final name = admin?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return admin?.uid ?? 'unknown_admin';
  }

  Map<String, dynamic> _buildModerationAuditFields({
    required String status,
    required String action,
    String? note,
  }) {
    final admin = FirebaseAuth.instance.currentUser;
    final actionLabel = _moderationActionLabels[action] ?? action;
    final actor = _currentAdminActor();

    return {
      'status': status,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedAction': action,
      'resolvedActionLabel': actionLabel,
      'resolvedBy': actor,
      'resolvedByUid': admin?.uid,
      'resolvedByEmail': admin?.email,
      'resolvedByDisplayName': admin?.displayName,
      'moderationActor': actor,
      'moderationActorUid': admin?.uid,
      'moderationActorEmail': admin?.email,
      'moderationActorDisplayName': admin?.displayName,
      'moderationUpdatedAt': FieldValue.serverTimestamp(),
      if (note != null && note.trim().isNotEmpty) 'resolutionNote': note.trim(),
    };
  }

  Future<void> _deleteLiveFeedMessage(
    BuildContext context,
    DocumentSnapshot postDoc,
    Map<String, dynamic> post,
  ) async {
    try {
      await postDoc.reference.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
      return;
    } on FirebaseException catch (e) {
      // Fallback to moderation-style soft delete when hard delete is blocked.
      try {
        final currentText = (post['content'] ?? post['text'] ?? '').toString();
        final replacement = currentText.isNotEmpty
            ? '[Message removed by moderator]'
            : '[Removed]';
        final admin = FirebaseAuth.instance.currentUser;

        final isGlobal = _selectedFeedId == 'global';
        final patch = <String, dynamic>{
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedByUid': admin?.uid,
          'deletedByEmail': admin?.email,
          'moderationUpdatedAt': FieldValue.serverTimestamp(),
          if (isGlobal)
            'content': replacement
          else
            'text': replacement,
        };

        await postDoc.reference.set(patch, SetOptions(merge: true));

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message removed (soft delete).'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      } catch (_) {
        if (!mounted) return;
        final code = e.code.isNotEmpty ? e.code : 'unknown';
        final friendly = code == 'permission-denied'
            ? 'Delete blocked by permissions for this message.'
            : 'Delete failed ($code).';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendly), backgroundColor: Colors.red),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e'), backgroundColor: Colors.red),
      );
    }
  }


  @override
  void initState() {
    super.initState();
    TranslationService.instance.init();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _adminChatController.dispose();
    super.dispose();
  }

  Future<void> _sendAdminChat(String text) async {
      final content = text.trim();
      if (content.isEmpty) return;
      
      try {
        if (_selectedFeedId == 'global') {
          await FirebaseFirestore.instance.collection('community_posts').add({
            'content': content,
            'userId': 'admin_host',
            'userName': 'Harmony Host', // Distinct name
            'userPhoto': null, // Or admin avatar URL
            'timestamp': FieldValue.serverTimestamp(),
            'isAdmin': true, 
          });
        } else {
          await FirebaseFirestore.instance
              .collection('community_groups')
              .doc(_selectedFeedId)
              .collection('messages') // Matches ChatScreen path
              .add({
                'text': content,
                'sender': 'Harmony Host',
                'userId': 'admin_host',
                'timestamp': FieldValue.serverTimestamp(),
                'isAdmin': true,
              });
        }
        _adminChatController.clear();
          _messageController.clear();
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Posted as Admin')));
        }
      } catch (e) {
         if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
  }

  Future<void> _saveAdminMessage(String value) async {
    // Allow clearing the message if empty string is passed (to remove the sticky header)
    final messageToSave = value.trim();
    
    try {
      if (_selectedFeedId == 'global') {
        await FirebaseFirestore.instance
            .collection('app_config')
            .doc('community_settings')
            .set({'admin_message': messageToSave}, SetOptions(merge: true));
      } else {
        // Save specific message for this group
        await FirebaseFirestore.instance
            .collection('community_groups')
            .doc(_selectedFeedId)
            .set({'adminMessage': messageToSave}, SetOptions(merge: true));
      }
          
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pinned message updated for $_selectedFeedName')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating message: $e')),
        );
      }
    }
  }

  Future<void> _saveFeedScrollSettings({
    required bool enabled,
    required double speed,
  }) async {
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_settings')
          .set({
        'auto_scroll_enabled': enabled,
        'auto_scroll_speed': speed,
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving feed scroll settings: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Compact section header with view toggle
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Community & Communication',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.indigo,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<bool>(
                    valueListenable: TranslationService.instance.enabledNotifier,
                    builder: (context, enabled, _) {
                      return IconButton(
                        tooltip: enabled
                            ? 'Disable Translator'
                            : 'Enable Translator',
                        onPressed: () async {
                          await TranslationService.instance.setEnabled(!enabled);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                !enabled
                                    ? 'Translator enabled for moderation and live feed'
                                    : 'Translator disabled for moderation and live feed',
                              ),
                            ),
                          );
                        },
                        icon: Icon(
                          Icons.translate,
                          color: enabled ? Colors.indigo : Colors.grey,
                        ),
                      );
                    },
                  ),
                  // View toggle — always visible so you can switch freely
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('moderation_queue')
                        .where('status', isEqualTo: 'pending')
                        .snapshots(),
                    builder: (context, snap) {
                      final pendingCount = snap.hasData ? snap.data!.docs.length : 0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ViewToggleButton(
                            label: 'Moderation Queue',
                            icon: Icons.shield_outlined,
                            selected: _communityView == 'queue',
                            badge: pendingCount > 0 ? '$pendingCount' : null,
                            onTap: () => setState(() => _communityView = 'queue'),
                          ),
                          const SizedBox(width: 6),
                          _ViewToggleButton(
                            label: 'Live Feed',
                            icon: Icons.dynamic_feed_outlined,
                            selected: _communityView == 'feed',
                            onTap: () => setState(() => _communityView = 'feed'),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Content
        Expanded(
          child: _communityView == 'feed'
              ? _buildLiveFeed()
              : _buildModerationQueue(),
        ),
      ],
    );
  }

  Widget _buildModerationQueue() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('moderation_queue')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load moderation queue: ${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade200),
                const SizedBox(height: 16),
                const Text(
                  'All Caught Up!',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'No pending moderation reports.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final reports = List<QueryDocumentSnapshot>.from(snapshot.data!.docs);
        reports.sort((a, b) {
          final aTs = ((a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?);
          final bTs = ((b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?);
          final aMs = aTs?.millisecondsSinceEpoch ?? 0;
          final bMs = bTs?.millisecondsSinceEpoch ?? 0;
          return bMs.compareTo(aMs);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          itemBuilder: (context, index) {
            final reportDoc = reports[index];
            final report = reportDoc.data() as Map<String, dynamic>;
            final timestamp = (report['timestamp'] as Timestamp?)?.toDate();
            final reportedUserId = report['reportedUserId'] as String?;
            final reportContext = report['context'] as String? ?? 'Unknown';
            final reason = report['reason'] as String? ?? 'No reason given';
            final isReelReport = _isReelReport(report);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.red.shade50,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade100,
                  child: const Icon(Icons.warning, color: Colors.red),
                ),
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        report['userName'] ?? reportedUserId ?? 'Unknown User',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (timestamp != null)
                      Text(
                        DateFormat('MMM d, h:mm a').format(timestamp),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(reportContext, style: const TextStyle(fontSize: 10, color: Colors.indigo)),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    TranslatableText(report['content'] ?? ''),
                    if (isReelReport && (report['reelTitle'] as String?)?.isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Reel: ${report['reelTitle']}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Reason: $reason',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: TranslationService.instance.enabledNotifier,
                      builder: (context, enabled, _) {
                        if (!enabled || reason.trim().isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reason (translated): ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              Expanded(
                                child: TranslatableText(
                                  reason,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_search, size: 16),
                          label: const Text('Manage User'),
                          onPressed: () => _manageReportedUser(reportedUserId),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            side: const BorderSide(color: Colors.indigo),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.check, size: 16, color: Colors.green),
                          label: const Text('Resolve', style: TextStyle(color: Colors.green)),
                          onPressed: () => _resolveReport(reportDoc),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.close, size: 16, color: Colors.red),
                          label: const Text('Dismiss', style: TextStyle(color: Colors.red)),
                          onPressed: () => _dismissReport(reportDoc),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                        if (isReelReport)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('View Reel'),
                            onPressed: () => _openReelFromReport(report),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.indigo,
                              side: const BorderSide(color: Colors.indigo),
                            ),
                          ),
                        if (isReelReport)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete_forever, size: 16, color: Colors.red),
                            label: const Text('Remove Reel', style: TextStyle(color: Colors.red)),
                            onPressed: () => _removeFlaggedReel(reportDoc, report),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _manageReportedUser(String? userId) {
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user ID on this report')),
      );
      return;
    }
    if (widget.onUserSelected != null) {
      widget.onUserSelected!(userId);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reported User'),
          content: SelectableText('User ID: $userId'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  bool _isReelReport(Map<String, dynamic> report) {
    final context = (report['context'] as String? ?? '').toLowerCase();
    final source = (report['source'] as String? ?? '').toLowerCase();
    final type = (report['contentType'] as String? ?? '').toLowerCase();
    return type == 'reel' || context.contains('reel') || source.contains('reel');
  }

  void _openReelFromReport(Map<String, dynamic> report) {
    final rawUrl = (report['reelUrl'] as String? ?? '').trim();
    final reelType = (report['reelType'] as String? ?? '').toLowerCase().trim();
    final reelTitle = (report['reelTitle'] as String? ?? 'Reel Preview');

    if (rawUrl.isEmpty) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reel URL Not Available'),
          content: const Text(
            'This report was submitted before reel URL capture was enabled.\n\n'
            'To review the reel, go to App Content → Reels and find it by title.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Extract YouTube video ID if applicable
    String? videoId;
    if (reelType == 'youtube' ||
        rawUrl.contains('youtube.com') ||
        rawUrl.contains('youtu.be')) {
      final pattern = RegExp(
        r'(?:youtube\.com/(?:watch\?v=|embed/|shorts/)|youtu\.be/)([a-zA-Z0-9_-]{11})',
      );
      videoId = pattern.firstMatch(rawUrl)?.group(1);
    }

    // Use EXACT same logic as _buildReelPreview in app_content_tab
    Widget media;
    if (reelType == 'youtube') {
      media = SizedBox(
        height: 360,
        child: VideoGridItem(url: rawUrl, type: 'youtube', enablePreview: true),
      );
    } else if (reelType == 'video') {
      media = SizedBox(
        height: 360,
        child: HtmlVideoPreview(
          url: rawUrl,
          autoPlay: false,
          loop: false,
          muted: false,
          controls: true,
          objectFit: 'contain',
        ),
      );
    } else if (reelType == 'image') {
      media = SizedBox(
        height: 360,
        child: Image.network(rawUrl, fit: BoxFit.cover),
      );
    } else {
      media = SizedBox(
        height: 120,
        child: Center(
          child: Text(
            reelType == 'pdf' ? 'PDF Reel' : 'Link Reel',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SizedBox(
          width: 900,
          height: 550,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        reelTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(child: media),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeFlaggedReel(
    DocumentSnapshot reportDoc,
    Map<String, dynamic> report,
  ) async {
    final rawUrl = (report['reelUrl'] as String? ?? '').trim();
    if (rawUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No reel URL found for this report.')),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Reel?'),
        content: const Text(
          'This will remove the reel from App Content (home_screen reelItems) and any exact URL matches in Media Library.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final homeRef = FirebaseFirestore.instance.collection('app_config').doc('home_screen');
      final homeDoc = await homeRef.get();
      int removedFromHome = 0;

      if (homeDoc.exists) {
        final data = homeDoc.data() as Map<String, dynamic>? ?? {};
        final raw = (data['reelItems'] as List?) ?? const [];
        final items = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        final updated = items.where((item) {
          final url = (item['url'] as String? ?? '').trim();
          final keep = url != rawUrl;
          if (!keep) removedFromHome++;
          return keep;
        }).toList();

        await homeRef.set({'reelItems': updated}, SetOptions(merge: true));
      }

      final mediaQuery = await FirebaseFirestore.instance
          .collection('media_library')
          .where('url', isEqualTo: rawUrl)
          .get();

      for (final doc in mediaQuery.docs) {
        await doc.reference.delete();
      }

      await reportDoc.reference.update({
        ..._buildModerationAuditFields(
          status: 'resolved',
          action: 'content_removed_reel',
          note: 'Removed from Home Reels and Media Library by moderator.',
        ),
        'removedFromHomeReels': removedFromHome,
        'removedFromMediaLibrary': mediaQuery.docs.length,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reel removed. Home: $removedFromHome, Media Library: ${mediaQuery.docs.length}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove reel: $e')),
        );
      }
    }
  }

  Future<void> _resolveReport(DocumentSnapshot reportDoc) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Resolve Report — Action Taken'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'no_action'),
            child: const ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.grey),
              title: Text('No action needed'),
              subtitle: Text('Report reviewed, content is acceptable'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'warned'),
            child: const ListTile(
              leading: Icon(Icons.warning_amber, color: Colors.orange),
              title: Text('User warned'),
              subtitle: Text('Warning issued to the reported user'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'content_removed'),
            child: const ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text('Content removed'),
              subtitle: Text('The reported content has been deleted'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'user_suspended'),
            child: const ListTile(
              leading: Icon(Icons.block, color: Colors.red),
              title: Text('User suspended'),
              subtitle: Text('User account has been suspended'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const ListTile(
              leading: Icon(Icons.cancel_outlined, color: Colors.grey),
              title: Text('Cancel'),
            ),
          ),
        ],
      ),
    );

    if (action == null || !mounted) return;

    try {
      await reportDoc.reference.update(
        _buildModerationAuditFields(status: 'resolved', action: action),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report resolved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('_resolveReport error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not resolve report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _dismissReport(DocumentSnapshot reportDoc) async {
    try {
      await reportDoc.reference.update(
        _buildModerationAuditFields(status: 'dismissed', action: 'dismissed'),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report dismissed')),
        );
      }
    } catch (e) {
      debugPrint('_dismissReport error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not dismiss report: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildLiveFeed() {
    return Column(
      children: [
        // Feed Selector & Admin Message
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: Column(
            children: [
              // Feed Selector
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('community_groups').orderBy('sortOrder').snapshots(),
                builder: (context, snapshot) {
                  List<DropdownMenuItem<String>> items = [
                    const DropdownMenuItem(value: 'global', child: Text('Global Public Feed (Default)')),
                  ];
                  
                  if (snapshot.hasData) {
                    items.addAll(snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: doc.id, 
                        child: Text('Chat Group: ${data['name'] ?? 'Unknown'}')
                      );
                    }));
                  }

                  return Row(
                    children: [
                      const Text('Viewing:', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedFeedId,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: items,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _selectedFeedId = val;
                                // Simple update for display logic if needed 
                                _selectedFeedName = items.firstWhere((i) => i.value == val).child.toString();
                                // Try to extract clean name from widget if possible, or just query again. 
                                // Actually, for simpler code, let's just clear the controller so it reloads from stream
                                _messageController.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  );
                }
              ),
              const SizedBox(height: 10),
              
              // Admin Pinned Message (Available for Global AND Groups now)
              StreamBuilder<DocumentSnapshot>(
                // Dynamically switch stream based on selection
                stream: _selectedFeedId == 'global'
                    ? FirebaseFirestore.instance.collection('app_config').doc('community_settings').snapshots()
                    : FirebaseFirestore.instance.collection('community_groups').doc(_selectedFeedId).snapshots(),
                builder: (context, snapshot) {
                  String? currentMessage;
                  
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    if (_selectedFeedId == 'global') {
                      currentMessage = data['admin_message'] as String?;
                    } else {
                      currentMessage = data['adminMessage'] as String?;
                    }
                  }
                  
                  // Only load the message when feed changes or first load
                  // We rely on the Key of the StreamBuilder or manual management to reset controller
                  // Ideally, we reset controller when _selectedFeedId changes.
                  
                  return Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: 'Type pinned message or chat post...',
                            labelText: 'Admin Message',
                            border: const OutlineInputBorder(),
                            filled: true,
                            fillColor: Colors.white,
                            suffixIcon: _messageController.text.isNotEmpty 
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.grey),
                                    onPressed: () => _saveAdminMessage(''), // Clear message
                                    tooltip: 'Remove Message',
                                  )
                                : null,
                          ),
                          onSubmitted: _saveAdminMessage,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.push_pin),
                        label: const Text('Pin'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        onPressed: () => _saveAdminMessage(_messageController.text),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.forum),
                        label: const Text('Post'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        onPressed: () => _sendAdminChat(_messageController.text),
                      ),
                    ],
                  );
                }
              ),
              const SizedBox(height: 8),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('app_config')
                    .doc('community_settings')
                    .snapshots(),
                builder: (context, snapshot) {
                  final data =
                      snapshot.data?.data() as Map<String, dynamic>? ?? {};
                  final autoScrollEnabled =
                      (data['auto_scroll_enabled'] as bool?) ?? false;
                    final autoScrollSpeed =
                      ((data['auto_scroll_speed'] as num?)?.toDouble() ?? 28)
                        .clamp(8, 120)
                        .toDouble();

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.swap_vert, size: 18, color: Colors.indigo),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Auto-Scroll Controls (User App)',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            Switch(
                              value: autoScrollEnabled,
                              onChanged: (val) => _saveFeedScrollSettings(
                                enabled: val,
                                speed: autoScrollSpeed,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'Current speed: ${autoScrollSpeed.toStringAsFixed(0)} px/s',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                        Slider(
                          value: autoScrollSpeed,
                          min: 8,
                          max: 120,
                          divisions: 28,
                          label: autoScrollSpeed.toStringAsFixed(0),
                          onChanged: autoScrollEnabled
                              ? (val) => _saveFeedScrollSettings(
                                  enabled: autoScrollEnabled,
                                  speed: val,
                                )
                              : null,
                        ),
                        Text(
                          'Slider is always visible here for quick tuning while monitoring live comments.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        
        // Bottom "Chat as Admin" bar removed as per user request to have single input source.
        
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            key: ValueKey(_selectedFeedId), // Force rebuild when ID changes
            stream: _selectedFeedId == 'global'
              ? FirebaseFirestore.instance.collection('community_posts').orderBy('timestamp', descending: true).snapshots()
              : FirebaseFirestore.instance.collection('community_groups').doc(_selectedFeedId).collection('messages').orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(_selectedFeedId == 'global' ? 'No live feed activity' : 'No messages in this group yet'),
                    ],
                  ),
                );
              }

              final posts = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: posts.length,
                itemBuilder: (context, index) {
                  final postDoc = posts[index];
                  final post = postDoc.data() as Map<String, dynamic>;
                  final timestamp = (post['timestamp'] as Timestamp?)?.toDate();
                  
                  // Handle different field names between Global Feed and Group Chat
                  final content = post['content'] ?? post['text'] ?? '';
                  final userName = post['userName'] ?? post['sender'] ?? 'Anonymous';
                  final userPhoto = post['userPhoto']; // Only in global currently

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade100,
                        backgroundImage: userPhoto != null ? NetworkImage(userPhoto) : null,
                        child: userPhoto == null 
                            ? Text((userName.isNotEmpty ? userName[0].toUpperCase() : '?'))
                            : null,
                      ),
                      title: Row(
                        children: [
                          Text(userName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          if (timestamp != null)
                            Text(
                              DateFormat('MMM d, h:mm a').format(timestamp),
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                            ),
                            
                           // Badge to show origin if needed, but the dropdown context is enough
                        ],
                      ),
                      subtitle: TranslatableText(content),
                      trailing: PopupMenuButton(
                        onSelected: (value) async {
                          if (value == 'delete') {
                            await _deleteLiveFeedMessage(context, postDoc, post);
                          } else if (value == 'suspend') {
                            final userId = post['userId'];
                            if (userId != null) {
                              // Standardized suspension logic matching User Management
                              await FirebaseFirestore.instance.collection('users').doc(userId).update({
                                'status': 'suspended',
                                'suspensionExpiry': null, // Indefinite by default when triggered from chat
                                'lastAdminAction': 'Suspended from Live Feed',
                                'lastAdminActionDate': FieldValue.serverTimestamp(),
                              });

                              await FirebaseFirestore.instance.collection('moderation_queue').add({
                                'status': 'resolved',
                                'reason': 'Admin suspension from Live Feed',
                                'source': _selectedFeedId == 'global'
                                    ? 'Live Feed (Global)'
                                    : 'Live Feed (Group: $_selectedFeedName)',
                                'userId': userId,
                                'userName': post['userName'] ?? post['sender'] ?? 'Unknown User',
                                'content': post['content'] ?? post['text'] ?? '',
                                'timestamp': FieldValue.serverTimestamp(),
                                ..._buildModerationAuditFields(
                                  status: 'resolved',
                                  action: 'user_suspended',
                                  note: 'Suspended directly from Live Feed actions menu.',
                                ),
                              });
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('User suspended. Moved to "Resolved/Suspended" list.'),
                                    backgroundColor: Colors.orange,
                                  ),
                                );
                              }
                            } else {
                                if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Cannot suspend: User ID is missing')),
                                );
                              }
                            }
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: 'delete', child: Row(
                            children: [Icon(Icons.delete, size: 20, color: Colors.grey), SizedBox(width: 8), Text('Delete Message')],
                          )),
                          const PopupMenuItem(value: 'suspend', child: Row(
                            children: [Icon(Icons.block, size: 20, color: Colors.red), SizedBox(width: 8), Text('Suspend User')],
                          )),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _replyToMessage(BuildContext context, DocumentSnapshot msgDoc, String userName) {
    final replyController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reply to $userName'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: replyController,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Type your reply...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reply = replyController.text.trim();
              if (reply.isEmpty) return;

              Navigator.pop(ctx);
              try {
                // Add reply to the same collection
                await msgDoc.reference.parent.add({
                  'content': reply,
                  'sender': 'admin',
                  'timestamp': FieldValue.serverTimestamp(),
                  'read': false,
                  'replyTo': msgDoc.id,
                  'title': 'Re: ${(msgDoc.data() as Map<String, dynamic>)['title'] ?? 'Message'}',
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Reply sent!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error sending reply: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Send Reply'),
          ),
        ],
      ),
    );
  }
}

/// Small toggle pill button used in the Community tab header.
class _ViewToggleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final String? badge;
  final VoidCallback onTap;

  const _ViewToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.indigo : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.indigo : Colors.grey.shade300,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? Colors.white24 : Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: selected ? Colors.white : Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
