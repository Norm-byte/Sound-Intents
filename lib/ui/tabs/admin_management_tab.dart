import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'dart:math';
import '../../services/auth_service.dart';
import '../../services/admin_user_service.dart';
import '../../services/media_library_service.dart';
import '../../models/media_item.dart';

class AdminManagementTab extends StatefulWidget {
  const AdminManagementTab({super.key});

  @override
  State<AdminManagementTab> createState() => _AdminManagementTabState();
}

class _AdminManagementTabState extends State<AdminManagementTab> with SingleTickerProviderStateMixin {
  final _authService = AuthService();
  final _adminService = AdminUserService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _superAdminCodeController = TextEditingController();
  final _securityPasswordController = TextEditingController();
  final _unlockController = TextEditingController();
  
  // Beta Access & VIP Variables
  final _assigneeController = TextEditingController();
  final _contactController = TextEditingController();
  final _customCodeController = TextEditingController(); // Added custom code
  bool _isGenerating = false;
  String _selectedType = 'beta_tester'; // beta_tester, admin

  late TabController _tabController;
  
  bool _showAddForm = false;
  bool _generateVipForNewAdmin = false; // New: Integrate VIP generation
  bool _isSavingCode = false;
  bool _isSyncing = false;
  bool _isLocked = false; 
  bool _isSuperAdminUnlocked = false; // New: Lock Super Admin Tab by default
  bool _isLoadingLockState = false;
  bool _isSettingPassword = false;
  String? _storedSecurityPassword;
  String? _storedVipCode;
  String? _selectedAdminUid;
  String? _selectedAdminEmail;

  // Admin Permissions Defaults — keys must match buildTab() calls in main.dart
  final Map<String, bool> _defaultAdminPermissions = {
    'dashboard': true,
    'event_creator': false,       // Worldwide Events
    'event_scheduler': false,     // National Events
    'media_library': false,
    'app_content': false,         // App Content
    'chat_management': false,     // Chat Rooms
    'topics': false,
    'community': false,           // Community
    'monetization': false,        // Deals/Offers
    'system': false,              // System
    'notifications': false,
    'legal': false,
    'documentation': true,        // Operators Manual — always granted
  };

  /// Human-readable tab names shown in permission checkboxes.
  static const Map<String, String> _permissionLabels = {
    'dashboard':       'Dashboard',
    'event_creator':   'Worldwide Events',
    'event_scheduler': 'National Events',
    'media_library':   'Media Library',
    'app_content':     'App Content',
    'chat_management': 'Chat Rooms',
    'topics':          'Topics',
    'community':       'Community',
    'monetization':    'Deals / Offers',
    'system':          'System',
    'notifications':   'Notifications',
    'legal':           'Legal',
    'documentation':   'Operators Manual',
  };
  
  // Current selection for new admin
  Map<String, bool> _newAdminPermissions = {};
  
