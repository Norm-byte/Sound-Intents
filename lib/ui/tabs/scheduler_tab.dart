import 'package:flutter/material.dart';
import '../../models/event.dart';

class SchedulerTab extends StatefulWidget {
  final List<Event> events;
  final Function(Map<String, dynamic>) onAddRule;
  final Function(String) onDeleteRule;
  final Function(String) onToggleRule;

  const SchedulerTab({
    super.key,
    required this.events,
    required this.onAddRule,
    required this.onDeleteRule,
    required this.onToggleRule,
  });

  @override
  State<SchedulerTab> createState() => _SchedulerTabState();
}

class _SchedulerTabState extends State<SchedulerTab> {
  Event? _selectedEvent;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  String _repeatPattern = 'daily';
  bool _isActive = true;
  final List<String> _selectedDays = [];
  
  // Mock recurring rules
  final List<Map<String, dynamic>> _rules = [
    {
      'id': '1',
      'eventTitle': 'Morning Meditation',
      'time': '09:00',
      'pattern': 'Daily',
      'active': true,
      'nextRun': '2025-11-08 09:00',
    },
    {
      'id': '2',
      'eventTitle': 'Evening Relaxation',
      'time': '18:00',
      'pattern': 'Weekdays',
      'active': true,
      'nextRun': '2025-11-07 18:00',
    },
    {
      'id': '3',
      'eventTitle': 'Weekend Focus Session',
      'time': '10:00',
      'pattern': 'Weekends',
      'active': false,
      'nextRun': '2025-11-09 10:00',
    },
  ];

  bool _showAddForm = false;

