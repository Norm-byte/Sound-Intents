import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/user_profile.dart';
import '../../services/lock_service.dart';
import '../../services/translation_service.dart';
import '../../utils/quick_replies.dart';
import '../../widgets/translatable_text.dart';

class UserManagementTab extends StatefulWidget {
  final String? initialUserId;
  const UserManagementTab({super.key, this.initialUserId});

  @override
  State<UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends State<UserManagementTab> {
  String _searchQuery = '';
  String _filterStatus = 'all'; // all, active, suspended, trial
  String _viewMode = 'users'; // 'users', 'resolved', or 'inbox'
  UserProfile? _selectedUser;
  int _initialDetailTabIndex = 0; // To open specific tab in detail panel

  String _canonicalUserKey(UserProfile user) {
    final email = user.email.trim().toLowerCase();
    if (email.isNotEmpty && email != 'no-email@example.com') {
      return 'email:$email';
    }
    return 'id:${user.id.toLowerCase()}';
  }

  @override
  void initState() {
    super.initState();
    TranslationService.instance.init();
    if (widget.initialUserId != null) {
      _loadInitialUser();
    }
  }

  @override
  void dispose() {
    // Release any held lock
    if (_selectedUser != null) {
      LockService().releaseLock(_selectedUser!.id, 'user');
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(UserManagementTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialUserId != oldWidget.initialUserId && widget.initialUserId != null) {
      _loadInitialUser();
    }
  }

  Future<void> _loadInitialUser() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(widget.initialUserId).get();
      if (doc.exists) {
        setState(() {
          _selectedUser = UserProfile.fromFirestore(doc.id, doc.data() as Map<String, dynamic>);
          _viewMode = 'users'; // Ensure we are in user view
          _initialDetailTabIndex = 2; // Open Communications tab
        });
      }
    } catch (e) {
      debugPrint('Error loading initial user: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // User Index Cards (Left Panel)
        Expanded(
          flex: 2,
          child: Column(
            children: [
              // Search and Filters
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people, color: Colors.indigo),
                        const SizedBox(width: 8),
                        const Text(
                          'User Management',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        // View Toggle
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.list, 
                                  color: _viewMode == 'users' ? Colors.indigo : Colors.grey),
                                onPressed: () => setState(() {
                                  _viewMode = 'users';
                                  _filterStatus = 'all';
                                }),
                                tooltip: 'User List',
                              ),
                              Container(width: 1, height: 24, color: Colors.grey.shade300),
                              IconButton(
                                icon: Icon(Icons.check_circle_outline, 
                                  color: _viewMode == 'resolved' ? Colors.green : Colors.grey),
                                onPressed: () => setState(() {
                                  _viewMode = 'resolved';
                                  _filterStatus = 'suspended';
                                }),
                                tooltip: 'Resolved / Suspended',
                              ),
                              Container(width: 1, height: 24, color: Colors.grey.shade300),
                              IconButton(
                                icon: Icon(Icons.inbox, 
                                  color: _viewMode == 'inbox' ? Colors.indigo : Colors.grey),
                                onPressed: () => setState(() => _viewMode = 'inbox'),
                                tooltip: 'Support Inbox',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_viewMode == 'users' || _viewMode == 'resolved') ...[
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Search by name, email, or ID...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                      ),
                      const SizedBox(height: 12),
                      if (_viewMode == 'users')
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('All Non-Suspended'),
                            selected: _filterStatus == 'all',
                            onSelected: (_) => setState(() => _filterStatus = 'all'),
                          ),
                          ChoiceChip(
                            label: const Text('Active'),
                            selected: _filterStatus == 'active',
                            onSelected: (_) => setState(() => _filterStatus = 'active'),
                          ),
                          ChoiceChip(
                            label: const Text('Trial'),
                            selected: _filterStatus == 'trial',
                            onSelected: (_) => setState(() => _filterStatus = 'trial'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // List Content
              Expanded(
                child: (_viewMode == 'users' || _viewMode == 'resolved')
                    ? _buildUserList() 
                    : _buildSupportInbox(),
              ),
            ],
          ),
        ),

        // Detailed User Profile (Right Panel)
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(left: BorderSide(color: Colors.grey.shade300)),
            ),
            child: _selectedUser == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_outline, size: 80, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(
                          'Select a user to view details',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : _UserDetailPanel(
                    key: ValueKey(_selectedUser!.id),
                    user: _selectedUser!,
                    initialTabIndex: _initialDetailTabIndex,
                    onUpdate: () => setState(() {}),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildUserList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Error loading users: ${snapshot.error}'),
          );
        }

        final userDocs = snapshot.data?.docs ?? [];
                    final users = userDocs.map((doc) {
                      return UserProfile.fromFirestore(doc.id, doc.data() as Map<String, dynamic>);
                    }).where((user) {
                      // Apply search filter
                      if (_searchQuery.isNotEmpty) {
                        final match = user.name.toLowerCase().contains(_searchQuery) ||
                            user.email.toLowerCase().contains(_searchQuery) ||
                            user.id.toLowerCase().contains(_searchQuery);
                        if (!match) return false;
                      }
                      // Apply view mode & status filter
                      if (_viewMode == 'resolved') {
                        // In Resolved mode, only show suspended or explicitly resolved
                        if (user.status != 'suspended') return false;
                      } else {
                        // In Users mode, hide suspended
                        if (user.status == 'suspended') return false;
                        
                        // Apply specific chip filters
                        if (_filterStatus != 'all') {
                          if (_filterStatus == 'active' && user.status != 'active') return false;
                          if (_filterStatus == 'trial' && user.status != 'trial') return false;
                        }
                      }
                      return true;
                    }).toList();

                    // Guard against duplicate cards by collapsing equivalent user records.
                    final seenUserKeys = <String>{};
                    final dedupedUsers = <UserProfile>[];
                    for (final user in users) {
                      final key = _canonicalUserKey(user);
                      if (seenUserKeys.add(key)) {
                        dedupedUsers.add(user);
                      }
                    }

                    if (dedupedUsers.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty ? 'No users found' : 'No users match your search',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: dedupedUsers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final user = dedupedUsers[index];
                        final isSelected = _selectedUser?.id == user.id;
                        return _UserIndexCard(
                          user: user,
                          isSelected: isSelected,
                          onTap: () async {
                            if (_selectedUser?.id == user.id) return;

                            // 1. Try to acquire lock
                            try {
                              final lockedBy = await LockService().acquireLock(user.id, 'user');
                              
                              if (lockedBy != null) {
                                if (context.mounted) {
                                  showDialog(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Row(children: [
                                        const Icon(Icons.lock, color: Colors.orange), 
                                        const SizedBox(width: 8), 
                                        const Text('Locked'),
                                      ]),
                                      content: Text('This user is currently being processed by administrator "$lockedBy".\n\nPlease wait for them to finish.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                                      ],
                                    ),
                                  );
                                }
                                return;
                              }
                            } catch (e) {
                              debugPrint('Lock error (ignored): $e');
                            }

                            // 2. Release previous lock if exists
                            if (_selectedUser != null) {
                               LockService().releaseLock(_selectedUser!.id, 'user').catchError((_){});
                            }

                            setState(() {
                              _selectedUser = user;
                              _initialDetailTabIndex = 0;
                            });
                          },
                        );
                      },
                    );
                  },
                );
  }

  Widget _buildSupportInbox() {
    return Column(
      children: [
        // Header to distinguish from User List
        Container(
          padding: const EdgeInsets.all(12),
          width: double.infinity,
          color: Colors.indigo.shade50,
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Support Inbox (Recent Thread Activity)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ),
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
                                ? 'Translator enabled for support views'
                                : 'Translator disabled for support views',
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
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('support_inbox') // Now using the summarized inbox
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('Inbox Empty'),
                    ],
                  ),
                );
              }

              final messages = snapshot.data!.docs;

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final msgDoc = messages[index];
                  final msg = msgDoc.data() as Map<String, dynamic>;
                  final timestamp = _safeDate(msg['timestamp']);
                  
                  // In the new system, document ID is the User ID
                  final userId = msg['userId'] ?? msgDoc.id; 
                  final userName = msg['userName'] ?? 'Unknown User';
                  
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.indigo.shade100,
                      child: const Icon(Icons.person, color: Colors.indigo),
                    ),
                    title: Row(
                      children: [
                        Expanded(child: Text(userName, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                        if (timestamp != null)
                          Text(
                            DateFormat('MMM d, h:mm a').format(timestamp),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         TranslatableText(
                           msg['content'] ?? 'New Message',
                           maxLines: 2,
                           overflow: TextOverflow.ellipsis,
                         ),
                      ],
                    ),
                    onTap: () async {
                      // Fetch direct user reference
                      final userDocRef = FirebaseFirestore.instance.collection('users').doc(userId);
                      
                      try {
                          final userDoc = await userDocRef.get();
                          if (!userDoc.exists) {
                             if (context.mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User profile not found.')));
                             }
                             return;
                          }

                          final userData = userDoc.data() as Map<String, dynamic>;
                          final user = UserProfile.fromFirestore(userDoc.id, userData);
                          
                          // Lock Logic
                          if (_selectedUser?.id != user.id) {
                            // ... Locking logic ...
                             if (_selectedUser != null) {
                               LockService().releaseLock(_selectedUser!.id, 'user').catchError((e) {});
                             }
                          }

                          setState(() {
                            _selectedUser = user;
                            _initialDetailTabIndex = 2; // Switch to Communications tab
                          });
                        } catch (e) {
                          debugPrint('Error accessing user details: $e');
                        }
                    },
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.grey),
                      tooltip: 'Clear from Inbox',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Remove from Inbox?'),
                            content: const Text('This will remove the conversation from this list. The message history is still preserved in the user profile.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                        );

                        if (confirm == true) {
                           await msgDoc.reference.delete();
                        }
                      },
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
}

// User Index Card (Compact View)
class _UserIndexCard extends StatelessWidget {
  final UserProfile user;
  final bool isSelected;
  final VoidCallback onTap;

  const _UserIndexCard({
    required this.user,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: LockService().watchLock(user.id, 'user'),
      builder: (context, snapshot) {
        final lockedBy = snapshot.data;
        final isLocked = lockedBy != null;

        return Card(
          elevation: isSelected ? 4 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isLocked 
                  ? Colors.orange.withOpacity(0.5) 
                  : (isSelected ? Colors.indigo : Colors.transparent),
              width: 2,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: _statusColor(user.status).withOpacity(0.2),
                        child: Text(
                          user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _statusColor(user.status),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email,
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _StatusBadge(status: user.status),
                                const SizedBox(width: 8),
                                Icon(Icons.event, size: 14, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text(
                                  '${user.eventsJoined} events',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!isLocked)
                        Icon(
                          Icons.chevron_right,
                          color: isSelected ? Colors.indigo : Colors.grey.shade400,
                        ),
                    ],
                  ),
                ),
                if (isLocked)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock, size: 12, color: Colors.deepOrange),
                          const SizedBox(width: 4),
                          Text(
                            lockedBy!,
                            style: const TextStyle(fontSize: 10, color: Colors.deepOrange, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'trial':
        return Colors.orange;
      case 'suspended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'active':
        color = Colors.green;
        label = 'Active';
        break;
      case 'trial':
        color = Colors.orange;
        label = 'Trial';
        break;
      case 'suspended':
        color = Colors.red;
        label = 'Suspended';
        break;
      default:
        color = Colors.grey;
        label = 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// Detailed User Profile Panel
class _UserDetailPanel extends StatefulWidget {
  final UserProfile user;
  final int initialTabIndex;
  final VoidCallback onUpdate;

  const _UserDetailPanel({
    super.key,
    required this.user,
    this.initialTabIndex = 0,
    required this.onUpdate,
  });

  @override
  State<_UserDetailPanel> createState() => _UserDetailPanelState();
}

class _UserDetailPanelState extends State<_UserDetailPanel> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // User Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Reduced padding
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24, // Smaller radius
                backgroundColor: Colors.indigo.shade100,
                child: Text(
                  widget.user.name.isNotEmpty ? widget.user.name[0].toUpperCase() : '?',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.user.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      widget.user.email,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _StatusBadge(status: widget.user.status),
                        const SizedBox(width: 8),
                        Text(widget.user.subscriptionPlan, 
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                        if (widget.user.status == 'suspended') ...[
                           const SizedBox(width: 8),
                           const Icon(Icons.timer_off, size: 12, color: Colors.red),
                           const SizedBox(width: 4),
                           Text('Suspended', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              // Compact Actions Column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                       IconButton(
                        icon: const Icon(Icons.message, size: 20, color: Colors.indigo),
                        tooltip: 'Message',
                        onPressed: () => _sendMessage(context),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                       ),
                       IconButton(
                        icon: const Icon(Icons.edit_note, size: 20, color: Colors.indigo),
                        tooltip: 'Actions',
                        onPressed: () => _manageSubscription(context),
                        constraints: const BoxConstraints(),
                         padding: EdgeInsets.zero,
                       ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // Tab Bar
        SizedBox(
          height: 36, // Force smaller height for TabBar
          child: TabBar(
            controller: _tabController,
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            tabs: const [
              Tab(text: 'Overview', height: 32),
              Tab(text: 'Events', height: 32),
              Tab(text: 'Comm.', height: 32),
              Tab(text: 'Billing', height: 32),
            ],
          ),
        ),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _OverviewTab(user: widget.user),
              _EventsTab(user: widget.user),
              _CommunicationsTab(user: widget.user),
              _BillingTab(user: widget.user),
            ],
          ),
        ),
      ],
    );
  }

  void _sendMessage(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Send Message to ${widget.user.name}'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
               TextButton.icon(
                 icon: const Icon(Icons.flash_on, size: 16, color: Colors.amber),
                 label: const Text('Quick Reply', style: TextStyle(color: Colors.amber)),
                 style: TextButton.styleFrom(
                   tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                   padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                 ),
                 onPressed: () => _showQuickReplyPicker(context, _noteController),
               ),
               const SizedBox(height: 4),
               TextField(
                controller: _noteController,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Type your message...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final message = _noteController.text.trim();
              if (message.isEmpty) return;

              Navigator.pop(ctx);
              
              try {
                // 1. Add message to user's subcollection
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.user.id)
                    .collection('messages')
                    .add({
                  'content': message,
                  'sender': 'admin',
                  'timestamp': FieldValue.serverTimestamp(),
                  'read': false,
                  'title': 'Admin Message',
                });

                // 2. Increment messagesReceived counter
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.user.id)
                    .update({
                  'messagesReceived': FieldValue.increment(1),
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Message sent successfully!'), backgroundColor: Colors.green),
                  );
                  _noteController.clear();
                  widget.onUpdate(); // Refresh UI
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error sending message: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            icon: const Icon(Icons.send),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _manageSubscription(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Manage ${widget.user.name}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Suspend for 1 Week'),
                subtitle: const Text('User will be suspended for 7 days.'),
                leading: const Icon(Icons.timer_off, color: Colors.orange),
                onTap: () {
                  Navigator.pop(ctx);
                  _performUserAction('suspend_7_days');
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Suspend Indefinitely'),
                subtitle: const Text('User moved to resolved/suspended list.'),
                leading: const Icon(Icons.block, color: Colors.red),
                onTap: () {
                  Navigator.pop(ctx);
                  _performUserAction('suspend_indefinite');
                },
              ),
              const Divider(),
              if (widget.user.status == 'suspended')
                ListTile(
                  title: const Text('Restore User'),
                  subtitle: const Text('Activate account and remove suspension.'),
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  onTap: () {
                    Navigator.pop(ctx);
                    _performUserAction('restore');
                  },
                ),
              ListTile(
                title: const Text('Edit Subscription Plan'),
                leading: const Icon(Icons.edit, color: Colors.indigo),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditSubscriptionDialog(context);
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Delete User', style: TextStyle(color: Colors.red)),
                subtitle: const Text('Permanently remove user data.'),
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteUser(context);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }

  void _confirmDeleteUser(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User?'),
        content: Text('Are you sure you want to permanently delete "${widget.user.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _performUserAction('delete');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _performUserAction(String action) async {
    try {
      if (action == 'delete') {
         await FirebaseFirestore.instance.collection('users').doc(widget.user.id).delete();
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('User deleted successfully.'), backgroundColor: Colors.red),
           );
           widget.onUpdate();
         }
         return;
      }

      final Map<String, dynamic> updates = {
         'lastAdminActionDate': FieldValue.serverTimestamp(),
      };
      
      String feedbackMessage = '';

      switch (action) {
        case 'suspend_7_days':
          updates['status'] = 'suspended';
          updates['suspensionExpiry'] = DateTime.now().add(const Duration(days: 7));
          updates['lastAdminAction'] = 'Suspended for 7 days';
          feedbackMessage = 'User suspended for 7 days.';
          break;
        case 'suspend_indefinite':
          updates['status'] = 'suspended';
          updates['suspensionExpiry'] = null;
          updates['lastAdminAction'] = 'Suspended indefinitely';
          feedbackMessage = 'User suspended indefinitely.';
          break;
        case 'restore':
          updates['status'] = 'active'; // or previous status if tracked
          updates['suspensionExpiry'] = null;
          updates['lastAdminAction'] = 'Restored by admin';
          feedbackMessage = 'User restored successfully.';
          break;
      }

      await FirebaseFirestore.instance.collection('users').doc(widget.user.id).update(updates);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(feedbackMessage), backgroundColor: Colors.indigo),
        );
        widget.onUpdate();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showEditSubscriptionDialog(BuildContext context) {
    String selectedStatus = widget.user.status;
    String selectedPlan = widget.user.subscriptionPlan;
    String selectedVipQuota =
      (widget.user.vipQuotaTier == 'starter_access' ||
        widget.user.vipQuotaTier == 'unlimited_access')
      ? widget.user.vipQuotaTier!
      : '__auto__';
    final renewalController = TextEditingController(text: widget.user.renewalDate ?? '');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Edit Subscription'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [ // ... existing items
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'trial', child: Text('Trial')),
                    DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                  ],
                  onChanged: (val) => setState(() => selectedStatus = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedPlan,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: const [
                    DropdownMenuItem(value: 'Free', child: Text('Free')),
                    DropdownMenuItem(value: 'Premium', child: Text('Premium')),
                    DropdownMenuItem(value: 'Pro', child: Text('Pro')),
                  ],
                  onChanged: (val) => setState(() => selectedPlan = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedVipQuota,
                  decoration: const InputDecoration(
                    labelText: 'VIP Daily Quota',
                    helperText: 'Only applies when user has VIP access.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: '__auto__',
                      child: Text('Automatic (no VIP override)'),
                    ),
                    DropdownMenuItem(
                      value: 'starter_access',
                      child: Text('Starter (10/day)'),
                    ),
                    DropdownMenuItem(
                      value: 'unlimited_access',
                      child: Text('Harmony 100 (100/day)'),
                    ),
                  ],
                  onChanged: (val) => setState(() => selectedVipQuota = val!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: renewalController,
                  decoration: const InputDecoration(
                    labelText: 'Renewal Date (YYYY-MM-DD)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(widget.user.id)
                        .update({
                      'status': selectedStatus,
                      'subscriptionPlan': selectedPlan,
                      'vipQuotaTier': selectedVipQuota == '__auto__' ? null : selectedVipQuota,
                      'renewalDate': renewalController.text.isEmpty ? null : renewalController.text,
                    });
                    
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Subscription updated!'), backgroundColor: Colors.green),
                      );
                      widget.onUpdate();
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating subscription: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                child: const Text('Save Changes'),
              ),
            ],
          );
        }
      ),
    );
  }
}

