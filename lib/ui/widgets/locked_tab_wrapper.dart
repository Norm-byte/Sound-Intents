import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LockedTabWrapper extends StatefulWidget {
  final Widget child;
  final String title;
  final Function(bool)? onUnlock;

  const LockedTabWrapper({
    super.key,
    required this.child,
    required this.title,
    this.onUnlock,
  });

  @override
  State<LockedTabWrapper> createState() => _LockedTabWrapperState();
}

class _LockedTabWrapperState extends State<LockedTabWrapper> {
  final TextEditingController _unlockController = TextEditingController();
  bool _isLocked = true;
  bool _isLoading = true;
  String? _storedSecurityPassword;
  String? _storedVipCode;
  String? _storedDirectVipCode;

  @override
  void initState() {
    super.initState();
    _loadAuthSecrets();
  }

  Future<void> _loadAuthSecrets() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. Get Security Password & Direct VIP Code from admin_users
      final userDoc = await FirebaseFirestore.instance
          .collection('admin_users')
          .doc(user.uid)
          .get();
      
      _storedSecurityPassword = userDoc.data()?['security_password'];
      _storedDirectVipCode = userDoc.data()?['vipCode'];

      // 2. Get VIP Code from vip_codes collection (super_admin type assigned to user)
      final vipQuery = await FirebaseFirestore.instance
          .collection('vip_codes')
          .where('assignee', isEqualTo: user.email)
          .get();
      
      if (vipQuery.docs.isNotEmpty) {
        final superAdminCode = vipQuery.docs.firstWhere(
          (d) => d.data()['type'] == 'super_admin', 
          orElse: () => vipQuery.docs.first
        );
        _storedVipCode = superAdminCode.data()['code'];
      }

      // If no password/code set at all, maybe we should unlock? 
      // User requirement says "all should have password protection", so we enforce lock unless credentials exist.
      // But if they don't have a password set, they can't unlock it?
      // Assuming admins MUST have a password/code set if they are Restricted.
      
    } catch (e) {
      debugPrint('Error loading auth secrets: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _attemptUnlock() async {
    final input = _unlockController.text.trim();
    if (input.isEmpty) return;

    bool unlocked = false;
    
    // Check personal security password
    if (_storedSecurityPassword != null && input == _storedSecurityPassword) unlocked = true;
    
    // Check assigned VIP code
    if (_storedVipCode != null && input == _storedVipCode) unlocked = true;
    
    // Check direct VIP code on user doc
    if (_storedDirectVipCode != null && input == _storedDirectVipCode) unlocked = true;

    // Fallback: Check Global VIP Codes (if allowed by policy? LegalTab does this)
    if (!unlocked) {
        try {
            final query = await FirebaseFirestore.instance
                .collection('vip_codes')
                .where('code', isEqualTo: input)
                .where('type', isEqualTo: 'super_admin')
                .where('status', isEqualTo: 'active')
                .limit(1)
                .get();
            if (query.docs.isNotEmpty) unlocked = true;
        } catch (e) {
            // ignore
        }
    }

    if (unlocked) {
      setState(() {
        _isLocked = false;
        _unlockController.clear();
      });
      widget.onUnlock?.call(true);
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
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isLocked) {
      return widget.child; // Render content when unlocked
    }

    // Lock Screen UI (Matching LegalTab/UserManagement style)
    return Center(
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.all(32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.indigo),
              const SizedBox(height: 24),
              Text(
                '${widget.title} Locked',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'You do not have permission to view this tab freely.\nPlease enter your Security Password or VIP Code to access it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _unlockController,
                obscureText: true,
                onSubmitted: (_) => _attemptUnlock(),
                decoration: const InputDecoration(
                  labelText: 'Password / VIP Code',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.vpn_key),
                ),
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
                  child: const Text('Unlock Access'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
