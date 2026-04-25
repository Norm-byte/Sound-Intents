import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'models/event.dart';
import 'repositories/event_repository.dart';
// import 'repositories/local_event_repository.dart';
import 'repositories/firestore_event_repository.dart'; // Using Firestore for real-time
import 'services/admin_user_service.dart';
import 'models/admin_user.dart';
import 'ui/auth/login_screen.dart';
import 'ui/auth/setup_super_admin_screen.dart';
import 'ui/auth/access_restricted_screen.dart';
import 'ui/tabs/dashboard_tab.dart';
import 'ui/tabs/event_creator_tab.dart';
import 'ui/tabs/event_scheduler_tab.dart';
import 'ui/tabs/media_library_tab.dart';
import 'ui/tabs/youtube_library_tab.dart';
import 'ui/tabs/system_tab.dart';
import 'ui/tabs/legal_tab.dart';
import 'ui/tabs/documentation_tab.dart'; // Added for Operators Manual
import 'ui/tabs/chat_management_tab.dart';
import 'ui/tabs/monetization_tab.dart';
import 'ui/tabs/app_content_tab.dart';
import 'ui/notifications_screen.dart';
import 'ui/widgets/locked_tab_wrapper.dart';
import 'widgets/app_footer.dart';
import 'widgets/session_timeout_manager.dart'; // Add Session Manager
import 'services/lock_service.dart'; // Add Lock Service
import 'build_info.dart';

Future<void> main() async {
  print("HARMONY_ADMIN_DEBUG: Starting App...");
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase with the generated options
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Fix for Web Timeouts: Explicitly disable persistence to avoid cache sync issues
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      sslEnabled: true,
    );
  } catch (e) {
    // Firebase init failed - continue in local-only mode.
    debugPrint('Firebase init failed: $e');
  }

  runApp(const HarmonyAdminApp());
}

class HarmonyAdminApp extends StatelessWidget {
  const HarmonyAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harmony Admin FIXED',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Show loading while checking auth state
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // Show login if not authenticated
          if (!snapshot.hasData || snapshot.data == null) {
            return const LoginScreen();
          }

          // If authenticated, gate access by admin status in Firestore
          // Wraps the main app in the SessionTimeoutManager
          // 20 minutes (1200 seconds) timeout.
          return SessionTimeoutManager(
              timeoutDuration: const Duration(minutes: 20),
              onTimeout: () {
                FirebaseAuth.instance.signOut();
              },
              child: _AdminAccessWrapper(user: snapshot.data!));
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class _AdminAccessWrapper extends StatelessWidget {
  final User user;
  const _AdminAccessWrapper({required this.user});

  @override
  Widget build(BuildContext context) {
    final service = AdminUserService();
    final adminDocStream = FirebaseFirestore.instance
        .collection('admin_users')
        .doc(user.uid)
        .snapshots()
        .distinct((prev, next) {
      // Prevent rebuild loop caused by heartbeat (lastActive updates)
      if (prev.exists != next.exists) return false;
      if (!prev.exists) return true; // Both don't exist, no change

      final d1 = prev.data();
      final d2 = next.data();

      if (d1 == null && d2 == null) return true;
      if (d1 == null || d2 == null) return false;

      // Check critical fields that affect access/permissions
      if (d1['role'] != d2['role']) return false;
      if (d1['isActive'] != d2['isActive']) return false;

      // Check permissions list equality
      final p1 = d1['permissions'];
      final p2 = d2['permissions'];

      // Simple list comparison (assuming List<String> or null)
      if (p1 == null && p2 == null) return true;
      if (p1 == null || p2 == null) return false;

      if (p1 is List && p2 is List) {
        if (p1.length != p2.length) return false;
        for (int i = 0; i < p1.length; i++) {
          if (p1[i] != p2[i]) return false;
        }
        return true;
      }

      return false; // Different types or something else changed
    });

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: adminDocStream,
      builder: (context, adminSnap) {
        if (adminSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final exists = adminSnap.data?.exists == true;
        if (exists) {
          final data = adminSnap.data!.data();
          if (data == null) {
            return const AccessRestrictedScreen(
                reason: 'Invalid admin profile.');
          }

          AdminUser admin;
          try {
            admin = AdminUser.fromJson(data);
          } catch (e) {
            debugPrint('Error parsing admin user: $e');
            // If parsing fails, show restricted screen so they can use "Fix My Account" to repair the data
            return const AccessRestrictedScreen(
              reason:
                  'Profile data corrupted. Please click "Fix My Account" to repair.',
            );
          }

          if (!admin.isActive) {
            return const AccessRestrictedScreen(
              reason:
                  'Your admin account is suspended. Please contact a super-admin.',
            );
          }
          // Optionally update lastLogin (fire and forget) - MOVED to AdminHomePage to prevent build loop
          // service.updateLastLoginNow();
          return AdminHomePage(adminUser: admin);
        } else {
          // No admin record for this user. Check if any admins exist.
          return FutureBuilder<bool>(
            future: service.hasAnyAdmins(),
            builder: (context, hasAny) {
              if (hasAny.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                    body: Center(child: CircularProgressIndicator()));
              }
              if (hasAny.data == true) {
                return const AccessRestrictedScreen(
                  reason: 'Your account is not authorized for admin access.',
                );
              } else {
                // First-time setup: let this user become super-admin
                return const SetupSuperAdminScreen();
              }
            },
          );
        }
      },
    );
  }
}

