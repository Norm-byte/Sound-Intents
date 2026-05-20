import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AccessRestrictedScreen extends StatefulWidget {
  final String reason;
  const AccessRestrictedScreen({super.key, required this.reason});

  @override
  State<AccessRestrictedScreen> createState() => _AccessRestrictedScreenState();
}

class _AccessRestrictedScreenState extends State<AccessRestrictedScreen> {
  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
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
                            child: Text('If sign-in fails, contact your super-admin for the correct operator credentials.'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
