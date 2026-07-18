import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../widgets/video_widgets.dart';
import '../../services/lock_service.dart';
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
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _liveFeedScrollController = ScrollController();
  Timer? _featuredPublishTimer;
  Timer? _liveFeedAutoScrollTimer;
  StreamSubscription<DocumentSnapshot>? _communitySettingsSubscription;
  bool _featuredCarouselEnabled = false;
  bool _featuredAutoPublish = false;
  bool _featuredTickInFlight = false;
  bool _liveFeedAutoScrollEnabled = false;
  double _liveFeedAutoScrollSpeedPxPerSecond = 28;
  int _liveFeedDensityPreset = 1; // 0: Normal, 1: Compact, 2: Ultra
  String _lastKnownGlobalAdminManualMessage = '';
  
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

  String _currentAdminLockName() {
    final admin = FirebaseAuth.instance.currentUser;
    final email = admin?.email?.trim() ?? '';
    if (email.isNotEmpty) {
      return email.split('@').first;
    }
    final name = admin?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Admin';
  }

  bool _isMyModerationLock(String? lockedBy) {
    if (lockedBy == null || lockedBy.isEmpty) return false;
    return lockedBy == _currentAdminLockName();
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

  Future<void> _withModerationLock(
    DocumentSnapshot reportDoc,
    Future<void> Function() action,
  ) async {
    try {
      final lockedBy = await LockService().acquireLock(
        reportDoc.id,
        'moderation',
      );
      if (lockedBy != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This moderation item is currently being handled by "$lockedBy".',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      await action();
    } finally {
      LockService().releaseLock(reportDoc.id, 'moderation').catchError((_) {});
    }
  }

  Future<void> _sendModerationNotice({
    required String userId,
    required String message,
    required String action,
  }) async {
    if (userId.trim().isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('messages')
        .add({
      'sender': 'admin',
      'content': message,
      'type': 'moderation_update',
      'action': action,
      'read': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _setReportedUserStatus({
    required String userId,
    required String action,
  }) async {
    if (userId.trim().isEmpty) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    await FirebaseFirestore.instance.runTransaction((txn) async {
      final userDoc = await txn.get(userRef);
      final data = userDoc.data() as Map<String, dynamic>?;
      final currentStatus =
          (data?['status'] as String?)?.trim().toLowerCase() ?? 'active';

      if (action == 'user_suspended') {
        txn.set(userRef, {
          'status': 'suspended',
          'suspensionExpiry': null,
          'lastAdminAction': 'Suspended via moderation queue',
          'lastAdminActionDate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return;
      }

      if (currentStatus == 'under_review') {
        txn.set(userRef, {
          'status': 'active',
          'suspensionExpiry': null,
          'lastAdminAction': 'Reinstated after moderation review',
          'lastAdminActionDate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
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
    _watchCommunitySettings();
  }

  @override
  void dispose() {
    _featuredPublishTimer?.cancel();
    _liveFeedAutoScrollTimer?.cancel();
    _communitySettingsSubscription?.cancel();
    _messageFocusNode.dispose();
    _liveFeedScrollController.dispose();
    _messageController.dispose();
    _adminChatController.dispose();
    super.dispose();
  }

  void _syncLiveFeedAutoScroll() {
    _liveFeedAutoScrollTimer?.cancel();
    if (!_liveFeedAutoScrollEnabled) return;

    const interval = Duration(milliseconds: 180);
    _liveFeedAutoScrollTimer = Timer.periodic(interval, (_) {
      if (!mounted || !_liveFeedAutoScrollEnabled || !_liveFeedScrollController.hasClients) {
        return;
      }

      final pos = _liveFeedScrollController.position;
      final maxExtent = pos.maxScrollExtent;
      if (maxExtent <= 0) return;

      final step = _liveFeedAutoScrollSpeedPxPerSecond * (interval.inMilliseconds / 1000);
      final next = (pos.pixels + step) >= maxExtent ? 0.0 : (pos.pixels + step);

      _liveFeedScrollController.jumpTo(next);
    });
  }

  Future<void> _saveUserFlowScrollSettings({
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
    } catch (_) {
      // Keep this fire-and-forget to avoid interrupting live moderation.
    }
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
            .set({
              'admin_message_manual': messageToSave,
              'admin_message': messageToSave,
              'admin_message_display_type': 'pinned',
              'featuredLastSourceType': 'manual',
              'featuredLastPostId': null,
              'featuredLastKeyword': null,
            }, SetOptions(merge: true));
              _lastKnownGlobalAdminManualMessage = messageToSave;
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
    } on FirebaseException catch (e) {
      final detail = e.code.isNotEmpty ? '${e.code}: ${e.message ?? ''}' : e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating message: $detail')),
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

  void _watchCommunitySettings() {
    _communitySettingsSubscription?.cancel();
    _communitySettingsSubscription = FirebaseFirestore.instance
        .collection('app_config')
        .doc('community_settings')
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data() ?? const <String, dynamic>{};
      final enabled = (data['featuredCarouselEnabled'] as bool?) ?? false;
      final autoPublish = (data['featuredAutoPublish'] as bool?) ?? false;

      final changed =
          enabled != _featuredCarouselEnabled || autoPublish != _featuredAutoPublish;
      _featuredCarouselEnabled = enabled;
      _featuredAutoPublish = autoPublish;

      if (changed) {
        _syncFeaturedAutoPublishTimer();
      }
    });
  }

  void _syncFeaturedAutoPublishTimer() {
    final shouldRun = _featuredCarouselEnabled && _featuredAutoPublish;
    if (!shouldRun) {
      _featuredPublishTimer?.cancel();
      _featuredPublishTimer = null;
      return;
    }

    _featuredPublishTimer?.cancel();
    _featuredPublishTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _runFeaturedAutopublishTick(),
    );

    // Trigger a pass quickly when toggled on so admins can validate behavior.
    unawaited(_runFeaturedAutopublishTick());
  }

  List<Map<String, dynamic>> _parseFeaturedItems(dynamic raw) {
    final list = (raw as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
        .where((item) => (item['text'] as String?)?.trim().isNotEmpty == true)
        .toList();
  }

  List<String> _parseFeaturedKeywords(dynamic raw) {
    return ((raw as List?) ?? const [])
        .map((e) => e.toString().trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
  }

  Future<void> _updateCommunitySettings(Map<String, dynamic> patch) async {
    await FirebaseFirestore.instance
        .collection('app_config')
        .doc('community_settings')
        .set(patch, SetOptions(merge: true));
  }

  String _buildFeaturedDisplayText(Map<String, dynamic> item) {
    final rawText = (item['text'] as String? ?? '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (rawText.isEmpty) return '';

    final sourceType = (item['sourceType'] as String? ?? 'manual').toLowerCase();
    final isCommentSource = sourceType.contains('comment');

    final maxLen = isCommentSource ? 180 : 260;
    var display = rawText.length > maxLen ? '${rawText.substring(0, maxLen)}...' : rawText;

    if (isCommentSource) {
      DateTime? ts;
      final tsRaw = item['sourceTimestamp'];
      if (tsRaw is Timestamp) {
        ts = tsRaw.toDate();
      } else if (tsRaw is String) {
        ts = DateTime.tryParse(tsRaw);
      }
      if (ts != null) {
        // Keep metadata compact to avoid inflating the pinned panel height.
        display = '$display  [Feed ${DateFormat('MMM d, h:mm a').format(ts)}]';
      }
    }

    return display;
  }

  Future<void> _runFeaturedAutopublishTick() async {
    if (_featuredTickInFlight) return;
    _featuredTickInFlight = true;

    try {
      final settingsRef = FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_settings');
      final settingsSnap = await settingsRef.get();
      final settings = settingsSnap.data() ?? const <String, dynamic>{};

      final enabled = (settings['featuredCarouselEnabled'] as bool?) ?? false;
      final autoPublish = (settings['featuredAutoPublish'] as bool?) ?? false;
      if (!enabled || !autoPublish) return;

      final intervalSeconds =
          ((settings['featuredIntervalSeconds'] as num?)?.toInt() ?? 60)
              .clamp(30, 172800);
      final lastPublishedAt = settings['featuredLastPublishedAt'] as Timestamp?;
      if (lastPublishedAt != null) {
        final elapsed = DateTime.now().difference(lastPublishedAt.toDate()).inSeconds;
        if (elapsed < intervalSeconds) return;
      }

      final randomize = (settings['featuredRandomize'] as bool?) ?? false;
      final sourceMode =
          (settings['featuredSourceMode'] as String? ?? 'mixed').toLowerCase();
      final currentIndex = (settings['featuredCurrentIndex'] as num?)?.toInt() ?? 0;
      final adminIndex = (settings['featuredAdminIndex'] as num?)?.toInt() ?? currentIndex;
      final userIndex = (settings['featuredUserIndex'] as num?)?.toInt() ?? 0;
      final mixedUserStreak =
          (settings['featuredMixedUserStreak'] as num?)?.toInt() ?? 0;
      final mixedAdminEveryUsers =
          ((settings['featuredMixedAdminEveryUsers'] as num?)?.toInt() ?? 5)
              .clamp(1, 100);
      final keywords = _parseFeaturedKeywords(settings['featuredKeywords']);
        final includeManual = sourceMode != 'keywords_only';
        final includeKeywords = sourceMode != 'admin_only';
        final manualMessage =
            (settings['admin_message_manual'] as String? ?? '').trim();
      final manualItems = includeManual
          ? _parseFeaturedItems(settings['featuredItems'])
              .where((item) => (item['active'] as bool?) ?? true)
              .toList()
          : <Map<String, dynamic>>[];

      final adminCandidates = <Map<String, dynamic>>[
        if (includeManual && manualMessage.isNotEmpty)
          {
            'id': 'manual_admin_message',
            'text': manualMessage,
            'sourceType': 'manual_admin_message',
            'active': true,
          },
        ...manualItems,
      ];

      final userCandidates = <Map<String, dynamic>>[];

      if (includeKeywords && keywords.isNotEmpty) {
        final postSnap = await FirebaseFirestore.instance
            .collection('community_posts')
            .orderBy('timestamp', descending: true)
            .limit(120)
            .get();

        for (final doc in postSnap.docs) {
          final data = doc.data();
          final content = (data['content'] as String? ?? '').trim();
          if (content.isEmpty) continue;

          final lower = content.toLowerCase();
          final matchedKeyword = keywords.firstWhere(
            lower.contains,
            orElse: () => '',
          );
          if (matchedKeyword.isEmpty) continue;

          final ts = data['timestamp'];
          userCandidates.add({
            'id': 'kw_${doc.id}',
            'text': content,
            'sourceType': 'keyword_comment',
            'sourceKeyword': matchedKeyword,
            'sourcePostId': doc.id,
            if (ts != null) 'sourceTimestamp': ts,
            'active': true,
          });
        }
      }

      List<Map<String, dynamic>> selectedPool;
      var selectedPoolType = 'admin';
      var nextAdminIndex = adminIndex;
      var nextUserIndex = userIndex;
      var nextMixedUserStreak = mixedUserStreak;

      if (sourceMode == 'admin_only') {
        selectedPool = adminCandidates;
        selectedPoolType = 'admin';
      } else if (sourceMode == 'keywords_only') {
        selectedPool = userCandidates;
        selectedPoolType = 'user';
      } else {
        if (adminCandidates.isEmpty && userCandidates.isEmpty) return;

        final shouldUseAdmin = userCandidates.isEmpty ||
            (adminCandidates.isNotEmpty && mixedUserStreak >= mixedAdminEveryUsers);

        if (shouldUseAdmin && adminCandidates.isNotEmpty) {
          selectedPool = adminCandidates;
          selectedPoolType = 'admin';
        } else if (userCandidates.isNotEmpty) {
          selectedPool = userCandidates;
          selectedPoolType = 'user';
        } else {
          selectedPool = adminCandidates;
          selectedPoolType = 'admin';
        }
      }

      if (selectedPool.isEmpty) return;

      final selectedIndex = randomize
          ? Random().nextInt(selectedPool.length)
          : ((selectedPoolType == 'admin' ? adminIndex : userIndex) % selectedPool.length);

      if (!randomize) {
        if (selectedPoolType == 'admin') {
          nextAdminIndex = (selectedIndex + 1) % selectedPool.length;
        } else {
          nextUserIndex = (selectedIndex + 1) % selectedPool.length;
        }
      }

      if (sourceMode == 'mixed') {
        nextMixedUserStreak = selectedPoolType == 'admin'
            ? 0
            : (mixedUserStreak + 1).clamp(0, 100000);
      } else {
        nextMixedUserStreak = 0;
      }

      final selected = selectedPool[selectedIndex];
      final publishText = _buildFeaturedDisplayText(selected);
      if (publishText.isEmpty) return;

      final selectedSourceType =
          (selected['sourceType'] as String? ?? 'manual').toLowerCase();
      final displayType = selectedSourceType.contains('comment')
          ? 'featured'
          : 'pinned';

      await settingsRef.set({
        'admin_message': publishText,
        'admin_message_display_type': displayType,
        'featuredCurrentIndex': selectedPoolType == 'admin' ? nextAdminIndex : nextUserIndex,
        'featuredAdminIndex': nextAdminIndex,
        'featuredUserIndex': nextUserIndex,
        'featuredMixedUserStreak': nextMixedUserStreak,
        'featuredLastPublishedAt': FieldValue.serverTimestamp(),
        'featuredLastSourceType': selected['sourceType'] ?? 'manual',
        'featuredLastKeyword': selected['sourceKeyword'],
        'featuredLastPostId': selected['sourcePostId'],
        'featuredLastPublishedPreview': publishText,
      }, SetOptions(merge: true));
    } catch (_) {
      // Keep timer robust; this loop should not interrupt admin use on transient failures.
    } finally {
      _featuredTickInFlight = false;
    }
  }

  Future<void> _addFeaturedManualItem() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Featured Input'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'Type announcement, shout out, or featured prompt...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );

    final text = controller.text.trim();
    if (saved != true || text.isEmpty) return;

    final settingsRef = FirebaseFirestore.instance
        .collection('app_config')
        .doc('community_settings');
    final snap = await settingsRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final items = _parseFeaturedItems(data['featuredItems']);
    items.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'text': text,
      'sourceType': 'manual',
      'active': true,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await _updateCommunitySettings({'featuredItems': items});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to featured carousel inputs.')),
    );
  }

  Future<void> _editFeaturedKeywords(List<String> currentKeywords) async {
    final controller = TextEditingController(text: currentKeywords.join(', '));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keyword Match Inputs'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'abundance, love, health',
            helperText: 'Carousel will include comments containing these words.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (saved != true) return;
    final keywords = controller.text
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    await _updateCommunitySettings({'featuredKeywords': keywords});
  }

  Future<void> _manageFeaturedItems(List<Map<String, dynamic>> initialItems) async {
    final mutable = initialItems.map((e) => Map<String, dynamic>.from(e)).toList();

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Manage Carousel Inputs'),
              content: SizedBox(
                width: 700,
                child: mutable.isEmpty
                    ? const Text('No featured inputs yet.')
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: mutable.length,
                        itemBuilder: (context, index) {
                          final item = mutable[index];
                          final text = (item['text'] as String? ?? '').trim();
                          final active = (item['active'] as bool?) ?? true;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              dense: true,
                              title: Text(
                                text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                ((item['sourceType'] as String?) ?? 'manual')
                                    .replaceAll('_', ' '),
                              ),
                              leading: Switch(
                                value: active,
                                onChanged: (val) {
                                  setDialogState(() {
                                    item['active'] = val;
                                  });
                                },
                              ),
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_upward, size: 18),
                                    onPressed: index == 0
                                        ? null
                                        : () {
                                            setDialogState(() {
                                              final temp = mutable[index - 1];
                                              mutable[index - 1] = mutable[index];
                                              mutable[index] = temp;
                                            });
                                          },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_downward, size: 18),
                                    onPressed: index == mutable.length - 1
                                        ? null
                                        : () {
                                            setDialogState(() {
                                              final temp = mutable[index + 1];
                                              mutable[index + 1] = mutable[index];
                                              mutable[index] = temp;
                                            });
                                          },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18),
                                    onPressed: () async {
                                      final editor = TextEditingController(text: text);
                                      final edited = await showDialog<bool>(
                                        context: context,
                                        builder: (eCtx) => AlertDialog(
                                          title: const Text('Edit Input'),
                                          content: TextField(
                                            controller: editor,
                                            maxLines: 4,
                                            decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(eCtx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Navigator.pop(eCtx, true),
                                              child: const Text('Save'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (edited == true) {
                                        final next = editor.text.trim();
                                        if (next.isNotEmpty) {
                                          setDialogState(() {
                                            item['text'] = next;
                                          });
                                        }
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        mutable.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Changes')),
              ],
            );
          },
        );
      },
    );

    if (save == true) {
      await _updateCommunitySettings({'featuredItems': mutable});
    }
  }

  Future<void> _featureCommentFromLiveFeed(Map<String, dynamic> post) async {
    final content = (post['content'] ?? post['text'] ?? '').toString().trim();
    if (content.isEmpty) return;

    final ts = post['timestamp'];
    final settingsRef = FirebaseFirestore.instance
        .collection('app_config')
        .doc('community_settings');
    final snap = await settingsRef.get();
    final data = snap.data() ?? const <String, dynamic>{};
    final items = _parseFeaturedItems(data['featuredItems']);
    items.add({
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'text': content,
      'sourceType': 'comment_pick',
      'active': true,
      if (post['userId'] != null) 'sourceUserId': post['userId'],
      if (post['userName'] != null) 'sourceUserName': post['userName'],
      if (post['sender'] != null) 'sourceUserName': post['sender'],
      if (ts != null) 'sourceTimestamp': ts,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await _updateCommunitySettings({'featuredItems': items});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Comment added to featured carousel inputs.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Compact section header with view toggle
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'Community & Communication',
                      style: TextStyle(
                        fontSize: 12,
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

            return StreamBuilder<String?>(
              stream: LockService().watchLock(reportDoc.id, 'moderation'),
              builder: (context, lockSnapshot) {
                final lockedBy = lockSnapshot.data;
                final lockedByOther =
                    lockedBy != null && !_isMyModerationLock(lockedBy);

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
                    if (lockedBy != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.lock, size: 14, color: Colors.deepOrange),
                            const SizedBox(width: 6),
                            Text(
                              lockedByOther
                                  ? 'Locked by $lockedBy'
                                  : 'You are handling this item',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.deepOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_search, size: 16),
                          label: const Text('Manage User'),
                          onPressed: lockedByOther
                              ? null
                              : () => _withModerationLock(
                                    reportDoc,
                                    () async => _manageReportedUser(reportedUserId),
                                  ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            side: const BorderSide(color: Colors.indigo),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.check, size: 16, color: Colors.green),
                          label: const Text('Resolve', style: TextStyle(color: Colors.green)),
                          onPressed: lockedByOther
                              ? null
                              : () => _withModerationLock(
                                    reportDoc,
                                    () => _resolveReport(reportDoc, report),
                                  ),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.close, size: 16, color: Colors.red),
                          label: const Text('Dismiss', style: TextStyle(color: Colors.red)),
                          onPressed: lockedByOther
                              ? null
                              : () => _withModerationLock(
                                    reportDoc,
                                    () => _dismissReport(reportDoc, report),
                                  ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                        if (isReelReport)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('View Reel'),
                            onPressed: lockedByOther
                                ? null
                                : () => _openReelFromReport(report),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.indigo,
                              side: const BorderSide(color: Colors.indigo),
                            ),
                          ),
                        if (isReelReport)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.delete_forever, size: 16, color: Colors.red),
                            label: const Text('Remove Reel', style: TextStyle(color: Colors.red)),
                            onPressed: lockedByOther
                                ? null
                                : () => _withModerationLock(
                                      reportDoc,
                                      () => _removeFlaggedReel(reportDoc, report),
                                    ),
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

  Future<void> _resolveReport(
    DocumentSnapshot reportDoc,
    Map<String, dynamic> report,
  ) async {
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
      final reportedUserId = (report['reportedUserId'] as String?)?.trim() ?? '';

      await _setReportedUserStatus(userId: reportedUserId, action: action);

      await reportDoc.reference.update({
        ..._buildModerationAuditFields(status: 'resolved', action: action),
        'claimedBy': _currentAdminLockName(),
      });

      if (reportedUserId.isNotEmpty) {
        final message = action == 'user_suspended'
            ? 'Your account has been suspended after moderation review. Please contact support in My Harmony.'
            : 'A moderation report involving your account has been reviewed and resolved.';
        await _sendModerationNotice(
          userId: reportedUserId,
          message: message,
          action: action,
        );
      }

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

  Future<void> _dismissReport(
    DocumentSnapshot reportDoc,
    Map<String, dynamic> report,
  ) async {
    try {
      final reportedUserId = (report['reportedUserId'] as String?)?.trim() ?? '';

      await _setReportedUserStatus(userId: reportedUserId, action: 'dismissed');

      await reportDoc.reference.update({
        ..._buildModerationAuditFields(status: 'dismissed', action: 'dismissed'),
        'claimedBy': _currentAdminLockName(),
      });

      if (reportedUserId.isNotEmpty) {
        await _sendModerationNotice(
          userId: reportedUserId,
          message:
              'A moderation report involving your account has been dismissed and no further action was required.',
          action: 'dismissed',
        );
      }

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

              // Compact controls for admin reading flow + user-facing flow speed.
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('app_config')
                    .doc('community_settings')
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                  final userFlowEnabled = (data['auto_scroll_enabled'] as bool?) ?? false;
                  final userFlowSpeed =
                      ((data['auto_scroll_speed'] as num?)?.toDouble() ?? 28).clamp(8, 120).toDouble();

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.swap_vert, size: 14, color: Colors.indigo),
                            const SizedBox(width: 6),
                            const Text('Admin read', style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 6),
                            Switch(
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              value: _liveFeedAutoScrollEnabled,
                              onChanged: (val) {
                                setState(() {
                                  _liveFeedAutoScrollEnabled = val;
                                });
                                _syncLiveFeedAutoScroll();
                              },
                            ),
                            if (_liveFeedAutoScrollEnabled) ...[
                              const SizedBox(width: 4),
                              DropdownButton<double>(
                                value: _liveFeedAutoScrollSpeedPxPerSecond,
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(value: 18, child: Text('Slow', style: TextStyle(fontSize: 11))),
                                  DropdownMenuItem(value: 28, child: Text('Medium', style: TextStyle(fontSize: 11))),
                                  DropdownMenuItem(value: 40, child: Text('Fast', style: TextStyle(fontSize: 11))),
                                ],
                                onChanged: (val) {
                                  if (val == null) return;
                                  setState(() {
                                    _liveFeedAutoScrollSpeedPxPerSecond = val;
                                  });
                                  _syncLiveFeedAutoScroll();
                                },
                              ),
                            ],
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.public, size: 14, color: Colors.teal),
                            const SizedBox(width: 6),
                            const Text('User flow', style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 6),
                            Switch(
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              value: userFlowEnabled,
                              onChanged: (val) => _saveUserFlowScrollSettings(
                                enabled: val,
                                speed: userFlowSpeed,
                              ),
                            ),
                            if (userFlowEnabled) ...[
                              const SizedBox(width: 4),
                              DropdownButton<double>(
                                value: userFlowSpeed,
                                isDense: true,
                                items: const [
                                  DropdownMenuItem(value: 16, child: Text('Slow', style: TextStyle(fontSize: 11))),
                                  DropdownMenuItem(value: 28, child: Text('Medium', style: TextStyle(fontSize: 11))),
                                  DropdownMenuItem(value: 45, child: Text('Fast', style: TextStyle(fontSize: 11))),
                                ],
                                onChanged: (val) {
                                  if (val == null) return;
                                  _saveUserFlowScrollSettings(
                                    enabled: userFlowEnabled,
                                    speed: val,
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Density', style: TextStyle(fontSize: 11)),
                            const SizedBox(width: 6),
                            DropdownButton<int>(
                              value: _liveFeedDensityPreset,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('Normal', style: TextStyle(fontSize: 11))),
                                DropdownMenuItem(value: 1, child: Text('Compact', style: TextStyle(fontSize: 11))),
                                DropdownMenuItem(value: 2, child: Text('Ultra', style: TextStyle(fontSize: 11))),
                              ],
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _liveFeedDensityPreset = val;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
              
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
                      final rawManual = data['admin_message_manual'];
                      if (rawManual != null) {
                        currentMessage = rawManual.toString();
                        _lastKnownGlobalAdminManualMessage = currentMessage;
                      } else {
                        final displayType =
                            (data['admin_message_display_type'] as String? ?? 'pinned')
                                .toLowerCase();
                        final lastSource =
                            (data['featuredLastSourceType'] as String? ?? 'manual')
                                .toLowerCase();
                        final rawBanner = data['admin_message'];
                        final canRecover = rawBanner != null &&
                            displayType == 'pinned' &&
                            (lastSource.contains('manual'));
                        if (canRecover) {
                          currentMessage = rawBanner.toString();
                          _lastKnownGlobalAdminManualMessage = currentMessage;
                          unawaited(
                            FirebaseFirestore.instance
                                .collection('app_config')
                                .doc('community_settings')
                                .set(
                              {'admin_message_manual': currentMessage},
                              SetOptions(merge: true),
                            ),
                          );
                        } else {
                          currentMessage = _lastKnownGlobalAdminManualMessage;
                        }
                      }
                    } else {
                      final raw = data['adminMessage'];
                      currentMessage = raw == null ? null : raw.toString();
                    }
                  }

                  final incomingMessage = currentMessage ?? '';
                  if (!_messageFocusNode.hasFocus &&
                      _messageController.text != incomingMessage) {
                    _messageController.value = TextEditingValue(
                      text: incomingMessage,
                      selection: TextSelection.collapsed(
                        offset: incomingMessage.length,
                      ),
                    );
                  }
                  
                  // Only load the message when feed changes or first load
                  // We rely on the Key of the StreamBuilder or manual management to reset controller
                  // Ideally, we reset controller when _selectedFeedId changes.
                  
                  return Row(
                    children: [
                      Expanded(
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _messageController,
                          builder: (context, value, _) => TextField(
                            controller: _messageController,
                            focusNode: _messageFocusNode,
                            decoration: InputDecoration(
                              hintText: 'Type pinned message or chat post...',
                              labelText: 'Admin Message',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              suffixIcon: value.text.trim().isNotEmpty
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
                  final featuredEnabled =
                      (data['featuredCarouselEnabled'] as bool?) ?? false;
                  final featuredAutoPublish =
                      (data['featuredAutoPublish'] as bool?) ?? false;
                  final featuredRandomize =
                      (data['featuredRandomize'] as bool?) ?? false;
                  final featuredSourceMode =
                      (data['featuredSourceMode'] as String? ?? 'mixed').toLowerCase();
                    final featuredMixedAdminEveryUsers =
                      ((data['featuredMixedAdminEveryUsers'] as num?)?.toInt() ?? 5)
                        .clamp(1, 100);
                  final featuredInterval =
                      ((data['featuredIntervalSeconds'] as num?)?.toInt() ?? 60)
                          .clamp(30, 172800);
                  final featuredKeywords = _parseFeaturedKeywords(data['featuredKeywords']);
                  final featuredItems = _parseFeaturedItems(data['featuredItems']);
                  final activeFeaturedCount = featuredItems
                      .where((item) => (item['active'] as bool?) ?? true)
                      .length;
                  final lastPreview =
                      (data['featuredLastPublishedPreview'] as String? ?? '').trim();
                    final compactLastPreview =
                      lastPreview.replaceAll(RegExp(r'\s+'), ' ').trim();

                  const intervalChoices = <int>[
                    30,
                    60,
                    120,
                    300,
                    600,
                    1800,
                    3600,
                    21600,
                    43200,
                    86400,
                    172800,
                  ];

                  String formatInterval(int seconds) {
                    if (seconds < 60) return '${seconds}s';
                    if (seconds < 3600) return '${seconds ~/ 60}m';
                    if (seconds < 86400) return '${seconds ~/ 3600}h';
                    return '${seconds ~/ 86400}d';
                  }

                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
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
                                const Icon(Icons.view_carousel, size: 16, color: Colors.indigo),
                                const SizedBox(width: 6),
                                const Expanded(
                                  child: Text(
                                    'Pinned Carousel (Admin Only)',
                                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                                  ),
                                ),
                                Switch(
                                  value: featuredEnabled,
                                  onChanged: (val) => _updateCommunitySettings({
                                    'featuredCarouselEnabled': val,
                                  }),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Source', style: TextStyle(fontSize: 12)),
                                    const SizedBox(width: 8),
                                    DropdownButton<String>(
                                      value: featuredSourceMode,
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'mixed',
                                          child: Text('Mixed'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'admin_only',
                                          child: Text('Admin Only'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'keywords_only',
                                          child: Text('Keywords Only'),
                                        ),
                                      ],
                                      onChanged: (val) {
                                        if (val == null) return;
                                        _updateCommunitySettings({
                                          'featuredSourceMode': val,
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                if (featuredSourceMode == 'mixed')
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Admin ratio', style: TextStyle(fontSize: 12)),
                                      const SizedBox(width: 8),
                                      DropdownButton<int>(
                                        value: featuredMixedAdminEveryUsers,
                                        items: const [
                                          DropdownMenuItem(value: 1, child: Text('1 : 1 users')),
                                          DropdownMenuItem(value: 3, child: Text('1 : 3 users')),
                                          DropdownMenuItem(value: 5, child: Text('1 : 5 users')),
                                          DropdownMenuItem(value: 10, child: Text('1 : 10 users')),
                                          DropdownMenuItem(value: 20, child: Text('1 : 20 users')),
                                          DropdownMenuItem(value: 30, child: Text('1 : 30 users')),
                                        ],
                                        onChanged: featuredEnabled
                                            ? (val) {
                                                if (val == null) return;
                                                _updateCommunitySettings({
                                                  'featuredMixedAdminEveryUsers': val,
                                                  'featuredMixedUserStreak': 0,
                                                });
                                              }
                                            : null,
                                      ),
                                    ],
                                  ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Auto publish', style: TextStyle(fontSize: 12)),
                                    Switch(
                                      value: featuredAutoPublish,
                                      onChanged: featuredEnabled
                                          ? (val) => _updateCommunitySettings({
                                                'featuredAutoPublish': val,
                                              })
                                          : null,
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Randomize', style: TextStyle(fontSize: 12)),
                                    Switch(
                                      value: featuredRandomize,
                                      onChanged: featuredEnabled
                                          ? (val) => _updateCommunitySettings({
                                                'featuredRandomize': val,
                                              })
                                          : null,
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('Interval', style: TextStyle(fontSize: 12)),
                                    const SizedBox(width: 8),
                                    DropdownButton<int>(
                                      value: featuredInterval,
                                      items: intervalChoices
                                          .map(
                                            (seconds) => DropdownMenuItem<int>(
                                              value: seconds,
                                              child: Text(formatInterval(seconds)),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: featuredEnabled
                                          ? (val) {
                                              if (val == null) return;
                                              _updateCommunitySettings({
                                                'featuredIntervalSeconds': val,
                                              });
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            if (featuredEnabled) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _addFeaturedManualItem,
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add input'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _manageFeaturedItems(featuredItems),
                                    icon: const Icon(Icons.edit_note, size: 16),
                                    label: Text('Manage (${featuredItems.length})'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _editFeaturedKeywords(featuredKeywords),
                                    icon: const Icon(Icons.key, size: 16),
                                    label: const Text('Keywords'),
                                  ),
                                  if (featuredAutoPublish)
                                    OutlinedButton.icon(
                                      onPressed: _runFeaturedAutopublishTick,
                                      icon: const Icon(Icons.bolt, size: 16),
                                      label: const Text('Publish now'),
                                    ),
                                  ...featuredKeywords.map(
                                    (k) => Chip(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(horizontal: 6),
                                      label: Text(k, style: const TextStyle(fontSize: 11)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Active inputs: $activeFeaturedCount • Mode: ${featuredSourceMode.replaceAll('_', ' ')}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              ),
                              if (compactLastPreview.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                ClipRect(
                                  child: Text(
                                    'Latest publish preview: $compactLastPreview',
                                    maxLines: 2,
                                    softWrap: true,
                                    overflow: TextOverflow.ellipsis,
                                    strutStyle: const StrutStyle(
                                      forceStrutHeight: true,
                                      height: 1.0,
                                    ),
                                    textHeightBehavior: const TextHeightBehavior(
                                      applyHeightToFirstAscent: false,
                                      applyHeightToLastDescent: false,
                                    ),
                                    style: TextStyle(
                                      fontSize: 10,
                                      height: 1.0,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
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

              return LayoutBuilder(
                builder: (context, constraints) {
                  final isNormal = _liveFeedDensityPreset == 0;
                  final isCompact = _liveFeedDensityPreset == 1;
                  final isUltra = _liveFeedDensityPreset == 2;

                  final crossAxisCount = isUltra
                    ? (constraints.maxWidth >= 1500 ? 3 : (constraints.maxWidth >= 980 ? 2 : 1))
                    : (isCompact
                      ? (constraints.maxWidth >= 1080 ? 2 : 1)
                      : (constraints.maxWidth >= 1280 ? 2 : 1));
                  final mainExtent = isUltra ? 82.0 : (isCompact ? 100.0 : 118.0);
                  final userFontSize = isUltra ? 11.0 : (isCompact ? 12.0 : 12.5);
                  final timeFontSize = isUltra ? 9.0 : (isCompact ? 10.0 : 10.5);
                  final contentFontSize = isUltra ? 10.0 : (isCompact ? 11.0 : 11.5);
                  final contentMaxLines = 1;
                  return GridView.builder(
                    controller: _liveFeedScrollController,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 8,
                      mainAxisExtent: mainExtent,
                    ),
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
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      dense: true,
                      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.indigo.shade100,
                        backgroundImage: userPhoto != null ? NetworkImage(userPhoto) : null,
                        child: userPhoto == null 
                            ? Text((userName.isNotEmpty ? userName[0].toUpperCase() : '?'))
                            : null,
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              userName,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: userFontSize),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (timestamp != null)
                            Text(
                              DateFormat('MMM d, h:mm a').format(timestamp),
                              style: TextStyle(fontSize: timeFontSize, color: Colors.grey.shade500),
                            ),
                        ],
                      ),
                      subtitle: TranslatableText(
                        content,
                        style: TextStyle(
                          fontSize: contentFontSize,
                          height: 1.2,
                          color: Colors.grey.shade800,
                        ),
                        maxLines: contentMaxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: PopupMenuButton(
                        onSelected: (value) async {
                          if (value == 'delete') {
                            await _deleteLiveFeedMessage(context, postDoc, post);
                          } else if (value == 'feature') {
                            await _featureCommentFromLiveFeed(post);
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
                          const PopupMenuItem(value: 'feature', child: Row(
                            children: [Icon(Icons.push_pin, size: 20, color: Colors.indigo), SizedBox(width: 8), Text('Feature in Carousel')],
                          )),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
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
            Icon(icon, size: 13, color: selected ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