  void _addRule() {
    if (_selectedEvent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an event first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final rule = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'eventId': _selectedEvent!.id,
      'eventTitle': _selectedEvent!.title,
      'time': '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
      'pattern': _repeatPattern,
      'active': _isActive,
      'days': _selectedDays,
    };

    widget.onAddRule(rule);
    setState(() {
      _rules.add(rule);
      _showAddForm = false;
      _selectedEvent = null;
      _selectedDays.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recurring rule added successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _manualTrigger(Event event) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.play_arrow, color: Colors.indigo),
            SizedBox(width: 8),
            Text('Manual Trigger'),
          ],
        ),
        content: Text(
          'Trigger "${event.title}" immediately?\n\nThis will publish the event now and send notifications to all subscribed users.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Event "${event.title}" triggered!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: const Icon(Icons.send),
            label: const Text('Trigger Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Event Selector Sidebar
        SizedBox(
          width: 280,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_note, color: Colors.indigo),
                        SizedBox(width: 8),
                        Text(
                          'Reusable Index',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Select an event to schedule',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: widget.events.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'No events available.\n\nCreate events first in the Event Creator tab.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.events.length,
                        itemBuilder: (context, i) {
                          final e = widget.events[i];
                          final isSelected = _selectedEvent?.id == e.id;
                          final rulesCount = _rules.where((r) => r['eventTitle'] == e.title).length;

                          return Container(
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.indigo.shade100
                                  : Colors.transparent,
                              border: Border(
                                bottom: BorderSide(color: Colors.grey.shade200),
                              ),
                            ),
                            child: ListTile(
                              selected: isSelected,
                              leading: CircleAvatar(
                                backgroundColor: e.isPublished
                                    ? Colors.green.shade100
                                    : Colors.orange.shade100,
                                child: Icon(
                                  e.isPublished ? Icons.check_circle : Icons.drafts,
                                  size: 20,
                                  color: e.isPublished ? Colors.green : Colors.orange,
                                ),
                              ),
                              title: Text(
                                e.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                rulesCount > 0 ? '$rulesCount active rules' : 'No rules',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: rulesCount > 0 ? Colors.blue : Colors.grey,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.play_arrow, color: Colors.indigo),
                                onPressed: () => _manualTrigger(e),
                                tooltip: 'Trigger Now',
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedEvent = isSelected ? null : e;
                                });
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        
        VerticalDivider(width: 1, thickness: 1, color: Colors.grey.shade300),
        
        // Main Scheduler Area
        Expanded(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
                child: Row(
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Event Scheduler',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Create recurring schedules and manual triggers',
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                      ],
                    ),
                    const Spacer(),
                    if (!_showAddForm)
                      ElevatedButton.icon(
                        onPressed: () {
                          if (_selectedEvent == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please select an event first'),
                                backgroundColor: Colors.orange,
                              ),
                            );
                            return;
                          }
                          setState(() => _showAddForm = true);
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New Recurring Rule'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
              
              // Add Rule Form
              if (_showAddForm)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    border: Border(
                      bottom: BorderSide(color: Colors.blue.shade200),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.add_circle, color: Colors.indigo),
                          const SizedBox(width: 8),
                          const Text(
                            'Add Recurring Rule',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _showAddForm = false),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Selected Event Display
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.event, color: Colors.indigo),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Event:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Text(
                                    _selectedEvent?.title ?? 'None selected',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Time Picker
                      Row(
                        children: [
                          Expanded(
                            child: Card(
                              child: ListTile(
                                leading: const Icon(Icons.access_time),
                                title: const Text('Trigger Time'),
                                subtitle: Text(
                                  '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                trailing: const Icon(Icons.edit),
                                onTap: () async {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: _selectedTime,
                                  );
                                  if (time != null) {
                                    setState(() => _selectedTime = time);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Repeat Pattern',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: _repeatPattern,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        isDense: true,
                                      ),
                                      items: const [
                                        DropdownMenuItem(value: 'daily', child: Text('Daily')),
                                        DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
                                        DropdownMenuItem(value: 'weekends', child: Text('Weekends')),
                                        DropdownMenuItem(value: 'custom', child: Text('Custom Days')),
                                      ],
                                      onChanged: (v) {
                                        setState(() => _repeatPattern = v!);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      // Custom Days (if selected)
                      if (_repeatPattern == 'custom') ...[
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Select Days',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                                      .map((day) => FilterChip(
                                            label: Text(day),
                                            selected: _selectedDays.contains(day),
                                            onSelected: (selected) {
                                              setState(() {
                                                if (selected) {
                                                  _selectedDays.add(day);
                                                } else {
                                                  _selectedDays.remove(day);
                                                }
                                              });
                                            },
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 16),
                      
                      // Active Toggle and Save
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              value: _isActive,
                              onChanged: (v) => setState(() => _isActive = v ?? true),
                              title: const Text('Active'),
                              subtitle: Text(_isActive
                                  ? 'Rule will run automatically'
                                  : 'Rule is paused'),
                              secondary: Icon(
                                _isActive ? Icons.check_circle : Icons.pause_circle,
                                color: _isActive ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          ElevatedButton.icon(
                            onPressed: _addRule,
                            icon: const Icon(Icons.save),
                            label: const Text('Add Rule'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              
              // Rules Table
              Expanded(
                child: _rules.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today, size: 80, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                              'No recurring rules yet',
                              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create your first recurring schedule',
                              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Active Recurring Rules (${_rules.where((r) => r['active']).length}/${_rules.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            DataTable(
                              columnSpacing: 24,
                              columns: const [
                                DataColumn(label: Text('Event', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Time', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Pattern', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Next Run', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                              ],
                              rows: _rules.map((rule) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      SizedBox(
                                        width: 200,
                                        child: Text(
                                          rule['eventTitle'],
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(rule['time'])),
                                    DataCell(Text(rule['pattern'])),
                                    DataCell(Text(rule['nextRun'] ?? 'N/A')),
                                    DataCell(
                                      Switch(
                                        value: rule['active'],
                                        onChanged: (v) {
                                          setState(() {
                                            rule['active'] = v;
                                          });
                                          widget.onToggleRule(rule['id']);
                                        },
                                      ),
                                    ),
                                    DataCell(
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, size: 20),
                                            onPressed: () {
                                              // Edit functionality placeholder
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Edit functionality coming soon'),
                                                ),
                                              );
                                            },
                                            tooltip: 'Edit',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                            onPressed: () {
                                              setState(() {
                                                _rules.removeWhere((r) => r['id'] == rule['id']);
                                              });
                                              widget.onDeleteRule(rule['id']);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Rule deleted'),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            },
                                            tooltip: 'Delete',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
