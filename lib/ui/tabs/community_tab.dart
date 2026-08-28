import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _adminChatController.dispose();
    _featuredKeywordsController.dispose();
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

  String? _imageUrlForPost(Map<String, dynamic> post) {
    final candidates = [
      post['imageUrl'],
      post['thumbnailUrl'],
      post['mediaUrl'],
      post['downloadUrl'],
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
    return ClipRRect(
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

            final userId =
                (item['userId'] ??
                        item['uid'] ??
                        item['ownerUid'] ??
                        item['authorUid'] ??
                        item['reportedUserId'])
                    ?.toString();
            final userName = (item['userName'] ?? item['username'] ?? 'Unknown user').toString();
            final content = (item['content'] ?? '').toString();
            final reason = (item['reason'] ?? 'Review required').toString();
            final source = (item['source'] ?? 'unknown').toString();
            final type = (item['type'] ?? '').toString();
            final imageUrl = _imageUrlForPost(item);

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
                      reason,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
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
                          label: const Text('Resolve', style: TextStyle(color: Colors.green)),
                          onPressed: () async {
                              await queueDoc.reference.set({
                                'status': 'resolved',
                                'resolvedAt': FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Marked as resolved')),
                                );
                              }
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
