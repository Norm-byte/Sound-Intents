import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Shared with CommunitySupportTab: both dropdowns read/write the same
// app_config/community_settings.postRetentionDays field.
const List<int> kPostRetentionDayOptions = [7, 14, 21, 30, 45, 60, 90];

class CommunityTab extends StatefulWidget {
  final Function(String userId)? onUserSelected;
  const CommunityTab({super.key, this.onUserSelected});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _messageController = TextEditingController(); // For Pinned Message
  final TextEditingController _adminChatController = TextEditingController(); // For Admin Chat
  final TextEditingController _featuredKeywordsController = TextEditingController();
  final TextEditingController _caseSearchController = TextEditingController();
  String _resolvedDecisionFilter = 'all';
  String? _resolvedHistoryUserId;
  String? _resolvedHistoryUserName;
  bool _isMessageLoaded = false;
  bool _featuredControlsHydrated = false;
  String _lastFeaturedKeywordsText = '';
  
  // Feed Selection State
  String _selectedFeedId = 'global'; // 'global' or groupId
  String _selectedFeedName = 'Global Public Feed';

  // Simple profanity list for moderation queue
  final List<String> _badWords = ['badword', 'abuse', 'hate', 'violence', 'kill', 'damn', 'hell'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _caseSearchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _adminChatController.dispose();
    _featuredKeywordsController.dispose();
    _caseSearchController.dispose();
    super.dispose();
  }

  Future<void> _saveCommunitySettings(Map<String, dynamic> patch) async {
    try {
      await FirebaseFirestore.instance
          .collection('app_config')
          .doc('community_settings')
          .set(patch, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Community settings updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $e')),
      );
    }
  }

