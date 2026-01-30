import 'package:flutter/material.dart';
import 'dart:async';
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
  final FocusNode _focusNode = FocusNode(); // ADDED FocusNode
  bool _isLocked = true;
  bool _isLoading = true;
  String? _storedSecurityPassword;
  String? _storedVipCode;
  String? _storedDirectVipCode;
  StreamSubscription? _userSub;

  @override
  void initState() {
    super.initState();
    _initAuthSecrets();
  }

  @override
  void dispose() {
    _userSub?.cancel();
    _unlockController.dispose();
    _focusNode.dispose(); // ADDED dispose
    super.dispose();
  }

  void _initAuthSecrets() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
       // 1. Subscription to admin user doc for real-time updates (handles password reset)
      _userSub = FirebaseFirestore.instance
          .collection('admin_users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
            if (mounted && snapshot.exists) {
              setState(() {
                _storedSecurityPassword = snapshot.data()?['security_password'];
                _storedDirectVipCode = snapshot.data()?['vipCode'];
                _isLoading = false;
              });
            }
          }, onError: (e) {
             debugPrint('Error stream admin user: $e');
             if(mounted) setState(() => _isLoading = false);
          });

      // 2. Get VIP Code from vip_codes collection (super_admin type assigned to user)
      // This is less likely to change rapidly, so we can keep it as a get or move to stream if needed.
      // Keeping as get for now to minimize reads, but re-fetching on unlock attempt might be safer.
      final vipQuery = await FirebaseFirestore.instance
          .collection('vip_codes')
          .where('assignee', isEqualTo: user.email)
          .get();
      
      if (vipQuery.docs.isNotEmpty) {
        final superAdminCode = vipQuery.docs.firstWhere(
          (d) => d.data()['type'] == 'super_admin', 
          orElse: () => vipQuery.docs.first
        );
        setState(() {
          _storedVipCode = superAdminCode.data()['code'];
        });
      }
    } catch (e) {
      debugPrint('Error loading auth secrets: $e');
      if(mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _attemptUnlock() async {
    final input = _unlockController.text.trim();
    if (input.isEmpty) return;

    bool unlocked = false;

    // 1. Try Firebase Auth Re-authentication (Primary Method)
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
          AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: input);
          // NOTE: reauthenticateWithCredential can throw if the token is stale or password wrong.
          // It can also cause a state change that disconnects active streams if using FlutterFire.
          await user.reauthenticateWithCredential(credential);
          
          // Force reload user to get fresh token which fixes "permission denied" on other tabs immediately
          await user.reload(); 
          
          unlocked = true;
          debugPrint('Unlocked via Firebase Auth');
      }
    } catch (e) {
      debugPrint('Auth unlock failed: $e');
      // If error is "wrong password", we just fail silently to try legacy.
      // If error is "assertion failed" or network, we might want to log it.
    }

    // 2. Legacy Checks
    if (!unlocked && _storedSecurityPassword != null && input == _storedSecurityPassword) unlocked = true;
    if (!unlocked && _storedVipCode != null && input == _storedVipCode) unlocked = true;
    if (!unlocked && _storedDirectVipCode != null && input == _storedDirectVipCode) unlocked = true;

    // 3. Fallback: Global VIP Codes
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect password or VIP code'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
                focusNode: _focusNode, // ADDED FocusNode attachment
                autofocus: true,       // Ensures immediate focus
                obscureText: true,
                onSubmitted: (_) { 
                   _attemptUnlock();
                   _focusNode.requestFocus(); // Keep focus if failed
                },
                decoration: InputDecoration( // CHANGED from const to allow suffix
                  labelText: 'Password / VIP Code',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.vpn_key),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () { 
                       _unlockController.clear(); 
                    },
                  ),
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
