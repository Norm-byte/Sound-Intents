import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Added for Timer
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/event.dart';
import '../widgets/active_operators_card.dart'; // Added for Active Operators
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
  // NOTE: This is also used by the "Year Command Center"
  final Map<int, int> _weekViewOffset = {};
  
  // Dashboard Status Card State
  int _selectedNationalOffset = 0; // 0, 15, 30, 45

  // Automation / System State
  bool _isAutoSystemEnabled = false; // "Auto-Publish" Toggle (Current + 3)

  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    
    // Calculate initial scroll position (Jump to Current Week)
    final now = DateTime.now();
    final firstDayOfYear = DateTime.utc(now.year, 1, 1);
    final daysOffset = firstDayOfYear.weekday - 1; 
    final firstMondayOfYear = firstDayOfYear.subtract(Duration(days: daysOffset));
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    final diffDays = todayUtc.difference(firstMondayOfYear).inDays;
    final currentWeekIndex = (diffDays / 7).floor();
    
    _scrollController = ScrollController(
      initialScrollOffset: (currentWeekIndex * 190.0).clamp(0.0, double.infinity),
    );
    
    _startClock();

    // Load persisted state for Auto-System
    _loadAutoSystemState();
  }

  Future<void> _loadAutoSystemState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('auto_system_enabled') ?? true;
      if (mounted) {
        setState(() => _isAutoSystemEnabled = enabled);
        if (enabled) {
          // Delay to ensure frame is ready for SnackBars etc.
          WidgetsBinding.instance.addPostFrameCallback((_) {
             _checkAutoSystemRules();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading auto-system state: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
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
  
  // Implementation of "Auto-System" (Current + 3) Rule
  // This simulates the behavior requested:
  // "if active, check if the 5th week (Current+4) is filled (glowing Amber)... take the vacant place of the 4th... keeping Current+3"
  // Auto-System: "Current week published + Next week as draft"
  // - If we have crossed into a new week and drafts exist for it → auto-publish them.
  // - If next week is empty → auto-copy current week events as unpublished draft.
  // - Never more than 1 published week at a time, preventing duplicate notice boards.
  void _checkAutoSystemRules() {
    final now = DateTime.now();
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    final daysSinceMonday = todayUtc.weekday - 1;
    final thisWeekStart = todayUtc.subtract(Duration(days: daysSinceMonday));
    final nextWeekStart = thisWeekStart.add(const Duration(days: 7));
    final nextNextWeekStart = nextWeekStart.add(const Duration(days: 7));

    // Events whose startTimeUTC falls in next week's range
    final nextWeekEvents = widget.events.where((e) {
      if (e.startTimeUTC == null) return false;
      final start = DateTime.parse(e.startTimeUTC!);
      return !start.isBefore(nextWeekStart) && start.isBefore(nextNextWeekStart);
    }).toList();

    final nextWeekDrafts = nextWeekEvents.where((e) => e.isDraft == true).toList();
    final nextWeekPublished = nextWeekEvents.where((e) => e.isPublished == true).toList();

    // STEP 1: We have crossed into what was "next week" — publish those drafts now.
    if (!todayUtc.isBefore(nextWeekStart) && nextWeekDrafts.isNotEmpty) {
      widget.onPublishWeek?.call(0); // offset 0 = current week (formerly next week)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Auto-System: Published ${nextWeekDrafts.length} events for the new week.'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
      return;
    }

    // STEP 2: Next week has no content yet — auto-create draft from current week.
    if (nextWeekDrafts.isEmpty && nextWeekPublished.isEmpty) {
      final currentWeekEvents = widget.events.where((e) {
        if (e.startTimeUTC == null) return false;
        final start = DateTime.parse(e.startTimeUTC!);
        return !start.isBefore(thisWeekStart) && start.isBefore(nextWeekStart) && e.isPublished == true;
      }).toList();

      if (currentWeekEvents.isNotEmpty) {
        _handleDirectCopyPaste(currentWeekEvents, nextWeekStart, 'Next Week (Auto-Draft)');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Auto-System: Created ${currentWeekEvents.length} draft events for next week.'),
          backgroundColor: Colors.amber.shade800,
          duration: const Duration(seconds: 4),
        ));
      }
      return;
    }

    // STEP 3: Next week already has a draft — all is well.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Auto-System: Next week has ${nextWeekDrafts.length} draft(s) ready to go.'),
      backgroundColor: Colors.indigo,
      duration: const Duration(seconds: 3),
    ));
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
            height: 190, 
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Worldwide Events Card (Left)
                Expanded(
                  flex: 3,
                  child: _WorldwideEventsCard(events: events),
                ),
                const SizedBox(width: 16),
                
                // National Events Card (Right) - Replacing Published/Total
                Expanded(
                  flex: 4, // Reduced slightly to fit operators
                  child: _NationalEventsCard(
                    events: events,
                    selectedOffset: _selectedNationalOffset,
                    onOffsetChanged: (val) => setState(() => _selectedNationalOffset = val),
                    onJumpToAttention: () {
                         // Find first week with incomplete data for this offset
                         ScaffoldMessenger.of(context).showSnackBar(
                           const SnackBar(content: Text("Jump to Attention: Moving to nearest incomplete week... (Logic Placeholder)")),
                         );
                    },
                  ),
                ),

                const SizedBox(width: 16),

                // Active Operators (New)
                const Expanded(
                  flex: 2,
                  child: ActiveOperatorsCard(),
                ),

                const SizedBox(width: 16),
                // Admin Alerts
                Expanded(
                  flex: 2, 
                  child: const _AdminAlertsCard(),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          // Community Pulse (Trending Intent) Row
          // Removed fixed height because "System Calculated" field makes it dynamic
            Row(
              children: [
                Expanded(
                  child: _TrendingIntentCard(),
                ),
              ],
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
    final firstDayOfYear = DateTime.utc(now.year, 1, 1);
    final daysOffset = firstDayOfYear.weekday - 1; 
    final firstMondayOfYear = firstDayOfYear.subtract(Duration(days: daysOffset));
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    final diffDays = todayUtc.difference(firstMondayOfYear).inDays;
    final currentWeekIndex = (diffDays / 7).floor();

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
                // NEW: Automation Status - "Auto-System" Toggle
                // "if active, the app will check to see if the week 5th is filled..."
                InkWell(
                  onTap: () async {
                    final newValue = !_isAutoSystemEnabled;
                    setState(() => _isAutoSystemEnabled = newValue);
                    
                    // Persist state
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('auto_system_enabled', newValue);

                    if (_isAutoSystemEnabled) {
                      _checkAutoSystemRules(); // Run check immediately
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_isAutoSystemEnabled ? 'Auto-System ACTIVATED: Managing current week + next week draft...' : 'Auto-System DEACTIVATED: Manual control only.'),
                          duration: const Duration(seconds: 2),
                          backgroundColor: _isAutoSystemEnabled ? Colors.green : Colors.orange,
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: _isAutoSystemEnabled ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                      border: Border.all(color: _isAutoSystemEnabled ? Colors.green : Colors.grey),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isAutoSystemEnabled ? Icons.autorenew : Icons.pause_circle_outline, 
                          color: _isAutoSystemEnabled ? Colors.green : Colors.grey, 
                          size: 16
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isAutoSystemEnabled ? 'Auto-System: ON' : 'Auto-System: PAUSED', 
                          style: TextStyle(
                            color: _isAutoSystemEnabled ? Colors.green : Colors.grey, 
                            fontWeight: FontWeight.bold, 
                            fontSize: 12
                          )
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                TextButton(
                  onPressed: () {
                     _scrollController.animateTo(
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
              controller: _scrollController,
              itemCount: 52, // 52 Weeks standard
              padding: const EdgeInsets.only(right: 12),
              itemBuilder: (context, index) {
                // Calculate Week Date Range
                final weekStart = firstMondayOfYear.add(Duration(days: 7 * index));
                // ignore: unused_local_variable
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
                      subtitle: isCurrent ? "(Current)" : (isPast ? "(Completed)" : null),
                      showCleanUpAction: isPast, // NEW: Only show Clone action for past/completed weeks
                      currentWeekIndex: currentWeekIndex,
                      scrollController: _scrollController,
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


  Widget _buildSingleWeekCard(String label, int weekOffset, {String? subtitle, bool showCleanUpAction = false, int? currentWeekIndex, ScrollController? scrollController}) {
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
        return inRange;
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
    // Map hour (0-23) to status: 0=Empty, 1=Published, 2=Draft, 3=Completed
    Map<int, int> currentViewHourStatus = {};
    final isPastWeek = weekOffset < 0;
    
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

        // Prioritize Draft (2) > Completed/Amber (3) > Published (1)
        if (!e.isPublished) {
          currentViewHourStatus[start.hour] = 2;
        } else if (isPastWeek || (start.weekday == DateTime.sunday && start.isBefore(now))) {
          // Past week OR Sunday slot that has already passed → amber
          if (current != 2) currentViewHourStatus[start.hour] = 3;
        } else {
          if (current != 2 && current != 3) currentViewHourStatus[start.hour] = 1;
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
                          // Dropdown for Week Actions
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: Colors.grey),
                            tooltip: 'Week Actions',
                            onSelected: (value) async {
                               if (value == 'copy_to') {
                                 // Show Copy To Dialog
                                 final targetWeekStr = await _showCopyToDialog(context, weekStart.year);
                                 if (targetWeekStr != null) {
                                   int targetWeekNum = int.parse(targetWeekStr);
                                   // Calculate target date (Assuming Week 1 is index 0 in list)
                                   // Week 1 = Index 0 = weekStart + (targetWeekNum - (index+1)) * 7 ??
                                   // Simpler: The dialog returns just the NUMBER (1-52).
                                   // Find the current week number (label "Week X" -> X).
                                   final currentWeekNum = int.parse(label.replaceAll(RegExp(r'[^0-9]'), ''));
                                   final diffWeeks = targetWeekNum - currentWeekNum;
                                   
                                   final targetStartDate = weekStart.add(Duration(days: 7 * diffWeeks));
                                   final targetLabel = "Week $targetWeekNum";
                                   
                                   // We use the clipboard logic but bypass the actual clipboard buffer? 
                                   // Or just fill clipboard and paste immediately?
                                   // Ideally: direct transfer.
                                   _handleDirectCopyPaste(weekEvents, targetStartDate, targetLabel);
                                 }
                               }
                            },
                            itemBuilder: (BuildContext context) {
                              return [
                                const PopupMenuItem(
                                  value: 'copy_to',
                                  child: Row(
                                    children: [
                                      Icon(Icons.drive_file_move_outline, size: 18, color: Colors.blue),
                                      SizedBox(width: 8),
                                      Text('Copy To Week...'),
                                    ],
                                  ),
                                ),
                              ];
                            },
                          ),
                          if (anyDraftsInWeek) ...[
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () {
                                  if (widget.onPublishWeek != null) widget.onPublishWeek!(weekOffset);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text("Publishing $label..."))
                                  );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(right: 6.0),
                                    child: Icon(Icons.warning_amber_rounded, size: 16),
                                  ),
                                  Text("Publish Drafts", style: TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  
                  // NEW: Cleanup/Clone Action for Past Items
                  if (showCleanUpAction) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history, color: Colors.amber, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(child: Text("Completed Week", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.indigo,
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                            icon: const Icon(Icons.copy, size: 14),
                            label: const Text("Clone to +4 Weeks", style: TextStyle(fontSize: 12)),
                            onPressed: () {
                               // AUTOMATION LOGIC: Current Week + 4
                               // 1. Capture events
                               if (weekEvents.isNotEmpty) {
                                    // 2. Calculate target offset
                                    final targetOffset = weekOffset + 4;
                                    
                                    if (currentWeekIndex != null && scrollController != null) {
                                      final targetWeekIndex = currentWeekIndex + targetOffset;

                                      // 3. Auto-Jump: Scroll to the target week
                                      if (targetWeekIndex < 52) {
                                        scrollController.animateTo(
                                          (targetWeekIndex * 190.0), // Approximate height
                                          duration: const Duration(seconds: 1),
                                          curve: Curves.easeInOut,
                                        );
                                        
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text("Copied! Jumping to Week ${targetWeekIndex + 1}... Click PASTE there."),
                                            duration: const Duration(seconds: 3),
                                            backgroundColor: Colors.indigo,
                                          )
                                        );
                                      } else {
                                         ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text("Target week is beyond this year!"))
                                         );
                                      }
                                    }
                                }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                  
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
                         // 1: Published (Green), 2: Draft (Amber/Orange), 3: Completed (Amber)
                         Color dotColor = Colors.grey[300]!;
                         if (status == 1) dotColor = Colors.greenAccent[400]!;
                         if (status == 2) dotColor = Colors.orangeAccent;
                         if (status == 3) dotColor = Colors.amber;
                         
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



  void _handleDirectCopyPaste(List<Event> srcEvents, DateTime targetWeekStart, String targetLabel) {
     if (srcEvents.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Source week is empty.")));
        return;
     }

     final newEvents = _cloneEventsToWeek(srcEvents, targetWeekStart);
     if (newEvents.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text("No events were copied.")),
       );
       return;
     }

     if (widget.onImportEvents != null) {
       widget.onImportEvents!(newEvents);
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
           content: Text("Pasted ${newEvents.length} drafts into $targetLabel"),
           backgroundColor: Colors.amber.shade800,
         ),
       );
     }
  }

  List<Event> _cloneEventsToWeek(List<Event> srcEvents, DateTime targetWeekStart) {
    if (srcEvents.isEmpty) return [];

    final first = DateTime.parse(srcEvents.first.startTimeUTC!);
    final daysSinceMon = first.weekday - 1;
    final sourceWeekStart = DateTime.utc(first.year, first.month, first.day)
        .subtract(Duration(days: daysSinceMon));

    final daysDiff = targetWeekStart.difference(sourceWeekStart).inDays;
    final List<Event> newEvents = [];

    for (final srcEvent in srcEvents) {
      try {
        final srcStart = DateTime.parse(srcEvent.startTimeUTC!);
        final newStart = srcStart.add(Duration(days: daysDiff));

        // New ID per copied slot+date, preserving all other event payload fields.
        final slot =
            '${newStart.hour.toString().padLeft(2, '0')}${newStart.minute.toString().padLeft(2, '0')}';
        final dateSuffix =
            '${newStart.year}${newStart.month.toString().padLeft(2, '0')}${newStart.day.toString().padLeft(2, '0')}';
        final newId = 'copy_${slot}_$dateSuffix';

        newEvents.add(
          srcEvent.copyWith(
            id: newId,
            startTimeUTC: newStart.toIso8601String(),
            isPublished: false,
            isDraft: true,
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );
      } catch (e) {
        debugPrint("Error copying event: $e");
      }
    }

    return newEvents;
  }

  Future<String?> _showCopyToDialog(BuildContext context, int year) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Copy to Week...'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: 52,
              itemBuilder: (context, index) {
                final weekNum = index + 1;
                return ListTile(
                  title: Text('Week $weekNum'),
                  subtitle: Text('Year $year'), // Could add date range here if calc was easy
                  onTap: () {
                    Navigator.pop(context, weekNum.toString());
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ],
        );
      },
    );
  }

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
    // Show ALL Global Events (Active, Draft, Past, Future) to allow full management
    final now = DateTime.now().toUtc();
    final events = widget.events; 

    // Filter strictly for Global events
    final activeEvents = events.where((e) => e.type == 'global').toList();

    // Sort by Start Time (Newest First/Future First) so upcoming/recent are at top
    // activeEvents.sort((a, b) => (a.startTimeUTC ?? '').compareTo(b.startTimeUTC ?? '')); // Old ascending sort
    
    // Improved Sort: Decending (Newest dates at top) makes it easier to find what was just created
    activeEvents.sort((a, b) {
       final tA = a.startTimeUTC ?? '';
       final tB = b.startTimeUTC ?? '';
       return tB.compareTo(tA);
    });

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
                    // Determine Status
                    // 1. DRAFT: explicitly isDraft OR !isPublished
                    // 2. PLAYED OUT (Amber): Published BUT End Time < Now
                    // 3. LIVE/PUBLISHED (Green): Published AND End Time > Now
                    
                    bool isDraft = !event.isPublished || event.isDraft;
                    bool isPlayedOut = false;
                    
                    if (!isDraft) {
                       final end = startTime.add(Duration(seconds: event.durationSeconds ?? 3600));
                       if (end.isBefore(now.toLocal())) { // Compare Local to Local
                          isPlayedOut = true;
                       }
                    }

                    // Define Visuals
                    Color baseColor = Colors.green;
                    String statusLabel = 'LIVE';
                    IconData statusIcon = Icons.public;
                    
                    if (isDraft) {
                        baseColor = Colors.orange; // User Request: "Draft (amber)"
                        statusLabel = 'DRAFT';
                        statusIcon = Icons.edit_note;
                    } else if (isPlayedOut) {
                        baseColor = Colors.amber.shade700; 
                        statusLabel = 'PLAYED OUT';
                        statusIcon = Icons.history;
                    } else if (isRecurring) {
                        baseColor = Colors.blue;
                        statusLabel = 'RECURRING';
                        statusIcon = Icons.loop;
                    }

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
                                child: Icon(statusIcon, color: baseColor, size: 20),
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
                                child: Text(statusLabel,
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
                              if (isDraft || isPlayedOut) // Allow "Republishing" played out events essentially
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                       if (widget.onPublishEvent != null) {
                                         // If played out, maybe reset start time to future?
                                         // For now, just call publish handling
                                         widget.onPublishEvent!(event);
                                       }
                                    },
                                    icon: const Icon(Icons.send, size: 14),
                                    label: Text(isPlayedOut ? 'Republish' : 'Publish'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isDraft ? Colors.green.shade600 : Colors.green,
                                      foregroundColor: Colors.white,
                                      elevation: isDraft ? 4 : 2, // Highlight strict draft status with elevation?
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
  
  // Real Data
  int _supportMessages = 0;
  int _moderationQueue = 0;

  @override
  void initState() {
    super.initState();
    _checkAlerts();
  }

  Future<void> _checkAlerts() async {
    setState(() => _isLoading = true);
    
    // 1. Check Unread Support Messages (Central Inbox)
    try {
      final supportSnapshot = await FirebaseFirestore.instance
          .collection('support_inbox')
          .where('read', isEqualTo: false)
          .count()
          .get();
      
      // 2. Check Pending Moderation Items
      final modSnapshot = await FirebaseFirestore.instance
          .collection('moderation_queue')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();

      if (mounted) {
        setState(() {
          _supportMessages = supportSnapshot.count ?? 0;
          _moderationQueue = modSnapshot.count ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching admin alerts: $e");
      if (mounted) setState(() => _isLoading = false);
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
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active, color: hasAlerts ? Colors.orange : Colors.grey, size: 20),
                const SizedBox(width: 8),
                const Text('Admin Alerts', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                const Spacer(),
                SizedBox(
                  width: 32, height: 32,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.refresh, size: 18, color: Colors.grey),
                    onPressed: _checkAlerts,
                    tooltip: 'Refresh Alerts',
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            if (_isLoading)
               const Expanded(child: Center(child: CircularProgressIndicator()))
            else
               Expanded(
                 child: SingleChildScrollView(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       _buildAlertRow(Icons.support_agent, 'Support', _supportMessages, 'New'),
                       const SizedBox(height: 6),
                       _buildAlertRow(Icons.gavel, 'Moderation', _moderationQueue, 'Pending'),
                     ],
                   ),
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
        Icon(icon, size: 18, color: Colors.blueGrey), // Reduced 20->18
        const SizedBox(width: 8), // Reduced 12->8
        Expanded(
          child: Text(
            title, 
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        if (hasCount)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count $label', 
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          )
        else
           const Text('OK', style: TextStyle(color: Colors.green, fontSize: 11, fontStyle: FontStyle.italic)), // Shortened "All Clear"
      ],
    );
  }
}

// --- NEW V3 CARDS ---

class _WorldwideEventsCard extends StatelessWidget {
  final List<Event> events;
  
  const _WorldwideEventsCard({required this.events});
  
  @override
  Widget build(BuildContext context) {
    
    final globalEvents = events.where((e) => e.type == 'global').toList();
    
    // Count Published: Must be isPublished AND NOT expired
    // Count Drafts: isDraft OR (isPublished but Expired) - essentially requiring attention?
    // Or simpler: Expired events should basically drop out of 'Published' count.
    
    final now = DateTime.now().toUtc();
    
    final published = globalEvents.where((e) {
      if (!e.isPublished) return false;
      if (e.startTimeUTC == null) return false;
      try {
         final start = DateTime.parse(e.startTimeUTC!);
         final duration = Duration(seconds: e.durationSeconds ?? 3600);
         final end = start.add(duration);
         // If end time has passed, it's not "Currently Published/Active" in the sense of upcoming/live
         if (end.isBefore(now)) return false; 
         return true;
      } catch (_) {
         return true; // Fallback
      }
    }).length;

    // Drafts or Past/Played Out needing reset
    // User: "displayed as a draft... played out... turned Amber" 
    // This implies Played Out events contribute to the "Drafts Await" or a new "Played Out" category?
    // Let's assume if it played out, it's effectively a slot that needs attention (like a draft).
    final drafts = globalEvents.where((e) {
      if (e.isDraft) return true;
      if (!e.isPublished) return true; // Unlink published flag
      // Check if expired
      if (e.startTimeUTC != null) {
          try {
             final start = DateTime.parse(e.startTimeUTC!);
             final duration = Duration(seconds: e.durationSeconds ?? 3600);
             final end = start.add(duration);
             if (end.isBefore(now)) return true; // Count expired as draft/needing attention
          } catch (_) {}
      }
      return false;
    }).length;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, // Light theme card
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.public, color: Colors.indigo, size: 20),
              ),
              const SizedBox(width: 8),
              const Text('Worldwide Events', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
            ],
          ),
          const Spacer(),
          _buildRow('Published', '$published', Colors.green),
          const SizedBox(height: 8),
          _buildRow('Drafts Await', '$drafts', Colors.orange),
        ],
      ),
    );
  }
  
  Widget _buildRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _NationalEventsCard extends StatelessWidget {
  final List<Event> events;
  final int selectedOffset; // 0, 15, 30, 45
  final Function(int) onOffsetChanged;
  final VoidCallback onJumpToAttention;
  
  const _NationalEventsCard({
    required this.events, 
    required this.selectedOffset, 
    required this.onOffsetChanged,
    required this.onJumpToAttention,
  });
  
  @override
  Widget build(BuildContext context) {
    // Analyze "National" stats based on the selected offset
    // The "Published Slots" counter should represent "Complete Published Week Cards" for this channel.
    // Meaning: For this specific minute offset (e.g., :00), how many weeks have ALL 24 hours filled and published?
    // Actually, user said: "counter (Published Slots)... will represent complete published week cards, not individual time slots."
    
    // So we need to iterate through all 52 weeks.
    // For each week, check if ALL 24 hours for the selected offset have a published event.
    
    int completePublishedWeeks = 0;
    int incompleteWeeks = 0; // Weeks that have SOME content but not full, OR represent empty weeks needing attention?
                             // User: "how many cards require attention, i.e part filled or empty"
                             // So Incomplete = Total Weeks (52) - Complete Weeks.

    // 1. Group events by Week Index (0-51)
    final Map<int, Set<int>> publishedHoursPerWeek = {}; // weekIndex -> Set of hours (0-23) filled
    
    // We need to know the year structure to map event -> week index
    final now = DateTime.now();
    final firstDayOfYear = DateTime.utc(now.year, 1, 1);
    final daysOffset = firstDayOfYear.weekday - 1; 
    final firstMondayOfYear = firstDayOfYear.subtract(Duration(days: daysOffset));

    for (var e in events) {
       if (e.startTimeUTC != null && e.isPublished) {
           try {
             final dt = DateTime.parse(e.startTimeUTC!);
             if (dt.minute == selectedOffset) {
                 // Calculate Week Index
                 final diffDays = dt.difference(firstMondayOfYear).inDays;
                 if (diffDays >= 0) {
                     final weekIndex = (diffDays / 7).floor();
                     if (weekIndex >= 0 && weekIndex < 52) {
                         publishedHoursPerWeek.putIfAbsent(weekIndex, () => <int>{});
                         publishedHoursPerWeek[weekIndex]!.add(dt.hour);
                     }
                 }
             }
           } catch (_) {}
       }
    }

    // 2. Count Complete Weeks
    for (int i = 0; i < 52; i++) {
        final hoursFilled = publishedHoursPerWeek[i]?.length ?? 0;
        if (hoursFilled >= 24) {
            completePublishedWeeks++;
        }
    }
    
    // "Attention Needed" = Total Weeks - Complete Weeks
    // Every week needs a full 24h schedule for the National Channel.
    final attentionNeeded = 52 - completePublishedWeeks;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          // Left: Stats (Clickable to jump)
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: onJumpToAttention, // Tap to Jump
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                   color: Colors.grey.withOpacity(0.05),
                   borderRadius: BorderRadius.circular(12),
                   border: Border.all(color: Colors.grey.withOpacity(0.1)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('National Channel :${selectedOffset.toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo)),
                    const SizedBox(height: 8),
                    _buildStatLine('Published Weeks', '$completePublishedWeeks/52', Colors.indigo),
                    const SizedBox(height: 4),
                    _buildStatLine('Attention Needed', '$attentionNeeded Wks', Colors.redAccent),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                         Icon(Icons.touch_app, size: 12, color: Colors.grey[400]),
                         const SizedBox(width: 4),
                         Text('Tap to resolve', style: TextStyle(fontSize: 10, color: Colors.grey[400])),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 12),
          Container(width: 1, height: 100, color: Colors.grey[200]),
          const SizedBox(width: 12),
          
          // Right: 4 Icons Selector (Matched to Year Command Center)
          Expanded(
            flex: 1,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                 _buildIconBtn(context, 0, Icons.access_time, "On the Hour (:00)"),    
                 _buildTextBtn(context, 15, "15", "Quarter Past (:15)"),            
                 _buildTextBtn(context, 30, "1/2", "Half Past (:30)"),    
                 _buildTextBtn(context, 45, "45", "Quarter To (:45)"),             
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatLine(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
  
  Widget _buildIconBtn(BuildContext context, int offset, IconData icon, String tooltip) {
    final isSelected = selectedOffset == offset;
    return InkWell(
      onTap: () => onOffsetChanged(offset),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.shade300),
          ),
          child: Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
        ),
      ),
    );
  }

  Widget _buildTextBtn(BuildContext context, int offset, String text, String tooltip) {
    final isSelected = selectedOffset == offset;
    return InkWell(
      onTap: () => onOffsetChanged(offset),
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: isSelected ? Colors.indigo : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? Colors.transparent : Colors.grey.shade300),
          ),
          child: Center(
            child: Text(
              text, 
              style: TextStyle(
                fontSize: 10, 
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey
              )
            ),
          ),
        ),
      ),
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

