import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_management_tab.dart';
import 'app_account_management_tab.dart';
import 'user_management_tab.dart';
import 'welcome_screen_manager.dart';
import '../../services/translation_service.dart';
import '../../widgets/translatable_text.dart';

class SystemTab extends StatefulWidget {
  final bool canManageAppAccounts;

  const SystemTab({
    super.key,
    required this.canManageAppAccounts,
  });

  @override
  State<SystemTab> createState() => _SystemTabState();
}

class _SystemTabState extends State<SystemTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    // Initialize controller immediately to prevent build errors
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Outer LockedTabWrapper in main.dart handles access control.
    // No inner lock needed here.
    return Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Configure system settings, monitor performance, and manage users',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                  tabs: const [
                    Tab(icon: Icon(Icons.people), text: 'Users'),
                    Tab(icon: Icon(Icons.person_add), text: 'App Accounts'),
                    Tab(icon: Icon(Icons.security), text: 'Safety & Filter'),
                    Tab(icon: Icon(Icons.gavel), text: 'Legal & Compliance'),
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
                const UserManagementTab(),
                AppAccountManagementTab(
                  canManageAppAccounts: widget.canManageAppAccounts,
                ),
                const ChatSafetyTab(),
                const ComplianceTab(),
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

class ComplianceTab extends StatefulWidget {
  const ComplianceTab({super.key});

  @override
  State<ComplianceTab> createState() => _ComplianceTabState();
}

