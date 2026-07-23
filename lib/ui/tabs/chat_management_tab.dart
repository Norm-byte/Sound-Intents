import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../models/community_group.dart';
import '../../repositories/group_repository.dart';

// No longer using local ChatRoom model, using CommunityGroup instead

class ChatManagementTab extends StatefulWidget {
  const ChatManagementTab({super.key});

  @override
  State<ChatManagementTab> createState() => _ChatManagementTabState();
}

class _ChatManagementTabState extends State<ChatManagementTab> {
  final GroupRepository _repository = GroupRepository();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _showGroupDialog({CommunityGroup? group}) {
    final nameController = TextEditingController(text: group?.name ?? '');
    final descController = TextEditingController(text: group?.description ?? '');
    String selectedIcon = group?.iconName ?? 'public';
    // Use a default color if new, or existing color
    Color selectedColor = group != null ? Color(group.colorValue) : Colors.blue; 
    // Default to true for new groups so they are visible immediately
    bool isPublished = group?.isPublished ?? true;
    bool isPaused = group?.isPaused ?? false;
    bool showLiveCounter = group?.showLiveCounter ?? false;
    
    // Helper to pick color (simplified - could be a color picker later)
    // For now we just use a dropdown of presets for simplicity
    final colors = [
        Colors.blue, Colors.pinkAccent, Colors.amber, Colors.orangeAccent, Colors.purple, Colors.teal, Colors.redAccent, Colors.indigo, Colors.cyan
    ];

    final icons = [
        'public', 'psychology', 'favorite', 'wb_sunny', 'nature', 'self_improvement', 'spa', 'music_note'
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(group == null ? 'Create Group' : 'Edit Group'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                   const Text('Group Details', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Group Name'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // Status Toggles
                  SwitchListTile(
                    title: const Text('Published'),
                    subtitle: const Text('Visible to users in the app'),
                    value: isPublished,
                    onChanged: (val) => setStateDialog(() => isPublished = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Paused (Maintenance)'),
                    subtitle: const Text('Lock new posts (read-only)'),
                    value: isPaused,
                    onChanged: (val) => setStateDialog(() => isPaused = val),
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Show Live Counter Overlay'),
                    subtitle: const Text('Display active-now user count in this room header'),
                    value: showLiveCounter,
                    onChanged: (val) => setStateDialog(() => showLiveCounter = val),
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 16),
                  const Text('Icon', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: icons.map((iconName) {
                       final isSelected = iconName == selectedIcon;
                       return InkWell(
                         onTap: () => setStateDialog(() => selectedIcon = iconName),
                         child: Container(
                           padding: const EdgeInsets.all(8),
                           decoration: BoxDecoration(
                             color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
                             border: isSelected ? Border.all(color: Colors.blue) : Border.all(color: Colors.grey.shade300),
                             borderRadius: BorderRadius.circular(8),
                           ),
                           child: Icon(
                             _getIconData(iconName), 
                             color: isSelected ? Colors.blue : Colors.grey,
                           ),
                         ),
                       );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('Color', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: colors.map((c) {
                        final isSelected = c.value == selectedColor.value;
                        return InkWell(
                            onTap: () => setStateDialog(() => selectedColor = c),
                            child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                    color: c,
                                    shape: BoxShape.circle,
                                    border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
                                ),
                            ),
                        );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isEmpty) return;
                  
                  final newGroup = CommunityGroup(
                    id: group?.id ?? '', // ID handled by Firestone on add
                    name: nameController.text,
                    description: descController.text,
                    iconName: selectedIcon,
                    colorValue: selectedColor.value,
                    memberCount: group?.memberCount ?? 0,
                    sortOrder: group?.sortOrder ?? 0,
                    isPublished: isPublished,
                    isPaused: isPaused,
                    showLiveCounter: showLiveCounter,
                  );

                  if (group == null) {
                    await _repository.addGroup(newGroup);
                  } else {
                    await _repository.updateGroup(newGroup);
                  }
                  
                  if (context.mounted) Navigator.pop(context);
                },
                child: Text(group == null ? 'Create' : 'Save'),
              ),
            ],
          );
        }
      ),
    );
  }
  
  IconData _getIconData(String name) {
      switch (name) {
        case 'public': return Icons.public;
        case 'psychology': return Icons.psychology;
        case 'favorite': return Icons.favorite;
        case 'wb_sunny': return Icons.wb_sunny;
        case 'nature': return Icons.nature;
        case 'self_improvement': return Icons.self_improvement;
        case 'spa': return Icons.spa;
        case 'music_note': return Icons.music_note;
        default: return Icons.group;
      }
  }

