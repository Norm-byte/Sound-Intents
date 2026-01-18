import 'package:flutter/material.dart';
import '../../models/event.dart';

class PreviewTab extends StatefulWidget {
  final List<Event> events;

  const PreviewTab({super.key, required this.events});

  @override
  State<PreviewTab> createState() => _PreviewTabState();
}

class _PreviewTabState extends State<PreviewTab> {
  String _filter = 'upcoming';
  Event? _selectedEvent;

  List<Event> get _filteredEvents {
    final now = DateTime.now();

    switch (_filter) {
      case 'upcoming':
        return widget.events.where((e) {
          if (e.startTimeUTC == null) return false;
          final start = DateTime.parse(e.startTimeUTC!);
          return start.isAfter(now) && e.isPublished;
        }).toList()
          ..sort((a, b) {
            final aTime = DateTime.parse(a.startTimeUTC!);
            final bTime = DateTime.parse(b.startTimeUTC!);
            return aTime.compareTo(bTime);
          });

      case 'past':
        return widget.events.where((e) {
          if (e.startTimeUTC == null) return false;
          final start = DateTime.parse(e.startTimeUTC!);
          return start.isBefore(now) && e.isPublished;
        }).toList()
          ..sort((a, b) {
            final aTime = DateTime.parse(a.startTimeUTC!);
            final bTime = DateTime.parse(b.startTimeUTC!);
            return bTime.compareTo(aTime); // Reverse sort for past events
          });

      case 'draft':
        return widget.events.where((e) => e.isDraft).toList();

      case 'all':
      default:
        return widget.events;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with Filters
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'User View Preview',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Preview how events will appear to users in the mobile app',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),

              // Filter Chips
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Upcoming'),
                    selected: _filter == 'upcoming',
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = 'upcoming');
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Past Events'),
                    selected: _filter == 'past',
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = 'past');
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Drafts'),
                    selected: _filter == 'draft',
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = 'draft');
                    },
                  ),
                  ChoiceChip(
                    label: const Text('All Events'),
                    selected: _filter == 'all',
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = 'all');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // Preview Area
        Expanded(
          child: Row(
            children: [
              // Mobile Preview Panel (3-Card Layout)
              Expanded(
                flex: 2,
                child: Container(
                  color: Colors.grey.shade100,
                  child: Center(
                    child: Container(
                      width: 400,
                      height: double.infinity,
                      margin: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Column(
                          children: [
                            // Mock Phone Header
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade700,
                              ),
                              child: const Column(
                                children: [
                                  Text(
                                    'Harmony by Intent',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Sound & Visual Events',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Event Cards (3-Card Layout)
                            Expanded(
                              child: _filteredEvents.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.event_busy,
                                            size: 64,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'No events to display',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _filter == 'draft'
                                                ? 'Draft events are not visible to users'
                                                : 'Create and publish events to see them here',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: _filteredEvents.length,
                                      itemBuilder: (context, i) {
                                        final event = _filteredEvents[i];
                                        return _EventCard(
                                          event: event,
                                          onTap: () {
                                            setState(
                                              () => _selectedEvent = event,
                                            );
                                          },
                                          isSelected:
                                              _selectedEvent?.id == event.id,
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Details Panel
              if (_selectedEvent != null)
                Container(
                  width: 400,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: _EventDetailsPanel(
                    event: _selectedEvent!,
                    onClose: () => setState(() => _selectedEvent = null),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback onTap;
  final bool isSelected;

  const _EventCard({
    required this.event,
    required this.onTap,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startTime =
        event.startTimeUTC != null ? DateTime.parse(event.startTimeUTC!) : null;
    final isPast = startTime != null && startTime.isBefore(now);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: isSelected ? 8 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.indigo : Colors.transparent,
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image/Visual Section
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.indigo.shade100,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(
                      Icons.image,
                      size: 48,
                      color: Colors.indigo.shade300,
                    ),
                  ),
                  // Status Badge
                  if (event.isDraft)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DRAFT',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (isPast && !event.isDraft)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade600,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PAST',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Content Section
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (event.intent != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      event.intent!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Time and Duration Info
                  Row(
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        startTime != null
                            ? '${startTime.toLocal().month}/${startTime.toLocal().day} at ${startTime.toLocal().hour}:${startTime.toLocal().minute.toString().padLeft(2, '0')}'
                            : 'Time not set',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      if (event.flexibleDurationMinutes != null) ...[
                        const SizedBox(width: 12),
                        Icon(
                          Icons.timer,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${event.flexibleDurationMinutes}min',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Action Row
                  Row(
                    children: [
                      if (event.soundUrl != null)
                        Chip(
                          avatar: const Icon(Icons.audiotrack, size: 16),
                          label: const Text(
                            'Sound',
                            style: TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (event.learnMoreContent != null ||
                          event.learnMoreYoutubeUrl != null) ...[
                        const SizedBox(width: 8),
                        Chip(
                          avatar: const Icon(Icons.info, size: 16),
                          label: const Text(
                            'Learn More',
                            style: TextStyle(fontSize: 11),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventDetailsPanel extends StatelessWidget {
  final Event event;
  final VoidCallback onClose;

  const _EventDetailsPanel({required this.event, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            children: [
              const Icon(Icons.visibility, color: Colors.indigo),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Event Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: onClose),
            ],
          ),
        ),

        // Scrollable Details
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Status Indicator
                Row(
                  children: [
                    Icon(
                      event.isPublished ? Icons.check_circle : Icons.drafts,
                      color: event.isPublished ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      event.isPublished ? 'Published' : 'Draft',
                      style: TextStyle(
                        color: event.isPublished ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Intent
                if (event.intent != null) ...[
                  const _SectionTitle(title: 'Intent'),
                  const SizedBox(height: 8),
                  Text(
                    event.intent!,
                    style: const TextStyle(fontSize: 14, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                ],

                // Scheduling
                const _SectionTitle(title: 'Scheduling'),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.schedule,
                  label: 'Start Time',
                  value: event.startTimeUTC != null
                      ? DateTime.parse(event.startTimeUTC!).toLocal().toString()
                      : 'Not set',
                ),
                if (event.flexibleDurationMinutes != null)
                  _InfoRow(
                    icon: Icons.timer,
                    label: 'Duration',
                    value: '${event.flexibleDurationMinutes} minutes',
                  ),
                const SizedBox(height: 24),

                // Media
                const _SectionTitle(title: 'Media'),
                const SizedBox(height: 8),
                _InfoRow(
                  icon: Icons.audiotrack,
                  label: 'Sound',
                  value: event.soundUrl ?? 'Not set',
                ),
                _InfoRow(
                  icon: Icons.image,
                  label: 'Visual',
                  value: event.visualUrl ?? 'Not set',
                ),
                const SizedBox(height: 24),

                // Learn More Content
                if (event.learnMoreContent != null ||
                    event.learnMoreYoutubeUrl != null) ...[
                  const _SectionTitle(title: 'Learn More'),
                  const SizedBox(height: 8),
                  if (event.learnMoreContent != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        event.learnMoreContent!,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (event.learnMoreYoutubeUrl != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.video_library, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'YouTube Video',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  event.learnMoreYoutubeUrl!,
                                  style: const TextStyle(fontSize: 11),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 24),
                ],

                // Comments Section (Placeholder)
                const _SectionTitle(title: 'User Comments'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.comment,
                        size: 48,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Comments feature coming soon',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Users will be able to share their experiences here',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.indigo,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}
