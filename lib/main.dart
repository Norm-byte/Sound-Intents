import 'package:flutter/material.dart';

void main() {
  runApp(const HarmonyAdminApp());
}

class HarmonyAdminApp extends StatelessWidget {
  const HarmonyAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harmony Admin',
      theme: ThemeData(
        primarySwatch: Colors.blue,
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

class _AdminHomePageState extends State<AdminHomePage> {
  String selectedEvent = 'Sample Event';
  String intentText = 'Enter intent description here...';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Harmony by Intent — Admin'),
        centerTitle: true,
      ),
      body: Row(
        children: [
          // Left panel: Event list / upload
          Flexible(
            flex: 2,
            child: Container(
              color: Colors.white,
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Text('Events', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        ListTile(
                          title: const Text('Sample Event'),
                          subtitle: const Text('Saved reusable event'),
                          selected: selectedEvent == 'Sample Event',
                          onTap: () => setState(() => selectedEvent = 'Sample Event'),
                        ),
                        ListTile(
                          title: const Text('Event 2'),
                          subtitle: const Text('Another saved event'),
                          selected: selectedEvent == 'Event 2',
                          onTap: () => setState(() => selectedEvent = 'Event 2'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Upload Event (placeholder)'),
                      onPressed: () {
                        // Placeholder - user will implement upload
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload placeholder')));
                      },
                    ),
                  )
                ],
              ),
            ),
          ),

          // Center panel: Content editor
          Flexible(
            flex: 4,
            child: Container(
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Content Editor', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    maxLines: 6,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Intent description...'),
                    controller: TextEditingController(text: intentText),
                    onChanged: (v) => setState(() => intentText = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          // Placeholder save
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Save placeholder')));
                        },
                        child: const Text('Save Event Card'),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => setState(() => intentText = 'Enter intent description here...'),
                        child: const Text('Reset'),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),

          // Right panel: Integrated preview
          Flexible(
            flex: 3,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Integrated Preview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Card(
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selectedEvent, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(intentText, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
                      child: const Center(child: Text('Preview of the three-card layout would render here')),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
