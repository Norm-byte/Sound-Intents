import 'dart:convert';
import 'package:flutter/material.dart';
import 'models/event.dart';
import 'services/local_storage_service.dart';
import 'services/firebase_service.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Try to initialize Firebase if web config is present - if not, continue without failing.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Firebase not configured yet - continue in local-only mode.
    debugPrint('Firebase init skipped or failed: $e');
  }

  runApp(const HarmonyAdminApp());
}

class HarmonyAdminApp extends StatelessWidget {
  const HarmonyAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harmony Admin',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const AdminHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Event> events = [];
  final LocalStorageService _local = LocalStorageService();
  final FirebaseService _firebase = FirebaseService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final saved = await _local.loadEvents();
    setState(() {
      events = saved;
    });
  }

  Future<void> _saveEvent(Event e, {bool publish = false}) async {
    setState(() => events.insert(0, e));
    await _local.saveEvents(events);
    if (publish) {
      try {
        await _firebase.publishEvent(e);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Published to Firestore (if configured)')));
      } catch (err) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Publish failed (no Firebase configured)')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Harmony by Intent — Admin'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Dashboard'),
            Tab(text: 'Event Creator'),
            Tab(text: 'Content Editor'),
            Tab(text: 'Media Library'),
            Tab(text: 'Preview'),
            Tab(text: 'Scheduler'),
            Tab(text: 'Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboard(),
          EventCreatorPanel(onSave: _saveEvent, initialEvents: events),
          const Center(child: Text('Content Editor - coming soon')),
          const Center(child: Text('Media Library - coming soon')),
          _buildPreview(),
          const Center(child: Text('Scheduler - coming soon')),
          const Center(child: Text('Users - coming soon')),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Dashboard', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Events saved locally: ${events.length}'),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: events.length,
              itemBuilder: (context, i) {
                final e = events[i];
                return ListTile(
                  title: Text(e.title),
                  subtitle: Text(e.intent ?? ''),
                  trailing: Text(e.startTimeUTC ?? ''),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Integrated Preview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Expanded(
            child: events.isEmpty
                ? const Center(child: Text('No events saved yet'))
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final e = events[i];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12.0),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(e.intent ?? ''),
                              const SizedBox(height: 8),
                              Text('Start (UTC): ${e.startTimeUTC ?? 'not set'}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          )
        ],
      ),
    );
  }
}

class EventCreatorPanel extends StatefulWidget {
  final Function(Event e, {bool publish}) onSave;
  final List<Event> initialEvents;

  const EventCreatorPanel({required this.onSave, required this.initialEvents, super.key});

  @override
  State<EventCreatorPanel> createState() => _EventCreatorPanelState();
}

class _EventCreatorPanelState extends State<EventCreatorPanel> {
  final _title = TextEditingController();
  final _intent = TextEditingController();
  DateTime? _referenceLocal;
  String _timezone = 'UTC';
  String? _startUTCPreview;
  bool _publish = false;

  void _computeStartUTC() {
    if (_referenceLocal == null) return;
    // For now, treat referenceLocal as already in UTC or convert via timezone placeholder.
    final utc = _referenceLocal!.toUtc();
    setState(() {
      _startUTCPreview = utc.toIso8601String();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Event Creator', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(controller: _intent, maxLines: 4, decoration: const InputDecoration(labelText: 'Intent Description')),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.access_time),
                  label: const Text('Pick Reference Time'),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) {
                      final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                      if (time != null) {
                        setState(() {
                          _referenceLocal = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                        });
                        _computeStartUTC();
                      }
                    }
                  },
                ),
                const SizedBox(width: 12),
                Text(_referenceLocal == null ? 'No time chosen' : _referenceLocal!.toLocal().toString()),
              ],
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Timezone:'),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _timezone,
                items: const [
                  DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                  DropdownMenuItem(value: 'Local', child: Text('Local')),
                ],
                onChanged: (v) => setState(() => _timezone = v ?? 'UTC'),
              )
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Checkbox(value: _publish, onChanged: (v) => setState(() => _publish = v ?? false)),
              const Text('Publish to Firestore (if configured)')
            ]),
            const SizedBox(height: 8),
            Text('StartTimeUTC Preview: ${_startUTCPreview ?? 'N/A'}'),
            const SizedBox(height: 12),
            Row(children: [
              ElevatedButton(
                onPressed: () {
                  final e = Event(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: _title.text,
                    intent: _intent.text,
                    startTimeUTC: _startUTCPreview,
                  );
                  widget.onSave(e, publish: _publish);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event saved locally')));
                },
                child: const Text('Save Event'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: () => setState(() { _title.clear(); _intent.clear(); _referenceLocal = null; _startUTCPreview = null; _publish = false;}), child: const Text('Reset'))
            ])
          ],
        ),
      ),
    );
  }
}
