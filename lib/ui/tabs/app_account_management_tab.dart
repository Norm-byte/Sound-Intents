import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppAccountManagementTab extends StatefulWidget {
  final bool canManageAppAccounts;

  const AppAccountManagementTab({
    super.key,
    required this.canManageAppAccounts,
  });

  @override
  State<AppAccountManagementTab> createState() => _AppAccountManagementTabState();
}

class _AppAccountManagementTabState extends State<AppAccountManagementTab> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _vipQuotaTierController = TextEditingController(text: 'tier_beta');

  final _codeAssigneeController = TextEditingController();
  final _codeContactController = TextEditingController();
  final _customCodeController = TextEditingController();

  bool _isVip = true;
  bool _isSaving = false;
  bool _isGeneratingCode = false;
  String _selectedCodeType = 'beta_tester';

  String _firstNonEmpty(List<dynamic> values, {String fallback = ''}) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return fallback;
  }

  DateTime? _asDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  bool _isActiveAccount(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    return data['isVip'] == true || data['isActive'] == true || status == 'active';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _vipQuotaTierController.dispose();
    _codeAssigneeController.dispose();
    _codeContactController.dispose();
    _customCodeController.dispose();
    super.dispose();
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    final raw = String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
    return '${raw.substring(0, 4)}-${raw.substring(4, 8)}';
  }

  Future<void> _createVipCode() async {
    final assignee = _codeAssigneeController.text.trim();
    if (assignee.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter who the code is for.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isGeneratingCode = true);
    try {
      final custom = _customCodeController.text.trim().toUpperCase();
      final code = custom.isNotEmpty ? custom : _generateCode();

      await FirebaseFirestore.instance.collection('vip_codes').add({
        'code': code,
        'assignee': assignee,
        'contactInfo': _codeContactController.text.trim(),
        'status': 'active',
        'vipQuotaTier': 'tier_beta',
        'createdAt': FieldValue.serverTimestamp(),
        'redeemedBy': null,
        'redeemedAt': null,
        'type': _selectedCodeType,
      });

      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: code));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('VIP code created and copied: $code'),
          backgroundColor: Colors.green,
        ),
      );

      _codeAssigneeController.clear();
      _codeContactController.clear();
      _customCodeController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not generate VIP code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGeneratingCode = false);
    }
  }

  Future<void> _provisionAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('provisionAppUserAccount')
          .call({
        'email': _emailController.text.trim(),
        'initialPassword': _passwordController.text.trim(),
        'fullName': _fullNameController.text.trim(),
        'username': _usernameController.text.trim(),
        'isVip': _isVip,
        'vipQuotaTier': _vipQuotaTierController.text.trim(),
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      final existed = data['existed'] == true;
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final username = _usernameController.text.trim();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existed
                ? 'Existing app account updated successfully.'
                : 'App account created successfully.',
          ),
          backgroundColor: Colors.green,
        ),
      );

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('App Account Ready'),
          content: SelectableText(
            'Email: $email\n'
            'Password: $password\n'
            'Username: $username\n'
            'Beta-VIP: ${_isVip ? 'Yes' : 'No'}',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: 'Email: $email\nPassword: $password\nUsername: $username',
                  ),
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Credentials copied to clipboard.')),
                  );
                }
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      _emailController.clear();
      _passwordController.clear();
      _fullNameController.clear();
      _usernameController.clear();
      _vipQuotaTierController.text = 'tier_beta';
      setState(() => _isVip = true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not create app account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canManageAppAccounts) {
      return Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.lock_outline, size: 40, color: Colors.grey),
                SizedBox(height: 12),
                Text(
                  'You do not have permission to manage app accounts.',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8),
                Text(
                  'Ask a super-admin to grant the App Accounts permission.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1200;

        final formCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create / Update App Accounts',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use this for tester onboarding. Username is written to all profile identity fields used by community and chat display.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return 'Please enter an email address';
                      if (!trimmed.contains('@')) return 'Please enter a valid email address';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.password_outlined),
                    ),
                    validator: (value) {
                      if ((value?.trim() ?? '').length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.alternate_email),
                    ),
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return 'Please enter a username';
                      final lower = trimmed.toLowerCase();
                      if (lower == 'guest' || lower == 'member') {
                        return 'Please choose a different username';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    value: _isVip,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Grant Beta-VIP access'),
                    subtitle: const Text('Turn this off when you want to test the full subscription path.'),
                    onChanged: (value) => setState(() => _isVip = value),
                  ),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Advanced (Optional)'),
                    children: [
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _vipQuotaTierController,
                        enabled: _isVip,
                        decoration: const InputDecoration(
                          labelText: 'VIP Quota Tier',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.workspace_premium_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _provisionAccount,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person_add_alt_1),
                    label: Text(_isSaving ? 'Saving...' : 'Create / Update App Account'),
                  ),
                ],
              ),
            ),
          ),
        );

        final rightPane = Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Beta-VIP Code Generator',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedCodeType,
                      decoration: const InputDecoration(
                        labelText: 'Access Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'beta_tester',
                          child: Text('Beta Tester (App Only)'),
                        ),
                        DropdownMenuItem(
                          value: 'super_admin',
                          child: Text('Super Admin (Full Access)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedCodeType = value);
                      },
                    ),
                    if (_selectedCodeType == 'super_admin') ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Warning: This creates a Super Admin code for the user app.',
                        style: TextStyle(fontSize: 12, color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeAssigneeController,
                      decoration: const InputDecoration(
                        labelText: 'Assignee',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _codeContactController,
                      decoration: const InputDecoration(
                        labelText: 'Contact (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _customCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Custom Code (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: _isGeneratingCode ? null : _createVipCode,
                      icon: _isGeneratingCode
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.vpn_key),
                      label: Text(_isGeneratingCode ? 'Generating...' : 'Generate VIP Code'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'App Accounts (Live)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 360,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .limit(200)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snapshot.data!.docs.where((doc) {
                            final data = doc.data();
                            final email = (data['email'] ?? '').toString().trim();
                            final username = (data['username'] ?? data['userName'] ?? data['displayName'] ?? '').toString().trim();
                            return email.isNotEmpty || username.isNotEmpty;
                          }).toList()
                            ..sort((a, b) {
                              final ad = a.data();
                              final bd = b.data();
                              final aDate = _asDateTime(ad['updatedAt']) ??
                                  _asDateTime(ad['joinDate']) ??
                                  _asDateTime(ad['createdAt']) ??
                                  DateTime.fromMillisecondsSinceEpoch(0);
                              final bDate = _asDateTime(bd['updatedAt']) ??
                                  _asDateTime(bd['joinDate']) ??
                                  _asDateTime(bd['createdAt']) ??
                                  DateTime.fromMillisecondsSinceEpoch(0);
                              return bDate.compareTo(aDate);
                            });

                          if (docs.isEmpty) {
                            return const Center(child: Text('No app accounts found yet.'));
                          }

                          return ListView.builder(
                            itemCount: docs.length,
                            itemBuilder: (context, index) {
                              final doc = docs[index];
                              final data = doc.data();
                              final username = _firstNonEmpty([
                                data['username'],
                                data['userName'],
                                data['displayName'],
                                data['name'],
                              ], fallback: 'Unknown');
                              final fullName = _firstNonEmpty([
                                data['fullName'],
                                data['name'],
                              ], fallback: '—');
                              final displayName = _firstNonEmpty([
                                data['displayName'],
                                data['name'],
                              ], fallback: '—');
                              final email = _firstNonEmpty([data['email']], fallback: '—');
                              final status = _firstNonEmpty([data['status']], fallback: '—');
                              final createdAt = _asDateTime(data['createdAt']) ?? _asDateTime(data['joinDate']);
                              final updatedAt = _asDateTime(data['updatedAt']) ?? _asDateTime(data['lastActive']);
                              final isVip = data['isVip'] == true;
                              final isActive = _isActiveAccount(data);

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isActive ? Colors.green.shade400 : Colors.grey.shade300,
                                    width: isActive ? 1.6 : 1,
                                  ),
                                  boxShadow: isActive
                                      ? [
                                          BoxShadow(
                                            color: Colors.green.withOpacity(0.22),
                                            blurRadius: 10,
                                            spreadRadius: 1,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            username,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                        ),
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(isVip ? 'VIP' : 'Standard'),
                                          backgroundColor:
                                              isVip ? Colors.green.shade100 : Colors.grey.shade200,
                                        ),
                                        const SizedBox(width: 6),
                                        Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(isActive ? 'Active' : status),
                                          backgroundColor: isActive
                                              ? Colors.green.shade100
                                              : Colors.orange.shade100,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('Email: $email'),
                                    Text('Full Name: $fullName'),
                                    Text('Display Name: $displayName'),
                                    Text('Doc ID: ${doc.id}'),
                                    Text('Created: ${_formatDate(createdAt)}'),
                                    Text('Updated/Active: ${_formatDate(updatedAt)}'),
                                  ],
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
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VIP Codes (Merged Existing List)',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 240,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('vip_codes')
                            .orderBy('createdAt', descending: true)
                            .limit(60)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snapshot.data!.docs;
                          if (docs.isEmpty) {
                            return const Center(child: Text('No VIP codes found.'));
                          }

                          return ListView.separated(
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final data = docs[index].data();
                              final code = (data['code'] ?? '—').toString();
                              final assignee = (data['assignee'] ?? 'Unassigned').toString();
                              final status = (data['status'] ?? 'unknown').toString();
                              return ListTile(
                                dense: true,
                                title: Text(code),
                                subtitle: Text(assignee),
                                trailing: Chip(label: Text(status)),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );

        if (wide) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: formCard),
                const SizedBox(width: 16),
                Expanded(flex: 6, child: rightPane),
              ],
            ),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              formCard,
              const SizedBox(height: 12),
              rightPane,
            ],
          ),
        );
      },
    );
  }
}