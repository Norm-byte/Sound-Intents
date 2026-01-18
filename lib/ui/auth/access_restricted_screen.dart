import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/admin_user_service.dart';

class AccessRestrictedScreen extends StatefulWidget {
  final String reason;
  const AccessRestrictedScreen({super.key, required this.reason});

  @override
  State<AccessRestrictedScreen> createState() => _AccessRestrictedScreenState();
}

class _AccessRestrictedScreenState extends State<AccessRestrictedScreen> {
  final _service = AdminUserService();
  bool _requested = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final r = await _service.hasPendingRequestForCurrentUser();
    if (mounted) setState(() { _requested = r; _loading = false; });
  }

  Future<void> _requestAccess() async {
    setState(() { _loading = true; });
    await _service.requestAccess();
    if (mounted) setState(() { _requested = true; _loading = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Access request sent. A super-admin will review it.')),
      );
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _fixMyAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loading = true);
    try {
      // Force promote to super-admin with ALL required fields to prevent parsing crashes
      await FirebaseFirestore.instance.collection('admin_users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': 'Super Admin',
        'role': 'super-admin',
        'isActive': true,
        'createdAt': DateTime.now().toIso8601String(), // Model expects String
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Success! Please REFRESH your browser now.'), backgroundColor: Colors.green, duration: Duration(seconds: 10)),
        );
        // Do NOT navigate automatically - let user refresh
      }
    } catch (e) {
      if (mounted) {
        String errorMsg = 'Fix Failed: $e';
        if (e.toString().contains('TimeoutException')) {
          errorMsg = 'Fix Timed Out (5s). Network blocking writes? Try Hotspot.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRedeemDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redeem VIP Code'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Enter Code',
            hintText: 'e.g. VIP-12345',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _redeemCode(controller.text.trim());
            },
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
  }

  Future<void> _redeemCode(String code) async {
    if (code.isEmpty) return;
    setState(() => _loading = true);
    try {
      await _service.redeemVipCode(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Code redeemed successfully! Refreshing...'), backgroundColor: Colors.green),
        );
        // The stream in main.dart should pick up the change automatically
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF455A64), Color(0xFF263238)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.lock_outline, color: Colors.blueGrey, size: 28),
                        SizedBox(width: 8),
                        Text('Access Restricted (v2.1)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(widget.reason, style: const TextStyle(color: Colors.black87)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF90CAF9)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.info_outline, color: Color(0xFF1976D2)),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text('If you need access, request approval from a super-admin.'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_requested)
                            const Center(child: Text('Access requested. Waiting for approval.', style: TextStyle(color: Colors.black54)))
                          else
                            ElevatedButton.icon(
                              onPressed: _requestAccess,
                              icon: const Icon(Icons.outgoing_mail),
                              label: const Text('Request Access'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _showRedeemDialog,
                            icon: const Icon(Icons.vpn_key),
                            label: const Text('Redeem VIP Code'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _fixMyAccount,
                            icon: const Icon(Icons.admin_panel_settings, color: Colors.orange),
                            label: const Text('Fix My Account (Owner Only)'),
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                          ),
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _signOut,
                            icon: const Icon(Icons.logout, color: Colors.red),
                            label: const Text('Sign Out'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
