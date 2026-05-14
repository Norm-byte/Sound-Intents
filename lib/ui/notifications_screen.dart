import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/translation_service.dart';
import '../widgets/translatable_text.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  String _targetTopic = 'all_users';
  bool _isSending = false;

  final List<String> _topics = [
    'all_users',
    'zone_UTC',
    'zone_EST', // Eastern Standard Time (US)
    'zone_PST', // Pacific Standard Time (US)
    'zone_GMT', // Greenwich Mean Time
    'zone_CET', // Central European Time
    'zone_AEST', // Australian Eastern Standard Time (Sydney, Melbourne)
    'zone_ACST', // Australian Central Standard Time (Adelaide)
    'zone_AWST', // Australian Western Standard Time (Perth)
    'zone_NZST', // New Zealand Standard Time
    'zone_JST', // Japan Standard Time
    'zone_IST', // India Standard Time
  ];

  @override
  void initState() {
    super.initState();
    TranslationService.instance.init();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _sendNotification() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    try {
      // 1. Send Push Notification via Cloud Function
      final result = await FirebaseFunctions.instance
          .httpsCallable('sendPushNotification')
          .call({
        'title': _titleController.text.trim(),
        'body': _bodyController.text.trim(),
        'topic': _targetTopic,
      });

      final data = result.data as Map<String, dynamic>;
      final success = data['success'] == true;
      final message = data['message'] ?? 'Unknown result';

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(success ? 'Success' : 'Failed'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        
        if (success) {
          _titleController.clear();
          _bodyController.clear();
        }
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text('An unexpected error occurred: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push Notifications'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Send a Global Alert',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Use this form to send push notifications to all users or specific groups. Be careful, this goes to everyone!',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerRight,
                child: ValueListenableBuilder<bool>(
                  valueListenable: TranslationService.instance.enabledNotifier,
                  builder: (context, enabled, _) {
                    return OutlinedButton.icon(
                      onPressed: () async {
                        await TranslationService.instance.setEnabled(!enabled);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              !enabled
                                  ? 'Translator enabled for push preview'
                                  : 'Translator disabled for push preview',
                            ),
                          ),
                        );
                      },
                      icon: Icon(
                        Icons.translate,
                        color: enabled ? Colors.indigo : Colors.grey,
                      ),
                      label: Text(enabled ? 'Translator: ON' : 'Translator: OFF'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Target Topic
              DropdownButtonFormField<String>(
                initialValue: _targetTopic,
                decoration: const InputDecoration(
                  labelText: 'Target Audience',
                  helperText: 'Who should receive this message?',
                  border: OutlineInputBorder(),
                ),
                items: _topics.map((topic) {
                  return DropdownMenuItem(
                    value: topic,
                    child: Text(topic),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _targetTopic = value);
                },
              ),
              const SizedBox(height: 24),

              // Title Field
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Notification Title',
                  hintText: 'e.g., "Global Event Starting Now!"',
                  helperText: 'The main headline that appears on the lock screen.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Please enter a title' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),

              // Body Field
              TextFormField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Notification Body',
                  hintText: 'e.g., "Join us for the Peace Intent in 5 minutes."',
                  helperText: 'The detailed message content.',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Please enter a message body' : null,
                onChanged: (_) => setState(() {}),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: TranslationService.instance.enabledNotifier,
                builder: (context, enabled, _) {
                  if (!enabled) return const SizedBox.shrink();
                  final title = _titleController.text.trim();
                  final body = _bodyController.text.trim();
                  if (title.isEmpty && body.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Translated Push Preview',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                        if (title.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Title',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TranslatableText(title),
                        ],
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Body',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TranslatableText(body),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),

              // Send Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendNotification,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Send Notification'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
