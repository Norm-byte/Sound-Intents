import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Added for Timer
import '../../models/event.dart';
// import '../widgets/dashboard_clock.dart'; // Removed

class DashboardTab extends StatefulWidget {
  final List<Event> events;
  final VoidCallback onCreateEvent;
  final Function(DateTime?, TimeOfDay?) onViewSchedule;
  final Function(Event) onEditEvent;
  final Function(Event) onDeleteEvent;
  final Function(List<Event>)? onImportEvents;
  final Function(int weekOffset)? onPublishWeek;
  final Function(int weekOffset, int? minuteFilter)? onClearWeek; // Updated callback
  final Function(Event)? onPublishEvent;

  const DashboardTab({
    super.key,
    required this.events,
    required this.onCreateEvent,
    required this.onViewSchedule,
    required this.onEditEvent,
    required this.onDeleteEvent,
    this.onImportEvents,
    this.onPublishWeek,
    this.onClearWeek, // New
    this.onPublishEvent,
  });

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  // Timer for the digital clock
  Timer? _timer;
  DateTime _now = DateTime.now();

  // Track the selected minute offset for each week card (0, 15, 30, 45)
  // Key: weekOffset, Value: minute (0, 15, 30, 45)
  final Map<int, int> _weekViewOffset = {};

  @override
  void initState() {
    super.initState();
    _startClock();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startClock() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Simplify access to widget props
    final events = widget.events;
    
    final totalEvents = events.length;
    final published = events.where((e) => e.isPublished).length;
    final drafts = events.where((e) => e.isDraft).length;
    final recentEvents = events.take(5).toList();

    void exportEvents() async {
      final jsonData = jsonEncode(events.map((e) => e.toJson()).toList());
      await Clipboard.setData(ClipboardData(text: jsonData));
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Events Exported'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('JSON copied to clipboard. Paste into a file to save.'),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: SelectableText(jsonData, style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Export copied to clipboard'), backgroundColor: Colors.green),
        );
      }
    }

    Future<void> importEvents() async {
      try {
        final result = await FilePicker.platform.pickFiles(withData: true, type: FileType.custom, allowedExtensions: const ['json']);
        final file = result?.files.single;
        if (file == null || file.bytes == null) return;
        final jsonString = utf8.decode(file.bytes!);
        final List<dynamic> jsonList = jsonDecode(jsonString);
        final importedEvents = jsonList.map((j) => Event.fromJson(j as Map<String, dynamic>)).toList();
        if (widget.onImportEvents != null) {
          widget.onImportEvents!(importedEvents);
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Imported ${importedEvents.length} events'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          
          // Stats Cards
          SizedBox(
            height: 190, // Increased height to prevent overflow
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _StatCard(
                    title: 'Total Events',
                    value: '$totalEvents',
                    icon: Icons.event,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _StatCard(
                    title: 'Published',
                    value: '$published',
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                // National Participation (Moved from left column)
                Expanded(
                  child: _NationalParticipationCard(),
                ),
                const SizedBox(width: 16),
                // Trending Intent (Enhanced) REPLACED by Admin Alerts
                Expanded(
                  flex: 2, // Give it more space
                  child: const _AdminAlertsCard(), // Renamed from _TrendingIntentCard
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          _buildSchedulerStatus(context),
          
          const SizedBox(height: 32),
          
          _buildWorldwideEventStatus(context),

        ],
      ),
    );
  }

  // New Widget: 52-Week "Year Command Center"
  Widget _buildWeekCards(BuildContext context) {
    
    // 1. Calculate Current Week Info
    final now = DateTime.now();
    // Get the first monday of the year? Or just start Jan 1st?
    // User logic: "Jan 1st would obviously be week1"
    // We'll align cards to Week Blocks starting from Jan 1st?
    // But usually weeks start on Monday. The existing logic used "Today + Offset".
    // Let's standardise on ISO 8601 weeks (Monday start) or simple "Jan 1 + 7 days".
    // Sticking to Monday-based weeks is safer for a "Schedule".
    
    // Let's align to the *current year's* structure.
    final firstDayOfYear = DateTime.utc(now.year, 1, 1);
    final daysOffset = firstDayOfYear.weekday - 1; // 0=Mon, 6=Sun
    final firstMondayOfYear = firstDayOfYear.subtract(Duration(days: daysOffset));
    
    // Calculate current week index (0-based)
    // We treat the week containing "Today" as the current week.
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    final diffDays = todayUtc.difference(firstMondayOfYear).inDays;
    final currentWeekIndex = (diffDays / 7).floor();

    // Scroll Controller to jump to current week
    final scrollController = ScrollController(
      initialScrollOffset: (currentWeekIndex * 190.0).clamp(0.0, double.infinity), // Approx card height + padding
    );

    return SizedBox(
      height: 600, // Fixed height for the scrolling area
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                const Icon(Icons.calendar_view_week, color: Colors.blue),
                const SizedBox(width: 8),
                Text('Year Command Center (${now.year})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton(
                  onPressed: () {
                     scrollController.animateTo(
                       currentWeekIndex * 190.0, 
                       duration: const Duration(milliseconds: 500), 
                       curve: Curves.easeInOut
                     );
                  },
                  child: const Text('Jump to Today'),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: 52, // 52 Weeks standard
              padding: const EdgeInsets.only(right: 12),
              itemBuilder: (context, index) {
                // Calculate Week Date Range
                final weekStart = firstMondayOfYear.add(Duration(days: 7 * index));
                final weekEnd = weekStart.add(const Duration(days: 7));
                
                final isPast = index < currentWeekIndex;
                final isCurrent = index == currentWeekIndex;
                
                // Determine Offset for existing logic (0 = This Week, 1 = Next Week...)
                // Existing logic expects 0 to be "Today's Week".
                // So pass (index - currentWeekIndex) as the weekOffset.
                final logicOffset = index - currentWeekIndex;
                
                // Visual Styles
                final opacity = isPast ? 0.5 : 1.0;
                final cardColor = isCurrent ? Colors.blue.withOpacity(0.05) : null;
                final border = isCurrent ? Border.all(color: Colors.blue, width: 2) : null;
                
                return Opacity(
                  opacity: opacity,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                       color: cardColor,
                       borderRadius: BorderRadius.circular(12),
                       border: border,
                    ),
                    child: _buildSingleWeekCard(
                      "Week ${index + 1}", 
                      logicOffset, 
                      subtitle: isCurrent ? "(Current)" : (isPast ? "(Completed)" : null)
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleWeekCard(String label, int weekOffset, {String? subtitle}) {
    final int currentOffset = _weekViewOffset[weekOffset] ?? 0;
    
    // 1. Calculate Time Range (Aligned to Monday)
    // NOTE: This logic recalculates based on 'Today + 7*offset'.
    // Since we passed (index - currentWeekIndex) as offset, this correctly effectively reconstructs the absolute date.
    final now = DateTime.now().toUtc();
    final todayRaw = DateTime.utc(now.year, now.month, now.day);
    final daysSinceMonday = todayRaw.weekday - 1; // weekday 1=Mon
    final thisWeekMonday = todayRaw.subtract(Duration(days: daysSinceMonday));
    
    final weekStart = thisWeekMonday.add(Duration(days: 7 * weekOffset));
    final weekEnd = weekStart.add(const Duration(days: 7)); // Exclusive

    // 2. Pre-process events for this week to determine "Active Slots" (Glowing Indicators)
    // We need to know if there is ANY content for 00, 15, 30, 45 in this week.
    final Map<int, bool> hasContentAt = {0: false, 15: false, 30: false, 45: false};
    final Map<int, bool> hasDraftsAt = {0: false, 15: false, 30: false, 45: false};

    // Filter events strictly within this week range
    final weekEvents = widget.events.where((e) {
      if (e.type == 'global') return false; 
      if (e.startTimeUTC == null) return false;
      try {
        final start = DateTime.parse(e.startTimeUTC!);
        final inRange = start.isAfter(weekStart.subtract(const Duration(seconds: 1))) && 
                        start.isBefore(weekEnd);
        return inRange || (e.isRecurring == true);
      } catch (_) { return false; }
    }).toList();

    // Analyze minute slots
    for (var e in weekEvents) {
      try {
         final start = DateTime.parse(e.startTimeUTC!);
         final minute = start.minute;
         // Normalize minute to nearest bucket if needed, or exact match?
         // Assuming users create events exactly at 0, 15, 30, 45 or close to it.
         // Let's use strict mapping:
         if (hasContentAt.containsKey(minute)) {
             hasContentAt[minute] = true;
             if (!e.isPublished) hasDraftsAt[minute] = true;
         }
      } catch (_) {}
    }

    // 3. Build dots for the CURRENTLY selected offset view
    // Map hour (0-23) to status: 0=Empty, 1=Published, 2=Draft
    Map<int, int> currentViewHourStatus = {};
    
    // Filter events again for the *selected* view (currentOffset)
    final eventsInCurrentView = weekEvents.where((e) {
       try {
         final start = DateTime.parse(e.startTimeUTC!);
         return start.minute == currentOffset;
       } catch (_) { return false; }
    }).toList();

    for (var e in eventsInCurrentView) {
      try {
        final start = DateTime.parse(e.startTimeUTC!);
        final current = currentViewHourStatus[start.hour] ?? 0;
        // Prioritize Draft (2) 
        if (!e.isPublished) {
            currentViewHourStatus[start.hour] = 2;
        } else if (current != 2) {
            currentViewHourStatus[start.hour] = 1;
        }
      } catch (_) {}
    }

    // Has drafts in the current view? (For current view button color if we wanted, 
    // but the request is for the main Sync button to reflect *general* status per week maybe? 
    // User: "i can also see that there is something maybe a draft... but that there is something there it would glow")
    // Let's check if there are drafts *anywhere* in the week for the main SYNC button?
    // Or just for the current view? Usually Sync applies to the whole week context.
    // Let's assume global week drafts for the main button color.
    final bool anyDraftsInWeek = hasDraftsAt.values.any((v) => v);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // LEFT SIDE: Label + Main Actions + Grid
            Expanded(
              child: Column(
                children: [
                  // Header Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Label
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              if (subtitle != null) ...[
                                const SizedBox(width: 8),
                                Text(subtitle, style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.blueGrey)),
                              ]
                            ],
                          ),
                          Text(
                            "${DateFormat('MMM d').format(weekStart)} - ${DateFormat('MMM d').format(weekEnd.subtract(const Duration(days: 1)))}",
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      
                      // Actions (Trash + Sync) - Moved Left as requested
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            tooltip: 'Clear Week (Selected View)',
                            onPressed: () {
                              if (widget.onClearWeek != null) widget.onClearWeek!(weekOffset, currentOffset);
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                                if (widget.onPublishWeek != null) widget.onPublishWeek!(weekOffset);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Publishing $label..."))
                                );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: anyDraftsInWeek ? Colors.amber.shade800 : Colors.blue, // Amber for drafts
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (anyDraftsInWeek) const Padding(
                                  padding: EdgeInsets.only(right: 6.0),
                                  child: Icon(Icons.warning_amber_rounded, size: 16),
                                ),
                                Text(anyDraftsInWeek ? "Publish Drafts" : "Sync", style: const TextStyle(fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // DOTS GRID (For Current Selection)
                  SizedBox(
                    height: 35,
                    child: GridView.builder(
                      scrollDirection: Axis.horizontal,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 1, 
                        mainAxisSpacing: 6,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: 24,
                      itemBuilder: (context, index) {
                         final status = currentViewHourStatus[index] ?? 0;
                         // 1: Published (Green), 2: Draft (Amber)
                         Color dotColor = Colors.grey[300]!;
                         if (status == 1) dotColor = Colors.greenAccent[400]!;
                         if (status == 2) dotColor = Colors.orangeAccent;
                         
                         // Visual tweaks for empty state
                         if (status == 0) dotColor = Colors.grey.shade100;
                         
                         return InkWell(
                           onTap: () {
                              // Navigate
                              final targetDate = weekStart.add(Duration(hours: index, minutes: currentOffset));
                              final targetTime = TimeOfDay(hour: index, minute: currentOffset);
                              widget.onViewSchedule(targetDate, targetTime);
                           },
                           child: Container(
                             decoration: BoxDecoration(
                               shape: BoxShape.circle,
                               color: dotColor,
                               border: Border.all(
                                 color: status > 0 ? Colors.transparent : Colors.grey.shade300,
                                 width: 1
                               ),
                               boxShadow: status > 0 ? [
                                 BoxShadow(color: dotColor.withOpacity(0.6), blurRadius: 4, spreadRadius: 1)
                               ] : null,
                             ),
                             child: Center(
                                child: Text("$index", 
                                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold,
                                  color: status > 0 ? Colors.white : Colors.grey[400]))
                             ),
                           ),
                         );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),
            Container(width: 1, height: 80, color: Colors.grey.shade200),
            const SizedBox(width: 8),

            // RIGHT SIDE: Vertical Indicators (00, 15, 30, 45)
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildMinuteToggle(0, currentOffset, hasContentAt[0]!, hasDraftsAt[0]!, weekOffset, Icons.access_time),
                const SizedBox(height: 8),
                _buildMinuteToggle(15, currentOffset, hasContentAt[15]!, hasDraftsAt[15]!, weekOffset, null, "15"),
                const SizedBox(height: 8),
                _buildMinuteToggle(30, currentOffset, hasContentAt[30]!, hasDraftsAt[30]!, weekOffset, null, "1/2"),
                const SizedBox(height: 8),
                _buildMinuteToggle(45, currentOffset, hasContentAt[45]!, hasDraftsAt[45]!, weekOffset, null, "45"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMinuteToggle(
      int minute, int currentSelection, bool hasContent, bool hasDrafts, int weekOffset, [IconData? icon, String? text]) {
    
    final isSelected = minute == currentSelection;
    
    // Glow Color Logic
    Color? glowColor;
    if (hasDrafts) glowColor = Colors.amber;
    else if (hasContent) glowColor = Colors.green;
    
    return InkWell(
      onTap: () {
        setState(() {
          _weekViewOffset[weekOffset] = minute;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigo.shade50 : (glowColor?.withOpacity(0.1) ?? Colors.transparent),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
             color: isSelected 
                 ? Colors.indigo 
                 : (glowColor ?? Colors.grey.shade300),
             width: isSelected ? 2 : 1.5
          ),
          boxShadow: glowColor != null ? [
            BoxShadow(color: glowColor.withOpacity(0.4), blurRadius: 6, spreadRadius: 0)
          ] : null,
        ),
        child: Center(
          child: icon != null 
            ? Icon(icon, size: 18, color: isSelected ? Colors.indigo : (glowColor ?? Colors.grey))
            : Text(
                text ?? "",
                style: TextStyle(
                  fontSize: 10, 
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.indigo : (glowColor ?? Colors.grey)
                ),
              ),
        ),
      ),
    );
  }

  // Old code commented out or removed for brevity...
  /*
  Widget _buildSingleWeekCard_OLD(String label, int weekOffset) {
    /* ... existing implementation ... */
  } 
  */

  Widget _buildSchedulerStatus(BuildContext context) {
      // Replaced old Timeline with new Layout (No Clock)
      return Container(
          decoration: BoxDecoration(
             color: Colors.grey[50],
             borderRadius: BorderRadius.circular(16),
             border: Border.all(color: Colors.grey.shade200)
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
              children: [
                  const Text("Schedule Overview", style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0
                  )),
                  const SizedBox(height: 16),
                  _buildWeekCards(context),
              ],
          ),
      );
  }

  Widget _buildWorldwideEventStatus(BuildContext context) {
    // Show ACTIVE PUBLISHED Global Events AND Draft Global Events
    final now = DateTime.now().toUtc();
    final events = widget.events; 

    final activeEvents = events.where((e) {
      if (e.type != 'global') return false;
      
      // Always show drafts
      if (e.isDraft || !e.isPublished) return true;
      
      final isRecurring = e.recurrenceType != null && e.recurrenceType != 'None';
      if (isRecurring) return true;

      // ... (rest of the detailed active check for published events)
      if (e.startTimeUTC != null) {
        try {
          var start = DateTime.parse(e.startTimeUTC!);
          if (!start.isUtc) {
             start = DateTime.utc(start.year, start.month, start.day, start.hour, start.minute, start.second);
          }
          final duration = Duration(seconds: e.durationSeconds ?? 3600); 
          final end = start.add(duration);
          final isActive = end.isAfter(now); 
          
          return isActive;
        } catch (err) {
          return false;
        }
      }
      return false; // Published checks failed?
    }).toList();

    activeEvents.sort((a, b) => (a.startTimeUTC ?? '').compareTo(b.startTimeUTC ?? ''));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Worldwide Event Status',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (activeEvents.isEmpty)
              const SizedBox(
                height: 350,
                child: Center(
                  child: Text('No active worldwide events.',
                      style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              SizedBox(
                height: 350,
                child: ListView.separated(
                  padding: const EdgeInsets.only(right: 8), 
                  itemCount: activeEvents.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = activeEvents[index];
                    final startTime = event.startTimeUTC != null 
                        ? DateTime.parse(event.startTimeUTC!).toLocal() 
                        : DateTime.now();
                    
                    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
                    final dateStr = '${months[startTime.month - 1]} ${startTime.day}, ${startTime.year}';
                    final timeStr = '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}';
                    
                    final isRecurring = event.recurrenceType != null && event.recurrenceType != 'None';
                    final isDraft = !event.isPublished || event.isDraft;
                    final baseColor = isDraft ? Colors.grey : (isRecurring ? Colors.amber : Colors.green);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: baseColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: baseColor.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: baseColor.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(isDraft ? Icons.edit_note : (isRecurring ? Icons.loop : Icons.public), color: baseColor, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(event.title,
                                        style: const TextStyle(
                                            fontSize: 16, fontWeight: FontWeight.bold)),
                                    if (event.intent != null)
                                      Text('Intent: ${event.intent}',
                                          style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: baseColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(isDraft ? 'DRAFT' : (isRecurring ? 'RECURRING' : 'LIVE'),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 16, color: Colors.black87),
                              const SizedBox(width: 6),
                              Text('$dateStr at $timeStr', style: const TextStyle(fontSize: 14, color: Colors.black87, fontWeight: FontWeight.w500)),
                              const Spacer(),
                              if (isDraft)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                       if (widget.onPublishEvent != null) {
                                         widget.onPublishEvent!(event);
                                       }
                                    },
                                    icon: const Icon(Icons.send, size: 14),
                                    label: const Text('Publish'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      minimumSize: Size.zero,
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ),
                              OutlinedButton.icon(
                                onPressed: () => widget.onEditEvent(event),
                                icon: const Icon(Icons.edit, size: 14),
                                label: const Text('Manage'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: baseColor,
                                  side: BorderSide(color: baseColor),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                                onPressed: () => widget.onDeleteEvent(event),
                                tooltip: 'Delete Event',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NationalParticipationCard extends StatelessWidget {
  const _NationalParticipationCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('National Participation', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
            const Spacer(),
            Row(
              children: [
                Text('70%', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                const SizedBox(width: 8),
                const Text('Active', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 0.7,
              backgroundColor: Colors.grey.shade200,
              color: Colors.blue,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const Spacer(),
            const Text('Next: Peace Meditation (18:00)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _AdminAlertsCard extends StatefulWidget {
  const _AdminAlertsCard();

  @override
  State<_AdminAlertsCard> createState() => _AdminAlertsCardState();
}

class _AdminAlertsCardState extends State<_AdminAlertsCard> {
  bool _isLoading = false;
  
  // Mock Alert Data
  int _supportMessages = 0;
  int _moderationQueue = 0;

  @override
  void initState() {
    super.initState();
    _checkAlerts();
  }

  Future<void> _checkAlerts() async {
    setState(() => _isLoading = true);
    // Simulate API Check
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      setState(() {
        _supportMessages = 3; // Mock: 3 unread messages
        _moderationQueue = 1; // Mock: 1 item to moderate
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Basic severity check
    final hasAlerts = _supportMessages > 0 || _moderationQueue > 0;
    final cardColor = hasAlerts ? Colors.orange.shade50 : Colors.white;

    return Card(
      elevation: 2,
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active, color: hasAlerts ? Colors.orange : Colors.grey, size: 24),
                const SizedBox(width: 8),
                const Text('Admin Alerts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
                  onPressed: _checkAlerts,
                  tooltip: 'Refresh Alerts',
                ),
              ],
            ),
            const Divider(),
            if (_isLoading)
               const Expanded(child: Center(child: CircularProgressIndicator()))
            else
               Expanded(
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     _buildAlertRow(Icons.support_agent, 'Customer Support', _supportMessages, 'New Messages'),
                     const SizedBox(height: 12),
                     _buildAlertRow(Icons.gavel, 'Moderation Queue', _moderationQueue, 'Pending Review'),
                   ],
                 ),
               ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertRow(IconData icon, String title, int count, String label) {
    final hasCount = count > 0;
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blueGrey),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        if (hasCount)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count $label', 
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          )
        else
           const Text('All Clear', style: TextStyle(color: Colors.green, fontSize: 12, fontStyle: FontStyle.italic)),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 32),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _SchedulerView extends StatefulWidget {
  final List<Event> events;
  final Function(DateTime?, TimeOfDay?) onViewSchedule;

  const _SchedulerView({
    super.key,
    required this.events,
    required this.onViewSchedule,
  });

  @override
  State<_SchedulerView> createState() => _SchedulerViewState();
}

class _SchedulerViewState extends State<_SchedulerView> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);

    return SizedBox(
      height: 350,
      child: Scrollbar(
        controller: _controller,
        thumbVisibility: true,
        child: ListView.separated(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: 8,
          separatorBuilder: (ctx, i) => const SizedBox(height: 12),
          itemBuilder: (context, rowIndex) {
            final startHour = rowIndex * 3;
            final label = '${startHour.toString().padLeft(2, '0')}:00';

            return Row(
              children: [
                SizedBox(
                  width: 40,
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 12,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, colIndex) {
                      final hour = startHour + (colIndex ~/ 4);
                      final minute = (colIndex % 4) * 15;
                      
                      Event? slotEvent;
                      try {
                        slotEvent = widget.events.firstWhere((e) {
                          // Filter out Global events from the 24-hour schedule
                          if (e.type == 'global') return false;

                          if (e.startTimeUTC == null) return false;
                          final start = DateTime.parse(e.startTimeUTC!);
                          
                          // Check time match
                          final timeMatch = start.hour == hour && start.minute >= minute && start.minute < minute + 15;
                          if (!timeMatch) return false;

                          // Check date match OR recurrence
                          final dateMatch = start.year == today.year && start.month == today.month && start.day == today.day;
                          // Fix: Check recurrenceType as well, as isRecurring might be false/null for legacy events
                          final isRecurring = (e.isRecurring == true) || (e.recurrenceType != null && e.recurrenceType != 'None');

                          // If it's recurring, we only care about the time match (which is already checked above)
                          // If it's NOT recurring, we need the date to match today
                          if (isRecurring) return true;
                          return dateMatch;
                        });
                      } catch (_) {}

                      Color color = Colors.grey.shade200;
                      if (slotEvent != null) {
                        final nowLocal = DateTime.now();
                        final updatedAtStr = slotEvent.updatedAt;
                        
                        if (updatedAtStr != null) {
                          final updatedAt = DateTime.parse(updatedAtStr);
                          final diff = nowLocal.difference(updatedAt).inDays;
                          
                          if (diff < 1) {
                            color = Colors.green;
                          } else if (diff < 5) {
                            color = Colors.amber;
                          } else {
                            color = Colors.red;
                          }
                        } else {
                          final start = DateTime.parse(slotEvent.startTimeUTC!);
                          if (start.isAfter(nowLocal)) {
                            color = Colors.green; 
                          } else {
                            color = Colors.amber; 
                          }
                        }
                      }

                      return Tooltip(
                        message: '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}${slotEvent != null ? ' - ${slotEvent.title}' : ''}',
                        child: InkWell(
                          onTap: () {
                            final targetDate = today.add(Duration(hours: hour, minutes: minute));
                            widget.onViewSchedule(targetDate, TimeOfDay(hour: hour, minute: minute));
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
