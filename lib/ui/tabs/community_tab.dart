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
  bool _isMessageLoaded = false;
  
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header & Tabs
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Community & Communication',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Manage user interactions, moderate content, and respond to inquiries.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
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
          .collection('community_posts')
          .orderBy('timestamp', descending: true)
          .limit(100) // Limit to recent posts for performance
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('No data'));
        }

        // Client-side filtering for profanity OR manually flagged
        final flaggedPosts = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final content = (data['content'] as String? ?? '').toLowerCase();
          
          // Future V3: Check 'status' field here (e.g. status == 'open')
          // if (data['status'] == 'resolved') return false; 
          
          final containsProfanity = _badWords.any((word) => content.contains(word));
          final manualFlag = data['isFlagged'] == true; // Support future manual flagging
          
          return containsProfanity || manualFlag;
        }).toList();

        if (flaggedPosts.isEmpty) {
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
                  'No content flagged for profanity.',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: flaggedPosts.length,
          itemBuilder: (context, index) {
            final postDoc = flaggedPosts[index];
            final post = postDoc.data() as Map<String, dynamic>;
            final timestamp = (post['timestamp'] as Timestamp?)?.toDate();

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.red.shade50, // Highlight flagged posts
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.red.shade100,
                  child: const Icon(Icons.warning, color: Colors.red),
                ),
                title: Row(
                  children: [
                    Text(post['userName'] ?? 'Anonymous', style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    Text(post['content'] ?? ''),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.person_search, size: 16),
                          label: const Text('Manage User'),
                          onPressed: () {
                            final userId = post['userId'];
                            if (userId != null && widget.onUserSelected != null) {
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
                          label: const Text('Resolve (V3 Mock)', style: TextStyle(color: Colors.green)),
                          onPressed: () async {
                              // V3 Preparation: This button creates the 'status' and 'assignedTo' fields.
                              // This ensures the data structure is ready for the future update.
                              await postDoc.reference.set({
                                'status': 'resolved',
                                'resolvedAt': FieldValue.serverTimestamp(),
                                'assignedTo': 'admin_legacy', // Placeholder for token system
                              }, SetOptions(merge: true));
                              
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Marked as Resolved (Prepared for V3)')),
                                );
                              }
                          },
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.green)),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                          label: const Text('Delete Post', style: TextStyle(color: Colors.red)),
                          onPressed: () async {
                            await postDoc.reference.delete();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Post deleted')),
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
    return Column(
      children: [
        // Feed Selector & Admin Message
        Container(
          padding: const EdgeInsets.all(16),
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
              const SizedBox(height: 16),
              
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
                            hintText: 'Type message for top of screen...',
                            labelText: 'Admin Message (Appears at Top of Chat)',
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
                      const SizedBox(width: 8),
                      // "Send" button as requested (performs Pin/Save operation)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send),
                        label: const Text('Send'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                        ),
                        onPressed: () => _saveAdminMessage(_messageController.text),
                      ),
                    ],
                  );
                }
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
                      subtitle: Text(content),
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