  bool _readBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return true;
      }
      if (normalized == 'false' || normalized == '0' || normalized == 'no') {
        return false;
      }
    }
    return fallback;
  }

  Widget _buildLiveFeedControlsCard(Map<String, dynamic> data) {
    final autoScrollEnabled =
        _readBool(data['auto_scroll_enabled'], fallback: false);
    final autoScrollSpeed =
        ((data['auto_scroll_speed'] as num?)?.toDouble() ?? 28)
            .clamp(8, 120)
            .toDouble();
    final featuredSourceMode =
        (data['featuredSourceMode'] as String?)?.trim().isNotEmpty == true
            ? (data['featuredSourceMode'] as String).trim()
            : 'mixed';
    final featuredMixedAdminEveryUsers =
        ((data['featuredMixedAdminEveryUsers'] as num?)?.toInt() ?? 5)
            .clamp(1, 20);
    final showPinnedAdminMessage =
        _readBool(data['showPinnedAdminMessage'], fallback: true);
    final featuredKeywords = (data['featuredKeywords'] as List<dynamic>? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final featuredKeywordsText = featuredKeywords.join(', ');
    // Shared with the Community Support tab: same field, same value, so the
    // two dropdowns can never drift apart.
    final postRetentionDays =
        ((data['postRetentionDays'] as num?)?.toInt() ?? 30).clamp(1, 365);
    final isPostRetentionEnabled = data['isPostRetentionEnabled'] == true;

    if (!_featuredControlsHydrated || _lastFeaturedKeywordsText != featuredKeywordsText) {
      _featuredKeywordsController.text = featuredKeywordsText;
      _lastFeaturedKeywordsText = featuredKeywordsText;
      _featuredControlsHydrated = true;
    }

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
          const Text(
            'Auto-Scroller + Featured/Pinned',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18, color: Colors.deepOrange),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Post Retention (Live Feed + Support)',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              DropdownButton<int>(
                value: kPostRetentionDayOptions.contains(postRetentionDays)
                    ? postRetentionDays
                    : kPostRetentionDayOptions.first,
                items: kPostRetentionDayOptions
                    .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  _saveCommunitySettings({'postRetentionDays': value});
                },
              ),
            ],
          ),
          Text(
            'Posts older than this are deleted automatically (paused for anything under active moderation). Same value applies in the Community Support tab.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          Row(
            children: [
              Switch(
                value: isPostRetentionEnabled,
                onChanged: (value) =>
                    _saveCommunitySettings({'isPostRetentionEnabled': value}),
              ),
              Expanded(
                child: Text(
                  isPostRetentionEnabled
                      ? 'Active — automatic deletion is running.'
                      : 'Off — no posts are deleted automatically.',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isPostRetentionEnabled
                        ? Colors.green.shade700
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 18),
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
            'Slider stays visible for quick tuning while monitoring comments.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          const Divider(height: 18),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Pinned Message Visible in User App',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Switch(
                value: showPinnedAdminMessage,
                onChanged: (val) => _saveCommunitySettings({
                  'showPinnedAdminMessage': val,
                  if (!val) 'admin_message': '',
                }),
              ),
            ],
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: featuredSourceMode,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              labelText: 'Source Mode',
            ),
            items: const [
              DropdownMenuItem(value: 'mixed', child: Text('Mixed (Admin + Keyword Comments)')),
              DropdownMenuItem(value: 'admin_only', child: Text('Admin Only')),
              DropdownMenuItem(value: 'keywords_only', child: Text('Keyword Comments Only')),
            ],
            onChanged: (value) {
              if (value == null) return;
              _saveCommunitySettings({
                'featuredSourceMode': value,
              });
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Mixed ratio: 1 admin message every $featuredMixedAdminEveryUsers keyword comments',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          Slider(
            value: featuredMixedAdminEveryUsers.toDouble(),
            min: 1,
            max: 20,
            divisions: 19,
            label: '$featuredMixedAdminEveryUsers',
            onChanged: (value) {
              _saveCommunitySettings({
                'featuredMixedAdminEveryUsers': value.round(),
              });
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _featuredKeywordsController,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Keyword Search List',
              hintText: 'peace, healing, gratitude',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: () {
                  final keywords = _featuredKeywordsController.text
                      .split(',')
                      .map((e) => e.trim().toLowerCase())
                      .where((e) => e.isNotEmpty)
                      .toSet()
                      .toList();
                  _saveCommunitySettings({
                    'featuredKeywords': keywords,
                  });
                },
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save Keywords'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Used by featured rotation scanner in Cloud Functions.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveFeedList() {
    return StreamBuilder<QuerySnapshot>(
      key: ValueKey(_selectedFeedId), // Force rebuild when ID changes
      stream: _selectedFeedId == 'global'
          ? FirebaseFirestore.instance
              .collection('community_posts')
              .orderBy('timestamp', descending: true)
              .snapshots()
          : FirebaseFirestore.instance
              .collection('community_groups')
              .doc(_selectedFeedId)
              .collection('messages')
              .orderBy('timestamp', descending: true)
              .snapshots(),
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
            final imageUrl = _imageUrlForPost(post);

            // Handle different field names between Global Feed and Group Chat
            final content = post['content'] ?? post['text'] ?? '';
            final userName = post['userName'] ?? post['sender'] ?? 'Anonymous';
            final userPhoto = post['userPhoto']; // Only in global currently

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (imageUrl != null)
                      _buildImageThumbnail(imageUrl)
                    else
                      CircleAvatar(
                        backgroundColor: Colors.indigo.shade100,
                        backgroundImage: userPhoto != null ? NetworkImage(userPhoto) : null,
                        child: userPhoto == null
                            ? Text((userName.isNotEmpty ? userName[0].toUpperCase() : '?'))
                            : null,
                      ),
                    if (imageUrl != null)
                      Positioned(
                        right: -4,
                        bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade700,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.image, size: 10, color: Colors.white),
                        ),
                      ),
                  ],
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
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(content),
                  ],
                ),
                trailing: PopupMenuButton(
                  onSelected: (value) async {
                    if (value == 'delete') {
                      await postDoc.reference.delete();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Message deleted')),
                        );
                      }
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
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('User $userName suspended.')),
                          );
                        }
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'delete', child: Text('Delete Message')),
                    const PopupMenuItem(value: 'suspend', child: Text('Suspend User')),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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

  String? _userIdForModerationItem(Map<String, dynamic> item) {
    final candidates = [
      item['reporterId'],
      item['userId'],
      item['targetUserId'],
      item['authorUid'],
      item['uid'],
      item['ownerUid'],
      item['reportedUserId'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value == 'admin_media') continue;
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String _safeText(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  bool _isSystemSafeSearchItem(Map<String, dynamic> item) {
    final source = _safeText(item['source']).toLowerCase();
    final type = _safeText(item['type']).toLowerCase();
    return source == 'safe_search_storage_finalize' || type.startsWith('safe_search');
  }

  String _displayUserLabel(Map<String, dynamic> item) {
    final userName = _safeText(item['userName'] ?? item['username']);
    if (userName.isNotEmpty) return userName;

    final reporterName = _safeText(item['reporterName']);
    if (reporterName.isNotEmpty) return reporterName;

    if (_isSystemSafeSearchItem(item)) {
      return 'Automated Media Scanner';
    }

    return 'Unknown user';
  }

  bool _isReelReport(Map<String, dynamic> item) {
    final contentType = _safeText(item['contentType']).toLowerCase();
    if (contentType == 'reel') return true;

    final context = _safeText(item['context']).toLowerCase();
    if (context == 'reel') return true;

    final metadata = item['metadata'];
    if (metadata is Map) {
      final metaType = _safeText(metadata['contentType']).toLowerCase();
      if (metaType == 'reel') return true;
      if (_safeText(metadata['reelUrl']).isNotEmpty) return true;
    }

    return false;
  }

  Future<bool> _disableReportedReel(Map<String, dynamic> item) async {
    final metadata = item['metadata'];
    final reelUrl = metadata is Map ? _safeText(metadata['reelUrl']) : '';
    final reelTitle = metadata is Map ? _safeText(metadata['reelTitle']) : '';
    final reelType = metadata is Map ? _safeText(metadata['reelType']) : '';

    final configRef = FirebaseFirestore.instance
        .collection('app_config')
        .doc('home_screen');
    final snap = await configRef.get();
    if (!snap.exists) return false;

    final data = snap.data() ?? <String, dynamic>{};
    final rawItems = (data['reelItems'] as List?) ?? const [];
    if (rawItems.isEmpty) return false;

    var updated = false;
    final nextItems = rawItems.map((entry) {
      if (entry is! Map) return entry;
      final map = Map<String, dynamic>.from(entry);
      final itemUrl = _safeText(map['url']);
      final itemTitle = _safeText(map['title']);
      final itemType = _safeText(map['type']);

      final urlMatch = reelUrl.isNotEmpty && itemUrl == reelUrl;
      final titleTypeMatch =
          reelUrl.isEmpty &&
          reelTitle.isNotEmpty &&
          itemTitle == reelTitle &&
          (reelType.isEmpty || itemType == reelType);

      if (urlMatch || titleTypeMatch) {
        updated = true;
        map['enabled'] = false;
        map['moderationDisabledAt'] = DateTime.now().toUtc().toIso8601String();
        map['moderationDisabledReason'] =
            _safeText(item['reason'], fallback: 'Moderation queue disable');
      }
      return map;
    }).toList();

    if (!updated) return false;

    await configRef.set({
      'reelItems': nextItems,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  int _keywordHits(String text) {
    final normalized = text.toLowerCase();
    if (normalized.isEmpty) return 0;
    return _badWords.where((word) => normalized.contains(word)).length;
  }

  ({String label, Color bg, Color fg}) _severityForItem({
    required String content,
    required String reason,
    required String type,
  }) {
    final hits = _keywordHits(content);
    final normalizedReason = reason.toLowerCase();
    final normalizedType = type.toLowerCase();

    if (hits >= 2 ||
        normalizedReason.contains('violence') ||
        normalizedReason.contains('threat') ||
        normalizedReason.contains('self-harm') ||
        normalizedReason.contains('suicide') ||
        normalizedType.contains('urgent')) {
      return (
        label: 'High',
        bg: Colors.red.shade100,
        fg: Colors.red.shade900,
      );
    }

    if (hits == 1 || normalizedReason.contains('profanity')) {
      return (
        label: 'Medium',
        bg: Colors.orange.shade100,
        fg: Colors.orange.shade900,
      );
    }

    return (
      label: 'Review',
      bg: Colors.blue.shade100,
      fg: Colors.blue.shade900,
    );
  }

  /// Full-screen view of the reported/resolved post: content + image at
  /// full size, without leaving this screen. Renders whatever was stored
  /// on the moderation_queue item (pending) or moderation_cases doc (resolved).
  Future<void> _showPostContentDialog({
    required String content,
    String? imageUrl,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Reported Post', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
                const Divider(),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: GestureDetector(
                              onTap: () => _showExpandedImage(imageUrl),
                              child: Image.network(imageUrl, fit: BoxFit.contain),
                            ),
                          ),
                        if (imageUrl != null && imageUrl.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 4, bottom: 12),
                            child: Text('Tap image to zoom',
                                style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ),
                        Text(
                          content.isEmpty ? 'No text content attached to this post.' : content,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showExpandedImage(String imageUrl) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.94),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String? _offendingUserIdForItem(Map<String, dynamic> item) {
    final targetKind = _safeText(item['targetKind']).toLowerCase();
    final targetUserId = _safeText(item['targetUserId']);
    if (targetUserId.isNotEmpty) return targetUserId;

    if (targetKind == 'community_post' ||
        targetKind == 'community_reply' ||
        targetKind == 'chat_message' ||
        targetKind == 'support_message' ||
        targetKind == 'user') {
      final userId = _safeText(item['userId']);
      if (userId.isNotEmpty) return userId;
    }

    return null;
  }

  String _reportExplanationForItem(Map<String, dynamic> item) {
    final metadata = item['metadata'];
    if (metadata is Map) {
      final value = _safeText(metadata['reportExplanation']);
      if (value.isNotEmpty) return value;
    }
    return _safeText(item['reportExplanation']);
  }

  Future<String> _applyModerationAction(
    Map<String, dynamic> item,
    String contentAction, {
    bool refreshRetention = false,
  }) async {
    final targetKind = _safeText(item['targetKind']).toLowerCase();
    final targetId = _safeText(item['targetId']);
    final metadata = item['metadata'];

    if (contentAction == 'remove') {
      if (_isReelReport(item)) {
        final disabled = await _disableReportedReel(item);
        return disabled
            ? 'Removed: Reel disabled from user app'
            : 'Requested removal but reel target was not found';
      }

      if (targetKind == 'community_post' && targetId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('community_posts')
            .doc(targetId)
            .delete();
        return 'Removed: Community post deleted';
      }

      if (targetKind == 'community_reply' && metadata is Map) {
        final postId = _safeText(metadata['postId']);
        final replyId = _safeText(metadata['replyId'] ?? targetId);
        if (postId.isNotEmpty && replyId.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('community_posts')
              .doc(postId)
              .collection('replies')
              .doc(replyId)
              .delete();
          return 'Removed: Community reply deleted';
        }
      }

      return 'Remove requested: No direct removal path for this content type';
    }

    if (targetKind == 'community_post' && targetId.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('community_posts')
          .doc(targetId)
          .set({
        'isModerated': false,
        'moderationStatus': 'cleared',
        'moderatedAt': FieldValue.serverTimestamp(),
        if (refreshRetention) 'retentionAnchorAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return 'Left content active: Community post retained';
    }

    if (targetKind == 'community_reply' && metadata is Map) {
      final postId = _safeText(metadata['postId']);
      final replyId = _safeText(metadata['replyId'] ?? targetId);
      if (postId.isNotEmpty && replyId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('community_posts')
            .doc(postId)
            .collection('replies')
            .doc(replyId)
            .set({
          'isModerated': false,
          'moderationStatus': 'cleared',
          'moderatedAt': FieldValue.serverTimestamp(),
          if (refreshRetention) 'retentionAnchorAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return 'Left content active: Community reply retained';
      }
    }

    return 'Left content active';
  }

  Future<void> _notifyUserOfUpheldReport({
    required String userId,
    required String caseNumber,
    required String adminReason,
    required String actionSummary,
  }) async {
    final message = [
      'Your recent content was reported by a community member and reviewed by our moderation team.',
      'Outcome: The report was upheld.',
      'Reason: $adminReason',
      'Action taken: $actionSummary',
      'Case reference: $caseNumber',
      'If you would like more information, please contact support@harmonybyintent.com and include your case reference.',
    ].join('\n');

    final userMessageRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('messages')
        .doc();

    await userMessageRef.set({
      'title': 'Harmony Content Review Outcome',
      'content': message,
      'sender': 'support',
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
      'category': 'moderation_outcome',
      'caseNumber': caseNumber,
    });
  }

  String _caseNumberNow() {
    final now = DateTime.now().toUtc();
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(now);
    final millisTail = (now.millisecond).toString().padLeft(3, '0');
    return 'MOD-$stamp-$millisTail';
  }

  Future<void> _decideModerationItem({
    required DocumentSnapshot queueDoc,
    required Map<String, dynamic> item,
    required String decision,
    required String decisionNote,
    required String contentAction,
    bool refreshRetention = false,
  }) async {
    final caseNumber = _caseNumberNow();
    final moderator = FirebaseAuth.instance.currentUser;
    final moderatorLabel = _safeText(
      moderator?.displayName ?? moderator?.email ?? moderator?.uid,
      fallback: 'admin_operator',
    );

    final actionSummary = await _applyModerationAction(
      item,
      contentAction,
      refreshRetention: refreshRetention,
    );
    final offenderUserId = _offendingUserIdForItem(item);
    var notificationSent = false;
    String? notificationError;

    final caseDocRef = FirebaseFirestore.instance.collection('moderation_cases').doc();
    await caseDocRef.set({
      'caseNumber': caseNumber,
      'status': 'resolved',
      'decision': decision,
      'contentAction': contentAction,
      'actionSummary': actionSummary,
      'decisionNote': decisionNote,
      'decidedAt': FieldValue.serverTimestamp(),
      'decidedBy': moderatorLabel,
      'decidedByUid': moderator?.uid,
      'targetKind': _safeText(item['targetKind']),
      'targetId': _safeText(item['targetId']),
      'reason': _safeText(item['reason']),
      'reportExplanation': _reportExplanationForItem(item),
      'offenderUserId': offenderUserId,
      'offenderUserName': _safeText(item['userName']),
      'reporterId': _safeText(item['reporterId']),
      'reporterName': _safeText(item['reporterName']),
      'imageUrl': _imageUrlForPost(item),
      'queueItemId': queueDoc.id,
      'notificationSent': notificationSent,
      'source': _safeText(item['source']),
      'type': _safeText(item['type']),
      'context': _safeText(item['context']),
      'originalTimestamp': item['timestamp'],
      'content': _safeText(item['content']),
      'rawItem': item,
    });

    if (decision == 'agree' && offenderUserId != null && offenderUserId.isNotEmpty) {
      try {
        await _notifyUserOfUpheldReport(
          userId: offenderUserId,
          caseNumber: caseNumber,
          adminReason: decisionNote,
          actionSummary: actionSummary,
        );
        notificationSent = true;
      } catch (e) {
        notificationError = e.toString();
      }

      await caseDocRef.set({
        'notificationSent': notificationSent,
        if (notificationError != null) 'notificationError': notificationError,
      }, SetOptions(merge: true));
    }

    await queueDoc.reference.delete();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          notificationError == null
              ? 'Case $caseNumber resolved (${decision.toUpperCase()})'
              : 'Case $caseNumber resolved; user notification failed',
        ),
      ),
    );
  }

  Future<void> _showDecisionDialog(DocumentSnapshot queueDoc, Map<String, dynamic> item) async {
    final noteController = TextEditingController();
    String contentAction = 'remove';
    bool refreshRetention = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final note = noteController.text.trim();
              final canDecide = note.length >= 8;
              return AlertDialog(
                title: const Text('Decide Moderation Case'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Add a clear decision reason first, then choose Agree or Disagree.',
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteController,
                        maxLines: 4,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Decision reason (required)',
                          hintText: 'Minimum 8 characters',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        canDecide
                            ? 'Reason captured.'
                            : 'Please enter at least 8 characters.',
                        style: TextStyle(
                          color: canDecide ? Colors.green : Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Content action:'),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'remove',
                            label: Text('Remove content'),
                          ),
                          ButtonSegment<String>(
                            value: 'leave',
                            label: Text('Leave active'),
                          ),
                        ],
                        selected: {contentAction},
                        onSelectionChanged: (selection) {
                          if (selection.isEmpty) return;
                          setDialogState(() => contentAction = selection.first);
                        },
                      ),
                      if (contentAction == 'leave') ...[
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          value: refreshRetention,
                          onChanged: (value) =>
                              setDialogState(() => refreshRetention = value ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text(
                            'Give this post a fresh retention period from today',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: canDecide
                        ? () async {
                            Navigator.pop(dialogContext);
                              try {
                                await _decideModerationItem(
                                  queueDoc: queueDoc,
                                  item: item,
                                  decision: 'disagree',
                                  decisionNote: noteController.text.trim(),
                                  contentAction: contentAction,
                                  refreshRetention: refreshRetention,
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Decision failed: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                          }
                        : null,
                    child: const Text('Disagree'),
                  ),
                  ElevatedButton(
                    onPressed: canDecide
                        ? () async {
                            Navigator.pop(dialogContext);
                              try {
                                await _decideModerationItem(
                                  queueDoc: queueDoc,
                                  item: item,
                                  decision: 'agree',
                                  decisionNote: noteController.text.trim(),
                                  contentAction: contentAction,
                                  refreshRetention: refreshRetention,
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Decision failed: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                          }
                        : null,
                    child: const Text('Agree'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      noteController.dispose();
    }
  }

  Future<void> _editResolvedCase(DocumentSnapshot caseDoc, Map<String, dynamic> data) async {
    final controller = TextEditingController(text: _safeText(data['decisionNote']));
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Edit ${_safeText(data['caseNumber'], fallback: 'Case')}'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Decision note',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final updated = controller.text.trim();
                if (updated.length < 8) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Decision note must be at least 8 characters')),
                  );
                  return;
                }
                final moderator = FirebaseAuth.instance.currentUser;
                await caseDoc.reference.set({
                  'decisionNote': updated,
                  'editedAt': FieldValue.serverTimestamp(),
                  'editedBy': _safeText(
                    moderator?.displayName ?? moderator?.email ?? moderator?.uid,
                    fallback: 'admin_operator',
                  ),
                }, SetOptions(merge: true));
                if (mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  bool _matchesResolvedFilter(String decision) {
    final normalized = decision.toLowerCase();
    if (_resolvedDecisionFilter == 'all') return true;
    return normalized == _resolvedDecisionFilter;
  }

  String _resolvedHistoryKeyForData(Map<String, dynamic> data) {
    final offenderUserId = _safeText(data['offenderUserId']);
    if (offenderUserId.isNotEmpty) return 'uid:$offenderUserId';
    final offenderUserName = _safeText(data['offenderUserName']).toLowerCase();
    if (offenderUserName.isNotEmpty) return 'name:$offenderUserName';
    return '';
  }

  bool _matchesResolvedHistoryFilter(Map<String, dynamic> data) {
    if (_resolvedHistoryUserId == null && _resolvedHistoryUserName == null) {
      return true;
    }

    final offenderUserId = _safeText(data['offenderUserId']);
    final offenderUserName = _safeText(data['offenderUserName']);

    if (_resolvedHistoryUserId != null && _resolvedHistoryUserId!.isNotEmpty) {
      return offenderUserId == _resolvedHistoryUserId;
    }
    if (_resolvedHistoryUserName != null && _resolvedHistoryUserName!.isNotEmpty) {
      return offenderUserName.toLowerCase() == _resolvedHistoryUserName!.toLowerCase();
    }
    return true;
  }

  void _openResolvedHistory(Map<String, dynamic> data) {
    final offenderUserId = _safeText(data['offenderUserId']);
    final offenderUserName = _safeText(data['offenderUserName']);
    if (offenderUserId.isEmpty && offenderUserName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user identity is attached to this case.')),
      );
      return;
    }
    setState(() {
      _resolvedHistoryUserId = offenderUserId.isNotEmpty ? offenderUserId : null;
      _resolvedHistoryUserName = offenderUserName.isNotEmpty ? offenderUserName : null;
    });
  }

  void _clearResolvedHistory() {
    setState(() {
      _resolvedHistoryUserId = null;
      _resolvedHistoryUserName = null;
    });
  }

  Widget _buildResolvedCases() {
    final searchTerm = _caseSearchController.text.trim().toLowerCase();
    return Column(
      children: [
        if (_resolvedHistoryUserId != null || _resolvedHistoryUserName != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _clearResolvedHistory,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to all cases'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Viewing history for ${_resolvedHistoryUserName ?? _resolvedHistoryUserId}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _caseSearchController,
            decoration: InputDecoration(
              labelText: 'Search by case number',
              hintText: 'e.g. MOD-20260830-...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchTerm.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () => _caseSearchController.clear(),
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              const Text('Decision:'),
              const SizedBox(width: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(value: 'all', label: Text('Both')),
                  ButtonSegment<String>(value: 'agree', label: Text('Agree')),
                  ButtonSegment<String>(value: 'disagree', label: Text('Disagree')),
                ],
                selected: {_resolvedDecisionFilter},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  setState(() => _resolvedDecisionFilter = selection.first);
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('moderation_cases')
                .orderBy('decidedAt', descending: true)
                .limit(200)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Failed to load resolved cases: ${snapshot.error}'));
              }
              final allDocs = snapshot.data?.docs ?? [];
              final caseCountsByUser = <String, int>{};
              for (final doc in allDocs) {
                final data = doc.data() as Map<String, dynamic>;
                final key = _resolvedHistoryKeyForData(data);
                if (key.isEmpty) continue;
                caseCountsByUser[key] = (caseCountsByUser[key] ?? 0) + 1;
              }

              final docs = allDocs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                if (searchTerm.isEmpty) return true;
                final caseNumber = _safeText(data['caseNumber']).toLowerCase();
                final matchesCaseSearch = caseNumber.contains(searchTerm);
                if (!matchesCaseSearch) return false;
                final decision = _safeText(data['decision'], fallback: 'unknown');
                if (!_matchesResolvedFilter(decision)) return false;
                return _matchesResolvedHistoryFilter(data);
              }).where((doc) {
                if (searchTerm.isNotEmpty) return true;
                final data = doc.data() as Map<String, dynamic>;
                final decision = _safeText(data['decision'], fallback: 'unknown');
                if (!_matchesResolvedFilter(decision)) return false;
                return _matchesResolvedHistoryFilter(data);
              }).toList();

              final historyDisplayName = _resolvedHistoryUserName ?? _resolvedHistoryUserId;
              final resultSummary = historyDisplayName != null
                  ? 'Showing ${docs.length} case${docs.length == 1 ? '' : 's'} for $historyDisplayName'
                  : 'Showing ${docs.length} case${docs.length == 1 ? '' : 's'}';

              if (docs.isEmpty) {
                return Center(
                  child: Text(
                    historyDisplayName != null
                        ? 'No resolved cases found for $historyDisplayName.'
                        : 'No resolved cases found.',
                  ),
                );
              }

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        resultSummary,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final caseNumber = _safeText(data['caseNumber'], fallback: doc.id);
                        final decision = _safeText(data['decision'], fallback: 'unknown');
                        final decisionNormalized = decision.toLowerCase();
                        final contentAction = _safeText(data['contentAction'], fallback: 'unspecified');
                        final note = _safeText(data['decisionNote']);
                        final reason = _safeText(data['reason']);
                        final reporterName = _safeText(data['reporterName']);
                        final reporterId = _safeText(data['reporterId']);
                        final offenderUserName = _safeText(data['offenderUserName']);
                        final offenderUserId = _safeText(data['offenderUserId']);
                        final caseUserKey = _resolvedHistoryKeyForData(data);
                        final caseCountForUser = caseCountsByUser[caseUserKey] ?? 1;
                        final timestamp = (data['decidedAt'] as Timestamp?)?.toDate();
                        final decidedBy = _safeText(data['decidedBy']);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          color: decisionNormalized == 'disagree'
                              ? Colors.red.shade50
                              : (decisionNormalized == 'agree' ? Colors.green.shade50 : null),
                          child: ListTile(
                            onTap: () => _openResolvedHistory(data),
                            title: Text(
                              '$caseNumber • ${decision.toUpperCase()}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: decisionNormalized == 'disagree'
                                            ? Colors.red.shade100
                                            : Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        decisionNormalized == 'disagree' ? 'DISAGREE' : 'AGREE',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: decisionNormalized == 'disagree'
                                              ? Colors.red.shade900
                                              : Colors.green.shade900,
                                        ),
                                      ),
                                    ),
                                    if (caseCountForUser > 1)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade100,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '$caseCountForUser incidents for this user',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.indigo.shade900,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Reason: ${reason.isEmpty ? 'N/A' : reason}'),
                                Text('Action: $contentAction'),
                                Text(
                                  'Reported user: ${offenderUserName.isNotEmpty ? offenderUserName : 'N/A'}',
                                ),
                                Text(
                                  'Reported user ID: ${offenderUserId.isNotEmpty ? offenderUserId : 'N/A'}',
                                ),
                                Text(
                                  'Reporter: ${reporterName.isNotEmpty ? reporterName : 'N/A'}',
                                ),
                                Text(
                                  'Reporter ID: ${reporterId.isNotEmpty ? reporterId : 'N/A'}',
                                ),
                                if (note.isNotEmpty) Text('Decision note: $note'),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _showPostContentDialog(
                                        content: _safeText(data['content']),
                                        imageUrl: _safeText(data['imageUrl']).isEmpty
                                            ? null
                                            : _safeText(data['imageUrl']),
                                      ),
                                      icon: const Icon(Icons.visibility_outlined, size: 16),
                                      label: const Text('View Post'),
                                    ),
                                    if (offenderUserId.isNotEmpty && widget.onUserSelected != null)
                                      OutlinedButton.icon(
                                        onPressed: () => widget.onUserSelected!(offenderUserId),
                                        icon: const Icon(Icons.person_search, size: 16),
                                        label: const Text('Manage User'),
                                      ),
                                    if (caseCountForUser > 1)
                                      OutlinedButton.icon(
                                        onPressed: () => _openResolvedHistory(data),
                                        icon: const Icon(Icons.history, size: 16),
                                        label: const Text('View History'),
                                      ),
                                  ],
                                ),
                                Text(
                                  [
                                    if (timestamp != null)
                                      DateFormat('MMM d, h:mm a').format(timestamp),
                                    if (decidedBy.isNotEmpty) 'By: $decidedBy',
                                  ].join(' • '),
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: 'Edit case note',
                              icon: const Icon(Icons.edit_note),
                              onPressed: () => _editResolvedCase(doc, data),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  String? _imageUrlForPost(Map<String, dynamic> post) {
    final metadata = post['metadata'];
    final candidates = [
      post['imageUrl'],
      post['thumbnailUrl'],
      post['mediaUrl'],
      post['downloadUrl'],
      if (metadata is Map) metadata['imageUrl'],
      if (metadata is Map) metadata['thumbnailUrl'],
      if (metadata is Map) metadata['mediaUrl'],
    ];

    for (final candidate in candidates) {
      final url = candidate?.toString().trim() ?? '';
      if (url.isNotEmpty) {
        return url;
      }
    }

    final hasImage = post['hasImage'] == true || post['image'] == true;
    if (hasImage) {
      final fallback = post['image']?.toString().trim() ?? '';
      if (fallback.isNotEmpty) {
        return fallback;
      }
    }

    return null;
  }

  Widget _buildImageThumbnail(String imageUrl) {
    return GestureDetector(
      onTap: () => _showExpandedImage(imageUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 52,
          height: 52,
          color: Colors.grey.shade200,
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade500, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Compact section header and sub-tabs
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
                  Text(
                    'Live moderation workspace',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TabBar(
                controller: _tabController,
                labelColor: Colors.indigo,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.indigo,
                tabs: const [
                  Tab(icon: Icon(Icons.gavel), text: 'Moderation Queue'),
                  Tab(icon: Icon(Icons.assignment_turned_in), text: 'Resolved'),
                  Tab(icon: Icon(Icons.forum), text: 'Live Feed'),
                ],
              ),
            ],
          ),
        ),
        
        // Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildModerationQueue(),
              _buildResolvedCases(),
              _buildLiveFeed(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildModerationQueue() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('moderation_queue')
          .where('status', isEqualTo: 'pending')
          .limit(100)
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

        if (!snapshot.hasData) {
          return const Center(child: Text('No data'));
        }

        final pendingItems = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final type = (data['type'] ?? '').toString().trim().toLowerCase();
          return type != 'safe_search_passed';
        }).toList()
          ..sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            final bTs = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
            final aMs = aTs?.millisecondsSinceEpoch ?? 0;
            final bMs = bTs?.millisecondsSinceEpoch ?? 0;
            return bMs.compareTo(aMs);
          });

        if (pendingItems.isEmpty) {
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
                  'No pending moderation items.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: pendingItems.length,
          itemBuilder: (context, index) {
            final queueDoc = pendingItems[index];
            final item = queueDoc.data() as Map<String, dynamic>;
            final timestamp = (item['timestamp'] as Timestamp?)?.toDate();

            final userId = _userIdForModerationItem(item);
            final userName = _displayUserLabel(item);
            final content = _safeText(item['content']);
            final reason = _safeText(item['reason'], fallback: 'Review required');
            final source = _safeText(item['source'], fallback: 'unknown');
            final type = _safeText(item['type']);
            final targetKind = _safeText(item['targetKind']);
            final targetId = _safeText(item['targetId']);
            final reporterName = _safeText(item['reporterName']);
            final reporterId = _safeText(item['reporterId']);
            final imageUrl = _imageUrlForPost(item);
            final isSystemItem = _isSystemSafeSearchItem(item);
            final isReelItem = _isReelReport(item);
            final metadata = item['metadata'];
            final reelTitle = metadata is Map ? _safeText(metadata['reelTitle']) : '';
            final reelUrl = metadata is Map ? _safeText(metadata['reelUrl']) : '';
            final reelType = metadata is Map ? _safeText(metadata['reelType']) : '';
            final reportExplanation = _reportExplanationForItem(item);
            final safeSearch = item['safeSearch'];
            final severity = _severityForItem(
              content: content,
              reason: reason,
              type: type,
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.red.shade50, // Highlight flagged posts
              child: ListTile(
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (imageUrl != null)
                      _buildImageThumbnail(imageUrl)
                    else
                      CircleAvatar(
                        backgroundColor: Colors.red.shade100,
                        child: const Icon(Icons.warning, color: Colors.red),
                      ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.gavel, size: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        userName,
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
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      'Report reason: $reason',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: severity.bg,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Risk: ${severity.label}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: severity.fg,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: imageUrl != null
                                ? Colors.indigo.shade100
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            imageUrl != null
                                ? 'Image: Tap thumbnail to expand'
                                : (isReelItem
                                    ? 'Image: No reel thumbnail provided'
                                    : 'Image: Not attached'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: imageUrl != null
                                  ? Colors.indigo.shade900
                                  : Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (targetKind.isNotEmpty || targetId.isNotEmpty || reporterName.isNotEmpty || reporterId.isNotEmpty)
                      Text(
                        [
                          if (targetKind.isNotEmpty) 'Target: $targetKind',
                          if (targetId.isNotEmpty) 'ID: $targetId',
                          if (reporterName.isNotEmpty) 'Reporter: $reporterName',
                          if (reporterName.isEmpty && isSystemItem) 'Reporter: Automated system',
                          if (reporterId.isNotEmpty) 'Reporter ID: $reporterId',
                        ].join(' • '),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    if (targetKind.isNotEmpty || targetId.isNotEmpty || reporterName.isNotEmpty || reporterId.isNotEmpty)
                      const SizedBox(height: 4),
                    if (isReelItem && (reelTitle.isNotEmpty || reelType.isNotEmpty || reelUrl.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          [
                            if (reelTitle.isNotEmpty) 'Reel: $reelTitle',
                            if (reelType.isNotEmpty) 'Type: $reelType',
                            if (reelUrl.isNotEmpty) 'URL: $reelUrl',
                            if (reelUrl.isEmpty) 'URL: missing (legacy report)',
                          ].join(' • '),
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    if (safeSearch is Map)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'SafeSearch: adult=${_safeText(safeSearch['adult'], fallback: 'UNKNOWN')} • violence=${_safeText(safeSearch['violence'], fallback: 'UNKNOWN')} • racy=${_safeText(safeSearch['racy'], fallback: 'UNKNOWN')}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    if (reportExplanation.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Reporter note: $reportExplanation',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                        ),
                      ),
                    if (reportExplanation.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Reporter note: Not provided',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ),
                    if (content.isNotEmpty)
                      Text(content),
                    if (content.isEmpty)
                      Text(
                        imageUrl != null
                            ? 'Image-only moderation item (no text body).'
                            : 'No text content attached to this report.',
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Source: $source${type.isNotEmpty ? ' • Type: $type' : ''}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.visibility_outlined, size: 16, color: Colors.indigo),
                          label: const Text('View Post', style: TextStyle(color: Colors.indigo)),
                          onPressed: () => _showPostContentDialog(
                            content: content,
                            imageUrl: imageUrl,
                          ),
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.indigo)),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_search, size: 16),
                          label: const Text('Manage User'),
                          onPressed: () {
                            if (userId != null && userId.isNotEmpty && widget.onUserSelected != null) {
                              widget.onUserSelected!(userId);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Cannot navigate: User ID missing or handler not set')),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.indigo,
                            side: const BorderSide(color: Colors.indigo),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.check, size: 16, color: Colors.green),
                          label: const Text('Decide', style: TextStyle(color: Colors.green)),
                          onPressed: () async {
                            await _showDecisionDialog(queueDoc, item);
                          },
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                          label: const Text('Delete Queue Item', style: TextStyle(color: Colors.red)),
                          onPressed: () async {
                            await queueDoc.reference.delete();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Queue item deleted')),
                              );
                            }
                          },
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

  Widget _buildLiveFeed() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 1180;

        final controls = Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey.shade100,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('community_groups')
                    .orderBy('sortOrder')
                    .snapshots(),
                builder: (context, snapshot) {
                  List<DropdownMenuItem<String>> items = [
                    const DropdownMenuItem(
                      value: 'global',
                      child: Text('Global Public Feed (Default)'),
                    ),
                  ];

                  if (snapshot.hasData) {
                    items.addAll(snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DropdownMenuItem(
                        value: doc.id,
                        child: Text('Chat Group: ${data['name'] ?? 'Unknown'}'),
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
                                _selectedFeedName = items
                                    .firstWhere((i) => i.value == val)
                                    .child
                                    .toString();
                                _messageController.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              StreamBuilder<DocumentSnapshot>(
                stream: _selectedFeedId == 'global'
                    ? FirebaseFirestore.instance
                        .collection('app_config')
                        .doc('community_settings')
                        .snapshots()
                    : FirebaseFirestore.instance
                        .collection('community_groups')
                        .doc(_selectedFeedId)
                        .snapshots(),
                builder: (context, snapshot) {
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
                                    onPressed: () => _saveAdminMessage(''),
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
                },
              ),
              const SizedBox(height: 8),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('app_config')
                    .doc('community_settings')
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
                  return _buildLiveFeedControlsCard(data);
                },
              ),
            ],
          ),
        );

        final feed = _buildLiveFeedList();

        if (sideBySide) {
          return Row(
            children: [
              SizedBox(
                width: 460,
                child: SingleChildScrollView(child: controls),
              ),
              VerticalDivider(width: 1, color: Colors.grey.shade300),
              Expanded(child: feed),
            ],
          );
        }

        return Column(
          children: [
            SizedBox(
              height: 300,
              child: SingleChildScrollView(child: controls),
            ),
            const Divider(height: 1),
            Expanded(child: feed),
          ],
        );
      },
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