class AdminHomePage extends StatefulWidget {
  final AdminUser adminUser;
  const AdminHomePage({super.key, required this.adminUser});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Event> events = [];
  late EventRepository _repository;
  Stream<List<Event>>? _eventsStream;
  StreamSubscription<List<Event>>? _eventsSub;
  StreamSubscription<List<Event>>? _globalEventsSub;
  // Timer? _heartbeatTimer; // Moved to LockService

  List<Event> _scheduledEvents = [];
  List<Event> _globalEvents = [];

  // Use ValueNotifier for robust communication with the Scheduler Tab
  final ValueNotifier<String?> _schedulerSelectionNotifier =
      ValueNotifier(null);

  Event? _eventToEdit;

  late List<Widget> _tabs;

  void _calculateTabs() {
    _tabs = const [
      Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
      Tab(icon: Icon(Icons.public), text: 'Worldwide Events'), // Renamed
      Tab(icon: Icon(Icons.schedule), text: 'National Events'), // Renamed
      Tab(icon: Icon(Icons.perm_media), text: 'Media Library'),
      Tab(icon: Icon(Icons.mobile_screen_share), text: 'App Content'),
      Tab(icon: Icon(Icons.chat), text: 'Chat Rooms'),
      Tab(icon: Icon(Icons.monetization_on), text: 'Deals/Offers'),
      Tab(icon: Icon(Icons.lightbulb), text: 'Topics'),
      Tab(icon: Icon(Icons.settings), text: 'System'),
      Tab(icon: Icon(Icons.notifications_active), text: 'Notifications'),
      Tab(icon: Icon(Icons.gavel), text: 'Legal'), // Restored
      Tab(
          icon: Icon(Icons.menu_book),
          text: 'Operators Manual'), // Restored Docs as Manual
    ];
  }

  bool _hasAccess(String key) {
    // Documentation is always accessible
    if (key == 'documentation') return true;

    final permissions = widget.adminUser.permissions;
    final isSuperAdmin = widget.adminUser.isSuperAdmin;

    if (isSuperAdmin) return true;
    if (permissions == null || permissions.isEmpty)
      return false; // Default to locked if no permissions explicitly granted
    return permissions.contains(key);
  }

