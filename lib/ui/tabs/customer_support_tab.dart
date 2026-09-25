import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/admin_user.dart';
import '../../utils/quick_replies.dart';
import '../../widgets/translatable_text.dart';

class CustomerSupportTab extends StatefulWidget {
  final AdminUser adminUser;

  const CustomerSupportTab({super.key, required this.adminUser});

  @override
  State<CustomerSupportTab> createState() => _CustomerSupportTabState();
}

class _CustomerSupportTabState extends State<CustomerSupportTab> {
  String _filter = 'open';
  String _query = '';
  String? _selectedUserId;
  final _replyController = TextEditingController();
  final _noteController = TextEditingController();
  bool _sending = false;
  bool _savingTicket = false;

  @override
  void dispose() {
    _replyController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _ensureTicket(DocumentSnapshot<Map<String, dynamic>> ticket) async {
    final data = ticket.data() ?? const <String, dynamic>{};
    if ((data['caseNumber'] as String?)?.isNotEmpty == true) return;
    final stamp = DateFormat('yyyyMMdd-HHmmss').format(DateTime.now().toUtc());
    await ticket.reference.set({
      'caseNumber': 'SUP-$stamp-${ticket.id.substring(0, 6).toUpperCase()}',
      'status': 'open',
      'priority': 'normal',
      'assignedAdminName': widget.adminUser.displayName,
      'assignedAdminId': widget.adminUser.uid,
      'openedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _selectTicket(DocumentSnapshot<Map<String, dynamic>> ticket) async {
    await _ensureTicket(ticket);
    // Opening a ticket clears its dashboard alert; resolving does the same below.
    await ticket.reference.set({'read': true}, SetOptions(merge: true));
    if (!mounted) return;
    setState(() => _selectedUserId = ticket.id);
  }

  Future<void> _updateTicket(Map<String, dynamic> fields) async {
    if (_selectedUserId == null) return;
    setState(() => _savingTicket = true);
    try {
      await FirebaseFirestore.instance.collection('support_inbox').doc(_selectedUserId).set({
        ...fields,
        if (fields['status'] == 'resolved') 'read': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => _savingTicket = false);
    }
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty || _selectedUserId == null) return;
    setState(() => _sending = true);
    try {
      final batch = FirebaseFirestore.instance.batch();
      final message = FirebaseFirestore.instance
          .collection('users')
          .doc(_selectedUserId)
          .collection('messages')
          .doc();
      batch.set(message, {
        'content': content,
        'sender': 'admin',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'title': 'Harmony Support',
      });
      batch.set(FirebaseFirestore.instance.collection('support_inbox').doc(_selectedUserId), {
        'content': content,
        'read': true,
        'status': 'waiting_on_customer',
        'lastReplyAt': FieldValue.serverTimestamp(),
        'lastReplyBy': widget.adminUser.displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      _replyController.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Reply failed: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _addInternalNote() async {
    final note = _noteController.text.trim();
    if (note.isEmpty || _selectedUserId == null) return;
    await FirebaseFirestore.instance.collection('support_inbox').doc(_selectedUserId).collection('internal_notes').add({
      'content': note,
      'author': widget.adminUser.displayName,
      'authorId': widget.adminUser.uid,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _noteController.clear();
  }

  Color _statusColor(String status) => switch (status) {
        'resolved' => Colors.green,
        'waiting_on_customer' => Colors.orange,
        _ => Colors.indigo,
      };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('support_inbox').orderBy('timestamp', descending: true).snapshots(),
      builder: (context, snapshot) {
        final tickets = (snapshot.data?.docs ?? const [])
            .where((ticket) {
              final data = ticket.data();
              final status = (data['status'] as String?) ?? 'open';
              final haystack = '${data['userName'] ?? ''} ${data['content'] ?? ''} ${data['caseNumber'] ?? ''}'.toLowerCase();
              return (_filter == 'all' || status == _filter) && haystack.contains(_query);
            })
            .toList();
        final selected = _selectedUserId == null ? null : snapshot.data?.docs.where((ticket) => ticket.id == _selectedUserId).cast<DocumentSnapshot<Map<String, dynamic>>?>().firstOrNull;
        return Row(children: [
          SizedBox(width: 370, child: _buildQueue(tickets)),
          const VerticalDivider(width: 1),
          Expanded(child: selected == null ? const Center(child: Text('Select a support ticket')) : _buildTicket(selected)),
        ]);
      },
    );
  }

  Widget _buildQueue(List<QueryDocumentSnapshot<Map<String, dynamic>>> tickets) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Customer Support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(onChanged: (value) => setState(() => _query = value.trim().toLowerCase()), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search customer or reference')),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'open', label: Text('Open')),
                ButtonSegment(value: 'waiting_on_customer', label: Text('Waiting')),
                ButtonSegment(value: 'resolved', label: Text('Resolved')),
                ButtonSegment(value: 'all', label: Text('All')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) => setState(() => _filter = value.first),
            ),
          ]),
        ),
        Expanded(child: ListView.separated(
          itemCount: tickets.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final ticket = tickets[index];
            final data = ticket.data();
            final status = (data['status'] as String?) ?? 'open';
            return ListTile(
              selected: ticket.id == _selectedUserId,
              leading: CircleAvatar(backgroundColor: _statusColor(status).withValues(alpha: 0.15), child: Icon(Icons.support_agent, color: _statusColor(status))),
              title: Text((data['userName'] as String?)?.isNotEmpty == true ? data['userName'] as String : 'Customer'),
              subtitle: Text('${data['caseNumber'] ?? 'Unassigned reference'}\n${data['content'] ?? ''}', maxLines: 3, overflow: TextOverflow.ellipsis),
              isThreeLine: true,
              onTap: () => _selectTicket(ticket),
            );
          },
        )),
      ]);

  Widget _buildTicket(DocumentSnapshot<Map<String, dynamic>> ticket) {
    final data = ticket.data()!;
    final status = (data['status'] as String?) ?? 'open';
    return Column(children: [
      Container(padding: const EdgeInsets.all(16), color: Colors.white, child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data['userName'] ?? 'Customer', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text(data['caseNumber'] ?? 'Creating reference...', style: TextStyle(color: Colors.grey.shade600)),
        ])),
        DropdownButton<String>(value: status, items: const [
          DropdownMenuItem(value: 'open', child: Text('Open')),
          DropdownMenuItem(value: 'waiting_on_customer', child: Text('Waiting on customer')),
          DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
        ], onChanged: _savingTicket ? null : (value) { if (value != null) _updateTicket({'status': value}); }),
        const SizedBox(width: 12),
        FilledButton.icon(onPressed: _savingTicket ? null : () => _updateTicket({'assignedAdminName': widget.adminUser.displayName, 'assignedAdminId': widget.adminUser.uid}), icon: const Icon(Icons.person_pin), label: const Text('Assign to me')),
      ])),
      Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(ticket.id).collection('messages').orderBy('timestamp').snapshots(),
        builder: (context, messages) => ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: messages.data?.docs.length ?? 0,
          itemBuilder: (context, index) {
            final message = messages.data!.docs[index].data();
            final fromAdmin = message['sender'] == 'admin';
            return Align(alignment: fromAdmin ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12), constraints: const BoxConstraints(maxWidth: 560),
              decoration: BoxDecoration(color: fromAdmin ? Colors.indigo.shade50 : Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: TranslatableText(message['content'] ?? ''),
            ));
          },
        ),
      )),
      _buildComposer(ticket.id),
    ]);
  }

  Widget _buildComposer(String userId) => Container(
    padding: const EdgeInsets.all(16), color: Colors.white,
    child: Column(children: [
      Row(children: [
        Expanded(child: TextField(controller: _replyController, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Reply to customer', border: OutlineInputBorder()))),
        const SizedBox(width: 10),
        IconButton(tooltip: 'Quick reply', onPressed: () async {
          final selected = await showDialog<QuickReply>(context: context, builder: (context) => SimpleDialog(title: const Text('Quick replies'), children: kQuickReplies.map((reply) => SimpleDialogOption(onPressed: () => Navigator.pop(context, reply), child: Text('${reply.category}: ${reply.text}'))).toList()));
          if (selected != null) _replyController.text = selected.text;
        }, icon: const Icon(Icons.bolt)),
        IconButton.filled(onPressed: _sending ? null : _sendReply, icon: _sending ? const CircularProgressIndicator() : const Icon(Icons.send)),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _noteController, onSubmitted: (_) => _addInternalNote(), decoration: InputDecoration(labelText: 'Internal note (not sent to customer)', suffixIcon: IconButton(onPressed: _addInternalNote, icon: const Icon(Icons.add_comment_outlined)), border: const OutlineInputBorder())),
    ]),
  );
}