// Overview Tab
class _OverviewTab extends StatelessWidget {
  final UserProfile user;
  const _OverviewTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('User Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _InfoRow(label: 'User ID', value: user.id),
          _InfoRow(label: 'Join Date', value: user.joinDate ?? 'Unknown'),
          _InfoRow(label: 'Last Active', value: user.lastActive ?? 'Never'),
          _InfoRow(label: 'Events Joined', value: user.eventsJoined.toString()),
          _InfoRow(label: 'Subscription Plan', value: user.subscriptionPlan),
          if (user.renewalDate != null) _InfoRow(label: 'Next Renewal', value: user.renewalDate!),
          
          if (user.status == 'suspended') ...[
             const SizedBox(height: 16),
             const Text('Suspension Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
             const SizedBox(height: 8),
             if (user.suspensionExpiry != null)
               _InfoRow(label: 'Suspension Ends', value: user.suspensionExpiry!.toString().split(' ')[0]),
             if (user.lastAdminAction != null)
               _InfoRow(label: 'Last Action', value: user.lastAdminAction!),
          ],

          const SizedBox(height: 24),
          const Text('Quick Stats', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.event, size: 32, color: Colors.indigo),
                        const SizedBox(height: 8),
                        Text(
                          user.eventsJoined.toString(),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const Text('Events Joined', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Icon(Icons.chat_bubble, size: 32, color: Colors.green),
                        const SizedBox(height: 8),
                        Text(
                          user.messagesReceived.toString(),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const Text('Messages', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

// Events Tab
class _EventsTab extends StatelessWidget {
  final UserProfile user;
  const _EventsTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .collection('registered_events')
          .orderBy('registeredAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.event_busy, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('No events registered yet'),
                const SizedBox(height: 8),
                Text(
                  'Total events joined: ${user.eventsJoined}',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        final events = snapshot.data!.docs;

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final event = events[index].data() as Map<String, dynamic>;
            final date = _safeDate(event['eventDate']);
            final registeredAt = _safeDate(event['registeredAt']);

            return Card(
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.event, color: Colors.indigo),
                ),
                title: Text(event['title'] ?? 'Unknown Event'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (date != null)
                      Text('Event Date: ${date.toString().split(' ')[0]}'),
                    if (registeredAt != null)
                      Text('Registered: ${registeredAt.toString().split(' ')[0]}', 
                           style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
                trailing: Chip(
                  label: Text(event['status'] ?? 'Registered'),
                  backgroundColor: Colors.green.shade50,
                  labelStyle: TextStyle(color: Colors.green.shade700, fontSize: 12),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Communications Tab
class _CommunicationsTab extends StatefulWidget {
  final UserProfile user;
  const _CommunicationsTab({required this.user});

  @override
  State<_CommunicationsTab> createState() => _CommunicationsTabState();
}

class _CommunicationsTabState extends State<_CommunicationsTab> {
  final _messageController = TextEditingController();
  bool _isSending = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    TranslationService.instance.init();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSending = true);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.id)
          .collection('messages')
          .add({
        'content': content,
        'sender': 'admin',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                'Customer Support Translation',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: TranslationService.instance.enabledNotifier,
                builder: (context, enabled, _) {
                  return TextButton.icon(
                    onPressed: () async {
                      await TranslationService.instance.setEnabled(!enabled);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            !enabled
                                ? 'Translator enabled for support views'
                                : 'Translator disabled for support views',
                          ),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.translate,
                      size: 18,
                      color: enabled ? Colors.indigo : Colors.grey,
                    ),
                    label: Text(enabled ? 'ON' : 'OFF'),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.user.id)
                .collection('messages')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No communication history'),
                      const SizedBox(height: 8),
                      Text(
                        'Messages received: ${widget.user.messagesReceived}',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                );
              }

              final messages = snapshot.data!.docs;

              return ListView.separated(
                controller: _scrollController,
                reverse: true, // Show newest at bottom (standard chat UI)
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final msg = messages[index].data() as Map<String, dynamic>;
                  final timestamp = _safeDate(msg['timestamp']);
                  final isFromAdmin = msg['sender'] == 'admin';

                  return Align(
                    alignment: isFromAdmin ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isFromAdmin ? Colors.indigo.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFromAdmin ? Colors.indigo.shade100 : Colors.grey.shade300,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isFromAdmin ? Icons.admin_panel_settings : Icons.person,
                                size: 16,
                                color: isFromAdmin ? Colors.indigo : Colors.grey.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isFromAdmin ? 'Admin' : widget.user.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isFromAdmin ? Colors.indigo : Colors.grey.shade700,
                                ),
                              ),
                              if (timestamp != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          TranslatableText(msg['content'] ?? ''),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    prefixIcon: IconButton(
                       icon: const Icon(Icons.flash_on, color: Colors.amber),
                       tooltip: 'Quick Reply',
                       onPressed: () => _showQuickReplyPicker(context, _messageController),
                    ),
                    hintText: 'Type a reply...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(color: Colors.indigo),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: _isSending ? null : _sendMessage,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                ),
                icon: _isSending 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Billing Tab
class _BillingTab extends StatelessWidget {
  final UserProfile user;
  const _BillingTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Subscription Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _InfoRow(label: 'Plan', value: user.subscriptionPlan),
          _InfoRow(label: 'Status', value: user.status),
          if (user.renewalDate != null) _InfoRow(label: 'Renewal Date', value: user.renewalDate!),
          if (user.vipQuotaTier != null && user.vipQuotaTier!.isNotEmpty)
            _InfoRow(label: 'VIP Quota Tier', value: user.vipQuotaTier!),
          
          // Auto-Renew Status
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 140,
                  child: Text(
                    'Auto-Renew',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Icon(
                        user.willRenew ? Icons.check_circle : Icons.cancel,
                        color: user.willRenew ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        user.willRenew ? 'On' : 'Off / Cancelled',
                        style: TextStyle(
                            color: user.willRenew ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          const Text('Payment History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.id)
                .collection('billing_history')
                .orderBy('date', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      const Text('No payment history found'),
                    ],
                  ),
                );
              }

              final transactions = snapshot.data!.docs;

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: transactions.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final tx = transactions[index].data() as Map<String, dynamic>;
                  final date = _safeDate(tx['date']);
                  final amount = tx['amount'] ?? 0.0;
                  final status = tx['status'] ?? 'completed';

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.green.shade50,
                      child: const Icon(Icons.attach_money, color: Colors.green),
                    ),
                    title: Text(tx['description'] ?? 'Subscription Payment'),
                    subtitle: Text(date != null ? date.toString().split(' ')[0] : 'Unknown Date'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '\$${amount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            color: status == 'completed' ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

// User Profile Model moved to src/admin/lib/models/user_profile.dart

DateTime? _safeDate(dynamic val) {
  if (val is Timestamp) return val.toDate();
  if (val is String) return DateTime.tryParse(val);
  return null;
}

void _showQuickReplyPicker(BuildContext context, TextEditingController controller) {
  showDialog(
    context: context,
    builder: (ctx) => ValueListenableBuilder<bool>(
      valueListenable: TranslationService.instance.enabledNotifier,
      builder: (ctx, enabled, _) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.flash_on, color: Colors.amber),
              const SizedBox(width: 8),
              const Expanded(child: Text('Quick Replies')),
              IconButton(
                tooltip: enabled ? 'Disable Translator' : 'Enable Translator',
                icon: Icon(
                  Icons.translate,
                  color: enabled ? Colors.indigo : Colors.grey,
                ),
                onPressed: () async {
                  await TranslationService.instance.setEnabled(!enabled);
                },
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            height: 520,
            child: ListView.separated(
              itemCount: kQuickReplies.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reply = kQuickReplies[index];
                return ListTile(
                  visualDensity: VisualDensity.compact,
                  title: Text(reply.text, style: const TextStyle(fontSize: 13)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reply.category.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.indigo.shade300,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (enabled) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Translated preview:',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TranslatableText(
                          reply.text,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    final text = reply.text;
                    final selection = controller.selection;
                    if (selection.isValid && selection.start >= 0) {
                      final newText = controller.text.replaceRange(
                        selection.start,
                        selection.end,
                        text,
                      );
                      controller.value = TextEditingValue(
                        text: newText,
                        selection: TextSelection.collapsed(
                          offset: selection.start + text.length,
                        ),
                      );
                    } else {
                      if (controller.text.isNotEmpty) {
                        controller.text = '${controller.text}\n$text';
                      } else {
                        controller.text = text;
                      }
                    }
                    Navigator.pop(ctx);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ],
        );
      },
    ),
  );
}