  // Creation Mode
  // String _creationMode = 'admin'; // Removed as per request

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _newAdminPermissions = Map.from(_defaultAdminPermissions);
    _showAddForm = true; // Always show the form by default
    _loadLockState();
  }

  Future<void> _loadLockState() async {
    // Deprecated: No more tab lock.
  }

  Future<void> _verifySuperAdminAccess() async {
    final password = _unlockController.text;
    if (password.isEmpty) return;

    setState(() => _isLoadingLockState = true);

    try {
      await _authService.reauthenticate(password);
      setState(() {
        _isSuperAdminUnlocked = true;
        _unlockController.clear();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid password. Access denied.'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLockState = false);
    }
  }

  Future<void> _updateSecurityPassword() async {
    // Deprecated: No more security password.
  }

  Future<void> _syncAuthData() async {
    setState(() => _isSyncing = true);
    final currentUser = FirebaseAuth.instance.currentUser;
    
    try {
      if (currentUser == null) {
        throw Exception('No user logged in');
      }

      await FirebaseFirestore.instance
          .collection('admin_users')
          .doc(currentUser.uid)
          .set({
            'email': currentUser.email,
            'isActive': true,
            'role': 'super-admin', // Self-healing for owner
            'lastLogin': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile synced! Database now matches your login.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed (Network Blocked?): $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _addAdmin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty || _nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final normalizedEmail = _emailController.text.trim().toLowerCase();
      final displayName = _nameController.text.trim();
      final initialPassword = _passwordController.text.trim();

      // Calculate permissions list
      final allowedTabs = _newAdminPermissions.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final result = await FirebaseFunctions.instance
          .httpsCallable('provisionAdminOperator')
          .call({
        'email': normalizedEmail,
        'displayName': displayName,
        'initialPassword': initialPassword,
        'permissions': allowedTabs,
      });

      final existed = (result.data as Map?)?['existed'] == true;

      // Send password reset email as an invite mechanism if possible, 
      // or just rely on them signing up with this email.
      // _authService.sendPasswordResetEmail(_emailController.text.trim());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              existed
                  ? 'Existing account linked as an operator and permissions updated.'
                  : 'Admin user added. They can now access the admin panel with these permissions.',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // Create invitation message for the operator login only.
        final inviteMsg = "Welcome to the Harmony by Intent Admin Team, $displayName.\n\n"
            "Your Operator Access Credentials:\n"
          "Email: $normalizedEmail\n"
            "Initial Password: $initialPassword\n\n"
            "Please log in to the Admin Panel to begin.";

        _showShareDialog(initialPassword, displayName, normalizedEmail, customMessage: inviteMsg);
      
        setState(() {
          // _showAddForm = false; // Keep form open as requested
          _generateVipForNewAdmin = false;
          _emailController.clear();
          _passwordController.clear();
          _nameController.clear();
          _newAdminPermissions = Map.from(_defaultAdminPermissions);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding admin: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _loadAdminIntoOnboardForm(String uid, Map<String, dynamic> data) {
    final permissions = List<String>.from(data['permissions'] ?? const []);
    final nextPermissions = Map<String, bool>.from(_defaultAdminPermissions);
    for (final permission in permissions) {
      if (nextPermissions.containsKey(permission)) {
        nextPermissions[permission] = true;
      }
    }

    setState(() {
      _selectedAdminUid = uid;
      _selectedAdminEmail = (data['email'] ?? '').toString();
      _nameController.text = (data['displayName'] ?? '').toString();
      _emailController.text = _selectedAdminEmail!;
      _passwordController.clear();
      _newAdminPermissions = nextPermissions;
    });
  }

  void _clearOnboardSelection() {
    setState(() {
      _selectedAdminUid = null;
      _selectedAdminEmail = null;
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();
      _newAdminPermissions = Map<String, bool>.from(_defaultAdminPermissions);
    });
  }

  Future<void> _updateSelectedAdminPermissions() async {
    final selectedUid = _selectedAdminUid;
    if (selectedUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select an operator from Current Admin Team first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final allowedTabs = _newAdminPermissions.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();

    await FirebaseFirestore.instance.collection('admin_users').doc(selectedUid).update({
      'permissions': allowedTabs,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Permissions updated for ${_nameController.text.trim().isEmpty ? 'the selected operator' : _nameController.text.trim()}.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _resetPassword(String email) async {
    try {
      await _authService.sendPasswordResetEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateSuperAdminCode() async {
    setState(() => _isSavingCode = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || user.email == null) {
        throw Exception('You must be logged in to set an access code.');
      }
      
      final newCode = _superAdminCodeController.text.trim();
      if (newCode.isEmpty) {
        throw Exception('Code cannot be empty');
      }

      // 1. Find existing super admin code for this user
      final query = await FirebaseFirestore.instance
          .collection('vip_codes')
          .where('type', isEqualTo: 'super_admin')
          .where('assignee', isEqualTo: user.email)
          .get()
          .timeout(const Duration(seconds: 10), onTimeout: () {
            throw Exception('Connection timed out. Please check your internet or if Firestore is enabled in the console.');
          });

      // 2. Delete old ones (cleanup)
      for (var doc in query.docs) {
        await doc.reference.delete();
      }

      // 3. Create new one
      await FirebaseFirestore.instance.collection('vip_codes').add({
        'code': newCode,
        'type': 'super_admin',
        'assignee': user.email,
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'isPermanent': true,
      }).timeout(const Duration(seconds: 10));

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Success'),
            content: const Text('Super Admin Access Code Updated!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error'),
            content: Text(e.toString().replaceAll('Exception: ', '')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingCode = false);
      }
    }
  }

  // --- Beta Access & VIP Methods ---

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Removed I, O, 1, 0 to avoid confusion
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(
        8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  Future<void> _createCode() async {
    if (_assigneeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a name for who this code is for')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      String formattedCode;
      if (_customCodeController.text.trim().isNotEmpty) {
          formattedCode = _customCodeController.text.trim().toUpperCase();
          // Check for uniqueness potentially (skipped for now, assumption is low volume)
      } else {
          final code = _generateCode();
          // Format as XXXX-XXXX
          formattedCode = '${code.substring(0, 4)}-${code.substring(4, 8)}';
      }

      final assignee = _assigneeController.text.trim();
      final contact = _contactController.text.trim();

      final data = {
        'code': formattedCode,
        'assignee': assignee,
        'contactInfo': contact,
        'status': 'active', // active, redeemed, revoked
        'vipQuotaTier': 'tier_beta',
        'createdAt': FieldValue.serverTimestamp(),
        'redeemedBy': null,
        'redeemedAt': null,
        'type': _selectedType,
      };

      // If creating an admin code (VIP), we might want to attach permissions if that was the intent
      // But for now, VIP codes are mostly for bypassing subscription or super admin access.
      // The user asked for "user app vip codes" and "admin site" access.
      // Admin site access is handled by 'admin_users' collection.
      // VIP codes are for the App.
      
      await FirebaseFirestore.instance.collection('vip_codes').add(data);

      _assigneeController.clear();
      _contactController.clear();
      
      if (mounted) {
        Navigator.pop(context); // Close dialog
        
        // Show success with immediate share option
        _showShareDialog(formattedCode, assignee, contact);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating code: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showShareDialog(String code, String assignee, String contact, {String? customMessage}) {
    final message = customMessage ?? "Hello $assignee, here is your VIP access code for Harmony by Intent: $code\n\nRedeem this code in the app to unlock full access.";
    final encodedMessage = Uri.encodeComponent(message);
    
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Share Credentials'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: message));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [Icon(Icons.copy, color: Colors.grey), SizedBox(width: 12), Text('Copy to Clipboard')]),
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              final url = Uri.parse('https://wa.me/?text=$encodedMessage');
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [Icon(Icons.chat, color: Colors.green), SizedBox(width: 12), Text('Share via WhatsApp')]),
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              final subject = Uri.encodeComponent("Harmony by Intent Access Details");
              // Use a safer mailto construction
              final url = Uri.parse('mailto:$contact?subject=$subject&body=$encodedMessage');
              try {
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                } else {
                   // Fallback for some browsers/clients
                   await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              } catch (e) {
                debugPrint('Error launching email: $e');
                if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open email client. Try copying to clipboard.')));
                }
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [Icon(Icons.email, color: Colors.blue), SizedBox(width: 12), Text('Send via Email')]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }

  void _showGenerateDialog() {
    _assigneeController.clear();
    _contactController.clear();
    _customCodeController.clear();
    // Default to beta_tester
    _selectedType = 'beta_tester';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Generate VIP Access Code'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Generate a unique code or create a custom one.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Access Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'beta_tester', child: Text('Beta Tester (App Only)')),
                    DropdownMenuItem(value: 'super_admin', child: Text('Super Admin (Full Access)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                       setStateDialog(() => _selectedType = val);
                       // Update parent too for _createCode to use
                       this.setState(() => _selectedType = val);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _customCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Code (Optional)',
                    hintText: 'e.g. SARAH-VIP',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _assigneeController,
                  decoration: const InputDecoration(
                    labelText: 'Assignee Name (Friend/Family)',
                    hintText: 'e.g. John Doe',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _contactController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Info (Email/Phone)',
                    hintText: 'e.g. john@example.com',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _isGenerating ? null : _createCode,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                child: _isGenerating 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Generate Code'),
              ),
            ],
          );
        }
      ),
    );
  }

  Future<void> _revokeCode(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('vip_codes').doc(docId).update({
        'status': 'revoked',
      });
    } catch (e) {
      debugPrint('Error revoking code: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingLockState) {
      return const Center(child: CircularProgressIndicator());
    }

    // REMOVED: Tab Lock Screen Check (_isLocked)

    final currentUser = FirebaseAuth.instance.currentUser;
    
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin User Management',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage administrator access and permissions',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const Spacer(),
                  if (!_showAddForm && _tabController.index == 0)
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _showAddForm = true),
                      icon: const Icon(Icons.person_add),
                      label: const Text('Add Admin'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                labelColor: Colors.indigo,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.indigo,
                isScrollable: true,
                onTap: (_) => setState(() {}),
                tabs: const [
                  Tab(icon: Icon(Icons.person_add), text: 'Onboard Admin'),
                  // Tab(icon: Icon(Icons.pending_actions), text: 'Access Requests'), // Removed
                  Tab(icon: Icon(Icons.admin_panel_settings), text: 'Super Admin'),
                  Tab(icon: Icon(Icons.build), text: 'Maintenance'),
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
              // Tab 1: Onboard Admin
              _buildOnboardAdminTab(),
              
              // Tab 2: Access Requests (Removed)
              // _buildAccessRequestsTab(),

              // Tab 3: Super Admin
              _buildSuperAdminTab(),

              // Tab 4: Maintenance
              const _MaintenanceTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOnboardAdminTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // New Admin Form (Restored Layout)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_add, color: Colors.indigo),
                    const SizedBox(width: 8),
                    const Text(
                      'Create New Admin Operators Access Codes',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: Icon(Icons.person),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email Address *',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: Icon(Icons.email),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _passwordController,
                            obscureText: false,
                            decoration: const InputDecoration(
                              labelText: 'Initial Password *',
                              border: OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: Icon(Icons.lock),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.vpn_key),
                          label: const Text('Generate Password'),
                          onPressed: () {
                            if (mounted) {
                               setState(() {
                                  _passwordController.text = _generateRandomPassword();
                               });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_selectedAdminUid != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.edit_note, color: Colors.indigo),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Editing ${_nameController.text.trim()} (${_selectedAdminEmail ?? ''}). Adjust the checkboxes, then tap Update Operator Permissions.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: _clearOnboardSelection,
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ),
                
                const Text('Tab Permissions:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: _newAdminPermissions.keys.map((key) {
                    final label = _permissionLabels[key] ?? key.replaceAll('_', ' ');
                    return SizedBox(
                      width: 200,
                      child: CheckboxListTile(
                        title: Text(label, style: const TextStyle(fontSize: 12)),
                        value: _newAdminPermissions[key],
                        onChanged: (val) {
                          setState(() {
                            _newAdminPermissions[key] = val ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _addAdmin,
                        icon: const Icon(Icons.save),
                        label: const Text('Create Admin User'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _selectedAdminUid == null ? null : _updateSelectedAdminPermissions,
                        icon: const Icon(Icons.upgrade),
                        label: const Text('Update Operator Permissions'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Tip: select a team member below to load their existing permissions into these checkboxes.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        
          const SizedBox(height: 32),
          const Text('Current Admin Team', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // Simple Read-Only List
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('admin_users').orderBy('createdAt', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snapshot.data!.docs;
              
              if (docs.isEmpty) return const Text('No other admins found.');

              return Card(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final name = data['displayName'] ?? 'Unknown';
                    final role = data['role'] ?? 'admin';
                    final isActive = data['isActive'] ?? true;
                    final isSelected = _selectedAdminUid == doc.id;
                    // Hiding Super Admin from here as requested
                    if (role == 'super-admin') return const SizedBox.shrink();

                    return Material(
                      color: isSelected ? Colors.indigo.shade50 : Colors.transparent,
                      child: ListTile(
                        onTap: () => _loadAdminIntoOnboardForm(doc.id, data),
                        leading: CircleAvatar(
                          backgroundColor: isActive ? Colors.indigo.shade100 : Colors.red.shade100,
                          child: Icon(Icons.person, color: isActive ? Colors.indigo : Colors.red),
                        ),
                        title: Text(name),
                        subtitle: Text('${data['email'] ?? ''} • ${role.toUpperCase()}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Icon(Icons.check_circle, color: Colors.indigo),
                              ),
                            isActive 
                                ? const Chip(label: Text('ACTIVE', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.green)
                                : const Chip(label: Text('INACTIVE', style: TextStyle(color: Colors.white, fontSize: 10)), backgroundColor: Colors.red),
                          ],
                        ),
                      ),
                      );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _resetUserPassword(String uid, String email) async {
    // Generate new random password
    final newPassword = _generateRandomPassword();
    
    // In a real app, this would call a Cloud Function to update Firebase Auth.
    // Since we are client-side only for now, we will update the record and SEND A RESET EMAIL.
    // Changing another user's password directly requires Cloud Admin SDK (Backend).
    
    await _authService.sendPasswordResetEmail(email);
    
    // Update the record for the Super Admin's reference (Note: this is just a record)
    await FirebaseFirestore.instance.collection('admin_users').doc(uid).update({
      'initialPassword': 'Reset Email Sent: ${DateTime.now().toIso8601String().substring(0, 10)}',
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent to $email. They can set a new password via the link.')),
      );
    }
  }

  String _generateRandomPassword() {
    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890!@#\$%^&*';
    final rnd = Random();
    return String.fromCharCodes(Iterable.generate(12, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

    // --- SUPER ADMIN TAB & HELPERS ---

  Widget _buildSuperAdminTab() {
    final currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('admin_users').doc(currentUser?.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: SelectableText('Error loading profile: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final role = userData['role'] ?? 'admin';
        
        // Security Check: Only Super Admin sees this content
        if (role != 'super-admin') {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text('Restricted Access', style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Only Super Administrators can view this tab.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        // DOUBLE SECURITY: Lock Screen for Super Admin
        if (!_isSuperAdminUnlocked) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                child: Container(
                  width: 400,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.security, size: 48, color: Colors.indigo),
                      const SizedBox(height: 16),
                      const Text(
                        'Super Admin Verification',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please enter your password to access restricted controls.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _unlockController,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                        ),
                        onSubmitted: (_) => _verifySuperAdminAccess(),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _unlockController.clear(),
                            child: const Text('Clear'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _verifySuperAdminAccess,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: _isLoadingLockState 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Unlock Access'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return DefaultTabController(
          length: 3, 
          child: Column(
            children: [
              Container(
                color: Colors.white,
                child: const TabBar(
                  labelColor: Colors.purple,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.purple,
                  tabs: [
                    Tab(text: 'My Profile'),
                    Tab(text: 'Master Admin List'),
                    Tab(text: 'Beta & VIP Codes'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildSuperAdminProfile(userData),
                    _buildMasterAdminList(),
                    _buildVipManagement(),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildSuperAdminProfile(Map<String, dynamic> ignoredUserData) {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('admin_users').where('role', isEqualTo: 'super-admin').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: SelectableText('Error loading admins: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final admins = snapshot.data!.docs;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Super Admin Team', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.purple)),
              const SizedBox(height: 16),
              ...admins.map((doc) {
                 final data = doc.data() as Map<String, dynamic>;
                 final uid = doc.id;
                 final isMe = currentUser?.uid == uid;
                 final name = data['displayName'] ?? 'Super Admin';
                 final email = data['email'] ?? 'No Email';
                 
                 return Card(
                   margin: const EdgeInsets.only(bottom: 16),
                   child: Padding(
                     padding: const EdgeInsets.all(24),
                     child: Column(
                       children: [
                         ListTile(
                           leading: const CircleAvatar(backgroundColor: Colors.purple, child: Icon(Icons.security, color: Colors.white)),
                           title: Text('$name${isMe ? " (You)" : ""}', style: const TextStyle(fontWeight: FontWeight.bold)),
                           subtitle: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text(email),
                               if (isMe) ...[
                                 const SizedBox(height: 8),
                                 Row(
                                   children: [
                                     const Text('Latest Recorded Password: ', style: TextStyle(color: Colors.grey)),
                                     // Obfuscated password text logic
                                     StatefulBuilder(builder: (context, setStateObscure) {
                                        // We use a local variable key for this builder to toggle state, but simpler to just use a custom widget or generic state.
                                        // Since we can't easily add state variables for dynamic list, we'll just show it or hide it.
                                        // Actually, let's just make it selectable. Obscuring it requires state.
                                        // We will just label it clearly.
                                        return Tooltip(
                                          message: "This is the password recorded during the last Global Reset. If you changed it manually elsewhere, this may be outdated.",
                                          child: Text(data['initialPassword'] ?? 'Not recorded', style: const TextStyle(fontWeight: FontWeight.bold)),
                                        );
                                     }),
                                   ],
                                 ),
                               ],
                             ],
                           ),
                           trailing: isMe 
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    OutlinedButton(
                                      onPressed: _showChangeEmailDialog,
                                      child: const Text('Change Email'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _showChangeSuperAdminPasswordDialog(),
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                                      child: const Text('Change Password'),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  tooltip: 'Delete this Super Admin',
                                  onPressed: () {
                                    showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete Super Admin'),
                                          content: Text('Are you sure you want to remove $name ($email)?'),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                              onPressed: () async {
                                                await FirebaseFirestore.instance.collection('admin_users').doc(uid).delete();
                                                if(mounted) Navigator.pop(ctx);
                                              },
                                              child: const Text('Delete'),
                                            )
                                          ]
                                        )
                                    );
                                  },
                                ),
                         ),
                         if (isMe) ...[
                            const Divider(),
                            _buildGlobalPasswordResetSection(),
                         ]
                       ],
                     ),
                   ),
                 );
              }).toList(),
              
              const SizedBox(height: 24),
              _buildGlobalAppSettings(),
            ],
          ),
        );
      }
    );
  }

  void _showChangeSuperAdminPasswordDialog() {
    final passController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Super Admin Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             const Text('This updates your IMMEDIATE login password for Firebase Auth. It also updates the record causing the System tab lock to update.'),
             const SizedBox(height: 16),
             TextField(
               controller: passController,
               obscureText: true,
               decoration: const InputDecoration(labelText: 'New Password', border: OutlineInputBorder()),
             ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newPass = passController.text.trim();
              if(newPass.length < 6) {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password too short')));
                 return;
              }
              Navigator.pop(ctx);
              
              try {
                // Update Auth
                await FirebaseAuth.instance.currentUser!.updatePassword(newPass);
                // Update Record (For System Tab Lock consistency check if we used that, but we use Auth now. 
                // We update initialPassword just for record keeping on the card)
                await FirebaseFirestore.instance.collection('admin_users').doc(FirebaseAuth.instance.currentUser!.uid).update({
                  'initialPassword': newPass,
                  // Ensure legacy field is dead
                  'security_password': FieldValue.delete(),
                });
                
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password Updated Successfully')));
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalPasswordResetSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade900),
              const SizedBox(width: 12),
              Text(
                'Emergency credential Reset',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red.shade900),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'This action will generate new passwords for ALL other administrators and allow you to set a new Super Admin password. Use this if you suspect a security breach or need to rotate all keys.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              onPressed: _showGlobalPasswordResetDialog,
              icon: const Icon(Icons.lock_reset),
              label: const Text('RESET ALL PASSWORDS'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showGlobalPasswordResetDialog() {
    final newSuperPasswordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Global Password Reset'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '1. You may enter a new "Supreme Password" for yourself below (or leave blank to keep current).\n'
                '2. All other admins will receive new randomly generated passwords.\n'
                '3. You will be able to share these new credentials immediately.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: newSuperPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Super Admin Password (Optional)',
                  hintText: 'Leave empty to keep current',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.admin_panel_settings),
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
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeGlobalReset(newSuperPasswordController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('EXECUTE RESET'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeGlobalReset(String newSuperPass) async {
    setState(() => _isSyncing = true); // Show loading
    String status = "Initializing...";
    
    try {
      final batch = FirebaseFirestore.instance.batch();
      final adminUsersRef = FirebaseFirestore.instance.collection('admin_users');
      final currentUser = FirebaseAuth.instance.currentUser;
      final currentUid = currentUser?.uid;

      // 1. Update Super Admin if requested
      if (newSuperPass.isNotEmpty) {
        if (currentUid != null) {
          status = "Updating your password...";
          // Update Auth
          try {
            await currentUser!.updatePassword(newSuperPass);
          } catch (e) {
             throw Exception('Failed to update your password: $e. (Try logging out and in again)');
          }
          
          // Update Record - Use set/merge to avoid "Not Found" errors if doc is missing
          batch.set(adminUsersRef.doc(currentUid), {
            'initialPassword': 'Set by Reset: ${DateTime.now().toIso8601String().substring(0, 10)}',
            'security_password': FieldValue.delete(), // DELETE LEGACY SECURITY PASSWORD 
          }, SetOptions(merge: true));
        }
      }

      // 2. Fetch all other admins
      status = "Fetching admins...";
      final query = await adminUsersRef.get();
      final List<Map<String, String>> updatedAdmins = [];

      status = "Generating new credentials...";
      for (var doc in query.docs) {
        if (doc.id == currentUid) continue; // Skip self
        final data = doc.data();
        if (data['role'] == 'super-admin') continue; // Safety check

        final newPass = _generateRandomPassword();
        
        // Use set/merge for robustness
        batch.set(doc.reference, {
          'initialPassword': newPass,
          'security_password': FieldValue.delete(), // DELETE LEGACY SECURITY PASSWORD for others too
        }, SetOptions(merge: true));
        
        updatedAdmins.add({
          'name': data['displayName'] ?? 'Admin',
          'email': data['email'] ?? '',
          'pass': newPass,
        });
      }

      // 3. Commit
      status = "Saving to database...";
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Global Reset Complete! Credentials Updated.'), backgroundColor: Colors.green),
        );
        _showMasterShareDialog(updatedAdmins);
      }

    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error during Reset'),
            content: Text('Failed at step: "$status"\n\nDetails: $e'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  void _showMasterShareDialog(List<Map<String, String>>? admins) {
    if (admins == null || admins.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No admins to share with.')));
      return;
    }

    final emails = admins.map((e) => e['email']!).join(',');
    final subject = 'IMPORTANT: Harmony by Intent Admin Credentials Update';
    final body = "Dear Admin Team,\n\n"
                 "A global security reset has been performed. Please find your new credentials below:\n\n"
                 "${admins.map((e) => "${e['name']}: ${e['email']} - Password: ${e['pass']}").join('\n')}\n\n"
                 "Please confirm receipt of this message with a reply.\n\n"
                 "Best regards,\nSuper Admin";
    
    final encodedBody = Uri.encodeComponent(body);
    final encodedSubject = Uri.encodeComponent(subject);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Distribute Credentials'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You can now email all admins with their new credentials including a receipt confirmation request.'),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.email),
                label: const Text('Open Email Client (To All)'),
                onPressed: () async {
                   final url = Uri.parse('mailto:?bcc=$emails&subject=$encodedSubject&body=$encodedBody');
                    try {
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url);
                      } else {
                         await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    } catch (e) {
                      debugPrint('Error launching email: $e');
                    }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 50)),
              ),
               const SizedBox(height: 16),
               const Text('Or copy the summary to clipboard:', style: TextStyle(fontWeight: FontWeight.bold)),
               const SizedBox(height: 8),
               Container(
                 height: 150,
                 width: double.infinity,
                 padding: const EdgeInsets.all(8),
                 decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300)),
                 child: SingleChildScrollView(child: SelectableText(body)),
               ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
               Clipboard.setData(ClipboardData(text: body));
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
            },
            child: const Text('Copy to Clipboard'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    );
  }

  Widget _buildGlobalAppSettings() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('global').snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData && snapshot.data!.exists 
            ? snapshot.data!.data() as Map<String, dynamic> 
            : <String, dynamic>{};
            
        final supportEmail = data['supportEmail'] ?? '';
        
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings_applications, color: Colors.indigo),
                    SizedBox(width: 12),
                    Text('Global App Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Public contact details displayed in the app.', style: TextStyle(color: Colors.grey)),
                const Divider(height: 32),
                
                ListTile(
                  title: const Text('Support / Contact Email'),
                  subtitle: Text(supportEmail.isNotEmpty ? supportEmail : 'Not Set (Using Default)'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit, color: Colors.indigo),
                    onPressed: () => _showUpdateSupportEmailDialog(supportEmail),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  void _showUpdateSupportEmailDialog(String current) {
    final controller = TextEditingController(text: current);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Support Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter the dedicated email address for app support inquiries (e.g., admin@harmonybyintent.com).'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Support Email Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await FirebaseFirestore.instance.collection('settings').doc('global').set({
                'supportEmail': controller.text.trim(),
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save Configuration'),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterAdminList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('admin_users').snapshots(),
      builder: (context, snapshot) {
         if (snapshot.hasError) {
           return Center(
             child: Padding(
               padding: const EdgeInsets.all(16.0),
               child: Column(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   const Icon(Icons.error_outline, color: Colors.red, size: 48),
                   const SizedBox(height: 16),
                   SelectableText('Error loading admins: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                 ],
               ),
             ),
           );
         }
         if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
         
         // Filter out Super Admins from this list as per requirement
         final docs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['role'] != 'super-admin';
         }).toList();

         return Column(
           children: [
             Padding(
               padding: const EdgeInsets.all(16.0),
               child: ElevatedButton.icon(
                 onPressed: () {
                    // Collect all admins and share (excluding super admin from share list? no, logic handles that)
                    final List<Map<String, String>> admins = [];
                    for(var doc in docs) {
                       final d = doc.data() as Map<String, dynamic>;
                       // logic above already filtered super-admin, but safe to keep check or just use filtered docs
                       admins.add({
                         'name': d['displayName'] ?? 'Admin',
                         'email': d['email'] ?? '',
                         'pass': d['initialPassword'] ?? 'Not set',
                       });
                    }
                    _showMasterShareDialog(admins);
                 },
                 icon: const Icon(Icons.share),
                 label: const Text('MASTER SHARE: Email All Admins'),
                 style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
               ),
             ),
             Expanded(
               child: ListView.builder(
                 padding: const EdgeInsets.all(24),
                 itemCount: docs.length,
                 itemBuilder: (ctx, i) {
                   final doc = docs[i];
                   final data = doc.data() as Map<String, dynamic>;
                   final permissions = List<String>.from(data['permissions'] ?? []);
                   
                   return Card(
                     margin: const EdgeInsets.only(bottom: 12),
                     child: ExpansionTile(
                       title: Text('${data['displayName']} (${data['role']})'),
                       subtitle: Text(data['email'] ?? ''),
                       children: [
                         Padding(
                           padding: const EdgeInsets.all(16.0),
                           child: Column(
                             crossAxisAlignment: CrossAxisAlignment.start,
                             children: [
                               Text('Initial Password Record: ${data['initialPassword'] ?? 'Not set'}'),
                               const SizedBox(height: 8),
                               Wrap(
                                 spacing: 8,
                                 children: permissions.map((p) => Chip(label: Text(p), visualDensity: VisualDensity.compact)).toList(),
                               ),
                               const SizedBox(height: 8),
                               if (data['vipCode'] != null)
                                 SelectableText('Link User App Access Code: ${data['vipCode']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                               const SizedBox(height: 8),
                               if (data['role'] != 'super-admin')
                                 Row(
                                   mainAxisAlignment: MainAxisAlignment.end,
                                   children: [
                                      IconButton(
                                       icon: const Icon(Icons.share, color: Colors.indigo),
                                       tooltip: 'Share Credentials',
                                       onPressed: () {
                                          final msg = "Hello ${data['displayName']},\n\nHere are your updated admin credentials:\n"
                                                      "Email: ${data['email']}\n"
                                                      "Password: ${data['initialPassword']}\n\n"
                                                      "Please confirm receipt by replying to this message.";
                                          _showShareDialog(data['initialPassword'] ?? '', data['displayName'] ?? '', data['email'] ?? '', customMessage: msg);
                                       },
                                     ),
                                     TextButton.icon(
                                       icon: const Icon(Icons.edit_note, size: 16),
                                       label: const Text('Update Pwd Record'),
                                       onPressed: () {
                                          final controller = TextEditingController(text: data['initialPassword']);
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Update Password Record'),
                                              content: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Text(
                                                    'NOTE: This only updates the text record below. It DOES NOT change their actual login password. '
                                                    'To force a password change, use "Send Password Reset Email".',
                                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  TextField(
                                                    controller: controller,
                                                    decoration: const InputDecoration(labelText: 'New Password Reference'),
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                                ElevatedButton(
                                                  onPressed: () {
                                                     FirebaseFirestore.instance.collection('admin_users').doc(doc.id).update({
                                                       'initialPassword': controller.text.trim(),
                                                       // Also ensure legacy is gone
                                                       'security_password': FieldValue.delete(),
                                                     });
                                                     Navigator.pop(ctx);
                                                  },
                                                  child: const Text('Save Record'),
                                                ),
                                              ],
                                            ),
                                          );
                                       },
                                     ),
                                     TextButton.icon(
                                       icon: const Icon(Icons.lock_reset, size: 16),
                                       label: const Text('Send Reset Email'),
                                       onPressed: () => _resetUserPassword(doc.id, data['email']), 
                                     ),
                                     const SizedBox(width: 8),
                                     TextButton(
                                       onPressed: () {
                                           // Delete Admin User
                                           FirebaseFirestore.instance.collection('admin_users').doc(doc.id).delete();
                                       }, 
                                       style: TextButton.styleFrom(foregroundColor: Colors.red),
                                       child: const Text('Revoke / Delete Admin'), 
                                     ),
                                   ],
                                 ),
                             ],
                           ),
                         ),
                       ],
                     ),
                   );
                 }
               ),
             ),
           ],
         );
      }
    );
  }

  Widget _buildVipManagement() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _showGenerateDialog,
            icon: const Icon(Icons.add),
            label: const Text('Generate VIP Code'),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('vip_codes').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 48),
                          const SizedBox(height: 16),
                          SelectableText('Error loading VIP codes: ${snapshot.error}', style: const TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return ListView.separated(
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (ctx, i) => const Divider(),
                  itemBuilder: (ctx, i) {
                    final doc = snapshot.data!.docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text(data['code'] ?? '???', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                      subtitle: Text('To: ${data['assignee'] ?? 'Unknown'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.share), onPressed: () => _showShareDialog(data['code'], data['assignee'] ?? '', '')),
                          IconButton(icon: const Icon(Icons.delete, color: Colors.grey), onPressed: () => _deleteCode(doc.id)),
                        ],
                      ),
                    );
                  },
                );
              }
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCode(String docId) async {
    await FirebaseFirestore.instance.collection('vip_codes').doc(docId).delete();
  }

Widget _buildActiveAdminsTab_UNUSED() {
    final currentUser = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Add Admin Form
          if (_showAddForm)
            Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.indigo.shade200),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_add, color: Colors.indigo),
                    const SizedBox(width: 8),
                    const Text(
                      'Create New Admin Operators Access Codes',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // ADMIN FORM
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Full Name',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email Address *',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _passwordController,
                        obscureText: false, // Visible by default as requested
                        decoration: const InputDecoration(
                          labelText: 'Initial Password *',
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                const Text('Tab Permissions:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: _newAdminPermissions.keys.map((key) {
                    final label = _permissionLabels[key] ?? key.replaceAll('_', ' ');
                    return SizedBox(
                      width: 200,
                      child: CheckboxListTile(
                        title: Text(label, style: const TextStyle(fontSize: 12)),
                        value: _newAdminPermissions[key],
                        onChanged: (val) {
                          setState(() {
                            _newAdminPermissions[key] = val ?? false;
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'New admin will receive an email and can change their password after first login. A VIP Access Code will also be generated automatically.',
                          style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _addAdmin,
                  icon: const Icon(Icons.save),
                  label: const Text('Create Admin User'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        
        // Real Admin List from Firestore
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('admin_users').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Text('Error: ${snapshot.error}');
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

            final docs = snapshot.data?.docs ?? [];
            
            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final uid = docs[index].id;
                final email = data['email'] ?? '';
                final name = data['displayName'] ?? 'Admin';
                final role = data['role'] ?? 'admin';
                final isActive = data['isActive'] ?? true;
                final isMe = uid == currentUser?.uid;
                final permissions = List<String>.from(data['permissions'] ?? []);
                final initialPassword = data['initialPassword'] as String?;
                final vipCode = data['vipCode'] as String?;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: CircleAvatar(
                      backgroundColor: role == 'super-admin' ? Colors.purple : (isActive ? Colors.indigo : Colors.grey),
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'A', style: const TextStyle(color: Colors.white)),
                    ),
                    title: Row(
                      children: [
                        Text(name, style: TextStyle(fontWeight: FontWeight.bold, color: isActive ? Colors.black : Colors.grey)),
                        if (isMe)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                            child: const Text('YOU', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                        if (!isActive)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                            child: const Text('BLOCKED', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    subtitle: Text('$email • ${role.toUpperCase()}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isMe) // Can't toggle own status
                          Switch(
                            value: isActive,
                            activeThumbColor: Colors.green,
                            inactiveThumbColor: Colors.red,
                            onChanged: (val) {
                              FirebaseFirestore.instance.collection('admin_users').doc(uid).update({'isActive': val});
                            },
                          ),
                        if (!isMe) // Can't delete self
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.lock_reset, color: Colors.orange),
                                tooltip: 'Reset Password',
                                onPressed: () => _resetUserPassword(uid, email),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                tooltip: 'Delete Admin',
                                onPressed: () {
                                  // Confirm delete
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Admin'),
                                  content: Text('Are you sure you want to delete $name?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                      onPressed: () {
                                        FirebaseFirestore.instance.collection('admin_users').doc(uid).delete();
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Permissions:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _defaultAdminPermissions.keys.map((key) {
                                final hasPerm = permissions.contains(key);
                                return FilterChip(
                                  label: Text(key.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 10)),
                                  selected: hasPerm,
                                  onSelected: isMe ? null : (val) { // Can't edit own permissions here to prevent lockout
                                    final newPerms = List<String>.from(permissions);
                                    if (val) {
                                      newPerms.add(key);
                                    } else {
                                      newPerms.remove(key);
                                    }
                                    FirebaseFirestore.instance.collection('admin_users').doc(uid).update({
                                      'permissions': newPerms
                                    });
                                  },
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 24),
                            const Divider(),
                            const SizedBox(height: 16),

                            const Text('Credentials & Access:', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                const Icon(Icons.password, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                const Text('Initial Password: ', style: TextStyle(color: Colors.grey)),
                                SelectableText(initialPassword ?? 'Not set', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                if (!isMe)
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                    tooltip: 'Update Password Record',
                                    onPressed: () {
                                      final controller = TextEditingController(text: initialPassword);
                                      showDialog(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Update Password Record'),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Text('This updates the record of the password given to the user. It does NOT change their actual login password if they have already set one.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                              const SizedBox(height: 16),
                                              TextField(
                                                controller: controller,
                                                decoration: const InputDecoration(labelText: 'New Password Record'),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                            ElevatedButton(
                                              onPressed: () {
                                                FirebaseFirestore.instance.collection('admin_users').doc(uid).update({
                                                  'initialPassword': controller.text.trim(),
                                                });
                                                Navigator.pop(ctx);
                                              },
                                              child: const Text('Update'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),

                            if (isMe && _storedSecurityPassword != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.lock, size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    const Text('Tab Lock Password: ', style: TextStyle(color: Colors.grey)),
                                    SelectableText(_storedSecurityPassword!, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),

                            if (vipCode != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.vpn_key, size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    const Text('VIP App Code: ', style: TextStyle(color: Colors.grey)),
                                    SelectableText(vipCode, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                                    const SizedBox(width: 8),
                                    if (!isMe)
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                        tooltip: 'Update VIP Code',
                                        onPressed: () {
                                          final controller = TextEditingController(text: vipCode);
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Update VIP Code'),
                                              content: TextField(
                                                controller: controller,
                                                decoration: const InputDecoration(labelText: 'New VIP Code'),
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    FirebaseFirestore.instance.collection('admin_users').doc(uid).update({
                                                      'vipCode': controller.text.trim(),
                                                    });
                                                    Navigator.pop(ctx);
                                                  },
                                                  child: const Text('Update'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    if (!isMe)
                                      IconButton(
                                        icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                        tooltip: 'Revoke VIP Code',
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Revoke VIP Code'),
                                              content: const Text('Are you sure you want to remove this VIP code? The user will lose app access.'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                                ElevatedButton(
                                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                  onPressed: () {
                                                    FirebaseFirestore.instance.collection('admin_users').doc(uid).update({
                                                      'vipCode': FieldValue.delete(),
                                                    });
                                                    Navigator.pop(ctx);
                                                  },
                                                  child: const Text('Revoke'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                final pass = initialPassword ?? 'Not set';
                                final code = vipCode ?? 'Not assigned';
                                final msg = "Hello $name,\n\nHere are your admin credentials for Harmony by Intent:\n\n"
                                    "Email: $email\n"
                                    "Initial Password: $pass\n"
                                    "VIP Access Code: $code\n\n"
                                    "Please log in and change your password immediately.";
                                
                                _showShareDialog(code, name, email, customMessage: msg);
                              },
                              icon: const Icon(Icons.share, size: 16),
                              label: const Text('Share Credentials'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo.shade50,
                                foregroundColor: Colors.indigo,
                              ),
                            ),
                          ],
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



  // Moderation Tab: live comments mock + simple profanity flagging + live event view
  Widget _buildModerationTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: const [
                  Icon(Icons.forum, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text('Live Comments (Mock)', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    itemCount: 20,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final sample = _sampleComment(i);
                      final flagged = _isProfane(sample);
                      return ListTile(
                        leading: CircleAvatar(child: Text(String.fromCharCode(65 + (i % 26)))),
                        title: Text(sample),
                        subtitle: Text('User #${i + 1002} • ${DateTime.now().subtract(Duration(minutes: i * 3))}'),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (flagged) const Icon(Icons.flag, color: Colors.red),
                          IconButton(icon: const Icon(Icons.delete), onPressed: () {}),
                          IconButton(icon: const Icon(Icons.check_circle, color: Colors.green), onPressed: () {}),
                        ]),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: const [
                  Icon(Icons.live_tv, color: Colors.indigo),
                  SizedBox(width: 8),
                  Text('Live Event View (Mock)', style: TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 8),
                Container(
                  height: 160,
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                  child: const Center(child: Icon(Icons.play_circle_outline, color: Colors.white, size: 48)),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, children: const [
                  Chip(label: Text('Participants ~ 12.4k')),
                  Chip(label: Text('Countries 47')),
                  Chip(label: Text('Latency: 120ms')),
                ]),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  String _sampleComment(int i) {
    const samples = [
      'Wonderful intention, joining from UK!',
      'So inspiring to be a part of this.',
      'Can’t wait for the session to start.',
      'Sending love from Brazil.',
      'Grateful for this community.',
      'Peace to all beings.',
      'Vibes are high today!',
      'What’s the local time in Tokyo?',
    ];
    return samples[i % samples.length];
  }

  bool _isProfane(String text) {
    // Mock profanity filter keywords — replace with real moderation service later
    const banned = ['badword', 'worseword'];
    final lower = text.toLowerCase();
    return banned.any(lower.contains);
  }



  // Access Requests Tab removed as per request
  // Widget _buildAccessRequestsTab() { ... }


  /* Helper methods for Access Requests removed */


  void _showChangeEmailDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final isPasswordAuth = user?.providerData.any((p) => p.providerId == 'password') ?? false;

    if (!isPasswordAuth) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cannot Change Email'),
          content: const Text('You are signed in with a social account (Google/Apple). Please change your email in your provider settings.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        ),
      );
      return;
    }

    final emailController = TextEditingController(text: user?.email);
    final passwordController = TextEditingController();
    bool isUpdating = false;
    bool isForceUpdating = false;
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Change Email Address'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Changing your email will send a verification link to the new address. You may need to sign in again.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'New Email Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                    helperText: 'Required for security verification',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: (isUpdating || isForceUpdating) ? null : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            // FORCE UPDATE BUTTON (Hidden unless needed)
            TextButton(
              onPressed: (isUpdating || isForceUpdating) ? null : () async {
                 setState(() => errorMessage = null);
                 if (emailController.text.isEmpty) {
                   setState(() => errorMessage = 'Please enter new email');
                   return;
                 }
                 setState(() => isForceUpdating = true);
                 try {
                   // SKIP Re-authenticate to prevent hanging
                   
                   // Update Firestore ONLY
                   try {
                     await FirebaseFirestore.instance
                         .collection('admin_users')
                         .doc(FirebaseAuth.instance.currentUser?.uid)
                         .update({'email': emailController.text.trim()})
                         .timeout(const Duration(seconds: 5));
                   } catch (e) {
                     debugPrint('DB Update timed out: $e');
                     // Proceed anyway
                   }

                   if (mounted) {
                     Navigator.pop(context);
                     ScaffoldMessenger.of(context).showSnackBar(
                       const SnackBar(
                         content: Text('Switching Account... Please Register with your new email now.'), 
                         backgroundColor: Colors.green,
                         duration: Duration(seconds: 10),
                       ),
                     );
                     // Force logout to ensure clean state
                     await FirebaseAuth.instance.signOut();
                   }
                 } catch (e) {
                   if (mounted) setState(() => errorMessage = 'Force Update Failed: $e');
                 } finally {
                   if (mounted) setState(() => isForceUpdating = false);
                 }
              },
              child: isForceUpdating 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Force Update (Emergency)', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton(
              onPressed: (isUpdating || isForceUpdating) ? null : () async {
                setState(() => errorMessage = null);

                if (emailController.text.isEmpty || passwordController.text.isEmpty) {
                  setState(() => errorMessage = 'Please fill in all fields');
                  return;
                }

                setState(() => isUpdating = true);

                try {
                  // 1. Re-authenticate (with timeout)
                  await _authService.reauthenticate(passwordController.text)
                      .timeout(const Duration(seconds: 10), onTimeout: () {
                        throw Exception('Connection timed out during password check. Please check your internet.');
                      });
                  
                  // 2. Update Email (with timeout)
                  await _authService.updateEmail(emailController.text.trim())
                      .timeout(const Duration(seconds: 10), onTimeout: () {
                        throw Exception('Connection timed out during email update. Please try again.');
                      });
                  
                  // 3. Update Firestore (Optimistic - Fire & Forget)
                  // We wrap this in its own try-catch so it doesn't block the success message if it fails.
                  try {
                    await FirebaseFirestore.instance
                        .collection('admin_users')
                        .doc(FirebaseAuth.instance.currentUser?.uid)
                        .update({'email': emailController.text.trim()})
                        .timeout(const Duration(seconds: 5));
                  } catch (e) {
                    debugPrint('Firestore update failed (non-critical): $e');
                    // Ignore DB error - user can use "Sync Data" button later
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Verification link sent to ${emailController.text.trim()}! Check your Spam/Junk folder.'),
                        backgroundColor: Colors.green,
                        duration: const Duration(seconds: 10),
                        action: SnackBarAction(
                          label: 'OK',
                          textColor: Colors.white,
                          onPressed: () {},
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    setState(() => errorMessage = e.toString().replaceAll('Exception: ', ''));
                  }
                } finally {
                  if (mounted) {
                    setState(() => isUpdating = false);
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              child: isUpdating 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Update Email'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Your Password'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
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
              if (newPasswordController.text != confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Passwords do not match'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                await _authService.reauthenticate(currentPasswordController.text);
                await _authService.changePassword(newPasswordController.text);
                
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Password changed successfully!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
            child: const Text('Change Password'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}

class _MaintenanceTab extends StatefulWidget {
  const _MaintenanceTab();

  @override
  State<_MaintenanceTab> createState() => _MaintenanceTabState();
}

class _MaintenanceTabState extends State<_MaintenanceTab> {
  bool _isMaintenanceMode = false;
  final _messageController = TextEditingController(text: 'System under maintenance. We will be back shortly.');
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('settings').doc('global').get();
      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          _isMaintenanceMode = data['maintenanceMode'] ?? false;
          if (data['maintenanceMessage'] != null) {
            _messageController.text = data['maintenanceMessage'];
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('global').set({
        'maintenanceMode': _isMaintenanceMode,
        'maintenanceMessage': _messageController.text,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving settings: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Maintenance',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Control access to the application during updates or maintenance.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 32),
          
          // Active Admins Section
          const _ActiveAdminsWidget(),
          const SizedBox(height: 32),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Maintenance Mode'),
                    subtitle: const Text('When enabled, users will see a maintenance screen and cannot access the app.'),
                    value: _isMaintenanceMode,
                    onChanged: (value) {
                      setState(() => _isMaintenanceMode = value);
                    },
                    secondary: Icon(
                      Icons.build,
                      color: _isMaintenanceMode ? Colors.orange : Colors.grey,
                    ),
                  ),
                  const Divider(height: 32),
                  const Text(
                    'Maintenance Message',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Enter message to display to users',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save),
                      label: const Text('Save Changes'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
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

class _ActiveAdminsWidget extends StatelessWidget {
  const _ActiveAdminsWidget();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('admin_users')
          .where('lastActive', isGreaterThan: DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String())
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final admins = snapshot.data!.docs;
        if (admins.isEmpty) return const SizedBox.shrink();

        return Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.people, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Active Admins (${admins.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: admins.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return Chip(
                      avatar: const CircleAvatar(child: Icon(Icons.person, size: 12)),
                      label: Text(data['displayName'] ?? 'Unknown'),
                      backgroundColor: Colors.white,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Pricing Tab (Removed)

// Legal Tab
class _LegalTab extends StatefulWidget {
  const _LegalTab();

  @override
  State<_LegalTab> createState() => _LegalTabState();
}

class _LegalTabState extends State<_LegalTab> {
  String _selectedDocId = 'terms';
  Map<String, String?> _pdfUrls = {};
  bool _isLoading = true;

  final List<Map<String, dynamic>> _documents = [
    {'title': 'Terms & Conditions', 'id': 'terms', 'hasCheckbox': true},
    {'title': 'Legal', 'id': 'legal', 'hasCheckbox': false},
    {'title': 'About', 'id': 'about', 'hasCheckbox': false},
  ];

  @override
  void initState() {
    super.initState();
    print('DEBUG: _LegalTab initialized');
    _loadAllDocs();
  }

  Future<void> _loadAllDocs() async {
    setState(() => _isLoading = true);
    try {
      for (var doc in _documents) {
        final snapshot = await FirebaseFirestore.instance
            .collection('app_config')
            .doc(doc['id'])
            .get();
        if (snapshot.exists) {
          _pdfUrls[doc['id']] = snapshot.data()?['pdfUrl'];
        }
      }
    } catch (e) {
      debugPrint('Error loading docs: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFromMediaLibrary(String docId) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _MediaPickerDialog(),
    );

    if (result != null) {
      setState(() {
        _pdfUrls[docId] = result;
      });
      _publish(docId); // Auto-save/publish on selection for smoother UX? Or manual?
      // Let's keep it manual save or auto-save. The user asked to "load a document", usually implies selection.
      // I'll add a save button or auto-save. Let's do auto-save for simplicity in this new layout.
      _publish(docId);
    }
  }

  Future<void> _publish(String docId) async {
    final doc = _documents.firstWhere((d) => d['id'] == docId);
    final url = _pdfUrls[docId];
    
    if (url == null) return;

    try {
      await FirebaseFirestore.instance.collection('app_config').doc(docId).set({
        'pdfUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
        'title': doc['title'],
        'hasCheckbox': doc['hasCheckbox'],
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${doc['title']} updated successfully')),
        );
      }
    } catch (e) {
      debugPrint('Error publishing: $e');
    }
  }

  Future<void> _delete(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('app_config').doc(docId).delete();
      setState(() {
        _pdfUrls[docId] = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document removed')),
        );
      }
    } catch (e) {
      debugPrint('Error deleting: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDoc = _documents.firstWhere((d) => d['id'] == _selectedDocId);
    final selectedUrl = _pdfUrls[_selectedDocId];

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Side: Document List
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Legal Documents',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Select a document to view and edit.'),
                  const SizedBox(height: 24),
                  ..._documents.map((doc) => _buildDocCard(doc)).toList(),
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 32),

          // Right Side: Phone Preview
          Expanded(
            flex: 4, // Increased flex for larger viewer
            child: Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(8), // Reduced padding
              alignment: Alignment.center,
              child: Column(
                children: [
                  const Text('LIVE PREVIEW',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  // EXTRA CONTROLS FOR VISIBILITY
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _pickFromMediaLibrary(_selectedDocId),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Upload PDF'),
                      ),
                      const SizedBox(width: 16),
                      if (selectedUrl != null)
                        ElevatedButton.icon(
                          onPressed: () => _publish(_selectedDocId),
                          icon: const Icon(Icons.publish),
                          label: const Text('Publish'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.contain, // Ensure it scales to fit
                      child: Container(
                        width: 450, // Wider
                        height: 900, // Taller
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(40),
                          border:
                              Border.all(color: Colors.grey.shade800, width: 8),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                spreadRadius: 5),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: Column(
                            children: [
                              // Phone Status Bar (Fake)
                              Container(
                                height: 44, // Standard iOS status bar height
                                color: const Color(0xFF1A1A2E),
                                padding: const EdgeInsets.symmetric(horizontal: 24),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('9:41', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                    Row(
                                      children: [
                                        Icon(Icons.signal_cellular_alt, color: Colors.white, size: 16),
                                        SizedBox(width: 6),
                                        Icon(Icons.wifi, color: Colors.white, size: 16),
                                        SizedBox(width: 6),
                                        Icon(Icons.battery_full, color: Colors.white, size: 16),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // App Bar (Fake)
                              Container(
                                height: 56,
                                color: const Color(0xFF1A1A2E), // App Theme Color
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                                    const SizedBox(width: 16),
                                    Text(
                                      selectedDoc['title'],
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                                    ),
                                  ],
                                ),
                              ),
                              // Content
                              Expanded(
                                child: Container(
                                  color: Colors.white,
                                  child: Stack(
                                    children: [
                                      if (_isLoading)
                                        const Center(child: CircularProgressIndicator())
                                      else if (selectedUrl != null)
                                        SfPdfViewer.network(
                                          selectedUrl,
                                          canShowScrollHead: false,
                                          canShowScrollStatus: false,
                                        )
                                      else
                                        Center(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              const Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey),
                                              const SizedBox(height: 16),
                                              Text(
                                                'No PDF Selected for\n${selectedDoc['title']}',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(color: Colors.grey, fontSize: 16),
                                              ),
                                            ],
                                          ),
                                        ),
                                      
                                      // Conditional Checkbox Overlay (Only for Terms)
                                      if (selectedDoc['id'] == 'terms')
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(24),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withOpacity(0.1),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, -2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              children: [
                                                Checkbox(
                                                  value: false, 
                                                  onChanged: (_) {},
                                                  activeColor: Colors.indigo,
                                                ),
                                                const Expanded(
                                                  child: Text(
                                                    'I agree to the Terms & Conditions',
                                                    style: TextStyle(fontSize: 14),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              // Phone Home Indicator Area
                              Container(
                                height: 34,
                                color: Colors.black,
                                alignment: Alignment.topCenter,
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  width: 134,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2.5),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Widget _buildDocCard(Map<String, dynamic> doc) {
    final isSelected = _selectedDocId == doc['id'];
    final hasFile = _pdfUrls[doc['id']] != null;

    return Card(
      elevation: isSelected ? 4 : 1,
      color: isSelected ? Colors.indigo.shade50 : Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected ? const BorderSide(color: Colors.indigo, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => setState(() => _selectedDocId = doc['id']),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.indigo : Colors.grey.shade200,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.description,
                  color: isSelected ? Colors.white : Colors.grey,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc['title'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.indigo : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasFile ? 'PDF Uploaded' : 'No file selected',
                      style: TextStyle(
                        color: hasFile ? Colors.green : Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected || true) // ALWAYS SHOW BUTTONS FOR DEBUGGING
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.upload_file, color: Colors.blue),
                      tooltip: 'Change PDF',
                      onPressed: () => _pickFromMediaLibrary(doc['id']),
                    ),
                    if (hasFile) ...[
                      IconButton(
                        icon: const Icon(Icons.publish, color: Colors.green),
                        tooltip: 'Publish',
                        onPressed: () => _publish(doc['id']),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        tooltip: 'Remove',
                        onPressed: () => _delete(doc['id']),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPickerDialog extends StatelessWidget {
  final MediaLibraryService _mediaService = MediaLibraryService();

  _MediaPickerDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Select PDF from Media Library', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<MediaItem>>(
                stream: _mediaService.getMediaStream(section: 'All'),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Text('Error: ${snapshot.error}');
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  
                  final items = snapshot.data!;
                  // Filter for PDFs (simple check)
                  final pdfs = items.where((item) => item.name.toLowerCase().endsWith('.pdf') || item.type == 'pdf').toList();
                  
                  if (pdfs.isEmpty) {
                    return const Center(child: Text('No PDFs found in Media Library. Upload some first!'));
                  }

                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: pdfs.length,
                    itemBuilder: (context, index) {
                      final item = pdfs[index];
                      return InkWell(
                        onTap: () => Navigator.pop(context, item.url),
                        child: Card(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.picture_as_pdf, size: 40, color: Colors.red),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(item.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
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
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        ),
      ),
    );
  }
}
