import 'package:flutter/material.dart';
import '../../services/admin_user_service.dart';

class SetupSuperAdminScreen extends StatefulWidget {
  const SetupSuperAdminScreen({super.key});

  @override
  State<SetupSuperAdminScreen> createState() => _SetupSuperAdminScreenState();
}

class _SetupSuperAdminScreenState extends State<SetupSuperAdminScreen> {
  final _nameController = TextEditingController();
  final _service = AdminUserService();
  bool _submitting = false;
  String? _error;

  Future<void> _create() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _service.createSuperAdminForCurrentUser(
        displayName: _nameController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Super admin created. Welcome!')),
        );
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF3949AB), Color(0xFF1A237E)],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.verified_user, color: Colors.indigo, size: 28),
                        SizedBox(width: 8),
                        Text('First-time Setup', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'No administrators exist yet. You\'re about to create the first super-admin with full access.',
                      style: TextStyle(color: Colors.black87),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your Name (optional)',
                        border: OutlineInputBorder(),
                        helperText: 'Used for display in the admin console. You can change it later.',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Color(0xFFFFEBEE),
                          border: Border.all(color: Color(0xFFEF9A9A)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_error!, style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _submitting ? null : _create,
                        icon: const Icon(Icons.star),
                        label: _submitting
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Make me the Super Admin'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Note: This action creates a record in Firestore (admin_users) binding your account as the super-admin.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
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