  void _deleteGroup(CommunityGroup group) {
      showDialog(
          context: context,
          builder: (context) => AlertDialog(
              title: Text('Delete ${group.name}?'),
              content: const Text('This cannot be undone. Users who joined this group will lose access to it.'),
              actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () async {
                          await _repository.deleteGroup(group.id);
                          if(context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Delete'),
                  ),
              ],
          ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('Community Forums', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const Spacer(),
                ElevatedButton.icon(
                    onPressed: () => _showGroupDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Forum'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: StreamBuilder<List<CommunityGroup>>(
                stream: _repository.getGroupsStream(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                  final groups = snapshot.data!;
                  
                  if (groups.isEmpty) {
                      return Center(
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                  const Icon(Icons.forum, size: 64, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text('No community forums found.'),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                      onPressed: () => _showGroupDialog(),
                                      child: const Text('Create First Forum'),
                                  )
                              ],
                          ),
                      );
                  }

                  return ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Color(group.colorValue).withOpacity(0.2),
                            child: Icon(_getIconData(group.iconName), color: Color(group.colorValue)),
                          ),
                          title: Row(
                            children: [
                              Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              // Member Count Badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.person, size: 12, color: Colors.blue),
                                    const SizedBox(width: 2),
                                    Text(
                                        '${group.memberCount}', 
                                        style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.bold)
                                    ),
                                  ],
                                ),
                              ),
                              if (group.showLiveCounter) ...[
                                const SizedBox(width: 6),
                                _roomLiveCountChip(group.id),
                              ],
                              const SizedBox(width: 8),
                              if (group.isPublished)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.green),
                                  ),
                                  child: const Text('LIVE', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                                )
                              else
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey),
                                  ),
                                  child: const Text('HIDDEN', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              if (group.isPaused) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber),
                                  ),
                                  child: const Text('PAUSED', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(group.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Publish Toggle
                              Tooltip(
                                message: group.isPublished ? 'Unpublish' : 'Publish',
                                child: IconButton(
                                  icon: Icon(
                                      group.isPublished ? Icons.visibility : Icons.visibility_off, 
                                      color: group.isPublished ? Colors.green : Colors.grey
                                  ),
                                  onPressed: () => _togglePublish(group),
                                ),
                              ),
                              // Pause Toggle
                              Tooltip(
                                message: group.showLiveCounter
                                    ? 'Hide Live Counter'
                                    : 'Show Live Counter',
                                child: IconButton(
                                  icon: Icon(
                                    Icons.query_stats,
                                    color: group.showLiveCounter
                                        ? Colors.lightGreen
                                        : Colors.grey,
                                  ),
                                  onPressed: () => _toggleLiveCounter(group),
                                ),
                              ),
                              Tooltip(
                                message: group.isPaused ? 'Resume' : 'Pause (Maintenance)',
                                child: IconButton(
                                  icon: Icon(
                                      group.isPaused ? Icons.pause_circle_filled : Icons.play_circle_filled, 
                                      color: group.isPaused ? Colors.amber : Colors.blueGrey
                                  ),
                                  onPressed: () => _togglePause(group),
                                ),
                              ),
                              const VerticalDivider(width: 24, thickness: 1),
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () => _showGroupDialog(group: group),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteGroup(group),
                              ),
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
        ),
      ),
    );
  }
  
  Future<void> _togglePublish(CommunityGroup group) async {
      await _repository.updateGroup(group.copyWith(isPublished: !group.isPublished));
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(group.isPublished ? 'Group Hidden' : 'Group Published'),
                  duration: const Duration(seconds: 1),
              )
          );
      }
  }

  Future<void> _togglePause(CommunityGroup group) async {
      final isPausing = !group.isPaused;
      
      // If pausing, confirm with admin (since it affects users)
      if (isPausing) {
          final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                  title: const Text('Pause Group?'),
                  content: const Text(
                      'Users will see this group as "Under Maintenance" and won\'t be able to post messages.\n\nThis overrides any automatic status.'
                  ),
                  actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Pause Group')),
                  ],
              ),
          );
          if (confirm != true) return;
      }

      await _repository.updateGroup(group.copyWith(isPaused: isPausing));
      if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(isPausing ? 'Group Paused' : 'Group Resumed'),
                  duration: const Duration(seconds: 1),
              )
          );
      }
  }

  Future<void> _toggleLiveCounter(CommunityGroup group) async {
    final next = !group.showLiveCounter;
    await _repository.updateGroup(group.copyWith(showLiveCounter: next));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'Live counter enabled for ${group.name}'
                : 'Live counter hidden for ${group.name}',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Widget _roomLiveCountChip(String roomId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('room_live_presence')
          .doc(roomId)
          .collection('sessions')
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final cutoff = DateTime.now().subtract(const Duration(seconds: 15));
        final liveCount = docs.where((doc) {
          final ts = doc.data()['lastSeenAt'];
          if (ts is! Timestamp) return false;
          return ts.toDate().isAfter(cutoff);
        }).length;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.groups_2, size: 12, color: Colors.green),
              const SizedBox(width: 2),
              Text(
                '$liveCount live',
                style: const TextStyle(
                  color: Colors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
