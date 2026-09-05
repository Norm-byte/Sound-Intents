import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LiveSetupTab extends StatefulWidget {
  const LiveSetupTab({super.key});

  @override
  State<LiveSetupTab> createState() => _LiveSetupTabState();
}

class _LiveSetupTabState extends State<LiveSetupTab> {
  final _titleController = TextEditingController();
  final _hostController = TextEditingController();
  final _streamUrlController = TextEditingController();
  final _posterUrlController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final _backgroundUrlController = TextEditingController();
  final _newGenreController = TextEditingController();
  String _streamType = 'YouTube';
  String _genre = 'General';
  List<String> _genres = ['General'];
  DateTime _startTime = DateTime.now().add(const Duration(hours: 1));
  String? _editingId;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _hostController.dispose();
    _streamUrlController.dispose();
    _posterUrlController.dispose();
    _durationController.dispose();
    _backgroundUrlController.dispose();
    _newGenreController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadHubSettings();
  }

  Future<void> _loadHubSettings() async {
    final doc = await FirebaseFirestore.instance.collection('app_config').doc('live_hub').get();
    if (!doc.exists || !mounted) return;
    final data = doc.data() ?? {};
    final genres = (data['genres'] as List<dynamic>? ?? const []).map((value) => value.toString().trim()).where((value) => value.isNotEmpty).toList();
    setState(() {
      _genres = genres.isEmpty ? ['General'] : genres;
      _genre = _genres.contains(_genre) ? _genre : _genres.first;
      _backgroundUrlController.text = (data['backgroundImageUrl'] ?? '').toString();
    });
  }

  Future<void> _saveHubSettings() async {
    await FirebaseFirestore.instance.collection('app_config').doc('live_hub').set({
      'genres': _genres,
      'backgroundImageUrl': _backgroundUrlController.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Live Hub display settings saved.')));
  }

  void _clearForm() {
    setState(() {
      _editingId = null;
      _titleController.clear();
      _hostController.clear();
      _streamUrlController.clear();
      _posterUrlController.clear();
      _durationController.text = '60';
      _streamType = 'YouTube';
      _genre = _genres.first;
      _startTime = DateTime.now().add(const Duration(hours: 1));
    });
  }

  Future<void> _pickStartTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startTime),
    );
    if (time == null) return;
    setState(() => _startTime = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save({required bool publish}) async {
    final title = _titleController.text.trim();
    final host = _hostController.text.trim();
    final url = _streamUrlController.text.trim();
    final duration = int.tryParse(_durationController.text.trim());
    if (title.isEmpty || host.isEmpty || url.isEmpty || duration == null || duration < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a title, host, stream URL, and duration.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final ref = _editingId == null
          ? FirebaseFirestore.instance.collection('live_events').doc()
          : FirebaseFirestore.instance.collection('live_events').doc(_editingId);
      await ref.set({
        'title': title,
        'hostName': host,
        'streamType': _streamType,
        'streamUrl': url,
        'posterImageUrl': _posterUrlController.text.trim(),
        'genre': _genre,
        'startTime': Timestamp.fromDate(_startTime),
        'durationMinutes': duration,
        'isPublished': publish,
        'updatedAt': FieldValue.serverTimestamp(),
        if (_editingId == null) 'createdAt': FieldValue.serverTimestamp(),
        if (publish) 'publishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(publish ? 'Live show published.' : 'Draft saved.')));
        _clearForm();
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _edit(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? {};
    setState(() {
      _editingId = document.id;
      _titleController.text = (data['title'] ?? '').toString();
      _hostController.text = (data['hostName'] ?? '').toString();
      _streamUrlController.text = (data['streamUrl'] ?? '').toString();
      _posterUrlController.text = (data['posterImageUrl'] ?? '').toString();
      _durationController.text = (data['durationMinutes'] ?? 60).toString();
      _streamType = (data['streamType'] ?? 'YouTube').toString();
      _genre = (data['genre'] ?? _genres.first).toString();
      final start = data['startTime'];
      _startTime = start is Timestamp ? start.toDate() : DateTime.now().add(const Duration(hours: 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.live_tv, color: Colors.redAccent),
              const SizedBox(width: 10),
              Text(_editingId == null ? 'Live Setup' : 'Edit Live Show', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(onPressed: _saving ? null : _clearForm, icon: const Icon(Icons.add), label: const Text('New show')),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth <= 900) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildEditor(),
                    const SizedBox(height: 24),
                    _buildHubSettings(),
                    const SizedBox(height: 24),
                    _buildQueue(),
                    const SizedBox(height: 24),
                    _buildPhonePreview(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _buildEditor(),
                        const SizedBox(height: 20),
                        _buildHubSettings(),
                        const SizedBox(height: 20),
                        _buildQueue(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: Align(alignment: Alignment.topCenter, child: _buildPhonePreview())),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEditor() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _hostController, decoration: const InputDecoration(labelText: 'Host name', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(initialValue: _streamType, decoration: const InputDecoration(labelText: 'Stream type', border: OutlineInputBorder()), items: const [DropdownMenuItem(value: 'YouTube', child: Text('YouTube')), DropdownMenuItem(value: 'Mixcloud', child: Text('Mixcloud'))], onChanged: (value) => setState(() => _streamType = value ?? 'YouTube'))),
            const SizedBox(width: 12),
            Expanded(child: DropdownButtonFormField<String>(initialValue: _genre, decoration: const InputDecoration(labelText: 'Genre', border: OutlineInputBorder()), items: _genres.map((genre) => DropdownMenuItem(value: genre, child: Text(genre))).toList(), onChanged: (value) => setState(() => _genre = value ?? _genres.first))),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _streamUrlController, decoration: const InputDecoration(labelText: 'Stream URL or YouTube video ID', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: _posterUrlController, decoration: const InputDecoration(labelText: 'Poster image URL (optional)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : _pickStartTime, icon: const Icon(Icons.schedule), label: Text(DateFormat('d MMM yyyy, HH:mm').format(_startTime)))),
            const SizedBox(width: 12),
            SizedBox(width: 150, child: TextField(controller: _durationController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes', border: OutlineInputBorder()))),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _saving ? null : () => _save(publish: false), icon: const Icon(Icons.save_outlined), label: const Text('Save draft'))),
            const SizedBox(width: 12),
            Expanded(child: FilledButton.icon(onPressed: _saving ? null : () => _save(publish: true), icon: const Icon(Icons.publish), label: const Text('Publish to Harmony'))),
          ]),
        ],
      ),
    ),
  );

  Widget _buildPhonePreview() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        const Text('User App Preview', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 16),
        SizedBox(
          width: 280,
          height: 560,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.black, width: 8),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, 12),
                    child: Text('Live Hub', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (_posterUrlController.text.trim().isNotEmpty)
                    AspectRatio(aspectRatio: 16 / 9, child: Image.network(_posterUrlController.text.trim(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.white12))),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Chip(label: Text(_genre), backgroundColor: Colors.amber),
                      const SizedBox(height: 8),
                      Text(_titleController.text.isEmpty ? 'Live show title' : _titleController.text, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Text(_hostController.text.isEmpty ? 'Host name' : _hostController.text, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 12),
                      Text('Starts ${DateFormat('d MMM, HH:mm').format(_startTime)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.notifications_none), label: const Text('Remind Me')),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]),
    ),
  );

  Widget _buildHubSettings() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Live Hub display', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(controller: _backgroundUrlController, decoration: const InputDecoration(labelText: 'Background image URL (optional)', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: _newGenreController, decoration: const InputDecoration(labelText: 'Add genre', border: OutlineInputBorder()))),
          IconButton(icon: const Icon(Icons.add), tooltip: 'Add genre', onPressed: () {
            final genre = _newGenreController.text.trim();
            if (genre.isEmpty || _genres.contains(genre)) return;
            setState(() { _genres.add(genre); _newGenreController.clear(); });
          }),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: _genres.map((genre) => InputChip(label: Text(genre), onDeleted: _genres.length == 1 ? null : () => setState(() { _genres.remove(genre); if (_genre == genre) _genre = _genres.first; }))).toList()),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _saveHubSettings, icon: const Icon(Icons.save), label: const Text('Save Live Hub display')),
      ]),
    ),
  );

  Widget _buildQueue() => Card(
    child: SizedBox(
      height: 260,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Live event queue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('live_events').orderBy('startTime').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return const Center(child: Text('Could not load live events.'));
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No draft or published live shows yet.'));
                return ListView.separated(
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _buildQueueRow(snapshot.data!.docs[index]),
                );
              },
            ),
          ),
        ]),
      ),
    ),
  );

  Widget _buildQueueRow(DocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data() ?? {};
    final start = data['startTime'] is Timestamp ? (data['startTime'] as Timestamp).toDate() : null;
    final published = data['isPublished'] == true;
    return ListTile(
        leading: Icon(published ? Icons.public : Icons.edit_note, color: published ? Colors.green : Colors.orange),
        title: Text((data['title'] ?? 'Untitled live show').toString()),
        subtitle: Text('${data['hostName'] ?? 'Host'}${start == null ? '' : ' - ${DateFormat('d MMM, HH:mm').format(start)}'}'),
        trailing: Wrap(spacing: 4, children: [
          IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit), onPressed: () => _edit(document)),
          IconButton(tooltip: published ? 'Emergency offline' : 'Publish', icon: Icon(published ? Icons.stop_circle_outlined : Icons.publish), color: published ? Colors.red : Colors.green, onPressed: () => document.reference.update({'isPublished': !published, 'updatedAt': FieldValue.serverTimestamp()})),
        ]),
      );
  }
}