  List<Widget> _buildTabViews() {
    // Helper to wrap locked tabs
    Widget buildTab(String permKey, String title, Widget child) {
      if (_hasAccess(permKey)) return child;
      return LockedTabWrapper(title: title, child: child);
    }

    return [
      // 1. Dashboard
      buildTab(
        'dashboard',
        'Dashboard',
        DashboardTab(
          events: events,
          onCreateEvent: () {
            // Animate to Worldwide Events (Index 1)
            if (_hasAccess('event_creator')) {
              _tabController.animateTo(1);
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Access Denied')));
            }
          },
          onViewSchedule: (date, time) {
            // Animate to National Events (Index 2)
            if (_hasAccess('event_scheduler')) {
              _tabController.animateTo(2);
              if (time != null) {
                final slotId =
                    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                _schedulerSelectionNotifier.value = slotId;
              }
            } else {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Access Denied')));
            }
          },
          onEditEvent: _handleEditEvent,
          onDeleteEvent: _handleDeleteEvent,
          onImportEvents: _importEvents,
          onPublishWeek: _handlePublishWeek,
          onClearWeek: (offset, minute) => _handleClearWeek(offset,
              minuteFilter: minute), // Updated Clear Callback
          onClearTimeSlots: (offset, minute) => _handleClearWeekDraftSlots(
              offset,
              minuteFilter: minute),
          onPublishEvent: _handlePublishEvent,
        ),
      ),

      // 2. Event Creator -> Worldwide Events
      buildTab(
        'event_creator',
        'Worldwide Events',
        EventCreatorTab(
          eventToEdit: _eventToEdit,
          onEventUpdated: _handleEventUpdated,
        ),
      ),

      // 3. Event Scheduler -> National Events
      buildTab(
        'event_scheduler',
        'National Events',
        EventSchedulerTab(
          selectionNotifier: _schedulerSelectionNotifier,
          liveEvents: _scheduledEvents
              .where((event) => event.type != 'global' && event.isPublished)
              .toList(),
        ),
      ),

      // 4. Media Library
      buildTab('media_library', 'Media Library', const MediaLibraryTab()),

      // 5. App Content (promoted to top-level for full-screen workflow)
      buildTab('system', 'App Content', const AppContentTab()),

      // 6. Chat Rooms
      buildTab('chat_management', 'Chat Rooms', const ChatManagementTab()),

      // Monetization / Deals
      buildTab('monetization', 'Deals', const MonetizationTab()),

      // 7. Topics
      buildTab('topics', 'Topics', const YoutubeLibraryTab()),

      // 8. System
      buildTab('system', 'System', const SystemTab()),

      // 9. Notifications
      buildTab('notifications', 'Notifications', const NotificationsScreen()),

      // 10. Legal (Locked)
      buildTab('legal', 'Legal', const LegalTab()),

      // 11. Operators Manual (Accessible to All - DocumentationTab under the hood)
      buildTab('documentation', 'Operators Manual', const DocumentationTab()),
    ];
  }

