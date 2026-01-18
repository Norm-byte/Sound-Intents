import 'package:flutter/material.dart';
import '../../models/event.dart';

class DashboardClock extends StatefulWidget {
  final List<Event> events;
  final Function(DateTime?, TimeOfDay?) onViewSchedule;

  const DashboardClock({
    super.key,
    required this.events,
    required this.onViewSchedule,
  });

  @override
  State<DashboardClock> createState() => _DashboardClockState();
}

class _DashboardClockState extends State<DashboardClock> {
  final ScrollController _scrollController = ScrollController();
  final double _hourHeight = 60.0;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNow();
    });
  }

  void _scrollToNow() {
    final now = DateTime.now();
    double offset = (now.hour * _hourHeight) + (now.minute * (_hourHeight / 60)) - 150; // 150px buffer
    if (offset < 0) offset = 0;
    
    // Clamp to max scroll extent
    // 24 * 60 = 1440
    
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Prepare events for rendering
    final displayEvents = <_DisplayEvent>[];

    for (var e in widget.events) {
      if (e.startTimeUTC == null) continue;
      
      final startUtc = DateTime.parse(e.startTimeUTC!);
      final startLocal = startUtc.toLocal(); // Convert base time to local
      
      final isRecurring = (e.recurrenceType != null && e.recurrenceType != 'None');
      final isToday = startLocal.year == now.year && 
                      startLocal.month == now.month && 
                      startLocal.day == now.day;

      if (isToday || isRecurring) {
        // For display, we normalize to today's date so they plot correctly on the 0-24h y-axis
        // For recurring events, we trust the HOUR/MINUTE from the start time
        final displayTime = DateTime(
          now.year, now.month, now.day,
          startLocal.hour, startLocal.minute, startLocal.second
        );
        
        displayEvents.add(_DisplayEvent(event: e, displayTime: displayTime));
      }
    }

    return Container(
      height: 500, // Tall enough for view
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule, color: Colors.purple),
                    const SizedBox(width: 8),
                    const Text(
                      "Today's Schedule",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: _scrollToNow,
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text("Current Time"),
                  style: TextButton.styleFrom(foregroundColor: Colors.purple),
                )
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Scrollable Timeline
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SizedBox(
                height: 24 * _hourHeight + 20, // 24 hours + pad
                child: Stack(
                  children: [
                    // Hour Grid
                    ...List.generate(24, (index) {
                      return Positioned(
                        top: index * _hourHeight,
                        left: 0,
                        right: 0,
                        height: _hourHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade50),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 60,
                                alignment: Alignment.topCenter,
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${index.toString().padLeft(2, '0')}:00',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Container(
                                  height: 1,
                                  color: Colors.grey.shade100,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // Events
                    ...displayEvents.map((de) {
                      final top = (de.displayTime.hour * _hourHeight) + 
                                (de.displayTime.minute * (_hourHeight / 60));
                      
                      // Calculate height based on duration, min 45px for visibility
                      double durationHeight = (de.event.durationSeconds ?? 3600) / 3600 * _hourHeight;
                      if (durationHeight < 45) durationHeight = 45;

                      final isRecurring = de.event.recurrenceType != null && de.event.recurrenceType != 'None';
                      final color = isRecurring ? Colors.amber : Colors.green;

                      return Positioned(
                        top: top,
                        left: 70, // After time labels
                        right: 12,
                        height: durationHeight,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => widget.onViewSchedule(de.displayTime, TimeOfDay.fromDateTime(de.displayTime)),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                border: Border(left: BorderSide(color: color, width: 4)),
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    de.event.title,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: color.withOpacity(0.8), // Darker text
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (de.event.intent != null)
                                    Text(
                                      de.event.intent!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),

                    // Current Time Indicator (Red Line)
                    Positioned(
                      top: (now.hour * _hourHeight) + (now.minute * (_hourHeight / 60)),
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 8),
                            child: const Text(
                              "NOW",
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 10,
                                fontWeight: FontWeight.bold
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(color: Colors.red, thickness: 1.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DisplayEvent {
  final Event event;
  final DateTime displayTime;
  
  _DisplayEvent({required this.event, required this.displayTime});
}
