import 'package:flutter/material.dart';
import '../../services/lock_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class ActiveOperatorsCard extends StatelessWidget {
  const ActiveOperatorsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 300, // Fixed width suitable for a dashboard card
        height: 160, // Fixed height to match potential row height
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.admin_panel_settings, color: Colors.indigo, size: 20),
                SizedBox(width: 8),
                Text(
                  'Active Operators',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<AdminPresence>>(
                stream: LockService().getActiveOperators(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(fontSize: 10)));
                  }
                  
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(child: Text('No other operators online', style: TextStyle(color: Colors.grey)));
                  }

                  final admins = snapshot.data!;

                  return ListView.separated(
                    itemCount: admins.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final admin = admins[index];
                      // Determine status color
                      final isVeryRecent = DateTime.now().difference(admin.lastSeen).inMinutes < 2;
                      final statusColor = isVeryRecent ? Colors.green : Colors.orange;

                      return Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              admin.displayName,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            isVeryRecent ? 'Online' : timeago.format(admin.lastSeen, locale: 'en_short'),
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                        ],
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
}
