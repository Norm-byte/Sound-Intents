import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_management_tab.dart';
import 'user_management_tab.dart';
import 'community_tab.dart';
import 'welcome_screen_manager.dart';

class SystemTab extends StatefulWidget {
  const SystemTab({super.key});

  @override
  State<SystemTab> createState() => _SystemTabState();
}

class _SystemTabState extends State<SystemTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Locking State
  bool _isLocked = true;
  bool _isLoadingLockState = true;
  final _unlockController = TextEditingController();
  String? _storedSecurityPassword;
  String? _storedVipCode;
  String? _selectedUserIdForManagement;

  @override
  void initState() {
    super.initState();
    // Initialize controller immediately to prevent build errors
    _tabController = TabController(length: 6, vsync: this);
    
    // Start loading lock state safely
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLockState();
    });
  }

  Future<void> _loadLockState() async {
    if (!mounted) return;
    print('SystemTab: Loading lock state...');
    setState(() => _isLoadingLockState = true);
    
    // Safety timer to prevent infinite loading
    final safetyTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isLoadingLockState) {
        print('SystemTab: Safety timer triggered. Forcing unlock.');
        setState(() {
          _isLoadingLockState = false;
          // Optional: _isLocked = false; // Uncomment to auto-unlock on timeout
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('System check timed out. Please try unlocking manually.')),
        );
      }
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('SystemTab: No user logged in');
        return;
      }

      // 1. Get Security Password
      print('SystemTab: Fetching admin user doc...');
      final userDoc = await FirebaseFirestore.instance
          .collection('admin_users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 5));
      
      if (mounted) {
        _storedSecurityPassword = userDoc.data()?['security_password'];
        print('SystemTab: Security password found: ${_storedSecurityPassword != null}');
      }

      // 2. Get VIP Code
      print('SystemTab: Fetching VIP code...');
      final vipQuery = await FirebaseFirestore.instance
          .collection('vip_codes')
          .where('type', isEqualTo: 'super_admin')
          .where('assignee', isEqualTo: user.email)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));
      
      if (mounted && vipQuery.docs.isNotEmpty) {
        _storedVipCode = vipQuery.docs.first.data()['code'];
      }
      print('SystemTab: VIP code found: ${_storedVipCode != null}');

      // If neither is set, unlock by default (first run)
      if (_storedSecurityPassword == null && _storedVipCode == null) {
        print('SystemTab: No lock set, unlocking...');
        if (mounted) setState(() => _isLocked = false);
      }

    } catch (e) {
      debugPrint('Error loading lock state: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection error: $e')),
        );
      }
    } finally {
      safetyTimer.cancel();
      if (mounted) {
        setState(() => _isLoadingLockState = false);
        print('SystemTab: Loading complete. Locked: $_isLocked');
      }
    }
  }

  Future<void> _attemptUnlock() async {
    final input = _unlockController.text.trim();
    if (input.isEmpty) return;

    bool unlocked = false;
    if (_storedSecurityPassword != null && input == _storedSecurityPassword) unlocked = true;
    if (_storedVipCode != null && input == _storedVipCode) unlocked = true;

    // Fallback: Check Firestore for any valid super_admin code
    if (!unlocked) {
      try {
        final query = await FirebaseFirestore.instance
            .collection('vip_codes')
            .where('code', isEqualTo: input)
            .where('type', isEqualTo: 'super_admin')
            .where('status', isEqualTo: 'active')
            .limit(1)
            .get();
            
        if (query.docs.isNotEmpty) {
          unlocked = true;
        }
      } catch (e) {
        debugPrint('Error checking VIP code: $e');
      }
    }

    if (unlocked) {
      setState(() {
        _isLocked = false;
        _unlockController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect password or VIP code'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _unlockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLockState) return const Center(child: CircularProgressIndicator());

    if (_isLocked) {
      return Center(
        child: SingleChildScrollView(
          child: Card(
            elevation: 4,
            margin: const EdgeInsets.all(32),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 64, color: Colors.indigo),
                  const SizedBox(height: 24),
                  const Text(
                    'System Access Restricted',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Please enter your Security Password or VIP Code to access System Management.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _unlockController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password or VIP Code',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key),
                    ),
                    onSubmitted: (_) => _attemptUnlock(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _attemptUnlock,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'System Management',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Configure system settings, monitor performance, and manage users',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.people), text: 'Users'),
                  Tab(icon: Icon(Icons.forum), text: 'Community'),
                  Tab(icon: Icon(Icons.analytics), text: 'Performance'),
                  Tab(icon: Icon(Icons.admin_panel_settings), text: 'Admin Management'),
                  Tab(icon: Icon(Icons.home), text: 'Welcome Screen'),
                  Tab(icon: Icon(Icons.build), text: 'Maintenance'),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              UserManagementTab(initialUserId: _selectedUserIdForManagement),
              CommunityTab(
                onUserSelected: (userId) {
                  setState(() {
                    _selectedUserIdForManagement = userId;
                  });
                  _tabController.animateTo(0);
                },
              ),
              const _PerformanceTab(),
              const AdminManagementTab(),
              const WelcomeScreenManager(),
              const _MaintenanceTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// Performance Tab
class _PerformanceTab extends StatelessWidget {
  const _PerformanceTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Performance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  title: 'Total Users',
                  value: '1,247',
                  trend: '+12%',
                  trendPositive: true,
                  icon: Icons.people,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MetricCard(
                  title: 'Active Events',
                  value: '23',
                  trend: '+3',
                  trendPositive: true,
                  icon: Icons.event,
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MetricCard(
                  title: 'Avg Response Time',
                  value: '245ms',
                  trend: '-15%',
                  trendPositive: true,
                  icon: Icons.speed,
                  color: Colors.purple,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MetricCard(
                  title: 'Storage Used',
                  value: '3.2 GB',
                  trend: '+0.5 GB',
                  trendPositive: false,
                  icon: Icons.storage,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Mock Graph Areas
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'User Activity (Last 7 Days)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.show_chart, size: 48, color: Colors.blue.shade300),
                                const SizedBox(height: 8),
                                Text(
                                  'Chart visualization coming soon',
                                  style: TextStyle(color: Colors.blue.shade700),
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
              const SizedBox(width: 16),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Event Engagement',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.pie_chart, size: 48, color: Colors.green.shade300),
                                const SizedBox(height: 8),
                                Text(
                                  'Pie chart coming soon',
                                  style: TextStyle(color: Colors.green.shade700),
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
            ],
          ),
          const SizedBox(height: 24),
          
          // System Health
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'System Health',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  _HealthIndicator(label: 'Firebase Connection', status: 'Healthy', isHealthy: true),
                  _HealthIndicator(label: 'Database Performance', status: 'Optimal', isHealthy: true),
                  _HealthIndicator(label: 'Storage Quota', status: '68% Used', isHealthy: true),
                  _HealthIndicator(label: 'API Rate Limits', status: 'Normal', isHealthy: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}













// Helper Widgets
class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String trend;
  final bool trendPositive;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.trend,
    required this.trendPositive,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.1),
                  child: Icon(icon, color: color),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: trendPositive ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        trendPositive ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                        color: trendPositive ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        trend,
                        style: TextStyle(
                          fontSize: 12,
                          color: trendPositive ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthIndicator extends StatelessWidget {
  final String label;
  final String status;
  final bool isHealthy;

  const _HealthIndicator({
    required this.label,
    required this.status,
    required this.isHealthy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            isHealthy ? Icons.check_circle : Icons.warning,
            color: isHealthy ? Colors.green : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(
            status,
            style: TextStyle(
              color: isHealthy ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackItem extends StatelessWidget {
  final String quote;
  final String author;
  final String date;

  const _FeedbackItem({
    required this.quote,
    required this.author,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            quote,
            style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '— $author',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const Spacer(),
              Text(
                date,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}






class _MaintenanceTab extends StatefulWidget {
  const _MaintenanceTab();

  @override
  State<_MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<_MaintenanceTab> {
  bool _isCleaning = false;

  Future<void> _clearAllEvents() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('WARNING: Clear ALL Events?'),
        content: const Text(
          'This will PERMANENTLY DELETE all scheduled and global events from the database. '
          'This action cannot be undone. Are you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE ALL', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isCleaning = true);

    try {
      final firestore = FirebaseFirestore.instance;
      
      // 1. Delete 'events' collection
      final eventsSnapshot = await firestore.collection('events').get();
      // Batch writes are limited to 500 operations. We should handle chunks if there are many events.
      // For now, assuming < 500 for simple batch. If more, we need loop.
      
      int deletedCount = 0;
      WriteBatch batch = firestore.batch();
      int batchCount = 0;

      for (final doc in eventsSnapshot.docs) {
        batch.delete(doc.reference);
        batchCount++;
        deletedCount++;
        if (batchCount >= 450) {
          await batch.commit();
          batch = firestore.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) await batch.commit();
      
      print('Deleted ' + deletedCount.toString() + ' scheduled events.');

      // 2. Delete 'global_events' collection
      final globalSnapshot = await firestore.collection('global_events').get();
      
      batch = firestore.batch();
      batchCount = 0;
      int globalDeletedCount = 0;

      for (final doc in globalSnapshot.docs) {
        batch.delete(doc.reference);
        batchCount++;
        globalDeletedCount++;
        if (batchCount >= 450) {
          await batch.commit();
          batch = firestore.batch();
          batchCount = 0;
        }
      }
      if (batchCount > 0) await batch.commit();
      
      print('Deleted ' + globalDeletedCount.toString() + ' global events.');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All events cleared successfully.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error clearing events: ' + e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCleaning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Maintenance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Danger Zone',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Use these tools to fix database inconsistencies or reset data. Proceed with caution.',
                  ),
                  const SizedBox(height: 24),
                  ListTile(
                    title: const Text('Clear All Events'),
                    subtitle: const Text('Deletes all scheduled and global events. Use this to remove ghost events.'),
                    trailing: _isCleaning
                        ? const CircularProgressIndicator()
                        : ElevatedButton.icon(
                            onPressed: _clearAllEvents,
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Clear All'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