  Future<void> _handlePublishEvent(Event event) async {
    try {
      final updated = event.copyWith(isPublished: true, isDraft: false);

      if (updated.type == 'global' || updated.id.startsWith('global_event_')) {
        if (_repository is FirestoreEventRepository) {
          await (_repository as FirestoreEventRepository)
              .saveGlobalEvent(updated);
        } else {
          // Fallback or error
          throw Exception("Global events require Firestore repository");
        }
      } else {
        await _repository.saveEvent(updated);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Event Published!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error publishing: $e'),
            backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _handlePublishWeek(int weekOffset, int? minuteFilter) async {
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final daysSinceMonday = today.weekday - 1;
    final thisWeekMonday = today.subtract(Duration(days: daysSinceMonday));
    final weekStart = thisWeekMonday.add(Duration(days: 7 * weekOffset));
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Publish only scheduler slot docs for this week/lane.
    // Legacy non-slot docs can carry stale metadata and must never be auto-promoted.
    final eventsToPublish = _scheduledEvents.where((e) {
      if (e.type == 'global') return false;
      if (e.startTimeUTC == null) return false;
      final isSlotDoc =
          e.id.startsWith('slot_') || e.id.startsWith('draft_slot_');
      if (!isSlotDoc) return false;

      final start = DateTime.parse(e.startTimeUTC!);
      if (minuteFilter != null && start.minute != minuteFilter) return false;
      final inRange =
          start.isAfter(weekStart.subtract(const Duration(seconds: 1))) &&
              start.isBefore(weekEnd);
      return inRange;
    }).toList();

    if (eventsToPublish.isEmpty) {
      if (mounted) {
        final suffix = minuteFilter == null
            ? ''
            : ' for :${minuteFilter.toString().padLeft(2, '0')} lane';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No events found in this week$suffix to sync.')));
      }
      return;
    }

    final upcomingCount = eventsToPublish.where((e) {
      if (e.startTimeUTC == null) return false;
      final start = DateTime.parse(e.startTimeUTC!);
      return !start.isBefore(now);
    }).length;

    int count = 0;
    for (var e in eventsToPublish) {
      try {
        // Always set published=true, regardless of previous state
        // This forces an update to Firestore which the User App will see
        final publishedId = e.id.startsWith('draft_slot_')
            ? e.id.replaceFirst('draft_slot_', 'slot_')
            : e.id;
        final updated = e.copyWith(
          id: publishedId,
          isPublished: true,
          isDraft: false,
        );
        await _repository.saveEvent(updated);
        if (e.id.startsWith('draft_slot_') && e.id != publishedId) {
          await _repository.deleteEvent(e.id);
        }
        count++;
      } catch (e) {
        debugPrint('Error publishing event: $e');
      }
    }

    if (mounted) {
      final weekLabel =
          '${weekStart.year}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
      final weekEndLabel =
          '${weekEnd.year}-${weekEnd.month.toString().padLeft(2, '0')}-${weekEnd.day.toString().padLeft(2, '0')}';
      final laneLabel = minuteFilter == null
          ? 'all lanes'
          : ':${minuteFilter.toString().padLeft(2, '0')} lane';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Synced $count events for week $weekLabel to $weekEndLabel ($laneLabel, upcoming now: $upcomingCount).',
          ),
          backgroundColor: Colors.green));
    }
  }

  Future<void> _handleClearWeek(int weekOffset, {int? minuteFilter}) async {
    String msg =
      'Are you sure you want to delete events in Week ${weekOffset + 1}';
    if (minuteFilter != null) {
      msg += ' for the :${minuteFilter.toString().padLeft(2, '0')} minute slot';
    }
    msg +=
      '? Matching draft slot data will also be cleared to prevent stale noticeboard content from republishing.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Week Events?'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final now = DateTime.now().toUtc();
    final todayRaw = DateTime.utc(now.year, now.month, now.day);
    final daysSinceMonday = todayRaw.weekday - 1;
    final thisWeekMonday = todayRaw.subtract(Duration(days: daysSinceMonday));

    final weekStart = thisWeekMonday.add(Duration(days: 7 * weekOffset));
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Strict clear: remove all national events in this week/lane, including
    // legacy non-slot docs, so stale metadata cannot survive hidden.
    final eventsToDelete = _scheduledEvents.where((e) {
      if (e.type == 'global') return false;
      if (e.startTimeUTC == null) return false;
      final start = DateTime.parse(e.startTimeUTC!);
      bool matchesWeek =
          start.isAfter(weekStart.subtract(const Duration(seconds: 1))) &&
              start.isBefore(weekEnd);

      if (!matchesWeek) return false;

      // Apply Minute Filter if present
      if (minuteFilter != null) {
        if (start.minute != minuteFilter) return false;
      }

      return true;
    }).toList();

    if (eventsToDelete.isEmpty) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No slot events found to clear.')));
      return;
    }