class _TrendingIntentCard extends StatefulWidget {
  const _TrendingIntentCard();
  @override
  State<_TrendingIntentCard> createState() => _TrendingIntentCardState();
}

class _TrendingIntentCardState extends State<_TrendingIntentCard> {
  final TextEditingController _intentController = TextEditingController();
  bool _isAutoGenerated = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('system_settings').doc('trending_intent').get();
      if (doc.exists) {
        setState(() {
          _isAutoGenerated = doc.data()?['isAutoGenerated'] ?? true;
          _intentController.text = doc.data()?['currentIntent'] ?? 'Harmony';
        });
      }
    } catch (e) {
      debugPrint('Error loading trending intent: ' + e.toString());
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('system_settings').doc('trending_intent').set({
        'isAutoGenerated': _isAutoGenerated,
        'currentIntent': _intentController.text,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Community Pulse Updated'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Error saving trending intent: ' + e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String> _fetchCalculatedIntent() async {
    try {
      // Logic: Find the most recent Global Event (Published)
      // Client-side filtering to avoid complex index requirements for now
      final snapshot = await FirebaseFirestore.instance
          .collection('events')
          .where('type', isEqualTo: 'global')
          .get();

      if (snapshot.docs.isNotEmpty) {
        final docs = snapshot.docs.where((d) => d.data()['isPublished'] == true).toList();
        
        // Sort by startTimeUTC descending
        docs.sort((a, b) {
           final aTime = a.data()['startTimeUTC'] as String? ?? '';
           final bTime = b.data()['startTimeUTC'] as String? ?? '';
           return bTime.compareTo(aTime);
        });

        if (docs.isNotEmpty) {
          final eventIntent = docs.first.data()['intent'] as String?;
          if (eventIntent != null && eventIntent.isNotEmpty) {
            return eventIntent;
          }
        }
      }
      return "None yet";
    } catch (e) {
      debugPrint("Error calculating intent: $e");
      return "Error: $e";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.pink.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite, size: 32, color: Colors.pink.shade400),
                  const SizedBox(height: 8),
                  Text('Pulse', style: TextStyle(color: Colors.pink.shade700, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Trending Intent (My Impact)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  
                  // Calculated Intent Display
                  FutureBuilder<String>(
                    future: _fetchCalculatedIntent(),
                    builder: (context, snapshot) {
                      final calculated = snapshot.data;
                      final isError = calculated != null && calculated.startsWith("Error");
                      final displayDate = calculated ?? "Loading...";
                      
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.analytics_outlined, size: 18, color: Colors.pink.shade300),
                            const SizedBox(width: 8),
                            const Text("System Calculated: ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13)),
                            Expanded(
                              child: Text(
                                displayDate, 
                                style: TextStyle(
                                  fontWeight: FontWeight.bold, 
                                  color: isError ? Colors.red : Colors.indigo, 
                                  fontSize: 14
                                ), 
                                overflow: TextOverflow.ellipsis
                              )
                            ),
                            if (snapshot.hasData && !isError && calculated != "None yet" && calculated != "Loading...")
                               Tooltip(
                                 message: "Use this intent",
                                 child: InkWell(
                                   onTap: () {
                                     setState(() {
                                       _intentController.text = calculated!;
                                       _isAutoGenerated = false; // Switch to manual if they click it
                                     });
                                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Intent copied to manual override"), duration: Duration(seconds: 1)));
                                   },
                                   child: Container(
                                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                     decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)),
                                     child: const Row(
                                       children: [
                                         Text("APPLY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo)),
                                         SizedBox(width: 4),
                                         Icon(Icons.copy, size: 12, color: Colors.indigo),
                                       ],
                                     ),
                                   ),
                                 ),
                               )
                          ],
                        ),
                      );
                    }
                  ),
                  
                  Row(
                    children: [
                      Row(
                        children: [
                          const Text('Mode: ', style: TextStyle(color: Colors.grey)),
                          Switch(
                            value: _isAutoGenerated,
                            activeColor: Colors.pink,
                            onChanged: (val) {
                              setState(() => _isAutoGenerated = val);
                              _saveSettings();
                            },
                          ),
                          Text(
                            _isAutoGenerated ? 'Live (Auto)' : 'Manual Override',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _isAutoGenerated ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 32),
                      Expanded(
                        child: TextField(
                          controller: _intentController,
                          enabled: !_isAutoGenerated,
                          decoration: InputDecoration(
                            hintText: 'Enter positive intent keyword...',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            suffixIcon: _isAutoGenerated 
                                ? const Tooltip(message: 'System is listening...', child: Icon(Icons.hearing, color: Colors.green))
                                : IconButton(
                                    icon: _isLoading 
                                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                                      : const Icon(Icons.save, color: Colors.indigo),
                                    onPressed: _saveSettings,
                                    tooltip: 'Publish Intent',
                                  ),
                          ),
                          onSubmitted: (_) => _saveSettings(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: 200,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isAutoGenerated 
                      ? 'Displaying highest count keyword from recent user activity.' 
                      : 'You are broadcasting a specific intent to all user dashboards.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4),
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