class _ComplianceTabState extends State<ComplianceTab> {
  final _privacyController = TextEditingController();
  final _termsController = TextEditingController();
  final _eulaController = TextEditingController();
  final _contactController = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('system_settings').doc('legal').get();
      if (doc.exists) {
        final data = doc.data()!;
        _privacyController.text = data['privacy_url'] ?? '';
        _termsController.text = data['terms_url'] ?? '';
        _eulaController.text = data['eula_url'] ?? '';
        _contactController.text = data['contact_email'] ?? '';
      }
    } catch (e) {
      debugPrint('Error loading legal settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('system_settings').doc('legal').set({
        'privacy_url': _privacyController.text,
        'terms_url': _termsController.text,
        'eula_url': _eulaController.text,
        'contact_email': _contactController.text,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Legal Settings Saved')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Legal & Compliance Documents', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Enter the URLs where your legal documents are hosted. These will be linked in the User App.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 24),
              
              const Text('GDPR & Privacy', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _privacyController,
                decoration: const InputDecoration(
                  labelText: 'Privacy Policy URL',
                  hintText: 'https://your-website.com/privacy',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.privacy_tip),
                ),
              ),
              const SizedBox(height: 16),
              
              const Text('Terms & Conditions', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _termsController,
                decoration: const InputDecoration(
                  labelText: 'Terms of Service URL',
                  hintText: 'https://your-website.com/terms',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
              ),
              const SizedBox(height: 16),
              
              const Text('EULA (End User License Agreement)', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _eulaController,
                decoration: const InputDecoration(
                  labelText: 'EULA URL (Required for Apple App Store)',
                  hintText: 'https://your-website.com/eula',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.gavel),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text('Apple requires a standard EULA for apps with User Generated Content (Chat/Community). You can use Apple\'s standard EULA or your own.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              
              const SizedBox(height: 16),
              
              const Text('Contact Information', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _contactController,
                decoration: const InputDecoration(
                  labelText: 'Support / DPO Email',
                  hintText: 'support@your-domain.com',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
              ),

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Computance Settings'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.all(16),
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              const Text('Compliance Checklist Advice:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildChecklistItem('GDPR Deletion', 'Users must be able to delete their account. This is handled in the App Settings.'),
              _buildChecklistItem('Content Moderation', 'For Chat/Community, ensure you have "Report" and "Block" features (Implemented).'),
              _buildChecklistItem('Age Rating', 'Set correctly in App Store Connect / Google Play Console (12+ or 17+ for Unfiltered Internet Access).'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChecklistItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatSafetyTab extends StatefulWidget {
  const ChatSafetyTab({super.key});

  @override
  State<ChatSafetyTab> createState() => _ChatSafetyTabState();
}

class _ChatSafetyTabState extends State<ChatSafetyTab> {
  final TextEditingController _testController = TextEditingController();
  final TextEditingController _addWordController = TextEditingController();
  List<String> _bannedWords = [];
  bool _isLoading = true;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _loadBannedWords();
    TranslationService.instance.init();
  }

  Future<void> _loadBannedWords() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('system_settings').doc('profanity_filter').get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          _bannedWords = List<String>.from(doc.data()!['banned_words'] ?? []);
          _isLoading = false;
        });
      } else {
        setState(() {
          _bannedWords = []; // Initialize empty
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profanity filter: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addWord() async {
    final word = _addWordController.text.trim().toLowerCase();
    if (word.isEmpty) return;
    
    if (_bannedWords.contains(word)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Word already in list')));
      return;
    }

    final updatedWords = <String>{..._bannedWords, word}.toList()..sort();
    final previousWords = List<String>.from(_bannedWords);

    setState(() {
      _bannedWords = updatedWords;
      _addWordController.clear();
    });

    try {
      await _saveWords(updatedWords);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bannedWords = previousWords;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add word: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _removeWord(String word) async {
    final previousWords = List<String>.from(_bannedWords);
    final updatedWords = List<String>.from(_bannedWords)..remove(word);

    setState(() {
      _bannedWords = updatedWords;
    });

    try {
      await _saveWords(updatedWords);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bannedWords = previousWords;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove word: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _seedDefaults() async {
    setState(() => _isLoading = true);
    // Representative subset of "LDNOOBW" and standard safety lists.
    // Covers: Profanity, Hate Speech, Sexual Content, Violence, Self-Harm.
    final defaults = [
      // Standard Profanity
      "abuse", "arse", "ass", "asshole", "bastard", "bitch", "bloody", "bollocks",
      "bullshit", "cock", "cunt", "damn", "dick", "douche", "dyke", "fag", "faggot",
      "fuck", "fucker", "fucking", "goddamn", "hell", "homo", "jerk", "kike", "nigger",
      "nigga", "piss", "prick", "pussy", "queer", "shit", "slut", "spic", "tits",
      "twat", "wank", "wanker", "whore", "retard", "spastic",
      
      // Sexual Content / Harassment
      "anal", "anus", "blowjob", "boner", "boob", "clitoris", "cum", "dildo", 
      "ejaculation", "handjob", "masturbate", "naked", "nude", "orgasm", "penis", 
      "porn", "sex", "vagina", "xxx", "rape", "rapist", "molest", "incest", 
      "pedophile", "pornography", "strip club", "hooker",

      // Violence / Threat / Self-Harm
      "kill", "murder", "die", "suicide", "terrorist", "bomb", "massacre", "shoot",
      "stab", "attack", "death", "execute", "mass shooting", "cut myself", "kill myself",

      // Drugs
      "cocaine", "heroin", "meth", "crack", "weed", "marijuana", "lsd", "acid",

      // Phrases (Matching logic: text.contains(phrase))
      "white power", "black power", "hate you", "go die", "kill yourself", 
      "blow me", "eat me", "suck it", "piece of shit", "son of a bitch",

      // --- International (Common European - DE, FR, ES) ---
      // Spanish
      "puta", "mierda", "coño", "cabron", "maricon", "pendejo", "gilipollas", 
      "verga", "chinga", "culo", "hijo de puta", "joder",
      
      // French
      "merde", "putain", "connard", "connasse", "salope", "encule", "foutre", 
      "bite", "couille", "pede", "nique", "bordel", "chatte",
      
      // German
      "scheisse", "arschloch", "fotze", "hure", "wichser", "schlampe", 
      "ficken", "verdammt", "arsch", "miststueck"
    ];
    
    final previousWords = List<String>.from(_bannedWords);
    try {
      final updatedWords = <String>{..._bannedWords, ...defaults}.toList()..sort();
      await _saveWords(updatedWords);
      if (!mounted) return;
      setState(() {
        _bannedWords = updatedWords;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standards-Based Safety Blocklist Loaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bannedWords = previousWords;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load safety blocklist: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveWords(List<String> words) async {
    await FirebaseFirestore.instance.collection('system_settings').doc('profanity_filter').set({
      'banned_words': words,
      'last_updated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _testPhrase() {
    final text = _testController.text.toLowerCase();
    if (text.isEmpty) return;

    final found = _bannedWords.where((w) => text.contains(w)).toList();
    if (found.isNotEmpty) {
      setState(() {
        _testResult = '❌ FLAGGED: Contains banned words: ${found.join(", ")}';
      });
    } else {
      setState(() {
        _testResult = '✅ PASSED: No banned words found.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Row(
      children: [
        // Left Column: Filter Management
        Expanded(
          flex: 2,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
               padding: const EdgeInsets.all(16),
               child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                   const Text('Blocked Words List', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   const Text('Messages containing these words will be flagged for moderation.', style: TextStyle(color: Colors.grey)),
                   const SizedBox(height: 8),
                   Align(
                     alignment: Alignment.centerLeft,
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
                                       ? 'Translator enabled for Safety & Filter'
                                       : 'Translator disabled for Safety & Filter',
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
                   
                   Row(children: [
                     Expanded(child: TextField(
                       controller: _addWordController,
                       decoration: const InputDecoration(
                         labelText: 'Add word or phrase to blocklist',
                         border: OutlineInputBorder(),
                         prefixIcon: Icon(Icons.block),
                       ),
                       onSubmitted: (_) => _addWord(),
                     )),
                     const SizedBox(width: 8),
                     ElevatedButton(onPressed: _addWord, child: const Text('Add')),
                   ]),
                   
                   const SizedBox(height: 8),
                   Align(
                     alignment: Alignment.centerLeft,
                     child: OutlinedButton.icon(
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Load/Refreshed Standard Safety Blocklist'),
                        onPressed: _seedDefaults,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                        ),
                      ),
                   ),

                   const SizedBox(height: 16),
                   Expanded(
                     child: Container(
                       decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                       child: _bannedWords.isEmpty 
                         ? const Center(child: Text('No words banned yet.'))
                         : ListView.separated(
                           itemCount: _bannedWords.length,
                           separatorBuilder: (c, i) => const Divider(height: 1),
                           itemBuilder: (ctx, index) {
                             final word = _bannedWords[index];
                             return ListTile(
                               title: TranslatableText(word),
                               trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _removeWord(word)),
                             );
                           },
                         ),
                     ),
                   ),
                 ],
               ),
            ),
          ),
        ),
        
        // Right Column: Testing Tool
        Expanded(
          flex: 1,
          child: Card(
            margin: const EdgeInsets.only(top: 16, bottom: 16, right: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Filter Test Tool',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: TranslationService.instance.enabledNotifier,
                        builder: (context, enabled, _) {
                          return IconButton(
                            tooltip: enabled
                                ? 'Disable Translator'
                                : 'Enable Translator',
                            onPressed: () async {
                              await TranslationService.instance.setEnabled(!enabled);
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    !enabled
                                        ? 'Translator enabled for Safety & Filter'
                                        : 'Translator disabled for Safety & Filter',
                                  ),
                                ),
                              );
                            },
                            icon: Icon(
                              Icons.translate,
                              color: enabled ? Colors.indigo : Colors.grey,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Type a sentence to check if it would be flagged.', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 24),
                  
                  TextField(
                    controller: _testController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'e.g. "This works fine" or "You are a [bad word]"',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: TranslationService.instance.enabledNotifier,
                    builder: (context, enabled, _) {
                      if (!enabled || _testController.text.trim().isEmpty) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.indigo.shade100),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Translated preview',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.indigo.shade700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TranslatableText(_testController.text.trim()),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _testPhrase,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Test Filter'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  
                  if (_testResult != null) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _testResult!.startsWith('❌') ? Colors.red.shade50 : Colors.green.shade50,
                        border: Border.all(color: _testResult!.startsWith('❌') ? Colors.red.shade200 : Colors.green.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.bold,
                          color: _testResult!.startsWith('❌') ? Colors.red.shade900 : Colors.green.shade900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
  bool _isLoadingConfig = true;
  bool _showNicheChatRooms = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
       final doc = await FirebaseFirestore.instance.collection('system_settings').doc('app_config').get();
       if (doc.exists) {
          setState(() {
             _showNicheChatRooms = doc.data()?['show_niche_chat_rooms'] ?? true;
          });
       }
    } catch(e) { 
      debugPrint(e.toString()); 
    } finally { 
      if(mounted) setState(() => _isLoadingConfig = false); 
    }
  }
  
  Future<void> _toggleNicheChatRooms(bool value) async {
     setState(() => _showNicheChatRooms = value);
     await FirebaseFirestore.instance.collection('system_settings').doc('app_config').set({
        'show_niche_chat_rooms': value
     }, SetOptions(merge: true));

     if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text(value ? 'Niche Chat Rooms Enabled' : 'Niche Chat Rooms Paused (Hidden)'),
           backgroundColor: value ? Colors.green : Colors.orange,
         ),
       );
     }
  }

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

          // Feature Configuration
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   const Text('Feature Configuration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                   const SizedBox(height: 8),
                   SwitchListTile(
                     title: const Text('Enable Niche Chat Rooms'),
                     subtitle: const Text('Show "My Chat Rooms" & "Find Chatrooms" in User App (My Harmony). Turn OFF to pause these features.'),
                     value: _showNicheChatRooms,
                     onChanged: _isLoadingConfig ? null : _toggleNicheChatRooms,
                   ),
                ],
              ),
            ),
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