    final idsToDelete = <String>{};
    for (final e in eventsToDelete) {
      idsToDelete.add(e.id);
      if (e.id.startsWith('slot_')) {
        idsToDelete.add(e.id.replaceFirst('slot_', 'draft_slot_'));
      } else if (e.id.startsWith('draft_slot_')) {
        idsToDelete.add(e.id.replaceFirst('draft_slot_', 'slot_'));
      }
    }

    int deletedCount = 0;
    for (final id in idsToDelete) {
      try {
        await _repository.deleteEvent(id);
        deletedCount++;
      } catch (_) {
        // Ignore missing docs in strict-clear sweep.
      }
    }

    // Also clear local scheduler cache for this week/lane so stale drafts
    // do not reappear in editor state after strict clear.
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftKey = 'eventSchedulerDraftV3_Week$weekOffset';
      final deletedKey = 'eventSchedulerDeletedSlotsV1_Week$weekOffset';

      if (minuteFilter == null) {
        await prefs.setString(draftKey, '{}');
        await prefs.setString(deletedKey, '[]');
      } else {
        final draftString = prefs.getString(draftKey);
        if (draftString != null) {
          final Map<String, dynamic> draftMap = jsonDecode(draftString);
          final keysToRemove = draftMap.keys.where((slotId) {
            final parts = slotId.split(':');
            if (parts.length != 2) return false;
            final minute = int.tryParse(parts[1]);
            return minute == minuteFilter;
          }).toList();
          for (final k in keysToRemove) {
            draftMap.remove(k);
          }
          await prefs.setString(draftKey, jsonEncode(draftMap));
        }

        final deletedString = prefs.getString(deletedKey);
        if (deletedString != null) {
          final List<dynamic> deletedList = jsonDecode(deletedString);
          deletedList.removeWhere((slotId) {
            if (slotId is! String) return false;
            final parts = slotId.split(':');
            if (parts.length != 2) return false;
            final minute = int.tryParse(parts[1]);
            return minute == minuteFilter;
          });
          await prefs.setString(deletedKey, jsonEncode(deletedList));
        }
      }
    } catch (e) {
      debugPrint('Failed strict-clear local scheduler cache: $e');
    }

    // Prevent immediate Auto-System republish of current week right after a manual clear.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_system_skip_current_week_autopublish_once', true);
    } catch (e) {
      debugPrint('Could not set auto-system skip flag: $e');
    }

    await _loadEvents(); // Refresh UI

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Strict clear complete: removed $deletedCount published/draft slot docs.'),
          backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _handleClearWeekDraftSlots(int weekOffset,
      {int? minuteFilter}) async {
    String msg =
        'Are you sure you want to clear DRAFT time slots in Week ${weekOffset + 1}';
    if (minuteFilter != null) {
      msg += ' for the :${minuteFilter.toString().padLeft(2, '0')} minute slot';
    }
    msg += '? This clears scheduler slot drafts.';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Time Slots?'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Clear', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final now = DateTime.now().toUtc();
    final todayRaw = DateTime.utc(now.year, now.month, now.day);
    final daysSinceMonday = todayRaw.weekday - 1;
    final thisWeekMonday = todayRaw.subtract(Duration(days: daysSinceMonday));

    final weekStart = thisWeekMonday.add(Duration(days: 7 * weekOffset));
    final weekEnd = weekStart.add(const Duration(days: 7));

    final draftEventsToDelete = _scheduledEvents.where((e) {
      if (e.type == 'global') return false;
      if (e.startTimeUTC == null) return false;
      final isDraftSlot = e.isDraft || e.id.startsWith('draft_slot_');
      if (!isDraftSlot) return false;

      final start = DateTime.parse(e.startTimeUTC!);
      final matchesWeek =
          start.isAfter(weekStart.subtract(const Duration(seconds: 1))) &&
              start.isBefore(weekEnd);
      if (!matchesWeek) return false;

      if (minuteFilter != null && start.minute != minuteFilter) return false;
      return true;
    }).toList();

    int deletedCount = 0;
    for (final e in draftEventsToDelete) {
      await _repository.deleteEvent(e.id);
      deletedCount++;
    }

    // Also clear local scheduler cache for this week so drafts don't reappear from local storage.
    try {
      final prefs = await SharedPreferences.getInstance();
      final draftKey = 'eventSchedulerDraftV3_Week$weekOffset';
      final deletedKey = 'eventSchedulerDeletedSlotsV1_Week$weekOffset';

      if (minuteFilter == null) {
        await prefs.setString(draftKey, '{}');
        await prefs.setString(deletedKey, '[]');
      } else {
        final draftString = prefs.getString(draftKey);
        if (draftString != null) {
          final Map<String, dynamic> draftMap = jsonDecode(draftString);
          final keysToRemove = draftMap.keys.where((slotId) {
            final parts = slotId.split(':');
            if (parts.length != 2) return false;
            final minute = int.tryParse(parts[1]);
            return minute == minuteFilter;
          }).toList();
          for (final k in keysToRemove) {
            draftMap.remove(k);
          }
          await prefs.setString(draftKey, jsonEncode(draftMap));
        }

        final deletedString = prefs.getString(deletedKey);
        if (deletedString != null) {
          final List<dynamic> deletedList = jsonDecode(deletedString);
          deletedList.removeWhere((slotId) {
            if (slotId is! String) return false;
            final parts = slotId.split(':');
            if (parts.length != 2) return false;
            final minute = int.tryParse(parts[1]);
            return minute == minuteFilter;
          });
          await prefs.setString(deletedKey, jsonEncode(deletedList));
        }
      }
    } catch (e) {
      debugPrint('Failed clearing local scheduler draft cache: $e');
    }

    await _loadEvents();

    if (mounted) {
      final lane = minuteFilter == null
          ? 'all lanes'
          : ':${minuteFilter.toString().padLeft(2, '0')} lane';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleared $deletedCount draft slots for $lane.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  void _handleEventUpdated(Event event) {
    setState(() {
      // Update global events list
      final index = _globalEvents.indexWhere((e) => e.id == event.id);
      if (index != -1) {
        _globalEvents[index] = event;
      } else {
        _globalEvents.add(event);
      }
      // Rebuild combined list
      events = [..._scheduledEvents, ..._globalEvents];

      // Also update _eventToEdit if it matches, to keep it fresh
      if (_eventToEdit?.id == event.id) {
        _eventToEdit = event;
      }
    });
  }

  void _handleEditEvent(Event event) {
    setState(() {
      _eventToEdit = event;
    });
    // Check permission before navigation
    if (_hasAccess('event_creator')) {
      _tabController.animateTo(1); // Index 1 is Event Creator
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access Denied to Event Creator')));
    }
  }

  Future<void> _handleDeleteEvent(Event event) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Event?'),
        content: Text(
            'Are you sure you want to delete "${event.title}"? This will remove it from the dashboard and reset its slot.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      if (event.id.startsWith('global_event_')) {
        if (_repository is FirestoreEventRepository) {
          await (_repository as FirestoreEventRepository)
              .deleteGlobalEvent(event.id);
        }
        // Optimistic update for global events
        setState(() {
          _globalEvents.removeWhere((e) => e.id == event.id);
          events = [..._scheduledEvents, ..._globalEvents];
        });
      } else {
        await _repository.deleteEvent(event.id);

        // --- CLEANUP DRAFT ---
        try {
          if (event.startTimeUTC != null) {
            final start = DateTime.parse(event.startTimeUTC!).toUtc();
            final now = DateTime.now().toUtc();
            final today = DateTime.utc(now.year, now.month, now.day);

            // Calculate Week Match relative to rolling week
            final eventDate = DateTime.utc(start.year, start.month, start.day);
            final diff = eventDate.difference(today).inDays;

            if (diff >= 0) {
              final weekOffset = (diff / 7).floor();
              final slotId =
                  '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';

              final prefs = await SharedPreferences.getInstance();
              final key = 'eventSchedulerDraftV3_Week$weekOffset';

              final draftString = prefs.getString(key);
              if (draftString != null) {
                final Map<String, dynamic> draftMap = jsonDecode(draftString);
                if (draftMap.containsKey(slotId)) {
                  draftMap.remove(slotId);
                  await prefs.setString(key, jsonEncode(draftMap));
                  debugPrint(
                      'Auto-removed deleted event from Draft (Week $weekOffset, Slot $slotId)');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Draft cleanup failed: $e');
        }

        // Optimistic update for scheduled events
        setState(() {
          _scheduledEvents.removeWhere((e) => e.id == event.id);
          events = [..._scheduledEvents, ..._globalEvents];
        });
      }
      // await _loadEvents(); // Refresh - Removed to prevent race condition with slow sync
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Event deleted')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _calculateTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
    // Switch to Firestore repository for real-time streaming
    _repository = FirestoreEventRepository();
    _loadEvents();
    _initStream();
    LockService().startService(); // Replace manual heartbeat
    AdminUserService().updateLastLoginNow();
  }

  // _startHeartbeat removed - handled by LockService

  Future<void> _loadEvents() async {
    final saved = await _repository.loadEvents();
    List<Event> globals = [];
    if (_repository is FirestoreEventRepository) {
      globals =
          await (_repository as FirestoreEventRepository).loadGlobalEvents();
    }

    setState(() {
      _scheduledEvents = saved;
      _globalEvents = globals;
      events = [..._scheduledEvents, ..._globalEvents];
    });
  }

  void _initStream() {
    _eventsStream = _repository.eventsStream();
    if (_eventsStream != null) {
      _eventsSub = _eventsStream!.listen((live) {
        setState(() {
          _scheduledEvents = live;
          events = [..._scheduledEvents, ..._globalEvents];
        });
      });
    }

    if (_repository is FirestoreEventRepository) {
      final firestoreRepo = _repository as FirestoreEventRepository;
      final globalStream = firestoreRepo.globalEventsStream();
      if (globalStream != null) {
        _globalEventsSub = globalStream.listen((live) {
          print('HARMONY_DEBUG: Loaded ${live.length} global events');
          setState(() {
            _globalEvents = live;
            events = [..._scheduledEvents, ..._globalEvents];
          });
        });
      }
    }
  }

  Future<void> _saveEvent(Event e, {bool publish = false}) async {
    if (publish) {
      await _repository.publishEvent(e);
    } else {
      await _repository.saveEvent(e);
    }
    await _loadEvents(); // Refresh list
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(publish ? 'Event published!' : 'Event saved as draft'),
          backgroundColor: publish ? Colors.green : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Harmony by Intent — Admin'),
        centerTitle: true,
        actions: [
          // User info
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.account_circle,
                      color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: 8),
                  Text(
                    currentUser.email ?? 'Admin',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
          // About
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About',
            onPressed: () {
              showAboutDialog(
                context: context,
                applicationName: 'Harmony Admin',
                applicationVersion: BuildInfo.version,
                applicationIcon: const Icon(Icons.movie_creation_outlined),
                children: const [
                  Text('Admin console for Harmony by Intent.'),
                  SizedBox(height: 8),
                  Text('Changelog: https://github.com/Norm-byte/Sound-Intents'),
                ],
              );
            },
          ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Sign Out'),
                  content: const Text('Are you sure you want to sign out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Sign Out'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await FirebaseAuth.instance.signOut();
              }
            },
            tooltip: 'Sign Out',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _buildTabViews(),
      ),
      bottomNavigationBar: const AppFooter(),
    );
  }

  void _importEvents(List<Event> importedEvents) async {
    for (final imported in importedEvents) {
      await _repository.saveEvent(imported);
    }
    await _loadEvents();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _globalEventsSub?.cancel();
    // _heartbeatTimer?.cancel(); // Handled by LockService
    _tabController.dispose();
    LockService().stopService();
    super.dispose();
  }
}
